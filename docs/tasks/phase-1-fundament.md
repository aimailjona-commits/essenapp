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

- [ ] `xtool new` in `ios/`, `bundleID` festlegen, `xtool.yml` prüfen
- [ ] 👤 `xtool dev`: auf dem iPhone Entwicklermodus aktivieren und Entwickler unter Einstellungen › Allgemein › VPN & Geräteverwaltung vertrauen
- [ ] Hello-World läuft auf dem iPhone
- [ ] Test: SwiftData `@Model` kompiliert und speichert → sonst GRDB. Ergebnis ins Entscheidungslog im Playbook
- [ ] Test: App-Icon ohne Asset-Catalog (`CFBundleIconFiles` mit PNGs). Ergebnis ins Playbook
- [ ] Test: eigene Schrift als Ressource + `UIAppFonts` (falls im Design-System eine Schrift gewählt ist)
- [ ] `Theme.swift` mit allen Tokens aus `docs/ui/design-system.md`
- [ ] Basis-Komponenten aus dem Design-System (Karte, Pill-Button, Tab-Bar, Nährwert-Chip) + eine Demo-Seite, die alle zeigt

## Backend-Grundgerüst

- [ ] `backend/` mit `uv init`, FastAPI, SQLAlchemy, Alembic, pydantic-settings, pytest
- [ ] `GET /health` → `{"status":"ok"}` + Test
- [ ] Datenbank (SQLite) + erste leere Migration
- [ ] `.env.example`
- [ ] Backend vom iPhone aus erreichbar machen (WSL mirrored networking oder `netsh portproxy`, Windows-Firewall-Regel). Weg im Playbook dokumentieren

## DoD

- Die App startet auf dem iPhone, zeigt die Komponenten-Demo im Design-System und den Text „Backend: ok“ aus `/health`.
- SwiftData/GRDB-Entscheidung, App-Icon-Weg, iPhone-Verbindung und Netzwerkweg stehen im Playbook.
