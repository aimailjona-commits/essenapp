"""Ersatzzutaten (7): erst die eingebaute Tabelle (ohne KI), sonst Haiku. Allergien, Ernährungsform und Abneigungen
prüft immer der Code, auch bei KI-Vorschlägen."""
import threading
from collections.abc import Callable
from typing import Literal

from pydantic import BaseModel

from app.services import food_map
from app.services.matching import words
from app.services.normalize import ingredient_key
from app.services.recipes import SPOON_G

# Zutat → (Basis, [(Hinweis zur Wirkung, [(Ersatz, Faktor, Einheit)])]).
# Basis "g": Menge des Originals in g/ml (g ≈ ml), "stk": je Stück. Ersatzmenge = Originalmenge × Faktor,
# Einheit None = wie das Original. Reihenfolge = Empfehlung.
G, STK = "g", "stk"
TABLE: dict[str, tuple[str, list[tuple[str, list[tuple[str, float, str | None]]]]]] = {
    "sahne": (G, [("cremiger, weniger flüssig", [("Frischkäse", .75, "g"), ("Milch", .25, "ml")]),
                  ("leichter, etwas weniger cremig", [("Milch", .8, "ml"), ("Butter", .2, "g")]),
                  ("vegan, leicht nussig", [("Hafer-Cuisine", 1, None)]),
                  ("exotisch, für Currys und Suppen", [("Kokosmilch", 1, None)])]),
    "schlagsahne": (G, [("cremiger, weniger flüssig", [("Frischkäse", .75, "g"), ("Milch", .25, "ml")]),
                        ("vegan, aufschlagbar", [("Kokosmilch (fester Teil)", 1, None)])]),
    "saure sahne": (G, [("fast gleich, etwas fester", [("Schmand", 1, None)]),
                        ("frischer, leichter", [("Joghurt", 1, None)]), ("milder", [("Crème fraîche", 1, None)])]),
    "schmand": (G, [("fast gleich, etwas weniger fett", [("Saure Sahne", 1, None)]),
                    ("reichhaltiger, kocht nicht aus", [("Crème fraîche", 1, None)]),
                    ("leichter, frischer", [("Griechischer Joghurt", 1, None)])]),
    "crème fraîche": (G, [("etwas säuerlicher", [("Schmand", 1, None)]),
                          ("leichter, nicht stark erhitzen", [("Griechischer Joghurt", 1, None)]),
                          ("cremig, milder", [("Frischkäse", .8, "g"), ("Milch", .2, "ml")])]),
    "creme fraiche": (G, [("etwas säuerlicher", [("Schmand", 1, None)]),
                          ("leichter, nicht stark erhitzen", [("Griechischer Joghurt", 1, None)])]),
    "mascarpone": (G, [("leichter, etwas säuerlich", [("Frischkäse", 1, None)]),
                       ("deutlich leichter, flüssiger", [("Quark", .7, "g"), ("Sahne", .3, "ml")]),
                       ("italienisch, körniger", [("Ricotta", 1, None)])]),
    "ricotta": (G, [("cremiger, etwas fester", [("Frischkäse", 1, None)]), ("frischer, feuchter", [("Quark", 1, None)]),
                    ("körnig, mild", [("Hüttenkäse", 1, None)])]),
    "frischkäse": (G, [("leichter, etwas feuchter", [("Quark", 1, None)]), ("reichhaltiger", [("Mascarpone", 1, None)]),
                       ("körnig, mild", [("Ricotta", 1, None)])]),
    "quark": (G, [("cremiger, reichhaltiger", [("Frischkäse", 1, None)]),
                  ("flüssiger, säuerlicher", [("Griechischer Joghurt", 1, None)]), ("ähnlich, proteinreich", [("Skyr", 1, None)])]),
    "skyr": (G, [("fast gleich", [("Magerquark", 1, None)]), ("cremiger, etwas fetter", [("Griechischer Joghurt", 1, None)])]),
    "joghurt": (G, [("dicker, proteinreicher", [("Skyr", 1, None)]), ("säuerlicher, fester", [("Saure Sahne", 1, None)]),
                    ("vegan", [("Sojajoghurt", 1, None)]), ("fester, mit etwas Milch glattrühren", [("Quark", .8, "g"), ("Milch", .2, "ml")])]),
    "griechischer joghurt": (G, [("ähnlich, magerer", [("Skyr", 1, None)]), ("leichter, flüssiger", [("Joghurt", 1, None)]),
                                 ("fester", [("Quark", .8, "g"), ("Milch", .2, "ml")])]),
    "milch": (G, [("vegan, leicht süßlich", [("Haferdrink", 1, None)]), ("vegan, neutral", [("Sojadrink", 1, None)]),
                  ("reichhaltiger", [("Wasser", .5, "ml"), ("Sahne", .5, "ml")])]),
    "buttermilch": (G, [("fast gleich", [("Milch", .95, "ml"), ("Zitronensaft", .05, "ml")]),
                        ("dicker, säuerlich", [("Joghurt", .75, "g"), ("Milch", .25, "ml")]), ("ähnlich säuerlich", [("Kefir", 1, None)])]),
    "kondensmilch": (G, [("weniger süß, flüssiger", [("Sahne", 1, None)]), ("leichter", [("Milch", 1, None)])]),
    "kokosmilch": (G, [("ohne Kokosaroma, cremig", [("Sahne", 1, None)]), ("leichter, nicht kochen", [("Joghurt", 1, None)])]),
    "butter": (G, [("neutraler, für Braten und Teig", [("Rapsöl", .8, "ml")]), ("vegan", [("Margarine", 1, None)]),
                   ("fruchtig, eher herzhaft", [("Olivenöl", .8, "ml")])]),
    "margarine": (G, [("butteriger", [("Butter", 1, None)]), ("zum Braten", [("Rapsöl", .8, "ml")])]),
    "parmesan": (G, [("milder, fast gleich", [("Grana Padano", 1, None)]), ("würziger, salziger", [("Pecorino", 1, None)]),
                     ("vegan, nussig-würzig", [("Hefeflocken", .5, "g")])]),
    "pecorino": (G, [("milder", [("Parmesan", 1, None)])]),
    "mozzarella": (G, [("würziger, schmilzt gut", [("Gouda", .8, "g")]), ("cremiger", [("Burrata", 1, None)]),
                       ("salziger, zerfällt", [("Feta", .8, "g")])]),
    "feta": (G, [("milder, cremiger", [("Hirtenkäse", 1, None)]), ("salzig-würzig, fester", [("Halloumi", 1, None)]),
                 ("milder, schmilzt", [("Mozzarella", 1, None)])]),
    "halloumi": (G, [("zerbröselt beim Braten", [("Feta", 1, None)]), ("vegan, gut anbraten", [("Tofu natur", 1, None)])]),
    "gouda": (G, [("kräftiger", [("Emmentaler", 1, None)]), ("milder", [("Edamer", 1, None)]), ("würzig", [("Bergkäse", 1, None)])]),
    "emmentaler": (G, [("milder", [("Gouda", 1, None)]), ("würziger", [("Bergkäse", 1, None)])]),
    "cheddar": (G, [("milder", [("Gouda", 1, None)]), ("würzig", [("Bergkäse", 1, None)])]),
    "ei": (STK, [("bindet in Teig, nussig", [("Leinsamen geschrotet", 10, "g"), ("Wasser", 30, "ml")]),
                 ("bindet, süßlich – für Kuchen", [("Banane", .5, "stk")]),
                 ("bindet, neutral", [("Speisestärke", 10, "g"), ("Wasser", 30, "ml")]),
                 ("saftig, für Muffins", [("Apfelmus", 60, "g")])]),
    "eier": (STK, [("bindet in Teig, nussig", [("Leinsamen geschrotet", 10, "g"), ("Wasser", 30, "ml")]),
                   ("bindet, süßlich – für Kuchen", [("Banane", .5, "stk")]),
                   ("bindet, neutral", [("Speisestärke", 10, "g"), ("Wasser", 30, "ml")])]),
    "mehl": (G, [("kräftiger, gleiche Menge", [("Dinkelmehl", 1, None)]), ("glutenfrei, bindet stärker", [("Speisestärke", .5, "g")]),
                 ("glutenfrei, nussig", [("Buchweizenmehl", 1, None)])]),
    "weizenmehl": (G, [("kräftiger, gleiche Menge", [("Dinkelmehl", 1, None)]), ("glutenfrei, nussig", [("Buchweizenmehl", 1, None)])]),
    "speisestärke": (G, [("bindet etwas schwächer", [("Mehl", 2, "g")]), ("klarer, glänzender", [("Kartoffelstärke", 1, None)])]),
    "paniermehl": (G, [("knuspriger", [("Panko", 1, None)]), ("nussig, glutenfrei", [("Gemahlene Mandeln", 1, None)]),
                       ("kerniger", [("Haferflocken zart", 1, None)])]),
    "semmelbrösel": (G, [("knuspriger", [("Panko", 1, None)]), ("kerniger", [("Haferflocken zart", 1, None)])]),
    "zucker": (G, [("flüssig, eigenes Aroma", [("Honig", .75, "g")]), ("karamellig", [("Brauner Zucker", 1, None)]),
                   ("vegan, flüssig", [("Ahornsirup", .75, "ml")])]),
    "brauner zucker": (G, [("weniger karamellig", [("Zucker", 1, None)]), ("kräftig", [("Kokosblütenzucker", 1, None)])]),
    "puderzucker": (G, [("im Mixer fein mahlen", [("Zucker", 1, None)])]),
    "honig": (G, [("vegan, mild", [("Ahornsirup", 1, None)]), ("vegan, neutral", [("Agavendicksaft", 1, None)]),
                  ("fester, weniger aromatisch", [("Zucker", 1.25, "g")])]),
    "ahornsirup": (G, [("blumiger", [("Honig", 1, None)]), ("neutral", [("Agavendicksaft", 1, None)])]),
    "backpulver": (G, [("mit Säure im Teig (Joghurt, Buttermilch)", [("Natron", .25, "g")])]),
    "hefe": (G, [("Trockenhefe: 7 g ersetzen 21 g frische", [("Trockenhefe", 1 / 3, "g")])]),
    "trockenhefe": (G, [("frische Hefe, 3-fache Menge", [("Hefe", 3, "g")])]),
    "gelatine": (G, [("vegan, stärker gelierend – kurz aufkochen", [("Agar-Agar", .25, "g")])]),
    "nudeln": (G, [("glutenfrei", [("Reisnudeln", 1, None)]), ("mehr Ballaststoffe", [("Vollkornnudeln", 1, None)]),
                   ("low carb", [("Zucchini", 2, "g")])]),
    "spaghetti": (G, [("mehr Ballaststoffe", [("Vollkornspaghetti", 1, None)]), ("glutenfrei", [("Reisnudeln", 1, None)]),
                      ("andere Form, gleiche Garzeit", [("Linguine", 1, None)])]),
    "reis": (G, [("schneller, kräftiger", [("Bulgur", 1, None)]), ("nussig, proteinreicher", [("Quinoa", 1, None)]),
                 ("sehr schnell", [("Couscous", 1, None)])]),
    "basmatireis": (G, [("ähnlich duftend", [("Jasminreis", 1, None)]), ("mehr Ballaststoffe", [("Vollkornreis", 1, None)])]),
    "couscous": (G, [("körniger, etwas länger kochen", [("Bulgur", 1, None)]), ("glutenfrei", [("Quinoa", 1, None)])]),
    "bulgur": (G, [("feiner, sehr schnell", [("Couscous", 1, None)]), ("glutenfrei", [("Quinoa", 1, None)])]),
    "quinoa": (G, [("glutenhaltig, ähnlich", [("Bulgur", 1, None)]), ("weicher", [("Hirse", 1, None)])]),
    "kartoffeln": (G, [("süßlicher", [("Süßkartoffeln", 1, None)]), ("leichter", [("Blumenkohl", 1, None)])]),
    "kartoffel": (G, [("süßlicher", [("Süßkartoffel", 1, None)]), ("leichter", [("Blumenkohl", 1, None)])]),
    "süßkartoffel": (G, [("weniger süß", [("Kartoffeln", 1, None)]), ("ähnlich süß, herbstlich", [("Hokkaido-Kürbis", 1, None)])]),
    "hackfleisch": (G, [("magerer", [("Putenhack", 1, None)]), ("vegetarisch, kräftig", [("Rote Linsen (trocken)", .5, "g")]),
                        ("vegan, gleiche Menge", [("Sojagranulat (eingeweicht)", 1, None)])]),
    "rinderhack": (G, [("milder, günstiger", [("Hackfleisch gemischt", 1, None)]), ("magerer", [("Putenhack", 1, None)])]),
    "hähnchenbrust": (G, [("ähnlich mager", [("Putenbrust", 1, None)]), ("saftiger", [("Hähnchenschenkel ohne Knochen", 1, None)]),
                          ("vegan", [("Tofu", 1, None)])]),
    "putenbrust": (G, [("ähnlich mager", [("Hähnchenbrust", 1, None)]), ("vegetarisch", [("Halloumi", .8, "g")])]),
    "speck": (G, [("milder, magerer", [("Kochschinken", 1, None)]), ("vegetarisch, rauchig", [("Räuchertofu", 1, None)])]),
    "schinken": (G, [("geräuchert", [("Putenbrust Aufschnitt", 1, None)]), ("vegetarisch", [("Räuchertofu", 1, None)])]),
    "lachs": (G, [("milder, günstiger", [("Forelle", 1, None)]), ("weißer Fisch", [("Seelachs", 1, None)])]),
    "thunfisch": (G, [("ähnlich, aus der Dose", [("Makrele", 1, None)]), ("vegetarisch", [("Kichererbsen", 1, None)])]),
    "garnelen": (G, [("günstiger, fester", [("Tintenfischringe", 1, None)]), ("weißer Fisch", [("Seelachs", 1, None)])]),
    "tofu": (G, [("würziger, fester", [("Tempeh", 1, None)]), ("vegetarisch, salzig", [("Halloumi", 1, None)])]),
    "weißwein": (G, [("alkoholfrei, etwas Säure", [("Gemüsebrühe", .9, "ml"), ("Zitronensaft", .1, "ml")]),
                     ("alkoholfrei, fruchtig", [("Traubensaft hell", .8, "ml"), ("Weißweinessig", .2, "ml")])]),
    "rotwein": (G, [("alkoholfrei, kräftig", [("Gemüsebrühe", .8, "ml"), ("Balsamico", .2, "ml")]),
                    ("alkoholfrei, fruchtig", [("Traubensaft rot", .9, "ml"), ("Rotweinessig", .1, "ml")])]),
    "zitronensaft": (G, [("ähnlich sauer", [("Limettensaft", 1, None)]), ("milder", [("Weißweinessig", .5, "ml")])]),
    "limettensaft": (G, [("ähnlich sauer", [("Zitronensaft", 1, None)])]),
    "zitrone": (STK, [("ähnlich sauer", [("Limette", 1.5, "stk")]), ("Saft aus der Flasche", [("Zitronensaft", 40, "ml")])]),
    "limette": (STK, [("ähnlich sauer", [("Zitrone", .7, "stk")]), ("aus der Flasche", [("Limettensaft", 25, "ml")])]),
    "balsamico": (G, [("milder, fruchtig", [("Apfelessig", .75, "ml"), ("Honig", .25, "g")]), ("kräftiger", [("Rotweinessig", 1, None)])]),
    "essig": (G, [("fruchtiger", [("Apfelessig", 1, None)]), ("frischer", [("Zitronensaft", 1, None)])]),
    "sojasoße": (G, [("glutenfrei", [("Tamari", 1, None)]), ("sojafrei, süßlich", [("Kokos-Aminos", 1, None)]),
                     ("salzig-würzig", [("Gemüsebrühe", 1, None)])]),
    "gemüsebrühe": (G, [("kräftiger", [("Hühnerbrühe", 1, None)]), ("einfach", [("Wasser", 1, None), ("Salz", .01, "g")])]),
    "tomatenmark": (G, [("milder, mehr Menge", [("Passierte Tomaten", 3, "g")]), ("süßlich-würzig", [("Ketchup", 1.5, "g")])]),
    "passierte tomaten": (G, [("stückiger", [("Gehackte Tomaten (Dose)", 1, None)]),
                              ("konzentrierter, mit Wasser", [("Tomatenmark", .3, "g"), ("Wasser", .7, "ml")])]),
    "dosentomaten": (G, [("glatter", [("Passierte Tomaten", 1, None)]), ("frisch", [("Tomaten", 1.2, "g")])]),
    "tomaten": (G, [("aus der Dose", [("Gehackte Tomaten (Dose)", 1, None)]), ("süßer", [("Cherrytomaten", 1, None)])]),
    "zwiebel": (STK, [("milder", [("Schalotten", 2, "stk")]), ("milder, frischer", [("Frühlingszwiebeln", 3, "stk")]),
                      ("kräftig, weniger", [("Lauch", 80, "g")])]),
    "zwiebeln": (STK, [("milder", [("Schalotten", 2, "stk")]), ("frischer", [("Frühlingszwiebeln", 3, "stk")])]),
    "schalotte": (STK, [("kräftiger", [("Zwiebel", .5, "stk")])]),
    "knoblauch": (STK, [("milder, aus dem Glas", [("Knoblauchpaste", 5, "g")]), ("getrocknet", [("Knoblauchpulver", 1, "g")])]),
    "frühlingszwiebeln": (STK, [("kräftiger", [("Zwiebel", .3, "stk")]), ("feiner", [("Schnittlauch", 5, "g")])]),
    "lauch": (G, [("kräftiger", [("Zwiebeln", 1, None)]), ("milder", [("Frühlingszwiebeln", 1, None)])]),
    "spinat": (G, [("kräftiger", [("Mangold", 1, None)]), ("roh und milder", [("Rucola", .7, "g")]), ("tiefgekühlt", [("TK-Spinat", 1, None)])]),
    "rucola": (G, [("milder", [("Feldsalat", 1, None)]), ("zart", [("Babyspinat", 1, None)])]),
    "zucchini": (G, [("weicher, kräftiger", [("Aubergine", 1, None)]), ("knackiger", [("Paprika", 1, None)])]),
    "aubergine": (G, [("milder, schneller gar", [("Zucchini", 1, None)])]),
    "paprika": (STK, [("frisch, saftig", [("Zucchini", 150, "g")]), ("aus dem Glas, rauchig", [("Geröstete Paprika (Glas)", 120, "g")])]),
    "brokkoli": (G, [("milder", [("Blumenkohl", 1, None)]), ("feiner", [("Romanesco", 1, None)])]),
    "blumenkohl": (G, [("kräftiger", [("Brokkoli", 1, None)]), ("feiner", [("Romanesco", 1, None)])]),
    "champignons": (G, [("aromatischer", [("Braune Champignons", 1, None)]), ("asiatisch", [("Shiitake", 1, None)])]),
    "kichererbsen": (G, [("weicher", [("Weiße Bohnen", 1, None)]), ("schneller", [("Rote Linsen (gekocht)", 1, None)])]),
    "rote linsen": (G, [("bissfester, länger kochen", [("Gelbe Linsen", 1, None)]), ("bissfest", [("Belugalinsen", 1, None)])]),
    "kidneybohnen": (G, [("milder", [("Schwarze Bohnen", 1, None)]), ("weicher", [("Weiße Bohnen", 1, None)])]),
    "mandeln": (G, [("kräftiger", [("Haselnüsse", 1, None)]), ("nussfrei", [("Sonnenblumenkerne", 1, None)])]),
    "gemahlene mandeln": (G, [("kräftiger", [("Gemahlene Haselnüsse", 1, None)]), ("nussfrei, saftig", [("Haferflocken zart", 1, None)])]),
    "walnüsse": (G, [("milder", [("Pekannüsse", 1, None)]), ("nussfrei", [("Kürbiskerne", 1, None)])]),
    "pinienkerne": (G, [("günstiger, ähnlich", [("Sonnenblumenkerne", 1, None)]), ("kräftiger", [("Cashews", 1, None)])]),
    "erdnussbutter": (G, [("milder", [("Mandelmus", 1, None)]), ("nussfrei", [("Tahin", 1, None)])]),
    "tahin": (G, [("nussig, süßlicher", [("Erdnussbutter", 1, None)]), ("mild", [("Cashewmus", 1, None)])]),
    "basilikum": (G, [("getrocknet, 1/3 der Menge", [("Basilikum getrocknet", 1 / 3, "g")]), ("frisch, anders", [("Petersilie", 1, None)])]),
    "petersilie": (G, [("frisch, intensiver", [("Koriander", 1, None)]), ("getrocknet", [("Petersilie getrocknet", 1 / 3, "g")])]),
    "koriander": (G, [("milder", [("Petersilie", 1, None)]), ("frisch-würzig", [("Thai-Basilikum", 1, None)])]),
    "schnittlauch": (G, [("kräftiger", [("Frühlingszwiebeln", 1, None)])]),
    "ingwer": (G, [("getrocknet", [("Ingwerpulver", .2, "g")]), ("aus der Tube", [("Ingwerpaste", 1, None)])]),
    "vanilleschote": (STK, [("einfach", [("Vanillezucker", 8, "g")]), ("intensiv", [("Vanilleextrakt", 5, "ml")])]),
    "kakao": (G, [("süßer", [("Zartbitterschokolade (geschmolzen)", 1.5, "g")])]),
    "schokolade": (G, [("Backkakao + Fett", [("Kakao", .5, "g"), ("Butter", .3, "g"), ("Zucker", .3, "g")])]),
}


