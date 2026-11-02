"""Läden in der Nähe für die Kartenauswahl: kaufDA-Shelf (closestStore), OpenStreetMap nur als Ersatz."""
import math
import time

import httpx

from app.sources import kaufda

# Öffentliche Overpass-Instanzen (Hauptserver + offizielle Mirrors); bei Ausfall die nächste probieren.
OVERPASS_URLS = ["https://overpass-api.de/api/interpreter", "https://overpass.kumi.systems/api/interpreter",
                 "https://overpass.private.coffee/api/interpreter"]
# Erste passende Regel gewinnt; gesucht wird im brand-Tag, sonst im name-Tag (klein geschrieben).
CHAIN_RULES = [
    ("aldi süd", "aldi_sued"), ("aldi sued", "aldi_sued"), ("aldi nord", "aldi_nord"),
    ("netto", "netto_md"), ("lidl", "lidl"), ("rewe", "rewe"), ("e center", "edeka"), ("marktkauf", "edeka"),
    ("edeka", "edeka"), ("kaufland", "kaufland"), ("penny", "penny"), ("dm-drogerie", "dm"),
    ("dm drogerie", "dm"), ("rossmann", "rossmann"),
]
NETTO_SCOTTIE = "Q552652"  # Wikidata-ID von Netto (Salling Group), nicht Netto Marken-Discount

# shortcut: Caches im Prozessspeicher, bei mehreren Workern auf DB/Redis umstellen
_cache: dict[tuple, tuple[float, list[dict]]] = {}
_shelf_cache: dict[tuple, tuple[float, list[dict]]] = {}
DAY = 24 * 3600


def chain_of(tags: dict) -> str | None:
    label = (tags.get("brand") or tags.get("name") or "").strip().lower()
    if label == "dm":
        return "dm"
    chain = next((c for needle, c in CHAIN_RULES if needle in label), None)
    if chain == "netto_md":
        everything = " ".join(str(v) for v in tags.values()).lower()
        if "scottie" in everything or "salling" in everything or tags.get("brand:wikidata") == NETTO_SCOTTIE:
            return None
    return chain


def distance_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Haversine-Entfernung."""
    p1, p2 = math.radians(lat1), math.radians(lat2)
    a = math.sin((p2 - p1) / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(math.radians(lng2 - lng1) / 2) ** 2
    return 2 * 6371.0 * math.asin(math.sqrt(a))


def parse_overpass(data: dict, lat: float, lng: float) -> list[dict]:
    """Overpass-JSON -> bekannte Ketten, nach Entfernung sortiert."""
    out = []
    for el in data.get("elements", []):
        tags = el.get("tags") or {}
        pos = el if "lat" in el else el.get("center") or {}
        chain = chain_of(tags)
        if not chain or "lat" not in pos:
            continue
        street = " ".join(filter(None, [tags.get("addr:street"), tags.get("addr:housenumber")]))
        city = " ".join(filter(None, [tags.get("addr:postcode"), tags.get("addr:city")]))
        out.append({
            "osm_id": f"{el['type']}/{el['id']}", "chain": chain,
            "name": tags.get("name") or tags.get("brand") or chain,
            "address": ", ".join(filter(None, [street, city])),
            "lat": pos["lat"], "lng": pos["lon"],
            "distance_km": round(distance_km(lat, lng, pos["lat"], pos["lon"]), 2),
        })
    return sorted(out, key=lambda s: s["distance_km"])


def stores_from_shelf(brochures: list[dict], lat: float, lng: float, radius_km: float) -> list[dict]:
    """closestStore der Prospekte -> ein Laden je (Kette, Filial-ID) im Umkreis, nach Entfernung sortiert."""
    found = {}
    for b in brochures:
        s = b["store"]
        if not s.get("externalId") or s.get("latitude") is None or s.get("longitude") is None:
            continue
        dist = round(distance_km(lat, lng, s["latitude"], s["longitude"]), 2)
        if dist > radius_km:
            continue
        street = " ".join(filter(None, [s.get("street"), s.get("streetNumber")]))
        city = " ".join(filter(None, [s.get("zip"), s.get("city")]))
        found.setdefault((b["chain"], str(s["externalId"])), {
            "osm_id": f"kaufda/{b['chain']}/{s['externalId']}", "chain": b["chain"], "name": s.get("name") or b["chain"],
            "address": ", ".join(filter(None, [street, city])),
            "lat": s["latitude"], "lng": s["longitude"], "distance_km": dist,
        })
    return sorted(found.values(), key=lambda s: s["distance_km"])


def shelf(lat: float, lng: float) -> list[dict]:
    """kaufDA-Shelf am Ort, 24 h gecacht."""
    key = (round(lat, 5), round(lng, 5))
    if key not in _shelf_cache or time.time() - _shelf_cache[key][0] > DAY:
        _shelf_cache[key] = (time.time(), kaufda.fetch_shelf(lat, lng))
    return _shelf_cache[key][1]


def nearby(lat: float, lng: float, radius_km: int) -> list[dict]:
    """Hauptquelle kaufDA; Overpass nur, wenn kaufDA nichts liefert. Fehler gehen nur raus, wenn beide scheitern."""
    try:
        stores, kaufda_failed = stores_from_shelf(shelf(lat, lng), lat, lng, radius_km), False
    except (httpx.HTTPError, RuntimeError):
        stores, kaufda_failed = [], True
    if stores:
        return stores
    try:
        return overpass(lat, lng, radius_km)
    except httpx.HTTPError:
        if kaufda_failed:
            raise
        return []


def overpass(lat: float, lng: float, radius_km: int) -> list[dict]:
    """Live-Abfrage bei Overpass (höchstens ~10 s über alle Mirrors), 24 h gecacht."""
    key = (round(lat, 5), round(lng, 5), radius_km)
    if key in _cache and time.time() - _cache[key][0] < DAY:
        return _cache[key][1]
    query = (f'[out:json][timeout:10];nwr["shop"~"supermarket|chemist|convenience"]'
             f"(around:{radius_km * 1000},{lat},{lng});out center tags;")
    deadline = time.time() + 10
    for url in OVERPASS_URLS:
        try:
            r = httpx.post(url, data={"data": query}, timeout=max(deadline - time.time(), 1),
                           headers={"User-Agent": kaufda.HEADERS["User-Agent"]})
            r.raise_for_status()
            break
        except httpx.HTTPError:
            if url == OVERPASS_URLS[-1] or time.time() >= deadline:
                raise
    stores = parse_overpass(r.json(), lat, lng)
    _cache[key] = (time.time(), stores)
    return stores
