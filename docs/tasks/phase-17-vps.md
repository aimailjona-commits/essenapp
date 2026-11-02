# Phase 17 – Umzug auf IONOS-VPS (am Ende, Nutzerwunsch)

Details: [`docs/features/spec-p08-fundament.md`](../features/spec-p08-fundament.md) Abschnitt **72**.

## Aufgaben

- [ ] 👤 IONOS-VPS (Ubuntu 24.04, ≥ 2 GB) + Domain, SSH-Schlüssel `~/.ssh/essenapp_vps.pub` (WSL) hinterlegen, DNS `essenapp.<domain>` + `push.<domain>`
- [ ] Docker Compose: api, db (Postgres), caddy (HTTPS), ntfy (eigener Server), scheduler
- [ ] Daten-Umzug SQLite → Postgres, /media-Volume, tägliche Backups + Wiederherstellungstest
- [ ] `NTFY_URL`/`PUBLIC_BASE_URL` umstellen, Topics bleiben gültig
- [ ] iOS auf HTTPS, ATS-Ausnahme entfernen
- [ ] Playbook aktualisiert

## DoD

- Abnahme aus 72 erfüllt (HTTPS, Links im Mobilfunk, Push, Backup getestet)
