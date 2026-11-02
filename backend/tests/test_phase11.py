"""Phase 11 (Clever planen) + Ersatzzutaten (7): Abwechslung, Gäste, Keine Lust, Reste, Frühstück/Snacks, Lunchbox,
Specials, Plan-Generator."""
import random
import re
import time
from datetime import date, datetime, timedelta

from app import jobs
from app.jobs import BERLIN
from app.models import Household, MealPlan, Member, Offer, PantryItem, Recipe
from app.services import food_map, pantry_ai, planner, seasons, substitutes, variety
from app.services.planner import PlanDraft, PlannedIngredient, PlannedMeal

RULES = variety.rules_of({})


def ing(name, amount, unit="g", offer_id=None, pack=500, price=200, pantry=False):
    return PlannedIngredient(name=name, amount=amount, unit=unit, offer_id=offer_id, pack_amount=pack,
                             pack_price_cents=price, in_pantry=pantry)


def meal(day, title, ingredients=(), meal_type="mittag", side="andere", protein="vegetarisch", cuisine="", steps=None,
         prep=20):
    return PlannedMeal(day=day, meal_type=meal_type, title=title, description="", cuisine=cuisine, prep_minutes=prep,
                       servings=2, ingredients=list(ingredients), steps=steps or ["kochen"], side=side, protein=protein)


def text(prompt):
    return "\n".join(block["text"] for block in prompt)


def household(**kw):
    values = dict(persons=2, diet="alles", allergies=[], excluded_ingredients=[], cuisines=[], plz="",
                  nutrition_goal="ausgewogen", max_cook_minutes=30, budget_food_week_cents=100000,
                  meal_types=["mittag", "abend"], plan_days=list(range(7)), variety={})
    return Household(**(values | kw))


USAGE = {"model": "claude-haiku-5-5", "input_tokens": 100, "output_tokens": 10, "cost_cents": 0.01}


# --- 12 Abwechslung ---

def repair_fake(first: PlanDraft, calls: list):
    """Gefälschte KI: erster Aufruf = Entwurf mit Verstößen, zweiter Durchgang befolgt die Anweisungen je Slot."""
    def ask(prompt):
        calls.append(text(prompt))
        if len(calls) == 1:
            return first, USAGE
        meals = []
        for d, m, fix in re.findall(r"- day=(\d) \(\w+\), meal_type=(\w+): (.*)", calls[-1]):
            protein = "fisch" if "Fischgericht" in fix else "vegetarisch"
            meals.append(meal(int(d), f"Neu {d} {m}", meal_type=m, protein=protein, cuisine=f"küche{d}{m}"))
        return PlanDraft(meals=meals), USAGE
    return ask


def test_ten_fake_plans_keep_all_variety_rules():
    h = household()
    slots = planner.week_slots(h)
    for seed in range(10):
        rnd = random.Random(seed)
        first = PlanDraft(meals=[meal(d, rnd.choice(["Spaghetti", "Risotto", "Gulasch", "Curry", "Bowl"]) + f" {d}{m}",
                                      meal_type=m, side=rnd.choice(["pasta", "reis", "kartoffel", "andere"]),
                                      protein=rnd.choice(["rot", "gefluegel", "vegetarisch", "rot"]),
                                      cuisine=rnd.choice(["italienisch", "deutsch"])) for d, m in slots])
        before = variety.check(planner.dishes(first.meals), RULES)
        calls = []
        p = planner.make_plan(h, [], slots, favorites=[], ask=repair_fake(first, calls), rules=RULES)
        after = variety.check(planner.dishes(p.draft.meals), RULES)
        assert before.issues and after.issues == [], (seed, before.issues, after.issues)
        assert len(calls) == 2  # genau eine Reparatur-Runde
        repaired = {(int(d), m) for d, m in re.findall(r"- day=(\d) \(\w+\), meal_type=(\w+):", calls[1])}
        assert repaired == set(before.fixes)  # nur die betroffenen Slots
        assert "Bleibt im Plan:" in calls[1]


def test_check_texts_and_rules_line():
    meals = [meal(0, "Spaghetti A", side="pasta", protein="rot", cuisine="italienisch"),
             meal(1, "Spaghetti B", side="pasta", protein="rot", cuisine="italienisch"),
             meal(2, "Steak", protein="rot")]
    c = variety.check(planner.dishes(meals), RULES)
    assert c.issues[:2] == ["2× Pasta", "3× rotes Fleisch"] and "kein Fisch" in c.issues
    assert "2× italienisch hintereinander" in c.issues and "nur 0 vegetarische Tage" not in c.issues
    assert "kein vegetarischer Tag" in c.issues
    assert c.fixes[(1, "mittag")][0] == "Beilage nicht Pasta"
    line = variety.rules_line(RULES, fish_ok=True)
    assert "Pasta max. 1×" in line and "Fisch mind. 1×" in line and "Folgetagen" not in line
    assert "Fisch" not in variety.rules_line(RULES, fish_ok=False)
    assert variety.check(planner.dishes(meals), RULES | {"max_pasta": 2, "max_red_meat": 3, "min_fish": 0,
                                                         "veggie_days": 0, "no_same_cuisine_row": False}).issues == []


