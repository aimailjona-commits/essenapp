from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Offer

KEY = ("chain", "store_ref", "source_id", "valid_from")


def upsert_offers(db: Session, offers: list[dict]) -> int:
    """Speichert Angebote; vorhandene (gleicher Unique-Key) werden aktualisiert. Gibt die Anzahl zurück."""
    for data in offers:
        # Autoflush macht auch Dubletten innerhalb derselben Liste sichtbar.
        row = db.scalar(select(Offer).filter_by(**{k: data[k] for k in KEY}))
        if row is None:
            db.add(Offer(**data))
        else:
            for k, v in data.items():
                setattr(row, k, v)
    db.commit()
    return len(offers)
