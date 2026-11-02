# Screens

Status: **Entwurf v2** – offene Punkte im autonomen Modus entschieden (E17–E21, siehe Playbook). Mockups: `mockups/kern-screens-v1.html`, `mockups/weitere-screens-v1.html`.

## Navigation

Tab-Bar (Komponente `TabBar`):

| Position | Tab | Inhalt |
|---|---|---|
| 1 | **Start** | Überblick der Woche |
| 2 | **Angebote** | Angebote + Merkliste (Lieblingsprodukte) |
| Mitte | **Schwarzer Button** | Öffnet **Schnell-Aktionen** (E14): Wochenplan erstellen, Barcode scannen, Zur Einkaufsliste, Rezept anlegen (→ S17, auch `essenapp://recipe/new`), dazu volle Breite „📸 Kühlschrank scannen“ (→ S23, Feature 69). Solange es keinen Barcode-Scanner gibt, steht an seiner Stelle „Angebote stöbern“ |
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
  - Karte „📸 Kühlschrank scannen“ (Feature 69) unter „Lieblingsrezepte günstig“: Emoji im getönten Quadrat, Titel, „Fotos machen – wir füllen den Vorrat und schlagen Gerichte vor“, Chevron → S23.
  - Karte unter dem Budget (Feature 3, `GET /recipes/deals`): bis zu 3 überlappende Tellerfotos, Text „N Lieblingsrezepte sind diese Woche günstig“, darunter die ersten Titel, Chevron. Tippen → Tab Rezepte › Meine Rezepte mit Filter „Im Angebot“. Keine Treffer → Karte fehlt.
- Zustände: kein Plan → `EmptyState` „Noch kein Wochenplan“ + `PrimaryButton` „Plan erstellen“; Laden → Skeleton

### S2 Wochenplan
- Kopf: „KW 45“, Zeitraum, Gesamtkosten, Budget-Status
- Tagesleiste horizontal (Mo–So, aktiver Tag schwarz)
- Pro Mahlzeit eine Karte: Tellerbild, Name, Zeit, Preis/Portion, `NutrientStat`s
- Aktionen pro Gericht: neu würfeln, fixieren (Schloss), ersetzen durch eigenes Rezept, entfernen
- Tageswerte unten: kcal, Protein, KH, Fett gegen Ziel
  - Umsetzung (Feature 2/48): Karte „Tageswerte“ unter den Gerichten, rechts „Für: 🧑‍🍳 Jona ▾“. Pro Person Ringe (außen kcal, innen Protein gegen das Ziel aus dem Profil, Emoji in der Mitte, Name darunter; gewählte Person auf `accentSoft`, Tippen wählt sie). Darunter 4 `NutrientStat` (kcal, Protein, KH, Fett) der gewählten Person und „Ziel Jona: 2500 kcal · 140 g Protein“. Fehlen Nährwerte (`complete = false`) → Schimmer über Ringen/Werten + „Nährwerte werden noch berechnet …“, einmal nach ~3 s neu laden. Ringe animieren nach Würfeln/Ersetzen.
  - Kopf: Wochenschnitt der gewählten Person „🧑‍🍳 Ø 1980 / 2500 kcal · 104 / 140 g Protein pro Tag“.
  - Gericht-Zeile: Aktionen als 2×2 runde Knöpfe – Herz (Favorit), Ersetzen (→ S19 „Durch eigenes Rezept ersetzen“), Schloss, Würfel.
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
- Darüber fest: `PrimaryButton` in `accent` „▶︎ Kochen starten“ → S18. Oben rechts runder Teilen-Knopf → Menü „Als Bild teilen“ (Bildkarte, Feature 10), „Als Link teilen“ (kommt mit Feature 56)
- Phase 9 (Features 2 + 3), gilt für Plan-Gerichte und gespeicherte Rezepte (aus S12):
  - Kopfzeile: Zurück · Herz (Favorit des Haushalts, `symbolEffect(.bounce)` + Haptik) · bei eigenen/importierten Rezepten runder „…“-Knopf (Bearbeiten → S17, Löschen → Rückfrage „Rezept löschen?“; steht es im Plan, bleibt es dort) · Teilen.
  - Unter dem Namen: Sterne-Durchschnitt + „4,5 · 2 Bewertungen“ (nur wenn bewertet).
  - Gespeichertes Rezept: `SecondaryButton` „Diese Woche einplanen“ → S19. Preis = Live-Kosten aus den aktuellen Angeboten, Angebotszutaten mit `DealBadge` + `StoreChip`.
  - „Für:“-Karte, darunter 4 `NutrientTile` (kcal, Protein, KH, Fett) pro Portion der gewählten Person (Portion × Faktor aus dem kcal-Ziel). Werte fehlen noch → 4 Schimmer-Kacheln, einmal nach ~3 s neu laden.
  - Karte „Zusammensetzung“ mit `ShareBloom`: Tellerfoto in der Mitte, je Zutat ein Blütenblatt mit Verlauf (Länge nach Anteil), außen Prozent + Name; Anteile < 3 % → „Sonstiges“ (grau); ganze Prozent, Summe 100. Blätter wachsen nacheinander auf (bei „Bewegung reduzieren“ ohne Versatz). Fehlt die Zusammensetzung noch → Schimmer.
  - Zutatenmengen im Plan = Rezeptmenge × `scale`; „Deine Portion“ = Menge × scale × Faktor / portions_total.
  - Unten Karte „Bewertungen“: Name, Sterne, Datum, „Wieder kochen: Bald/Irgendwann/Nie“ (Nie rot), Notiz.