def test_breakfast_and_lunchbox_rules():
    meals = [meal(0, "Porridge", meal_type="fruehstueck", prep=5), meal(1, "Porridge", meal_type="fruehstueck", prep=5),
             meal(2, "Shakshuka", meal_type="fruehstueck", prep=25),
             meal(0, "Linsensuppe", meal_type="lunchbox", steps=["Am Vorabend: kochen"]),
             meal(1, "Kürbissuppe", meal_type="lunchbox", steps=["Am Vorabend: kochen, im Thermobehälter mitnehmen"])]
    c = variety.check(planner.dishes(meals), RULES | {"veggie_days": 0, "min_fish": 0})
    assert set(c.issues) == {"Frühstück wiederholt sich", "Frühstück über 10 min", "Lunchbox-Suppe ohne Thermobehälter"}
    assert set(c.fixes) == {(1, "fruehstueck"), (2, "fruehstueck"), (0, "lunchbox")}


def test_variety_settings_and_chip(client, auth, monkeypatch):
    r = client.patch("/household", headers=auth, json={"variety": {"max_pasta": 2, "no_same_cuisine_row": False, "veggie_days": 1},
                                                       "meal_types": ["mittag"], "plan_days": [0, 1]})
    v = r.json()["variety"]
    assert v["max_pasta"] == 2 and v["no_same_cuisine_row"] is False and v["max_rice"] == 2
    client.patch("/household", headers=auth, json={"variety": {"max_pasta": 0}})
    assert client.get("/household", headers=auth).json()["variety"]["no_same_cuisine_row"] is False
    assert client.patch("/household", headers=auth, json={"variety": {"veggie_days": 8}}).status_code == 422

    def ask(prompt):
        return PlanDraft(meals=[meal(0, "Pasta", side="pasta"), meal(1, "Lachs", protein="fisch")]), USAGE
    monkeypatch.setattr(planner, "ask_claude", ask)
    body = client.post("/plans", headers=auth).json()
    assert body["variety"] == {"ok": False, "issues": ["1× Pasta"]}  # max_pasta 0, Reparatur bringt nichts
    assert body["entries"][0]["recipe"]["tags"] == ["pasta", "vegetarisch"]
    client.patch("/household", headers=auth, json={"variety": {"max_pasta": 1}})
    assert client.get("/plans/current", headers=auth).json()["variety"] == {"ok": True, "issues": []}


# --- 15 Gäste ---

def test_guests_in_generator_and_afterwards(client, auth, db, monkeypatch):
    client.patch("/household", headers=auth, json={"meal_types": ["mittag"], "plan_days": [4, 5], "persons": 2,
                                                   "stores": [{"chain": "rewe", "store_ref": "1"}]})
    db.add(Offer(chain="rewe", store_ref="1", source_id="h", title="Hähnchen", price_cents=400, amount=1000, unit="g",
                 category="fleisch_fisch", valid_from=date.today(), valid_to=date.today() + timedelta(days=2)))
    db.commit()
    seen = []

    def ask(prompt):
        seen.append(text(prompt))
        return PlanDraft(meals=[meal(4, "Linsen", [ing("Linsen", 200)]),
                                meal(5, "Hähnchen", [ing("Hähnchen", 600, offer_id=1)], protein="gefluegel")]), USAGE
    monkeypatch.setattr(planner, "ask_claude", ask)
    r = client.post("/plans", headers=auth, json={"guests": [{"day": 5, "meal_type": "mittag", "count": 4}],
                                                  "guest_budget_cents": 2000, "save_as_default": True})
    assert r.status_code == 201, r.text
    assert "day=5 (Samstag), meal_type=mittag, portionen=6 (davon 4 Gäste)" in seen[0]
    sat = r.json()["entries"][1]
    assert (sat["guests"], sat["portions_total"]) == (4, 6)
    assert "guests" not in client.get("/household", headers=auth).json()

    # nachträglich: +4 → ×(2+4)/2 bezogen auf die Esser; hier von 4 auf 2 Gäste → Mengen × 4/6
    friday = r.json()["entries"][0]
    r = client.post(f"/plans/current/entries/{friday['id']}/guests", headers=auth, json={"count": 4})
    fri = r.json()["entries"][0]
    assert (fri["guests"], fri["portions_total"], fri["scale"]) == (4, 6, 3)
    items = {i["name"]: i for i in client.get("/lists", headers=auth).json() and
             client.get(f"/lists/{client.get('/lists', headers=auth).json()[0]['id']}", headers=auth).json()["items"]}
    assert items["Linsen"]["amount"] == 600  # 200 g × (2+4)/2
    r = client.post(f"/plans/current/entries/{sat['id']}/guests", headers=auth, json={"count": 0})
    assert r.json()["entries"][1]["scale"] == 2 / 6 and r.json()["entries"][1]["portions_total"] == 2
    assert client.post(f"/plans/current/entries/{sat['id']}/guests", headers=auth, json={"count": 21}).status_code == 422


