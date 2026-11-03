"""Merkliste mit Alarm (27), Preisalarm für Zutaten (40), Verbrauchsrhythmus (58). Abgleich nach jedem Import,
Push über APNs (jobs.notify, Ruhezeiten), höchstens 1 Push je Eintrag und ISO-Woche."""
import re
from datetime import date, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Member, Offer, PricePoint, Product, ShoppingItem, WatchHit, WatchItem
from app.services.matching import Matcher, words
from app.services.prices import iso_week

CHAIN_NAMES = {"rewe": "Rewe", "aldi_sued": "Aldi Süd", "aldi_nord": "Aldi Nord", "lidl": "Lidl", "edeka": "Edeka",
               "kaufland": "Kaufland", "penny": "Penny", "netto_md": "Netto", "dm": "dm", "rossmann": "Rossmann"}
EMOJI = {"drogerie": "🧴", "haushalt": "🧽"}
BASE_UNIT = {"g": "kg", "ml": "l", "stk": "stk"}  # Grundpreis der Angebote: pro kg, l bzw. Stück
# „Hält ca. X Wochen“ (58): Vorschlag nach Stichwort, sonst nach Kategorie; änderbar
LASTS = (("shampoo", 6), ("spülung", 6), ("duschgel", 4), ("dusch", 4), ("zahnpasta", 6), ("zahncreme", 6),
         ("zahnbürste", 12), ("deo", 6), ("rasier", 4), ("creme", 8), ("bodylotion", 8), ("waschmittel", 8),
         ("weichspüler", 8), ("spülmittel", 6), ("geschirr", 6), ("spülmaschinentabs", 6), ("toilettenpapier", 3),
         ("klopapier", 3), ("küchenrolle", 3), ("taschentücher", 3), ("windel", 1), ("feuchttücher", 2),
         ("müllbeutel", 8), ("reiniger", 8))
CATEGORY_LASTS = {"drogerie": 6, "haushalt": 8}
SOON_PUSH, SOON_LIST = 14, 3  # Tage vor „leer“: Push, wenn im Angebot / „bald leer“ auf die Liste


def lasts_suggestion(label: str, category: str) -> float | None:
    text = label.lower()
    return next((w for k, w in LASTS if k in text), CATEGORY_LASTS.get(category))


def euro(c: int) -> str:
    return f"{c / 100:.2f} €".replace(".", ",")


def _tokens(text: str) -> set[str]:
    return set(words(text)) | set(re.findall(r"\w+", (text or "").lower()))


def _has(tokens: set[str], w: str) -> bool:
    return any(t == w or (len(w) >= 4 and t.endswith(w)) for t in tokens)


def name_match(item: WatchItem, title: str, brand: str = "") -> bool:
    """Name/Marke normalisiert per Token-Abgleich: Marke (falls gesetzt) muss vorkommen, vom Namen dann ≥ 1/2 der
    Wörter (Sorte wie „Classic“ fehlt im Prospekt oft), ohne Marke ≥ 2/3; Mengenangaben wie „300ml“ zählen nicht."""
    return fitter(item)(_tokens(f"{title} {brand}"))


def fitter(item: WatchItem):
    """name_match als Funktion über fertige Tokens (Wörter des Eintrags nur einmal zerlegt, für viele Titel)."""
    brand = words(item.brand)
    want = [w for w in words(item.label) if not w[0].isdigit() and w not in brand]

    def fits(have: set[str]) -> bool:
        if brand and not all(_has(have, w) for w in brand):
            return False
        if not want:
            return bool(brand)
        found = sum(_has(have, w) for w in want)
        return found * 2 >= len(want) if brand else found * 3 >= len(want) * 2
    return fits


def matches(item: WatchItem, offers: list[Offer]) -> list[Offer]:
    """Passende Angebote, die den Alarm erfüllen (Wunschpreis bzw. Grundpreis), günstigste zuerst."""
    pool = [o for o in offers if not item.chains or o.chain in item.chains]
    if item.ean:
        found = [o for o in pool if o.ean == item.ean]
    else:
        found = []
    if not found:
        found = Matcher(pool).find(item.label) if item.kind == "zutat" else [
            o for o in pool if name_match(item, o.title, o.brand)]
    if item.max_price_cents is not None:
        found = [o for o in found if o.price_cents <= item.max_price_cents]
    if item.max_base_price_cents is not None:  # Grundpreis-Alarm: unabhängig von der Packungsgröße
        found = [o for o in found if o.base_price_cents is not None and BASE_UNIT.get(o.unit) == item.base_unit
                 and o.base_price_cents <= item.max_base_price_cents]
    return sorted(found, key=lambda o: (o.base_price_cents if item.max_base_price_cents is not None else o.price_cents,
                                        o.price_cents))


def last_offers(db: Session, items: list[WatchItem], chains: set[str], week: str) -> dict[int, PricePoint]:
    """„Zuletzt im Angebot: KW …“ aus dem Preisverlauf (28): neuester Preispunkt bis `week` der passenden Produkte
    (EAN, sonst Name/Marke wie name_match) in den Läden des Eintrags bzw. des Haushalts; gleiche Woche → günstigster."""
    if not items:
        return {}
    # shortcut: alle Produkte je Aufruf im Speicher (4300 → ~10 ms je Eintrag), bei viel mehr Produkten per SQL vorfiltern
    products = [(pid, ean, _tokens(f"{title} {brand}"))
                for pid, ean, title, brand in db.execute(select(Product.id, Product.ean, Product.title, Product.brand))]
    found = {}
    for i in items:
        fits = fitter(i)
        found[i.id] = ({pid for pid, ean, _ in products if i.ean and ean == i.ean}
                       or {pid for pid, _, have in products if fits(have)})
    points: dict[int, list[PricePoint]] = {}
    if ids := set().union(*found.values()):
        for p in db.scalars(select(PricePoint).where(PricePoint.product_id.in_(ids), PricePoint.week <= week)):
            points.setdefault(p.product_id, []).append(p)
    out = {}
    for i in items:
        if cands := [p for pid in found[i.id] for p in points.get(pid, ()) if p.chain in (i.chains or chains)]:
            out[i.id] = max(cands, key=lambda p: (p.week, -p.price_cents))
    return out


