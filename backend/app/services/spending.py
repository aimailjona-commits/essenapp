"""Monats-Dashboard (34, A10): Ausgaben = Preise der abgehakten Artikel. Beim Abhaken wird ein `purchase` mit Preis
und Zeitpunkt festgehalten (Angebotspreis, sonst Normalpreis-Schätzung „geschätzt“); Abhaken rückgängig löscht ihn."""
import calendar
import csv
import io
from collections import defaultdict
from datetime import date, datetime, timedelta
from types import SimpleNamespace

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.models import Household, Offer, PricePoint, Product, Purchase, ShoppingItem
from app.services import bonus, prices
from app.services.matching import Matcher, words
from app.services.store_split import packs

NON_FOOD = ("drogerie", "haushalt")  # zählen nicht fürs Lebensmittel-Budget (Budget-Wächter, 54)


def estimate(db: Session, item: ShoppingItem) -> tuple[int, str]:
    """Normalpreis-Schätzung (ganze Packungen) aus dem Preisverlauf (28) der letzten 8 Wochen: Streichpreis, sonst
    Preis; bevorzugt der Laden des Artikels, dann der kürzeste passende Titel („Bananen“ vor „Schoko-Banane“).
    → (Cent, Kategorie); (0, sonstiges) wenn nichts passt."""
    ws = words(item.name)
    # Vorauswahl per SQL über `product` (klein) statt `offer` (Rohdaten, Sekunden je Abhaken);
    # shortcut: Synonyme des Matchers (z.B. Möhre ↔ Karotte) fallen dadurch weg
    products = {p.id: p for p in db.scalars(select(Product).where(*(func.lower(Product.title).contains(w)
                                                                       for w in ws)))} if ws else {}
    if not products:
        return 0, "sonstiges"
    since = prices.iso_week(date.today() - timedelta(weeks=8))
    cands = [SimpleNamespace(title=products[pp.product_id].title, amount=products[pp.product_id].amount,
                             unit=products[pp.product_id].unit, price_cents=pp.regular_price_cents or pp.price_cents,
                             base_price_cents=pp.base_price_cents, chain=pp.chain, category="", product_id=pp.product_id)
             for pp in db.scalars(select(PricePoint).where(PricePoint.product_id.in_(products), PricePoint.week >= since))]
    for chain in ([item.chain] if item.chain else []) + [None]:
        if found := Matcher([c for c in cands if not chain or c.chain == chain], False).find(item.name):
            o = min(found, key=lambda o: (len(words(o.title)), packs(item, o) * o.price_cents))
            category = db.scalar(select(Offer.category).where(Offer.product_id == o.product_id).limit(1))
            return packs(item, o) * o.price_cents, category or "sonstiges"
    return 0, "sonstiges"


def record(db: Session, household_id: int, item: ShoppingItem, by: str, now: datetime | None = None) -> Purchase:
    offer = db.get(Offer, item.offer_id) if item.offer_id else None
    p = Purchase(household_id=household_id, item_id=item.id, name=item.name, amount=item.amount, unit=item.unit,
                 chain=item.chain or (offer.chain if offer else ""), source=item.source, bought_by=by,
                 bought_at=now or datetime.now())
    if offer is not None:
        n = packs(item, offer)
        p.price_cents, p.category, p.estimated = n * offer.price_cents, offer.category, False
        p.saved_cents = n * max((offer.regular_price_cents or 0) - offer.price_cents, 0)
        p.verdict = prices.verdicts(db, [offer])[offer.id]["verdict"]
    else:
        p.price_cents, p.category = estimate(db, item)
        p.estimated, p.saved_cents = True, 0
    db.add(p)
    return p


def checked(db: Session, household_id: int, item: ShoppingItem, by: str) -> None:
    """Aufruf bei jeder Haken-Änderung: abgehakt → Kauf festhalten, Haken weg → Kauf löschen."""
    old = list(db.scalars(select(Purchase).where(Purchase.item_id == item.id)))
    for p in old:
        db.delete(p)
    if item.checked:
        record(db, household_id, item, by)


def month_range(month: str) -> tuple[date, date]:
    y, m = map(int, month.split("-"))
    return date(y, m, 1), date(y, m, calendar.monthrange(y, m)[1]) + timedelta(days=1)


def purchases(db: Session, household_id: int, start: date, end: date) -> list[Purchase]:
    return list(db.scalars(select(Purchase).where(
        Purchase.household_id == household_id, Purchase.bought_at >= datetime.combine(start, datetime.min.time()),
        Purchase.bought_at < datetime.combine(end, datetime.min.time())).order_by(Purchase.bought_at.desc())))


def budget_cents(h: Household, days: int) -> int:
    """Budget für so viele Tage: Lebensmittel-Wochenbudget (+ Drogerie-Wochenbudget, falls gesetzt) × Tage / 7."""
    return round((h.budget_food_week_cents + (h.budget_drugstore_cents or 0)) * days / 7)


def dashboard(db: Session, h: Household, month: str) -> dict:
    start, end = month_range(month)
    rows = purchases(db, h.id, start, end)
    total = sum(p.price_cents for p in rows)
    prev_start = (start - timedelta(days=1)).replace(day=1)
    prev = sum(p.price_cents for p in purchases(db, h.id, prev_start, start))
    weeks, stores, cats = defaultdict(int), defaultdict(int), defaultdict(int)
    d = start
    while d < end:  # alle Wochen des Monats, auch leere (Balken)
        weeks[prices.iso_week(d)] += 0
        d += timedelta(days=1)
    for p in rows:
        weeks[prices.iso_week(p.bought_at.date())] += p.price_cents
        stores[p.chain] += p.price_cents
        cats[p.category] += p.price_cents
    return {
        "month": month, "total_cents": total, "estimated_cents": sum(p.price_cents for p in rows if p.estimated),
        "budget_cents": budget_cents(h, (end - start).days),
        "saved_cents": sum(p.saved_cents for p in rows), "bonus_cents": bonus.earned_cents(db, h.id, start, end),
        "weeks": [{"week": w, "total_cents": c} for w, c in sorted(weeks.items())],
        "stores": [{"chain": k, "total_cents": c} for k, c in sorted(stores.items(), key=lambda x: -x[1])],
        "categories": [{"category": k, "total_cents": c} for k, c in sorted(cats.items(), key=lambda x: -x[1])],
        "top": sorted(rows, key=lambda p: -p.price_cents)[:5],
        "prev_total_cents": prev, "change_pct": round(100 * (total - prev) / prev, 1) if prev else None,
        "items": rows,
    }


def to_csv(rows: list[Purchase]) -> str:
    """Excel-freundlich (deutsch): Semikolon, Dezimalkomma."""
    out = io.StringIO()
    w = csv.writer(out, delimiter=";")
    w.writerow(["Datum", "Artikel", "Menge", "Einheit", "Laden", "Kategorie", "Preis €", "Gespart €", "Geschätzt"])
    for p in sorted(rows, key=lambda p: p.bought_at):
        w.writerow([p.bought_at.strftime("%d.%m.%Y %H:%M"), p.name, f"{p.amount:g}" if p.amount else "", p.unit,
                    p.chain, p.category, f"{p.price_cents / 100:.2f}".replace(".", ","),
                    f"{p.saved_cents / 100:.2f}".replace(".", ","), "ja" if p.estimated else "nein"])
    return out.getvalue()
