# Screens

Status: **Entwurf v2** – offene Punkte im autonomen Modus entschieden (E17–E21, siehe Playbook). Mockups: `mockups/kern-screens-v1.html`, `mockups/weitere-screens-v1.html`.

## Navigation

Tab-Bar (Komponente `TabBar`):

| Position | Tab | Inhalt |
|---|---|---|
| 1 | **Start** | Überblick der Woche |
| 2 | **Angebote** | Angebote + Merkliste (Lieblingsprodukte); Zahl-Badge (`deal`) = Merklisten-Einträge mit Treffer diese Woche (27) |
| Mitte | **Schwarzer Button** | Öffnet **Schnell-Aktionen** (E14): Wochenplan erstellen, Barcode scannen, Zur Einkaufsliste, Rezept anlegen (→ S17, auch `essenapp://recipe/new`), dazu volle Breite „📸 Kühlschrank scannen“ (→ S23, Feature 69). „🔎 Barcode scannen“ öffnet den Scanner aus S10 (Phase 12) |
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
- Phase 11: direkt unter dem `SearchField` Start-Banner (Feature 25, `GET /specials`, nur wenn `banner`): Emoji im `accentSoft`-Quadrat, „Weihnachten in 12 Tagen – Menü planen?“, darunter „Festtagsmenü im Plan-Generator“ (`micro`), Chevron → S7 mit dieser Special-Vorlage. Unter der Heute-Karte `SecondaryButton` „😮‍💨 Keine Lust“ → S27 (Feature 16).

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
- Phase 11:
  - Kopf unter „essen mit“: Chip „✓ Abwechslung“ (`success` getönt) bzw. „⚠ 2× Pasta“ (`warning` getönt, erster Verstoß aus `variety.issues`; mehrere → „+1 ▾“, Antippen zeigt alle als Menü) (Feature 12).
  - Unter den drei Kennzahl-Kacheln Karte „Reste“ (Feature 19, nur wenn `leftovers.planned > 0` oder etwas übrig): ♻︎ im `successSoft`-Quadrat, „Reste: 3 verplant, 1 übrig (Sahne 100 ml)“, darunter je Rest der Vorschlag („Sahne: Bis Do verbrauchen …“, `micro`).
  - Gerichte eines Tages in der Reihenfolge Frühstück · Lunchbox · Mittag · Snack · Vorspeise · Abend · Dessert. Lunchbox-Gerichte (Feature 24): Überschrift „🥡 LUNCHBOX“, Badge „🥡 Lunchbox · Jona“ (Esser).
  - Unter jeder Gericht-Zeile Badges: „♻︎ Rest von Mo“ (je Herkunftstag), Pill „👤+ Gäste“ bzw. „+4 Gäste“ (`accentSoft`) → S28 (Feature 15).
  - Ist der gewählte Tag heute: unter den Gerichten `SecondaryButton` „😮‍💨 Keine Lust“ → S27.

### S3 Rezeptdetail
- Großes freigestelltes Tellerbild oben (wie Referenz 02), Zurück-Button, Merken (Herz)
- Name (`title`), darunter Portion in g, Preis pro Portion, Zeit
- `NutrientTile`s: kcal, Protein, KH, Fett
- `ShareBloom`: Anteile der Zutaten am Gewicht (E19)
- Zutatenliste: Bild/Icon, Name, Menge; bei Angebot `DealBadge` + `StoreChip`; Vorrat-Hinweis
- Portionen-Stepper
- Zubereitungsschritte nummeriert
- Unten fest: `PrimaryButton` „Gekocht – bewerten“
- Darüber fest: `PrimaryButton` in `accent` „▶︎ Kochen starten“ → S18. Oben rechts runder Teilen-Knopf → Menü „Als Bild teilen“ (Bildkarte, Feature 10), „Als Link teilen“ (Feature 56 → S36)
- Phase 9 (Features 2 + 3), gilt für Plan-Gerichte und gespeicherte Rezepte (aus S12):
  - Kopfzeile: Zurück · Herz (Favorit des Haushalts, `symbolEffect(.bounce)` + Haptik) · bei eigenen/importierten Rezepten runder „…“-Knopf (Bearbeiten → S17, Löschen → Rückfrage „Rezept löschen?“; steht es im Plan, bleibt es dort) · Teilen.
  - Unter dem Namen: Sterne-Durchschnitt + „4,5 · 2 Bewertungen“ (nur wenn bewertet).
  - Gespeichertes Rezept: `SecondaryButton` „Diese Woche einplanen“ → S19. Preis = Live-Kosten aus den aktuellen Angeboten, Angebotszutaten mit `DealBadge` + `StoreChip`.
  - „Für:“-Karte, darunter 4 `NutrientTile` (kcal, Protein, KH, Fett) pro Portion der gewählten Person (Portion × Faktor aus dem kcal-Ziel). Werte fehlen noch → 4 Schimmer-Kacheln, einmal nach ~3 s neu laden.
  - Karte „Zusammensetzung“ mit `ShareBloom`: Tellerfoto in der Mitte, je Zutat ein Blütenblatt mit Verlauf (Länge nach Anteil), außen Prozent + Name; Anteile < 3 % → „Sonstiges“ (grau); ganze Prozent, Summe 100. Blätter wachsen nacheinander auf (bei „Bewegung reduzieren“ ohne Versatz). Fehlt die Zusammensetzung noch → Schimmer.
  - Zutatenmengen im Plan = Rezeptmenge × `scale`; „Deine Portion“ = Menge × scale × Faktor / portions_total.
  - Unten Karte „Bewertungen“: Name, Sterne, Datum, „Wieder kochen: Bald/Irgendwann/Nie“ (Nie rot), Notiz.
- Phase 10/11 (Features 7, 19): Zutat lange drücken → Menü „Ersatz finden“ → S26 (auch per VoiceOver-Aktion). Zutaten, die aus einem Rest stammen, tragen den Badge „♻︎ Rest von Mo“. Nach dem Ersetzen zeigt S3 das geänderte Rezept (Plan-Gerichte immer im aktuellen Plan-Stand).
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
- Phase 12:
  - Unter dem Segment Pillen „Diese Woche“ · „Nächste Woche“ (`FilterChip`, mit Anzahl; zweite mit `DealBadge` „neu“, sobald `GET /offers?week=next` etwas liefert, Feature 30). Nächste Woche: Kopf „N ab nächster Woche“, leer → `EmptyState` 👀 „Noch keine Prospekte für nächste Woche“ + „Die meisten Läden zeigen sie ab Donnerstag oder Freitag …“. Im Angebotsdetail statt „noch N Tage“ der Chip „ab 9.11.“; „Zur Einkaufsliste“ legt Vorschau-Angebote in die Gruppe „Nächste Woche“.
  - Zweite Chip-Reihe unter den Läden: „✓ Nur echte Angebote“ (blendet `kein_echtes` aus, 28), „Bio“, „🌱 Vegan“, „Nutri A/B“ (49), „🎁 Bonus-Aktionen“ mit Anzahl (39, `bonus_cents`), kombinierbar, lokal gefiltert. Hat noch kein Angebot ein Urteil: Hinweis „Noch zu wenig Preisdaten (ab 3 Wochen) – bis dahin zeigt der Filter alle Angebote.“
  - `OfferCard`: oben rechts auf dem Bild `VerdictBadge` (klein, gleiche Texte/Farben wie S9, bei `zu_wenig_daten` keiner), unten links `LabelBadges` (Nutri-Score in Originalfarbe, 🌱 vegan, „Bio“). Lieber kein Badge als ein falsches.
  - Kategorie Drogerie: oben Karte „📅 Monatsaktionen“ (dm/Rossmann, `monthly`, horizontale `MiniOffer`s), leer → „Gerade keine Monatsaktion bei dm oder Rossmann.“; das Raster zeigt die übrigen (59). Demo: `nextweek`.

