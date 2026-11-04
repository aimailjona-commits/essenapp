"""Übersicht „Fehler melden“ (19.9) für den Entwickler: ./dev.sh python -m app.reports [Tage]
Falsche Angebote stehen am Ende als Paare für die Zuordnungs-Tests (tests/test_phase19.py, fits)."""
import sys
from collections import Counter
from datetime import datetime, timedelta

from sqlalchemy import select

from app.core.db import SessionLocal
from app.models import Recipe, Report


def main(days: int = 30) -> None:
    with SessionLocal() as db:
        rows = db.execute(select(Report, Recipe.title).outerjoin(Recipe, Recipe.id == Report.recipe_id)
                          .where(Report.created_at >= datetime.now() - timedelta(days=days))
                          .order_by(Report.created_at.desc())).all()
    print(f"{len(rows)} Meldungen in {days} Tagen:", dict(Counter(r.kind for r, _ in rows)))
    for r, title in rows:
        print(f"{r.created_at:%d.%m. %H:%M}  {r.kind:15} {title or '-'} | {r.ingredient} {r.offer_title} | {r.note}")
    pairs = {(r.ingredient, r.offer_title) for r, _ in rows if r.kind == "angebot_falsch" and r.offer_title}
    if pairs:
        print("\nTestfälle (Zutat ≠ Angebot):")
        for ing, offer in sorted(pairs):
            print(f'    assert not fits("{ing}", offer(0, "{offer}"))')


if __name__ == "__main__":
    main(int(sys.argv[1]) if len(sys.argv) > 1 else 30)
