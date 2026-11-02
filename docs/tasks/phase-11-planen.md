# Phase 11 – Clever planen

Details, Abläufe und Abnahmekriterien: [`docs/features/spec-p11-planen.md`](../features/spec-p11-planen.md). Jede Aufgabe erst abhaken, wenn die Abnahme des Features erfüllt ist.

## Aufgaben

- [x] 12 Backend: Regeln in `household.variety`, KI-Tags, Prüfung + Teil-Reparatur, `PlanOut.variety` (E59; Abnahme: 10 Testpläne mit gefälschter KI + 2 echte Pläne ✓)
- [ ] 12 iOS: Einstellungen › Präferenzen › „Abwechslung“, Chip im Plan-Kopf
- [x] 15 Backend: `PlanOptions.guests`/`guest_budget_cents`, `…/entries/{id}/guests` (E60)
- [ ] 15 iOS: „+ Gäste“-Stepper auf den Tagespillen, Badge, „Gäste hinzufügen“
- [x] 16 Backend: `POST /no-mood` (live ~6 s), `POST /plans/current/postpone` (E60)
- [ ] 16 iOS: Knopf „😮‍💨 Keine Lust“, Sheet mit Wischen, „Auf morgen verschieben?“
- [x] 17 Backend: Plan-Erinnerung per APNs (E47/E52), `GET /plans/generator` mit Top-3-Angeboten (E60); Ende-zu-Ende erst mit APNs-Schlüssel
- [ ] 17 iOS: Generator mit Standards + „Diese Woche im Angebot: …“ nach `essenapp://generator`
- [x] 19 Backend: Reste im Pricing, Durchgang 2, `MealOut.rests`, `PlanOut.leftovers`, `…/leftovers` → `/pantry/bulk` (E59)
- [ ] 19 iOS: Badge „♻︎ Rest von Mo“, Reste-Karte, Reste nach dem Kochen bestätigen
- [x] 23 Backend: `weekly_basic` + Job Mo 06:30, Frühstücksregeln, Mahlzeit `snack` (E61)
- [ ] 23 iOS: Einstellungen „Frühstück & Snacks“, Snack-Chip im Generator
- [x] 24 Backend: Slot `lunchbox` je Mitglied/Tag, Regeln, Abend-Push `lunchbox_push` (E61)
- [ ] 24 iOS: Lunchbox-Karte mit 🥡, Push-Einstellung, Deep Link `essenapp://recipe/<id>`
- [x] 25 Backend: `services/seasons.py`, `GET /specials`, `PlanOptions.special`, Saison im Prompt (E62)
- [ ] 25 iOS: Start-Banner, Generator mit Special-Vorlage
- [ ] `docs/ui/screens.md` + `Demo.swift` + `ios/tools/screenshots.sh` um neue Screens ergänzt, CI-Screenshots geprüft
- [ ] Playbook-Entscheidungslog aktualisiert

## DoD

- Abnahme aus 12, 15, 16, 17, 19, 23, 24, 25 erfüllt
