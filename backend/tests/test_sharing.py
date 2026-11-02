from datetime import date, datetime, timedelta

from app.models import Invite, MealPlan, MealPlanEntry, Offer, Recipe


def new_household(client, name="Andere"):
    token = client.post("/households", json={"name": name, "member_name": "X"}).json()["token"]
    return {"Authorization": f"Bearer {token}"}


def test_invite_join_members(client, auth, db):
    invite = client.post("/household/invites", headers=auth).json()
    assert len(invite["code"]) == 8 and invite["url"].endswith(f"/join/{invite['code']}")
    r = client.post(f"/join/{invite['code']}", json={"member_name": "Oma"})
    assert r.status_code == 201 and r.json()["household"]["name"] == "Test"
    oma = {"Authorization": f"Bearer {r.json()['token']}"}
    assert client.post(f"/join/{invite['code']}", json={"member_name": "Opa"}).status_code == 201  # mehrfach nutzbar
    members = client.get("/household/members", headers=oma).json()
    assert [(m["name"], m["role"]) for m in members] == [("J", "owner"), ("Oma", "member"), ("Opa", "member")]

    assert client.delete(f"/household/members/{members[2]['id']}", headers=oma).status_code == 403
    assert client.delete(f"/household/members/{members[0]['id']}", headers=auth).status_code == 422
    assert client.delete(f"/household/members/{members[0]['id']}", headers=new_household(client)).status_code == 404
    assert client.delete(f"/household/members/{members[2]['id']}", headers=auth).status_code == 204
    assert len(client.get("/household/members", headers=auth).json()) == 2

    db.get(Invite, 1).expires_at = datetime.now() - timedelta(seconds=1)
    db.commit()
    assert client.post(f"/join/{invite['code']}", json={"member_name": "Zu spät"}).status_code == 404
    assert client.post("/join/falsch", json={"member_name": "X"}).status_code == 404

    share = client.get("/household/share", headers=auth).json()["url"]
    assert "/h/" in share and share == client.get("/household/share", headers=auth).json()["url"]


def test_lists_are_household_scoped(client, auth):
    lists = client.get("/lists", headers=auth).json()
    assert [(l["kind"], l["total_count"]) for l in lists] == [("household", 0)]
    hid = lists[0]["id"]
    item = client.post(f"/lists/{hid}/items", headers=auth, json={"name": "Milch", "amount": 1, "unit": "l"}).json()
    assert item["added_by"] == "J" and item["source"] == "manual"
    checked = client.patch(f"/items/{item['id']}", headers=auth, json={"checked": True}).json()
    assert checked["checked"] and checked["checked_by"] == "J"
    assert client.get("/lists", headers=auth).json()[0]["open_count"] == 0
    assert client.delete(f"/lists/{hid}", headers=auth).status_code == 422

    other = new_household(client)
    assert client.get(f"/lists/{hid}", headers=other).status_code == 404
    assert client.post(f"/lists/{hid}/items", headers=other, json={"name": "Hack"}).status_code == 404
    assert client.patch(f"/items/{item['id']}", headers=other, json={"checked": False}).status_code == 404
    assert client.delete(f"/items/{item['id']}", headers=other).status_code == 404
    assert client.post(f"/lists/{hid}/items", headers=auth, json={"name": "x" * 101}).status_code == 422
    assert client.delete(f"/items/{item['id']}", headers=auth).status_code == 204


def test_guest_only_sees_shared_oneoff_list(client, auth):
    party = client.post("/lists", headers=auth, json={"name": "Grillparty"}).json()
    code = party["share_url"].rsplit("/", 1)[1]
    assert party["kind"] == "oneoff"
    item = client.post(f"/shared/{code}/items?guest=Ben", json={"name": "Kohle"}).json()
    assert item["added_by"] == "Ben"
    assert client.patch(f"/shared/{code}/items/{item['id']}?guest=Ben", json={"checked": True}).json()["checked_by"] == "Ben"
    assert [i["name"] for i in client.get(f"/shared/{code}").json()["items"]] == ["Kohle"]

    hid = client.get("/lists", headers=auth).json()[0]["id"]
    private = client.post(f"/lists/{hid}/items", headers=auth, json={"name": "Geheim"}).json()
    assert client.patch(f"/shared/{code}/items/{private['id']}", json={"checked": True}).status_code == 404
    assert client.get("/shared/falsch").status_code == 404
    assert client.delete(f"/lists/{party['id']}", headers=auth).status_code == 204
    assert client.get(f"/shared/{code}").status_code == 404


def add_plan(db, household_id, ingredients_per_meal):
    plan = MealPlan(household_id=household_id, week="2026-W45")
    for day, ingredients in enumerate(ingredients_per_meal):
        plan.entries.append(MealPlanEntry(day=day, meal_type="abend", recipe=Recipe(
            title=f"Gericht {day}", meal_type="abend", servings=2, prep_minutes=20, ingredients=ingredients,
            steps=["kochen"])))
    db.add(plan)
    db.commit()


