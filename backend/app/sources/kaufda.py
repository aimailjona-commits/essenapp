"""kaufDA/Bonial-Adapter. Endpunkte und Feldnamen: docs/research/datenquellen.md, Abschnitt 0."""
import re
import time
from datetime import date, datetime
from zoneinfo import ZoneInfo

import httpx

from app.services.normalize import BAG, base_price_cents, cents, euro_to_cents, parse_quantity

CHAINS = {  # kaufDA-Händlername (klein) -> unser chain-Schlüssel
    "rewe": "rewe", "aldi süd": "aldi_sued", "aldi nord": "aldi_nord", "lidl": "lidl",
    "edeka": "edeka", "e center": "edeka", "marktkauf": "edeka", "kaufland": "kaufland",
    "penny": "penny", "netto marken-discount": "netto_md", "dm-drogerie markt": "dm", "rossmann": "rossmann",
}
SEARCH_QUERIES = {"aldi_sued": "ALDI", "dm": "dm-drogerie markt"}  # Prospekt nur über die Suche erreichbar

# Feine Kategorie (19.1) -> grobe Kategorie. Erste passende gewinnt: Spezielles vor Allgemeinem
# („Milchschokolade“ ist Süßes, „Tomatensauce“ Sauce, „Kartoffelchips“ Snack, „Pizza Salami“ Tiefkühl).
SUBCATEGORIES = [
    ("getraenke", "getraenke", ("getränk", "saft", "wasser", "bier", "pils", "wein", "sekt", "cola", "limo", "drink",
                                "schorle", "pfand", "hefeweizen", "spirituose", "likör", "whisky", "wodka", "smoothie")),
    ("suesses", "vorrat", ("schoko", "praline", "keks", "gummi", "bonbon", "riegel", "waffel", "lebkuchen", "kuchen",
                           "marzipan", "spekulatius", "stollen", "dominostein", "eiscreme", "speiseeis", "eis am stiel", "nougat",
                           "creme kugeln", "pistaziencreme", "nusscreme", "nuss-nougat")),
    ("snacks", "vorrat", ("chips", "flips", "cracker", "salzstang", "erdnuss", "nüsse", "nusskerne", "mandeln",
                          "cashew", "studentenfutter", "popcorn")),
    ("saucen", "vorrat", ("sauce", "soße", "ketchup", "mayonnaise", "senf", "dressing", "pesto", "brühe", "fond")),
    ("tiefkuehl", "kuehlung", ("tiefgefroren", "tiefkühl", "pizza", "pommes", "fischstäbchen", "rahmspinat")),
    ("kaese", "kuehlung", ("käse", "gouda", "mozzarella", "feta", "parmesan", "camembert", "emmentaler", "cheddar",
                           "brie", "mascarpone", "ricotta", "halloumi", "grana padano", "burrata")),
    ("joghurt", "kuehlung", ("joghurt", "jogurt", "skyr", "quark", "pudding", "dessert", "kefir", "ayran")),
    ("molkerei", "kuehlung", ("milch", "butter", "sahne", "schmand", "crème fraîche", "margarine", "eier", "gekühlt")),
    ("wurst", "fleisch_fisch", ("wurst", "schinken", "salami", "aufschnitt", "bacon", "speck", "leberkäse")),
    ("fisch", "fleisch_fisch", ("lachs", "fisch", "garnele", "shrimp", "forelle", "hering", "kabeljau", "seelachs",
                                "thunfisch", "matjes")),
    ("fleisch", "fleisch_fisch", ("fleisch", "schwein", "hack", "schnitzel", "gulasch", "steak", "hähnchen",
                                  "chicken", "pute", "rind", "lamm", "braten", "filet", "kotelett", "geschnetzeltes")),
    ("obst", "obst_gemuese", ("obst", "apfel", "äpfel", "banane", "clementine", "mandarine", "orange", "trauben",
                              "birne", "beeren", "kiwi", "mango", "ananas", "zitrone", "limette", "melone")),
    ("gemuese", "obst_gemuese", ("gemüse", "tomate", "kartoffel", "zwiebel", "salat", "paprika", "gurke", "möhre",
                                 "karotte", "zucchini", "brokkoli", "blumenkohl", "kohl", "lauch", "pilz",
                                 "champignon", "spinat", "aubergine", "kürbis", "avocado", "rucola")),
    ("fruehstueck", "vorrat", ("müsli", "cornflakes", "haferflocken", "marmelade", "konfitüre", "honig", "aufstrich")),
    ("brot", "vorrat", ("brot", "brötchen", "toast", "baguette", "croissant", "wraps", "tortilla")),
    ("nudeln_reis", "vorrat", ("nudel", "pasta", "spaghetti", "penne", "fusilli", "reis", "couscous", "bulgur",
                               "gnocchi", "maultasche")),
    ("kaffee_tee", "vorrat", ("kaffee", "espresso", "tee", "cappuccino")),
    ("backen", "vorrat", ("mehl", "zucker", "backpulver", "hefe")),
    ("konserven", "vorrat", ("konserve", "dose", "bohnen", "linsen", "kichererbsen", "mais", "passata",
                             "kokosmilch", "olivenöl", "rapsöl", "sonnenblumenöl", "speiseöl", "essig")),
    ("drogerie", "drogerie", ("shampoo", "dusch", "creme", "pflege", "zahn", "deo", "windel", "schaumbad",
                              "kosmetik")),
    ("haushalt", "haushalt", ("wasch", "spülmittel", "reiniger", "küchenrolle", "toilettenpapier", "müllbeutel",
                              "duft", "kerze", "teelicht", "deko", "vase", "lampe")),
]
# Teilwort-Abgleich, damit Komposita treffen („Rotwein“, „Thunfisch“, „Colorwaschmittel“); reiner Wortanfang verlöre
# die. Stattdessen Wörter, in denen ein Stichwort nur zufällig steckt (gefunden in echten Prospekten 11/2026):
TRAPS = {k: re.compile(v) for k, v in {
    "wein": r"schwein|weinkocher|weintraube|weinbeere|weinessig", "bier": r"bier(?=schinken|wurst|käse)", "cola": r"chocola|rucola|piccola",
    "deo": r"video", "eier": r"freier", "obst": r"grobst", "sekt": r"insekt", "tomate": r"automat",
    "lachs": r"flachs|lachs(?=braten|schinken|kotelett|steak)|lamm-?lachs", "hack": r"gehackt", "fleisch": r"zahnfleisch|fruchtfleisch", "pasta": r"zahnpasta",
    "saft": r"hustensaft|saftig|saftschinken", "wasser": r"spritzwasser|mizellenwasser|meerwasser|wassermelone", "wasch": r"waschbar",
    "kaffee": r"kaffee(?:vollautomat|maschine|becher)", "tee": r"teelicht|steel|tee(?=löffel)",
    "creme": r"(?:eis|nuss|pistazien|gebäck|koch|nougat|schoko)creme",
    "rind": r"rinde", "pute": r"computer", "dose": r"dosier", "kohl": r"kohle", "fond": r"fondue|fondant",
    "lamm": r"flamm", "reis": r"preis|kreis|reise", "käse": r"leberkäse", "milch": r"kokosmilch",
    "eier": r"freier|eier(?=nudel|teig|spätzle)",
}.items()}
_BASE = re.compile(  # "(1 kg = 2.98 €)", "1 l = € 1.38", "12.99/kg", "EUR 2,83 / 1 l", "kg-Preis 4.48"
    r"\b1\s*(?:kg|l|liter)\s*=\s*(?:ab\s*)?€?\s*(\d+[.,]\d+)"
    r"|(\d+[.,]\d+)\s*€?\s*/\s*(?:1\s*)?(?:kg|l|st)\b"
    r"|(?:kg|l)-preis\s*=?\s*(\d+[.,]\d+)", re.I)
