# Redesign v3 „Küchen-Pinnwand“ – Bau-Playbook (1:1)

Status: **Richtung freigegeben 2026-11-03** (E87). Vorlage: [`mockups/redesign-v3.html`](mockups/redesign-v3.html) – ansehen über den Vorschau-Server `mockups` (`.claude/launch.json`) unter `http://localhost:5173/docs/ui/mockups/redesign-v3.html`, sonst fehlen die Fotos.

Dieses Dokument ist die Bauanleitung, um **das gesamte UI** (iOS-App, Erweiterungen, Web-PWA) exakt wie das Mockup umzubauen. Aufgaben und Abhaken: [`docs/tasks/phase-18-redesign-v3.md`](../tasks/phase-18-redesign-v3.md).

## 0. Regeln für den Umbau

1. **Das Mockup ist die Wahrheit.** Jeder Wert (Farbe, Größe, Abstand, Radius, Schatten, Schrift) kommt aus diesem Dokument bzw. dem CSS des Mockups. Weicht dieses Dokument vom Mockup ab, gilt das Mockup – und dieses Dokument wird korrigiert.
2. **Nichts erfinden.** Ein Screen, Zustand oder Baustein, der im Mockup fehlt, wird **zuerst als Mockup ergänzt** (Teil 3 in derselben Datei) und vom Nutzer freigegeben, dann gebaut (Abschnitt 7).
3. **Funktion bleibt.** v3 ändert das Aussehen. Inhalte, Aktionen und Zustände aus [`screens.md`](screens.md) bleiben, außer sie stehen in Abschnitt 6.2 („Verhaltensänderungen“).
4. **Nutzer-Feedback aus der Abstimmung ist verbindlich:**
   - Farben **sanft/pastell**, nie gesättigt. Pastell nie als Schriftfarbe auf hellem Grund (Kontrast) – dafür `deal`, `ink` oder `star`.
   - **Keine Klebebänder.** **Alles gerade:** Karten, Listen, Kassenbon, Ordner, Kacheln, Notizen ohne Drehung. Gedreht sein dürfen nur Foto-Sticker im Tages-Satz (−8°/+7°), Emojis als Deko und der Preis-Stern (−8°).
   - Handkreise liegen **um** den Text, nie darüber.
   - **Echte Händler-Logos**, immer vollständig auf weißem Plättchen (E44, nur verlinkt).
5. Alle Werte nur in `Theme.swift` (iOS) und `app.css` (PWA), keine Zahlen in Views (`ios/CLAUDE.md`).

## 1. Die Handschrift (was v3 ausmacht)

| Merkmal | Wo | Baustein |
|---|---|---|
| Riesige Überschrift in **Fraunces** (weich, leicht schief), 2. Zeile kursiv grau | Kopf jedes Tabs | `DisplayHeader` |
| Tag als **Satz** mit Tellerfoto-Stickern, Ersparnis handgemalt eingekreist | Start | `SentenceHero`, `Scribble` |
| **Pastell-Karten** je Wochentag, überlappend wie Sprechblasen | Wochenplan | `DayCard` |
| **Preis-Stern** wie im Prospekt | Angebote, Angebotsdetail | `PriceBurst` |
| **Coupon-Kerben** + Perforation | „Knaller der Woche“, Coupons | `CouponCard` |
| **Kassenbon** mit Zackenrand und Mono-Ziffern | Einkaufsliste | `Receipt` |
| **Ordner** je Laden mit echtem Logo | Einkauf | `ListCard` (Ordner) |
| **Schwarze schwebende Pille** mit Limetten-Mitte; Menü als **Fächer** mit weißer Wölbung | überall | `TabBar`, `QuickActions` |
| **Summen-Leiste** unten (schwarz, Limetten-Knopf) | Detail-Screens | `TotalBar` |
| Feines **Papierkorn** über allem | überall | `PaperGrain` |
| Fotos randlos, Farbverlauf in eine Foto-Farbe | Rezeptdetail | `RecipeHero` |

## 2. Farben (Hell)

| Token (Swift `Theme.C.*`) | Wert | Verwendung |
|---|---|---|
| `bg` | `#F4F1EA` | Seitenhintergrund (Creme) |
| `card` | `#FFFFFF` | Karten, Zeilen-Pillen, Suchfeld |
| `surface` | `#E9E5DC` | Nebenknöpfe, Segment-Grund, Skeleton, inaktive Zähler |
| `line` | Schwarz 7 % | Haarlinien (1 pt) |
| `ink` (= `action`, `text1`) | `#111111` | Text, Primärknöpfe, Tab-Leiste, Preis-Pille |
| `onInk` | `#FFFFFF` | Schrift auf `ink` |
| `text2` | `#7A766E` | Untertitel, Meta |
| `text3` | `#B3AEA4` | 2. Zeile `DisplayHeader`, Platzhalter |
| `lime` | `#DCEDA0` | Aktionsfarbe „los“: Mittel-Knopf, `AccentButton`, Abgehakt, Fortschritt, Ersparnis auf Dunkel, Handkreis auf Dunkel |
| `deal` | `#E8694A` | Rabatt (Stern, Pille), „Heute“, Ersparnis-Kreis auf Papier, Zähler-Badge |
| `star` | `#E8B33A` | Bewertungssterne (Pastell wäre zu blass) |
| `chipBorder` | `#CFC9BD` | Rand inaktiver Chips, Kassenbon-Trennlinie, Schritt-Punkte hell |
| `paper` | `#FFFDF7` | Kassenbon |

