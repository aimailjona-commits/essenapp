"""KI-Wochenplan: Claude plant Gerichte rund um die Angebote, der Code rechnet die Kosten (E10)."""
from collections.abc import Callable
from dataclasses import dataclass
from typing import Literal

import anthropic
from pydantic import BaseModel

from app.core.config import settings
from app.models import Household, Offer
from app.services.normalize import cents
from app.services.pricing import Pack, cost_line

MEAL_TYPES = {"fruehstueck": "Frühstück", "mittag": "Mittagessen", "abend": "Abendessen", "dessert": "Dessert"}
DAYS = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]


class PlannedIngredient(BaseModel):
    name: str
    amount: float
    unit: Literal["g", "ml", "stk"]
    offer_id: int | None
    pack_amount: float
    pack_price_cents: int
    in_pantry: bool


class PlannedMeal(BaseModel):
    day: int
    meal_type: Literal["fruehstueck", "mittag", "abend", "dessert"]
    title: str
    description: str
    cuisine: str
    prep_minutes: int
    servings: int
    ingredients: list[PlannedIngredient]
    steps: list[str]


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
- Plane genau die genannten Mahlzeiten, nicht mehr und nicht weniger."""


@dataclass
class PricedPlan:
    draft: PlanDraft
    total_cents: int
    saved_cents: int
    meal_costs: list[int]


def build_prompt(household: Household, offers: list[Offer], slots: list[tuple[int, str]],
                 favorites: list[str], feedback: str = "") -> str:
    offer_lines = "\n".join(
        f"{o.id} | {o.chain} | {o.title}{' (' + o.brand + ')' if o.brand else ''} | {o.price_cents} ct"
        f" | {o.amount or '?'} {o.unit} | {o.category}"
        for o in offers if o.category not in ("drogerie", "haushalt")
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
        f"\nZu planende Mahlzeiten:\n{slot_lines}",
        f"\nAngebote dieser Woche (id | laden | produkt | preis | menge | kategorie):\n{offer_lines or '-'}",
    ]
    if feedback:
        parts.append(f"\nKorrektur zum vorigen Entwurf: {feedback}")
    return "\n".join(parts)


def ask_claude(prompt: str) -> PlanDraft:
    client = anthropic.Anthropic(api_key=settings.anthropic_api_key or None)
    response = client.beta.messages.parse(
        model=settings.model_planner,
        max_tokens=16000,
        betas=["server-side-fallback-2026-07-01"],
        fallbacks="default",
        output_config={"effort": settings.planner_effort},
        cache_control={"type": "ephemeral"},
        system=SYSTEM,
        messages=[{"role": "user", "content": prompt}],
        output_format=PlanDraft,
    )
    if response.stop_reason != "end_turn" or response.parsed_output is None:
        raise RuntimeError(f"Plan nicht erzeugt (stop_reason={response.stop_reason})")
    return response.parsed_output


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
              ask: Callable[[str], PlanDraft] = ask_claude, max_repairs: int = 2) -> PricedPlan:
    offers_by_id = {o.id: o for o in offers}
    feedback = ""
    best: PricedPlan | None = None
    for _ in range(max_repairs + 1):
        draft = ask(build_prompt(household, offers, slots, favorites, feedback))
        draft.meals = [m for m in draft.meals if (m.day, m.meal_type) in set(slots)]
        planned = price(draft, offers_by_id)
        if best is None or planned.total_cents < best.total_cents:
            best = planned
        if planned.total_cents <= household.budget_food_week_cents:
            return planned
        feedback = (f"Der Entwurf kostet {planned.total_cents} ct, das Budget ist {household.budget_food_week_cents} ct. "
                    "Ersetze die teuersten Gerichte durch günstigere mit mehr Angeboten.")
    return best  # Budget nicht erreichbar: günstigster Entwurf, Nutzer entscheidet (S7 „Trotzdem übernehmen“)


def week_slots(household: Household) -> list[tuple[int, str]]:
    order = list(MEAL_TYPES)
    meals = sorted((m for m in household.meal_types if m in MEAL_TYPES), key=order.index)
    return [(d, m) for d in sorted(household.plan_days) for m in meals]