# --- 16 Keine Lust ---

def idea(title, ingredients, prep=10):
    return pantry_ai.Idea(title=title, description="", cuisine="", meal_type="abend", prep_minutes=prep, servings=2,
                          ingredients=[pantry_ai.IdeaIngredient(name=n, amount=a, unit=u) for n, a, u in ingredients],
                          steps=["kochen"], image_query="")


def test_no_mood_only_without_missing_ingredients(client, auth, monkeypatch):
    lst = client.get("/lists", headers=auth).json()[0]["id"]
    item = client.post(f"/lists/{lst}/items", headers=auth, json={"name": "Nudeln", "amount": 500, "unit": "g"}).json()
    client.patch(f"/items/{item['id']}", headers=auth, json={"checked": True})
    client.post("/pantry", headers=auth, json={"name": "Eier", "amount": 6, "unit": "stk"})
    prompts = []

    def ask(prompt, schema, think=True):
        prompts.append(prompt)
        assert think is False  # schnell: ohne Denkphase
        return pantry_ai.Ideas(ideas=[
            idea("Nudeln mit Ei", [("Nudeln", 250, "g"), ("Eier", 2, "stk"), ("Salz", 1, "prise"), ("Wasser", 2000, "ml")]),
            idea("Rührei", [("Eier", 8, "stk")]),  # mehr als da, aber angebrochen da → ok
            idea("Carbonara", [("Nudeln", 250, "g"), ("Speck", 100, "g")]),  # Speck fehlt
            idea("Lasagne", [("Nudeln", 250, "g")], prep=60),  # zu lang
        ]), USAGE
    monkeypatch.setattr(food_map, "ask_claude", ask)
    start = time.time()
    r = client.post("/no-mood", headers=auth, json={"exclude": ["Omelett"]})
    assert r.status_code == 200, r.text
    assert time.time() - start < 8
    assert [i["recipe"]["title"] for i in r.json()] == ["Nudeln mit Ei", "Rührei"]
    assert all(i["missing"] == [] for i in r.json())
    assert "Höchstens 15 Minuten" in prompts[0] and "es darf nichts fehlen" in prompts[0]
    assert "Nudeln 500g" in prompts[0] and "Nicht noch einmal vorschlagen: Omelett" in prompts[0]
    assert client.get("/usage", headers=auth).json()["by_kind"]["no_mood"] == 0.01


def test_postpone_shifts_later_dishes(client, auth, monkeypatch):
    client.patch("/household", headers=auth, json={"meal_types": ["abend"], "plan_days": [0, 1, 2, 3]})
    monkeypatch.setattr(planner, "ask_claude", lambda p: (PlanDraft(meals=[
        meal(d, t, [ing(t, 100)], meal_type="abend") for d, t in enumerate(["A", "B", "C", "D"])]), USAGE))
    plan = client.post("/plans", headers=auth).json()
    a, b, c, d = plan["entries"]
    client.patch(f"/plans/current/entries/{c['id']}", headers=auth, json={"locked": True})
    other = client.post("/recipes", headers=auth, json={"title": "Schnell", "servings": 2, "prep_minutes": 10,
                                                        "meal_type": "abend",
                                                        "ingredients": [{"name": "Ei", "amount": 2, "unit": "stk"}]})
    client.post(f"/plans/current/entries/{a['id']}/replace", headers=auth, json={"recipe_id": other.json()["id"]})
    r = client.post("/plans/current/postpone", headers=auth,
                    json={"recipe_id": a["recipe"]["id"], "day": 1, "meal_type": "abend"})
    assert r.status_code == 200, r.text
    assert [e["recipe"]["title"] for e in r.json()["entries"]] == ["Schnell", "A", "C", "B"]  # C fixiert, D fällt raus
    assert client.post("/plans/current/postpone", headers=auth,
                       json={"recipe_id": a["recipe"]["id"], "day": 2, "meal_type": "abend"}).status_code == 422


# --- 19 Reste ---

def chicken(i=7, amount=400, category="fleisch_fisch", title="Hähnchen"):
    return Offer(id=i, chain="rewe", title=title, price_cents=399, amount=amount, unit="g", category=category,
                 source_id=str(i), valid_from=date.today(), valid_to=date.today())


