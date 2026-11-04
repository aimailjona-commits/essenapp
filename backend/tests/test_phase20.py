"""Phase 20 – Woche per Swipe (E97): Stapel, Abstimmung im Haushalt, Verteilen, Plan aus der Auswahl."""
import re

import pytest

from app.models import Household, Recipe, SwipeCard
from app.services import planner, recipes, swipe, variety
from app.services.planner import CardDraft, CardIngredient, CardSet, PlanDraft
from tests.test_planner import ing, meal

pytestmark = pytest.mark.usefixtures("jobs_inline")


def card(title, protein="vegetarisch", side="andere", ings=(("Linsen", 80),)):
    return CardDraft(title=title, description=f"{title} lecker", cuisine="deutsch", prep_minutes=20, side=side,
                     protein=protein, image_query=title,
                     ingredients=[CardIngredient(name=n, amount=a, unit="g", offer_id=None) for n, a in ings])


DISHES = ("Curry Gulasch Lasagne Risotto Paella Chili Ramen Tacos Quiche Frikadellen Rouladen Schnitzel Pfannkuchen "
          "Porridge Omelett Bowl Wraps Falafel Moussaka Shakshuka Dal Pho Burger Gnocchi Flammkuchen Rösti Couscous "
          "Bulgur Muffins Smoothie Crêpes Waffeln Sushi Enchiladas Polenta Eintopf Spätzle Maultaschen Knödel").split()


def fake_cards(asked: list):
    names = iter(DISHES)  # verschiedene Titel (ähnliche fasst der Stapel zusammen)

    def ask(prompt):
        text = prompt[-1]["text"]
        m = re.search(r"meal_type=(\w+)", text).group(1)
        n = int(re.search(r"Schlage (\d+)", text).group(1))
        asked.append((m, n, text))
        return CardSet(cards=[card(next(names), protein="fisch" if i == 0 else "vegetarisch") for i in range(n)]), \
            {"model": "claude-haiku-5-5", "cost_cents": 0.1, "output_tokens": 100}
    return ask


def member2(client, auth, name="S"):
    code = client.post("/household/invites", headers=auth).json()["code"]
    return {"Authorization": f"Bearer {client.post(f'/join/{code}', json={'member_name': name}).json()['token']}"}


@pytest.fixture
def deck(client, auth, db, monkeypatch):
    client.patch("/household", headers=auth, json={"meal_types": ["fruehstueck", "abend"], "plan_days": [0, 1, 2],
                                                    "variety": {"min_fish": 0, "veggie_days": 0}})
    asked = []
    monkeypatch.setattr(planner, "ask_cards", fake_cards(asked))
    r = client.post("/swipe", headers=auth)
    assert r.status_code == 200, r.text
    return r.json(), asked


def test_deck_mixes_in_own_favorites(client, auth, db, monkeypatch):
    client.patch("/household", headers=auth, json={"meal_types": ["abend"], "plan_days": [0, 1, 2]})
    h = db.query(Household).one()
    fav = Recipe(household_id=h.id, source="manual", title="Omas Gulasch", meal_type="abend", servings=2,
                 prep_minutes=60, ingredients=[{"name": "Rindfleisch", "amount": 500, "unit": "g"}], steps=["kochen"])
    db.add(fav)
    db.commit()
    client.post(f"/recipes/{fav.id}/favorite", headers=auth)
    asked = []
    monkeypatch.setattr(planner, "ask_cards", fake_cards(asked))
    cards = client.post("/swipe", headers=auth).json()["cards"]
    assert sorted(n for _, n, _ in asked) == [2, 3] and len(cards) == 6  # 2 × 3 Plätze, eins das eigene Rezept
    assert cards[1]["title"] == "Omas Gulasch" and cards[1]["source"] == "rezept" and cards[1]["recipe_id"] == fav.id


def test_deck_need_progress_and_cards(deck):
    body, asked = deck
    assert body["need"] == {"fruehstueck": 3, "abend": 3}
    assert sorted((m, n) for m, n, _ in asked) == [("abend", 3)] * 2 + [("fruehstueck", 3)] * 2  # Pakete à 3
    assert len({re.search(r"Schwerpunkt: ([^(]+)", t).group(1) for m, _, t in asked if m == "abend"}) == 2
    assert "Angebote dieser Woche" not in asked[0][2] and "Zu planende Mahlzeiten" not in asked[0][2]
    assert len(body["cards"]) == 12 and body["cards"][0]["meal_type"] == "fruehstueck"
    assert body["have"] == {"fruehstueck": 0, "abend": 0} and not body["ready"] and not body["loading"]


