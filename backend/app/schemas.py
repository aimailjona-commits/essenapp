"""API-Vertrag. Die Swift-Modelle (Codable) in ios/ richten sich nach diesen Klassen."""
from datetime import date
from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field


class StoreIn(BaseModel):
    chain: str
    store_ref: str = ""
    store_name: str = ""
    enabled: bool = True
    osm_id: str = ""
    lat: float | None = None
    lng: float | None = None
    address: str = ""


class StoreOut(StoreIn):
    model_config = ConfigDict(from_attributes=True)


class HouseholdSettings(BaseModel):
    name: str | None = None
    plz: str | None = Field(None, pattern=r"^\d{5}$")
    persons: int | None = Field(None, ge=1, le=20)
    diet: str | None = None
    allergies: list[str] | None = None
    excluded_ingredients: list[str] | None = None
    cuisines: list[str] | None = None
    meal_types: list[str] | None = None
    plan_days: list[int] | None = None
    budget_food_week_cents: int | None = Field(None, ge=0)
    budget_drugstore_cents: int | None = Field(None, ge=0)
    nutrition_goal: str | None = None
    max_cook_minutes: int | None = Field(None, ge=5)
    radius_km: int | None = Field(None, ge=1, le=30)
    stores: list[StoreIn] | None = None


class HouseholdOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    plz: str
    lat: float | None
    lng: float | None
    persons: int
    diet: str
    allergies: list[str]
    excluded_ingredients: list[str]
    cuisines: list[str]
    meal_types: list[str]
    plan_days: list[int]
    budget_food_week_cents: int
    budget_drugstore_cents: int | None
    nutrition_goal: str
    max_cook_minutes: int
    radius_km: int
    stores: list[StoreOut]


class HouseholdCreate(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    member_name: str = Field(min_length=1, max_length=50)


class HouseholdCreated(BaseModel):
    token: str
    household: HouseholdOut


class OfferOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    chain: str
    store_ref: str
    title: str
    brand: str
    category: str
    price_cents: int
    regular_price_cents: int | None
    amount: float | None
    unit: str
    base_price_cents: int | None
    valid_from: date
    valid_to: date
    image_url: str


class RecipeOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    title: str
    description: str
    cuisine: str
    meal_type: str
    servings: int
    prep_minutes: int
    ingredients: list[dict]
    steps: list[str]
    image_url: str


class MealOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    day: int
    meal_type: str
    cost_cents: int
    locked: bool
    recipe: RecipeOut


class PlanOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    week: str
    total_cents: int
    saved_cents: int
    entries: list[MealOut]


class EntryUpdate(BaseModel):
    locked: bool


class NearbyStoreOut(BaseModel):
    osm_id: str
    chain: str
    name: str
    address: str
    lat: float
    lng: float
    distance_km: float


class PlanOptions(BaseModel):
    """Einstellungen nur für diesen Plan (POST /plans). Fehlende Felder = Werte des Haushalts."""
    cuisines: list[str] | None = None
    meal_types: list[str] | None = None
    plan_days: list[Annotated[int, Field(ge=0, le=6)]] | None = None
    budget_food_week_cents: int | None = Field(None, ge=0)
    nutrition_goal: str | None = None
    persons: int | None = Field(None, ge=1, le=20)
    max_cook_minutes: int | None = Field(None, ge=5)
    diet: str | None = None
    wishes: str | None = Field(None, max_length=300)  # Freitext, wird nie gespeichert
    save_as_default: bool = False  # zusätzlich (ohne wishes) in den Haushalt schreiben


class UsageOut(BaseModel):
    plans: int
    cost_cents_total: float  # geschätzte KI-Kosten in Cent
    cost_cents_last: float


# --- Teilen: Einladungen, gemeinsame Einkaufslisten (E40) ---

class InviteOut(BaseModel):
    code: str
    url: str


class ShareOut(BaseModel):
    url: str


class JoinIn(BaseModel):
    member_name: str = Field(min_length=1, max_length=50)


class MemberOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    role: str


class ListCreate(BaseModel):
    name: str = Field(min_length=1, max_length=100)


class ListSummary(BaseModel):
    id: int
    name: str
    kind: str  # household | oneoff
    share_url: str | None
    open_count: int
    total_count: int


class ItemCreate(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    amount: float | None = Field(None, ge=0, le=100000)
    unit: str = Field("", max_length=10)
    chain: str = Field("", max_length=30)
    offer_id: int | None = None


class ItemUpdate(BaseModel):
    checked: bool | None = None
    name: str | None = Field(None, min_length=1, max_length=100)
    amount: float | None = Field(None, ge=0, le=100000)


class ItemOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    amount: float | None
    unit: str
    chain: str
    offer_id: int | None
    checked: bool
    added_by: str
    checked_by: str
    source: str  # plan | manual


class ListOut(BaseModel):
    id: int
    name: str
    kind: str
    share_url: str | None
    items: list[ItemOut]
