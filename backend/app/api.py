from datetime import date
from types import SimpleNamespace

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.core.auth import current_member, new_token
from app.core.db import get_db
from app.models import Household, HouseholdStore, MealPlan, MealPlanEntry, Member, Offer, Recipe
from app.schemas import (EntryUpdate, HouseholdCreate, HouseholdCreated, HouseholdOut, HouseholdSettings,
                         NearbyStoreOut, OfferOut, PlanOptions, PlanOut, UsageOut)
from app.services import nearby_stores, offers_import, planner

router = APIRouter()


@router.post("/households", response_model=HouseholdCreated, status_code=201)
def create_household(body: HouseholdCreate, db: Session = Depends(get_db)):
    token, token_hash = new_token()
    household = Household(name=body.name)
    db.add_all([household, Member(household=household, name=body.member_name, token_hash=token_hash, role="owner")])
    db.commit()
    return {"token": token, "household": household}


@router.get("/household", response_model=HouseholdOut)
def get_household(member: Member = Depends(current_member)):
    return member.household


@router.patch("/household", response_model=HouseholdOut)
def update_household(body: HouseholdSettings, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    household = member.household
    changes = body.model_dump(exclude_unset=True)
    if changes.get("plz", household.plz) != household.plz:
        household.lat = household.lng = None  # neu geocodieren
    if (stores := changes.pop("stores", None)) is not None:
        household.stores = [HouseholdStore(**s) for s in stores]
    for key, value in changes.items():
        setattr(household, key, value)
    db.commit()
    return household


def household_offers(db: Session, household: Household, chain: str | None = None) -> list[Offer]:
    """Heute gültige Angebote der eingestellten Läden/Filialen."""
    stores = {(s.chain, s.store_ref) for s in household.stores if s.enabled and (chain is None or s.chain == chain)}
    if not stores:
        return []
    today = date.today()
    return list(db.scalars(select(Offer).where(
        or_(*[(Offer.chain == c) & (Offer.store_ref == ref) for c, ref in stores]),
        Offer.valid_from <= today, Offer.valid_to >= today,
    ).order_by(Offer.category, Offer.title)))


@router.get("/offers", response_model=list[OfferOut])
def list_offers(chain: str | None = None, category: str | None = None, q: str | None = None,
                member: Member = Depends(current_member), db: Session = Depends(get_db)):
    offers = household_offers(db, member.household, chain)
    return [o for o in offers if (not category or o.category == category) and (not q or q.lower() in o.title.lower())]


@router.get("/stores/nearby", response_model=list[NearbyStoreOut])
def stores_nearby(radius_km: int | None = Query(None, ge=1, le=30),
                  member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Läden bekannter Ketten im Umkreis (kaufDA, Ersatz OpenStreetMap). Ohne radius_km gilt der Umkreis des Haushalts."""
    household = member.household
    try:
        if household.lat is None:
            if not household.plz:
                raise ValueError("Keine PLZ eingestellt")
            household.lat, household.lng = offers_import.geocode(household.plz)
            db.commit()
        return nearby_stores.nearby(household.lat, household.lng, radius_km or household.radius_km)
    except ValueError as e:
        raise HTTPException(422, str(e))
    except (httpx.HTTPError, RuntimeError) as e:
        raise HTTPException(502, f"Ladensuche nicht erreichbar: {e}")


@router.post("/offers/refresh")
def refresh_offers(member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Lädt die Angebote der Läden des Haushalts neu (dauert je nach Läden 10–60 s)."""
    try:
        count = offers_import.refresh_household(db, member.household)
    except (ValueError, RuntimeError) as e:
        raise HTTPException(422, str(e))
    return {"imported": count}


def _prefs(household: Household, options: dict) -> SimpleNamespace:
    """Haushaltswerte mit den Plan-Optionen überschrieben, ohne den Haushalt selbst zu ändern."""
    values = {c.key: getattr(household, c.key) for c in Household.__table__.columns}
    return SimpleNamespace(**(values | {k: v for k, v in options.items() if k != "wishes"}))


@router.post("/plans", response_model=PlanOut, status_code=201)
def create_plan(options: PlanOptions | None = None, member: Member = Depends(current_member),
                db: Session = Depends(get_db)):
    """Optionaler Body PlanOptions gilt nur für diesen Plan; save_as_default schreibt ihn (ohne wishes) in den Haushalt."""
    household = member.household
    opts = options.model_dump(exclude_none=True, exclude={"save_as_default"}) if options else {}
    prefs = _prefs(household, opts)
    slots = planner.week_slots(prefs)
    if not slots:
        raise HTTPException(422, "Keine Mahlzeiten oder Tage eingestellt")
    try:
        priced = planner.make_plan(prefs, household_offers(db, household), slots, favorites=[],
                                   wishes=opts.get("wishes", ""))
    except RuntimeError as e:
        raise HTTPException(502, str(e))
    if options and options.save_as_default:
        for key, value in opts.items():
            if key != "wishes":
                setattr(household, key, value)
    year, week, _ = date.today().isocalendar()
    plan = MealPlan(household_id=household.id, week=f"{year}-W{week:02d}", total_cents=priced.total_cents,
                    saved_cents=priced.saved_cents,
                    params={"budget": prefs.budget_food_week_cents, "options": opts, "usage": priced.usage})
    for meal, cost in zip(priced.draft.meals, priced.meal_costs):
        plan.entries.append(MealPlanEntry(day=meal.day, meal_type=meal.meal_type, recipe=_recipe(household, meal),
                                          cost_cents=cost))
    db.add(plan)
    db.commit()
    return plan


@router.get("/usage", response_model=UsageOut)
def usage(member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Geschätzte KI-Kosten des Haushalts (Pläne inkl. Neu würfeln)."""
    plans = db.scalars(select(MealPlan).where(MealPlan.household_id == member.household_id).order_by(MealPlan.id))
    costs = [(p.params or {}).get("usage", {}).get("cost_cents", 0) for p in plans]
    return {"plans": len(costs), "cost_cents_total": round(sum(costs), 4), "cost_cents_last": costs[-1] if costs else 0}


def _recipe(household: Household, meal: planner.PlannedMeal) -> Recipe:
    return Recipe(household_id=household.id, title=meal.title, description=meal.description, cuisine=meal.cuisine,
                  meal_type=meal.meal_type, servings=meal.servings, prep_minutes=meal.prep_minutes,
                  ingredients=[i.model_dump() for i in meal.ingredients], steps=meal.steps)


def _current(db: Session, household_id: int) -> MealPlan:
    plan = db.scalar(select(MealPlan).where(MealPlan.household_id == household_id).order_by(MealPlan.id.desc()).limit(1))
    if not plan:
        raise HTTPException(404, "Noch kein Wochenplan")
    return plan


def _entry(plan: MealPlan, entry_id: int) -> MealPlanEntry:
    entry = next((e for e in plan.entries if e.id == entry_id), None)
    if entry is None:
        raise HTTPException(404, "Gericht nicht im aktuellen Plan")
    return entry


@router.get("/plans/current", response_model=PlanOut)
def current_plan(member: Member = Depends(current_member), db: Session = Depends(get_db)):
    return _current(db, member.household_id)


@router.patch("/plans/current/entries/{entry_id}", response_model=PlanOut)
def update_entry(entry_id: int, body: EntryUpdate, member: Member = Depends(current_member),
                 db: Session = Depends(get_db)):
    plan = _current(db, member.household_id)
    _entry(plan, entry_id).locked = body.locked
    db.commit()
    return plan


@router.post("/plans/current/entries/{entry_id}/reroll", response_model=PlanOut)
def reroll_entry(entry_id: int, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Ersetzt ein Gericht durch ein neues der KI und rechnet die Kosten des ganzen Plans neu."""
    household, plan = member.household, _current(db, member.household_id)
    entry = _entry(plan, entry_id)
    if entry.locked:
        raise HTTPException(409, "Gericht ist fixiert")
    offers = household_offers(db, household)
    others = [e.recipe.title for e in plan.entries if e is not entry]
    opts = (plan.params or {}).get("options", {})
    try:
        meal, call_usage = planner.reroll_meal(_prefs(household, opts), offers, (entry.day, entry.meal_type),
                                               [entry.recipe.title, *others], wishes=opts.get("wishes", ""))
    except RuntimeError as e:
        raise HTTPException(502, str(e))
    entry.recipe = _recipe(household, meal)
    plan.params = {**plan.params, "usage": planner.add_usage(plan.params.get("usage", {}), call_usage)}

    draft = planner.PlanDraft(meals=[planner.PlannedMeal(
        day=e.day, meal_type=e.meal_type, title=e.recipe.title, description=e.recipe.description,
        cuisine=e.recipe.cuisine, prep_minutes=e.recipe.prep_minutes, servings=e.recipe.servings,
        ingredients=[planner.PlannedIngredient(**i) for i in e.recipe.ingredients], steps=e.recipe.steps,
    ) for e in plan.entries])
    priced = planner.price(draft, {o.id: o for o in offers})
    plan.total_cents, plan.saved_cents = priced.total_cents, priced.saved_cents
    for e, cost in zip(plan.entries, priced.meal_costs):
        e.cost_cents = cost
    db.commit()
    return plan