### S5 Einkauf
- Übersicht: `ListCard` pro Laden (Pastellton aus `listTints`, E18) mit Anzahl offener Artikel und Avataren
- Detail: Kopf mit Laden, Summe, Ersparnis; `ChecklistRow`s nach Kategorie gruppiert; abgehakte nach unten
- Artikel hinzufügen (Freitext), Mitglieder einladen (+)
- Offline abhakbar (Feature 66): ohne Netz oder Server oben Glas-Banner (Liquid Glass, sonst Material, Symbol `wifi.slash`) „Offline – Änderungen werden später übertragen“ über allen Screens. Abhaken, Artikel hinzufügen/entfernen (Haushaltsliste und einmalige Listen) und Vorrat (anlegen, Menge, löschen) wirken sofort und warten in einer Warteschlange; beim nächsten Netz der Reihe nach gesendet, dann neu geladen. Konflikte: letzter Stand gewinnt pro Feld, auf dem Server abgehakte Artikel bleiben abgehakt. Angezeigt wird der zuletzt geladene Stand (Cache) von Haushalt, Plan, Listen, Angeboten, Vorrat, Rezepten; Bilder aus dem URLCache, wenn schon gesehen. Demo: `offline`.
- Sprach-Eingabe (Feature 45): im Feld „Artikel hinzufügen …“ (Haushaltsliste und einmalige Listen) rechts ein 🎙-Knopf (44 pt, `text2`). Tippen → Glas-Overlay (Liquid Glass, sonst Material; Radius Sheet) über `scrim`, unten über der Tab-Leiste: Kopf `VoicePill` „🎙 hört zu …“ mit Pegel (wie Kochmodus; nach Zeitlimit/Stopp stattdessen Glas-Pill „🎙 Weiter sprechen“, hängt an den bisherigen Text an) + runder ✕; darunter der erkannte Text in Anführungszeichen (leer: „Sag z. B. „zwei Liter Milch, Eier und ein Brot““, `text2`); dann Vorschau-Chips (`card`-Pills, umbrechend) „2 l Milch“, bei Angebot mit Laden „Rewe“ in `text2`, ✕ – Antippen entfernt den Chip; unten `PrimaryButton` „3 hinzufügen“ (ohne Chips „Hinzufügen“, halb transparent, inaktiv). Erkennung de-DE auf dem Gerät, Zerlegung an Komma/Punkt/„und“/„sowie“/„plus“, Mengen + Einheiten per Regeln (l, ml, g, kg, Stück, Packung, Flasche, Dose, Glas, Becher, Bund, Kiste; Zahl ohne Einheit = Stück). Laden-Zuordnung: günstigstes passendes Angebot (Kette + Angebot am Artikel). Hinzufügen → Toast „3 Sachen hinzugefügt“, offline über die Warteschlange. Fehlende Erlaubnis → Hinweis in der Pille. Demo: `voiceadd`.

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
- Phase 11 (`GET /plans/generator` + `GET /specials` beim Öffnen; ohne Antwort fehlen die Karten):
  - Untertitel beginnt mit „KW 46 · “ (Planungswoche, ab Freitag die nächste).
  - Karte „🏷️ Diese Woche im Angebot“ (Feature 17): Satz „Diese Woche im Angebot: Hähnchenbrustfilet, Lachsfilet, Feta“, darunter die Top-3 als kleine Angebotskarten mit `DealBadge`.
  - Karte „✨ Special“ (Feature 25, nur wenn Vorlagen passen): Chips „Ohne“ + „🎄 Festtagsmenü“, „🍪 Plätzchen-Back-Plan“, „🔥 Grillparty“ (aktiver Chip `accent`), darunter Anlass + Inhalt („Weihnachten · Vorspeise, Hauptgang und Dessert am Tag des Anlasses“). Aus dem Start-Banner vorgewählt. → `PlanOptions.special`.
  - Karte „👥 Gäste“ (Feature 15) nach „Wünsche“: Tagespillen Mo–So (nicht geplante Tage halb transparent, gewählter Tag `action`), Badge „+4“ (`accent`) oben rechts an Tagen mit Gästen; darunter je gewählter Mahlzeit Zeile „Abend · +4 Gäste“ mit Stepper 0–20. Ab 1 Gast: Schalter „Gäste-Budget extra“ → Betrag groß + Regler 5–100 € (5er), aus → „Ohne Extra-Budget zahlen die Gäste aus dem Wochenbudget.“ → `PlanOptions.guests` / `guest_budget_cents`.
  - Mahlzeiten-Chips enthalten „Snack“ (Feature 23c; nicht im Onboarding).

### S8 Bewertung (Sheet, halbe Höhe)
- Kleines Tellerfoto + Gericht-Name.
- „Wie war's?“ + `RatingStars` (groß).
- „Wieder kochen?“ Segment: Bald / Irgendwann / Nie. „Nie“ = Rezept wird nicht mehr vorgeschlagen.
- Speichern → `POST /recipes/{id}/rate` (wer und wann setzt der Server); Fehler → Toast, Sheet bleibt offen.
- Optionale Notiz (einzeilig, wächst).
- Nach „Vom Vorrat abgezogen“ („Weiter“) bzw. direkt: S30 „Reste in den Vorrat?“, wenn `GET /plans/current/entries/{id}/leftovers` etwas liefert (Feature 19).
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
- Phase 12 (Feature 31): direkt unter dem Preis Karte „💡 Vorratstipp“ (`GET /offers/{id}/stockup`, nur wenn ein Tipp kommt, sonst nichts): „3 Packungen reichen ~6 Wochen, sparst 4,20 €“ (ohne Verbrauchsdaten „3 Packungen (vorsichtig geschätzt, noch ohne Verbrauchsdaten) …“), `PrimaryButton` „3× auf die Liste“ → `POST /lists/{id}/items {amount, offer_id, chain, source: stockup}` (offline: Warteschlange), danach „Auf der Liste ✓“. Demo: `offerstock`.
- Phase 12 (Feature 49): im dunklen Kopf unter der Marke `LabelBadges`; unter den Fakten Karte „Bio, vegan, Nutri-Score“ mit je Zeile Badge + Erklärung („Nutri-Score A – Nährwert-Ampel von A (günstig) bis E …“, „Vegan – ohne tierische Zutaten“, „Bio – laut Bio-Siegel bzw. „Bio“ im Prospekt“), „Quelle: Prospekttext · Open Food Facts (ODbL). Wir zeigen nur sichere Treffer …“ und bei `off_code` Link „Bei Open Food Facts ansehen“.
- Phase 12: Herz = Merkliste über `POST /watch {offer_id}` bzw. `DELETE /watch/{id}` (gefüllt, wenn ein Eintrag das Angebot beobachtet).
- Preisverlauf: Beschriftung „Normalpreis 5,99 €“ rechts über der gestrichelten Linie in einer `card`-Kapsel mit Haarlinie (liegt nicht in den Linien).
- Phase 9 (Feature 2): Karte „Nährwerte“ unter den Fakten (`GET /offers/{id}/nutrition`): `PillSegment` „pro 100 g | pro Packung (400 g)“ (nur wenn `per_pack`), 4 `NutrientTile` (kcal, Protein, KH, Fett), darunter „Quelle: USDA FoodData Central · „<food>““. `pending` → Schimmer-Kacheln + „Nährwerte werden zugeordnet …“, nach 3/6/12/24 s neu fragen. `none` → Karte fehlt.

