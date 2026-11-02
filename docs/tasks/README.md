# Aufgaben

**Aktive Phase: [Phase 8 – Fundament](phase-8-fundament-server.md)** (Phasen 1–7: Grundlage steht, Rest aufgegangen in 8–17) (blockiert durch 👤 Apple-ID-Login; im autonomen Modus (E16) wurde an Phase 2 und 3 weitergearbeitet)

| Phase | Datei | Status |
|---|---|---|
| 0 | [UI-Planung](phase-0-ui-planung.md) | vorläufig fertig (Feedback offen) |
| 1 | [Fundament](phase-1-fundament.md) | aktiv – fehlt: Login, App aufs iPhone, Netzwerk |
| 2 | [Angebote](phase-2-angebote.md) | großteils fertig |
| 3 | [Wochenplan](phase-3-wochenplan.md) | begonnen |
| 4 | [Personalisierung + Web](phase-4-personalisierung-web.md) | offen |
| 5 | [Drogerie & Alarme](phase-5-drogerie-alarme.md) | offen |
| 6 | [Extras](phase-6-extras.md) | offen |
| 7 | [VPS](phase-7-vps.md) | → aufgegangen in Phase 8 (IONOS) |
| 8 | [Fundament: Server, Personen, Vorrat](phase-8-fundament-server.md) | geplant |
| 9 | [Rezepte, Instagram-Import, Kühlschrank-Foto](phase-9-rezepte-import.md) | geplant |
| 10 | [Kochen](phase-10-kochen.md) | geplant |
| 11 | [Clever planen](phase-11-planen.md) | geplant |
| 12 | [Sparen](phase-12-sparen.md) | geplant |
| 13 | [Bonus, Laden, Ausgaben](phase-13-bonus-laden.md) | geplant |
| 14 | [Motivation & Teilen](phase-14-motivation.md) | geplant |
| 15 | [Komfort](phase-15-komfort.md) | geplant |
| 16 | [Erweiterungen (Widget, Live-Aktivität)](phase-16-erweiterungen.md) | geplant |
| 17 | [Umzug auf IONOS-VPS](phase-17-vps.md) | geplant (ganz am Ende) |

## Wartet auf dich 👤

| Was | Wofür | Phase |
|---|---|---|
| Xcode 27.1 `.xip` herunterladen (https://developer.apple.com/download/all/?q=Xcode) | iOS-SDK für xtool | 1 |
| `xtool setup` mit Apple-ID (Claude startet es, du tippst Login/2FA) | Signieren | 1 |
| iPhone per USB, „Vertrauen“, Entwicklermodus | App installieren | 1 |
| Offene (C)-Entscheidungen im Playbook prüfen (E17–E21) | optional | – |

## Regeln

- Aufgaben der Reihe nach. Nur die aktive Phase bearbeiten. **Ausnahme (E16, autonomer Modus):** Ist die aktive Phase durch 👤-Schritte blockiert, an nicht blockierten Aufgaben späterer Phasen weiterarbeiten (vor allem Backend, testbar ohne iPhone).
- `[ ]` offen, `[x]` erledigt, `[~]` begonnen, `[!]` blockiert (Grund dahinter schreiben).
- 👤 = muss der Nutzer selbst tun. Claude erklärt kurz, was zu tun ist, und wartet.
- Jede Phase endet mit der **Definition of Done (DoD)**. Erst wenn sie geprüft ist, nächste Phase in der Tabelle oben auf „aktiv“ setzen.
- Neue Aufgaben, die unterwegs auffallen, unten in die passende Phase schreiben, nicht sofort bauen.
