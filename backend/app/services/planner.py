"""KI-Wochenplan: Claude plant Gerichte rund um die Angebote, der Code rechnet die Kosten (E10)."""
import logging
import math
import re
from difflib import SequenceMatcher
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from typing import Literal

import anthropic
from pydantic import BaseModel, ConfigDict, ValidationError

from app.core.config import settings
from app.models import AiCost, Household, MemberProfile, Offer, PantryItem
from app.services import recipe_images, variety
from app.services.matching import fits, is_a, stem
from app.services.normalize import cents
from app.services.pricing import Pack, Stock, cost_line, pack_amount, shelf_days, stock_key
from app.sources.kaufda import SUBCATEGORIES, TRAPS

logger = logging.getLogger(__name__)

# im Generator wählbar (Snack: 23c); lunchbox (24) und vorspeise (Festtagsmenü, 25) legt der Planer selbst an
MEAL_TYPES = {"fruehstueck": "Frühstück", "mittag": "Mittagessen", "abend": "Abendessen", "snack": "Snack",
              "dessert": "Dessert"}
SLOT_ORDER = ["fruehstueck", "lunchbox", "mittag", "snack", "vorspeise", "abend", "dessert"]  # Reihenfolge am Tag
MealKind = Literal["fruehstueck", "lunchbox", "mittag", "snack", "vorspeise", "abend", "dessert"]
DAYS = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]
FOOD_CATEGORIES = ("fleisch_fisch", "obst_gemuese", "kuehlung", "vorrat", "sonstiges")  # ohne Getränke/Drogerie/Haushalt
MAX_OFFERS = 120
PART_SLOTS = 6  # 19.6: größere Wochen in Tagesblöcken parallel planen
# Cent pro Mio. Tokens (Eingabe, Ausgabe, Cache-Lesen), Prompts bis 100K Tokens; Cache-Schreiben = 1,25 × Eingabe.
PRICES = {"claude-haiku-5-5": (10, 50, 1), "claude-sonnet-5-5": (200, 1000, 20), "claude-opus-5-5": (400, 2000, 20)}
USAGE_KEYS = ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens", "output_tokens", "cost_cents")


class PlannedIngredient(BaseModel):
    name: str
    amount: float
    unit: Literal["g", "ml", "stk"]
    offer_id: int | None
    pack_amount: float
    pack_price_cents: int
    in_pantry: bool


class PlannedMeal(BaseModel):
    # Schema für Claude: image_query trotz Default Pflicht (Felder mit Default würde das Modell sonst gern weglassen)
    model_config = ConfigDict(json_schema_mode_override="serialization", json_schema_serialization_defaults_required=True)

    day: int
    meal_type: MealKind
    title: str
    description: str
    cuisine: str
    prep_minutes: int
    servings: int
    ingredients: list[PlannedIngredient]
    steps: list[str]
    image_query: str = ""  # englische Suchbegriffe fürs Foto; Default, weil api.py Gerichte aus der DB nachbaut
    side: Literal["pasta", "reis", "kartoffel", "brot", "andere"] = "andere"  # Abwechslung (12)
    protein: Literal["fisch", "rot", "gefluegel", "vegetarisch", "vegan"] = "vegetarisch"


class PlanDraft(BaseModel):
    meals: list[PlannedMeal]


SYSTEM = """Du planst Wochengerichte für einen deutschen Haushalt, der sparen will.
Regeln:
- Baue die Gerichte so weit wie möglich aus den Angeboten der Woche. Für eine Zutat aus der Angebotsliste setze offer_id auf deren ID, sonst null.
  offer_id nur, wenn das Produkt genau diese Zutat ist (Joghurt ≠ Käse, Milch ≠ Haferdrink, Käse ≠ Frischkäse).
- pack_amount/pack_price_cents: übliche Packungsgröße und Preis in Cent. Bei Angeboten den Angebotspreis, sonst eine realistische Schätzung des deutschen Normalpreises (Discounter-Niveau).
- in_pantry=true nur für Basics und typische Vorratszutaten (Salz, Pfeffer, Öl, Essig, Gewürze, Zucker, Mehl, Brühe).
- Vorrat zuerst verwenden, bald ablaufende Sachen zuerst; gleiche Namen und Einheiten wie im Vorrat.
- Mengen je Mahlzeit für die dort angegebenen Portionen (1 Portion = Esser mit 2000 kcal/Tag). Einheiten nur g, ml oder stk.
  Brot/Toast in g (1 Scheibe ≈ 40 g), pack_amount immer in derselben Einheit wie amount.
- Nutze Zutaten über mehrere Gerichte, damit wenig übrig bleibt (z.B. halbe Packung Feta am nächsten Tag): angebrochene
  frische Packungen (Fleisch, Gemüse, Obst, Milchprodukte) in den nächsten 1–3 Tagen ganz aufbrauchen; keine
  Großpackung (z.B. 2 kg Obst, 1 kg Fleisch), wenn die Woche sie nicht verbraucht.
- Ernährungsform, Allergien und Ausschlüsse sind harte Regeln. Kochzeit nicht überschreiten.
- Alle Texte auf Deutsch. Schritte kurz und konkret, 3–8 Schritte.
- Jede Zutat, die in den Schritten vorkommt, steht in ingredients (außer Wasser); eine Zutat, die mehrfach gebraucht
  wird, nur einmal mit der Gesamtmenge.
- image_query: 2–4 englische Suchbegriffe für ein Foto des Gerichts, z.B. "chicken tikka masala".
- side = Hauptbeilage (pasta, reis, kartoffel, brot, andere); protein = fisch, rot (Rind, Schwein, Lamm, Wild),
  gefluegel, vegetarisch oder vegan.
- fruehstueck: einfach aus Bausteinen (Basis + Topping + Obst/Gemüse), max. 10 min, jeden Tag anders.
- snack: transportierbar, passend zum Ziel (proteinreich z.B. Skyr, Nüsse; kalorienarm z.B. Gemüsesticks mit Hummus).
  Vorkochen für mehrere Tage erlaubt (gleicher Snack an diesen Tagen, erster Schritt „Vorkochen am <Tag> für <n> Tage: …“).
- lunchbox: Essen für die Arbeit, kalt essbar oder gut aufwärmbar, transportsicher, am Vorabend vorbereitbar (erster
  Schritt „Am Vorabend: …“). Suppen/Eintöpfe nur mit Hinweis „im Thermobehälter“.
- Mahlzeiten mit Gästen: gästetauglich (gut teilbar, nicht zu experimentell).
- „verwende Rest …“: diese Zutat mit gleichem Namen, gleicher offer_id und mindestens dieser Menge einplanen (Rest ganz
  aufbrauchen, Mengen der anderen Zutaten anpassen).
- Plane genau die genannten Mahlzeiten, nicht mehr und nicht weniger."""


