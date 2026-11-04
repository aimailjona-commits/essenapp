import json
from pathlib import Path

from sqlalchemy import func, select

from app.models import Offer
from app.services.importer import upsert_offers
from app.sources.kaufda import bonus_cents, category_of, classify, parse_pages, parse_search, parse_shelf, pick_brochures

FIX = Path(__file__).parent / "fixtures" / "sources" / "kaufda"
FIELDS = {"chain", "store_ref", "source_id", "title", "brand", "category", "subcategory", "price_cents", "regular_price_cents",
          "amount", "unit", "base_price_cents", "ean", "valid_from", "valid_to", "image_url", "ingredient_id", "raw",
          "bonus_cents"}


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


def test_rewe_bonus_from_deal_text():
    """39: kaufDA hat kein Bonus-Feld; Betrag aus dem Deal-Text (Fixture vom 02.11.2026)."""
    offers = parse_pages(load("brochure_pages_rewe_ceb30b11.json"), "rewe", "1763159")
    bonus = {o["title"]: o["bonus_cents"] for o in offers if o["bonus_cents"]}
    assert bonus["Pizza Tradizionale Salame Romano"] == 20 and bonus["Die Ofenfrische Vier Käse"] == 20
    assert bonus["Sahnepudding oder Vollmilchpudding"] == 50 and bonus["Les Sauces Hollandaise"] == 10
    assert len(bonus) == 14 and next(o for o in offers if o["title"] == "Soja Dessert")["bonus_cents"] is None
    lidl = parse_pages(load("brochure_pages_lidl.json"), "lidl", "5741")
    assert all(o["bonus_cents"] is None for o in lidl)


def test_bonus_cents_variants():
    deals = [{"type": "SALES_PRICE", "description": "Goldbären"}, {"type": "OTHER", "description": "0,10 € Bonus"},
             {"type": "SALES_PRICE", "description": "Color-Rado"}]
    assert bonus_cents(deals, "Goldbären", ["Goldbären", "Color-Rado"]) == 10
    two = [{"description": "Pizza Salame\n0,20 € Bonus"}, {"description": "Vier Käse-\n0,30 € Bonus"}]
    assert bonus_cents(two, "Vier Käse", ["Pizza Salame", "Vier Käse"]) == 30
    assert bonus_cents([{"description": "Bonus 0,15€"}], "X", ["X"]) == 15
    assert bonus_cents([{"description": "Diesen Artikel zum Aktionspreis kaufen, 0,20 € Bonus in der REWE App "
                                        "sammeln 0,20€"}], "X", ["X"]) == 20
    assert bonus_cents([{"description": "", "conditions": [{"other": "0.20 € Bonus"}]}], "X", ["X"]) == 20
    assert bonus_cents([{"description": "0,10 €Vegane Mühlen Schnitzel0,20 € Bonus"}], "Schnitzel", ["Schnitzel"]) == 20
    assert bonus_cents([{"description": "Je"}], "X", ["X"]) is None


def test_pages_regional_chain_keeps_its_store():
    offers = parse_pages(load("brochure_pages_lidl.json"), "lidl", "5741")
    assert_plausible(offers)
    assert {o["store_ref"] for o in offers} == {"5741"}


def test_pick_brochures_one_store_per_chain():
    b = [{"chain": c, "store_id": s, "content_id": i} for c, s, i in [
        ("rewe", "1", "a"), ("rewe", "2", "b"), ("rewe", "1", "c"), ("lidl", "7", "d"), ("lidl", "8", "e"),
        ("penny", "3", "f"), ("dm", "", "g")]]
    picked = pick_brochures(b, {"rewe", "lidl", "dm"}, {("lidl", "8")})
    assert [x["content_id"] for x in picked] == ["a", "c", "e"]  # rewe: nächste Filiale, lidl: gewählte


