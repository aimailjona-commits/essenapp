"""Phase 12 (Sparen): Urteil in GET /offers (28), Vorschau (30), Vorratskauf (31), Merkliste + Preisalarm (27/40),
Ein-Laden-Modus (41), Laden-Empfehlung (42), Budget-Rest (43), Bio/Vegan/Nutri-Score (49), Verbrauchsrhythmus (58),
Monatsaktionen (59)."""
from datetime import date, datetime, timedelta

import pytest
from sqlalchemy import event, select

from app import jobs
from app.api import next_monday
from app.jobs import BERLIN
from app.models import Household, MealPlan, Offer, Product, ShoppingItem, WatchItem
from app.services import labels, pantry_ai, planner, prices, stockup, store_split, watch
from app.services.planner import PlanDraft
from tests.test_phase11 import USAGE, ing, meal

TODAY = date.today()


def offer(db, title, price, chain="lidl", regular=None, category="vorrat", amount=None, unit="", base=None,
          start=None, end=None, store_ref="", brand="", raw=None, **kw):
    o = Offer(chain=chain, store_ref=store_ref, source_id=f"{title}-{chain}-{price}-{start}", title=title, brand=brand,
              price_cents=price, regular_price_cents=regular, category=category, amount=amount, unit=unit,
              base_price_cents=base, valid_from=start or TODAY, valid_to=end or TODAY + timedelta(days=3),
              raw=raw or {}, **kw)
    db.add(o)
    db.commit()
    return o


def history(db, title, weekly, chain="lidl", **kw):
    """Preispunkte der letzten Wochen (älteste zuerst) für ein Produkt."""
    for back, price in enumerate(reversed(weekly), start=1):
        monday = TODAY - timedelta(days=TODAY.weekday(), weeks=back)
        o = offer(db, title, price, chain, start=monday, end=monday + timedelta(days=5), **kw)
        prices.record(db, [o], monday)
    db.commit()


def stores(client, auth, *chains, **extra):
    client.patch("/household", headers=auth, json={"stores": [{"chain": c} for c in chains], **extra})


# --- 28: Urteil in GET /offers, effizient ---

def test_offers_have_verdict_without_n_plus_one(client, auth, db):
    stores(client, auth, "lidl")
    for i in range(5):
        history(db, f"Nudeln {i}", [199, 199, 199], amount=500, unit="g")
        offer(db, f"Nudeln {i}", 99 if i % 2 == 0 else 249, regular=199 if i % 2 == 0 else 299, amount=500, unit="g")
    offer(db, "Neu ohne Historie", 100)
    selects = []
    event.listen(db.get_bind(), "before_cursor_execute",
                 lambda conn, cur, stmt, *a: selects.append(stmt) if "FROM price_point" in stmt else None)
    rows = client.get("/offers", headers=auth).json()
    assert len([s for s in selects if s.lstrip().startswith("SELECT")]) <= 2  # eine Abfrage + record() für Neues
    verdicts = {r["title"]: r["verdict"] for r in rows}
    assert verdicts["Nudeln 0"] == "bestpreis" and verdicts["Nudeln 1"] == "kein_echtes"
    assert verdicts["Neu ohne Historie"] == "zu_wenig_daten"
    real = [r["title"] for r in client.get("/offers?real=true", headers=auth).json()]
    assert "Nudeln 1" not in real and "Nudeln 0" in real


# --- 30: Vorschau nächste Woche ---

