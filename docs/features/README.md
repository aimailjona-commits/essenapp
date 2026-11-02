# Feature-Roadmap (Phasen 8–16)

Stand: 2026-11-02 · Auswahl des Nutzers: 44 Features (Nummern aus der Ideenliste).
Ziel: **Jedes Feature wird zu 100 % so umgesetzt, wie hier beschrieben.** Abweichungen nur nach Rückfrage; offene Punkte stehen unten unter „Bitte prüfen“.

## So wird damit gearbeitet (für Claude)

1. Phase in `docs/tasks/phase-<n>-*.md` abarbeiten, Detailbeschreibung steht in der hier verlinkten Spezifikation.
2. Jede Spezifikation hat **Abnahmekriterien** – erst wenn alle erfüllt und geprüft sind (Tests, Simulator-Screenshots E34, iPhone), gilt das Feature als fertig.
3. Neue Screens: zuerst in `docs/ui/screens.md` aufnehmen, Demo-Screen in `Demo.swift` + `ios/tools/screenshots.sh`, dann bauen.
4. PonyTail `full` gilt weiterhin – aber nichts aus diesen Spezifikationen weglassen (gilt als „vom Nutzer verlangt“).
5. KI immer über Claude Haiku 5.5 (E38), Kosten pro Aufruf loggen (`params.usage`), Ausnahme nur nach Rückfrage.
6. Design v3 + Liquid Glass (E43/E44), alle Texte deutsch, Animationen nach `docs/ui/design-system.md`.

## Überblick

Aufwand: S = bis 1 Tag, M = 1–3 Tage, L = > 3 Tage (Claude-Arbeitszeit, grob). KI-Kosten mit Haiku 5.5.

| Nr | Feature | Phase | Aufwand | KI-Kosten | Hängt ab von |
|---|---|---|---|---|---|
| 72 | Umzug auf IONOS-VPS (+ ntfy, Scheduler, HTTPS) | 8 | L | – | – |
| 48 | Ziele pro Person (Mitglieder-Profile) | 8 | M | – | – |
| 60 | Vorratskammer | 8 | M | – | – |
| 3 | Meine Rezepte (merken, eigene, Bewertung → Planer) | 9 | L | – | 8 (Rezept-Modell) |
| 1 | Zutat antippen → Angebot | 9 | S | – | – |
| 2 | Nährwerte + Blüten-Diagramm | 9 | L | ~0,01 ct / neue Zutat | 48 |
| 5 | **Rezept-Import aus Instagram** (Teilen-Menü) | 9 | L | ~0,1 ct / Import | 3 |
| 9 | Original-Reel + KI-Bild pro Schritt | 9 | M | ~0,3 ct / Bild (fal.ai) | 5 |
| 69 | **Kühlschrank-Foto** → Vorrat, „Was koche ich jetzt?“, Plan | 9 | M | ~0,2 ct / Foto | 60 |
| 4 | Kochmodus | 10 | M | – | – |
| 8 | Mehrere Timer + Sprachsteuerung | 10 | M | – | 4 |
| 7 | Ersatzzutaten | 10 | S | ~0,02 ct / Anfrage | – |
| 10 | Rezept als Bildkarte teilen | 10 | S | – | – |
| 12 | Abwechslungsregeln | 11 | M | – | – |
| 15 | Gäste-Modus | 11 | S | – | – |
| 16 | „Keine Lust“-Knopf | 11 | S | ~0,05 ct | 60 |
| 17 | Auto-Wochenplan „erst nachfragen“ | 11 | S | – | 72 |
| 19 | Reste-Planung | 11 | M | – | – |
| 23 | Frühstück & Snacks (Basics, Ideen, unterwegs) | 11 | M | – | 60 |
| 24 | Lunchbox Arbeit | 11 | S | – | 48 |
| 25 | Feiertags-/Saison-Specials | 11 | S | – | – |
| 28 | **Preisverlauf** | 12 | M | – | – |
| 30 | **Prospekt-Vorschau nächste Woche** | 12 | M | – | – |
| 31 | **Vorratskauf-Tipp** | 12 | M | – | 28, 60 |
| 27+40 | Merkliste mit Alarm + Preisalarm für Zutaten | 12 | L | – | 72 (Push) |
| 41 | Ein-Laden-Modus | 12 | S | – | – |
| 42 | Laden-Empfehlung | 12 | M | – | – |
| 43 | Budget-Rest-Hinweis | 12 | S | ~0,05 ct | – |
| 49 | Nutri-Score, Bio, Vegan | 12 | M | – | – |
| 58 | Verbrauchsrhythmus Drogerie | 12 | M | – | 27 |
| 59 | dm/Rossmann Monatsaktionen & Coupons | 12 | S | – | 38 |
| 38 | Payback & Rewe Bonus (Coupons, Guthaben, Planung, Erinnerung) | 13 | L | ~0,1 ct / Coupon-Foto | 36 |
| 39 | Rewe-Bonus-Aktionen erkennen | 13 | M | – | – |
| 36 | Standort-Erinnerung | 13 | M | – | – |
| 45 | Einkaufsliste per Sprache | 13 | S | – | – |
| 34 | Monats-Dashboard (abgehakte Artikel) | 13 | M | – | – |
| 54 | Erfolge (Sparen, Gesundheit) | 14 | M | – | 2, 34 |
| 55 | Wochenrückblick | 14 | M | – | 34 |
| 56 | Rezepte zwischen Haushalten teilen | 14 | M | – | 3 |
| 66 | Offline-Modus | 15 | M | – | – |
| 68 | Dark Mode | 15 | M | – | – |
| 65 | Widget „Heute“ | 16 | M | – | Spike App-Erweiterung |
| 37 | Live-Aktivität beim Einkaufen | 16 | M | – | Spike App-Erweiterung |

