"""Woche per Swipe (Phase 20, E97): Kartenstapel je Mahlzeitart, Abstimmung im Haushalt, Verteilen, Plan aus der
Auswahl. Karten-Erzeugung und Plan laufen im Hintergrund (Muster E94)."""
import logging
import math
import time
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, date, datetime

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app import api
from app.core.auth import current_member
from app.core.db import get_db
from app.models import (Household, JobRun, MealPlan, MealPlanEntry, Member, Rating, Recipe, SwipeCard, SwipeDeck,
                        SwipeVote)
from app.schemas import DistributeIn, DistributeOut, FinishIn, PlanJobOut, SwipeOut, VoteIn, VoteOut
from app.services import food_map, planner, prices, pro, recipe_images, recipes, swipe, variety

router = APIRouter()
log = logging.getLogger(__name__)

CARDS_PER_SLOT = 2  # Stapelgröße = 2 × Plätze …
MAX_BATCH = 10  # … höchstens so viele Karten je Mahlzeitart und Aufruf
REPEAT_BATCH = 6  # Frühstück/Snack: ein Gericht deckt mehrere Tage
REFILL_AT = 5  # weniger offene Karten einer Art → nachladen
OWN_SHARE = 3  # jede dritte Karte ein eigenes Rezept (Favorit, ≥ 4 ★), solange vorhanden
PART = 3  # Karten je KI-Aufruf
FOCUS = {"abend": ["Fleisch oder Geflügel", "vegetarisch", "Fisch oder Hülsenfrüchte", "international (asiatisch, "
                   "orientalisch, mexikanisch)"],
         "fruehstueck": ["herzhaft", "süß", "schnell zum Mitnehmen"],
         "snack": ["proteinreich", "Obst oder Gemüse", "selbst gebacken"]}
FOCUS["mittag"] = FOCUS["lunchbox"] = FOCUS["abend"]


def week_slots(db: Session, household: Household) -> tuple[object, list[tuple[int, str]], dict]:
    """Wie POST /plans: Plätze der Woche, an denen jemand isst (Lunchbox nur an Lunchbox-Tagen)."""
    prefs = api._prefs(household, {})
    profiles = api._profiles(household)
    lunch_days = {d for p in profiles for d in (p.lunchbox_days or [])}
    all_slots = planner.week_slots(prefs, lunch_days)
    eaters = planner.slot_eaters(profiles, prefs.persons, all_slots)
    return prefs, [s for s in all_slots if eaters[s][1] > 0], eaters


def open_deck(db: Session, household_id: int) -> SwipeDeck | None:
    return db.scalar(select(SwipeDeck).where(SwipeDeck.household_id == household_id, SwipeDeck.state == "offen")
                     .order_by(SwipeDeck.id.desc()).limit(1))


def my_deck(db: Session, member: Member) -> SwipeDeck:
    deck = open_deck(db, member.household_id)
    if deck is None:
        raise HTTPException(404, "Kein Stapel offen")
    return deck


def deck_votes(db: Session, deck: SwipeDeck) -> list[SwipeVote]:
    return list(db.scalars(select(SwipeVote).join(SwipeCard, SwipeCard.id == SwipeVote.card_id)
                           .where(SwipeCard.deck_id == deck.id).order_by(SwipeVote.id)))


def job_row(db: Session, deck_id: int) -> JobRun | None:
    return db.scalar(select(JobRun).where(JobRun.name == f"swipe:{deck_id}").order_by(JobRun.id.desc()).limit(1))


def card_out(t: swipe.Tally) -> dict:
    return {**{k: getattr(t.card, k) for k in ("id", "meal_type", "source", "recipe_id", "title", "description",
                                                 "cuisine", "prep_minutes", "image_url", "cost_cents", "deals",
                                                 "chain")},
            "match": t.match, "yes": t.yes, "days": t.days, "ingredients": [i["name"] for i in t.card.ingredients or []]}


