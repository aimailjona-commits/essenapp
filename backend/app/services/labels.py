"""Bio, vegan, Nutri-Score (49) und Barcode-Abfrage (27). Quellen: Prospekttext (Titel/Beschreibung) und Open Food Facts
(ODbL, Daten am product gecacht). Lieber kein Badge als ein falsches: OFF zählt nur bei sicherem Treffer.
API: openfoodfacts.github.io/openfoodfacts-server/api/ – Produkt 15 Abrufe/min, Suche 10/min je IP."""
import logging
import re
import time
from datetime import datetime
from difflib import SequenceMatcher

import httpx

from app.models import Offer, Product
from app.services.prices import norm

log = logging.getLogger(__name__)
HEADERS = {"User-Agent": "Essenapp/0.1 (privat)", "Accept-Language": "de-DE"}
PRODUCT_URL = "https://world.openfoodfacts.org/api/v2/product/{}.json"
SEARCH_URL = "https://search.openfoodfacts.org/search"
FIELDS = "code,product_name,product_name_de,brands,nutriscore_grade,labels_tags,image_front_url,quantity"
SEARCH_PAUSE = 6.5  # s zwischen Suchen (Limit 10/min)
SIMILAR = 0.8  # sicherer Treffer laut Spezifikation
FOOD = ("fleisch_fisch", "obst_gemuese", "kuehlung", "vorrat", "sonstiges", "getraenke")

# EU-Bio-Siegel-Pflichttext („DE-ÖKO-001“), „aus kontrolliert biologischem Anbau“, Wort „Bio“ (auch „Bio-Joghurt“,
# nicht „Bio-Baumwolle“ – Textilien stehen bei kaufDA teils unter „sonstiges“)
BIO = re.compile(r"\bbio\b(?![-\s]*(baumwolle|cotton))|\bbioland\b|\bdemeter\b|\bnaturland\b|ö[kc]o-\d{3}|kontrolliert biologisch|ökologische[mrn]? (anbau|landwirtschaft)", re.I)
VEGAN = re.compile(r"\bvegan", re.I)
TEXTILE = re.compile(r"baumwolle|cotton|polyamid|elasthan|polyester|viskose", re.I)  # Kleidung unter „sonstiges“
VEGGIE = re.compile(r"\bvegetarisch|\bveggie\b", re.I)


def offer_text(o: Offer) -> str:
    """Titel, Marke und Beschreibung aus den Rohdaten (kaufDA: products[].description bzw. description)."""
    raw = o.raw or {}
    desc = raw.get("description") if isinstance(raw.get("description"), str) else ""
    for p in raw.get("products") or []:
        desc += " " + " ".join(d.get("paragraph") or "" for d in p.get("description") or [])
    return f"{o.title} {o.brand} {desc}"


def flags(o: Offer, p: Product | None) -> dict:
    """{bio, vegan, vegetarian, nutri_score, label_sources} für ein Angebot."""
    text = offer_text(o)
    food = o.category in FOOD and not TEXTILE.search(text)
    t_bio, t_vegan = food and bool(BIO.search(text)), food and bool(VEGAN.search(text))
    t_veggie = food and (t_vegan or bool(VEGGIE.search(text)))
    off = p is not None and bool(p.off_code)
    out = {"bio": t_bio or (off and p.off_bio), "vegan": t_vegan or (off and p.off_vegan),
           "vegetarian": t_veggie or (off and (p.off_vegetarian or p.off_vegan)),
           "nutri_score": p.nutri_score.upper() if off and p.nutri_score else None,
           "off_code": p.off_code if off else ""}
    sources = []
    if t_bio or t_vegan or t_veggie:
        sources.append("Prospekttext")
    if off and (out["nutri_score"] or p.off_bio or p.off_vegan or p.off_vegetarian):
        sources.append("Open Food Facts (ODbL)")
    return out | {"label_sources": sources}


def _get(url: str, **params) -> dict:
    r = httpx.get(url, params=params, headers=HEADERS, timeout=15)
    if r.status_code in (403, 429, 503):
        raise RuntimeError(f"Open Food Facts blockt ({r.status_code})")
    r.raise_for_status()
    return r.json()


def _facts(hit: dict) -> dict:
    tags = set(hit.get("labels_tags") or [])
    grade = (hit.get("nutriscore_grade") or "").lower()
    brands = hit.get("brands") or ""
    return {"code": str(hit.get("code") or ""), "name": (hit.get("product_name_de") or hit.get("product_name") or "").strip(),
            "brand": (brands[0] if isinstance(brands, list) else brands.split(",")[0]).strip() if brands else "",
            "image_url": hit.get("image_front_url") or "", "nutri_score": grade if grade in "abcde" and grade else None,
            "bio": bool(tags & {"en:organic", "en:eu-organic", "de:bio"}), "vegan": "en:vegan" in tags,
            "vegetarian": "en:vegetarian" in tags}


_ean_cache: dict[str, dict | None] = {}


def by_ean(ean: str) -> dict | None:
    """Barcode → {code, name, brand, image_url, nutri_score, bio, vegan, vegetarian} oder None (nicht gefunden)."""
    if ean not in _ean_cache:
        data = _get(PRODUCT_URL.format(ean), fields=FIELDS)
        _ean_cache[ean] = _facts(data["product"]) if data.get("status") == 1 and data.get("product") else None
    return _ean_cache[ean]


def secure_match(product: Product, hits: list[dict]) -> dict | None:
    """Sicherer Treffer: Marke stimmt, „Marke Name“ ≥ 0,8 ähnlich; mehrere sichere Treffer mit unterschiedlichem
    Nutri-Score → keiner (lieber kein Badge als ein falsches)."""
    brand = norm(product.brand)
    if not brand:
        return None
    want = norm(f"{product.brand} {product.title}")
    good = []
    for h in map(_facts, hits):
        names = {norm(h["name"]), norm(f"{h['brand']} {h['name']}")}
        if brand in norm(h["brand"]) and any(SequenceMatcher(None, want, n).ratio() >= SIMILAR or
                                             SequenceMatcher(None, norm(product.title), n).ratio() >= SIMILAR
                                             for n in names if n):
            good.append(h)
    if not good or len({h["nutri_score"] for h in good}) > 1:
        return None
    return good[0]


def search(product: Product) -> dict | None:
    data = _get(SEARCH_URL, q=f"{product.brand} {product.title}", langs="de", page_size=10, fields=FIELDS)
    return secure_match(product, data.get("hits") or [])


def enrich(products: list[Product], limit: int = 30, pause: float = SEARCH_PAUSE, find=None) -> int:
    """OFF-Suche für noch nicht geprüfte Produkte mit Marke (höchstens limit je Lauf, Pause wegen Rate-Limit).
    Gibt die Zahl sicherer Treffer zurück; abgebrochen wird bei Sperre/Netzfehler (Rest beim nächsten Lauf)."""
    find = find or search
    found = 0
    for i, p in enumerate([p for p in products if p.off_checked_at is None and p.brand][:limit]):
        if i and pause:
            time.sleep(pause)
        try:
            hit = find(p)
        except (httpx.HTTPError, RuntimeError) as e:
            log.warning("Open Food Facts: %s", e)
            break
        p.off_checked_at = datetime.now()
        if hit:
            found += 1
            p.off_code, p.nutri_score = hit["code"][:20], hit["nutri_score"]
            p.off_bio, p.off_vegan, p.off_vegetarian = hit["bio"], hit["vegan"], hit["vegetarian"]
    return found
