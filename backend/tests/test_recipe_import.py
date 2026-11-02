from pathlib import Path

import httpx
import pytest

from app import api
from app.models import AiCost, Recipe
from app.services import food_map, recipe_images, recipe_import
from app.services.recipe_import import ImportedRecipe, ImportIngredient

DATA = Path(__file__).parent / "data"
REAL = Path(__file__).parent / "fixtures" / "sources" / "instagram" / "embed_captioned_C-K40FjSskE.html"
JPEG = b"\xff\xd8\xff\xe0" + b"0" * 50
USAGE = {"model": "claude-haiku-5-5", "cost_cents": 0.05}


def page(name: str) -> str:
    return (DATA / name).read_text(encoding="utf-8")


def pasta(**kw) -> ImportedRecipe:
    return ImportedRecipe(**{
        "is_recipe": True, "title": "One-Pot-Pasta", "description": "Schnell.", "servings": 2, "prep_minutes": 20,
        "cuisine": "italienisch", "meal_type": "abend", "tags": ["pasta", " "], "image_query": "one pot pasta",
        "steps": ["Alles in einen Topf.", "12 Minuten kochen."],
        "ingredients": [ImportIngredient(name="Spaghetti", amount=0.25, unit="kg", estimated=False),
                        ImportIngredient(name="Salz", amount=1, unit="prise", estimated=True)]} | kw)


def test_canonical_urls():
    assert recipe_import.canonical("https://www.instagram.com/reel/ABC_1-x/?igsh=xyz&utm_source=ig") == \
        "https://www.instagram.com/reel/ABC_1-x/"
    assert recipe_import.canonical("https://instagram.com/reels/ABC/") == "https://www.instagram.com/reel/ABC/"
    assert recipe_import.canonical("https://www.instagram.com/koch_xy/p/XYZ") == "https://www.instagram.com/p/XYZ/"
    assert recipe_import.canonical("https://Kueche.example/dal?id=3&utm_medium=x#rezept") == \
        "https://kueche.example/dal?id=3"


def test_parse_instagram_embed():
    post = recipe_import.parse_instagram(page("instagram_embed_recipe.html"))
    assert post["author"] == "@koch_xy" and post["image"] == "https://cdn.example/reel.jpg?stp=dst-jpg&x=1"
    assert post["text"].startswith("One-Pot-Pasta") and "250 g Spaghetti\n1 Dose Tomaten" in post["text"]
    assert "Olivenöl" in post["text"] and "comments" not in post["text"]
    empty = recipe_import.parse_instagram(page("instagram_embed_empty.html"))
    assert empty == {"text": "", "author": "@koch_xy", "image": "https://cdn.example/reel.jpg"}


@pytest.mark.skipif(not REAL.exists(), reason="echte Instagram-Rohdaten nur lokal (tests/fixtures, nicht im Git)")
def test_parse_real_instagram_embed():
    post = recipe_import.parse_instagram(REAL.read_text(encoding="utf-8"))
    assert post["author"] == "@justaddhotsauce" and "newsletter" in post["text"]
    assert post["image"].startswith("https://scontent")


def test_json_ld_recipe_in_graph_and_broken_json():
    node = recipe_import.json_ld_recipe(page("web_jsonld_recipe.html"))
    assert node["name"] == "Roter Linsen-Dal" and len(node["recipeIngredient"]) == 4
    assert recipe_import.json_ld_recipe(page("web_no_recipe.html")) is None


def fake_ask(result, calls):
    def ask(prompt, schema):
        calls.append(prompt)
        assert schema is ImportedRecipe
        return result, USAGE
    return ask


def test_read_instagram_web_and_no_recipe():
    calls, got = [], []

    def get(url):
        got.append(url)
        return {"https://www.instagram.com/reel/ABC/embed/captioned/": page("instagram_embed_recipe.html"),
                "https://www.instagram.com/p/EMPTY/embed/captioned/": page("instagram_embed_empty.html"),
                "https://kueche.example/dal": page("web_jsonld_recipe.html"),
                "https://kueche.example/info": page("web_no_recipe.html")}[url]

    found = recipe_import.read("https://www.instagram.com/reel/ABC/", get=get, ask=fake_ask(pasta(), calls))
    assert (found.source, found.author, found.image_url) == ("instagram", "@koch_xy", "https://cdn.example/reel.jpg?stp=dst-jpg&x=1")
    assert "Instagram-Beschreibung" in calls[0] and "250 g Spaghetti" in calls[0]

    found = recipe_import.read("https://kueche.example/dal", get=get, ask=fake_ask(pasta(), calls))
    assert (found.source, found.author, found.image_url) == ("web", "Anna Beispiel", "https://kueche.example/bilder/dal.jpg")
    assert "schema.org/Recipe" in calls[1] and "200 g rote Linsen" in calls[1] and "Menü" not in calls[1]
    assert "aggregateRating" not in calls[1]  # nur Rezeptfelder an die KI

    with pytest.raises(recipe_import.NoRecipe) as e:  # Seitentext ohne Rezept: KI sagt nein, Kosten bleiben
        recipe_import.read("https://kueche.example/info", get=get, ask=fake_ask(pasta(is_recipe=False), calls))
    assert e.value.usage == USAGE
    assert "Öffnungszeiten" in calls[2] and "var x" not in calls[2] and "color:red" not in calls[2]

    n = len(calls)
    with pytest.raises(recipe_import.NoRecipe) as e:  # leere Einbettung, kein Text → ohne KI-Aufruf
        recipe_import.read("https://www.instagram.com/p/EMPTY/", get=get, ask=fake_ask(pasta(), calls))
    assert e.value.usage is None and len(calls) == n
    found = recipe_import.read("https://www.instagram.com/p/EMPTY/", "Zutaten: 2 Eier, Butter", get=get,
                               ask=fake_ask(pasta(), calls))  # Text aus dem Teilen-Menü
    assert "2 Eier" in calls[-1] and found.author == "@koch_xy"


