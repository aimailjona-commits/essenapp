from datetime import date, datetime

from sqlalchemy import JSON, ForeignKey, String, UniqueConstraint, func, true
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.db import Base

# Geld immer in Cent (int), nie float.

QUIET_DEFAULT = {"start": "22:00", "end": "07:00"}  # Ruhezeit für Pushes (Europe/Berlin)


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

    household: Mapped[Household] = relationship(back_populates="members")
    profile: Mapped["MemberProfile | None"] = relationship(cascade="all, delete-orphan")
    devices: Mapped[list["PushDevice"]] = relationship(cascade="all, delete-orphan")


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
    source: Mapped[str] = mapped_column(String(10), default="manual")  # manual | list | scan | barcode
    updated_at: Mapped[datetime] = mapped_column(default=datetime.now, onupdate=datetime.now)


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
    source: Mapped[str] = mapped_column(String(10), default="manual")  # plan | manual | basics
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