def test_preview_next_week_and_cheaper_card(client, auth, db):
    stores(client, auth, "lidl", "rewe")
    monday = next_monday()
    offer(db, "Hähnchenbrust", 499, "rewe", category="fleisch_fisch", amount=400, unit="g", base=1248)
    offer(db, "Hähnchenbrust", 349, "lidl", regular=499, category="fleisch_fisch", amount=400, unit="g", base=873,
          start=monday, end=monday + timedelta(days=5))
    offer(db, "Butter", 199, "rewe", category="kuehlung", amount=250, unit="g")
    offer(db, "Butter", 189, "lidl", category="kuehlung", amount=250, unit="g", start=monday, end=monday + timedelta(5))
    this = [o["title"] for o in client.get("/offers", headers=auth).json()]
    nxt = [o["title"] for o in client.get("/offers?week=next", headers=auth).json()]
    assert this == ["Hähnchenbrust", "Butter"] or set(this) == {"Hähnchenbrust", "Butter"}
    assert sorted(nxt) == ["Butter", "Hähnchenbrust"] and len(nxt) == 2
    lst = client.get("/lists", headers=auth).json()[0]["id"]
    item = client.post(f"/lists/{lst}/items", headers=auth, json={"name": "Hähnchenbrust", "amount": 400,
                                                                   "unit": "g"}).json()
    client.post(f"/lists/{lst}/items", headers=auth, json={"name": "Butter"})
    deals = client.get("/offers/next-week-cheaper", headers=auth).json()
    assert [(d["name"], d["saving_pct"], d["now_price_cents"], d["offer"]["price_cents"], d["now_chain"])
            for d in deals] == [("Hähnchenbrust", 30, 499, 349, "rewe")]  # Butter nur −5 % → kein Hinweis
    moved = client.post(f"/items/{item['id']}/next-week", headers=auth,
                        json={"offer_id": deals[0]["offer"]["id"]}).json()
    assert moved["next_week"] and moved["chain"] == "lidl" and moved["defer_week"] == prices.iso_week(monday)
    assert client.get("/offers/next-week-cheaper", headers=auth).json() == []  # schon verschoben
    back = client.patch(f"/items/{item['id']}", headers=auth, json={"next_week": False}).json()
    assert back["next_week"] is False


def test_plan_for_next_week_uses_preview_offers(client, auth, db, monkeypatch):
    stores(client, auth, "lidl", meal_types=["abend"], plan_days=[0])
    monday = next_monday()
    now = offer(db, "Lachs jetzt", 299, category="fleisch_fisch")
    later = offer(db, "Lachs Vorschau", 279, category="fleisch_fisch", start=monday, end=monday + timedelta(days=5))
    seen = []

    def ask(prompt):
        seen.append(prompt[0]["text"])
        return PlanDraft(meals=[meal(0, "Lachs", [ing("Lachs", 200, offer_id=later.id)], meal_type="abend",
                                     protein="fisch")]), USAGE
    monkeypatch.setattr(planner, "ask_claude", ask)
    plan = client.post("/plans", headers=auth, json={"next_week": True}).json()
    assert plan["week"] == prices.iso_week(monday) and "Lachs Vorschau" in seen[0] and "Lachs jetzt" not in seen[0]
    assert now.id  # bleibt in „Diese Woche“


# --- 31: Vorratskauf ---

def V(verdict="bestpreis", interval=6, median=198):
    return {"verdict": verdict, "avg_interval_weeks": interval, "median_cents": median}


def test_stockup_pasta_six_packs_and_caps():
    pasta = Offer(id=1, title="Spaghetti", category="vorrat", price_cents=99, regular_price_cents=198, amount=500,
                  unit="g", chain="lidl")
    t = stockup.tip(pasta, V(), use=1.0, storage="mittel")
    assert (t["packs"], t["weeks"], t["saving_cents"]) == (6, 6.0, 99 * 6)  # Abnahme: 1/Woche, alle 6 Wochen → 6
    assert stockup.tip(pasta, V(interval=12), 1.0, "mittel")["packs"] == 6  # Vorratsplatz mittel
    assert stockup.tip(pasta, V(interval=12), 1.0, "gross")["packs"] == 12
    assert stockup.tip(pasta, V(interval=40), 0.25, "gross")["packs"] == 6  # 6 Monate: 26 × 0,25
    assert stockup.tip(pasta, V(), None)["packs"] == 2 and stockup.tip(pasta, V(), None)["weeks"] is None
    assert stockup.tip(pasta, V(verdict="normal"), 1.0) is None
    weak = Offer(title="Spaghetti", category="vorrat", price_cents=160, regular_price_cents=198, amount=500, unit="g")
    assert stockup.tip(weak, V(), 1.0) is None  # nur 19 % Rabatt
    fresh = Offer(title="Hähnchenbrust", category="fleisch_fisch", price_cents=99, regular_price_cents=300)
    assert stockup.tip(fresh, V(), 1.0) is None  # nichts Frisches
    tk = Offer(title="TK-Erbsen", category="kuehlung", price_cents=99, regular_price_cents=300, amount=1000, unit="g")
    assert stockup.durable(tk) and stockup.tip(tk, V(), 1.0)["packs"] == 6


