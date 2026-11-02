"""API-Vertrag. Die Swift-Modelle (Codable) in ios/ richten sich nach diesen Klassen."""
from datetime import date, datetime
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, HttpUrl, computed_field, model_validator

from app.core.config import settings


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
    step_images: bool | None = None  # Schalter „Schritt-Bilder erzeugen (ca. 2 Cent/Rezept)“ (9)
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
    step_images: bool  # Schalter (Standard an); wirkt nur, wenn step_images_available
    stores: list[StoreOut]

    @computed_field
    @property
    def step_images_available(self) -> bool:
        """FAL_KEY im Backend gesetzt → Schalter „Schritt-Bilder“ anzeigen."""
        return bool(settings.fal_key)


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


class NutritionOut(BaseModel):
    """Pro Portion (1 Portion = Esser mit 2000 kcal/Tag); pro Person = × factor aus portions (2)."""
    kcal: float
    protein: float
    carbs: float
    fat: float
    fiber: float


class CompositionItem(BaseModel):
    name: str
    grams: float  # pro Portion
    share: float  # Gewichtsanteil 0–1, Summe = 1


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
    image_url: str  # extern (https://…) oder relativ zum Backend (/media/recipes/<id>.jpg?v=…)
    source: str  # ai | user | instagram | web | shared
    source_url: str
    source_author: str
    tags: list[str]
    favorite: bool = False  # Favorit des Haushalts
    nutrition: NutritionOut | None = None  # null = Zuordnung läuft noch
    composition: list[CompositionItem] | None = None  # Blüten-Diagramm, null wie nutrition
    # KI-Bild je Schritt (9), gleich lang wie steps: "/media/steps/<id>/<n>.jpg" oder "" = (noch) keins
    step_images: list[str] = []

    @model_validator(mode="after")
    def _pad_step_images(self):
        self.step_images = [*self.step_images, *[""] * len(self.steps)][:len(self.steps)]
        return self


class Portion(BaseModel):
    member_id: int
    factor: float  # kcal-Ziel / 2000, auf 0,25 gerundet


class MealOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    day: int
    meal_type: str
    cost_cents: int
    locked: bool
    recipe: RecipeOut
    portions: list[Portion]  # Esser dieses Gerichts (48); leer bei alten Plänen
    portions_total: float  # Rezeptmengen gelten für so viele Portionen; 0 = alter Plan → recipe.servings
    scale: float  # Menge im Plan = Rezeptmenge × scale (eingesetzte Rezepte, 3); KI-Gerichte 1


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


