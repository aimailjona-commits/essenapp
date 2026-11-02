import base64
import secrets
import shutil
import threading
import time
from concurrent.futures import ThreadPoolExecutor, wait
from datetime import date, datetime, timedelta
from pathlib import Path
from types import SimpleNamespace

import httpx
from fastapi import APIRouter, Body, Depends, File, Form, HTTPException, Query, Request, Response, UploadFile
from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.core.auth import current_member, new_token
from app.core.config import settings
from app.core.db import get_db
from app.models import (AiCost, Household, HouseholdStore, Invite, MealPlan, MealPlanEntry, Member, MemberProfile,
                        MemberToken, Offer, PairingCode, PantryItem, PricePoint, PushDevice, Rating, Recipe,
                        RecipeFavorite, ShoppingItem, ShoppingList, WeeklyBasic)
from app.schemas import (ConsumeIn, CookIdeaOut, DeviceIn, EntryUpdate, FavoriteOut, HouseholdCreate,
                         HouseholdCreated, HouseholdOut, HouseholdSettings, ImportIn, InviteOut, ItemCreate, ItemOut,
                         ItemPatchOut, ItemUpdate, JoinIn, ListCreate, ListOut, ListSummary, MemberOut,
                         MemberProfileOut, NearbyStoreOut, OfferHistoryOut, OfferNutritionOut, OfferOut,
                         PairedTokenOut, PairIn, PairingCodeOut, PairOut, PantryIn, PantryOut, PantryUpdate,
                         PlanNutritionOut, PlanOptions, PlanOut, ProfileOut, ProfileUpdate, PushSettings,
                         PushSettingsUpdate, RatingIn, RatingOut, RecipeCard, RecipeCostOut, RecipeDetail, RecipeIn,
                         RecipeOut, RecipePatch, ReplaceIn, ScanOut, ShareOut, StepImagesOut, UsageOut,
                         EntryLeftover, GeneratorOut, GuestsIn, NoMoodIn, PostponeIn, SpecialsOut, SubstituteIn,
                         SubstitutesOut, WeeklyBasicIn, WeeklyBasicOut, WeeklyBasicUpdate)
from app.services import (food_map, nearby_stores, nutrition, offers_import, pantry_ai, planner, prices, push,
                          recipe_images, recipe_import, recipes, seasons, substitutes, variety)
from app.services.matching import Matcher
from app.services.normalize import base_unit, cents, ingredient_key
from app.services.pricing import PANTRY_WORDS, Stock

router = APIRouter()


@router.post("/households", response_model=HouseholdCreated, status_code=201)
def create_household(body: HouseholdCreate, db: Session = Depends(get_db)):
    token, token_hash = new_token()
    household = Household(name=body.name)
    db.add_all([household, Member(household=household, name=body.member_name, token_hash=token_hash, role="owner")])
    db.flush()
    db.add_all([PantryItem(household_id=household.id, name=n, ingredient_key=ingredient_key(n), is_basic=True)
                for n in BASICS])
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
    if (rules := changes.pop("variety", None)) is not None:
        household.variety = {**(household.variety or {}), **{k: v for k, v in rules.items() if v is not None}}
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