### S10 Merkliste (Tab „Angebote“, Segment „Merkliste“, Phase 12: Server `/watch`, Features 27/40/58)
- Kopf wie S4 („Merkliste / N beobachtet“), Segment auf „Merkliste · N“.
- Zuerst Abschnitt **„🔥 Diese Woche günstig“** (Einträge mit `hits`): Zeilen (Kachel) mit Produktbild auf Kategorie-Tönung, Name, „1,79 € bei dm“ + `DealBadge` „−25 %“, Chevron → S9 des günstigsten Treffers.
- Dann **„👀 Beobachtet“** (Produkte ohne Treffer): Name · Marke, darunter „Alarm unter 2,00 € · hält ca. 6 Wochen · leer ca. 1.12.“ und „zuletzt im Angebot: KW 44 bei Lidl (1,99 €)“ (`last_offer_week/chain/price_cents`; fehlt alles → „gerade nicht im Angebot“). Drogerie-Coupon (59) als Badge „🎟 −20 %“ (antippen → Kasse S31b). Antippen → Bearbeiten-Sheet.
- Dann **„🔔 Preisalarme“** (Zutaten, 40) mit Knopf „+ Zutat“ rechts: „Butter unter 1,49 €“ / „Lachsfilet unter 15,00 €/kg“, darunter „greift: 3,49 € bei Lidl – Lachsfilet“ (`success`) bzw. „wartet auf ein passendes Angebot“. Leer: Hinweis „Z. B. „Butter unter 1,49 €“ oder „Hähnchenbrust unter 7 €/kg“ – auch per langem Druck auf eine Rezept-Zutat.“
- Jede Zeile lange drücken → „Bearbeiten“, „Entfernen“.
- Unten zwei Buttons nebeneinander: `SecondaryButton` „Suchen“ und `PrimaryButton` „Barcode scannen“.
- **Bearbeiten-Sheet** (groß, runder ✕): Titel = Name, Untertitel Marke bzw. „Für eine Zutat – jede passende Marke und Packung“. Karte „🔔 Wunschpreis“: „unter [__] €“ (Zahlentastatur), Segment „Packung · pro kg · pro l · pro Stück“ (Grundpreis-Alarm gilt für jede Packungsgröße). Karte „🏪 Läden“: Chips „Alle“ + gewählte Ketten (`accent`). Nur Produkte: Karte „🔁 Verbrauchsrhythmus“ (Schalter; „Hält ca. 6 Wochen“ + Stepper 1–52, „Vorschlag: 6 Wochen“, Schalter „Zuletzt gekauft“ + Datum, Hinweis „Wird automatisch gesetzt, wenn du es auf der Liste abhakst …“, 58). `PrimaryButton` „Speichern“ → `PATCH /watch/{id}`, „Entfernen“ rot. Ohne Eintrag („+ Zutat“, Rezept-Zutat lange drücken → „Preisalarm“): Titel „Preisalarm“, Namensfeld, Button „Preisalarm anlegen“ (erst mit Name + Preis aktiv) → `POST /watch {kind: zutat}`.
- **Suchen-Sheet:** „Produkt merken“, `SearchField`; ab 2 Buchstaben `PrimaryButton` „„Shampoo“ beobachten“ (`POST /watch {label}`) und „Diese Woche im Angebot“: `OfferRow`s mit Herz rechts.
- **Barcode-Scan** (Vollbild, VisionKit `DataScannerViewController`, EAN-8/13, UPC-E): schwarzer Grund, Kamera, Orange-Ecken-Rahmen (`CornerFrame`, `accent`, 270 × 170), oben „Barcode scannen“ + runder ✕, unten Glas-Pille „Strichcode in den Rahmen halten“. Ohne Kamera-Erlaubnis „Kamera ist nicht erlaubt.“ + „In iOS-Einstellungen öffnen“; Gerät ohne Unterstützung „Dieses iPhone kann keine Barcodes scannen.“ Treffer (Haptik) → Sheet „Auf Merkliste?“ (`GET /products/ean/{ean}`): Laden → Schimmer „Suche in Open Food Facts …“; gefunden → Bild, Name, Marke, Nutri-Score, „EAN …“, „Daten: Open Food Facts (ODbL)“; unbekannt bzw. 502 → Satz + Namensfeld. `PrimaryButton` „Auf die Merkliste“ (`POST /watch {label, brand, ean, image_url}`, schließt den Scanner), `SecondaryButton` „Weiter scannen“. Auch aus der Schnell-Aktion „Barcode scannen“.
- Laden → 3 Skeleton-Zeilen; Fehler → `ErrorState`; leer → `EmptyState` 🤍 „Noch nichts gemerkt“ + „Merk dir Lieblingsprodukte – wir sagen Bescheid, wenn sie im Angebot sind.“
- Push „🧴 Dein Shampoo ist bei dm im Angebot …“ öffnet `essenapp://offer/<id>` → S9. Demo: `watch`, `scanner`.

### Phase 12 – Spar-Karten (Start S1, Einkauf S5, Generator S7, Einstellungen S13, Rezept S3)
- **S1 Start** unter der Budget-Karte, in dieser Reihenfolge (jede fehlt, wenn es nichts zu zeigen gibt):
  - **Budget-Rest (43)** (`GET /plans/current/budget`): `rest` → Karte „💶 Noch 6,80 € übrig – wie wär's mit …“, darunter 3 Ideen (`POST /plans/current/budget/ideas`, einmal je Plan-Stand; Laden → 3 Skeleton-Zeilen + „Ideen werden gesucht …“, Fehler → Satz + „Erneut versuchen“, leer → „Gerade keine Idee, die ins Restbudget passt.“): Zeile mit Emoji im `accentSoft`-Quadrat (🍰 Dessert, 🥨 Snack, 🥫 Vorrat), Titel, Art, rechts Kosten + „einplanen“ bzw. „auf die Liste“. Dessert/Snack → Rückfrage „Wann einplanen?“ (Tage des Haushalts) → `POST /plans/current/entries`, Toast „Eingeplant: Mi · Dessert“; Vorrat → wie „n× auf die Liste“. Erledigte Zeile „✓ erledigt“. `over` → Karte auf `warning`-Tönung „⚠️ 3,20 € über Budget – günstigere Alternative für Do?“, „„Lachs-Bowl“ kostet 6,20 € – neu würfeln mit höchstens 3,00 €.“, `PrimaryButton` „Günstiger würfeln“ (`…/reroll {max_cost_cents}`, Spinner). `ok` → keine Karte. Demo: `savings`, `budgetover`.
  - **„👀 Nächste Woche günstiger“ (30)** (`GET /offers/next-week-cheaper`, max. 3): Zeile mit Laden-Logo und Satz „**Hähnchenbrust** nächste Woche **−30 %** bei Lidl (3,49 € statt 4,99 € bei Rewe) – Kauf verschieben?“, darunter `accentSoft`-Pille „Auf nächste Woche schieben“ → `POST /items/{id}/next-week {offer_id}` (offline: Warteschlange) bzw. Merklisten-Treffer `POST /lists/{id}/items {next_week: true}`; Toast „„Hähnchenbrust“ → Nächste Woche“, Zeile verschwindet.
  - **„💡 Vorrat anlegen lohnt sich“ (31)** (`GET /stockup?limit=3`): Zeilen mit Produktbild, Titel, Tipp-Text, rechts schwarze Pille „6×“ (→ „✓“, `success`); Zeile antippen → S9.
