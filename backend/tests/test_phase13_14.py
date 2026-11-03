"""Phase 13 (Payback & Rewe Bonus 38, Rewe-Bonus-Aktionen 39, Monats-Dashboard 34, Drogerie-Coupons 59) und
Phase 14 (Erfolge 54, Wochenrückblick 55, Rezepte teilen 56). Keine echte KI, kein Netz, kein Push."""
import re
from datetime import date, datetime, timedelta
from types import SimpleNamespace

import pytest
from sqlalchemy import select

from app import jobs
from app.jobs import BERLIN
from app.models import Achievement, Coupon, Household, Member, Purchase, Recipe
from app.services import bonus, food_map, motivation, planner, prices, push
from app.services.planner import PlanDraft
from tests.test_phase11 import USAGE, ing, meal, text
from tests.test_phase12 import offer, stores

TODAY = date.today()
JPEG = b"\xff\xd8\xff\xe0" + b"0" * 100


def household_list_id(client, auth):
    return client.get("/lists", headers=auth).json()[0]["id"]


@pytest.fixture
def pushes(monkeypatch):
    calls = []
    monkeypatch.setattr(push, "send", lambda m, title, message, **kw: calls.append((m.id, message, kw)) or True)
    return calls


# --- 38a Coupon-Wallet ---

def test_coupon_scan_reads_fields_logs_cost_and_saves_nothing(client, auth, db, monkeypatch):
    seen = []

    def ask(content, schema, think=True):
        seen.append(content)
        return schema(partner="dm-drogerie markt", program="payback", product="Balea Shampoo", category="drogerie",
                      benefit="10fach Punkte", multiplier=10, bonus_cents=None, percent=None, min_spend_cents=200,
                      valid_until=f"{TODAY.year}-12-31"), USAGE
    monkeypatch.setattr(food_map, "ask_claude", ask)
    r = client.post("/coupons/scan", headers=auth, files={"file": ("c.jpg", JPEG, "image/jpeg")})
    assert r.status_code == 200, r.text
    body = r.json()
    assert (body["chain"], body["multiplier"], body["valid_until"], body["cost_cents"]) == (
        "dm", 10, f"{TODAY.year}-12-31", 0.01)
    assert seen[0][0]["type"] == "image" and "Coupon" in seen[0][1]["text"]
    assert db.scalars(select(Coupon)).all() == []
    assert client.get("/usage", headers=auth).json()["by_kind"]["coupon"] == 0.01
    assert client.post("/coupons/scan", headers=auth, files={"file": ("c.png", b"PNG", "image/png")}).status_code == 422


def test_coupon_crud_order_expired_and_store_bar(client, auth):
    def add(**kw):
        r = client.post("/coupons", headers=auth, json=kw)
        assert r.status_code == 201, r.text
        return r.json()
    late = add(partner="REWE", program="rewe_bonus", product="Kaffee", benefit="0,50 € Bonus", bonus_cents=50,
               valid_until=str(TODAY + timedelta(days=10)), code="2400000123456", code_type="ean13", source="barcode")
    soon = add(partner="dm", program="payback", product="Shampoo", multiplier=10, valid_until=str(TODAY + timedelta(1)))
    old = add(partner="Rossmann", program="rossmann", percent=20, valid_until=str(TODAY - timedelta(days=1)))
    aral = add(partner="Aral", program="payback", multiplier=5)
    assert (late["chain"], soon["chain"], old["chain"], aral["chain"]) == ("rewe", "dm", "rossmann", "")
    assert (late["badge"], soon["badge"], old["badge"]) == ("🎟 0,50 €", "🎟 10fach", "🎟 −20 %")
    wallet = client.get("/coupons", headers=auth).json()
    assert [c["id"] for c in wallet] == [soon["id"], late["id"], aral["id"], old["id"]]
    assert wallet[-1]["expired"] and wallet[0]["days_left"] == 1
    assert [c["id"] for c in client.get("/coupons?chain=rewe", headers=auth).json()] == [late["id"]]
    assert [c["id"] for c in client.get("/coupons?chain=rossmann", headers=auth).json()] == []
    p = client.patch(f"/coupons/{old['id']}", headers=auth, json={"valid_until": None, "product": "Zahnpasta"}).json()
    assert not p["expired"] and p["valid_until"] is None and p["product"] == "Zahnpasta" and p["percent"] == 20
    assert client.delete(f"/coupons/{aral['id']}", headers=auth).status_code == 204
    assert client.get("/coupons/999", headers=auth).status_code in (404, 405)
    assert client.patch("/coupons/999", headers=auth, json={}).status_code == 404


