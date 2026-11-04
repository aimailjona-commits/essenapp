"""API-Vertrag. Die Swift-Modelle (Codable) in ios/ richten sich nach diesen Klassen."""
import math
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


class VarietyRules(BaseModel):
    """Abwechslungsregeln (12), Standardwerte laut Spezifikation. Zählen für Hauptgerichte (mittag/abend/lunchbox)."""
    max_pasta: int = Field(1, ge=0, le=14)
    max_rice: int = Field(2, ge=0, le=14)
    max_potato: int = Field(2, ge=0, le=14)
    min_fish: int = Field(1, ge=0, le=3)  # gilt nicht bei vegetarisch/vegan oder Fisch-Allergie/-Abneigung
    veggie_days: int = Field(2, ge=0, le=7)  # Tage, an denen alle Hauptgerichte vegetarisch/vegan sind
    max_red_meat: int = Field(2, ge=0, le=14)
    repeat_weeks: int = Field(3, ge=1, le=12)  # gleiches Gericht frühestens nach N Wochen
    no_same_cuisine_row: bool = True  # gleiche Küche nicht an zwei Tagen hintereinander


class VarietyUpdate(BaseModel):
    """Nur genannte Regeln ändern (PATCH /household {"variety": {...}})."""
    max_pasta: int | None = Field(None, ge=0, le=14)
    max_rice: int | None = Field(None, ge=0, le=14)
    max_potato: int | None = Field(None, ge=0, le=14)
    min_fish: int | None = Field(None, ge=0, le=3)
    veggie_days: int | None = Field(None, ge=0, le=7)
    max_red_meat: int | None = Field(None, ge=0, le=14)
    repeat_weeks: int | None = Field(None, ge=1, le=12)
    no_same_cuisine_row: bool | None = None


class ProductRule(BaseModel):
    """„Immer use statt instead“ (19.2), z.B. Hafermilch statt Milch."""
    instead: str = Field(min_length=1, max_length=60)
    use: str = Field(min_length=1, max_length=60)


class HouseholdSettings(BaseModel):
    name: str | None = None
    plz: str | None = Field(None, pattern=r"^\d{5}$")
    persons: int | None = Field(None, ge=1, le=20)
    diet: str | None = None
    allergies: list[str] | None = None
    excluded_ingredients: list[str] | None = None
    product_rules: list[ProductRule] | None = Field(None, max_length=30)
    cuisines: list[str] | None = None
    meal_types: list[str] | None = None
    plan_days: list[int] | None = None
    budget_food_week_cents: int | None = Field(None, ge=0)
    budget_drugstore_cents: int | None = Field(None, ge=0)
    nutrition_goal: str | None = None
    max_cook_minutes: int | None = Field(None, ge=5)
    radius_km: int | None = Field(None, ge=1, le=30)
    step_images: bool | None = None  # Schalter „Schritt-Bilder erzeugen (ca. 2 Cent/Rezept)“ (9)
    variety: VarietyUpdate | None = None  # Abwechslungsregeln (12)
    storage_space: Literal["klein", "mittel", "gross"] | None = None  # Vorratsplatz für Vorratskauf-Tipps (31)
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
    product_rules: list[ProductRule]
    cuisines: list[str]
    meal_types: list[str]
    plan_days: list[int]
    budget_food_week_cents: int
    budget_drugstore_cents: int | None
    nutrition_goal: str
    max_cook_minutes: int
    radius_km: int
    step_images: bool  # Schalter (Standard an); wirkt nur, wenn step_images_available
    variety: VarietyRules  # Abwechslungsregeln (12), immer vollständig
    storage_space: str  # klein | mittel | gross (31)
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
    subcategory: str = ""  # feine Kategorie (19.1), Filter im Angebote-Screen (19.4)
    price_cents: int
    regular_price_cents: int | None
    amount: float | None
    unit: str
    base_price_cents: int | None
    valid_from: date
    valid_to: date
    image_url: str
    # Preisverlauf-Urteil (28) für Badge + Filter „Nur echte Angebote“; null nur in Listen ohne Urteil (top_offers)
    verdict: Literal["bestpreis", "gut", "normal", "kein_echtes", "zu_wenig_daten"] | None = None
    # Nutri-Score, Bio, Vegan (49): lieber kein Badge als ein falsches
    bio: bool = False
    vegan: bool = False
    vegetarian: bool = False
    nutri_score: Literal["A", "B", "C", "D", "E"] | None = None
    label_sources: list[str] = []  # „Prospekttext“, „Open Food Facts (ODbL)“ (Erklärung im Detail)
    off_code: str = ""  # Open-Food-Facts-Barcode des sicheren Treffers → world.openfoodfacts.org/product/<code>
    monthly: bool = False  # dm/Rossmann-Monatsaktion (59)
    bonus_cents: int | None = None  # Rewe-Bonus-Aktion (39): Badge „🎁 0,50 € Bonus“, Filter ?bonus=true


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


