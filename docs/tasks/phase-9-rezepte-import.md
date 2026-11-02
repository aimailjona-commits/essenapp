# Phase 9 – Rezepte, Instagram-Import, Kühlschrank-Foto

Details, Abläufe und Abnahmekriterien: [`docs/features/spec-p09-rezepte-import.md`](../features/spec-p09-rezepte-import.md). Jede Aufgabe erst abhaken, wenn die Abnahme des Features erfüllt ist.

## Aufgaben

- [ ] Spike: Share Extension mit xtool + kostenlose Apple-ID (App Group/Keychain?) → Ergebnis ins Playbook (A1)
- [x] 3 Modelle `recipe_favorite`, `rating`, Felder source/source_url/source_author/tags; Endpunkte /recipes …, Foto-Upload `/media/recipes`, `…/replace` (Backend, E50)
- [ ] 3 iOS: Meine Rezepte (Filter, Suche, Raster), Rezept-Formular S17, Bewertung speichern, „Diese Woche einplanen“
- [x] 3 Planner: Favoriten/Bewertungen/Nie-Liste, 3-Wochen-Regel, „Rezept im Angebot“ (`GET /recipes/deals`) (Backend, E50; Start-Karte in der App folgt mit 3 iOS)
- [ ] 1 Zutat antippen → Angebot / Sheet „Angebote für …“ / Vorrat
- [x] 2 USDA-Import `food`, `ingredient_map` (Haiku-Zuordnung, Cache), Nährwert-Rechnung pro Person (Backend, E51)
- [x] 2 Nährwerte im Angebotsdetail `GET /offers/{id}/nutrition` (Backend, E57)
- [ ] 2 iOS: Nährwert-Kacheln, Blüten-Diagramm (animiert), Tagesringe pro Person, Nährwerte im Angebotsdetail
- [x] 5 `POST /import`: Instagram-Einbettungsseite, schema.org-Recipe, Haiku → Rezept (Backend, E54; Abnahme „3 echte Reels mit Rezept in < 15 s“ noch offen)
- [x] 5 Kopplungscode `POST /me/pairing-code`, `POST /pair`, Widerruf (Backend, E53)
- [ ] 5 Share Extension `EssenappShare` (bzw. Ersatz laut Spike), Vorschau-Sheet, Speichern/Einplanen
- [x] 9 KI-Schritt-Bilder (fal.ai, gespeichert unter /media/steps), Einstellung an/aus (Backend, E55)
- [ ] 9 iOS: Knopf „Original-Reel“, Schritt-Bilder mit Schimmer, Schalter in den Einstellungen
- [x] 69 `POST /pantry/scan` (Haiku Vision), `POST /pantry/bulk` (Backend, E56)
- [ ] 69 iOS: Kamera-Sheet (mehrere Fotos, Modi), Prüf-Bildschirm
- [x] 69 „Was koche ich jetzt?“ `POST /pantry/cook-now` (3 Vorschläge, Backend, E56)
- [ ] 69 iOS: Sheet „Was koche ich jetzt?“ + „Heute kochen“
- [ ] `docs/ui/screens.md` + `Demo.swift` + `ios/tools/screenshots.sh` um neue Screens ergänzt, CI-Screenshots geprüft
- [ ] Playbook-Entscheidungslog aktualisiert

## DoD

- Abnahme aus 3, 1, 2, 5, 9, 69 erfüllt (inkl. 3 echte Instagram-Reels importiert)