**Wochentage / Kartenfarben** (`Theme.C.day[0…6]`, auch Ordner-Palette `Theme.storeColor`):

| Mo `tomato` | Di `sun` | Mi `lav` | Do `sky` | Fr `mint` | Sa `orange` | So `pink` |
|---|---|---|---|---|---|---|
| `#F2B9A8` | `#F3DC9E` | `#D5CDF0` | `#BCD0F2` | `#C3E3CF` | `#F2CBA6` | `#F0CADA` |

Schrift auf Kartenfarben immer `ink`. Ordnerfarbe je Laden: feste Zuordnung aus dieser Palette (Lidl `sun`, Rewe `tomato`, dm `lav`, Wochenmarkt/„Überall“ `mint`; weitere Ketten der Reihe nach `sky`, `orange`, `pink`) – keine Markenfarben.

**Kategorie-Tönungen** (`Theme.hue(...).tint`, Produktflächen): Obst & Gemüse `#E4F5D9`, Fleisch & Fisch `#FFE3DB`, Kühlung `#DFE9FF`, Vorrat `#FFF1C9`, Drogerie `#ECE6FF`, Haushalt `#FFE4EF`, Getränke/Sonstiges `surface`.

**Nährwert-Tönungen** (`NutrientTile`, `NutrientStat`): kcal `#FFE7D6`, Protein `#FFE0E1`, KH `#E4F5D9`, Fett `#FFF1C9`.

**Urteile** (`VerdictBadge`): Bestpreis `ink`/weiß · Gutes Angebot `lime`/`ink` · Normal `surface`/`#555555` · Kein echtes `#FFF1C9`/`#8A5A00`. Nutri-Score: Originalfarben wie bisher.

**Dunkle Flächen** (Start-Kopf, Kochmodus, Menü): `#111111` Grund, `#161616` Koch-Sheet, `#2A2A2A` Knöpfe/Trenner, `#222222` Chips mit Rand `#333333` und Schrift `#DDDDDD`; Text grau `#77736B`, Labels `#9A978F`, inaktive Tabs `#8C8A85`.

**Rezept-Kopf:** Verlaufsfarbe = dunkle Hauptfarbe des Fotos (Durchschnittsfarbe, Helligkeit auf ~25 % gezogen); Fallback `#5C4038`. Text darauf weiß, Nebentext `#E3CFC5`, Knöpfe weiß 14 %.

**Dunkelmodus:** im Mockup **noch nicht festgelegt** → Aufgabe 18.1c (erst Mockup, dann Werte hier eintragen). Bis dahin keinen Dunkel-Wert erfinden.

## 3. Schrift

Drei Familien. Alle Größen über Dynamic Type (`relativeTo:` bzw. `UIFontMetrics`), Werte = Standardgröße.

| Token | Familie / Schnitt | Größe / Zeilenhöhe / Laufweite | Verwendung |
|---|---|---|---|
| `display` | **Fraunces** 800, Achsen `SOFT 100`, `WONK 1`, `opsz 144` | 46 / 0.95 / −2.5 % (Start 52, Liste 56, Onboarding 50, Menü 44) | `DisplayHeader` Zeile 1 |
| `displayItalic` | Fraunces *kursiv* 400, `SOFT 100` | wie `display`, Farbe `text3` (auf Dunkel `#8C8A85`) | `DisplayHeader` Zeile 2 („KW 45“, „Jona?“) |
| `title` | SF Pro 900 | Rezept-Kopf 34 (−4 %), Angebot 24 (−3,5 %), „Schritt 2“ 30 | Gericht-/Produktname im Detail (so im Mockup: **nicht** Fraunces) |
| `cardTitle` | Fraunces 800, `SOFT 100`, `WONK 1`, `opsz 28` | 21 (Ordner 19 = SF 800!, Kacheln 17, Coupon 25) | `DayCard`, `rtile`, „Knaller“ |
| `sentence` | Fraunces *kursiv* 400, `SOFT 100`, `opsz 72`; hervorgehoben: Fraunces 700 aufrecht, `SOFT 100`, `opsz 72` | 27 / 1.32 / −1 % | `SentenceHero` |
| `burst` | Fraunces 900, `opsz 20`, ohne SOFT/WONK | siehe `PriceBurst` | Preis-Stern |

Feste Schnitte (aus den variablen Schriften erzeugt mit `ios/tools/make_fonts.py`, PostScript-Namen): `FrauncesV3-Display`, `-Title`, `-Bold`, `-Black`, `-Italic`, `-TextItalic`, `JetBrainsMonoV3-Medium`, `-Bold`.
| `section` | SF Pro 800 | 22, Laufweite −3 % | „Diese Woche“ |
| `headline` | SF Pro 700 | 18 | Abschnitte in Karten |
| `body` | SF Pro 400 | 16 | Fließtext |
| `callout` | SF Pro 700 | 15–17 | Zeilen-Titel, Knöpfe (16) |
| `caption` | SF Pro 500 | 13, `text2` | Untertitel |
| `micro` | SF Pro 700–800, GROSS, +6 % | 11–12 | Mahlzeit, Meta auf Karten |
| `price` | SF Pro 800, `monospacedDigit` | 16 (Pille), 19 (Leiste) | Preise |
| `mono` | **JetBrains Mono** 500/700 | 13 (Kopf 12, SUMME 16) | Kassenbon |
| `step` | SF Pro 400 | 19 / 1.45 | Kochschritt-Text |

Lizenzen: Fraunces und JetBrains Mono stehen unter SIL OFL 1.1 → Dateien + Lizenztext in `ios/Sources/Essenapp/Resources/fonts/` (Download fragt der Nutzer frei, Aufgabe 18.2).