Spezifikationen:
[Phase 8 – Fundament](spec-p08-fundament.md) ·
[Phase 9 – Rezepte, Import, Kühlschrank](spec-p09-rezepte-import.md) ·
[Phase 10 – Kochen](spec-p10-kochen.md) ·
[Phase 11 – Clever planen](spec-p11-planen.md) ·
[Phase 12 – Sparen](spec-p12-sparen.md) ·
[Phase 13 – Bonus, Laden, Ausgaben](spec-p13-bonus-laden.md) ·
[Phase 14 – Motivation & Teilen](spec-p14-motivation.md) ·
[Phase 15–16 – Komfort & Erweiterungen](spec-p15-16-komfort.md)

## Reihenfolge – warum so

- **Phase 8 zuerst:** VPS (Push für Alarme und Auto-Plan, Einladungslinks außerhalb des WLANs), Mitglieder-Profile und Vorratskammer sind Grundlage für viele andere Features.
- **Phase 9:** Deine wichtigsten Wünsche (Instagram-Import, Kühlschrank-Foto) brauchen „Meine Rezepte“ bzw. die Vorratskammer – deshalb direkt danach.
- **Phase 12** enthält die drei „!“-Features (Preisverlauf, Prospekt-Vorschau, Vorratskauf); der Preisverlauf sammelt ab Phase 8 schon Daten (Import-Job speichert Historie), damit die Kurven dann nicht leer sind.
- **Widget & Live-Aktivität** am Ende (Nutzerentscheidung).

## Bitte prüfen (Annahmen und Risiken)

| # | Thema | Was ich angenommen habe / was das Risiko ist |
|---|---|---|
| A1 | **Teilen-Menü aus Instagram (5)** | Braucht eine *Share Extension*. Die Erweiterung muss sich mit der App den Login teilen (App Group / Keychain-Gruppe). Ob das mit der **kostenlosen Apple-ID** + xtool geht, ist unklar → wird als erstes in Phase 9 getestet (Spike). **Ersatz, falls nicht:** In der Erweiterung einmalig einen 6-stelligen Kopplungscode eingeben (aus den App-Einstellungen), danach läuft es ohne weitere Eingabe. |
| A2 | Instagram-Inhalte | Instagram gibt Beschreibung/Video ohne Login nicht immer heraus. Geplant: öffentliche Einbettungs-Seite des Beitrags lesen. Klappt das bei einem Beitrag nicht, zeigt die App „Rezept steht nicht in der Beschreibung“ und bietet an, Screenshots zu wählen. *(Screenshots hattest du nicht ausgewählt – ist dieser Ersatz ok?)* |
| A3 | KI-Bilder pro Schritt (9) | Braucht einen **fal.ai-Key** (`FAL_KEY`), ca. 0,3 Cent pro Bild → etwa 2 Cent pro Rezept. Bilder werden einmal erzeugt und auf dem Server gespeichert. |
| A4 | Push-Nachrichten | Ohne bezahlten Apple-Account über die App **ntfy** (kostenlos, einmal installieren und Kanal abonnieren). Betrifft 17, 27, 40, 58, 38. |
| A5 | Standort-Erinnerung (36) | Braucht die Standort-Erlaubnis **„Immer“**; iOS erlaubt max. 20 überwachte Orte → die 20 nächsten gewählten Läden. |
| A6 | Nährwerte (2) | Quelle: USDA-Nährwertdatenbank (gemeinfrei, englisch). Die KI ordnet deutsche Zutaten einmalig einem Eintrag zu, Werte kommen aus der Datenbank (E10). Genauigkeit „gute Schätzung“, nicht Laborwert. |
| A7 | Payback/Rewe Bonus (38) | Keine offizielle Schnittstelle → Coupons per Foto/Scan, Guthaben manuell. Keine Logins bei Payback/Rewe über die App. |
| A8 | Ziele pro Person (48) | Nur für **eingeladene Mitglieder** (deine Wahl) – Kinder ohne Handy bekommen kein eigenes Profil. |
| A9 | Lunchbox (24) | Nur Arbeit/Erwachsene, eigene Gerichte (nicht automatisch Reste vom Vorabend). |
| A10 | Dashboard (34) | Ausgaben = Preise der **abgehakten** Artikel (geschätzt; Artikel ohne Preis zählen mit Normalpreis-Schätzung). |
| A11 | IONOS-VPS (72) | Ca. 5–10 €/Monat + Domain (~1 €/Monat). Die IONOS-Verbindung in Claude war vorhin nicht erreichbar → du richtest VPS/Domain ein oder gibst mir Zugriff, das Aufsetzen mache ich. |
| A12 | Rewe-Bonus-Aktionen (39) | Ob die Prospektdaten Bonus-Beträge enthalten, ist unklar → Recherche-Schritt am Anfang; sonst Erkennung über den Prospekttext. |
