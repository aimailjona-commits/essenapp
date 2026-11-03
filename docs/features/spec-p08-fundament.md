# Phase 8 – Fundament: Server, Personen, Vorrat

Vorlage für jedes Feature: **Ziel · Ablauf · UI · Backend · Abnahme · Risiken**.

---

## 72 · Umzug auf IONOS-VPS (+ Scheduler, HTTPS, APNs)

**Ziel:** App, Web-Version und Einladungslinks funktionieren überall (nicht nur im Heim-WLAN); Grundlage für Push (APNs, E52) und zeitgesteuerte Jobs.

**Ablauf**
1. 👤 Nutzer bucht bei IONOS einen VPS (Ubuntu 24.04, ≥ 2 GB RAM) und eine Domain (Vorschlag: `essenapp.<deine-domain>.de`), gibt Claude SSH-Zugang (Schlüssel `~/.ssh/essenapp_vps.pub` aus WSL, kein Passwort im Chat). DNS: nur ein A-Record `essenapp.<domain>` → VPS-IP (kein `push.`-Eintrag).
2. Claude richtet ein: Docker + Docker Compose, Dienste `api` (FastAPI, uvicorn, 2 Worker), `db` (Postgres 16), `caddy` (HTTPS via Let's Encrypt), `scheduler` (eigener Container, ruft `python -m app.jobs` auf; im `api`-Container `SCHEDULER=0`). Kein eigener Push-Server: der APNs-Key (`backend/secrets/AuthKey_….p8`) wird read-only in `api` und `scheduler` eingebunden. Alles in `deploy/` (Anleitung `deploy/README.md`, Einrichtung `deploy/setup-vps.sh`).
3. Daten-Umzug SQLite → Postgres (`deploy/migrate_sqlite_to_postgres.py`, einmalig, Zählvergleich), Bilder (`/media`) als Docker-Volume. Links (Einladung, Liste, Rezept `/r/<code>`) bauen auf `PUBLIC_BASE_URL` = `https://<domain>`.
4. iOS: Server-Adresse in den Einstellungen auf `https://…` umstellen (Feld existiert); ATS-Ausnahme `NSAllowsArbitraryLoads` wird entfernt (`Info.plist` und `EssenappWidget-Info.plist`, E-Eintrag), nur noch HTTPS; Widget und Teilen-Erweiterung bekommen die neue Server-Adresse + neuen Kopplungscode.
5. Backups: täglicher `pg_dump` + `/media` → verschlüsseltes Archiv, 14 Tage aufbewahrt (`deploy/backup.sh`, optional rsync-Ziel); Wiederherstellung einmal getestet (`deploy/restore.sh --test`).

**Scheduler-Jobs** (konfigurierbar per Umgebungsvariablen)
| Job | Wann | Was |
|---|---|---|
| `import_offers` | Sa 22:00 + Mo 06:00 + Mi 06:00 | Angebote aller Haushalte, inkl. Folgewoche (30) |
| `price_history` | nach jedem Import | Preisverlauf fortschreiben (28) |
| `watch_alarms` | nach jedem Import | Merkliste/Preisalarme prüfen (27/40/58) |
| `plan_prompt` | pro Haushalt Tag/Uhrzeit aus Einstellungen (Standard So 18:00) | Push „Neuer Wochenplan?“ (17) |
| `coupon_expiry` | täglich 09:00 | Coupons laufen in 2 Tagen ab (38) |
| `week_review` | So 19:00 | Wochenrückblick erzeugen (55) |
| `achievements` | täglich 03:00 | Erfolge prüfen (54) |
| `reinstall_reminder` | alle 6 Tage | „App neu installieren“ (E2) |

**Push (APNs, E52):** Geräte-Tokens (`push_device`) ziehen mit der Datenbank um, die App muss sich nicht neu registrieren. Einstellungen › Benachrichtigungen hat den „Test-Push“-Knopf; Push-Klick öffnet Deep-Links der App (`essenapp://generator`, `essenapp://offer/<id>`, …) über das URL-Schema `essenapp` (CFBundleURLTypes) + Router in der App.

**Abnahme**
- `https://<domain>/health` → ok mit gültigem Zertifikat; Web-Version und Einladungslinks funktionieren im Mobilfunk.
- App läuft nur über HTTPS; Daten aus SQLite vollständig übernommen (Anzahl Haushalte, Pläne, Listen gleich).
- Test-Push kommt auf dem iPhone an und öffnet per Tipp die richtige Stelle der App.
- Backup + Wiederherstellung auf einer Test-DB nachgewiesen.

**Risiken:** IONOS-Zugang (A11). Kaufda-Abrufe vom Rechenzentrum aus könnten anders behandelt werden als vom Heimanschluss → nach Umzug Import beobachten.

---

## 48 · Ziele pro Person (nur eingeladene Mitglieder)

**Ziel:** Jedes Haushaltsmitglied hat eigene Ernährungsziele; Mengen und Nährwerte werden pro Person berechnet, der Plan bleibt gemeinsam.

**Ablauf**
- Einstellungen › „Mein Profil“: Name, Avatar-Farbe/Emoji, Ziel (Ausgewogen/Proteinreich/Kalorienarm/Eigenes), kcal/Tag und Protein g/Tag (Vorschlag aus Ziel, änderbar), Allergien, „Mag ich nicht“, Lunchbox-Tage (24), isst mit (pro Wochentag & Mahlzeit an/aus, z. B. Mittags nie zu Hause).
- Der Haushalt hat keine eigene „Personen“-Zahl mehr für Mitglieder; Personenzahl pro Mahlzeit = Mitglieder, die an dem Slot mitessen (+ Gäste, 15). Haushalt-weite Allergien = Vereinigung aller Mitglieder (harte Regel).
- **Portionen:** Jedes Gericht wird für die Summe der Portionsfaktoren gekocht (Faktor aus kcal-Ziel relativ zu 2000 kcal, gerundet auf 0,25). Rezeptansicht zeigt „Deine Portion: 520 g · 640 kcal · 48 g Protein“ für das angemeldete Mitglied, umschaltbar auf andere Mitglieder.
- **Tagesziele:** Wochenplan-Tagesansicht zeigt pro Mitglied Ringe für kcal/Protein (aus 2).

**UI:** S15 „Mein Profil“ (Formular wie Präferenzen, Karten, Ringe-Vorschau), Mitglieder-Avatare im Plan-Kopf, Umschalter „Für: Jona ▾“ in Rezept und Tagesansicht.

**Backend:** Tabelle `member_profile` (member_id, emoji, goal, kcal, protein_g, allergies[], dislikes[], lunchbox_days[], eats[slot] Matrix); Planner bekommt Liste der Esser pro Slot + Portionsfaktoren; `GET/PATCH /me/profile`, `GET /household/profiles`.

**Abnahme:** Zwei Mitglieder mit unterschiedlichen Zielen → Plan respektiert Allergien beider, Rezept zeigt je Person andere Portion; ein Mitglied „mittags nie zu Hause“ → Mittags-Mengen nur für die anderen.

---

## 60 · Vorratskammer

**Ziel:** Was zu Hause ist, wird nicht gekauft und bevorzugt verkocht.

**Ablauf**
- Tab „Rezepte“ bekommt dritten Pillen-Tab? → **Nein**: eigener Bereich im Tab **Einkauf** oben: Pillen „Liste | Vorrat“.
- Hinzufügen: (a) beim Abhaken in der Einkaufsliste kurzer Toast „In den Vorrat?“ mit „Ja“ (Standard: Vorrat-Kategorien automatisch ja, Frisches fragt), (b) manuell (Name, Menge, Einheit, optional Haltbarkeit), (c) Kühlschrank-Foto (69), (d) Barcode-Scan (Open Food Facts → Name).
- Verbrauch: „Gekocht ★“ im Rezept zieht die Mengen ab (mit Rückfrage-Liste, editierbar); Vorrat < 0 → Eintrag weg.
- Basics-Flag (z. B. Salz, Öl, Gewürze) ersetzt das bisherige `in_pantry` der KI: Basics gelten immer als vorhanden, bis man „leer“ meldet → kommt dann auf die Liste.
- Planner: bekommt Vorrat (Name, Menge, Haltbarkeit) und soll ihn zuerst verwenden; Pricing setzt Kosten für vorhandene Mengen auf 0.
- Haltbarkeit (optional): Anzeige „läuft in 2 Tagen ab“ (orange), wird beim Planen bevorzugt.

**UI:** S16 Vorrat: Suchfeld, Kategorien-Kreise (wie Angebote), Zeilen mit Emoji, Menge (Stepper), Haltbarkeits-Chip, Wischen zum Löschen; leer: EmptyState „📸 Kühlschrank fotografieren“ (→ 69).

**Backend:** `pantry_item` (household_id, name, ingredient_key, amount, unit, best_before, is_basic, source), CRUD-Endpunkte, `POST /pantry/consume` (Rezept-ID → Abzug), Planner/Pricing-Anbindung, `sync-plan` lässt vorhandene Mengen weg (bzw. reduziert).

**Abnahme:** 500 g Reis im Vorrat → Plan mit Reis kauft keinen Reis; „Gekocht“ zieht 160 g ab; Basics „Öl“ leer melden → steht auf der Liste.
