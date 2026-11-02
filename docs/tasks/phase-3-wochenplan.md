# Phase 3 – Wochenplan

Ziel: Ein Wochenplan nach Angeboten, Budget und Vorlieben, mit Einkaufsliste.

## Backend

- [ ] Zutaten-Stammdaten: Nährwerte (Open Food Facts / BLS, Lizenz prüfen), Normalpreis-Schätzung, typische Packungsgröße
- [ ] Modelle: `recipe`, `recipe_ingredient`, `meal_plan`, `meal_plan_entry`, `shopping_item`
- [ ] Pricing-Service: Einkaufs- vs. Verbrauchskosten, ganze Packungen, Reste (Tests!)
- [ ] Nutrition-Service: pro Portion und Tag (Tests!)
- [ ] Planner: Kandidaten → Claude (strukturierte Ausgabe) → Validierung → Reparaturschleife (max. 2)
- [ ] Rezeptbilder nach Entscheidung aus Phase 0
- [ ] Einkaufsliste nach Läden, Ersparnis
- [ ] API: Plan erzeugen, Plan lesen, Gericht neu würfeln/fixieren/ersetzen, Einkaufsliste lesen/abhaken

## iOS

- [ ] Einstellungen: Küche, Mahlzeiten, Tage, Budget, Ernährung, Allergien, Nährwertziel, Kochzeit
- [ ] Plan-Generator-Sheet + Lade-Zustand
- [ ] Wochenplan-Screen
- [ ] Rezeptdetail (inkl. Nährwert-Chips und Anteils-Diagramm)
- [ ] Einkaufsliste (offline abhakbar, Sync)
- [ ] Start-Screen mit „Heute“ und Wochenüberblick

## DoD

- Plan in < 60 s, Budget eingehalten, Allergien respektiert, Einkaufsliste passt zu den Rezepten.
- Pricing und Nutrition haben Tests.
