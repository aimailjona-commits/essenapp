# Essenapp – alle Funktionen nach Kern-Objekt (Stand v8 / Phase 21)

Quelle: `docs/features/README.md`, `docs/ui/screens.md`, `docs/ui/redesign-v8.md`, Views in `ios/Sources/Essenapp/`.
Spalte „heute“ = wo man die Funktion in v8 findet. **Fett** = heute schwer zu finden (nur über Einstellungen, langes Drücken oder ganz unten auf einer Seite).

## 1 Gericht (Rezept, Plan-Gericht)

| Funktion | Feature | heute | Swift |
|---|---|---|---|
| Rezept ansehen (Teller, Zeit, Preis, Zutaten, Schritte) | – | S3 aus Start/Woche/Rezepte | `RecipeDetailView`, `SavedRecipeView` |
| Kochmodus mit Schritten, mehreren Timern, Sprachsteuerung | 4, 8 | S3 ▶ | `CookingView`, `TimerBar`, `VoicePill` |
| Bewerten (Sterne, „Wieder kochen?“, Notiz) | 3 | S3 unten „Gekocht – bewerten“ | `RatingSheet` |
| Reste in den Vorrat | 19 | nach Bewerten | `RestsConfirmView`, `LeftoversCard` |
| Merken / Favorit (Herz) | 3 | S3 Kopf, S2 Aktionen | `HeartButton`, `PlateHeart` |
| Diese Woche einplanen | 3 | S3 bei gespeicherten Rezepten | `PlanSlotSheet` (S19) |
| Tauschen / neu würfeln / fixieren | – | S2 Tag, 2×2-Knöpfe | `RerollDialog`, `DayMealRow` |
| **Mag ich nicht** (nie wieder vorschlagen) | 12 | **nur im Würfel-Dialog / Bewertung „Nie“** | `DislikeDialog` |
| Zutaten auf die Einkaufsliste | – | indirekt über Plan | – |
| Zutat → passende Angebote | 1 | S3 Zutat antippen | `IngredientOffersSheet` |
| **Ersatzzutat finden** | 7 | **Zutat lange drücken** | `SubstituteSheet` (S26) |
| **Preisalarm für Zutat** | 40 | **Zutat lange drücken** | `WatchSheet` |
| Nährwerte + Zusammensetzungs-Blüte, „Für: Person“ | 2, 48 | S3 Mitte | `ShareBloom`, `DetailBloom`, `PersonPicker` |
| Portionen ändern | – | S3 Stepper | `Stepper8` |
| Als Bild teilen | 10 | S3 Teilen-Menü | `ShareCardSheet`, `RecipeShareCard` |
| Als Link teilen / geteiltes Rezept öffnen | 56 | S3 Teilen-Menü / Deep-Link | `RecipeLinkSheet`, `SharedRecipeSheet` |
| Original-Reel (Instagram-Import) | 5, 9 | S3 Quelle-Chip | `StepImage` |
| Rezept anlegen / bearbeiten / löschen | 3 | Schnell-Aktionen, S12 „+“, S3 „…“ | `RecipeFormSheet` (S17) |
| **Rezept aus Link / Instagram importieren** | 5 | **S12 Link-Knopf, Teilen-Erweiterung, Einstellungen** | `RecipeLinkSheet`, `InstagramShareView` |
| Meine Rezepte (Filter Favoriten/Eigene/Importiert/Im Angebot/Zuletzt) | 3 | Tab Rezepte | `RecipesTab`, `MyRecipesList` |

## 2 Woche / Plan

| Funktion | Feature | heute | Swift |
|---|---|---|---|
| Wochenplan ansehen, Tag im Detail | – | Tab Woche | `WeekPlanView`, `DayDetailView` |
| Plan erstellen („Überrasch mich“, KI) | – | Schnell-Aktionen, Start leer | `PlanGeneratorSheet` (S7) |
| Woche per Swipe planen (Stapel → Match → Auswahl → verteilen) | Ph. 20 | „Woche planen“ auf S1/S2 | `SwipeView`, `MatchView`, `SwipeSelection`, `SwipeWeek` |
| Keine Lust? (schnell, ohne Einkauf) | 16 | S1 unter Heute, S2 heute | `NoMoodSheet` (S27) |
| Gäste für einen Tag | 15 | S2 Gericht-Badge | `GuestsSheet` (S28) |
| Abwechslungsregeln + Chip „✓ Abwechslung“ | 12 | **Einstellungen › Präferenzen**, S2 Chip | `VarietyView`, `VarietyChip` |
| Reste-Planung | 19 | S2 Karte „Reste“ | `LeftoversCard` |
| Frühstück & Snacks / Wochen-Basics | 23 | **Einstellungen** | `WeeklyBasicsView` (S29) |
| Lunchbox Arbeit | 24 | **Mein Profil** | `ProfileView` |
| Festtags-/Saison-Specials | 25 | Start-Banner, Generator „Mehr Optionen“ | `SpecialBanner` |
| Auto-Wochenplan „erst nachfragen“ | 17 | Push | `NotificationsView` |
| Tageswerte pro Person | 2, 48 | S2 Tag unten | `DayValues`, `DayNutritionCard` |
| **Kühlschrank-Foto → Vorrat → „Was koche ich jetzt?“** | 69 | **Schnell-Aktionen (hinter „+“)** | `FridgeScanSheet`, `CookNowView` (S23–S25) |

## 3 Angebot

