"""Vorratskauf-Tipp (31): bei starkem Rabatt auf Haltbares so viel kaufen, wie bis zum nächsten erwarteten Angebot
verbraucht wird – gedeckelt auf 6 Monate und den Vorratsplatz."""
import math
import re
from dataclasses import dataclass
from datetime import date, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import MealPlan, Offer, ShoppingItem, ShoppingList, WatchItem, WeeklyBasic
from app.services.matching import Matcher
from app.services.normalize import base_unit
from app.services.pricing import PANTRY_WORDS
from app.services.recipes import convert

STORAGE = {"klein": 3, "mittel": 6, "gross": 12}  # (C) höchstens so viele Packungen je Tipp
DURABLE = ("vorrat", "getraenke", "drogerie", "haushalt")
FROZEN = re.compile(r"\btk\b|tiefk[üu]hl|tiefgefroren|gefroren", re.I)
KEEP_WORDS = (*PANTRY_WORDS, "dose", "konserve", "getrocknet")
MIN_DISCOUNT, MAX_WEEKS, HISTORY_WEEKS = 0.25, 26, 8
DEFAULT_PACKS = 2  # ohne Verbrauchshistorie konservativ
DEFAULT_INTERVAL = 4  # (C) Wochen bis zum nächsten Angebot, wenn der Preisverlauf noch keinen Rhythmus kennt


def durable(o: Offer) -> bool:
    """Haltbar ≥ 3 Monate: Kategorien Vorrat/Getränke/Drogerie/Haushalt, Tiefkühl oder haltbare Begriffe."""
    if o.category in DURABLE or FROZEN.search(o.title):
        return True
    title_words = o.title.lower().replace("-", " ").split()
    return any(w.startswith(p) or w.endswith(p) for w in title_words for p in KEEP_WORDS)


@dataclass
class Usage:
    """Verbrauchsquellen eines Haushalts (letzte 8 Wochen), einmal geladen für alle Kandidaten."""
    plan_rows: list[dict]  # Zutaten aus Plänen (Menge im Plan)
    list_rows: list[ShoppingItem]  # abgehakte Listenartikel, die nicht aus dem Plan kommen
    basics: list[WeeklyBasic]
    rhythm: list[WatchItem]


def load_usage(db: Session, household_id: int, today: date | None = None) -> Usage:
    since = datetime.combine((today or date.today()) - timedelta(weeks=HISTORY_WEEKS), datetime.min.time())
    plans = db.scalars(select(MealPlan).where(MealPlan.household_id == household_id, MealPlan.created_at >= since))
    rows = [{**i, "amount": (i.get("amount") or 0) * (e.scale or 1)} for p in plans for e in p.entries
            for i in e.recipe.ingredients]
    items = list(db.scalars(select(ShoppingItem).join(ShoppingList, ShoppingItem.list_id == ShoppingList.id).where(
        ShoppingList.household_id == household_id, ShoppingItem.checked, ShoppingItem.source != "plan",
        ShoppingItem.created_at >= since)))
    basics = list(db.scalars(select(WeeklyBasic).where(WeeklyBasic.household_id == household_id)))
    rhythm = list(db.scalars(select(WatchItem).where(WatchItem.household_id == household_id,
                                                     WatchItem.lasts_weeks.is_not(None))))
    return Usage(rows, items, basics, rhythm)


def _packs(amount: float | None, unit: str, o: Offer) -> float:
    """Menge als Anzahl Packungen des Angebots; ohne umrechenbare Menge = 1 Packung."""
    if amount and unit and o.amount:
        amount, unit = base_unit(amount, unit) if unit in ("kg", "l") else (amount, unit)
        if (n := convert(amount, unit, o.unit or "stk", None)) is not None:
            return n / o.amount
    return 1.0


def weekly_use(u: Usage, o: Offer) -> float | None:
    """Packungen pro Woche aus Plänen/Listen (8 Wochen), Wochen-Basics (23) und Verbrauchsrhythmus (58); None = keine
    Historie."""
    m = Matcher([o], False)

    def hit(name: str, offer_id: int | None = None) -> bool:
        return offer_id == o.id or bool(m.find(name))

    from app.services.watch import name_match  # watch importiert pricing/matching, nicht dieses Modul
    history = sum(_packs(r.get("amount"), r.get("unit", ""), o) for r in u.plan_rows if hit(r["name"], r.get("offer_id")))
    history += sum(_packs(i.amount, i.unit, o) for i in u.list_rows if hit(i.name, i.offer_id))
    use = history / HISTORY_WEEKS
    use += sum(_packs(b.amount, b.unit, o) for b in u.basics if hit(b.name))
    use += sum(1 / w.lasts_weeks for w in u.rhythm if w.lasts_weeks and name_match(w, o.title, o.brand))
    return use or None


def tip(o: Offer, verdict: dict, use: float | None, storage: str = "mittel") -> dict | None:
    """Empfehlung oder None. verdict = prices.history() des Angebots."""
    if not durable(o) or verdict["verdict"] not in ("bestpreis", "gut"):
        return None
    normal = o.regular_price_cents or verdict["median_cents"]
    if not normal or o.price_cents > normal * (1 - MIN_DISCOUNT):
        return None
    limit = STORAGE.get(storage, STORAGE["mittel"])
    if use:
        interval = verdict["avg_interval_weeks"] or DEFAULT_INTERVAL
        packs = min(math.ceil(use * interval - 1e-9), max(1, math.floor(use * MAX_WEEKS + 1e-9)), limit)
        weeks = round(packs / use, 1)
    else:
        packs, weeks = min(DEFAULT_PACKS, limit), None
    packs = max(packs, 1)
    return {"offer": o, "packs": packs, "weeks": weeks, "weekly_use": round(use, 2) if use else None,
            "saving_cents": (normal - o.price_cents) * packs, "normal_price_cents": normal,
            "verdict": verdict["verdict"]}
