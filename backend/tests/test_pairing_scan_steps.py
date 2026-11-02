from datetime import date, datetime, timedelta
from types import SimpleNamespace

import pytest

from app import api
from app.models import AiCost, Food, IngredientMap, Offer, PairingCode, PantryItem, Recipe
from app.services import food_map, pantry_ai, recipe_images
from app.services.pantry_ai import Idea, IdeaIngredient, Ideas, Seen, SeenItem
from tests.test_profiles_pantry import join

JPEG = b"\xff\xd8\xff\xe0" + b"0" * 50
USAGE = {"model": "claude-haiku-5-5", "cost_cents": 0.12}


# --- Kopplungscode (E48) ---

@pytest.fixture(autouse=True)
def fresh_rate_limit():
    api._pair_fails.clear()


def test_pairing_code_gives_revocable_token_for_same_member(client, auth, db):
    r = client.post("/me/pairing-code", headers=auth)
    assert r.status_code == 201 and len(r.json()["code"]) == 6 and r.json()["code"].isdigit()
    paired = client.post("/pair", json={"code": r.json()["code"]})
    assert paired.status_code == 201, paired.text
    body = paired.json()
    assert body["member_id"] == 1 and body["member_name"] == "J" and body["household"]["id"] == 1
    ext = {"Authorization": f"Bearer {body['token']}"}
    assert client.get("/me/profile", headers=ext).json()["member_id"] == 1  # dasselbe Mitglied
    assert client.post("/pair", json={"code": r.json()["code"]}).status_code == 410  # einmalig

    tokens = client.get("/me/tokens", headers=auth).json()
    assert [t["label"] for t in tokens] == ["Teilen-Erweiterung"]
    assert client.delete(f"/me/tokens/{tokens[0]['id']}", headers=join(client, auth)).status_code == 404  # fremd
    assert client.delete(f"/me/tokens/{tokens[0]['id']}", headers=auth).status_code == 204
    assert client.get("/me/profile", headers=ext).status_code == 401  # widerrufen
    assert client.get("/me/profile", headers=auth).status_code == 200  # Haupt-Token unberührt


def test_pairing_errors_expiry_new_code_and_rate_limit(client, auth, db):
    first = client.post("/me/pairing-code", headers=auth).json()["code"]
    second = client.post("/me/pairing-code", headers=auth).json()["code"]
    assert db.query(PairingCode).count() == 1  # neuer Code ersetzt den alten
    if first != second:
        assert client.post("/pair", json={"code": first}).status_code == 404
    db.query(PairingCode).one().expires_at = datetime.now() - timedelta(seconds=1)
    db.commit()
    r = client.post("/pair", json={"code": second})
    assert r.status_code == 410 and r.json()["detail"] == "Code abgelaufen"
    assert client.post("/pair", json={"code": "12a456"}).status_code == 422
    for _ in range(5):
        client.post("/pair", json={"code": "000000" if second != "000000" else "000001"})
    assert client.post("/pair", json={"code": second}).status_code == 429


# --- Kühlschrank-Foto, Vorrat übernehmen, „Was koche ich jetzt?“ (69) ---

def seen(name, **kw):
    return SeenItem(**{"name": name, "amount": None, "unit": "", "location": "kuehlschrank", "category": "kuehlung",
                       "confidence": "hoch", "shelf_life_days": None} | kw)


