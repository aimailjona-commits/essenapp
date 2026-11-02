"""Angebote eines Haushalts aktualisieren: PLZ → Koordinaten → kaufDA → nächster Markt → DB."""
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
    # Rewe/Edeka mit Kartenposition: Markt-ID über den kaufDA-Shelf an der Filiale selbst bestimmen
    located = [s for s in enabled if s.chain in kaufda.STORE_CHAINS and s.lat is not None and s.lng is not None]
    wanted = []
    for store in located:
        found = fetch(store.lat, store.lng, {store.chain}, nearest_only=True)
        store.store_ref = next((o["store_ref"] for o in found if o["store_ref"]), store.store_ref)
        wanted += [o for o in found if o["store_ref"] == store.store_ref]

    rest = [s for s in enabled if s not in located]
    offers = fetch(household.lat, household.lng, {s.chain for s in rest}) if rest else []
    # Filialabhängige Händler: ohne gewählte Filiale die erste aus kaufDA nehmen (Shelf ist nach Nähe sortiert, ungeprüft)
    for store in rest:
        if store.chain in kaufda.STORE_CHAINS and not store.store_ref:
            store.store_ref = next((o["store_ref"] for o in offers if o["chain"] == store.chain and o["store_ref"]), "")
    refs = {(s.chain, s.store_ref) for s in rest}
    wanted += [o for o in offers if o["chain"] not in kaufda.STORE_CHAINS or (o["chain"], o["store_ref"]) in refs]
    count = upsert_offers(db, wanted)
    household.offers_refreshed_at = datetime.now()
    db.commit()
    return count