- **S5 Einkauf:**
  - Unter „Diese Woche gespart“ Karte **„🏆 Am günstigsten“ (42)** (`GET /lists/{id}/stores`, neu bei jeder Änderung offener Artikel): bis zu zwei auswählbare Zeilen (Kreis-Haken `accent`, Logos, „alles bei Lidl“ · „1,2 km Weg“, bzw. „Rewe + Lidl“ · „2,30 € gespart · +1 Laden · +1,2 km“ in `success`, rechts Summe); vorgewählt die günstigste. „1 Artikel ohne bekannten Preis zählt nicht mit.“ `PrimaryButton` „So aufteilen“ → `POST /lists/{id}/assign {chains}`, Toast „Liste neu aufgeteilt“. Laden → Skeleton; Fehler → Zeile „Laden-Empfehlung gerade nicht verfügbar.“ + „Erneut versuchen“; weniger als 2 Möglichkeiten oder nichts offen → keine Karte.
  - Nach den Laden-Karten Abschnitt **„📅 Nächste Woche“** (30, Artikel mit `next_week`): `ItemRow`s, lange drücken → „Doch diese Woche“ (`PATCH /items/{id} {next_week: false}`, offline Warteschlange), „Entfernen“. Diese Artikel zählen nicht bei den Laden-Karten, der Laden-Liste und der Standort-Erinnerung.
  - `ItemRow`: Badge „Vorratskauf“ (`ok`, source `stockup`, 31) bzw. „bald leer“ (`soft`, source `rhythm`, 58).
- **S7 Plan-Generator:** direkt unter dem Untertitel Karte **„🛒 Woche & Läden“**: Schalter „Plan für nächste Woche“ (30; ohne Vorschau-Angebote inaktiv mit „Noch keine Prospekte für nächste Woche – meist ab Donnerstag oder Freitag.“, sonst „Nutzt die Vorschau-Angebote (N) …“; der Untertitel zeigt dann die KW des nächsten Montags), Trennlinie, Schalter „Nur ein Laden“ (41) → Reihe der Logos der gewählten Läden (44 pt, gewählt mit `accent`-Rand und größer, Rest halb transparent) + „Einkauf komplett bei Lidl – Zutaten ohne Angebot zum Normalpreis von Lidl.“ → `PlanOptions.next_week` / `single_store`. Demo: `singlestore`.
- **S13 Einstellungen › Einkaufen:** Zeile „Vorratsplatz“ („begrenzt Vorratskauf-Tipps“) mit Menü „Klein (3 Packungen) · Mittel (6) · Groß (12)“ → `PATCH /household {storage_space}` (31).
- **S3 Rezeptdetail:** Zutat lange drücken → zusätzlich „Preisalarm“ (auch VoiceOver-Aktion) → Bearbeiten-Sheet aus S10 mit dem Zutatnamen (40).

### Erklär-Sheets („Nichts verpassen“, Standort, Koch-Timer)
- Gleiche Komponente `PushPermissionSheet`: Höhe passt sich dem Inhalt an (etwa halbe Höhe), Titel und Text mehrzeilig, nie abgeschnitten; bei großer Schrift scrollbar.

### Offline-Banner (66)
- Das Glas-Banner schiebt den Inhalt nach unten (Safe-Area-Einschub oben) und überdeckt keine Bedienelemente (z. B. „Liste | Vorrat“).

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
  - **Mein Profil** (ganz oben): Emoji-Avatar, Name, Ziel → S15; darunter Zeile „Erfolge“ (🏅, „Sparen & Gesundheit“) → S34
  - Phase 13: in **Einkaufen** Zeile „Ausgaben“ („Monats-Dashboard“) → S32
  - **Haushalt:** Personen, Ernährung, Allergien, Mag ich nicht
  - **Einkaufen:** Ort (PLZ), Läden & Filialen, Budget Lebensmittel, Budget Drogerie
  - **Planung:** Mahlzeiten, Tage, Küchen, Nährwertziel, Max. Kochzeit
  - Phase 11: in der Gruppe **Präferenzen** zusätzlich Zeile „Abwechslung“ („max. 1× Pasta · 2 Veggie-Tage“) und – nach einer Trennlinie – „Frühstück & Snacks“ („jede Woche auf die Liste“) → S29.
  - **Benachrichtigungen** (Push über Apple/APNs, kein ntfy; Test-Push: 422 → Toast „Erst Mitteilungen erlauben“, 502 → „Apple hat abgelehnt“; die Wochenplan-Erinnerung hat die Aktionen „Plan erstellen“ → S7 und „Später“): Status der iOS-Erlaubnis (abgelehnt → „In iOS-Einstellungen öffnen“), „Test-Push senden“, Push an/aus, Wochenplan-Erinnerung (an/aus, Wochentag, Uhrzeit), Ruhezeit (an/aus, Von/Bis), Angebotsalarme an/aus. Vor der iOS-Abfrage einmal ein Erklär-Sheet „Nichts verpassen“ (nach dem Onboarding bzw. beim ersten Öffnen der Einstellungen). Antippen einer Mitteilung öffnet `essenapp://start|generator|offer/<id>|recipe/<id>|list/<kette>`.
    - Phase 11 (Feature 24): unter der Ruhezeit Schalter „Lunchbox-Erinnerung am Vorabend“ (Standard 20:00) + Uhrzeit, Hinweis „🥡 „Lunchbox für morgen vorbereiten“ – nur am Abend vor deinen Lunchbox-Tagen (Mein Profil).“ (`PATCH /me/push/settings {lunchbox_push}`, aus = null). Die Mitteilung öffnet `essenapp://recipe/<id>` → Tab Rezepte, S3 (Plan-Gericht mit Mengen des Slots, sonst gespeichertes Rezept).
    - Karte **Standort-Erinnerung** (Feature 36) unter den Push-Einstellungen: Schalter „Erinnern, wenn ich in einem Laden bin“, darunter (`micro`, `text2`) „Bis zu 20 deiner Läden (nächste zuerst), 8–21 Uhr, höchstens einmal pro Laden und Tag – nur wenn dort etwas auf der Liste steht oder ein Coupon gilt.“ Eingeschaltet: „N Läden überwacht“ mit 📍-Symbol (`success`); ohne Laden mit Standort „Noch kein Laden mit Standort – wähle deine Läden auf der Karte (Einstellungen › Läden & Filialen).“; Standort nicht „Immer“ → Hinweis in `danger` („Standort steht auf „Beim Verwenden“ – für Erinnerungen „Immer“ wählen.“ bzw. „Standort ist in iOS nicht erlaubt.“) + `SecondaryButton` „In iOS-Einstellungen öffnen“.
    - Einschalten ohne Erlaubnis „Immer“ → Erklär-Sheet (wie „Nichts verpassen“, halbe Höhe): 📍 „Erinnerung im Laden“, „Bist du bei einem deiner Läden, sagen wir dir, was dort auf der Liste steht. Dafür braucht die App den Standort „Immer“ – er bleibt auf deinem iPhone.“, `PrimaryButton` „Standort erlauben“ (iOS-Abfrage „Immer“, danach ggf. Mitteilungen; schon abgelehnt → iOS-Einstellungen), `SecondaryButton` „Später“. Demo: `storeask`.
    - Mitteilung (lokal, 120 m um den Laden): „🛒 Du bist bei Rewe: 4 Sachen auf der Liste · Coupon Kaffee“ (38d, bald ablaufender Coupon der Kette); nichts offen, aber Coupon → „🎟 Du bist bei Rewe: Denk an deinen Payback-Coupon für Kaffee (läuft So ab)“ → öffnet die Laden-Liste S5b.
  - **Familie:** Mitglieder (Avatare), „Einladungslink teilen“
  - **Rezepte** (Phase 9): „Teilen aus Instagram“ → S21; Schalter „Schritt-Bilder erzeugen“ mit Untertitel „ca. 2 Cent/Rezept“ (nur wenn `step_images_available`, speichert `PATCH /household {step_images}`).
  - **Geräte & Widget** (Phase 16): „Widget einrichten“ (Icon `square.grid.2x2.fill`, Wert „koppeln“) → S38
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

