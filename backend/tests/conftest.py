import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.core.db import Base, get_db
from app.main import app


@pytest.fixture
def db():
    engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    Base.metadata.create_all(engine)
    with sessionmaker(engine)() as session:
        yield session


@pytest.fixture
def client(db):
    app.dependency_overrides[get_db] = lambda: db
    yield TestClient(app)
    app.dependency_overrides.clear()


@pytest.fixture
def auth(client):
    """Legt einen Haushalt an und liefert die Auth-Header."""
    token = client.post("/households", json={"name": "Test", "member_name": "J"}).json()["token"]
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture(autouse=True)
def no_image_lookup(monkeypatch, request):
    """API-Tests sollen keine echten Bildsuchen machen (test_recipe_images testet die Suche selbst)."""
    if request.module.__name__.endswith("test_recipe_images"):
        return
    from app.services import recipe_images
    monkeypatch.setattr(recipe_images, "find_image", lambda q: "")


@pytest.fixture(autouse=True)
def no_food_mapping(monkeypatch):
    """Keine KI-Zuordnung im Hintergrund (die liefe gegen die echte DB); test_nutrition testet map_missing selbst."""
    from app.services import food_map
    monkeypatch.setattr(food_map, "map_later", lambda names: None)


@pytest.fixture(autouse=True)
def no_local_env(monkeypatch):
    """Tests unabhängig von backend/.env (z.B. REINSTALL_BASE des Entwicklers)."""
    from app.core.config import settings
    monkeypatch.setattr(settings, "reinstall_base", None)
    monkeypatch.setattr(settings, "fal_key", "")  # sonst starten Schritt-Bilder echte fal.ai-Aufrufe gegen die echte DB
    monkeypatch.setattr(settings, "apns_key_path", "")  # kein echter Push (test_push_jobs setzt eigene Werte)


@pytest.fixture(autouse=True)
def no_real_ai(monkeypatch):
    """Nie echte KI-Aufrufe: jeder Test muss ask_claude ersetzen, sonst schlägt er laut fehl."""
    import anthropic

    def blocked(*a, **kw):
        raise AssertionError("Echter Anthropic-Aufruf im Test")
    monkeypatch.setattr(anthropic, "Anthropic", blocked)


@pytest.fixture(autouse=True)
def no_open_food_facts(monkeypatch):
    """Nie echte Open-Food-Facts-Abrufe (Suche/Barcode); Tests ersetzen labels._get bzw. find selbst."""
    from app.services import labels

    def blocked(*a, **kw):
        raise AssertionError("Echter Open-Food-Facts-Abruf im Test")
    monkeypatch.setattr(labels, "_get", blocked)
    monkeypatch.setattr(labels, "_ean_cache", {})
