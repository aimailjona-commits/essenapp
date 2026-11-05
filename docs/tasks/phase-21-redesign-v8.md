# Phase 21 – Redesign v8 „Tinte & Bogen“ (ganzes UI, 1:1 nach Mockup)

Bauanleitung: [`docs/ui/redesign-v8.md`](../ui/redesign-v8.md). Vorlage: `docs/ui/mockups/redesign-v8.html`, `redesign-v8-alle.html`, `animationen-v8.html`. Entscheidung E98. Löst Phase 18 (v3) ab.

Ablauf: erst Grundlage (21.1, ein Paket), dann die Screen-Gruppen A–F parallel (je eigene Dateien), dann CI-Vergleich und Nacharbeit. Eine Bau-Aufgabe ist erst fertig, wenn der CI-Screenshot neben dem Mockup-Telefon passt.

## 21.1 Grundlage iOS

- [x] 👤 Download freigegeben (2026-11-04): DM Serif Display, Manrope, Inter Tight (OFL, google/fonts) → feste Schnitte per `ios/tools/make_fonts.py` nach `Resources/fonts/`; Fraunces/JetBrains Mono raus
- [x] Illustrationen `docs/ui/mockups/ill-v7/*.webp` → `ios/Sources/Essenapp/Resources/ill/`
- [x] `Theme.swift` auf v8-Tokens (Farben, Schriften, Maße); alte Token-Namen auf v8 abgebildet; App fest hell bis 21.2
- [x] `V8Components.swift`: alle Bausteine aus redesign-v8.md Abschnitt 3; Icons aus dem Mockup per `ios/tools/make_icons.py` → `Icons8.swift`
- [x] `NotchTabBar` (Mulde, gleitend) ersetzt v3-Tab-Leiste; Papier-Korn raus
- [x] `PotLoader`, `Hop3`
- [x] Build in WSL grün

## 21.2 Dunkelmodus (Nutzerwunsch 2026-11-04: mitentwerfen)

- [x] Dunkel-Mockup v8 (Kern-Screens + Bausteine) in `docs/ui/mockups/redesign-v8-dunkel.html`
- [ ] 👤 Freigabe
- [ ] Dunkel-Werte in `Theme.swift` + redesign-v8.md, App folgt wieder dem System

## 21.3 Screen-Gruppen (parallel, Dateien siehe redesign-v8.md Abschnitt 4)

- [x] A Start & Planen
- [x] B Rezepte & Kochen
- [x] C Angebote
- [x] D Einkauf, Vorrat, Coupons, Kühlschrank, Live-Aktivität
- [x] E Onboarding, Einstellungen, Teilen-Erweiterung, Widget
- [x] F Ausgaben, Erfolge, Rückblick
- [ ] Ohne v8-Mockup nur auf Tokens/Bausteine umgestellt: Paywall, Swipe (→ 👤 Mockup nachreichen?)

## 21.4 Animationen

- [ ] Alle 15 aus `animationen-v8.html` an ihren Stellen (Tabelle redesign-v8.md Abschnitt 5), „Bewegung reduzieren“ beachtet

## 21.5 Prüfen

- [x] CI-Screenshots aller Demo-Fälle ↔ Mockup, Abweichungen nachgebaut (3 Läufe, 82 Screens; Rest unten)
- [ ] 👤 Abnahme auf dem iPhone

## 21.6 Web-PWA

- [x] `backend/app/web/static/app.css`: v8-Tokens, Schriften, Bausteine (Nav mit Mulde, Zeilen, Chips, Knöpfe)
- [x] Templates auf v8, Prüfung im Browser bei 390 px

## 21.7 Abschluss (DoD)

- [x] Kein Screen nutzt noch v3-Bausteine; `V3Components.swift`, Grain, Fraunces/JetBrains entfernt (FlowLayout, hidesTabBar → V8Components)
- [ ] `design-system.md`/`screens.md` verweisen auf redesign-v8.md
- [ ] Phase 18 als „abgelöst“ markiert

## Offen / ohne Mockup

(beim Bau gefundene Lücken hier eintragen)

- PWA: keine eigenen Web-Mockups – zusammengesetzt aus S1/S2, S5b, S6.1, S37, Leer-Zustand; Einkaufsliste beginnt unter dem blauen Blatt (größere Lücke)
- iOS: ohne Mockup selbst gebaut – Laden/Leer/Fehler-Zustände, Formular Seite 3+4, Rückblick Seiten 4+5, Paywall, Swipe (nur Tokens/Bausteine)
- iOS: offen 👤 „Plan erstellen“ ohne Plan → Swipe (heute) oder Generator (Mockup-Text)?
- iOS: Kleinigkeiten – Filter-Badge offersempty 4 statt 3, Drogerie-Monatsaktionen 1 statt 3, Live-Aktivität „5/12“ abgeschnitten, Zutaten ohne Zeichnung zeigen Blatt-Icon
- iOS: Erweiterungen (Teilen, Widget) ohne eigene Schriften → Systemschrift
- Vorfall 2026-11-05: Prüfbau-Befehle der Agenten liefen als `rsync --delete … /`; gestoppt, kein Schaden an Repo/Nutzerdaten; `build.sh` verweigert jetzt Ziele außerhalb `~/build/`
