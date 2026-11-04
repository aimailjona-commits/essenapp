from datetime import date

from app.models import Offer
from app.services import planner
from app.services.matching import Matcher, fits
from app.sources.kaufda import classify
from tests.test_planner import ing, meal


def offer(i, title, chain="lidl"):
    cat, sub = classify(chain, title)
    return Offer(id=i, chain=chain, title=title, category=cat, subcategory=sub, price_cents=99, amount=500, unit="g",
                 source_id=str(i), valid_from=date.today(), valid_to=date.today())


def test_fits_rejects_wrong_product_kind():
    assert not fits("Joghurt", offer(1, "Cherrygold Käse"))
    assert not fits("Käse", offer(2, "Frischkäse Natur"))
    assert not fits("Milch", offer(3, "Kokosmilch"))
    assert fits("Joghurt", offer(4, "Naturjoghurt 3,8 %"))
    assert fits("Passierte Tomaten", offer(5, "Passata"))  # Dose statt frisch ist ok
    assert fits("Zwiebeln", offer(6, "Gemüsezwiebeln"))
    assert not fits("Kaffee", Offer(id=7, title="Kaffeemühle", category="nonfood", subcategory=""))


def test_matcher_skips_unfitting_offers():
    m = Matcher([offer(1, "Frischkäse Natur"), offer(2, "Gouda jung"), offer(3, "Sahnejoghurt")])
    assert [o.title for o in m.find("Käse")] == []  # Gouda heißt nicht „Käse“, Frischkäse ist keiner
    assert [o.title for o in m.find("Joghurt")] == ["Sahnejoghurt"]


def test_price_drops_offer_that_does_not_fit_the_ingredient():
    draft = planner.PlanDraft(meals=[meal(0, "Bowl", [ing("Joghurt", 500, offer_id=1, pack=500, price=129)])])
    p = planner.price(draft, {1: offer(1, "Cherrygold Käse")})
    assert draft.meals[0].ingredients[0].offer_id is None  # nicht mehr als Angebot verknüpft
    assert p.total_cents == 129  # Normalpreis-Schätzung der KI statt Käse-Angebot


def test_classify_unknown_asks_once_per_title_and_reuses_known(db):
    from datetime import timedelta
    from app.services.importer import Kind, Kinds, classify_unknown

    def row(i, title, cat="sonstiges", sub="", days=3):
        return Offer(chain="lidl", store_ref="", source_id=str(i), title=title, category=cat, subcategory=sub,
                     price_cents=99, valid_from=date.today() - timedelta(days=days), valid_to=date.today() + timedelta(days=days - 3))
    db.add_all([row(1, "Rama"), row(2, "Rama"), row(3, "Doppelzimmer"), row(4, "Yakult"),
                row(5, "Yakult", "kuehlung", "joghurt", days=10)])  # Yakult aus einer früheren Woche bekannt
    db.commit()
    asked = []

    def ask(prompt, schema, think=True):
        asked.append(prompt)
        lines = prompt.split("\n\n", 1)[1].splitlines()
        kinds = {"rama": "molkerei", "doppelzimmer": "nonfood"}
        return Kinds(items=[Kind(i=int(l.split("|")[0]), kind=kinds[l.split("|")[1]]) for l in lines]), {"cost_cents": 0.01}
    assert classify_unknown(db, ask) == 4
    assert len(asked) == 1 and "yakult" not in asked[0]
    got = {(o.title, o.category, o.subcategory) for o in db.query(Offer)}
    assert ("Rama", "kuehlung", "molkerei") in got and ("Doppelzimmer", "nonfood", "nonfood") in got
    assert ("Yakult", "kuehlung", "joghurt") in got