def test_scan_returns_items_without_saving(client, auth, db, monkeypatch):
    prompts = []

    def ask(content, schema):
        prompts.append(content)
        assert schema is Seen
        return Seen(items=[seen("Eier", amount=6, unit="stk", shelf_life_days=14), seen("Paprika rot", amount=0,
                           unit="stk", category="obst_gemuese", confidence="niedrig"), seen("eier"), seen(" ")]), USAGE

    monkeypatch.setattr(food_map, "ask_claude", ask)
    files = [("files", ("a.jpg", JPEG, "image/jpeg")), ("files", ("b.jpg", JPEG, "image/jpeg"))]
    r = client.post("/pantry/scan", headers=auth, files=files, data={"mode": "gefrierfach"})
    assert r.status_code == 200, r.text
    items = r.json()["items"]
    assert [i["name"] for i in items] == ["Eier", "Paprika rot"]  # Dubletten/Leeres raus
    assert items[0] | {"best_before": None} == {"name": "Eier", "amount": 6, "unit": "stk", "location": "kuehlschrank",
                                                "category": "kuehlung", "confidence": "hoch", "best_before": None}
    assert items[0]["best_before"] == str(date.today() + timedelta(days=14))
    assert items[1]["amount"] is None and items[1]["unit"] == ""  # 0 = unbekannt
    blocks = prompts[0]
    assert [b["type"] for b in blocks] == ["image", "image", "text"] and "Gefrierfach" in blocks[-1]["text"]
    assert blocks[0]["source"]["media_type"] == "image/jpeg"
    assert db.query(PantryItem).filter_by(is_basic=False).count() == 0  # nicht automatisch gespeichert
    assert r.json()["cost_cents"] == 0.12 and db.query(AiCost).one().kind == "scan"

    png = [("files", ("a.png", b"\x89PNG....", "image/png"))]
    assert client.post("/pantry/scan", headers=auth, files=png).status_code == 422
    assert client.post("/pantry/scan", headers=auth, files=files * 3).status_code == 422  # 6 Fotos


def test_bulk_merges_into_pantry(client, auth, db):
    client.post("/pantry", headers=auth, json={"name": "Milch", "amount": 500, "unit": "ml"})
    r = client.post("/pantry/bulk", headers=auth, json=[
        {"name": "milch", "amount": 1000, "unit": "ml", "source": "scan"},
        {"name": "Eier", "amount": 6, "unit": "stk", "source": "scan", "best_before": "2026-11-20"},
        {"name": "Eier", "amount": 4, "unit": "stk", "source": "scan", "best_before": "2026-11-10"},
        {"name": "Salz", "source": "scan"}])
    assert r.status_code == 201, r.text
    by = {p["name"]: p for p in r.json()}
    assert by["Milch"]["amount"] == 1500 and by["Eier"]["amount"] == 10 and by["Eier"]["best_before"] == "2026-11-10"
    assert by["Salz"]["is_basic"] and by["Salz"]["amount"] is None
    assert client.post("/pantry/bulk", headers=auth, json=[]).status_code == 422


def idea(title, ingredients, minutes=20):
    return Idea(title=title, description="", cuisine="deutsch", meal_type="abend", prep_minutes=minutes, servings=2,
                ingredients=[IdeaIngredient(name=n, amount=a, unit=u) for n, a, u in ingredients],
                steps=["Kochen"], image_query="dish")


def test_missing_uses_pantry_basics_and_units():
    pantry = [PantryItem(name="Sahne", ingredient_key="sahne", amount=200, unit="ml", is_basic=False),
              PantryItem(name="Eier", ingredient_key="eier", amount=2, unit="stk", is_basic=False),
              PantryItem(name="Reis", ingredient_key="reis", amount=None, unit="g", is_basic=False),
              PantryItem(name="Öl", ingredient_key="öl", amount=None, unit="", is_basic=True)]
    ings = [{"name": "Sahne", "amount": 100, "unit": "g"}, {"name": "Eier", "amount": 4, "unit": "stk"},
            {"name": "Reis", "amount": 300, "unit": "g"}, {"name": "Olivenöl", "amount": 2, "unit": "el"},
            {"name": "Speck", "amount": 1, "unit": "el"}]
    assert pantry_ai.missing(ings, pantry) == [{"name": "Eier", "amount": 2.0, "unit": "stk"},
                                               {"name": "Speck", "amount": 1.0, "unit": "el"}]


