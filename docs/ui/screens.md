# Screens

Status: **Entwurf v2** – offene Punkte im autonomen Modus entschieden (E17–E21, siehe Playbook). Mockups: `mockups/kern-screens-v1.html`, `mockups/weitere-screens-v1.html`.

## Navigation

Tab-Bar (Komponente `TabBar`):

| Position | Tab | Inhalt |
|---|---|---|
| 1 | **Start** | Überblick der Woche |
| 2 | **Angebote** | Angebote + Merkliste (Lieblingsprodukte) |
| Mitte | **Schwarzer Button** | Öffnet **Schnell-Aktionen** (E14): Wochenplan erstellen, Barcode scannen, Zur Einkaufsliste, Rezept anlegen |
| 3 | **Einkauf** | Einkaufslisten |
| 4 | **Rezepte** | Wochenplan-Gerichte, gespeicherte und eigene Rezepte |

Einstellungen/Profil: über den Avatar oben rechts auf dem Start-Screen.

## Kern-Screens (Mockups in Phase 0)

### S1 Start
- `DisplayHeader`: „Was kochen wir / diese Woche?“ + Avatar, Glocke
- `SearchField` (sucht Rezepte und Angebote)
- **Heute:** große `MealCard` des heutigen Gerichts (Mahlzeit-Chip: Frühstück/Mittag/Abend/Dessert)
- **Diese Woche:** horizontal scrollende `MealCard`s, „Alle ansehen“ → Wochenplan
- **Budget-Karte:** geplant vs. Budget (Fortschrittsbalken), Ersparnis durch Angebote → Ersparnis-Screen
- **Im Angebot:** Hinweis „3 deiner Lieblingsrezepte sind diese Woche günstig“ / Merkliste-Treffer
- Zustände: kein Plan → `EmptyState` „Noch kein Wochenplan“ + `PrimaryButton` „Plan erstellen“; Laden → Skeleton

### S2 Wochenplan
- Kopf: „KW 45“, Zeitraum, Gesamtkosten, Budget-Status
- Tagesleiste horizontal (Mo–So, aktiver Tag schwarz)
- Pro Mahlzeit eine Karte: Tellerbild, Name, Zeit, Preis/Portion, `NutrientStat`s
- Aktionen pro Gericht: neu würfeln, fixieren (Schloss), ersetzen durch eigenes Rezept, entfernen
- Tageswerte unten: kcal, Protein, KH, Fett gegen Ziel
- Zustände: wird erstellt → Skeleton + Text „Angebote werden ausgewertet …“

### S3 Rezeptdetail
- Großes freigestelltes Tellerbild oben (wie Referenz 02), Zurück-Button, Merken (Herz)
- Name (`title`), darunter Portion in g, Preis pro Portion, Zeit
- `NutrientTile`s: kcal, Protein, KH, Fett
- `ShareBloom`: Anteile der Zutaten am Gewicht (E19)
- Zutatenliste: Bild/Icon, Name, Menge; bei Angebot `DealBadge` + `StoreChip`; Vorrat-Hinweis
- Portionen-Stepper
- Zubereitungsschritte nummeriert
- Unten fest: `PrimaryButton` „Gekocht – bewerten“

### S4 Angebote
- Oben: Filiale/Ort mit Umschalter (wie Referenz 08), rechts Merkliste-Button
- Segment: „Angebote“ | „Merkliste“
- `FilterChips`: Alle, je Laden, Kategorien (Obst & Gemüse, Fleisch & Fisch, Kühlung, Vorrat, Drogerie, Haushalt) mit Anzahl
- `SearchField`
- Raster 2-spaltig mit `OfferCard`
- Zustände: keine Angebote für Filter → `EmptyState`; Händler nicht erreichbar → Hinweis-Banner, Rest anzeigen

### S5 Einkauf
- Übersicht: `ListCard` pro Laden (Pastellton aus `listTints`, E18) mit Anzahl offener Artikel und Avataren
- Detail: Kopf mit Laden, Summe, Ersparnis; `ChecklistRow`s nach Kategorie gruppiert; abgehakte nach unten
- Artikel hinzufügen (Freitext), Mitglieder einladen (+)
- Offline abhakbar

