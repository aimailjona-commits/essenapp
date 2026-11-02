"""Wöchentlicher Import für alle Haushalte. Aufruf (z.B. per cron, So + Mo früh): ./dev.sh python -m app.jobs"""
from sqlalchemy import select

from app.core.db import SessionLocal
from app.models import Household
from app.services.offers_import import refresh_household

if __name__ == "__main__":
    with SessionLocal() as db:
        for household in db.scalars(select(Household).where(Household.plz != "")):
            try:
                print(household.id, refresh_household(db, household))
            except Exception as e:  # ein Haushalt darf die anderen nicht blockieren
                db.rollback()
                print(household.id, "Fehler:", e)