def test_stockup_endpoint_usage_and_list(client, auth, db, monkeypatch):
    stores(client, auth, "lidl")
    history(db, "Spaghetti", [199, 189, 199], amount=500, unit="g")
    o = offer(db, "Spaghetti", 99, regular=199, amount=500, unit="g")
    offer(db, "Erdbeeren", 99, regular=299, category="obst_gemuese")
    client.post("/weekly-basics", headers=auth, json={"name": "Spaghetti", "amount": 500, "unit": "g"})
    tips = client.get("/stockup", headers=auth).json()
    assert [(t["offer"]["title"], t["packs"], t["weekly_use"]) for t in tips] == [("Spaghetti", 4, 1.0)]
    assert tips[0]["saving_cents"] == 400 and tips[0]["offer"]["verdict"] == "bestpreis"
    assert client.get(f"/offers/{o.id}/stockup", headers=auth).json()["packs"] == 4
    lst = client.get("/lists", headers=auth).json()[0]["id"]
    item = client.post(f"/lists/{lst}/items", headers=auth, json={"name": "Spaghetti", "amount": 4, "offer_id": o.id,
                                                                   "chain": "lidl", "source": "stockup"}).json()
    assert item["source"] == "stockup"


# --- 27 + 40: Merkliste, Preisalarm ---

@pytest.fixture
def pushes(monkeypatch):
    calls = []
    monkeypatch.setattr(jobs.push, "send", lambda m, title, message, **kw: calls.append((m.id, message, kw)) or True)
    return calls


def at(d: date, hhmm="12:00") -> datetime:
    h, m = map(int, hhmm.split(":"))
    return datetime(d.year, d.month, d.day, h, m, tzinfo=BERLIN)


def test_scanned_product_and_exactly_one_push_per_week(client, auth, db, pushes, monkeypatch):
    stores(client, auth, "dm")
    db.get(Household, 1).members[0].quiet_hours = None
    monkeypatch.setattr(labels, "_get", lambda url, **p: {"status": 1, "product": {
        "code": "4005900000001", "product_name_de": "Anti-Schuppen Shampoo", "brands": "Head & Shoulders",
        "nutriscore_grade": "not-applicable", "image_front_url": "https://img/x.jpg"}})
    scan = client.get("/products/ean/4005900000001", headers=auth).json()
    assert scan == {"ean": "4005900000001", "found": True, "name": "Anti-Schuppen Shampoo", "brand": "Head & Shoulders",
                    "image_url": "https://img/x.jpg", "nutri_score": None}
    w = client.post("/watch", headers=auth, json={"label": scan["name"], "brand": scan["brand"], "ean": scan["ean"],
                                                  "category": "drogerie", "max_price_cents": 300}).json()
    assert w["lasts_weeks"] == 6 and w["hits"] == []  # Vorschlag aus „Shampoo“
    db.add(Offer(chain="dm", store_ref="", source_id="s", title="Head & Shoulders Anti-Schuppen Shampoo 300 ml",
                 category="drogerie", price_cents=179, regular_price_cents=239, valid_from=TODAY,
                 valid_to=TODAY + timedelta(days=5)))
    db.commit()
    assert [h["price_cents"] for h in client.get("/watch", headers=auth).json()[0]["hits"]] == [179]
    jobs.watch_alarms(db, at(TODAY))
    jobs.watch_alarms(db, at(TODAY, "18:00"))  # zweiter Import derselben Woche
    assert [p[1] for p in pushes] == ["🧴 Dein Anti-Schuppen Shampoo ist bei dm im Angebot: 1,79 € (−25 %)"]
    assert pushes[0][2]["click_url"].startswith("essenapp://offer/")


