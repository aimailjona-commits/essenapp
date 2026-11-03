"""USDA FoodData Central → Tabelle `food` (2). Daten gemeinfrei (CC0 1.0), siehe fdc.nal.usda.gov/api-guide.
Aufruf: ./dev.sh python -m app.tools.import_usda
Lädt die offiziellen CSV-Bulk-Downloads (Foundation Foods + SR Legacy) in ein temporäres Verzeichnis, liest nur
food.csv und food_nutrient.csv direkt aus dem ZIP und baut danach die Volltextsuche neu auf."""
import csv
import io
import logging
import sys
import tempfile
import zipfile
from pathlib import Path

import httpx
from sqlalchemy import delete, text
from sqlalchemy.orm import Session

from app.core.db import SessionLocal
from app.models import Food

log = logging.getLogger(__name__)
BASE = "https://fdc.nal.usda.gov/fdc-datasets/"
# Links von fdc.nal.usda.gov/download-datasets (Stand 2026-11-02). Das CSV-ZIP vom Oktober 2026 enthält dort
# (noch) kein food.csv/food_nutrient.csv → es wird das erste vollständige genommen.
SOURCES = [("FoodData_Central_foundation_food_csv_2026-10-29.zip", "FoodData_Central_foundation_food_csv_2026-04-30.zip"),
           ("FoodData_Central_sr_legacy_food_csv_2018-04.zip",)]
TYPES = {"foundation_food", "sr_legacy_food"}
# Spalte → USDA-Nährstoff-IDs (nutrient.csv), erste vorhandene zählt
NUTRIENTS = {"kcal": (1008, 2048, 2047), "protein": (1003,), "fat": (1004, 1085), "carbs": (1005, 1050),
             "fiber": (1079,), "sugar": (2000, 1063), "sodium_mg": (1093,)}
WANTED = {i for ids in NUTRIENTS.values() for i in ids}


def _member(zf: zipfile.ZipFile, name: str) -> str | None:
    return next((n for n in zf.namelist() if n.rsplit("/", 1)[-1] == name), None)


def _rows(zf: zipfile.ZipFile, name: str):
    with zf.open(_member(zf, name)) as f:
        yield from csv.DictReader(io.TextIOWrapper(f, "utf-8"))


def complete(path: Path) -> bool:
    with zipfile.ZipFile(path) as zf:
        return all(_member(zf, n) for n in ("food.csv", "food_nutrient.csv"))


def parse(path: Path) -> list[dict]:
    """Lebensmittel mit Nährwerten pro 100 g aus einem FDC-CSV-ZIP (nur Foundation/SR Legacy)."""
    with zipfile.ZipFile(path) as zf:
        foods = {int(r["fdc_id"]): (r["description"][:300], r["data_type"])
                 for r in _rows(zf, "food.csv") if r["data_type"] in TYPES}
        values: dict[int, dict[int, float]] = {}
        for r in _rows(zf, "food_nutrient.csv"):
            fdc, nid = int(r["fdc_id"]), int(r["nutrient_id"])
            if fdc in foods and nid in WANTED and r["amount"] != "":
                values.setdefault(fdc, {})[nid] = float(r["amount"])
    out = []
    for fdc, (description, data_type) in foods.items():
        v = values.get(fdc, {})
        row = {k: next((v[i] for i in ids if i in v), None) for k, ids in NUTRIENTS.items()}
        sodium = row.pop("sodium_mg")
        row["salt"] = round(sodium * 2.5 / 1000, 3) if sodium is not None else None
        if row["kcal"] is None and row["protein"] is None:
            continue  # ohne Kernwerte nutzlos
        out.append({"id": fdc, "description": description, "data_type": data_type.removesuffix("_food"), **row})
    return out


def rebuild_fts(db: Session) -> None:
    """Volltextindex für food_map.search: SQLite FTS5 (lokal), Postgres GIN-Index auf tsvector (VPS, 72)."""
    if db.get_bind().dialect.name == "postgresql":  # USDA-Beschreibungen sind englisch
        db.execute(text("CREATE INDEX IF NOT EXISTS food_fts ON food USING gin (to_tsvector('english', description))"))
        return
    db.execute(text("CREATE VIRTUAL TABLE IF NOT EXISTS food_fts USING fts5(description, content='food', "
                    "content_rowid='id')"))
    db.execute(text("INSERT INTO food_fts(food_fts) VALUES('rebuild')"))


def store(db: Session, foods: list[dict]) -> int:
    """Ersetzt den Inhalt von `food` (FDC-IDs bleiben gleich, ingredient_map bleibt gültig)."""
    db.execute(delete(Food))
    db.bulk_insert_mappings(Food, foods)
    rebuild_fts(db)
    db.commit()
    return len(foods)


def download(name: str, folder: Path) -> Path:
    path = folder / name
    with httpx.stream("GET", BASE + name, timeout=120, follow_redirects=True) as r:
        r.raise_for_status()
        with path.open("wb") as f:
            for chunk in r.iter_bytes():
                f.write(chunk)
    return path


def main() -> None:
    foods = []
    with tempfile.TemporaryDirectory(prefix="usda-") as tmp:
        for candidates in SOURCES:
            for name in candidates:
                path = download(name, Path(tmp))
                if complete(path):
                    part = parse(path)
                    log.info("%s: %d Lebensmittel", name, len(part))
                    foods += part
                    break
                log.warning("%s ist unvollständig (kein food.csv/food_nutrient.csv), nehme das nächste", name)
            else:
                sys.exit(f"Kein vollständiger Download für {candidates[0]}")
    with SessionLocal() as db:
        print(f"{store(db, foods)} Lebensmittel importiert")


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    main()