def test_coupon_expiry_push_once(client, auth, db, pushes):
    client.post("/coupons", headers=auth, json={"partner": "REWE", "program": "payback", "product": "Kaffee",
                                                "multiplier": 10, "valid_until": str(TODAY + timedelta(days=2))})
    client.post("/coupons", headers=auth, json={"partner": "dm", "product": "Seife", "percent": 10,
                                                "valid_until": str(TODAY + timedelta(days=5))})
    now = datetime.combine(TODAY, datetime.min.time(), BERLIN).replace(hour=12)
    assert jobs.run(db, "coupon_expiry", now).info == "1 Coupons, 1 Pushes"
    assert pushes[0][1] == "🎟 Dein Payback-Coupon für Kaffee läuft übermorgen ab"
    assert pushes[0][2]["click_url"].startswith("essenapp://coupon/")
    assert jobs.run(db, "coupon_expiry", now).info == "0 Coupons, 0 Pushes"  # genau einmal


# --- 38b Konten ---

def test_bonus_accounts_plus_minus_set(client, auth):
    accts = {a["program"]: a for a in client.get("/bonus", headers=auth).json()}
    assert accts["payback"]["balance"] == 0 and accts["rewe_bonus"]["unit"] == "cent"
    a = client.post("/bonus/payback", headers=auth, json={"set": 1240}).json()
    assert (a["balance"], a["value_cents"], a["earned_month_cents"]) == (1240, 1240, 0)  # Korrektur zählt nicht
    a = client.post("/bonus/payback", headers=auth, json={"delta": 60, "note": "Heute bekommen"}).json()
    assert (a["balance"], a["earned_month_cents"]) == (1300, 60)
    a = client.post("/bonus/payback", headers=auth, json={"delta": -300}).json()
    assert (a["balance"], a["earned_month_cents"]) == (1000, 60)
    assert client.post("/bonus/payback", headers=auth, json={"delta": -5000}).status_code == 422
    assert client.post("/bonus/payback", headers=auth, json={"delta": 5, "set": 3}).status_code == 422
    assert client.post("/bonus/xyz", headers=auth, json={"delta": 5}).status_code == 422
    r = client.post("/bonus/rewe_bonus", headers=auth, json={"delta": 850}).json()
    assert (r["balance"], r["value_cents"], r["earned_month_cents"]) == (850, 850, 850)


# --- 38c / 39 Effektivpreis ---

def test_effective_price_rules():
    o = SimpleNamespace(chain="rewe", title="Röstkaffee Classic", brand="Jacobs", category="vorrat")
    kaffee = Coupon(chain="rewe", product="Kaffee", multiplier=10)
    assert bonus.fits_offer(kaffee, o) and bonus.discount(kaffee, 1000) == 50  # 10 × 0,5 % (1 °P je 2 €)
    assert not bonus.fits_offer(Coupon(chain="edeka", product="Kaffee", multiplier=10), o)
    assert bonus.fits_offer(Coupon(chain="rewe", category="vorrat", percent=10), o)
    assert not bonus.fits_offer(Coupon(chain="rewe", product="Tee", percent=10), o)
    assert bonus.discount(Coupon(bonus_cents=50), 30) == 30 and bonus.discount(Coupon(percent=20), 199) == 40


