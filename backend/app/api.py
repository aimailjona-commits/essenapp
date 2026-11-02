import secrets
from datetime import date, datetime, timedelta
from types import SimpleNamespace

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response
from sqlalchemy import or_, select
from sqlalchemy.orm import Session

from app.core.auth import current_member, new_token
from app.core.db import get_db
from app.models import (Household, HouseholdStore, Invite, MealPlan, MealPlanEntry, Member, Offer, Recipe, ShoppingItem,
                        ShoppingList)
from app.schemas import (EntryUpdate, HouseholdCreate, HouseholdCreated, HouseholdOut, HouseholdSettings, InviteOut,
                         ItemCreate, ItemOut, ItemUpdate, JoinIn, ListCreate, ListOut, ListSummary, MemberOut,
                         NearbyStoreOut, OfferOut, PlanOptions, PlanOut, ShareOut, UsageOut)
from app.services import nearby_stores, offers_import, planner, recipe_images

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
        plan.entries.append(MealPlanEntry(day=meal.day, meal_type=meal.meal_type, recipe=_recipe(household, meal, image),
                                          cost_cents=cost))
    db.add(plan)
    db.flush()
    sync_plan(db, household.id)
    db.commit()
    return plan


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
    entry.recipe = _recipe(household, meal, recipe_images.find_image(meal.image_query or meal.title))
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
    sync_plan(db, household.id)
    db.commit()
    return plan


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

    needed: dict[tuple, dict] = {}
    for entry in plan.entries if plan else []:
        for ing in entry.recipe.ingredients:
            if ing.get("in_pantry"):
                continue
            unit, offer_id = ing.get("unit", ""), ing.get("offer_id")
            row = needed.setdefault(key_of(ing["name"], unit, offer_id),
                                    {"name": ing["name"][:100], "amount": 0.0, "unit": unit, "offer_id": offer_id})
            row["amount"] += ing.get("amount") or 0
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


@router.patch("/items/{item_id}", response_model=ItemOut)
def patch_item(item_id: int, body: ItemUpdate, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    return update_item(db, member_item(db, member, item_id), body, member.name)


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