## Weitere Screens

Mockups: `mockups/weitere-screens-v1.html`.

### S6 Onboarding (4 Schritte, Fortschritt als 4 Striche oben)
1. **Willkommen:** Vollbild-Foto (KI-Tellerfoto-Collage) mit dunklem Verlauf nach unten, `display` weiß „Kochen nach / Angebot.“, ein Satz Erklärung, `PrimaryButton` (hier weiß auf schwarz invertiert) „Los geht's“, darunter Textlink „Ich habe einen Einladungslink“.
2. **Ort & Läden:** `DisplayHeader` „Wo kaufst / du ein?“, PLZ-Feld (5 Ziffern, Zahlentastatur), darunter Liste der verfügbaren Händler als Zeilen mit Schalter; bei filialabhängigen Händlern (Rewe, Edeka) erscheint nach dem Einschalten „Filiale wählen ›“ mit den nächstgelegenen Filialen. Weiter-Button erst aktiv bei gültiger PLZ und ≥ 1 Laden.
3. **Haushalt & Ernährung:** Personen-Stepper, Ernährungsform als Chips (Alles, Vegetarisch, Vegan, Pescetarisch, Halal), Allergien als Mehrfach-Chips (Gluten, Laktose, Nüsse, Erdnüsse, Ei, Soja, Fisch, Sellerie), Freitext „Mag ich nicht“.
4. **Budget & Ziel:** Budget-Regler 20–200 €/Woche (Schritt 5 €, Betrag groß), Nährwertziel als große Auswahlkarten (Ausgewogen, Proteinreich, Kalorienarm, Eigenes), Mahlzeiten als Chips (Frühstück, Mittag, Abend, Dessert), Küchen als Chips. `PrimaryButton` „Ersten Plan erstellen“.
- Push (ntfy) wird nicht im Onboarding abgefragt, sondern später in S13.
- Zustände: Händlerliste lädt → Skeleton-Zeilen; PLZ ohne Händler-Daten → Hinweis „Für diese PLZ haben wir noch keine Angebote“.

### S7 Plan-Generator (Sheet von unten, Radius 36, Griff oben)
- Titel „Wochenplan erstellen“, Untertitel „KW 45 · 2.–8. November“ (Woche umschaltbar ‹ ›).
- Abschnitte, vorbelegt aus den Einstellungen, hier nur für diesen Plan änderbar:
  - Läden (Chips mit Anzahl Angebote)
  - Küche (Chips, Mehrfachauswahl, „Gemischt“ = alle)
  - Mahlzeiten (Chips) und Tage (Mo–So als runde Toggles)
  - Budget (Regler + Betrag)
  - Ziel (Segment: Ausgewogen / Proteinreich / Kalorienarm)
  - Schalter „Lieblingsrezepte bevorzugen“ (an), „Vorrat zuerst verbrauchen“ (an)
- Fester `PrimaryButton` „Plan erstellen“ mit Sparkle-Icon.
- **Lade-Zustand** (eigener Screen im Sheet): Teller-Platzhalter dreht sich langsam, darunter wechselnde Schritte mit Häkchen: „Angebote auswerten“ → „Lieblingsrezepte prüfen“ → „Gerichte planen“ → „Preise & Nährwerte rechnen“. Dauer < 60 s.
- Fehler: `ErrorState` im Sheet mit „Erneut versuchen“; Budget nicht erreichbar → Hinweis mit günstigster gefundener Summe und Button „Trotzdem übernehmen“.

### S8 Bewertung (Sheet, halbe Höhe)
- Kleines Tellerfoto + Gericht-Name.
- „Wie war's?“ + `RatingStars` (groß).
- „Wieder kochen?“ Segment: Bald / Irgendwann / Nie. „Nie“ = Rezept wird nicht mehr vorgeschlagen.
- Optionale Notiz (einzeilig, wächst).
- `PrimaryButton` „Speichern“. Nach dem Speichern: kurzer Haken-Toast „Gespeichert – kommt öfter“ (bei 4–5 Sternen).