## 4. Maße

- **Seitenrand 20.** Abstände 4 · 6 · 8 · 10 · 12 · 14 · 16 · 18 · 20 · 22 · 24 · 30.
- **Radien:** Chip 16 · Kachel 22 · Angebotskarte 26 · Rezept-Kachel 28 · Karte 30 · Tageskarte 34 · Sheet 40 · Telefon-Kopf-Sheet 36–40 · Knöpfe/Pillen voll rund.
- **Schatten:** `soft` y 10, Blur 28, `ink` 8 % · `float` y 18, Blur 40, `ink` 22 % · Teller y 12, Blur 24, Schwarz 18 % · Kassenbon y 10, Blur 14, Schwarz 9 %.
- **Größen:** runder Knopf 46 (klein 38) · Primärknopf Höhe 56 (Koch 60) · Chip 42 · Suchfeld 54 · Tab-Leiste 70 hoch, 18 vom Rand, 26 vom Boden · Tab 52 · Mittel-Knopf 56 · Summen-Leiste 72 · Tap-Fläche nie < 44.
- **Teller** (`Plate`): Kreis, Foto `scaledToFill`, weißer Innenring 4 pt, Teller-Schatten. Größen 46 (Sticker), 56 (Zeile), 84 (Tageskarte), 128 (MealCard).

## 5. Bausteine

„Datei“ = wo der Baustein heute liegt bzw. neu angelegt wird. Neue Shapes kommen nach `Components.swift` (oder `Shapes.swift`, falls > 150 Zeilen).

