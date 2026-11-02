# Phase 9 – Rezepte, Import, Kühlschrank-Foto

---

## 3 · Meine Rezepte

**Ziel:** Gerichte merken, eigene anlegen, importierte sammeln; Bewertungen steuern künftige Pläne.

**Ablauf**
- Herz in Rezeptdetail und auf Gericht-Karten → „Meine Rezepte“ (Favorit).
- Bewertung nach „Gekocht ★“ wird gespeichert (1–5 Sterne, „Wieder kochen?“ Bald/Irgendwann/Nie, Notiz, wer, wann).
- Eigenes Rezept anlegen (Formular): Titel, Foto (Kamera/Fotos), Portionen, Zeit, Küche, Mahlzeit, Zutaten-Zeilen (Name, Menge, Einheit – mit Vorschlägen aus bekannten Zutaten), Schritte (sortierbar), Tags. Speichern legt `source=user` an.
- Liste „Meine Rezepte“ (Tab Rezepte › Pille „Meine Rezepte“): Filter-Pillen Alle · ♥ Favoriten · Eigene · Importiert · Im Angebot · Zuletzt gekocht; Suche; Raster-Karten (Foto, Titel, Sterne, Preis/Portion aktuell, Badge „im Angebot“ ab 40 % Kostenanteil, Badge „Instagram“ bei Imports).
- Aus Liste: „Diese Woche einplanen“ → Tag/Mahlzeit wählen → ersetzt Slot (wie Würfeln, ohne KI).
- **Planner:** Favoriten + ≥4★ werden bevorzugt (Prompt bekommt die Top 15 inkl. Zutaten), „Nie“ und ≤2★ werden ausgeschlossen (auch ähnliche Titel), Wiederholung frühestens nach 3 Wochen (12).
- „Rezept im Angebot“: nach jedem Import Kostenanteil pro gespeichertem Rezept berechnen → Start-Karte „3 Lieblingsrezepte sind diese Woche günstig“ (Tippen → gefilterte Liste).

**UI:** S12 erweitert, S17 Rezept-Formular (Schritt-für-Schritt-Sheet), Sterne-Animation, Herz mit `symbolEffect(.bounce)` + Haptik.

**Backend:** `recipe` erhält `favorite_of` (n:m `recipe_favorite`), `source` (ai/user/instagram/web), `source_url`, `tags[]`, `image_url`; Tabelle `rating`; Endpunkte `GET /recipes?filter=`, `POST /recipes`, `PATCH/DELETE /recipes/{id}`, `POST /recipes/{id}/favorite`, `POST /recipes/{id}/rate`, `POST /plans/current/entries/{id}/replace` (recipe_id). Rezept-Kosten live aus aktuellen Angeboten (`GET /recipes/{id}/cost`).

**Abnahme:** Rezept anlegen → erscheint, lässt sich einplanen; 5★ → taucht im nächsten Plan bevorzugt auf (Prompt-Test); „Nie“ → nie wieder; Badge „im Angebot“ korrekt.

---

## 1 · Zutat antippen → Angebot

**Ablauf**
- Zutat mit `offer_id` → öffnet Angebotsdetail (S9) als Push.
- Zutat ohne Angebot → Sheet „Angebote für *Zwiebeln*“: Treffer aus aktuellen Angeboten (Name-Suche, normalisiert, Synonyme z. B. „Hähnchenbrust“↔„Hähnchenbrustfilet“), sortiert nach Grundpreis, mit Laden-Logo; leer → „Diese Woche nicht im Angebot – Normalpreis ca. 1,29 €“ + „Zur Liste“.
- Zutat im Vorrat → Chip „im Vorrat (500 g)“, Tippen öffnet Vorrat.

**Abnahme:** jede Zutatzeile ist antippbar, richtige Ziele, leerer Zustand vorhanden.

---

## 2 · Nährwerte + Blüten-Diagramm

**Ziel:** Echte, berechnete Nährwerte pro Portion/Person/Tag (E10).

**Datenquelle:** USDA FoodData Central (Foundation + SR Legacy, gemeinfrei) als Tabelle `food` (kcal, Protein, Fett, KH, Ballaststoffe, Zucker, Salz pro 100 g) einmalig importiert. Zuordnung deutscher Zutatnamen → `food_id` per Haiku (Auswahl aus Top-10 Volltexttreffern, englische Übersetzung), Ergebnis in `ingredient_map` gecacht; Stück-Gewichte (`grams_per_piece`) aus Tabelle bzw. KI-Vorschlag einmalig.

**UI**
- Rezept: 4 Kacheln (kcal, Protein, KH, Fett) pro Portion der gewählten Person; darunter **Blüten-Diagramm** (Zutatenanteile nach Gewicht, Mitte Tellerfoto, Blütenblätter mit Verlauf, Prozent + Name, Animation: Blätter wachsen nacheinander auf).
- Wochenplan-Tag: Ringe pro Person (kcal/Protein gegen Ziel), Wochenschnitt im Kopf.
- Angebote mit Nährwerten (wenn Zuordnung sicher) im Detail.

**Abnahme:** Tikka Masala zeigt plausible Werte (kcal ±15 % gegen manuelle Rechnung), Blüte summiert 100 %, Tagesringe reagieren auf Würfeln.

---

## 5 · Rezept-Import aus Instagram (Teilen-Menü) ⭐ sehr wichtig

**Ziel:** In Instagram bei einem Reel/Beitrag auf „Teilen → Essenapp“ tippen → fertiges Rezept in „Meine Rezepte“.

