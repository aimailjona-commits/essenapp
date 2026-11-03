"""Laden-Empfehlung (42): offene Listenartikel in allen Kombinationen aus höchstens 2 Läden rechnen
(Angebot dieses Ladens, sonst Normalpreis dieses Ladens, sonst Normalpreis-Schätzung irgendeines Ladens)."""
import math
from itertools import combinations

from app.models import Offer, ShoppingItem
from app.services.matching import Matcher
from app.services.normalize import base_unit
from app.services.recipes import convert


def packs(item: ShoppingItem, o: Offer) -> int:
    """Ganze Packungen für die Menge des Artikels; ohne umrechenbare Menge 1 Packung."""
    if item.amount and item.unit and o.amount:
        amount, unit = base_unit(item.amount, item.unit)
        if (n := convert(amount, unit or item.unit, o.unit or "stk", None)) is not None:
            return max(1, math.ceil(n / o.amount - 1e-9))
    return 1


class Prices:
    """Preis je Artikel und Laden (ganze Packungen) → (Cent, offer_id | None)."""

    def __init__(self, offers: list[Offer], history: list[Offer], chains: list[str]):
        self.now = {c: Matcher([o for o in offers if o.chain == c], False) for c in chains}
        self.hist = {c: Matcher([o for o in history if o.chain == c], False) for c in chains}
        self.any = Matcher(history, False)

    def of(self, item: ShoppingItem) -> dict[str, tuple[int, int | None]]:
        out = {}
        fallback = None
        for c in self.now:
            found = [(packs(item, o) * o.price_cents, o.id) for o in self.now[c].find(item.name)]
            if not found:
                found = [(packs(item, o) * (o.regular_price_cents or o.price_cents), None)
                         for o in self.hist[c].find(item.name)]
            if not found:
                if fallback is None:
                    fallback = min(((packs(item, o) * (o.regular_price_cents or o.price_cents), None)
                                    for o in self.any.find(item.name)), default=())
                found = [fallback] if fallback else []
            if found:
                out[c] = min(found)
        return out


def km(a: tuple[float, float], b: tuple[float, float]) -> float:
    """Luftlinie (Haversine)."""
    la1, lo1, la2, lo2 = map(math.radians, (*a, *b))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 2 * 6371 * math.asin(math.sqrt(h))


def route_km(home: tuple | None, stops: list[tuple | None]) -> float | None:
    """Rundweg Zuhause → Läden → Zuhause (Luftlinie), None ohne Koordinaten."""
    if home is None or any(s is None for s in stops):
        return None
    path = [home, *stops, home]
    return round(sum(km(a, b) for a, b in zip(path, path[1:])), 1)


def combos(items: list[ShoppingItem], prices: Prices, chains: list[str], home: tuple | None = None,
           coords: dict[str, tuple] | None = None) -> list[dict]:
    """Alle Läden einzeln + alle Paare, günstigste zuerst. assignment {item_id: (chain, offer_id, cents)};
    total_cents = Summe der Artikel (gleiche Zahlen wie nach „So aufteilen“)."""
    coords = coords or {}
    table = {i.id: prices.of(i) for i in items}
    out = []
    for combo in [*([c] for c in chains), *map(list, combinations(chains, 2))]:
        assignment, unpriced = {}, 0
        for i in items:
            options = [(table[i.id][c][0], c, table[i.id][c][1]) for c in combo if c in table[i.id]]
            if not options:
                unpriced += 1
                continue
            cents, c, offer_id = min(options)
            assignment[i.id] = (c, offer_id, cents)
        per_store = {c: sum(v[2] for v in assignment.values() if v[0] == c) for c in combo}
        out.append({"chains": combo, "total_cents": sum(per_store.values()), "per_store": per_store,
                    "unpriced": unpriced, "assignment": assignment,
                    "distance_km": route_km(home, [coords.get(c) for c in combo])})
    out.sort(key=lambda r: (r["total_cents"], len(r["chains"])))
    singles = [r for r in out if len(r["chains"]) == 1]
    best = singles[0] if singles else None
    for r in out:
        r["saved_cents"] = best["total_cents"] - r["total_cents"] if best else 0
        r["extra_km"] = (round(r["distance_km"] - best["distance_km"], 1)
                         if best and r["distance_km"] is not None and best["distance_km"] is not None else None)
    return out