_BERLIN = ZoneInfo("Europe/Berlin")
# Rewe-Bonus (39): kaufDA hat kein eigenes Feld, der Betrag steht im Deal-Text („0,20 € Bonus“, „Bonus 0,15€“,
# „… 0,10 € Bonus in der REWE App sammeln“), Typ OTHER oder SALES_PRICE, selten in conditions[].other
_BONUS = re.compile(r"(\d+[.,]\d{1,2})\s*€?\s*Bonus|Bonus\s*(\d+[.,]\d{1,2})\s*€", re.I)

HEADERS = {"User-Agent": "Essenapp/0.1 (privat)", "Accept-Language": "de-DE"}
SHELF_URL = "https://www.kaufda.de/api/shelf"
SEARCH_URL = "https://www.kaufda.de/api/search"
PAGES_URL = "https://content-viewer-be.kaufda.de/v1/brochures/{}/pages"


def chain_of(publisher_name: str | None) -> str | None:
    return CHAINS.get((publisher_name or "").strip().lower())


# Oberste kaufDA-Produktkategorie (products[].categoryPaths[0]); nur hier stecken Lebensmittel. Ohne Pfad (Suche,
# einzelne Angebote) entscheiden die Stichwörter.
FOOD_PATHS = {"Lebensmittel und Getränke", "Marken", "Saison und Events", ""}
DROGERIE_PATH = "Drogerie und Haushalt"


