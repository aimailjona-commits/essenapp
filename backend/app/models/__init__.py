from datetime import date, datetime

from sqlalchemy import JSON, ForeignKey, String, UniqueConstraint, func, true
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.db import Base

# Geld immer in Cent (int), nie float.

QUIET_DEFAULT = {"start": "22:00", "end": "07:00"}  # Ruhezeit für Pushes (Europe/Berlin)
# Abwechslungsregeln (12): Standardwerte laut Spezifikation
VARIETY_DEFAULT = {"max_pasta": 1, "max_rice": 2, "max_potato": 2, "min_fish": 1, "veggie_days": 2, "max_red_meat": 2,
                   "repeat_weeks": 3, "no_same_cuisine_row": True}


class Household(Base):
    __tablename__ = "household"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(100))
    plz: Mapped[str] = mapped_column(String(5), default="")
    lat: Mapped[float | None]  # aus der PLZ geocodiert (für kaufDA)
    lng: Mapped[float | None]
    offers_refreshed_at: Mapped[datetime | None]
    persons: Mapped[int] = mapped_column(default=2)
    diet: Mapped[str] = mapped_column(String(30), default="alles")
    allergies: Mapped[list[str]] = mapped_column(JSON, default=list)
    excluded_ingredients: Mapped[list[str]] = mapped_column(JSON, default=list)
    cuisines: Mapped[list[str]] = mapped_column(JSON, default=list)
    meal_types: Mapped[list[str]] = mapped_column(JSON, default=lambda: ["mittag", "abend"])
    plan_days: Mapped[list[int]] = mapped_column(JSON, default=lambda: [0, 1, 2, 3, 4, 5, 6])
    budget_food_week_cents: Mapped[int] = mapped_column(default=6000)
    budget_drugstore_cents: Mapped[int | None]
    nutrition_goal: Mapped[str] = mapped_column(String(30), default="ausgewogen")
    max_cook_minutes: Mapped[int] = mapped_column(default=45)
    radius_km: Mapped[int] = mapped_column(default=5, server_default="5")  # Umkreis für die Ladensuche
    step_images: Mapped[bool] = mapped_column(default=True, server_default=true())  # KI-Schritt-Bilder (9), nur mit FAL_KEY
    variety: Mapped[dict] = mapped_column(JSON, default=dict, server_default="{}")  # Abwechslungsregeln (12), fehlende Schlüssel = VARIETY_DEFAULT
    storage_space: Mapped[str] = mapped_column(String(10), default="mittel", server_default="mittel")  # Vorratsplatz (31): klein|mittel|gross
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())

    members: Mapped[list["Member"]] = relationship(back_populates="household")
    stores: Mapped[list["HouseholdStore"]] = relationship(back_populates="household", cascade="all, delete-orphan")


class Member(Base):
    __tablename__ = "member"

    id: Mapped[int] = mapped_column(primary_key=True)
    household_id: Mapped[int] = mapped_column(ForeignKey("household.id"))
    name: Mapped[str] = mapped_column(String(50))
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    role: Mapped[str] = mapped_column(String(10), default="member")
    push_enabled: Mapped[bool] = mapped_column(default=True, server_default=true())
    plan_prompt_enabled: Mapped[bool] = mapped_column(default=True, server_default=true())
    plan_prompt_weekday: Mapped[int] = mapped_column(default=6, server_default="6")  # 0 = Montag
    plan_prompt_time: Mapped[str] = mapped_column(String(5), default="18:00", server_default="18:00")
    quiet_hours: Mapped[dict | None] = mapped_column(JSON, default=lambda: dict(QUIET_DEFAULT))  # None = keine
    lunchbox_push: Mapped[str | None] = mapped_column(String(5))  # „Lunchbox für morgen vorbereiten“ um HH:MM, None = aus (24)

    household: Mapped[Household] = relationship(back_populates="members")
    profile: Mapped["MemberProfile | None"] = relationship(cascade="all, delete-orphan")
    devices: Mapped[list["PushDevice"]] = relationship(cascade="all, delete-orphan")
    tokens: Mapped[list["MemberToken"]] = relationship(cascade="all, delete-orphan")
    pairing_codes: Mapped[list["PairingCode"]] = relationship(cascade="all, delete-orphan")


