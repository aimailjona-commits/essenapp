"""Woche per Swipe (Phase 20, E97): Abstimmung, Fortschritt und Verteilen auf die Woche – ohne KI."""
import random
from dataclasses import dataclass

from app.models import SwipeCard, SwipeVote
from app.services import variety
from app.services.pricing import shelf_days, stock_key

REPEAT = ("fruehstueck", "snack")  # ein gemochtes Gericht darf an mehreren Tagen kommen
TRIES = 300  # zufällige Reihenfolgen je Verteilung; die mit den wenigsten Verstößen gewinnt
PERISHABLE = {"fisch": 2, "rot": 1, "gefluegel": 1}  # Strafe je Tag Verspätung: Frisches früh in der Woche


@dataclass
class Tally:
    card: SwipeCard
    yes: int = 0
    no: int = 0
    out: bool = False  # „Mag ich nicht“ von irgendwem → für alle raus
    days: int = 1

    @property
    def chosen(self) -> bool:
        return self.yes > 0 and not self.out

    @property
    def match(self) -> bool:
        """Alle, die abgestimmt haben, mögen es – erst ab zwei Stimmen ein Match."""
        return self.yes >= 2 and self.no == 0 and not self.out


def tally(cards: list[SwipeCard], votes: list[SwipeVote]) -> dict[int, Tally]:
    out = {c.id: Tally(c) for c in cards}
    for v in votes:
        t = out.get(v.card_id)
        if t is None:
            continue
        if v.vote == "ja":
            t.yes += 1
            t.days = max(t.days, v.days or 1)
        elif v.vote == "nein":
            t.no += 1
        else:
            t.out = True
    return out


def ranked(tallies: dict[int, Tally], meal_type: str) -> list[Tally]:
    """Gewählte Karten einer Mahlzeitart: Matches zuerst, dann mehr Ja-Stimmen, dann günstiger."""
    return sorted((t for t in tallies.values() if t.card.meal_type == meal_type and t.chosen),
                  key=lambda t: (not t.match, -t.yes, t.card.cost_cents, t.card.position))


def progress(need: dict[str, int], tallies: dict[int, Tally]) -> dict[str, int]:
    """Belegte Plätze je Mahlzeitart (Frühstück/Snack zählen Tage), höchstens so viele wie gebraucht."""
    return {m: min(n, sum(t.days if m in REPEAT else 1 for t in ranked(tallies, m))) for m, n in need.items()}


def pending(cards: list[SwipeCard], votes: list[SwipeVote], member_id: int, tallies: dict[int, Tally]) -> list[SwipeCard]:
    """Karten, über die dieses Mitglied noch nicht entschieden hat (ohne die, die jemand nicht mag)."""
    mine = {v.card_id for v in votes if v.member_id == member_id}
    return [c for c in cards if c.id not in mine and not tallies[c.id].out]


def _dish(day: int, meal_type: str, c: SwipeCard) -> variety.Dish:
    return variety.Dish(day, meal_type, c.title, c.cuisine, c.side, c.protein, c.prep_minutes, c.description)


def fresh_keys(c: SwipeCard, recipe_ingredients: list[dict] = ()) -> set[str]:
    """Frische Hauptzutaten (Reste-Ketten): Schlüssel der Zutaten mit kurzer Haltbarkeit."""
    return {stock_key(i["name"]) for i in (c.ingredients or recipe_ingredients) if shelf_days(i["name"])}


def score(assign: dict[tuple[int, str], SwipeCard], rules: dict, fish_ok: bool, fresh: dict[int, set[str]]) -> int:
    """Kleiner ist besser: Abwechslungsregeln (Hauptgerichte), Frisches spät in der Woche, gemeinsame frische
    Zutaten in den nächsten zwei Tagen (Reste-Kette) als Bonus."""
    main = [_dish(d, m, c) for (d, m), c in assign.items() if m in variety.MAIN]
    total = 10 * len(variety.check(main, rules, fish_ok).issues)
    total += sum(PERISHABLE.get(c.protein, 0) * d for (d, m), c in assign.items() if m in variety.MAIN)
    items = sorted(assign.items())
    for i, ((d1, _), c1) in enumerate(items):
        for (d2, _), c2 in items[i + 1:]:
            if c1.id != c2.id and 0 < d2 - d1 <= 2 and fresh.get(c1.id, set()) & fresh.get(c2.id, set()):
                total -= 3
    return total


def distribute(tallies: dict[int, Tally], slots: list[tuple[int, str]], fixed: dict[tuple[int, str], int],
               rules: dict, fish_ok: bool, seed: int = 0, fresh: dict[int, set[str]] | None = None
               ) -> tuple[dict[tuple[int, str], int], list[int]]:
    """Gewählte Karten auf die freien Slots (fixed = vom Nutzer gesetzt, bleibt). Pro Mahlzeitart die besten Karten
    nach Rang; Frühstück/Snack mit ihren Tagen am Stück. Reihenfolge: viele zufällige Versuche (seed = „Neu
    mischen“), der mit dem kleinsten score gewinnt. → ({Slot: card_id}, Reserve-IDs)"""
    rng = random.Random(seed)
    fresh = fresh or {}
    by_id = {t.card.id: t.card for t in tallies.values()}
    units: dict[str, list[SwipeCard]] = {}
    reserve: list[int] = []
    free: dict[str, list[tuple[int, str]]] = {}
    for s in slots:
        if s not in fixed:
            free.setdefault(s[1], []).append(s)
    for m, places in free.items():
        used = [by_id[cid] for (d, mt), cid in fixed.items() if mt == m and cid in by_id]
        pool = []
        for t in ranked(tallies, m):
            left = (t.days if m in REPEAT else 1) - sum(1 for c in used if c.id == t.card.id)
            pool += [t.card] * max(left, 0)
        units[m] = pool[:len(places)]
        taken = {c.id for c in units[m]} | {c.id for c in used}
        reserve += [t.card.id for t in ranked(tallies, m) if t.card.id not in taken]
    base = {s: by_id[cid] for s, cid in fixed.items() if cid in by_id}
    best, best_score = None, None
    for _ in range(TRIES):
        assign = dict(base)
        for m, places in free.items():
            pool = list(units[m])
            if m not in REPEAT:  # Frühstück/Snack bleiben am Stück (Müsli Mo–Fr, Rührei Sa+So)
                rng.shuffle(pool)
            assign.update(zip(sorted(places), pool))
        sc = score(assign, rules, fish_ok, fresh)
        if best is None or sc < best_score:
            best, best_score = assign, sc
    return {s: c.id for s, c in (best or {}).items()}, reserve
