# Phase 22 – v9-Umbau nach iPhone-Test (E101)

Mockups: [`docs/ui/mockups/redesign-v9-entwurf.html`](../ui/mockups/redesign-v9-entwurf.html) (Teile in `docs/ui/mockups/v9-parts/`). Stil v8 + E99 (Crimson Pro, Weiß). Gewählte Varianten (Nutzer 2026-11-05):

| Bereich | Variante | Mockup-Teil | Dateien |
|---|---|---|---|
| Gericht – Nährwerte | **C** Säulen gegen deine Woche | `a.html` | `PlanViews.swift` (RecipeDetailView, Teil 2), neu `NutritionColumns.swift` |
| Deine Woche | **A** Rad (pro Tag einrasten) | `b.html` | `PlanViews.swift` (WeekPlanView), neu `WeekWheel.swift` |
| Angebote | **C** Ein Markt im Fokus | `c.html` | `OffersView.swift` |
| Einkauf | Übersicht **B** Taschen-Reihe, geöffnete Liste **A** | `d.html` | `ShoppingView.swift`, neu `ShoppingBags.swift` |
| Swipen | **A** Wochen-Tisch + „Mag ich nicht“-Sheet (D), links = mag ich (E100) | `e.html` | `Swipe.swift`, `PlanViews.swift` (DislikeDialog) |
| Start | **1A** Bereiche + Tab-Leiste Start · Woche · + · Angebote · Einkauf | `f.html` | `StartView.swift`, `ContentView.swift`, `Components.swift`/`V8Components.swift` (Tab-Leiste) |
| Alle Funktionen | **2A** „+“ öffnet „Alles“ + Abschnitt „Noch nicht ausprobiert“ aus 2B | `f.html` | neu `AllSheet.swift` |

## 22.1 Umbau (parallel, getrennte Dateien)

- [x] G1 Gericht: Zusammensetzung (Blüte) raus, Säulen-Statistik C
- [x] G2 Woche: Rad A, Scroll-getrieben, Tag ↔ Teller auf einer Höhe
- [x] G3 Angebote: Markt-Fokus C
- [x] G4 Einkauf: Taschen-Reihe B + geöffnete Liste A
- [x] G5 Swipen: Wochen-Tisch A + Mag-ich-nicht-Sheet
- [x] G6 Start 1A, neue Tab-Leiste (Rezepte unter „+“), „Alles“-Sheet 2A mit „Noch nicht ausprobiert“

## 22.2 Gleiche Knöpfe überall (Mockup `f.html` Abschnitt 3)

- [ ] Gericht-Aktionsleiste (Kochen · Tauschen · Liste · Teilen · Mehr) + ein gemeinsames Gericht-Menü, in Woche, Start, Rezepte, Swipe
- [ ] Angebots-Aktionen (Merken · Auf Liste · Rezepte damit) in jeder Angebotszeile

## 22.3 Prüfen

- [ ] Build, CI-Screenshots ↔ Mockup
- [ ] 👤 iPhone

## Offen

- Annahmen der Agents (👤 prüfen): Tagesbedarf KH/Fett/Ballaststoffe nach DGE; Zucker/Salz fehlen im Backend; „Gekocht x/y“ = vergangene Tage; „+ Abend dazuplanen“ öffnet den Tag (kein Endpunkt); Taschenform je Kette fest; nur eine Zutat pro „Mag ich nicht“; Farben Frühstück/Snack angenommen; Fleisch/Getränke/Haushalt ohne Zeichnung.
- Web-PWA nachziehen (gleiche Varianten) – nach iOS-Abnahme.