**Ablauf**
1. Share Extension `EssenappShare` nimmt URL (und Text, falls Instagram ihn mitgibt) entgegen. Erweiterungs-UI: kleines Sheet im Essenapp-Stil: Vorschau (Titel/Bild sobald geladen), Fortschritt „Rezept wird gelesen …“, Ergebnis: Titel, Zutatenzahl, „In Meine Rezepte speichern“ + Optionen „Diese Woche einplanen“.
2. Erweiterung schickt URL an `POST /import` (Auth siehe A1: App Group/Keychain-Gruppe, sonst einmaliger Kopplungscode).
3. Backend: Instagram-Link erkennen (`/p/`, `/reel/`, `/tv/`), öffentliche Einbettungs-Seite lesen (Beschreibung, Autor, Vorschaubild, Reel-URL), ohne Login, schonend (1 Abruf, Cache). Andere Webseiten: `schema.org/Recipe` (JSON-LD) direkt übernehmen, sonst Seitentext.
4. Haiku macht daraus strukturiert: Titel, Portionen, Zeit, Zutaten (Menge/Einheit, deutsch), Schritte, Küche, Tags, `image_query`. Fehlt etwas (z. B. Mengen), schätzt die KI und markiert „geschätzt“.
5. Speichern mit `source=instagram`, `source_url`, Autor („von @koch_xy“), Vorschaubild als Rezeptfoto.
6. Kein Rezept in der Beschreibung → Hinweis + Angebot „Screenshots wählen“ (A2, falls bestätigt).

**UI:** Rezeptdetail zeigt Quelle-Chip „Instagram · @autor“ + Knopf „Original-Reel ansehen“ (9). Import-Liste unter Meine Rezepte (Filter „Importiert“).

**Abnahme:** 3 echte öffentliche Reels mit Rezept in der Beschreibung → je ein vollständiges Rezept (Zutaten mit Mengen, Schritte) in < 15 s; Abbruch/Fehler zeigen verständliche Meldung; Kosten pro Import geloggt (< 0,2 ct).

**Risiken:** A1 (Erweiterung + Login-Teilung), A2 (Instagram liefert Beschreibung nicht), xtool-Erweiterungsfehler (#313/#379) → **Spike am Phasenanfang**: leere Share Extension bauen, signieren, installieren; Ergebnis im Playbook.

---

## 9 · Original-Reel + KI-Bild pro Schritt

- **Original-Reel:** bei `source=instagram` Knopf „▶︎ Original-Reel“ (öffnet Instagram-App bzw. Safari).
- **KI-Bild pro Schritt:** im Rezept und Kochmodus bekommt jeder Schritt ein Bild (16:10). Erzeugung bei erstem Öffnen eines Rezepts (Hintergrund, Platzhalter-Schimmer), Prompt aus Rezepttitel + Schritttext + einheitlichem Stil („bright overhead food photography, home kitchen, natural light“), fal.ai FLUX schnell, Bild wird auf dem Server gespeichert (`/media/steps/<recipe>/<n>.jpg`), danach nie neu erzeugt. Schalter in Einstellungen „Schritt-Bilder erzeugen (ca. 2 Cent/Rezept)“, Standard an, wenn `FAL_KEY` gesetzt.
- **Abnahme:** Rezept mit 5 Schritten → 5 Bilder, beim zweiten Öffnen sofort da, Kosten im Kostenprotokoll.

---

## 69 · Kühlschrank-Foto ⭐⭐

**Ziel:** Fotos von Kühlschrank, Vorratsschrank, Gefrierfach → Zutaten erkannt → Vorrat, sofortige Kochideen, Plan nutzt sie.

**Ablauf**
1. Einstieg: Schnell-Aktionen „📸 Kühlschrank scannen“, Vorrat-Leerzustand, Start-Karte.
2. Kamera-Sheet mit Modus-Pillen „Kühlschrank · Vorrat · Gefrierfach“, mehrere Fotos nacheinander (Thumbnails unten, löschbar), „Fertig“.
3. Bilder (verkleinert auf 1024 px) → `POST /pantry/scan` → Haiku (Vision) gibt Liste: Name, geschätzte Menge+Einheit, Ort, Sicherheit (hoch/mittel/niedrig), Haltbarkeits-Schätzung bei Frischem.
4. Prüf-Bildschirm: Liste mit Häkchen (unsichere vorab abgewählt, gelb markiert), Mengen editierbar, „+ fehlt etwas?“ → „In den Vorrat übernehmen“ (Animation: Karten fliegen in die Vorrats-Pille).
5. Direkt danach Sheet **„Was koche ich jetzt?“**: 3 Vorschläge (Haiku, max. 30 min, nur Vorrat + Basics, höchstens 2 Zutaten fehlen → werden angezeigt mit „Zur Liste“). Tippen → Rezeptdetail, „Heute kochen“ setzt es in den heutigen Slot.
6. Nächster Wochenplan verbraucht diese Zutaten bevorzugt (über 60).

**Kosten:** ~0,1–0,2 ct pro Foto (Haiku Vision), Vorschläge ~0,05 ct.

**Abnahme:** Foto eines echten Kühlschranks erkennt ≥ 80 % der sichtbaren Lebensmittel (Stichprobe), Prüf-Bildschirm übernimmt korrekt, 3 Vorschläge ohne Einkauf möglich, nächster Plan nutzt mindestens 3 erkannte Zutaten.
