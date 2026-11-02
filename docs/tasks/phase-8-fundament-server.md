# Phase 8 – Fundament: Personen, Vorrat, Push (VPS kommt in Phase 17)

Details, Abläufe und Abnahmekriterien: [`docs/features/spec-p08-fundament.md`](../features/spec-p08-fundament.md). Jede Aufgabe erst abhaken, wenn die Abnahme des Features erfüllt ist.

## Aufgaben

- [x] Lokaler Scheduler-Thread (`SCHEDULER=1`, `dev.sh serve`) mit allen Jobs aus der Spezifikation, `job_run`-Protokoll, `python -m app.jobs <name>` (Backend, E47)
- [x] `price_history` echt füllen (Tabelle `price_point` aus 28): Import schreibt Punkte, Job nach jedem Import, Rückfüllung aus gespeicherten Angeboten, `GET /offers/{id}/history` (E49); `watch_alarms`, `coupon_expiry`, `week_review`, `achievements` folgen in Phase 12–14
- [x] Push über ntfy.sh (Backend): Topic pro Mitglied, `GET /me/push`, `POST /me/push/test`, `GET/PATCH /me/push/settings`, Plan-Erinnerung + Neu-Installations-Erinnerung (E47)
- [x] Push auf Apple Push (APNs) umgestellt (Backend): `push_device`, `POST/DELETE /me/push/device`, Ruhezeit über `push_outbox`, ntfy entfernt (E52)
- [ ] Push iOS (Nutzerentscheidung: APNs statt ntfy): Einstellungen › Benachrichtigungen (Erlaubnis, Test-Push, Einstellungen), Erklär-Sheet, Token an `POST /me/push/device`, URL-Schema `essenapp://` + Router – UI fertig; offen: bezahlter Account + `aps-environment` (Backend `/me/push/device` + APNs-Versand fertig, E52)
- [x] 48 `member_profile` + `GET/PATCH /me/profile`, Portionsfaktoren, Esser pro Slot im Planner (Backend, E46)
- [x] 48 iOS: S15 Mein Profil, Umschalter „Für: …“ im Rezept, Esser-Avatare im Plan-Kopf (Tages-Ringe kcal/Protein folgen mit Nährwerten aus 2)
- [x] 60 `pantry_item` + CRUD + `/pantry/consume`, Basics-Flag, Planner/Pricing/sync-plan nutzen Vorrat (Backend, E46)
- [x] 60 iOS: Einkauf › Pille „Vorrat“ (S16), „In den Vorrat?“-Toast beim Abhaken, „Gekocht“ zieht ab
- [ ] `docs/ui/screens.md` + `Demo.swift` + `ios/tools/screenshots.sh` um neue Screens ergänzt, CI-Screenshots geprüft
- [ ] Playbook-Entscheidungslog aktualisiert

## DoD

- Alles aus den Abnahme-Abschnitten von 48, 60 erfüllt; Test-Push (APNs) kommt an und öffnet die App
- Preisverlauf-Daten werden ab jetzt wöchentlich gesammelt
