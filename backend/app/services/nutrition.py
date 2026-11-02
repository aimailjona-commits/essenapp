"""Nährwerte werden gerechnet, nicht von der KI geschätzt (E10). Werte aus `food` (USDA) über `ingredient_map`."""
from dataclasses import asdict, dataclass, fields

from app.services.normalize import ingredient_key
from app.services.recipes import SPOON_G


@dataclass(frozen=True)
class Nutrients:
    kcal: float = 0
    protein: float = 0
    carbs: float = 0
    fat: float = 0
    fiber: float = 0

    def __add__(self, other: "Nutrients") -> "Nutrients":
        return Nutrients(*(getattr(self, f.name) + getattr(other, f.name) for f in fields(self)))

    def scaled(self, factor: float) -> "Nutrients":
        return Nutrients(*(getattr(self, f.name) * factor for f in fields(self)))

    def rounded(self) -> dict:
        return {k: round(v, 1) for k, v in asdict(self).items()}


def for_amount(per_100: Nutrients, amount: float, unit: str, grams_per_piece: float | None = None) -> Nutrients:
    """Nährwerte für eine Menge in g, ml (≈ g) oder Stück."""
    if unit == "stk":
        if not grams_per_piece:
            raise ValueError("Stück-Zutat ohne Gewicht pro Stück")
        amount *= grams_per_piece
    return per_100.scaled(amount / 100)


def per_serving(items: list[Nutrients], servings: int) -> Nutrients:
    total = sum(items, Nutrients())
    return total.scaled(1 / servings)


def grams(amount: float, unit: str, grams_per_piece: float | None) -> float | None:
    """Gewicht in g (ml ≈ g, Löffelmaße geschätzt); None = Stück ohne bekanntes Gewicht."""
    if unit in SPOON_G:
        return amount * SPOON_G[unit]
    if unit == "stk":
        return amount * grams_per_piece if grams_per_piece else None
    return amount


def per_100(food) -> Nutrients:
    return Nutrients(food.kcal or 0, food.protein or 0, food.carbs or 0, food.fat or 0, food.fiber or 0)


def dish(ingredients: list[dict], maps: dict, portions: float, scale: float = 1) -> tuple[dict | None, list | None]:
    """Nährwerte und Gewichtsanteile pro Portion. maps: ingredient_key → (IngredientMap, Food | None).
    Fehlt eine Zuordnung noch (Hintergrund läuft) → (None, None). Zutaten ohne passenden Eintrag zählen mit 0."""
    total, parts = Nutrients(), []
    for ing in ingredients:
        hit = maps.get(ingredient_key(ing["name"]))
        if hit is None:
            return None, None
        m, food = hit
        g = grams((ing.get("amount") or 0) * scale, ing.get("unit", ""), m.grams_per_piece)
        if g is None:
            return None, None
        if food is not None:
            total += per_100(food).scaled(g / 100)
        parts.append((ing["name"], g))
    portions = portions or 1
    weight = sum(g for _, g in parts)
    composition = [{"name": n, "grams": round(g / portions, 1), "share": round(g / weight, 4) if weight else 0}
                   for n, g in sorted(parts, key=lambda p: -p[1])]
    if composition and weight:  # Rundung: Blüte summiert genau 100 %
        composition[0]["share"] = round(1 - sum(c["share"] for c in composition[1:]), 4)
    return total.scaled(1 / portions).rounded(), composition