@router.get("/offers/{offer_id}/history", response_model=OfferHistoryOut)
def offer_history(offer_id: int, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Preisverlauf des Produkts (alle Läden, letzte 12 Wochen) und Urteil (28)."""
    offer = db.get(Offer, offer_id)
    if offer is None:
        raise HTTPException(404, "Angebot nicht gefunden")
    if offer.product_id is None:  # Import vor dem Preisverlauf: jetzt nachtragen
        prices.record(db, [offer])
        db.commit()
    points = list(db.scalars(select(PricePoint).where(PricePoint.product_id == offer.product_id)))
    return prices.history(points, offer.price_cents, offer.regular_price_cents, prices.point_week(offer, date.today()))


NUTRITION_CATEGORIES = (*planner.FOOD_CATEGORIES, "getraenke")


@router.get("/offers/{offer_id}/nutrition", response_model=OfferNutritionOut)
def offer_nutrition(offer_id: int, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Nährwerte im Angebotsdetail (2), nur bei sicherer Zuordnung (hoch). Die erste Anfrage startet die Zuordnung im
    Hintergrund (status pending); Drogerie/Haushalt bekommen keine."""
    offer = db.get(Offer, offer_id)
    if offer is None:
        raise HTTPException(404, "Angebot nicht gefunden")
    none = {"status": "none", "food": "", "per_100g": None, "per_pack": None}
    if offer.category not in NUTRITION_CATEGORIES:
        return none
    hit = food_map.load(db, [offer.title]).get(ingredient_key(offer.title))
    if hit is None:
        food_map.map_later([offer.title])
        return none | {"status": "pending"}
    m, food = hit
    if food is None or m.confidence != "hoch":
        return none
    per_100 = nutrition.per_100(food)
    grams = nutrition.grams(offer.amount, offer.unit, m.grams_per_piece) if offer.amount else None
    return {"status": "ok", "food": food.description, "per_100g": per_100.rounded(),
            "per_pack": per_100.scaled(grams / 100).rounded() if grams else None}


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
    """Haushaltswerte mit den Plan-Optionen überschrieben, ohne den Haushalt selbst zu ändern.
    Allergien und Ausschlüsse: Vereinigung aus Haushalt und allen Mitglieder-Profilen (harte Regel, 48)."""
    values = {c.key: getattr(household, c.key) for c in Household.__table__.columns}
    profiles = [m.profile for m in household.members if m.profile]
    values["allergies"] = list(dict.fromkeys([*household.allergies, *(a for p in profiles for a in p.allergies)]))
    values["excluded_ingredients"] = list(dict.fromkeys(
        [*household.excluded_ingredients, *(d for p in profiles for d in p.dislikes)]))
    return SimpleNamespace(**(values | {k: v for k, v in options.items() if k != "wishes"}))


def _profiles(household: Household) -> list[MemberProfile]:
    """Ab zwei Mitgliedern mit mindestens einem Profil zählen die Profile (fehlende = Vorschlag)."""
    members = household.members
    if len(members) > 1 and any(m.profile for m in members):
        return [m.profile or new_profile(m) for m in members]
    return [m.profile for m in members if m.profile]


def _eaters(household: Household, persons: int, slots: list[tuple[int, str]]) -> dict:
    """Esser je Slot (48), Lunchbox nur für Mitglieder mit diesem Lunchbox-Tag (24)."""
    return planner.slot_eaters(_profiles(household), persons, slots)


PLAN_ONLY = ("wishes", "guests", "guest_budget_cents", "special")  # gelten nie als Haushalts-Standard


def fish_ok(prefs) -> bool:
    """Fisch-Pflicht (12) nur, wenn Fisch erlaubt ist."""
    return prefs.diet not in ("vegetarisch", "vegan") and "fisch" not in " ".join(
        [*prefs.allergies, *prefs.excluded_ingredients]).lower()


def weekly_basics(db: Session, household_id: int) -> list[WeeklyBasic]:
    return list(db.scalars(select(WeeklyBasic).where(WeeklyBasic.household_id == household_id)
                           .order_by(WeeklyBasic.id)))


def weekly_stock(db: Session, household_id: int) -> list[PantryItem]:
    """Wochen-Basics (23) als Vorrat (nicht gespeichert): sie kommen über die Liste (Quelle basics), Gerichte kaufen
    sie nicht nochmal."""
    return [PantryItem(name=b.name, ingredient_key=ingredient_key(b.name), amount=b.amount, unit=b.unit,
                       is_basic=False) for b in weekly_basics(db, household_id)]


def plan_stock(db: Session, household_id: int) -> list[PantryItem]:
    return household_pantry(db, household_id) + weekly_stock(db, household_id)


def plan_extra(db: Session, household: Household, prefs, slots: list[tuple[int, str]], hint: str = "") -> list[str]:
    """Kompakte Zusatzzeilen für den variablen Prompt-Teil: Abwechslung (12), Saison/Feiertage (25),
    Frühstücks-Basics und Snack-Ziel (23), Special-Hinweis (25)."""
    lines = [variety.rules_line(variety.rules_of(household.variety), fish_ok(prefs)),
             *seasons.prompt_lines(date.today(), household.plz)]
    meals = {m for _, m in slots}
    if meals & {"fruehstueck", "snack"} and (basics := weekly_basics(db, household.id)):
        lines.append("Frühstücks-/Snack-Basics (kauft der Haushalt jede Woche, bevorzugt nutzen): " + ", ".join(
            b.name + (f" {b.amount:g}{b.unit}" if b.amount else "") for b in basics))
    if "snack" in meals:
        goals = list(dict.fromkeys(p.goal for p in _profiles(household))) or [prefs.nutrition_goal]
        lines.append(f"Snack-Ziel: {', '.join(goals)}")
    if hint:
        lines.append(hint)
    return lines


@router.post("/plans", response_model=PlanOut, status_code=201)
def create_plan(options: PlanOptions | None = None, member: Member = Depends(current_member),
                db: Session = Depends(get_db)):
    """Optionaler Body PlanOptions gilt nur für diesen Plan; save_as_default schreibt ihn (ohne wishes, Gäste,
    Special) in den Haushalt. Gäste (15) erhöhen die Portionen ihres Slots (Gast = 1 Portion), guest_budget_cents
    das Budget; special (25) fügt die Slots der Vorlage hinzu."""
    household = member.household
    opts = options.model_dump(exclude_none=True, exclude={"save_as_default"}) if options else {}
    prefs = _prefs(household, opts)
    extra_slots, hint = [], ""
    if key := opts.get("special"):
        if key not in seasons.EVENTS:
            raise HTTPException(422, "Unbekanntes Special")
        extra_slots, hint = seasons.special_plan(key, date.today(), prefs.plan_days)
    profiles = _profiles(household)
    lunch_days = {d for p in profiles for d in (p.lunchbox_days or [])}
    all_slots = planner.week_slots(prefs, lunch_days, extra_slots)
    eaters = planner.slot_eaters(profiles, prefs.persons, all_slots)
    guests = {(g["day"], g["meal_type"]): g["count"] for g in opts.get("guests", []) if g["count"]}
    slots = [s for s in all_slots if eaters[s][1] + guests.get(s, 0) > 0]  # niemand isst mit → Slot entfällt
    if not slots:
        raise HTTPException(422, "Keine Mahlzeiten oder Tage eingestellt")
    prefs.budget_food_week_cents += opts.get("guest_budget_cents", 0)
    portions = {s: eaters[s][1] + guests.get(s, 0) for s in slots}
    rules = variety.rules_of(household.variety)
    memory = recipes.planner_memory(db, household.id, repeat_weeks=rules["repeat_weeks"])
    try:
        priced = planner.make_plan(prefs, household_offers(db, household), slots, favorites=memory["favorites"],
                                   wishes=opts.get("wishes", ""), portions=portions,
                                   pantry=household_pantry(db, household.id), never=memory["never"],
                                   recent=memory["recent"], rules=rules, fish_ok=fish_ok(prefs),
                                   extra=plan_extra(db, household, prefs, slots, hint), guests=guests,
                                   stock=plan_stock(db, household.id))
    except RuntimeError as e:
        raise HTTPException(502, str(e))
    planner.add_images(priced)  # erst freie Fotos, dann KI (E13/E41)
    if options and options.save_as_default:
        for key, value in opts.items():
            if key not in PLAN_ONLY:
                setattr(household, key, value)
    year, week, _ = date.today().isocalendar()
    plan = MealPlan(household_id=household.id, week=f"{year}-W{week:02d}", total_cents=priced.total_cents,
                    saved_cents=priced.saved_cents,
                    params={"budget": prefs.budget_food_week_cents, "options": opts, "usage": priced.usage,
                            "rests": priced.rests})
    for meal, cost, image in zip(priced.draft.meals, priced.meal_costs, priced.images):
        slot = (meal.day, meal.meal_type)
        plan.entries.append(MealPlanEntry(day=meal.day, meal_type=meal.meal_type, recipe=_recipe(household, meal, image),
                                          cost_cents=cost, portions=eaters[slot][0], portions_total=portions[slot],
                                          guests=guests.get(slot, 0)))
    db.add(plan)
    db.flush()
    sync_plan(db, household.id)
    db.commit()
    food_map.map_later([i["name"] for e in plan.entries for i in e.recipe.ingredients])
    return plan_out(db, plan)


@router.get("/usage", response_model=UsageOut)
def usage(member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Geschätzte KI-Kosten des Haushalts (Pläne inkl. Neu würfeln)."""
    plans = db.scalars(select(MealPlan).where(MealPlan.household_id == member.household_id).order_by(MealPlan.id))
    costs = [(p.params or {}).get("usage", {}).get("cost_cents", 0) for p in plans]
    log = list(db.scalars(select(AiCost).where(AiCost.household_id == member.household_id)
                          .order_by(AiCost.id.desc())))
    by_kind = {"plan": round(sum(costs), 4)}
    for row in log:
        by_kind[row.kind] = round(by_kind.get(row.kind, 0) + row.cost_cents, 4)
    return {"plans": len(costs), "cost_cents_total": round(sum(by_kind.values()), 4),
            "cost_cents_last": costs[-1] if costs else 0, "by_kind": by_kind, "recent": log[:20]}


def _recipe(household: Household, meal: planner.PlannedMeal, image: str = "") -> Recipe:
    return Recipe(household_id=household.id, title=meal.title, description=meal.description, cuisine=meal.cuisine,
                  meal_type=meal.meal_type, servings=meal.servings, prep_minutes=meal.prep_minutes,
                  ingredients=[i.model_dump() for i in meal.ingredients], steps=meal.steps, image_url=image[:500],
                  tags=[meal.side, meal.protein])  # Beilage/Protein für die Abwechslungsregeln (12)


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
    return plan_out(db, _current(db, member.household_id))


@router.patch("/plans/current/entries/{entry_id}", response_model=PlanOut)
def update_entry(entry_id: int, body: EntryUpdate, member: Member = Depends(current_member),
                 db: Session = Depends(get_db)):
    plan = _current(db, member.household_id)
    _entry(plan, entry_id).locked = body.locked
    db.commit()
    return plan_out(db, plan)


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
    prefs, slot, pantry = _prefs(household, opts), (entry.day, entry.meal_type), household_pantry(db, household.id)
    portions, total = _eaters(household, prefs.persons, [slot])[slot]
    total += entry.guests
    if not total:
        raise HTTPException(422, "Bei dieser Mahlzeit isst niemand mit")
    rules = variety.rules_of(household.variety)
    memory = recipes.planner_memory(db, household.id, repeat_weeks=rules["repeat_weeks"])
    try:
        meal, call_usage = planner.reroll_meal(prefs, offers, slot, [entry.recipe.title, *others],
                                               wishes=opts.get("wishes", ""), portions={slot: total}, pantry=pantry,
                                               extra=plan_extra(db, household, prefs, [slot]),
                                               guests={slot: entry.guests}, repeat_weeks=rules["repeat_weeks"],
                                               **memory)
    except RuntimeError as e:
        raise HTTPException(502, str(e))
    entry.recipe = _recipe(household, meal, recipe_images.find_image(meal.image_query or meal.title))
    entry.portions, entry.portions_total, entry.scale = portions, total, 1
    plan.params = {**plan.params, "usage": planner.add_usage(plan.params.get("usage", {}), call_usage)}
    reprice(db, plan, offers, pantry)
    sync_plan(db, household.id)
    db.commit()
    food_map.map_later([i["name"] for i in entry.recipe.ingredients])
    return plan_out(db, plan)


def entry_ingredients(entry: MealPlanEntry) -> list[dict]:
    """Zutaten mit der Menge im Plan (Rezeptmenge × scale)."""
    return [{**i, "amount": (i.get("amount") or 0) * (entry.scale or 1)} for i in entry.recipe.ingredients]


def pricer(db: Session, offers: list[Offer], names: list[str]) -> recipes.Pricer:
    return recipes.Pricer(offers, recipes.history_offers(db), food_map.piece_grams(db, names))


def reprice(db: Session, plan: MealPlan, offers: list[Offer], pantry: list[PantryItem]) -> None:
    """Kosten des ganzen Plans neu (ganze Packungen über alle Gerichte); eingesetzte Rezepte ohne KI-Preise
    bekommen Angebot bzw. Normalpreis-Schätzung über den Namensabgleich."""
    names = [i["name"] for e in plan.entries for i in e.recipe.ingredients]
    p = pricer(db, offers, names)
    draft = planner.PlanDraft(meals=[planner.PlannedMeal(
        day=e.day, meal_type=e.meal_type, title=e.recipe.title, description=e.recipe.description,
        cuisine=e.recipe.cuisine, prep_minutes=e.recipe.prep_minutes, servings=e.recipe.servings,
        ingredients=[planner.PlannedIngredient(**p.planned(i)) for i in entry_ingredients(e)], steps=e.recipe.steps,
        protein=dish_of(e).protein,
    ) for e in plan.entries])
    priced = planner.price(draft, {o.id: o for o in offers}, [*pantry, *weekly_stock(db, plan.household_id)])
    plan.params = {**(plan.params or {}), "rests": priced.rests}  # Reste-Badges/-Karte (19) passend zum neuen Stand
    plan.total_cents, plan.saved_cents = priced.total_cents, priced.saved_cents
    for e, cost in zip(plan.entries, priced.meal_costs):
        e.cost_cents = cost


@router.post("/plans/current/entries/{entry_id}/replace", response_model=PlanOut)
def replace_entry(entry_id: int, body: ReplaceIn, member: Member = Depends(current_member),
                  db: Session = Depends(get_db)):
    """„Diese Woche einplanen“: setzt ein gespeichertes Rezept in den Slot (ohne KI), Mengen auf die Esser des Slots
    skaliert, Kosten neu, Einkaufsliste synchron."""
    household, plan = member.household, _current(db, member.household_id)
    entry = _entry(plan, entry_id)
    recipe = household_recipe(db, member, body.recipe_id)
    target = entry.portions_total or entry.recipe.servings
    entry.recipe, entry.scale = recipe, target / recipe.servings
    reprice(db, plan, household_offers(db, household), household_pantry(db, household.id))
    sync_plan(db, household.id)
    db.commit()
    food_map.map_later([i["name"] for i in recipe.ingredients])
    return plan_out(db, plan)


# --- Teilen: Einladungen, Mitglieder, gemeinsame Einkaufslisten (E40) ---

INVITE_DAYS = 7


def base_url(request: Request) -> str:
    return str(request.base_url).rstrip("/")


def new_code() -> str:
    return secrets.token_urlsafe(6)  # 8 Zeichen


def valid_invite(db: Session, code: str) -> Invite:
    invite = db.scalar(select(Invite).where(Invite.code == code[:16], Invite.expires_at > datetime.now()))
    if not invite:
        raise HTTPException(404, "Einladung ungültig oder abgelaufen")
    return invite


def share_invite(db: Session, household_id: int) -> Invite:
    """Noch mindestens einen Tag gültige Einladung wiederverwenden, sonst neue."""
    invite = db.scalar(select(Invite).where(Invite.household_id == household_id,
                                            Invite.expires_at > datetime.now() + timedelta(days=1)).limit(1))
    if not invite:
        invite = Invite(household_id=household_id, code=new_code(),
                        expires_at=datetime.now() + timedelta(days=INVITE_DAYS))
        db.add(invite)
        db.commit()
    return invite


def join_household(db: Session, code: str, member_name: str) -> tuple[str, Member]:
    invite = valid_invite(db, code)
    token, token_hash = new_token()
    member = Member(household_id=invite.household_id, name=member_name, token_hash=token_hash)
    db.add(member)
    db.commit()
    return token, member


@router.post("/household/invites", response_model=InviteOut, status_code=201)
def create_invite(request: Request, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    invite = Invite(household_id=member.household_id, code=new_code(),
                    expires_at=datetime.now() + timedelta(days=INVITE_DAYS))
    db.add(invite)
    db.commit()
    return {"code": invite.code, "url": f"{base_url(request)}/join/{invite.code}"}


@router.post("/join/{code}", response_model=HouseholdCreated, status_code=201)
def join(code: str, body: JoinIn, db: Session = Depends(get_db)):
    token, member = join_household(db, code, body.member_name)
    return {"token": token, "household": member.household}


@router.get("/household/share", response_model=ShareOut)
def share_household(request: Request, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    return {"url": f"{base_url(request)}/h/{share_invite(db, member.household_id).code}"}


@router.get("/household/members", response_model=list[MemberOut])
def list_members(member: Member = Depends(current_member)):
    return member.household.members


@router.delete("/household/members/{member_id}", status_code=204)
def remove_member(member_id: int, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    if member.role != "owner":
        raise HTTPException(403, "Nur der Besitzer kann Mitglieder entfernen")
    if member_id == member.id:
        raise HTTPException(422, "Du kannst dich nicht selbst entfernen")
    other = db.get(Member, member_id)
    if not other or other.household_id != member.household_id:
        raise HTTPException(404, "Mitglied nicht gefunden")
    db.delete(other)
    db.commit()
    return Response(status_code=204)


# --- Kopplungscode für die Teilen-Erweiterung (E48: keine App Group mit kostenloser Apple-ID) ---

PAIRING_MINUTES, PAIR_MAX_FAILS, PAIR_WINDOW = 10, 5, 600
_pair_fails: dict[str, list[float]] = {}  # shortcut: Fehlversuche je IP im Speicher (weg nach Neustart), reicht für 1 Prozess
_pair_lock = threading.Lock()


@router.post("/me/pairing-code", response_model=PairingCodeOut, status_code=201)
def create_pairing_code(member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Neuer 6-stelliger Code für dieses Mitglied (ältere Codes des Mitglieds verfallen), 10 min gültig, einmalig."""
    now = datetime.now()
    for old in db.scalars(select(PairingCode).where(or_(PairingCode.member_id == member.id,
                                                        PairingCode.expires_at < now - timedelta(days=1)))):
        db.delete(old)
    db.flush()
    taken = set(db.scalars(select(PairingCode.code)))
    code = f"{secrets.randbelow(10**6):06d}"
    while code in taken:
        code = f"{secrets.randbelow(10**6):06d}"
    pairing = PairingCode(member_id=member.id, code=code, expires_at=now + timedelta(minutes=PAIRING_MINUTES))
    db.add(pairing)
    db.commit()
    return pairing


def _pair_failed(ip: str, status: int, detail: str):
    with _pair_lock:
        _pair_fails.setdefault(ip, []).append(time.time())
    raise HTTPException(status, detail)


@router.post("/pair", response_model=PairOut, status_code=201)
def pair(body: PairIn, request: Request, db: Session = Depends(get_db)):
    """Code einlösen (ohne Auth) → eigenes, widerrufbares Token für dasselbe Mitglied. 404 unbekannt, 410 abgelaufen
    oder schon benutzt, 429 nach 5 Fehlversuchen in 10 min je IP."""
    ip = request.client.host if request.client else "?"
    with _pair_lock:
        recent = [t for t in _pair_fails.get(ip, []) if time.time() - t < PAIR_WINDOW]
        _pair_fails[ip] = recent
    if len(recent) >= PAIR_MAX_FAILS:
        raise HTTPException(429, "Zu viele Fehlversuche – bitte in 10 Minuten erneut versuchen")
    pairing = db.scalar(select(PairingCode).where(PairingCode.code == body.code))
    if pairing is None:
        _pair_failed(ip, 404, "Code ungültig")
    if pairing.used_at is not None:
        _pair_failed(ip, 410, "Code wurde schon benutzt")
    if pairing.expires_at < datetime.now():
        _pair_failed(ip, 410, "Code abgelaufen")
    token, token_hash = new_token()
    pairing.used_at = datetime.now()
    member = db.get(Member, pairing.member_id)
    db.add(MemberToken(member_id=member.id, token_hash=token_hash, label=body.label))
    db.commit()
    return {"token": token, "household": member.household, "member_id": member.id, "member_name": member.name}


@router.get("/me/tokens", response_model=list[PairedTokenOut])
def paired_tokens(member: Member = Depends(current_member)):
    """Gekoppelte Erweiterungen/Geräte dieses Mitglieds (zum Widerrufen)."""
    return member.tokens


@router.delete("/me/tokens/{token_id}", status_code=204)
def revoke_token(token_id: int, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    token = db.get(MemberToken, token_id)
    if token is None or token.member_id != member.id:
        raise HTTPException(404, "Kopplung nicht gefunden")
    db.delete(token)
    db.commit()
    return Response(status_code=204)


def household_list(db: Session, household_id: int) -> ShoppingList:
    """Die eine Haushaltsliste, bei Bedarf angelegt."""
    lst = db.scalar(select(ShoppingList).where(ShoppingList.household_id == household_id,
                                               ShoppingList.kind == "household"))
    if not lst:
        lst = ShoppingList(household_id=household_id, name="Einkaufsliste", kind="household")
        db.add(lst)
        db.flush()
    return lst


def member_list(db: Session, member: Member, list_id: int) -> ShoppingList:
    lst = db.get(ShoppingList, list_id)
    if not lst or lst.household_id != member.household_id:
        raise HTTPException(404, "Liste nicht gefunden")
    return lst


def shared_list(db: Session, share_code: str) -> ShoppingList:
    lst = db.scalar(select(ShoppingList).where(ShoppingList.share_code == share_code[:16],
                                               ShoppingList.kind == "oneoff"))
    if not lst:
        raise HTTPException(404, "Liste nicht gefunden")
    return lst


def list_item(lst: ShoppingList, item_id: int) -> ShoppingItem:
    item = next((i for i in lst.items if i.id == item_id), None)
    if item is None:
        raise HTTPException(404, "Eintrag nicht gefunden")
    return item


def share_url(request: Request, lst: ShoppingList) -> str | None:
    return f"{base_url(request)}/l/{lst.share_code}" if lst.share_code else None


def list_out(request: Request, lst: ShoppingList) -> dict:
    return {"id": lst.id, "name": lst.name, "kind": lst.kind, "share_url": share_url(request, lst), "items": lst.items}


def add_item(db: Session, lst: ShoppingList, body: ItemCreate, by: str) -> ShoppingItem:
    item = ShoppingItem(**body.model_dump(), added_by=by, source="manual")
    lst.items.append(item)
    db.commit()
    return item


def update_item(db: Session, item: ShoppingItem, body: ItemUpdate, by: str) -> ShoppingItem:
    changes = body.model_dump(exclude_unset=True)
    if changes.get("name") is None:
        changes.pop("name", None)
    if changes.get("checked") is None:
        changes.pop("checked", None)
    else:
        item.checked_by = by if changes["checked"] else ""
    for key, value in changes.items():
        setattr(item, key, value)
    db.commit()
    return item


def sync_plan(db: Session, household_id: int) -> ShoppingList:
    """Zutaten des aktuellen Plans (ohne Vorrat) als source=plan in die Haushaltsliste.
    Gleiche Zutat/offer_id wird summiert, vorhandene Plan-Einträge aktualisiert (Haken bleiben),
    Plan-Einträge, die nicht mehr im Plan sind, entfernt. Manuelle Einträge bleiben unberührt."""
    lst = household_list(db, household_id)
    plan = db.scalar(select(MealPlan).where(MealPlan.household_id == household_id)
                     .order_by(MealPlan.id.desc()).limit(1))

    def key_of(name: str, unit: str, offer_id: int | None) -> tuple:
        return ("offer", offer_id) if offer_id else ("name", name.strip().lower(), unit)

    entries = plan.entries if plan else []
    user_names = [i["name"] for e in entries for i in e.recipe.ingredients if "offer_id" not in i]
    match = pricer(db, household_offers(db, db.get(Household, household_id)), user_names) if user_names else None
    needed: dict[tuple, dict] = {}
    for entry in entries:
        for ing in entry_ingredients(entry):
            if "offer_id" not in ing:  # eingesetztes Rezept (ohne KI-Zuordnung): Angebot über den Namen
                ing["offer_id"] = match.line(ing).offer_id
            unit, offer_id = ing.get("unit", ""), ing.get("offer_id")
            row = needed.setdefault(key_of(ing["name"], unit, offer_id), {"name": ing["name"][:100], "amount": 0.0,
                                    "unit": unit, "offer_id": offer_id, "in_pantry": True})
            row["amount"] += ing.get("amount") or 0
            row["in_pantry"] &= bool(ing.get("in_pantry"))
    stock = Stock(plan_stock(db, household_id))  # nur fehlende Mengen auf die Liste (60), Wochen-Basics (23)
    for key, row in list(needed.items()):
        have = stock.take(row["name"], row["unit"], row["amount"], row["in_pantry"])
        if have > 0 and have >= row["amount"]:
            del needed[key]
        else:
            row["amount"] -= have
    offer_ids = [r["offer_id"] for r in needed.values() if r["offer_id"]]
    chains = dict(db.execute(select(Offer.id, Offer.chain).where(Offer.id.in_(offer_ids))).all())

    existing = {key_of(i.name, i.unit, i.offer_id): i for i in lst.items if i.source == "plan"}
    for key, item in existing.items():
        if key not in needed:
            lst.items.remove(item)
    for key, row in needed.items():
        item = existing.get(key)
        if item is None:
            item = ShoppingItem(source="plan", added_by="Wochenplan")
            lst.items.append(item)
        item.name, item.unit, item.offer_id = row["name"], row["unit"], row["offer_id"]
        item.amount = row["amount"] or None
        item.chain = chains.get(row["offer_id"], "")
    db.flush()
    return lst


@router.get("/lists", response_model=list[ListSummary])
def get_lists(request: Request, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    household_list(db, member.household_id)
    db.commit()
    lists = db.scalars(select(ShoppingList).where(ShoppingList.household_id == member.household_id)
                       .order_by(ShoppingList.kind != "household", ShoppingList.id))
    return [{"id": lst.id, "name": lst.name, "kind": lst.kind, "share_url": share_url(request, lst),
             "open_count": sum(not i.checked for i in lst.items), "total_count": len(lst.items)} for lst in lists]


@router.post("/lists", response_model=ListOut, status_code=201)
def create_list(body: ListCreate, request: Request, member: Member = Depends(current_member),
                db: Session = Depends(get_db)):
    lst = ShoppingList(household_id=member.household_id, name=body.name, kind="oneoff", share_code=new_code())
    db.add(lst)
    db.commit()
    return list_out(request, lst)


@router.post("/lists/household/sync-plan", response_model=ListOut)
def sync_plan_endpoint(request: Request, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    lst = sync_plan(db, member.household_id)
    db.commit()
    return list_out(request, lst)


@router.get("/lists/{list_id}", response_model=ListOut)
def get_list(list_id: int, request: Request, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    return list_out(request, member_list(db, member, list_id))


@router.delete("/lists/{list_id}", status_code=204)
def delete_list(list_id: int, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    lst = member_list(db, member, list_id)
    if lst.kind == "household":
        raise HTTPException(422, "Die Haushaltsliste kann nicht gelöscht werden")
    db.delete(lst)
    db.commit()
    return Response(status_code=204)


@router.post("/lists/{list_id}/items", response_model=ItemOut, status_code=201)
def create_item(list_id: int, body: ItemCreate, member: Member = Depends(current_member),
                db: Session = Depends(get_db)):
    return add_item(db, member_list(db, member, list_id), body, member.name)


def member_item(db: Session, member: Member, item_id: int) -> ShoppingItem:
    item = db.get(ShoppingItem, item_id)
    if not item or db.get(ShoppingList, item.list_id).household_id != member.household_id:
        raise HTTPException(404, "Eintrag nicht gefunden")
    return item


def pantry_suggest(db: Session, item: ShoppingItem) -> bool:
    """„In den Vorrat?“ standardmäßig ja: Basics, Angebote der Kategorie vorrat, bekannte haltbare Begriffe."""
    offer = db.get(Offer, item.offer_id) if item.offer_id else None
    words = ingredient_key(item.name).split()
    return (item.source == "basics" or (offer is not None and offer.category == "vorrat")
            or any(w.startswith(p) or w.endswith(p) for w in words for p in PANTRY_WORDS))


@router.patch("/items/{item_id}", response_model=ItemPatchOut)
def patch_item(item_id: int, body: ItemUpdate, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    item = update_item(db, member_item(db, member, item_id), body, member.name)
    return {**ItemOut.model_validate(item).model_dump(), "pantry_suggest": bool(body.checked) and pantry_suggest(db, item)}


@router.post("/items/{item_id}/to-pantry", response_model=PantryOut)
def item_to_pantry(item_id: int, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Abgehakten Artikel in den Vorrat: gleiche Zutat+Einheit wird aufaddiert, ein Basic gilt wieder als vorhanden."""
    item = member_item(db, member, item_id)
    amount, unit = base_unit(item.amount, item.unit)
    pantry = add_pantry(db, member.household_id, item.name, amount, unit, "list")
    db.commit()
    return pantry


def add_pantry(db: Session, household_id: int, name: str, amount: float | None, unit: str, source: str,
               best_before: date | None = None, location: str | None = None) -> PantryItem:
    """In den Vorrat: gleiche Zutat+Einheit wird aufaddiert, ein Basic gilt wieder als vorhanden;
    Haltbarkeit = die frühere."""
    key = ingredient_key(name)
    pantry = next((p for p in household_pantry(db, household_id)
                   if p.ingredient_key == key and (p.is_basic or p.unit == unit)), None)
    if pantry is None:
        pantry = PantryItem(household_id=household_id, name=name, ingredient_key=key, amount=amount, unit=unit,
                            source=source, best_before=best_before, location=location)
        db.add(pantry)
        db.flush()
        return pantry
    if pantry.is_basic or amount is None or pantry.amount is None:
        pantry.amount = None  # Basic wieder voll bzw. Menge unbekannt
    else:
        pantry.amount += amount
    if best_before and (pantry.best_before is None or best_before < pantry.best_before):
        pantry.best_before = best_before
    pantry.location = location or pantry.location
    db.flush()
    return pantry


@router.delete("/items/{item_id}", status_code=204)
def delete_item(item_id: int, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    db.delete(member_item(db, member, item_id))
    db.commit()
    return Response(status_code=204)


# Gäste ohne Konto: nur die eine einmalige Liste hinter share_code, Name per ?guest=
GUEST = Query("Gast", min_length=1, max_length=50)


@router.get("/shared/{share_code}", response_model=ListOut)
def get_shared(share_code: str, request: Request, db: Session = Depends(get_db)):
    return list_out(request, shared_list(db, share_code))


@router.post("/shared/{share_code}/items", response_model=ItemOut, status_code=201)
def create_shared_item(share_code: str, body: ItemCreate, guest: str = GUEST, db: Session = Depends(get_db)):
    return add_item(db, shared_list(db, share_code), body, guest)


@router.patch("/shared/{share_code}/items/{item_id}", response_model=ItemOut)
def patch_shared_item(share_code: str, item_id: int, body: ItemUpdate, guest: str = GUEST,
                      db: Session = Depends(get_db)):
    return update_item(db, list_item(shared_list(db, share_code), item_id), body, guest)


# --- Ziele pro Person (48) ---

GOAL_DEFAULTS = {"ausgewogen": (2000, 80), "proteinreich": (2200, 140), "kalorienarm": (1600, 90),
                 "eigenes": (2000, 80)}  # Vorschlag kcal/Tag, Protein g/Tag


def new_profile(member: Member) -> MemberProfile:
    """Profil-Vorschlag aus den Haushaltswerten (nicht gespeichert)."""
    h = member.household
    goal = h.nutrition_goal if h.nutrition_goal in GOAL_DEFAULTS else "ausgewogen"
    kcal, protein = GOAL_DEFAULTS[goal]
    return MemberProfile(member_id=member.id, emoji="🙂", goal=goal, kcal=kcal, protein_g=protein,
                         allergies=list(h.allergies), dislikes=list(h.excluded_ingredients), lunchbox_days=[],
                         eats={m: [True] * 7 for m in planner.MEAL_TYPES})


def member_profile(db: Session, member: Member) -> MemberProfile:
    """Profil des Mitglieds, beim ersten Abruf mit Werten aus dem Haushalt angelegt."""
    if member.profile is None:
        member.profile = new_profile(member)
        db.commit()
    return member.profile


def profile_out(member: Member, p: MemberProfile) -> dict:
    return {"member_id": member.id, "name": member.name, "emoji": p.emoji, "goal": p.goal, "kcal": p.kcal,
            "protein_g": p.protein_g, "allergies": p.allergies, "dislikes": p.dislikes,
            "lunchbox_days": p.lunchbox_days, "eats": p.eats}


@router.get("/me/profile", response_model=ProfileOut)
def get_profile(member: Member = Depends(current_member), db: Session = Depends(get_db)):
    return profile_out(member, member_profile(db, member))


@router.patch("/me/profile", response_model=ProfileOut)
def patch_profile(body: ProfileUpdate, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    p = member_profile(db, member)
    changes = body.model_dump(exclude_none=True)
    if "name" in changes:
        member.name = changes.pop("name")
    if "eats" in changes:
        changes["eats"] = {**p.eats, **changes["eats"]}
    if "lunchbox_days" in changes:
        changes["lunchbox_days"] = sorted(set(changes["lunchbox_days"]))
    for key, value in changes.items():
        setattr(p, key, value)
    db.commit()
    return profile_out(member, p)


@router.get("/household/profiles", response_model=list[MemberProfileOut])
def household_profiles(member: Member = Depends(current_member), db: Session = Depends(get_db)):
    return [profile_out(m, member_profile(db, m)) for m in member.household.members]


# --- Vorratskammer (60) ---

BASICS = ("Salz", "Pfeffer", "Öl", "Zucker", "Mehl", "Essig", "Gemüsebrühe")  # Standard beim Anlegen eines Haushalts


def household_pantry(db: Session, household_id: int) -> list[PantryItem]:
    """Vorrat, bald ablaufende zuerst, Basics am Ende."""
    return list(db.scalars(select(PantryItem).where(PantryItem.household_id == household_id).order_by(
        PantryItem.is_basic, PantryItem.best_before.is_(None), PantryItem.best_before, PantryItem.name)))


def member_pantry_item(db: Session, member: Member, item_id: int) -> PantryItem:
    item = db.get(PantryItem, item_id)
    if not item or item.household_id != member.household_id:
        raise HTTPException(404, "Vorrat-Eintrag nicht gefunden")
    return item


@router.get("/pantry", response_model=list[PantryOut])
def get_pantry(member: Member = Depends(current_member), db: Session = Depends(get_db)):
    return household_pantry(db, member.household_id)


@router.post("/pantry", response_model=PantryOut, status_code=201)
def create_pantry_item(body: PantryIn, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    item = PantryItem(household_id=member.household_id, ingredient_key=ingredient_key(body.name), **body.model_dump())
    db.add(item)
    db.commit()
    return item


@router.patch("/pantry/{item_id}", response_model=PantryOut)
def patch_pantry_item(item_id: int, body: PantryUpdate, member: Member = Depends(current_member),
                      db: Session = Depends(get_db)):
    item = member_pantry_item(db, member, item_id)
    changes = body.model_dump(exclude_unset=True)
    for key in ("name", "unit", "is_basic"):  # nicht null-bar; amount/best_before/location dürfen null werden
        if changes.get(key) is None:
            changes.pop(key, None)
    if "name" in changes:
        item.ingredient_key = ingredient_key(changes["name"])
    for key, value in changes.items():
        setattr(item, key, value)
    db.commit()
    return item


@router.delete("/pantry/{item_id}", status_code=204)
def delete_pantry_item(item_id: int, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    db.delete(member_pantry_item(db, member, item_id))
    db.commit()
    return Response(status_code=204)


@router.post("/pantry/basics/{item_id}/empty", response_model=ItemOut)
def empty_basic(item_id: int, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Basic leer gemeldet → gilt nicht mehr als vorhanden und kommt (source basics) auf die Haushaltsliste."""
    item = member_pantry_item(db, member, item_id)
    if not item.is_basic:
        raise HTTPException(422, "Kein Basic")
    item.amount = 0
    lst = household_list(db, member.household_id)
    entry = next((i for i in lst.items if not i.checked and ingredient_key(i.name) == item.ingredient_key), None)
    if entry is None:
        entry = ShoppingItem(name=item.name, source="basics", added_by=member.name)
        lst.items.append(entry)
    db.commit()
    return entry


MAX_SCAN_IMAGES, MAX_SCAN_BYTES = 5, 5 * 1024 * 1024


@router.post("/pantry/scan", response_model=ScanOut)
def pantry_scan(files: list[UploadFile] = File(...),
                mode: str = Form("kuehlschrank", pattern="^(kuehlschrank|vorrat|gefrierfach)$"),
                member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Kühlschrank-Foto (69): 1–5 JPEGs (multipart „files“, App verkleinert auf 1024 px), Modus kuehlschrank|vorrat|
    gefrierfach → erkannte Lebensmittel. Speichert nichts; übernehmen über POST /pantry/bulk nach dem Prüf-Bildschirm."""
    if not 1 <= len(files) <= MAX_SCAN_IMAGES:
        raise HTTPException(422, "1 bis 5 Fotos")
    images = [f.file.read(MAX_SCAN_BYTES + 1) for f in files]
    if any(len(i) > MAX_SCAN_BYTES or not i.startswith(b"\xff\xd8\xff") for i in images):
        raise HTTPException(422, "Fotos müssen JPEGs bis 5 MB sein")
    try:
        items, usage = pantry_ai.scan(images, mode)
    except RuntimeError as e:
        raise HTTPException(502, str(e))
    planner.log_cost(db, member.household_id, "scan", usage["cost_cents"], usage["model"],
                     f"{len(images)} Foto(s), {len(items)} erkannt")
    db.commit()
    return {"items": items, "cost_cents": usage["cost_cents"]}


@router.post("/pantry/bulk", response_model=list[PantryOut], status_code=201)
def pantry_bulk(body: list[PantryIn] = Body(min_length=1, max_length=100), member: Member = Depends(current_member),
                db: Session = Depends(get_db)):
    """„In den Vorrat übernehmen“ (Prüf-Bildschirm 69, source scan): mehrere Einträge auf einmal, gleiche
    Zutat+Einheit wird aufaddiert (wie Abhaken → Vorrat). Gibt die betroffenen Einträge zurück."""
    out: dict[int, PantryItem] = {}
    for item in body:
        p = add_pantry(db, member.household_id, item.name, item.amount, item.unit, item.source, item.best_before,
                       item.location)
        out[p.id] = p
    db.commit()
    return list(out.values())


@router.post("/pantry/cook-now", response_model=list[CookIdeaOut])
def cook_now(member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """„Was koche ich jetzt?“ (69): bis zu 3 Gerichte (max. 30 min) aus Vorrat + Basics, höchstens 2 fehlende Zutaten
    (im Code geprüft), wenigste fehlende zuerst. Die Gerichte werden als Rezepte (source ai) gespeichert, damit
    Rezeptdetail und „Heute kochen“ (POST /plans/current/entries/{id}/replace) funktionieren."""
    household = member.household
    pantry = household_pantry(db, household.id)
    if not any(not p.is_basic and p.amount != 0 for p in pantry):
        raise HTTPException(422, "Vorrat ist leer")
    try:
        ideas, usage = pantry_ai.cook_now(_prefs(household, {}), pantry)
    except RuntimeError as e:
        raise HTTPException(502, str(e))
    planner.log_cost(db, household.id, "cook_now", usage["cost_cents"], usage["model"], f"{len(ideas)} Vorschläge")
    return save_ideas(db, household, ideas)


def save_ideas(db: Session, household: Household, ideas: list, image_wait: float | None = None) -> list[dict]:
    """Vorschläge als Rezepte (source ai) speichern, damit Rezeptdetail und „Heute kochen“ (…/replace) gehen.
    image_wait: höchstens so lange auf Fotos warten (Rest ohne Foto; die Suche läuft weiter und füllt den Cache)."""
    pool = ThreadPoolExecutor(max_workers=3)
    futures = [pool.submit(recipe_images.find_image, i.image_query or i.title) for i, _ in ideas]
    wait(futures, timeout=image_wait)
    images = [f.result() if f.done() else "" for f in futures]
    pool.shutdown(wait=False)
    out = []
    for (idea, missing), image in zip(ideas, images):
        ingredients = [ingredient_row(i.model_dump()) for i in idea.ingredients][:60]
        recipe = Recipe(household_id=household.id, title=idea.title[:200], description=idea.description[:500],
                        cuisine=idea.cuisine[:30], meal_type=idea.meal_type, servings=min(max(idea.servings, 1), 20),
                        prep_minutes=min(max(idea.prep_minutes, 1), 600), image_url=image[:500],
                        ingredients=ingredients, steps=[s[:1000] for s in idea.steps][:40],
                        tags=list(variety.classify(idea.title, [i["name"] for i in ingredients])))
        db.add(recipe)
        out.append((recipe, missing))
    db.commit()
    food_map.map_later([i["name"] for r, _ in out for i in r.ingredients])
    return [{"recipe": recipe_out(db, r, False), "missing": m} for r, m in out]


@router.post("/no-mood", response_model=list[CookIdeaOut])
def no_mood(body: NoMoodIn | None = None, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """„Keine Lust“ (16): 3 Gerichte ≤ 15 min nur aus Vorrat + Basics + abgehakten Listenartikeln, nichts fehlt (im
    Code geprüft). exclude = schon gezeigte Titel („Wischen für weitere 3“). Auswahl → POST …/entries/{id}/replace,
    danach „Auf morgen verschieben?“ → POST /plans/current/postpone mit dem ursprünglichen Rezept."""
    household = member.household
    bought = [PantryItem(name=i.name, ingredient_key=ingredient_key(i.name), unit=unit, amount=amount, is_basic=False)
              for i in household_list(db, household.id).items if i.checked
              for amount, unit in [base_unit(i.amount, i.unit) if i.unit else (i.amount, "")]]
    pantry = household_pantry(db, household.id) + bought
    if not any(not p.is_basic and p.amount != 0 for p in pantry):
        raise HTTPException(422, "Vorrat ist leer")
    try:
        ideas, usage = pantry_ai.cook_now(_prefs(household, {}), pantry, minutes=15, max_missing=0,
                                          exclude=body.exclude if body else [])
    except RuntimeError as e:
        raise HTTPException(502, str(e))
    planner.log_cost(db, household.id, "no_mood", usage["cost_cents"], usage["model"], f"{len(ideas)} Vorschläge")
    return save_ideas(db, household, ideas, image_wait=1)


@router.post("/pantry/consume", response_model=list[PantryOut])
def consume(body: ConsumeIn, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Gekocht: zieht die Rezeptmengen × servings_factor vom Vorrat ab (gleicher Name und Einheit, bald ablaufende
    zuerst; Basics bleiben). Gibt die geänderten Einträge zurück, amount 0 = gelöscht."""
    if body.entry_id is not None:
        entry = db.get(MealPlanEntry, body.entry_id)
        if not entry or db.get(MealPlan, entry.plan_id).household_id != member.household_id:
            raise HTTPException(404, "Gericht nicht gefunden")
        recipe, scale = entry.recipe, entry.scale or 1
    elif body.recipe_id is not None:
        recipe = db.get(Recipe, body.recipe_id)
        if not recipe or recipe.household_id not in (None, member.household_id):
            raise HTTPException(404, "Rezept nicht gefunden")
        scale = 1
    else:
        raise HTTPException(422, "entry_id oder recipe_id fehlt")
    stock = [p for p in household_pantry(db, member.household_id) if not p.is_basic and p.amount is not None]
    changed: dict[int, PantryItem] = {}
    for ing in recipe.ingredients:
        need, key = (ing.get("amount") or 0) * scale * body.servings_factor, ingredient_key(ing["name"])
        for p in stock:
            if need > 0 and p.amount > 0 and p.ingredient_key == key and p.unit == ing.get("unit", ""):
                took = min(p.amount, need)
                p.amount, need = p.amount - took, need - took
                changed[p.id] = p
    db.flush()
    out = [PantryOut.model_validate(p) for p in changed.values()]
    for p in changed.values():
        if p.amount <= 0:
            db.delete(p)
    db.commit()
    return out


# --- Meine Rezepte (3) + Nährwerte (2) ---

MEDIA = Path(__file__).resolve().parents[1] / "media"  # backend/media, ausgeliefert unter /media (main.py)
MAX_IMAGE = 2 * 1024 * 1024
IMPORTED = ("instagram", "web", "shared")
FILTERS = ("alle", "favoriten", "eigene", "importiert", "im_angebot", "zuletzt")


def household_recipe(db: Session, member: Member, recipe_id: int) -> Recipe:
    recipe = db.get(Recipe, recipe_id)
    if not recipe or recipe.household_id not in (None, member.household_id):
        raise HTTPException(404, "Rezept nicht gefunden")
    return recipe


def own_recipe(db: Session, member: Member, recipe_id: int) -> Recipe:
    """Nur eigene und importierte Rezepte des Haushalts dürfen geändert/gelöscht werden."""
    recipe = household_recipe(db, member, recipe_id)
    if recipe.source == "ai" or recipe.household_id != member.household_id:
        raise HTTPException(403, "Nur eigene oder importierte Rezepte können geändert werden")
    return recipe


def save_image(recipe: Recipe, data: str) -> None:
    """Base64-JPEG → backend/media/recipes/<id>.jpg; ?v= damit Apps ein geändertes Foto neu laden."""
    try:
        raw = base64.b64decode(data, validate=True)
    except ValueError:
        raise HTTPException(422, "Bild ist kein gültiges Base64")
    if len(raw) > MAX_IMAGE:
        raise HTTPException(422, "Bild zu groß (max. 2 MB)")
    if not raw.startswith(b"\xff\xd8\xff"):
        raise HTTPException(422, "Bild muss ein JPEG sein")
    store_jpeg(recipe, raw)


def store_jpeg(recipe: Recipe, raw: bytes) -> None:
    folder = MEDIA / "recipes"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / f"{recipe.id}.jpg").write_bytes(raw)
    recipe.image_url = f"/media/recipes/{recipe.id}.jpg?v={int(time.time())}"


def ingredient_row(i: dict) -> dict:
    amount, unit = base_unit(i["amount"], i["unit"]) if i["unit"] in ("kg", "l") else (i["amount"], i["unit"])
    return {"name": i["name"].strip(), "amount": amount, "unit": unit}


def apply_recipe(db: Session, recipe: Recipe, body: RecipePatch) -> None:
    changes = body.model_dump(exclude_unset=True, exclude={"image"})
    if changes.get("ingredients") is not None:
        changes["ingredients"] = [ingredient_row(i) for i in changes["ingredients"]]
    if recipe.id and changes.get("steps") is not None and changes["steps"] != recipe.steps:
        recipe.step_images = []  # Schritte geändert → Schritt-Bilder passen nicht mehr (9)
        shutil.rmtree(MEDIA / "steps" / str(recipe.id), ignore_errors=True)
    for key, value in changes.items():
        if value is not None:
            setattr(recipe, key, value)
    db.flush()
    if body.image:
        save_image(recipe, body.image)


def cards(db: Session, member: Member, items: list[Recipe]) -> list[dict]:
    """Karten mit Live-Kosten (aktuelle Angebote der Läden), Favorit, Sternen."""
    p = pricer(db, household_offers(db, member.household), [i["name"] for r in items for i in r.ingredients])
    stats = recipes.rating_stats(db, [r.id for r in items])
    favs = recipes.favorite_ids(db, member.household_id)
    out = []
    for r in items:
        _, total, share = p.cost(r.ingredients)
        st = stats.get(r.id)
        out.append({"id": r.id, "title": r.title, "image_url": r.image_url, "cuisine": r.cuisine,
                    "meal_type": r.meal_type, "prep_minutes": r.prep_minutes, "servings": r.servings,
                    "source": r.source, "source_author": r.source_author, "favorite": r.id in favs,
                    "avg_stars": st.avg_stars if st else None, "last_cooked": st.last_cooked if st else None,
                    "cost_per_serving_cents": cents(total / r.servings), "offer_share": share})
    return out


@router.get("/recipes", response_model=list[RecipeCard])
def list_recipes(filter: str = Query("alle", pattern="^(" + "|".join(FILTERS) + ")$"),
                 q: str | None = Query(None, max_length=100),
                 member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Meine Rezepte: eigene/importierte + favorisierte/bewertete KI-Gerichte, neueste zuerst
    (zuletzt: nach letztem Kochen)."""
    items = recipes.household_recipes(db, member.household_id)
    if q:
        needle = q.strip().lower()
        items = [r for r in items if needle in r.title.lower() or any(needle in t.lower() for t in r.tags)]
    favs = recipes.favorite_ids(db, member.household_id)
    items = {"favoriten": [r for r in items if r.id in favs], "eigene": [r for r in items if r.source == "user"],
             "importiert": [r for r in items if r.source in IMPORTED]}.get(filter, items)
    out = cards(db, member, items)
    if filter == "im_angebot":
        out = [c for c in out if c["offer_share"] >= recipes.OFFER_BADGE]
    if filter == "zuletzt":
        out = sorted((c for c in out if c["last_cooked"]), key=lambda c: c["last_cooked"], reverse=True)
    return out


@router.get("/recipes/deals", response_model=list[RecipeCard])
def recipe_deals(member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Start-Karte „Lieblingsrezepte diese Woche günstig“: Favoriten/≥4★ mit Kostenanteil im Angebot ≥ 40 %."""
    items = recipes.household_recipes(db, member.household_id)
    stats = recipes.rating_stats(db, [r.id for r in items])
    favs = recipes.favorite_ids(db, member.household_id)
    liked = [r for r in items if not recipes.is_disliked(stats.get(r.id))
             and (r.id in favs or (r.id in stats and (stats[r.id].avg_stars or 0) >= 4))]
    return sorted((c for c in cards(db, member, liked) if c["offer_share"] >= recipes.OFFER_BADGE),
                  key=lambda c: -c["offer_share"])


def recipe_out(db: Session, recipe: Recipe, favorite: bool) -> dict:
    nut, comp = nutrition.dish(recipe.ingredients, food_map.load(db, [i["name"] for i in recipe.ingredients]),
                               recipe.servings)
    return {c.key: getattr(recipe, c.key) for c in Recipe.__table__.columns} | {
        "favorite": favorite, "nutrition": nut, "composition": comp}


def recipe_detail(db: Session, member: Member, recipe: Recipe) -> dict:
    card = cards(db, member, [recipe])[0]
    names = dict(db.execute(select(Member.id, Member.name).where(Member.household_id == member.household_id)).all())
    ratings = db.scalars(select(Rating).where(Rating.recipe_id == recipe.id).order_by(Rating.cooked_at.desc()))
    return recipe_out(db, recipe, card["favorite"]) | {k: card[k] for k in (
        "avg_stars", "last_cooked", "cost_per_serving_cents", "offer_share")} | {
        "ratings": [{"id": r.id, "member_id": r.member_id, "member_name": names.get(r.member_id, ""), "stars": r.stars,
                     "again": r.again, "note": r.note, "cooked_at": r.cooked_at} for r in ratings]}


def start_step_images(member: Member, recipe: Recipe) -> bool:
    """Fehlende Schritt-Bilder im Hintergrund erzeugen (9), wenn FAL_KEY gesetzt und eingeschaltet; True = läuft."""
    todo = [*(recipe.step_images or []), *[""] * len(recipe.steps)][:len(recipe.steps)]
    if settings.fal_key and member.household.step_images and not all(todo):
        recipe_images.step_images_later(recipe.id, MEDIA)
    return recipe_images.steps_pending(recipe.id)


@router.get("/recipes/{recipe_id}", response_model=RecipeDetail)
def get_recipe(recipe_id: int, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Beim Öffnen starten fehlende Schritt-Bilder im Hintergrund (Platzhalter-Schimmer, bis step_images gefüllt)."""
    recipe = household_recipe(db, member, recipe_id)
    start_step_images(member, recipe)
    return recipe_detail(db, member, recipe)


@router.post("/recipes/{recipe_id}/step-images", response_model=StepImagesOut, status_code=202)
def step_images(recipe_id: int, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Schritt-Bilder anfordern (z.B. Kochmodus mit Plan-Gericht). Vorhandene werden nie neu erzeugt."""
    recipe = household_recipe(db, member, recipe_id)
    if not settings.fal_key:
        raise HTTPException(422, "Schritt-Bilder nicht eingerichtet (FAL_KEY fehlt)")
    if not member.household.step_images:
        raise HTTPException(422, "Schritt-Bilder sind in den Einstellungen ausgeschaltet")
    pending = start_step_images(member, recipe)
    return {"step_images": RecipeOut.model_validate(recipe).step_images, "pending": pending}


@router.post("/import", response_model=RecipeDetail, status_code=201)
def import_recipe(body: ImportIn, response: Response, member: Member = Depends(current_member),
                  db: Session = Depends(get_db)):
    """Rezept-Import (5) aus Instagram-Beitrag/Reel oder Webseite. Gleiche URL schon importiert → dieses Rezept (200).
    422 „Kein Rezept gefunden“, 502 Seite/KI nicht erreichbar."""
    url = recipe_import.canonical(str(body.url))
    existing = db.scalar(select(Recipe).where(Recipe.household_id == member.household_id, Recipe.source_url == url,
                                              Recipe.source.in_(("instagram", "web"))).limit(1))
    if existing:
        response.status_code = 200
        return recipe_detail(db, member, existing)
    try:
        found = recipe_import.read(url, body.text)
    except recipe_import.NoRecipe as e:
        if e.usage:
            planner.log_cost(db, member.household_id, "import", e.usage["cost_cents"], e.usage["model"],
                             f"kein Rezept: {url}")
            db.commit()
        raise HTTPException(422, "Kein Rezept gefunden")
    except httpx.HTTPStatusError as e:
        raise HTTPException(502, f"Seite nicht abrufbar (HTTP {e.response.status_code})")
    except httpx.HTTPError:
        raise HTTPException(502, "Seite nicht erreichbar")
    except RuntimeError as e:
        raise HTTPException(502, str(e))
    r = found.recipe
    recipe = Recipe(household_id=member.household_id, source=found.source, source_url=url[:500],
                    source_author=found.author, title=r.title.strip()[:200] or "Rezept",
                    description=r.description[:500], cuisine=r.cuisine[:30], meal_type=r.meal_type,
                    servings=min(max(r.servings, 1), 20), prep_minutes=min(max(r.prep_minutes, 1), 600),
                    tags=[t.strip()[:50] for t in r.tags if t.strip()][:20],
                    steps=[s.strip()[:1000] for s in r.steps if s.strip()][:40],
                    ingredients=[{**ingredient_row({"name": i.name[:100], "amount": max(i.amount, 0), "unit": i.unit}),
                                  **({"estimated": True} if i.estimated else {})} for i in r.ingredients][:60])
    db.add(recipe)
    db.flush()
    planner.log_cost(db, member.household_id, "import", found.usage["cost_cents"], found.usage["model"], url)
    raw = None
    if found.image_url:
        try:
            raw = recipe_images.download_jpeg(found.image_url)
        except httpx.HTTPError:
            pass  # Vorschaubild ist fürs Rezept nicht nötig
    if raw:
        store_jpeg(recipe, raw)  # Instagram-Bild-URLs verfallen, darum lokal gespeichert
    elif found.source == "web" and found.image_url:
        recipe.image_url = found.image_url[:500]
    else:
        recipe.image_url = recipe_images.find_image(r.image_query or r.title)[:500]
    db.commit()
    food_map.map_later([i["name"] for i in recipe.ingredients])
    return recipe_detail(db, member, recipe)


@router.get("/recipes/{recipe_id}/cost", response_model=RecipeCostOut)
def recipe_cost(recipe_id: int, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Kosten live aus den aktuellen Angeboten der Läden (Verbrauchsmenge, nicht ganze Packungen)."""
    recipe = household_recipe(db, member, recipe_id)
    p = pricer(db, household_offers(db, member.household), [i["name"] for i in recipe.ingredients])
    lines, total, share = p.cost(recipe.ingredients)
    return {"cost_cents": total, "cost_per_serving_cents": cents(total / recipe.servings), "offer_share": share,
            "lines": [vars(line) for line in lines]}


@router.post("/recipes", response_model=RecipeDetail, status_code=201)
def create_recipe(body: RecipeIn, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Eigenes Rezept (source=user)."""
    recipe = Recipe(household_id=member.household_id, source="user", title=body.title, meal_type=body.meal_type,
                    servings=body.servings, prep_minutes=body.prep_minutes)
    db.add(recipe)
    apply_recipe(db, recipe, body)
    db.commit()
    food_map.map_later([i["name"] for i in recipe.ingredients])
    return recipe_detail(db, member, recipe)


@router.patch("/recipes/{recipe_id}", response_model=RecipeDetail)
def patch_recipe(recipe_id: int, body: RecipePatch, member: Member = Depends(current_member),
                 db: Session = Depends(get_db)):
    recipe = own_recipe(db, member, recipe_id)
    apply_recipe(db, recipe, body)
    db.commit()
    food_map.map_later([i["name"] for i in recipe.ingredients])
    return recipe_detail(db, member, recipe)


@router.delete("/recipes/{recipe_id}", status_code=204)
def delete_recipe(recipe_id: int, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Löscht Favorit, Bewertungen und Rezept. Steht es noch in einem Wochenplan, bleibt es dort als Plan-Gericht
    (source=ai) erhalten und verschwindet nur aus „Meine Rezepte“."""
    recipe = own_recipe(db, member, recipe_id)
    for model in (RecipeFavorite, Rating):
        for row in db.scalars(select(model).where(model.recipe_id == recipe.id)):
            db.delete(row)
    if db.scalar(select(MealPlanEntry.id).where(MealPlanEntry.recipe_id == recipe.id).limit(1)):
        recipe.source = "ai"
    else:
        (MEDIA / "recipes" / f"{recipe.id}.jpg").unlink(missing_ok=True)
        shutil.rmtree(MEDIA / "steps" / str(recipe.id), ignore_errors=True)
        db.delete(recipe)
    db.commit()
    return Response(status_code=204)


@router.post("/recipes/{recipe_id}/favorite", response_model=FavoriteOut)
def toggle_favorite(recipe_id: int, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Herz an/aus – gilt für den ganzen Haushalt."""
    recipe = household_recipe(db, member, recipe_id)
    fav = db.scalar(select(RecipeFavorite).where(RecipeFavorite.household_id == member.household_id,
                                                 RecipeFavorite.recipe_id == recipe.id))
    if fav:
        db.delete(fav)
    else:
        db.add(RecipeFavorite(household_id=member.household_id, recipe_id=recipe.id, member_id=member.id))
    db.commit()
    return {"favorite": fav is None}


@router.post("/recipes/{recipe_id}/rate", response_model=RatingOut, status_code=201)
def rate_recipe(recipe_id: int, body: RatingIn, member: Member = Depends(current_member),
                db: Session = Depends(get_db)):
    """Bewertung nach „Gekocht ★“: Sterne, „Wieder kochen?“, Notiz, wer, wann."""
    recipe = household_recipe(db, member, recipe_id)
    rating = Rating(recipe_id=recipe.id, member_id=member.id, stars=body.stars, again=body.again, note=body.note,
                    cooked_at=body.cooked_at or datetime.now())
    db.add(rating)
    db.commit()
    return {"id": rating.id, "member_id": member.id, "member_name": member.name, "stars": rating.stars,
            "again": rating.again, "note": rating.note, "cooked_at": rating.cooked_at}


def dish_of(e: MealPlanEntry) -> variety.Dish:
    r = e.recipe
    side, protein = variety.tags_of(r.tags or [], r.title, [i["name"] for i in r.ingredients])
    return variety.Dish(e.day, e.meal_type, r.title, r.cuisine, side, protein, r.prep_minutes,
                        " ".join([r.description, *r.steps]))


def plan_monday(plan: MealPlan) -> date:
    year, week = plan.week.split("-W")
    return date.fromisocalendar(int(year), int(week), 1)


def leftover_out(r: dict) -> dict:
    until = r["until_day"]
    day = seasons.DAY_SHORT[until] if until < 7 else "Anfang nächster Woche"
    tip = "verbrauchen oder einfrieren" if r.get("meat") else "verbrauchen, z.B. im Frühstück, als Snack oder in einer Soße"
    return {"name": r["name"], "amount": r["amount"], "unit": r["unit"], "until_day": until,
            "suggestion": f"Bis {day} {tip}"}


def plan_variety(db: Session, plan: MealPlan) -> dict:
    """Chip im Plan-Kopf (12): live, damit Neu würfeln/Einsetzen/Verschieben ihn aktualisieren."""
    household = db.get(Household, plan.household_id)
    rules = variety.rules_of(household.variety)
    recent = recipes.recent_titles(db, plan.household_id, plan_monday(plan), rules["repeat_weeks"], exclude_plan=plan.id)
    c = variety.check([dish_of(e) for e in plan.entries], rules, fish_ok(_prefs(household, {})), recent)
    return {"ok": not c.issues, "issues": c.issues}


def plan_out(db: Session, plan: MealPlan) -> dict:
    """Plan mit Favorit, Nährwerten und Blüten-Daten pro Gericht (pro Portion; null, solange Zuordnung läuft),
    Reste-Badges und -Karte (19), Abwechslungs-Chip (12)."""
    out = PlanOut.model_validate(plan).model_dump()
    maps = food_map.load(db, [i["name"] for e in plan.entries for i in e.recipe.ingredients])
    favs = recipes.favorite_ids(db, plan.household_id)
    rests = (plan.params or {}).get("rests") or {}
    for meal, e in zip(out["entries"], plan.entries):
        nut, comp = nutrition.dish(e.recipe.ingredients, maps, e.portions_total or e.recipe.servings, e.scale or 1)
        meal["recipe"] |= {"favorite": e.recipe.id in favs, "nutrition": nut, "composition": comp}
        meal["rests"] = [{"name": n, "from_day": d} for n, d in
                         rests.get("badges", {}).get(planner.slot_key(e.day, e.meal_type), {}).items()]
    out["leftovers"] = {"planned": rests.get("planned", 0), "left": [leftover_out(r) for r in rests.get("left", [])]}
    out["variety"] = plan_variety(db, plan)
    return out


@router.get("/plans/current/nutrition", response_model=PlanNutritionOut)
def plan_nutrition(member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Pro Tag und Mitglied: Summe der Gerichte, bei denen es mitisst (Portion × Faktor), plus Ziele aus dem Profil."""
    plan, members = _current(db, member.household_id), member.household.members
    profiles = {m.id: m.profile or new_profile(m) for m in members}
    maps = food_map.load(db, [i["name"] for e in plan.entries for i in e.recipe.ingredients])
    days = sorted({e.day for e in plan.entries})
    sums = {(m.id, d): [nutrition.Nutrients(), True] for m in members for d in days}
    for e in plan.entries:
        nut, _ = nutrition.dish(e.recipe.ingredients, maps, e.portions_total or e.recipe.servings, e.scale or 1)
        eaters = e.portions or [{"member_id": m.id, "factor": planner.portion_factor(profiles[m.id].kcal)}
                                for m in members]  # alte Pläne ohne Esser: alle
        for p in eaters:
            if cell := sums.get((p["member_id"], e.day)):
                if nut is None:
                    cell[1] = False
                else:
                    cell[0] += nutrition.Nutrients(**nut).scaled(p["factor"])
    n = len(days) or 1
    return {"members": [{"member_id": m.id, "name": m.name, "emoji": profiles[m.id].emoji,
                         "kcal_goal": profiles[m.id].kcal, "protein_goal": profiles[m.id].protein_g,
                         "avg_kcal": round(sum(sums[(m.id, d)][0].kcal for d in days) / n, 1),
                         "avg_protein": round(sum(sums[(m.id, d)][0].protein for d in days) / n, 1)}
                        for m in members],
            "days": [{"day": d, "members": [{"member_id": m.id, **sums[(m.id, d)][0].rounded(),
                                             "complete": sums[(m.id, d)][1]} for m in members]} for d in days]}


# --- Push über Apple Push (E52) ---

@router.post("/me/push/device", status_code=204)
def register_device(body: DeviceIn, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Gerätetoken der App speichern (bei jedem Start; ein Token gehört immer zum zuletzt angemeldeten Mitglied)."""
    token = body.token.lower()
    device = db.scalar(select(PushDevice).where(PushDevice.token == token))
    if device is None:
        device = PushDevice(token=token)
        db.add(device)
    device.member_id, device.environment = member.id, body.environment
    db.commit()
    return Response(status_code=204)


@router.delete("/me/push/device/{token}", status_code=204)
def delete_device(token: str, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    device = db.scalar(select(PushDevice).where(PushDevice.token == token.lower()[:200],
                                                PushDevice.member_id == member.id))
    if device is None:
        raise HTTPException(404, "Gerät nicht gefunden")
    db.delete(device)
    db.commit()
    return Response(status_code=204)


@router.post("/me/push/test", status_code=204)
def test_push(member: Member = Depends(current_member)):
    if not member.devices:
        raise HTTPException(422, "Kein Gerät registriert")
    if not push.send(member, "Essenapp", "Test-Push – tippen öffnet die App.", click_url="essenapp://start",
                     thread_id="test"):
        raise HTTPException(502, "Push konnte nicht gesendet werden")
    return Response(status_code=204)


@router.get("/me/push/settings", response_model=PushSettings)
def get_push_settings(member: Member = Depends(current_member)):
    return member


@router.patch("/me/push/settings", response_model=PushSettings)
def patch_push_settings(body: PushSettingsUpdate, member: Member = Depends(current_member),
                        db: Session = Depends(get_db)):
    for key, value in body.model_dump(exclude_unset=True).items():
        if value is not None or key in ("quiet_hours", "lunchbox_push"):  # diese dürfen null werden (= aus)
            setattr(member, key, value)
    db.commit()
    return member


# --- Clever planen (Phase 11) ---

@router.post("/plans/current/entries/{entry_id}/guests", response_model=PlanOut)
def set_guests(entry_id: int, body: GuestsIn, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """„Gäste hinzufügen“ nachträglich (15), ohne KI: Mengen × (Portionen ohne Gäste + neu) / bisher, Kosten und
    Einkaufsliste neu."""
    plan = _current(db, member.household_id)
    entry = _entry(plan, entry_id)
    old = entry.portions_total or entry.recipe.servings
    new = old - entry.guests + body.count
    if new <= 0:
        raise HTTPException(422, "Bei dieser Mahlzeit isst dann niemand mit")
    entry.scale = (entry.scale or 1) * new / old
    entry.portions_total, entry.guests = new, body.count
    reprice(db, plan, household_offers(db, member.household), household_pantry(db, member.household_id))
    sync_plan(db, member.household_id)
    db.commit()
    return plan_out(db, plan)


@router.post("/plans/current/postpone", response_model=PlanOut)
def postpone(body: PostponeIn, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """„Auf morgen verschieben?“ (16): das ursprüngliche Gericht kommt auf body.day; die späteren, nicht fixierten
    Gerichte derselben Mahlzeit rücken je einen Plan-Tag weiter, das letzte fällt heraus. Mengen passen sich an die
    Esser des neuen Slots an (Rezepte bleiben pro Portion gleich)."""
    plan = _current(db, member.household_id)
    recipe = household_recipe(db, member, body.recipe_id)
    chain = sorted((e for e in plan.entries if e.meal_type == body.meal_type and e.day >= body.day and not e.locked),
                   key=lambda e: e.day)
    if not chain or chain[0].day != body.day:
        raise HTTPException(422, "An diesem Tag ist dafür kein freies Gericht geplant")
    moves = []
    for target, (r, src) in zip(chain, [(recipe, None), *[(e.recipe, e) for e in chain]]):
        total = target.portions_total or r.servings
        scale = (src.scale or 1) * total / (src.portions_total or src.recipe.servings) if src else total / r.servings
        moves.append((target, r, scale))
    for target, r, scale in moves:
        target.recipe, target.scale = r, scale
    reprice(db, plan, household_offers(db, member.household), household_pantry(db, member.household_id))
    sync_plan(db, member.household_id)
    db.commit()
    return plan_out(db, plan)


@router.get("/plans/current/entries/{entry_id}/leftovers", response_model=list[EntryLeftover])
def entry_leftovers(entry_id: int, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Nach dem Kochen (19): erwartete Reste angebrochener Packungen; bestätigt → POST /pantry/bulk (source rest)."""
    plan = _current(db, member.household_id)
    entry = _entry(plan, entry_id)
    rows = ((plan.params or {}).get("rests") or {}).get("after", {}).get(planner.slot_key(entry.day, entry.meal_type), [])
    monday = plan_monday(plan)
    return [{"name": r["name"], "amount": r["amount"], "unit": r["unit"],
             "best_before": monday + timedelta(days=r["until_day"]) if r["until_day"] is not None else None}
            for r in rows]


@router.get("/plans/generator", response_model=GeneratorOut)
def generator(member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Plan-Generator nach dem Push „Plan erstellen“ (17, essenapp://generator): Standards des Haushalts,
    Top-3-Angebote („Diese Woche im Angebot: …“), Special-Banner. Der Plan entsteht erst mit POST /plans."""
    h, today = member.household, date.today()
    deals, seen = [], set()
    for o in sorted((o for o in household_offers(db, h) if o.category in planner.FOOD_CATEGORIES
                     and o.regular_price_cents and o.regular_price_cents > o.price_cents),
                    key=lambda o: (o.price_cents / o.regular_price_cents, o.price_cents)):
        if o.title.lower() not in seen and len(deals) < 3:
            seen.add(o.title.lower())
            deals.append(o)
    defaults = PlanOptions(cuisines=h.cuisines, meal_types=h.meal_types, plan_days=h.plan_days,
                           budget_food_week_cents=h.budget_food_week_cents, nutrition_goal=h.nutrition_goal,
                           persons=h.persons, max_cook_minutes=h.max_cook_minutes, diet=h.diet)
    return {"week": seasons.plan_monday(today).isocalendar().week, "defaults": defaults, "top_offers": deals,
            "banner": seasons.specials(today, h.plz)["banner"]}


@router.get("/specials", response_model=SpecialsOut)
def get_specials(on: date | None = Query(None, alias="date"), member: Member = Depends(current_member)):
    """Feiertags-/Saison-Specials (25): Start-Banner 14 Tage vorher, Vorlagen, Feiertage (Bundesland aus der PLZ),
    Saisons. ?date=YYYY-MM-DD simuliert ein Datum."""
    return seasons.specials(on or date.today(), member.household.plz)


# --- Frühstück & Snacks: Wochen-Basics (23a) ---

def member_weekly(db: Session, member: Member, basic_id: int) -> WeeklyBasic:
    b = db.get(WeeklyBasic, basic_id)
    if b is None or b.household_id != member.household_id:
        raise HTTPException(404, "Basic nicht gefunden")
    return b


@router.get("/weekly-basics", response_model=list[WeeklyBasicOut])
def list_weekly_basics(member: Member = Depends(current_member), db: Session = Depends(get_db)):
    return weekly_basics(db, member.household_id)


@router.post("/weekly-basics", response_model=WeeklyBasicOut, status_code=201)
def create_weekly_basic(body: WeeklyBasicIn, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    b = WeeklyBasic(household_id=member.household_id, **body.model_dump())
    db.add(b)
    db.commit()
    return b


@router.patch("/weekly-basics/{basic_id}", response_model=WeeklyBasicOut)
def patch_weekly_basic(basic_id: int, body: WeeklyBasicUpdate, member: Member = Depends(current_member),
                       db: Session = Depends(get_db)):
    b = member_weekly(db, member, basic_id)
    for key, value in body.model_dump(exclude_unset=True).items():
        if value is not None or key == "amount":  # Menge darf null werden (ohne Menge)
            setattr(b, key, value)
    db.commit()
    return b


@router.delete("/weekly-basics/{basic_id}", status_code=204)
def delete_weekly_basic(basic_id: int, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    db.delete(member_weekly(db, member, basic_id))
    db.commit()
    return Response(status_code=204)


def apply_weekly_basics(db: Session, household: Household) -> ShoppingList:
    """Wochen-Basics auf die Haushaltsliste (Quelle basics): Vorrat wird abgezogen, günstigstes passendes Angebot
    der eigenen Läden setzt Laden + Preis (offer_id). Offene Basics-Einträge werden aktualisiert, nicht verdoppelt."""
    lst = household_list(db, household.id)
    stock = Stock(household_pantry(db, household.id))
    matcher = Matcher(household_offers(db, household))
    open_items = {ingredient_key(i.name): i for i in lst.items if i.source == "basics" and not i.checked}
    for b in weekly_basics(db, household.id):
        need = b.amount
        if need:
            need -= min(stock.take(b.name, b.unit, need), need)
            if need <= 0:
                continue
        elif stock.take(b.name, b.unit, 1) >= 1:
            continue
        offers = matcher.find(b.name)  # günstigster Grundpreis zuerst
        item = open_items.get(ingredient_key(b.name))
        if item is None:
            item = ShoppingItem(source="basics", added_by="Frühstück & Snacks")
            lst.items.append(item)
        item.name, item.amount, item.unit = b.name, round(need, 1) if need else None, b.unit
        item.offer_id, item.chain = (offers[0].id, offers[0].chain) if offers else (None, "")
    db.flush()
    return lst


@router.post("/weekly-basics/to-list", response_model=ListOut)
def weekly_basics_to_list(request: Request, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Sofort auf die Liste (sonst montags 06:30 automatisch, Job weekly_basics)."""
    lst = apply_weekly_basics(db, member.household)
    db.commit()
    return list_out(request, lst)


# --- Ersatzzutaten (7) ---

def recipe_ingredient(recipe: Recipe, index: int) -> dict:
    if not 0 <= index < len(recipe.ingredients):
        raise HTTPException(404, "Zutat nicht gefunden")
    return recipe.ingredients[index]


@router.get("/recipes/{recipe_id}/ingredients/{index}/substitutes", response_model=SubstitutesOut)
def get_substitutes(recipe_id: int, index: int, member: Member = Depends(current_member),
                    db: Session = Depends(get_db)):
    """„Ersatz finden“: 2–4 Alternativen mit umgerechneter Menge und Wirkung, markiert im Vorrat / im Angebot.
    Erst Tabelle (ohne KI), sonst Haiku; Allergien und Ernährungsform des Haushalts + aller Profile prüft der Code."""
    recipe = household_recipe(db, member, recipe_id)
    ing = recipe_ingredient(recipe, index)
    prefs = _prefs(member.household, {})
    try:
        source, options, usage = substitutes.suggest(
            ing["name"], ing.get("amount") or 0, ing.get("unit") or "g", recipe.title,
            [i["name"] for i in recipe.ingredients if i is not ing], prefs.allergies, prefs.diet,
            prefs.excluded_ingredients)
    except RuntimeError as e:
        raise HTTPException(502, str(e))
    if usage:
        planner.log_cost(db, member.household_id, "substitute", usage["cost_cents"], usage["model"], ing["name"])
        db.commit()
    pantry = household_pantry(db, member.household_id)
    stock, matcher = Stock(pantry), Matcher(household_offers(db, member.household))

    def mark(i: dict) -> dict:
        key = ingredient_key(i["name"])
        hit = (matcher.find(i["name"]) or [None])[0]
        return i | {"in_pantry": bool(stock.basic(i["name"])) or any(
                        p.ingredient_key == key and p.amount != 0 for p in pantry if not p.is_basic),
                    "offer": {"id": hit.id, "chain": hit.chain, "price_cents": hit.price_cents} if hit else None}
    return {"ingredient": {k: ing.get(k) for k in ("name", "amount", "unit")}, "source": source,
            "options": [{"note": o["note"], "ingredients": [mark(i) for i in o["ingredients"]]} for o in options]}


@router.post("/recipes/{recipe_id}/ingredients/{index}/substitute", response_model=RecipeDetail)
def apply_substitute(recipe_id: int, index: int, body: SubstituteIn, member: Member = Depends(current_member),
                     db: Session = Depends(get_db)):
    """Ersetzt die Zutat in diesem Rezept (globale Rezepte: Kopie für den Haushalt, aktueller Plan zeigt auf die
    Kopie). Neue Zeilen tragen "replaces": <alte Zutat>. Steht das Rezept im aktuellen Plan: Kosten + Liste neu."""
    recipe = household_recipe(db, member, recipe_id)
    old = recipe_ingredient(recipe, index)
    plan = db.scalar(select(MealPlan).where(MealPlan.household_id == member.household_id)
                     .order_by(MealPlan.id.desc()).limit(1))
    if recipe.household_id is None:
        copy = Recipe(**{c.key: getattr(recipe, c.key) for c in Recipe.__table__.columns
                         if c.key not in ("id", "created_at", "household_id")}, household_id=member.household_id)
        db.add(copy)
        for e in plan.entries if plan else []:
            if e.recipe_id == recipe.id:
                e.recipe = copy
        recipe = copy
    rows = [ingredient_row(i.model_dump()) | {"replaces": old["name"]} for i in body.ingredients]
    recipe.ingredients = [*recipe.ingredients[:index], *rows, *recipe.ingredients[index + 1:]]
    db.flush()
    if plan and any(e.recipe_id == recipe.id for e in plan.entries):
        reprice(db, plan, household_offers(db, member.household), household_pantry(db, member.household_id))
        sync_plan(db, member.household_id)
    db.commit()
    food_map.map_later([r["name"] for r in rows])
    return recipe_detail(db, member, recipe)