# Richtung beim Neu-Würfeln (19.3) → Zusatz im Auftrag
DIRECTIONS = {"schneller": "Höchstens 20 Minuten Kochzeit, wenige Schritte.",
              "guenstiger": "Deutlich günstiger als das alte Gericht: Angebote, einfache Zutaten.",
              "ohne_fleisch": "Vegetarisch, ohne Fleisch und Fisch.",
              "leichter": "Leichter und kalorienärmer, viel Gemüse.",
              "anders": "Ganz andere Küche und Hauptzutat als das alte Gericht."}


@dataclass
class PricedPlan:
    draft: PlanDraft
    total_cents: int
    saved_cents: int
    meal_costs: list[int]
    usage: dict = field(default_factory=dict)
    images: list[str] = field(default_factory=list)  # Foto-URL je Gericht in draft.meals, "" = keins
    # Reste (19): badges {"Tag|Mahlzeit": {Zutat: Tag des Anbruchs}}, after {"Tag|Mahlzeit": [Rest nach dem Kochen]},
    # left [übrige frische Reste am Wochenende], planned = frische Reste, die ein späteres Gericht verwendet
    rests: dict = field(default_factory=dict)


def select_offers(offers: list[Offer], limit: int = MAX_OFFERS) -> list[Offer]:
    """Vorauswahl für den Prompt: nur Lebensmittel, keine Titel-Dubletten, Rabatt und bekannte Menge zuerst,
    reihum je Kategorie, damit jede Kategorie gleich viele Plätze bekommt."""
    queues: dict[str, list[Offer]] = {c: [] for c in FOOD_CATEGORIES}
    seen = set()
    for o in sorted(offers, key=lambda o: (o.regular_price_cents is None, o.amount is None, o.price_cents, o.id or 0)):
        title = o.title.strip().lower()
        if o.category in queues and title not in seen:
            seen.add(title)
            queues[o.category].append(o)
    picked, rank = [], 0
    while len(picked) < limit and any(len(q) > rank for q in queues.values()):
        picked += [q[rank] for q in queues.values() if len(q) > rank][:limit - len(picked)]
        rank += 1
    return picked


def cost_cents(usage: dict) -> float:
    """Geschätzte Kosten eines Aufrufs in Cent (Bruchteile, darum float; kein Geldbetrag der App)."""
    model = usage.get("model", "")
    p_in, p_out, p_read = next((p for k, p in PRICES.items() if model.startswith(k)), PRICES["claude-opus-5-5"])
    total = (usage.get("input_tokens", 0) * p_in + usage.get("cache_read_input_tokens", 0) * p_read
             + usage.get("cache_creation_input_tokens", 0) * p_in * 1.25 + usage.get("output_tokens", 0) * p_out)
    return round(total / 1_000_000, 4)


def log_cost(db, household_id: int | None, kind: str, cost: float, model: str = "", info: str = "") -> None:
    """Kostenprotokoll (ai_cost) für KI-Aufrufe außerhalb der Pläne; Pläne speichern ihren Verbrauch in params.usage."""
    db.add(AiCost(household_id=household_id, kind=kind, model=model[:60], cost_cents=round(cost, 4), info=info[:200]))
    logger.info("KI-Kosten %s: %.4f ct (%s) %s", kind, cost, model, info)


def add_usage(total: dict, usage: dict) -> dict:
    out = {k: round(total.get(k, 0) + usage.get(k, 0), 4) for k in USAGE_KEYS}
    out["model"] = usage.get("model") or total.get("model", "")
    return out


def similar(a: str, b: str) -> bool:
    """Gleiches oder ähnliches Gericht: ein Titel steckt wortweise im anderen („Leber“ ~ „Leber mit Zwiebeln“,
    nicht „Leberkäse“) oder die Titel sind fast gleich geschrieben."""
    wa, wb = set(re.findall(r"\w+", a.lower())), set(re.findall(r"\w+", b.lower()))
    return bool(wa and wb and (wa <= wb or wb <= wa)) or SequenceMatcher(None, a.lower(), b.lower()).ratio() >= 0.85


