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

## Weitere Screens (nach Freigabe der Kern-Screens spezifizieren)

| ID | Screen | Kurz |
|---|---|---|
| S6 | Onboarding | Vollbild-Foto + schwarzer Pill-Button (Referenz 03), dann PLZ & Läden, Haushalt & Ernährung, Budget & Ziel, Push (ntfy) |
| S7 | Plan-Generator (Sheet) | Läden, Küchen, Mahlzeiten, Tage, Budget-Regler, Nährwertziel, „Erstellen“ |
| S8 | Bewertung (Sheet) | `RatingStars`, „Wieder kochen?“, Notiz |
| S9 | Angebotsdetail | Großes Bild, Preis, Grundpreis, Gültigkeit, Laden, „Zur Liste“, „Auf Merkliste“, passende Rezepte |
| S10 | Merkliste | Lieblingsprodukte mit Status (im Angebot wo / nicht), Hinzufügen per Suche oder Barcode |
| S11 | Ersparnis | Großer Betrag (Referenz 08), Verlauf nach Woche |
| S12 | Meine Rezepte | Favoriten, eigene, zuletzt gekocht, Bewertungen; Rezept anlegen |
| S13 | Einstellungen | Haushalt, Ort/Filialen, Läden, Ernährung, Budget, Ziele, Benachrichtigungen, Familie, Backend-URL |