def test_price_tracks_rests_badges_and_leftovers():
    offers = {7: chicken(), 8: chicken(8, 200, "kuehlung", "Feta")}
    draft = PlanDraft(meals=[
        meal(0, "Curry", [ing("Hähnchen", 250, offer_id=7), ing("Feta", 100, offer_id=8)], protein="gefluegel"),
        meal(1, "Wrap", [ing("Hähnchen", 150, offer_id=7)], protein="gefluegel"),
        meal(6, "Salat", [ing("Feta", 50, offer_id=8)]),
    ])
    p = planner.price(draft, offers)
    assert p.rests["badges"] == {"1|mittag": {"Hähnchen": 0}}  # Feta am So: nach Fr (Anbruch Mo + 4) abgelaufen
    assert p.rests["planned"] == 1
    assert [(r["name"], r["amount"], r["until_day"]) for r in p.rests["left"]] == [("Feta", 50, 4)]
    assert p.rests["after"]["0|mittag"] == [{"name": "Hähnchen", "amount": 150, "unit": "g", "until_day": 2},
                                            {"name": "Feta", "amount": 100, "unit": "g", "until_day": 4}]
    assert planner.price(PlanDraft(meals=[meal(0, "x", [ing("Reis", 100, pack=1000)])]), {}).rests["left"] == []


def test_second_pass_uses_at_least_70_percent_of_rests():
    offers = [chicken(), chicken(8, 200, "kuehlung", "Feta"), chicken(9, 200, "kuehlung", "Sahne"),
              chicken(10, 500, "obst_gemuese", "Zucchini")]
    first = PlanDraft(meals=[
        meal(0, "Hähnchen-Curry", [ing("Hähnchen", 250, offer_id=7), ing("Sahne", 100, offer_id=9)], protein="gefluegel",
             cuisine="indisch"),
        meal(0, "Feta-Salat", [ing("Feta", 100, offer_id=8)], meal_type="abend", cuisine="griechisch"),
        meal(1, "Hähnchen-Wrap", [ing("Hähnchen", 300, offer_id=7)], protein="gefluegel", cuisine="mexikanisch"),
        meal(1, "Zucchini-Pfanne", [ing("Zucchini", 200, offer_id=10)], meal_type="abend", cuisine="deutsch"),
        meal(2, "Lachs", [ing("Lachs", 200, pack=200)], protein="fisch", cuisine="nordisch"),
        meal(2, "Linsen", [ing("Linsen", 200)], meal_type="abend", cuisine="türkisch"),
        meal(3, "Pute", [ing("Pute", 200, pack=200)], protein="gefluegel", cuisine="asiatisch"),
        meal(3, "Bohnen", [ing("Bohnen", 200)], meal_type="abend", cuisine="spanisch"),
    ])
    h = household(plan_days=[0, 1, 2, 3])
    before = planner.price(first, {o.id: o for o in offers})
    assert len(before.rests["left"]) == 4  # Hähnchen 250, Feta 100, Sahne 100, Zucchini 300
    calls = []

    def ask(prompt):
        calls.append(text(prompt))
        if len(calls) == 1:
            return first, USAGE
        meals = []
        for d, m, todo in re.findall(r"- day=(\d) \(\w+\), meal_type=(\w+): (.*)", calls[-1]):
            used = [ing(n, float(a), u, offer_id=int(o)) for a, u, n, o in
                    re.findall(r"verwende Rest ([\d.]+) (\w+) (\w+) \(offer_id=(\d+)\)", todo)]
            old = next(x for x in first.meals if (x.day, x.meal_type) == (int(d), m))
            meals.append(old.model_copy(update={"title": old.title + " mit Resten",
                                                "ingredients": [*old.ingredients, *used]}))
        return PlanDraft(meals=meals), USAGE

    p = planner.make_plan(h, offers, planner.week_slots(h), favorites=[], ask=ask,
                          rules=RULES | {"veggie_days": 0, "min_fish": 0})
    assert len(calls) == 2 and "verwende Rest 250 g Hähnchen (offer_id=7)" in calls[1]
    used = 4 - len(p.rests["left"])
    assert used / 4 >= 0.7 and p.rests["planned"] >= 3
    # Hähnchen geht nur in ein Fleischgericht, nie in ein vegetarisches
    target = re.search(r"- day=(\d) \(\w+\), meal_type=(\w+): [^\n]*Hähnchen", calls[1]).groups()
    assert next(m for m in first.meals if (m.day, m.meal_type) == (int(target[0]), target[1])).protein != "vegetarisch"