def banned_meals(draft: PlanDraft, banned: list[str]) -> list[str]:
    return [m.title for m in draft.meals if any(similar(m.title, b) for b in banned)]


def build_prompt(household: Household, offers: list[Offer], slots: list[tuple[int, str]],
                 favorites: list[str], wishes: str = "", note: str = "", portions: dict | None = None,
                 pantry: list[PantryItem] = (), never: list[str] = (), recent: list[str] = (),
                 extra: list[str] = (), guests: dict | None = None, repeat_weeks: int = 3) -> list[dict]:
    """Zwei Blöcke: Angebotsliste (stabil und gecacht, gleich für Plan, Korrektur und Neu würfeln), dann Haushalt/Auftrag.
    portions: Portionen je Slot (Standard: household.persons, inkl. Gäste), pantry: Vorrat – beides im variablen Block.
    favorites: „Titel (Zutaten)“ der Lieblingsrezepte, never: „Nie“/≤2★, recent: Gerichte der letzten Wochen (3/12).
    extra: kurze Zusatzzeilen (Abwechslung, Saison, Frühstücks-Basics, Special …), guests: Gäste je Slot (15)."""
    offer_lines = "\n".join(
        f"{o.id}|{o.title}|{o.price_cents}|{f'{o.amount:g}{o.unit}' if o.amount else '?'}|{o.chain}"
        for o in select_offers(offers)
    )
    portions, guests = portions or {}, guests or {}
    slot_lines = "\n".join(f"- day={d} ({DAYS[d]}), meal_type={m}, portionen={portions.get((d, m), household.persons):g}"
                           + (f" (davon {guests[(d, m)]} Gäste)" if guests.get((d, m)) else "") for d, m in slots)
    stock = sorted((p for p in pantry if not p.is_basic), key=lambda p: (p.best_before is None, p.best_before, p.name))
    parts = [
        f"Ernährung: {household.diet}",
        f"Allergien: {', '.join(household.allergies) or 'keine'}",
        f"Mag nicht: {', '.join(household.excluded_ingredients) or '-'}",
        *([f"Immer ersetzen: {', '.join(f'{r['instead']} → {r['use']}' for r in household.product_rules)}"]
          if getattr(household, "product_rules", None) else []),
        f"Küchen: {', '.join(household.cuisines) or 'gemischt'}",
        f"Ziel: {household.nutrition_goal}",
        f"Max. Kochzeit: {household.max_cook_minutes} min",
        f"Budget für alle Einkäufe der Woche: {household.budget_food_week_cents} ct",
    ]
    if favorites:
        parts.append("Lieblingsrezepte (gern einplanen, max. 2 pro Woche, Titel übernehmen):\n"
                     + "\n".join(f"- {f}" for f in favorites))
    if never:
        parts.append(f"Nie vorschlagen (auch nichts Ähnliches): {', '.join(never)}")
    if recent:
        parts.append(f"In den letzten {repeat_weeks} Wochen gekocht, nicht wiederholen: {', '.join(recent)}")
    if wishes:
        parts.append(f"Wünsche: {wishes}")
    if basics := [p.name for p in pantry if p.is_basic and p.amount != 0]:
        parts.append(f"Basics (immer da): {', '.join(basics)}")
    if stock:
        parts.append("Vorrat (zuerst verbrauchen): " + ", ".join(
            p.name + (f" {p.amount:g}{p.unit}" if p.amount is not None else "")
            + (f" bis {p.best_before:%d.%m.}" if p.best_before else "") for p in stock))
    parts += extra
    parts.append(f"\nZu planende Mahlzeiten:\n{slot_lines}")
    if note:
        parts.append(f"\n{note}")
    return [
        {"type": "text", "text": f"Angebote dieser Woche (id|produkt|preis ct|menge|laden):\n{offer_lines or '-'}",
         "cache_control": {"type": "ephemeral"}},
        {"type": "text", "text": "\n".join(parts)},
    ]


def ask_claude(content: list[dict]) -> tuple[PlanDraft, dict]:
    client = anthropic.Anthropic(api_key=settings.anthropic_api_key or None)
    model = settings.model_planner
    params = dict(model=model, max_tokens=16000, output_config={"effort": settings.planner_effort}, system=SYSTEM,
                  messages=[{"role": "user", "content": content}], output_format=PlanDraft)
    if settings.planner_effort in ("low", "medium", "high"):  # ohne Denken geht nur bis high
        # Haiku dachte sonst bis ~10k Tokens vor, das JSON brach bei max_tokens ab (und dauerte)
        params["thinking"] = {"type": "disabled"}
    try:
        if model.startswith(("claude-opus", "claude-sonnet")):
            response = client.beta.messages.parse(**params, betas=["server-side-fallback-2026-07-01"],
                                                  fallbacks="default")
        else:  # Haiku 5.5 hat keinen serverseitigen Fallback bei Ablehnung
            response = client.messages.parse(**params)
    except ValidationError as e:  # abgeschnittenes JSON
        raise RuntimeError("Plan nicht erzeugt (Antwort unvollständig)") from e
    u = response.usage
    usage = {"model": response.model, "input_tokens": u.input_tokens, "output_tokens": u.output_tokens,
             "cache_read_input_tokens": u.cache_read_input_tokens or 0,
             "cache_creation_input_tokens": u.cache_creation_input_tokens or 0}
    usage["cost_cents"] = cost_cents(usage)
    logger.info("Claude-Aufruf: %s", usage)
    if response.stop_reason != "end_turn" or response.parsed_output is None:
        raise RuntimeError(f"Plan nicht erzeugt (stop_reason={response.stop_reason})")
    return response.parsed_output, usage