- Phase 9 (Features 5 + 9):
  - Importierte Rezepte (`source` instagram/web): unter dem Namen Quelle-Chip „Instagram · @autor“ bzw. „Web · Autor/Domain“; bei Instagram rechts schwarzer Pill-Knopf „▶︎ Original-Reel“ (öffnet `source_url` → Instagram-App, sonst Safari).
  - Zutaten mit `estimated` bekommen den Badge „Menge geschätzt“.
  - Zubereitung: über jedem Schritt das Schritt-Bild 16:10 (Radius Kachel). Leer (`""`) und Schritt-Bilder eingeschaltet → Schimmer-Platzhalter; die App fragt `POST /recipes/{id}/step-images` mit wachsendem Abstand (2 s, 4 s … max. 30 s) nach, solange `pending`. Fertig/aus → leere Plätze verschwinden. Abgehakte Schritte: Bild halb transparent.

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
- Offline abhakbar (Feature 66): ohne Netz oder Server oben Glas-Banner (Liquid Glass, sonst Material, Symbol `wifi.slash`) „Offline – Änderungen werden später übertragen“ über allen Screens. Abhaken, Artikel hinzufügen/entfernen (Haushaltsliste und einmalige Listen) und Vorrat (anlegen, Menge, löschen) wirken sofort und warten in einer Warteschlange; beim nächsten Netz der Reihe nach gesendet, dann neu geladen. Konflikte: letzter Stand gewinnt pro Feld, auf dem Server abgehakte Artikel bleiben abgehakt. Angezeigt wird der zuletzt geladene Stand (Cache) von Haushalt, Plan, Listen, Angeboten, Vorrat, Rezepten; Bilder aus dem URLCache, wenn schon gesehen. Demo: `offline`.

### Dark Mode (Feature 68, alle Screens)
- Jeder Screen hat eine dunkle Fassung mit den Werten aus `design-system.md` (Abschnitt Dark Mode). Ausnahmen: Kochmodus S18 immer dunkel, Bildkarte (Feature 10) immer hell. Teilen-Erweiterung S20 folgt dem System.
- CI-Screenshots: jeder Demo-Screen zusätzlich als `dark-<name>` (`-demoAppearance dark`).

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
- Speichern → `POST /recipes/{id}/rate` (wer und wann setzt der Server); Fehler → Toast, Sheet bleibt offen.
- Optionale Notiz (einzeilig, wächst).
- `PrimaryButton` „Speichern“. Nach dem Speichern: kurzer Haken-Toast „Gespeichert – kommt öfter“ (bei 4–5 Sternen).