class MemberToken(Base):
    """Zusätzliches Token desselben Mitglieds, z.B. für die Teilen-Erweiterung (Kopplungscode, E48); widerrufbar."""
    __tablename__ = "member_token"

    id: Mapped[int] = mapped_column(primary_key=True)
    member_id: Mapped[int] = mapped_column(ForeignKey("member.id"), index=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    label: Mapped[str] = mapped_column(String(50), default="Teilen-Erweiterung")
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())


class PairingCode(Base):
    """6-stelliger Kopplungscode (E48): 10 min gültig, einmal einlösbar. Klartext, weil kurzlebig und rate-limitiert."""
    __tablename__ = "pairing_code"

    id: Mapped[int] = mapped_column(primary_key=True)
    member_id: Mapped[int] = mapped_column(ForeignKey("member.id"), index=True)
    code: Mapped[str] = mapped_column(String(6), unique=True)
    expires_at: Mapped[datetime]
    used_at: Mapped[datetime | None]


class AiCost(Base):
    """Kostenprotokoll für KI-Aufrufe außerhalb der Pläne (Import, Scan, Vorschläge, Schritt-Bilder). Cent (USD), Bruchteile."""
    __tablename__ = "ai_cost"

    id: Mapped[int] = mapped_column(primary_key=True)
    household_id: Mapped[int | None] = mapped_column(ForeignKey("household.id"), index=True)
    kind: Mapped[str] = mapped_column(String(20))  # import | scan | cook_now | step_image
    model: Mapped[str] = mapped_column(String(60), default="")
    cost_cents: Mapped[float]
    info: Mapped[str] = mapped_column(String(200), default="")
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())


class PushDevice(Base):
    """iPhone für Apple Push (E52); token = APNs-Gerätetoken (hex)."""
    __tablename__ = "push_device"

    id: Mapped[int] = mapped_column(primary_key=True)
    member_id: Mapped[int] = mapped_column(ForeignKey("member.id"), index=True)
    token: Mapped[str] = mapped_column(String(200), unique=True)
    environment: Mapped[str] = mapped_column(String(12))  # development | production
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    last_ok: Mapped[datetime | None]  # letzte angenommene Zustellung


class PushOutbox(Base):
    """In der Ruhezeit verschobener Push, der Scheduler sendet ihn ab send_at (E52)."""
    __tablename__ = "push_outbox"

    id: Mapped[int] = mapped_column(primary_key=True)
    member_id: Mapped[int] = mapped_column(ForeignKey("member.id"), index=True)
    title: Mapped[str] = mapped_column(String(200))
    message: Mapped[str] = mapped_column(String(1000))
    click_url: Mapped[str | None] = mapped_column(String(200))
    thread_id: Mapped[str] = mapped_column(String(40), default="essenapp")
    category: Mapped[str | None] = mapped_column(String(40))
    send_at: Mapped[datetime]  # UTC ohne Zeitzone (wie job_run.ran_at)


class MemberProfile(Base):
    """Ziele pro Person (48). eats = {meal_type: [Mo..So]} → isst an dem Slot mit."""
    __tablename__ = "member_profile"

    id: Mapped[int] = mapped_column(primary_key=True)
    member_id: Mapped[int] = mapped_column(ForeignKey("member.id"), unique=True)
    emoji: Mapped[str] = mapped_column(String(16), default="🙂")
    goal: Mapped[str] = mapped_column(String(20), default="ausgewogen")  # ausgewogen|proteinreich|kalorienarm|eigenes
    kcal: Mapped[int] = mapped_column(default=2000)
    protein_g: Mapped[int] = mapped_column(default=80)
    allergies: Mapped[list[str]] = mapped_column(JSON, default=list)
    dislikes: Mapped[list[str]] = mapped_column(JSON, default=list)
    lunchbox_days: Mapped[list[int]] = mapped_column(JSON, default=list)
    eats: Mapped[dict[str, list[bool]]] = mapped_column(JSON, default=dict)