def apply_rules(meals: list[PlannedMeal], rules: list[dict]) -> None:
    """Produkt-Regeln im Code durchsetzen (19.2): „Vollmilch“ wird bei „Hafermilch statt Milch“ zu Hafermilch, ohne
    Angebot (passt nicht mehr) – auch wenn die KI die Regel übersieht."""
    for m in meals:
        for ing in m.ingredients:
            rule = next((r for r in rules or () if is_a(ing.name, r["instead"]) and not is_a(ing.name, r["use"])), None)
            if rule:
                ing.name, ing.offer_id = rule["use"], None


def violations(meals: list[PlannedMeal], forbid: Callable[[str], bool] | None) -> list[str]:
    """„Gericht (Zutat)“ für Gerichte, die eine Allergie, die Ernährungsform oder eine Abneigung verletzen (19.2)."""
    return [f"{m.title} ({bad})" for m in meals if forbid
            for bad in [next((i.name for i in m.ingredients if forbid(i.name)), None)] if bad]


# 19.5: Stichwörter der Angebots-Kategorien, die in Schritten auf eine Zutat zeigen; Oberbegriffe zählen nicht
GENERIC = ("wasser", "sauce", "soße", "fleisch", "käse", "nudel", "brot", "creme", "öl", "dressing", "gemüse",
           "salat", "teig", "brühe", "fond", "saft")
FOOD_WORDS = sorted({w.strip() for _, _, ws in SUBCATEGORIES for w in ws if len(w.strip()) >= 4} - set(GENERIC))


def unlisted(meal: PlannedMeal) -> list[str]:
    """Substantive aus den Schritten, die nach Lebensmittel klingen, aber in keiner Zutat stecken (R1: „Wraps füllen“
    ohne Wraps in der Liste)."""
    have = " ".join(i.name for i in meal.ingredients).lower().replace("-", "").replace("porree", "porree lauch")
    out = []
    for w in sorted({m.lower() for m in re.findall(r"(?<!\w)[A-ZÄÖÜ][a-zäöüß]{3,}", " ".join(meal.steps))}):
        if w.startswith(GENERIC) or w.endswith(GENERIC):
            continue
        kws = [k for k in FOOD_WORDS if (w.startswith(k) or w.endswith(k)) and not (k in TRAPS and TRAPS[k].search(w))]
        if kws and stem(w) not in have and not any(k in have for k in kws):
            out.append(w)
    return out


def slot_key(day: int, meal_type: str) -> str:
    return f"{day}|{meal_type}"


def chrono(meal) -> tuple[int, int]:
    return meal.day, SLOT_ORDER.index(meal.meal_type) if meal.meal_type in SLOT_ORDER else len(SLOT_ORDER)


def worth_keeping(amount: float, unit: str, pack: float) -> bool:
    """Rest lohnt sich (sonst Krümel): mind. 1 Stück bzw. 30 g/ml und 10 % der Packung."""
    return amount >= 1 if unit == "stk" else amount >= max(30, 0.1 * pack)


def price(draft: PlanDraft, offers_by_id: dict[int, Offer], pantry: list[PantryItem] = ()) -> PricedPlan:
    """Kauft ganze Packungen pro Zutat über alle Gerichte und verteilt die Kosten anteilig.
    Vorhandene Mengen (Vorrat, Basics) kosten nichts, Teilmengen anteilig. Reste (19): Packungen werden in
    zeitlicher Reihenfolge angebrochen; ein späteres Gericht, das aus dem Rest kocht, bekommt ein Badge."""
    stock = Stock(pantry)
    needs: dict[tuple, list[tuple[int, PlannedIngredient]]] = {}
    for i in sorted(range(len(draft.meals)), key=lambda i: chrono(draft.meals[i])):
        for ing in draft.meals[i].ingredients:
            if ing.offer_id in offers_by_id and not fits(ing.name, offers_by_id[ing.offer_id]):
                logger.info("Angebot passt nicht zur Zutat: %s ≠ %s", ing.name, offers_by_id[ing.offer_id].title)
                ing.offer_id = None  # 19.1: KI hat z.B. Käse für Joghurt gewählt → Normalpreis-Schätzung
            # 19.5: „Zwiebel“/„Zwiebeln“ = eine Zeile, eine Packung
            key = ("offer", ing.offer_id) if ing.offer_id in offers_by_id else ("est", stock_key(ing.name), ing.unit)
            needs.setdefault(key, []).append((i, ing))

    meal_costs = [0] * len(draft.meals)
    total = saved = 0
    rests = {"badges": {}, "after": {}, "left": [], "planned": 0}
    for key, uses in needs.items():
        first = uses[0][1]
        category = None
        if key[0] == "offer":
            o = offers_by_id[key[1]]
            # Packungsgröße aus dem Angebot, wenn bekannt und in derselben Einheit
            amount = o.amount if o.amount and o.unit == first.unit else pack_amount(first.name, first.unit,
                                                                                    first.pack_amount)
            pack = Pack(o.price_cents, amount, o.regular_price_cents, o.id, o.chain)
            category = o.category
        else:
            pack = Pack(first.pack_price_cents, pack_amount(first.name, first.unit, first.pack_amount))
        needed = sum(ing.amount for _, ing in uses)
        have = stock.take(first.name, first.unit, needed, all(ing.in_pantry for _, ing in uses))
        line = cost_line(first.name, max(needed - have, 0), [pack])
        total += line.buy_cents
        saved += line.saved_cents
        for i, ing in uses:
            meal_costs[i] += cents(line.use_cents * ing.amount / needed) if needed else 0
        if line.pack is not None and pack.amount > 0:
            track_rests(rests, draft, uses, have, pack, shelf_days(first.name, category))
    return PricedPlan(draft, total, saved, meal_costs, rests=rests)


