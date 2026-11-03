# Aufgaben

**Stand 2026-11-03: Phasen 8–16 gebaut (Code + Tests + CI-Screenshots), offen sind die Abnahmen auf dem iPhone und der APNs-Ende-zu-Ende-Test (wartet auf bezahlten Apple-Account). Phase 17 (VPS) wird vorbereitet, Umzug am Ende.**

| Phase | Datei | Status |
|---|---|---|
| 0 | [UI-Planung](phase-0-ui-planung.md) | vorläufig fertig (Feedback offen) |
| 1 | [Fundament](phase-1-fundament.md) | fertig |
| 2 | [Angebote](phase-2-angebote.md) | großteils fertig |
| 3 | [Wochenplan](phase-3-wochenplan.md) | begonnen |
| 4 | [Personalisierung + Web](phase-4-personalisierung-web.md) | offen |
| 5 | [Drogerie & Alarme](phase-5-drogerie-alarme.md) | offen |
| 6 | [Extras](phase-6-extras.md) | offen |
| 7 | [VPS](phase-7-vps.md) | → aufgegangen in Phase 8 (IONOS) |
| 8 | [Fundament: Server, Personen, Vorrat](phase-8-fundament-server.md) | gebaut – Abnahme iPhone + APNs offen |
| 9 | [Rezepte, Instagram-Import, Kühlschrank-Foto](phase-9-rezepte-import.md) | gebaut – Abnahme iPhone offen |
| 10 | [Kochen](phase-10-kochen.md) | gebaut – Abnahme iPhone offen |
| 11 | [Clever planen](phase-11-planen.md) | gebaut – Abnahme iPhone offen |
| 12 | [Sparen](phase-12-sparen.md) | gebaut – Abnahme iPhone offen |
| 13 | [Bonus, Laden, Ausgaben](phase-13-bonus-laden.md) | gebaut – Abnahme iPhone offen |
| 14 | [Motivation & Teilen](phase-14-motivation.md) | gebaut – Abnahme iPhone offen |
| 15 | [Komfort](phase-15-komfort.md) | gebaut – Abnahme iPhone offen |
| 16 | [Erweiterungen (Widget, Live-Aktivität)](phase-16-erweiterungen.md) | gebaut – Abnahme iPhone offen |
| 17 | [Umzug auf IONOS-VPS](phase-17-vps.md) | Vorbereitung läuft – wartet auf 👤 IONOS-VPS + Domain |
| 18 | [Redesign v3 „Küchen-Pinnwand“](phase-18-redesign-v3.md) | **aktiv** – Richtung freigegeben, Bau nach [`docs/ui/redesign-v3.md`](../ui/redesign-v3.md) |

## Wartet auf dich 👤

| Was | Wofür | Phase |
|---|---|---|
| iPhone anschließen + entsperren, Apple Devices offen | neue Version installieren, Abnahmen | 8–16 |
| Bezahlter Apple-Account aktiv → APNs-Schlüssel (`.p8`) erstellen, nach `backend/secrets/`, Key-ID + Team-ID nennen; xtool neu einloggen | Push Ende-zu-Ende | 8, 11–14 |
| 3 Instagram-Reels mit Rezept in der Beschreibung | Abnahme Import | 9 |
| Kühlschrank-Foto, 10 echte Coupons, Testscan an der Kasse | Abnahmen | 9, 13 |
| Entscheidung Payback-Umrechnung (Spec „10fach = 10 %“ vs. 1 °P/2 € = 5 %; umgesetzt 5 %) | Coupons | 13 |
| Selbst getroffene Entscheidungen prüfen (Playbook E78–E85) | optional | 11–16 |
| IONOS-VPS (Ubuntu 24.04, ≥ 2 GB) + Domain anlegen | Umzug | 17 |
| Download Fraunces + JetBrains Mono (OFL) freigeben; Mockup-Gruppen freigeben | Redesign v3 | 18 |

## Regeln

- Aufgaben der Reihe nach. Nur die aktive Phase bearbeiten. **Ausnahme (E16, autonomer Modus):** Ist die aktive Phase durch 👤-Schritte blockiert, an nicht blockierten Aufgaben späterer Phasen weiterarbeiten (vor allem Backend, testbar ohne iPhone).
- `[ ]` offen, `[x]` erledigt, `[~]` begonnen, `[!]` blockiert (Grund dahinter schreiben).
- 👤 = muss der Nutzer selbst tun. Claude erklärt kurz, was zu tun ist, und wartet.
- Jede Phase endet mit der **Definition of Done (DoD)**. Erst wenn sie geprüft ist, nächste Phase in der Tabelle oben auf „aktiv“ setzen.
- Neue Aufgaben, die unterwegs auffallen, unten in die passende Phase schreiben, nicht sofort bauen.
