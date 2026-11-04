import base64
import logging
import secrets
import shutil
import threading
import time
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor, wait
from datetime import UTC, date, datetime, timedelta
from pathlib import Path
from types import SimpleNamespace

import httpx
from fastapi import APIRouter, Body, Depends, File, Form, HTTPException, Query, Request, Response, UploadFile
from fastapi import Path as Path_
from fastapi.encoders import jsonable_encoder
from sqlalchemy import or_, select
from sqlalchemy.orm import Session, object_session

from app.core.auth import current_member, new_token
from app.core.config import settings
from app.core.db import get_db
from app.models import (Achievement, AdReward, AiCost, BonusEntry, Coupon, Household, HouseholdStore, Invite, MealPlan,
                        JobRun, MealPlanEntry, Member, MemberProfile, MemberToken, Offer, PairingCode, PantryItem, PricePoint,
                        Product, PushDevice, Rating, Recipe, RecipeFavorite, ShoppingItem, ShoppingList, WatchItem,
                        WeekReview, WeeklyBasic)
from app.schemas import (ConsumeIn, CookIdeaOut, DeviceIn, EntryUpdate, FavoriteOut, HouseholdCreate,
                         HouseholdCreated, HouseholdOut, HouseholdSettings, ImportIn, InviteOut, ItemCreate, ItemOut,
                         ItemPatchOut, ItemUpdate, JoinIn, ListCreate, ListOut, ListSummary, MemberOut,
                         MemberProfileOut, NearbyStoreOut, OfferHistoryOut, OfferNutritionOut, OfferOut,
                         PairedTokenOut, PairIn, PairingCodeOut, PairOut, PantryIn, PantryOut, PantryUpdate,
                         PlanJobOut, PlanNutritionOut, ProOut, AppleIn, PlanOptions, PlanOut, ProfileOut, ProfileUpdate, PushSettings,
                         PushSettingsUpdate, RatingIn, RatingOut, RecipeCard, RecipeCostOut, RecipeDetail, RecipeIn,
                         RecipeOut, RecipePatch, ReplaceIn, ScanOut, ShareOut, StepImagesOut, UsageOut,
                         EntryLeftover, GeneratorOut, GuestsIn, NoMoodIn, PostponeIn, SpecialsOut, SubstituteIn,
                         SubstitutesOut, WeeklyBasicIn, WeeklyBasicOut, WeeklyBasicUpdate, AddEntryIn, AssignIn,
                         BudgetIdeaOut, BudgetOut, EanProductOut, NextWeekDealOut, NextWeekIn, RerollIn,
                         StockupOut, StoreComboOut, WatchIn, WatchOut, WatchUpdate, AchievementOut, BonusAccountOut,
                         BonusIn, CouponIn, CouponOut, CouponScanOut, CouponUpdate, RecipeShareOut, ReviewSummary,
                         SeenIn, SharedRecipeOut, SpendingOut, WeekReviewOut)
from app.services import (bonus, food_map, pro, labels, motivation, nearby_stores, nutrition, offers_import, pantry_ai,
                          planner, prices, push, recipe_images, recipe_import, recipes, seasons, spending, stockup,
                          store_split, substitutes, variety, watch)
from app.services.matching import Matcher
from app.services.normalize import base_unit, cents, ingredient_key
from app.services.pricing import PANTRY_WORDS, Stock, pack_amount, stock_key

router = APIRouter()
log = logging.getLogger(__name__)


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


def _store_filter(household: Household, chain: str | None):
    stores = {(s.chain, s.store_ref) for s in household.stores if s.enabled and (chain is None or s.chain == chain)}
    return or_(*[(Offer.chain == c) & (Offer.store_ref == ref) for c, ref in stores]) if stores else None


def household_offers(db: Session, household: Household, chain: str | None = None, on: date | None = None) -> list[Offer]:
    """Am Stichtag (Standard heute) gültige Angebote der eingestellten Läden/Filialen."""
    stores, day = _store_filter(household, chain), on or date.today()
    if stores is None:
        return []
    return list(db.scalars(select(Offer).where(stores, Offer.valid_from <= day, Offer.valid_to >= day)
                           .order_by(Offer.category, Offer.title)))


def next_monday(today: date | None = None) -> date:
    today = today or date.today()
    return today + timedelta(days=7 - today.weekday())


def next_week_offers(db: Session, household: Household, chain: str | None = None) -> list[Offer]:
    """Vorschau (30): Angebote, deren Gültigkeit in der nächsten Woche beginnt (kaufDA listet sie meist ab Do/Fr/Sa)."""
    stores, monday = _store_filter(household, chain), next_monday()
    if stores is None:
        return []
    return list(db.scalars(select(Offer).where(stores, Offer.valid_from >= monday,
                                               Offer.valid_from <= monday + timedelta(days=6))
                           .order_by(Offer.category, Offer.title)))


DRUGSTORES = ("dm", "rossmann")


def is_monthly(o: Offer) -> bool:
    """dm/Rossmann-Monatsaktion (59): gilt bis Monatsende bzw. mindestens 3 Wochen."""
    return o.chain in DRUGSTORES and ((o.valid_to + timedelta(days=1)).day == 1 or (o.valid_to - o.valid_from).days >= 20)


def offer_rows(db: Session, offers: list[Offer]) -> list[dict]:
    """OfferOut mit Urteil (28), Bio/Vegan/Nutri-Score (49) und Monatsaktion (59) – je eine Abfrage für Preispunkte
    und Produkte, keine N+1."""
    verdicts = prices.verdicts(db, offers)
    ids = {o.product_id for o in offers if o.product_id}
    products = {p.id: p for p in db.scalars(select(Product).where(Product.id.in_(ids)))} if ids else {}
    return [OfferOut.model_validate(o).model_dump() | labels.flags(o, products.get(o.product_id))
            | {"verdict": verdicts[o.id]["verdict"], "monthly": is_monthly(o)} for o in offers]


