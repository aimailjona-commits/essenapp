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

- [ ] 👤 IONOS-VPS (Ubuntu 24.04, ≥ 2 GB) + Domain, SSH-Schlüssel `~/.ssh/essenapp_vps.pub` (WSL) hinterlegen, DNS-A-Record `essenapp.<domain>` (deploy/README.md, Schritte 1–3)
- [ ] Lokalen Server stoppen, Daten-Snapshot + Repo auf den VPS, `setup-vps.sh` (deploy/README.md, Teil B)
- [ ] `https://<domain>/health` ok, Daten-Zählvergleich ok, Einladungslink im Mobilfunk
- [ ] Erstes Backup + `restore.sh --test` auf dem VPS
- [ ] iOS: ATS-Ausnahme entfernen (`ios/Info.plist`, `ios/EssenappWidget-Info.plist`), Server-Adresse `https://…` in App, Widget, Teilen-Erweiterung; Test-Push
- [ ] Nach einer Woche: Angebotsimport vom Rechenzentrum aus läuft (kaufDA)
- [ ] Playbook aktualisiert

## DoD

- Abnahme aus 72 erfüllt (HTTPS, Links im Mobilfunk, Push, Backup getestet)
