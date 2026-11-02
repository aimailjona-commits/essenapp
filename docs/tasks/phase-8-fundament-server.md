# Phase 8 – Fundament: Server, Personen, Vorrat

Details, Abläufe und Abnahmekriterien: [`docs/features/spec-p08-fundament.md`](../features/spec-p08-fundament.md). Jede Aufgabe erst abhaken, wenn die Abnahme des Features erfüllt ist.

## Aufgaben

- [ ] 👤 IONOS-VPS + Domain buchen, SSH-Schlüssel für Claude hinterlegen (A11)
- [ ] 72 Docker Compose: api, db (Postgres), caddy (HTTPS), ntfy, scheduler
- [ ] 72 Daten-Umzug SQLite → Postgres, /media-Volume, Backups + Wiederherstellungstest
- [ ] 72 Scheduler-Jobs laut Tabelle (Import inkl. Folgewoche, Preisverlauf-Punkte sammeln, Alarme, Plan-Erinnerung …)
- [ ] 72 ntfy-Topics pro Mitglied, Einstellungen › Benachrichtigungen (QR, Test-Push), URL-Schema `essenapp://` + Router
- [ ] 72 iOS auf HTTPS umstellen, ATS-Ausnahme entfernen
- [ ] 48 `member_profile` + `GET/PATCH /me/profile`, Portionsfaktoren, Esser pro Slot im Planner
- [ ] 48 iOS: S15 Mein Profil, Umschalter „Für: …“ in Rezept/Tag
- [ ] 60 `pantry_item` + CRUD + `/pantry/consume`, Basics-Flag, Planner/Pricing/sync-plan nutzen Vorrat
- [ ] 60 iOS: Einkauf › Pille „Vorrat“ (S16), „In den Vorrat?“-Toast beim Abhaken, „Gekocht“ zieht ab
- [ ] `docs/ui/screens.md` + `Demo.swift` + `ios/tools/screenshots.sh` um neue Screens ergänzt, CI-Screenshots geprüft
- [ ] Playbook-Entscheidungslog aktualisiert

## DoD

- Alles aus den Abnahme-Abschnitten von 72, 48, 60 erfüllt
- Preisverlauf-Daten werden ab jetzt wöchentlich gesammelt
