"""Kosten eines Plans: ganze Packungen kaufen, Reste ausweisen, Vorrat kostet nichts."""
import math
from dataclasses import dataclass

from app.services.normalize import cents, ingredient_key


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
        self.basics = {i.ingredient_key: i.amount != 0 for i in items if i.is_basic}
        self.left: dict[tuple[str, str], float] = {}
        for i in items:
            if not i.is_basic:
                k = (i.ingredient_key, i.unit)
                self.left[k] = self.left.get(k, 0) + (math.inf if i.amount is None else i.amount)

    def basic(self, name: str) -> bool | None:
        key = ingredient_key(name)
        # shortcut: Komposita wie "Olivenöl" zählen zum Basic "Öl", Wortgruppen nicht; bei Fehltreffern Synonymliste
        return next((full for b, full in self.basics.items() if key == b or (" " not in key and key.endswith(b))), None)

    def take(self, name: str, unit: str, needed: float, ai_in_pantry: bool = False) -> float:
        """Menge aus dem Vorrat (inf = unbegrenzt) und zieht sie für weitere Zeilen ab."""
        if (basic := self.basic(name)) is not None:
            return math.inf if basic else 0.0
        k = (ingredient_key(name), unit)
        if k not in self.left:
            return math.inf if ai_in_pantry else 0.0
        took = min(self.left[k], needed)
        self.left[k] -= took
        return took