def test_two_members_match_and_dislike_removes_for_all(client, auth, db, deck):
    body, _ = deck
    other = member2(client, auth)
    abend = [c for c in body["cards"] if c["meal_type"] == "abend"]
    a, b, c = abend[0]["id"], abend[1]["id"], abend[2]["id"]
    assert client.post(f"/swipe/cards/{a}/vote", headers=auth, json={"vote": "ja"}).json()["match"] is False
    assert client.post(f"/swipe/cards/{a}/vote", headers=other, json={"vote": "ja"}).json()["match"] is True
    client.post(f"/swipe/cards/{b}/vote", headers=auth, json={"vote": "ja"})
    client.post(f"/swipe/cards/{b}/vote", headers=other, json={"vote": "mag_nicht", "reason": "schmeckt_nicht"})
    client.post(f"/swipe/cards/{c}/vote", headers=other, json={"vote": "mag_nicht", "reason": "keine_lust"})
    mine = client.get("/swipe", headers=auth).json()
    assert [x["id"] for x in mine["chosen"]] == [a] and mine["chosen"][0]["match"]
    assert c in [x["id"] for x in mine["cards"]]  # „Keine Lust“ gilt nur für die andere Person
    assert mine["members"] == ["J", "S"]
    h = db.query(Household).one()
    assert abend[1]["title"] in recipes.planner_memory(db, h.id)["never"]  # KI-Karte auf der Nie-Liste


def test_dislike_ingredient_goes_to_household_list(client, auth, db, deck):
    body, _ = deck
    cid = body["cards"][0]["id"]
    client.post(f"/swipe/cards/{cid}/vote", headers=auth, json={"vote": "mag_nicht", "reason": "zutat",
                                                                "ingredient": "Linsen"})
    assert "Linsen" in client.get("/household", headers=auth).json()["excluded_ingredients"]
    assert cid not in [c["id"] for c in client.get("/swipe", headers=auth).json()["cards"]]


def test_breakfast_days_fill_progress_ready_and_refill(client, auth, db, deck):
    body, asked = deck
    breakfast = [c for c in body["cards"] if c["meal_type"] == "fruehstueck"]
    r = client.post(f"/swipe/cards/{breakfast[0]['id']}/vote", headers=auth, json={"vote": "ja", "days": 3}).json()
    assert r["have"]["fruehstueck"] == 3 and not r["ready"]
    for c in [c for c in body["cards"] if c["meal_type"] == "abend"][:3]:
        r = client.post(f"/swipe/cards/{c['id']}/vote", headers=auth, json={"vote": "ja"}).json()
    assert r["ready"]
    for c in [c for c in body["cards"] if c["meal_type"] == "abend"][3:5]:
        client.post(f"/swipe/cards/{c['id']}/vote", headers=auth, json={"vote": "nein"})
    assert len(asked) == 6  # bei 4 offenen Abend-Karten nachgeladen (2 Pakete), danach (genug gewählt) nicht mehr
    before = len(client.get("/swipe", headers=auth).json()["cards"])
    assert len(client.post("/swipe/undo", headers=auth).json()["cards"]) == before + 1


def test_refill_when_type_runs_low(client, auth, db, deck):
    body, asked = deck
    abend = [c for c in body["cards"] if c["meal_type"] == "abend"]
    for c in abend[:2]:
        client.post(f"/swipe/cards/{c['id']}/vote", headers=auth, json={"vote": "nein"})
    assert [m for m, _, _ in asked[4:]] == ["abend", "abend"]  # 4 offen < 5 → nachladen
    assert abend[0]["title"] in asked[4][2]  # keine Dubletten im Stapel
    assert len(client.get("/swipe", headers=auth).json()["cards"]) == 16


