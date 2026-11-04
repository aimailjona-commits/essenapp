import logging
from datetime import date
from typing import Literal

from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Offer
from app.services import food_map, planner, prices
from app.sources.kaufda import SUBCATEGORIES

log = logging.getLogger(__name__)

KEY = ("chain", "store_ref", "source_id", "valid_from")


def upsert_offers(db: Session, offers: list[dict]) -> int:
    """Speichert Angebote; vorhandene (gleicher Unique-Key) werden aktualisiert. Schreibt Preispunkte (28).
    Gibt die Anzahl zurück."""
    rows = []
    for data in offers:
        # Autoflush macht auch Dubletten innerhalb derselben Liste sichtbar.
        row = db.scalar(select(Offer).filter_by(**{k: data[k] for k in KEY}))
        if row is None:
            row = Offer(**data)
            db.add(row)
        else:
            for k, v in data.items():
                setattr(row, k, v)
        rows.append(row)
    db.flush()
    prices.record(db, rows)
    db.commit()
    return len(offers)


KINDS = {sub: cat for sub, cat, _ in SUBCATEGORIES} | {"nonfood": "nonfood"}
BATCH = 150


class Kind(BaseModel):
    i: int
    kind: Literal[tuple(KINDS)]  # type: ignore[valid-type]


class Kinds(BaseModel):
    items: list[Kind]


def classify_unknown(db: Session, ask=food_map.ask_claude) -> int:
    """Laufende Angebote ohne feine Kategorie (Stichwörter trafen nicht: „Rama“, „Yakult“, „Doppelzimmer“) einmal je
    Titel per Haiku einordnen (19.1); bekannte Titel aus früheren Wochen übernehmen. Fehler nur geloggt."""
    todo = db.scalars(select(Offer).where(Offer.category == "sonstiges", Offer.subcategory == "",
                                          Offer.valid_to >= date.today())).all()
    titles = sorted({o.title.lower() for o in todo})
    if not titles:
        return 0
    known = {t.lower(): s for t, s in db.execute(select(Offer.title, Offer.subcategory)
                                                 .where(Offer.subcategory != "", Offer.category != "drogerie"))}
    found = {t: known[t] for t in titles if t in known}
    rest = [t for t in titles if t not in found]
    for start in range(0, len(rest), BATCH):
        part = rest[start:start + BATCH]
        try:
            out, usage = ask("Ordne jedes Prospekt-Produkt einer Kategorie zu. Kategorien: " + ", ".join(KINDS)
                             + ". nonfood = kein Lebensmittel/Getränk (Möbel, Reisen, Kleidung, Deko, Technik). "
                             "Für jede Zeile genau ein Eintrag mit ihrer Nummer i.\n\n"
                             + "\n".join(f"{i}|{t}" for i, t in enumerate(part)), Kinds, think=False)
        except Exception as e:  # Kür: ohne Einordnung bleibt „sonstiges“
            log.warning("Angebote einordnen fehlgeschlagen: %s", e)
            break
        planner.log_cost(db, None, "classify", usage["cost_cents"], usage.get("model", ""), f"{len(part)} Titel")
        found |= {part[k.i]: k.kind for k in out.items if 0 <= k.i < len(part)}
    n = 0
    for o in todo:
        if kind := found.get(o.title.lower()):
            # nonfood merkt sich subcategory "nonfood", damit der Titel nächste Woche nicht erneut gefragt wird
            o.category, o.subcategory = KINDS[kind], kind
            n += 1
    db.commit()
    return n
