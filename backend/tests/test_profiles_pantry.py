"""Ziele pro Person (48) und Vorratskammer (60)."""
from datetime import date

from app.models import MemberProfile, PantryItem, Recipe
from app.services import planner
from app.services.planner import PlanDraft
from tests.test_planner import ing as planned, meal, text
from tests.test_sharing import add_plan, ing, new_household


def test_portion_factor_and_eaters_per_slot():
    assert [planner.portion_factor(k) for k in (2000, 2600, 1500, 1000, 5000)] == [1, 1.25, 0.75, 0.5, 2.5]
    jona = MemberProfile(member_id=1, kcal=2500, eats={})
    oma = MemberProfile(member_id=2, kcal=1500, eats={"mittag": [False] * 7})
    eaters = planner.slot_eaters([jona, oma], 4, [(0, "mittag"), (0, "abend")])
    assert eaters[(0, "mittag")] == ([{"member_id": 1, "factor": 1.25}], 1.25)
    assert eaters[(0, "abend")] == ([{"member_id": 1, "factor": 1.25}, {"member_id": 2, "factor": 0.75}], 2)
    # ein Mitglied bzw. keine Profile: Personenzahl des Haushalts
    assert planner.slot_eaters([oma], 3, [(0, "mittag")])[(0, "mittag")] == ([{"member_id": 2, "factor": 0.75}], 3)
    assert planner.slot_eaters([], 3, [(0, "mittag")])[(0, "mittag")] == ([], 3)


def join(client, auth, name="Oma"):
    code = client.post("/household/invites", headers=auth).json()["code"]
    return {"Authorization": f"Bearer {client.post(f'/join/{code}', json={'member_name': name}).json()['token']}"}


def test_profile_created_from_household_and_validated(client, auth):
    client.patch("/household", headers=auth, json={"allergies": ["Nüsse"], "excluded_ingredients": ["Pilze"],
                                                    "nutrition_goal": "proteinreich"})
    p = client.get("/me/profile", headers=auth).json()
    assert (p["name"], p["goal"], p["kcal"], p["protein_g"], p["allergies"], p["dislikes"]) == \
        ("J", "proteinreich", 2200, 140, ["Nüsse"], ["Pilze"])
    assert p["eats"]["mittag"] == [True] * 7 and p["lunchbox_days"] == []

    r = client.patch("/me/profile", headers=auth, json={"name": "Jona", "kcal": 2500, "lunchbox_days": [4, 0, 0],
                                                         "eats": {"mittag": [False] * 5 + [True] * 2}})
    assert r.status_code == 200, r.text
    p = r.json()
    assert (p["name"], p["kcal"], p["lunchbox_days"]) == ("Jona", 2500, [0, 4])
    assert p["eats"]["mittag"][0] is False and p["eats"]["abend"] == [True] * 7  # nur genannte Mahlzeit ersetzt
    for bad in ({"kcal": 999}, {"kcal": 5001}, {"protein_g": 401}, {"allergies": ["x"] * 21},
                {"lunchbox_days": [7]}, {"eats": {"mittag": [True] * 6}}, {"eats": {"brunch": [True] * 7}},
                {"goal": "masse"}):
        assert client.patch("/me/profile", headers=auth, json=bad).status_code == 422, bad

    join(client, auth)
    profiles = client.get("/household/profiles", headers=auth).json()
    assert [(x["name"], x["kcal"]) for x in profiles] == [("Jona", 2500), ("Oma", 2200)]
    assert "dislikes" not in profiles[0] and set(profiles[1]) >= {"member_id", "emoji", "goal", "eats", "allergies"}