| Baustein | Status | Datei | Spezifikation (1:1 Mockup) |
|---|---|---|---|
| `DisplayHeader` | umbauen | Components | Zeile 1 `display`, optional Zeile 2 `displayItalic`. Rechts: optional `meta` (SF 15/600, `ink`) + bis zu 2 `RoundIconButton` (46; Hauptknopf `ink`/weiß, sonst `surface`). |
| `RoundIconButton` | umbauen | Components | Kreis 46/38; Varianten `surface`, `ink`, `card`, Glas dunkel (Schwarz 28 % + Blur, auf Fotos), `lime`. Icon 22 (klein 16), Strich 2. |
| `SearchField` | umbauen | Components | Höhe 54, `card`, Haarlinie, Lupe links `text3`, Filter-Knopf 42 `ink` im Feld rechts. |
| `FilterChip` | umbauen | Components | Höhe 42, Rand 1.5 `chipBorder`, Text 15/600 `#8A857B`, Zahl-Kapsel 24 `surface`. Aktiv: Rand 2 `ink`, Text `ink`, Zahl `ink`/weiß. Schalter-Filter an: gefüllt `ink`, Zahl `lime`/`ink`. Merkliste-Zahl: `deal`/weiß. |
| `PrimaryButtonStyle` | umbauen | Components | `ink`, weiß, 56, voll rund, 16/700. |
| `AccentButtonStyle` | **neu** | Components | wie Primär, aber `lime`/`ink`. Max. 1 pro Screen (Kochen, Auf die Liste, Nächster Schritt, Einkauf starten). |
| `SecondaryButtonStyle` | umbauen | Components | `surface`/`ink`. |
| `ActionCluster` | **neu** | Components | Kapsel `surface`, Innenabstand 4, Kreise 48 (Hauptknopf 56 `ink`), Abstand 2. Auf Karten: Kreise 34, Schwarz 8 %, Icon 17. |
| `DealBadge` | umbauen | Components | Kapsel 26, `deal`, weiß, 12/800. Nur noch in Textzeilen (Liste, Zutaten, Rezept-Kopf). |
| `PriceBurst` | **neu** | Components | Stern mit 14 Zacken (28 Punkte, innen 82 % des Radius, erster Punkt oben), −8° gedreht. Text eine Zeile, Fraunces 900, „−35“ + „%“ in 62 %. Größen: 58 (Text 15, Karten), 66 (17, Coupon), 100 (25, Angebotsdetail). Farben: `deal`/weiß · `lime`/`ink` · `ink`/`lime`. Auf `OfferCard` oben links, 6 pt nach außen versetzt. |
| `VerdictBadge` | umbauen | PriceHistory | Kapsel 26, 12/700, Farben Abschnitt 2. Auf Karten nur das Emoji oben rechts (18). |
| `StoreChip` | umbauen | Components | Kapsel 26, `card` + Haarlinie, Farbpunkt 8 in Ordnerfarbe, 12/700. Dunkle Variante (Start-Kopf) siehe Abschnitt 2. |
| `StoreLogo` | umbauen | Components | Weißes Plättchen (Ordner 64/R18, Listenkopf 60/R18), Logo `AsyncImage` aus `API.logos`, `scaledToFit` max. 50×38, **nie beschnitten**. Ohne Logo: Emoji 🧺 bzw. Kürzel. |
| `Plate` | umbauen | Components | Abschnitt 4. Ohne Foto: Emoji auf `card` (bzw. Tönung). |
| `PhotoSticker` | **neu** | Components | Kreis 46, Rand 3 weiß, Schatten y 6/Blur 14/25 %, −8° bzw. +7°, im Fließtext (Baseline −8). |
| `SentenceHero` | **neu** | StartView | Text-Teile `[.plain, .bold, .sticker(url), .scribble(Betrag), .emoji]`; Zeilenumbruch mit eingebetteten Bildern über `Text` + `Image` oder Flow-Layout. Vom Server (Plan + Ersparnis) oder lokal aus dem Plan gebaut. |
| `Scribble` | **neu** | Components | Pfad im 120×50-Rahmen `M22 6 C62 0 112 4 117 24 C121 44 72 50 42 48 C10 46 0 34 3 22 C6 10 30 4 60 3`, gestreckt auf Textrahmen + 12 pt seitlich / 9 pt oben-unten, Strich 2.6 rund, Text-Innenabstand 3. Farben: `lime` auf Dunkel, `deal` auf Papier, `ink` auf Hell. Zeichnet sich beim Erscheinen (`trim` 0→1, 0.6 s, ease-out; bei „Bewegung reduzieren“ sofort). |
| `MealCard` | umbauen | StartView | `card`, R30, Teller 128 ragt 56 über den Rand, `micro` Meta, `cardTitle` 21, 3 `NutrientStat` + Preis-Pille 40. |
| `WeekRow` | **neu** (ersetzt `MealCardSmall` auf Start) | StartView | Teller 56, Meta `micro` (`deal` bei „Heute“, sonst `text2`), Name 17/700, „2,10 € · 25 min“ 13 `text2`, rechts `DealBadge` „2 im Angebot“ oder Chevron `text3`. Trenner Haarlinie, Zeilen 12 pt Innenabstand. |
| `DayCard` | **neu** (ersetzt `MealRow` im Plan) | PlanViews | R34, Grund: n-te Karte des Tages = Farbe von Tag + n (Di: `sun`, dann `lav` …, wie Mockup); Dessert/Snack `card` + Haarlinie, Innenabstand 20, links 116. Teller 84 bei (16, 22). Meta `micro` 65 %, Name `cardTitle`, Info 13/600 75 %, `ActionCluster` klein (Herz, Ersetzen, Schloss, Würfel). Zähler oben rechts: Kreis 30 `ink` = Zutaten im Angebot. Karten überlappen −18 (spätere oben). **Nicht gedreht.** |
| `DaySelector` | umbauen | PlanViews | 7 Pillen 44×58 `card` + Haarlinie, Kürzel 13/800, Punkt 8 in Tagesfarbe; aktiv `ink`/weiß. Gleitende Auswahl (`matchedGeometryEffect`). |
| `OfferCard` | umbauen | OffersView | R26, Innenabstand 12, Grund Kategorie-Tönung, Bildfläche 118 (Produktbild bzw. Emoji 66 mit Schatten), `PriceBurst` oben links, Urteil-Emoji oben rechts, Name 15/700, Grundpreis/Laden 12 `#6A665E`, unten Preis-Pille 36 (`ink`, 16/800, Streichpreis 11 `#9A978F`) + Plus-Knopf 38 (`card`; auf der Liste: `lime` mit Haken). |
| `CouponCard` | **neu** | OffersView / Bonus | R24, Kerben r 13 links/rechts auf 64 % Höhe, Perforation gestrichelt 2 pt Schwarz 18 % auf 64 %, 18 pt Rand. „Knaller der Woche“: Höhe 150, `lime`, Micro-Titel 60 %, Name Fraunces 25/800 + kursive 2. Zeile, Produkt-Emoji 76 (−12°), `PriceBurst` 66 `ink`, unten `VerdictBadge`. |
| `NutrientStat` / `NutrientTile` | umbauen | Components | Stat: Quadrat 34 R12 in Tönung + Emoji, Wert 16/800, Bezeichnung 12 `text2`. Tile: Fläche in Tönung R22, Wert 22/900, Bezeichnung 12/700 70 %. |
| `ShareBloom` | umbauen | Components | Blätter Breite 46, Verlauf Kartenfarbe → helle Stufe, Länge nach Anteil, Teller 96 in der Mitte, „Sonstiges“ `#C9C3B6`. |
| `ChecklistRow` | umbauen | ShoppingView/Sharing | Pille 58 `card` + Haarlinie, Kreis 36 Rand 2 `#D3CEC3`; abgehakt `lime` + Haken, 50 % + durchgestrichen. (Für Einmal-Listen und Vorrat; Laden-Listen nutzen `Receipt`.) |
| `Receipt` | **neu** | ShoppingView | Papier `paper`, Zacken 9 pt oben+unten, Schatten Kassenbon, Innenabstand 22/18. Kopf `mono` 12/700 GROSS zentriert („LIDL · BERLIN-MITTE / KW 45 · 12 ARTIKEL“, `#555`), Trenner gestrichelt 1.5 `chipBorder`. Zeile: Kästchen 20 R6 Rand 1.8 `#222`, Name, Menge `#8A857B`, Rabatt `deal` 11/700, Preis rechts 700. Abgehakt: Kästchen `lime` + Haken, Text `#A9A398` durchgestrichen, ans Ende. Fuß: „SUMME“ 16/700 + Betrag, „davon gespart“ + Betrag in `Scribble` `deal`. |
| `ListCard` (Ordner) | umbauen | ShoppingView | Höhe 172. Reiter 56 % breit, 34 hoch, R18 oben; Körper ab 22, Ecken 0/24/24/24, **gleiche Farbe** (nahtlos). `StoreLogo` 64 oben links (14/14). Unten Name 19/800, „12 Artikel“ 13/600 65 %, Avatar 30 weiß unten rechts. Schatten y 8/Blur 14/7 % auf der Gesamtform. |
| `QtyStepper` | **neu** | Components | Klein: Preis-Pille `surface` hinter Kapsel `ink` 48 mit −, Zahl in weißem Kreis 28, +. Groß: −/+ als Knöpfe 56 `surface`, Zahl 68/900. |
| `TotalBar` | **neu** (ersetzt festen Aktionsbereich) | Components | Kapsel `ink`, 72 hoch, Position der Tab-Leiste (18/28). Links Label 11/600 `#9A978F` + Wert 19/800 weiß; „››››“ `lime` 18/800; rechts `AccentButton` 56. |
| `StepDots` | **neu** | Cooking | Kreise 32 Rand 1.5; dunkel: Rand `#555`, aktiv weiß/`ink`, erledigt `lime` + ✓, Ziel 🏁. Hell: Rand `chipBorder`, aktiv `ink`. |
| `BudgetCard` | umbauen | StartView | `ink`, R30, Innenabstand 20, Micro-Titel `#9A978F`, Urteil-Pille `lime` „−12,40 € gespart“, Betrag 34/900 + „von 60 €“ 20 `#77736B`, Balken 12 (`#333`, Füllung `lime`), Satz 13 `#9A978F`. Hell-Variante (Plan-Kopf): Balken auf `surface`, Füllung `ink`. |
| `RatingStars` | umbauen | Components | 34, `star`, leer `#DDD7CB`. |
| `Toast` | umbauen | Components | Kapsel 52 `ink`, Kreis 36 `lime` mit ✓, 15/700 weiß, `float`. |
| `EmptyState` / `SkeletonCard` / `ErrorState` | umbauen | Components | Empty: `card` R30, Emoji 56, `headline`, Satz `caption`, `PrimaryButton`. Skeleton: Schimmer `surface` → `#F6F3EE`. Fehler: Pille `card` mit Text + `SecondaryButton` 40 „Erneut“. |
| `Sheet` | umbauen | überall | `card`, R40 oben, Griff 40×5 `#D8D3C8`. |
| `TabBar` | umbauen (ersetzt Liquid Glass, E87) | Components | Kapsel `ink` 70, Innenabstand 9, `float`. Tabs 52 Icon `#8C8A85`; aktiv: weiße Kapsel mit Icon + Name 14/800 `ink` (gleitend). Mitte: Kreis 56 `lime` mit +. Zähler (Angebote) Kapsel 18 `deal`, Rand 2 `ink`, oben rechts. |
| `QuickActions` (Fächer) | umbauen | ContentView | Siehe Screen „Schnell-Aktionen“ (6.1). |
| `PaperGrain` | **neu** | Theme/Components | Kachelndes Rauschbild (180 px, fraktales Rauschen, Schwarz 9 % Alpha) mit Deckkraft 55 %, `multiply`, über jedem Screen, nicht antippbar. PNG einmal per Skript erzeugen (`ios/tools/make_grain.py`, Pillow), als Ressource. |
| `RecipeHero` | **neu** | PlanViews/Recipes | Foto randlos 0–420, Verlauf 220–420 in die Foto-Farbe, darunter Fläche in Foto-Farbe. Knöpfe Glas dunkel. |

