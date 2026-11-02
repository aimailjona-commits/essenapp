from datetime import date, datetime
from types import SimpleNamespace

from sqlalchemy import select

from app import jobs
from app.models import Offer, PricePoint, Product
from app.services import prices
from app.services.importer import upsert_offers


def P(week, price, chain="lidl", regular=None, offer=False):
    return SimpleNamespace(week=f"2026-W{week}", chain=chain, price_cents=price, regular_price_cents=regular,
                           is_offer=offer)


BASE = [P(40, 199, offer=True), P(41, 249), P(42, 249), P(43, 249)]


def verdict(points, price, regular=None, week="2026-W45"):
    return prices.history(points, price, regular, week)


def test_verdicts():
    assert verdict(BASE[:1] + [P(45, 179)], 179)["verdict"] == "zu_wenig_daten"  # 2 Wochen
    best = verdict(BASE + [P(45, 179, offer=True)], 179)
    assert (best["verdict"], best["median_cents"], best["min_cents"]) == ("bestpreis", 249, 179)
    assert best["last_low"] is None
    assert verdict(BASE + [P(45, 209)], 209)["verdict"] == "gut"  # 209 ≤ 0,85 × 249, aber nicht unter 199
    normal = verdict(BASE + [P(45, 229)], 229)
    assert normal["verdict"] == "normal"
    assert normal["last_low"] == {"week": "2026-W40", "chain": "lidl", "price_cents": 199}
    assert verdict(BASE + [P(45, 249, regular=299, offer=True)], 249, 299)["verdict"] == "kein_echtes"  # ≥ Median


def test_moon_price_is_no_real_offer():
    """Normalpreis in Nicht-Angebotswochen 1,55 €; „Angebot“ 1,59 € statt angeblich 2,99 €."""
    points = [P(40, 155), P(41, 155), P(42, 249, "rewe", 299, True), P(43, 249, "rewe", 299, True),
              P(44, 249, "rewe", 299, True), P(45, 159, regular=299, offer=True)]
    assert verdict(points, 159, 299)["verdict"] == "kein_echtes"
    assert verdict(points, 159, None)["verdict"] == "gut"  # ohne Streichpreis ist es nur günstig


def test_window_dedupe_and_interval():
    points = [P(30, 99, offer=True), P(40, 199, offer=True), P(40, 189, offer=True), P(42, 249, offer=True),
              P(44, 249, offer=True), P(45, 229)]
    h = verdict(points, 229)
    assert [p["week"] for p in h["points"]] == ["2026-W40", "2026-W42", "2026-W44", "2026-W45"]  # W30 außerhalb
    assert h["points"][0]["price_cents"] == 189  # günstigste Filiale der Kette
    assert h["avg_interval_weeks"] == 4.7  # Angebote W30, W40, W42, W44: 14 Wochen / 3
    assert h["last_low"]["price_cents"] == 189


def offer_dict(title, price, start, end, chain="lidl", store_ref="", regular=None, source_id=None):
    return {"chain": chain, "store_ref": store_ref, "source_id": source_id or title, "title": title, "brand": "Milsani",
            "category": "kuehlung", "price_cents": price, "regular_price_cents": regular, "amount": 1000.0,
            "unit": "ml", "base_price_cents": price, "valid_from": start, "valid_to": end}


def test_import_writes_points_idempotent_per_week(db):
    week = (date(2026, 11, 2), date(2026, 11, 7))
    upsert_offers(db, [offer_dict("Frische Milch 3,5%", 99, *week, regular=119)])
    upsert_offers(db, [offer_dict("Frische Milch 3,5%", 99, *week, regular=119)])  # Import erneut
    upsert_offers(db, [offer_dict("frische  Milch 3,5 %", 109, date(2026, 11, 9), date(2026, 11, 14),
                                  chain="rewe", store_ref="R1", source_id="m2")])
    assert db.scalar(select(Product.key)) == "frische milch 3 5|milsani|1000ml"
    pts = db.scalars(select(PricePoint).order_by(PricePoint.week)).all()
    assert [(p.chain, p.week, p.price_cents, p.is_offer) for p in pts] == [
        ("lidl", "2026-W45", 99, True), ("rewe", "2026-W46", 109, False)]
    assert all(o.product_id == pts[0].product_id for o in db.scalars(select(Offer)))


def test_price_history_job_backfills_old_offers(db):
    db.add_all([Offer(chain="lidl", store_ref="", source_id=str(i), title="Butter", brand="", price_cents=p,
                      valid_from=d, valid_to=d) for i, (p, d) in enumerate(
        [(199, date(2026, 10, 13)), (179, date(2026, 10, 20)), (219, date(2026, 11, 3))])])
    db.commit()
    run = jobs.run(db, "price_history", datetime(2026, 11, 3, 8, tzinfo=jobs.BERLIN))
    assert run.ok and run.info == "3 Preispunkte aus 3 Angeboten"
    assert sorted(db.scalars(select(PricePoint.week))) == ["2026-W42", "2026-W43", "2026-W45"]
    assert jobs.price_history(db, datetime(2026, 11, 3, 9, tzinfo=jobs.BERLIN)) == "1 Preispunkte aus 1 Angeboten"


def test_history_endpoint(client, auth, db):
    db.add_all([Offer(chain="lidl", source_id=str(w), title="Butter", price_cents=p, regular_price_cents=r,
                      valid_from=date.fromisocalendar(2026, w, 1), valid_to=date.fromisocalendar(2026, w, 6))
                for w, p, r in [(42, 229, None), (43, 229, None), (44, 199, 229)]])
    db.commit()
    prices.record(db, db.scalars(select(Offer)).all(), date(2026, 11, 2))
    db.add(Offer(id=99, chain="lidl", source_id="now", title="Butter", price_cents=149, regular_price_cents=229,
                 valid_from=date.today(), valid_to=date.today()))
    db.commit()
    h = client.get("/offers/99/history", headers=auth).json()  # ohne product_id: wird nachgetragen
    assert h["verdict"] == "bestpreis" and h["min_cents"] == 149 and len(h["points"]) == 4
    assert client.get("/offers/12345/history", headers=auth).status_code == 404
