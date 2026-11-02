import math
import re

_UNITS = {"g": ("g", 1), "kg": ("g", 1000), "ml": ("ml", 1), "l": ("ml", 1000), "liter": ("ml", 1000), "cl": ("ml", 10),
          "stk": ("stk", 1), "stück": ("stk", 1), "st": ("stk", 1)}
_QTY = re.compile(r"(?:(\d+)\s*[x×]\s*)?(\d+(?:[.,]\d+)?)\s*-?\s*(kg|g|ml|cl|liter|l|stück|stk|st)\b", re.I)
# Beutel/Säcke: Literangabe ist das Fassungsvermögen, kein Inhalt ("Duft-Müllbeutel 35 l"); Nachfüllbeutel bleiben
BAG = re.compile(r"(müll|abfall|gefrier|frühstücks|allzweck)\w*beutel|s[aä]ck", re.I)


def parse_quantity(text: str) -> tuple[float, str] | None:
    """'6 x 1,5 l' -> (9000.0, 'ml'); '400-g-Packung' -> (400.0, 'g'). Einheit: g, ml oder stk."""
    for m in _QTY.finditer(text or ""):
        count, value, unit = m.groups()
        base, factor = _UNITS[unit.lower()]
        if base == "ml" and BAG.search(text):
            continue
        return float(value.replace(",", ".")) * factor * int(count or 1), base
    return None


def base_price_cents(price_cents: int, amount: float | None, unit: str) -> int | None:
    """Preis pro kg, l (bei g/ml) bzw. pro Stück."""
    if not amount:
        return None
    per = 1000 if unit in ("g", "ml") else 1
    return cents(price_cents * per / amount)


def euro_to_cents(text: str | float) -> int:
    """'1,99 €' / '1.99' / 1.99 -> 199"""
    if isinstance(text, (int, float)):
        return cents(text * 100)
    s = re.sub(r"[^\d,.\-]", "", text).replace(",", ".")
    return cents(float(s) * 100)


def cents(value: float) -> int:
    """Kaufmännisch runden (Python-round rundet 598,5 auf 598)."""
    return math.floor(value + 0.5 + 1e-9)