### S14 Läden & Umkreis (Karte)
- Karte (MapKit) mit Umkreis-Kreis um die PLZ, Pins pro Laden (Farbe der Kette, Anfangsbuchstabe), Tippen wählt aus.
- Regler 1–30 km; nach Loslassen neue Suche (`GET /stores/nearby`). Liste darunter mit Entfernung, Adresse, Haken.
- „X Läden übernehmen“ speichert Läden + Umkreis und lädt Angebote neu. Erreichbar aus Onboarding (Schritt 2), Angebote-Kopf und Einstellungen.

### S9 Angebotsdetail (Push-Screen)
- Oben großes Produktbild auf getönter Fläche (Radius 36), `DealBadge` oben links, Herz (Merkliste) oben rechts.
- Name (`title`), Marke + Menge (`caption`).
- Preis groß, Normalpreis durchgestrichen, Grundpreis, `StoreChip`, „gültig bis Sa, 7.11.“.
- „Passt zu“: horizontale kleine `MealCard`s mit Rezepten aus Plan oder Favoriten, die die Zutat nutzen.
- Fester `PrimaryButton` „Zur Einkaufsliste“ (wird zu „Auf der Liste ✓“ mit `SecondaryButton`-Stil, wenn schon drauf).
- Phase 12 (Feature 28): Karte **„Preisverlauf“** direkt unter dem Preis (`GET /offers/{id}/history`): Kopf „Preisverlauf“, rechts Urteil-Badge (getönte Pille): „🔥 Bestpreis“ (`deal`), „👍 Gutes Angebot“ (`success`), „😐 Normal“ (`text2`), „⚠️ Kein echtes Angebot“ (`warning`). Swift-Charts-Diagramm (220 pt) der letzten 12 Wochen: Stufenlinie je Laden (Farbe `Theme.storeColor`, Legende unten), Angebotswochen als Punkte, aktuelle Woche als `accentSoft`-Band und großer Punkt, Normalpreis (Streichpreis, sonst Median der Wochen ohne Angebot) als gestrichelte Linie mit „Normalpreis 5,99 €“. Antippen/Ziehen zeigt eine Linie mit Kästchen „KW 41 · Lidl 3,79 € · Angebot“. Darunter zwei `surface`-Kacheln „Median 12 Wochen“ / „Tiefstpreis“, „Zuletzt so günstig: KW 38 bei Lidl (3,79 €)“, „Im Schnitt alle 4 Wochen im Angebot“. Zustände: Laden → Skeleton (200 pt); `zu_wenig_daten` → „Noch zu wenig Daten (ab 3 Wochen)“ ohne Diagramm und Badge; Fehler → „Preisverlauf gerade nicht verfügbar.“ + „Erneut versuchen“. Demo: `offer`.
- Phase 9 (Feature 2): Karte „Nährwerte“ unter den Fakten (`GET /offers/{id}/nutrition`): `PillSegment` „pro 100 g | pro Packung (400 g)“ (nur wenn `per_pack`), 4 `NutrientTile` (kcal, Protein, KH, Fett), darunter „Quelle: USDA FoodData Central · „<food>““. `pending` → Schimmer-Kacheln + „Nährwerte werden zugeordnet …“, nach 3/6/12/24 s neu fragen. `none` → Karte fehlt.

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
- Kopf: `DisplayHeader` „Meine Rezepte / N gespeichert“, rechts runder weißer Button 🔗 „Rezept aus Link importieren“ → S22 und runder schwarzer Button „+“ → S17.
- `SearchField` („Rezept oder Tag suchen“, sucht im Backend in Titel und Tags) + `FilterChips` mit Anzahl (Spezifikation Phase 9): Alle · ♥ Favoriten · Eigene · Importiert · Im Angebot · Zuletzt gekocht (nach letztem Kochen sortiert).
- Bei „Alle“ ohne Suche oben Abschnitt **„🔥 Im Angebot diese Woche“** (`GET /recipes/deals`): horizontale Karten.
- Raster 2-spaltig mit `MealCard` (klein): Tellerfoto, Name, Sterne-Durchschnitt (sonst „noch nicht bewertet“), Preis/Portion aktuell, Badge „im Angebot“ wenn ≥ 40 % der Kosten im Angebot, Badge „Instagram“ bei Imports; Herz oben rechts. Lange drücken → „Diese Woche einplanen“ (S19). Tippen → S3.
- Zustände: Laden → 4 Skeleton-Karten; Fehler → `ErrorState`; leer → `EmptyState` „Noch keine Rezepte gespeichert“ + „Rezept anlegen“; Filter/Suche ohne Treffer → `EmptyState` „Nichts gefunden“.

