"""Geplante Jobs (Spezifikation 72, E47). Zeiten in Europe/Berlin, jeder Lauf steht in `job_run`.
Lokal: SCHEDULER=1 (dev.sh serve) startet loop() als Thread im API-Prozess. VPS: eigener Container `python -m app.jobs`.
Manuell: ./dev.sh python -m app.jobs <name>"""
import logging
import sys
import threading
import time
from datetime import UTC, datetime, timedelta
from zoneinfo import ZoneInfo

from sqlalchemy import or_, select
from sqlalchemy.orm import Session, object_session

from app.core.config import settings
from app.core.db import SessionLocal
from app.models import Household, JobRun, MealPlan, Member, Offer, Product, PushOutbox, WatchItem
from app.services import labels, prices, push, watch
from app.services.offers_import import refresh_household

log = logging.getLogger(__name__)
BERLIN = ZoneInfo("Europe/Berlin")
DAYS = ["mo", "di", "mi", "do", "fr", "sa", "so"]
GRACE = timedelta(hours=12)  # verpasste Termine (PC aus) werden höchstens so spät nachgeholt
REMIND_AFTER, REMINDERS = timedelta(hours=2), 2  # Plan-Erinnerung erneut nach 2 h, max. 2× (17)
REINSTALL_EVERY, REINSTALL_AT = 6, "18:00"  # Tage seit REINSTALL_BASE, Uhrzeit


def hm(text: str):
    return datetime.strptime(text, "%H:%M").time()


def utc(dt: datetime) -> datetime:
    return dt.astimezone(UTC).replace(tzinfo=None)


def last_slot(spec: str, now: datetime) -> datetime:
    """Letzter Termin ≤ now, spec z.B. "Sa 22:00, Mo 06:00" oder "täglich 09:00"."""
    slots = []
    for part in spec.split(","):
        day, at = part.split()
        daily = day.lower() == "täglich"
        d = now.date() - timedelta(days=0 if daily else (now.weekday() - DAYS.index(day[:2].lower())) % 7)
        slot = datetime.combine(d, hm(at), BERLIN)
        if slot > now:
            slot = datetime.combine(d - timedelta(days=1 if daily else 7), hm(at), BERLIN)
        slots.append(slot)
    return max(slots)


def runs_since(db: Session, name: str, since: datetime) -> list[JobRun]:
    return list(db.scalars(select(JobRun).where(JobRun.name == name, JobRun.ran_at >= utc(since))
                           .order_by(JobRun.ran_at)))


def due(db: Session, name: str, slot: datetime | None, now: datetime) -> bool:
    return slot is not None and now - slot <= GRACE and not runs_since(db, name, slot)


def run(db: Session, name: str, now: datetime, job=None) -> JobRun:
    """Führt einen Job aus und protokolliert ihn. Der Eintrag entsteht vor dem Lauf, damit ein Absturz
    oder ein zweiter Prozess ihn nicht nochmal startet."""
    row = JobRun(name=name, ran_at=utc(now), ok=False, info="läuft")
    db.add(row)
    db.commit()
    try:
        row.info, row.ok = str((job or JOBS[name][1])(db, now))[:500], True
    except Exception as e:
        db.rollback()
        log.exception("Job %s fehlgeschlagen", name)
        row.info = f"Fehler: {e}"[:500]
    db.commit()
    log.info("Job %s: %s", name, row.info)
    return row


# --- Push-Helfer ---

def quiet_end(quiet: dict | None, now: datetime) -> datetime | None:
    """Ende der Ruhezeit, falls now in ihr liegt (Ruhezeit darf über Mitternacht gehen)."""
    if not quiet:
        return None
    start, end, t = hm(quiet["start"]), hm(quiet["end"]), now.time()
    if not (start <= t < end if start <= end else t >= start or t < end):
        return None
    return datetime.combine(now.date() + timedelta(days=0 if t < end else 1), end, BERLIN)


