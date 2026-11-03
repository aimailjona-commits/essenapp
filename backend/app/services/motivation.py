"""Erfolge (54) und Wochenrückblick (55). Zahlen rechnet der Code aus Käufen (34), Bonus-Konten (38), Plänen und
Nährwerten (2/48); Gesundheit zählt nur vergangene Plan-Tage."""
from collections import defaultdict
from datetime import date, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Achievement, Household, MealPlan, Member, Offer, Purchase, Rating, Recipe
from app.services import bonus, food_map, nutrition, planner, prices, spending
from app.services.pricing import stock_key

# key, Gruppe, Emoji, Titel, Kennzahl, Ziel, Einheit; Gesundheit gilt pro Mitglied
DEFS = [
    *[(f"gespart_{e}", "sparen", "💰", f"{e:,} € gespart".replace(",", "."), "saved", e * 100, "cent")
      for e in (10, 50, 100, 250, 500, 1000)],
    *[(f"budget_{w}", "sparen", "🎯", f"Budget-Wächter: {w} {'Woche' if w == 1 else 'Wochen'} in Folge im Budget",
       "budget_streak", w, "wochen") for w in (1, 4, 12)],
    *[(f"bestpreis_{n}", "sparen", "🔥", f"Bestpreis-Jäger: {n} Bestpreis-Angebote gekauft", "bestpreis", n,
       "angebote") for n in (10, 50)],
    ("vorrat_5", "sparen", "🏦", "Vorratsprofi: 5 Vorratskauf-Tipps genutzt", "stockup", 5, "tipps"),
    *[(f"protein_{d}", "gesundheit", "💪", f"Proteinziel an {d} Tagen erreicht", "protein_days", d, "tage")
      for d in (3, 7, 30)],
    *[(f"pflanzen_{n}", "gesundheit", "🥦", f"Pflanzenvielfalt: {n} verschiedene Pflanzen in einer Woche",
       "plants_week", n, "pflanzen") for n in (15, 30)],
    ("ausgewogen_7", "gesundheit", "⚖️", "Ausgewogen: 7 Tage kcal-Ziel ±10 %", "kcal_days", 7, "tage"),
]
BY_KEY = {d[0]: d for d in DEFS}

# Pflanzen (Obst, Gemüse, Hülsenfrüchte, Vollkorn/Getreide, Nüsse, Samen, Kräuter); Wortanfang oder -ende zählt
# shortcut: Stichwortliste statt Lebensmittel-Klassifikation; bei Fehltreffern Liste ergänzen
PLANT_WORDS = (
    "apfel", "äpfel", "birne", "banane", "beere", "orange", "mandarine", "clementine", "zitrone", "limette",
    "traube", "kiwi", "mango", "ananas", "pfirsich", "nektarine", "pflaume", "kirsche", "melone", "granatapfel",
    "feige", "dattel", "rosine", "tomate", "gurke", "paprika", "zucchini", "aubergine", "karotte", "möhre",
    "kartoffel", "zwiebel", "schalotte", "knoblauch", "lauch", "porree", "sellerie", "spinat", "salat", "rucola",
    "kohl", "brokkoli", "kohlrabi", "fenchel", "spargel", "kürbis", "pilz", "champignon", "erbse", "bohne", "linse",
    "kichererbse", "edamame", "mais", "reis", "hafer", "quinoa", "bulgur", "couscous", "hirse", "buchweizen",
    "gerste", "dinkel", "nuss", "nüsse", "mandel", "cashew", "pistazie", "sesam", "leinsamen", "chia", "kern",
    "ingwer", "petersilie", "basilikum", "koriander", "schnittlauch", "dill", "minze", "rosmarin", "thymian",
    "oregano", "avocado", "olive", "radieschen", "rote bete", "bete", "mangold", "tofu", "rettich", "pastinake",
    "rhabarber", "chili", "lauchzwiebel", "frühlingszwiebel", "okra", "artischocke", "süßkartoffel")
NOT_PLANT = ("öl", "brühe", "sauce", "soße", "saft", "essig", "milch", "joghurt", "pulver", "mark")


def is_plant(name: str) -> bool:
    ws = name.lower().replace(",", " ").split()
    if any(w.endswith(n) for w in ws for n in NOT_PLANT):
        return False
    return any(w.startswith(p) or w.endswith(p) for w in ws for p in PLANT_WORDS)


def plan_date(plan: MealPlan, day: int) -> date:
    return prices.week_monday(plan.week) + timedelta(days=day)


def latest_plans(db: Session, household_id: int, weeks: set[str] | None = None) -> list[MealPlan]:
    """Je Woche der zuletzt erzeugte Plan."""
    plans = {}
    for p in db.scalars(select(MealPlan).where(MealPlan.household_id == household_id).order_by(MealPlan.id)):
        if weeks is None or p.week in weeks:
            plans[p.week] = p
    return list(plans.values())