### S13 Einstellungen (Push-Screen über Avatar)
- Kopf: Avatar groß, Name, Haushaltsname.
- Gruppen als weiße Karten mit Zeilen (Icon im getönten Quadrat, Titel, aktueller Wert grau, Chevron):
  - **Mein Profil** (ganz oben): Emoji-Avatar, Name, Ziel → S15
  - **Haushalt:** Personen, Ernährung, Allergien, Mag ich nicht
  - **Einkaufen:** Ort (PLZ), Läden & Filialen, Budget Lebensmittel, Budget Drogerie
  - **Planung:** Mahlzeiten, Tage, Küchen, Nährwertziel, Max. Kochzeit
  - **Benachrichtigungen** (Push über Apple/APNs, kein ntfy; Test-Push: 422 → Toast „Erst Mitteilungen erlauben“, 502 → „Apple hat abgelehnt“; die Wochenplan-Erinnerung hat die Aktionen „Plan erstellen“ → S7 und „Später“): Status der iOS-Erlaubnis (abgelehnt → „In iOS-Einstellungen öffnen“), „Test-Push senden“, Push an/aus, Wochenplan-Erinnerung (an/aus, Wochentag, Uhrzeit), Ruhezeit (an/aus, Von/Bis), Angebotsalarme an/aus. Vor der iOS-Abfrage einmal ein Erklär-Sheet „Nichts verpassen“ (nach dem Onboarding bzw. beim ersten Öffnen der Einstellungen). Antippen einer Mitteilung öffnet `essenapp://start|generator|offer/<id>`.
  - **Familie:** Mitglieder (Avatare), „Einladungslink teilen“
  - **Rezepte** (Phase 9): „Teilen aus Instagram“ → S21; Schalter „Schritt-Bilder erzeugen“ mit Untertitel „ca. 2 Cent/Rezept“ (nur wenn `step_images_available`, speichert `PATCH /household {step_images}`).
  - **App:** Erscheinungsbild (Menü **System · Hell · Dunkel**, Feature 68, sofort wirksam für alle Screens und Sheets), Server-Adresse, Version, „Neu installieren fällig in 5 Tagen“ (7-Tage-Signatur, E2)
- Änderungen werden sofort gespeichert (kein Speichern-Button), Fehler als Banner.

### S15 Mein Profil (Push-Screen aus S13, Feature 48)
- `DisplayHeader` „Mein Profil / Ziele & Essenszeiten“, Abschnitte als Karten wie Präferenzen.
- Avatar & Name: großes Emoji, Raster beliebter Emojis (8 Spalten), Namensfeld.
- Ziel als Karten (wie Onboarding): Ausgewogen, Proteinreich, Kalorienarm, Eigenes. Wahl setzt Vorschlag für kcal/Protein.
- Tagesziel: Ringe-Vorschau (kcal, Protein) + „Portion ×1,25“ (kcal / 2000, auf 0,25), Regler kcal (1000–5000) und Protein (0–400 g) mit Zahl, „Vorschlag übernehmen“.
- Allergien (`ChipFlow`) und „Mag ich nicht“ (Textfeld, kommagetrennt).
- **Isst mit:** Matrix Mahlzeiten × Mo–So als runde Toggles. **Lunchbox-Tage:** Mo–So runde Toggles.
- Fester `PrimaryButton` „Speichern“ (PATCH, Toast „Profil gespeichert“). Zustände: Laden → Skeleton, Fehler → `ErrorState`.
- Dazu: S3 zeigt „Für: 🧑‍🍳 Jona ▾“ (alle Profile) mit „Deine Portion: 520 g · 2,10 €“ und je Zutat die Menge der Person; Portionen-Stepper skaliert weiter das ganze Rezept. S2-Kopf zeigt die Avatare der Esser des Tages.