def test_base_price_alarm_across_pack_sizes(db):
    item = WatchItem(kind="zutat", label="Hähnchenbrust", max_base_price_cents=700, base_unit="kg", chains=[])
    small = Offer(id=1, title="Hähnchenbrustfilet", chain="lidl", category="fleisch_fisch", price_cents=329, amount=400,
                  unit="g", base_price_cents=823)
    big = Offer(id=2, title="Hähnchenbrust XXL", chain="rewe", category="fleisch_fisch", price_cents=649, amount=1000,
                unit="g", base_price_cents=649)
    assert [o.id for o in watch.matches(item, [small, big])] == [2]  # teurer Packungspreis, aber günstiger je kg
    assert "6,49 €/kg" in watch.message(item, big)
    butter = WatchItem(kind="zutat", label="Butter", max_price_cents=149, chains=["lidl"])
    offers = [Offer(id=3, title="Deutsche Markenbutter", chain="lidl", category="kuehlung", price_cents=139),
              Offer(id=4, title="Butter", chain="rewe", category="kuehlung", price_cents=119)]
    assert [o.id for o in watch.matches(butter, offers)] == [3]  # nur gewählte Läden
    assert watch.name_match(WatchItem(label="Shampoo Classic", brand="Head & Shoulders"),
                            "Head & Shoulders Shampoo", "")
    assert not watch.name_match(WatchItem(label="Shampoo", brand="Nivea"), "Head & Shoulders Shampoo")


def test_heart_on_offer_and_patch(client, auth, db):
    o = offer(db, "Barilla Spaghetti", 99, brand="Barilla", amount=500, unit="g")
    w = client.post("/watch", headers=auth, json={"offer_id": o.id}).json()
    assert (w["label"], w["brand"], w["category"], w["lasts_weeks"]) == ("Barilla Spaghetti", "Barilla", "vorrat", None)
    w = client.patch(f"/watch/{w['id']}", headers=auth, json={"max_price_cents": 89}).json()
    assert w["max_price_cents"] == 89
    assert client.patch(f"/watch/{w['id']}", headers=auth, json={"max_base_price_cents": 100}).status_code == 422
    assert client.delete(f"/watch/{w['id']}", headers=auth).status_code == 204
    assert client.get("/watch", headers=auth).json() == []


# --- 58: Verbrauchsrhythmus ---

def test_rhythm_push_two_weeks_before_and_list_three_days_before(client, auth, db, pushes):
    stores(client, auth, "dm")
    db.get(Household, 1).members[0].quiet_hours = None
    start = TODAY
    w = client.post("/watch", headers=auth, json={"label": "Shampoo", "category": "drogerie", "lasts_weeks": 6,
                                                  "last_bought": str(start)}).json()
    assert w["empty_on"] == str(start + timedelta(weeks=6))
    db.add(Offer(chain="dm", store_ref="", source_id="x", title="Balea Shampoo", category="drogerie", price_cents=95,
                 regular_price_cents=127, valid_from=start, valid_to=start + timedelta(weeks=8)))
    db.commit()
    jobs.watch_rhythm(db, at(start + timedelta(days=27)))  # 15 Tage vor leer: noch nichts
    assert pushes == []
    jobs.watch_rhythm(db, at(start + timedelta(days=28)))  # 14 Tage vorher, im Angebot → Push
    jobs.watch_rhythm(db, at(start + timedelta(days=29)))
    assert [p[1] for p in pushes] == ["🧴 Shampoo bald leer – gerade −25 % bei dm"]
    lst = client.get("/lists", headers=auth).json()[0]["id"]
    assert client.get(f"/lists/{lst}", headers=auth).json()["items"] == []
    jobs.watch_rhythm(db, at(start + timedelta(days=39)))  # 3 Tage vorher → auf die Liste
    jobs.watch_rhythm(db, at(start + timedelta(days=40)))
    items = client.get(f"/lists/{lst}", headers=auth).json()["items"]
    assert [(i["name"], i["source"], i["chain"]) for i in items] == [("Shampoo", "rhythm", "dm")]
    client.patch(f"/items/{items[0]['id']}", headers=auth, json={"checked": True})  # gekauft → neuer Zyklus
    assert client.get("/watch", headers=auth).json()[0]["last_bought"] == str(TODAY)


