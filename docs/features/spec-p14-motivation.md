# Phase 14 – Motivation & Teilen

---

## 54 · Erfolge (Sparen + Gesundheit)

**Sparen**
- 💰 10 € / 50 € / 100 € / 250 € / 500 € / 1.000 € gespart (Angebote + Bonus)
- 🎯 Budget-Wächter: 1 / 4 / 12 Wochen in Folge im Budget
- 🔥 Bestpreis-Jäger: 10 / 50 Bestpreis-Angebote (28) gekauft
- 🏦 Vorratsprofi: 5 Vorratskauf-Tipps (31) genutzt

**Gesundheit** (pro Mitglied, aus 2/48)
- 💪 Proteinziel 3 / 7 / 30 Tage erreicht
- 🥦 Pflanzenvielfalt: 15 / 30 verschiedene Pflanzen pro Woche
- ⚖️ Ausgewogen: 7 Tage kcal-Ziel ±10 %

**UI:** Profil › „Erfolge“: Raster mit Medaillen (gesperrt = grau mit Fortschrittsring), Detail mit Datum. Freischalten: Vollbild-Moment mit Konfetti, Medaille fliegt ein, Haptik; Push optional.

**Abnahme:** Regeln per Unit-Test; Freischalten genau einmal; Fortschritt sichtbar.

---

## 55 · Wochenrückblick

- Sonntag 19:00 (Job) bzw. beim ersten Öffnen ab Sonntag: Story-artige Seiten (wischen, 5–6 Seiten, Fotos/Emojis, Zahlen zählen hoch):
  1. „Deine Woche“: X Gerichte gekocht, Lieblingsgericht (beste Bewertung)
  2. Gespart & ausgegeben (34), Budget-Status
  3. Gesundheit: Protein-/kcal-Schnitt, Pflanzenvielfalt
  4. Vorrat & Reste: verwendet, weggeworfen (falls erfasst)
  5. Neue Erfolge
  6. „Nächste Woche günstig“ (30) + Knopf „Plan erstellen“
- Teilen als Bildkarte (wie 10).
- Archiv aller Rückblicke.

**Abnahme:** Rückblick mit echten Zahlen, alle Seiten, Teilen funktioniert.

---

## 56 · Rezepte zwischen Haushalten teilen

- Rezept › Teilen › „Als Link“: `https://<domain>/r/<code>` (VPS 72).
- Web-Ansicht (für alle): Foto, Zutaten, Schritte, „Mit Essenapp geplant“; Knopf „In meine Rezepte übernehmen“ – für App-Nutzer öffnet der Link per Deep-Link `essenapp://import-recipe/<code>` die App; Web-Nutzer eines Haushalts können es in ihren Haushalt übernehmen.
- Übernommenes Rezept = Kopie mit Quelle „von Familie Müller“.

**Abnahme:** Link öffnet Web-Ansicht, Übernahme legt Kopie im anderen Haushalt an.