### S16 Vorrat (Tab „Einkauf“, Pille „Liste | Vorrat | Coupons“, Feature 60)
- `DisplayHeader` „Vorrat / N Sachen zu Hause“ + runder „+“-Button.
- `SearchField`, `CategoryCircles` (Kategorie aus dem Namen, eigene Gruppe „Basics“ 🧂).
- Zeilen (weiße Kacheln): Emoji auf Kategorie-Tönung, Name, Menge, Haltbarkeits-Chip („läuft in 2 Tagen ab“ orange, „abgelaufen“ rot, sonst grau), rechts Stepper (g/ml 10er bzw. ab 100 50er, Stück 1er; 0 → Eintrag weg). Basics statt Stepper Schalter vorhanden/leer; leer → kommt auf die Liste, Toast „Öl steht auf der Liste“.
- Wischen nach links oder lange drücken → Löschen.
- „+“-Sheet: Name, Menge (optional), Einheit (g/ml/Stück/ohne), Haltbarkeit optional, Schalter „Basic“.
- Leer: `EmptyState` „📸 Kühlschrank fotografieren“ mit `PrimaryButton` „📸 Kühlschrank fotografieren“ → S23 (Feature 69). Laden → Skeleton, Fehler → `ErrorState`.
- Ort (E63, aus dem Kühlschrank-Foto): in der Zeile hinter Menge/Haltbarkeit „🧊 Kühlschrank“ / „🥫 Vorrat“ / „❄️ Gefrierfach“ (`micro`, `text2`); ohne Ort nichts. Keine eigene Gruppierung.
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

- Phase 10 (Feature 7): Zutat der Vorbereitung lange drücken → „Ersatz finden“ → S26 (Sheet im App-Erscheinungsbild); ersetzt die Zutat im Rezept, Kochmodus zeigt sie sofort.

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
- Fester `PrimaryButton` „N in den Vorrat übernehmen“ → `POST /pantry/bulk` (`source: scan`); danach fliegen die gewählten Karten nacheinander in die Vorrats-Pille (Haptik), Toast „N Sachen im Vorrat“, weiter zu S25. Der Ort wird mitgespeichert (`location`, E63) und in S16 angezeigt.

### S25 Was koche ich jetzt? (im Sheet S23)
- Kopf „Was koche ich jetzt? / Aus deinem Vorrat · höchstens 30 min“, runder ✕.
- Laden (`POST /pantry/cook-now`, bis ~15 s): drehender Teller + Schritte „Vorrat ansehen“, „Ideen sammeln“, „Fehlende Zutaten prüfen“.
- Bis zu 3 Karten: Tellerfoto, Titel, „25 min · 2 Portionen“, „Alles da ✓“ oder Box „Fehlt: Sahne (100 ml)“ mit „Zur Liste“ (→ Haushaltsliste, wird „Auf der Liste“); `PrimaryButton` in `accent` „🔥 Heute kochen“ → ersetzt das heutige Gericht (gleiche Mahlzeit bevorzugt, nicht fixierte zuerst) über `…/replace`, Toast „Heute: <Titel>“; heute kein Gericht im Plan → S19. Karte antippen → S3.
- Vorrat leer (422) → `EmptyState` „Vorrat ist leer“; keine Idee → „Keine passende Idee“; Fehler → `ErrorState`.

## Phase 10/11 – Ersatz & Clever planen (S26–S30)

### S26 Ersatz finden (Sheet aus S3/S18, Feature 7)
- Kopf „Ersatz für Joghurt“, darunter „150 g im Rezept · aus unserer Ersatz-Tabelle“ bzw. „· Vorschläge der KI“, runder ✕.
- 2–4 Karten (Kachel-Radius, gestaffelt): „Skyr statt Joghurt“ (`headline` rounded), Mengen „130 g Skyr + 20 ml Wasser“ (`callout`, `accentDeep`), Wirkung (`caption`, `text2`), Badges „im Vorrat“ (`DealBadge` ok; bei mehreren Zutaten „Wasser im Vorrat“) und „im Angebot 1,29 €“ + `StoreChip`; rechts ⇄ bzw. Spinner beim Ersetzen.
- Antippen → `POST /recipes/{id}/ingredients/{i}/substitute` → Toast „Ersetzt: Joghurt → Skyr + Wasser“, Haptik, Sheet zu; Plan, Liste und Nährwerte werden neu geladen.
- Darunter Hinweis „Antippen ersetzt die Zutat nur in diesem Rezept – Nährwerte und Kosten werden neu berechnet.“
- Laden → 3 Skeleton-Karten + „Suche passenden Ersatz …“; keine Optionen → `EmptyState` 🤷 „Kein Ersatz gefunden“; Fehler → `ErrorState` (502 „Die Ersatz-Suche ist gerade nicht erreichbar.“). Demo: `substitute`.

### S27 Keine Lust? (Sheet aus S1/S2, Feature 16)
- Kopf „Keine Lust?“ / „Schnell & ohne Einkauf · höchstens 15 min“, runder ✕.
- Laden (`POST /no-mood`): drehender Teller + Schritte „Vorrat ansehen“, „Ideen sammeln“, „Prüfen, ob alles da ist“.
- Seite mit 3 Karten (wie S25): Tellerfoto, Titel, „12 min · 2 Portionen“, Badge „Alles da ✓“, `PrimaryButton` in `accent` „🔥 Das koche ich heute“; Karte antippen → S3. Horizontal wischen → nächste Seite mit 3 weiteren (`exclude` = gezeigte Titel), währenddessen 2 Skeleton-Karten + „Weitere Ideen …“; nichts mehr → `EmptyState` „Mehr fällt uns gerade nicht ein“. Unten Hinweis „Wischen für 3 weitere ›“.
- Auswahl → ersetzt das heutige Gericht (Mittag, sonst Abend) über `…/replace`, Toast „Heute: <Titel>“. Gibt es später im Plan noch ein nicht fixiertes Gericht derselben Mahlzeit: Rückfrage „Auf morgen verschieben?“ (bzw. „Auf Donnerstag verschieben?“) mit „„Tikka Masala“ – die Zutaten sind schon da. Spätere Gerichte rücken einen Tag weiter.“ → `POST /plans/current/postpone`, Toast „„Tikka Masala“ → Mittwoch“; „Nein, danke“ schließt. Heute kein Gericht → S19.
- Vorrat leer (422) → `EmptyState` „Vorrat ist leer“; keine Idee → „Keine passende Idee“; Fehler → `ErrorState`. Demo: `nomood`.

### S28 Gäste hinzufügen (Sheet aus S2, Feature 15)
- Kopf „Gäste hinzufügen“, „Dienstag · Abend: „Lachs-Bowl““, runder ✕.
- Karte: 👥 im `accentSoft`-Quadrat, große Zahl „+2“ (40 pt rounded, Zahlen-Übergang) + „Gäste“, Stepper 0–20 (Haptik).
- Hinweis „Mengen, Kosten und Einkaufsliste werden angepasst – ohne neue KI-Planung.“, `PrimaryButton` „Übernehmen“ (erst bei Änderung aktiv) → `POST /plans/current/entries/{id}/guests`, Toast „Für +2 Gäste angepasst“ bzw. „Gäste entfernt“; 422 → Toast „Bei dieser Mahlzeit isst dann niemand mit“. Demo: `guests`.