### S16 Vorrat (Tab „Einkauf“, Pille „Liste | Vorrat“, Feature 60)
- `DisplayHeader` „Vorrat / N Sachen zu Hause“ + runder „+“-Button.
- `SearchField`, `CategoryCircles` (Kategorie aus dem Namen, eigene Gruppe „Basics“ 🧂).
- Zeilen (weiße Kacheln): Emoji auf Kategorie-Tönung, Name, Menge, Haltbarkeits-Chip („läuft in 2 Tagen ab“ orange, „abgelaufen“ rot, sonst grau), rechts Stepper (g/ml 10er bzw. ab 100 50er, Stück 1er; 0 → Eintrag weg). Basics statt Stepper Schalter vorhanden/leer; leer → kommt auf die Liste, Toast „Öl steht auf der Liste“.
- Wischen nach links oder lange drücken → Löschen.
- „+“-Sheet: Name, Menge (optional), Einheit (g/ml/Stück/ohne), Haltbarkeit optional, Schalter „Basic“.
- Leer: `EmptyState` „📸 Kühlschrank fotografieren“ mit `PrimaryButton` „📸 Kühlschrank fotografieren“ → S23 (Feature 69). Laden → Skeleton, Fehler → `ErrorState`.
- Abhaken in S5b: haltbare Artikel → Toast „„Reis“ abgehakt“ mit Aktion „In den Vorrat“. „Gekocht ★“ (S8): nach dem Speichern wird der Vorrat abgezogen, Liste „Vom Vorrat abgezogen“ mit korrigierbaren Mengen, Toast „Vorrat aktualisiert“.

### S17 Rezept-Formular (Sheet, Feature 3)
- Kopf: „Neues Rezept“ bzw. „Rezept bearbeiten“, runder Schließen-Knopf; darunter 4 Fortschritts-Striche und „Schritt 2 von 4 · Zutaten“.
- Seite 1 **Das Rezept:** Tellerfoto-Vorschau (rund), `SecondaryButton`s „Kamera“ (nur wenn vorhanden) und „Fotos“; Foto wird auf ≤ 1600 px / ≤ 2 MB JPEG verkleinert. Titel, Stepper Portionen (1–20) und Zeit (5er-Schritte), Mahlzeit als Chips, Küche als Chips (optional).
- Seite 2 **Zutaten:** Zeilen mit Name, Menge (Zahlentastatur), Einheit (Menü: g, kg, ml, l, Stück, EL, TL, Prise), Entfernen; unter der aktiven Zeile Vorschläge aus bekannten Zutaten (Plan, Vorrat) als Chips; „+ Zutat hinzufügen“.
- Seite 3 **Zubereitung:** nummerierte Schritte, mehrzeilig, mit Griff sortierbar, Wischen löscht; „+ Schritt hinzufügen“.
- Seite 4 **Tags:** Feld + „+“, Tags als Chips (Tippen entfernt), Zusammenfassung „Titel · N Zutaten · M Schritte“.
- Unten „Zurück“ (`SecondaryButton`) + „Weiter“ / „Speichern“ (`PrimaryButton`, erst aktiv mit Titel bzw. ≥ 1 Zutat). Speichern → `POST /recipes` (`source=user`) bzw. `PATCH`, Toast „Rezept gespeichert“; Fehler → Toast, Sheet bleibt offen.

### S19 Diese Woche einplanen (Sheet, Feature 3)
- Titel „Diese Woche einplanen“, Satz „„Ofen-Lachs“ ersetzt das Gericht im gewählten Slot.“
- Zeilen aller Plan-Gerichte nach Tag und Mahlzeit: kleines Tellerfoto, „Dienstag · Mittag“, aktuelles Gericht, Schloss bei fixierten, Ersetzen-Symbol. Tippen → `POST /plans/current/entries/{id}/replace` (Mengen auf die Esser skaliert, Liste und Nährwerte neu), Toast „Eingeplant: Di · Mittag“.
- Kein Plan → `EmptyState` „Noch kein Wochenplan“.
- Aus S2 (Ersetzen-Knopf der Gericht-Zeile) umgekehrt: Titel „Durch eigenes Rezept ersetzen“, Satz „Dienstag · Mittag: „Tikka Masala“ wird ersetzt.“, Zeilen aus Meine Rezepte (Tellerfoto, Titel, „3,10 € / Portion · 40 min“); das aktuelle Gericht ist ausgegraut. Laden → Skeleton-Zeilen, Fehler → `ErrorState`, leer → `EmptyState` „Noch keine Rezepte gespeichert“.