def _match(text: str) -> tuple[str, str] | None:
    text = text.lower()
    return next(((sub, cat) for sub, cat, words in SUBCATEGORIES
                 if any(w in (TRAPS[w].sub(" ", text) if w in TRAPS else text) for w in words)), None)


def classify(chain: str, text: str, path: str = "", title: str = "") -> tuple[str, str]:
    """(grobe Kategorie, feine Kategorie); ohne Treffer ("sonstiges", ""), Nicht-Lebensmittel ("nonfood", "").
    Der Produktname (title) entscheidet vor der Beschreibung (text): „Kochschinken … mit Butter verfeinert“."""
    sub, cat = (title and _match(title)) or _match(text) or ("", "sonstiges")
    if chain in ("dm", "rossmann") or path == DROGERIE_PATH:
        return ("haushalt", "haushalt") if cat == "haushalt" else ("drogerie", "drogerie")
    if path not in FOOD_PATHS:  # Spielzeug, Möbel, Elektronik, Tierfutter …: „Kaffeemühle“ ist kein Kaffee
        return "nonfood", ""
    return cat, sub


def top_path(product: dict) -> str:
    paths = product.get("categoryPaths") or []
    return (paths[0].get("name") or "") if paths else ""


def category_of(chain: str, text: str) -> str:
    return classify(chain, text)[0]


def _day(ts: str) -> date:
    """'2026-11-01T23:00:00.000+0000' -> 2026-11-02 (deutsche Ortszeit)."""
    return datetime.strptime(ts, "%Y-%m-%dT%H:%M:%S.%f%z").astimezone(_BERLIN).date()


def _offer(chain, store_ref, source_id, title, brand, text, price_cents, regular_cents, base_text,
           valid_from, valid_to, image_url, raw, path: str = "") -> dict:
    qty = parse_quantity(text)
    amount, unit = qty if qty else (None, "")
    m = _BASE.search(base_text or "")
    if m and BAG.search(text) and re.search(r"\bl\b|liter", m.group(0), re.I):
        m = None  # Literpreis eines Müllbeutels ist kein Grundpreis
    base = euro_to_cents(next(g for g in m.groups() if g)) if m else base_price_cents(price_cents, amount, unit)
    return {
        "chain": chain, "store_ref": store_ref, "source_id": source_id,
        "title": title[:200], "brand": (brand or "")[:100],
        **dict(zip(("category", "subcategory"), classify(chain, text, path, title))),
        "price_cents": price_cents,
        "regular_price_cents": regular_cents if regular_cents and regular_cents > price_cents else None,
        "amount": amount, "unit": unit, "base_price_cents": base, "ean": "",
        "valid_from": valid_from, "valid_to": valid_to, "image_url": (image_url or "")[:500],
        "ingredient_id": None, "raw": raw, "bonus_cents": None,
    }