class PantryItem(Base):
    """Vorratskammer (60). Basics: amount None = vorhanden, 0 = leer gemeldet."""
    __tablename__ = "pantry_item"

    id: Mapped[int] = mapped_column(primary_key=True)
    household_id: Mapped[int] = mapped_column(ForeignKey("household.id"), index=True)
    name: Mapped[str] = mapped_column(String(100))
    ingredient_key: Mapped[str] = mapped_column(String(100))  # normalize.ingredient_key(name)
    amount: Mapped[float | None]  # None = Menge unbekannt, gilt als vorhanden
    unit: Mapped[str] = mapped_column(String(10), default="")  # g, ml, stk oder leer
    best_before: Mapped[date | None]
    is_basic: Mapped[bool] = mapped_column(default=False)
    source: Mapped[str] = mapped_column(String(10), default="manual")  # manual | list | scan | barcode | rest
    location: Mapped[str | None] = mapped_column(String(15))  # kuehlschrank | vorrat | gefrierfach (69), None = offen
    updated_at: Mapped[datetime] = mapped_column(default=datetime.now, onupdate=datetime.now)


class WeeklyBasic(Base):
    """Frühstück & Snacks (23a): kommt jede Woche mit der Wochenmenge auf die Haushaltsliste (Quelle basics)."""
    __tablename__ = "weekly_basic"

    id: Mapped[int] = mapped_column(primary_key=True)
    household_id: Mapped[int] = mapped_column(ForeignKey("household.id"), index=True)
    name: Mapped[str] = mapped_column(String(100))
    amount: Mapped[float | None]  # Wochenmenge, None = „1×“ ohne Menge (z.B. Brot)
    unit: Mapped[str] = mapped_column(String(10), default="")  # g, ml, stk oder leer


class HouseholdStore(Base):
    __tablename__ = "household_store"

    id: Mapped[int] = mapped_column(primary_key=True)
    household_id: Mapped[int] = mapped_column(ForeignKey("household.id"))
    chain: Mapped[str] = mapped_column(String(30))
    store_ref: Mapped[str] = mapped_column(String(50), default="")  # Filial-ID, leer = regional
    store_name: Mapped[str] = mapped_column(String(100), default="")
    # z.B. "node/123" (OpenStreetMap) oder "kaufda/edeka/EDEKA-RR_10008482"
    osm_id: Mapped[str] = mapped_column(String(60), default="", server_default="")
    lat: Mapped[float | None]  # Filial-Koordinaten (kaufDA oder OpenStreetMap)
    lng: Mapped[float | None]
    address: Mapped[str] = mapped_column(String(200), default="", server_default="")
    enabled: Mapped[bool] = mapped_column(default=True)

    household: Mapped[Household] = relationship(back_populates="stores")


class Ingredient(Base):
    __tablename__ = "ingredient"

    id: Mapped[int] = mapped_column(primary_key=True)
    slug: Mapped[str] = mapped_column(String(60), unique=True)
    name: Mapped[str] = mapped_column(String(100))
    category: Mapped[str] = mapped_column(String(30), default="sonstiges")