def notify(member: Member, now: datetime, title: str, message: str, **kw) -> bool:
    """Push nur wenn eingeschaltet; in der Ruhezeit wird er bis zu deren Ende verschoben (push_outbox)."""
    if not member.push_enabled:
        return False
    if end := quiet_end(member.quiet_hours, now):
        object_session(member).add(PushOutbox(member_id=member.id, title=title, message=message, send_at=utc(end),
                                              **kw))
        return True
    return push.send(member, title, message, **kw)


def send_outbox(db: Session, now: datetime) -> int:
    """Verschobene Pushes, deren Ruhezeit vorbei ist (jede Minute im tick)."""
    rows = list(db.scalars(select(PushOutbox).where(PushOutbox.send_at <= utc(now))))
    for row in rows:
        if (member := db.get(Member, row.member_id)) and member.push_enabled:
            push.send(member, row.title, row.message, click_url=row.click_url, thread_id=row.thread_id,
                      category=row.category)
        db.delete(row)
    db.commit()
    return len(rows)


# --- Jobs ---

AFTER_IMPORT = ("price_history", "watch_alarms", "product_facts")


def import_offers(db: Session, now: datetime) -> str:
    """Angebote aller Haushalte. Folgewoche (30): refresh_household nimmt alle Prospekte aus dem kaufDA-Shelf
    ohne Datumsfilter, also auch die ab nächstem Montag, sobald kaufDA sie listet (live geprüft: Lidl ab Montag der
    Vorwoche); sie erscheinen in GET /offers?week=next."""
    results, failed = [], False
    for household in db.scalars(select(Household).where(Household.plz != "")).all():
        try:
            results.append(f"{household.id}: {refresh_household(db, household)}")
        except Exception as e:  # ein Haushalt darf die anderen nicht blockieren
            db.rollback()
            failed = True
            results.append(f"{household.id}: Fehler {e}")
    for name in AFTER_IMPORT:
        run(db, name, now)
    info = ", ".join(results) or "keine Haushalte mit PLZ"
    if failed:
        raise RuntimeError(info)
    return info


def price_history(db: Session, now: datetime) -> str:
    """Preispunkte aus allen aktuellen Angeboten (28); Angebote ohne Produkt werden mit nachgetragen
    (einmalige Rückfüllung aus bereits gespeicherten Angeboten, danach nur noch Neues)."""
    today = now.date()
    offers = list(db.scalars(select(Offer).where(or_(Offer.product_id.is_(None), Offer.valid_to >= today))))
    written = prices.record(db, offers, today)
    db.commit()
    return f"{written} Preispunkte aus {len(offers)} Angeboten"


def watch_households(db: Session, rhythm: bool = False) -> list[Household]:
    q = select(WatchItem.household_id)
    if rhythm:
        q = q.where(WatchItem.lasts_weeks.is_not(None), WatchItem.last_bought.is_not(None))
    return list(db.scalars(select(Household).where(Household.id.in_(q))))


def watch_alarms(db: Session, now: datetime) -> str:
    """Merkliste (27) + Preisalarme (40) nach jedem Import: Treffer → Push, höchstens 1 je Eintrag und Woche."""
    from app.api import household_offers  # spät importiert: api importiert jobs nicht
    sent = [watch.check(db, h.id, household_offers(db, h, on=now.date()), now, notify) for h in watch_households(db)]
    return f"{sum(sent)} Hinweise in {len(sent)} Haushalten"


def watch_rhythm(db: Session, now: datetime) -> str:
    """Verbrauchsrhythmus (58), täglich: „bald leer“ als Push (im Angebot, 2 Wochen vorher) bzw. auf die Liste
    (3 Tage vorher)."""
    from app.api import household_list, household_offers
    done = [x for h in watch_households(db, rhythm=True)
            for x in watch.rhythm(db, h.id, household_offers(db, h, on=now.date()), household_list(db, h.id), now,
                                  notify)]
    return ", ".join(done) or "nichts fällig"