class SubIng(BaseModel):
    name: str
    amount: float
    unit: Literal["g", "ml", "stk", "el", "tl", "prise"]


class SubOption(BaseModel):
    note: str  # kurze Wirkung, z.B. „cremiger, weniger flüssig“
    ingredients: list[SubIng]


class SubOptions(BaseModel):
    options: list[SubOption]


AI_PROMPT = """Schlage 2–4 Ersatzzutaten für „{amount:g} {unit} {name}“ im Rezept „{title}“ vor (Zutaten: {others}).
- Je Vorschlag 1–2 Zutaten mit umgerechneter Menge (Einheit g, ml, stk, el, tl oder prise) und ein kurzer Hinweis zur
  Wirkung (max. 60 Zeichen, z.B. „cremiger, weniger flüssig“). Übliche deutsche Supermarkt-Zutaten.
- Niemals verwenden (Allergien): {allergies}. Ernährung: {diet}. Mag nicht: {dislikes}."""

# Allergene: Wörter, die (als Wortanfang/-ende) eine Zutat ausschließen. Pflanzliche Drinks sind keine Milch.
ALLERGENS = {
    "milch": ("milch", "sahne", "butter", "käse", "joghurt", "quark", "schmand", "frischkäse", "crème", "creme",
              "mascarpone", "ricotta", "mozzarella", "parmesan", "pecorino", "feta", "skyr", "kefir", "ghee", "gouda",
              "emmentaler", "cheddar", "halloumi", "burrata", "grana", "edamer", "bergkäse", "hirtenkäse"),
    "ei": ("ei", "eier", "eigelb", "eiweiß", "mayonnaise", "mayo"),
    "gluten": ("weizen", "mehl", "dinkel", "roggen", "gerste", "brot", "brösel", "panko", "paniermehl", "nudel",
               "nudeln", "spaghetti", "linguine", "pasta", "grieß", "couscous", "bulgur", "seitan", "semmel", "toast",
               "haferflocken", "tamari"),
    "nuss": ("nuss", "nüsse", "mandel", "mandeln", "mandelmus", "cashew", "cashews", "cashewmus", "pistazie", "pekan",
             "macadamia", "pinienkerne"),
    "erdnuss": ("erdnuss", "erdnüsse", "erdnussbutter"),
    "soja": ("soja", "sojadrink", "sojajoghurt", "tofu", "räuchertofu", "tempeh", "edamame", "miso", "sojasoße",
             "sojagranulat", "tamari"),
    "fisch": ("fisch", "lachs", "thunfisch", "sardelle", "anchovis", "seelachs", "forelle", "makrele", "kabeljau"),
    "krebstiere": ("garnele", "garnelen", "shrimp", "krabbe", "hummer", "scampi", "muschel", "tintenfisch"),
    "sesam": ("sesam", "tahin"),
    "sellerie": ("sellerie",),
    "senf": ("senf",),
    "lupine": ("lupine",),
}
ALIASES = {"laktose": "milch", "milcheiweiß": "milch", "kuhmilch": "milch", "zöliakie": "gluten", "weizen": "gluten",
           "nüsse": "nuss", "schalenfrüchte": "nuss", "eier": "ei", "hühnerei": "ei", "meeresfrüchte": "krebstiere",
           "schalentiere": "krebstiere", "krustentiere": "krebstiere", "erdnüsse": "erdnuss"}
