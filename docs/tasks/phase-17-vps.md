# Phase 17 – Umzug auf IONOS-VPS (am Ende, Nutzerwunsch)

Details: [`docs/features/spec-p08-fundament.md`](../features/spec-p08-fundament.md) Abschnitt **72**, Anleitung [`deploy/README.md`](../../deploy/README.md), Entscheidungen E86.

## Vorbereitet (ohne VPS, E86)

- [x] Docker Compose: api (2 Worker), db (Postgres 16), caddy (HTTPS), scheduler; Healthchecks, Log-Rotation, Volumes `pgdata`/`media`, APNs-Key read-only aus `backend/secrets/` (kein ntfy, keine `push.`-Subdomain)
- [x] Backend läuft auf Postgres (`DATABASE_URL`, SQLite bleibt lokal Standard); Testsuite grün auf SQLite und Postgres (`TEST_DATABASE_URL`)
- [x] Umzugsskript SQLite → Postgres mit Zählvergleich (mit Kopie der echten DB getestet)
- [x] `backup.sh` (verschlüsselt, 14 Tage, optional rsync) + `restore.sh` (`--test` = Wiederherstellungstest) lokal getestet
- [x] `setup-vps.sh` (Docker, ufw, unattended-upgrades, Benutzer, `.env`, Umzug, Start, Backup-cron)
- [x] `PUBLIC_BASE_URL` für Einladungs-, Listen- und Rezept-Links

## Umzug

- [x] 👤 IONOS-VPS + Domain, SSH-Schlüssel hinterlegt; geteilter VPS → Eingang über Cloudflare-Tunnel statt A-Record/Caddy (E88)
- [x] Lokalen Server stoppen, Daten-Snapshot + Repo auf den VPS, `setup-vps.sh` (2026-11-03; 33 Tabellen, Zählvergleich gleich)
- [~] `https://<domain>/health` ok, Daten-Zählvergleich ok – offen: Einladungslink im Mobilfunk
- [x] Erstes Backup + `restore.sh --test` auf dem VPS (Probe OK)
- [ ] iOS: ATS-Ausnahme entfernen (`ios/Info.plist`, `ios/EssenappWidget-Info.plist`), Server-Adresse `https://…` in App, Widget, Teilen-Erweiterung; Test-Push
- [ ] Nach einer Woche: Angebotsimport vom Rechenzentrum aus läuft (kaufDA)
- [x] Playbook aktualisiert (E88)

## DoD

- Abnahme aus 72 erfüllt (HTTPS, Links im Mobilfunk, Push, Backup getestet)
