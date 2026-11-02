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


def text(prompt):
    return "\n".join(block["text"] for block in prompt)


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
        usage = {"model": "claude-haiku-5-5", "input_tokens": 1000, "output_tokens": 100, "cost_cents": 0.015}
        return (expensive if len(prompts) == 1 else cheap), usage

    p = planner.make_plan(household, [], planner.week_slots(household), favorites=[], ask=ask)
    assert p.total_cents == 129
    assert [m.title for m in p.draft.meals] == ["Linsen"]  # nicht angefragte Slots fliegen raus
    assert "Budget ist 500 ct" in text(prompts[1])
    assert prompts[0][0] == prompts[1][0]  # Angebotsblock bleibt gleich (Cache-Präfix)
    assert p.usage["input_tokens"] == 2000 and p.usage["cost_cents"] == 0.03 and p.usage["model"] == "claude-haiku-5-5"

    prompts.clear()  # höchstens eine Korrekturrunde
    p = planner.make_plan(household, [], planner.week_slots(household), favorites=[], ask=lambda c: ask(c) and (expensive, {}))
    assert len(prompts) == 2 and p.total_cents == 1500


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
        seen["prompt"] = text(prompt)
        return PlanDraft(meals=[meal(0, "Curry", [ing("Hähnchen", 400, offer_id=1)]), meal(1, "Dal", [ing("Linsen", 250)])]), \
            {"model": "claude-haiku-5-5", "cost_cents": 0.5}

    monkeypatch.setattr(planner, "ask_claude", fake_ask)
    r = client.post("/plans", headers=auth)
    assert r.status_code == 201, r.text
    body = r.json()
    assert [e["recipe"]["title"] for e in body["entries"]] == ["Curry", "Dal"]
    assert body["total_cents"] == 399 + 200
    assert "1|Hähnchen|399|400g|rewe" in seen["prompt"] and "Wünsche" not in seen["prompt"]
    assert client.get("/plans/current", headers=auth).json()["id"] == body["id"]
    assert client.get("/usage", headers=auth).json() == {"plans": 1, "cost_cents_total": 0.5, "cost_cents_last": 0.5,
                                                         "by_kind": {"plan": 0.5}, "recent": []}


def test_reroll_and_lock_entry(client, auth, db, monkeypatch):
    test_plan_endpoint(client, auth, db, monkeypatch)
    plan = client.get("/plans/current", headers=auth).json()
    curry, dal = plan["entries"]
    seen = {}

    def fake_ask(prompt):
        seen["prompt"] = text(prompt)
        return PlanDraft(meals=[meal(0, "Chili", [ing("Bohnen", 400, pack=400, price=99)])]), {"cost_cents": 0.25}

    monkeypatch.setattr(planner, "ask_claude", fake_ask)
    r = client.post(f"/plans/current/entries/{curry['id']}/reroll", headers=auth)
    assert r.status_code == 200, r.text
    body = r.json()
    assert [e["recipe"]["title"] for e in body["entries"]] == ["Chili", "Dal"]
    assert body["total_cents"] == 99 + 200 and body["entries"][0]["cost_cents"] == 99
    assert "anders als: Curry und andere Gerichte der Woche (Dal)" in seen["prompt"]
    assert "day=0 (Montag), meal_type=mittag" in seen["prompt"] and "day=1" not in seen["prompt"]
    assert client.get("/usage", headers=auth).json()["cost_cents_last"] == 0.75  # Neu würfeln zählt zum Plan

    r = client.patch(f"/plans/current/entries/{dal['id']}", headers=auth, json={"locked": True})
    assert r.status_code == 200 and r.json()["entries"][1]["locked"] is True
    assert client.post(f"/plans/current/entries/{dal['id']}/reroll", headers=auth).status_code == 409
    assert client.post("/plans/current/entries/9999/reroll", headers=auth).status_code == 404


def test_plan_options_override_only_this_plan(client, auth, monkeypatch):
    client.patch("/household", headers=auth, json={"persons": 2, "meal_types": ["abend"], "plan_days": [0, 1]})
    seen = {}

    def fake_ask(prompt):
        seen["prompt"] = text(prompt)
        return PlanDraft(meals=[meal(2, "Fisch", [ing("Lachs", 200)], "mittag")]), {}

    monkeypatch.setattr(planner, "ask_claude", fake_ask)
    body = {"persons": 4, "meal_types": ["mittag"], "plan_days": [2], "wishes": "mehr Fisch, ein Gericht mit Kürbis"}
    r = client.post("/plans", headers=auth, json=body)
    assert r.status_code == 201, r.text
    assert "portionen=4" in seen["prompt"] and "Wünsche: mehr Fisch, ein Gericht mit Kürbis" in seen["prompt"]
    assert "day=2 (Mittwoch), meal_type=mittag" in seen["prompt"] and "abend" not in seen["prompt"]
    h = client.get("/household", headers=auth).json()
    assert (h["persons"], h["meal_types"], h["plan_days"]) == (2, ["abend"], [0, 1])

    assert client.post("/plans", headers=auth, json={**body, "save_as_default": True}).status_code == 201
    h = client.get("/household", headers=auth).json()
    assert (h["persons"], h["meal_types"], h["plan_days"]) == (4, ["mittag"], [2]) and "wishes" not in h
    assert client.post("/plans", headers=auth, json={"wishes": "x" * 301}).status_code == 422
    assert client.post("/plans", headers=auth, json={"plan_days": [7]}).status_code == 422


def offer(i, title, category="kuehlung", regular=None, amount=None):
    return Offer(id=i, chain="lidl", title=title, category=category, price_cents=100 + i, regular_price_cents=regular,
                 amount=amount, unit="g" if amount else "", source_id=str(i), valid_from=date.today(), valid_to=date.today())


def test_select_offers_food_only_dedup_prefers_discount_and_keeps_variety():
    offers = [offer(1, "Bier", "getraenke"), offer(2, "Shampoo", "drogerie"), offer(3, "Milch"),
              offer(4, "milch ", regular=300), offer(5, "Quark", amount=500), offer(6, "Joghurt"),
              *[offer(10 + i, f"Wurst {i}", "fleisch_fisch") for i in range(5)], offer(20, "Nudeln", "vorrat")]
    picked = planner.select_offers(offers, limit=6)
    assert [o.id for o in picked] == [10, 4, 20, 11, 5, 12]
    assert len(planner.select_offers(offers)) == 9  # ohne Getränke, Drogerie und die Milch-Dublette


def test_cost_cents():
    assert planner.cost_cents({"model": "claude-haiku-5-5", "input_tokens": 1_000_000, "output_tokens": 1_000_000}) == 60
    assert planner.cost_cents({"model": "claude-haiku-5-5", "cache_read_input_tokens": 1_000_000,
                               "cache_creation_input_tokens": 1_000_000}) == 1 + 12.5
    assert planner.cost_cents({"model": "claude-sonnet-5-5", "input_tokens": 10_000, "output_tokens": 2_000}) == 4
    assert planner.cost_cents({"model": "claude-opus-5-5", "input_tokens": 10_000, "output_tokens": 2_000}) == 8