PLANT = ("hafer", "soja", "kokos", "mandel", "reis", "erbsen", "cashew", "vegan", "erdnuss")  # „Hafermilch“: keine Milch
GLUTEN_FREE = ("reis", "mais", "buchweizen", "kichererbsen", "mandel", "kartoffel", "glutenfrei")
MEAT = ("fleisch", "hack", "hähnchen", "huhn", "pute", "rind", "schwein", "lamm", "speck", "schinken", "wurst",
        "salami", "hühnerbrühe", "gelatine")


def _hit(word: str, group: tuple[str, ...]) -> bool:
    return any(word == g or (len(g) >= 4 and (word.startswith(g) or word.endswith(g))) for g in group)


def groups_of(allergies: list[str]) -> list[str]:
    out = []
    for a in allergies:
        for w in ingredient_key(a).replace("-", " ").split():
            key = next((g for g in ALLERGENS if w == g or w.startswith(g) or w.endswith(g)),
                       next((g for a, g in ALIASES.items() if w.startswith(a)), None))
            out.append(key or w)  # unbekannte Allergie: das Wort selbst ausschließen
    return out


def forbidden(name: str, allergies: list[str], diet: str = "alles", dislikes: list[str] = ()) -> bool:
    """True, wenn die Zutat eine Allergie, die Ernährungsform oder eine Abneigung verletzt."""
    words_ = ingredient_key(name).replace("-", " ").replace("(", " ").replace(")", " ").split()
    for group in groups_of(allergies):
        if group not in ALLERGENS:
            if any(group in w for w in words_):
                return True
            continue
        for w in words_:
            if group == "milch" and any(w.startswith(p) for p in PLANT):
                continue
            if group == "gluten" and any(w.startswith(p) for p in GLUTEN_FREE):
                continue
            if _hit(w, ALLERGENS[group]):
                return True
    d = (diet or "").lower()
    if d in ("vegetarisch", "vegan", "pescetarisch") and any(_hit(w, MEAT) for w in words_):
        return True
    if d in ("vegetarisch", "vegan") and any(_hit(w, ALLERGENS["fisch"] + ALLERGENS["krebstiere"]) for w in words_):
        return True
    if d == "vegan" and (any(_hit(w, ALLERGENS["ei"]) or w == "honig" for w in words_) or any(
            _hit(w, ALLERGENS["milch"]) and not any(w.startswith(p) for p in PLANT) for w in words_)):
        return True
    return any(ingredient_key(x) and ingredient_key(x) in ingredient_key(name) for x in dislikes)