def health_days(db: Session, plans: list[MealPlan], members: list[Member], profiles: dict) -> dict:
    """{(member_id, Datum): [Nährwerte, vollständig, Pflanzen-Set]} aus den Plänen (Portion × Faktor wie
    GET /plans/current/nutrition)."""
    names = [i["name"] for p in plans for e in p.entries for i in e.recipe.ingredients]
    maps = food_map.load(db, names) if names else {}
    out: dict = {}
    for plan in plans:
        for e in plan.entries:
            nut, _ = nutrition.dish(e.recipe.ingredients, maps, e.portions_total or e.recipe.servings, e.scale or 1)
            plants = {stock_key(i["name"]) for i in e.recipe.ingredients if is_plant(i["name"])}
            eaters = e.portions or [{"member_id": m.id, "factor": planner.portion_factor(profiles[m.id].kcal)}
                                    for m in members]
            for p in eaters:
                cell = out.setdefault((p["member_id"], plan_date(plan, e.day)), [nutrition.Nutrients(), True, set()])
                if nut is None:
                    cell[1] = False
                else:
                    cell[0] += nutrition.Nutrients(**nut).scaled(p["factor"])
                cell[2] |= plants
    return out


def profiles_of(members: list[Member]) -> dict:
    from app.api import new_profile  # spät: api importiert diesen Dienst
    return {m.id: m.profile or new_profile(m) for m in members}


def member_metrics(days: dict, member_id: int, profile, before: date) -> dict:
    mine = {d: c for (m, d), c in days.items() if m == member_id and d < before}
    weeks = defaultdict(set)
    for d, c in mine.items():
        weeks[prices.iso_week(d)] |= c[2]
    return {"protein_days": sum(1 for c in mine.values() if c[1] and c[0].protein >= profile.protein_g),
            "kcal_days": sum(1 for c in mine.values() if c[1] and abs(c[0].kcal - profile.kcal) <= 0.1 * profile.kcal),
            "plants_week": max((len(s) for s in weeks.values()), default=0)}


def budget_streak(rows: list[Purchase], budget: int, today: date) -> int:
    """Abgeschlossene Wochen in Folge (ab letzter Woche rückwärts) mit Lebensmittel-Einkäufen ≤ Wochenbudget."""
    food = defaultdict(int)
    for p in rows:
        if p.category not in spending.NON_FOOD:
            food[prices.iso_week(p.bought_at.date())] += p.price_cents
    streak, monday = 0, today - timedelta(days=today.weekday() + 7)
    while (w := prices.iso_week(monday)) in food and food[w] <= budget:
        streak, monday = streak + 1, monday - timedelta(weeks=1)
    return streak


def household_metrics(db: Session, h: Household, today: date) -> dict:
    rows = list(db.scalars(select(Purchase).where(Purchase.household_id == h.id)))
    return {"saved": sum(p.saved_cents for p in rows) + bonus.earned_cents(db, h.id, date.min, date.max),
            "budget_streak": budget_streak(rows, h.budget_food_week_cents, today),
            "bestpreis": sum(p.verdict == "bestpreis" for p in rows),
            "stockup": sum(p.source == "stockup" for p in rows)}


def evaluate(db: Session, h: Household, today: date | None = None) -> tuple[dict, list[Achievement]]:
    """Kennzahlen rechnen und neu erreichte Erfolge genau einmal speichern → ({member_id (0 = Haushalt): {key:
    Fortschritt}}, neue Achievement-Zeilen)."""
    today = today or date.today()
    members = list(h.members)
    profiles = profiles_of(members)
    days = health_days(db, latest_plans(db, h.id), members, profiles)
    hm = household_metrics(db, h, today)
    progress = {0: {k: hm[d[4]] for k, d in BY_KEY.items() if d[1] == "sparen"}}
    for m in members:
        mm = member_metrics(days, m.id, profiles[m.id], today)
        progress[m.id] = {k: mm[d[4]] for k, d in BY_KEY.items() if d[1] == "gesundheit"}
    have = {(a.member_id, a.key) for a in db.scalars(select(Achievement).where(Achievement.household_id == h.id))}
    new = []
    for mid, values in progress.items():
        for key, value in values.items():
            if value >= BY_KEY[key][5] and (mid, key) not in have:
                new.append(Achievement(household_id=h.id, member_id=mid, key=key, unlocked_at=datetime.now()))
    db.add_all(new)
    db.flush()
    return progress, new


def achievement_out(key: str, progress: float, row: Achievement | None) -> dict:
    _, group, emoji, title, _, target, unit = BY_KEY[key]
    return {"key": key, "group": group, "emoji": emoji, "title": title, "target": target,
            "progress": min(progress, target), "unit": unit, "unlocked_at": row.unlocked_at if row else None,
            "new": bool(row and row.seen_at is None)}