### S29 Frühstück & Snacks (Push-Screen aus S13, Feature 23a)
- Zurück, `DisplayHeader` „Frühstück / & Snacks“ + runder schwarzer „+“, Satz „Deine Basics kommen jeden Montag automatisch auf die Haushaltsliste – im Angebot, wenn es in deinen Läden günstiger ist; was im Vorrat ist, wird abgezogen.“
- Zeilen (weiße Kacheln): Kategorie-Emoji auf Tönung, Name, „1.000 g pro Woche“ bzw. „ohne Menge · jede Woche“, Chevron → Sheet; lange drücken → „Löschen“.
- Sheet „Neues Basic“ / „Basic ändern“: Name, Menge pro Woche (optional, Zahlentastatur), Einheit g/ml/Stück/ohne, `PrimaryButton` „Hinzufügen“/„Speichern“, beim Ändern „Löschen“ (rot).
- Fest unten `PrimaryButton` „Jetzt auf die Liste“ (`POST /weekly-basics/to-list`, Toast „Basics stehen auf der Liste“).
- Laden → Skeleton, Fehler → `ErrorState`, leer → `EmptyState` 🥣 „Noch keine Basics“ + „Basic hinzufügen“. Demo: `basics`.

### S30 Reste in den Vorrat? (im Sheet S8, Feature 19)
- Titel „Reste in den Vorrat?“, Satz „Von angebrochenen Packungen bleibt etwas übrig – Menge prüfen, dann übernehmen.“
- Zeilen wie S24: Häkchen-Kreis (`accent`), Kategorie-Emoji, Name, Haltbarkeits-Chip, Menge (Zahlentastatur) + Einheit.
- `PrimaryButton` „N in den Vorrat“ → `POST /pantry/bulk` (`source: rest`), Toast „N Reste im Vorrat“; `SecondaryButton` „Nichts übrig“ schließt. Demo: `leftovers`.

### Einstellungen › Präferenzen › Abwechslung (Feature 12)
- Unter dem Präferenzen-Formular Überschrift „🔄 Abwechslung“ + „Der Planer hält diese Regeln ein – Verstöße zeigt der Plan-Kopf.“, drei Karten mit Stepper-Zeilen (Wert groß rechts, Zahlen-Übergang, Haptik): „🍝 Beilagen pro Woche“ (Pasta höchstens 1×, Reis 2×, Kartoffeln 2×; 0–14), „🐟 Fisch, Fleisch, Gemüse“ (Fisch mindestens 0–3, Vegetarische Tage 0–7, Rotes Fleisch höchstens 0–14), „🔁 Wiederholungen“ (Gleiches Gericht frühestens nach 1–12 Wochen, Schalter „Gleiche Küche nicht zwei Tage hintereinander“). Speichern mit dem festen Button → `PATCH /household {variety}`. Demo: `variety`.

## Phase 13/14 – Bonus, Ausgaben, Motivation (S31–S37)

Demo: `wallet`, `bonus`, `coupon`, `couponadd`, `spending`, `achievements`, `unlock`, `review`, `reviews`, `recipelink`, `sharedrecipe` (hell + dunkel).

### S31 Coupons (Tab „Einkauf“, Pille „Liste | Vorrat | Coupons“, Feature 38/59)
- `DisplayHeader` „Coupons / N gültig“ + runder schwarzer „+“ → S31c.
- Zwei Konto-Karten nebeneinander (Kachel, `card`): Programm-Emoji im `accentSoft`-Quadrat, rechts ±-Symbol; „Payback“ / „1.240 °P“ (`title2` rounded, Zahlen-Übergang) / „≈ 12,40 €“; „Rewe Bonus“ / „8,50 €“ / „+2,30 € im Monat“ (`success`). Antippen → S31d.
- Coupon-Zeilen (Kachel): Laden-Logo bzw. Programm-Emoji (🅿️ Payback, 🎁 Rewe Bonus, 🧴 dm/Rossmann, 🎟 sonst), Vorteil fett („10fach Punkte“), „Payback · Kaffee“ (sonst Kategorie bzw. „den ganzen Einkauf“), Ablauf („läuft heute/morgen/So ab“ ≤ 2 Tage als `DealBadge` soft, sonst „gültig bis 30.11.“ `text2`), „ab 20,00 € Einkauf“; rechts Barcode-/QR-Symbol. Reihenfolge vom Server (bald ablaufende oben). Antippen → S31b; lange drücken → „An der Kasse zeigen“, „Bearbeiten“, „Löschen“.
- Abschnitt „⌛️ Abgelaufen“: gleiche Zeilen grau (Graustufen, 50 %).
- Laden → 3 Skeleton-Zeilen; Fehler → `ErrorState`; leer → `EmptyState` 🎟 „Noch keine Coupons“ + „Coupon hinzufügen“.

### S31b Kasse (Vollbild aus S31, Badge, Coupon-Leiste, Push `essenapp://coupon/<id>`)
- Kopf „An der Kasse zeigen“ + runder ✕. Helligkeit auf Maximum, beim Schließen zurück.
- Weißes Plättchen (immer hell, Radius Karte, Schatten `float`): Logo + Partner + Programm, Vorteil groß (`largeTitle` heavy rounded), „für Kaffee“, Barcode (Code128/QR per CoreImage, EAN-13/EAN-8 selbst gezeichnet, ganze Pixel je Modul, Ruhezone), darunter der Code in Monospace (nicht bei QR), Chips Ablauf + Mindestumsatz.
- Ohne Code: „Kein Barcode gespeichert – zeig den Coupon in der Payback-App oder scanne ihn hier ein.“ + `SecondaryButton` „Barcode ergänzen“ → S31c (Bearbeiten). Unbekannte ID → `EmptyState` „Coupon nicht gefunden“.

### S31c Coupon hinzufügen / prüfen / bearbeiten (Sheet)
- Auswahl: Zeilen „📸 Coupon fotografieren“ (Kamera; Pille „Foto aus der Mediathek“ darunter), „▦ Barcode scannen“ (Scanner aus S10 mit Code128/EAN/QR, Titel „Coupon-Barcode scannen“, Pille „Barcode oder QR-Code in den Rahmen halten“), „✏️ Manuell eingeben“.
- Foto → Skeleton + „Coupon wird gelesen …“ (`POST /coupons/scan`, JPEG ≤ 5 MB) → Formular „Coupon prüfen / Aus dem Foto gelesen – bitte kurz prüfen.“; Fehler: 422 „Das Foto konnte nicht gelesen werden …“, 502 „Die Erkennung ist gerade nicht erreichbar …“ + „Anderes Foto“ / „Manuell eingeben“.
- Formular (Karten): **Partner** (Chips Payback · Rewe Bonus · dm · Rossmann · Sonstige; Feld Partner; Menü „Laden“ mit den Läden des Haushalts, „Kein bestimmter“), **Vorteil** (Segment Xfach · € Bonus · % Rabatt · Sonstiges + Zahl, Text – leer → „10fach Punkte“/„0,50 € Bonus“/„20 % Rabatt“, Produkt/Marke, Kategorie-Menü, Mindestumsatz €), **Gültigkeit** (Schalter „Gültig bis“ + Datum, Hinweis Erinnerung 2 Tage vorher), **Barcode** (Vorschau auf weißem Plättchen + Typ-Segment, Feld „Code eintippen“, „Barcode scannen“/„Neu scannen“). `PrimaryButton` „Speichern“ (aktiv mit Partner oder Programm) → `POST`/`PATCH /coupons`, Toast; beim Bearbeiten „Löschen“ rot.

