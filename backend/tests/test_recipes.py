import base64
from datetime import date, datetime, timedelta

from app import api
from app.models import MealPlan, MealPlanEntry, Offer, Rating, Recipe
from app.services import planner, recipes
from app.services.matching import Matcher
from app.services.planner import PlanDraft
from tests.test_planner import ing as planned, meal, text
from tests.test_sharing import add_plan, ing, new_household

JPEG = b"\xff\xd8\xff\xe0" + b"0" * 100
TODAY = date.today()


def chicken_offer(**kw):
    return Offer(**{"id": 7, "chain": "rewe", "store_ref": "1", "source_id": "h", "title": "Hähnchenbrustfilet",
                    "category": "fleisch_fisch", "price_cents": 399, "regular_price_cents": 599, "amount": 400,
                    "unit": "g", "base_price_cents": 998, "valid_from": TODAY, "valid_to": TODAY} | kw)


def new_recipe(client, auth, **kw):
    body = {"title": "Hähnchen-Reis", "servings": 2, "prep_minutes": 25, "cuisine": "deutsch", "meal_type": "abend",
            "ingredients": [{"name": "Hähnchenbrust", "amount": 400, "unit": "g"},
                            {"name": "Reis", "amount": 0.1, "unit": "kg"}, {"name": "Öl", "amount": 1, "unit": "el"}],
            "steps": ["Anbraten", "Reis kochen"], "tags": ["schnell"]} | kw
    r = client.post("/recipes", headers=auth, json=body)
    assert r.status_code == 201, r.text
    return r.json()


def test_matcher_names_plural_compounds_synonyms():
    offers = [chicken_offer(), chicken_offer(id=8, title="Gemüsezwiebeln", category="obst_gemuese"),
              chicken_offer(id=9, title="Butterkeks", category="vorrat"), chicken_offer(id=10, title="Eier M",
                                                                                     category="kuehlung"),
              chicken_offer(id=11, title="Duschgel Hähnchenbrust", category="drogerie")]
    m = Matcher(offers)
    assert [o.id for o in m.find("Hähnchenbrust")] == [7]  # Synonym, Drogerie ignoriert
    assert [o.id for o in m.find("Zwiebeln")] == [8]  # Plural + Kompositum
    assert m.find("Butter") == [] and [o.id for o in m.find("Ei")] == [10]
    assert m.find("frische Zwiebel")[0].id == 8


def test_create_recipe_with_image_and_cost(client, auth, db, monkeypatch, tmp_path):
    monkeypatch.setattr(api, "MEDIA", tmp_path)
    client.patch("/household", headers=auth, json={"stores": [{"chain": "rewe", "store_ref": "1"}]})
    db.add_all([chicken_offer(),  # Reis nur früher bei Lidl → Normalpreis-Schätzung
                Offer(chain="lidl", source_id="r", title="Langkornreis", category="vorrat", price_cents=129,
                      regular_price_cents=149, amount=1000, unit="g", valid_from=TODAY - timedelta(days=20),
                      valid_to=TODAY - timedelta(days=15))])
    db.commit()
    r = new_recipe(client, auth, image=base64.b64encode(JPEG).decode())
    assert r["source"] == "user" and r["tags"] == ["schnell"] and r["favorite"] is False
    assert r["ingredients"][1] == {"name": "Reis", "amount": 100, "unit": "g"}  # kg → g
    assert r["image_url"].startswith(f"/media/recipes/{r['id']}.jpg?v=")
    assert (tmp_path / "recipes" / f"{r['id']}.jpg").read_bytes() == JPEG
    assert r["nutrition"] is None and r["ratings"] == []  # Zuordnung läuft noch

    cost = client.get(f"/recipes/{r['id']}/cost", headers=auth).json()
    lines = {line["name"]: line for line in cost["lines"]}
    assert lines["Hähnchenbrust"]["cost_cents"] == 399 and lines["Hähnchenbrust"]["in_offer"]
    assert lines["Reis"]["cost_cents"] == 15 and not lines["Reis"]["in_offer"]  # 100 g von 1,49 €/kg
    assert not lines["Öl"]["priced"]
    assert cost["cost_cents"] == 414 and cost["cost_per_serving_cents"] == 207 and cost["offer_share"] == 0.964

    bad = client.post("/recipes", headers=auth, json={**{"title": "X", "servings": 1, "prep_minutes": 5,
                      "meal_type": "abend", "ingredients": [{"name": "A", "amount": 1, "unit": "g"}]},
                      "image": base64.b64encode(b"\x89PNG....").decode()})
    assert bad.status_code == 422
    assert client.post("/recipes", headers=auth, json={"title": "X", "servings": 1, "prep_minutes": 5,
                                                       "meal_type": "abend", "ingredients": []}).status_code == 422


