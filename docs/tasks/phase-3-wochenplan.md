# Phase 3 – Wochenplan

Ziel: Ein Wochenplan nach Angeboten, Budget und Vorlieben, mit Einkaufsliste.

## Backend

- [ ] Zutaten-Stammdaten: Nährwerte (Open Food Facts / BLS, Lizenz prüfen), Normalpreis-Schätzung, typische Packungsgröße
- [~] Modelle: `recipe` (Zutaten als JSON, E31), `meal_plan`, `meal_plan_entry` ✓; `shopping_item` offen
- [x] Pricing-Service: Einkaufs- vs. Verbrauchskosten, ganze Packungen, Reste (Tests)
- [~] Nutrition-Service gerechnet + Tests; fehlt: Zutaten-Stammdaten als Datenquelle
- [x] Planner: Claude (strukturierte Ausgabe) → Kosten → Budget-Reparatur (max. 2), live getestet. Favoriten folgen mit Phase 4
- [ ] Rezeptbilder nach Entscheidung aus Phase 0
- [ ] Einkaufsliste nach Läden, Ersparnis
- [~] API: Plan erzeugen/lesen ✓; neu würfeln/fixieren/ersetzen, Einkaufsliste im Backend offen

## iOS

- [ ] Einstellungen: Küche, Mahlzeiten, Tage, Budget, Ernährung, Allergien, Nährwertziel, Kochzeit
- [~] Plan-Generator-Sheet + Lade-Zustand (Einstellungen nur anzeigen, nicht pro Plan änderbar)
- [x] Wochenplan-Screen (Tagesleiste, Karten; Würfeln/Fixieren folgt)
- [~] Rezeptdetail (Zutaten mit Angebot/Laden, Schritte, Bewertung-Sheet); Nährwerte + Blüten-Diagramm fehlen (Stammdaten)
- [~] Einkaufsliste nach Läden, offline abhakbar (lokal, E31); Sync offen
- [x] Start-Screen mit „Heute“, Wochenüberblick, Budget-Karte

## DoD

- Plan in < 60 s, Budget eingehalten, Allergien respektiert, Einkaufsliste passt zu den Rezepten.
- Pricing und Nutrition haben Tests.
