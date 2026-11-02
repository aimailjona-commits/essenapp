"""Zuordnung deutscher Zutatennamen → USDA-Eintrag (2): englische Suchanfrage (Haiku) → Volltextsuche Top 10 →
Haiku wählt. Ergebnis einmalig in `ingredient_map` (Cache). Läuft im Hintergrund, blockiert keine Anfrage."""
import logging
import re
import threading
from collections.abc import Callable
from typing import Literal

import anthropic
from pydantic import BaseModel
from sqlalchemy import func, select, text
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.db import SessionLocal
from app.models import Food, IngredientMap
from app.services.matching import words
from app.services.normalize import ingredient_key
from app.services.planner import cost_cents

log = logging.getLogger(__name__)
CHUNK, CANDIDATES = 25, 10
# Stückgewichte (essbarer Teil, g); Schlüssel wie matching.words (Wortende zählt: „Gemüsezwiebel“ → zwiebel)
PIECE_G = {"ei": 55, "eier": 55, "zwiebel": 100, "schalotte": 30, "knoblauchzeh": 4, "knoblauch": 4, "tomat": 120,
           "kartoffel": 150, "paprika": 160, "paprikaschot": 160, "karott": 80, "möhr": 80, "zitron": 100,
           "limett": 60, "apfel": 150, "birn": 170, "orang": 180, "banan": 120, "gurk": 400, "zucchini": 250,
           "aubergin": 300, "avocado": 150, "brötchen": 60, "tortilla": 60, "wrap": 60, "frühlingszwiebel": 15,
           "lauchzwiebel": 15, "chili": 10, "chilischot": 10, "champignon": 20, "lauch": 200, "brokkoli": 400,
           "blumenkohl": 600, "mozzarella": 125, "ingwer": 20}


class Translation(BaseModel):
    name: str
    query: str
    grams_per_piece: float | None


class Translations(BaseModel):
    items: list[Translation]


class Choice(BaseModel):
    name: str
    food_id: int | None
    confidence: Literal["hoch", "mittel", "niedrig"]


class Choices(BaseModel):
    items: list[Choice]


TRANSLATE = """Übersetze deutsche Zutatennamen in eine englische Suchanfrage für die USDA-Nährwertdatenbank:
2–4 Wörter, Grundzutat in roher/unverarbeiteter Form, wenn üblich (z.B. "Hähnchenbrust" → "chicken breast raw",
"Passierte Tomaten" → "tomato puree canned"). grams_per_piece: typisches Gewicht eines Stücks in g (essbarer Teil),
wenn die Zutat auch stückweise verwendet wird, sonst null. Für jeden Namen genau ein Eintrag, name unverändert.

"""
CHOOSE = """Wähle für jede deutsche Zutat den passenden USDA-Eintrag aus ihren Kandidaten (id|Beschreibung).
Roh/unverarbeitet bevorzugen, außer die Zutat ist verarbeitet (Dose, gekocht, Pulver …). food_id null, wenn keiner
passt. confidence: hoch, mittel oder niedrig. Für jede Zutat genau ein Eintrag, name unverändert.

"""


def piece_g(key: str) -> float | None:
    ws = words(key)
    last = ws[-1] if ws else ""
    return next((g for k, g in PIECE_G.items() if last == k or (len(k) >= 4 and last.endswith(k))), None)


def ask_claude(prompt: str | list[dict], schema: type[BaseModel]) -> tuple[BaseModel, dict]:
    """Haiku (MODEL_FAST) mit strukturierter Ausgabe; prompt = Text oder Inhaltsblöcke (z.B. Bilder). Auch für Import,
    Kühlschrank-Scan und „Was koche ich jetzt?“ (5/69)."""
    client = anthropic.Anthropic(api_key=settings.anthropic_api_key or None)
    response = client.messages.parse(model=settings.model_fast, max_tokens=8000, output_config={"effort": "low"},
                                     messages=[{"role": "user", "content": prompt}], output_format=schema)
    u = response.usage
    usage = {"model": response.model, "input_tokens": u.input_tokens, "output_tokens": u.output_tokens,
             "cache_read_input_tokens": u.cache_read_input_tokens or 0,
             "cache_creation_input_tokens": u.cache_creation_input_tokens or 0}
    usage["cost_cents"] = cost_cents(usage)
    log.info("KI-Aufruf %s: %s", schema.__name__, usage)
    if response.stop_reason != "end_turn" or response.parsed_output is None:
        raise RuntimeError(f"KI-Antwort unbrauchbar (stop_reason={response.stop_reason})")
    return response.parsed_output, usage


