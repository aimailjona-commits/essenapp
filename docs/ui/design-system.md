# Design-System

Status: **v2 (E36), vorläufig freigegeben (C)** – im autonomen Modus entschieden (E16–E22), Nutzer kann jederzeit ändern. Mockups in `mockups/`.

Grundidee: hell, warm, ruhig, viel Luft. Das Essen ist die Farbe. Akzent ist ein frisches Limettengrün, Hauptaktionen sind schwarz.

## Farben (v2, E36 – Quelle der Wahrheit: `ios/Sources/Essenapp/Theme.swift`)

| Token | Wert | Verwendung |
|---|---|---|
| `bg` | `#F5F4F0` | Seitenhintergrund |
| `surface` | `#EDECE7` | Flächen, Nebenbuttons, Skeleton |
| `card` | `#FFFFFF` + Haarlinie `line` (Schwarz 6 %) | Karten |
| `text1` / `text2` / `text3` | `#14161A` / `#6E7178` / `#A9ACB2` | Text, 2. Zeile der Überschrift = `text3` |
| `action` | `#14161A` | Primär-Buttons |
| `accent` / `accentSoft` / `accentDeep` | `#22B573` / `#DDF5E8` / `#15804F` | Marke, Auswahl (Tab-Pille), Fortschritt, Ersparnis |
| `highlight` | `#C6F36B` | Limette: „auf der Liste“, Willkommens-Akzent |
| `deal` | `#FF5A36` | Rabatt |
| Nährwerte | kcal `#FF8A3D`, Protein `#FF5A5F`, KH `#3DBE6B`, Fett `#F7B731` | Icons in getönten Quadraten |

Kategorie-Farben (`Theme.hue`): Obst & Gemüse Grün + 🥦, Fleisch & Fisch Tomate + 🥩, Kühlung Himmelblau + 🧀, Vorrat Sonnengelb + 🥫, Getränke Türkis + 🥤, Drogerie Lavendel + 🧴, Haushalt Pink + 🧽, Sonstiges Grau + 🛒. Die Tönung ist der Hintergrund der Produktbilder.
Laden-Farben (`Theme.storeColor`): feste Palette je Kette, keine Markenfarben (E18).

## Dark Mode (Feature 68, ersetzt E15)

Einstellung in S13 › App › „Erscheinungsbild“: **System · Hell · Dunkel** (Standard System). Alle Tokens in `Theme.swift` sind Hell/Dunkel-Paare (`Color(hell, dunkel)` über `UIColor { trait in … }`, keine `.xcassets`); die Teilen-Erweiterung (`ShareTheme.swift`) hat dieselben Paare und folgt dem System. Web-PWA: gleiche Werte über `prefers-color-scheme`.

| Token | Hell | Dunkel |
|---|---|---|
| `bg` | `#F3F3F3` | `#0F0F10` |
| `surface` | `#EAEAEA` | `#2C2C2E` |
| `card` | `#FFFFFF` | `#1C1C1E` |
| `line` | Schwarz 6 % | Weiß 10 % |
| `text1` / `text2` / `text3` | `#111111` / `#8A8A8E` / `#B4B4B8` | `#F5F5F5` / `#A0A0A5` / `#8A8A8E` |
| `action` / `onAction` | `#111111` / Weiß | `#F5F5F5` / `#111111` (helle Pille, dunkle Schrift) |
| `accent` / `deal` / `warning` / `highlight` / Nährwerte / Blüte | unverändert | unverändert (Orange bleibt) |
| `accentSoft` / `accentDeep` | `#FFE9E1` / `#E0461C` | `#3A1E14` / `#FF7A52` |
| `success` / `successSoft` | `#1FA35C` / `#DFF5E8` | `#34C77B` / `#12301F` |
| `danger` | `#E5483B` | `#FF6B5E` |
| `tabInactive` | `#A9ACB2` | `#6C6C70` |
| Nutri-Score A–E (`Theme.C.nutri`) | `#038141` `#85BB2F` `#FECB02` `#EE8100` `#E63E11` | unverändert (Originalfarben); Buchstabe weiß, auf C `onBright` `#111111` |
| `imageBg` (Produktbild-Fläche) | `#F7F7F7` | `#2A2A2D` |
| `heroDark` (Kopf Angebotsdetail, Tab-Leiste ohne Glas) | `#141414` | `#1C1C1E` |
| `scrim` (hinter Schnell-Aktionen) | Schwarz 25 % | Schwarz 55 % |
| `shimmer` (Skeleton) | Weiß 70 % | Weiß 12 % |
| `photoDim` (über Fotos) | – | Schwarz 12 % |
| `plate` (Logo-/Teller-Plättchen) | Weiß | Weiß |
| Kategorie-Tönungen (`Theme.hue`) | wie oben | `#1E3326`, `#3A2420`, `#1E2A3A`, `#3A3320`, `#1A3236`, `#2A2640`, `#3A2030`, `#2C2C2E` |