def test_plan_rest_card_and_entry_leftovers(client, auth, db, monkeypatch):
    client.patch("/household", headers=auth, json={"meal_types": ["mittag"], "plan_days": [0, 1],
                                                   "stores": [{"chain": "rewe", "store_ref": "1"}]})
    db.add(Offer(chain="rewe", store_ref="1", source_id="h", title="Hähnchen", price_cents=399, amount=400, unit="g",
                 category="fleisch_fisch", valid_from=date.today(), valid_to=date.today() + timedelta(days=2)))
    db.commit()
    monkeypatch.setattr(planner, "ask_claude", lambda p: (PlanDraft(meals=[
        meal(0, "Curry", [ing("Hähnchen", 250, offer_id=1)], protein="gefluegel"),
        meal(1, "Wrap", [ing("Hähnchen", 100, offer_id=1)], protein="gefluegel")]), USAGE))
    plan = client.post("/plans", headers=auth).json()
    assert plan["entries"][1]["rests"] == [{"name": "Hähnchen", "from_day": 0}]
    assert plan["entries"][0]["rests"] == []
    assert plan["leftovers"] == {"planned": 1, "left": [{"name": "Hähnchen", "amount": 50, "unit": "g", "until_day": 2,
                                                         "suggestion": "Bis Mi verbrauchen oder einfrieren"}]}
    r = client.get(f"/plans/current/entries/{plan['entries'][0]['id']}/leftovers", headers=auth).json()
    monday = date.fromisocalendar(*map(int, plan["week"].split("-W")), 1)
    assert r == [{"name": "Hähnchen", "amount": 150, "unit": "g", "best_before": str(monday + timedelta(days=2))}]
    r = client.post("/pantry/bulk", headers=auth, json=[{"name": "Hähnchen", "amount": 150, "unit": "g",
                                                          "source": "rest", "location": "kuehlschrank"}])
    assert r.json()[0]["source"] == "rest" and r.json()[0]["location"] == "kuehlschrank"


# --- 23 Frühstück & Snacks ---

def test_weekly_basics_to_list_with_offers_and_pantry(client, auth, db):
    client.patch("/household", headers=auth, json={"stores": [{"chain": "lidl", "store_ref": "1"},
                                                              {"chain": "rewe", "store_ref": "2"}]})
    for i, (chain, ref, price) in enumerate([("lidl", "1", 129), ("rewe", "2", 99)]):
        db.add(Offer(chain=chain, store_ref=ref, source_id=str(i), title="Haferflocken zart", price_cents=price,
                     amount=500, unit="g", base_price_cents=price * 2, category="vorrat",
                     valid_from=date.today(), valid_to=date.today() + timedelta(days=3)))
    db.commit()
    ids = [client.post("/weekly-basics", headers=auth, json=b).json()["id"] for b in (
        {"name": "Haferflocken", "amount": 1000, "unit": "g"}, {"name": "Joghurt", "amount": 1000, "unit": "g"},
        {"name": "Brot"}, {"name": "Bananen", "amount": 6, "unit": "stk"})]
    assert client.patch(f"/weekly-basics/{ids[3]}", headers=auth, json={"amount": 5}).json()["amount"] == 5
    client.post("/pantry", headers=auth, json={"name": "Joghurt", "amount": 400, "unit": "g"})
    client.post("/pantry", headers=auth, json={"name": "Brot"})
    lst = client.post("/weekly-basics/to-list", headers=auth).json()
    items = {i["name"]: i for i in lst["items"]}
    assert set(items) == {"Haferflocken", "Joghurt", "Bananen"}  # Brot ist da
    assert (items["Haferflocken"]["chain"], items["Haferflocken"]["amount"]) == ("rewe", 1000)  # günstigere Filiale
    assert items["Joghurt"]["amount"] == 600 and items["Bananen"]["source"] == "basics"
    lst = client.post("/weekly-basics/to-list", headers=auth).json()
    assert len(lst["items"]) == 3  # nicht verdoppelt
    assert client.delete(f"/weekly-basics/{ids[2]}", headers=auth).status_code == 204
    assert len(client.get("/weekly-basics", headers=auth).json()) == 3


def test_weekly_basics_job_monday(db, monkeypatch):
    m = Member(household=Household(name="T", plz=""), name="J", token_hash="x" * 64, role="owner")
    db.add(m)
    db.commit()
    from app import api
    from app.models import WeeklyBasic
    db.add(WeeklyBasic(household_id=m.household_id, name="Haferflocken", amount=500, unit="g"))
    db.commit()
    monkeypatch.setattr(jobs, "refresh_household", lambda db, h: 0)
    jobs.tick(db, datetime(2026, 11, 9, 6, 29, tzinfo=BERLIN))
    assert not api.household_list(db, m.household_id).items
    jobs.tick(db, datetime(2026, 11, 9, 6, 30, tzinfo=BERLIN))
    assert [i.name for i in api.household_list(db, m.household_id).items] == ["Haferflocken"]


