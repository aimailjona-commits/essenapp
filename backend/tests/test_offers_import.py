from datetime import date, timedelta

from app.api import household_offers
from app.models import Household, HouseholdStore, Offer
from app.services.offers_import import refresh_household


def offer(chain, store_ref, sid):
    today = date.today()
    return {"chain": chain, "store_ref": store_ref, "source_id": sid, "title": sid, "brand": "", "category": "sonstiges",
            "price_cents": 99, "regular_price_cents": None, "amount": None, "unit": "", "base_price_cents": None,
            "ean": "", "valid_from": today, "valid_to": today + timedelta(days=5), "image_url": "", "raw": {}}


def test_refresh_picks_nearest_market_per_chain_and_region_for_search_chains(db):
    h = Household(name="T", plz="50667", stores=[HouseholdStore(chain="rewe"), HouseholdStore(chain="lidl"),
                                                 HouseholdStore(chain="aldi_sued")])
    db.add(h)
    db.commit()
    fetched = [offer("rewe", "111", "a"), offer("rewe", "222", "b"), offer("lidl", "5741", "c"),
               offer("aldi_sued", "", "d")]
    seen = {}

    def fetch(lat, lng, chains, stores=frozenset()):
        seen.update(lat=lat, chains=chains, stores=stores)
        return fetched

    assert refresh_household(db, h, fetch=fetch, locate=lambda plz: (50.9, 6.9)) == 3
    assert seen == {"lat": 50.9, "chains": {"rewe", "lidl", "aldi_sued"}, "stores": {("aldi_sued", "plz:50667")}}
    assert {s.chain: s.store_ref for s in h.stores} == {"rewe": "111", "lidl": "5741", "aldi_sued": "plz:50667"}
    assert sorted((o.source_id, o.store_ref) for o in db.query(Offer)) == [
        ("a", "111"), ("c", "5741"), ("d", "plz:50667")]
    assert h.offers_refreshed_at is not None


def test_refresh_uses_kaufda_market_at_each_located_store(db):
    h = Household(name="T", plz="50667", lat=50.9, lng=6.9, stores=[
        HouseholdStore(chain="rewe", lat=51.0, lng=7.0), HouseholdStore(chain="rewe", lat=52.0, lng=8.0),
        HouseholdStore(chain="lidl", lat=50.95, lng=6.95), HouseholdStore(chain="penny", enabled=False),
        HouseholdStore(chain="dm", lat=50.9, lng=6.9)])
    db.add(h)
    db.commit()
    calls = []

    def fetch(lat, lng, chains, stores=frozenset()):
        calls.append((lat, chains))
        if chains == {"lidl"}:
            return [offer("lidl", "", "l")]  # Prospekt ohne closestStore
        if chains == {"dm"}:
            return [offer("dm", "", "d")]
        return [offer("rewe", f"m{lat}", f"r{lat}")]

    assert refresh_household(db, h, fetch=fetch, locate=None) == 4
    assert calls == [(51.0, {"rewe"}), (52.0, {"rewe"}), (50.95, {"lidl"}), (50.9, {"dm"})]
    assert [s.store_ref for s in h.stores] == ["m51.0", "m52.0", "plz:50667", "", "plz:50667"]
    assert sorted(o.source_id for o in db.query(Offer)) == ["d", "l", "r51.0", "r52.0"]


def test_kaufda_stores_use_their_market_id_and_cities_do_not_mix(db):
    h = Household(name="T", plz="24118", lat=54.34, lng=10.12, stores=[
        HouseholdStore(chain="rewe", osm_id="kaufda/rewe/111", lat=54.3, lng=10.1),
        HouseholdStore(chain="edeka", osm_id="kaufda/edeka/EDEKA-NST_10001234", lat=54.3, lng=10.1),
        HouseholdStore(chain="lidl", osm_id="kaufda/lidl/5741", lat=54.3, lng=10.1)])
    db.add(h)
    db.commit()
    calls = []

    def fetch(lat, lng, chains, stores=frozenset()):
        calls.append((lat, chains, stores))
        return [offer("rewe", "111", "r1"), offer("rewe", "222", "r2"), offer("edeka", "EDEKA-NST_10001234", "e1"),
                offer("edeka", "EDEKA-NST_9", "e2"), offer("lidl", "5741", "l1")]

    refresh_household(db, h, fetch=fetch, locate=None)
    # kein zweiter Shelf-Abruf an den Filialen; nur die gewählten Filialen werden geladen
    assert calls == [(54.34, {"rewe", "edeka", "lidl"},
                      {("rewe", "111"), ("edeka", "EDEKA-NST_10001234"), ("lidl", "5741")})]
    assert [s.store_ref for s in h.stores] == ["111", "EDEKA-NST_10001234", "5741"]
    db.add_all([Offer(**offer("penny", "", "p1")),  # Kette nicht gewählt
                Offer(**offer("lidl", "", "alt")),  # Altbestand ohne Filiale (gemischt)
                Offer(**offer("lidl", "1234", "koeln"))])  # Lidl eines anderen Haushalts in Köln
    db.commit()
    assert sorted(o.source_id for o in household_offers(db, h)) == ["e1", "l1", "r1"]