def test_rules_and_forbidden_ingredients():
    from app.services.matching import is_a
    from app.services.substitutes import forbidden
    assert is_a("Vollmilch", "Milch") and is_a("Rinderhackfleisch", "Hackfleisch") and is_a("Saure Sahne", "Sahne")
    assert not is_a("Buttermilch", "Milch") and not is_a("Reis", "Ei") and not is_a("Milchreis", "Milch")
    assert forbidden("Champignons braun", [], dislikes=["Champignons"]) and not forbidden("Basmatireis", [], dislikes=["Ei"])
    meals = [meal(0, "Porridge", [ing("Vollmilch", 300, unit="ml", offer_id=3), ing("Buttermilch", 100, unit="ml")])]
    planner.apply_rules(meals, [{"instead": "Milch", "use": "Hafermilch"}])
    assert [(i.name, i.offer_id) for i in meals[0].ingredients] == [("Hafermilch", None), ("Buttermilch", None)]


def test_make_plan_replaces_meals_with_forbidden_ingredients():
    from types import SimpleNamespace
    h = SimpleNamespace(persons=2, diet="alles", allergies=["Erdnüsse"], excluded_ingredients=[], cuisines=[],
                        nutrition_goal="ausgewogen", max_cook_minutes=30, budget_food_week_cents=10000,
                        product_rules=[], plan_days=[0], meal_types=["abend"])
    drafts = iter([planner.PlanDraft(meals=[meal(0, "Satay", [ing("Erdnussbutter", 50)], "abend")]),
                   planner.PlanDraft(meals=[meal(0, "Curry", [ing("Kichererbsen", 400)], "abend")])])
    notes = []

    def ask(prompt):
        notes.append(prompt[-1]["text"])
        return next(drafts), {}
    from app.services.substitutes import forbidden
    p = planner.make_plan(h, [], [(0, "abend")], [], ask=ask, forbid=lambda n: forbidden(n, h.allergies))
    assert p.draft.meals[0].title == "Curry" and "Satay (Erdnussbutter)" in notes[1]


def test_reroll_direction_and_undo_entry_and_plan(client, auth, db, monkeypatch):
    from tests.test_planner import test_plan_endpoint, text
    test_plan_endpoint(client, auth, db, monkeypatch)
    first = client.get("/plans/current", headers=auth).json()
    curry = first["entries"][0]
    seen = {}

    def fake_ask(prompt):
        seen["prompt"] = text(prompt)
        return planner.PlanDraft(meals=[meal(0, "Gemüsepfanne", [ing("Zucchini", 400)])]), {"cost_cents": 0.1}
    monkeypatch.setattr(planner, "ask_claude", fake_ask)
    r = client.post(f"/plans/current/entries/{curry['id']}/reroll", headers=auth,
                    json={"direction": "ohne_fleisch", "wish": "mit Reis"})
    assert r.status_code == 200 and r.json()["entries"][0]["recipe"]["title"] == "Gemüsepfanne"
    assert "Vegetarisch, ohne Fleisch" in seen["prompt"] and "Wunsch für dieses Gericht: mit Reis" in seen["prompt"]
    r = client.post(f"/plans/current/entries/{curry['id']}/undo", headers=auth)
    assert r.status_code == 200 and r.json()["entries"][0]["recipe"]["title"] == "Curry"
    assert r.json()["total_cents"] == first["total_cents"]

    # neuer Plan, dann „Rückgängig“: der vorige ist wieder aktuell, Einkaufsliste folgt
    monkeypatch.setattr(planner, "ask_claude", lambda p: (planner.PlanDraft(meals=[
        meal(0, "Suppe", [ing("Kartoffeln", 500)]), meal(1, "Salat", [ing("Gurke", 1, unit="stk")])]), {}))
    assert client.post("/plans", headers=auth).status_code == 201
    r = client.post("/plans/current/undo", headers=auth)
    assert r.status_code == 200 and r.json()["id"] == first["id"]
    assert client.get("/plans/current", headers=auth).json()["id"] == first["id"]
    lists = client.get("/lists", headers=auth).json()
    items = client.get(f"/lists/{lists[0]['id']}", headers=auth).json()["items"]
    assert "Kartoffeln" not in {i["name"] for i in items}