## 6. Screens

### 6.1 Gemockt (bauen 1:1)

Positionen in pt auf 390×844 (iPhone-Breite), oben inkl. Statusleiste 52.

**Tab-Leiste & Tabs** – alle Tab-Screens: Inhalt Innenabstand oben 62, unten 120 (Platz für die Leiste).

**S1 Start** (`start`, `StartView`)
- Oberer Teil `ink` bis 470. Statusleiste weiß.
- Kopf ab 66: „Heute“ `display` 52 weiß. Rechts: „● KW 45“ (Punkt Tagesfarbe Mo, Text weiß 15/600) / „Dienstag“ `#77736B`, daneben Avatar-Knopf 38 `#2A2A2A`.
- `SentenceHero` 30 darunter: „Hallo Jona! Heute gibt's **Spaghetti Pomodoro** [Sticker], morgen **Lachs mit Salat** [Sticker] – und mit den Angeboten **sparst du (12,40 €)** 🏷️“ – Kreis `lime`.
- 22 darunter: „Aus 3 Prospekten“ 14/600 `#77736B` + `StoreChip` dunkel je Laden.
- Sheet ab 470: `bg`, R40 oben, Innenabstand 22. Kopf „Diese Woche“ `section` + rechts „7 Gerichte ⚟“ 14/600 `text2`. Danach `WeekRow`s ab heute.
- Weiter unten (scrollend, **noch nicht gemockt → 7**): Banner (Special), „Keine Lust“, `BudgetCard`, Lieblingsrezepte günstig, Kühlschrank scannen.
- Zustände Leer/Laden: noch nicht gemockt → 7.

**S2 Wochenplan** (`plan`, `RecipesTab` › Plan)
- `DisplayHeader` „Woche“ / *„KW 45“*, rechts Teilen (`surface`) + Würfeln (`ink`).
- 14 darunter: „38,20 € von 60 €“ (17/800, Rest `text2` 600) + Pille `lime` „12,40 € gespart“; Balken 12 hell (`surface`, Füllung `ink`), 10 Abstand.
- `DaySelector` (18 oben, 20 unten).
- `DayCard`s des Tages in der Reihenfolge aus `screens.md` (Lunchbox-Meta „🥡 LUNCHBOX · JONA“, Rest-Hinweis „♻︎ Rest von Mo“ in der Info-Zeile).
- Darunter (nicht gemockt → 7): „essen mit“, Abwechslung, Tageswerte-Ringe, Reste, Gäste, „Keine Lust“.