@router.get("/offers", response_model=list[OfferOut])
def list_offers(chain: str | None = None, category: str | None = None, q: str | None = None,
                week: str = Query("this", pattern="^(this|next)$"), real: bool = False, bio: bool = False,
                vegan: bool = False, nutri_ab: bool = False, monthly: bool = False, bonus: bool = False,
                member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Angebote dieser Woche (heute gültig) bzw. week=next: Vorschau der nächsten Woche (30). Filter: real = „Nur echte
    Angebote“ (Urteil nicht kein_echtes, 28), bio/vegan/nutri_ab (Nutri-Score A/B, 49), monthly = dm/Rossmann-
    Monatsaktionen (59), bonus = Rewe-Bonus-Aktionen (39)."""
    offers = (next_week_offers if week == "next" else household_offers)(db, member.household, chain)
    offers = [o for o in offers if (not category or o.category == category) and (not q or q.lower() in o.title.lower())
              and (not monthly or is_monthly(o)) and (not bonus or o.bonus_cents)]
    rows = offer_rows(db, offers)
    db.commit()  # Preispunkte für Angebote ohne Produkt (vor dem Preisverlauf importiert)
    return [r for r in rows if (not real or r["verdict"] != "kein_echtes") and (not bio or r["bio"])
            and (not vegan or r["vegan"]) and (not nutri_ab or r["nutri_score"] in ("A", "B"))]


def _same_pack_price(now: Offer, nxt: Offer, regular: bool = False) -> int:
    """Heutiger Preis umgerechnet auf die Packung des Vorschau-Angebots (Grundpreis, wenn beide einen haben)."""
    price = (now.regular_price_cents or now.price_cents) if regular else now.price_cents
    if now.base_price_cents and nxt.amount and now.unit == nxt.unit and now.amount and now.amount != nxt.amount:
        return cents(price * nxt.amount / now.amount)
    return price


@router.get("/offers/next-week-cheaper", response_model=list[NextWeekDealOut])
def next_week_cheaper(member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Start-Karte „👀 Nächste Woche günstiger“ (30): offene Listenartikel (inkl. Plan) und Merkliste, die nächste Woche
    mindestens 10 % günstiger werden. Vergleich: heutiges Angebot, sonst Normalpreis (Streichpreis bzw. Historie)."""
    h = member.household
    nxt = next_week_offers(db, h)
    if not nxt:
        return []
    now_offers = household_offers(db, h)
    m_next, m_now = Matcher(nxt, False), Matcher(now_offers, False)
    m_hist = Matcher(recipes.history_offers(db), False)
    wants = [(i.name, i.id, None) for i in household_list(db, h.id).items
             if not i.checked and not ItemOut.model_validate(i).next_week]
    watches = list(db.scalars(select(WatchItem).where(WatchItem.household_id == h.id, WatchItem.kind == "produkt")))
    deals, seen = [], set()
    for name, item_id, w in [*wants, *[(w.label, None, w) for w in watches]]:
        cands = watch.matches(w, nxt) if w else m_next.find(name)
        if not cands or name.lower() in seen:
            continue
        o = min(cands, key=lambda c: c.price_cents)
        now = (watch.matches(w, now_offers) if w else m_now.find(name))
        if now:
            ref, chain = min(_same_pack_price(n, o) for n in now), min(now, key=lambda n: _same_pack_price(n, o)).chain
        elif o.regular_price_cents:
            ref, chain = o.regular_price_cents, ""
        elif hist := m_hist.find(name):
            ref, chain = min(_same_pack_price(n, o, regular=True) for n in hist), ""
        else:
            continue
        pct = round(100 * (1 - o.price_cents / ref)) if ref else 0
        if pct >= 10:
            seen.add(name.lower())
            deals.append({"name": name, "item_id": item_id, "watch_id": w.id if w else None, "offer": o,
                          "now_price_cents": ref, "now_chain": chain, "saving_pct": pct})
    rows = {r["id"]: r for r in offer_rows(db, [d["offer"] for d in deals])}
    db.commit()
    return sorted(({**d, "offer": rows[d["offer"].id]} for d in deals), key=lambda d: -d["saving_pct"])


def stockup_tips(db: Session, household: Household, offers: list[Offer]) -> list[dict]:
    """Vorratskauf-Tipps (31) für diese Angebote, größte Ersparnis zuerst, je Titel einer."""
    cands = [o for o in offers if stockup.durable(o)]
    verdicts = prices.verdicts(db, cands)
    usage, tips, seen = None, [], set()
    for o in cands:
        if o.title.lower() in seen or stockup.tip(o, verdicts[o.id], None) is None:
            continue
        usage = usage or stockup.load_usage(db, household.id)
        seen.add(o.title.lower())
        tips.append(stockup.tip(o, verdicts[o.id], stockup.weekly_use(usage, o), household.storage_space))
    rows = {r["id"]: r for r in offer_rows(db, [t["offer"] for t in tips])}
    db.commit()
    return sorted(({**t, "offer": rows[t["offer"].id]} for t in tips), key=lambda t: -t["saving_cents"])


@router.get("/stockup", response_model=list[StockupOut])
def list_stockup(limit: int = Query(3, ge=1, le=50), member: Member = Depends(current_member),
                 db: Session = Depends(get_db)):
    """Start-Karte „💡 Vorrat anlegen lohnt sich“ (31, max. 3)."""
    return stockup_tips(db, member.household, household_offers(db, member.household))[:limit]


@router.get("/offers/{offer_id}/stockup", response_model=StockupOut | None)
def offer_stockup(offer_id: int, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Angebotsdetail „Vorratstipp: 3 Packungen reichen ~6 Wochen, sparst 4,20 €“; null = kein Tipp."""
    offer = db.get(Offer, offer_id)
    if offer is None:
        raise HTTPException(404, "Angebot nicht gefunden")
    return next(iter(stockup_tips(db, member.household, [offer])), None)


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


def forbid_of(prefs) -> Callable[[str], bool]:
    """Harte Regel nach der KI (19.2): Zutat verletzt Allergie, Ernährungsform oder „Mag nicht“."""
    return lambda name: substitutes.forbidden(name, prefs.allergies, prefs.diet, prefs.excluded_ingredients)


def _profiles(household: Household) -> list[MemberProfile]:
    """Ab zwei Mitgliedern mit mindestens einem Profil zählen die Profile (fehlende = Vorschlag)."""
    members = household.members
    if len(members) > 1 and any(m.profile for m in members):
        return [m.profile or new_profile(m) for m in members]
    return [m.profile for m in members if m.profile]


def _eaters(household: Household, persons: int, slots: list[tuple[int, str]]) -> dict:
    """Esser je Slot (48), Lunchbox nur für Mitglieder mit diesem Lunchbox-Tag (24)."""
    return planner.slot_eaters(_profiles(household), persons, slots)


PLAN_ONLY = ("wishes", "guests", "guest_budget_cents", "special", "next_week", "single_store")  # nie Haushalts-Standard


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


def plan_extra(db: Session, household: Household, prefs, slots: list[tuple[int, str]], hint: str = "",
               offers: list[Offer] = (), days: int | None = None) -> list[str]:
    """Kompakte Zusatzzeilen für den variablen Prompt-Teil: Abwechslung (12, Mindestregeln anteilig zu den Plan-Tagen),
    Saison/Feiertage (25), Frühstücks-Basics und Snack-Ziel (23), Nutri-Score A/B (49), Special-Hinweis (25)."""
    days = days or len({d for d, m in slots if m in variety.MAIN}) or 7
    lines = [variety.rules_line(variety.rules_of(household.variety), fish_ok(prefs), days),
             *seasons.prompt_lines(date.today(), household.plz)]
    picked = planner.select_offers(list(offers))
    ids = {o.product_id for o in picked if o.product_id}
    good = set(db.scalars(select(Product.id).where(Product.id.in_(ids), Product.nutri_score.in_(("a", "b"))))) if ids else set()
    if deals := list(dict.fromkeys(f"{o.title} ({o.badge})" for o in picked if getattr(o, "badge", "")))[:25]:
        lines.append("Coupon/Bonus (Effektivpreis schon eingerechnet, Gerichte damit bevorzugen): " + ", ".join(deals))
    if names := list(dict.fromkeys(o.title for o in picked if o.product_id in good))[:25]:
        lines.append(f"Nutri-Score A/B (bei Ziel „{prefs.nutrition_goal}“ bei ähnlichem Preis bevorzugen): "
                     + ", ".join(names))
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
    started = time.monotonic()
    household = member.household
    opts = options.model_dump(exclude_none=True, exclude={"save_as_default"}) if options else {}
    if not opts.get("next_week"):
        opts.pop("next_week", None)
    prefs = _prefs(household, opts)
    extra_slots, hint = [], ""
    pro.require(db, household, "plan")
    if (single := opts.get("single_store")) and single not in {s.chain for s in household.stores if s.enabled}:
        raise HTTPException(422, "Laden ist nicht ausgewählt")
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
    monday = next_monday() if opts.get("next_week") else None
    offers = effective_offers(db, household, household_offers(db, household, single, monday))
    if single:
        name = watch.CHAIN_NAMES.get(single, single)
        hint = (hint + "\n" if hint else "") + (f"Einkauf komplett bei {name}: nur dessen Angebote; Zutaten ohne "
                                                 f"Angebot zum Normalpreis von {name} schätzen.")
    try:
        priced = planner.make_plan(prefs, offers, slots, favorites=memory["favorites"],
                                   wishes=opts.get("wishes", ""), portions=portions,
                                   pantry=household_pantry(db, household.id), never=memory["never"],
                                   recent=memory["recent"], rules=rules, fish_ok=fish_ok(prefs),
                                   extra=plan_extra(db, household, prefs, slots, hint, offers), guests=guests,
                                   stock=plan_stock(db, household.id), forbid=forbid_of(prefs))
    except RuntimeError as e:
        raise HTTPException(502, str(e))
    planner.add_images(priced)  # erst freie Fotos, dann KI (E13/E41)
    if options and options.save_as_default:
        for key, value in opts.items():
            if key not in PLAN_ONLY:
                setattr(household, key, value)
    plan = MealPlan(household_id=household.id, week=prices.iso_week(monday or date.today()), total_cents=priced.total_cents,
                    saved_cents=priced.saved_cents,
                    params={"budget": prefs.budget_food_week_cents, "options": opts, "usage": priced.usage,
                            "rests": priced.rests, "seconds": round(time.monotonic() - started)})  # 19.6: Dauer messen
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


PLAN_JOB_MINUTES = 10  # länger läuft kein Plan (KI-Timeout 300 s + Reparatur); älter und ohne Ergebnis = abgestürzt


def plan_job_row(db: Session, household_id: int) -> JobRun | None:
    return db.scalar(select(JobRun).where(JobRun.name == f"plan:{household_id}").order_by(JobRun.id.desc()).limit(1))


def plan_job_state(row: JobRun | None) -> dict:
    if row is None:
        return {"state": "none", "error": ""}
    if row.ok:
        return {"state": "done", "error": ""}
    if row.info != "läuft":
        return {"state": "error", "error": row.info}
    if row.ran_at > datetime.now(UTC).replace(tzinfo=None) - timedelta(minutes=PLAN_JOB_MINUTES):
        return {"state": "running", "error": ""}
    return {"state": "error", "error": "Abgebrochen, bitte erneut versuchen"}


def run_later(target: Callable, *args) -> None:
    threading.Thread(target=target, args=args, name="plan_job", daemon=True).start()


@router.post("/plans/job", response_model=PlanJobOut, status_code=202)
def start_plan_job(options: PlanOptions | None = None, member: Member = Depends(current_member),
                   db: Session = Depends(get_db)):
    """19.6: Plan im Hintergrund erstellen (wie POST /plans, dauert bis ~2 min). Stand über GET /plans/job, bei
    „done“ GET /plans/current. Läuft schon einer für den Haushalt, wird kein zweiter gestartet. Der Stand liegt in
    job_run, damit jeder uvicorn-Worker ihn kennt."""
    row = plan_job_row(db, member.household_id)
    if plan_job_state(row)["state"] == "running":
        return plan_job_state(row)
    pro.require(db, member.household, "plan", spend=False)  # 402 sofort; abgebucht wird im Lauf
    row = JobRun(name=f"plan:{member.household_id}", ran_at=datetime.now(UTC).replace(tzinfo=None), info="läuft")
    db.add(row)
    db.commit()
    run_later(_plan_job, db.get_bind(), row.id, member.id, options)
    return plan_job_state(row)


def _plan_job(bind, row_id: int, member_id: int, options: PlanOptions | None) -> None:
    with Session(bind) as db:
        try:
            create_plan(options, db.get(Member, member_id), db)
            ok, info = True, "fertig"
        except HTTPException as e:
            db.rollback()
            ok, info = False, str(e.detail)
        except Exception:
            db.rollback()
            log.exception("Plan im Hintergrund fehlgeschlagen")
            ok, info = False, "Plan konnte nicht erstellt werden, bitte erneut versuchen"
        row = db.get(JobRun, row_id)
        row.ok, row.info = ok, info[:500]
        db.commit()


def _fill_image(bind, recipe_id: int, query: str) -> None:
    """Foto nach der Antwort suchen (19.6): das neue Gericht erscheint sofort, das Bild beim nächsten Laden."""
    image = recipe_images.find_image(query)
    with Session(bind) as db:
        if image and (recipe := db.get(Recipe, recipe_id)):
            recipe.image_url = image[:500]
            db.commit()


@router.get("/plans/job", response_model=PlanJobOut)
def plan_job(member: Member = Depends(current_member), db: Session = Depends(get_db)):
    return plan_job_state(plan_job_row(db, member.household_id))


def pro_out(db: Session, h: Household) -> dict:
    return {"paywall": settings.paywall, "pro": pro.is_pro(h), "until": h.pro_until, "trial_until": h.pro_trial_until,
            "ad_credits": h.ad_credits, "free_plans_left": pro.free_plans_left(db, h), "price": pro.PRICE,
            "features": pro.FEATURES}


@router.get("/pro", response_model=ProOut)
def get_pro(member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Pro-Stand (19.8); ein abgelaufenes Abo wird höchstens alle 6 h bei Apple nachgesehen (Verlängerung)."""
    pro.refresh(member.household)
    db.commit()
    return pro_out(db, member.household)


@router.post("/pro/apple", response_model=ProOut)
def pro_apple(body: AppleIn, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Kauf/Wiederherstellen in der App: originalTransactionId → Server fragt Apple und schaltet den ganzen Haushalt
    frei (R11). Dieselbe Transaktion gehört nur zu einem Haushalt."""
    if not pro.apple_configured():
        raise HTTPException(503, "Abo-Prüfung nicht eingerichtet")
    other = db.scalar(select(Household).where(Household.apple_transaction_id == body.original_transaction_id,
                                              Household.id != member.household_id))
    if other is not None:
        raise HTTPException(409, "Dieses Abo gehört schon zu einem anderen Haushalt")
    try:
        status = pro.apple_status(body.original_transaction_id)
    except httpx.HTTPError as e:
        raise HTTPException(502, f"App Store nicht erreichbar: {e}")
    if status is None:
        raise HTTPException(404, "Kein Abo gefunden")
    member.household.apple_transaction_id = body.original_transaction_id
    pro.apply(member.household, status)
    db.commit()
    return pro_out(db, member.household)


@router.get("/pro/admob", status_code=200)
def pro_admob(request: Request, db: Session = Depends(get_db)):
    """AdMob-Prämie (Server-Prüfung, kein Login): Google ruft das nach einem ganz angesehenen Video auf; user_id =
    Haushalt. Gültige Signatur → eine Pro-Nutzung gutschreiben, jede transaction_id nur einmal."""
    params = pro.admob_verified(request.url.query)
    if params is None:
        raise HTTPException(403, "Signatur ungültig")
    household = db.get(Household, int(params["user_id"])) if params.get("user_id", "").isdigit() else None
    if household is None:
        return {"ok": True}  # Testaufruf aus der AdMob-Konsole hat keinen Haushalt
    if db.scalar(select(AdReward).where(AdReward.transaction_id == params.get("transaction_id", ""))) is None:
        db.add(AdReward(household_id=household.id, transaction_id=params.get("transaction_id", "")[:100]))
        household.ad_credits += 1
        db.commit()
    return {"ok": True}


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
    plan = db.scalar(select(MealPlan).where(MealPlan.household_id == household_id).order_by(MealPlan.active_at.desc(), MealPlan.id.desc()).limit(1))
    if not plan:
        raise HTTPException(404, "Noch kein Wochenplan")
    return plan


def plan_offers(db: Session, household: Household, plan: MealPlan | None) -> list[Offer]:
    """Angebote, mit denen ein Plan rechnet: nur der Laden im Ein-Laden-Modus (41), Stichtag Montag beim Plan für
    nächste Woche (30)."""
    opts = ((plan.params or {}).get("options") or {}) if plan else {}
    return effective_offers(db, household, household_offers(db, household, opts.get("single_store"),
                                                            plan_monday(plan) if opts.get("next_week") else None))


def effective_offers(db: Session, household: Household, offers: list[Offer]) -> list[Offer]:
    """Effektivpreise (38c/39): Rewe-Bonus und aktive Coupons wirken für Planner/Pricing wie Rabatt."""
    return bonus.apply(offers, bonus.active(db, household.id))


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
def reroll_entry(entry_id: int, body: RerollIn | None = None, member: Member = Depends(current_member),
                 db: Session = Depends(get_db)):
    """Ersetzt ein Gericht durch ein neues der KI und rechnet die Kosten des ganzen Plans neu. max_cost_cents (43):
    „günstigere Alternative“ mit Kostengrenze."""
    household, plan = member.household, _current(db, member.household_id)
    entry = _entry(plan, entry_id)
    if entry.locked:
        raise HTTPException(409, "Gericht ist fixiert")
    if body and (body.direction or body.wish.strip()):
        pro.require(db, household, "reroll_direction")
    offers = plan_offers(db, household, plan)
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
                                               extra=plan_extra(db, household, prefs, [slot], offers=offers,
                                                                days=len({e.day for e in plan.entries
                                                                          if e.meal_type in variety.MAIN})),
                                               guests={slot: entry.guests}, repeat_weeks=rules["repeat_weeks"],
                                               max_cost_cents=body.max_cost_cents if body else None,
                                               direction=body.direction or "" if body else "",
                                               wish=body.wish if body else "", forbid=forbid_of(prefs), **memory)
    except RuntimeError as e:
        raise HTTPException(502, str(e))
    entry.prev_recipe_id = entry.recipe_id
    entry.recipe = _recipe(household, meal)
    entry.portions, entry.portions_total, entry.scale = portions, total, 1
    plan.params = {**plan.params, "usage": planner.add_usage(plan.params.get("usage", {}), call_usage)}
    reprice(db, plan, offers, pantry)
    sync_plan(db, household.id)
    db.commit()
    run_later(_fill_image, db.get_bind(), entry.recipe.id, meal.image_query or meal.title)
    food_map.map_later([i["name"] for i in entry.recipe.ingredients])
    return plan_out(db, plan)


@router.post("/plans/current/entries/{entry_id}/undo", response_model=PlanOut)
def undo_entry(entry_id: int, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Gericht vor dem letzten Neu-Würfeln/Ersetzen zurück (19.3); erneutes Rückgängig tauscht wieder."""
    plan = _current(db, member.household_id)
    entry = _entry(plan, entry_id)
    if entry.prev_recipe_id is None:
        raise HTTPException(409, "Nichts zum Rückgängigmachen")
    old = db.get(Recipe, entry.prev_recipe_id)
    target = entry.portions_total or entry.recipe.servings
    entry.prev_recipe_id, entry.recipe = entry.recipe_id, old
    entry.scale = 1 if old.source == "ai" else target / old.servings  # KI-Gerichte sind schon für den Slot gerechnet
    reprice(db, plan, plan_offers(db, member.household, plan), household_pantry(db, member.household_id))
    sync_plan(db, member.household_id)
    db.commit()
    return plan_out(db, plan)


@router.post("/plans/current/undo", response_model=PlanOut)
def undo_plan(member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Vorigen Plan wieder aktiv machen (19.3, „Rückgängig“ nach einem neuen Plan); der neue bleibt gespeichert."""
    plans = db.scalars(select(MealPlan).where(MealPlan.household_id == member.household_id)
                       .order_by(MealPlan.active_at.desc(), MealPlan.id.desc()).limit(2)).all()
    if len(plans) < 2:
        raise HTTPException(409, "Kein vorheriger Plan")
    plans[1].active_at = datetime.now()
    db.flush()
    sync_plan(db, member.household_id)
    db.commit()
    return plan_out(db, plans[1])


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
    entry.prev_recipe_id = entry.recipe_id
    entry.recipe, entry.scale = recipe, target / recipe.servings
    reprice(db, plan, plan_offers(db, household, plan), household_pantry(db, household.id))
    sync_plan(db, household.id)
    db.commit()
    food_map.map_later([i["name"] for i in recipe.ingredients])
    return plan_out(db, plan)


# --- Teilen: Einladungen, Mitglieder, gemeinsame Einkaufslisten (E40) ---

INVITE_DAYS = 7


def base_url(request: Request) -> str:
    return (settings.public_base_url or str(request.base_url)).rstrip("/")


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
    return {"id": lst.id, "name": lst.name, "kind": lst.kind, "share_url": share_url(request, lst),
            "items": with_coupons(object_session(lst), lst.household_id, lst.items)}


def coupon_badge(c: Coupon | None) -> dict | None:
    return {"id": c.id, "text": bonus.badge(c), "program": c.program, "partner": c.partner} if c else None


def with_coupons(db: Session, household_id: int | None, items: list[ShoppingItem]) -> list[ShoppingItem]:
    """Setzt item.coupon (Badge „🎟 10fach“) für Artikel mit passendem aktivem Coupon (38c/59)."""
    coupons = bonus.active(db, household_id) if household_id else []
    ids = {i.offer_id for i in items if i.offer_id}
    offers = {o.id: o for o in db.scalars(select(Offer).where(Offer.id.in_(ids)))} if coupons and ids else {}
    for i in items:
        i.coupon = coupon_badge(bonus.item_coupon(coupons, i.name, i.chain, offers.get(i.offer_id))) if coupons else None
    return items


def add_item(db: Session, lst: ShoppingList, body: ItemCreate, by: str) -> ShoppingItem:
    item = ShoppingItem(**body.model_dump(exclude={"next_week"}), added_by=by,
                        defer_week=prices.iso_week(next_monday()) if body.next_week else None)
    lst.items.append(item)
    db.commit()
    return item


def update_item(db: Session, item: ShoppingItem, body: ItemUpdate, by: str) -> ShoppingItem:
    changes = body.model_dump(exclude_unset=True)
    if changes.get("name") is None:
        changes.pop("name", None)
    if (later := changes.pop("next_week", None)) is not None:
        item.defer_week = prices.iso_week(next_monday()) if later else None
    toggled = changes.get("checked") is not None and changes["checked"] != item.checked
    household_id = db.get(ShoppingList, item.list_id).household_id
    if changes.get("checked") is None:
        changes.pop("checked", None)
    else:
        item.checked_by = by if changes["checked"] else ""
        if changes["checked"]:  # Verbrauchsrhythmus (58): „zuletzt gekauft“
            watch.mark_bought(db, household_id, item.name, date.today())
    for key, value in changes.items():
        setattr(item, key, value)
    if toggled and household_id:  # Monats-Dashboard (34): Preis + Zeitpunkt des Abhakens festhalten
        db.flush()
        spending.checked(db, household_id, item, by)
    db.commit()
    return item


def sync_plan(db: Session, household_id: int) -> ShoppingList:
    """Zutaten des aktuellen Plans (ohne Vorrat) als source=plan in die Haushaltsliste.
    Gleiche Zutat/offer_id wird summiert, vorhandene Plan-Einträge aktualisiert (Haken bleiben),
    Plan-Einträge, die nicht mehr im Plan sind, entfernt. Manuelle Einträge bleiben unberührt."""
    lst = household_list(db, household_id)
    plan = db.scalar(select(MealPlan).where(MealPlan.household_id == household_id)
                     .order_by(MealPlan.active_at.desc(), MealPlan.id.desc()).limit(1))

    def key_of(name: str, unit: str, offer_id: int | None) -> tuple:
        return ("offer", offer_id) if offer_id else ("name", stock_key(name), unit)  # Zwiebel = Zwiebeln (19.5)

    entries = plan.entries if plan else []
    single = ((plan.params or {}).get("options") or {}).get("single_store") if plan else None
    user_names = [i["name"] for e in entries for i in e.recipe.ingredients if "offer_id" not in i]
    match = pricer(db, plan_offers(db, db.get(Household, household_id), plan), user_names) if user_names else None
    needed: dict[tuple, dict] = {}
    for entry in entries:
        for ing in entry_ingredients(entry):
            if "offer_id" not in ing:  # eingesetztes Rezept (ohne KI-Zuordnung): Angebot über den Namen
                ing["offer_id"] = match.line(ing).offer_id
            amount, unit = base_unit(ing.get("amount") or 0, ing.get("unit", ""))  # 1 kg + 500 g = 1500 g
            if not unit:  # EL, TL, Prise bleiben wie im Rezept
                amount, unit = ing.get("amount") or 0, ing.get("unit", "")
            offer_id = ing.get("offer_id")
            row = needed.setdefault(key_of(ing["name"], unit, offer_id), {"name": ing["name"][:100], "amount": 0.0,
                                    "unit": unit, "offer_id": offer_id, "in_pantry": True, "pack": None})
            row["amount"] += amount
            if ing.get("pack_amount") and ing.get("unit") == unit:  # Schätzung der KI, Einheit wie amount
                row["pack"] = pack_amount(ing["name"], unit, ing["pack_amount"])
            row["in_pantry"] &= bool(ing.get("in_pantry"))
    stock = Stock(plan_stock(db, household_id))  # nur fehlende Mengen auf die Liste (60), Wochen-Basics (23)
    for key, row in list(needed.items()):
        have = stock.take(row["name"], row["unit"], row["amount"], row["in_pantry"])
        if have > 0 and have >= row["amount"]:
            del needed[key]
        else:
            row["amount"] -= have
    offer_ids = [r["offer_id"] for r in needed.values() if r["offer_id"]]
    offers = {o.id: o for o in db.scalars(select(Offer).where(Offer.id.in_(offer_ids)))}

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
        o = offers.get(row["offer_id"])
        item.chain = single or (o.chain if o else "")  # Ein-Laden-Modus (41): alles bei diesem Laden
        # Packung des Angebots (Einheit passend), sonst die Normalpreis-Schätzung der KI (19.5)
        item.pack_amount = o.amount if o and o.amount and o.unit == row["unit"] else row["pack"]
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


def _split(db: Session, member: Member, list_id: int, chains: list[str] | None = None):
    h = member.household
    lst = member_list(db, member, list_id)
    enabled = list(dict.fromkeys(s.chain for s in h.stores if s.enabled))
    if chains and not set(chains) <= set(enabled):
        raise HTTPException(422, "Laden ist nicht ausgewählt")
    chains = chains or enabled
    items = [i for i in lst.items if not i.checked and not ItemOut.model_validate(i).next_week]
    coords = {}
    for s_ in h.stores:
        if s_.enabled and s_.lat is not None and s_.chain not in coords:
            coords[s_.chain] = (s_.lat, s_.lng)
    p = store_split.Prices(household_offers(db, h), recipes.history_offers(db), chains)
    home = (h.lat, h.lng) if h.lat is not None else None
    return lst, items, store_split.combos(items, p, chains, home, coords)


@router.get("/lists/{list_id}/stores", response_model=list[StoreComboOut])
def list_stores(list_id: int, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Laden-Empfehlung (42): offene Artikel in allen Kombinationen aus max. 2 gewählten Läden (Angebote +
    Normalpreise, ganze Packungen), günstigste zuerst."""
    return _split(db, member, list_id)[2]


@router.post("/lists/{list_id}/assign", response_model=ListOut)
def assign_stores(list_id: int, body: AssignIn, request: Request, member: Member = Depends(current_member),
                  db: Session = Depends(get_db)):
    """„So aufteilen“ (42): jeder offene Artikel kommt in den günstigsten der gewählten Läden (Laden-Gruppen neu)."""
    lst, items, combos = _split(db, member, list_id, body.chains)
    combo = next(c for c in combos if c["chains"] == list(dict.fromkeys(body.chains)))
    for item in items:
        if item.id in combo["assignment"]:
            item.chain, item.offer_id, _ = combo["assignment"][item.id]
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
    return with_coupons(db, member.household_id, [add_item(db, member_list(db, member, list_id), body, member.name)])[0]


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
    with_coupons(db, member.household_id, [item])
    return {**ItemOut.model_validate(item).model_dump(), "pantry_suggest": bool(body.checked) and pantry_suggest(db, item)}


@router.post("/items/{item_id}/next-week", response_model=ItemOut)
def item_next_week(item_id: int, body: NextWeekIn | None = None, member: Member = Depends(current_member),
                   db: Session = Depends(get_db)):
    """„Auf nächste Woche schieben“ (30): Artikel wandert in die Gruppe „Nächste Woche“; mit offer_id bekommt ein
    nicht aus dem Plan stammender Artikel Laden und Angebot der nächsten Woche."""
    item = member_item(db, member, item_id)
    item.defer_week = prices.iso_week(next_monday())
    if body and body.offer_id and item.source != "plan":
        offer = db.get(Offer, body.offer_id)
        if offer is None:
            raise HTTPException(404, "Angebot nicht gefunden")
        item.offer_id, item.chain = offer.id, offer.chain
    db.commit()
    return item


@router.post("/items/{item_id}/to-pantry", response_model=PantryOut)
def item_to_pantry(item_id: int, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Abgehakten Artikel in den Vorrat: gleiche Zutat+Einheit wird aufaddiert, ein Basic gilt wieder als vorhanden."""
    item = member_item(db, member, item_id)
    # ganze Packungen gekauft: der Rest über den Bedarf hinaus liegt danach im Vorrat (19.5)
    packs = ItemOut.model_validate(item).packs
    amount, unit = base_unit(packs * item.pack_amount if packs else item.amount, item.unit)
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
    pro.require(db, member.household, "scan")
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
    pro.require(db, household, "no_mood")
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
    if settings.fal_key and member.household.step_images and pro.allowed(member.household) and not all(todo):
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
    pro.require(db, member.household, "step_images", spend=False)  # Bilder bleiben am Rezept, kein Verbrauch je Abruf
    pending = start_step_images(member, recipe)
    return {"step_images": RecipeOut.model_validate(recipe).step_images, "pending": pending}


@router.post("/import", response_model=RecipeDetail, status_code=201)
def import_recipe(body: ImportIn, response: Response, member: Member = Depends(current_member),
                  db: Session = Depends(get_db)):
    """Rezept-Import (5) aus Instagram-Beitrag/Reel oder Webseite. Gleiche URL schon importiert → dieses Rezept (200).
    422 „Kein Rezept gefunden“, 502 Seite/KI nicht erreichbar."""
    pro.require(db, member.household, "import")
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
    names = [i["name"] for e in plan.entries for i in e.recipe.ingredients]
    maps = food_map.load(db, names)
    food_map.map_later([n for n in names if ingredient_key(n) not in maps])  # z.B. nach Neu-Zuordnung (19.2)
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
    if not push.send(member, "Kochpilot", "Test-Push – tippen öffnet die App.", click_url="essenapp://start",
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
    reprice(db, plan, plan_offers(db, member.household, plan), household_pantry(db, member.household_id))
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
    reprice(db, plan, plan_offers(db, member.household, plan), household_pantry(db, member.household_id))
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
    plan = db.scalar(select(MealPlan).where(MealPlan.household_id == household.id).order_by(MealPlan.active_at.desc(), MealPlan.id.desc()).limit(1))
    single = ((plan.params or {}).get("options") or {}).get("single_store") if plan else None
    matcher = Matcher(household_offers(db, household, single))
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
        item.offer_id, item.chain = (offers[0].id, offers[0].chain) if offers else (None, single or "")
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
    pro.require(db, member.household, "substitutes")
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
                     .order_by(MealPlan.active_at.desc(), MealPlan.id.desc()).limit(1))
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
        reprice(db, plan, plan_offers(db, member.household, plan), household_pantry(db, member.household_id))
        sync_plan(db, member.household_id)
    db.commit()
    food_map.map_later([r["name"] for r in rows])
    return recipe_detail(db, member, recipe)


# --- Merkliste (27), Preisalarm (40), Verbrauchsrhythmus (58) ---

def member_watch(db: Session, member: Member, watch_id: int) -> WatchItem:
    item = db.get(WatchItem, watch_id)
    if item is None or item.household_id != member.household_id:
        raise HTTPException(404, "Merklisten-Eintrag nicht gefunden")
    return item


def watch_out(item: WatchItem, hits: list[dict], coupon: Coupon | None = None, last: PricePoint | None = None) -> dict:
    return {c.key: getattr(item, c.key) for c in WatchItem.__table__.columns} | {
        "lasts_weeks_suggestion": watch.lasts_suggestion(item.label, item.category),
        "empty_on": watch.empty_on(item), "hits": hits, "coupon": coupon_badge(coupon),
        "last_offer_week": last and last.week, "last_offer_chain": last and last.chain,
        "last_offer_price_cents": last and last.price_cents}


def watch_list(db: Session, member: Member, items: list[WatchItem]) -> list[dict]:
    offers = household_offers(db, member.household)
    found = {i.id: watch.matches(i, offers) for i in items}
    rows = {r["id"]: r for r in offer_rows(db, list({o.id: o for os in found.values() for o in os}.values()))}
    coupons = bonus.active(db, member.household_id)
    last = watch.last_offers(db, items, {s.chain for s in member.household.stores if s.enabled},
                              prices.iso_week(date.today()))
    db.commit()
    return [watch_out(i, [rows[o.id] for o in found[i.id]], coupons and bonus.item_coupon(
        coupons, f"{i.label} {i.brand}", i.chains[0] if len(i.chains) == 1 else "",
        found[i.id][0] if found[i.id] else None), last.get(i.id)) for i in items]


@router.get("/watch", response_model=list[WatchOut])
def get_watch(member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """S10 Merkliste: Einträge mit aktuellen Treffern (hits nicht leer → „Diese Woche günstig“, Badge am Angebote-Tab),
    Produkte ohne Treffer → „Beobachtet“, kind zutat → „Preisalarme“."""
    items = list(db.scalars(select(WatchItem).where(WatchItem.household_id == member.household_id)
                            .order_by(WatchItem.id)))
    return watch_list(db, member, items)


@router.post("/watch", response_model=WatchOut, status_code=201)
def create_watch(body: WatchIn, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Herz am Angebot (offer_id), Barcode (ean), Freitext oder „+ Zutat“ (kind zutat). Drogerie/Haushalt bekommen
    „Hält ca. X Wochen“ als Vorschlag (58)."""
    if body.kind == "zutat" or body.max_price_cents or body.max_base_price_cents:
        pro.require(db, member.household, "price_alert")
    data = body.model_dump(exclude={"offer_id"})
    if body.offer_id is not None:
        o = db.get(Offer, body.offer_id)
        if o is None:
            raise HTTPException(404, "Angebot nicht gefunden")
        data |= {"label": body.label or o.title, "brand": body.brand or o.brand, "category": body.category or o.category,
                 "image_url": body.image_url or o.image_url, "ean": body.ean or o.ean}
    if data["lasts_weeks"] is None and body.kind == "produkt":
        data["lasts_weeks"] = watch.lasts_suggestion(data["label"], data["category"]) if data["category"] in (
            "drogerie", "haushalt") else None
    item = WatchItem(household_id=member.household_id, created_by=member.id, **data)
    db.add(item)
    db.commit()
    return watch_list(db, member, [item])[0]


@router.patch("/watch/{watch_id}", response_model=WatchOut)
def patch_watch(watch_id: int, body: WatchUpdate, member: Member = Depends(current_member),
                db: Session = Depends(get_db)):
    item = member_watch(db, member, watch_id)
    if body.max_price_cents or body.max_base_price_cents:
        pro.require(db, member.household, "price_alert")
    nullable = ("max_price_cents", "max_base_price_cents", "lasts_weeks", "last_bought")
    for key, value in body.model_dump(exclude_unset=True).items():
        if value is not None or key in nullable:
            setattr(item, key, value)
    if item.max_base_price_cents is not None and not item.base_unit:
        raise HTTPException(422, "base_unit fehlt (kg, l oder stk)")
    db.commit()
    return watch_list(db, member, [item])[0]


@router.delete("/watch/{watch_id}", status_code=204)
def delete_watch(watch_id: int, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    db.delete(member_watch(db, member, watch_id))
    db.commit()
    return Response(status_code=204)


@router.get("/products/ean/{ean}", response_model=EanProductOut)
def product_by_ean(ean: str = Path_(pattern=r"^(\d{8}|\d{12,14})$"), member: Member = Depends(current_member)):
    """Barcode-Scan (27): EAN → Open Food Facts (Name, Marke, Bild, Nutri-Score); found false = unbekannt."""
    try:
        hit = labels.by_ean(ean)
    except (httpx.HTTPError, RuntimeError, KeyError) as e:
        raise HTTPException(502, f"Open Food Facts nicht erreichbar: {e}")
    if hit is None:
        return {"ean": ean, "found": False, "name": "", "brand": "", "image_url": "", "nutri_score": None}
    return {"ean": ean, "found": True, "name": hit["name"], "brand": hit["brand"], "image_url": hit["image_url"],
            "nutri_score": hit["nutri_score"].upper() if hit["nutri_score"] else None}


# --- Budget-Rest-Hinweis (43) ---

REST_MIN = 500  # ab 5 € Rest Ideen anbieten


def budget_state(plan: MealPlan, household: Household) -> dict:
    budget = (plan.params or {}).get("budget") or household.budget_food_week_cents
    rest = budget - plan.total_cents
    over = None
    if rest < 0 and (free := [e for e in plan.entries if not e.locked]):
        e = max(free, key=lambda e: e.cost_cents)
        over = {"entry_id": e.id, "day": e.day, "title": e.recipe.title, "cost_cents": e.cost_cents,
                "max_cost_cents": max(e.cost_cents + rest, 0)}
    return {"budget_cents": budget, "total_cents": plan.total_cents, "rest_cents": rest,
            "state": "over" if rest < 0 else "rest" if rest >= REST_MIN else "ok", "over": over}


@router.get("/plans/current/budget", response_model=BudgetOut)
def plan_budget(member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Karte nach dem Plan: „💶 Noch 6,80 € übrig – wie wär's mit …“ (state rest) bzw. „⚠️ 3,20 € über Budget –
    günstigere Alternative für Do?“ (state over → POST …/entries/{over.entry_id}/reroll {max_cost_cents})."""
    return budget_state(_current(db, member.household_id), member.household)


def buy_cents(p: recipes.Pricer, stock: Stock, ingredients: list[dict]) -> int:
    """Einkaufspreis (ganze Packungen) ohne Vorhandenes."""
    total = 0
    for i in ingredients:
        row = p.planned(i)
        need = row["amount"] - min(stock.take(row["name"], row["unit"], row["amount"]), row["amount"])
        if need > 0 and row["pack_amount"]:
            total += -(-need // row["pack_amount"]) * row["pack_price_cents"]
    return int(total)


@router.post("/plans/current/budget/ideas", response_model=list[BudgetIdeaOut])
def budget_ideas(member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """3 Ideen für den Rest (Dessert, Snack per Haiku; Vorratskauf aus 31) mit Kosten ≤ Rest. Dessert/Snack sind
    gespeicherte Rezepte → einplanen über POST /plans/current/entries; Vorrat → „auf die Liste“."""
    household, plan = member.household, _current(db, member.household_id)
    state = budget_state(plan, household)
    if state["state"] != "rest":
        raise HTTPException(422, "Kein Restbudget ab 5 €")
    rest, offers = state["rest_cents"], plan_offers(db, household, plan)
    prefs = _prefs(household, (plan.params or {}).get("options") or {})
    try:
        ideas, usage = pantry_ai.budget_ideas(prefs, offers, rest)
    except RuntimeError as e:
        raise HTTPException(502, str(e))
    planner.log_cost(db, household.id, "budget", usage["cost_cents"], usage["model"], f"{len(ideas)} Ideen, Rest {rest} ct")
    p = pricer(db, offers, [i.name for idea in ideas for i in idea.ingredients])
    priced = []
    for idea in ideas:
        cost = buy_cents(p, Stock(plan_stock(db, household.id)), [ingredient_row(i.model_dump()) for i in idea.ingredients])
        if cost <= rest and idea.meal_type in ("dessert", "snack") and idea.meal_type not in {k for k, _, _ in priced}:
            priced.append((idea.meal_type, idea, cost))
    saved = save_ideas(db, household, [(idea, []) for _, idea, _ in priced], image_wait=1)
    out = [{"kind": k, "title": idea.title, "cost_cents": cost, "recipe": r["recipe"], "stockup": None}
           for (k, idea, cost), r in zip(priced, saved)]
    for t in stockup_tips(db, household, offers):
        packs = min(t["packs"], rest // t["offer"]["price_cents"])
        if packs >= 1:
            t = t | {"packs": packs, "saving_cents": (t["normal_price_cents"] - t["offer"]["price_cents"]) * packs}
            out.append({"kind": "vorrat", "title": t["offer"]["title"], "cost_cents": t["offer"]["price_cents"] * packs,
                        "recipe": None, "stockup": t})
            break
    return out


@router.post("/plans/current/entries", response_model=PlanOut, status_code=201)
def add_entry(body: AddEntryIn, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Gericht zusätzlich einplanen (43: Dessert/Snack aus den Budget-Ideen), Mengen für die Esser des Slots,
    Kosten + Liste neu."""
    household, plan = member.household, _current(db, member.household_id)
    recipe = household_recipe(db, member, body.recipe_id)
    prefs = _prefs(household, (plan.params or {}).get("options") or {})
    slot = (body.day, body.meal_type)
    portions, total = _eaters(household, prefs.persons, [slot])[slot]
    if not total:
        raise HTTPException(422, "Bei dieser Mahlzeit isst niemand mit")
    plan.entries.append(MealPlanEntry(day=body.day, meal_type=body.meal_type, recipe=recipe, portions=portions,
                                      portions_total=total, scale=total / recipe.servings))
    db.flush()
    reprice(db, plan, plan_offers(db, household, plan), household_pantry(db, household.id))
    sync_plan(db, household.id)
    db.commit()
    food_map.map_later([i["name"] for i in recipe.ingredients])
    return plan_out(db, plan)


# --- Payback & Rewe Bonus (38), Drogerie-Coupons (59) ---

def coupon_out(c: Coupon) -> dict:
    left = bonus.days_left(c)
    return {k.key: getattr(c, k.key) for k in Coupon.__table__.columns} | {
        "badge": bonus.badge(c), "expired": left is not None and left < 0, "days_left": left}


def member_coupon(db: Session, member: Member, coupon_id: int) -> Coupon:
    c = db.get(Coupon, coupon_id)
    if c is None or c.household_id != member.household_id:
        raise HTTPException(404, "Coupon nicht gefunden")
    return c


@router.post("/coupons/scan", response_model=CouponScanOut)
def coupon_scan(file: UploadFile = File(...), member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Coupon-Foto (38a): 1 JPEG ≤ 5 MB → Haiku liest Partner, Produkt/Kategorie, Vorteil, Mindestumsatz, Gültig-bis.
    Speichert nichts; den Barcode liest die App selbst (VisionKit)."""
    image = file.file.read(MAX_SCAN_BYTES + 1)
    if len(image) > MAX_SCAN_BYTES or not image.startswith(b"\xff\xd8\xff"):
        raise HTTPException(422, "Foto muss ein JPEG bis 5 MB sein")
    try:
        read, usage = bonus.scan(image)
    except RuntimeError as e:
        raise HTTPException(502, str(e))
    planner.log_cost(db, member.household_id, "coupon", usage["cost_cents"], usage["model"],
                     f"{read['partner']} {read['benefit']}")
    db.commit()
    return read | {"cost_cents": usage["cost_cents"]}


@router.get("/coupons", response_model=list[CouponOut])
def list_coupons(chain: str | None = Query(None, max_length=30), active: bool = False,
                 member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Wallet: gültige zuerst (bald ablaufende oben), dann abgelaufene (grau). chain = Coupon-Leiste im Laden (38d,
    nur gültige Coupons dieses Ladens), active = nur gültige."""
    rows = [coupon_out(c) for c in db.scalars(select(Coupon).where(Coupon.household_id == member.household_id))]
    if chain is not None:
        rows = [r for r in rows if r["chain"] == chain and not r["expired"]]
    if active:
        rows = [r for r in rows if not r["expired"]]
    return sorted(rows, key=lambda r: (r["expired"], r["days_left"] is None, r["days_left"] or 0, r["id"]))


@router.post("/coupons", response_model=CouponOut, status_code=201)
def create_coupon(body: CouponIn, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Coupon speichern (Foto geprüft, Barcode oder manuell). Ohne chain wird der Laden aus partner abgeleitet."""
    c = Coupon(household_id=member.household_id, created_by=member.id, **body.model_dump())
    c.chain = c.chain or bonus.chain_of(c.partner)
    db.add(c)
    db.commit()
    return coupon_out(c)


@router.patch("/coupons/{coupon_id}", response_model=CouponOut)
def patch_coupon(coupon_id: int, body: CouponUpdate, member: Member = Depends(current_member),
                 db: Session = Depends(get_db)):
    c = member_coupon(db, member, coupon_id)
    nullable = ("multiplier", "bonus_cents", "percent", "min_spend_cents", "valid_until")
    for key, value in body.model_dump(exclude_unset=True).items():
        if value is not None or key in nullable:
            setattr(c, key, value)
    if "valid_until" in body.model_fields_set:
        c.expiry_notified_at = None  # neues Datum → neuer Ablauf-Push
    db.commit()
    return coupon_out(c)


@router.delete("/coupons/{coupon_id}", status_code=204)
def delete_coupon(coupon_id: int, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    db.delete(member_coupon(db, member, coupon_id))
    db.commit()
    return Response(status_code=204)


@router.get("/bonus", response_model=list[BonusAccountOut])
def bonus_accounts(member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Karten „Payback: 1.240 °P (≈ 12,40 €)“ und „Rewe Bonus: 8,50 €“ (38b), Werte manuell gepflegt."""
    return bonus.accounts(db, member.household_id)


@router.post("/bonus/{program}", response_model=BonusAccountOut)
def bonus_update(body: BonusIn, program: str = Path_(pattern="^(payback|rewe_bonus)$"),
                 member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Plus/Minus-Sheet: delta > 0 = „Heute bekommen: +60 °P“ (zählt als Ersparnis „Bonus“), delta < 0 = eingelöst,
    set = Kontostand korrigieren (zählt nicht als Ersparnis). Payback in °P, Rewe Bonus in Cent."""
    balance = next(a["balance"] for a in bonus.accounts(db, member.household_id) if a["program"] == program)
    if body.set is not None:
        kind, delta = "set", body.set - balance
    else:
        kind, delta = ("plus" if body.delta > 0 else "minus"), body.delta
    if balance + delta < 0:
        raise HTTPException(422, "Kontostand darf nicht negativ werden")
    db.add(BonusEntry(household_id=member.household_id, program=program, kind=kind, delta=delta, note=body.note,
                      member_id=member.id))
    db.commit()
    return next(a for a in bonus.accounts(db, member.household_id) if a["program"] == program)


# --- Monats-Dashboard (34) ---

MONTH = Query(None, pattern=r"^\d{4}-(0[1-9]|1[0-2])$")


@router.get("/spending", response_model=SpendingOut)
def get_spending(month: str | None = MONTH, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Ausgaben eines Monats (Standard: aktueller) = abgehakte Artikel zum Zeitpunkt des Abhakens (A10)."""
    return spending.dashboard(db, member.household, month or date.today().strftime("%Y-%m"))


@router.get("/spending/export")
def export_spending(month: str | None = MONTH, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """CSV zum Teilen (Semikolon, Dezimalkomma)."""
    month = month or date.today().strftime("%Y-%m")
    rows = spending.purchases(db, member.household_id, *spending.month_range(month))
    return Response(spending.to_csv(rows), media_type="text/csv; charset=utf-8",
                    headers={"Content-Disposition": f'attachment; filename="ausgaben-{month}.csv"'})


# --- Erfolge (54) ---

@router.get("/achievements", response_model=list[AchievementOut])
def get_achievements(member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Profil › Erfolge: Sparen (Haushalt) + Gesundheit des Mitglieds; neu Erreichtes wird hier sofort (genau einmal)
    freigeschaltet, new = Vollbild-Moment zeigen, danach POST /achievements/seen."""
    out, _ = motivation.for_member(db, member.household, member)
    db.commit()
    return out


@router.post("/achievements/seen", status_code=204)
def achievements_seen(body: SeenIn, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    for a in db.scalars(select(Achievement).where(Achievement.household_id == member.household_id,
                                                  Achievement.member_id.in_((0, member.id)),
                                                  Achievement.key.in_(body.keys), Achievement.seen_at.is_(None))):
        a.seen_at = datetime.now()
    db.commit()
    return Response(status_code=204)


# --- Wochenrückblick (55) ---

def week_review(db: Session, household: Household, week: str, rebuild: bool = False) -> WeekReview:
    """Rückblick anlegen (bzw. mit rebuild neu rechnen); „Nächste Woche günstig“ = Angebote ab dem Folgemontag."""
    row = db.scalar(select(WeekReview).where(WeekReview.household_id == household.id, WeekReview.week == week))
    if row is None or rebuild:
        motivation.evaluate(db, household)  # neue Erfolge gehören auf Seite 5
        after = prices.week_monday(week) + timedelta(days=7)
        data = motivation.build_review(db, household, week, household_offers(db, household, on=after))
        if row is None:
            row = WeekReview(household_id=household.id, week=week)
            db.add(row)
        row.data = jsonable_encoder(data)
        db.commit()
    return row


def review_out(row: WeekReview) -> dict:
    return row.data | {"created_at": row.created_at}


@router.get("/reviews", response_model=list[ReviewSummary])
def list_reviews(member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Archiv aller Rückblicke, neueste zuerst."""
    rows = db.scalars(select(WeekReview).where(WeekReview.household_id == member.household_id)
                      .order_by(WeekReview.week.desc()))
    return [{"week": r.week, "kw": r.data["kw"], "created_at": r.created_at, "spent_cents": r.data["money"]["spent_cents"],
             "cooked": r.data["cooking"]["cooked"]} for r in rows]


@router.get("/reviews/current", response_model=WeekReviewOut)
def current_review(member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Beim ersten Öffnen ab Sonntag die laufende Woche, Mo–Sa die vorige (sonst Job So 19:00)."""
    return review_out(week_review(db, member.household, motivation.review_week(date.today())))


@router.get("/reviews/{week}", response_model=WeekReviewOut)
def get_review(week: str = Path_(pattern=r"^\d{4}-W\d{2}$"), member: Member = Depends(current_member),
               db: Session = Depends(get_db)):
    row = db.scalar(select(WeekReview).where(WeekReview.household_id == member.household_id, WeekReview.week == week))
    if row is None:
        raise HTTPException(404, "Kein Rückblick für diese Woche")
    return review_out(row)


# --- Rezepte zwischen Haushalten teilen (56) ---

def shared_recipe(db: Session, code: str) -> Recipe:
    recipe = db.scalar(select(Recipe).where(Recipe.share_code == code[:16]))
    if recipe is None:
        raise HTTPException(404, "Rezept-Link ungültig")
    return recipe


def recipe_origin(db: Session, recipe: Recipe) -> str:
    h = db.get(Household, recipe.household_id) if recipe.household_id else None
    return h.name if h else "Kochpilot"


def import_shared(db: Session, recipe: Recipe, household_id: int, url: str) -> tuple[Recipe, bool]:
    """Kopie im eigenen Haushalt mit Quelle „von <Haushalt>“ (source shared); Foto und Schritt-Bilder werden
    mitkopiert. Schon übernommen oder eigenes Rezept → (vorhandenes, False)."""
    if recipe.household_id == household_id:
        return recipe, False
    existing = db.scalar(select(Recipe).where(Recipe.household_id == household_id, Recipe.source == "shared",
                                              Recipe.source_url == url).limit(1))
    if existing:
        return existing, False
    skip = ("id", "created_at", "household_id", "share_code", "source", "source_url", "source_author", "image_url",
            "step_images")
    copy = Recipe(**{c.key: getattr(recipe, c.key) for c in Recipe.__table__.columns if c.key not in skip},
                  household_id=household_id, source="shared", source_url=url[:500],
                  source_author=recipe_origin(db, recipe)[:100], image_url=recipe.image_url)
    db.add(copy)
    db.flush()
    if recipe.image_url.startswith(f"/media/recipes/{recipe.id}.jpg") and (
            src := MEDIA / "recipes" / f"{recipe.id}.jpg").exists():
        store_jpeg(copy, src.read_bytes())
    steps = MEDIA / "steps" / str(recipe.id)
    if any(recipe.step_images or []) and steps.exists():
        shutil.copytree(steps, MEDIA / "steps" / str(copy.id), dirs_exist_ok=True)
        copy.step_images = [i.replace(f"/steps/{recipe.id}/", f"/steps/{copy.id}/") for i in recipe.step_images]
    db.commit()
    food_map.map_later([i["name"] for i in copy.ingredients])
    return copy, True


def share_link(request: Request, code: str) -> str:
    return f"{base_url(request)}/r/{code}"


@router.post("/recipes/{recipe_id}/share", response_model=RecipeShareOut)
def share_recipe(recipe_id: int, request: Request, member: Member = Depends(current_member),
                 db: Session = Depends(get_db)):
    """Rezept › Teilen › „Als Link“: /r/<code> (Web-Ansicht für alle) + Deep-Link essenapp://import-recipe/<code>.
    Ein Rezept behält seinen Code."""
    recipe = household_recipe(db, member, recipe_id)
    if not recipe.share_code:
        taken = True
        while taken:
            recipe.share_code = new_code()
            taken = db.scalar(select(Recipe.id).where(Recipe.share_code == recipe.share_code, Recipe.id != recipe.id))
        db.commit()
    return {"code": recipe.share_code, "url": share_link(request, recipe.share_code),
            "app_url": f"essenapp://import-recipe/{recipe.share_code}"}


@router.get("/shared-recipes/{code}", response_model=SharedRecipeOut)
def get_shared_recipe(code: str, db: Session = Depends(get_db)):
    """Vorschau ohne Login (App nach essenapp://import-recipe/<code>)."""
    r = shared_recipe(db, code)
    return {"code": r.share_code, "title": r.title, "description": r.description, "image_url": r.image_url,
            "servings": r.servings, "prep_minutes": r.prep_minutes, "ingredients": r.ingredients, "steps": r.steps,
            "from_household": recipe_origin(db, r)}


@router.post("/shared-recipes/{code}/import", response_model=RecipeDetail, status_code=201)
def import_shared_recipe(code: str, request: Request, response: Response, member: Member = Depends(current_member),
                         db: Session = Depends(get_db)):
    """„In meine Rezepte übernehmen“: Kopie (201) bzw. schon vorhanden (200)."""
    recipe = shared_recipe(db, code)
    copy, created = import_shared(db, recipe, member.household_id, share_link(request, recipe.share_code))
    if not created:
        response.status_code = 200
    return recipe_detail(db, member, copy)
