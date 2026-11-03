"""Abwechslungsregeln (12) + Regeln für Frühstück (23b) und Lunchbox (24): der Code prüft den Plan, Verstöße werden
als Anweisungen je Slot für die eine Reparatur-Runde zurückgegeben (nur betroffene Slots, günstig)."""
import math
import re
from dataclasses import dataclass, field

from app.models import VARIETY_DEFAULT

MAIN = ("mittag", "lunchbox", "abend")  # zählen für Beilage/Protein/Küche
SIDES = {"pasta": ("Pasta", "max_pasta"), "reis": ("Reis", "max_rice"), "kartoffel": ("Kartoffeln", "max_potato")}
PROTEINS = ("fisch", "rot", "gefluegel", "vegetarisch", "vegan")
DAY_SHORT = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
# Fallback für Gerichte ohne KI-Tags (eigene Rezepte): Stichwörter in Titel/Zutaten
SIDE_WORDS = {"pasta": ("nudel", "pasta", "spaghetti", "penne", "fusilli", "tagliatelle", "lasagne", "gnocchi",
                        "farfalle", "maccheroni", "linguine", "rigatoni", "spätzle", "tortellini", "ravioli"),
              "reis": ("reis", "risotto", "paella"), "kartoffel": ("kartoffel", "pommes", "kroketten", "rösti"),
              "brot": ("brot", "brötchen", "baguette", "toast", "wrap", "tortilla", "pizza", "flammkuchen")}
PROTEIN_WORDS = {"fisch": ("fisch", "lachs", "thunfisch", "kabeljau", "seelachs", "forelle", "garnele", "shrimp",
                           "scampi", "dorade", "hering", "makrele", "tintenfisch", "muschel", "zander", "pangasius"),
                 "rot": ("rind", "schwein", "hack", "lamm", "wild", "speck", "schinken", "salami", "chorizo",
                         "bratwurst", "wurst", "steak", "gulasch", "kotelett", "leberkäse", "gyros"),
                 "gefluegel": ("hähnchen", "huhn", "hühn", "pute", "chicken", "ente", "gans")}
SOUP = re.compile(r"suppe|eintopf|soup", re.I)


@dataclass
class Dish:
    day: int
    meal_type: str
    title: str
    cuisine: str = ""
    side: str = "andere"
    protein: str = "vegetarisch"
    prep_minutes: int = 0
    text: str = ""  # Beschreibung + Schritte (Lunchbox-Prüfung)


def classify(title: str, ingredient_names: list[str]) -> tuple[str, str]:
    """(Beilage, Protein) aus Stichwörtern, wenn ein Rezept keine KI-Tags hat."""
    text = " ".join([title, *ingredient_names]).lower()
    side = next((s for s, ws in SIDE_WORDS.items() if any(w in text for w in ws)), "andere")
    protein = next((p for p, ws in PROTEIN_WORDS.items() if any(w in text for w in ws)), "vegetarisch")
    return side, protein


def tags_of(tags: list[str], title: str, ingredient_names: list[str]) -> tuple[str, str]:
    side = next((t for t in tags if t in (*SIDES, "brot", "andere")), None)
    protein = next((t for t in tags if t in PROTEINS), None)
    if side and protein:
        return side, protein
    guess = classify(title, ingredient_names)
    return side or guess[0], protein or guess[1]


def rules_of(variety: dict | None) -> dict:
    return {**VARIETY_DEFAULT, **(variety or {})}


def scaled(rules: dict, days: int) -> dict:
    """Mindestregeln gelten pro Woche → bei kürzeren Plänen anteilig, kaufmännisch gerundet (2 Tage: 0× Fisch,
    1 vegetarischer Tag); Höchstregeln bleiben."""
    if days >= 7:
        return rules
    return rules | {k: math.floor(rules[k] * days / 7 + 0.5) for k in ("min_fish", "veggie_days")}


def rules_line(rules: dict, fish_ok: bool, days: int = 7) -> str:
    """Kompakte Prompt-Zeile (variabler Teil); days = Plan-Tage mit Hauptgerichten (Mindestregeln anteilig)."""
    rules = scaled(rules, days)
    parts = [f"Pasta max. {rules['max_pasta']}×", f"Reis max. {rules['max_rice']}×",
             f"Kartoffeln max. {rules['max_potato']}×", f"rotes Fleisch max. {rules['max_red_meat']}×"]
    if rules["veggie_days"]:
        parts.append(f"mind. {rules['veggie_days']} vegetarische Tage (alle Hauptgerichte des Tages)")
    if fish_ok and rules["min_fish"]:
        parts.insert(3, f"Fisch mind. {rules['min_fish']}×")
    if rules["no_same_cuisine_row"]:
        parts.append("nie dieselbe Küche an zwei Tagen hintereinander")
    return "Abwechslung pro Woche (Hauptgerichte mittag/abend/lunchbox): " + ", ".join(parts)