def test_bag_volume_is_no_quantity():
    page = {"contents": [{"offers": [{"content": {
        "id": "x", "publicationProfiles": [{"validity": {"startDate": "2026-11-01T23:00:00.000+0000",
                                                         "endDate": "2026-11-06T23:00:00.000+0000"}}],
        "deals": [{"type": "SALES_PRICE", "min": 1.49, "priceByBaseUnit": "1 l = 0,04 €"}],
        "products": [{"name": "Duft-Müllbeutel", "description": [{"paragraph": "35 l, 20 Stück"}]}]}}]}]}
    o = parse_pages(page, "aldi_nord", "1")[0]
    assert (o["category"], o["amount"], o["unit"], o["base_price_cents"]) == ("haushalt", 20, "stk", 7)


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
    # Stichwort zufällig im Wort (echte Prospekttitel), Komposita treffen weiter
    for text, cat in [("Schweine-Hackfleisch", "fleisch_fisch"), ("Schweinefilet", "fleisch_fisch"),
                      ("Rotwein trocken", "getraenke"), ("Glühwein", "getraenke"), ("Mineralwasser", "getraenke"),
                      ("Bierschinken", "fleisch_fisch"), ("König Ludwig Bierkäse", "kuehlung"),
                      ("Weißbier", "getraenke"), ("Rucola", "obst_gemuese"), ("Thunfisch", "fleisch_fisch"),
                      ("The Chocolate Block, Rotwein", "getraenke"), ("Vanilla & Chocolate Swirl", "sonstiges"),
                      ("Zahnpasta mit Zahnfleischschutz", "drogerie"), ("Erdnusskerne gehackt", "vorrat"),
                      ("Pistaziencreme Kugeln", "vorrat"), ("Handcreme", "drogerie"),
                      ("Colorwaschmittel", "haushalt"), ("Kaffeevollautomat", "sonstiges")]:
        assert category_of("lidl", text) == cat, text


def test_subcategory():
    """Fehlgriffe der groben Stichwort-Reihenfolge (19.1): Joghurt ≠ Käse, Süßes/Saucen/Snacks/Tiefkühl vor Zutaten."""
    for text, sub in [("Milchschokolade", "suesses"), ("Tomatensauce", "saucen"), ("Kartoffelchips", "snacks"),
                      ("Pizza Salami", "tiefkuehl"), ("Cremiger Joghurt Kirsche", "joghurt"),
                      ("Gouda jung", "kaese"), ("Bierkäse", "kaese"), ("Leberkäse", "wurst"),
                      ("Speisequark 20 %", "joghurt"), ("Frische Vollmilch 3,5 %", "molkerei"),
                      ("Brotaufstrich", "fruehstueck"), ("Weintrauben hell", "obst"), ("Eiernudeln", "nudeln_reis"),
                      ("Langkornreis Aktionspreis", "nudeln_reis"), ("Kokosmilch", "konserven"),
                      ("Lachsfilet", "fisch"), ("Schweine-Lachsbraten", "fleisch"), ("Lamm-Lachs", "fleisch"), ("Hähnchenbrustfilet", "fleisch"), ("Kaffeebohnen", "kaffee_tee"),
                      ("Pfefferminztee", "kaffee_tee"), ("Teelichter", "haushalt"), ("Holzkugelbahn", "")]:
        assert classify("lidl", text)[1] == sub, text
    assert classify("dm", "Bio Haferflocken") == ("drogerie", "drogerie")
    # Prospekt-Kategorie schlägt Stichwörter: Kaffeemühle ist Elektronik, Laufschuhe mit Gummisohle kein Süßes
    assert classify("lidl", "Elektrische Kaffeemühle", "Elektronik und Technik") == ("nonfood", "")
    assert classify("lidl", "Speisequark Magerstufe", "Lebensmittel und Getränke") == ("kuehlung", "joghurt")
    assert classify("lidl", "Küchentücher XXL", "Drogerie und Haushalt") == ("drogerie", "drogerie")


def test_upsert_offers(db):
    offers = parse_pages(load("brochure_pages_edeka.json"), "edeka", "EDEKA-RR_10008482")
    assert upsert_offers(db, offers) == len(offers)
    count = db.scalar(select(func.count(Offer.id)))
    offers[0]["price_cents"] = 1
    upsert_offers(db, offers)  # zweiter Import aktualisiert statt zu duplizieren
    assert db.scalar(select(func.count(Offer.id))) == count
    assert db.scalar(select(Offer.price_cents).filter_by(source_id=offers[0]["source_id"])) == 1
