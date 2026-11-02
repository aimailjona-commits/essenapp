from app.services import nearby_stores, offers_import

OVERPASS = {"elements": [
    {"type": "node", "id": 1, "lat": 50.9400, "lon": 6.9600,
     "tags": {"shop": "supermarket", "brand": "REWE", "name": "REWE City", "addr:street": "Breite Straße",
              "addr:housenumber": "12", "addr:postcode": "50667", "addr:city": "Köln"}},
    {"type": "way", "id": 2, "center": {"lat": 50.9387, "lon": 6.9586},
     "tags": {"shop": "supermarket", "brand": "ALDI SÜD", "addr:city": "Köln"}},
    {"type": "node", "id": 3, "lat": 50.9390, "lon": 6.9590, "tags": {"shop": "chemist", "brand": "dm-drogerie markt"}},
    {"type": "node", "id": 4, "lat": 50.9391, "lon": 6.9591, "tags": {"shop": "supermarket", "name": "Netto Marken-Discount"}},
    {"type": "node", "id": 5, "lat": 50.9392, "lon": 6.9592, "tags": {"shop": "supermarket", "brand": "Netto",
                                                                      "operator": "Netto ApS (Salling Group)"}},
    {"type": "node", "id": 6, "lat": 50.9393, "lon": 6.9593, "tags": {"shop": "convenience", "name": "Kiosk Ali"}},
    {"type": "relation", "id": 7, "tags": {"shop": "supermarket", "brand": "Lidl"}},  # ohne Position
]}


def test_parse_overpass_maps_chains_and_sorts_by_distance():
    stores = nearby_stores.parse_overpass(OVERPASS, 50.9385, 6.9585)
    assert [(s["osm_id"], s["chain"]) for s in stores] == [
        ("way/2", "aldi_sued"), ("node/3", "dm"), ("node/4", "netto_md"), ("node/1", "rewe")]
    rewe = stores[-1]
    assert rewe["name"] == "REWE City" and rewe["address"] == "Breite Straße 12, 50667 Köln"
    assert stores[0]["address"] == "Köln" and stores[0]["lat"] == 50.9387
    assert 0.1 < rewe["distance_km"] < 0.3


def test_nearby_endpoint_geocodes_and_saves_coordinates(client, auth, monkeypatch):
    client.patch("/household", headers=auth, json={"plz": "50667", "radius_km": 3})
    seen = {}
    monkeypatch.setattr(offers_import, "geocode", lambda plz: (50.9, 6.9))
    monkeypatch.setattr(nearby_stores, "nearby", lambda lat, lng, r: seen.update(args=(lat, lng, r)) or [
        {"osm_id": "node/1", "chain": "rewe", "name": "REWE", "address": "", "lat": 50.9, "lng": 6.9, "distance_km": 0.0}])
    r = client.get("/stores/nearby", headers=auth)
    assert r.status_code == 200 and r.json()[0]["osm_id"] == "node/1"
    assert seen["args"] == (50.9, 6.9, 3)
    h = client.get("/household", headers=auth).json()
    assert (h["lat"], h["lng"], h["radius_km"]) == (50.9, 6.9, 3)
    client.get("/stores/nearby?radius_km=10", headers=auth)
    assert seen["args"][2] == 10
    assert client.get("/stores/nearby?radius_km=31", headers=auth).status_code == 422