@dataclass
class Check:
    issues: list[str] = field(default_factory=list)  # Chip-Texte, z.B. „2× Pasta“
    fixes: dict[tuple[int, str], list[str]] = field(default_factory=dict)  # Slot → Anweisungen für die Reparatur

    def add(self, text: str, slot: tuple[int, str] | None = None, fix: str = ""):
        if text not in self.issues:
            self.issues.append(text)
        if slot and fix and fix not in self.fixes.setdefault(slot, []):
            self.fixes[slot].append(fix)


def check(dishes: list[Dish], rules: dict, fish_ok: bool = True, recent: list[str] = (),
          locked: set[tuple[int, str]] = frozenset()) -> Check:
    """Prüft alle Regeln; Reparatur-Slots bevorzugt spätere Gerichte, fixierte Slots nie."""
    from app.services.planner import similar  # planner importiert dieses Modul
    c = Check()
    order = sorted(dishes, key=lambda d: (d.day, MAIN.index(d.meal_type) if d.meal_type in MAIN else -1))
    main = [d for d in order if d.meal_type in MAIN]
    free = [d for d in main if (d.day, d.meal_type) not in locked]
    rules = scaled(rules, len({d.day for d in main}))

    def slot(d: Dish) -> tuple[int, str]:
        return d.day, d.meal_type

    for side, (name, key) in SIDES.items():
        hits = [d for d in main if d.side == side]
        if len(hits) > rules[key]:
            for d in [h for h in hits if h in free][rules[key] - len(hits):]:
                c.add(f"{len(hits)}× {name}", slot(d), f"Beilage nicht {name}")
    red = [d for d in main if d.protein == "rot"]
    if len(red) > rules["max_red_meat"]:
        extra = len(red) - rules["max_red_meat"]
        for d in [r for r in red if r in free][-extra:]:
            c.add(f"{len(red)}× rotes Fleisch", slot(d), "kein rotes Fleisch")
    fish = [d for d in main if d.protein == "fisch"]
    need_fish = min(rules["min_fish"], len(main)) if fish_ok else 0
    if len(fish) < need_fish:
        candidates = sorted((d for d in free if d.protein != "fisch"),
                            key=lambda d: ("rot", "gefluegel").index(d.protein) if d.protein in ("rot", "gefluegel") else 2)
        for d in candidates[:need_fish - len(fish)]:
            c.add("kein Fisch" if not fish else f"nur {len(fish)}× Fisch", slot(d), "Fischgericht")
    days = sorted({d.day for d in main})
    veggie = [day for day in days if all(d.protein in ("vegetarisch", "vegan") for d in main if d.day == day)]
    need_veg = min(rules["veggie_days"], len(days))
    if len(veggie) < need_veg:
        # Tage ohne Fisch(-Reparatur) und mit den wenigsten Fleischgerichten zuerst vegetarisch machen
        def fishy(day):
            return any(d.day == day and (d.protein == "fisch" or "Fischgericht" in c.fixes.get(slot(d), []))
                       for d in main)
        others = sorted((day for day in days if day not in veggie),
                        key=lambda day: (fishy(day), sum(d.protein not in ("vegetarisch", "vegan")
                                                         for d in main if d.day == day), -day))
        n = len(veggie)
        for day in others[:need_veg - n]:
            for d in main:
                if d.day == day and d.protein not in ("vegetarisch", "vegan") and d in free:
                    c.add({0: "kein vegetarischer Tag", 1: "nur 1 vegetarischer Tag"}.get(n, f"nur {n} vegetarische Tage"),
                          slot(d), "vegetarisch")
    if rules["no_same_cuisine_row"]:
        cuisines = {day: {d.cuisine.strip().lower() for d in main if d.day == day and d.cuisine.strip()} for day in days}
        for day in days:
            same = cuisines.get(day, set()) & cuisines.get(day - 1, set())
            for cuisine in sorted(same):
                for d in main:
                    if d.day == day and d.cuisine.strip().lower() == cuisine and d in free:
                        c.add(f"2× {d.cuisine.strip()} hintereinander", slot(d), f"andere Küche als {d.cuisine.strip()}")
    seen: dict[str, Dish] = {}
    for d in order:
        if d.meal_type == "snack":
            continue  # Snacks dürfen vorgekocht mehrere Tage gleich sein
        key = d.title.strip().lower()
        if key in seen and (d.day, d.meal_type) not in locked:
            c.add(f"2× {d.title}" if d.meal_type != "fruehstueck" else "Frühstück wiederholt sich", slot(d),
                  "anderes Gericht als die übrigen der Woche")
        seen.setdefault(key, d)
        if any(similar(d.title, r) for r in recent) and (d.day, d.meal_type) not in locked:
            c.add(f"Wiederholung: {d.title}", slot(d),
                  f"neues Gericht (nicht in den letzten {rules['repeat_weeks']} Wochen)")
        if d.meal_type == "fruehstueck" and d.prep_minutes > 10:
            c.add("Frühstück über 10 min", slot(d), "einfaches Frühstück, max. 10 min")
        if d.meal_type == "lunchbox" and SOUP.search(d.title) and "thermo" not in d.text.lower():
            c.add("Lunchbox-Suppe ohne Thermobehälter", slot(d), "kalt essbar oder mit Hinweis „im Thermobehälter“")
    return c