### S31d Plus/Minus (Sheet aus der Konto-Karte, Höhe passt sich an)
- Kopf Emoji + „Payback“, runder ✕; Kontostand groß (40 pt rounded) + „≈ 12,40 €“.
- `PillSegment` „Bekommen · Eingelöst · Korrigieren“, Feld mit „+ / − / =“ und Einheit (°P Ziffern, € Dezimal), Schnell-Chips (10/50/100/500 °P bzw. 0,50/1,00/2,00/5,00 €).
- `PrimaryButton` „Heute bekommen: +60 °P“ / „Eingelöst: −500 °P“ / „Kontostand: 1.240 °P“ → `POST /bonus/{program}` `{delta}` bzw. `{set}`; Toast „Payback: 1.300 °P“; 422 → „Kontostand darf nicht negativ werden“. Hinweis: Bekommen zählt als Ersparnis „Bonus“, Korrektur nicht.

### Phase 13 – Ergänzungen bestehender Screens
- **S4/S9:** Rewe-Bonus-Aktion (39) als `DealBadge` (ok, Orange) „🎁 0,50 € Bonus“ neben dem Rabatt-Pill der `OfferCard` und im dunklen Kopf von S9.
- **S5 `ItemRow`:** Coupon-Badge „🎟 10fach“ (`ItemOut.coupon`, nur offene Artikel), antippen → S31b. **S5b Laden-Liste:** unter dem Kopf **Coupon-Leiste** (`GET /coupons?chain=`, nur wenn vorhanden): `accentSoft`-Kapseln „🎟 10fach“ (`accentDeep`) + „Kaffee“ / „läuft So ab“ (≤ 2 Tage `deal`), antippen → S31b; Zeile lange drücken → zusätzlich „Coupon zeigen“.
- **S1 Start:** nach „Vorrat anlegen lohnt sich“ Karte „🧾 Ausgaben November“: „182,40 € von 257,14 €“ + Fortschrittsbalken (`accent`, über Budget `danger`), Chevron → S32; danach Karte „📖 Wochenrückblick KW 45“ (S35).

### S32 Monats-Dashboard (Push-Screen aus S1 und S13, Feature 34)
- Kopf: Zurück, rechts runder Teilen-Knopf (CSV `ausgaben-2026-11.csv`, nur mit Käufen). `DisplayHeader` „Ausgaben / November 2026“, darunter „‹ Oktober“ … „Dezember ›“ (nicht über den aktuellen Monat hinaus); waagerecht wischen wechselt den Monat (Haptik).
- Karte Ring (104 pt, `accent`, über Budget `danger`, wächst beim Erscheinen) mit „61 % vom Budget“; daneben „Ausgegeben“ + Summe (30 pt rounded, zählt hoch), „Budget 257,14 €“ (ohne Budget „Kein Budget eingestellt“), „davon 12,60 € geschätzt“, „+8,6 % zum Oktober“ (`danger` mehr / `success` weniger).
- Karte „💰 Gespart“ (Summe `success`) mit zwei `surface`-Kacheln „Angebote“ / „Bonus“.
- Karte „Pro Woche“: Swift-Charts-Balken je KW (`accent`, aktuelle Woche `accentDeep`), Betrag über dem Balken, Balken wachsen beim Erscheinen.
- Karten „Pro Laden“ (Ring-Torte in `Theme.storeColor`, Legende mit Farbpunkt, Logo, Name, %) und „Pro Kategorie“ (Kategorie-Farben + Emoji); Torte dreht und skaliert beim Erscheinen auf.
- Karte „Top 5 teuerste“: Rang im Kreis, Name, `StoreChip`, Datum, Badge „geschätzt“, Preis.
- Laden → 3 Skeleton-Karten; Fehler → `ErrorState`; Monat ohne Käufe → `EmptyState` 🧾 „Noch keine Einkäufe im Oktober“ + „Ausgaben entstehen, wenn ihr Artikel auf der Liste abhakt …“.

### S34 Erfolge (Push-Screen aus S13 › Mein Profil, Push `essenapp://achievements`, Feature 54)
- Zurück, `DisplayHeader` „Erfolge / 5 von 18 erreicht“; Abschnitte „💰 Sparen · Haushalt“ und „💪 Gesundheit · Jona“, je Raster mit 3 Spalten.
- Medaille 76 pt: erreicht = Verlauf `highlight` → `accent` mit weißem Innenring und Schatten, darunter Titel + Datum (`accentDeep`); gesperrt = `surface`, Emoji grau/halb transparent, Fortschrittsring `accent`, darunter „34 / 50 €“ (`text3`). Erscheinen gestaffelt.
- Antippen → Sheet (halbe Höhe): Medaille 130 pt, Titel, „✓ Erreicht am 2.11.2026“ (`success`) bzw. Fortschrittsbalken + „34 / 50 €“ + „Noch 16 € bis zum Ziel“.
- Laden → 9 Skeleton-Kacheln; Fehler → `ErrorState`.
- **Vollbild-Moment** (über allem, sobald `GET /achievements` etwas mit `new` liefert – beim Start/Neuladen und in S34): `heroDark` 94 %, Konfetti (aus bei „Bewegung reduzieren“), „Neuer Erfolg!“, Medaille 170 pt fliegt gedreht von oben ein (Feder), Titel, Gruppe, Haptik; `PrimaryButton` (`accent`) „Weiter (1/2)“ bzw. „Super!“ → danach `POST /achievements/seen`.

### S35 Wochenrückblick (Vollbild-Story aus S1, Archiv, Push `essenapp://review/<woche>`, Feature 55)
- 6 Seiten, wischen oder tippen (linkes Drittel zurück, sonst weiter); oben 6 Fortschrittsstriche, „📖 Wochenrückblick KW 45“, runde Knöpfe Teilen + ✕ (Weiß 18 %). Weiße Schrift; Hintergrund je Seite `accent`, `success`, `heroDark`, `accentDeep`, `heroDark`, `accent` (sanfter Verlauf).
  1. „Deine Woche“ / „KW 45 · 2.–8. November“: gekochte Gerichte (84 pt, zählt hoch), „von 9 geplanten“; Lieblingsgericht (Tellerfoto 150 pt springt auf, Titel, Sterne) bzw. Hinweis „Bewertet Gerichte mit „Gekocht ★“ …“.
  2. „Gespart & ausgegeben“: Ausgegeben (zählt hoch), „davon … geschätzt“, Glas-Kacheln „durch Angebote“ / „Bonus“, Kapsel „✓ Im Budget (60,00 €)“ bzw. „⚠ 8,90 € über Budget“.
  3. „Gesundheit / Schnitt pro Tag“: je Person Kachel mit Emoji, Name, „🥦 18 Pflanzen“, Balken kcal (`kcal`) und Protein (`protein`) gegen das Ziel.
  4. „Vorrat & Reste“: Kacheln „Reste verwendet“, „noch übrig“; „weggeworfen“ nur, wenn erfasst (`thrown_away` ≠ null).
  5. „Neue Erfolge“: Medaillen springen gestaffelt auf + Konfetti; leer „Diese Woche kein neuer Erfolg – nächste Woche klappt’s!“.
  6. „Nächste Woche günstig“: bis zu 3 Zeilen (Bild auf Plättchen, Titel, Logo, „3,49 € statt 4,99 €“, „−30 %“), `PrimaryButton` „✨ Plan erstellen“ → schließt und öffnet S7.