def deck_out(db: Session, deck: SwipeDeck, member: Member) -> dict:
    votes = deck_votes(db, deck)
    tallies = swipe.tally(deck.cards, votes)
    have = swipe.progress(deck.need, tallies)
    state = api.plan_job_state(job_row(db, deck.id))
    voters = {v.member_id for v in votes}
    order = {m: i for i, m in enumerate(planner.SLOT_ORDER)}
    return {"id": deck.id, "state": deck.state, "loading": state["state"] == "running", "error": state["error"],
            "need": deck.need, "have": have, "ready": all(have[m] >= n for m, n in deck.need.items()),
            "cards": [card_out(tallies[c.id]) for c in sorted(swipe.pending(deck.cards, votes, member.id, tallies),
                                                               key=lambda c: (order.get(c.meal_type, 9), c.position))],
            "chosen": [card_out(t) for m in sorted(deck.need, key=lambda m: order.get(m, 9))
                       for t in swipe.ranked(tallies, m)],
            "members": [m.name for m in member.household.members if m.id in voters],
            "slots": [{"day": d, "meal_type": m, "card_id": 0} for d, m in deck.slots]}


def start_fill(db: Session, deck: SwipeDeck, meal_types: list[str]) -> None:
    """Karten im Hintergrund erzeugen; läuft schon ein Lauf für den Stapel, kein zweiter."""
    if api.plan_job_state(job_row(db, deck.id))["state"] == "running":
        return
    row = JobRun(name=f"swipe:{deck.id}", ran_at=datetime.now(UTC).replace(tzinfo=None), info="läuft")
    db.add(row)
    db.commit()
    api.run_later(_fill_job, db.get_bind(), row.id, deck.id, meal_types)


def _fill_job(bind, row_id: int, deck_id: int, meal_types: list[str]) -> None:
    with Session(bind) as db:
        try:
            images = fill_deck(db, db.get(SwipeDeck, deck_id), meal_types)
            ok, info = True, "fertig"
        except Exception:
            db.rollback()
            log.exception("Swipe-Karten fehlgeschlagen")
            ok, info, images = False, "Karten konnten nicht geladen werden, bitte erneut versuchen", []
        row = db.get(JobRun, row_id)
        row.ok, row.info = ok, info
        db.commit()
        # Fotos nach dem Speichern: Karten erscheinen sofort mit Teller-Platzhalter
        with ThreadPoolExecutor(max_workers=6) as pool:
            found = list(pool.map(lambda q: recipe_images.find_image(q[1]), images))
        for (card_id, _), url in zip(images, found):
            if url and (card := db.get(SwipeCard, card_id)):
                card.image_url = url[:500]
        db.commit()


def priced_card(pricer, ingredients: list[dict], servings: float = 1) -> tuple[int, int, str]:
    """(Kosten pro Portion, Zutaten im Angebot, Laden mit den meisten Angeboten)."""
    lines, total, _ = pricer.cost(ingredients)
    chains = Counter(line.chain for line in lines if line.in_offer and line.chain)
    return round(total / max(servings, 1)), sum(1 for line in lines if line.in_offer), \
        chains.most_common(1)[0][0] if chains else ""


