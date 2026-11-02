import pytest

from app.services.nutrition import Nutrients, for_amount, per_serving
from app.services.pricing import Pack, cost_line, sum_needs


def test_whole_packs_and_leftover():
    line = cost_line("haehnchenbrust", 600, [Pack(399, 400, regular_price_cents=599)])
    assert line.packs == 2
    assert line.buy_cents == 798
    assert line.use_cents == 599  # 600/400 * 3,99
    assert line.leftover == 200
    assert line.saved_cents == 400


def test_picks_cheapest_total_not_cheapest_pack():
    small = Pack(150, 250)  # 2 nötig → 3,00
    big = Pack(249, 1000)   # 1 nötig → 2,49
    assert cost_line("reis", 400, [small, big]).pack == big


def test_pantry_is_free():
    line = cost_line("salz", 5, [], in_pantry=True)
    assert line.buy_cents == 0 and line.pack is None


def test_missing_price_raises():
    with pytest.raises(ValueError):
        cost_line("trueffel", 10, [])


def test_sum_needs():
    assert sum_needs([[("zwiebel", 1), ("reis", 200)], [("zwiebel", 2)]]) == {"zwiebel": 3, "reis": 200}


def test_nutrition_grams_and_pieces():
    rice = Nutrients(kcal=350, protein=7, carbs=78, fat=0.6)
    assert for_amount(rice, 200, "g").kcal == 700
    egg = Nutrients(kcal=150, protein=12.5)
    assert for_amount(egg, 2, "stk", grams_per_piece=60).protein == 15
    with pytest.raises(ValueError):
        for_amount(egg, 2, "stk")


def test_per_serving():
    n = per_serving([Nutrients(kcal=800, protein=40), Nutrients(kcal=400, protein=20)], servings=2)
    assert (n.kcal, n.protein) == (600, 30)
