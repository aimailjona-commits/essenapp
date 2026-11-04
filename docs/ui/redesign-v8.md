# Redesign v8 „Tinte & Bogen“ – Bauanleitung (1:1)

Freigegeben vom Nutzer am 2026-11-04 („gefällt mir perfekt … 1:1 genau so umbauen“, E98). Löst v3 (`redesign-v3.md`, Phase 18) ab.
Aufgaben: [`docs/tasks/phase-21-redesign-v8.md`](../tasks/phase-21-redesign-v8.md).

**Vorlage ist der HTML-/CSS-Code der Mockups, nicht nur das Bild.** Maße, Farben, Schriftgrößen, Abstände und Positionen werden aus dem Mockup-Code übernommen (px = pt).

| Datei | Inhalt |
|---|---|
| `mockups/redesign-v8.html` | Stil-Quelle: Tokens (`:root`), Grundklassen, Nav-Skript, 9 Kern-Screens |
| `mockups/redesign-v8-alle.html` | alle 93 Screens (gebaut aus `v8-parts/a–f.html` + `_extra.html`) |
| `mockups/animationen-v8.html` | 15 Animationen (gebaut aus `v8-parts/anim0–2.html`) |
| `mockups/ill-v7/*.webp` | Illustrationen (Tinte, Pastellblau) → iOS `Resources/ill/` |

## 1 Grundsätze

1. Keine flachen Rechteck-Kacheln über die Seite. Farbe nur als **Pastell-Form, die aus dem Bildschirmrand läuft**: Kreis (`.blob`), Halbkreis, Tor-Bogen (`.arch`), Blatt (`.leaf`), Lasche (`.offer .tab`), Viertelkreis (`.quarter`). **Keine L-Formen.**
2. Inhalte als **Zeilen mit Haarlinie** (`.irow`, `.offer`, `.hr`), nicht als Karten.
3. **Große Zahlen** in Inter Tight mit Haarlinie darüber, Label links oben (`.stat`).
4. Pastellblau ist die Hauptfarbe, Farben gedämpft. Tinte `#151515` für Text, Knöpfe, aktive Chips.
5. Illustrationen sind Tuschezeichnungen (`ill/`), keine Emojis als Bildersatz, keine Fotos außer Gericht-Tellern (`.plate`).
6. Nav: nur Icons, Leiste mit **Mulde**, aktives Symbol schwebt im blauen Kreis.
7. Bewegung erzählt mit den Zeichnungen, kurz (0,2–0,6 s), federt leicht, entfällt bei „Bewegung reduzieren“. Kein drehender Kreis – lange Aktionen nutzen den **Topf-Lader**.
8. Logos: echte Händler-Logos (Wikimedia, nur verlinkt, E44) auf weißem Kreis.

## 2 Tokens (`Theme.swift`)

### Farben (hell)

| Token | Hex | CSS |
|---|---|---|
| `bg` | `#F3EEE4` | `--bg` Seitengrund |
| `card` | `#FBF8F2` | `--card` Felder, Teller-Rand, Sheet-Innenflächen |
| `ink` | `#151515` | `--ink` Text 1, Knöpfe, aktive Chips |
| `ink2` | `#7C776D` | `--ink2` Text 2, Labels |
| `ink3` | `#B9B3A7` | `--ink3` Text 3, inaktiv, Griff |
| `line` | `#DCD5C7` | `--line` Haarlinien, Ränder |
| `blue` | `#AFC4F2` | `--blue` Hauptfarbe, aktive Nav-Mulde, `.btn.blue` |
| `blue1` | `#DCE5F8` | `--blue1` helle Pastell-Formen, `.soft` |
| `blue3` | `#7C9BE6` | `--blue3` Akzent in Grafiken |
| `sage` | `#CFE3D2` | `--sage` Form/„ok“ |
| `rose` | `#F2CFC8` | `--rose` Form |
| `sand` | `#E7DCC5` | `--sand` Form |
| `warn` | `#F6E2B8` | `.warn` |
| `deal` | `#E0603F` | `--deal` Rabatt-Pille |
| `scrim` | `#151515` 32 % | `.scrim` |