def fill_deck(db: Session, deck: SwipeDeck, meal_types: list[str],
              ask=None) -> list[tuple[int, str]]:
    """Neue Karten je Mahlzeitart: eigene Lieblingsrezepte dazwischen, Rest KI-Ideen aus den Angeboten (parallel).
    → [(card_id, Bildsuche)] für KI-Karten ohne Foto."""
    ask = ask or planner.ask_cards
    household = db.get(Household, deck.household_id)
    prefs = api._prefs(household, {})
    rules = variety.rules_of(household.variety)
    memory = recipes.planner_memory(db, household.id, repeat_weeks=rules["repeat_weeks"])
    offers = api.effective_offers(db, household, api.household_offers(db, household))
    pantry = api.household_pantry(db, household.id)
    forbid = api.forbid_of(prefs)
    seen = [c.title for c in deck.cards]
    used = {c.recipe_id for c in deck.cards if c.recipe_id}
    extra = api.plan_extra(db, household, prefs, [tuple(s) for s in deck.slots], "", offers)
    want = {m: min(REPEAT_BATCH if m in swipe.REPEAT else MAX_BATCH, CARDS_PER_SLOT * deck.need[m])
            for m in meal_types if m in deck.need}

    own: dict[str, list[Recipe]] = {}
    for r in recipes.liked_recipes(db, household.id, recent=memory["recent"]):
        m = r.meal_type if r.meal_type in want else None
        if m and r.id not in used and r.title not in seen and not any(forbid(i["name"]) for i in r.ingredients):
            own.setdefault(m, []).append(r)
    own = {m: rs[:max(want[m] // OWN_SHARE, 1 if rs else 0)] for m, rs in own.items()}

    def ask_part(job: tuple[str, int, int]):
        m, n, k = job
        focus = FOCUS.get(m, FOCUS["abend"])[k % len(FOCUS.get(m, FOCUS["abend"]))]
        note = (f"Schlage {n} verschiedene Gerichte für {planner.MEAL_TYPES.get(m, m)} (meal_type={m}) vor, "
                f"Schwerpunkt: {focus} (nur wenn es zur Ernährungsform passt). Nicht: {', '.join(seen) or '-'}.")
        return ask(planner.build_prompt(prefs, offers, [], favorites=[], note=note, pantry=pantry,
                                        never=memory["never"], recent=memory["recent"], extra=extra,
                                        repeat_weeks=rules["repeat_weeks"]))

    # kleine Pakete parallel: erste Karten nach ~5 s statt ~12 s; je Paket ein anderer Schwerpunkt (Abwechslung)
    jobs = [(m, min(PART, n - k * PART), k) for m in want for n in [want[m] - len(own.get(m, []))]
            for k in range(math.ceil(max(n, 0) / PART))]
    with ThreadPoolExecutor(max_workers=max(len(jobs), 1)) as pool:
        parts = list(pool.map(ask_part, jobs))
    results = {m: (planner.CardSet(cards=[]), {}) for m in want}
    for (m, _, _), (cs, u) in zip(jobs, parts):
        results[m] = (planner.CardSet(cards=[*results[m][0].cards, *cs.cards]), planner.add_usage(results[m][1], u))
    names = [i.name for cs, _ in results.values() for c in cs.cards for i in c.ingredients]
    names += [i["name"] for rs in own.values() for r in rs for i in r.ingredients]
    pricer = api.pricer(db, offers, names)
    position = max((c.position for c in deck.cards), default=0)
    images = []
    for m in want:
        drafts = []
        for c in results[m][0].cards:  # Pakete laufen getrennt: ähnliche Titel nur einmal
            if not any(planner.similar(c.title, t) for t in [*seen, *(d.title for d in drafts)]) \
                    and not any(forbid(i.name) for i in c.ingredients):
                drafts.append(c)
        mine = list(own.get(m, []))
        for k in range(len(drafts) + len(mine)):
            position += 1
            if mine and (k % OWN_SHARE == 1 or not drafts):
                r = mine.pop(0)
                cost, deals, chain = priced_card(pricer, r.ingredients, r.servings)
                side, protein = variety.tags_of(r.tags or [], r.title, [i["name"] for i in r.ingredients])
                deck.cards.append(SwipeCard(meal_type=m, position=position, source="rezept", recipe_id=r.id,
                                            title=r.title[:200], description=(r.description or "")[:500],
                                            cuisine=(r.cuisine or "")[:50], prep_minutes=r.prep_minutes or 0, side=side,
                                            protein=protein, image_url=r.image_url or "", cost_cents=cost, deals=deals,
                                            chain=chain, ingredients=r.ingredients))
                continue
            d = drafts.pop(0)
            ings = [i.model_dump() for i in d.ingredients]
            cost, deals, chain = priced_card(pricer, ings)
            card = SwipeCard(meal_type=m, position=position, source="ki", title=d.title[:200],
                             description=d.description[:500], cuisine=d.cuisine[:50], prep_minutes=d.prep_minutes,
                             side=d.side, protein=d.protein, cost_cents=cost, deals=deals, chain=chain,
                             ingredients=ings)
            deck.cards.append(card)
            seen.append(d.title)
            images.append((card, d.image_query or d.title))
    db.flush()
    usage = {}
    for _, u in results.values():
        usage = planner.add_usage(usage, u)
    if usage.get("cost_cents"):
        planner.log_cost(db, household.id, "swipe", usage["cost_cents"], usage.get("model", ""), f"Stapel {deck.id}")
    db.commit()
    return [(c.id, q) for c, q in images]


@router.post("/swipe", response_model=SwipeOut)
def start_swipe(member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """„Woche planen“: offenen Stapel holen oder neu anlegen (Karten kommen im Hintergrund, GET /swipe)."""
    household = member.household
    deck = open_deck(db, household.id)
    if deck is None:
        pro.require(db, household, "plan", spend=False)  # gebucht wird beim Plan (POST /swipe/finish)
        _, slots, _ = week_slots(db, household)
        if not slots:
            raise HTTPException(422, "Keine Mahlzeiten oder Tage eingestellt")
        deck = SwipeDeck(household_id=household.id, member_id=member.id, week=prices.iso_week(date.today()),
                         need=dict(Counter(m for _, m in slots)), slots=[list(s) for s in slots])
        db.add(deck)
        db.commit()
        start_fill(db, deck, list(deck.need))
        db.refresh(deck)
    return deck_out(db, deck, member)


@router.get("/swipe", response_model=SwipeOut)
def get_swipe(member: Member = Depends(current_member), db: Session = Depends(get_db)):
    return deck_out(db, my_deck(db, member), member)


@router.delete("/swipe", status_code=204)
def drop_swipe(member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Stapel verwerfen (neu anfangen); Stimmen und Karten gehen mit."""
    deck = my_deck(db, member)
    for v in deck_votes(db, deck):
        db.delete(v)
    db.delete(deck)
    db.commit()


def never_again(db: Session, member: Member, card: SwipeCard, note: str) -> None:
    """„Schmeckt mir nicht“/„Sonstiges“ → Nie-Liste wie eine „nie“-Bewertung (E96). Eine KI-Karte wird dafür als
    Rezept gemerkt. shortcut: ohne Schritte (nur Titel/Hauptzutaten), reicht für Nie-Liste und „Ausgeblendet“."""
    recipe = db.get(Recipe, card.recipe_id) if card.recipe_id else None
    if recipe is None:
        recipe = Recipe(household_id=member.household_id, source="ai", title=card.title, description=card.description,
                        cuisine=card.cuisine, meal_type=card.meal_type, servings=1, prep_minutes=card.prep_minutes,
                        ingredients=card.ingredients, steps=[], image_url=card.image_url, tags=[card.side, card.protein])
        db.add(recipe)
        db.flush()
        card.recipe_id = recipe.id
    recipe.unhidden = False
    db.add(Rating(recipe_id=recipe.id, member_id=member.id, stars=1, again="nie", note=note[:300],
                  cooked_at=datetime.now()))


@router.post("/swipe/cards/{card_id}/vote", response_model=VoteOut)
def vote(card_id: int, body: VoteIn, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Rechts = ja, links = nein, oben = mag_nicht mit Grund. „Keine Lust“ zählt nur als Nein dieser Person;
    „Mag ich nicht“ nimmt die Karte für alle raus. Wird eine Art knapp, lädt der Stapel nach."""
    deck = my_deck(db, member)
    card = next((c for c in deck.cards if c.id == card_id), None)
    if card is None:
        raise HTTPException(404, "Karte nicht im Stapel")
    kind = "nein" if body.vote == "mag_nicht" and body.reason == "keine_lust" else body.vote
    if kind == "mag_nicht":
        if body.reason == "zutat" and body.ingredient.strip():
            name = body.ingredient.strip()
            household = member.household
            if name.lower() not in (e.lower() for e in household.excluded_ingredients):
                household.excluded_ingredients = [*household.excluded_ingredients, name]
        elif body.reason in ("schmeckt_nicht", "sonstiges", None):
            never_again(db, member, card, f"Mag ich nicht: {body.note or body.reason or 'swipe'}")
    old = db.scalar(select(SwipeVote).where(SwipeVote.card_id == card.id, SwipeVote.member_id == member.id))
    if old:
        old.vote, old.days = kind, body.days
    else:
        db.add(SwipeVote(card_id=card.id, member_id=member.id, vote=kind, days=body.days))
    db.commit()
    votes = deck_votes(db, deck)
    tallies = swipe.tally(deck.cards, votes)
    have = swipe.progress(deck.need, tallies)
    left = [c for c in swipe.pending(deck.cards, votes, member.id, tallies) if c.meal_type == card.meal_type]
    if len(left) < REFILL_AT and have[card.meal_type] < deck.need[card.meal_type]:
        start_fill(db, deck, [card.meal_type])
    return {"match": kind == "ja" and tallies[card.id].match, "have": have,
            "ready": all(have[m] >= n for m, n in deck.need.items())}


@router.post("/swipe/undo", response_model=SwipeOut)
def undo_vote(member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """Letzte eigene Entscheidung zurück. shortcut: eine Mag-nicht-Zutat bzw. Nie-Bewertung bleibt bestehen
    (zurücknehmen über Einstellungen bzw. „Ausgeblendet“)."""
    deck = my_deck(db, member)
    mine = [v for v in deck_votes(db, deck) if v.member_id == member.id]
    if mine:
        db.delete(mine[-1])
        db.commit()
    return deck_out(db, deck, member)


@router.post("/swipe/more/{meal_type}", response_model=SwipeOut)
def more_cards(meal_type: str, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    deck = my_deck(db, member)
    if meal_type not in deck.need:
        raise HTTPException(422, "Mahlzeit nicht im Stapel")
    start_fill(db, deck, [meal_type])
    return deck_out(db, deck, member)


def fresh_of(db: Session, deck: SwipeDeck) -> dict[int, set[str]]:
    own = {r.id: r for r in db.scalars(select(Recipe).where(Recipe.id.in_([c.recipe_id for c in deck.cards
                                                                            if c.recipe_id])))}
    return {c.id: swipe.fresh_keys(c, own[c.recipe_id].ingredients if c.recipe_id in own else []) for c in deck.cards}


def checked(deck: SwipeDeck, items, complete: bool) -> dict[tuple[int, str], int]:
    """Zuordnung prüfen: nur Plätze und Karten dieses Stapels, Karte passt zur Mahlzeit; complete = alle Plätze."""
    slots = {tuple(s) for s in deck.slots}
    cards = {c.id: c for c in deck.cards}
    out = {}
    for it in items:
        s = (it.day, it.meal_type)
        if s not in slots or it.card_id not in cards or cards[it.card_id].meal_type != it.meal_type or s in out:
            raise HTTPException(422, "Zuordnung passt nicht zum Stapel")
        out[s] = it.card_id
    if complete and set(out) != slots:
        raise HTTPException(422, "Nicht alle Mahlzeiten belegt")
    return out


@router.post("/swipe/distribute", response_model=DistributeOut)
def distribute(body: DistributeIn, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """„Verteilen“ / „Neu mischen“ (ohne KI, ohne Speichern): gewählte Karten auf die freien Plätze."""
    deck = my_deck(db, member)
    fixed = checked(deck, body.fixed, complete=False)
    household = member.household
    prefs = api._prefs(household, {})
    assign, reserve = swipe.distribute(swipe.tally(deck.cards, deck_votes(db, deck)), [tuple(s) for s in deck.slots],
                                       fixed, variety.rules_of(household.variety), api.fish_ok(prefs), body.seed,
                                       fresh_of(db, deck))
    return {"assignment": [{"day": d, "meal_type": m, "card_id": c} for (d, m), c in sorted(assign.items())],
            "reserve": reserve}


@router.post("/swipe/finish", response_model=PlanJobOut, status_code=202)
def finish(body: FinishIn, member: Member = Depends(current_member), db: Session = Depends(get_db)):
    """„Plan übernehmen“: ganze Rezepte für die KI-Karten (parallel), eigene Rezepte direkt; Stand über GET /plans/job
    wie beim KI-Plan."""
    deck = my_deck(db, member)
    assignment = checked(deck, body.assignment, complete=True)
    row = api.plan_job_row(db, member.household_id)
    if api.plan_job_state(row)["state"] == "running":
        return api.plan_job_state(row)
    pro.require(db, member.household, "plan", spend=False)
    deck_id = deck.id
    row = JobRun(name=f"plan:{member.household_id}", ran_at=datetime.now(UTC).replace(tzinfo=None), info="läuft")
    db.add(row)
    db.commit()
    api.run_later(api._plan_job, db.get_bind(), row.id, member.id, None,
                  lambda m, s: swipe_plan(m, s, deck_id, assignment))
    return api.plan_job_state(row)


def swipe_plan(member: Member, db: Session, deck_id: int, assignment: dict[tuple[int, str], int],
               ask=None) -> MealPlan:
    started = time.monotonic()
    household = member.household
    deck = db.get(SwipeDeck, deck_id)
    pro.require(db, household, "plan")
    prefs, _, eaters = week_slots(db, household)
    cards = {c.id: c for c in deck.cards}
    slots = sorted(assignment, key=lambda s: (s[0], planner.SLOT_ORDER.index(s[1])))
    portions = {s: eaters[s][1] if s in eaters else prefs.persons for s in slots}
    offers = api.effective_offers(db, household, api.household_offers(db, household))
    pantry = api.household_pantry(db, household.id)
    ki = [s for s in slots if cards[assignment[s]].source == "ki"]
    meals, usage = {}, {}
    if ki:
        try:
            priced = planner.make_plan(
                prefs, offers, ki, favorites=[], portions=portions, pantry=pantry,
                extra=api.plan_extra(db, household, prefs, ki, "", offers), stock=api.plan_stock(db, household.id),
                forbid=api.forbid_of(prefs), ask=ask,
                fixed={s: f"{cards[assignment[s]].title} – {cards[assignment[s]].description}" for s in ki})
        except RuntimeError as e:
            raise HTTPException(502, str(e))
        meals, usage = {(m.day, m.meal_type): m for m in priced.draft.meals}, priced.usage
    plan = MealPlan(household_id=household.id, week=prices.iso_week(date.today()),
                    params={"budget": prefs.budget_food_week_cents, "options": {"swipe": deck.id}, "usage": usage})
    for s in slots:
        card = cards[assignment[s]]
        entry = MealPlanEntry(day=s[0], meal_type=s[1], portions=eaters.get(s, ([], 0))[0],
                              portions_total=portions[s], guests=0)
        if card.source == "ki":
            if s not in meals:
                raise HTTPException(502, "Rezept konnte nicht geschrieben werden, bitte erneut versuchen")
            entry.recipe = api._recipe(household, meals[s], card.image_url)
        else:
            recipe = db.get(Recipe, card.recipe_id)
            entry.recipe, entry.scale = recipe, portions[s] / max(recipe.servings, 1)
        plan.entries.append(entry)
    db.add(plan)
    db.flush()
    api.reprice(db, plan, offers, pantry)
    plan.params = {**plan.params, "seconds": round(time.monotonic() - started)}
    deck.state = "fertig"
    api.sync_plan(db, household.id)
    db.commit()
    food_map.map_later([i["name"] for e in plan.entries for i in e.recipe.ingredients])
    return plan