class CostEntry(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    kind: str  # import | scan | cook_now | step_image
    model: str
    cost_cents: float
    info: str
    created_at: datetime


class UsageOut(BaseModel):
    plans: int
    cost_cents_total: float  # geschätzte KI-Kosten in Cent (Pläne + Kostenprotokoll)
    cost_cents_last: float  # letzter Plan
    by_kind: dict[str, float]  # plan, import, scan, cook_now, step_image
    recent: list[CostEntry]  # Kostenprotokoll, neueste 20


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
    source: str  # plan | manual | basics


class ListOut(BaseModel):
    id: int
    name: str
    kind: str
    share_url: str | None
    items: list[ItemOut]


class ItemPatchOut(ItemOut):
    pantry_suggest: bool = False  # nach Abhaken: „In den Vorrat?“ standardmäßig ja (haltbare Sachen)


# --- Ziele pro Person (48) ---

GOALS = Literal["ausgewogen", "proteinreich", "kalorienarm", "eigenes"]
MealType = Literal["fruehstueck", "mittag", "abend", "dessert"]
Weekday = Annotated[int, Field(ge=0, le=6)]
Tag = Annotated[str, Field(min_length=1, max_length=50)]


class MemberProfileOut(BaseModel):
    member_id: int
    name: str
    emoji: str
    goal: str
    kcal: int
    protein_g: int
    allergies: list[str]
    lunchbox_days: list[int]
    eats: dict[str, list[bool]]  # {meal_type: [Mo..So]}


class ProfileOut(MemberProfileOut):
    dislikes: list[str]


class ProfileUpdate(BaseModel):
    name: str | None = Field(None, min_length=1, max_length=50)
    emoji: str | None = Field(None, min_length=1, max_length=16)
    goal: GOALS | None = None
    kcal: int | None = Field(None, ge=1000, le=5000)
    protein_g: int | None = Field(None, ge=0, le=400)
    allergies: list[Tag] | None = Field(None, max_length=20)
    dislikes: list[Tag] | None = Field(None, max_length=50)
    lunchbox_days: list[Weekday] | None = Field(None, max_length=7)
    eats: dict[MealType, Annotated[list[bool], Field(min_length=7, max_length=7)]] | None = None  # nur genannte Mahlzeiten


# --- Vorratskammer (60) ---

PantryUnit = Literal["", "g", "ml", "stk"]


class PantryIn(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    amount: float | None = Field(None, ge=0, le=100000)
    unit: PantryUnit = ""
    best_before: date | None = None
    is_basic: bool = False
    source: Literal["manual", "list", "scan", "barcode"] = "manual"


class ScanItem(BaseModel):
    """Erkanntes Lebensmittel (69), noch nicht gespeichert. confidence niedrig → im Prüf-Bildschirm vorab abgewählt."""
    name: str
    amount: float | None
    unit: PantryUnit
    location: Literal["kuehlschrank", "vorrat", "gefrierfach"]
    category: str  # obst_gemuese | fleisch_fisch | kuehlung | vorrat | getraenke | sonstiges
    confidence: Literal["hoch", "mittel", "niedrig"]
    best_before: date | None  # nur bei Frischem: geschätzte Haltbarkeit


class ScanOut(BaseModel):
    items: list[ScanItem]
    cost_cents: float


class MissingIngredient(BaseModel):
    name: str
    amount: float
    unit: str


class PantryUpdate(BaseModel):
    name: str | None = Field(None, min_length=1, max_length=100)
    amount: float | None = Field(None, ge=0, le=100000)
    unit: PantryUnit | None = None
    best_before: date | None = None
    is_basic: bool | None = None


class PantryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    ingredient_key: str
    amount: float | None  # Basics: null = vorhanden, 0 = leer gemeldet
    unit: str
    best_before: date | None
    is_basic: bool
    source: str
    updated_at: datetime


class ConsumeIn(BaseModel):
    """Entweder entry_id (Plan-Gericht, ganze Menge) oder recipe_id mit servings_factor."""
    entry_id: int | None = None
    recipe_id: int | None = None
    servings_factor: float = Field(1, gt=0, le=20)


# --- Push (Apple Push, E52) + Scheduler (E47) ---

HHMM = Annotated[str, Field(pattern=r"^([01]\d|2[0-3]):[0-5]\d$")]  # Europe/Berlin


class DeviceIn(BaseModel):
    token: str = Field(pattern=r"^[0-9a-fA-F]{64,200}$")  # APNs-Gerätetoken (hex)
    environment: Literal["development", "production"]  # Debug-Build → development (Sandbox)


class QuietHours(BaseModel):
    start: HHMM
    end: HHMM  # darf vor start liegen (über Mitternacht)


class PushSettings(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    push_enabled: bool
    plan_prompt_enabled: bool
    plan_prompt_weekday: int  # 0 = Montag … 6 = Sonntag
    plan_prompt_time: str
    quiet_hours: QuietHours | None  # null = keine Ruhezeit


class PushSettingsUpdate(BaseModel):
    push_enabled: bool | None = None
    plan_prompt_enabled: bool | None = None
    plan_prompt_weekday: Weekday | None = None
    plan_prompt_time: HHMM | None = None
    quiet_hours: QuietHours | None = None  # explizit null = Ruhezeit aus


# --- Preisverlauf (28) ---

class PricePointOut(BaseModel):
    week: str  # "2026-W45"
    chain: str
    price_cents: int
    regular_price_cents: int | None
    is_offer: bool


class LastLow(BaseModel):
    week: str
    chain: str
    price_cents: int


class OfferHistoryOut(BaseModel):
    points: list[PricePointOut]  # letzte 12 Wochen, je Woche+Kette der günstigste Preis
    median_cents: int | None
    min_cents: int | None
    verdict: Literal["bestpreis", "gut", "normal", "kein_echtes", "zu_wenig_daten"]
    last_low: LastLow | None  # „Zuletzt so günstig: KW 38 bei Lidl (1,79 €)“
    avg_interval_weeks: float | None  # „Im Schnitt alle 5 Wochen im Angebot“


# --- Meine Rezepte (3) ---

RecipeUnit = Literal["g", "kg", "ml", "l", "stk", "el", "tl", "prise"]  # kg/l werden zu g/ml
Again = Literal["bald", "irgendwann", "nie"]


class IngredientIn(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    amount: float = Field(ge=0, le=100000)
    unit: RecipeUnit


class RecipePatch(BaseModel):
    title: str | None = Field(None, min_length=1, max_length=200)
    description: str | None = Field(None, max_length=500)
    servings: int | None = Field(None, ge=1, le=20)
    prep_minutes: int | None = Field(None, ge=1, le=600)
    cuisine: str | None = Field(None, max_length=30)
    meal_type: MealType | None = None
    ingredients: list[IngredientIn] | None = Field(None, max_length=60)
    steps: list[Annotated[str, Field(min_length=1, max_length=1000)]] | None = Field(None, max_length=40)
    tags: list[Tag] | None = Field(None, max_length=20)
    image: str | None = Field(None, max_length=3_000_000)  # Base64-JPEG, max. 2 MB


class RecipeIn(RecipePatch):
    title: str = Field(min_length=1, max_length=200)
    servings: int = Field(ge=1, le=20)
    prep_minutes: int = Field(ge=1, le=600)
    meal_type: MealType
    ingredients: list[IngredientIn] = Field(min_length=1, max_length=60)
    steps: list[Annotated[str, Field(min_length=1, max_length=1000)]] = Field(default_factory=list, max_length=40)


class RecipeCard(BaseModel):
    id: int
    title: str
    image_url: str
    cuisine: str
    meal_type: str
    prep_minutes: int
    servings: int
    source: str
    source_author: str
    favorite: bool
    avg_stars: float | None
    last_cooked: datetime | None
    cost_per_serving_cents: int  # live aus aktuellen Angeboten
    offer_share: float  # Anteil der Kosten aus aktuellen Angeboten 0–1, Badge ab 0,4


class RatingIn(BaseModel):
    stars: int = Field(ge=1, le=5)
    again: Again
    note: str = Field("", max_length=500)
    cooked_at: datetime | None = None  # Standard: jetzt


class RatingOut(BaseModel):
    id: int
    member_id: int
    member_name: str
    stars: int
    again: str
    note: str
    cooked_at: datetime


class RecipeDetail(RecipeOut):
    avg_stars: float | None
    last_cooked: datetime | None
    cost_per_serving_cents: int
    offer_share: float
    ratings: list[RatingOut]


class CostLineOut(BaseModel):
    name: str
    amount: float
    unit: str
    cost_cents: int  # Verbrauchskosten der Menge
    offer_id: int | None
    chain: str
    in_offer: bool
    priced: bool  # false = kein Preis bekannt


class RecipeCostOut(BaseModel):
    cost_cents: int
    cost_per_serving_cents: int
    offer_share: float
    lines: list[CostLineOut]


class FavoriteOut(BaseModel):
    favorite: bool


class ReplaceIn(BaseModel):
    recipe_id: int


# --- Nährwerte (2) ---

class MemberDayNutrition(NutritionOut):
    member_id: int
    complete: bool  # false = mindestens ein Gericht noch ohne Zuordnung


class DayNutrition(BaseModel):
    day: int
    members: list[MemberDayNutrition]


class MemberGoal(BaseModel):
    member_id: int
    name: str
    emoji: str
    kcal_goal: int
    protein_goal: int
    avg_kcal: float  # Wochenschnitt über die Plan-Tage
    avg_protein: float


class PlanNutritionOut(BaseModel):
    members: list[MemberGoal]
    days: list[DayNutrition]


class OfferNutritionOut(BaseModel):
    """Nährwerte im Angebotsdetail (2): nur bei sicherer Zuordnung (confidence hoch)."""
    status: Literal["ok", "pending", "none"]  # pending = Zuordnung läuft, später erneut abrufen
    food: str  # USDA-Eintrag (englisch)
    per_100g: NutritionOut | None
    per_pack: NutritionOut | None  # Packung laut Angebot (g/ml bzw. Stück mit bekanntem Gewicht)


# --- Kopplungscode für die Teilen-Erweiterung (E48) ---

class PairingCodeOut(BaseModel):
    code: str  # 6 Ziffern
    expires_at: datetime  # 10 min, einmal einlösbar


class PairIn(BaseModel):
    code: str = Field(pattern=r"^\d{6}$")
    label: str = Field("Teilen-Erweiterung", min_length=1, max_length=50)


class PairOut(HouseholdCreated):
    member_id: int
    member_name: str


class PairedTokenOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    label: str
    created_at: datetime


# --- Rezept-Import (5), Schritt-Bilder (9), „Was koche ich jetzt?“ (69) ---

class ImportIn(BaseModel):
    url: HttpUrl  # Instagram-Beitrag/Reel oder Webseite mit Rezept
    text: str = Field("", max_length=10000)  # Text aus dem Teilen-Menü, falls Instagram ihn mitgibt


class StepImagesOut(BaseModel):
    step_images: list[str]  # wie RecipeOut.step_images
    pending: bool  # Erzeugung läuft im Hintergrund → später erneut abrufen


class CookIdeaOut(BaseModel):
    recipe: RecipeOut  # gespeichert (source ai) → Rezeptdetail, „Heute kochen“ über …/replace
    missing: list[MissingIngredient]  # höchstens 2, „Zur Liste“