def product_facts(db: Session, now: datetime) -> str:
    """Nutri-Score/Bio/Vegan aus Open Food Facts (49) für Produkte aktueller Lebensmittel-Angebote mit Marke,
    schonend: höchstens 30 Suchen je Lauf (Limit 10/min), Ergebnis am product gecacht."""
    today = now.date()
    products = list(db.scalars(select(Product).where(Product.off_checked_at.is_(None), Product.brand != "",
                                                     Product.id.in_(select(Offer.product_id).where(
                                                         Offer.valid_to >= today,
                                                         Offer.category.in_(labels.FOOD))))))
    found = labels.enrich(products)
    db.commit()
    return f"{found} sichere Treffer, {len([p for p in products if p.off_checked_at])} geprüft, {len(products)} offen"


def waiting(phase: str):
    return lambda db, now: f"Platzhalter, wartet auf {phase}"


def plan_week(now: datetime) -> int:
    """KW, für die geplant wird: ab Freitag die nächste."""
    return (now + timedelta(days=7 - now.weekday() if now.weekday() >= 4 else 0)).isocalendar().week


def send_plan_prompt(member: Member, now: datetime) -> bool:
    # Kategorie PLAN_PROMPT: Aktionen „Plan erstellen“ (öffnet url) und „Später“ (schließt nur; Erinnerung nach
    # 2 h kommt automatisch) registriert die App
    return notify(member, now, "Essenapp", f"🍽️ Neue Woche – sollen wir deinen Plan für KW {plan_week(now)} erstellen?",
                  click_url="essenapp://generator", thread_id="plan", category="PLAN_PROMPT")


def prompt_members(db: Session) -> list[Member]:
    return list(db.scalars(select(Member).where(Member.plan_prompt_enabled, Member.push_enabled)))


def prompt_job(member: Member):
    def job(db, now):
        if not send_plan_prompt(member, now):
            raise RuntimeError("Push nicht gesendet")
        return f"KW {plan_week(now)}"
    return job


def plan_prompts(db: Session, now: datetime) -> None:
    """Pro Mitglied zu Tag/Uhrzeit aus den Einstellungen. Ohne neuen Plan seit dem ersten Push: erneut nach 2 h."""
    for member in prompt_members(db):
        name = f"plan_prompt:{member.id}"
        slot = last_slot(f"{DAYS[member.plan_prompt_weekday]} {member.plan_prompt_time}", now)
        if now - slot > GRACE:
            continue
        runs = runs_since(db, name, slot)
        if not runs or (len(runs) <= REMINDERS and utc(now) >= runs[-1].ran_at + REMIND_AFTER and not db.scalar(
                select(MealPlan.id).where(MealPlan.household_id == member.household_id,
                                          MealPlan.created_at >= runs[0].ran_at).limit(1))):
            run(db, name, now, prompt_job(member))


def weekly_basics(db: Session, now: datetime) -> str:
    """Frühstück & Snacks (23a): Wochen-Basics jeden Montag auf die Haushaltsliste (nach dem Angebotsimport 06:00)."""
    from app.api import apply_weekly_basics  # api importiert jobs nicht; hier spät, damit der Scheduler leicht bleibt
    from app.models import WeeklyBasic
    households = list(db.scalars(select(Household).where(Household.id.in_(select(WeeklyBasic.household_id)))))
    for household in households:
        apply_weekly_basics(db, household)
    db.commit()
    return f"{len(households)} Haushalte"


def lunchbox_job(member: Member):
    """„Lunchbox für morgen vorbereiten“ (24): nur wenn morgen im aktuellen Plan eine Lunchbox für das Mitglied steht."""
    def job(db, now):
        plan = db.scalar(select(MealPlan).where(MealPlan.household_id == member.household_id)
                         .order_by(MealPlan.id.desc()).limit(1))
        tomorrow = (now + timedelta(days=1)).weekday()
        entry = next((e for e in (plan.entries if plan else []) if e.meal_type == "lunchbox" and e.day == tomorrow
                      and any(p["member_id"] == member.id for p in e.portions)), None)
        if entry is None:
            return "keine Lunchbox morgen"
        if not notify(member, now, "Essenapp", f"🥡 Lunchbox für morgen vorbereiten: {entry.recipe.title}",
                      click_url=f"essenapp://recipe/{entry.recipe_id}", thread_id="lunchbox"):
            raise RuntimeError("Push nicht gesendet")
        return entry.recipe.title
    return job