def test_breakfast_snack_prompt_and_basics_not_bought_twice(client, auth, monkeypatch):
    client.patch("/household", headers=auth, json={"meal_types": ["fruehstueck", "snack"], "plan_days": [0]})
    client.patch("/me/profile", headers=auth, json={"goal": "proteinreich"})
    client.post("/weekly-basics", headers=auth, json={"name": "Haferflocken", "amount": 1000, "unit": "g"})
    seen = []

    def ask(prompt):
        seen.append(text(prompt))
        return PlanDraft(meals=[meal(0, "Porridge", [ing("Haferflocken", 80), ing("Beeren", 100)], "fruehstueck", prep=5),
                                meal(0, "Skyr-Becher", [ing("Skyr", 250)], "snack")]), USAGE
    monkeypatch.setattr(planner, "ask_claude", ask)
    assert client.post("/plans", headers=auth).status_code == 201
    assert "Frühstücks-/Snack-Basics (kauft der Haushalt jede Woche, bevorzugt nutzen): Haferflocken 1000g" in seen[0]
    assert "Snack-Ziel: proteinreich" in seen[0] and "meal_type=snack" in seen[0]
    lst = client.get("/lists", headers=auth).json()[0]["id"]
    names = [i["name"] for i in client.get(f"/lists/{lst}", headers=auth).json()["items"]]
    assert "Haferflocken" not in names and "Beeren" in names
    assert "fruehstueck: einfach aus Bausteinen" in planner.SYSTEM and "snack: transportierbar" in planner.SYSTEM


# --- 24 Lunchbox ---

def test_lunchbox_slots_for_member_days(client, auth, db, monkeypatch):
    client.patch("/household", headers=auth, json={"meal_types": ["abend"], "plan_days": list(range(7))})
    client.patch("/me/profile", headers=auth, json={"lunchbox_days": [0, 1, 2, 3, 4], "kcal": 2500})
    seen = []

    def ask(prompt):
        seen.append(text(prompt))
        slots = re.findall(r"- day=(\d) \(\w+\), meal_type=(\w+)", seen[-1])
        return PlanDraft(meals=[meal(int(d), f"G{d}{m}", meal_type=m, cuisine=f"k{d}{m}",
                                     protein="fisch" if (d, m) == ("6", "abend") else "vegetarisch",
                                     steps=["Am Vorabend: Salat schneiden"] if m == "lunchbox" else None)
                                for d, m in slots]), USAGE
    monkeypatch.setattr(planner, "ask_claude", ask)
    plan = client.post("/plans", headers=auth).json()
    boxes = [e for e in plan["entries"] if e["meal_type"] == "lunchbox"]
    assert [e["day"] for e in boxes] == [0, 1, 2, 3, 4] and len(seen) == 1
    assert boxes[0]["portions_total"] == 1.25 and boxes[0]["portions"][0]["factor"] == 1.25
    assert "day=0 (Montag), meal_type=lunchbox, portionen=1.25" in seen[0]
    assert "lunchbox: Essen für die Arbeit" in planner.SYSTEM and "Thermobehälter" in planner.SYSTEM

    member = db.query(Member).first()
    member.lunchbox_push, member.plan_prompt_enabled = "20:00", False
    db.commit()
    sent = []
    monkeypatch.setattr(jobs.push, "send", lambda m, title, message, **kw: sent.append((message, kw)) or True)
    monday = date.fromisocalendar(*map(int, plan["week"].split("-W")), 1)
    jobs.tick(db, datetime.combine(monday - timedelta(days=1), datetime.min.time(), BERLIN).replace(hour=19, minute=59))
    assert sent == []
    jobs.tick(db, datetime.combine(monday - timedelta(days=1), datetime.min.time(), BERLIN).replace(hour=20))
    assert sent and sent[0][0] == "🥡 Lunchbox für morgen vorbereiten: G0lunchbox"


# --- 25 Feiertage & Saison ---

def test_holidays_states_and_easter():
    assert seasons.easter(2026) == date(2026, 4, 5) and seasons.easter(2027) == date(2027, 3, 28)
    assert [seasons.state(p) for p in ("50667", "80331", "10115", "01067", "20095", "24103", "99084", "63739", "x")] \
        == ["NW", "BY", "BE", "SN", "HH", "SH", "TH", "BY", None]
    nw, sn = seasons.holidays(2026, "NW"), seasons.holidays(2026, "SN")
    assert nw[date(2026, 6, 4)] == "Fronleichnam" and nw[date(2026, 11, 1)] == "Allerheiligen"
    assert sn[date(2026, 11, 18)] == "Buß- und Bettag" and date(2026, 11, 1) not in sn
    assert seasons.holidays(2026)[date(2026, 5, 14)] == "Christi Himmelfahrt" and len(seasons.holidays(2026)) == 9
    assert seasons.mothers_day(2026) == date(2026, 5, 10)


