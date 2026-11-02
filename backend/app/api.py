from datetime import date

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.core.auth import current_member, new_token
from app.core.db import get_db
from app.models import Household, HouseholdStore, MealPlan, MealPlanEntry, Member, Offer, Recipe
from app.schemas import HouseholdCreate, HouseholdCreated, HouseholdOut, HouseholdSettings, OfferOut, PlanOut
from app.services import planner

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
    if (stores := changes.pop("stores", None)) is not None:
        household.stores = [HouseholdStore(**s) for s in stores]
    for key, value in changes.items():
        setattr(household, key, value)
    db.commit()
    return household


def household_offers(db: Session, household: Household, chain: str | None = None) -> list[Offer]:
    """Heute gültige Angebote der eingestellten Läden/Filialen."""
    stores = [s for s in household.stores if s.enabled and (chain is None or s.chain == chain)]
    if not stores:
        return []
    today = date.today()
    return list(db.scalars(select(Offer).where(
        or_(*[(Offer.chain == s.chain) & (Offer.store_ref == s.store_ref) for s in stores]),
        Offer.valid_from <= today, Offer.valid_to >= today,
    ).order_by(Offer.category, Offer.title)))


@router.get("/offers", response_model=list[OfferOut])
def list_offers(chain: str | None = None, category: str | None = None, q: str | None = None,
                member: Member = Depends(current_member), db: Session = Depends(get_db)):
    offers = household_offers(db, member.household, chain)
    return [o for o in offers if (not category or o.category == category) and (not q or q.lower() in o.title.lower())]


@router.post("/plans", response_model=PlanOut, status_code=201)
def create_plan(member: Member = Depends(current_member), db: Session = Depends(get_db)):
    household = member.household
    slots = planner.week_slots(household)
    if not slots:
        raise HTTPException(422, "Keine Mahlzeiten oder Tage eingestellt")
    priced = planner.make_plan(household, household_offers(db, household), slots, favorites=[])
    year, week, _ = date.today().isocalendar()
    plan = MealPlan(household_id=household.id, week=f"{year}-W{week:02d}", total_cents=priced.total_cents,
                    saved_cents=priced.saved_cents, params={"budget": household.budget_food_week_cents})
    for meal, cost in zip(priced.draft.meals, priced.meal_costs):
        recipe = Recipe(household_id=household.id, title=meal.title, description=meal.description, cuisine=meal.cuisine,
                        meal_type=meal.meal_type, servings=meal.servings, prep_minutes=meal.prep_minutes,
                        ingredients=[i.model_dump() for i in meal.ingredients], steps=meal.steps)
        plan.entries.append(MealPlanEntry(day=meal.day, meal_type=meal.meal_type, recipe=recipe, cost_cents=cost))
    db.add(plan)
    db.commit()
    return plan


@router.get("/plans/current", response_model=PlanOut)
def current_plan(member: Member = Depends(current_member), db: Session = Depends(get_db)):
    plan = db.scalar(select(MealPlan).where(MealPlan.household_id == member.household_id)
                     .order_by(MealPlan.id.desc()).limit(1))
    if not plan:
        raise HTTPException(404, "Noch kein Wochenplan")
    return plan