def test_rhythm_not_in_offer_only_list(db, pushes):
    h = Household(name="T")
    db.add(h)
    db.flush()
    item = WatchItem(household_id=h.id, label="Zahnpasta", category="drogerie", lasts_weeks=4,
                     last_bought=date(2026, 1, 1), chains=["rossmann"])
    db.add(item)
    db.commit()
    from app.api import household_list
    lst = household_list(db, h.id)
    assert watch.rhythm(db, h.id, [], lst, at(date(2026, 1, 15)), jobs.notify) == []
    assert watch.rhythm(db, h.id, [], lst, at(date(2026, 1, 26)), jobs.notify) == ["liste Zahnpasta"]
    assert [(i.name, i.chain) for i in lst.items] == [("Zahnpasta", "rossmann")] and pushes == []


# --- 41: Ein-Laden-Modus ---

def test_single_store_plan_and_list(client, auth, db, monkeypatch):
    stores(client, auth, "lidl", "rewe", meal_types=["abend"], plan_days=[0])
    lidl = offer(db, "Paprika", 99, "lidl", category="obst_gemuese", amount=500, unit="g")
    rewe = offer(db, "Zucchini", 79, "rewe", category="obst_gemuese", amount=500, unit="g")
    seen = []

    def ask(prompt):
        seen.append(prompt)
        return PlanDraft(meals=[meal(0, "Pfanne", [ing("Paprika", 300, offer_id=lidl.id), ing("Reis", 150)],
                                     meal_type="abend")]), USAGE
    monkeypatch.setattr(planner, "ask_claude", ask)
    assert client.post("/plans", headers=auth, json={"single_store": "aldi_nord"}).status_code == 422
    client.post("/plans", headers=auth, json={"single_store": "lidl"})
    assert "Zucchini" not in seen[0][0]["text"] and "Einkauf komplett bei Lidl" in seen[0][1]["text"]
    lst = client.get("/lists", headers=auth).json()[0]["id"]
    items = client.get(f"/lists/{lst}", headers=auth).json()["items"]
    assert {i["chain"] for i in items} == {"lidl"} and len(items) == 2  # auch Reis ohne Angebot
    assert rewe.id


# --- 42: Laden-Empfehlung ---

def test_store_recommendation_matches_list_sums(client, auth, db):
    stores(client, auth, "lidl", "rewe")
    h = db.get(Household, 1)
    h.lat, h.lng = 50.0, 7.0
    h.stores[0].lat, h.stores[0].lng = 50.01, 7.0
    h.stores[1].lat, h.stores[1].lng = 50.0, 7.02
    db.commit()
    offer(db, "Milch", 99, "lidl", category="kuehlung", amount=1000, unit="ml")
    offer(db, "Milch", 109, "rewe", category="kuehlung", amount=1000, unit="ml")
    offer(db, "Kaffee", 699, "lidl", amount=500, unit="g")
    offer(db, "Kaffee", 499, "rewe", amount=500, unit="g")
    offer(db, "Nudeln", 79, "lidl", amount=500, unit="g")
    lst = client.get("/lists", headers=auth).json()[0]["id"]
    for name, amount, unit in [("Milch", 2, "l"), ("Kaffee", None, ""), ("Nudeln", 1000, "g")]:
        client.post(f"/lists/{lst}/items", headers=auth, json={"name": name, "amount": amount, "unit": unit})
    combos = client.get(f"/lists/{lst}/stores", headers=auth).json()
    best_single = next(c for c in combos if len(c["chains"]) == 1)
    pair = next(c for c in combos if len(c["chains"]) == 2)
    assert (best_single["chains"], best_single["total_cents"]) == (["rewe"], 2 * 109 + 499 + 2 * 79)  # Nudeln: Lidl-Normalpreis
    assert (pair["total_cents"], pair["saved_cents"], pair["per_store"]) == (198 + 499 + 158, 20,
                                                                           {"lidl": 198 + 158, "rewe": 499})
    assert pair["distance_km"] > best_single["distance_km"] and pair["extra_km"] > 0
    out = client.post(f"/lists/{lst}/assign", headers=auth, json={"chains": ["lidl", "rewe"]}).json()
    assert {i["name"]: i["chain"] for i in out["items"]} == {"Milch": "lidl", "Kaffee": "rewe", "Nudeln": "lidl"}
    assert client.post(f"/lists/{lst}/assign", headers=auth, json={"chains": ["penny"]}).status_code == 422