def parse_shelf(data: dict) -> list[dict]:
    """Shelf-Antwort -> Prospekte bekannter Händler."""
    out = []
    for item in data.get("contents", []):
        c = item.get("content")
        if item.get("contentType") not in ("brochure", "brochurePremium") or not isinstance(c, dict):
            continue
        chain = chain_of((c.get("publisher") or {}).get("name"))
        if not chain or not c.get("contentId"):
            continue
        out.append({
            "chain": chain, "content_id": c["contentId"],
            "store_id": str((c.get("closestStore") or {}).get("externalId") or ""),
            "store": c.get("closestStore") or {},
            "valid_from": _day(c["validFrom"]), "valid_to": _day(c["validUntil"]),
        })
    return out


def _pick(deals: list[dict], *types: str) -> int | None:
    """Preis des ersten Deals mit passendem Typ (Typen in Vorrangreihenfolge)."""
    for t in types:
        for d in deals:
            if d.get("type") == t and d.get("min"):
                return cents(d["min"] * 100)
    return None


def bonus_cents(deals: list[dict], name: str, names: list[str]) -> int | None:
    """Rewe-Bonus eines Produkts: Deals mit seinem Namen, sonst Deals ohne den Namen eines anderen Produkts."""
    others = [n for n in names if n and n != name]
    for d in deals:
        texts = [d.get("description") or "", *((c or {}).get("other") or "" for c in d.get("conditions") or [])]
        mine = (d.get("description") or "").startswith(name) if name else False
        if not mine and any(t.startswith(o) for t in texts for o in others):
            continue
        for t in texts:
            if m := _BONUS.search(t):
                return euro_to_cents(m.group(1) or m.group(2))
    return None


def parse_pages(data: dict, chain: str, store_ref: str = "") -> list[dict]:
    """Brochure-/pages-Antwort -> Offer-Dicts (ein Dict pro Produkt)."""
    out = []
    for page in data.get("contents", []):
        for item in page.get("offers", []):
            c = item.get("content") or {}
            profiles = c.get("publicationProfiles") or []
            if not profiles:
                continue
            valid_from, valid_to = _day(profiles[0]["validity"]["startDate"]), _day(profiles[0]["validity"]["endDate"])
            if valid_from > valid_to:
                continue  # kommt in den Quelldaten vor (Lidl), Zeitraum unklar
            deals = c.get("deals") or []
            names = [(p.get("name") or "").strip() for p in c.get("products") or []]
            for i, p in enumerate(c.get("products") or []):
                name = (p.get("name") or "").strip()
                # Mehrere Produkte je Angebot: Deals über ihre Beschreibung dem Produkt zuordnen.
                own = [d for d in deals if name and (d.get("description") or "").startswith(name)] or deals
                price = _pick(own, "SALES_PRICE", "SPECIAL_PRICE")
                if not name or not price:
                    continue
                base_text = next((d.get("priceByBaseUnit") for d in own if d.get("priceByBaseUnit")), "")
                desc = " ".join(d.get("paragraph") or "" for d in p.get("description") or [])
                images = p.get("images") or []
                out.append(_offer(
                    chain, store_ref, c["id"] if i == 0 else f"{c['id']}#{i}",
                    name, p.get("brandName"), f"{name} {desc}", price,
                    _pick(own, "REGULAR_PRICE", "RECOMMENDED_RETAIL_PRICE"), base_text,
                    valid_from, valid_to,
                    images[0]["url"] if images else c.get("image"), c, top_path(p),
                ) | {"bonus_cents": bonus_cents(deals, name, names) if chain == "rewe" else None})
    return out