class Offer(Base):
    __tablename__ = "offer"
    __table_args__ = (UniqueConstraint("chain", "store_ref", "source_id", "valid_from"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    chain: Mapped[str] = mapped_column(String(30), index=True)
    store_ref: Mapped[str] = mapped_column(String(50), default="")
    source_id: Mapped[str] = mapped_column(String(100))
    title: Mapped[str] = mapped_column(String(200))
    brand: Mapped[str] = mapped_column(String(100), default="")
    category: Mapped[str] = mapped_column(String(30), default="sonstiges", index=True)
    price_cents: Mapped[int]
    regular_price_cents: Mapped[int | None]
    amount: Mapped[float | None]  # Menge in `unit`, z.B. 400 (g)
    unit: Mapped[str] = mapped_column(String(10), default="")  # g, ml, stk
    base_price_cents: Mapped[int | None]  # pro kg, l oder Stück
    ean: Mapped[str] = mapped_column(String(14), default="")
    valid_from: Mapped[date]
    valid_to: Mapped[date]
    image_url: Mapped[str] = mapped_column(String(500), default="")
    bonus_cents: Mapped[int | None]  # Rewe-Bonus-Guthaben je Packung (39), aus dem Prospekttext
    ingredient_id: Mapped[int | None] = mapped_column(ForeignKey("ingredient.id"))
    product_id: Mapped[int | None] = mapped_column(ForeignKey("product.id"), index=True)  # Preisverlauf (28)
    raw: Mapped[dict] = mapped_column(JSON, default=dict)
    fetched_at: Mapped[datetime] = mapped_column(server_default=func.now())


class Recipe(Base):
    __tablename__ = "recipe"

    id: Mapped[int] = mapped_column(primary_key=True)
    household_id: Mapped[int | None] = mapped_column(ForeignKey("household.id"))
    title: Mapped[str] = mapped_column(String(200))
    description: Mapped[str] = mapped_column(String(500), default="")
    cuisine: Mapped[str] = mapped_column(String(30), default="")
    meal_type: Mapped[str] = mapped_column(String(20))
    servings: Mapped[int]
    prep_minutes: Mapped[int]
    # shortcut: Zutaten als JSON [{name, amount, unit, offer_id}] statt eigener Tabelle; umbauen, sobald Zutaten-Stammdaten (Nährwerte) da sind
    ingredients: Mapped[list[dict]] = mapped_column(JSON, default=list)
    steps: Mapped[list[str]] = mapped_column(JSON, default=list)
    source: Mapped[str] = mapped_column(String(10), default="ai")  # ai | user | instagram | web | shared
    source_url: Mapped[str] = mapped_column(String(500), default="", server_default="")
    source_author: Mapped[str] = mapped_column(String(100), default="", server_default="")  # z.B. "@koch_xy"
    tags: Mapped[list[str]] = mapped_column(JSON, default=list, server_default="[]")
    image_url: Mapped[str] = mapped_column(String(500), default="")
    # KI-Bild je Schritt (9): "/media/steps/<id>/<n>.jpg" oder "" = noch keins; Länge kann < steps sein
    step_images: Mapped[list[str]] = mapped_column(JSON, default=list, server_default="[]")
    share_code: Mapped[str | None] = mapped_column(String(16), unique=True)  # Link /r/<code> (56)
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())


class RecipeFavorite(Base):
    """Favorit gilt für den ganzen Haushalt (3); member_id = wer das Herz gesetzt hat."""
    __tablename__ = "recipe_favorite"
    __table_args__ = (UniqueConstraint("household_id", "recipe_id"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    household_id: Mapped[int] = mapped_column(ForeignKey("household.id"), index=True)
    recipe_id: Mapped[int] = mapped_column(ForeignKey("recipe.id"), index=True)
    member_id: Mapped[int] = mapped_column(ForeignKey("member.id"))
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())


class Rating(Base):
    """Bewertung nach „Gekocht ★“ (3), eine Zeile pro Kochen."""
    __tablename__ = "rating"

    id: Mapped[int] = mapped_column(primary_key=True)
    recipe_id: Mapped[int] = mapped_column(ForeignKey("recipe.id"), index=True)
    member_id: Mapped[int] = mapped_column(ForeignKey("member.id"))
    stars: Mapped[int]  # 1–5
    again: Mapped[str] = mapped_column(String(12))  # bald | irgendwann | nie
    note: Mapped[str] = mapped_column(String(500), default="")
    cooked_at: Mapped[datetime] = mapped_column(default=datetime.now)


class MealPlan(Base):
    __tablename__ = "meal_plan"

    id: Mapped[int] = mapped_column(primary_key=True)
    household_id: Mapped[int] = mapped_column(ForeignKey("household.id"), index=True)
    week: Mapped[str] = mapped_column(String(8))  # ISO-Woche "2026-W45"
    total_cents: Mapped[int] = mapped_column(default=0)  # Einkauf an der Kasse
    saved_cents: Mapped[int] = mapped_column(default=0)
    params: Mapped[dict] = mapped_column(JSON, default=dict)  # Snapshot der Einstellungen
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())

    entries: Mapped[list["MealPlanEntry"]] = relationship(cascade="all, delete-orphan", order_by="MealPlanEntry.day")


class MealPlanEntry(Base):
    __tablename__ = "meal_plan_entry"

    id: Mapped[int] = mapped_column(primary_key=True)
    plan_id: Mapped[int] = mapped_column(ForeignKey("meal_plan.id"))
    day: Mapped[int]  # 0 = Montag
    meal_type: Mapped[str] = mapped_column(String(20))
    recipe_id: Mapped[int] = mapped_column(ForeignKey("recipe.id"))
    cost_cents: Mapped[int] = mapped_column(default=0)  # anteilige Kosten für dieses Gericht
    locked: Mapped[bool] = mapped_column(default=False)
    # Esser des Slots (48): [{member_id, factor}]; Rezeptmengen gelten für portions_total Portionen
    portions: Mapped[list[dict]] = mapped_column(JSON, default=list, server_default="[]")
    portions_total: Mapped[float] = mapped_column(default=0, server_default="0")
    # Mengenfaktor für eingesetzte Rezepte (3): Zutatenmenge im Plan = Rezeptmenge × scale (KI-Gerichte: 1)
    scale: Mapped[float] = mapped_column(default=1, server_default="1")
    guests: Mapped[int] = mapped_column(default=0, server_default="0")  # Gäste (15), in portions_total enthalten

    recipe: Mapped[Recipe] = relationship()


class Invite(Base):
    """Einladungscode für den Haushalt (mehrfach nutzbar bis expires_at)."""
    __tablename__ = "invite"

    id: Mapped[int] = mapped_column(primary_key=True)
    household_id: Mapped[int] = mapped_column(ForeignKey("household.id"), index=True)
    code: Mapped[str] = mapped_column(String(16), unique=True)
    expires_at: Mapped[datetime]
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())