def test_list_filters_favorite_rate_and_rights(client, auth, db):
    own = new_recipe(client, auth)
    db.add_all([Recipe(household_id=1, title="KI-Curry", meal_type="abend", servings=2, prep_minutes=20),
                Recipe(household_id=1, title="KI-Suppe", meal_type="abend", servings=2, prep_minutes=20),
                Recipe(household_id=1, title="Reel-Pasta", meal_type="abend", servings=2, prep_minutes=20,
                       source="instagram", source_author="@koch", tags=["pasta"])])
    db.commit()
    ids = lambda f="alle", q="": [c["id"] for c in client.get(f"/recipes?filter={f}&q={q}", headers=auth).json()]
    assert ids() == [4, own["id"]]  # KI-Gerichte nur, wenn favorisiert oder bewertet

    assert client.post("/recipes/2/favorite", headers=auth).json() == {"favorite": True}
    assert client.post("/recipes/4/favorite", headers=auth).json() == {"favorite": True}
    assert client.post("/recipes/4/favorite", headers=auth).json() == {"favorite": False}
    assert ids() == [4, 2, own["id"]] and ids("favoriten") == [2]
    assert ids("eigene") == [own["id"]] and ids("importiert") == [4] and ids(q="PASTA") == [4]

    r = client.post("/recipes/3/rate", headers=auth, json={"stars": 2, "again": "nie", "note": "zu scharf",
                                                            "cooked_at": "2026-11-01T19:00:00"})
    assert r.status_code == 201 and r.json()["member_name"] == "J"
    client.post(f"/recipes/{own['id']}/rate", headers=auth, json={"stars": 5, "again": "bald"})
    assert ids("zuletzt") == [own["id"], 3]
    assert client.post("/recipes/3/rate", headers=auth, json={"stars": 6, "again": "bald"}).status_code == 422
    assert client.post("/recipes/3/rate", headers=auth, json={"stars": 3, "again": "oft"}).status_code == 422
    detail = client.get(f"/recipes/{own['id']}", headers=auth).json()
    assert detail["avg_stars"] == 5 and detail["ratings"][0]["again"] == "bald" and detail["steps"][0] == "Anbraten"

    other = new_household(client)
    assert client.get(f"/recipes/{own['id']}", headers=other).status_code == 404
    assert client.patch("/recipes/2", headers=auth, json={"title": "Neu"}).status_code == 403  # KI-Gericht
    assert client.patch(f"/recipes/{own['id']}", headers=other, json={"title": "Neu"}).status_code == 404
    p = client.patch(f"/recipes/{own['id']}", headers=auth, json={"title": "Hähnchen-Reis scharf", "tags": ["scharf"]})
    assert p.json()["title"] == "Hähnchen-Reis scharf" and p.json()["tags"] == ["scharf"]
    assert p.json()["ingredients"][0]["name"] == "Hähnchenbrust"  # nicht geschickt → unverändert
    assert client.delete("/recipes/4", headers=auth).status_code == 204
    assert db.get(Recipe, 4) is None and ids("importiert") == []


def test_deals_and_offer_badge(client, auth, db):
    client.patch("/household", headers=auth, json={"stores": [{"chain": "rewe", "store_ref": "1"}]})
    db.add(chicken_offer())
    db.commit()
    fav = new_recipe(client, auth)
    other = new_recipe(client, auth, title="Kartoffelsuppe",
                       ingredients=[{"name": "Kartoffeln", "amount": 800, "unit": "g"}])
    liked = new_recipe(client, auth, title="Hähnchen-Wrap")
    client.post(f"/recipes/{fav['id']}/favorite", headers=auth)
    client.post(f"/recipes/{other['id']}/favorite", headers=auth)
    client.post(f"/recipes/{liked['id']}/rate", headers=auth, json={"stars": 4, "again": "bald"})
    deals = client.get("/recipes/deals", headers=auth).json()
    assert sorted(d["id"] for d in deals) == [fav["id"], liked["id"]] and all(d["offer_share"] >= 0.4 for d in deals)
    assert [c["id"] for c in client.get("/recipes?filter=im_angebot", headers=auth).json()] == [liked["id"], fav["id"]]