def test_coupon_and_rewe_bonus_change_plan_price_and_prompt(client, auth, db, monkeypatch):
    stores(client, auth, "rewe", "lidl")
    kaffee = offer(db, "Röstkaffee", 500, "rewe", category="vorrat", amount=500, unit="g")
    reis = offer(db, "Express Reis", 129, "rewe", category="vorrat", amount=250, unit="g", bonus_cents=20)
    plain = offer(db, "Nudeln", 99, "lidl", category="vorrat", amount=500, unit="g")
    assert [o["title"] for o in client.get("/offers?bonus=true", headers=auth).json()] == ["Express Reis"]
    assert next(o for o in client.get("/offers", headers=auth).json() if o["id"] == reis.id)["bonus_cents"] == 20
    prompts = []

    def ask(prompt):
        prompts.append(text(prompt))
        return PlanDraft(meals=[meal(0, "Reis", [ing("Express Reis", 250, offer_id=reis.id),
                                                 ing("Röstkaffee", 500, offer_id=kaffee.id),
                                                 ing("Nudeln", 500, offer_id=plain.id)])]), USAGE
    monkeypatch.setattr(planner, "ask_claude", ask)
    client.patch("/household", headers=auth, json={"meal_types": ["mittag"], "plan_days": [0]})
    before = client.post("/plans", headers=auth).json()
    assert before["total_cents"] == 500 + 109 + 99 and before["saved_cents"] == 20  # Bonus zählt als Ersparnis
    assert f"{reis.id}|Express Reis|109|" in prompts[-1] and "Express Reis (🎁 0,20 € Bonus)" in prompts[-1]
    client.post("/coupons", headers=auth, json={"partner": "REWE", "program": "payback", "product": "Kaffee",
                                                "percent": 20})
    after = client.post("/plans", headers=auth).json()
    assert after["total_cents"] == before["total_cents"] - 100 and after["saved_cents"] == 120
    assert f"{kaffee.id}|Röstkaffee|400|" in prompts[-1]
    assert "Coupon/Bonus (Effektivpreis schon eingerechnet, Gerichte damit bevorzugen): " in prompts[-1]
    assert "Röstkaffee (🎟 −20 %)" in prompts[-1]
    assert db.get(type(kaffee), kaffee.id).price_cents == 500  # gespeichertes Angebot bleibt unverändert


def test_coupon_badge_on_list_item_and_drugstore_watch(client, auth, db):
    stores(client, auth, "dm", "rewe")
    shampoo = offer(db, "Balea Shampoo Repair", 95, "dm", category="drogerie")
    lst = household_list_id(client, auth)
    a = client.post(f"/lists/{lst}/items", headers=auth, json={"name": "Shampoo", "chain": "dm"}).json()
    assert a["coupon"] is None
    c = client.post("/coupons", headers=auth, json={"partner": "dm", "program": "dm", "product": "Shampoo",
                                                    "percent": 15}).json()
    client.post(f"/lists/{lst}/items", headers=auth, json={"name": "Milch", "chain": "rewe"})
    client.post(f"/lists/{lst}/items", headers=auth, json={"name": "Shampoo", "chain": "rewe"})
    items = client.get(f"/lists/{lst}", headers=auth).json()["items"]
    badges = [(i["name"], i["chain"], i["coupon"] and i["coupon"]["text"]) for i in items]
    assert badges == [("Shampoo", "dm", "🎟 −15 %"), ("Milch", "rewe", None), ("Shampoo", "rewe", None)]
    assert items[0]["coupon"] == {"id": c["id"], "text": "🎟 −15 %", "program": "dm", "partner": "dm"}
    w = client.post("/watch", headers=auth, json={"offer_id": shampoo.id}).json()
    assert w["coupon"]["id"] == c["id"]  # 59: dm-Coupon beim passenden Artikel der Drogerie-Merkliste
    patched = client.patch(f"/items/{items[0]['id']}", headers=auth, json={"checked": True}).json()
    assert patched["coupon"]["id"] == c["id"]


# --- 34 Monats-Dashboard ---