def discount(o: Offer) -> int | None:
    return round(100 * (1 - o.price_cents / o.regular_price_cents)) if o.regular_price_cents else None


def message(item: WatchItem, o: Offer) -> str:
    """„🧴 Dein Shampoo ist bei dm im Angebot: 1,79 € (−25 %)“; Grundpreis-Alarm mit €/kg."""
    pct = discount(o)
    extra = f" (−{pct} %)" if pct else ""
    if item.max_base_price_cents is not None and o.base_price_cents is not None:
        extra = f" ({euro(o.base_price_cents)}/{item.base_unit}{', −' + str(pct) + ' %' if pct else ''})"
    emoji = EMOJI.get(item.category or o.category, "🔔" if item.kind == "zutat" else "🛒")
    who = item.label if item.kind == "zutat" else f"Dein {item.label}"
    return f"{emoji} {who} ist bei {CHAIN_NAMES.get(o.chain, o.chain)} im Angebot: {euro(o.price_cents)}{extra}"


def check(db: Session, household_id: int, offers: list[Offer], now: datetime, notify) -> int:
    """Abgleich nach dem Import: Treffer speichern, je Eintrag höchstens 1 Push pro Woche (an alle Mitglieder mit
    Push). notify(member, now, title, message, **kw) wie jobs.notify. Gibt die Zahl gesendeter Hinweise zurück."""
    week, sent = iso_week(now.date()), 0
    members = list(db.scalars(select(Member).where(Member.household_id == household_id)))
    for item in db.scalars(select(WatchItem).where(WatchItem.household_id == household_id)).all():
        hits = matches(item, offers)
        known = {h.offer_id: h for h in item.hits}
        for o in hits:
            if o.id not in known:
                known[o.id] = WatchHit(offer_id=o.id, week=week)
                item.hits.append(known[o.id])
        if not hits or any(h.notified_at and h.week == week for h in item.hits):
            continue
        best = hits[0]
        if any([notify(m, now, "Essenapp", message(item, best), click_url=f"essenapp://offer/{best.id}",
                       thread_id="watch") for m in members]):
            known[best.id].notified_at, known[best.id].week = now.replace(tzinfo=None), week
            sent += 1
    db.commit()
    return sent


def mark_bought(db: Session, household_id: int, name: str, today: date) -> None:
    """Abgehakt auf der Liste → „zuletzt gekauft“ (58) für passende Merklisten-Produkte."""
    for item in db.scalars(select(WatchItem).where(WatchItem.household_id == household_id,
                                                   WatchItem.kind == "produkt")):
        if name_match(item, name) or (item.label.strip().lower() == name.strip().lower()):
            item.last_bought = today


def empty_on(item: WatchItem) -> date | None:
    if item.lasts_weeks and item.last_bought:
        return item.last_bought + timedelta(days=round(item.lasts_weeks * 7))
    return None


def rhythm(db: Session, household_id: int, offers: list[Offer], lst, now: datetime, notify) -> list[str]:
    """Verbrauchsrhythmus (58), täglich: 2 Wochen vor „leer“ und im Angebot → Push „Shampoo bald leer – gerade −25 %
    bei dm“ (einmal je Zyklus); 3 Tage vor „leer“ → „bald leer“ auf die Liste (Quelle rhythm, Laden des Angebots
    bzw. der Merkliste), einmal je Zyklus und nur, wenn es nicht schon offen auf der Liste steht."""
    today, done = now.date(), []
    members = list(db.scalars(select(Member).where(Member.household_id == household_id)))
    for item in db.scalars(select(WatchItem).where(WatchItem.household_id == household_id)).all():
        empty = empty_on(item)
        if empty is None:
            continue
        hits = matches(item, offers)
        if today >= empty - timedelta(days=SOON_PUSH) and hits and not (
                item.rhythm_push_at and item.rhythm_push_at >= item.last_bought):
            o = hits[0]
            pct = discount(o)
            text = (f"{EMOJI.get(item.category or o.category, '🛒')} {item.label} bald leer – gerade "
                    + (f"−{pct} % " if pct else f"{euro(o.price_cents)} ") + f"bei {CHAIN_NAMES.get(o.chain, o.chain)}")
            if any([notify(m, now, "Essenapp", text, click_url=f"essenapp://offer/{o.id}", thread_id="watch")
                    for m in members]):
                item.rhythm_push_at = today
                done.append(f"push {item.label}")
        if today >= empty - timedelta(days=SOON_LIST) and not (
                item.rhythm_listed_at and item.rhythm_listed_at >= item.last_bought):
            if not any(not i.checked and name_match(item, i.name) for i in lst.items):
                o = hits[0] if hits else None
                lst.items.append(ShoppingItem(name=item.label[:100], source="rhythm", added_by="bald leer",
                                              offer_id=o.id if o else None,
                                              chain=o.chain if o else (item.chains[0] if len(item.chains) == 1 else "")))
            item.rhythm_listed_at = today
            done.append(f"liste {item.label}")
    db.commit()
    return done
