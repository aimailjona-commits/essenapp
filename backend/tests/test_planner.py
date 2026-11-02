from datetime import date, timedelta

from app.models import Household, Offer
from app.services import planner
from app.services.planner import PlanDraft, PlannedIngredient, PlannedMeal


def ing(name, amount, unit="g", offer_id=None, pack=500, price=200, pantry=False):
    return PlannedIngredient(name=name, amount=amount, unit=unit, offer_id=offer_id, pack_amount=pack,
                             pack_price_cents=price, in_pantry=pantry)


def meal(day, title, ingredients, meal_type="mittag"):
    return PlannedMeal(day=day, meal_type=meal_type, title=title, description="", cuisine="", prep_minutes=20,
                       servings=2, ingredients=ingredients, steps=["kochen"])


chicken = Offer(id=7, chain="rewe", title="Hähnchen", price_cents=399, regular_price_cents=599, amount=400, unit="g",
                source_id="x", valid_from=date.today(), valid_to=date.today())


def test_price_shares_packs_across_meals_and_uses_db_offer_price():
    draft = PlanDraft(meals=[
        meal(0, "Curry", [ing("Hähnchen", 300, offer_id=7, price=1), ing("Salz", 5, pantry=True)]),
        meal(1, "Wrap", [ing("Hähnchen", 300, offer_id=7), ing("Feta", 100, pack=200, price=149)]),
    ])
    p = planner.price(draft, {7: chicken})
    # 600 g Hähnchen → 2 Packungen à 3,99 (Preis aus der DB, nicht aus der KI-Antwort); Feta 1 Packung; Salz Vorrat
    assert p.total_cents == 2 * 399 + 149
    assert p.saved_cents == 2 * 200
    assert p.meal_costs == [300, 300 + 75]  # 599 ct Verbrauch, je Hälfte kaufmännisch gerundet


def test_make_plan_repairs_when_over_budget_and_keeps_cheapest():
    household = Household(persons=2, diet="alles", allergies=[], excluded_ingredients=[], cuisines=[],
                          nutrition_goal="ausgewogen", max_cook_minutes=30, budget_food_week_cents=500,
                          meal_types=["mittag"], plan_days=[0])
    expensive = PlanDraft(meals=[meal(0, "Steak", [ing("Rind", 500, pack=500, price=1500)])])
    cheap = PlanDraft(meals=[meal(0, "Linsen", [ing("Linsen", 250, pack=500, price=129)]), meal(3, "zu viel", [])])
    prompts = []

    def ask(prompt):
        prompts.append(prompt)
        return expensive if len(prompts) == 1 else cheap

    p = planner.make_plan(household, [], planner.week_slots(household), favorites=[], ask=ask)
    assert p.total_cents == 129
    assert [m.title for m in p.draft.meals] == ["Linsen"]  # nicht angefragte Slots fliegen raus
    assert "Budget ist 500 ct" in prompts[1]


def test_week_slots_order():
    h = Household(meal_types=["abend", "fruehstueck", "quatsch"], plan_days=[2, 0])
    assert planner.week_slots(h) == [(0, "fruehstueck"), (0, "abend"), (2, "fruehstueck"), (2, "abend")]


def test_plan_endpoint(client, auth, db, monkeypatch):
    client.patch("/household", headers=auth, json={"meal_types": ["mittag"], "plan_days": [0, 1],
                                                    "stores": [{"chain": "rewe", "store_ref": "1"}]})
    db.add(Offer(chain="rewe", store_ref="1", source_id="h", title="Hähnchen", price_cents=399, amount=400, unit="g",
                 valid_from=date.today(), valid_to=date.today() + timedelta(days=2)))
    db.commit()
    seen = {}

    def fake_ask(prompt):
        seen["prompt"] = prompt
        return PlanDraft(meals=[meal(0, "Curry", [ing("Hähnchen", 400, offer_id=1)]), meal(1, "Dal", [ing("Linsen", 250)])])

    monkeypatch.setattr(planner, "ask_claude", fake_ask)
    monkeypatch.setattr(planner.make_plan, "__defaults__", (fake_ask, 2))
    r = client.post("/plans", headers=auth)
    assert r.status_code == 201, r.text
    body = r.json()
    assert [e["recipe"]["title"] for e in body["entries"]] == ["Curry", "Dal"]
    assert body["total_cents"] == 399 + 200
    assert "1 | rewe | Hähnchen | 399 ct" in seen["prompt"]
    assert client.get("/plans/current", headers=auth).json()["id"] == body["id"]


def test_reroll_and_lock_entry(client, auth, db, monkeypatch):
    test_plan_endpoint(client, auth, db, monkeypatch)
    plan = client.get("/plans/current", headers=auth).json()
    curry, dal = plan["entries"]
    seen = {}

    def fake_ask(prompt):
        seen["prompt"] = prompt
        return PlanDraft(meals=[meal(0, "Chili", [ing("Bohnen", 400, pack=400, price=99)])])

    monkeypatch.setattr(planner, "ask_claude", fake_ask)
    r = client.post(f"/plans/current/entries/{curry['id']}/reroll", headers=auth)
    assert r.status_code == 200, r.text
    body = r.json()
    assert [e["recipe"]["title"] for e in body["entries"]] == ["Chili", "Dal"]
    assert body["total_cents"] == 99 + 200 and body["entries"][0]["cost_cents"] == 99
    assert "anders als: Curry und andere Gerichte der Woche (Dal)" in seen["prompt"]
    assert "day=0 (Montag), meal_type=mittag" in seen["prompt"] and "day=1" not in seen["prompt"]

    r = client.patch(f"/plans/current/entries/{dal['id']}", headers=auth, json={"locked": True})
    assert r.status_code == 200 and r.json()["entries"][1]["locked"] is True
    assert client.post(f"/plans/current/entries/{dal['id']}/reroll", headers=auth).status_code == 409
    assert client.post("/plans/current/entries/9999/reroll", headers=auth).status_code == 404
