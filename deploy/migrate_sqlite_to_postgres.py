"""Einmaliger Daten-Umzug SQLite → Postgres (Spezifikation 72, E86).

Ziel = DATABASE_URL, per `alembic upgrade head` angelegt und leer; beide auf derselben Alembic-Revision.
Kopiert alle Modell-Tabellen in Fremdschlüssel-Reihenfolge, zieht die id-Sequenzen nach, legt den Volltextindex
für `food` an und vergleicht am Ende die Zeilenzahlen (Exit 1 bei Abweichung).

VPS (setup-vps.sh macht das):  docker compose run --rm -v ./import:/import:ro -v ./migrate_sqlite_to_postgres.py:/m.py:ro \
                                   api python /m.py /import/essenapp.db
Lokal (Test):                  cd backend && DATABASE_URL=postgresql+psycopg://… ./dev.sh python ../deploy/migrate_sqlite_to_postgres.py <kopie.db>
"""
import os
import sys

sys.path.insert(0, os.getcwd())  # backend/ bzw. /app im Container

from sqlalchemy import create_engine, func, insert, select, text  # noqa: E402
from sqlalchemy.orm import Session  # noqa: E402

from app import models  # noqa: E402,F401  registriert alle Tabellen
from app.core.config import settings  # noqa: E402
from app.core.db import Base  # noqa: E402
from app.tools.import_usda import rebuild_fts  # noqa: E402

BATCH = 1000


def counts(conn, tables) -> dict[str, int]:
    return {t.name: conn.scalar(select(func.count()).select_from(t)) for t in tables}


def main(sqlite_path: str) -> None:
    if not os.path.isfile(sqlite_path):
        sys.exit(f"SQLite-Datei fehlt: {sqlite_path}")
    src = create_engine(f"sqlite:///file:{os.path.abspath(sqlite_path)}?mode=ro&uri=true")  # nur lesen
    dst = create_engine(settings.database_url)
    if dst.dialect.name != "postgresql":
        sys.exit(f"DATABASE_URL ist kein Postgres: {dst.url.render_as_string(hide_password=True)}")
    tables = Base.metadata.sorted_tables  # Eltern vor Kindern

    with src.connect() as s, dst.begin() as d:
        version = "SELECT version_num FROM alembic_version"
        if (sv := s.scalar(text(version))) != (dv := d.scalar(text(version))):
            sys.exit(f"Alembic-Revision verschieden: SQLite {sv}, Postgres {dv} – erst beide auf denselben Stand")
        if any(counts(d, tables).values()):
            sys.exit("Postgres ist nicht leer – Abbruch (Umzug läuft nur einmal in eine frische Datenbank)")
        known = {t.name for t in tables} | {"alembic_version"}
        if extra := [n for n in s.scalars(text("SELECT name FROM sqlite_master WHERE type = 'table'"))
                     if n not in known and not n.startswith(("food_fts", "sqlite_"))]:
            sys.exit(f"Tabellen ohne Modell in SQLite (würden fehlen): {extra}")

        for t in tables:
            rows, n = s.execute(select(t)).mappings(), 0  # Typen aus den Modellen: bool, JSON, Datum
            while chunk := [dict(r) for r in rows.fetchmany(BATCH)]:
                d.execute(insert(t), chunk)
                n += len(chunk)
            print(f"{t.name}: {n}")

        for t in tables:  # nächste id = max(id) + 1
            if "id" in t.c and (seq := d.scalar(text("SELECT pg_get_serial_sequence(:t, 'id')"), {"t": t.name})):
                d.execute(text(f'SELECT setval(:s, COALESCE((SELECT MAX(id) FROM "{t.name}"), 0) + 1, false)'),
                          {"s": seq})
        rebuild_fts(Session(bind=d))

    with src.connect() as s, dst.connect() as d:
        before, after = counts(s, tables), counts(d, tables)
    diff = {name: (before[name], after[name]) for name in before if before[name] != after[name]}
    print(f"Zählvergleich: {len(tables)} Tabellen, {sum(after.values())} Zeilen, "
          + (f"ABWEICHUNG {diff}" if diff else "alles gleich"))
    for name in ("household", "member", "meal_plan", "shopping_list", "recipe"):
        print(f"  {name}: {after[name]}")
    sys.exit(1 if diff else 0)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
