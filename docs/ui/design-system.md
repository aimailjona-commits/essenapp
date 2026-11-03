# Design-System

Status: **v3 „Küchen-Pinnwand“ (E87), freigegeben 2026-11-03.** Alle Einzelwerte, Bausteine und Screens stehen in [`redesign-v3.md`](redesign-v3.md); Vorlage [`mockups/redesign-v3.html`](mockups/redesign-v3.html). Quelle der Wahrheit im Code: `ios/Sources/Essenapp/Theme.swift` (iOS) und `backend/app/web/static/app.css` (PWA, Phase 18.6).

Grundidee: warm, Creme, viel Luft, eine fette Stimme. Das Essen und sanfte Pastell-Karten sind die Farbe, Hauptaktionen schwarz, „jetzt loslegen“ in Limette. Eigenheiten: Preis-Stern, Handkreis, Kassenbon, Coupon-Kerben, Papierkorn. Nichts gedreht, keine Klebebänder.

## Farben (Hell)

| Token | Wert | Verwendung |
|---|---|---|
| `bg` / `card` / `surface` | `#F4F1EA` / `#FFFFFF` / `#E9E5DC` | Seite, Karten, Nebenknöpfe |
| `text1` (= `ink`, `action`) / `text2` / `text3` | `#111111` / `#7A766E` / `#B3AEA4` | Text, Primärknöpfe, Tab-Leiste |
| `lime` | `#DCEDA0` | Mittel-Knopf, `AccentButton`, abgehakt, Fortschritt auf Dunkel |
| `deal` / `star` | `#E8694A` / `#E8B33A` | Rabatt, „Heute“ / Sterne |
| Wochentage Mo–So | `#F2B9A8` `#F3DC9E` `#D5CDF0` `#BCD0F2` `#C3E3CF` `#F2CBA6` `#F0CADA` | Tageskarten, Ordner, Kacheln (Schrift immer `ink`) |
| Kategorie-Tönungen | `#E4F5D9` `#FFE3DB` `#DFE9FF` `#FFF1C9` `#ECE6FF` `#FFE4EF` | Produktflächen |

Pastell nie als Schriftfarbe auf hellem Grund. Vollständige Liste (dunkle Flächen, Urteile, Nährwert-Tönungen, Kassenbon): `redesign-v3.md` Abschnitt 2.

## Dark Mode (Feature 68)

Einstellung in S13 › App › „Erscheinungsbild“: **System · Hell · Dunkel** (Standard System). Alle Tokens in `Theme.swift` sind Hell/Dunkel-Paare (`Color(hell, dunkel)`, keine `.xcassets`). v3-Dunkelwerte (freigegeben 2026-11-03): warmes Fast-Schwarz `#121110`, Karten `#1D1C1A`, Creme-Schrift `#F4F1EA`; Pastell, Limette, Kassenbon bleiben hell (Liste: `redesign-v3.md` Abschnitt 2). Immer dunkel: Kochmodus, Start-Kopf, Menü. Immer hell: Bildkarte (Feature 10). Logos und Teller auf weißen Plättchen.

## Schrift

Fraunces (Überschriften, Tages-Satz, Karten-Titel; feste Schnitte `FrauncesV3-*`), SF Pro (alles andere), JetBrains Mono (Kassenbon). Größen und Achsen: `redesign-v3.md` Abschnitt 3, Entscheidung E89. Dynamic Type über `relativeTo` bzw. Textstile.

## Abstände, Radien, Schatten

Seitenrand 20. Radien: Chip 16 · Kachel 22 · Angebotskarte 26 · Rezept-Kachel 28 · Karte 30 · Tageskarte 34 · Sheet 40 · Knöpfe voll rund. Schatten `soft` (y 10, Blur 28, 8 %), `float` (y 18, Blur 40, 22 %), Teller (y 12, Blur 24, 18 %). Details: `redesign-v3.md` Abschnitt 4.

## Animationen

- Standard-Feder `Theme.spring` (response 0.38, damping 0.78); Antippen `PressableStyle` (0.96).
- Gleitende Auswahl (`matchedGeometryEffect`) in Tab-Leiste, Tagesleiste, Segment.
- Handkreis zeichnet sich beim Erscheinen; Fächer-Menü springt gestaffelt auf. „Bewegung reduzieren“ schaltet beides ab.
- Listen gestaffelt (`.appear(delay:)`), Zahlen `.numericText()`, Symbole `.symbolEffect`, Haptik bei Auswahl/Haken/Hinzufügen.

## Icons

SF Symbols, Strichstärke `regular`, in Knöpfen `semibold`; Tab-Leiste nur Symbole (Umriss), kein Text.

App-Icon „Kochpilot“ (E88): Papierflieger in Limette `#C6F36B`/`#9FD24A`/`#7FB33A` zieht an weißer Leine ein Preisschild `deal` mit weißem %, Grund `#14161A`. Quelle: `ios/tools/make_icon.py` (schreibt iOS- und PWA-Icon).

## Komponenten

Liste mit Maßen: `redesign-v3.md` Abschnitt 5. Bestehende Bausteine in `Components.swift`, neue v3-Bausteine (`PriceBurst`, `Scribble`, `ReceiptPaper`/`ReceiptRow`, `FolderCard`, `CouponShape`/`KnallerCard`, `TotalBar`, `QtyStepper`, `StepDots`, `PhotoSticker`, `SentenceHero`, `DayCard`, `RTile`, `PaperGrain`) in `V3Components.swift` bzw. beim jeweiligen Screen.