class RestBadge(BaseModel):
    name: str  # Zutat
    from_day: int  # „♻︎ Rest von Mo“ (0 = Montag)


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
    guests: int  # Gäste (15), Badge „+4“; in portions_total enthalten
    rests: list[RestBadge] = []  # frische Zutaten aus dem Rest eines früheren Gerichts (19)


class VarietyOut(BaseModel):
    ok: bool  # Chip „✓ Abwechslung“
    issues: list[str]  # sonst „⚠ 2× Pasta“ (erstes Element), alle Verstöße


class LeftoverOut(BaseModel):
    name: str
    amount: float
    unit: str
    until_day: int  # haltbar bis (0 = Montag der Planwoche, ≥ 7 = nächste Woche)
    suggestion: str  # z.B. „Bis Do verbrauchen, z.B. im Frühstück oder als Snack“


class LeftoversOut(BaseModel):
    planned: int  # frische Reste, die ein späteres Gericht verwendet („3 verplant“)
    left: list[LeftoverOut]  # übrig („1 übrig (Sahne 100 ml)“)


class PlanOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    week: str
    total_cents: int
    saved_cents: int
    entries: list[MealOut]
    variety: VarietyOut = VarietyOut(ok=True, issues=[])  # (12), live berechnet
    leftovers: LeftoversOut = LeftoversOut(planned=0, left=[])  # Reste-Karte im Plan-Kopf (19)


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


PlanMeal = Literal["fruehstueck", "mittag", "abend", "snack", "dessert", "lunchbox", "vorspeise"]


class GuestSlot(BaseModel):
    day: Annotated[int, Field(ge=0, le=6)]
    meal_type: PlanMeal
    count: int = Field(ge=0, le=20)


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
    guests: list[GuestSlot] | None = Field(None, max_length=50)  # „+ Gäste“ je Tag/Mahlzeit (15)
    guest_budget_cents: int | None = Field(None, ge=0)  # „Gäste-Budget extra“, sonst aus dem Wochenbudget
    special: str | None = Field(None, max_length=20)  # Special-Vorlage = key aus GET /specials (25)
    next_week: bool = False  # „Plan für nächste Woche“ mit den Vorschau-Angeboten (30)
    single_store: str | None = Field(None, max_length=30)  # „Nur ein Laden“ (41): chain eines gewählten Ladens
    save_as_default: bool = False  # zusätzlich (ohne wishes/guests/special) in den Haushalt schreiben