def ing(name, amount, unit="g", offer_id=None, pantry=False):
    return {"name": name, "amount": amount, "unit": unit, "offer_id": offer_id, "in_pantry": pantry}


def test_sync_plan_sums_and_does_not_duplicate(client, auth, db):
    db.add(Offer(id=7, chain="lidl", source_id="h", title="Hack", price_cents=399, valid_from=date.today(),
                 valid_to=date.today()))
    add_plan(db, 1, [[ing("Hack", 250, offer_id=7), ing("Zwiebel", 1, "stk"), ing("Salz", 5, pantry=True)],
                     [ing("Hackfleisch", 250, offer_id=7), ing("zwiebel", 2, "stk")]])
    hid = client.get("/lists", headers=auth).json()[0]["id"]
    client.post(f"/lists/{hid}/items", headers=auth, json={"name": "Klopapier"})

    items = client.post("/lists/household/sync-plan", headers=auth).json()["items"]
    plan_items = {i["name"]: i for i in items if i["source"] == "plan"}
    assert {n: (i["amount"], i["chain"]) for n, i in plan_items.items()} == {"Hack": (500, "lidl"), "Zwiebel": (3, "")}
    client.patch(f"/items/{plan_items['Hack']['id']}", headers=auth, json={"checked": True})

    items = client.post("/lists/household/sync-plan", headers=auth).json()["items"]
    assert sorted(i["name"] for i in items) == ["Hack", "Klopapier", "Zwiebel"]
    assert next(i for i in items if i["name"] == "Hack")["checked"]

    add_plan(db, 1, [[ing("Nudeln", 500)]])  # neuer Plan: alte Plan-Einträge raus, manuelle bleiben
    items = client.post("/lists/household/sync-plan", headers=auth).json()["items"]
    assert sorted(i["name"] for i in items) == ["Klopapier", "Nudeln"]


def test_web_join_app_and_guest_pages(client, auth, db):
    add_plan(db, 1, [[ing("Nudeln", 500)]])
    client.post("/lists/household/sync-plan", headers=auth)
    code = client.post("/household/invites", headers=auth).json()["code"]

    assert client.get("/app").status_code == 401
    page = client.get(f"/join/{code}")
    assert page.status_code == 200 and "Beitreten" in page.text and "Test" in page.text
    assert "Gericht 0" in client.get(client.get("/household/share", headers=auth).json()["url"]).text
    assert client.get("/join/falsch").status_code == 404

    r = client.post(f"/app/join/{code}", data={"member_name": "Oma"}, follow_redirects=False)
    assert r.status_code == 303 and "httponly" in r.headers["set-cookie"].lower()
    assert "samesite=lax" in r.headers["set-cookie"].lower()
    client.cookies.set("essen_token", r.cookies["essen_token"])
    plan = client.get("/app")
    assert plan.status_code == 200 and "Gericht 0" in plan.text and "Zubereitung" in plan.text
    assert 'hx-trigger="every 10s"' in client.get("/app/list").text
    listed = client.post("/app/items", data={"name": "Brot"}).text
    assert "Brot" in listed and "von Oma" in listed
    item_id = next(i["id"] for i in client.get("/lists/1", headers=auth).json()["items"] if i["name"] == "Nudeln")
    assert "✓ Oma" in client.post(f"/app/items/{item_id}/toggle").text
    assert client.get(f"/join/{code}", follow_redirects=False).status_code == 303  # schon Mitglied

    client.cookies.clear()
    share = client.post("/lists", headers=auth, json={"name": "Party"}).json()["share_url"].rsplit("/", 1)[1]
    assert "Wie heißt du?" in client.get(f"/l/{share}").text
    assert "von Ben" in client.post(f"/l/{share}/items", data={"name": "Chips", "guest": "Ben"}).text
    assert client.post(f"/l/{share}/items/{item_id}/toggle", data={"guest": "Ben"}).status_code == 404
    assert client.get("/static/manifest.webmanifest").status_code == 200


def test_new_plan_fills_household_list(client, auth, monkeypatch):
    from app.services import planner
    from tests.test_planner import ing as planned, meal
    client.patch("/household", headers=auth, json={"meal_types": ["mittag"], "plan_days": [0]})
    monkeypatch.setattr(planner, "ask_claude", lambda prompt: (
        planner.PlanDraft(meals=[meal(0, "Dal", [planned("Linsen", 250), planned("Salz", 5, pantry=True)])]), {}))
    assert client.post("/plans", headers=auth).status_code == 201
    assert [i["name"] for i in client.get("/lists/1", headers=auth).json()["items"]] == ["Linsen"]