Dunkelmodus: erst Mockup → Freigabe (Phase 21.2), dann Werte hier ergänzen. Bis dahin ist die App fest hell.

### Schrift

| Token | Schrift | Gebrauch |
|---|---|---|
| `F.serif(size)` | DM Serif Display 400 | `.t1` 34/1.1, `.t2` 24/1.12, Zeilen-Namen 19, Tage 19, Titel bis 46 |
| `F.text(size, weight)` | Manrope 500/600/700/800 | Grundtext 600; `.small` 15/600, `.lbl` 11/800 +0.08em, `.sec2` 13/800 +0.06em, Knöpfe 16/800 |
| `F.num(size)` | Inter Tight 600 (500 wo im Mockup) | `.num`, Laufweite −0.05em, Zeilenhöhe 0.92 |

Feste Schnitte per `ios/tools/make_fonts.py` (Quelle: google/fonts, OFL). Dynamic Type über `relativeTo`.

### Formen, Maße

| Was | Wert |
|---|---|
| Seitenrand | 24 (`.scr` padding 66 oben, 24 seitlich, 120 unten über der Nav) |
| Haarlinie | 1.5 |
| `.btn` | Höhe 56, Kapsel, 16/800; `.btn2` 52, Rand 1.5 Tinte, 15/800 |
| `.field` | 52, Kapsel, `card`, Rand 1.5 `line` |
| `.chip` | 36, Kapsel, Rand 1.5 `line`, 14/700; an: Tinte, weiß |
| `.pill` | 30, Tinte, 13/700; `.deal` 22, 11/800; `.soft` 24, `blue1`, 12/800 |
| `.seg` | Kapsel, Rand 1.5, Innen-Pillen 34 |
| `.sw` Schalter | 50 × 30 |
| `.stepper` | 40, Knöpfe 30 |
| `.x` Schließen | 40, Rand 1.5 `line` |
| `.sheet` | Radius 36 oben, Griff 40 × 5, Padding 12/24/40 |
| `.irow` | Höhe 60, Kreis 48 (Bild 40), Name serif 19 |
| `.ck` Haken | 26, Rand 2 `ink3`; an: Tinte |
| `.offer` | Höhe 138, Lasche 150 × 112, Radius 56 links, rechts 24 aus dem Rand |
| `.plate` | Kreis-Foto, Rand 6 `card`, Schatten y 14 / Blur 30 / 16 % |
| `.toast` | Tinte, Kapsel, 14/700, 130 über unten |
| `.bar` | 8, Kapsel; `.prog` Striche 4 |
| Nav | 120 hoch, Mulde: Tab-Mitten x = 39 + 78·i, T = 34, R = 38; aktiv 58er Kreis `blue`, inaktiv `ink3` 44; Schatten y −6 / Blur 14 / 7 % |
| Icons | Strich 1.8, rund (Mockup-SVG-Symbole `#i-…`, in SwiftUI als SF Symbol nächster Form oder eigener `Shape`) |

## 3 Bausteine (SwiftUI-Namen ↔ CSS)

Einmal bauen in `V8Components.swift`, überall nutzen. Alte v3-Bausteine (`V3Components.swift`, Kassenbon, Ordner, Burst, Grain …) fallen weg, sobald kein Screen sie mehr nutzt.