def test_specials_banner_and_seasons(client, auth):
    s = seasons.specials(date(2026, 12, 10), "50667")
    assert s["banner"]["key"] == "weihnachten" and s["banner"]["text"] == "🎄 Weihnachten in 14 Tagen – Menü planen?"
    assert any(x["key"] == "plaetzchen" and x["running"] for x in s["specials"])
    assert seasons.specials(date(2026, 12, 12))["banner"]["text"] == "🎄 Weihnachten in 12 Tagen – Menü planen?"
    assert seasons.specials(date(2026, 11, 20))["banner"]["key"] == "plaetzchen"
    assert seasons.specials(date(2026, 7, 1))["banner"] is None
    may = seasons.prompt_lines(date(2026, 5, 6))
    assert "Spargel" in may[0] and "Spargelzeit: 1–2 Gerichte mit Spargel einplanen" in may
    assert any("Christi Himmelfahrt" in line for line in seasons.prompt_lines(date(2026, 5, 10)))
    r = client.get("/specials?date=2026-12-10", headers=auth).json()
    assert r["banner"]["days_until"] == 14 and r["banner"]["template"] == "festtagsmenue"


def test_special_template_in_plan(client, auth, monkeypatch):
    client.patch("/household", headers=auth, json={"meal_types": ["abend"], "plan_days": [3]})
    seen = []

    def ask(prompt):
        seen.append(text(prompt))
        return PlanDraft(meals=[meal(int(d), "x" + d + m, meal_type=m) for d, m in
                                re.findall(r"- day=(\d) \(\w+\), meal_type=(\w+)", seen[-1])]), USAGE
    monkeypatch.setattr(planner, "ask_claude", ask)
    r = client.post("/plans", headers=auth, json={"special": "grillsaison"})
    assert r.status_code == 201, r.text
    assert "meal_type=abend" in seen[0] and "Grillparty am" in seen[0]
    assert client.post("/plans", headers=auth, json={"special": "quatsch"}).status_code == 422
    slots, hint = seasons.special_plan("weihnachten", date(2026, 12, 10), [0])
    assert slots == [(3, "vorspeise"), (3, "abend"), (3, "dessert")] and "Festtagsmenü Weihnachten am Do" in hint


# --- 17 Plan-Generator ---

def test_generator_defaults_and_top_offers(client, auth, db):
    client.patch("/household", headers=auth, json={"stores": [{"chain": "rewe", "store_ref": "1"}], "persons": 3})
    for i, (title, price, regular, cat) in enumerate([("Butter", 149, 249, "kuehlung"), ("Lachs", 299, 599, "fleisch_fisch"),
                                                      ("Shampoo", 99, 399, "drogerie"), ("Äpfel", 199, None, "obst_gemuese"),
                                                      ("Käse", 199, 249, "kuehlung"), ("Reis", 99, 199, "vorrat")]):
        db.add(Offer(chain="rewe", store_ref="1", source_id=str(i), title=title, price_cents=price,
                     regular_price_cents=regular, category=cat, valid_from=date.today(),
                     valid_to=date.today() + timedelta(days=2)))
    db.commit()
    r = client.get("/plans/generator", headers=auth).json()
    assert [o["title"] for o in r["top_offers"]] == ["Reis", "Lachs", "Butter"]  # höchster Rabatt zuerst
    assert r["defaults"]["persons"] == 3 and r["defaults"]["meal_types"] == ["mittag", "abend"]
    assert r["week"] == seasons.plan_monday(date.today()).isocalendar().week


# --- 7 Ersatzzutaten ---

def recipe_with(client, auth, ingredients):
    return client.post("/recipes", headers=auth, json={
        "title": "Nudeln in Soße", "servings": 2, "prep_minutes": 20, "meal_type": "abend", "steps": ["kochen"],
        "ingredients": ingredients}).json()


def test_substitutes_table_fast_and_allergies(client, auth, db, monkeypatch):
    monkeypatch.setattr(food_map, "ask_claude", lambda *a: (_ for _ in ()).throw(AssertionError("keine KI")))
    r = recipe_with(client, auth, [{"name": "Nudeln", "amount": 250, "unit": "g"},
                                   {"name": "Sahne", "amount": 200, "unit": "ml"}])
    client.post("/pantry", headers=auth, json={"name": "Frischkäse", "amount": 200, "unit": "g"})
    start = time.time()
    s = client.get(f"/recipes/{r['id']}/ingredients/1/substitutes", headers=auth).json()
    assert time.time() - start < 2 and s["source"] == "tabelle" and 2 <= len(s["options"]) <= 4
    first = s["options"][0]
    assert first["note"] == "cremiger, weniger flüssig"
    assert [(i["name"], i["amount"], i["unit"], i["in_pantry"]) for i in first["ingredients"]] == [
        ("Frischkäse", 150, "g", True), ("Milch", 50, "ml", False)]
    client.patch("/me/profile", headers=auth, json={"allergies": ["Laktose"]})
    s = client.get(f"/recipes/{r['id']}/ingredients/1/substitutes", headers=auth).json()
    names = [i["name"] for o in s["options"] for i in o["ingredients"]]
    assert names == ["Hafer-Cuisine", "Kokosmilch"]
    assert client.get(f"/recipes/{r['id']}/ingredients/9/substitutes", headers=auth).status_code == 404


