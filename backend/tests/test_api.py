from datetime import date, timedelta

from app.models import Offer


def test_household_requires_token(client):
    assert client.get("/household").status_code == 401
    assert client.get("/household", headers={"Authorization": "Bearer falsch"}).status_code == 401


def test_update_settings_and_stores(client, auth):
    r = client.patch("/household", headers=auth, json={
        "plz": "50667", "persons": 3, "radius_km": 8, "stores": [
        {"chain": "rewe", "store_ref": "123"},
        {"chain": "aldi_sued", "osm_id": "node/5", "lat": 50.9, "lng": 6.9, "address": "Ring 1, 50667 Köln"}]})
    assert r.status_code == 200
    h = client.get("/household", headers=auth).json()
    assert h["plz"] == "50667" and h["persons"] == 3
    assert [s["chain"] for s in h["stores"]] == ["rewe", "aldi_sued"]
    assert h["radius_km"] == 8 and h["stores"][1]["osm_id"] == "node/5" and h["stores"][1]["lat"] == 50.9
    assert client.patch("/household", headers=auth, json={"radius_km": 31}).status_code == 422
    assert client.patch("/household", headers=auth, json={"plz": "123"}).status_code == 422


def test_offers_filtered_by_household_stores_and_validity(client, auth, db):
    client.patch("/household", headers=auth, json={"stores": [{"chain": "rewe", "store_ref": "123"}]})
    today = date.today()

    def offer(chain, store_ref, title, start=today, end=today + timedelta(days=3)):
        return Offer(chain=chain, store_ref=store_ref, source_id=title, title=title, price_cents=199,
                     valid_from=start, valid_to=end)

    db.add_all([
        offer("rewe", "123", "Tomaten"),
        offer("rewe", "999", "Andere Filiale"),
        offer("lidl", "", "Anderer Laden"),
        offer("rewe", "123", "Abgelaufen", today - timedelta(days=9), today - timedelta(days=2)),
    ])
    db.commit()
    titles = [o["title"] for o in client.get("/offers", headers=auth).json()]
    assert titles == ["Tomaten"]
    assert client.get("/offers?q=tom", headers=auth).json()[0]["title"] == "Tomaten"
