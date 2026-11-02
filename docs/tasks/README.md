# Aufgaben

**Aktive Phase: [Phase 0 – UI-Planung](phase-0-ui-planung.md)**

| Phase | Datei | Status |
|---|---|---|
| 0 | [UI-Planung](phase-0-ui-planung.md) | aktiv |
| 1 | [Fundament](phase-1-fundament.md) | offen |
| 2 | [Angebote](phase-2-angebote.md) | offen |
| 3 | [Wochenplan](phase-3-wochenplan.md) | offen |
| 4 | [Personalisierung + Web](phase-4-personalisierung-web.md) | offen |
| 5 | [Drogerie & Alarme](phase-5-drogerie-alarme.md) | offen |
| 6 | [Extras](phase-6-extras.md) | offen |
| 7 | [VPS](phase-7-vps.md) | offen |

## Wartet auf dich 👤

| Was | Wofür | Phase |
|---|---|---|
| Xcode 27.1 `.xip` herunterladen (https://developer.apple.com/download/all/?q=Xcode) | iOS-SDK für xtool | 1 |
| `winget install usbipd` | iPhone in WSL | 1 |
| `xtool setup` mit Apple-ID (Claude startet es, du tippst Login/2FA) | Signieren | 1 |
| iPhone per USB, „Vertrauen“, Entwicklermodus | App installieren | 1 |
| Anthropic-API-Key in `backend/.env` (`ANTHROPIC_API_KEY=`) | KI-Wochenplan | 3 |
| Offene (C)-Entscheidungen im Playbook prüfen (E17–E21) | optional | – |

## Regeln

- Aufgaben der Reihe nach. Nur die aktive Phase bearbeiten. **Ausnahme (E16, autonomer Modus):** Ist die aktive Phase durch 👤-Schritte blockiert, an nicht blockierten Aufgaben späterer Phasen weiterarbeiten (vor allem Backend, testbar ohne iPhone).
- `[ ]` offen, `[x]` erledigt, `[~]` begonnen, `[!]` blockiert (Grund dahinter schreiben).
- 👤 = muss der Nutzer selbst tun. Claude erklärt kurz, was zu tun ist, und wartet.
- Jede Phase endet mit der **Definition of Done (DoD)**. Erst wenn sie geprüft ist, nächste Phase in der Tabelle oben auf „aktiv“ setzen.
- Neue Aufgaben, die unterwegs auffallen, unten in die passende Phase schreiben, nicht sofort bauen.