def test_spending_records_checked_items_sums_and_csv(client, auth, db):
    stores(client, auth, "rewe", "lidl")
    butter = offer(db, "Butter", 199, "rewe", regular=249, category="kuehlung", amount=250, unit="g")
    eier = offer(db, "Bio Eier", 329, "lidl", regular=349, category="kuehlung", start=TODAY - timedelta(days=20),
                 end=TODAY - timedelta(days=14))
    prices.record(db, [eier], eier.valid_from)  # Preisverlauf (28) = Quelle der Normalpreis-Schätzung
    lst = household_list_id(client, auth)
    a = client.post(f"/lists/{lst}/items", headers=auth, json={"name": "Butter", "amount": 500, "unit": "g",
                                                               "chain": "rewe", "offer_id": butter.id}).json()
    b = client.post(f"/lists/{lst}/items", headers=auth, json={"name": "Eier", "chain": "lidl"}).json()
    c = client.post(f"/lists/{lst}/items", headers=auth, json={"name": "Quatsch-Ware"}).json()
    for i in (a, b, c):
        client.patch(f"/items/{i['id']}", headers=auth, json={"checked": True})
    client.patch(f"/items/{a['id']}", headers=auth, json={"checked": True})  # zweimal abhaken = ein Kauf
    rows = db.scalars(select(Purchase)).all()
    assert sorted((p.name, p.price_cents, p.saved_cents, p.estimated) for p in rows) == [
        ("Butter", 398, 100, False), ("Eier", 349, 0, True), ("Quatsch-Ware", 0, 0, True)]
    s = client.get("/spending", headers=auth).json()
    assert s["month"] == TODAY.strftime("%Y-%m") and s["total_cents"] == 747 == sum(i["price_cents"] for i in s["items"])
    assert s["estimated_cents"] == 349 and s["saved_cents"] == 100 and s["top"][0]["name"] == "Butter"
    assert {x["chain"]: x["total_cents"] for x in s["stores"]} == {"rewe": 398, "lidl": 349, "": 0}
    assert {x["category"]: x["total_cents"] for x in s["categories"]}["kuehlung"] == 747
    assert sum(w["total_cents"] for w in s["weeks"]) == 747 and len(s["weeks"]) >= 4
    assert s["budget_cents"] == round(6000 * len_month(TODAY) / 7) and s["change_pct"] is None
    client.patch(f"/items/{b['id']}", headers=auth, json={"checked": False})  # Haken weg → Kauf weg
    assert client.get("/spending", headers=auth).json()["total_cents"] == 398
    client.delete(f"/items/{a['id']}", headers=auth)  # Listeneintrag weg → Ausgabe bleibt
    assert client.get("/spending", headers=auth).json()["total_cents"] == 398
    csv = client.get("/spending/export", headers=auth)
    assert csv.headers["content-type"].startswith("text/csv") and "ausgaben-" in csv.headers["content-disposition"]
    assert "Butter;500;g;rewe;kuehlung;3,98;1,00;nein" in csv.text
    # Monatswechsel + Vergleich zum Vormonat
    prev = (TODAY.replace(day=1) - timedelta(days=1))
    db.add(Purchase(household_id=1, name="Alt", price_cents=199, bought_at=datetime.combine(prev, datetime.min.time())))
    db.commit()
    assert client.get("/spending", headers=auth).json()["change_pct"] == 100.0
    old = client.get(f"/spending?month={prev:%Y-%m}", headers=auth).json()
    assert old["total_cents"] == 199 and old["items"][0]["name"] == "Alt"
    assert client.get("/spending?month=2026-13", headers=auth).status_code == 422


def len_month(d: date) -> int:
    nxt = (d.replace(day=28) + timedelta(days=4)).replace(day=1)
    return (nxt - d.replace(day=1)).days


# --- 54 Erfolge ---

def test_achievement_rules():
    assert motivation.is_plant("Paprika rot") and motivation.is_plant("Kichererbsen") and motivation.is_plant("Walnüsse")
    assert not motivation.is_plant("Olivenöl") and not motivation.is_plant("Hähnchenbrust")
    assert not motivation.is_plant("Gemüsebrühe") and not motivation.is_plant("Hafermilch")
    monday = TODAY - timedelta(days=TODAY.weekday())

    def buy(weeks_back, cents, category="vorrat"):
        return Purchase(price_cents=cents, category=category,
                        bought_at=datetime.combine(monday - timedelta(weeks=weeks_back), datetime.min.time()))
    rows = [buy(1, 5000), buy(1, 9000, "drogerie"), buy(2, 6000), buy(3, 7000), buy(4, 100)]
    assert motivation.budget_streak(rows, 6000, TODAY) == 2  # W-3 über Budget beendet die Serie; Drogerie zählt nicht
    assert motivation.budget_streak([buy(2, 100)], 6000, TODAY) == 0  # letzte Woche ohne Einkauf
    days = {(1, monday - timedelta(days=k)): [motivation.nutrition.Nutrients(kcal=2000 + 100 * k, protein=90),
                                              k != 3, {f"p{k}", "x"}] for k in range(1, 6)}
    m = motivation.member_metrics(days, 1, SimpleNamespace(protein_g=80, kcal=2000), TODAY)
    assert m == {"protein_days": 4, "kcal_days": 2, "plants_week": 6}  # 2100/2200 kcal ≤ +10 %