- Teilen → Sheet „Als Bild teilen“ (wie Feature 10): Bildkarte 1080×1350, immer hell: „Meine Woche“, KW + Zeitraum, 4 Kacheln (gekocht, gespart, Pflanzen, neue Erfolge), Lieblingsgericht, „Mit Essenapp geplant“.
- Start-Karte (S1): 📖 im `accentSoft`-Quadrat, „Wochenrückblick KW 45“, „5 gekocht · 14,50 € gespart“, rechts „Archiv“ (`accentDeep`) → S35b. Sonntags öffnet sich die Story beim ersten Öffnen der Woche einmal von selbst.
- Laden → Spinner (weiß); Fehler → Satz + „Erneut versuchen“.

### S35b Rückblicke (Archiv, Push-Screen)
- Zurück, `DisplayHeader` „Rückblicke / 3 Wochen“; Zeilen (Kachel): „KW 45“ im `accentSoft`-Quadrat, „Woche 45 · 2026“, „5 gekocht · 68,90 € ausgegeben“, Chevron → S35. Leer → `EmptyState` 📖 „Noch kein Rückblick“ / „Der erste kommt am Sonntag um 19 Uhr.“; Laden → Skeleton; Fehler → `ErrorState`.

### S36 Als Link teilen (Sheet aus S3 › Teilen, Feature 56)
- „Als Link teilen“ + runder ✕, Satz „Wer den Link öffnet, sieht Foto, Zutaten und Schritte – mit Essenapp lässt sich „…“ in die eigenen Rezepte übernehmen.“
- Link-Kachel (🔗 `accent`, Monospace, auswählbar), `PrimaryButton` „Teilen“ (System-Teilen mit „Rezept „…“ aus unserer Essenapp:“), `SecondaryButton` „Link kopieren“ → „Kopiert ✓“ (Haptik). Laden → 2 Skeleton; Fehler → `ErrorState`.

### S37 Geteiltes Rezept (Sheet über allem, Deep-Link `essenapp://import-recipe/<code>`, Feature 56)
- Kopf „Geteiltes Rezept“ + ✕; Tellerfoto 180 pt, Titel, Chip „👥 von Familie Müller“, „45 min · 4 Portionen · 3 Schritte“, Beschreibung, Karte „Zutaten“ (Name, Menge).
- Fester `PrimaryButton` „Übernehmen“ → `POST /shared-recipes/{code}/import`, Toast „„Omas Linsensuppe“ liegt jetzt in deinen Rezepten“, Sheet zu → Tab Rezepte › S3 der Kopie (Quelle-Chip „👥 von Familie Müller“). Ungültiger Code (404 oder unzulässige Zeichen) → `EmptyState` 🤷 „Rezept-Link ungültig“; Fehler → `ErrorState`.

## Phase 16 – Widget & Live-Aktivität (S38–S40)

Ohne Vorlage im Mockup entschieden (Nutzer schläft, E84/E85); Werte nur aus `Theme.swift`/`ShareTheme.swift`. Widget und Live-Aktivität laufen in der Erweiterung `EssenappWidget` mit dem kleinen Theme aus `EssenappShareUI` (E58).

### S38 Widget einrichten (Push-Screen aus S13 › Geräte & Widget)
- Gleiche Oberfläche wie S21 (eine View): `DisplayHeader` „Widget / einrichten“, Satz „Heutiges Gericht, nächste Mahlzeit und offene Artikel auf Home- und Sperrbildschirm.“
- Karte „So geht's“: 1 „Code erzeugen“ tippen · 2 Home-Bildschirm lange drücken › „Bearbeiten“ › „Widget hinzufügen“ › „Essenapp“ (klein, mittel oder Sperrbildschirm) · 3 Widget lange drücken › „Widget bearbeiten“ › Server-Adresse und Kopplungscode eintragen · 4 Widget lädt selbst, etwa alle 30 Minuten; weitere Widgets brauchen nur die Server-Adresse.
- Karten „Kopplungscode“ (mit Zeile „Server-Adresse“ + „Kopieren“) und „Gekoppelte Geräte“ wie S21; Icon je Gerät: Widget `square.grid.2x2.fill`, sonst `square.and.arrow.up.fill`. Rückfrage beim Widerrufen: „Das Gerät muss sich danach mit einem neuen Code koppeln.“

### S39 Widget „Heute“ (Home- und Sperrbildschirm, Feature 65)
- **Klein:** Foto des Gerichts randlos (ohne Foto: `accentSoft` + Gericht-Emoji wie `Plate`), unten Verlauf nach Schwarz 65 %, weiß: „HEUTE · MITTAG“ (`micro`, 85 %), Titel (`headline`, 2 Zeilen), „🕑 35 min“ (`caption`).
- **Mittel:** links Foto 130 pt (Radius `tile`), rechts „HEUTE · MITTAG“ (`micro`, `accentDeep`), Titel (`headline`, 2 Zeilen), „🕑 35 min“, unten „Danach: Linsen-Dal mit Spinat“ und „🛒 6 offen · Hähnchenbrust, Feta, Lachsfilet“ (`caption`, 1 Zeile; nichts offen → „🛒 Liste erledigt“). Grund `card`.
- **Sperrbildschirm:** rechteckig „Heute · Mittag“ / „🍛 Tikka Masala“ / „35 min · 🛒 6 offen“; Zeile über der Uhr „🍛 Tikka Masala · 35 min“.
- Welches Gericht: Mittag bis 14 Uhr, Abend bis 21 Uhr, danach das nächste (Label „Morgen“ bzw. Wochentag); ohne Mittag/Abend im Plan alle Mahlzeiten. Antippen → `essenapp://recipe/<id>`.
- **Zustände:** ungekoppelt → 🔗 „Widget bearbeiten → Code eingeben“ + „Code: Essenapp › Einstellungen › Widget einrichten“ (bzw. Fehler des Kopplungscodes, z. B. „Code ungültig“); kein Plan → 🗓️ „Noch kein Wochenplan“ / „In der App einen Plan erstellen.“; Server nicht erreichbar → letzter Stand + „Stand 14:05“ mit `wifi.slash` (`micro`), ohne gespeicherten Stand 📡 „Gerade kein Stand“ + Meldung.

### S40 Live-Aktivität „Einkauf“ (Sperrbildschirm + Dynamic Island, Feature 37)
- **S5b:** unter dem Kopf `SecondaryButton` „🛒 Einkauf starten“ (nur wenn Live-Aktivitäten erlaubt sind und etwas offen ist), läuft sie: „■ Einkauf beenden“. Ein Einkauf zur Zeit.
- **Sperrbildschirm** (Grund `card`): Kürzel des Ladens auf `Theme.storeColor` (36 pt, wie `StoreLogo` ohne Bild, „Überall“: 🧺 auf `surface`), Name (`headline`), rechts „5 von 12“ (gerundet, fett); Fortschrittsbalken `accent`; die nächsten 3 offenen Artikel: ○ (`accent`) + Name (`callout`) + Menge (`caption`, `text2`) – antippen hakt ab. Nach 2 h: „Einkauf vorbei? In der App beenden.“
- **Dynamic Island:** kompakt links Kürzel (22 pt), rechts „5/12“ (`accent`); minimal Zahl der offenen Artikel; ausgeklappt Kürzel + Name links, „5 von 12“ rechts, darunter die 3 Artikel mit Abhak-Knopf (weiße Schrift).
- Endet von selbst, wenn alles abgehakt ist (bleibt kurz mit Endstand stehen) oder nach 2 h. Antippen → `essenapp://list/<kette>`.