def test_cook_now_three_ideas_by_coverage(client, auth, db, monkeypatch):
    assert client.post("/pantry/cook-now", headers=auth).status_code == 422  # nur Basics
    client.post("/pantry/bulk", headers=auth, json=[{"name": "Eier", "amount": 6, "unit": "stk"},
                                                    {"name": "Spinat", "amount": 300, "unit": "g"}])
    prompts = []

    def ask(prompt, schema):
        prompts.append(prompt)
        assert schema is Ideas
        return Ideas(ideas=[
            idea("Spinat-Omelett mit Feta", [("Eier", 3, "stk"), ("Spinat", 100, "g"), ("Feta", 100, "g")]),
            idea("Spiegelei", [("Eier", 2, "stk"), ("Salz", 1, "prise")]),
            idea("Zu viel fehlt", [("Eier", 1, "stk"), ("Lachs", 200, "g"), ("Dill", 5, "g"), ("Zitrone", 1, "stk")]),
            idea("Shakshuka", [("Eier", 4, "stk"), ("Tomaten", 400, "g"), ("Paprika", 1, "stk")]),
        ]), USAGE

    monkeypatch.setattr(food_map, "ask_claude", ask)
    r = client.post("/pantry/cook-now", headers=auth)
    assert r.status_code == 200, r.text
    out = r.json()
    assert [o["recipe"]["title"] for o in out] == ["Spiegelei", "Spinat-Omelett mit Feta", "Shakshuka"]
    assert out[0]["missing"] == [] and out[1]["missing"] == [{"name": "Feta", "amount": 100, "unit": "g"}]
    assert "Eier 6stk" in prompts[0] and "Salz" in prompts[0] and "30 Minuten" in prompts[0]
    rec = db.get(Recipe, out[0]["recipe"]["id"])
    assert rec.source == "ai" and rec.household_id == 1  # gespeichert → Rezeptdetail / „Heute kochen“
    assert client.get(f"/recipes/{rec.id}", headers=auth).status_code == 200
    assert db.query(AiCost).one().kind == "cook_now"


# --- KI-Bild pro Schritt (9) ---

def test_make_step_images_once_and_logged(db, tmp_path, monkeypatch):
    recipe = Recipe(household_id=None, title="Dal", meal_type="abend", servings=2, prep_minutes=20,
                    steps=["Zwiebel anbraten", "Linsen kochen", "Würzen"])
    db.add(recipe)
    db.commit()
    (tmp_path / "steps" / str(recipe.id)).mkdir(parents=True)
    (tmp_path / "steps" / str(recipe.id) / "3.jpg").write_bytes(JPEG)  # schon da → nicht neu
    calls = []

    def generate(prompt, timeout, **params):
        calls.append((prompt, params))
        return f"https://fal.media/{len(calls)}.jpg"

    monkeypatch.setattr(recipe_images, "download_jpeg", lambda url, timeout=10: JPEG)
    assert recipe_images.make_step_images(db, recipe, tmp_path, generate) == 2
    assert calls[0] == ("Dal: Zwiebel anbraten. bright overhead food photography, home kitchen, natural light",
                        {"image_size": {"width": 1024, "height": 640}, "output_format": "jpeg"})
    assert recipe.step_images == [f"/media/steps/{recipe.id}/{n}.jpg" for n in (1, 2, 3)]
    assert (tmp_path / "steps" / str(recipe.id) / "1.jpg").read_bytes() == JPEG
    assert [c.cost_cents for c in db.query(AiCost)] == [0.3, 0.3]
    assert recipe_images.make_step_images(db, recipe, tmp_path, generate) == 0 and len(calls) == 2  # nie doppelt