### Fester Aktionsbereich (alle Screens mit Buttons über der Tab-Leiste)
- S3, S9, S14, S15, Präferenzen, S7: die festen Buttons liegen in einem Bereich unter dem Scroll-Inhalt (Safe-Area-Einschub) mit Verlauf von transparent nach `bg`; der letzte Inhalt lässt sich ganz hochscrollen.
- Zahlen, Uhrzeiten und Datumsangaben immer deutsch (Komma, 24 h), auch bei englischer Gerätesprache; Portionen ohne „,0“ (z. B. „2,25 Portionen“, „2 Portionen“).

### S18 Kochmodus (Vollbild aus S3, Feature 4 + 8)
- Dunkler Grund `cookBg` (#111), weiße Schrift, Bildschirm bleibt an. Oben: runder Schließen-Knopf ✕, „Schritt 2 von 4“ + Fortschrittsbalken (`accent`, gleitet mit Feder), rechts 🎙-Knopf (an = `accent`).
- Seite 0 **Vorbereitung**: alle Zutaten mit den in S3 gewählten Portionen (+ Menge der gewählten Person) als Zeilen zum Abhaken („3 von 6“), Haken-Haptik.
- Je **Schritt eine Seite** (wischen oder Pfeil-Knöpfe unten: runder ‹ + `PrimaryButton` in `accent` „Weiter ›“): Schritt-Bild oben 16:10 (nur wenn vorhanden; wird es noch erzeugt → dunkler Schimmer, Feature 9), „Schritt N“ (`accent`), Schritttext ≥ 28 pt (Dynamic Type). Erkannte Zeiten („15 Minuten“, „5–7 Min.“ → obere Grenze) als Timer-Knopf „⏲ Reis · 15:00“. Unten Chips „Zutaten in diesem Schritt“ (Zutaten, deren Name im Text vorkommt).
- **Timer-Leiste** über den Knöpfen: je Timer eine Glas-Kapsel (iOS 26 Liquid Glass, sonst Material) mit Ring, Name, Restzeit, Pause/Weiter, „+1 min“, Stop. Ablauf: Ton + Haptik + oranges Banner „Reis ist fertig!“; im Hintergrund lokale Mitteilung. Erste Timer-Nutzung → Erklär-Sheet „Nichts verpassen“ vor der iOS-Abfrage.
- **Sprachsteuerung**: Glas-Pille „🎙 hört zu …“ mit Pegel unter dem Kopf; erkannter Befehl blinkt kurz („weiter“). Befehle: weiter, zurück, wiederholen (liest vor), Timer starten, Timer N Minuten, wie viel {Zutat}, Zutaten. Fehlende Erlaubnis → Hinweis in der Pille.
- Letzte Seite **„Fertig! 🎉“** mit Tellerbild und Konfetti (aus bei „Bewegung reduzieren“), Knopf „Bewerten ★“ → schließt und öffnet S8 (Bewertung + Vorrat abziehen).

## Phase 9 – Import & Kühlschrank-Foto (S20–S25)

### S20 Teilen-Erweiterung „Essenapp“ (Feature 5, System-Sheet aus dem Teilen-Menü)
- Eigenes kleines Theme mit den Werten aus `Theme.swift` (die Erweiterung kann das App-Modul nicht importieren, E58). Kopf: 🍲 im `accentSoft`-Kreis, „Essenapp“, rechts runder ✕. Buttons unten fest.
- Erkennt den ersten http(s)-Link aus URL- oder Text-Anhang; Text geht als `text` mit an `POST /import`. Kein Link → Seite „Rezept aus Link“ (wie S22) mit Feld.
- **Koppeln** (kein Token im Schlüsselbund der Erweiterung): Titel „Mit Essenapp koppeln“, Satz „Einmalig: In der App Einstellungen › Teilen aus Instagram …“, Feld „SERVER-ADRESSE“ (vorbelegt mit der zuletzt benutzten Adresse, sonst `http://`), 6 große Ziffern-Kästen (64 pt, aktiver Kasten mit `accent`-Rand, Zahlentastatur, Code aus Einfügen), bei 6 Ziffern automatisch `POST /pair`. Fehler rot unter den Kästen: 404 „Code ungültig – bitte in der App einen neuen Code erzeugen.“, 410 „Code abgelaufen/schon benutzt – …“, 429 „Zu viele Fehlversuche – bitte in 10 Minuten erneut versuchen.“, Netz „Server nicht erreichbar – Adresse und WLAN prüfen.“ `PrimaryButton` „Koppeln“. Token + Adresse → Schlüsselbund der Erweiterung (keine geteilte Gruppe). 401 beim Import → Token weg, zurück zu „Koppeln“ mit „Die Kopplung wurde widerrufen – bitte neu koppeln.“
- **Import:** drehender Teller (🍲 im weißen Kreis), „Rezept wird gelesen …“, Domain, Karte mit Schritten „Link öffnen“ → „Rezept wird gelesen …“ → „Zutaten & Mengen ordnen“ → „Foto speichern“ (alle 2,5 s ein Häkchen, Haptik, am Ende alle). `SecondaryButton` „Abbrechen“.
- **Ergebnis:** rundes Rezeptfoto (150 pt), Titel, „Instagram · @autor“, Chips „N Zutaten“ / „M Schritte“, grüne Pille „In Meine Rezepte gespeichert“ (200: „War schon in Meine Rezepte“) – das Backend speichert beim Import, ein eigener Speichern-Knopf entfällt. Geschätzte Mengen → gelbe Box „3 Mengen geschätzt“ + Namen + „Bitte beim Kochen prüfen“. Hinweis „Du findest es in Essenapp › Rezepte › Meine Rezepte (Filter „Importiert“).“ (Share-Erweiterungen können die App nicht öffnen.) Knöpfe: `SecondaryButton` „Diese Woche einplanen“ → Slot-Liste wie S19 (`GET /plans/current`, Tippen → `…/replace`, danach Pille „Eingeplant: Di · Mittag“), `PrimaryButton` „Fertig“.
- **Kein Rezept** (422): 🤷 „Kein Rezept gefunden“ + „In der Beschreibung steht kein Rezept – manche Reels zeigen es nur im Video …“, „Schließen“. **Fehler** (502/Netz): 📡 „Das hat nicht geklappt“ + Meldung, „Erneut versuchen“ / „Schließen“.

### S21 Teilen aus Instagram (Push-Screen aus S13)
- `DisplayHeader` „Teilen aus / Instagram“, Satz darunter.
- Karte „So geht's“: 4 nummerierte Schritte (Code erzeugen · in Instagram Teilen › „Teilen über …“ › Essenapp, ggf. unter „Mehr“ einschalten · beim ersten Mal Adresse + Code · Rezept landet in Meine Rezepte).
- Karte „Kopplungscode“: ohne Code `PrimaryButton` „Code erzeugen“ (`POST /me/pairing-code`); mit Code große Ziffern „482 913“ (46 pt, gerundet), „gültig noch 9:12 · nur einmal benutzbar“ (läuft sekündlich, danach „Code abgelaufen“ rot), `SecondaryButton` „Neuen Code erzeugen“. Darunter Zeile „Server-Adresse“ (Monospace) mit „Kopieren“ – die Erweiterung kennt die Adresse der App nicht (E48).
- Karte „Gekoppelte Geräte“ (`GET /me/tokens`): Zeilen mit Icon, Name, „gekoppelt am 2.11.2026“, „Widerrufen“ (rot) → Rückfrage „Kopplung widerrufen?“ → `DELETE /me/tokens/{id}`, Toast „Kopplung widerrufen“. Leer: „Noch kein Gerät gekoppelt.“ Laden → Skeleton, Fehler → `ErrorState`. Lädt neu beim Zurückkehren in die App und per Ziehen.

### S22 Link einfügen (Sheet aus S12)
- Gleiche Oberfläche wie S20 (geteiltes Modul), aber mit der Anmeldung der App, ohne Koppeln: Titel „Rezept aus Link“, Satz, rundes Feld + System-`PasteButton` (kein Einfügen-Dialog), `PrimaryButton` „Importieren“ (erst aktiv bei gültigem http(s)-Link). Dann Import- und Ergebnis-Seite wie S20; im Ergebnis `PrimaryButton` „Rezept ansehen“ → S3. Kein Rezept → zusätzlich „Anderen Link“.

### S23 Kühlschrank scannen (Sheet, Feature 69)
- Kopf „Kühlschrank scannen / Fotos → Vorrat & Kochideen“, runder ✕.
- `PillSegment` „Kühlschrank · Vorrat · Gefrierfach“ (= `mode`).
- Sucher-Fläche (340 pt, Radius Karte): letztes Foto bzw. Modus-Emoji + „Fotografiere jedes Fach einzeln – bis zu 5 Fotos.“, Eckrahmen in `accent`.
- Thumbnail-Leiste (56 pt) mit ✕ zum Löschen je Foto, rechts „2 / 5“.
- Darunter: weißer Pill „Aus Fotos“ (Fotomediathek, Rest bis 5), mittig schwarzer runder Auslöser 76 pt (System-Kamera, nach jedem Foto zurück; ohne Kamera Toast „Keine Kamera – wähle Fotos aus“).
- Fester `PrimaryButton` „Fertig · 2 Fotos“ (erst ab 1 Foto). Fotos werden auf 1024 px verkleinert (JPEG).
- **Upload:** Ring mit Prozent (Sende-Fortschritt), dann Modus-Emoji; Karte mit Schritten „Fotos hochladen“ → „Lebensmittel erkennen“ → „Mengen & Haltbarkeit schätzen“. Fehler: `ErrorState` (422 „Die Fotos konnten nicht gelesen werden …“, 502 „Die Erkennung ist gerade nicht erreichbar …“) + `SecondaryButton` „Andere Fotos“.

### S24 Prüf-Bildschirm (im Sheet S23)
- Kopf „N erkannt / Unsichere sind abgewählt – prüfen, Mengen anpassen.“, rechts schwarze Pille „🧺 Vorrat N“ (Ziel der Animation).
- Zeilen (weiße Kachel, unsichere gelb getönt): Häkchen-Kreis (`accent`; „niedrig“ vorab aus), Kategorie-Emoji, Name (editierbar), Sicherheit als Chip („sicher“ grün, „ziemlich sicher“ grau, „unsicher“ gelb); darunter umbrechend: Menge (Zahlentastatur), Einheit-Menü (g/ml/Stück/ohne), Ort-Menü (🧊 Kühlschrank/🥫 Vorrat/❄️ Gefrierfach), MHD als Datum mit ✕ bzw. „MHD +“.
- „+ Fehlt etwas?“ fügt eine leere Zeile an. Nichts erkannt → `EmptyState` „Nichts erkannt“ + „Neue Fotos“.
- Fester `PrimaryButton` „N in den Vorrat übernehmen“ → `POST /pantry/bulk` (`source: scan`); danach fliegen die gewählten Karten nacheinander in die Vorrats-Pille (Haptik), Toast „N Sachen im Vorrat“, weiter zu S25. Den Ort zeigt/ändert nur der Prüf-Bildschirm, das Backend speichert ihn nicht.

### S25 Was koche ich jetzt? (im Sheet S23)
- Kopf „Was koche ich jetzt? / Aus deinem Vorrat · höchstens 30 min“, runder ✕.
- Laden (`POST /pantry/cook-now`, bis ~15 s): drehender Teller + Schritte „Vorrat ansehen“, „Ideen sammeln“, „Fehlende Zutaten prüfen“.
- Bis zu 3 Karten: Tellerfoto, Titel, „25 min · 2 Portionen“, „Alles da ✓“ oder Box „Fehlt: Sahne (100 ml)“ mit „Zur Liste“ (→ Haushaltsliste, wird „Auf der Liste“); `PrimaryButton` in `accent` „🔥 Heute kochen“ → ersetzt das heutige Gericht (gleiche Mahlzeit bevorzugt, nicht fixierte zuerst) über `…/replace`, Toast „Heute: <Titel>“; heute kein Gericht im Plan → S19. Karte antippen → S3.
- Vorrat leer (422) → `EmptyState` „Vorrat ist leer“; keine Idee → „Keine passende Idee“; Fehler → `ErrorState`.
