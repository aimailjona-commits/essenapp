# Umzug auf den IONOS-VPS (Phase 17, Spezifikation 72, E86)

Auf dem VPS laufen vier Docker-Container: `api` (Backend + Web-Version, 2 Worker), `db` (Postgres 16),
`scheduler` (geplante Jobs und Pushes) und `caddy` (HTTPS mit automatischem Let's-Encrypt-Zertifikat).
Push geht direkt an Apple (APNs), dafür braucht es keinen eigenen Server und keine zweite Subdomain.

| Datei | Zweck |
|---|---|
| `docker-compose.yml`, `Dockerfile`, `Caddyfile` | die Dienste |
| `.env.example` | Vorlage für `deploy/.env` (Domain, Passwörter, Backup) – legt `setup-vps.sh` an |
| `setup-vps.sh` | einmaliges Einrichten, darf erneut laufen |
| `migrate_sqlite_to_postgres.py` | einmaliger Daten-Umzug, vergleicht am Ende die Zeilenzahlen |
| `backup.sh` / `restore.sh` | tägliches verschlüsseltes Backup / Wiederherstellung und Wiederherstellungstest |

App-Keys (`ANTHROPIC_API_KEY`, `FAL_KEY`, `APNS_*`, `REINSTALL_BASE`, `JOB_SCHEDULES`) bleiben wie lokal in
`backend/.env`, der APNs-Key in `backend/secrets/`. Beides wird auf den VPS kopiert, aber nie angezeigt.

---

## Teil A – das machst du bei IONOS (ca. 20 Minuten)

1. **VPS bestellen:** im IONOS-Kundenbereich unter *Server & Cloud* einen **VPS Linux** mit **mindestens 2 GB RAM**
   (die Paketnamen ändern sich, „2 GB RAM“ ist das Kriterium), Rechenzentrum Deutschland, Betriebssystem
   **Ubuntu 24.04**.
2. **SSH-Schlüssel hinterlegen:** Claude zeigt dir den öffentlichen Schlüssel (`~/.ssh/essenapp_vps.pub` in WSL,
   der ist nicht geheim). Füge ihn beim Einrichten des Servers bzw. im Cloud Panel unter *SSH-Schlüssel* hinzu.
   Geht das nicht: nimm das Root-Passwort aus dem Cloud Panel und tippe in WSL selbst
   `ssh-copy-id -i ~/.ssh/essenapp_vps.pub root@<IP>` (das Passwort gibst nur du ein).
3. **Firewall im Cloud Panel** (IONOS filtert vor dem Server): eingehend **TCP 22, 80, 443** und **UDP 443** erlauben.
4. **DNS:** *Domains & SSL* › deine Domain › *DNS* › *Record hinzufügen*: Typ **A**, Hostname **`essenapp`**,
   Ziel = IPv4-Adresse des VPS. Einen vorhandenen **AAAA**-Eintrag für `essenapp` löschen, sofern er nicht auf
   den VPS zeigt (sonst scheitert das Zertifikat).
5. **Claude Bescheid geben:** IP-Adresse und Domain (z. B. `essenapp.meine-domain.de`).

Danach am Ende: die **Backup-Passphrase** in deinen Passwortmanager legen (Teil B, Schritt 8) und am iPhone die neue
Server-Adresse eintragen (Schritt 9).

---

## Teil B – das macht Claude (aus WSL, im Repo-Ordner)

Platzhalter: `IP` = VPS-IPv4, `DOMAIN` = z. B. `essenapp.meine-domain.de`, `SSH="ssh -i ~/.ssh/essenapp_vps"`.

1. **Verbindung und DNS prüfen**
   ```bash
   $SSH -o StrictHostKeyChecking=accept-new root@IP 'lsb_release -ds; free -h | head -2; command -v rsync || apt-get install -y -q rsync'
   getent hosts DOMAIN    # muss IP zeigen
   ```
2. **Lokalen Server stoppen** (Nutzer: `./dev.sh serve` mit Strg+C beenden). Sonst laufen Jobs und Pushes doppelt
   und Änderungen nach dem Snapshot gingen verloren.
3. **Snapshot** (liest die echte DB nur, konsistent auch bei offenem Server):
   ```bash
   mkdir -p deploy/import && rm -f deploy/import/.imported
   python3 -c "import sqlite3; s=sqlite3.connect('file:backend/essenapp.db?mode=ro', uri=True); d=sqlite3.connect('deploy/import/essenapp.db'); s.backup(d); d.close()"
   tar -C backend -cf deploy/import/media.tar media
   ```
   `backend/.env` prüfen (ohne Werte auszugeben): `APNS_KEY_PATH` muss relativ sein (`secrets/AuthKey_….p8`).
   `grep -c '^APNS_KEY_PATH=secrets/' backend/.env` → 1.
4. **Kopieren** (inkl. `backend/.env`, `backend/secrets/`, `deploy/import/`):
   ```bash
   rsync -az -e "ssh -i ~/.ssh/essenapp_vps" --exclude /.git --exclude /ios --exclude /.debug --exclude __pycache__ \
     --exclude /backend/essenapp.db --exclude /backend/media --exclude /backend/image_cache.json --exclude /deploy/.env \
     ./ root@IP:/opt/essenapp/
   ```
   Alternativ `git clone` nach `/opt/essenapp` und nur `backend/.env`, `backend/secrets/`, `deploy/import/` kopieren.
5. **Einrichten** (Docker, Firewall, automatische Updates, Benutzer `essenapp`, `deploy/.env`, Umzug, Start, Backup-cron):
   ```bash
   $SSH root@IP 'DOMAIN=DOMAIN bash /opt/essenapp/deploy/setup-vps.sh'
   ```
   In der Ausgabe stehen die Zeilen je Tabelle und `Zählvergleich: … alles gleich`. Ab jetzt reicht der Benutzer
   `essenapp` (`$SSH essenapp@IP`); Passwort-Login per SSH ist danach aus.
6. **Prüfen**
   ```bash
   curl -sf https://DOMAIN/health                                  # {"status":"ok"}, gültiges Zertifikat
   $SSH essenapp@IP 'cd /opt/essenapp/deploy && docker compose ps && docker compose logs --tail 20 scheduler'
   ```
   Einladungslink aus der App im Mobilfunk (WLAN aus) öffnen → Web-Version lädt.
7. **Erstes Backup + Wiederherstellungstest** (siehe unten).
8. **Backup-Passphrase sichern** – das liest der Nutzer selbst aus (Claude gibt sie nicht aus):
   `ssh -i ~/.ssh/essenapp_vps essenapp@IP grep BACKUP_PASSPHRASE /opt/essenapp/deploy/.env`
9. **iOS umstellen:** ATS-Ausnahme `NSAllowsArbitraryLoads` aus `ios/Info.plist` und `ios/EssenappWidget-Info.plist`
   entfernen, App neu bauen/installieren. In der App: Einstellungen › Server-Adresse `https://DOMAIN`. Widget
   (Widget bearbeiten) und Teilen-Erweiterung: neue Server-Adresse + neuer Kopplungscode. Test-Push auslösen.
10. **Lokal:** `./dev.sh serve` nicht mehr starten (sonst doppelte Pushes). `backend/essenapp.db` bleibt als Archiv.

### Updates später

```bash
rsync … (wie Schritt 4, aber zusätzlich --exclude /deploy/import, Ziel essenapp@IP:/opt/essenapp/)
$SSH essenapp@IP 'cd /opt/essenapp/deploy && docker compose up -d --build'   # Migrationen laufen beim Start der api
```

---

## Backups

- `backup.sh` läuft täglich um 03:30 (cron `/etc/cron.d/essenapp-backup`, Log `/var/log/essenapp-backup.log`):
  `pg_dump` + `/media` → `BACKUP_DIR/essenapp-<Datum>.tar.enc` (AES-256, Passphrase `BACKUP_PASSPHRASE`),
  älter als `BACKUP_KEEP_DAYS` (14) wird gelöscht. Mit `BACKUP_RSYNC_TARGET=user@host:pfad/` geht zusätzlich eine
  Kopie per rsync/SSH weg (der VPS braucht dafür einen SSH-Schlüssel für das Ziel).
- Ohne Passphrase sind die Archive wertlos → im Passwortmanager ablegen.

### Wiederherstellungstest (einmal nach dem Umzug, danach gelegentlich)

```bash
$SSH essenapp@IP
cd /opt/essenapp/deploy
./backup.sh
./restore.sh --test "$(ls -t /var/backups/essenapp/*.tar.enc | head -1)"
```

Die Probe stellt die Datenbank in `essenapp_restore_test` wieder her, vergleicht die Zeilen wichtiger Tabellen und
die Zahl der `/media`-Dateien mit dem Live-Stand, löscht die Probe-Datenbank wieder und ändert nichts Live.
Erwartet: gleiche Zahlen (kleine Abweichungen = Änderungen seit dem Backup), am Ende `Probe OK`.

### Ernstfall

- Daten kaputt: `./restore.sh <archiv>` (fragt nach „ja“, stoppt api + scheduler, ersetzt DB und `/media`, startet neu).
- VPS weg: neuen VPS wie Teil A, Repo + `backend/.env` + `backend/secrets/` kopieren (ohne `deploy/import`),
  `setup-vps.sh`, dann in `deploy/.env` die alte `BACKUP_PASSPHRASE` eintragen, Archiv nach
  `/var/backups/essenapp/` kopieren und `./restore.sh <archiv>`.

---

## Nützliche Befehle (als `essenapp` in `/opt/essenapp/deploy`)

```bash
docker compose ps                                        # Status + Healthchecks
docker compose logs -f api                               # Logs (rotieren: 5 × 10 MB je Dienst)
docker compose exec scheduler python -m app.jobs import_offers   # Job sofort ausführen
docker compose exec db psql -U essenapp                  # Datenbank
```

## Erst auf dem VPS prüfbar

Let's-Encrypt-Zertifikat (braucht DNS + offene Ports 80/443), `setup-vps.sh` selbst (apt, Docker-Installation, ufw,
sshd), Push über APNs vom VPS aus, kaufDA-Abrufe aus dem Rechenzentrum (Spezifikation 72, Risiken).