def test_step_image_endpoints_setting_and_reset(client, auth, db, monkeypatch, tmp_path):
    monkeypatch.setattr(api, "MEDIA", tmp_path)
    started = []
    monkeypatch.setattr(recipe_images, "step_images_later", lambda rid, media: started.append(rid) or True)
    body = {"title": "Dal", "servings": 2, "prep_minutes": 20, "meal_type": "abend",
            "ingredients": [{"name": "Linsen", "amount": 200, "unit": "g"}], "steps": ["Kochen", "Würzen"]}
    rid = client.post("/recipes", headers=auth, json=body).json()["id"]

    monkeypatch.setattr(api.settings, "fal_key", "")
    assert client.get("/household", headers=auth).json()["step_images_available"] is False
    assert client.post(f"/recipes/{rid}/step-images", headers=auth).status_code == 422
    client.get(f"/recipes/{rid}", headers=auth)
    assert started == []  # ohne FAL_KEY nichts

    monkeypatch.setattr(api.settings, "fal_key", "k")
    h = client.get("/household", headers=auth).json()
    assert h["step_images"] is True and h["step_images_available"] is True
    r = client.post(f"/recipes/{rid}/step-images", headers=auth)
    assert r.status_code == 202 and r.json() == {"step_images": ["", ""], "pending": False}
    assert client.get(f"/recipes/{rid}", headers=auth).json()["step_images"] == ["", ""]
    assert started == [rid, rid]  # beim Öffnen gestartet

    db.get(Recipe, rid).step_images = [f"/media/steps/{rid}/1.jpg", f"/media/steps/{rid}/2.jpg"]
    db.commit()
    client.get(f"/recipes/{rid}", headers=auth)
    assert len(started) == 2  # alles da → nichts mehr erzeugen
    plan_recipe = client.patch(f"/recipes/{rid}", headers=auth, json={"steps": ["Neu", "Anders", "Dritter"]}).json()
    assert plan_recipe["step_images"] == ["", "", ""]  # Schritte geändert → Bilder verworfen
    client.get(f"/recipes/{rid}", headers=auth)
    assert len(started) == 3

    client.patch("/household", headers=auth, json={"step_images": False})
    assert client.post(f"/recipes/{rid}/step-images", headers=auth).status_code == 422
    client.get(f"/recipes/{rid}", headers=auth)
    assert len(started) == 3  # ausgeschaltet → nichts mehr


# --- Nährwerte im Angebotsdetail (2) ---

def test_offer_nutrition_only_when_sure(client, auth, db, monkeypatch):
    mapped = []
    monkeypatch.setattr(food_map, "map_later", lambda names: mapped.extend(names))
    today = date.today()
    db.add_all([Food(id=1, description="Chicken, breast, raw", data_type="foundation", kcal=120, protein=22.5,
                     fat=1.9, carbs=0, fiber=0, sugar=0, salt=0.1),
                IngredientMap(ingredient_key="hähnchenbrustfilet", food_id=1, confidence="hoch"),
                IngredientMap(ingredient_key="wurstsalat", food_id=1, confidence="mittel")])
    for i, (title, cat) in enumerate([("Hähnchenbrustfilet", "fleisch_fisch"), ("Wurstsalat", "kuehlung"),
                                      ("Gouda", "kuehlung"), ("Duschgel", "drogerie")], 1):
        db.add(Offer(id=i, chain="rewe", source_id=str(i), title=title, category=cat, price_cents=399, amount=400,
                     unit="g", valid_from=today, valid_to=today))
    db.commit()
    ok = client.get("/offers/1/nutrition", headers=auth).json()
    assert ok["status"] == "ok" and ok["food"] == "Chicken, breast, raw"
    assert ok["per_100g"]["kcal"] == 120 and ok["per_pack"] == {"kcal": 480, "protein": 90, "carbs": 0, "fat": 7.6,
                                                                 "fiber": 0}
    assert client.get("/offers/2/nutrition", headers=auth).json()["status"] == "none"  # nicht sicher
    assert client.get("/offers/3/nutrition", headers=auth).json()["status"] == "pending" and mapped == ["Gouda"]
    assert client.get("/offers/4/nutrition", headers=auth).json()["status"] == "none" and mapped == ["Gouda"]
    assert client.get("/offers/99/nutrition", headers=auth).status_code == 404