def lunchbox_reminders(db: Session, now: datetime) -> None:
    for member in db.scalars(select(Member).where(Member.lunchbox_push.is_not(None), Member.push_enabled)).all():
        name = f"lunchbox:{member.id}"
        if due(db, name, last_slot(f"täglich {member.lunchbox_push}", now), now):
            run(db, name, now, lunchbox_job(member))


def reinstall_slot(now: datetime) -> datetime | None:
    """Alle 6 Tage seit REINSTALL_BASE um 18:00 (freie Apple-ID: Signatur gilt 7 Tage, E2)."""
    base = settings.reinstall_base
    if not base:
        return None
    k = (now.date() - base).days // REINSTALL_EVERY
    def at(k):
        return datetime.combine(base + timedelta(days=k * REINSTALL_EVERY), hm(REINSTALL_AT), BERLIN)
    if k >= 1 and at(k) > now:
        k -= 1
    return at(k) if k >= 1 else None


def reinstall_reminder(db: Session, now: datetime) -> str:
    owners = list(db.scalars(select(Member).where(Member.role == "owner", Member.push_enabled)))
    sent = sum(notify(m, now, "Essenapp", "App neu installieren (7-Tage-Signatur)", thread_id="reinstall")
               for m in owners)
    return f"{sent}/{len(owners)} gesendet"


JOBS = {  # name: (Zeitplan oder None, Funktion(db, now) -> Info); Zeitpläne per JOB_SCHEDULES überschreibbar
    # Fr 06:00: Vorschau der nächsten Woche (30) ist ab Freitag sichtbar (kaufDA listet sie meist ab Do/Fr/Sa)
    "import_offers": ("Sa 22:00, Mo 06:00, Mi 06:00, Fr 06:00", import_offers),
    "price_history": (None, price_history),  # nach jedem Import
    "watch_alarms": (None, watch_alarms),  # nach jedem Import
    "product_facts": (None, product_facts),  # nach jedem Import (Open Food Facts, 49)
    "watch_rhythm": ("täglich 08:00", watch_rhythm),  # Verbrauchsrhythmus (58)
    "plan_prompt": (None, lambda db, now: f"{sum(send_plan_prompt(m, now) for m in prompt_members(db))} gesendet"),
    "coupon_expiry": ("täglich 09:00", waiting("Phase 13 (38 Payback & Rewe Bonus)")),
    "week_review": ("So 19:00", waiting("Phase 14 (55 Wochenrückblick)")),
    "achievements": ("täglich 03:00", waiting("Phase 14 (54 Erfolge)")),
    "reinstall_reminder": (None, reinstall_reminder),  # Termin aus reinstall_slot()
    "weekly_basics": ("Mo 06:30", weekly_basics),
}


def tick(db: Session, now: datetime) -> None:
    """Startet alle fälligen Jobs (plan_prompt: pro Mitglied, manuell = sofort an alle)."""
    schedules = {n: s for n, (s, _) in JOBS.items() if s} | settings.job_schedules
    for name, spec in schedules.items():
        if due(db, name, last_slot(spec, now), now):
            run(db, name, now)
    plan_prompts(db, now)
    lunchbox_reminders(db, now)
    if due(db, "reinstall_reminder", reinstall_slot(now), now):
        run(db, "reinstall_reminder", now)
    send_outbox(db, now)


def loop() -> None:
    log.info("Scheduler läuft (Europe/Berlin)")
    while True:
        try:
            with SessionLocal() as db:
                tick(db, datetime.now(BERLIN))
        except Exception:
            log.exception("Scheduler-Durchlauf fehlgeschlagen")
        time.sleep(60 - datetime.now().second)


def start() -> None:
    threading.Thread(target=loop, name="scheduler", daemon=True).start()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    if len(sys.argv) < 2:
        loop()
    elif sys.argv[1] not in JOBS:
        sys.exit(f"Unbekannter Job. Verfügbar: {', '.join(JOBS)}")
    else:
        with SessionLocal() as db:
            r = run(db, sys.argv[1], datetime.now(BERLIN))
            print(r.name, "ok" if r.ok else "FEHLER", r.info)
