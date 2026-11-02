# Phase 9 – Rezepte, Instagram-Import, Kühlschrank-Foto

Details, Abläufe und Abnahmekriterien: [`docs/features/spec-p09-rezepte-import.md`](../features/spec-p09-rezepte-import.md). Jede Aufgabe erst abhaken, wenn die Abnahme des Features erfüllt ist.

## Aufgaben

- [ ] Spike: Share Extension mit xtool + kostenlose Apple-ID (App Group/Keychain?) → Ergebnis ins Playbook (A1)
- [x] 3 Modelle `recipe_favorite`, `rating`, Felder source/source_url/source_author/tags; Endpunkte /recipes …, Foto-Upload `/media/recipes`, `…/replace` (Backend, E50)
- [ ] 3 iOS: Meine Rezepte (Filter, Suche, Raster), Rezept-Formular S17, Bewertung speichern, „Diese Woche einplanen“
- [x] 3 Planner: Favoriten/Bewertungen/Nie-Liste, 3-Wochen-Regel, „Rezept im Angebot“ (`GET /recipes/deals`) (Backend, E50; Start-Karte in der App folgt mit 3 iOS)
- [ ] 1 Zutat antippen → Angebot / Sheet „Angebote für …“ / Vorrat
- [x] 2 USDA-Import `food`, `ingredient_map` (Haiku-Zuordnung, Cache), Nährwert-Rechnung pro Person (Backend, E51)
- [ ] 2 iOS: Nährwert-Kacheln, Blüten-Diagramm (animiert), Tagesringe pro Person
- [ ] 5 `POST /import`: Instagram-Einbettungsseite, schema.org-Recipe, Haiku → Rezept
- [ ] 5 Share Extension `EssenappShare` (bzw. Ersatz laut Spike), Vorschau-Sheet, Speichern/Einplanen
- [ ] 9 Knopf „Original-Reel“; KI-Schritt-Bilder (fal.ai, gespeichert unter /media), Einstellung an/aus
- [ ] 69 Kamera-Sheet (mehrere Fotos, Modi), `POST /pantry/scan` (Haiku Vision), Prüf-Bildschirm
- [ ] 69 „Was koche ich jetzt?“ (3 Vorschläge) + „Heute kochen“
- [ ] `docs/ui/screens.md` + `Demo.swift` + `ios/tools/screenshots.sh` um neue Screens ergänzt, CI-Screenshots geprüft
- [ ] Playbook-Entscheidungslog aktualisiert

## DoD

- Abnahme aus 3, 1, 2, 5, 9, 69 erfüllt (inkl. 3 echte Instagram-Reels importiert)