def search(db: Session, query: str, limit: int = CANDIDATES) -> list[Food]:
    """Volltextsuche (SQLite FTS5, von tools.import_usda angelegt): alle Wörter, sonst irgendeins, beste zuerst."""
    terms = [f'"{t}"' for t in re.findall(r"[a-z]+", query.lower())]
    ids: list[int] = []
    for q in (" ".join(terms), " OR ".join(terms)) if terms else ():
        for i in db.execute(text("SELECT rowid FROM food_fts WHERE food_fts MATCH :q ORDER BY rank LIMIT :n"),
                            {"q": q, "n": limit}).scalars():
            if i not in ids:
                ids.append(i)
        if len(ids) >= limit:
            break
    return [db.get(Food, i) for i in ids[:limit]]


def map_missing(db: Session, names: list[str],
                ask: Callable[[str, type[BaseModel]], tuple[BaseModel, dict]] | None = None) -> int:
    """Ordnet noch unbekannte Zutaten zu und speichert sie (auch „kein Treffer“). Gibt die Zahl neuer Einträge zurück."""
    ask = ask or ask_claude
    todo = {ingredient_key(n): n.strip() for n in names if n.strip()}
    known = set(db.scalars(select(IngredientMap.ingredient_key).where(IngredientMap.ingredient_key.in_(todo))))
    todo = {k: n for k, n in todo.items() if k not in known}
    if not todo:
        return 0
    if not db.scalar(select(func.count()).select_from(Food)):
        log.warning("Tabelle food ist leer – erst `python -m app.tools.import_usda` ausführen")
        return 0
    added = 0
    items = list(todo.items())
    for start in range(0, len(items), CHUNK):
        chunk = dict(items[start:start + CHUNK])
        tr, _ = ask(TRANSLATE + "\n".join(chunk.values()), Translations)
        queries = {ingredient_key(t.name): t for t in tr.items if ingredient_key(t.name) in chunk}
        candidates = {k: search(db, t.query) for k, t in queries.items()}
        blocks = [f"Zutat: {chunk[k]}\n" + "\n".join(f"{f.id}|{f.description}" for f in foods)
                  for k, foods in candidates.items() if foods]
        choices = {}
        if blocks:
            ch, _ = ask(CHOOSE + "\n\n".join(blocks), Choices)
            choices = {ingredient_key(c.name): c for c in ch.items}
        for k, t in queries.items():
            c = choices.get(k)
            if candidates[k] and c is None:
                continue  # Antwort fehlt → beim nächsten Mal erneut
            allowed = {f.id for f in candidates[k]}
            food_id = c.food_id if c and c.food_id in allowed else None
            gpp = piece_g(k) or (t.grams_per_piece if t.grams_per_piece and 0 < t.grams_per_piece < 5000 else None)
            db.add(IngredientMap(ingredient_key=k, food_id=food_id, grams_per_piece=gpp,
                                 confidence=c.confidence if food_id else "niedrig"))
            added += 1
        db.commit()
    return added


_lock = threading.Lock()


def _run(names: list[str]) -> None:
    with _lock, SessionLocal() as db:  # nacheinander, damit keine Zutat doppelt angelegt wird
        try:
            log.info("Zutaten-Zuordnung: %s neu", map_missing(db, names))
        except Exception:
            log.exception("Zutaten-Zuordnung fehlgeschlagen")


def map_later(names: list[str]) -> None:
    """Zuordnung im Hintergrund starten (nicht blockierend); bis sie fertig ist, sind Nährwerte null."""
    if names := list(dict.fromkeys(names)):
        threading.Thread(target=_run, args=(names,), name="food_map", daemon=True).start()


def load(db: Session, names: list[str]) -> dict:
    """ingredient_key → (IngredientMap, Food | None) für die vorhandenen Zuordnungen."""
    keys = {ingredient_key(n) for n in names}
    rows = db.execute(select(IngredientMap, Food).outerjoin(Food, Food.id == IngredientMap.food_id)
                      .where(IngredientMap.ingredient_key.in_(keys))).all()
    return {m.ingredient_key: (m, f) for m, f in rows}


def piece_grams(db: Session, names: list[str]) -> dict[str, float]:
    """Stückgewicht je ingredient_key: Zuordnung (Tabelle/KI) oder Tabelle."""
    maps = load(db, names)
    out = {}
    for n in names:
        k = ingredient_key(n)
        if g := (maps[k][0].grams_per_piece if k in maps else None) or piece_g(k):
            out[k] = g
    return out