def test_store_split_packs():
    milk = Offer(title="Milch", amount=1000, unit="ml", price_cents=99)
    assert store_split.packs(ShoppingItem(name="Milch", amount=1.5, unit="l"), milk) == 2
    assert store_split.packs(ShoppingItem(name="Milch", amount=None, unit=""), milk) == 1
    assert store_split.route_km((50, 7), [(50, 7)]) == 0 and store_split.route_km(None, [(50, 7)]) is None


# --- 43: Budget-Rest ---

def test_budget_rest_ideas_and_add_entry(client, auth, db, monkeypatch):
    stores(client, auth, "lidl", meal_types=["abend"], plan_days=[0], budget_food_week_cents=2000)
    quark = offer(db, "Magerquark", 59, category="kuehlung", amount=500, unit="g")
    history(db, "Spaghetti", [199, 189, 199], amount=500, unit="g")
    offer(db, "Spaghetti", 99, regular=199, amount=500, unit="g")
    monkeypatch.setattr(planner, "ask_claude", lambda p: (PlanDraft(meals=[
        meal(0, "Linsen", [ing("Linsen", 200, pack=500, price=150)], meal_type="abend")]), USAGE))
    plan = client.post("/plans", headers=auth).json()
    b = client.get("/plans/current/budget", headers=auth).json()
    assert (b["state"], b["rest_cents"], b["over"]) == ("rest", 2000 - plan["total_cents"], None)
    asked = []

    def ask(prompt, schema, think=True):
        asked.append(prompt)
        idea = dict(description="", cuisine="", prep_minutes=10, servings=2, steps=["mischen"], image_query="x")
        return schema(ideas=[
            pantry_ai.Idea(title="Quarkcreme", meal_type="dessert", **idea,
                           ingredients=[pantry_ai.IdeaIngredient(name="Magerquark", amount=250, unit="g")]),
            pantry_ai.Idea(title="Gemüsesticks", meal_type="snack", **idea,
                           ingredients=[pantry_ai.IdeaIngredient(name="Karotten", amount=300, unit="g")])]), USAGE
    monkeypatch.setattr(pantry_ai.food_map, "ask_claude", ask)
    ideas = client.post("/plans/current/budget/ideas", headers=auth).json()
    assert [(i["kind"], i["title"]) for i in ideas][:1] == [("dessert", "Quarkcreme")]
    assert ideas[0]["cost_cents"] == quark.price_cents and "Magerquark|59|500g" in asked[0]
    vorrat = next(i for i in ideas if i["kind"] == "vorrat")
    assert vorrat["stockup"]["offer"]["title"] == "Spaghetti" and vorrat["cost_cents"] <= b["rest_cents"]
    new = client.post("/plans/current/entries", headers=auth, json={"recipe_id": ideas[0]["recipe"]["id"], "day": 0,
                                                                     "meal_type": "dessert"})
    assert new.status_code == 201 and [e["meal_type"] for e in new.json()["entries"]] == ["abend", "dessert"]
    assert new.json()["total_cents"] == plan["total_cents"] + 59
    assert client.get("/usage", headers=auth).json()["by_kind"]["budget"] > 0


def test_over_budget_reroll_with_cost_limit(client, auth, db, monkeypatch):
    stores(client, auth, "lidl", meal_types=["abend"], plan_days=[0, 3], budget_food_week_cents=500)
    monkeypatch.setattr(planner, "ask_claude", lambda p: (PlanDraft(meals=[
        meal(0, "Linsen", [ing("Linsen", 200, pack=500, price=150)], meal_type="abend"),
        meal(3, "Steak", [ing("Rindersteak", 400, pack=400, price=680)], meal_type="abend", protein="rot")]), USAGE))
    client.post("/plans", headers=auth)
    b = client.get("/plans/current/budget", headers=auth).json()
    assert b["state"] == "over" and b["rest_cents"] == 500 - 830
    assert (b["over"]["day"], b["over"]["title"], b["over"]["max_cost_cents"]) == (3, "Steak", 680 - 330)
    notes = []

    def ask(prompt):
        notes.append(prompt[1]["text"])
        return PlanDraft(meals=[meal(3, "Bohnenpfanne", [ing("Bohnen", 400, pack=400, price=89)],
                                     meal_type="abend")]), USAGE
    monkeypatch.setattr(planner, "ask_claude", ask)
    plan = client.post(f"/plans/current/entries/{b['over']['entry_id']}/reroll", headers=auth,
                       json={"max_cost_cents": b["over"]["max_cost_cents"]}).json()
    assert "höchstens 350 ct" in notes[0] and plan["total_cents"] == 150 + 89
    assert client.get("/plans/current/budget", headers=auth).json()["state"] == "ok"


