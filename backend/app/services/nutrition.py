"""Nährwerte werden gerechnet, nicht von der KI geschätzt (E10)."""
from dataclasses import dataclass, fields


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