- Glas-Leiste (Liquid Glass) wird im Dunkeln automatisch dunkel; Fotos leicht abgedunkelt, Händler-Logos auf weißen Plättchen.
- Immer dunkel: Kochmodus (`cookBg`). Immer hell: Bildkarte (ShareCard, Feature 10).
- Weiße Schrift nur auf Orange/Grün/dunklen Köpfen; auf `action` immer `onAction`.

## Animationen (v2)

- Standard-Feder `Theme.spring` (response 0.38, damping 0.78) für alle Zustandswechsel.
- Antippen: `PressableStyle` (Skalierung 0.96). Auswahl: gleitende Pille (`matchedGeometryEffect`) in Tab-Bar und Tagesleiste.
- Listen erscheinen gestaffelt (`.appear(delay:)`), Zahlen mit `.contentTransition(.numericText())`, Symbole mit `.symbolEffect`.
- Laden: Schimmer-Skeleton; Plan-Generator: drehender Teller + Schritt-Häkchen. Haptik (`sensoryFeedback`) bei Auswahl, Haken, Hinzufügen.
- Schatten klein halten (Radius ≤ 12), damit Scrollen flüssig bleibt; Bilder über großen `URLCache`.

## Schrift

System-Schrift **SF Pro** (E22 (C): keine Einbindung nötig, beste Dynamic-Type-Unterstützung). Web-PWA: `-apple-system, "Inter", system-ui`.

| Token | iOS-Textstil (Standardgröße) / Gewicht | Verwendung |
|---|---|---|
| `display` | `.largeTitle` (34) / Heavy, Laufweite −0.8 | Große Überschrift, 2 Zeilen: Zeile 1 `textPrimary`, Zeile 2 `textSecondary` |
| `title` | `.title2` (22) / Heavy | Gericht-Name im Detail |
| `headline` | `.headline` (17) / Bold | Abschnittstitel („Diese Woche“) |
| `body` | `.body` (17) / Regular | Fließtext, Zutaten |
| `callout` | `.subheadline` (15) / Semibold | Karten-Titel, Buttons |
| `caption` | `.footnote` (13) / Medium | Untertitel, Gewicht, „Alle ansehen“ |
| `micro` | `.caption2` (11) / Semibold | Badges, Chip-Werte |
| `number` | wie Kontext, `monospacedDigit` | Preise, Nährwerte |

Textstile statt fester Größen, damit Dynamic Type funktioniert (umgesetzt in `ios/.../Theme.swift`).

## Abstände, Radien, Schatten

