# Phase 18 – Redesign v3 „Küchen-Pinnwand“ (ganzes UI, 1:1 nach Mockup)

Bauanleitung mit allen Werten: [`docs/ui/redesign-v3.md`](../ui/redesign-v3.md). Vorlage: [`docs/ui/mockups/redesign-v3.html`](../ui/mockups/redesign-v3.html). Entscheidung E87.

Regeln: nur Werte aus `redesign-v3.md`/Mockup. Was nicht gemockt ist, zuerst mocken und freigeben lassen (Abschnitt 7), dann bauen. Jede Bau-Aufgabe erst abhaken, wenn der CI-Screenshot neben dem Mockup-Telefon passt (Abschnitt 9). Läuft parallel zu Phase 17 (die wartet auf 👤).

## 18.1 Vorbereitung (Doku)

- [ ] a `docs/ui/design-system.md` auf v3: Farben, Schrift, Maße, Bausteine aus `redesign-v3.md` Abschnitte 2–5 (alte v2-Tabellen raus, Hinweis „Quelle: redesign-v3.md“)
- [ ] b `docs/ui/screens.md`: Verhaltensänderungen aus `redesign-v3.md` 6.2 eintragen, Kopf auf „v3“
- [ ] c Mockup Teil 3, Gruppe I (Dunkelmodus) zeichnen → 👤 Freigabe → Dunkel-Werte in `redesign-v3.md` Abschnitt 2

## 18.2 Grundlage iOS

- [ ] 👤 Download freigeben: Fraunces (variabel, inkl. Italic) + JetBrains Mono von Google Fonts / GitHub (OFL), Dateien + `OFL.txt` nach `ios/Sources/Essenapp/Resources/fonts/`
- [ ] Spike Schriften: Registrierung per `CTFontManagerRegisterFontsForURL`, Fraunces-Achsen `SOFT/WONK/opsz/wght`, Dynamic Type; Ergebnis als E-Eintrag (variabel oder statische Schnitte)
- [ ] `Theme.swift` auf v3-Tokens (Farben, Wochentage, Tönungen, Schriften, Radien, Schatten); alte Token-Nutzung in allen Views umgestellt, Orange-Akzent entfernt
- [ ] Shapes: `BurstShape`, `ReceiptShape`, `CouponShape`, `FolderShape`, `ScribbleShape`, `BumpBarShape` (+ `swift test` für Punktzahl/Geometrie der Stern- und Zackenform)
- [ ] `PaperGrain` (Skript `ios/tools/make_grain.py`, PNG als Ressource, Overlay in `MainView`)
- [ ] `TabBar` v3 (schwarze Kapsel, gleitende weiße Pille, Limetten-Mitte, Zähler) – ersetzt Liquid Glass
- [ ] `TotalBar` + Tab-Leiste auf Detail-Screens ausblenden

## 18.3 Bausteine

- [ ] Alle Bausteine aus `redesign-v3.md` Abschnitt 5 (umbauen/neu), Namen wie dort
- [ ] Demo-Screen `components` (Galerie wie Mockup Teil 1) in `Demo.swift`/`MainView` + `ios/tools/screenshots.sh`
- [ ] CI-Vergleich `components` ↔ Mockup Teil 1 passt

## 18.4 Gemockte Screens (1:1, `redesign-v3.md` 6.1)

- [ ] S1 Start (oberer Teil + „Diese Woche“)
- [ ] S2 Wochenplan (Kopf, Tagesleiste, Tageskarten)
- [ ] S3 Rezeptdetail (Kopf bis Zutaten + Summen-Leiste)
- [ ] S18 Kochmodus
- [ ] S4 Angebote
- [ ] S9 Angebotsdetail (oberer Teil + Summen-Leiste)
- [ ] S5 Einkauf (Ordner mit Logos)
- [ ] S5 Liste (Kassenbon)
- [ ] S12 Rezepte (Kachel-Wand)
- [ ] Schnell-Aktionen (Fächer + Wölbung, Animation)
- [ ] S6 Onboarding Schritt 1

## 18.5 Restliche Screens (je Gruppe: Mockup → 👤 Freigabe → Bau → CI-Vergleich)

- [ ] A Start & Plan komplett (`start` unten, `empty`, `generator`, `generating`, `nomood`, `guests`, `leftovers`, `basics`, `variety`, Bewertung)
- [ ] B Rezepte (`recipe` unten, `myrecipe`, `recipeform`, `imported`, `importlink`, `instagram`, `sharecard`, `substitute`, `recipelink`, `sharedrecipe`)
- [ ] C Angebote (`offer` unten, `offerstock`, `watch`, `scanner`, `nextweek`, `stores`, `singlestore`)
- [ ] D Einkauf & Vorrat (`list` Kategorien, `pantry`, `voiceadd`, `offline`, `storeask`, `fridgecam`, `fridgereview`, `cooknow`)
- [ ] E Sparen & Bonus (`savings`, `budgetover`, `wallet`, `bonus`, `coupon`, `couponadd`, `spending`)
- [ ] F Motivation (`achievements`, `unlock`, `review`, `reviews`)
- [ ] G Einstellungen & Onboarding 2–4 (`settings`, `profile`, `notifications`, `onboarding`)
- [ ] H Erweiterungen (Teilen-Erweiterung `sharepair`/`shareimport`/`shareresult`, `widgetsetup`, `widget`, `liveactivity`)
- [ ] I Dunkelmodus für alle Screens (`dark-*` in CI)

## 18.6 Web-PWA

- [ ] `backend/app/web/static/app.css`: v3-Tokens als CSS-Variablen (hell + dunkel), Schriften, Bausteine (Tab-Leiste, Chips, Kassenbon-Liste, Ordner, Knöpfe)
- [ ] Templates (`app.html`, `_list.html`) auf v3; Prüfung im Browser bei 390 px

## 18.7 Abschluss

- [ ] Alte Bausteine/Tokens gelöscht (`HeroImage`-Start-Kopf, Orange, Glas-Leiste, ungenutzte Styles), Build ohne Warnungen zu ungenutztem Code
- [ ] `docs/ui/README.md`: v3 als gültige Vorlage, v1-Mockups als „abgelöst“ markiert
- [ ] Playbook-Entscheidungslog ergänzt (Spike-Ergebnis Schriften, Abweichungen)
- [ ] 👤 Abnahme auf dem iPhone (alle Tabs, Menü, Kochmodus, Liste, Dunkelmodus)

## DoD

- Jeder Demo-Screen (hell + dunkel) im CI-Screenshot entspricht dem freigegebenen Mockup (Layout, Farbe, Schrift, Abstand)
- Keine Werte außerhalb von `Theme.swift` / `app.css`; keine gedrehten Karten/Listen, keine Klebebänder, Pastell nie als Schrift auf Hell
- Dynamic Type (bis XXL) und VoiceOver-Labels funktionieren; „Bewegung reduzieren“ beachtet
- Händler-Logos vollständig sichtbar, nur verlinkt (E44)
- 👤 Nutzer hat auf dem iPhone abgenommen
