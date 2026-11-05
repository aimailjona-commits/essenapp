# Phase 22 – Regeln für Bau-Agents

- Arbeite nach `.claude/skills/ponytail/SKILL.md`, Stufe full. PonyTail kürzt nie, was im Mockup steht.
- Lies: `docs/tasks/phase-22-v9-umbau.md` (deine Zeile), `ios/CLAUDE.md`, `docs/ui/redesign-v8.md`, deinen Mockup-Teil in `docs/ui/mockups/v9-parts/` (gewählte Variante exakt nachbauen; Maße/Farben/Abstände aus dem CSS ablesen), die betroffenen Swift-Dateien.
- Baue mit den vorhandenen Bausteinen (`Theme`, `V8Components.swift`, `Components.swift`, `Icons8.swift`, `Ill`, `PlanPlate` …). Farben/Größen nur über `Theme`; fehlt ein Wert, als Konstante in `Theme.swift` ergänzen (nur per kleinem Edit, nie die ganze Datei neu schreiben).
- **Mehrere Agents arbeiten gleichzeitig.** Geteilte Dateien (`PlanViews.swift`, `Theme.swift`, `Components.swift`, `V8Components.swift`, `API.swift`) nur mit kleinen Edit-Aufrufen in deinem Bereich ändern, nie mit Write überschreiben, nichts außerhalb deines Bereichs anfassen. Größere neue Views in deine eigene neue Datei.
- Echte Daten verwenden (bestehende Store-/DTO-Felder). Fehlt etwas im Backend, nicht erfinden: weglassen oder aus vorhandenen Daten ableiten und im Bericht melden.
- Bestehende Funktionen bleiben erreichbar (nichts ersatzlos streichen, was nicht im Mockup ersetzt ist). Bestehende Demo-Fälle (`Demo.screen`) müssen weiter etwas Sinnvolles zeigen.
- Barrierefreiheit: Tap-Flächen ≥ 44 pt, VoiceOver-Labels, „Bewegung reduzieren“ beachten.
- **NICHT bauen, KEINE WSL-/Build-Befehle, KEIN git.** Der Hauptagent baut zentral. Schreibe sorgfältig kompilierbares Swift 6 (iOS 17+, `@MainActor`-Isolation beachten, keine `private` Funktionen in lokalen Scopes).
- Bericht (max. 12 Zeilen): geänderte/neue Dateien, was umgesetzt, was abweicht/fehlt (mit Grund), benötigte neue Demo-Fälle, Fragen an den Nutzer.