- Abstände: `4, 8, 12, 16, 20, 24, 32, 40`. Seitenrand **20**.
- Radien: Chip **14**, Kachel **20**, Karte **28**, große Karte / Sheet **36**, Buttons und Suchfeld **voll rund**.
- Schatten `soft`: y 12, Blur 32, Schwarz 7 %. Schatten `float` (Tab-Bar, schwebende Bilder): y 18, Blur 40, Schwarz 12 %.
- Bilder von Gerichten: freigestellt, rund (Teller von oben), dürfen über den Kartenrand hinausragen (wie Referenz 01).

## Icons

SF Symbols, Strichstärke `regular`, in Buttons `semibold`. Kleine Icons stehen in getönten Quadraten (Radius 10, Farbe mit 14 % Deckkraft).

App-Icon „Kochpilot“ (E88): Papierflieger in Limette `#C6F36B`/`#9FD24A`/`#7FB33A` zieht an weißer Leine ein Preisschild `deal` mit weißem %, Grund `#14161A`. Quelle: `ios/tools/make_icon.py` (schreibt iOS- und PWA-Icon).

## Komponenten

| Name | Beschreibung |
|---|---|
| `DisplayHeader` | Zweizeilige Riesen-Überschrift (schwarz/grau), rechts optional Avatar und Glocke in runden Buttons |
| `SearchField` | Voll rund, `surface`, Lupe links, daneben runder Filter-Button |
| `MealCard` | Hochkant-Karte: Tellerbild ragt oben heraus, Name zentriert, darunter 3 `NutrientStat` und Preis/Portion |
| `NutrientStat` | Icon im getönten Quadrat + Wert (`micro`/`number`) + Bezeichnung |
| `NutrientTile` | Große Kachel für Detailseite (Icon, Wert, Bezeichnung), 3–4 nebeneinander |
| `ShareBloom` | „Blüten“-Diagramm: Gericht in der Mitte, Blütenblätter mit Verlauf zeigen Anteile (Zutaten oder Nährwerte) |
| `OfferCard` | Raster-Karte: Produktbild auf getönter Fläche, `DealBadge` oben links, `AddToListButton` unten rechts, Name, Preis, Grundpreis, Laden-Chip |
| `DealBadge` | Pill mit Rabatt („−30 %“) oder „Angebot“ |
| `StoreChip` | Neutraler Pill mit Händlername |
| `VerdictBadge` | Kleines Urteil aus dem Preisverlauf (28) auf Karten: „🔥 Bestpreis“ (`deal`), „👍 Gutes Angebot“ (`success`), „😐 Normal“ (`text2`), „⚠️ Kein echtes Angebot“ (`warning`), getönte Kapsel auf `card`; bei zu wenig Daten keiner |
| `LabelBadges` / `NutriBadge` | Nutri-Score-Quadrat (Radius 30 %) in Originalfarbe, 🌱 vegan im `card`-Kreis, „Bio“ (`success` auf `successSoft`) – nur sichere Treffer (49) |
| `FilterChips` | Horizontal scrollende Pills mit Anzahl, aktiver Chip schwarz |
| `PrimaryButton` | Schwarzer voll runder Pill-Button, weißer Text, Höhe 56 |
| `SecondaryButton` | `surface`-Pill, schwarzer Text |
| `TabBar` | Schwebende weiße Leiste mit Radius 32, 4 Icons + schwarzer runder Mittel-Button (64 pt). Aktives Icon schwarz mit `accent`-Punkt darunter, inaktiv `#A3A3A0` |
| `ListCard` | Große farbige Einkaufslisten-Karte: Titel, Anzahl-Badge, Avatare, „+“ |
| `ChecklistRow` | Zeile der Einkaufsliste: Kreis zum Abhaken, Name, Menge, Preis, `DealBadge` |
| `RatingStars` | 5 große Sterne zum Tippen |
| `EmptyState` | Bild/Illustration, `headline`, ein Satz, optional `PrimaryButton` |
| `LoadingState` | Skeleton-Karten in Kartenform (kein Spinner auf leerem Screen) |
| `ErrorState` | wie `EmptyState` mit „Erneut versuchen“ |