def test_distribute_keeps_fixed_and_puts_fish_early():
    cards = [SwipeCard(id=i, meal_type="abend", title=f"G{i}", protein=p, side="andere", cuisine=f"k{i}",
                       cost_cents=100, position=i, ingredients=[]) for i, p in
             enumerate(["vegetarisch", "vegetarisch", "fisch", "vegetarisch"], start=1)]
    cards += [SwipeCard(id=10, meal_type="fruehstueck", title="Müsli", position=10, cost_cents=50, ingredients=[]),
              SwipeCard(id=11, meal_type="fruehstueck", title="Rührei", position=11, cost_cents=80, ingredients=[])]
    from app.models import SwipeVote
    votes = [SwipeVote(card_id=c.id, member_id=1, vote="ja", days=2 if c.id == 10 else 1) for c in cards]
    t = swipe.tally(cards, votes)
    slots = [(d, m) for d in range(3) for m in ("fruehstueck", "abend")]
    rules = variety.rules_of({"min_fish": 0, "veggie_days": 0})
    assign, reserve = swipe.distribute(t, slots, {(2, "abend"): 1}, rules, True, seed=1)
    assert assign[(2, "abend")] == 1 and assign[(0, "abend")] == 3  # fest bleibt, Fisch zuerst
    assert [assign[(d, "fruehstueck")] for d in range(3)] == [10, 10, 11]  # Müsli 2× am Stück, dann Rührei
    assert reserve == [4]
    assert swipe.distribute(t, slots, {}, rules, True, seed=5) == swipe.distribute(t, slots, {}, rules, True, seed=5)


def test_finish_writes_recipes_for_chosen_cards_and_builds_plan(client, auth, db, deck, monkeypatch):
    body, _ = deck
    h = db.query(Household).one()
    own = Recipe(household_id=h.id, source="manual", title="Porridge", meal_type="fruehstueck", servings=1,
                 prep_minutes=5, ingredients=[{"name": "Haferflocken", "amount": 60, "unit": "g"}], steps=["kochen"])
    db.add(own)
    db.flush()
    db.add(SwipeCard(deck_id=body["id"], meal_type="fruehstueck", position=99, source="rezept", recipe_id=own.id,
                     title="Porridge", ingredients=[]))
    db.commit()
    cards = client.get("/swipe", headers=auth).json()["cards"]
    porridge = next(c for c in cards if c["title"] == "Porridge")
    client.post(f"/swipe/cards/{porridge['id']}/vote", headers=auth, json={"vote": "ja", "days": 3})
    for c in [c for c in cards if c["meal_type"] == "abend"][:3]:
        client.post(f"/swipe/cards/{c['id']}/vote", headers=auth, json={"vote": "ja"})
    dist = client.post("/swipe/distribute", headers=auth, json={}).json()
    assert len(dist["assignment"]) == 6
    seen = []

    def fake_ask(prompt):
        text = prompt[-1]["text"]
        seen.append(text)
        fixed = re.findall(r"- day=(\d) \(\w+\), meal_type=(\w+): (.+?) –", text)
        return PlanDraft(meals=[meal(int(d), t, [ing("Linsen", 200)], m) for d, m, t in fixed]), {"cost_cents": 0.3}

    monkeypatch.setattr(planner, "ask_claude", fake_ask)
    bad = client.post("/swipe/finish", headers=auth, json={"assignment": dist["assignment"][:5]})
    assert bad.status_code == 422
    r = client.post("/swipe/finish", headers=auth, json={"assignment": dist["assignment"]})
    assert r.status_code == 202 and client.get("/plans/job", headers=auth).json()["state"] == "done", \
        client.get("/plans/job", headers=auth).json()
    plan = client.get("/plans/current", headers=auth).json()
    titles = {(e["day"], e["meal_type"]): e["recipe"]["title"] for e in plan["entries"]}
    assert [titles[(d, "fruehstueck")] for d in range(3)] == ["Porridge"] * 3
    assert {titles[(d, "abend")] for d in range(3)} == {c["title"] for c in cards if c["meal_type"] == "abend"
                                                         and c["id"] in {a["card_id"] for a in dist["assignment"]}}
    assert len(seen) == 1 and "Diese Gerichte stehen fest" in seen[0] and "fruehstueck" not in seen[0].split(
        "Diese Gerichte stehen fest")[1]
    assert client.get("/swipe", headers=auth).status_code == 404  # Stapel fertig
    lst = client.get("/lists", headers=auth).json()[0]["id"]
    assert any(i["name"] == "Haferflocken" for i in client.get(f"/lists/{lst}", headers=auth).json()["items"])
