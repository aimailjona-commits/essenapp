"""Rezeptfotos (Nutzerentscheidung: erst frei, dann KI): TheMealDB → Openverse → fal.ai FLUX schnell (nur mit FAL_KEY)."""
import json
import logging
import re
import threading
from collections.abc import Callable
from pathlib import Path

import httpx

from app.core.config import settings

logger = logging.getLogger(__name__)
CACHE = Path(__file__).resolve().parents[2] / "image_cache.json"  # backend/image_cache.json, nicht im Git
TIMEOUT = 8
HEADERS = {"User-Agent": "Essenapp/0.1 (privat)"}
FAL_PROMPT = "appetizing overhead photo of {} on a white plate, soft natural light, food photography"
FAL_URL = "https://fal.run/fal-ai/flux/schnell"
# Schritt-Bilder (9): einheitlicher Stil laut Spezifikation, 16:10
STEP_PROMPT = "{title}: {step}. bright overhead food photography, home kitchen, natural light"
STEP_SIZE = {"width": 1024, "height": 640}
FAL_CENTS = 0.3  # fal.ai FLUX schnell: 0,003 $ je angefangenem Megapixel (fal.ai/models/fal-ai/flux/schnell, 02.11.2026)
MAX_DOWNLOAD = 5 * 1024 * 1024
_lock = threading.Lock()


def mealdb(query: str) -> dict | None:
    """Treffer nur, wenn der Titel alle Hauptwörter enthält. Gesucht wird nach dem letzten Wort (meist das Gericht),
    weil die Suche nur Teilstrings des Titels findet ("red lentil dal" → "dal")."""
    words = [w for w in re.findall(r"[a-z]+", query) if len(w) > 2 and w not in ("and", "with", "the")]
    if not words:
        return None
    r = httpx.get("https://www.themealdb.com/api/json/v1/1/search.php", params={"s": words[-1]},
                  headers=HEADERS, timeout=TIMEOUT)
    r.raise_for_status()
    for meal in r.json().get("meals") or []:
        if all(re.search(rf"\b{w}", meal["strMeal"].lower()) for w in words):
            return {"url": meal["strMealThumb"], "credit": "TheMealDB"}
    return None


def openverse(query: str) -> dict | None:
    """Erstes Bild im Quer- oder Quadratformat; attribution ist die Lizenzangabe laut Openverse."""
    r = httpx.get("https://api.openverse.org/v1/images/", headers=HEADERS, timeout=TIMEOUT,
                  params={"q": query, "license_type": "commercial", "page_size": 5})
    r.raise_for_status()
    for img in r.json().get("results") or []:
        if img.get("url") and img.get("width") and img.get("height") and img["width"] >= img["height"]:
            return {"url": img["url"], "credit": img.get("attribution") or ""}
    return None


def fal_generate(prompt: str, timeout: float = TIMEOUT, **params) -> str:
    """fal.ai synchron (POST https://fal.run/<model>, Header "Authorization: Key …"), Antwort images[].url."""
    r = httpx.post(FAL_URL, json={"prompt": prompt, **params},
                   headers={"Authorization": f"Key {settings.fal_key}"}, timeout=timeout)
    r.raise_for_status()
    return r.json()["images"][0]["url"]


def fal(query: str) -> dict | None:
    return {"url": fal_generate(FAL_PROMPT.format(query)), "credit": "KI-generiert (FLUX.1 schnell)"}


def _load() -> dict:
    return json.loads(CACHE.read_text(encoding="utf-8")) if CACHE.exists() else {}


def find_image(query: str) -> str:
    """Bild-URL zur englischen Suchanfrage oder "" (auch bei Fehlern). Treffer werden je Anfrage gecacht."""
    key = " ".join(query.lower().split())
    if not key:
        return ""
    with _lock:
        if key in (cache := _load()):
            return cache[key]["url"]
    # shortcut: Fehlschläge werden nicht gecacht (sonst bliebe ein Gericht nach FAL_KEY oder Netzfehler ohne Bild)
    for source in (mealdb, openverse, fal) if settings.fal_key else (mealdb, openverse):
        try:
            hit = source(key)
        except Exception as e:  # Bildsuche darf den Plan nie verhindern
            logger.warning("Bildsuche %s(%r) fehlgeschlagen: %s", source.__name__, key, e)
            continue
        if hit:
            with _lock:
                cache = _load()
                cache[key] = hit
                CACHE.write_text(json.dumps(cache, ensure_ascii=False, indent=1), encoding="utf-8")
            return hit["url"]
    return ""


def download_jpeg(url: str, timeout: float = 10) -> bytes | None:
    """Bild laden; nur JPEG bis 5 MB, sonst None."""
    r = httpx.get(url, headers=HEADERS, timeout=timeout, follow_redirects=True)
    r.raise_for_status()
    raw = r.content
    return raw if raw.startswith(b"\xff\xd8\xff") and len(raw) <= MAX_DOWNLOAD else None


# --- KI-Bild pro Rezeptschritt (9) ---

def make_step_images(db, recipe, media: Path, generate: Callable[..., str] | None = None) -> int:
    """Fehlende Schritt-Bilder erzeugen und unter media/steps/<id>/<n>.jpg speichern (n ab 1). Vorhandene Bilder
    (Spalte oder Datei) werden nie neu erzeugt. Nach jedem Bild gespeichert, damit die App den Fortschritt sieht."""
    from app.services.planner import log_cost  # planner importiert dieses Modul
    generate = generate or fal_generate
    folder = media / "steps" / str(recipe.id)
    images = [*(recipe.step_images or []), *[""] * len(recipe.steps)][:len(recipe.steps)]
    made = 0
    for n, step in enumerate(recipe.steps, 1):
        if images[n - 1]:
            continue
        path = folder / f"{n}.jpg"
        if not path.exists():
            url = generate(STEP_PROMPT.format(title=recipe.title, step=step), timeout=60, image_size=STEP_SIZE,
                           output_format="jpeg")
            log_cost(db, recipe.household_id, "step_image", FAL_CENTS, "fal-ai/flux/schnell", f"Rezept {recipe.id}/{n}")
            raw = download_jpeg(url, timeout=30)
            if raw is None:
                db.commit()
                raise RuntimeError(f"Schritt-Bild {n} ist kein JPEG")
            folder.mkdir(parents=True, exist_ok=True)
            path.write_bytes(raw)
            made += 1
        images[n - 1] = f"/media/steps/{recipe.id}/{n}.jpg"
        recipe.step_images = list(images)
        db.commit()
    return made


_steps_running: set[int] = set()


def _steps_run(recipe_id: int, media: Path) -> None:
    from app.core.db import SessionLocal
    from app.models import Recipe
    try:
        with SessionLocal() as db:
            if recipe := db.get(Recipe, recipe_id):
                logger.info("Schritt-Bilder Rezept %s: %s neu", recipe_id, make_step_images(db, recipe, media))
    except Exception:
        logger.exception("Schritt-Bilder Rezept %s fehlgeschlagen", recipe_id)
    finally:
        with _lock:
            _steps_running.discard(recipe_id)


def step_images_later(recipe_id: int, media: Path) -> bool:
    """Erzeugung im Hintergrund starten; False, wenn für dieses Rezept schon eine läuft (nie doppelt)."""
    with _lock:
        if recipe_id in _steps_running:
            return False
        _steps_running.add(recipe_id)
    threading.Thread(target=_steps_run, args=(recipe_id, media), name="step_images", daemon=True).start()
    return True


def steps_pending(recipe_id: int) -> bool:
    with _lock:
        return recipe_id in _steps_running
