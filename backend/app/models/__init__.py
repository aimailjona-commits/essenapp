from datetime import date, datetime

from sqlalchemy import JSON, ForeignKey, String, UniqueConstraint, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.db import Base

# Geld immer in Cent (int), nie float.


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

    household: Mapped[Household] = relationship(back_populates="members")


class HouseholdStore(Base):
    __tablename__ = "household_store"

    id: Mapped[int] = mapped_column(primary_key=True)
    household_id: Mapped[int] = mapped_column(ForeignKey("household.id"))
    chain: Mapped[str] = mapped_column(String(30))
    store_ref: Mapped[str] = mapped_column(String(50), default="")  # Filial-ID, leer = regional
    store_name: Mapped[str] = mapped_column(String(100), default="")
    osm_id: Mapped[str] = mapped_column(String(30), default="", server_default="")  # z.B. "node/123"
    lat: Mapped[float | None]  # Filial-Koordinaten aus OpenStreetMap
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
    source: Mapped[str] = mapped_column(String(10), default="ai")  # ai | user | import
    image_url: Mapped[str] = mapped_column(String(500), default="")
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())


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

    recipe: Mapped[Recipe] = relationship()