**S3 Rezeptdetail** (`recipe`, `RecipeDetailView`/`SavedRecipeView`)
- `RecipeHero`. Oben (62): Zurück links, Herz + „…“ rechts (Glas dunkel).
- Text ab 330, Rand 22, weiß: Herkunft 15/700 `#E3CFC5` („Aus deinem Plan · Dienstag“), Name `title` 34, „★ 4,5 · 2 Bewertungen“ 15/600 `#E3CFC5`.
- Kennzahlen (18 Abstand): ZEIT · PORTION · KCAL (`micro` `#E3CFC5` / Wert 19/700), Trenner 1×36 weiß 25 %.
- Drei Knöpfe 48 nebeneinander, weiß 14 %: „Einplanen“, „Ersatz“, „Teilen“ (Icon 16 + 15/700).
- Zutaten-Karte weiß 12 %, R22: Zeilen 44 „🍅 Tomaten 400 g“ + `DealBadge` „−30 % Lidl“ bzw. „im Vorrat“.
- `TotalBar`: „Portionen − 2 +“ / `AccentButton` „▶ Kochen“.
- Darunter (nicht gemockt → 7): Nährwerte, Bloom, Schritte, Bewertungen, Quelle/Import-Chips.

**S18 Kochmodus** (`cooking`, `CookingView`) – immer dunkel
- Foto 0–330, oben ✕ (Glas dunkel) und Timer-Pille „⏱ 08:24“ (Schwarz 45 % + Blur, 44 hoch).
- Fortschritt bei 282: Linie 4, weiß 30 %, Füllung `lime`, Rand 24.
- Sheet ab 306: `#161616`, R36 oben, Innenabstand 26/24. „Schritt 2“ SF 30/900 zentriert, `StepDots` (16/18 Abstand), Zutaten des Schritts (Zeilen 46, Trenner `#2A2A2A`, Menge `#9A978F`), Text `step` `#C9C5BD` mit Zeit fett weiß.
- Unten 34: Mikro-Knopf 60 `#2A2A2A` + `AccentButton` 60 „Nächster Schritt →“.

**S4 Angebote** (`offers`, `OffersView`)
- `DisplayHeader` „Angebote“ + Such-Knopf `ink`. Darunter 8: „📍 10115 Berlin · 6 Läden ▾“ 15/600 `text2`, rechts „128 diese Woche“ `ink`.
- `FilterChip`-Reihe (16 oben, läuft rechts aus): Alle · **Merkliste** (Zahl `deal`) · Kategorien …
- „Knaller der Woche“ `CouponCard` (14 oben).
- Raster 2 Spalten, Abstand 10, `OfferCard`.

**S9 Angebotsdetail** (`offer`, `OfferDetailView`) – Grund `card`
- Kopf: Zurück · „Angebot“ 17/800 · Herz.
- Bildfläche 250: Kreis 230 in Kategorie-Tönung, Produkt 150, `PriceBurst` 100 oben links.
- `QtyStepper` groß, darunter Preis-Pille 42 (19) mit Streichpreis.
- Unteres Sheet ab 518: `bg`, R36 oben, Innenabstand 22: Name Fraunces 24/900, „600 g · 0,60 €/100 g · bis Sa 7.11.“ `caption`, Merken-Knopf `card`. Chips: `StoreChip`, `VerdictBadge`, Nutri. Preisverlauf-Mini: 12 Balken (5 Abstand, R5), Normalwochen `surface`, Angebotswochen `chipBorder`, aktuelle `lime` mit Rand 2 `ink`; Tippen → großes Diagramm (bestehendes `PriceHistoryCard` im v3-Stil).
- `TotalBar`: „Gesamt / 2 × 7,18 €“ + `AccentButton` „Auf die Liste“.
- Darunter (nicht gemockt → 7): Vorratstipp, Nährwerte, Labels, „Passt zu“.

**S5 Einkauf** (`shopping`, `ShoppingView`)
- `DisplayHeader` „Einkauf“, Meta „4 Listen“, „+“.
- Segment (16 oben): Kapsel `surface`, Innenabstand 4, Teile 42 hoch; aktiv `ink`/weiß, sonst `text2`.
- Ordner-Raster 2 Spalten, Abstand 14.
- Spar-Pille (16 oben): `ink`, 60 hoch, „Diese Woche gespart“ 600 + Betrag 20/800 `lime` + Chevron-Knopf 38 `#2A2A2A` → S11.

**S5 Liste** (`list`, `ShoppingListView`)
- Kopffläche 0–300 in Ordnerfarbe, R40 unten.
- Zeile oben: Zurück (`card`), rechts „Geteilt mit“ 14/700 + Avatare 36 (überlappend −10, Rand 2 in Kopffarbe) + Teilen 38.
- 22 darunter: `StoreLogo` 60 + Name `display` 56.
- „12 offen · 24,80 €“ 16/700 + Pille `ink` „−6,10 € gespart“ (Betrag `lime`).
- `Receipt` (34 Abstand) mit allen Artikeln (Gruppierung nach Kategorie: Kopfzeilen im Bon, noch nicht gemockt → 7).
- Feld „Artikel hinzufügen …“ (54, Mikro-Knopf `surface`).
- `TotalBar`: „Noch offen / 24,80 €“ + `AccentButton` „Einkauf starten“ (→ Live-Aktivität).

