"""Kosten eines Plans: ganze Packungen kaufen, Reste ausweisen, Vorrat kostet nichts."""
import math
import re
from dataclasses import dataclass

from app.services.matching import stem
from app.services.normalize import cents, ingredient_key

# Zusätze, die am Produkt nichts ändern („Joghurt, mild“ = Basic „Joghurt“); Text nach Komma/Klammer zählt nicht
STOCK_IGNORE = {"frisch", "frische", "frischer", "frisches", "bio", "mild", "milde", "milder", "natur", "fettarm",
                "fettarme", "fettarmer", "klein", "kleine", "groß", "große", "gross", "reif", "reife"}


def stock_key(name: str) -> str:
    """Schlüssel für den Vorrats-Abgleich (60/23): 'Joghurt, mild' → 'joghurt', 'Bananen' → 'banan'."""
    head = re.split(r"[,(]", name, maxsplit=1)[0]
    ws = sorted(stem(w) for w in re.findall(r"\w+", head.lower()) if w not in STOCK_IGNORE)
    return " ".join(ws) or ingredient_key(name)


SLICES = 15  # Scheiben je Brot (500–750 g)
WHOLE_BREAD = ("fladenbrot", "pitabrot", "naanbrot")  # werden als ganzes Stück gekauft und verwendet


def pack_amount(name: str, unit: str, amount: float) -> float:
    """Brot/Toast in „stk“ sind Scheiben: eine Packung „1 stk“ ist ein ganzes Brot, nicht eine Scheibe (sonst kostet
    das Frühstück mit 4 Scheiben 4 Brote)."""
    if unit == "stk" and amount <= 1 and any(w.endswith(("brot", "toast")) and w not in WHOLE_BREAD
                                             for w in ingredient_key(name).split()):
        return SLICES
    return amount


@dataclass(frozen=True)
class Pack:
    """Eine kaufbare Packung: Angebot oder Normalpreis-Schätzung."""
    price_cents: int
    amount: float  # in der Basiseinheit der Zutat (g, ml, stk)
    regular_price_cents: int | None = None  # gesetzt = Angebot
    offer_id: int | None = None
    chain: str = ""


@dataclass(frozen=True)
class LineCost:
    ingredient: str
    needed: float
    packs: int
    buy_cents: int  # was an der Kasse bezahlt wird
    use_cents: int  # anteilig für die verbrauchte Menge
    leftover: float
    saved_cents: int
    pack: Pack | None  # None = aus dem Vorrat


def cost_line(ingredient: str, needed: float, options: list[Pack], in_pantry: bool = False) -> LineCost:
    """Wählt die günstigste Packungsart für die benötigte Menge."""
    if in_pantry or needed <= 0:
        return LineCost(ingredient, needed, 0, 0, 0, 0, 0, None)
    if not options:
        raise ValueError(f"Kein Preis für {ingredient}")

    def total(p: Pack) -> int:
        return math.ceil(needed / p.amount) * p.price_cents

    best = min(options, key=total)
    packs = math.ceil(needed / best.amount)
    saved = packs * (best.regular_price_cents - best.price_cents) if best.regular_price_cents else 0
    return LineCost(
        ingredient, needed, packs,
        buy_cents=packs * best.price_cents,
        use_cents=cents(needed / best.amount * best.price_cents),
        leftover=packs * best.amount - needed,
        saved_cents=max(saved, 0),
        pack=best,
    )


def sum_needs(recipes: list[list[tuple[str, float]]]) -> dict[str, float]:
    """Summiert Zutatenmengen über alle Gerichte (gleiche Zutat → eine Einkaufszeile)."""
    needs: dict[str, float] = {}
    for items in recipes:
        for slug, amount in items:
            needs[slug] = needs.get(slug, 0) + amount
    return needs


