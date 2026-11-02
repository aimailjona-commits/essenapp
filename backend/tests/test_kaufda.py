import json
from pathlib import Path

from sqlalchemy import func, select

from app.models import Offer
from app.services.importer import upsert_offers
from app.sources.kaufda import category_of, parse_pages, parse_search, parse_shelf

FIX = Path(__file__).parent / "fixtures" / "sources" / "kaufda"
FIELDS = {"chain", "store_ref", "source_id", "title", "brand", "category", "price_cents", "regular_price_cents",
          "amount", "unit", "base_price_cents", "ean", "valid_from", "valid_to", "image_url", "ingredient_id", "raw"}


def load(name):
    return json.loads((FIX / name).read_text(encoding="utf-8"))


def assert_plausible(offers):
    assert offers
    for o in offers:
        assert set(o) == FIELDS
        assert o["title"].strip()
        assert isinstance(o["price_cents"], int) and 0 < o["price_cents"] < 100_000
        assert o["valid_from"] <= o["valid_to"]


def test_shelf_finds_rewe_with_store():
    brochures = parse_shelf(load("shelf_koeln_50667_page0.json"))
    rewe = [b for b in brochures if b["chain"] == "rewe"]
    assert any(b["content_id"].startswith("ceb30b11") and b["store_id"] == "1763159" for b in rewe)
    assert {"lidl", "penny", "netto_md"} <= {b["chain"] for b in brochures}
    assert all(b["chain"] != "mediamarkt" for b in brochures)  # unbekannte Händler fallen weg


def test_pages_rewe():
    offers = parse_pages(load("brochure_pages_rewe_ceb30b11.json"), "rewe", "1763159")
    assert_plausible(offers)
    assert len(offers) > 74  # mehrere Produkte je Angebot werden einzeln geführt
    assert {o["store_ref"] for o in offers} == {"1763159"}
    alpro = next(o for o in offers if o["title"] == "Soja Dessert")
    assert (alpro["price_cents"], alpro["amount"], alpro["unit"], alpro["base_price_cents"]) == (149, 500, "g", 298)
    assert str(alpro["valid_from"]) == "2026-11-02" and str(alpro["valid_to"]) == "2026-11-07"


def test_pages_regional_chain_has_no_store_ref():
    offers = parse_pages(load("brochure_pages_lidl.json"), "lidl", "5741")
    assert_plausible(offers)
    assert {o["store_ref"] for o in offers} == {""}


def test_search_aldi():
    offers = parse_search(load("api_search_ALDI_koeln.json"))
    assert_plausible(offers)
    assert {o["chain"] for o in offers} == {"aldi_sued"}
    gulasch = next(o for o in offers if o["title"] == "Gulasch")
    assert (gulasch["price_cents"], gulasch["base_price_cents"], gulasch["category"]) == (499, 499, "fleisch_fisch")


def test_search_dm_is_drogerie():
    offers = parse_search(load("api_search_dm_koeln.json"))
    assert_plausible(offers)
    assert {o["chain"] for o in offers} == {"dm"}
    assert {o["category"] for o in offers} <= {"drogerie", "haushalt"}
    assert any(o["category"] == "drogerie" for o in offers)


def test_category():
    assert category_of("rewe", "Barista Haferdrink 1-Liter-Packung") == "getraenke"
    assert category_of("rossmann", "Duschgel 250 ml") == "drogerie"
    assert category_of("dm", "Spülmittel 500 ml") == "haushalt"
    assert category_of("lidl", "Holzkugelbahn") == "sonstiges"


def test_upsert_offers(db):
    offers = parse_pages(load("brochure_pages_edeka.json"), "edeka", "EDEKA-RR_10008482")
    assert upsert_offers(db, offers) == len(offers)
    count = db.scalar(select(func.count(Offer.id)))
    offers[0]["price_cents"] = 1
    upsert_offers(db, offers)  # zweiter Import aktualisiert statt zu duplizieren
    assert db.scalar(select(func.count(Offer.id))) == count
    assert db.scalar(select(Offer.price_cents).filter_by(source_id=offers[0]["source_id"])) == 1