**S12 Rezepte** (`recipes`, `MyRecipesList`)
- `DisplayHeader` „Rezepte“, Meta Anzahl, „+“.
- Chips: Alle · Favoriten · Im Angebot · Eigene.
- Kachel-Wand 2 Spalten, Abstand 10, Spalten unabhängig hoch:
  - „Plan dieser Woche“ (`tomato`, 236): Herz-Knopf, 4 Mini-Zeilen (Kapsel 36, Schwarz 8 %, Kreis 18; erledigt gefüllt + durchgestrichen) → S2.
  - Sammlung „Aus Instagram · 5 Rezepte“ (`lav`, 150, Emoji 58 unten rechts).
  - Foto-Kachel (186, Verlauf unten Schwarz 55 %, Titel weiß, Herz Weiß 30 %).
  - „5 Lieblingsrezepte günstig“ (`lime`, 200): 3 überlappende Teller 48 (−16) + `DealBadge` „bis −35 %“.

**Schnell-Aktionen** (`quick`, `QuickActions`)
- Hintergrund: aktueller Screen, Blur 7, darüber Verlauf `ink` 60 % → 94 % (ab 55 %).
- Titel bei (24, 120): „Was jetzt,“ / *„Jona?“* (`display` 44 weiß, kursiv `#8C8A85`).
- **Tab-Leiste wird weiß** (Schatten Schwarz 40 %, Icons `#9A978F`), in der Mitte eine **Wölbung**: Kreis 92 `card`, 26 über der Oberkante; darin ✕-Knopf 64 `ink`. (Mockup ohne weiche Übergänge; in der App darf die Leiste als eine Form mit konkaven Übergängen gezeichnet werden – Radius 18.)
- **Fächer:** gestrichelter Bogen (weiß 18 %, Strich 1.5, 3/7) Radius 180 um den Wölbungs-Mittelpunkt, von 150° bis 30°. Knöpfe auf dem Bogen bei 150°, 120°, 90°, 60°, 30°: Barcode (`sky`), Zur Liste (`sun`), **Wochenplan erstellen** (`lime`, 88 mit Halo 6 `lime` 22 %), Rezept anlegen (`lav`), Kühlschrank scannen (`tomato`, 📸). Seitenknöpfe 64, Icon 26 `ink`, Schatten y 10/Blur 24/35 %. Beschriftung darunter 12/700 weiß (Mitte 13), max. 2 Zeilen.
- Animation: Knöpfe springen nacheinander (40 ms Versatz) aus der Mitte auf ihre Position (`Theme.spring`), Bogen blendet ein; Schließen umgekehrt. Haptik beim Öffnen.

**S6 Onboarding Schritt 1** (`onboarding`, `OnboardingView`)
- Grund `bg`. Collage (alles **gerade**): Blob `lav` 150 bei (28, 96) mit Teller 112, Notiz `sun` 150×150 R6 „Spart 12 € pro Woche!“ (Handschrift-Schrift), Stern `sky` 160, 🥑 72 (gedreht erlaubt), Pille `tomato` „Mo – So geplant ✓“, Kreis `mint` 76 mit 🛒.
- Unten (Rand 24, 40 vom Boden): Fortschritt 4 Striche (aktiv 44 `ink`, sonst 20 `#D8D3C8`), „Kochen nach“ / *„Angebot.“* (`display` 50), Satz 16 `text2`, `PrimaryButton` voll breit „Los geht's“, Textlink 15/600.
- Handschrift der Notiz: bisher Systemschrift „Bradley Hand“ (iOS vorhanden) – so übernehmen.

### 6.2 Verhaltensänderungen gegenüber `screens.md` (mit v3 gültig)

| Screen | Änderung |
|---|---|
| S1 | Kopf = `SentenceHero` statt Foto-Hero „GUTEN ABEND.“; „Diese Woche“ als Zeilenliste statt Karten-Karussell; die Heute-`MealCard` entfällt (Heute = erste Zeile). |
| S4 | Merkliste ist ein Chip (mit Zahl) statt eigenes Segment; Ort steht klein unter dem Titel; „Knaller der Woche“ = größte Ersparnis oben. |
| S9 | Menge wählbar (− / +), Summen-Leiste legt N Stück auf die Liste; Preisverlauf zuerst als Mini-Balken, Tippen öffnet das Diagramm. |
| S3 | Drei Knöpfe Einplanen / Ersatz / Teilen; Portionen in der Summen-Leiste. Wo „Gekocht – bewerten“ hinkommt, klärt das Mockup der Gruppe B (bis dahin nicht entfernen). |
| S5 | Laden-Listen als Kassenbon (Kästchen statt Kreise); Einmal-Listen behalten `ChecklistRow`. |
| Tab Rezepte | Wurzel ist die Kachel-Wand (S12). Der Wochenplan (S2) öffnet über die Kachel „Plan dieser Woche“; erneutes Tippen auf den Tab führt zurück zur Wand. Das Segment „Wochenplan / Meine Rezepte“ entfällt. „+“ öffnet ein Menü: Rezept anlegen · Aus Link importieren. |
| S1, S12 | Suchfeld steht (bis Gruppe A/B gemockt ist) unter dem gemockten Teil. |
| Tab-Leiste | Schwarze Kapsel statt Liquid Glass (E44 für die Leiste aufgehoben, E87). |
| Detail-Screens | `TotalBar` ersetzt den festen Aktionsbereich über der Tab-Leiste; die Tab-Leiste ist dort ausgeblendet. |

Diese Änderungen beim Umbau in `screens.md` nachtragen (Aufgabe 18.1b).

## 7. Noch nicht gemockt – erst mocken, dann bauen

Alles unten wird als **Teil 3 „Weitere Screens“** in `mockups/redesign-v3.html` ergänzt, nur mit den Bausteinen aus Abschnitt 5 (neue Bausteine nur mit Rückfrage). Reihenfolge = Bau-Reihenfolge. Jede Gruppe vom Nutzer freigeben lassen.