class ShoppingList(Base):
    __tablename__ = "shopping_list"

    id: Mapped[int] = mapped_column(primary_key=True)
    household_id: Mapped[int | None] = mapped_column(ForeignKey("household.id"), index=True)
    name: Mapped[str] = mapped_column(String(100))
    kind: Mapped[str] = mapped_column(String(10), default="household")  # household | oneoff
    share_code: Mapped[str | None] = mapped_column(String(16), unique=True)  # nur oneoff: Gast-Link
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())

    items: Mapped[list["ShoppingItem"]] = relationship(cascade="all, delete-orphan", order_by="ShoppingItem.id")


class ShoppingItem(Base):
    __tablename__ = "shopping_item"

    id: Mapped[int] = mapped_column(primary_key=True)
    list_id: Mapped[int] = mapped_column(ForeignKey("shopping_list.id"), index=True)
    name: Mapped[str] = mapped_column(String(100))
    amount: Mapped[float | None]
    unit: Mapped[str] = mapped_column(String(10), default="")
    chain: Mapped[str] = mapped_column(String(30), default="")
    offer_id: Mapped[int | None]  # kein FK: alte Angebote dürfen gelöscht werden
    checked: Mapped[bool] = mapped_column(default=False)
    added_by: Mapped[str] = mapped_column(String(50), default="")  # Mitglied oder Gast
    checked_by: Mapped[str] = mapped_column(String(50), default="")
    source: Mapped[str] = mapped_column(String(10), default="manual")  # plan | manual | basics | stockup | rhythm
    defer_week: Mapped[str | None] = mapped_column(String(8))  # „Nächste Woche“-Gruppe (30) bis zu dieser ISO-Woche
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())


