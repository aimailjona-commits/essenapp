# Essenapp

iOS-App (SwiftUI, gebaut mit xtool unter WSL) + Python-Backend (FastAPI) + Web-PWA für Familie.
Plant Wochengerichte aus aktuellen Supermarkt- und Drogerieprospekten.

## Pflicht bei jeder Coding-Aufgabe: PonyTail auf Stufe `full`

- Vor dem ersten Code in einer Sitzung den Skill `ponytail` laden (Skill-Tool, Argument `full`) und seine Regeln für die ganze Sitzung befolgen.
- Gilt auch für Subagents: jeder Prompt an einen Subagent, der Code schreibt oder prüft, beginnt mit „Arbeite nach `.claude/skills/ponytail/SKILL.md`, Stufe full.“
- Stufe nur ändern, wenn der Nutzer es ausdrücklich sagt.
- PonyTail kürzt **nie** etwas, das in `docs/ui/` oder in einer Task-Datei festgelegt ist. Das gilt als „vom Nutzer verlangt“.

## Leseordnung

1. `docs/tasks/README.md` – welche Phase aktiv ist, wie Tasks funktionieren
2. die aktive Phasen-Datei in `docs/tasks/` – nächste offene Aufgabe
3. `docs/PLAYBOOK.md` – Entscheidungen, Architektur, Datenmodell, xtool-Grenzen (bei Bedarf)
4. Bei UI-Arbeit: `docs/ui/README.md`, `docs/ui/design-system.md`, `docs/ui/screens.md`
5. `ios/CLAUDE.md` bzw. `backend/CLAUDE.md` – Regeln für den jeweiligen Teil

## Arbeitsablauf

1. Nächste offene Aufgabe der aktiven Phase nehmen. Nichts außerhalb der Phase bauen.
2. UI nur exakt nach `docs/ui/` bauen. Fehlt eine Vorgabe (Screen, Zustand, Farbe), **den Nutzer fragen**, nicht erfinden.
3. Prüfen wie in der Aufgabe beschrieben (Test, Gerät, Screenshot).
4. Aufgabe in der Phasen-Datei abhaken. Neue Entscheidungen ins Entscheidungslog im Playbook.
5. Phase fertig → DoD prüfen, in `docs/tasks/README.md` nächste Phase aktiv setzen.

## UI prüfen (E34)

- Nach UI-Änderungen: committen + pushen → GitHub Actions „iOS Screenshots“ läuft (oder `gh workflow run ios-screenshots.yml`). Danach
  `gh run download <id> --name screenshots --dir .debug/ci` und mit `tools/contact_sheet.py` zu Übersichten zusammenfügen, gegen `docs/ui/mockups/` vergleichen.
- Neuer Screen → Fall in `Demo.swift` / `MainView` ergänzen und in `ios/tools/screenshots.sh` aufnehmen.
- Nach Änderungen an `xtool.yml`, `Info.plist` oder Icon: `ios/tools/gen-xcode.sh` (WSL) ausführen und committen.
- Echtes iPhone: `tools/iphone-shot.ps1 [-Screen <name>]` (braucht laufenden tunneld des Nutzers). Screenshots können Privates zeigen: nur in `.debug/`, nie committen.

## Nutzer

- Kommunikation auf Deutsch.
- Der Nutzer muss SwiftUI-Code nicht verstehen. Nur erklären, was er selbst tun muss (iPhone anschließen, Vertrauen bestätigen, Apple-ID-Login, Downloads).
- Passwörter, Apple-ID und 2FA-Codes gibt der Nutzer selbst ein.

## Ordner

```
.claude/skills/ponytail/   PonyTail-Skill (MIT, v5.3.3, unverändert übernommen)
docs/PLAYBOOK.md           Vision, Entscheidungen, Architektur, Datenmodell
docs/tasks/                Phasen mit Aufgaben und Definition of Done
docs/ui/                   Design-System, Screen-Spezifikationen, Referenzen, Mockups
ios/                       iOS-App (SwiftPM + xtool)
backend/                   FastAPI-Backend + Web-PWA (backend/app/web)
deploy/                    Docker Compose, Caddy (Phase 7)
```
