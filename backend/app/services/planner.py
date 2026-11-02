"""KI-Wochenplan: Claude plant Gerichte rund um die Angebote, der Code rechnet die Kosten (E10)."""
import logging
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from typing import Literal

import anthropic
from pydantic import BaseModel, ConfigDict

from app.core.config import settings
from app.models import Household, Offer
from app.services import recipe_images
from app.services.normalize import cents
from app.services.pricing import Pack, cost_line

logger = logging.getLogger(__name__)

MEAL_TYPES = {"fruehstueck": "Frühstück", "mittag": "Mittagessen", "abend": "Abendessen", "dessert": "Dessert"}
DAYS = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]
FOOD_CATEGORIES = ("fleisch_fisch", "obst_gemuese", "kuehlung", "vorrat", "sonstiges")  # ohne Getränke/Drogerie/Haushalt
MAX_OFFERS = 120
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
    meal_type: Literal["fruehstueck", "mittag", "abend", "dessert"]
    title: str
    description: str
    cuisine: str
    prep_minutes: int
    servings: int
    ingredients: list[PlannedIngredient]
    steps: list[str]
    image_query: str = ""  # englische Suchbegriffe fürs Foto; Default, weil api.py Gerichte aus der DB nachbaut


class PlanDraft(BaseModel):
    meals: list[PlannedMeal]


SYSTEM = """Du planst Wochengerichte für einen deutschen Haushalt, der sparen will.
Regeln:
- Baue die Gerichte so weit wie möglich aus den Angeboten der Woche. Für eine Zutat aus der Angebotsliste setze offer_id auf deren ID, sonst null.
- pack_amount/pack_price_cents: übliche Packungsgröße und Preis in Cent. Bei Angeboten den Angebotspreis, sonst eine realistische Schätzung des deutschen Normalpreises (Discounter-Niveau).
- in_pantry=true nur für typische Vorratszutaten (Salz, Pfeffer, Öl, Essig, Gewürze, Zucker, Mehl, Brühe).
- Mengen sind für die angegebene Personenzahl. Einheiten nur g, ml oder stk.
- Nutze Zutaten über mehrere Gerichte, damit wenig übrig bleibt (z.B. halbe Packung Feta am nächsten Tag).
- Ernährungsform, Allergien und Ausschlüsse sind harte Regeln. Kochzeit nicht überschreiten.
- Alle Texte auf Deutsch. Schritte kurz und konkret, 3–8 Schritte.
- image_query: 2–4 englische Suchbegriffe für ein Foto des Gerichts, z.B. "chicken tikka masala".
- Plane genau die genannten Mahlzeiten, nicht mehr und nicht weniger."""


@dataclass
class PricedPlan:
    draft: PlanDraft
    total_cents: int
    saved_cents: int
    meal_costs: list[int]
    usage: dict = field(default_factory=dict)
    images: list[str] = field(default_factory=list)  # Foto-URL je Gericht in draft.meals, "" = keins


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


def add_usage(total: dict, usage: dict) -> dict:
    out = {k: round(total.get(k, 0) + usage.get(k, 0), 4) for k in USAGE_KEYS}
    out["model"] = usage.get("model") or total.get("model", "")
    return out


def build_prompt(household: Household, offers: list[Offer], slots: list[tuple[int, str]],
                 favorites: list[str], wishes: str = "", note: str = "") -> list[dict]:
    """Zwei Blöcke: Angebotsliste (stabil und gecacht, gleich für Plan, Korrektur und Neu würfeln), dann Haushalt/Auftrag."""
    offer_lines = "\n".join(
        f"{o.id}|{o.title}|{o.price_cents}|{f'{o.amount:g}{o.unit}' if o.amount else '?'}|{o.chain}"
        for o in select_offers(offers)
    )
    slot_lines = "\n".join(f"- day={d} ({DAYS[d]}), meal_type={m}" for d, m in slots)
    parts = [
        f"Personen: {household.persons}",
        f"Ernährung: {household.diet}",
        f"Allergien: {', '.join(household.allergies) or 'keine'}",
        f"Mag nicht: {', '.join(household.excluded_ingredients) or '-'}",
        f"Küchen: {', '.join(household.cuisines) or 'gemischt'}",
        f"Ziel: {household.nutrition_goal}",
        f"Max. Kochzeit: {household.max_cook_minutes} min",
        f"Budget für alle Einkäufe der Woche: {household.budget_food_week_cents} ct",
        f"Lieblingsgerichte (gern wieder einplanen): {', '.join(favorites) or '-'}",
    ]
    if wishes:
        parts.append(f"Wünsche: {wishes}")
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
    if model.startswith(("claude-opus", "claude-sonnet")):
        response = client.beta.messages.parse(**params, betas=["server-side-fallback-2026-07-01"], fallbacks="default")
    else:  # Haiku 5.5 hat keinen serverseitigen Fallback bei Ablehnung
        response = client.messages.parse(**params)
    u = response.usage
    usage = {"model": response.model, "input_tokens": u.input_tokens, "output_tokens": u.output_tokens,
             "cache_read_input_tokens": u.cache_read_input_tokens or 0,
             "cache_creation_input_tokens": u.cache_creation_input_tokens or 0}
    usage["cost_cents"] = cost_cents(usage)
    logger.info("Claude-Aufruf: %s", usage)
    if response.stop_reason != "end_turn" or response.parsed_output is None:
        raise RuntimeError(f"Plan nicht erzeugt (stop_reason={response.stop_reason})")
    return response.parsed_output, usage


