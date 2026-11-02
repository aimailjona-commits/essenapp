from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Offer
from app.services import prices

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