class JobRun(Base):
    """Scheduler-Protokoll (E47). Ein Lauf zählt ab Start, damit nichts doppelt läuft (auch nach Neustart)."""
    __tablename__ = "job_run"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(40), index=True)  # Job oder "plan_prompt:<member_id>"
    ran_at: Mapped[datetime]  # UTC ohne Zeitzone (wie func.now() in SQLite)
    ok: Mapped[bool] = mapped_column(default=False)
    info: Mapped[str] = mapped_column(String(500), default="")


class Product(Base):
    """Gleiches Produkt über Wochen und Läden (Grundlage 28/30/31): normalisierter Titel + Marke + Menge/Einheit."""
    __tablename__ = "product"

    id: Mapped[int] = mapped_column(primary_key=True)
    key: Mapped[str] = mapped_column(String(320), unique=True)  # prices.product_key()
    title: Mapped[str] = mapped_column(String(200))
    brand: Mapped[str] = mapped_column(String(100), default="")
    amount: Mapped[float | None]
    unit: Mapped[str] = mapped_column(String(10), default="")
    ean: Mapped[str] = mapped_column(String(14), default="", index=True)
    # Open Food Facts (49, ODbL), nur bei sicherem Treffer; off_checked_at gesetzt = schon gesucht
    nutri_score: Mapped[str | None] = mapped_column(String(1))  # a–e
    off_code: Mapped[str] = mapped_column(String(20), default="", server_default="")
    off_bio: Mapped[bool] = mapped_column(default=False, server_default="0")
    off_vegan: Mapped[bool] = mapped_column(default=False, server_default="0")
    off_vegetarian: Mapped[bool] = mapped_column(default=False, server_default="0")
    off_checked_at: Mapped[datetime | None]


class PricePoint(Base):
    """Ein Preis pro Produkt, Laden und ISO-Woche (28)."""
    __tablename__ = "price_point"
    __table_args__ = (UniqueConstraint("product_id", "chain", "store_ref", "week"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    product_id: Mapped[int] = mapped_column(ForeignKey("product.id"), index=True)
    chain: Mapped[str] = mapped_column(String(30))
    store_ref: Mapped[str] = mapped_column(String(50), default="")
    week: Mapped[str] = mapped_column(String(8))  # "2026-W45"
    price_cents: Mapped[int]
    regular_price_cents: Mapped[int | None]
    base_price_cents: Mapped[int | None]
    is_offer: Mapped[bool]  # Rabatt gegenüber regular_price
    valid_from: Mapped[date]
    valid_to: Mapped[date]


class Food(Base):
    """USDA FoodData Central (Foundation + SR Legacy, CC0), Werte pro 100 g (2). id = fdc_id."""
    __tablename__ = "food"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=False)
    description: Mapped[str] = mapped_column(String(300))
    data_type: Mapped[str] = mapped_column(String(20))
    kcal: Mapped[float | None]
    protein: Mapped[float | None]
    fat: Mapped[float | None]
    carbs: Mapped[float | None]
    fiber: Mapped[float | None]
    sugar: Mapped[float | None]
    salt: Mapped[float | None]  # g, aus Natrium × 2,5


class IngredientMap(Base):
    """Deutscher Zutatenname → food (Haiku-Auswahl, einmalig, Cache). food_id None = kein passender Eintrag."""
    __tablename__ = "ingredient_map"

    id: Mapped[int] = mapped_column(primary_key=True)
    ingredient_key: Mapped[str] = mapped_column(String(100), unique=True)  # normalize.ingredient_key
    food_id: Mapped[int | None] = mapped_column(ForeignKey("food.id"))
    grams_per_piece: Mapped[float | None]
    confidence: Mapped[str] = mapped_column(String(10), default="")  # hoch | mittel | niedrig
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())


