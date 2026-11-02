import base64
import secrets
import time
from datetime import date, datetime, timedelta
from pathlib import Path
from types import SimpleNamespace

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response
from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.core.auth import current_member, new_token
from app.core.db import get_db
from app.models import (Household, HouseholdStore, Invite, MealPlan, MealPlanEntry, Member, MemberProfile, Offer,
                        PantryItem, PricePoint, PushDevice, Rating, Recipe, RecipeFavorite, ShoppingItem,
                        ShoppingList)
from app.schemas import (ConsumeIn, DeviceIn, EntryUpdate, FavoriteOut, HouseholdCreate, HouseholdCreated,
                         HouseholdOut, HouseholdSettings, InviteOut, ItemCreate, ItemOut, ItemPatchOut, ItemUpdate, JoinIn,
                         ListCreate, ListOut, ListSummary, MemberOut, MemberProfileOut, NearbyStoreOut,
                         OfferHistoryOut, OfferOut, PantryIn, PantryOut, PantryUpdate, PlanNutritionOut, PlanOptions,
                         PlanOut, ProfileOut, ProfileUpdate, PushSettings, PushSettingsUpdate, RatingIn,
                         RatingOut, RecipeCard, RecipeCostOut, RecipeDetail, RecipeIn, RecipePatch, ReplaceIn,
                         ShareOut, UsageOut)
from app.services import (food_map, nearby_stores, nutrition, offers_import, planner, prices, push, recipe_images,
                          recipes)
from app.services.normalize import base_unit, cents, ingredient_key
from app.services.pricing import Stock

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


def _eaters(household: Household, persons: int, slots: list[tuple[int, str]]) -> dict:
    """Esser je Slot; ab zwei Mitgliedern mit mindestens einem Profil zählen die Profile (fehlende = Vorschlag)."""
    members = household.members
    if len(members) > 1 and any(m.profile for m in members):
        profiles = [m.profile or new_profile(m) for m in members]
    else:
        profiles = [m.profile for m in members if m.profile]
    return planner.slot_eaters(profiles, persons, slots)


@router.post("/plans", response_model=PlanOut, status_code=201)
def create_plan(options: PlanOptions | None = None, member: Member = Depends(current_member),
                db: Session = Depends(get_db)):
    """Optionaler Body PlanOptions gilt nur für diesen Plan; save_as_default schreibt ihn (ohne wishes) in den Haushalt."""
    household = member.household
    opts = options.model_dump(exclude_none=True, exclude={"save_as_default"}) if options else {}
    prefs = _prefs(household, opts)
    eaters = _eaters(household, prefs.persons, planner.week_slots(prefs))
    slots = [slot for slot, (_, total) in eaters.items() if total > 0]  # niemand isst mit → Slot entfällt
    if not slots:
        raise HTTPException(422, "Keine Mahlzeiten oder Tage eingestellt")
    memory = recipes.planner_memory(db, household.id)
    try:
        priced = planner.make_plan(prefs, household_offers(db, household), slots, favorites=memory["favorites"],
                                   wishes=opts.get("wishes", ""), portions={s: eaters[s][1] for s in slots},
                                   pantry=household_pantry(db, household.id), never=memory["never"],
                                   recent=memory["recent"])
    except RuntimeError as e:
        raise HTTPException(502, str(e))
    planner.add_images(priced)  # erst freie Fotos, dann KI (E13/E41)
    if options and options.save_as_default:
        for key, value in opts.items():
            if key != "wishes":
                setattr(household, key, value)
    year, week, _ = date.today().isocalendar()
    plan = MealPlan(household_id=household.id, week=f"{year}-W{week:02d}", total_cents=priced.total_cents,
                    saved_cents=priced.saved_cents,
                    params={"budget": prefs.budget_food_week_cents, "options": opts, "usage": priced.usage})
    for meal, cost, image in zip(priced.draft.meals, priced.meal_costs, priced.images):
        portions, total = eaters[(meal.day, meal.meal_type)]
        plan.entries.append(MealPlanEntry(day=meal.day, meal_type=meal.meal_type, recipe=_recipe(household, meal, image),
                                          cost_cents=cost, portions=portions, portions_total=total))
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
    return {"plans": len(costs), "cost_cents_total": round(sum(costs), 4), "cost_cents_last": costs[-1] if costs else 0}


def _recipe(household: Household, meal: planner.PlannedMeal, image: str = "") -> Recipe:
    return Recipe(household_id=household.id, title=meal.title, description=meal.description, cuisine=meal.cuisine,
                  meal_type=meal.meal_type, servings=meal.servings, prep_minutes=meal.prep_minutes,
                  ingredients=[i.model_dump() for i in meal.ingredients], steps=meal.steps, image_url=image[:500])


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
    if not total:
        raise HTTPException(422, "Bei dieser Mahlzeit isst niemand mit")
    memory = recipes.planner_memory(db, household.id)
    try:
        meal, call_usage = planner.reroll_meal(prefs, offers, slot, [entry.recipe.title, *others],
                                               wishes=opts.get("wishes", ""), portions={slot: total}, pantry=pantry,
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
    ) for e in plan.entries])
    priced = planner.price(draft, {o.id: o for o in offers}, pantry)
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
    stock = Stock(household_pantry(db, household_id))  # nur fehlende Mengen auf die Liste (60)
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


# Begriffe für haltbare Sachen: Wortanfang oder -ende ("Basmatireis", "Dosentomaten")
PANTRY_WORDS = ("reis", "nudel", "pasta", "spaghetti", "mehl", "zucker", "salz", "öl", "essig", "linsen", "bohnen",
                "kichererbsen", "dose", "konserve", "brühe", "gewürz", "pfeffer", "haferflocken", "kaffee", "honig",
                "senf", "ketchup", "tomatenmark", "passierte", "couscous", "bulgur", "quinoa", "müsli")


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
    key = ingredient_key(item.name)
    pantry = next((p for p in household_pantry(db, member.household_id)
                   if p.ingredient_key == key and (p.is_basic or p.unit == unit)), None)
    if pantry is None:
        pantry = PantryItem(household_id=member.household_id, name=item.name, ingredient_key=key, amount=amount,
                            unit=unit, source="list")
        db.add(pantry)
    elif pantry.is_basic or amount is None or pantry.amount is None:
        pantry.amount = None  # Basic wieder voll bzw. Menge unbekannt
    else:
        pantry.amount += amount
    db.commit()
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
    for key in ("name", "unit", "is_basic"):  # nicht null-bar; amount/best_before dürfen null werden
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


@router.get("/recipes/{recipe_id}", response_model=RecipeDetail)
def get_recipe(recipe_id: int, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    return recipe_detail(db, member, household_recipe(db, member, recipe_id))


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


def plan_out(db: Session, plan: MealPlan) -> dict:
    """Plan mit Favorit, Nährwerten und Blüten-Daten pro Gericht (pro Portion; null, solange Zuordnung läuft)."""
    out = PlanOut.model_validate(plan).model_dump()
    maps = food_map.load(db, [i["name"] for e in plan.entries for i in e.recipe.ingredients])
    favs = recipes.favorite_ids(db, plan.household_id)
    for meal, e in zip(out["entries"], plan.entries):
        nut, comp = nutrition.dish(e.recipe.ingredients, maps, e.portions_total or e.recipe.servings, e.scale or 1)
        meal["recipe"] |= {"favorite": e.recipe.id in favs, "nutrition": nut, "composition": comp}
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
        if value is not None or key == "quiet_hours":  # nur die Ruhezeit darf null werden
            setattr(member, key, value)
    db.commit()
    return member