def test_plan_two_members_portions_and_allergies(client, auth, db, monkeypatch):
    """Abnahme 48: Allergien beider, Portionen je Person, Oma mittags nie zu Hause."""
    client.patch("/household", headers=auth, json={"meal_types": ["mittag", "abend"], "plan_days": [0],
                                                    "variety": {"min_fish": 0},
                                                    "allergies": ["Sellerie"]})
    oma = join(client, auth)
    client.patch("/me/profile", headers=auth, json={"kcal": 2500, "allergies": ["Nüsse"]})
    client.patch("/me/profile", headers=oma, json={"kcal": 1500, "allergies": ["Laktose", "Nüsse"],
                                                   "eats": {"mittag": [False] * 7}})
    db.add(PantryItem(household_id=1, name="Reis", ingredient_key="reis", amount=500, unit="g",
                      best_before=date(2026, 11, 5)))
    db.commit()
    seen = {}

    def fake_ask(prompt):
        seen["prompt"] = text(prompt)
        return PlanDraft(meals=[meal(0, "Curry", [planned("Reis", 150)]),
                                meal(0, "Suppe", [planned("Linsen", 250)], "abend")]), {}

    monkeypatch.setattr(planner, "ask_claude", fake_ask)
    r = client.post("/plans", headers=auth)
    assert r.status_code == 201, r.text
    assert "meal_type=mittag, portionen=1.25" in seen["prompt"] and "meal_type=abend, portionen=2" in seen["prompt"]
    assert "Allergien: Sellerie, Nüsse, Laktose" in seen["prompt"]
    assert "Vorrat (zuerst verbrauchen): Reis 500g bis 05.11." in seen["prompt"]
    lunch, dinner = r.json()["entries"]
    assert (lunch["portions"], lunch["portions_total"]) == ([{"member_id": 1, "factor": 1.25}], 1.25)
    assert [p["factor"] for p in dinner["portions"]] == [1.25, 0.75] and dinner["portions_total"] == 2
    assert lunch["cost_cents"] == 0  # Reis aus dem Vorrat

    client.patch("/me/profile", headers=auth, json={"eats": {"mittag": [False] * 7}})
    monkeypatch.setattr(planner, "ask_claude", lambda prompt: (PlanDraft(meals=[
        meal(0, "Suppe", [planned("Linsen", 250)], "abend")]), {}))
    assert [e["meal_type"] for e in client.post("/plans", headers=auth).json()["entries"]] == ["abend"]  # Mittag entfällt


def pantry(name, amount=None, unit="", basic=False):
    return PantryItem(name=name, ingredient_key=name.lower(), amount=amount, unit=unit, is_basic=basic)


def test_price_uses_pantry_and_basics():
    draft = PlanDraft(meals=[
        meal(0, "Risotto", [planned("Reis", 300, pack=1000, price=200), planned("Olivenöl", 20, "ml", pack=500, price=400)]),
        meal(1, "Reispfanne", [planned("Reis", 300, pack=1000, price=200), planned("Oregano", 2, pantry=True)]),
    ])
    p = planner.price(draft, {}, [pantry("Reis", 500, "g"), pantry("Öl", basic=True)])
    # 600 g Reis, 500 g da → 100 g kaufen (1 Packung), Verbrauch 20 ct anteilig; Olivenöl = Basic; Oregano: KI-Fallback
    assert (p.total_cents, p.meal_costs) == (200, [10, 10])
    assert planner.price(draft, {}, [pantry("Reis", 1000, "g"), pantry("Öl", basic=True)]).total_cents == 0
    # Basic leer gemeldet schlägt die KI-Schätzung; Vorrat in anderer Einheit zählt nicht
    draft.meals[0].ingredients[1].in_pantry = True
    assert planner.price(draft, {}, [pantry("Reis", 5, "stk"), pantry("Öl", 0, basic=True)]).total_cents == 200 + 400


def test_sync_plan_only_missing_amounts(client, auth, db):
    """Abnahme 60: 500 g Reis im Vorrat → kein Reis auf der Liste; nur Fehlmengen."""
    client.post("/pantry", headers=auth, json={"name": "Reis", "amount": 500, "unit": "g"})
    add_plan(db, 1, [[ing("Reis", 400), ing("Salz", 5), ing("Zwiebel", 1, "stk")]])
    items = client.post("/lists/household/sync-plan", headers=auth).json()["items"]
    assert [(i["name"], i["amount"]) for i in items] == [("Zwiebel", 1)]  # Salz = Basic

    add_plan(db, 1, [[ing("Reis", 400)], [ing("Reis", 300), ing("Oregano", 1, pantry=True)]])
    items = client.post("/lists/household/sync-plan", headers=auth).json()["items"]
    assert [(i["name"], i["amount"]) for i in items] == [("Reis", 200)]