class Stock:
    """Vorrat für Kosten und Einkaufsliste (60). Basics gelten als vorhanden (leer gemeldet: nicht),
    sonst zählen Mengen gleicher Einheit; ohne Vorrats-Eintrag bleibt die in_pantry-Schätzung der KI."""

    def __init__(self, items=()):
        self.basics = {stock_key(i.name): i.amount != 0 for i in items if i.is_basic}
        self.left: dict[tuple[str, str], float] = {}
        for i in items:
            if not i.is_basic:
                k = (stock_key(i.name), i.unit)
                self.left[k] = self.left.get(k, 0) + (math.inf if i.amount is None else i.amount)

    def basic(self, name: str) -> bool | None:
        key = stock_key(name)
        # shortcut: Komposita wie "Olivenöl" zählen zum Basic "Öl", Wortgruppen nicht; bei Fehltreffern Synonymliste
        return next((full for b, full in self.basics.items() if key == b or (" " not in key and key.endswith(b))), None)

    def take(self, name: str, unit: str, needed: float, ai_in_pantry: bool = False) -> float:
        """Menge aus dem Vorrat (inf = unbegrenzt) und zieht sie für weitere Zeilen ab."""
        if (basic := self.basic(name)) is not None:
            return math.inf if basic else 0.0
        k = (stock_key(name), unit)
        if k not in self.left and self.left.get((k[0], "")) == math.inf:
            return math.inf  # ohne Einheit und Menge vorhanden (z.B. Wochen-Basic „Brot“): gilt für jede Einheit
        if k not in self.left:
            return math.inf if ai_in_pantry else 0.0
        took = min(self.left[k], needed)
        self.left[k] -= took
        return took


# --- Reste (19): Haltbarkeit nach dem Öffnen ---

SHELF_DAYS = {"fleisch_fisch": 2, "obst_gemuese": 3, "kuehlung": 4}  # frisch 2–3 Tage, Kühlung 4, Vorrat egal
SHELF_WORDS = {  # für Zutaten ohne Angebot; Wortanfang oder -ende („Hähnchenbrust“, „Schlagsahne“)
    "fleisch_fisch": ("hähnchen", "huhn", "pute", "hack", "rind", "schwein", "lamm", "fisch", "lachs", "garnele",
                      "speck", "schinken", "filet", "steak", "geschnetzeltes", "forelle", "kabeljau", "gyros"),
    "kuehlung": ("sahne", "milch", "joghurt", "quark", "käse", "feta", "mozzarella", "schmand", "frischkäse",
                 "crème", "creme", "skyr", "ricotta", "mascarpone", "tofu", "hummus", "kokosmilch"),
    "obst_gemuese": ("salat", "spinat", "zucchini", "paprika", "tomate", "gurke", "brokkoli", "blumenkohl",
                     "champignon", "pilz", "lauch", "porree", "kohl", "aubergine", "spargel", "kürbis", "avocado",
                     "beere", "kräuter", "petersilie", "basilikum", "koriander", "schnittlauch", "rucola", "fenchel",
                     "sellerie", "mangold", "bohne", "erbse", "kohlrabi", "radieschen"),
}
LONG_KEEP = ("kartoffel", "zwiebel", "knoblauch", "apfel", "zitrone", "limette", "ingwer", "möhre", "karotte",
             "dose", "getrocknet", "tk", "tiefkühl")
# Begriffe für haltbare Sachen (Abhaken → „In den Vorrat?“, 60): Wortanfang oder -ende
PANTRY_WORDS = ("reis", "nudel", "pasta", "spaghetti", "mehl", "zucker", "salz", "öl", "essig", "linsen", "bohnen",
                "kichererbsen", "dose", "konserve", "brühe", "gewürz", "pfeffer", "haferflocken", "kaffee", "honig",
                "senf", "ketchup", "tomatenmark", "passierte", "couscous", "bulgur", "quinoa", "müsli")


def shelf_days(name: str, category: str | None = None) -> int | None:
    """Tage, die ein angebrochener Rest hält; None = egal (Vorrat, Lagergemüse)."""
    words = ingredient_key(name).split()
    if any(w.startswith(p) or w.endswith(p) for w in words for p in (*LONG_KEEP, *PANTRY_WORDS)):
        return None
    if category in SHELF_DAYS:
        return SHELF_DAYS[category]
    return next((SHELF_DAYS[c] for c, ps in SHELF_WORDS.items()
                 if any(w.startswith(p) or w.endswith(p) for w in words for p in ps)), None)
