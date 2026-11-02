"""Rezept-Import (5): Instagram-Beitrag (öffentliche Einbettungsseite, ohne Login) oder Webseite (schema.org/Recipe
als JSON-LD, sonst Seitentext) → Haiku macht daraus ein strukturiertes Rezept in den Einheiten des API-Vertrags."""
import html
import json
import re
import threading
import time
from collections.abc import Callable
from dataclasses import dataclass, field
from typing import Literal
from urllib.parse import urljoin, urlsplit, urlunsplit

import httpx
from pydantic import BaseModel

from app.services import food_map

HEADERS = {"User-Agent": "Mozilla/5.0 (compatible; Essenapp/0.1; privat)", "Accept-Language": "de-DE,de;q=0.9"}
TIMEOUT = 10
CACHE_SECONDS = 3600
MAX_TEXT = 15000  # shortcut: Seitentext ohne JSON-LD wird gekürzt (Navigation/Fußzeile); bei Bedarf Hauptinhalt suchen
INSTAGRAM = re.compile(r"^https?://(?:www\.|m\.)?instagram\.com/(?:[\w.]+/)?(p|reels?|tv)/([\w-]+)", re.I)
CAPTION = re.compile(r'<div class="Caption">(.*?)(?:<div class="CaptionComments">|</div>)', re.S)
CAPTION_USER = re.compile(r'<a class="CaptionUsername"[^>]*>([^<]*)</a>')
USERNAME = re.compile(r'<span class="UsernameText">([^<]+)</span>')
MEDIA_IMAGE = re.compile(r'<img class="EmbeddedMediaImage"[^>]*?\ssrc="([^"]+)"')
JSON_LD = re.compile(r'<script[^>]*type=["\']application/ld\+json["\'][^>]*>(.*?)</script>', re.S | re.I)
LD_KEYS = ("name", "description", "recipeYield", "prepTime", "cookTime", "totalTime", "recipeCuisine",
           "recipeCategory", "keywords", "recipeIngredient", "recipeInstructions")


class NoRecipe(Exception):
    """Beitrag/Seite enthält kein Rezept (A2: klare Meldung, kein Screenshot-Ersatz). usage: Verbrauch, falls die KI
    schon gefragt wurde (Kosten trotzdem protokollieren)."""

    def __init__(self, usage: dict | None = None):
        super().__init__("Kein Rezept gefunden")
        self.usage = usage


class ImportIngredient(BaseModel):
    name: str
    amount: float
    unit: Literal["g", "kg", "ml", "l", "stk", "el", "tl", "prise"]
    estimated: bool  # Menge stand nicht im Text, von der KI geschätzt


class ImportedRecipe(BaseModel):
    is_recipe: bool
    title: str
    description: str
    servings: int
    prep_minutes: int
    cuisine: str
    meal_type: Literal["fruehstueck", "mittag", "abend", "dessert"]
    tags: list[str]
    ingredients: list[ImportIngredient]
    steps: list[str]
    image_query: str


PROMPT = """Lies das Rezept aus dem folgenden Inhalt ({kind}) und gib es strukturiert auf Deutsch zurück.
- is_recipe=false, wenn keine Zutaten des Gerichts genannt sind (z.B. nur „Rezept im Link/in der Bio“) – nichts erfinden.
- Zutaten: deutscher Name ohne Menge, amount + unit (g, kg, ml, l, stk, el, tl, prise). Cups/oz/lb umrechnen.
  Fehlt eine Menge, schätze sie für die Portionen und setze estimated=true; sonst estimated=false.
- servings: Portionen laut Text, sonst schätzen. prep_minutes: gesamte Zeit in Minuten, sonst schätzen.
- steps: kurze, konkrete Schritte in der Reihenfolge des Originals; fehlen sie, aus dem Text ableiten.
- title kurz (ohne Emojis/Hashtags), description 1 Satz, cuisine (z.B. italienisch), meal_type passend,
  tags: 1–5 kurze Stichwörter (z.B. vegetarisch, schnell), image_query: 2–4 englische Suchbegriffe für ein Foto.

Inhalt:
{content}"""


@dataclass
class Found:
    recipe: ImportedRecipe
    source: str  # instagram | web
    author: str
    image_url: str
    usage: dict = field(default_factory=dict)


def canonical(url: str) -> str:
    """Instagram: https://www.instagram.com/<p|reel|tv>/<code>/ (ohne Tracking); sonst URL ohne Fragment und utm_*."""
    if m := INSTAGRAM.match(url):
        kind = "reel" if m[1].lower().startswith("reel") else m[1].lower()
        return f"https://www.instagram.com/{kind}/{m[2]}/"
    parts = urlsplit(url)
    query = "&".join(q for q in parts.query.split("&") if q and not q.lower().startswith(("utm_", "fbclid", "gclid")))
    return urlunsplit((parts.scheme, parts.netloc.lower(), parts.path, query, ""))


_cache: dict[str, tuple[float, str]] = {}
_lock = threading.Lock()


