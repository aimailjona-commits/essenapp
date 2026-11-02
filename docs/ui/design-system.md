# Design-System

Status: **vorläufig freigegeben (C)** – im autonomen Modus entschieden (E16–E22), Nutzer kann jederzeit ändern. Mockups in `mockups/`.

Grundidee: hell, warm, ruhig, viel Luft. Das Essen ist die Farbe. Akzent ist ein frisches Limettengrün, Hauptaktionen sind schwarz.

## Farben

| Token | Hell | Verwendung |
|---|---|---|
| `bg` | `#ECEBE7` | Seitenhintergrund (warmes Hellgrau) |
| `surface` | `#F6F5F2` | Flächen, Eingabefelder, Kachelhintergrund |
| `card` | `#FFFFFF` → `#F3F2EE` (Verlauf von oben nach unten) | Karten |
| `textPrimary` | `#111111` | Überschriften, Werte |
| `textSecondary` | `#8C8C8C` | 2. Zeile der großen Überschrift, Untertitel |
| `textTertiary` | `#B8B8B4` | Platzhalter, Einheiten |
| `action` | `#111111` | Primär-Buttons, Mittel-Button der Tab-Bar |
| `onAction` | `#FFFFFF` | Text/Icon auf `action` |
| `accent` | `#9FE05A` | Auswahlrahmen, aktive Markierung, Fortschritt |
| `accentDeep` | `#3E7B1F` | Text/Icons auf hellem Grund in Grün |
| `deal` | `#FF5A36` | Rabatt-Badge, „Im Angebot“ (E17) |
| `success` | `#3E7B1F` | Ersparnis, abgehakt |
| `warning` | `#F5A623` | Budget knapp |
| `danger` | `#E5483B` | Fehler, Allergie-Warnung |
| `tabInactive` | `#A3A3A0` | Inaktive Tab-Icons |
| `scrim` | `#ECEBE7` mit 60 % + Blur 8 | Hintergrund hinter Schnell-Aktionen und Sheets |

Listen-Pastelltöne `listTints` (E18), in dieser Reihenfolge an Läden vergeben: `#F6DDD2`, `#DDE9D3`, `#E6DFF3`, `#F7EBC4`, `#D8E6F1`, `#F2DCE6`.

Produktbild-Tönungen in `OfferCard`: gleiche Palette wie `listTints`, nach Kategorie (Fleisch `#F6DDD2`, Obst & Gemüse `#DDE9D3`, Drogerie `#E6DFF3`, Vorrat `#F7EBC4`, Fisch/Kühlung `#D8E6F1`).

Nährwert-Farben (kleines Icon in getöntem Quadrat, wie Referenz 01):

| Nährwert | Farbe | SF Symbol |
|---|---|---|
| Kalorien | `#111111` | `flame.fill` |
| Protein | `#E5483B` | `cube.fill` |
| Kohlenhydrate | `#6BBF3A` | `leaf.fill` |
| Fett | `#F5A623` | `drop.fill` |

Dark Mode: **nicht in v1** (E15). Trotzdem nur Tokens verwenden, damit er später nachrüstbar ist.

## Schrift

System-Schrift **SF Pro** (E22 (C): keine Einbindung nötig, beste Dynamic-Type-Unterstützung). Web-PWA: `-apple-system, "Inter", system-ui`.

| Token | Größe / Gewicht | Verwendung |
|---|---|---|
| `display` | 34 / Bold, Zeilenhöhe 1.05, Laufweite −0.5 | Große Überschrift, 2 Zeilen: Zeile 1 `textPrimary`, Zeile 2 `textSecondary` |
| `title` | 24 / Bold | Gericht-Name im Detail |
| `headline` | 18 / Semibold | Abschnittstitel („Diese Woche“) |
| `body` | 16 / Regular | Fließtext, Zutaten |
| `callout` | 15 / Semibold | Karten-Titel, Buttons |
| `caption` | 13 / Medium | Untertitel, Gewicht, „Alle ansehen“ |
| `micro` | 11 / Semibold | Badges, Chip-Werte |
| `number` | wie Kontext, `monospacedDigit` | Preise, Nährwerte |

Alle Größen skalieren mit Dynamic Type.

## Abstände, Radien, Schatten

- Abstände: `4, 8, 12, 16, 20, 24, 32, 40`. Seitenrand **20**.
- Radien: Chip **14**, Kachel **20**, Karte **28**, große Karte / Sheet **36**, Buttons und Suchfeld **voll rund**.
- Schatten `soft`: y 12, Blur 32, Schwarz 7 %. Schatten `float` (Tab-Bar, schwebende Bilder): y 18, Blur 40, Schwarz 12 %.
- Bilder von Gerichten: freigestellt, rund (Teller von oben), dürfen über den Kartenrand hinausragen (wie Referenz 01).

## Icons

SF Symbols, Strichstärke `regular`, in Buttons `semibold`. Kleine Icons stehen in getönten Quadraten (Radius 10, Farbe mit 14 % Deckkraft).

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
