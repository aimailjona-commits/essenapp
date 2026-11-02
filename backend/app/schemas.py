"""API-Vertrag. Die Swift-Modelle (Codable) in ios/ richten sich nach diesen Klassen."""
from datetime import date

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
