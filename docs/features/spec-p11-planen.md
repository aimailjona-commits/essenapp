# Phase 11 – Clever planen

Alle Punkte erweitern den Plan-Generator (S7) und den Planner. Neue Regeln gehen als kompakte Zeilen in den **variablen** Prompt-Teil (Caching bleibt, E38).

---

## 12 · Abwechslungsregeln

**Einstellungen › Präferenzen › „Abwechslung“** (Karten mit Steppern/Schaltern):
- max. Pasta pro Woche (Standard 1), max. Reis (2), max. Kartoffeln (2)
- Fisch mind. pro Woche (0–3, Standard 1)
- Vegetarische Tage pro Woche (0–7, Standard 2)
- Rotes Fleisch max. pro Woche (Standard 2)
- Gleiches Gericht frühestens nach N Wochen (Standard 3)
- Gleiche Küche nicht zwei Tage hintereinander (an/aus)

**Technik:** KI gibt pro Gericht `tags` (Hauptbeilage: pasta/reis/kartoffel/brot/…, Protein: fisch/rot/geflügel/vegetarisch/vegan). Nach dem Planen prüft der Code alle Regeln; Verstöße → eine gezielte Reparatur-Runde nur für die betroffenen Slots (günstig). Im Plan-Kopf Chip „✓ Abwechslung“ oder „⚠ 2× Pasta“.

**Abnahme:** 10 Testpläne halten alle Regeln ein (Unit-Test mit gefälschter KI + 2 echte Pläne).

---

## 15 · Gäste-Modus

- Plan-Generator: pro Tag/Mahlzeit „+ Gäste“ (Stepper 0–20) auf den Tagespillen (Badge „+4“).
- Optional „Gäste-Budget extra“ (Betrag) – sonst aus dem Wochenbudget.
- Mengen/Kosten des Slots skaliert; Gericht soll „gästetauglich“ sein (Prompt-Hinweis).
- Auch nachträglich: Gericht im Plan › „Gäste hinzufügen“ → Mengen + Liste aktualisiert (ohne KI).

**Abnahme:** Samstag +4 → Mengen ×(Esser+4)/Esser, Einkaufsliste angepasst.

---

## 16 · „Keine Lust“-Knopf

- Auf der Heute-Karte (Start) und im Wochenplan: Knopf „😮‍💨 Keine Lust“.
- Sheet: 3 Vorschläge ≤ 15 min, **nur** aus Vorrat (60) + Basics + bereits gekauften/abgehakten Listenartikeln, kein Einkauf nötig. Wischen für weitere 3.
- Auswahl ersetzt das heutige Gericht; das ursprüngliche wandert als Vorschlag auf einen späteren Tag („Auf morgen verschieben?“), damit gekaufte Zutaten nicht verfallen.

**Abnahme:** Vorschläge kommen in < 8 s, enthalten keine fehlenden Zutaten, Verschieben funktioniert.

---

## 17 · Auto-Wochenplan „erst nachfragen“

- Einstellungen › Benachrichtigungen: „Wochenplan-Erinnerung“ an/aus, Tag (Standard Sonntag) + Uhrzeit (Standard 18:00).
- Server-Job sendet ntfy-Push „🍽️ Neue Woche – sollen wir deinen Plan für KW 46 erstellen?“ mit Aktionen „Plan erstellen“ (öffnet `essenapp://generator`) und „Später“ (erinnert in 2 h, max. 2×).
- Die App öffnet den Plan-Generator mit deinen Standards + Hinweis „Diese Woche im Angebot: …“ (Top-3-Angebote).

**Abnahme:** Push kommt pünktlich (±2 min), Tippen öffnet den Generator, „Später“ erinnert erneut.

---

## 19 · Reste-Planung

- Pricing kennt Reste (Packung 400 g, gebraucht 250 g → 150 g Rest).
- Planner-Durchgang 2: Reste mit Haltbarkeit (frisch 2–3 Tage, Kühlung 4 Tage, Vorrat egal) werden an die KI gegeben: „verwende 150 g Hähnchen bis Mi, 100 g Feta bis Do“ → Gerichte der Folgetage nutzen sie.
- UI: Badge „♻︎ Rest von Mo“ an Zutaten/Gerichten, Plan-Kopf Karte „Reste: 3 verplant, 1 übrig (Sahne 100 ml)“ mit Vorschlag.
- Nach dem Kochen: tatsächliche Reste bestätigen → Vorrat (60).

**Abnahme:** Testplan mit Packungsresten → mind. 70 % der Reste werden in Folgegerichten verwendet; Badges korrekt.

---

## 23 · Frühstück & Snacks

**a) Feste Basics jede Woche**
- Einstellungen › „Frühstück & Snacks“: Liste deiner Basics (z. B. Haferflocken 1 kg/Woche, Joghurt 2×500 g, Brot, Bananen) mit Wochenmenge.
- Jede Woche automatisch auf die Haushaltsliste (Quelle „basics“), **Angebot bevorzugt** (gleiches Produkt günstiger in gewähltem Laden → Laden-Zuordnung), Vorrat wird abgezogen.

**b) Abwechselnde Frühstücksideen**
- Wenn Mahlzeit „Frühstück“ aktiv: jeden Tag ein einfaches Frühstück aus Bausteinen (Basis + Topping + Obst/Gemüse), überwiegend aus den Basics, max. 10 min, Abwechslung über die Woche.

**c) Snacks für unterwegs**
- Neue Mahlzeit „Snack“ (Chip im Generator): 1 Snack pro Tag, transportierbar, zielbezogen (proteinreich → Skyr-Becher, Nüsse; kalorienarm → Gemüsesticks + Hummus), Vorkoch-Hinweis (Energy Balls am Sonntag für 5 Tage).

**Abnahme:** Basics stehen montags auf der Liste (mit Angebotspreisen), Frühstück variiert an 7 Tagen, Snacks passen zum Ziel.

---

## 24 · Lunchbox (Arbeit)

- Pro Mitglied (48): Lunchbox-Tage (z. B. Mo–Fr).
- Planner legt für diese Tage eigenen Slot „Lunchbox“ an: kalt essbar oder gut aufwärmbar, transportsicher, 1 Portion pro Person, am Vorabend vorbereitbar (Hinweis-Schritt „am Vorabend: …“).
- UI: Lunchbox-Karte im Tagesplan mit 🥡-Badge; Abend-Push optional „Lunchbox für morgen vorbereiten“.

**Abnahme:** Mitglied mit Mo–Fr bekommt 5 passende Gerichte, keine Suppen ohne Thermobehälter-Hinweis.

---

## 25 · Feiertags- & Saison-Specials

- Kalender: deutsche Feiertage (bundesweit + Bundesland aus PLZ), Anlässe (Weihnachten, Silvester, Ostern, Muttertag, Halloween), Saisons (Spargel Apr–Jun, Grillsaison Mai–Aug, Kürbis Sep–Nov, Glühwein/Plätzchen Dez), Saisonkalender Obst/Gemüse (für Hinweise).
- 14 Tage vorher: Start-Banner („🎄 Weihnachten in 12 Tagen – Menü planen?“) → Generator mit Special-Vorlage (Festtagsmenü: Vorspeise/Haupt/Dessert, Plätzchen-Back-Plan, Grillparty inkl. Beilagen).
- Planner bevorzugt Saisonzutaten immer leicht (Hinweis im Prompt).

**Abnahme:** Datum 10.12. simuliert → Weihnachts-Banner; Spargelzeit → Spargel-Vorschläge.