| Swift | CSS | Hinweis |
|---|---|---|
| `EdgeBlob(shape:color:frame:)` | `.blob` `.arch` `.leaf` `.quarter` `.offer .tab` | Form läuft aus dem Rand: absolut positioniert, Größe/Position wie im Mockup |
| `Ill(_ name:)` | `img.ill` | Illustration aus `Resources/ill/` |
| `Plate(url/image, size)` | `.plate` | Gericht-Kreis |
| `StatNumber(label:value:unit:mute:)` | `.stat` + `.num` | große Zahl mit Haarlinie |
| `ItemRow` | `.irow` | Kreis + Name + Rest |
| `OfferRow` | `.offer` | mit Lasche rechts |
| `CheckCircle` | `.ck` | |
| `PrimaryButton(style: .ink/.blue)` / `OutlineButton` | `.btn` / `.btn2` | |
| `Field`, `Segmented`, `Toggle8`, `Stepper8`, `CloseButton` | `.field` `.seg` `.sw` `.stepper` `.x` | |
| `Chip`, `Pill`, `DealPill`, `SoftPill` | `.chip` `.pill` `.deal` `.soft` | |
| `Sheet8` | `.sheet` + `.scrim` | eigener Sheet-Look (Griff, Radius 36) |
| `Toast8` | `.toast` | |
| `ProgressBar8`, `StepDots` | `.bar` `.prog` `.dots` | |
| `SectionLabel` | `.lbl` / `.sec2` | |
| `Skeleton` | `.sk` | |
| `NotchTabBar` | `.nav` | ersetzt v3-Tab-Leiste |
| `PotLoader(ingredients:)` | `.potld` + `.potdays` | lange Aktionen |
| `Hop3` | `.hop3` | kleiner Lader in Knöpfen/Zeilen |
| `Timeline` / `DayDot` | `.tl` `.day` | Woche |

## 4 Screens: Mockup → Swift → Demo-Fall

Kennung = Kommentar im Mockup-Code (`<!-- S… -->`). Gruppen = Bau-Pakete (je eine Datei-Menge, parallel baubar).

| Gruppe | Mockup | Screens | Swift-Dateien | Demo-Fälle |
|---|---|---|---|---|
| A Start & Planen | `a.html`, Kern S1/S2 | S1 Start (+gescrollt, Leer), Schnell-Aktionen, S2 Woche + Tag, S7 Generator (+Optionen, Laden), S8 Bewertung, S30 Reste, S27 Keine Lust, S28 Gäste, S19 Diese Woche einplanen | `StartView`, `Planning`, `PlanViews`, `Swipe` | start, empty, quick, plan, generator, generating, review?, leftovers, nomood, guests, basics, variety, swipe, match, auswahl, verteilen |
| B Rezepte & Kochen | `b.html`, Kern S3/S18 | S12, S3 (3 Teile + importiert), S17 Formular 1–2, S22 Import (Link, läuft, Ergebnis), S20 Koppeln, S18 Kochen (4), S26 Ersatz, S36/S37 Teilen | `Recipes`, `RecipeForm`, `Import`, `Cooking`, `Substitutes`, `Sharing`, `ShareCard` | recipes, recipe, myrecipe, recipeform, imported, importlink, instagram, cooking, substitute, sharecard, recipelink, sharedrecipe |
| C Angebote | `c.html`, Kern S4 | S4 (+Nächste Woche, Filter, Drogerie, Leer), S14 Läden, S9 (3 Teile), S10 Merkliste (+Sheets), Barcode, Auf Merkliste? | `OffersView`, `Watch`, `PriceHistory`, `IngredientOffers` | offers, nextweek, stores, singlestore, offer, offerstock, watch, scanner |
| D Einkauf & Vorrat | `d.html`, Kern S5 | S5, S5b, Sprache, Offline, S16 (+Sheet), S31 Coupons (b–d), S23 Kühlschrank (Intro, Sucher, Upload), S24, S25, S40 Live-Aktivität | `ShoppingView`, `Pantry`, `VoiceAdd`, `StoreReminder`, `Bonus`, `Fridge`, `LiveShop`, `EssenappShareUI/ShopActivity` | shopping, list, voiceadd, offline, storeask, pantry, wallet, bonus, coupon, couponadd, fridgecam, fridgereview, cooknow, liveactivity |
| E Onboarding & Einstellungen | `e.html`, Kern S6 | S6.1–6.4, S13 (oben/Mitte/unten, Mitteilungen), S15, S29, Abwechslung, Erklär-Sheets, S21 Teilen-Erweiterung, S38/S39 Widget | `Onboarding`, `Settings`, `Profile`, `Preferences`, `WidgetDemo`, `EssenappShareUI/*` (außer ShopActivity), `EssenappWidget` | onboarding, settings, profile, notifications, sharepair, shareimport, shareresult, widgetsetup, widget |
| F Ausgaben & Erfolge | `f.html` | S11 Ersparnis, S32 Ausgaben (3), S34 Erfolge (+Sheet, Neu), S35 Rückblick (Seiten, Archiv), Teilen-Sheet | `Spending`, `Saving`, `Motivation`, `DemoMotivation` | savings, budgetover, spending, achievements, unlock, review, reviews |

