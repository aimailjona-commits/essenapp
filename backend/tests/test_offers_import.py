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


def test_refresh_uses_kaufda_market_at_each_located_rewe(db):
    h = Household(name="T", plz="50667", lat=50.9, lng=6.9, stores=[
        HouseholdStore(chain="rewe", lat=51.0, lng=7.0), HouseholdStore(chain="rewe", lat=52.0, lng=8.0),
        HouseholdStore(chain="lidl", lat=50.95, lng=6.95), HouseholdStore(chain="penny", enabled=False)])
    db.add(h)
    db.commit()
    calls = []

    def fetch(lat, lng, chains, nearest_only=False):
        calls.append((lat, chains, nearest_only))
        if chains == {"lidl"}:
            return [offer("lidl", "", "l")]
        return [offer("rewe", f"m{lat}", f"r{lat}"), offer("rewe", "fern", f"x{lat}")]

    assert refresh_household(db, h, fetch=fetch, locate=None) == 3
    assert calls == [(51.0, {"rewe"}, True), (52.0, {"rewe"}, True), (50.9, {"lidl"}, False)]
    assert [s.store_ref for s in h.stores] == ["m51.0", "m52.0", "", ""]
    assert sorted(o.source_id for o in db.query(Offer)) == ["l", "r51.0", "r52.0"]