# --- 49: Bio, Vegan, Nutri-Score ---

def test_labels_from_text_and_open_food_facts(client, auth, db):
    stores(client, auth, "lidl")
    offer(db, "Bio-Joghurt mild", 79, category="kuehlung")
    offer(db, "Tofu", 149, category="kuehlung", raw={"products": [{"description": [{"paragraph": "vegan, 200 g"}]}]})
    offer(db, "Biotherm Creme", 999, category="drogerie")
    offer(db, "Thermo-Socken", 599, category="sonstiges",
          raw={"products": [{"description": [{"paragraph": "Baumwolle (teilweise Bio), Polyamid"}]}]})
    o = offer(db, "Spaghetti n.5", 99, brand="Barilla", amount=500, unit="g")
    prices.record(db, [o])
    p = db.get(Product, o.product_id)
    hits = [{"code": "8076800195057", "product_name_de": "Spaghetti No. 5", "brands": "Barilla",
             "nutriscore_grade": "a", "labels_tags": ["en:vegetarian"]},
            {"code": "1", "product_name_de": "Spaghetti 5", "brands": "Barilla", "nutriscore_grade": "a"},
            {"code": "2", "product_name_de": "Pesto Genovese", "brands": "Barilla", "nutriscore_grade": "d"}]
    assert labels.enrich([p], find=lambda prod: labels.secure_match(prod, hits), pause=0) == 1
    db.commit()
    rows = {r["title"]: r for r in client.get("/offers", headers=auth).json()}
    assert rows["Bio-Joghurt mild"]["bio"] and not rows["Bio-Joghurt mild"]["vegan"]
    assert rows["Tofu"]["vegan"] and rows["Tofu"]["vegetarian"] and rows["Tofu"]["label_sources"] == ["Prospekttext"]
    assert not rows["Biotherm Creme"]["bio"] and not rows["Thermo-Socken"]["bio"]
    s = rows["Spaghetti n.5"]
    assert (s["nutri_score"], s["off_code"], s["vegetarian"]) == ("A", "8076800195057", True)
    assert s["label_sources"] == ["Open Food Facts (ODbL)"]
    assert [r["title"] for r in client.get("/offers?nutri_ab=true", headers=auth).json()] == ["Spaghetti n.5"]
    assert [r["title"] for r in client.get("/offers?bio=true", headers=auth).json()] == ["Bio-Joghurt mild"]
    assert [r["title"] for r in client.get("/offers?vegan=true", headers=auth).json()] == ["Tofu"]


def test_off_secure_match_rather_none_than_wrong():
    p = Product(title="Spaghetti n.5", brand="Barilla")
    other_brand = [{"code": "9", "product_name_de": "Spaghetti n°5", "brands": "Spar", "nutriscore_grade": "a"}]
    assert labels.secure_match(p, other_brand) is None
    conflicting = [{"code": "1", "product_name_de": "Spaghetti No. 5", "brands": "Barilla", "nutriscore_grade": "a"},
                   {"code": "2", "product_name_de": "Spaghetti n 5", "brands": "Barilla", "nutriscore_grade": "b"}]
    assert labels.secure_match(p, conflicting) is None
    assert labels.secure_match(Product(title="Spaghetti", brand=""), conflicting) is None  # ohne Marke nie sicher
    assert labels.secure_match(p, [{"code": "3", "product_name_de": "Lasagne Sheets", "brands": "Barilla",
                                    "nutriscore_grade": "a"}]) is None