Ohne v8-Mockup (nur Tokens und Bausteine umstellen, Layout nicht neu erfinden, als offen melden): `Paywall`, Swipe-Screens (Mockup `swipe-v1.html` im alten Stil).

## 5 Animationen (`animationen-v8.html`)

| Kennung | Wo | Swift |
|---|---|---|
| `plan` Topf-Lader + Tage füllen | S7 Laden, S22 Import, S23 Upload | `PotLoader` |
| `button` Günstiger würfeln (Hop3 → Tausch, Zahl zählt) | S2 Tag, S8 | `Hop3`, Zahl mit `contentTransition(.numericText())` |
| `nav` Mulde gleitet | Tab-Wechsel | `NotchTabBar` (Mulde animiert x) |
| `a1-day` Tag wechseln | S2 | |
| `a1-shop` Abhaken | S5b | |
| `a1-add` Zur Liste | S4/S9 | |
| `a1-dice` Würfeln | S2 | |
| `a1-fav` Merken | S3/S9 | |
| `a1-num` Zahl zählt | Start, Ausgaben | |
| `a2-open` Gericht öffnen | Start/Woche → S3 | `matchedGeometryEffect` |
| `a2-sheet` Sheet | alle Sheets | `Sheet8` |
| `a2-win` Erfolg | S34 Neu | |
| `a2-empty` Leer-Zustand | Leer-Screens | |
| `a2-pull` Ziehen zum Aktualisieren | Angebote | |
| `a2-fridge` Kühlschrank erkennen | S23/S24 | |

Zeiten, Kurven und Wege aus den `@keyframes` des Mockups übernehmen. `@Environment(\.accessibilityReduceMotion)` → keine Bewegung.

## 6 Regeln beim Bau

- Nur Werte aus `Theme.swift` (die Tabellen oben). Kein Hex, keine Zahl direkt in Views – außer Positionen/Größen der Rand-Formen und Illustrationen, die je Screen aus dem Mockup kommen (als benannte Konstante am Screen).
- Jeder Screen 1:1 nach seinem Mockup-Code: Reihenfolge, Texte (Platzhalter durch echte Daten), Abstände, Formen, Illustrationen.
- Fehlt ein Zustand im Mockup (Laden, Fehler, Leer): mit den Bausteinen bauen, die das Mockup für ähnliche Zustände zeigt (Laden → `PotLoader`/`Hop3`/`Skeleton`, Leer → Illustration + `t2` + `.btn`), und in der Phasen-Datei als „ohne Mockup“ vermerken.
- Funktion bleibt: kein Knopf, kein Zustand, keine Aktion der bestehenden App fällt weg. Steht etwas im Mockup, das die App nicht kann (z. B. „+“ an Angebotszeilen), wird es mit vorhandener Logik angebunden oder gemeldet – nicht weggelassen, nicht neu erfunden.
- Tap-Flächen ≥ 44, VoiceOver-Labels für Icon-Knöpfe, Dynamic Type nicht brechen.

## 7 Prüfen

1. `BUILD_DIR=~/build/essenapp-<gruppe> ./build.sh build` in WSL baut fehlerfrei.
2. Commit + Push → CI „iOS Screenshots“ → `gh run download <id> --name screenshots --dir .debug/ci` → `tools/contact_sheet.py` → neben das Mockup-Telefon legen.
3. Abweichung > ein paar pt oder andere Form/Farbe = nicht fertig.
4. Web-PWA (`backend/app/web`) bekommt dieselben Tokens als CSS-Variablen; Prüfung im Browser bei 390 px.