def test_pantry_crud_consume_and_rights(client, auth, db):
    basics = client.get("/pantry", headers=auth).json()
    assert [b["name"] for b in basics if b["is_basic"]] == ["Essig", "Gemüsebrühe", "Mehl", "Pfeffer", "Salz",
                                                            "Zucker", "Öl"]
    rice = client.post("/pantry", headers=auth, json={"name": " Basmati  Reis", "amount": 500, "unit": "g",
                                                      "best_before": "2026-11-05"}).json()
    assert rice["ingredient_key"] == "basmati reis" and rice["source"] == "manual"
    assert client.get("/pantry", headers=auth).json()[0]["id"] == rice["id"]  # ablaufende zuerst, Basics zuletzt
    assert client.patch(f"/pantry/{rice['id']}", headers=auth, json={"name": "Reis", "best_before": None}).json()[
        "ingredient_key"] == "reis"
    assert client.post("/pantry", headers=auth, json={"name": "Reis", "unit": "kg"}).status_code == 422

    add_plan(db, 1, [[ing("Reis", 160), ing("Salz", 5)]])
    entry_id, recipe_id = 1, 1
    db.get(Recipe, recipe_id).household_id = 1
    db.commit()
    changed = client.post("/pantry/consume", headers=auth, json={"entry_id": entry_id}).json()
    assert [(c["name"], c["amount"]) for c in changed] == [("Reis", 340)]  # „Gekocht“ zieht 160 g ab, Basics bleiben
    changed = client.post("/pantry/consume", headers=auth, json={"recipe_id": recipe_id, "servings_factor": 2}).json()
    assert changed[0]["amount"] == 20
    assert client.post("/pantry/consume", headers=auth, json={"entry_id": entry_id}).json()[0]["amount"] == 0
    assert "Reis" not in [p["name"] for p in client.get("/pantry", headers=auth).json()]  # ≤ 0 → gelöscht
    assert client.post("/pantry/consume", headers=auth, json={}).status_code == 422

    other = new_household(client)
    salt = next(b for b in basics if b["name"] == "Salz")
    client.get("/lists", headers=auth)
    item = client.post("/lists/1/items", headers=auth, json={"name": "Milch"}).json()
    assert client.patch(f"/pantry/{salt['id']}", headers=other, json={"amount": 1}).status_code == 404
    assert client.delete(f"/pantry/{salt['id']}", headers=other).status_code == 404
    assert client.post(f"/pantry/basics/{salt['id']}/empty", headers=other).status_code == 404
    assert client.post("/pantry/consume", headers=other, json={"entry_id": entry_id}).status_code == 404
    assert client.post("/pantry/consume", headers=other, json={"recipe_id": recipe_id}).status_code == 404
    assert client.post(f"/items/{item['id']}/to-pantry", headers=other).status_code == 404
    assert len(client.get("/pantry", headers=other).json()) == 7  # eigene Basics, nichts Fremdes
    assert client.delete(f"/pantry/{salt['id']}", headers=auth).status_code == 204


def test_basic_empty_goes_to_list_and_back_to_pantry(client, auth, db):
    """Abnahme 60: Basic „Öl“ leer melden → steht auf der Liste; abhaken → wieder im Vorrat."""
    oil = next(p for p in client.get("/pantry", headers=auth).json() if p["name"] == "Öl")
    entry = client.post(f"/pantry/basics/{oil['id']}/empty", headers=auth).json()
    assert (entry["name"], entry["source"]) == ("Öl", "basics")
    assert client.post(f"/pantry/basics/{oil['id']}/empty", headers=auth).json()["id"] == entry["id"]  # keine Dublette
    rice = client.post("/pantry", headers=auth, json={"name": "Reis"}).json()
    assert client.post(f"/pantry/basics/{rice['id']}/empty", headers=auth).status_code == 422

    add_plan(db, 1, [[ing("Olivenöl", 30, "ml", pantry=True)]])  # KI meint „Vorrat“, Basic ist aber leer
    names = [i["name"] for i in client.post("/lists/household/sync-plan", headers=auth).json()["items"]]
    assert names == ["Öl", "Olivenöl"]

    r = client.patch(f"/items/{entry['id']}", headers=auth, json={"checked": True}).json()
    assert r["checked"] and r["pantry_suggest"] is True
    back = client.post(f"/items/{entry['id']}/to-pantry", headers=auth).json()
    assert (back["id"], back["amount"]) == (oil["id"], None)  # Basic wieder vorhanden


def test_pantry_suggest_and_item_to_pantry(client, auth):
    def add(name, amount=None, unit=""):
        return client.post("/lists/1/items", headers=auth, json={"name": name, "amount": amount, "unit": unit}).json()

    client.get("/lists", headers=auth)
    milk, rice, berries = add("Milch", 1, "l"), add("Basmatireis", 1, "kg"), add("Preiselbeeren")
    suggest = {i["name"]: client.patch(f"/items/{i['id']}", headers=auth, json={"checked": True}).json()["pantry_suggest"]
               for i in (milk, rice, berries)}
    assert suggest == {"Milch": False, "Basmatireis": True, "Preiselbeeren": False}
    assert client.patch(f"/items/{rice['id']}", headers=auth, json={"checked": False}).json()["pantry_suggest"] is False

    first = client.post(f"/items/{milk['id']}/to-pantry", headers=auth).json()
    assert (first["name"], first["amount"], first["unit"], first["source"]) == ("Milch", 1000, "ml", "list")
    again = client.post(f"/items/{milk['id']}/to-pantry", headers=auth).json()
    assert (again["id"], again["amount"]) == (first["id"], 2000)
