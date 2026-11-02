# Phase 8 – Fundament: Personen, Vorrat, Push (VPS kommt in Phase 17)

Details, Abläufe und Abnahmekriterien: [`docs/features/spec-p08-fundament.md`](../features/spec-p08-fundament.md). Jede Aufgabe erst abhaken, wenn die Abnahme des Features erfüllt ist.

## Aufgaben

- [ ] Lokaler Scheduler-Thread (`SCHEDULER=1`) mit den Jobs aus der Spezifikation (Import inkl. Folgewoche, Preisverlauf sammeln, Alarme, Plan-Erinnerung …)
- [ ] Push über ntfy.sh: Topic pro Mitglied, Einstellungen › Benachrichtigungen (QR, Test-Push), URL-Schema `essenapp://` + Router in der App
- [ ] 48 `member_profile` + `GET/PATCH /me/profile`, Portionsfaktoren, Esser pro Slot im Planner
- [ ] 48 iOS: S15 Mein Profil, Umschalter „Für: …“ in Rezept/Tag
- [ ] 60 `pantry_item` + CRUD + `/pantry/consume`, Basics-Flag, Planner/Pricing/sync-plan nutzen Vorrat
- [ ] 60 iOS: Einkauf › Pille „Vorrat“ (S16), „In den Vorrat?“-Toast beim Abhaken, „Gekocht“ zieht ab
- [ ] `docs/ui/screens.md` + `Demo.swift` + `ios/tools/screenshots.sh` um neue Screens ergänzt, CI-Screenshots geprüft
- [ ] Playbook-Entscheidungslog aktualisiert

## DoD

- Alles aus den Abnahme-Abschnitten von 48, 60 erfüllt; Test-Push über ntfy.sh kommt an und öffnet die App
- Preisverlauf-Daten werden ab jetzt wöchentlich gesammelt