def parse_search(data: dict) -> list[dict]:
    """/api/search-Antwort -> Offer-Dicts. Gültigkeit kommt vom Prospekt (Elternprospekt, sonst Händler)."""
    contents = data.get("searchResults", {}).get("contents", {})
    validity = {}
    for b in contents.get("brochures", []):
        c = b.get("content") or {}
        if c.get("validFrom") and c.get("validUntil"):
            span = (_day(c["validFrom"]), _day(c["validUntil"]))
            validity[c.get("contentId")] = span
            validity.setdefault((c.get("publisher") or {}).get("id"), span)
    out, seen = [], set()
    for o in contents.get("offers", []):
        chain = chain_of(o.get("publisherName"))
        prices = o.get("prices") or {}
        span = validity.get((o.get("parentContent") or {}).get("id")) or validity.get(o.get("publisherId"))
        title = (o.get("title") or "").strip()
        if not chain or not title or not prices.get("mainPrice") or not span or o["id"] in seen:
            continue  # shortcut: ohne bekannte Gültigkeit verworfen, statt Daten zu raten
        seen.add(o["id"])
        price = cents(prices["mainPrice"] * 100)
        regular = cents(prices["secondaryPrice"] * 100) if prices.get("secondaryPrice") else None
        out.append(_offer(
            chain, "", o["id"], title, o.get("brand"), f"{title} {o.get('description') or ''}", price, regular,
            prices.get("priceByBaseUnit"), *span, ((o.get("offerImages") or {}).get("url") or {}).get("large"), o,
        ))
    return out


def _getter(http: httpx.Client):
    def get(url, **params):
        time.sleep(1)
        r = http.get(url, params=params)
        if r.status_code in (403, 429):
            raise RuntimeError(f"kaufDA blockt ({r.status_code}): {url}")
        r.raise_for_status()
        return r.json()
    return get


def _shelf(get, lat: float, lng: float) -> list[dict]:
    brochures, page, pages = [], 0, 1
    while page < pages:
        data = get(SHELF_URL, lat=lat, lng=lng, size=50, page=page, sectorIds="")
        brochures += parse_shelf(data)
        pages, page = data.get("page", {}).get("totalPages", 0), page + 1
    return brochures


def fetch_shelf(lat: float, lng: float) -> list[dict]:
    """Alle Prospekte bekannter Händler am Ort (alle Shelf-Seiten), je mit closestStore."""
    with httpx.Client(headers=HEADERS, timeout=20, follow_redirects=True) as http:
        return _shelf(_getter(http), lat, lng)


def pick_brochures(brochures: list[dict], chains: set[str], stores: set[tuple[str, str]] = frozenset()) -> list[dict]:
    """Je Kette nur die Prospekte einer Filiale: der in stores {(chain, externalId)} gewählten,
    sonst der nächsten (Shelf ist nach Nähe sortiert). Ketten aus SEARCH_QUERIES laufen über die Suche."""
    chosen, nearest, done, out = {c for c, _ in stores}, {}, set(), []
    for b in brochures:
        if b["chain"] not in chains or b["chain"] in SEARCH_QUERIES or b["content_id"] in done:
            continue
        if b["chain"] in chosen:
            own = (b["chain"], b["store_id"]) in stores
        else:
            own = nearest.setdefault(b["chain"], b["store_id"]) == b["store_id"]
        if own:
            done.add(b["content_id"])
            out.append(b)
    return out


def fetch_offers(lat: float, lng: float, chains: set[str], stores: set[tuple[str, str]] = frozenset()) -> list[dict]:
    """Live-Abruf bei kaufDA. Höchstens 1 Anfrage/s; 403/429 und andere Fehler brechen mit Exception ab.
    store_ref = closestStore.externalId des Prospekts; Angebote aus der Suche haben store_ref ""."""
    with httpx.Client(headers=HEADERS, timeout=20, follow_redirects=True) as http:
        get = _getter(http)
        offers = []
        for b in pick_brochures(_shelf(get, lat, lng), chains, stores):
            data = get(PAGES_URL.format(b["content_id"]), partner="kaufda_web", brochureKey="", lat=lat, lng=lng)
            offers += parse_pages(data, b["chain"], b["store_id"])
        for chain, query in SEARCH_QUERIES.items():
            offset, total, known = 0, 1, []
            while chain in chains and offset < total:
                data = get(SEARCH_URL, query=query, lat=lat, lng=lng, offset=offset, limit=24)
                contents = data["searchResults"]["contents"]
                known += contents.get("brochures", [])
                contents["brochures"] = known  # Gültigkeit auch für Folgeseiten ohne Prospektliste
                offers += [o for o in parse_search(data) if o["chain"] == chain]
                total = data["searchResults"]["metadata"]["contentCount"].get("offer", 0)
                offset += 24
    return offers