def test_achievements_unlock_exactly_once_and_seen(client, auth, db, pushes):
    stores(client, auth, "rewe")
    lst = household_list_id(client, auth)
    big = offer(db, "Kaffee", 500, "rewe", regular=1600, category="vorrat")
    item = client.post(f"/lists/{lst}/items", headers=auth, json={"name": "Kaffee", "chain": "rewe",
                                                                  "offer_id": big.id, "source": "stockup"}).json()
    client.patch(f"/items/{item['id']}", headers=auth, json={"checked": True})
    grid = {a["key"]: a for a in client.get("/achievements", headers=auth).json()}
    assert len(grid) == len(motivation.DEFS) and grid["gespart_10"]["unlocked_at"] and grid["gespart_10"]["new"]
    assert grid["gespart_50"]["unlocked_at"] is None and grid["gespart_50"]["progress"] == 1100
    assert grid["vorrat_5"]["progress"] == 1 and grid["protein_3"]["group"] == "gesundheit"
    client.get("/achievements", headers=auth)
    assert len(db.scalars(select(Achievement)).all()) == 1  # genau einmal
    assert client.post("/achievements/seen", headers=auth, json={"keys": ["gespart_10"]}).status_code == 204
    assert not {a["key"]: a for a in client.get("/achievements", headers=auth).json()}["gespart_10"]["new"]
    client.post("/bonus/payback", headers=auth, json={"delta": 4000})  # Bonus zählt mit: 11 € + 40 € = 51 €
    now = datetime.combine(TODAY, datetime.min.time(), BERLIN).replace(hour=12)  # außerhalb der Ruhezeit
    assert jobs.run(db, "achievements", now).info == "1 neue Erfolge"
    assert pushes and pushes[-1][1] == "💰 Neuer Erfolg: 50 € gespart"
    assert jobs.run(db, "achievements", now).info == "0 neue Erfolge"


def test_health_achievements_from_past_plan_days(client, auth, db, monkeypatch):
    from app.models import Food, IngredientMap, MealPlan, MealPlanEntry
    db.add_all([Food(id=1, description="lentils", data_type="x", kcal=1000, protein=50, fat=0, carbs=0, fiber=0),
                IngredientMap(ingredient_key="linsen", food_id=1, confidence="hoch")])
    h = db.get(Household, 1)
    monday = TODAY - timedelta(days=TODAY.weekday() + 7)
    plan = MealPlan(household_id=1, week=f"{monday.isocalendar().year}-W{monday.isocalendar().week:02d}")
    for d in range(7):
        r = Recipe(household_id=1, title=f"Linsen {d}", meal_type="mittag", servings=1, prep_minutes=10,
                   ingredients=[{"name": "Linsen", "amount": 200, "unit": "g"}])
        plan.entries.append(MealPlanEntry(day=d, meal_type="mittag", recipe=r, portions_total=1))
    db.add(plan)
    db.commit()
    grid = {a["key"]: a for a in client.get("/achievements", headers=auth).json()}
    assert grid["protein_7"]["unlocked_at"] and grid["ausgewogen_7"]["unlocked_at"]  # 2000 kcal, 100 g Protein
    assert grid["protein_30"]["progress"] == 7 and grid["pflanzen_15"]["progress"] == 1


# --- 55 Wochenrückblick ---

