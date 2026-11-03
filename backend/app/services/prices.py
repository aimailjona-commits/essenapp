"""Preisdaten (Grundlage 28/30/31): Produkt-Schlüssel, ein Preispunkt pro Produkt/Laden/Woche, Urteil."""
import re
import statistics
from datetime import date, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Offer, PricePoint, Product
from app.services.normalize import cents

WINDOW, MIN_WEEKS = 12, 3  # Diagramm/Urteil über 12 Wochen, Urteil ab 3 Wochen mit Daten
GOOD = 0.85  # „Gutes Angebot“ ab 15 % unter Median


def norm(text: str) -> str:
    return " ".join(re.sub(r"[^\w]+", " ", (text or "").lower()).split())


def product_key(o: Offer) -> str:
    return f"{norm(o.title)}|{norm(o.brand)}|{o.amount or 0:g}{o.unit}"[:320]


def iso_week(d: date) -> str:
    year, week, _ = d.isocalendar()
    return f"{year}-W{week:02d}"


def week_monday(week: str) -> date:
    year, w = week.split("-W")
    return date.fromisocalendar(int(year), int(w), 1)


def point_week(o: Offer, today: date) -> str:
    """Woche des Preispunkts: heute, begrenzt auf die Gültigkeit (Vorschau → Startwoche, Altes → Endwoche)."""
    return iso_week(min(max(today, o.valid_from), o.valid_to))


def record(db: Session, offers: list[Offer], today: date | None = None) -> int:
    """Ordnet Angebote einem product zu und schreibt je product/chain/store_ref/week einen Preispunkt (idempotent).
    Gibt die Zahl der geschriebenen Punkte zurück."""
    today = today or date.today()
    # shortcut: alle Produkte im Speicher (wenige Tausend); bei sehr vielen Produkten gezielt per key/ean laden
    products = list(db.scalars(select(Product)))
    by_key = {p.key: p for p in products}
    by_ean = {p.ean: p for p in products if p.ean}
    pairs = []
    for o in offers:
        key = product_key(o)
        p = (by_ean.get(o.ean) if o.ean else None) or by_key.get(key)
        if p is None:
            p = Product(key=key, title=o.title[:200], brand=o.brand[:100], amount=o.amount, unit=o.unit, ean=o.ean)
            db.add(p)
            by_key[key] = p
            if o.ean:
                by_ean[o.ean] = p
        elif o.ean and not p.ean:
            p.ean = o.ean
        pairs.append((o, p))
    db.flush()
    for o, p in pairs:
        o.product_id = p.id

    weeks = {point_week(o, today) for o in offers}
    existing = {(pp.product_id, pp.chain, pp.store_ref, pp.week): pp for pp in db.scalars(select(PricePoint).where(
        PricePoint.product_id.in_({o.product_id for o in offers}), PricePoint.week.in_(weeks)))} if offers else {}
    written = set()
    for o in offers:
        k = (o.product_id, o.chain, o.store_ref, point_week(o, today))
        pp = existing.get(k)
        if pp is None:
            pp = existing[k] = PricePoint(product_id=o.product_id, chain=o.chain, store_ref=o.store_ref, week=k[3])
            db.add(pp)
        elif k in written and pp.price_cents <= o.price_cents:
            continue  # gleiches Produkt mehrfach im Prospekt: günstigster Preis zählt
        pp.price_cents, pp.regular_price_cents, pp.base_price_cents = o.price_cents, o.regular_price_cents, o.base_price_cents
        pp.is_offer = o.regular_price_cents is not None and o.regular_price_cents > o.price_cents
        pp.valid_from, pp.valid_to = o.valid_from, o.valid_to
        written.add(k)
    db.flush()
    return len(written)


def history(points: list, price_cents: int, regular_price_cents: int | None, week: str) -> dict:
    """Preisverlauf + Urteil für ein Angebot (price_cents in `week`). points: Preispunkte des Produkts
    (week, chain, price_cents, regular_price_cents, is_offer), mehrere Filialen je Kette → günstigster Preis."""
    best: dict[tuple[str, str], object] = {}
    for p in points:
        k = (p.week, p.chain)
        if k not in best or p.price_cents < best[k].price_cents:
            best[k] = p
    ordered = sorted(best.values(), key=lambda p: (p.week, p.chain))
    now = week_monday(week)
    start = now - timedelta(weeks=WINDOW - 1)
    window = [p for p in ordered if start <= week_monday(p.week) <= now]
    prices = [p.price_cents for p in window]
    median = cents(statistics.median(prices)) if prices else None
    low = min(prices) if prices else None

    normal = [p.price_cents for p in window if not p.is_offer]
    if len({p.week for p in window}) < MIN_WEEKS:
        verdict = "zu_wenig_daten"
    elif price_cents >= median or (
            regular_price_cents and normal and price_cents >= statistics.median(normal)):  # Rabatt nur auf Mondpreis
        verdict = "kein_echtes"
    elif price_cents <= low:
        verdict = "bestpreis"
    elif price_cents <= median * GOOD:
        verdict = "gut"
    else:
        verdict = "normal"

    last_low = next(({"week": p.week, "chain": p.chain, "price_cents": p.price_cents} for p in reversed(ordered)
                     if p.week < week and p.price_cents <= price_cents), None)
    offer_weeks = sorted({week_monday(p.week) for p in ordered if p.is_offer})
    interval = (round((offer_weeks[-1] - offer_weeks[0]).days / 7 / (len(offer_weeks) - 1), 1)
                if len(offer_weeks) > 1 else None)
    return {"points": [{"week": p.week, "chain": p.chain, "price_cents": p.price_cents,
                        "regular_price_cents": p.regular_price_cents, "is_offer": p.is_offer} for p in window],
            "median_cents": median, "min_cents": low, "verdict": verdict, "last_low": last_low,
            "avg_interval_weeks": interval}


def verdicts(db: Session, offers: list[Offer], today: date | None = None) -> dict[int, dict]:
    """history() für viele Angebote mit EINER Abfrage (Badges + Filter in GET /offers, Vorratstipps).
    Angebote ohne Produkt werden vorher zugeordnet."""
    today = today or date.today()
    if missing := [o for o in offers if o.product_id is None]:
        record(db, missing, today)
    ids = {o.product_id for o in offers}
    points: dict[int, list] = {}
    if ids:
        for p in db.scalars(select(PricePoint).where(PricePoint.product_id.in_(ids))):
            points.setdefault(p.product_id, []).append(p)
    return {o.id: history(points.get(o.product_id, []), o.price_cents, o.regular_price_cents, point_week(o, today))
            for o in offers}