| Gruppe | Screens (Demo-Name) |
|---|---|
| A Start & Plan komplett | `start` (unterer Teil), `empty`, `generator`, `generating`, `nomood`, `guests`, `leftovers`, `basics`, `variety`, Bewertung (S8) |
| B Rezepte | `recipe` (unterer Teil), `myrecipe`, `recipeform`, `imported`, `importlink`, `instagram`, `sharecard`, `substitute`, `recipelink`, `sharedrecipe` |
| C Angebote | `offer` (unterer Teil), `offerstock`, `watch`, `scanner`, `nextweek`, `stores` (Karte), `singlestore` |
| D Einkauf & Vorrat | `list` (Kategorien im Bon), `pantry`, `voiceadd`, `offline`, `storeask`, `fridgecam`, `fridgereview`, `cooknow` |
| E Sparen & Bonus | `savings`, `budgetover`, `wallet`, `bonus`, `coupon` (Kasse), `couponadd`, `spending` |
| F Motivation | `achievements`, `unlock`, `review` (Story), `reviews` |
| G Einstellungen | `settings`, `profile`, `notifications`, Onboarding Schritte 2–4 |
| H Erweiterungen | `sharepair`, `shareimport`, `shareresult` (Teilen-Erweiterung), `widgetsetup`, `widget`, `liveactivity` |
| I Dunkelmodus | je eine dunkle Fassung von S1, S2, S4, S5 Liste, S12 + Token-Tabelle Dunkel |

## 8. Technik (SwiftUI unter xtool)

- **Schriften:** TTF/OTF als SwiftPM-Ressource (`Resources/fonts/`), beim App-Start mit `CTFontManagerRegisterFontsForURL(url, .process, nil)` registrieren (kein `UIAppFonts` nötig, xtool-tauglich). Fraunces-Achsen (`SOFT`, `WONK`, `opsz`, `wght`) über `UIFontDescriptor` + `kCTFontVariationAttribute` setzen, Größe über `UIFontMetrics(forTextStyle:).scaledFont` → `Font(uiFont)`. **Spike zuerst** (18.2): wenn Variationsachsen nicht greifen, statische Schnitte nehmen (Fraunces 144pt SuperSoft ExtraBold / Italic). Widget und Teilen-Erweiterung registrieren die Schriften aus ihrem eigenen Bundle; schlägt das fehl, dort SF Pro (dokumentieren).
- **Shapes:** `BurstShape(points: 28, inner: 0.82)`, `ReceiptShape(tooth: 9)`, `CouponShape(notch: 13, at: 0.64)`, `FolderShape(tabWidth: 0.56, tabHeight: 34, …)`, `ScribbleShape` (Pfad aus 5), `BumpBarShape` (Kapsel mit Wölbung). Alle als `Shape`, Füllung über `.fill`, keine Masken-Tricks.
- **Foto-Farbe (RecipeHero):** `CIAreaAverage` auf dem geladenen Bild, Ergebnis auf HSB-Helligkeit 0.25–0.3 setzen; Cache je Bild-URL.
- **Papierkorn:** ein Overlay in `MainView` über allem (`.allowsHitTesting(false)`, `.blendMode(.multiply)`), nicht pro Screen.
- **Logos:** `StoreLogo` nutzt `API.logos` (Wikimedia-URLs, E44) mit `AsyncImage` + `URLCache`; Platzhalter beim Laden: Kürzel.
- **Performance:** Schatten-Radius ≤ 40 nur auf wenigen Ebenen; Blur im Menü einmal über einen Snapshot bzw. `.blur` auf dem Inhalts-Container.
- **Bewegung reduzieren:** Fächer ohne Versatz, Handkreis sofort, keine Feder.
- **Theme.swift:** Tokens aus 2–4 ersetzen die alten (Orange-Akzent fällt weg). Alte Token-Namen, die Views noch nutzen, einmal umbenennen (kein Alias-Gemisch): `accent` → `lime` (Aktion) bzw. `deal` (Preis-Hervorhebung) – je Stelle entscheiden, bei Unklarheit fragen.

## 9. Bau-Reihenfolge und Prüfung

1. Grundlage: Tokens, Schriften, Shapes, Papierkorn, Tab-Leiste, Summen-Leiste.
2. Bausteine (Abschnitt 5) + Bausteine-Galerie als Demo-Screen `components` (neu, für CI-Vergleich mit Teil 1 des Mockups).
3. Gemockte Screens (6.1) in dieser Reihenfolge: Start → Plan → Rezept → Kochmodus → Angebote → Angebot → Einkauf → Liste → Rezepte → Schnell-Aktionen → Onboarding 1.
4. Gruppen A–I aus 7: je Gruppe Mockup → Freigabe → Bau → Prüfung.
5. Web-PWA (`backend/app/web/static/app.css`, Templates): gleiche Tokens als CSS-Variablen, Schriften über Google Fonts bzw. selbst gehostet, Bausteine Liste/Bon/Chips/Tab-Leiste.
6. Aufräumen: alte Bausteine/Tokens löschen (`HeroImage`, Orange, Glas-Leiste), `design-system.md` + `screens.md` auf v3, Playbook-Log.

**Prüfen je Screen:** committen + pushen → CI „iOS Screenshots“ → `gh run download <id> --name screenshots --dir .debug/ci` → `tools/contact_sheet.py` → neben das Mockup-Telefon legen (gleiche Breite 390). Abweichung in Layout, Farbe, Schrift oder Abstand = nicht fertig. Danach Gerät-Check mit `tools/iphone-shot.ps1` (nur `.debug/`).