| Funktion | Feature | heute | Swift |
|---|---|---|---|
| Angebote je Laden/Kategorie, Suche, Filter (echt, Bio, Vegan, Nutri, Bonus) | 49, 39 | Tab Angebote | `OffersView`, `OfferRow8` |
| Angebote „Für dich“ | Ph. 20 | S4 oben | `OffersView` |
| Angebotsdetail: Preis, Normalpreis, gültig bis | – | S9 | `OfferDetailView` |
| Preisverlauf + Urteil (Bestpreis …) | 28 | S9 | `PriceHistoryCard` |
| Vorratskauf-Tipp | 31 | S9, S1 Spar-Tipps | `StockupTip`, `StockupCard` |
| Nährwerte / Bio / Nutri-Score | 2, 49 | S9 | `OfferNutritionCard`, `LabelsInfoCard` |
| Merken (Merkliste mit Alarm) | 27 | S9 Herz, S10 | `WatchListView`, `WatchSheet` |
| Auf die Einkaufsliste | – | S9 Knopf | – |
| Rezepte damit („Passt zu“) | – | S9 unten | `MiniOffer` |
| Nächste Woche (Prospekt-Vorschau) | 30 | S4 Pille, S1 Spar-Tipp | `NextWeekCard`, `NextWeekSheet` |
| **Barcode scannen** | 27 | **Schnell-Aktionen, S10 unten** | `BarcodeScanView`, `ScanResultSheet` |
| Lieblingsrezepte im Angebot | 3 | S1 Karte, S12 | `FavoriteDealsCard`, `DealsRow` |
| dm/Rossmann Monatsaktionen | 59 | S4 Kategorie Drogerie | `OffersView` |

## 4 Einkauf

| Funktion | Feature | heute | Swift |
|---|---|---|---|
| Einkaufsliste pro Laden, abhaken, offline | 66 | Tab Einkauf | `ShoppingView`, `ShoppingListView`, `ItemRow` |
| Artikel per Text / Sprache hinzufügen | 45 | S5 Feld + Mikro | `AddItemField`, `VoiceAddOverlay` |
| Einmalige Listen | – | S5 | `OneOffListView` |
| Ein-Laden-Modus / Laden-Empfehlung „Am günstigsten“ | 41, 42 | S5 | `StoreAdviceCard`, `StoreAdviceRows` |
| Budget-Rest-Hinweis | 43 | S1 Spar-Tipps | `BudgetHintCard` |
| Verbrauchsrhythmus Drogerie („bald leer“) | 58 | S5 Badge | `ItemRow` |
| Vorrat (Haltbarkeit, hinzufügen) | 60 | S5 Pille „Vorrat“ | `PantryView`, `PantryAddSheet` (S16) |
| Coupons, Payback/Rewe-Bonus, Kasse | 38 | S5 Pille „Coupons“ | `CouponWalletView`, `CouponCheckoutView`, `BonusSheet` |
| **Standort-Erinnerung im Laden** | 36 | **Einstellungen** | `StoreReminderCard` |
| Live-Aktivität beim Einkaufen | 37 | Sperrbildschirm | `LiveActivityGallery` |
| Ersparnis | – | S1 Zahl | `SavingsView` (S11) |
| **Ausgaben / Monats-Dashboard** | 34 | **S1 weit unten, Einstellungen** | `SpendingView` (S32) |
| Läden & Umkreis (Karte) | – | Onboarding, S4 Kopf, Einstellungen | `StoreMapView` (S14) |

## 5 Ich / Familie

| Funktion | Feature | heute | Swift |
|---|---|---|---|
| Mein Profil: Ziel, Tagesziel, Allergien, Mag ich nicht, isst mit | 48 | **Avatar › Einstellungen** | `ProfileView` (S15) |
| Familie: Mitglieder, Einladungslink | – | **Einstellungen** | `FamilySection` |
| Haushalt-Präferenzen (Ernährung, Küchen, Budget, Mahlzeiten) | – | **Einstellungen** | `PreferencesView` |
| Erfolge (Sparen, Gesundheit) | 54 | **Einstellungen › Mein Profil** | `AchievementsView` (S34) |
| Wochenrückblick + Archiv | 55 | S1 weit unten, Push | `ReviewStoryView`, `ReviewArchiveView` (S35) |
| Benachrichtigungen (APNs, Ruhezeit, Lunchbox-Erinnerung) | – | **Einstellungen** | `NotificationsView` |
| Widget „Heute“ einrichten (Kopplung) | 65 | **Einstellungen › Geräte** | `WidgetGallery` (S38/S39) |
| Erscheinungsbild Hell/Dunkel | 68 | Einstellungen | `SettingsView` |
| Abo / Paywall | 19.8 | bei 402 | `PaywallSheet` |
| Onboarding inkl. Gewohnheiten | Ph. 20 | erster Start, Einstellungen | `OnboardingView` (S46) |

## Befund

- 5 Kern-Objekte, ~70 Funktionen. Davon ~15 nur über Einstellungen, langes Drücken oder das „+“ erreichbar (fett).
- Gleiche Objekte haben je nach Ort andere Aktionen: Gericht auf Start = ▶ + Keine Lust; in der Woche = Herz/Tauschen/Schloss/Würfel; im Rezept = Teilen/Bewerten/Einplanen; im Swipe = mag ich / nicht. „Mag ich nicht“ und „Auf die Liste“ fehlen fast überall.
- Angebot: Merken/Liste/Rezepte nur im Detail S9, nicht in der Zeile.