def test_replace_entry_scales_and_syncs_list(client, auth, db):
    client.patch("/household", headers=auth, json={"stores": [{"chain": "rewe", "store_ref": "1"}]})
    db.add(chicken_offer())
    db.commit()
    add_plan(db, 1, [[ing("Nudeln", 250)], [ing("Linsen", 200)]])
    db.get(MealPlanEntry, 1).portions_total = 2
    db.commit()
    own = new_recipe(client, auth, servings=4, ingredients=[{"name": "Hähnchenbrust", "amount": 800, "unit": "g"}])
    r = client.post("/plans/current/entries/1/replace", headers=auth, json={"recipe_id": own["id"]})
    assert r.status_code == 200, r.text
    entry = r.json()["entries"][0]
    assert entry["recipe"]["id"] == own["id"] and entry["scale"] == 0.5
    assert entry["cost_cents"] == 399 and r.json()["total_cents"] >= 399  # 400 g = 1 Packung im Angebot
    items = client.get("/lists", headers=auth).json()[0]
    lst = client.get(f"/lists/{items['id']}", headers=auth).json()["items"]
    chicken = next(i for i in lst if i["name"] == "Hähnchenbrust")
    assert (chicken["amount"], chicken["chain"], chicken["offer_id"]) == (400, "rewe", 7)
    assert "Nudeln" not in [i["name"] for i in lst]
    assert client.post("/plans/current/entries/1/replace", headers=auth, json={"recipe_id": 999}).status_code == 404
    # Rezept steht im Plan → Löschen entfernt es nur aus „Meine Rezepte“
    assert client.delete(f"/recipes/{own['id']}", headers=auth).status_code == 204
    assert db.get(Recipe, own["id"]).source == "ai" and client.get("/recipes", headers=auth).json() == []


def test_planner_memory_and_prompt(client, auth, db, monkeypatch):
    def recipe(title, names=("Reis",)):
        r = Recipe(household_id=1, title=title, meal_type="abend", servings=2, prep_minutes=20,
                   ingredients=[{"name": n, "amount": 100, "unit": "g"} for n in names])
        db.add(r)
        db.flush()
        return r

    top, never, meh, old = recipe("Butter Chicken", ("Hähnchen", "Sahne")), recipe("Leber"), recipe("Eintopf"), \
        recipe("Lasagne")
    db.add_all([Rating(recipe_id=top.id, member_id=1, stars=5, again="bald"),
                Rating(recipe_id=never.id, member_id=1, stars=4, again="nie"),
                Rating(recipe_id=meh.id, member_id=1, stars=2, again="irgendwann"),
                Rating(recipe_id=old.id, member_id=1, stars=5, again="bald")])
    last_week = (TODAY - timedelta(weeks=1)).isocalendar()
    plan = MealPlan(household_id=1, week=f"{last_week[0]}-W{last_week[1]:02d}")
    plan.entries.append(MealPlanEntry(day=0, meal_type="abend", recipe=old))
    db.add(plan)
    db.commit()
    mem = recipes.planner_memory(db, 1)
    assert mem == {"favorites": ["Butter Chicken (Hähnchen, Sahne)"], "never": ["Eintopf", "Leber"],
                   "recent": ["Lasagne"]}

    asks = []

    def fake_ask(prompt):
        asks.append(text(prompt))
        title = "Leber mit Zwiebeln" if len(asks) == 1 else "Butter Chicken"
        return PlanDraft(meals=[meal(0, title, [planned("Reis", 100)], "abend")]), {}

    monkeypatch.setattr(planner, "ask_claude", fake_ask)
    client.patch("/household", headers=auth, json={"meal_types": ["abend"], "plan_days": [0]})
    r = client.post("/plans", headers=auth)
    assert r.status_code == 201 and r.json()["entries"][0]["recipe"]["title"] == "Butter Chicken"
    assert "Lieblingsrezepte (gern einplanen, max. 2 pro Woche, Titel übernehmen):\n- Butter Chicken (Hähnchen, Sahne)" \
        in asks[0]
    assert "Nie vorschlagen (auch nichts Ähnliches): Eintopf, Leber" in asks[0]
    assert "In den letzten 3 Wochen gekocht, nicht wiederholen: Lasagne" in asks[0]
    assert "Ersetze Leber mit Zwiebeln" in asks[1]  # Nie-Liste wird durchgesetzt (Korrekturrunde)
    assert planner.similar("Leber", "leber ") and not planner.similar("Leber", "Leberkäse mit Ei")