def fetch(url: str) -> str:
    """Eine Seite schonend laden: Timeout, eigener User-Agent, 1 h im Speicher gecacht (erneuter Import ohne Abruf)."""
    with _lock:
        hit = _cache.get(url)
        if hit and time.time() - hit[0] < CACHE_SECONDS:
            return hit[1]
    r = httpx.get(url, headers=HEADERS, timeout=TIMEOUT, follow_redirects=True)
    r.raise_for_status()
    with _lock:
        if len(_cache) > 100:
            _cache.clear()
        _cache[url] = (time.time(), r.text)
    return r.text


def text_of(fragment: str) -> str:
    fragment = re.sub(r"<br\s*/?>", "\n", fragment, flags=re.I)
    fragment = re.sub(r"</(p|div|li|h\d)>", "\n", fragment, flags=re.I)
    return html.unescape(re.sub(r"<[^>]+>", " ", fragment)).replace("\xa0", " ").strip()


def parse_instagram(page: str) -> dict:
    """Einbettungsseite (/embed/captioned/): Beschreibung, Autor, Vorschaubild ("" wenn nicht vorhanden)."""
    m = CAPTION.search(page)
    caption = text_of(CAPTION_USER.sub("", m[1])) if m else ""
    user = CAPTION_USER.search(page) or USERNAME.search(page)
    image = MEDIA_IMAGE.search(page)
    return {"text": re.sub(r"[ \t]+", " ", caption), "author": f"@{html.unescape(user[1]).strip()}" if user else "",
            "image": html.unescape(image[1]) if image else ""}


def _nodes(data):
    if isinstance(data, list):
        for d in data:
            yield from _nodes(d)
    elif isinstance(data, dict):
        yield data
        yield from _nodes(data.get("@graph", []))


def json_ld_recipe(page: str) -> dict | None:
    """Erstes schema.org/Recipe aus den JSON-LD-Blöcken (auch in @graph oder Listen). Verweise {"@id": …} bei
    image/author werden aufgelöst (z.B. chefkoch.de)."""
    nodes = []
    for m in JSON_LD.finditer(page):
        try:
            nodes += list(_nodes(json.loads(m[1].strip())))
        except ValueError:
            continue
    ids = {n["@id"]: n for n in nodes if isinstance(n.get("@id"), str) and len(n) > 1}

    def resolve(v):
        if isinstance(v, list):
            return [resolve(x) for x in v]
        return ids.get(v["@id"], v) if isinstance(v, dict) and set(v) == {"@id"} else v

    for node in nodes:
        types = node.get("@type", [])
        if "Recipe" in (types if isinstance(types, list) else [types]):
            return node | {k: resolve(node[k]) for k in ("image", "author") if k in node}
    return None


def _first_image(value) -> str:
    if isinstance(value, list):
        return next((u for u in map(_first_image, value) if u), "")
    if isinstance(value, dict):
        return value.get("url") or value.get("contentUrl") or ""
    return value if isinstance(value, str) else ""


def _author(value) -> str:
    if isinstance(value, list):
        return next((a for a in map(_author, value) if a), "")
    if isinstance(value, dict):
        return value.get("name") or ""
    return value if isinstance(value, str) else ""


def page_text(page: str) -> str:
    page = re.sub(r"<(script|style|noscript|svg|nav|footer|header)\b.*?</\1>", " ", page, flags=re.S | re.I)
    return re.sub(r"\s*\n\s*", "\n", re.sub(r"[ \t]+", " ", text_of(page)))[:MAX_TEXT]


def read(url: str, shared_text: str = "", get: Callable[[str], str] | None = None,
         ask: Callable | None = None) -> Found:
    """URL (bereits canonical) → Rezept. Ohne Beschreibung/Rezept → NoRecipe (ohne KI-Aufruf, wenn nichts da ist)."""
    get, ask = get or fetch, ask or food_map.ask_claude
    if m := INSTAGRAM.match(url):
        embed = get(f"https://www.instagram.com/{'reel' if m[1].startswith('reel') else m[1]}/{m[2]}/embed/captioned/")
        post = parse_instagram(embed)
        content = post["text"] or shared_text.strip()  # Text aus dem Teilen-Menü, falls die Einbettung leer ist
        if not content:
            raise NoRecipe
        source, author, image, kind = "instagram", post["author"], post["image"], "Instagram-Beschreibung"
    else:
        page = get(url)
        node = json_ld_recipe(page)
        if node:
            content = json.dumps({k: node[k] for k in LD_KEYS if k in node}, ensure_ascii=False)
            author, image, kind = _author(node.get("author")), _first_image(node.get("image")), "schema.org/Recipe"
        else:
            content, author, image, kind = page_text(page), "", "", "Webseiten-Text"
        if not content.strip():
            raise NoRecipe
        source, image = "web", urljoin(url, image) if image else ""
        author = author or urlsplit(url).netloc.removeprefix("www.")
    recipe, usage = ask(PROMPT.format(kind=kind, content=content), ImportedRecipe)
    if not recipe.is_recipe or not recipe.ingredients:
        raise NoRecipe(usage)
    return Found(recipe, source, author[:100], image, usage)
