# Phase 1 – Fundament

Ziel: Toolchain läuft, eine leere App mit dem Design-System läuft auf dem iPhone und spricht mit dem Backend in WSL.

## Vorbereitung

- [ ] 👤 Xcode 27.1 `.xip` herunterladen: https://developer.apple.com/download/all/?q=Xcode
- [x] 👤 `winget install usbipd` (USB-Durchreichung für WSL)
- [x] Git-Repo anlegen, `.gitignore` (u.a. `.env`, `.build/`, `*.ipa`, `__pycache__/`)

## WSL-Toolchain

- [x] Swift 6.4 installieren (swift.org/install/linux bzw. swiftly), `swift --version` prüfen → 6.4.2 via swiftly
- [x] `usbmuxd`, `libimobiledevice-utils` installieren
- [x] xtool AppImage nach `/usr/local/bin/xtool`, `xtool --help` prüfen
- [ ] 👤 `xtool setup`: Login-Modus „Password“, Apple-ID selbst eingeben, Pfad zum `.xip` angeben
- [ ] `swift sdk list` zeigt `darwin`
- [x] Python 3.12 + `uv` in WSL

## iPhone-Verbindung

- [x] 👤 iPhone per USB anschließen, „Vertrauen“ bestätigen
- [x] Weg A: `usbipd bind/attach` → in WSL `ideviceinfo` zeigt das Gerät (iPhone 12, iOS 26.3, Pairing ok)
- [-] nicht nötig – Weg B (falls `AFCClient.Error.muxError`): Relay über Windows-Apple-Gerätedienst, `USBMUXD_SOCKET_ADDRESS=<Windows-Host>:27015` (xtool Issue #19)
- [x] Funktionierenden Weg im Playbook dokumentieren

## iOS-Grundgerüst

- [x] `xtool new` in `ios/`, `bundleID` festlegen, `xtool.yml` prüfen (`de.jsenf.essenapp`, Build in WSL-Dateisystem E24)
- [ ] 👤 `xtool dev`: auf dem iPhone Entwicklermodus aktivieren und Entwickler unter Einstellungen › Allgemein › VPN & Geräteverwaltung vertrauen
- [~] App baut erfolgreich (`./build.sh build`). Aufs iPhone: wartet auf Apple-ID-Login
- [ ] 👤 `xtool setup` mit Apple-ID (SDK ist schon installiert), dann `./build.sh`
- [x] Test: SwiftData `@Model` → kompiliert nicht, JSON-Cache stattdessen (E25)
- [~] App-Icon über `iconPath` (E26): `Icon.png` liegt im Bundle; ob es auf dem Homescreen erscheint, auf dem Gerät prüfen
- [-] nicht nötig – Systemschrift (E22)
- [x] `Theme.swift` mit allen Tokens aus `docs/ui/design-system.md`
- [x] Basis-Komponenten aus dem Design-System + Demo-Seite (`Components.swift`, `ComponentDemoView`)

## Backend-Grundgerüst

- [x] `backend/` mit FastAPI, SQLAlchemy, Alembic, pydantic-settings, pytest
- [x] `GET /health` → `{"status":"ok"}` + Test
- [x] Datenbank (SQLite) + erste Migration (gleich mit den Modellen aus Phase 2)
- [x] `.env.example`
- [ ] 👤 (Admin-Abfrage nötig) Backend vom iPhone aus erreichbar machen (WSL mirrored networking oder `netsh portproxy`, Windows-Firewall-Regel). Weg im Playbook dokumentieren

## DoD

- Die App startet auf dem iPhone, zeigt die Komponenten-Demo im Design-System und den Text „Backend: ok“ aus `/health`.
- SwiftData/GRDB-Entscheidung, App-Icon-Weg, iPhone-Verbindung und Netzwerkweg stehen im Playbook.