def test_unlisted_finds_step_ingredients_missing_from_the_list():
    m = meal(0, "Hähnchenwraps", [ing("Hähnchen-Filetstreifen", 300), ing("Porree", 1, unit="stk")])
    m.steps = ["Hähnchen anbraten und Lauch hacken.", "Wraps mit Paprikastreifen füllen, mit Wasser abschmecken."]
    assert planner.unlisted(m) == ["paprikastreifen", "wraps"]  # Lauch = Porree, Verben und Wasser zählen nicht


def test_make_plan_asks_again_for_unlisted_ingredients():
    from types import SimpleNamespace
    h = SimpleNamespace(persons=2, diet="alles", allergies=[], excluded_ingredients=[], cuisines=[],
                        nutrition_goal="ausgewogen", max_cook_minutes=30, budget_food_week_cents=10000,
                        product_rules=[], plan_days=[0], meal_types=["abend"])
    bad = meal(0, "Wraps", [ing("Hähnchen", 300)], "abend")
    bad.steps = ["Wraps füllen."]
    good = meal(0, "Wraps", [ing("Hähnchen", 300), ing("Tortilla-Wraps", 4, unit="stk")], "abend")
    drafts, notes = iter([planner.PlanDraft(meals=[bad]), planner.PlanDraft(meals=[good])]), []

    def ask(prompt):
        notes.append(prompt[-1]["text"])
        return next(drafts), {}
    p = planner.make_plan(h, [], [(0, "abend")], [], ask=ask)
    assert len(p.draft.meals[0].ingredients) == 2 and "Wraps: wraps" in notes[1]


def test_list_merges_plural_and_shows_packs(client, auth, db, monkeypatch):
    from tests.test_planner import test_plan_endpoint
    test_plan_endpoint(client, auth, db, monkeypatch)  # Hähnchen-Angebot id 1: 400 g
    monkeypatch.setattr(planner, "ask_claude", lambda p: (planner.PlanDraft(meals=[
        meal(0, "Curry", [ing("Hähnchen", 300, offer_id=1), ing("Zwiebel", 1, unit="stk", pack=3)]),
        meal(1, "Dal", [ing("Zwiebeln", 2, unit="stk", pack=3), ing("Linsen", 600)])]), {}))
    assert client.post("/plans", headers=auth).status_code == 201
    plan = client.get("/plans/current", headers=auth).json()
    lst = client.get("/lists", headers=auth).json()[0]
    items = {i["name"]: i for i in client.get(f"/lists/{lst['id']}", headers=auth).json()["items"]}
    got = {n: (i["amount"], i["pack_amount"], i["packs"]) for n, i in items.items()}
    assert got == {"Hähnchen": (300, 400, 1), "Zwiebel": (3, 3, 1), "Linsen": (600, 500, 2)}
    assert plan["total_cents"] == 399 + 200 + 2 * 200  # ganze Packungen, Zwiebeln nur einmal
    # 2 × 500 g gekauft, 600 g gebraucht: alles in den Vorrat, der Plan verbraucht seinen Teil
    assert client.post(f"/items/{items['Linsen']['id']}/to-pantry", headers=auth).json()["amount"] == 1000


def test_web_list_shows_packs_and_german_units():
    from types import SimpleNamespace
    from app.web import qty, size
    item = SimpleNamespace(id=1, name="Tomaten", amount=700.0, unit="g", pack_amount=500.0, chain="", offer_id=None,
                           checked=False, added_by="", checked_by="", source="plan", defer_week=None)
    assert qty(item) == "2 × 500 g · 700 g gebraucht"
    assert size(1100, "g") == "1,1 kg" and size(2, "el") == "2 EL"


def test_plan_job_runs_in_background_and_reports_state(client, auth, db, monkeypatch):
    from tests.test_planner import test_plan_endpoint
    test_plan_endpoint(client, auth, db, monkeypatch)
    first = client.get("/plans/current", headers=auth).json()["id"]
    assert client.post("/plans/job", headers=auth).status_code == 202
    assert client.get("/plans/job", headers=auth).json() == {"state": "done", "error": ""}
    assert client.get("/plans/current", headers=auth).json()["id"] != first
    client.post("/plans/job", headers=auth, json={"single_store": "aldi_nord"})  # Laden nicht ausgewählt
    assert client.get("/plans/job", headers=auth).json() == {"state": "error", "error": "Laden ist nicht ausgewählt"}


