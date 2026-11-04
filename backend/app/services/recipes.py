"""Meine Rezepte (3): Live-Kosten aus Angeboten, Kostenanteil im Angebot, Bewertungen für den Planer."""
from dataclasses import dataclass
from datetime import date, timedelta

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import MealPlan, MealPlanEntry, Offer, Rating, Recipe, RecipeFavorite
from app.services.matching import Matcher
from app.services.normalize import cents, ingredient_key

OFFER_BADGE = 0.4  # Badge „im Angebot“ / Start-Karte ab 40 % Kostenanteil
SPOON_G = {"el": 15, "tl": 5, "prise": 0.5}  # Löffelmaße der Nutzer-Rezepte in g (Schätzung)
TOP_FAVORITES, REPEAT_WEEKS = 15, 3


def convert(amount: float, unit: str, target: str, piece_g: float | None) -> float | None:
    """Menge in eine andere Einheit (g ≈ ml, Stück über das Stückgewicht); None = nicht umrechenbar."""
    if unit in SPOON_G:
        amount, unit = amount * SPOON_G[unit], "g"
    if unit == target or {unit, target} == {"g", "ml"}:
        return amount
    if piece_g and unit == "stk" and target in ("g", "ml"):
        return amount * piece_g
    if piece_g and unit in ("g", "ml") and target == "stk":
        return amount / piece_g
    return None


@dataclass
class Line:
    name: str
    amount: float
    unit: str
    cost_cents: int
    offer_id: int | None
    chain: str
    in_offer: bool  # Preis aus einem aktuellen Angebot
    priced: bool  # False = kein Preis bekannt (zählt mit 0)
    pack_amount: float  # Packung in der Einheit der Zutat (für den Planer-Preis)
    pack_price_cents: int


class Pricer:
    """Kosten von Rezeptzutaten: aktuelles Angebot (offer_id der KI oder Namensabgleich) → Packungspreis der KI →
    zuletzt bekannter Preis eines passenden Produkts (Normalpreis-Schätzung) → unbekannt."""

    def __init__(self, offers: list[Offer], history: list[Offer] = (), piece_g: dict[str, float] | None = None):
        self.by_id = {o.id: o for o in offers}
        self.now, self.hist = Matcher(offers), Matcher(list(history))
        self.piece_g = piece_g or {}

    def _best(self, ing: dict, offers: list[Offer], regular: bool) -> tuple[Offer, float, int] | None:
        """(Angebot, Packung in Zutat-Einheit, Packungspreis) mit den geringsten Kosten für die Menge."""
        best = None
        for o in offers:
            price = (o.regular_price_cents or o.price_cents) if regular else o.price_cents
            pack = convert(o.amount or 1, o.unit or "stk", ing["unit"], self.piece_g.get(ingredient_key(ing["name"])))
            if pack and (best is None or price / pack < best[2] / best[1]):
                best = (o, pack, price)
        return best

    def line(self, ing: dict) -> Line:
        name, amount, unit = ing["name"], ing.get("amount") or 0, ing.get("unit", "")
        q = amount * SPOON_G[unit] if unit in SPOON_G else amount  # rechnen in g, anzeigen wie eingegeben
        calc = {**ing, "amount": q, "unit": "g" if unit in SPOON_G else unit}
        own = self.by_id.get(ing.get("offer_id"))
        hit = (self._best(calc, [own], False) if own else None) or self._best(calc, self.now.find(name), False)
        if hit:
            o, pack, price = hit
            return Line(name, amount, unit, cents(q / pack * price), o.id, o.chain, True, True, pack, price)
        if ing.get("pack_amount") and ing.get("pack_price_cents") is not None:  # Schätzung der KI
            pack, price = ing["pack_amount"], ing["pack_price_cents"]
            return Line(name, amount, unit, cents(q / pack * price), None, "", False, True, pack, price)
        if hit := self._best(calc, self.hist.find(name), True):
            o, pack, price = hit
            return Line(name, amount, unit, cents(q / pack * price), None, "", False, True, pack, price)
        return Line(name, amount, unit, 0, None, "", False, False, q or 1, 0)

    def cost(self, ingredients: list[dict]) -> tuple[list[Line], int, float]:
        """Zeilen, Verbrauchskosten gesamt, Anteil der Kosten aus aktuellen Angeboten (0–1)."""
        lines = [self.line(i) for i in ingredients]
        total = sum(line.cost_cents for line in lines)
        share = sum(line.cost_cents for line in lines if line.in_offer) / total if total else 0.0
        return lines, total, round(share, 3)

    def planned(self, ing: dict) -> dict:
        """Zutat im Format des Planers (PlannedIngredient). KI-Zutaten bleiben, Nutzer-Rezepte bekommen Packung/Preis."""
        if "pack_price_cents" in ing:
            return ing
        amount, unit = ing.get("amount") or 0, ing.get("unit", "")
        if unit in SPOON_G:
            amount, unit = amount * SPOON_G[unit], "g"
        line = self.line({**ing, "amount": amount, "unit": unit})
        return {"name": ing["name"], "amount": amount, "unit": unit if unit in ("g", "ml", "stk") else "stk",
                "offer_id": line.offer_id, "pack_amount": line.pack_amount, "pack_price_cents": line.pack_price_cents,
                "in_pantry": False}