class WatchItem(Base):
    """Merkliste (27) bzw. Preisalarm für eine Zutat (40), je Haushalt. Verbrauchsrhythmus (58) über lasts_weeks."""
    __tablename__ = "watch_item"

    id: Mapped[int] = mapped_column(primary_key=True)
    household_id: Mapped[int] = mapped_column(ForeignKey("household.id"), index=True)
    kind: Mapped[str] = mapped_column(String(10), default="produkt")  # produkt | zutat
    label: Mapped[str] = mapped_column(String(200))
    brand: Mapped[str] = mapped_column(String(100), default="")
    ean: Mapped[str] = mapped_column(String(14), default="")
    image_url: Mapped[str] = mapped_column(String(500), default="")
    category: Mapped[str] = mapped_column(String(30), default="")  # Angebots-Kategorie, z.B. drogerie
    max_price_cents: Mapped[int | None]  # Wunschpreis „Alarm unter 2,00 €“
    max_base_price_cents: Mapped[int | None]  # Grundpreis-Alarm „unter 7 €/kg“ (40)
    base_unit: Mapped[str] = mapped_column(String(3), default="")  # kg | l | stk (zu max_base_price_cents)
    chains: Mapped[list[str]] = mapped_column(JSON, default=list)  # leer = alle Läden des Haushalts
    lasts_weeks: Mapped[float | None]  # „Hält ca. X Wochen“ (58)
    last_bought: Mapped[date | None]  # automatisch beim Abhaken auf der Liste (58)
    rhythm_push_at: Mapped[date | None]  # „bald leer – gerade im Angebot“ gesendet (einmal je Zyklus)
    rhythm_listed_at: Mapped[date | None]  # „bald leer“ auf die Liste gesetzt (einmal je Zyklus)
    created_by: Mapped[int | None] = mapped_column(ForeignKey("member.id"))
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())

    hits: Mapped[list["WatchHit"]] = relationship(cascade="all, delete-orphan")