def test_plan_job_left_running_counts_as_aborted(client, auth, db):
    from datetime import UTC, datetime, timedelta
    from app.models import JobRun
    hid = client.get("/household", headers=auth).json()["id"]
    db.add(JobRun(name=f"plan:{hid}", ran_at=datetime.now(UTC).replace(tzinfo=None) - timedelta(minutes=11), info="läuft"))
    db.commit()
    assert client.get("/plans/job", headers=auth).json()["state"] == "error"


def test_repair_replans_only_the_bad_meal():
    from types import SimpleNamespace
    h = SimpleNamespace(persons=2, diet="alles", allergies=["Erdnüsse"], excluded_ingredients=[], cuisines=[],
                        nutrition_goal="ausgewogen", max_cook_minutes=30, budget_food_week_cents=10000,
                        product_rules=[], plan_days=[0, 1], meal_types=["abend"])
    drafts = iter([planner.PlanDraft(meals=[meal(0, "Satay", [ing("Erdnussbutter", 50)], "abend"),
                                            meal(1, "Suppe", [ing("Kartoffeln", 500)], "abend")]),
                   planner.PlanDraft(meals=[meal(0, "Curry", [ing("Kichererbsen", 400)], "abend")])])
    notes = []

    def ask(prompt):
        notes.append(prompt[-1]["text"])
        return next(drafts), {}
    from app.services.substitutes import forbidden
    p = planner.make_plan(h, [], [(0, "abend"), (1, "abend")], [], ask=ask, forbid=lambda n: forbidden(n, h.allergies))
    assert [m.title for m in p.draft.meals] == ["Curry", "Suppe"]
    assert "NUR diese Mahlzeiten" in notes[1] and "Di abend: Suppe" in notes[1]


def test_never_recipes_are_findable_and_can_be_unhidden(client, auth, db):
    rid = client.post("/recipes", headers=auth, json={"title": "Leberkäse", "servings": 2, "prep_minutes": 10,
                                                      "meal_type": "abend",
                                                      "ingredients": [{"name": "Leberkäse", "amount": 400, "unit": "g"}]}).json()["id"]
    client.post(f"/recipes/{rid}/rate", headers=auth, json={"stars": 1, "again": "nie"})
    hidden = client.get("/recipes?filter=ausgeblendet", headers=auth).json()
    assert [c["title"] for c in hidden] == ["Leberkäse"] and hidden[0]["hidden"]
    from app.services import recipes
    hid = client.get("/household", headers=auth).json()["id"]
    assert recipes.planner_memory(db, hid)["never"] == ["Leberkäse"]
    assert client.post(f"/recipes/{rid}/unhide", headers=auth).json()["hidden"] is False
    assert recipes.planner_memory(db, hid)["never"] == [] and client.get("/recipes?filter=ausgeblendet", headers=auth).json() == []
    client.post(f"/recipes/{rid}/rate", headers=auth, json={"stars": 2, "again": "irgendwann"})  # wieder schlecht
    assert recipes.planner_memory(db, hid)["never"] == ["Leberkäse"]


def test_report_keeps_linked_offer_for_wrong_offer(client, auth, db, monkeypatch):
    from app.models import Report
    from tests.test_planner import test_plan_endpoint
    test_plan_endpoint(client, auth, db, monkeypatch)  # Curry mit Hähnchen-Angebot
    rid = client.get("/plans/current", headers=auth).json()["entries"][0]["recipe"]["id"]
    r = client.post(f"/recipes/{rid}/report", headers=auth,
                    json={"kind": "angebot_falsch", "ingredient": "Hähnchen", "note": "war Käse"})
    assert r.status_code == 201
    assert [(x.kind, x.offer_title, x.note) for x in db.query(Report)] == [("angebot_falsch", "Hähnchen", "war Käse")]
    assert client.post(f"/recipes/{rid}/report", headers=auth, json={"kind": "quatsch"}).status_code == 422