def history_offers(db: Session, today: date | None = None) -> list[Offer]:
    """Angebote der letzten 8 Wochen aller Läden (Normalpreis-Schätzung für Zutaten ohne aktuelles Angebot)."""
    today = today or date.today()
    return list(db.scalars(select(Offer).where(Offer.valid_to >= today - timedelta(weeks=8))))


@dataclass
class Stats:
    avg_stars: float | None
    last_cooked: object  # datetime | None
    again: str  # letzte Angabe „Wieder kochen?“, "" = keine


def rating_stats(db: Session, recipe_ids: list[int]) -> dict[int, Stats]:
    rows = db.execute(select(Rating.recipe_id, func.avg(Rating.stars), func.max(Rating.cooked_at))
                      .where(Rating.recipe_id.in_(recipe_ids)).group_by(Rating.recipe_id)).all()
    last = {}
    for r in db.scalars(select(Rating).where(Rating.recipe_id.in_(recipe_ids)).order_by(Rating.cooked_at, Rating.id)):
        last[r.recipe_id] = r.again
    return {rid: Stats(round(avg, 2), cooked, last.get(rid, "")) for rid, avg, cooked in rows}


def favorite_ids(db: Session, household_id: int) -> set[int]:
    return set(db.scalars(select(RecipeFavorite.recipe_id).where(RecipeFavorite.household_id == household_id)))


def household_recipes(db: Session, household_id: int) -> list[Recipe]:
    """„Meine Rezepte“: eigene/importierte + KI-Gerichte, die favorisiert oder bewertet sind."""
    favs = favorite_ids(db, household_id)
    rated = set(db.scalars(select(Rating.recipe_id).join(Recipe, Recipe.id == Rating.recipe_id)
                           .where(Recipe.household_id == household_id)))
    recipes = db.scalars(select(Recipe).where(Recipe.household_id == household_id).order_by(Recipe.id.desc()))
    return [r for r in recipes if r.source != "ai" or r.id in favs or r.id in rated]


def is_disliked(stats: Stats | None) -> bool:
    return stats is not None and (stats.again == "nie" or (stats.avg_stars is not None and stats.avg_stars <= 2))


def hidden(r: Recipe, stats: dict[int, Stats]) -> bool:
    """Auf der Nie-Liste: „Nie“ oder ≤ 2 ★, außer „Wieder vorschlagen“ (19.9)."""
    return not r.unhidden and is_disliked(stats.get(r.id))


def recent_titles(db: Session, household_id: int, today: date | None = None, repeat_weeks: int = REPEAT_WEEKS,
                  exclude_plan: int | None = None) -> list[str]:
    """Gerichte der Vorwochen: gleiches Gericht frühestens nach repeat_weeks Wochen (12, Standard 3).
    exclude_plan: der geprüfte Plan selbst zählt nicht."""
    today = today or date.today()
    weeks = [f"{y}-W{w:02d}" for y, w, _ in ((today - timedelta(weeks=k)).isocalendar()
                                             for k in range(1, repeat_weeks))]
    return list(dict.fromkeys(db.scalars(
        select(Recipe.title).join(MealPlanEntry, MealPlanEntry.recipe_id == Recipe.id)
        .join(MealPlan, MealPlan.id == MealPlanEntry.plan_id)
        .where(MealPlan.household_id == household_id, MealPlan.week.in_(weeks), MealPlan.id != (exclude_plan or 0)))))


def planner_memory(db: Session, household_id: int, today: date | None = None,
                   repeat_weeks: int = REPEAT_WEEKS) -> dict:
    """Für den Prompt (3): Top 15 Favoriten/≥4★ mit Zutaten, „Nie“/≤2★-Titel, Gerichte der letzten N Wochen (12)."""
    recipes = household_recipes(db, household_id)
    stats = rating_stats(db, [r.id for r in recipes])
    recent = recent_titles(db, household_id, today, repeat_weeks)
    never = [r.title for r in recipes if hidden(r, stats)]
    liked = liked_recipes(db, household_id, recipes, stats, recent)
    favorites = [f"{r.title} ({', '.join(i['name'] for i in r.ingredients)})" for r in liked[:TOP_FAVORITES]]
    return {"favorites": favorites, "never": list(dict.fromkeys(never)), "recent": recent}


def liked_recipes(db: Session, household_id: int, recipes: list[Recipe] | None = None, stats: dict | None = None,
                  recent: list[str] | None = None) -> list[Recipe]:
    """Favoriten und ≥ 4 ★, nicht auf der Nie-Liste und nicht in den letzten Wochen; beste zuerst (auch Swipe, 20)."""
    recipes = household_recipes(db, household_id) if recipes is None else recipes
    stats = rating_stats(db, [r.id for r in recipes]) if stats is None else stats
    recent = recent_titles(db, household_id) if recent is None else recent
    favs = favorite_ids(db, household_id)
    liked = [r for r in recipes if not hidden(r, stats) and r.title not in recent
             and (r.id in favs or (stats.get(r.id) and (stats[r.id].avg_stars or 0) >= 4))]
    liked.sort(key=lambda r: (-(stats[r.id].avg_stars if r.id in stats else 0), r.id not in favs, -r.id))
    return liked
