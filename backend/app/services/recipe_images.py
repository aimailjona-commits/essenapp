"""Rezeptfotos (Nutzerentscheidung: erst frei, dann KI): TheMealDB → Openverse → fal.ai FLUX schnell (nur mit FAL_KEY)."""
import json
import logging
import re
import threading
from pathlib import Path

import httpx

from app.core.config import settings

logger = logging.getLogger(__name__)
CACHE = Path(__file__).resolve().parents[2] / "image_cache.json"  # backend/image_cache.json, nicht im Git
TIMEOUT = 8
HEADERS = {"User-Agent": "Essenapp/0.1 (privat)"}
FAL_PROMPT = "appetizing overhead photo of {} on a white plate, soft natural light, food photography"
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


def fal(query: str) -> dict | None:
    """fal.ai synchron (POST https://fal.run/<model>, Header "Authorization: Key …"), Antwort images[].url."""
    r = httpx.post("https://fal.run/fal-ai/flux/schnell", json={"prompt": FAL_PROMPT.format(query)},
                   headers={"Authorization": f"Key {settings.fal_key}"}, timeout=TIMEOUT)
    r.raise_for_status()
    return {"url": r.json()["images"][0]["url"], "credit": "KI-generiert (FLUX.1 schnell)"}


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