@pytest.fixture
def web(monkeypatch, tmp_path):
    monkeypatch.setattr(api, "MEDIA", tmp_path)
    pages, calls = {}, []
    monkeypatch.setattr(recipe_import, "fetch", lambda url: pages[url])
    monkeypatch.setattr(recipe_images, "download_jpeg", lambda url, timeout=10: JPEG if "reel.jpg" in url else None)
    return pages, calls


def test_import_endpoint_saves_dedupes_and_logs(client, auth, db, web, monkeypatch, tmp_path):
    pages, calls = web
    pages["https://www.instagram.com/reel/ABC/embed/captioned/"] = page("instagram_embed_recipe.html")
    monkeypatch.setattr(food_map, "ask_claude", fake_ask(pasta(), calls))
    r = client.post("/import", headers=auth, json={"url": "https://www.instagram.com/reel/ABC/?igsh=1"})
    assert r.status_code == 201, r.text
    rec = r.json()
    assert (rec["source"], rec["source_author"], rec["source_url"]) == (
        "instagram", "@koch_xy", "https://www.instagram.com/reel/ABC/")
    assert rec["ingredients"] == [{"name": "Spaghetti", "amount": 250, "unit": "g"},
                                  {"name": "Salz", "amount": 1, "unit": "prise", "estimated": True}]
    assert rec["tags"] == ["pasta"] and rec["step_images"] == ["", ""] and rec["meal_type"] == "abend"
    assert rec["image_url"].startswith(f"/media/recipes/{rec['id']}.jpg?v=")
    assert (tmp_path / "recipes" / f"{rec['id']}.jpg").read_bytes() == JPEG

    again = client.post("/import", headers=auth, json={"url": "https://instagram.com/reel/ABC/?utm_source=x"})
    assert again.status_code == 200 and again.json()["id"] == rec["id"] and len(calls) == 1
    usage = client.get("/usage", headers=auth).json()
    assert usage["by_kind"]["import"] == 0.05 and usage["recent"][0]["kind"] == "import"
    assert [c["id"] for c in client.get("/recipes?filter=importiert", headers=auth).json()] == [rec["id"]]


def test_import_errors(client, auth, db, web, monkeypatch):
    pages, calls = web
    pages["https://kueche.example/info"] = page("web_no_recipe.html")
    monkeypatch.setattr(food_map, "ask_claude", fake_ask(pasta(is_recipe=False), calls))
    r = client.post("/import", headers=auth, json={"url": "https://kueche.example/info"})
    assert r.status_code == 422 and r.json()["detail"] == "Kein Rezept gefunden"
    assert db.query(AiCost).one().kind == "import" and db.query(Recipe).count() == 0

    def down(url):
        raise httpx.ConnectTimeout("weg")
    monkeypatch.setattr(recipe_import, "fetch", down)
    assert client.post("/import", headers=auth, json={"url": "https://kueche.example/x"}).status_code == 502
    assert client.post("/import", headers=auth, json={"url": "kein link"}).status_code == 422


def test_import_web_keeps_external_non_jpeg_image(client, auth, db, web, monkeypatch):
    pages, calls = web
    pages["https://kueche.example/dal"] = page("web_jsonld_recipe.html")
    monkeypatch.setattr(food_map, "ask_claude", fake_ask(pasta(title="Roter Linsen-Dal"), calls))
    rec = client.post("/import", headers=auth, json={"url": "https://kueche.example/dal"}).json()
    assert rec["source"] == "web" and rec["source_author"] == "Anna Beispiel"
    assert rec["image_url"] == "https://kueche.example/bilder/dal.jpg"  # kein JPEG geladen → externe URL