def test_substitutes_ai_fallback_filters_allergens_and_apply(client, auth, monkeypatch):
    client.patch("/household", headers=auth, json={"allergies": ["Nüsse"], "meal_types": ["abend"], "plan_days": [0]})
    calls = []

    def ask(prompt, schema):
        calls.append(prompt)
        return substitutes.SubOptions(options=[
            substitutes.SubOption(note="nussig", ingredients=[substitutes.SubIng(name="Cashews", amount=30, unit="g")]),
            substitutes.SubOption(note="ähnlich", ingredients=[substitutes.SubIng(name="Kürbiskerne", amount=30, unit="g")]),
            substitutes.SubOption(note="frisch", ingredients=[substitutes.SubIng(name="Sonnenblumenkerne", amount=30, unit="g")]),
        ]), USAGE
    monkeypatch.setattr(food_map, "ask_claude", ask)
    monkeypatch.setattr(planner, "ask_claude", lambda p: (PlanDraft(meals=[
        meal(0, "Bowl", [ing("Yuzu-Kosho", 30), ing("Reis", 200)], meal_type="abend")]), USAGE))
    plan = client.post("/plans", headers=auth).json()
    rid = plan["entries"][0]["recipe"]["id"]
    s = client.get(f"/recipes/{rid}/ingredients/0/substitutes", headers=auth).json()
    assert s["source"] == "ki" and [o["ingredients"][0]["name"] for o in s["options"]] == ["Kürbiskerne", "Sonnenblumenkerne"]
    assert "Niemals verwenden (Allergien): Nüsse" in calls[0] and "Yuzu-Kosho" in calls[0]
    client.get(f"/recipes/{rid}/ingredients/0/substitutes", headers=auth)
    assert len(calls) == 1  # gecacht
    assert client.get("/usage", headers=auth).json()["by_kind"]["substitute"] == 0.01
    r = client.post(f"/recipes/{rid}/ingredients/0/substitute", headers=auth,
                    json={"ingredients": [{"name": "Kürbiskerne", "amount": 30, "unit": "g"}]})
    assert r.status_code == 200, r.text
    assert r.json()["ingredients"][0] == {"name": "Kürbiskerne", "amount": 30, "unit": "g", "replaces": "Yuzu-Kosho"}
    lst = client.get("/lists", headers=auth).json()[0]["id"]
    names = [i["name"] for i in client.get(f"/lists/{lst}", headers=auth).json()["items"]]
    assert "Kürbiskerne" in names and "Yuzu-Kosho" not in names


def test_forbidden_rules():
    f = substitutes.forbidden
    assert f("Schlagsahne", ["Laktoseintoleranz"]) and not f("Hafermilch", ["Laktose"]) and not f("Erdnussbutter", ["Milch"])
    assert f("Dinkelmehl", ["Gluten"]) and not f("Buchweizenmehl", ["Zöliakie"]) and f("Eier", ["Ei"])
    assert not f("Weizenmehl", ["Ei"]) and f("Haselnüsse", ["Nüsse"]) and f("Kiwi-Püree", ["Kiwi"])
    assert f("Speck", [], "vegetarisch") and f("Honig", [], "vegan") and f("Butter", [], "vegan")
    assert not f("Kokosmilch", [], "vegan") and f("Thunfisch", [], "vegetarisch") and not f("Tofu", [], "vegetarisch")
    assert f("Koriander frisch", [], dislikes=["Koriander"])
    assert substitutes.from_table("Eier", 2, "stk")[0]["ingredients"] == [
        {"name": "Leinsamen geschrotet", "amount": 20, "unit": "g"}, {"name": "Wasser", "amount": 60, "unit": "ml"}]
    assert substitutes.from_table("Sahne", 2, "el")[0]["ingredients"][0] == {"name": "Frischkäse", "amount": 22, "unit": "g"}
    assert substitutes.lookup("Kochsahne") == substitutes.TABLE["sahne"] and substitutes.lookup("Brei") is None
    assert len(substitutes.TABLE) >= 80


def test_stock_without_unit_counts_for_any_unit():
    from app.services.pricing import Stock
    stock = Stock([PantryItem(name="Brot", ingredient_key="brot", amount=None, unit="", is_basic=False),
                   PantryItem(name="Milch", ingredient_key="milch", amount=500, unit="", is_basic=False)])
    assert stock.take("Brot", "stk", 4) == float("inf")
    assert stock.take("Milch", "ml", 200) == 0  # Menge ohne Einheit ist nicht umrechenbar