def test_planner_prefers_nutri_ab(client, auth, db, monkeypatch):
    stores(client, auth, "lidl", meal_types=["abend"], plan_days=[0], nutrition_goal="kalorienarm")
    o = offer(db, "Haferflocken", 79, brand="Kölln", amount=500, unit="g")
    prices.record(db, [o])
    db.get(Product, o.product_id).nutri_score = "a"
    db.commit()
    seen = []
    monkeypatch.setattr(planner, "ask_claude", lambda p: seen.append(p[1]["text"]) or (PlanDraft(meals=[
        meal(0, "Porridge", [ing("Haferflocken", 100, offer_id=o.id)], meal_type="abend")]), USAGE))
    client.post("/plans", headers=auth)
    assert "Nutri-Score A/B (bei Ziel „kalorienarm“ bei ähnlichem Preis bevorzugen): Haferflocken" in seen[0]


# --- 59: Monatsaktionen ---

def test_monthly_drugstore_section(client, auth, db):
    stores(client, auth, "dm", "rossmann", "lidl")
    end = (TODAY.replace(day=28) + timedelta(days=4)).replace(day=1) - timedelta(days=1)
    offer(db, "Zahnpasta", 95, "dm", category="drogerie", start=TODAY, end=end)
    offer(db, "Duschgel", 75, "rossmann", category="drogerie", start=TODAY, end=TODAY + timedelta(days=4)
          if (TODAY + timedelta(days=5)).day != 1 else TODAY + timedelta(days=3))
    offer(db, "Bier", 499, "lidl", category="getraenke", start=TODAY, end=end)
    rows = client.get("/offers?monthly=true", headers=auth).json()
    assert [(r["title"], r["monthly"]) for r in rows] == [("Zahnpasta", True)]


# --- Fix 2: Reste auch am selben Tag später ---

def test_rest_target_same_day_later_meal():
    offers = {7: Offer(id=7, title="Sahne", chain="lidl", category="kuehlung", price_cents=99, amount=200, unit="ml")}
    draft = PlanDraft(meals=[meal(6, "Curry", [ing("Sahne", 100, "ml", offer_id=7)]),
                             meal(6, "Panna Cotta", [ing("Zucker", 50)], meal_type="dessert")])
    p = planner.price(draft, offers)
    targets, _ = planner.rest_targets(p, [(6, "mittag"), (6, "dessert")], {})
    assert targets == {(6, "dessert"): ["verwende Rest 100 ml Sahne (offer_id=7) komplett"]}


def test_kaufda_shelf_keeps_next_week_brochures():
    """30: Der Shelf listet den Folgewochen-Prospekt (live 02.11.: Lidl 09.–14.11.); er wird mit importiert."""
    from app.sources import kaufda
    shelf = {"contents": [{"contentType": "brochure", "content": {
        "contentId": cid, "publisher": {"name": "Lidl"}, "closestStore": {"externalId": "5741"},
        "validFrom": start, "validUntil": end}} for cid, start, end in [
        ("now", "2026-11-01T23:00:00.000+0000", "2026-11-07T22:00:00.000+0000"),
        ("next", "2026-11-08T23:00:00.000+0000", "2026-11-14T22:00:00.000+0000")]]}
    brochures = kaufda.parse_shelf(shelf)
    assert [(b["content_id"], b["valid_from"]) for b in kaufda.pick_brochures(brochures, {"lidl"})] == [
        ("now", date(2026, 11, 2)), ("next", date(2026, 11, 9))]


def test_big_rest_split_and_rests_of_repaired_slots_skipped():
    offers = {7: Offer(id=7, title="Hähnchen", chain="lidl", category="fleisch_fisch", price_cents=599, amount=1000,
                       unit="g")}
    draft = PlanDraft(meals=[meal(0, "Curry", [ing("Hähnchen", 200, offer_id=7)], protein="gefluegel"),
                             meal(1, "Wrap", [ing("Bohnen", 100)], protein="gefluegel"),
                             meal(1, "Bowl", [ing("Reis", 100)], meal_type="abend", protein="gefluegel")])
    p = planner.price(draft, offers)
    targets, _ = planner.rest_targets(p, [(0, "mittag"), (1, "mittag"), (1, "abend")], {})
    assert targets == {(1, "mittag"): ["verwende Rest 400 g Hähnchen (offer_id=7) komplett"],
                       (1, "abend"): ["verwende Rest 400 g Hähnchen (offer_id=7) komplett"]}
    assert planner.rest_targets(p, [(0, "mittag"), (1, "mittag"), (1, "abend")], {(0, "mittag"): ["vegetarisch"]})[0] == {}
