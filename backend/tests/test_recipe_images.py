import httpx
import pytest

from app.services import planner, recipe_images
from app.services.planner import PlanDraft, PlannedMeal, PricedPlan

MEALDB = "https://www.themealdb.com/api/json/v1/1/search.php"
OPENVERSE = "https://api.openverse.org/v1/images/"
FAL = "https://fal.run/fal-ai/flux/schnell"


@pytest.fixture
def web(monkeypatch, tmp_path):
    """Gemockte HTTP-Antworten je URL (Antwort-Formate wie live am 02.11.2026 bzw. laut API-Schema)."""
    monkeypatch.setattr(recipe_images, "CACHE", tmp_path / "image_cache.json")
    monkeypatch.setattr(recipe_images.settings, "fal_key", "")
    answers, calls = {}, []

    def respond(method, url, params=None, json=None, **_):
        calls.append((url, params or json))
        body = answers.get(url)
        if isinstance(body, Exception):
            raise body
        return httpx.Response(200, json=body, request=httpx.Request(method, url))

    monkeypatch.setattr(httpx, "get", lambda url, **kw: respond("GET", url, **kw))
    monkeypatch.setattr(httpx, "post", lambda url, **kw: respond("POST", url, **kw))
    return answers, calls


def test_mealdb_needs_all_main_words_then_cache(web):
    answers, calls = web
    answers[MEALDB] = {"meals": [{"strMeal": "Dal fry", "strMealThumb": "https://mealdb/dal.jpg"},
                                 {"strMeal": "Red Lentils Dal", "strMealThumb": "https://mealdb/red.jpg"}]}
    assert recipe_images.find_image("Red Lentil  Dal") == "https://mealdb/red.jpg"
    assert calls == [(MEALDB, {"s": "dal"})]
    assert recipe_images.find_image("red lentil dal") == "https://mealdb/red.jpg"  # aus dem Cache
    assert len(calls) == 1


def test_openverse_takes_first_landscape_image(web):
    answers, calls = web
    answers[MEALDB] = {"meals": None}
    answers[OPENVERSE] = {"result_count": 3, "results": [
        {"url": "https://ov/tall.jpg", "width": 600, "height": 900},
        {"url": "https://ov/nosize.jpg", "width": None, "height": None},
        {"url": "https://ov/wide.jpg", "width": 1024, "height": 768, "attribution": "Foto von X, CC BY 2.0"}]}
    assert recipe_images.find_image("chicken tikka masala") == "https://ov/wide.jpg"
    assert calls[1] == (OPENVERSE, {"q": "chicken tikka masala", "license_type": "commercial", "page_size": 5})
    assert recipe_images._load()["chicken tikka masala"]["credit"] == "Foto von X, CC BY 2.0"


def test_fal_only_with_key_and_errors_give_empty(web, monkeypatch):
    answers, calls = web
    answers[MEALDB] = httpx.ConnectTimeout("zu langsam")
    answers[OPENVERSE] = {"results": []}
    answers[FAL] = {"images": [{"url": "https://fal.media/x.jpg", "width": 1024, "height": 768}]}
    assert recipe_images.find_image("kale stew") == ""  # ohne Key keine KI, Fehlschlag nicht gecacht
    assert [u for u, _ in calls] == [MEALDB, OPENVERSE]

    monkeypatch.setattr(recipe_images.settings, "fal_key", "k")
    assert recipe_images.find_image("kale stew") == "https://fal.media/x.jpg"
    assert calls[-1] == (FAL, {"prompt": "appetizing overhead photo of kale stew on a white plate, "
                                         "soft natural light, food photography"})

    answers[FAL] = {"detail": "kaputt"}  # unerwartete Antwort -> ""
    assert recipe_images.find_image("bean soup") == ""


def test_add_images_parallel_to_meals():
    meals = [PlannedMeal(day=d, meal_type="mittag", title=t, description="", cuisine="", prep_minutes=20, servings=2,
                         ingredients=[], steps=[], image_query=q) for d, t, q in [(0, "Linsen-Dal", "red lentil dal"),
                                                                                   (1, "Eintopf", "")]]
    planned = PricedPlan(PlanDraft(meals=meals), 0, 0, [0, 0])
    assert planner.add_images(planned, find=lambda q: f"img:{q}").images == ["img:red lentil dal", "img:Eintopf"]
    # für Claude Pflichtfeld, im Code mit Default (api.py baut Gerichte aus der DB ohne image_query nach)
    assert "image_query" in PlanDraft.model_json_schema()["$defs"]["PlannedMeal"]["required"]
