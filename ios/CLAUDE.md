# iOS-App – Regeln

PonyTail `full` gilt (siehe Root-`CLAUDE.md`).

## Build

- Gebaut wird **in WSL (Ubuntu-24.04)** mit xtool, nie unter Windows direkt.
- Projekt liegt unter Windows in `C:\Users\jsenf\Desktop\essenapp\ios`, in WSL unter `/mnt/c/Users/jsenf/Desktop/essenapp/ios`.
  Falls Builds auf `/mnt/c` zu langsam sind oder Rechteprobleme machen: Entscheidung im Playbook dokumentieren.
- Befehle: `xtool dev` (bauen, signieren, installieren), `xtool dev build` (nur bauen).
- Kein Simulator. Logik in reine Swift-Typen ohne UI auslagern und mit `swift test` prüfen. UI auf dem iPhone prüfen.

## xtool-Grenzen (Details: PLAYBOOK Abschnitt 9)

- **Kein `.xcassets`.** Farben im Code (`Theme`), Bilder als SwiftPM-Ressourcen.
- `xtool.yml`: nur bekannte Keys (`version`, `bundleID`, `product`, `entitlementsPath`, `extensions`). Tippfehler werden still ignoriert.
- Keine Push-, iCloud- oder App-Group-Entitlements (kostenlose Apple-ID).
- Persistenz: SwiftData oder GRDB, je nach Ergebnis aus Phase 1 (steht dann im Playbook).

## UI

- Alle Farben, Schriftgrößen, Radien, Abstände und Schatten kommen aus **einer** Datei `Theme.swift`. Die Werte stehen in `docs/ui/design-system.md`. Keine Hex-Werte oder Zahlen direkt in Views.
- Wiederverwendbare Bausteine (Karte, Nährwert-Chip, Angebots-Badge, schwarzer Pill-Button, Tab-Bar) nur einmal bauen. Namen wie in `docs/ui/design-system.md` (Abschnitt Komponenten).
- Screens exakt nach `docs/ui/screens.md`. Jeder Screen hat die dort genannten Zustände (Laden, Leer, Fehler).
- Texte auf Deutsch, Beträge mit `€` und deutschem Format (`12,49 €`).
- Mindestgröße für Tap-Flächen 44 pt, Dynamic Type nicht brechen, VoiceOver-Labels für Icons.

## Backend-Zugriff

- Basis-URL ist in den Einstellungen änderbar (lokal: WSL-IP, später VPS).
- API-Modelle (Codable) passend zu den Pydantic-Schemas in `backend/app/schemas/`.