def price(draft: PlanDraft, offers_by_id: dict[int, Offer]) -> PricedPlan:
    """Kauft ganze Packungen pro Zutat über alle Gerichte und verteilt die Kosten anteilig."""
    needs: dict[tuple, list[tuple[int, PlannedIngredient]]] = {}
    for i, meal in enumerate(draft.meals):
        for ing in meal.ingredients:
            key = ("offer", ing.offer_id) if ing.offer_id in offers_by_id else ("est", ing.name.lower().strip(), ing.unit)
            needs.setdefault(key, []).append((i, ing))

    meal_costs = [0] * len(draft.meals)
    total = saved = 0
    for key, uses in needs.items():
        first = uses[0][1]
        if key[0] == "offer":
            o = offers_by_id[key[1]]
            # Packungsgröße aus dem Angebot, wenn bekannt und in derselben Einheit
            amount = o.amount if o.amount and o.unit == first.unit else first.pack_amount
            pack = Pack(o.price_cents, amount, o.regular_price_cents, o.id, o.chain)
        else:
            pack = Pack(first.pack_price_cents, first.pack_amount)
        needed = sum(ing.amount for _, ing in uses)
        line = cost_line(first.name, needed, [pack], in_pantry=all(ing.in_pantry for _, ing in uses))
        total += line.buy_cents
        saved += line.saved_cents
        for i, ing in uses:
            meal_costs[i] += cents(line.use_cents * ing.amount / needed) if needed else 0
    return PricedPlan(draft, total, saved, meal_costs)


def make_plan(household: Household, offers: list[Offer], slots: list[tuple[int, str]], favorites: list[str],
              wishes: str = "", ask: Callable[[list[dict]], tuple[PlanDraft, dict]] | None = None,
              max_repairs: int = 1) -> PricedPlan:
    ask = ask or ask_claude
    offers_by_id = {o.id: o for o in offers}
    note, usage = "", {}
    best: PricedPlan | None = None
    for _ in range(max_repairs + 1):
        draft, call_usage = ask(build_prompt(household, offers, slots, favorites, wishes, note))
        usage = add_usage(usage, call_usage)
        draft.meals = [m for m in draft.meals if (m.day, m.meal_type) in set(slots)]
        planned = price(draft, offers_by_id)
        if best is None or planned.total_cents < best.total_cents:
            best = planned
        if planned.total_cents <= household.budget_food_week_cents:
            break
        note = (f"Korrektur zum vorigen Entwurf: Er kostet {planned.total_cents} ct, das Budget ist "
                f"{household.budget_food_week_cents} ct. Ersetze die teuersten Gerichte durch günstigere mit mehr Angeboten.")
    best.usage = usage
    return best  # Budget evtl. nicht erreicht: günstigster Entwurf, Nutzer entscheidet (S7 „Trotzdem übernehmen“)


def add_images(planned: PricedPlan, find: Callable[[str], str] | None = None) -> PricedPlan:
    """Setzt planned.images (parallel zu draft.meals), höchstens 6 Abrufe gleichzeitig."""
    find = find or recipe_images.find_image
    with ThreadPoolExecutor(max_workers=6) as pool:
        planned.images = list(pool.map(find, [m.image_query or m.title for m in planned.draft.meals]))
    return planned


def reroll_meal(household: Household, offers: list[Offer], slot: tuple[int, str], avoid: list[str],
                wishes: str = "") -> tuple[PlannedMeal, dict]:
    """Genau ein neues Gericht für einen Platz im Plan; avoid[0] ist das alte Gericht, danach die übrigen der Woche."""
    note = (f"Plane genau EIN neues Gericht, anders als: {avoid[0]} und andere Gerichte der Woche "
            f"({', '.join(avoid[1:]) or '-'}).")
    draft, usage = ask_claude(build_prompt(household, offers, [slot], favorites=[], wishes=wishes, note=note))
    meal = next((m for m in draft.meals if (m.day, m.meal_type) == slot), None)
    if meal is None:
        raise RuntimeError("Kein neues Gericht erzeugt")
    return meal, usage


def week_slots(household: Household) -> list[tuple[int, str]]:
    order = list(MEAL_TYPES)
    meals = sorted((m for m in household.meal_types if m in MEAL_TYPES), key=order.index)
    return [(d, m) for d in sorted(household.plan_days) for m in meals]