def track_rests(rests: dict, draft: PlanDraft, uses: list, have: float, pack: Pack, shelf: int | None) -> None:
    """Packungen einer Zutat chronologisch anbrechen: Vorrat zuerst, dann der offene Rest, dann neue Packungen."""
    first = uses[0][1]
    open_left, opened, used_rest, opener = 0.0, None, False, None
    for i, ing in uses:
        meal = draft.meals[i]
        here, amount = (meal.day, meal.meal_type), ing.amount
        took = min(have, amount)
        have, amount = have - took, amount - took
        if amount <= 1e-9:
            continue
        if open_left > 1e-9:
            used = min(open_left, amount)
            open_left, amount = open_left - used, amount - used
            if shelf and opened != here and here[0] <= opened[0] + shelf:  # abgelaufener Rest: kein Badge
                rests["badges"].setdefault(slot_key(*here), {})[ing.name] = opened[0]
                used_rest = True
        if amount > 1e-9:
            open_left += math.ceil(amount / pack.amount - 1e-9) * pack.amount - amount
            opened, opener = here, meal
        if worth_keeping(open_left, first.unit, pack.amount):
            rests["after"].setdefault(slot_key(*here), []).append(
                {"name": first.name, "amount": round(open_left, 1), "unit": first.unit,
                 "until_day": opened[0] + shelf if shelf else None})
    if shelf:
        rests["planned"] += used_rest
        if worth_keeping(open_left, first.unit, pack.amount):
            rests["left"].append({"name": first.name, "amount": round(open_left, 1), "unit": first.unit,
                                  "until_day": opened[0] + shelf, "opened_day": opened[0], "opened_meal": opened[1],
                                  "offer_id": pack.offer_id,
                                  "meat": shelf == 2, "protein": opener.protein})


def dishes(meals: list[PlannedMeal]) -> list[variety.Dish]:
    return [variety.Dish(m.day, m.meal_type, m.title, m.cuisine, m.side, m.protein, m.prep_minutes,
                         " ".join([m.description, *m.steps])) for m in meals]


