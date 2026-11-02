"""Kühlschrank-Foto (69): Haiku Vision erkennt Lebensmittel; „Was koche ich jetzt?“: 3 Gerichte aus dem Vorrat.
Was fehlt, rechnet der Code (Stock), nicht die KI."""
import base64
from collections.abc import Callable
from datetime import date, timedelta
from typing import Literal

from pydantic import BaseModel

from app.models import PantryItem
from app.services import food_map
from app.services.pricing import Stock
from app.services.recipes import SPOON_G

Location = Literal["kuehlschrank", "vorrat", "gefrierfach"]
LOCATIONS = {"kuehlschrank": "Kühlschrank", "vorrat": "Vorratsschrank", "gefrierfach": "Gefrierfach"}
MAX_MISSING, IDEAS = 2, 3


class SeenItem(BaseModel):
    name: str
    amount: float | None
    unit: Literal["g", "ml", "stk", ""]
    location: Location
    category: Literal["obst_gemuese", "fleisch_fisch", "kuehlung", "vorrat", "getraenke", "sonstiges"]
    confidence: Literal["hoch", "mittel", "niedrig"]
    shelf_life_days: int | None


class Seen(BaseModel):
    items: list[SeenItem]


SCAN = """Die Fotos zeigen einen {place} in einem deutschen Haushalt. Liste alle erkennbaren Lebensmittel auf.
- name: deutscher Grundname wie in einer Einkaufsliste (z.B. „Eier“, „Gouda“, „Paprika rot“), keine Marken.
- amount/unit: geschätzte vorhandene Menge in g, ml oder stk; unbekannt → amount null, unit "".
- location: kuehlschrank, vorrat oder gefrierfach (wo es liegt). category: obst_gemuese, fleisch_fisch, kuehlung,
  vorrat, getraenke oder sonstiges.
- confidence: hoch (klar erkennbar), mittel, niedrig (geraten, verdeckt, unscharf).
- shelf_life_days: nur bei Frischem (Obst, Gemüse, Fleisch, Milchprodukte) geschätzte Resthaltbarkeit in Tagen, sonst null.
Jedes Lebensmittel nur einmal (gleiche Sachen zusammenfassen), nichts Unsichtbares erfinden, keine Behälter/Geräte."""


def scan(images: list[bytes], place: str = "kuehlschrank", ask: Callable | None = None,
         today: date | None = None) -> tuple[list[dict], dict]:
    """JPEGs → erkannte Lebensmittel (nicht gespeichert; die App zeigt erst den Prüf-Bildschirm)."""
    ask = ask or food_map.ask_claude
    today = today or date.today()
    content = [{"type": "image", "source": {"type": "base64", "media_type": "image/jpeg",
                                            "data": base64.b64encode(img).decode()}} for img in images]
    content.append({"type": "text", "text": SCAN.format(place=LOCATIONS.get(place, "Kühlschrank"))})
    seen, usage = ask(content, Seen)
    items, names = [], set()
    for i in seen.items:
        if not i.name.strip() or i.name.strip().lower() in names:
            continue
        names.add(i.name.strip().lower())
        amount = i.amount if i.amount is not None and 0 < i.amount <= 100000 else None
        days = i.shelf_life_days if i.shelf_life_days and 0 < i.shelf_life_days <= 3650 else None
        items.append({"name": i.name.strip()[:100], "amount": amount, "unit": i.unit if amount is not None else "",
                      "location": i.location, "category": i.category, "confidence": i.confidence,
                      "best_before": today + timedelta(days=days) if days else None})
    return items, usage


class IdeaIngredient(BaseModel):
    name: str
    amount: float
    unit: Literal["g", "ml", "stk", "el", "tl", "prise"]


class Idea(BaseModel):
    title: str
    description: str
    cuisine: str
    meal_type: Literal["fruehstueck", "mittag", "abend", "dessert"]
    prep_minutes: int
    servings: int
    ingredients: list[IdeaIngredient]
    steps: list[str]
    image_query: str


class Ideas(BaseModel):
    ideas: list[Idea]


COOK = """Schlage {n} verschiedene Gerichte vor, die man JETZT kochen kann.
Regeln:
- Höchstens 30 Minuten. Nur Zutaten aus dem Vorrat und den Basics; höchstens 2 Zutaten dürfen fehlen.
- Zutatennamen exakt wie im Vorrat schreiben, Mengen für {persons} Portionen; bald ablaufende Sachen zuerst nutzen.
- Ernährungsform, Allergien und Ausschlüsse sind harte Regeln.
- Alle Texte auf Deutsch, 3–6 kurze Schritte. image_query: 2–4 englische Suchbegriffe für ein Foto.

Ernährung: {diet}
Allergien: {allergies}
Mag nicht: {dislikes}
Basics (immer da): {basics}
Vorrat: {stock}"""


def missing(ingredients: list[dict], pantry: list[PantryItem]) -> list[dict]:
    """Zutaten, die (ganz oder teilweise) nicht im Vorrat sind, mit der fehlenden Menge. g und ml gelten als gleich."""
    stock, out = Stock(pantry), []
    for i in ingredients:
        amount, unit = i["amount"], i["unit"]
        if unit in SPOON_G:
            amount, unit = amount * SPOON_G[unit], "g"
        have = stock.take(i["name"], unit, amount)
        if have < amount and unit in ("g", "ml"):
            have += stock.take(i["name"], "ml" if unit == "g" else "g", amount - have)
        if have < amount:
            factor = (amount - have) / amount if amount else 1
            out.append({"name": i["name"], "amount": round(i["amount"] * factor, 1), "unit": i["unit"]})
    return out


def cook_now(prefs, pantry: list[PantryItem], ask: Callable | None = None) -> tuple[list[tuple[Idea, list]], dict]:
    """Bis zu 3 Gerichte, sortiert nach Abdeckung (wenigste fehlende Zutaten zuerst); mehr als 2 fehlende → raus.
    Die KI schlägt eins mehr vor, damit nach der Prüfung meist 3 übrig bleiben."""
    ask = ask or food_map.ask_claude
    stock = [p for p in pantry if not p.is_basic and p.amount != 0]
    if not stock:
        return [], {}
    prompt = COOK.format(
        n=IDEAS + 1, persons=prefs.persons, diet=prefs.diet, allergies=", ".join(prefs.allergies) or "keine",
        dislikes=", ".join(prefs.excluded_ingredients) or "-",
        basics=", ".join(p.name for p in pantry if p.is_basic and p.amount != 0) or "-",
        stock=", ".join(p.name + (f" {p.amount:g}{p.unit}" if p.amount is not None else "")
                        + (f" bis {p.best_before:%d.%m.}" if p.best_before else "") for p in stock))
    ideas, usage = ask(prompt, Ideas)
    checked = [(idea, missing([i.model_dump() for i in idea.ingredients], pantry)) for idea in ideas.ideas
               if idea.ingredients and idea.steps]
    checked = sorted((c for c in checked if len(c[1]) <= MAX_MISSING), key=lambda c: len(c[1]))
    return checked[:IDEAS], usage
