"""Läden in der Nähe aus OpenStreetMap (Overpass API) für die Kartenauswahl."""
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

_cache: dict[tuple, tuple[float, list[dict]]] = {}  # shortcut: Cache im Prozessspeicher, bei mehreren Workern auf DB/Redis umstellen


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


def nearby(lat: float, lng: float, radius_km: int) -> list[dict]:
    """Live-Abfrage bei Overpass, 24 h gecacht. Fehler (auch 429/504 bei Überlast) gehen als Exception raus."""
    key = (round(lat, 5), round(lng, 5), radius_km)
    if key in _cache and time.time() - _cache[key][0] < 24 * 3600:
        return _cache[key][1]
    query = (f'[out:json][timeout:25];nwr["shop"~"supermarket|chemist|convenience"]'
             f"(around:{radius_km * 1000},{lat},{lng});out center tags;")
    for url in OVERPASS_URLS:
        try:
            r = httpx.post(url, data={"data": query}, timeout=30, headers={"User-Agent": kaufda.HEADERS["User-Agent"]})
            r.raise_for_status()
            break
        except httpx.HTTPError:
            if url == OVERPASS_URLS[-1]:
                raise
    stores = parse_overpass(r.json(), lat, lng)
    _cache[key] = (time.time(), stores)
    return stores
