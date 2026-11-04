# Phase 21 – Redesign v8 „Tinte & Bogen“ (ganzes UI, 1:1 nach Mockup)

Bauanleitung: [`docs/ui/redesign-v8.md`](../ui/redesign-v8.md). Vorlage: `docs/ui/mockups/redesign-v8.html`, `redesign-v8-alle.html`, `animationen-v8.html`. Entscheidung E98. Löst Phase 18 (v3) ab.

Ablauf: erst Grundlage (21.1, ein Paket), dann die Screen-Gruppen A–F parallel (je eigene Dateien), dann CI-Vergleich und Nacharbeit. Eine Bau-Aufgabe ist erst fertig, wenn der CI-Screenshot neben dem Mockup-Telefon passt.

## 21.1 Grundlage iOS

- [ ] 👤 Download freigegeben (2026-11-04): DM Serif Display, Manrope, Inter Tight (OFL, google/fonts) → feste Schnitte per `ios/tools/make_fonts.py` nach `Resources/fonts/`; Fraunces/JetBrains Mono raus
- [ ] Illustrationen `docs/ui/mockups/ill-v7/*.webp` → `ios/Sources/Essenapp/Resources/ill/`
- [ ] `Theme.swift` auf v8-Tokens (Farben, Schriften, Maße); App fest hell bis 21.2
- [ ] `V8Components.swift`: alle Bausteine aus redesign-v8.md Abschnitt 3
- [ ] `NotchTabBar` (Mulde, gleitend) ersetzt v3-Tab-Leiste; Papier-Korn raus
- [ ] `PotLoader`, `Hop3`
- [ ] Build in WSL grün

## 21.2 Dunkelmodus (Nutzerwunsch 2026-11-04: mitentwerfen)

- [ ] Dunkel-Mockup v8 (Kern-Screens + Bausteine) in `docs/ui/mockups/redesign-v8-dunkel.html`
- [ ] 👤 Freigabe
- [ ] Dunkel-Werte in `Theme.swift` + redesign-v8.md, App folgt wieder dem System

## 21.3 Screen-Gruppen (parallel, Dateien siehe redesign-v8.md Abschnitt 4)

- [ ] A Start & Planen
- [ ] B Rezepte & Kochen
- [ ] C Angebote
- [ ] D Einkauf, Vorrat, Coupons, Kühlschrank, Live-Aktivität
- [ ] E Onboarding, Einstellungen, Teilen-Erweiterung, Widget
- [ ] F Ausgaben, Erfolge, Rückblick
- [ ] Ohne v8-Mockup nur auf Tokens/Bausteine umgestellt: Paywall, Swipe (→ 👤 Mockup nachreichen?)

## 21.4 Animationen

- [ ] Alle 15 aus `animationen-v8.html` an ihren Stellen (Tabelle redesign-v8.md Abschnitt 5), „Bewegung reduzieren“ beachtet

## 21.5 Prüfen

- [ ] CI-Screenshots aller Demo-Fälle ↔ Mockup, Abweichungen nachgebaut
- [ ] 👤 Abnahme auf dem iPhone

## 21.6 Web-PWA

- [ ] `backend/app/web/static/app.css`: v8-Tokens, Schriften, Bausteine (Nav mit Mulde, Zeilen, Chips, Knöpfe)
- [ ] Templates auf v8, Prüfung im Browser bei 390 px

## 21.7 Abschluss (DoD)

- [ ] Kein Screen nutzt noch v3-Bausteine; `V3Components.swift`, Grain, Fraunces/JetBrains entfernt
- [ ] `design-system.md`/`screens.md` verweisen auf redesign-v8.md
- [ ] Phase 18 als „abgelöst“ markiert

## Offen / ohne Mockup

(beim Bau gefundene Lücken hier eintragen)