def lookup(name: str) -> tuple[str, list] | None:
    """Tabellen-Eintrag: genauer Name, sonst längster Eintrag als Wortende („Schlagsahne“ → sahne)."""
    key = ingredient_key(name)
    if key in TABLE:
        return TABLE[key]
    last = key.split()[-1] if key else ""
    hits = [k for k in TABLE if " ".join(words(k)) == " ".join(words(key)) or (" " not in k and len(k) >= 4 and last.endswith(k))]
    return TABLE[max(hits, key=len)] if hits else None


def to_base(amount: float, unit: str, base: str, piece_g: float | None) -> float | None:
    """Originalmenge in die Basis der Tabelle (g bzw. Stück); None = nicht umrechenbar."""
    if unit in SPOON_G:
        amount, unit = amount * SPOON_G[unit], "g"
    amount, unit = (amount * 1000, {"kg": "g", "l": "ml"}[unit]) if unit in ("kg", "l") else (amount, unit)
    if base == STK:
        return amount if unit == "stk" else (amount / piece_g if piece_g and unit in ("g", "ml") else None)
    if unit in ("g", "ml"):
        return amount
    return amount * piece_g if unit == "stk" and piece_g else None


def from_table(name: str, amount: float, unit: str) -> list[dict] | None:
    """Vorschläge aus der Tabelle als [{note, ingredients: [{name, amount, unit}]}], None = kein Eintrag."""
    entry = lookup(name)
    if entry is None:
        return None
    base, options = entry
    qty = to_base(amount, unit, base, food_map.piece_g(ingredient_key(name)))
    if qty is None:
        return None
    orig_unit = unit if unit in ("g", "ml") else "g"
    return [{"note": note, "ingredients": [{"name": n, "amount": round(qty * f, 1 if u == "stk" else 0) or 1,
                                            "unit": u or orig_unit} for n, f, u in parts]}
            for note, parts in options]