def test_week_review_pages_archive_and_job(client, auth, db, pushes):
    stores(client, auth, "rewe")
    lst = household_list_id(client, auth)
    r = client.post("/recipes", headers=auth, json={"title": "Linsensuppe", "servings": 2, "prep_minutes": 20,
                                                     "meal_type": "abend", "ingredients": [{"name": "Linsen",
                                                                                            "amount": 200,
                                                                                            "unit": "g"}]}).json()
    client.post(f"/recipes/{r['id']}/rate", headers=auth, json={"stars": 5, "again": "bald",
                                                                "cooked_at": (datetime.now() - timedelta(days=7)).isoformat()})
    item = client.post(f"/lists/{lst}/items", headers=auth, json={"name": "Linsen"}).json()
    client.patch(f"/items/{item['id']}", headers=auth, json={"checked": True})
    db.query(Purchase).update({"bought_at": datetime.now() - timedelta(days=7)})
    db.commit()
    nxt = TODAY + timedelta(days=7 - TODAY.weekday()) if TODAY.weekday() == 6 else TODAY - timedelta(days=TODAY.weekday())
    offer(db, "Hähnchen", 399, "rewe", regular=699, category="fleisch_fisch", start=nxt, end=nxt + timedelta(days=5))
    rv = client.get("/reviews/current", headers=auth).json()
    week = motivation.review_week(TODAY)
    assert rv["week"] == week and set(rv) >= {"cooking", "money", "health", "pantry", "achievements", "next_week"}
    if TODAY.weekday() != 6:  # Mo–Sa: Rückblick der vorigen Woche enthält Bewertung und Kauf von vor 7 Tagen
        assert rv["cooking"]["cooked"] == 1 and rv["cooking"]["favorite"]["title"] == "Linsensuppe"
        assert rv["money"]["spent_cents"] == 0 or rv["money"]["estimated_cents"] == rv["money"]["spent_cents"]
    assert rv["pantry"]["thrown_away"] is None and rv["next_week"][0]["saving_pct"] == 43
    assert [x["week"] for x in client.get("/reviews", headers=auth).json()] == [week]
    assert client.get(f"/reviews/{week}", headers=auth).json()["kw"] == rv["kw"]
    assert client.get("/reviews/2020-W01", headers=auth).status_code == 404
    sunday = datetime.combine(TODAY + timedelta(days=6 - TODAY.weekday()), datetime.min.time(), BERLIN).replace(hour=19)
    info = jobs.run(db, "week_review", sunday).info
    assert info == "1 Rückblicke, 1 Pushes" and "Wochenrückblick KW" in pushes[-1][1]
    assert pushes[-1][2]["click_url"].startswith("essenapp://review/")


# --- 56 Rezepte teilen ---

def test_share_recipe_link_web_view_and_import_copy(client, auth, db):
    client.patch("/household", headers=auth, json={"name": "Familie Müller"})
    r = client.post("/recipes", headers=auth, json={"title": "Omas Gulasch", "servings": 4, "prep_minutes": 90,
                                                     "meal_type": "abend", "steps": ["Anbraten", "Schmoren"],
                                                     "ingredients": [{"name": "Rindfleisch", "amount": 1, "unit": "kg"}]
                                                     }).json()
    share = client.post(f"/recipes/{r['id']}/share", headers=auth).json()
    assert share["url"].endswith(f"/r/{share['code']}") and share["app_url"] == f"essenapp://import-recipe/{share['code']}"
    assert client.post(f"/recipes/{r['id']}/share", headers=auth).json()["code"] == share["code"]
    pre = client.get(f"/shared-recipes/{share['code']}").json()  # ohne Login
    assert pre["title"] == "Omas Gulasch" and pre["from_household"] == "Familie Müller"
    page = client.get(f"/r/{share['code']}")
    assert page.status_code == 200 and "Omas Gulasch" in page.text and "Mit Essenapp geplant" in page.text
    assert f"essenapp://import-recipe/{share['code']}" in page.text and "Schmoren" in page.text
    assert client.get("/r/unbekannt").status_code == 404

    other = {"Authorization": "Bearer " + client.post("/households", json={"name": "Schmidts", "member_name": "A"}
                                                      ).json()["token"]}
    imp = client.post(f"/shared-recipes/{share['code']}/import", headers=other)
    assert imp.status_code == 201, imp.text
    copy = imp.json()
    assert copy["id"] != r["id"] and copy["source"] == "shared" and copy["source_author"] == "Familie Müller"
    assert copy["ingredients"] == [{"name": "Rindfleisch", "amount": 1000, "unit": "g"}]
    assert client.post(f"/shared-recipes/{share['code']}/import", headers=other).status_code == 200
    assert client.post(f"/shared-recipes/{share['code']}/import", headers=auth).json()["id"] == r["id"]  # eigenes
    assert [x["title"] for x in client.get("/recipes", headers=other).json()] == ["Omas Gulasch"]

    # Web-Mitglied eines dritten Haushalts übernimmt über die Web-Ansicht
    third = client.post("/households", json={"name": "Web", "member_name": "B"}).json()
    client.cookies.set("essen_token", third["token"])
    assert "In meine Rezepte übernehmen" in client.get(f"/r/{share['code']}").text
    done = client.post(f"/r/{share['code']}/import", follow_redirects=False)
    assert done.status_code == 303 and done.headers["location"] == f"/r/{share['code']}?imported=1"
    assert "Liegt jetzt in den Rezepten von Web" in client.get(done.headers["location"]).text
    client.cookies.clear()
    hid = third["household"]["id"]
    assert db.scalar(select(Recipe).where(Recipe.household_id == hid)).source_author == "Familie Müller"
