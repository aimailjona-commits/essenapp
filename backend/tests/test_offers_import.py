from datetime import date, timedelta

from app.models import Household, HouseholdStore, Offer
from app.services.offers_import import refresh_household


def offer(chain, store_ref, sid):
    today = date.today()
    return {"chain": chain, "store_ref": store_ref, "source_id": sid, "title": sid, "brand": "", "category": "sonstiges",
            "price_cents": 99, "regular_price_cents": None, "amount": None, "unit": "", "base_price_cents": None,
            "ean": "", "valid_from": today, "valid_to": today + timedelta(days=5), "image_url": "", "raw": {}}


def test_refresh_picks_nearest_rewe_market_and_keeps_regional(db):
    h = Household(name="T", plz="50667", stores=[HouseholdStore(chain="rewe"), HouseholdStore(chain="lidl")])
    db.add(h)
    db.commit()
    fetched = [offer("rewe", "111", "a"), offer("rewe", "222", "b"), offer("lidl", "", "c")]
    seen = {}

    def fetch(lat, lng, chains):
        seen.update(lat=lat, chains=chains)
        return fetched

    assert refresh_household(db, h, fetch=fetch, locate=lambda plz: (50.9, 6.9)) == 2
    assert seen == {"lat": 50.9, "chains": {"rewe", "lidl"}}
    assert {s.chain: s.store_ref for s in h.stores} == {"rewe": "111", "lidl": ""}
    assert sorted(o.source_id for o in db.query(Offer)) == ["a", "c"]
    assert h.offers_refreshed_at is not None