class WatchHit(Base):
    """Treffer eines Merklisten-Eintrags; Push höchstens einmal je Eintrag und ISO-Woche (27)."""
    __tablename__ = "watch_hit"
    __table_args__ = (UniqueConstraint("watch_item_id", "offer_id"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    watch_item_id: Mapped[int] = mapped_column(ForeignKey("watch_item.id", ondelete="CASCADE"), index=True)
    offer_id: Mapped[int]  # kein FK: alte Angebote dürfen gelöscht werden
    week: Mapped[str] = mapped_column(String(8))
    notified_at: Mapped[datetime | None]


class Coupon(Base):
    """Coupon-Wallet (38a, 59): Payback/Rewe/dm/Rossmann-Coupon aus Foto, Barcode oder Eingabe – keine Logins (A7)."""
    __tablename__ = "coupon"

    id: Mapped[int] = mapped_column(primary_key=True)
    household_id: Mapped[int] = mapped_column(ForeignKey("household.id"), index=True)
    program: Mapped[str] = mapped_column(String(12), default="sonstige")  # payback | rewe_bonus | dm | rossmann | sonstige
    partner: Mapped[str] = mapped_column(String(50), default="")  # Anzeigename, z.B. „dm“, „Aral“
    chain: Mapped[str] = mapped_column(String(30), default="")  # Laden der App, "" = keiner (z.B. Aral)
    product: Mapped[str] = mapped_column(String(100), default="")  # Produkt/Marke, "" = ganzer Einkauf bzw. Kategorie
    category: Mapped[str] = mapped_column(String(30), default="")  # Angebots-Kategorie, "" = keine
    benefit: Mapped[str] = mapped_column(String(100), default="")  # „10fach Punkte“, „0,50 € Bonus“
    multiplier: Mapped[int | None]  # 10 = 10fach Punkte
    bonus_cents: Mapped[int | None]  # fester Vorteil in Cent (Bonus/Rabatt)
    percent: Mapped[int | None]  # Rabatt in %
    min_spend_cents: Mapped[int | None]
    valid_until: Mapped[date | None]
    code: Mapped[str] = mapped_column(String(200), default="")  # Barcode-Inhalt
    code_type: Mapped[str] = mapped_column(String(10), default="")  # code128 | ean13 | qr | ""
    source: Mapped[str] = mapped_column(String(10), default="manuell")  # foto | barcode | manuell
    expiry_notified_at: Mapped[date | None]  # Ablauf-Push gesendet
    created_by: Mapped[int | None] = mapped_column(ForeignKey("member.id"))
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())


class BonusEntry(Base):
    """Payback-Punkte bzw. Rewe-Bonus-Guthaben (38b): Kontostand = Summe delta. kind plus = „Heute bekommen“ (zählt als
    Ersparnis), minus = eingelöst, set = Korrektur auf einen Wert."""
    __tablename__ = "bonus_entry"

    id: Mapped[int] = mapped_column(primary_key=True)
    household_id: Mapped[int] = mapped_column(ForeignKey("household.id"), index=True)
    program: Mapped[str] = mapped_column(String(12))  # payback (°P) | rewe_bonus (Cent)
    kind: Mapped[str] = mapped_column(String(5))  # plus | minus | set
    delta: Mapped[int]
    note: Mapped[str] = mapped_column(String(100), default="")
    member_id: Mapped[int | None] = mapped_column(ForeignKey("member.id"))
    created_at: Mapped[datetime] = mapped_column(default=datetime.now)


class Purchase(Base):
    """Abgehakter Artikel mit Preis (34, A10): bleibt, auch wenn der Listeneintrag später verschwindet."""
    __tablename__ = "purchase"

    id: Mapped[int] = mapped_column(primary_key=True)
    household_id: Mapped[int] = mapped_column(ForeignKey("household.id"), index=True)
    item_id: Mapped[int | None] = mapped_column(index=True)  # kein FK: Listeneinträge dürfen gelöscht werden
    name: Mapped[str] = mapped_column(String(100))
    amount: Mapped[float | None]
    unit: Mapped[str] = mapped_column(String(10), default="")
    chain: Mapped[str] = mapped_column(String(30), default="")
    category: Mapped[str] = mapped_column(String(30), default="sonstiges")
    offer_id: Mapped[int | None]
    price_cents: Mapped[int]  # ganze Packungen: Angebotspreis, sonst Normalpreis-Schätzung
    saved_cents: Mapped[int] = mapped_column(default=0)  # Streichpreis − Angebotspreis
    estimated: Mapped[bool] = mapped_column(default=False)  # „geschätzt“
    verdict: Mapped[str | None] = mapped_column(String(15))  # Urteil des Angebots beim Kauf (Bestpreis-Jäger, 54)
    source: Mapped[str] = mapped_column(String(10), default="manual")  # wie shopping_item.source (stockup → 54)
    bought_by: Mapped[str] = mapped_column(String(50), default="")
    bought_at: Mapped[datetime] = mapped_column(default=datetime.now, index=True)


class Achievement(Base):
    """Freigeschaltete Medaille (54), genau einmal je Haushalt/Mitglied und Schlüssel. member_id 0 = Haushalt."""
    __tablename__ = "achievement"
    __table_args__ = (UniqueConstraint("household_id", "member_id", "key"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    household_id: Mapped[int] = mapped_column(ForeignKey("household.id"), index=True)
    member_id: Mapped[int] = mapped_column(default=0)
    key: Mapped[str] = mapped_column(String(30))
    unlocked_at: Mapped[datetime] = mapped_column(default=datetime.now)
    seen_at: Mapped[datetime | None]  # Vollbild-Moment gezeigt


class WeekReview(Base):
    """Wochenrückblick (55) als Schnappschuss fürs Archiv."""
    __tablename__ = "week_review"
    __table_args__ = (UniqueConstraint("household_id", "week"),)

    id: Mapped[int] = mapped_column(primary_key=True)
    household_id: Mapped[int] = mapped_column(ForeignKey("household.id"), index=True)
    week: Mapped[str] = mapped_column(String(8))  # "2026-W45"
    data: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(default=datetime.now)