_cache: dict[tuple, list[dict]] = {}  # KI-Vorschläge je Zutat/Menge/Rezept/Einschränkungen (Prozess-Speicher)
_lock = threading.Lock()


def suggest(name: str, amount: float, unit: str, title: str, others: list[str], allergies: list[str], diet: str,
            dislikes: list[str], ask: Callable | None = None) -> tuple[str, list[dict], dict]:
    """(Quelle tabelle|ki, 2–4 erlaubte Vorschläge, KI-Verbrauch oder {}). Allergien/Ernährung prüft der Code."""
    def allowed(opts):
        return [o for o in opts if o["ingredients"] and not any(
            forbidden(i["name"], allergies, diet, dislikes) for i in o["ingredients"])
            and not any(ingredient_key(i["name"]) == ingredient_key(name) for i in o["ingredients"])][:4]

    table = allowed(from_table(name, amount, unit) or [])
    if len(table) >= 2:
        return "tabelle", table, {}
    key = (ingredient_key(name), amount, unit, title, diet, tuple(sorted(allergies)), tuple(sorted(dislikes)))
    with _lock:
        if key in _cache:
            return "ki", _cache[key], {}
    prompt = AI_PROMPT.format(amount=amount, unit=unit, name=name, title=title, others=", ".join(others) or "-",
                              allergies=", ".join(allergies) or "keine", diet=diet or "alles",
                              dislikes=", ".join(dislikes) or "-")
    result, usage = (ask or food_map.ask_claude)(prompt, SubOptions)
    opts = allowed([{"note": o.note[:80], "ingredients": [{"name": i.name.strip()[:100], "amount": max(i.amount, 0),
                                                           "unit": i.unit} for i in o.ingredients if i.name.strip()][:3]}
                    for o in result.options])
    opts = (table + [o for o in opts if o not in table])[:4]
    with _lock:
        _cache[key] = opts
    return "ki", opts, usage
