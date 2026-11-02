"""Angebote eines Haushalts aktualisieren: PLZ → Koordinaten → kaufDA (je Kette eine Filiale) → DB."""
from collections.abc import Callable
from datetime import datetime

import httpx
from sqlalchemy.orm import Session

from app.models import Household
from app.services.importer import upsert_offers
from app.sources import kaufda


def geocode(plz: str) -> tuple[float, float]:
    """PLZ-Mittelpunkt über OpenStreetMap Nominatim (Nutzungsregeln: 1 Anfrage/s, eigener User-Agent)."""
    r = httpx.get("https://nominatim.openstreetmap.org/search", timeout=20,
                  params={"postalcode": plz, "country": "de", "format": "json", "limit": 1},
                  headers={"User-Agent": kaufda.HEADERS["User-Agent"]})
    r.raise_for_status()
    hits = r.json()
    if not hits:
        raise ValueError(f"PLZ {plz} nicht gefunden")
    return float(hits[0]["lat"]), float(hits[0]["lon"])


def refresh_household(db: Session, household: Household,
                      fetch: Callable[..., list[dict]] = kaufda.fetch_offers,
                      locate: Callable[[str], tuple[float, float]] = geocode) -> int:
    if not household.plz:
        raise ValueError("Keine PLZ eingestellt")
    if household.lat is None:
        household.lat, household.lng = locate(household.plz)
    enabled = [s for s in household.stores if s.enabled]
    region = f"plz:{household.plz}"  # Schlüssel für Angebote ohne Filiale (Suche), damit Städte nicht mischen
    fixed = []  # Filial-ID steht schon fest
    for store in enabled:
        if store.chain in kaufda.SEARCH_QUERIES:
            store.store_ref = region
        elif store.osm_id.startswith("kaufda/"):  # "kaufda/<chain>/<externalId>"
            store.store_ref = store.osm_id.split("/", 2)[2]
        else:
            continue
        fixed.append(store)
    # Filialen mit Kartenposition (OpenStreetMap): Filial-ID über den kaufDA-Shelf an der Filiale selbst bestimmen
    located = [s for s in enabled if s not in fixed and s.lat is not None and s.lng is not None]
    wanted = []
    for store in located:
        found = fetch(store.lat, store.lng, {store.chain})
        for o in found:
            o["store_ref"] = o["store_ref"] or region
        store.store_ref = next((o["store_ref"] for o in found), store.store_ref or region)
        wanted += [o for o in found if o["store_ref"] == store.store_ref]

    rest = [s for s in enabled if s not in located]
    offers = fetch(household.lat, household.lng, {s.chain for s in rest},
                   {(s.chain, s.store_ref) for s in fixed}) if rest else []
    for o in offers:
        o["store_ref"] = o["store_ref"] or region
    for store in rest:
        if store not in fixed:  # ohne gewählte Filiale gilt die nächste (fetch lädt je Kette nur eine)
            store.store_ref = next((o["store_ref"] for o in offers if o["chain"] == store.chain), region)
    refs = {(s.chain, s.store_ref) for s in rest}
    wanted += [o for o in offers if (o["chain"], o["store_ref"]) in refs]
    count = upsert_offers(db, wanted)
    household.offers_refreshed_at = datetime.now()
    db.commit()
    return count