### S9 Angebotsdetail (Push-Screen)
- Oben großes Produktbild auf getönter Fläche (Radius 36), `DealBadge` oben links, Herz (Merkliste) oben rechts.
- Name (`title`), Marke + Menge (`caption`).
- Preis groß, Normalpreis durchgestrichen, Grundpreis, `StoreChip`, „gültig bis Sa, 7.11.“.
- „Passt zu“: horizontale kleine `MealCard`s mit Rezepten aus Plan oder Favoriten, die die Zutat nutzen.
- Fester `PrimaryButton` „Zur Einkaufsliste“ (wird zu „Auf der Liste ✓“ mit `SecondaryButton`-Stil, wenn schon drauf).

### S10 Merkliste (Tab „Angebote“, Segment „Merkliste“)
- Kopf wie S4, Segment auf „Merkliste“.
- Zuerst Abschnitt **„Diese Woche im Angebot“**: Zeilen mit Produktbild, Name, bester Preis + Laden, `DealBadge`, Pfeil → S9.
- Dann **„Beobachtet“**: Zeilen mit Name, „zuletzt im Angebot: KW 41 bei dm“ oder „noch nie gesehen“, optional Wunschpreis („Alarm unter 2,00 €“).
- Unten zwei Buttons nebeneinander: `SecondaryButton` „Suchen“ und `PrimaryButton` „Barcode scannen“.
- Barcode-Scan: Vollbild-Kamera mit Limetten-Ecken-Rahmen (wie Referenz 02), Treffer → Sheet „Auf Merkliste?“ mit Produktname.
- Leer: `EmptyState` „Merk dir Lieblingsprodukte – wir sagen Bescheid, wenn sie im Angebot sind.“

### S11 Ersparnis (Push-Screen aus S1/S5)
- `DisplayHeader` „Gespart / seit Oktober“.
- Große Karte: Betrag gesamt (sehr groß, `success`), darunter „diese Woche 12,40 €“.
- Balkendiagramm letzte 8 Wochen (Balken `accent`, aktuelle Woche `accentDeep`), Achse KW.
- Verlauf nach Woche (wie Referenz 08): Datum-Gruppen, Zeilen „Rewe · 14 Artikel  +4,60 €“.

### S12 Meine Rezepte (Tab „Rezepte“, Segment „Meine Rezepte“)
- `SearchField` + Filter-Chips: Alle, Favoriten ♥, Eigene, Zuletzt gekocht, Im Angebot.
- Raster 2-spaltig mit `MealCard` (klein): Tellerfoto, Name, Sterne-Durchschnitt, Preis/Portion, Badge „im Angebot“ wenn ≥ 40 % der Kosten im Angebot.
- Rechts oben runder Button „+“ → Rezept anlegen (Formular: Name, Foto optional, Portionen, Zutaten-Zeilen mit Menge/Einheit, Schritte, Küche, Mahlzeit, Zeit).
- Leer: `EmptyState` „Noch keine Rezepte gespeichert“.

### S13 Einstellungen (Push-Screen über Avatar)
- Kopf: Avatar groß, Name, Haushaltsname.
- Gruppen als weiße Karten mit Zeilen (Icon im getönten Quadrat, Titel, aktueller Wert grau, Chevron):
  - **Haushalt:** Personen, Ernährung, Allergien, Mag ich nicht
  - **Einkaufen:** Ort (PLZ), Läden & Filialen, Budget Lebensmittel, Budget Drogerie
  - **Planung:** Mahlzeiten, Tage, Küchen, Nährwertziel, Max. Kochzeit
  - **Benachrichtigungen:** ntfy einrichten (QR-Code + Topic), Wochenplan-Erinnerung (Tag/Uhrzeit), Angebotsalarme an/aus
  - **Familie:** Mitglieder (Avatare), „Einladungslink teilen“
  - **App:** Server-Adresse, Version, „Neu installieren fällig in 5 Tagen“ (7-Tage-Signatur, E2)
- Änderungen werden sofort gespeichert (kein Speichern-Button), Fehler als Banner.