def for_member(db: Session, h: Household, member: Member) -> tuple[list[dict], list[Achievement]]:
    """Raster für Profil › Erfolge: Sparen (Haushalt) + Gesundheit dieses Mitglieds."""
    progress, new = evaluate(db, h)
    rows = {(a.member_id, a.key): a for a in db.scalars(select(Achievement).where(Achievement.household_id == h.id))}
    out = [achievement_out(k, progress[0][k], rows.get((0, k))) for k in progress[0]]
    out += [achievement_out(k, progress[member.id][k], rows.get((member.id, k))) for k in progress[member.id]]
    return out, new


# --- Wochenrückblick (55) ---

def review_week(today: date) -> str:
    """Ab Sonntag die laufende Woche, sonst die vorige."""
    return prices.iso_week(today if today.weekday() == 6 else today - timedelta(days=today.weekday() + 1))


def next_week_deals(offers: list[Offer], limit: int = 3) -> list[dict]:
    """„Nächste Woche günstig“ (30): höchster Rabatt, Lebensmittel, je Titel einmal."""
    out, seen = [], set()
    for o in sorted((o for o in offers if o.category in planner.FOOD_CATEGORIES and o.regular_price_cents
                     and o.regular_price_cents > o.price_cents), key=lambda o: o.price_cents / o.regular_price_cents):
        if o.title.lower() not in seen and len(out) < limit:
            seen.add(o.title.lower())
            out.append({"offer_id": o.id, "title": o.title, "chain": o.chain, "image_url": o.image_url,
                        "price_cents": o.price_cents, "regular_price_cents": o.regular_price_cents,
                        "saving_pct": round(100 * (1 - o.price_cents / o.regular_price_cents))})
    return out


def build_review(db: Session, h: Household, week: str, next_offers: list[Offer]) -> dict:
    start = prices.week_monday(week)
    end = start + timedelta(days=7)
    t0, t1 = datetime.combine(start, datetime.min.time()), datetime.combine(end, datetime.min.time())
    ratings = list(db.scalars(select(Rating).join(Recipe, Recipe.id == Rating.recipe_id).where(
        Recipe.household_id == h.id, Rating.cooked_at >= t0, Rating.cooked_at < t1)
        .order_by(Rating.stars.desc(), Rating.cooked_at.desc())))
    plans = latest_plans(db, h.id, {week})
    plan = plans[0] if plans else None
    fav = None
    if ratings:
        r = db.get(Recipe, ratings[0].recipe_id)
        fav = {"recipe_id": r.id, "title": r.title, "image_url": r.image_url, "stars": ratings[0].stars}
    rows = spending.purchases(db, h.id, start, end)
    spent = sum(p.price_cents for p in rows)
    budget = spending.budget_cents(h, 7)
    members = list(h.members)
    profiles = profiles_of(members)
    days = health_days(db, plans, members, profiles)
    health = []
    for m in members:
        mine = [c for (mid, _), c in days.items() if mid == m.id and c[1]]
        n = len(mine) or 1
        health.append({"member_id": m.id, "name": m.name, "emoji": profiles[m.id].emoji,
                       "avg_kcal": round(sum(c[0].kcal for c in mine) / n), "kcal_goal": profiles[m.id].kcal,
                       "avg_protein": round(sum(c[0].protein for c in mine) / n), "protein_goal": profiles[m.id].protein_g,
                       "plants": len(set().union(*(c[2] for (mid, _), c in days.items() if mid == m.id)))})
    rests = ((plan.params or {}).get("rests") or {}) if plan else {}
    unlocked = list(db.scalars(select(Achievement).where(Achievement.household_id == h.id,
                                                         Achievement.unlocked_at >= t0, Achievement.unlocked_at < t1)))
    return {
        "week": week, "kw": start.isocalendar().week, "start": start.isoformat(),
        "end": (end - timedelta(days=1)).isoformat(),
        "cooking": {"cooked": len(ratings), "planned": len(plan.entries) if plan else 0, "favorite": fav},
        "money": {"spent_cents": spent, "estimated_cents": sum(p.price_cents for p in rows if p.estimated),
                  "saved_cents": sum(p.saved_cents for p in rows), "bonus_cents": bonus.earned_cents(db, h.id, start, end),
                  "budget_cents": budget, "budget_ok": spent <= budget},
        "health": health,
        "pantry": {"rests_used": rests.get("planned", 0), "rests_left": len(rests.get("left", [])),
                   "thrown_away": None},  # Wegwerfen wird (noch) nicht erfasst
        "achievements": [achievement_out(a.key, BY_KEY[a.key][5], a) | {"member_id": a.member_id} for a in unlocked],
        "next_week": next_week_deals(next_offers),
    }