class CostEntry(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    kind: str  # import | scan | cook_now | step_image | no_mood | substitute | budget | coupon
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
    source: Literal["manual", "stockup"] = "manual"  # stockup = „n× auf die Liste“ (Badge „Vorratskauf“, 31)
    next_week: bool = False  # gleich in die Gruppe „Nächste Woche“ (30)


class ItemUpdate(BaseModel):
    checked: bool | None = None
    name: str | None = Field(None, min_length=1, max_length=100)
    amount: float | None = Field(None, ge=0, le=100000)
    next_week: bool | None = None  # „Auf nächste Woche schieben“ (30) bzw. zurück


class CouponBadge(BaseModel):
    """Coupon-Badge am Listenartikel/Merklisten-Eintrag (38c, 59): „🎟 10fach“ → Coupon antippen = Kassen-Vollbild."""
    id: int
    text: str
    program: str
    partner: str


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
    source: str  # plan | manual | basics | stockup (Badge „Vorratskauf“) | rhythm („bald leer“, 58)
    defer_week: str | None = None  # ISO-Woche der Gruppe „Nächste Woche“ (30)
    coupon: CouponBadge | None = None  # passender aktiver Coupon (38c/59)
    pack_amount: float | None = None  # Packungsgröße (19.5), Einheit = unit

    @computed_field
    @property
    def next_week(self) -> bool:
        """In der Gruppe „Nächste Woche“; ab dieser Woche wieder normal."""
        year, week, _ = date.today().isocalendar()
        return bool(self.defer_week) and self.defer_week > f"{year}-W{week:02d}"

    @computed_field
    @property
    def packs(self) -> int | None:
        """Zu kaufende Packungen („1 × 1,1 kg, 900 g gebraucht“)."""
        return math.ceil(self.amount / self.pack_amount - 1e-9) if self.amount and self.pack_amount else None


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
MealType = Literal["fruehstueck", "mittag", "abend", "snack", "dessert"]
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
    source: Literal["manual", "list", "scan", "barcode", "rest"] = "manual"  # rest = Reste nach dem Kochen (19)
    location: Literal["kuehlschrank", "vorrat", "gefrierfach"] | None = None  # Ort aus dem Kühlschrank-Foto (69)


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
    location: Literal["kuehlschrank", "vorrat", "gefrierfach"] | None = None  # explizit null = kein Ort


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
    location: str | None  # kuehlschrank | vorrat | gefrierfach, null = unbekannt
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
    lunchbox_push: str | None  # „Lunchbox für morgen vorbereiten“ um HH:MM (24), null = aus


class PushSettingsUpdate(BaseModel):
    push_enabled: bool | None = None
    plan_prompt_enabled: bool | None = None
    plan_prompt_weekday: Weekday | None = None
    plan_prompt_time: HHMM | None = None
    quiet_hours: QuietHours | None = None  # explizit null = Ruhezeit aus
    lunchbox_push: HHMM | None = None  # explizit null = aus


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


# --- Clever planen (Phase 11) + Ersatzzutaten (7) ---

class GuestsIn(BaseModel):
    count: int = Field(ge=0, le=20)  # „Gäste hinzufügen“ nachträglich (15), ohne KI


class PostponeIn(BaseModel):
    """„Auf morgen verschieben?“ (16): Rezept auf diesen Tag; spätere Gerichte derselben Mahlzeit rücken einen Tag
    weiter (fixierte bleiben), das letzte fällt aus dem Plan."""
    recipe_id: int
    day: Annotated[int, Field(ge=0, le=6)]
    meal_type: PlanMeal


class NoMoodIn(BaseModel):
    exclude: list[Annotated[str, Field(max_length=200)]] = Field(default_factory=list, max_length=30)  # gezeigte Titel


class EntryLeftover(BaseModel):
    """Erwarteter Rest nach dem Kochen dieses Gerichts (19) → bestätigen → POST /pantry/bulk (source rest)."""
    name: str
    amount: float
    unit: str
    best_before: date | None  # frische Reste: Anbruch + 2–4 Tage, sonst null


class WeeklyBasicIn(BaseModel):
    name: str = Field(min_length=1, max_length=100)
    amount: float | None = Field(None, ge=0, le=100000)  # Wochenmenge, null = ohne Menge (z.B. Brot)
    unit: PantryUnit = ""


class WeeklyBasicUpdate(BaseModel):
    name: str | None = Field(None, min_length=1, max_length=100)
    amount: float | None = Field(None, ge=0, le=100000)
    unit: PantryUnit | None = None


class WeeklyBasicOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    amount: float | None
    unit: str


class SubOffer(BaseModel):
    id: int
    chain: str
    price_cents: int


class SubIngredientOut(BaseModel):
    name: str
    amount: float
    unit: str
    in_pantry: bool  # „im Vorrat“
    offer: SubOffer | None  # „im Angebot“ (günstigstes passendes Angebot der eigenen Läden)


class SubstituteOption(BaseModel):
    note: str  # Wirkung, z.B. „cremiger, weniger flüssig“
    ingredients: list[SubIngredientOut]  # 1–3 Zutaten mit umgerechneter Menge


class SubstitutesOut(BaseModel):
    ingredient: dict  # die ersetzte Zutat {name, amount, unit}
    source: Literal["tabelle", "ki"]
    options: list[SubstituteOption]  # 2–4, nie mit Allergenen/gegen die Ernährungsform


class SubstituteIn(BaseModel):
    ingredients: list[IngredientIn] = Field(min_length=1, max_length=3)  # gewählte Option (Mengen wie geliefert)


class SpecialOut(BaseModel):
    key: str  # für PlanOptions.special
    name: str
    emoji: str
    date: date  # Anlass bzw. Saisonbeginn
    days_until: int
    template: Literal["festtagsmenue", "plaetzchen", "grillparty"]
    template_name: str  # Festtagsmenü | Plätzchen-Back-Plan | Grillparty
    running: bool  # Saison läuft schon


class BannerOut(SpecialOut):
    text: str  # „🎄 Weihnachten in 12 Tagen – Menü planen?“


class HolidayOut(BaseModel):
    date: date
    name: str


class SpecialsOut(BaseModel):
    state: str | None  # Bundesland-Kürzel aus der PLZ
    banner: BannerOut | None  # Start-Banner 14 Tage vorher
    specials: list[SpecialOut]  # alle jetzt passenden Vorlagen
    holidays: list[HolidayOut]  # Feiertage der nächsten 14 Tage
    seasons: list[str]  # z.B. „Spargelzeit“
    produce: list[str]  # Saisonkalender Obst/Gemüse dieses Monats


class GeneratorOut(BaseModel):
    """Plan-Generator nach „Plan erstellen“ (17): Standards des Haushalts + „Diese Woche im Angebot: …“."""
    week: int  # KW, für die geplant wird (ab Freitag die nächste)
    defaults: PlanOptions
    top_offers: list[OfferOut]  # Top-3 Angebote (höchster Rabatt, Lebensmittel)
    banner: BannerOut | None


# --- Sparen (Phase 12) ---

class NextWeekDealOut(BaseModel):
    """Start-Karte „👀 Nächste Woche günstiger“ (30): „Hähnchenbrust nächste Woche −30 % bei Lidl (3,49 € statt 4,99 €)
    – Kauf verschieben?“"""
    name: str
    item_id: int | None  # Listenartikel → POST /items/{id}/next-week; null = aus der Merkliste (→ POST …/items next_week)
    watch_id: int | None
    offer: OfferOut  # Angebot der nächsten Woche
    now_price_cents: int  # heutiger Preis für dieselbe Packung (Angebot, sonst Normalpreis)
    now_chain: str  # "" = Normalpreis ohne Laden
    saving_pct: int  # ≥ 10


class NextWeekIn(BaseModel):
    offer_id: int | None = None  # Angebot der nächsten Woche → Laden/Preis des Artikels (nicht bei Plan-Artikeln)


class StockupOut(BaseModel):
    """Vorratskauf-Tipp (31): „3 Packungen reichen ~6 Wochen, sparst 4,20 €“ → „3× auf die Liste“ (source stockup)."""
    offer: OfferOut
    packs: int
    weeks: float | None  # reicht ~so viele Wochen; null = ohne Verbrauchshistorie (konservativ 2 Packungen)
    weekly_use: float | None  # Packungen pro Woche
    saving_cents: int  # (Normalpreis − Angebotspreis) × packs
    normal_price_cents: int


WatchKind = Literal["produkt", "zutat"]


class WatchIn(BaseModel):
    """Merkliste (27): Herz am Angebot (offer_id), Barcode (ean + Daten aus GET /products/ean/{ean}) oder Freitext;
    Preisalarm für eine Zutat (40): kind zutat + max_price_cents oder max_base_price_cents/base_unit."""
    kind: WatchKind = "produkt"
    offer_id: int | None = None  # füllt label/brand/category/image_url aus dem Angebot
    label: str | None = Field(None, min_length=1, max_length=200)
    brand: str = Field("", max_length=100)
    ean: str = Field("", pattern=r"^(\d{8}|\d{12,14})?$")
    image_url: str = Field("", max_length=500)
    category: str = Field("", max_length=30)
    max_price_cents: int | None = Field(None, ge=1)  # Wunschpreis „Alarm unter 2,00 €“
    max_base_price_cents: int | None = Field(None, ge=1)  # Grundpreis „unter 7 €/kg“
    base_unit: Literal["", "kg", "l", "stk"] = ""
    chains: list[Annotated[str, Field(max_length=30)]] = Field(default_factory=list, max_length=12)  # leer = alle
    lasts_weeks: float | None = Field(None, gt=0, le=104)  # „Hält ca. X Wochen“ (58); null = Vorschlag aus Kategorie
    last_bought: date | None = None

    @model_validator(mode="after")
    def _check(self):
        if self.offer_id is None and not self.label:
            raise ValueError("label oder offer_id fehlt")
        if self.max_base_price_cents is not None and not self.base_unit:
            raise ValueError("base_unit fehlt (kg, l oder stk)")
        return self


class WatchUpdate(BaseModel):
    label: str | None = Field(None, min_length=1, max_length=200)
    brand: str | None = Field(None, max_length=100)
    max_price_cents: int | None = Field(None, ge=1)  # explizit null = kein Wunschpreis
    max_base_price_cents: int | None = Field(None, ge=1)
    base_unit: Literal["", "kg", "l", "stk"] | None = None
    chains: list[Annotated[str, Field(max_length=30)]] | None = Field(None, max_length=12)
    lasts_weeks: float | None = Field(None, gt=0, le=104)  # explizit null = kein Rhythmus
    last_bought: date | None = None


class WatchOut(BaseModel):
    id: int
    kind: str  # produkt | zutat
    label: str
    brand: str
    ean: str
    image_url: str
    category: str
    max_price_cents: int | None
    max_base_price_cents: int | None
    base_unit: str
    chains: list[str]
    lasts_weeks: float | None
    lasts_weeks_suggestion: float | None  # Vorschlag aus Kategorie/Stichwort (58)
    last_bought: date | None
    empty_on: date | None  # last_bought + lasts_weeks
    hits: list[OfferOut]  # aktuelle Treffer (erfüllen den Alarm), günstigste zuerst → „Diese Woche günstig“
    coupon: CouponBadge | None = None  # passender Drogerie-Coupon (59)
    # „zuletzt im Angebot: KW 44“ aus dem Preisverlauf (ISO-Woche „2026-W44“, bis zur laufenden Woche)
    last_offer_week: str | None = None
    last_offer_chain: str | None = None
    last_offer_price_cents: int | None = None


class EanProductOut(BaseModel):
    """Barcode → Open Food Facts (27/49)."""
    ean: str
    found: bool
    name: str
    brand: str
    image_url: str
    nutri_score: str | None  # A–E


class StoreComboOut(BaseModel):
    """Laden-Empfehlung (42): „🏆 Am günstigsten: alles bei Lidl 41,20 € · Rewe+Lidl 38,90 € (2,30 € gespart, +1 Laden)“."""
    chains: list[str]
    total_cents: int  # Summe der offenen Artikel (Angebote + Normalpreise, ganze Packungen)
    per_store: dict[str, int]
    saved_cents: int  # gegenüber dem günstigsten einzelnen Laden
    unpriced: int  # Artikel ohne bekannten Preis (zählen nicht mit)
    distance_km: float | None  # Rundweg Zuhause → Läden → Zuhause (Luftlinie)
    extra_km: float | None  # Weg-Hinweis „+1,2 km“ gegenüber dem günstigsten einzelnen Laden


class AssignIn(BaseModel):
    chains: list[Annotated[str, Field(max_length=30)]] = Field(min_length=1, max_length=2)


class BudgetOver(BaseModel):
    entry_id: int
    day: int
    title: str
    cost_cents: int
    max_cost_cents: int  # Kostengrenze fürs Neu würfeln (POST …/entries/{id}/reroll {max_cost_cents})


class BudgetOut(BaseModel):
    """Budget-Rest-Hinweis (43): state rest (≥ 5 € übrig) → Ideen über POST /plans/current/budget/ideas;
    over → „⚠️ 3,20 € über Budget – günstigere Alternative für Do?“."""
    budget_cents: int
    total_cents: int
    rest_cents: int  # negativ = über Budget
    state: Literal["rest", "over", "ok"]
    over: BudgetOver | None


class BudgetIdeaOut(BaseModel):
    kind: Literal["dessert", "snack", "vorrat"]
    title: str
    cost_cents: int
    recipe: RecipeOut | None  # dessert/snack → einplanen über POST /plans/current/entries
    stockup: StockupOut | None  # vorrat → „auf die Liste“ (POST /lists/{id}/items, source stockup)


class AddEntryIn(BaseModel):
    recipe_id: int
    day: Annotated[int, Field(ge=0, le=6)]
    meal_type: PlanMeal


class RerollIn(BaseModel):
    max_cost_cents: int | None = Field(None, ge=0)  # Kostengrenze (43, „günstigere Alternative“)
    direction: Literal["schneller", "guenstiger", "ohne_fleisch", "leichter", "anders"] | None = None  # 19.3
    wish: str = Field("", max_length=200)  # eigener Wunsch („mit Reis“)


# --- Payback & Rewe Bonus (38), Drogerie-Coupons (59) ---

Program = Literal["payback", "rewe_bonus", "dm", "rossmann", "sonstige"]
CouponCategory = Literal["", "fleisch_fisch", "obst_gemuese", "kuehlung", "vorrat", "getraenke", "drogerie", "haushalt",
                         "sonstiges"]
CodeType = Literal["", "code128", "ean13", "ean8", "qr"]


class CouponFields(BaseModel):
    partner: str = Field("", max_length=50)  # „dm“, „REWE“, „Aral“
    program: Program = "sonstige"
    chain: str = Field("", max_length=30)  # Laden der App; "" = keiner (beim Foto aus partner abgeleitet)
    product: str = Field("", max_length=100)  # Produkt/Marke, "" = ganzer Einkauf bzw. Kategorie
    category: CouponCategory = ""
    benefit: str = Field("", max_length=100)  # „10fach Punkte“, „0,50 € Bonus“, „20 % Rabatt“
    multiplier: int | None = Field(None, ge=1, le=100)
    bonus_cents: int | None = Field(None, ge=1, le=100000)
    percent: int | None = Field(None, ge=1, le=100)
    min_spend_cents: int | None = Field(None, ge=1)
    valid_until: date | None = None


class CouponIn(CouponFields):
    code: str = Field("", max_length=200)  # Barcode-Inhalt (VisionKit)
    code_type: CodeType = ""
    source: Literal["foto", "barcode", "manuell"] = "manuell"


class CouponUpdate(BaseModel):
    """Nur genannte Felder; multiplier/bonus_cents/percent/min_spend_cents/valid_until dürfen null werden."""
    partner: str | None = Field(None, max_length=50)
    program: Program | None = None
    chain: str | None = Field(None, max_length=30)
    product: str | None = Field(None, max_length=100)
    category: CouponCategory | None = None
    benefit: str | None = Field(None, max_length=100)
    multiplier: int | None = Field(None, ge=1, le=100)
    bonus_cents: int | None = Field(None, ge=1, le=100000)
    percent: int | None = Field(None, ge=1, le=100)
    min_spend_cents: int | None = Field(None, ge=1)
    valid_until: date | None = None
    code: str | None = Field(None, max_length=200)
    code_type: CodeType | None = None


class CouponOut(CouponIn):
    model_config = ConfigDict(from_attributes=True)

    id: int
    badge: str  # „🎟 10fach“
    expired: bool  # → grau unter „Abgelaufen“
    days_left: int | None  # bis valid_until, null = unbegrenzt
    created_at: datetime


class CouponScanOut(CouponFields):
    """Gelesene Felder (nicht gespeichert) → Prüfen → POST /coupons (source foto)."""
    cost_cents: float


class BonusAccountOut(BaseModel):
    """Karte „Payback: 1.240 °P (≈ 12,40 €)“ bzw. „Rewe Bonus: 8,50 €“ (38b)."""
    program: Literal["payback", "rewe_bonus"]
    name: str
    unit: Literal["punkte", "cent"]
    balance: int  # °P bzw. Cent
    value_cents: int  # Payback: 1 °P ≈ 1 ct
    earned_month_cents: int  # diesen Monat gutgeschrieben (Ersparnis „Bonus“)


class BonusIn(BaseModel):
    """Plus/Minus-Sheet: delta (+60 °P „Heute bekommen“, −500 eingelöst) oder set (Kontostand korrigieren)."""
    delta: int | None = Field(None, ge=-10_000_000, le=10_000_000)
    set: int | None = Field(None, ge=0, le=10_000_000)
    note: str = Field("", max_length=100)

    @model_validator(mode="after")
    def _one(self):
        if (self.delta is None) == (self.set is None) or self.delta == 0:
            raise ValueError("genau eins von delta (≠ 0) oder set angeben")
        return self


# --- Monats-Dashboard (34) ---

class PurchaseOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    amount: float | None
    unit: str
    chain: str
    category: str
    price_cents: int
    saved_cents: int
    estimated: bool  # „geschätzt“ (Normalpreis-Schätzung)
    bought_at: datetime  # Zeitpunkt des Abhakens
    bought_by: str


class WeekSum(BaseModel):
    week: str  # "2026-W45"
    total_cents: int


class ChainSum(BaseModel):
    chain: str  # "" = ohne Laden
    total_cents: int


class CategorySum(BaseModel):
    category: str
    total_cents: int


class SpendingOut(BaseModel):
    month: str  # "2026-11"
    total_cents: int
    estimated_cents: int  # davon geschätzt
    budget_cents: int  # (Lebensmittel- + Drogerie-Wochenbudget) × Tage / 7 (Ring)
    saved_cents: int  # Angebote
    bonus_cents: int  # Bonus (38b, gutgeschrieben)
    weeks: list[WeekSum]  # Balken pro Woche (alle Wochen des Monats)
    stores: list[ChainSum]  # Torte pro Laden
    categories: list[CategorySum]  # Torte pro Kategorie
    top: list[PurchaseOut]  # Top 5 teuerste
    prev_total_cents: int
    change_pct: float | None  # gegenüber Vormonat, null ohne Vormonat
    items: list[PurchaseOut]  # alle Käufe des Monats, neueste zuerst


# --- Erfolge (54) ---

class AchievementOut(BaseModel):
    key: str  # z.B. gespart_50, budget_4, protein_7
    group: Literal["sparen", "gesundheit"]
    emoji: str
    title: str
    target: int
    progress: float  # gedeckelt auf target (Fortschrittsring)
    unit: Literal["cent", "wochen", "angebote", "tipps", "tage", "pflanzen"]
    unlocked_at: datetime | None  # null = gesperrt (grau)
    new: bool  # freigeschaltet, Vollbild-Moment noch nicht gezeigt → danach POST /achievements/seen


class SeenIn(BaseModel):
    keys: list[Annotated[str, Field(max_length=30)]] = Field(min_length=1, max_length=50)


# --- Wochenrückblick (55) ---

class ReviewFavorite(BaseModel):
    recipe_id: int
    title: str
    image_url: str
    stars: int


class ReviewCooking(BaseModel):
    cooked: int  # „Gekocht ★“ in der Woche
    planned: int  # Gerichte im Plan der Woche
    favorite: ReviewFavorite | None  # beste Bewertung


class ReviewMoney(BaseModel):
    spent_cents: int
    estimated_cents: int
    saved_cents: int
    bonus_cents: int
    budget_cents: int
    budget_ok: bool


class ReviewHealth(BaseModel):
    member_id: int
    name: str
    emoji: str
    avg_kcal: int
    kcal_goal: int
    avg_protein: int
    protein_goal: int
    plants: int  # verschiedene Pflanzen der Woche


class ReviewPantry(BaseModel):
    rests_used: int  # frische Reste in Folgegerichten verplant (19)
    rests_left: int  # übrig gebliebene frische Reste
    thrown_away: int | None  # null = wird nicht erfasst


class ReviewAchievement(AchievementOut):
    member_id: int  # 0 = Haushalt


class ReviewDeal(BaseModel):
    offer_id: int
    title: str
    chain: str
    image_url: str
    price_cents: int
    regular_price_cents: int
    saving_pct: int


class WeekReviewOut(BaseModel):
    """Story-Seiten: 1 cooking, 2 money, 3 health, 4 pantry, 5 achievements, 6 next_week (+ „Plan erstellen“)."""
    week: str
    kw: int
    start: date
    end: date
    created_at: datetime
    cooking: ReviewCooking
    money: ReviewMoney
    health: list[ReviewHealth]
    pantry: ReviewPantry
    achievements: list[ReviewAchievement]
    next_week: list[ReviewDeal]


class ReviewSummary(BaseModel):
    week: str
    kw: int
    created_at: datetime
    spent_cents: int
    cooked: int


# --- Rezepte zwischen Haushalten teilen (56) ---

class RecipeShareOut(BaseModel):
    code: str
    url: str  # https://<server>/r/<code> (Web-Ansicht für alle)
    app_url: str  # essenapp://import-recipe/<code>


class SharedRecipeOut(BaseModel):
    """Vorschau ohne Login (App nach Deep-Link): übernehmen mit POST /shared-recipes/{code}/import."""
    code: str
    title: str
    description: str
    image_url: str
    servings: int
    prep_minutes: int
    ingredients: list[dict]
    steps: list[str]
    from_household: str  # „Familie Müller“ → Quelle „von Familie Müller“