def make_plan(household: Household, offers: list[Offer], slots: list[tuple[int, str]], favorites: list[str],
              wishes: str = "", ask: Callable[[list[dict]], tuple[PlanDraft, dict]] | None = None,
              max_repairs: int = 1, portions: dict | None = None, pantry: list[PantryItem] = (),
              never: list[str] = (), recent: list[str] = (), rules: dict | None = None, fish_ok: bool = True,
              extra: list[str] = (), guests: dict | None = None, stock: list[PantryItem] | None = None,
              forbid: Callable[[str], bool] | None = None) -> PricedPlan:
    """forbid(Zutat) = verletzt Allergie/Ernährung/Abneigung → Gericht wird wie ein Nie-Gericht ersetzt (19.2).
    rules (12) = Abwechslungsregeln → nach dem Planen Prüfung im Code und ein zweiter Durchgang nur für die
    betroffenen Slots, der zugleich frische Reste (19) in Folgegerichte legt. stock = Vorrat + Wochen-Basics (23)
    für die Kosten (Standard: pantry)."""
    ask = ask or ask_claude
    stock = list(pantry) if stock is None else stock
    offers_by_id = {o.id: o for o in offers}
    repeat_weeks = (rules or {}).get("repeat_weeks", 3)

    def prompt(todo: list[tuple[int, str]], note: str) -> list[dict]:
        return build_prompt(household, offers, todo, favorites, wishes, note, portions, pantry, never, recent, extra,
                            guests, repeat_weeks)

    def ask_once(todo: list[tuple[int, str]], note: str) -> tuple[PlanDraft, dict]:
        try:
            return ask(prompt(todo, note))
        except RuntimeError:  # unvollständige Antwort: ein zweiter Versuch
            logger.warning("Claude-Antwort unbrauchbar, zweiter Versuch", exc_info=True)
            return ask(prompt(todo, note))

    def ask_parts(todo: list[tuple[int, str]], note: str) -> tuple[PlanDraft, dict]:
        """19.6: Woche in Tagesblöcken parallel planen – je Aufruf weniger Ausgabe, Wartezeit ≈ ein Block.
        Doppelte Gerichte zwischen Blöcken fängt der zweite Durchgang (variety)."""
        days = sorted({d for d, _ in todo})
        n = max(min(math.ceil(len(todo) / PART_SLOTS), len(days)), 1)
        parts = [[s for s in todo if s[0] in days[i * len(days) // n:(i + 1) * len(days) // n]] for i in range(n)]
        with ThreadPoolExecutor(max_workers=n) as pool:
            results = list(pool.map(lambda p: ask_once(p, note), parts))
        usage = {}
        for _, u in results:
            usage = add_usage(usage, u)
        return PlanDraft(meals=[m for d, _ in results for m in d.meals]), usage

    note, usage, todo = "", {}, slots
    best: PricedPlan | None = None
    best_key = None
    draft = None
    for _ in range(max_repairs + 1):
        new, call_usage = ask_parts(todo, note)
        usage = add_usage(usage, call_usage)
        new.meals = [m for m in new.meals if (m.day, m.meal_type) in set(todo)]
        apply_rules(new.meals, getattr(household, "product_rules", None))
        if todo is not slots:  # 19.6: nur die beanstandeten Gerichte kamen neu, der Rest bleibt
            got = {(m.day, m.meal_type): m for m in new.meals}
            new = PlanDraft(meals=[got.pop((m.day, m.meal_type), m) for m in draft.meals] + list(got.values()))
        draft = new
        planned = price(draft, offers_by_id, stock)
        bad = violations(draft.meals, forbid)
        banned = banned_meals(draft, [*never, *recent]) + bad
        missing = [f"{m.title}: {', '.join(u)}" for m in draft.meals if (u := unlisted(m))]
        key = (len(banned), len(missing), planned.total_cents)  # erst Regeln, dann vollständige Liste, dann Preis
        if best is None or key < best_key:
            best, best_key = planned, key
        over = planned.total_cents > household.budget_food_week_cents
        if not over and not banned and not missing:
            break
        have = {(m.day, m.meal_type) for m in draft.meals}
        fix = [(m.day, m.meal_type) for m in draft.meals
               if banned_meals(PlanDraft(meals=[m]), [*never, *recent]) or violations([m], forbid) or unlisted(m)]
        fix += [s for s in slots if s not in have]
        # Budget betrifft die ganze Woche; sonst nur die betroffenen Slots neu (weniger Ausgabe = schneller)
        todo = slots if over or not fix else fix
        note = "Korrektur zum vorigen Entwurf:"
        if todo is not slots:
            note += (" Plane NUR diese Mahlzeiten neu, der Rest der Woche bleibt: "
                     + "; ".join(f"{DAYS[m.day][:2]} {m.meal_type}: {m.title}" for m in draft.meals
                                 if (m.day, m.meal_type) not in todo) + ".")
        if over:
            note += (f" Er kostet {planned.total_cents} ct, das Budget ist {household.budget_food_week_cents} ct. "
                     "Ersetze die teuersten Gerichte durch günstigere mit mehr Angeboten.")
        if banned := [b for b in banned if b not in bad]:
            note += (f" Ersetze {', '.join(banned)} – steht auf der Nie-Liste bzw. gab es in den letzten "
                     f"{repeat_weeks} Wochen.")
        if bad:
            note += f" Ersetze {', '.join(bad)} – die Zutat verletzt Allergie, Ernährungsform oder „Mag nicht“."
        if missing:
            note += f" In den Schritten verwendet, aber nicht in den Zutaten – mit Menge ergänzen: {'; '.join(missing)}."
    if rules is not None:
        best, usage = second_pass(best, usage, household, offers_by_id, slots, stock, rules, fish_ok, recent, never,
                                  ask_once, forbid)
    if bad := violations(best.draft.meals, forbid):  # harte Regel: lieber Fehler als Allergen im Plan
        raise RuntimeError(f"Kein Plan ohne ausgeschlossene Zutaten gefunden ({', '.join(bad)}), bitte erneut versuchen")
    best.usage = usage
    return best  # Budget evtl. nicht erreicht: günstigster Entwurf, Nutzer entscheidet (S7 „Trotzdem übernehmen“)


def score(planned: PricedPlan, budget: int, rules: dict, fish_ok: bool, recent, never,
          forbid: Callable[[str], bool] | None = None) -> tuple[int, int]:
    """(Regelverstöße inkl. Budget/Nie-Liste/verbotener Zutaten, übrige frische Reste) – kleiner ist besser."""
    c = variety.check(dishes(planned.draft.meals), rules, fish_ok, recent)
    return (len(c.fixes) + len(banned_meals(planned.draft, list(never))) + (planned.total_cents > budget)
            + 10 * len(violations(planned.draft.meals, forbid)),
            len(planned.rests.get("left", [])))


def rest_targets(planned: PricedPlan, slots: list[tuple[int, str]], fixes: dict, rules: dict | None = None,
                 fish_ok: bool = True) -> tuple[dict[tuple[int, str], list[str]], dict[tuple[int, str], str]]:
    """Je frischem Rest ein späteres Gericht bis zum Ablauf, gleichmäßig verteilt → (Anweisungen je Slot, Protein je
    Slot). Fleisch/Fisch nur in Hauptgerichte ohne Regel-Reparatur; wechselt dadurch die Proteinart, darf das keine
    Abwechslungsregel brechen (simuliert mit variety.check)."""
    current = {(m.day, m.meal_type): m for m in planned.draft.meals}
    protein = {s: m.protein for s, m in current.items()}

    def violations(prot: dict) -> int:
        if rules is None:
            return 0
        return len(variety.check([variety.Dish(m.day, m.meal_type, m.title, m.cuisine, m.side,
                                               prot[(m.day, m.meal_type)]) for m in planned.draft.meals],
                                 rules, fish_ok).fixes)

    base = violations(protein)
    targets: dict[tuple[int, str], list[str]] = {}
    for r in planned.rests.get("left", []):
        if (r["opened_day"], r.get("opened_meal")) in fixes:
            continue  # das anbrechende Gericht wird wegen einer Regel ersetzt → der Rest entsteht so nicht
        opened = (r["opened_day"], SLOT_ORDER.index(r.get("opened_meal", "dessert")))

        def ok(s):  # später als der Anbruch (auch am selben Tag) und vor dem Ablauf
            if s not in current or not opened < (s[0], SLOT_ORDER.index(s[1])) or s[0] > r["until_day"]:
                return False
            if r["meat"]:
                return s[1] in variety.MAIN and s not in fixes and (
                    protein[s] == r["protein"] or violations(protein | {s: r["protein"]}) <= base)
            return s[1] in (*variety.MAIN, "fruehstueck", "snack", "dessert")
        cands = sorted((s for s in slots if ok(s)), key=lambda s: (
            r["meat"] and protein[s] != r["protein"], len(targets.get(s, [])), s[0]))
        # große Reste (z.B. 600 g Hähnchen, 1,5 kg Mandarinen) auf zwei Folgegerichte verteilen
        big = r["amount"] >= (4 if r["unit"] == "stk" else 400)
        picked = cands[:2 if big else 1]
        for s in picked:
            if r["meat"]:
                protein[s] = r["protein"]
            part = r["amount"] / len(picked)
            targets.setdefault(s, []).append(
                f"verwende Rest {round(part, 1) if r['unit'] == 'stk' else round(part):g} {r['unit']} {r['name']}"
                + (f" (offer_id={r['offer_id']})" if r["offer_id"] else "") + " komplett")
    return targets, protein


def second_pass(best: PricedPlan, usage: dict, household, offers_by_id: dict, slots: list[tuple[int, str]],
                stock: list, rules: dict, fish_ok: bool, recent, never,
                ask: Callable[[list[tuple[int, str]], str], tuple[PlanDraft, dict]],
                forbid: Callable[[str], bool] | None = None) -> tuple[PricedPlan, dict]:
    """Planner-Durchgang 2: Regelverstöße (12/23/24) und frische Reste (19) in EINER Runde nur für die betroffenen
    Slots; übernommen, wenn das Ergebnis nicht schlechter ist."""
    c = variety.check(dishes(best.draft.meals), rules, fish_ok, recent)
    todo = {s: list(f) for s, f in c.fixes.items()}
    current = {(m.day, m.meal_type): m for m in best.draft.meals}
    targets, protein = rest_targets(best, slots, c.fixes, rules, fish_ok)
    for s, f in targets.items():
        if s not in todo:  # nur wegen Resten: Gericht behalten und ergänzen, sonst brechen neue Zutaten neue Packungen an
            m = current[s]
            f = [*f, f"sonst: Beilage {m.side}, Protein {protein[s]}, Küche {m.cuisine or 'beliebig'}; am besten das "
                     f"bisherige Gericht „{m.title}“ ({', '.join(i.name for i in m.ingredients)}) behalten und den Rest "
                     "einbauen"]
        todo.setdefault(s, []).extend(f)
    if not todo:
        return best, usage
    order = sorted(todo, key=lambda s: (s[0], SLOT_ORDER.index(s[1]) if s[1] in SLOT_ORDER else 9))
    kept = [m for m in best.draft.meals if (m.day, m.meal_type) not in todo]
    note = ("Zweiter Durchgang: plane NUR diese Mahlzeiten neu, der Rest der Woche bleibt. Keine weiteren frischen "
            "Packungen anbrechen, die übrig blieben (frische Zutaten aus den Resten, sonst Vorrat/Haltbares):\n"
            + "\n".join(f"- day={d} ({DAYS[d]}), meal_type={m}: {'; '.join(todo[(d, m)])}" for d, m in order)
            + "\nBleibt im Plan: " + "; ".join(f"{DAYS[m.day][:2]} {m.meal_type}: {m.title} [{m.side}, {m.protein}, "
                                                f"{m.cuisine}]" for m in sorted(kept, key=chrono)))
    try:
        draft, call_usage = ask(order, note)
    except RuntimeError as e:  # zweiter Durchgang ist Kür: ohne ihn bleibt der erste Plan
        logger.warning("Zweiter Durchgang fehlgeschlagen: %s", e)
        return best, usage
    usage = add_usage(usage, call_usage)
    new = {(m.day, m.meal_type): m for m in draft.meals if (m.day, m.meal_type) in todo}
    apply_rules(list(new.values()), getattr(household, "product_rules", None))
    merged = PlanDraft(meals=[new.get((m.day, m.meal_type), m) for m in best.draft.meals])
    candidate = price(merged, offers_by_id, stock)
    budget = household.budget_food_week_cents
    old = score(best, budget, rules, fish_ok, recent, never, forbid)
    now = score(candidate, budget, rules, fish_ok, recent, never, forbid)
    logger.info("Zweiter Durchgang: %d Slots, (Verstöße, Reste) %s → %s, %s; offen: %s", len(todo), old, now,
                "übernommen" if now <= old else "verworfen",
                variety.check(dishes(candidate.draft.meals), rules, fish_ok, recent).issues)
    return (candidate if now <= old else best), usage


def add_images(planned: PricedPlan, find: Callable[[str], str] | None = None) -> PricedPlan:
    """Setzt planned.images (parallel zu draft.meals), höchstens 6 Abrufe gleichzeitig."""
    find = find or recipe_images.find_image
    with ThreadPoolExecutor(max_workers=6) as pool:
        planned.images = list(pool.map(find, [m.image_query or m.title for m in planned.draft.meals]))
    return planned


def reroll_meal(household: Household, offers: list[Offer], slot: tuple[int, str], avoid: list[str],
                wishes: str = "", portions: dict | None = None, pantry: list[PantryItem] = (),
                favorites: list[str] = (), never: list[str] = (), recent: list[str] = (), extra: list[str] = (),
                guests: dict | None = None, repeat_weeks: int = 3,
                max_cost_cents: int | None = None, direction: str = "", wish: str = "",
                forbid: Callable[[str], bool] | None = None,
                ask: Callable[[list[dict]], tuple[PlanDraft, dict]] | None = None) -> tuple[PlannedMeal, dict]:
    """Genau ein neues Gericht für einen Platz im Plan; avoid[0] ist das alte Gericht, danach die übrigen der Woche.
    max_cost_cents: günstigere Alternative mit Kostengrenze (43). direction/wish: Richtung beim Neu-Würfeln (19.3).
    Verletzt das Gericht Allergie/Ernährung/Abneigung (forbid), einmal neu, dann Fehler."""
    ask = ask or ask_claude
    note = (f"Plane genau EIN neues Gericht, anders als: {avoid[0]} und andere Gerichte der Woche "
            f"({', '.join(avoid[1:]) or '-'}).")
    if max_cost_cents is not None:
        note += (f" Es darf höchstens {max_cost_cents} ct kosten (Zutaten anteilig): günstige Angebote, "
                 "einfache Zutaten.")
    if direction in DIRECTIONS:
        note += f" {DIRECTIONS[direction]}"
    if wish.strip():
        note += f" Wunsch für dieses Gericht: {wish.strip()[:200]}"
    usage: dict = {}
    for _ in range(2):
        draft, call_usage = ask(build_prompt(household, offers, [slot], favorites=favorites, wishes=wishes, note=note,
                                             portions=portions, pantry=pantry, never=never, recent=recent,
                                             extra=extra, guests=guests, repeat_weeks=repeat_weeks))
        usage = add_usage(usage, call_usage)
        meal = next((m for m in draft.meals if (m.day, m.meal_type) == slot), None)
        if meal is None:
            raise RuntimeError("Kein neues Gericht erzeugt")
        apply_rules([meal], getattr(household, "product_rules", None))
        if not (bad := violations([meal], forbid)):
            return meal, usage
        note += f" Nicht {bad[0]} – die Zutat verletzt Allergie, Ernährungsform oder „Mag nicht“."
    raise RuntimeError("Kein passendes Gericht ohne ausgeschlossene Zutaten gefunden, bitte erneut versuchen")


def week_slots(household: Household, lunchbox_days: set[int] = frozenset(),
               extra: list[tuple[int, str]] = ()) -> list[tuple[int, str]]:
    """Slots der Woche: gewählte Mahlzeiten an den Plan-Tagen, Lunchbox (24) an Plan-Tagen mit Lunchbox-Mitglied,
    Zusatz-Slots eines Specials (25), chronologisch."""
    meals = [m for m in household.meal_types if m in MEAL_TYPES]
    slots = {(d, m) for d in household.plan_days for m in meals}
    slots |= {(d, "lunchbox") for d in household.plan_days if d in lunchbox_days} | set(extra)
    return sorted(slots, key=lambda s: (s[0], SLOT_ORDER.index(s[1])))


def portion_factor(kcal: int) -> float:
    """Portionsfaktor aus dem kcal-Ziel relativ zu 2000 kcal, auf 0,25 gerundet (48)."""
    return max(0.25, round(kcal / 2000 * 4) / 4)


def slot_eaters(profiles: list[MemberProfile], persons: int,
                slots: list[tuple[int, str]]) -> dict[tuple[int, str], tuple[list[dict], float]]:
    """Je Slot: Esser [{member_id, factor}] und Portionen für die Mengen (Summe der Faktoren).
    Ohne Profile oder mit nur einem Mitglied gilt die Personenzahl des Haushalts. Lunchbox (24): nur Mitglieder mit
    diesem Lunchbox-Tag, je 1 Portion × Faktor; Vorspeise wie Abendessen."""
    eaters = {}
    for d, m in slots:
        if m == "lunchbox":
            here = [{"member_id": p.member_id, "factor": portion_factor(p.kcal)} for p in profiles
                    if d in (p.lunchbox_days or [])]
            eaters[(d, m)] = (here, sum(e["factor"] for e in here))
            continue
        if len(profiles) < 2:
            eaters[(d, m)] = ([{"member_id": p.member_id, "factor": portion_factor(p.kcal)} for p in profiles],
                              float(persons))
            continue
        here = [{"member_id": p.member_id, "factor": portion_factor(p.kcal)} for p in profiles
                if (p.eats.get("abend" if m == "vorspeise" else m) or [True] * 7)[d]]
        eaters[(d, m)] = (here, sum(e["factor"] for e in here))
    return eaters
