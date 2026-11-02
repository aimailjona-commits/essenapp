import pytest

from app.services.normalize import base_price_cents, euro_to_cents, parse_quantity


@pytest.mark.parametrize("text,expected", [
    ("400 g", (400.0, "g")),
    ("1 kg", (1000.0, "g")),
    ("500-g-Packung", (500.0, "g")),
    ("6 x 1,5 l", (9000.0, "ml")),
    ("0,75 l Flasche", (750.0, "ml")),
    ("20 x 0,33-Liter-Flaschen", (6600.0, "ml")),
    ("10 Stück", (10.0, "stk")),
    ("je Packung", None),
    ("Duft-Müllbeutel 35 l", None),  # Fassungsvermögen, kein Inhalt
    ("Recycling-Abfallsäcke 60 l", None),
    ("Müllbeutel 35 l, 20 Stück", (20.0, "stk")),
    ("Seife Nachfüllbeutel 1 l", (1000.0, "ml")),
    ("Kartoffeln 2,5 kg Sack", (2500.0, "g")),
])
def test_parse_quantity(text, expected):
    assert parse_quantity(text) == expected


def test_base_price():
    assert base_price_cents(399, 400, "g") == 998
    assert base_price_cents(79, 1, "stk") == 79
    assert base_price_cents(199, None, "") is None


def test_euro_to_cents():
    assert euro_to_cents("1,99 €") == 199
    assert euro_to_cents(3.49) == 349
