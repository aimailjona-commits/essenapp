# iOS-App – Regeln

PonyTail `full` gilt (siehe Root-`CLAUDE.md`).

## Build

- Gebaut wird **in WSL (Ubuntu-24.04)** mit xtool, nie unter Windows direkt.
- Quellen liegen in `ios/` (Windows), gebaut wird in `~/build/essenapp-ios` (E24). Immer über das Skript:
  `./build.sh build` (nur bauen) bzw. `./build.sh` (bauen, signieren, aufs iPhone).
- iPhone hängt an Windows (Apple Devices). Nach Windows-/WSL-Neustart: `tools/windows-setup.ps1` als Admin (Nutzer). Prüfen in WSL: `USBMUXD_SOCKET_ADDRESS=$(ip route list default | awk '{print $3}'):27015 idevice_id -l` (E33).
- Kein Simulator. Logik in reine Swift-Typen ohne UI auslagern und mit `swift test` prüfen. UI auf dem iPhone prüfen.

## xtool-Grenzen (Details: PLAYBOOK Abschnitt 9)

- **Kein `.xcassets`.** Farben im Code (`Theme`), Bilder als SwiftPM-Ressourcen.
- `xtool.yml`: nur bekannte Keys (E26). Tippfehler werden still ignoriert. Icon: `Icon.png` via `iconPath`, neu erzeugen mit `uv run --no-project --with pillow ios/tools/make_icon.py`.
- Keine Push-, iCloud- oder App-Group-Entitlements (kostenlose Apple-ID).
- **Kein SwiftData** (geht unter xtool nicht, E25). Lokaler Cache = Codable-JSON-Dateien.
- App Intents (Widget-Konfiguration, Live-Aktivitäts-Knöpfe) brauchen den Index `AppIntents/*/Metadata.appintents`: nach Änderungen an Intents `./build.sh build`, `python3 tools/appintents_index.py`, erneut bauen (E83). Widget-Target braucht `-u _main`.

## UI

- Alle Farben, Schriftgrößen, Radien, Abstände und Schatten kommen aus **einer** Datei `Theme.swift`. Die Werte stehen in `docs/ui/design-system.md`. Keine Hex-Werte oder Zahlen direkt in Views.
- Wiederverwendbare Bausteine (Karte, Nährwert-Chip, Angebots-Badge, schwarzer Pill-Button, Tab-Bar) nur einmal bauen. Namen wie in `docs/ui/design-system.md` (Abschnitt Komponenten).
- Screens exakt nach `docs/ui/screens.md`. Jeder Screen hat die dort genannten Zustände (Laden, Leer, Fehler).
- Texte auf Deutsch, Beträge mit `€` und deutschem Format (`12,49 €`).
- Mindestgröße für Tap-Flächen 44 pt, Dynamic Type nicht brechen, VoiceOver-Labels für Icons.

## Backend-Zugriff

- Basis-URL ist in den Einstellungen änderbar (lokal: WSL-IP, später VPS).
- API-Modelle (Codable) passend zu den Pydantic-Schemas in `backend/app/schemas/`.
