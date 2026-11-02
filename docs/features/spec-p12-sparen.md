# Phase 12 – Sparen

**Grundlage für 28/30/31/27/40:** Ein **Produkt-Schlüssel** fasst gleiche Produkte über Wochen zusammen: normalisierter Titel + Marke + Menge/Einheit (+ EAN, falls vorhanden) → `product` Tabelle; jedes Angebot zeigt auf ein `product`. Normalpreis = `regular_price` aus Prospekt, sonst Median der Nicht-Angebotswochen, sonst Schätzung.

---

## 28 · Preisverlauf ❗

**Ziel:** Bei jedem Angebot sehen, ob es wirklich günstig ist.

**Daten:** Tabelle `price_point` (product_id, chain, store_ref, week, price, regular_price, base_price, is_offer). Jeder Import schreibt Punkte; Start sofort ab Phase 8 (Daten sammeln). Zusätzlich Rückwirkung aus bereits gespeicherten Angeboten.

**UI (Angebotsdetail, neuer Abschnitt „Preisverlauf“):**
- Linien-/Stufendiagramm (Swift Charts) der letzten 12 Wochen pro Laden (Farbe = Laden), Angebotswochen als Punkte, Normalpreis als gestrichelte Linie, aktuelle Woche hervorgehoben, Antippen zeigt Wert.
- Urteil-Badge: **„🔥 Bestpreis“** (niedrigster Preis der letzten 12 Wochen), **„👍 Gutes Angebot“** (≥ 15 % unter Median), **„😐 Normal“**, **„⚠️ Kein echtes Angebot“** (≥ Median oder Rabatt nur auf Mondpreis).
- Text: „Zuletzt so günstig: KW 38 bei Lidl (1,79 €)“, „Im Schnitt alle 5 Wochen im Angebot“.
- Badges auch auf Angebotskarten (klein) und Filter „Nur echte Angebote“.

**Abnahme:** Produkt mit ≥ 3 Datenpunkten zeigt Diagramm und richtiges Urteil (Unit-Tests für Urteilslogik); ohne Historie „Noch zu wenig Daten (ab 3 Wochen)“.

---

## 30 · Prospekt-Vorschau nächste Woche ❗

**Daten:** Import holt auch Prospekte mit Gültigkeit ab nächstem Montag (kaufDA liefert sie meist ab Do/Fr/Sa). Angebote bekommen `valid_from` in der Zukunft → nicht in „Angebote“, sondern „Vorschau“.

**UI**
- Angebote: Pillen „Diese Woche · Nächste Woche“ (zweite mit Badge „neu“, sobald verfügbar).
- Start: Karte „👀 Nächste Woche günstiger“: Produkte, die du kaufen willst (Liste/Plan/Merkliste), die nächste Woche günstiger werden → „Hähnchenbrust nächste Woche −30 % bei Lidl (3,49 € statt 4,99 €) – Kauf verschieben?“ mit Aktion „Auf nächste Woche schieben“ (Artikel wandert in eine „Nächste Woche“-Gruppe der Liste).
- Plan-Generator: Option „Plan für nächste Woche“ (nutzt Vorschau-Angebote).

**Abnahme:** Ab Freitag sind Vorschau-Angebote sichtbar; Verschieben-Hinweis erscheint bei echtem Preisvorteil ≥ 10 %.

---

## 31 · Vorratskauf-Tipp ❗

**Ziel:** Bei starken Rabatten auf Haltbares mehr kaufen – aber nur so viel, wie realistisch verbraucht wird.

**Logik**
- Kandidaten: Kategorien Vorrat, Tiefkühl, Getränke, Drogerie, Haushalt + Produkte mit Haltbarkeit ≥ 3 Monate; Urteil aus 28 = Bestpreis/gutes Angebot; Rabatt ≥ 25 %.
- Verbrauch: aus Plänen/Listen der letzten 8 Wochen (Menge pro Woche), Basics (23), Verbrauchsrhythmus (58); ohne Historie konservativ (2 Packungen).
- Empfehlung: Menge = Verbrauch bis zum nächsten erwarteten Angebot (aus „im Schnitt alle N Wochen“, 28), gedeckelt auf 6 Monate und Vorratsplatz-Grenze (Einstellung: klein/mittel/groß).
- Ersparnis = (Normalpreis − Angebotspreis) × Menge.

**UI:** Start-Karte „💡 Vorrat anlegen lohnt sich“ (max. 3), Angebotsdetail-Abschnitt „Vorratstipp: 3 Packungen reichen ~6 Wochen, sparst 4,20 €“ mit Knopf „3× auf die Liste“; auf der Liste Badge „Vorratskauf“.

**Abnahme:** Nudeln −50 % bei 1 Packung/Woche Verbrauch und Angebot alle 6 Wochen → Tipp „6 Packungen“ (gedeckelt korrekt); keine Tipps für Frisches.

---

## 27 + 40 · Merkliste mit Alarm + Preisalarm für Zutaten

**Merkliste (Produkte)**
- Hinzufügen: Herz am Angebot; Barcode scannen (VisionKit `DataScannerViewController`, EAN → Open Food Facts → Name/Marke/Bild); Suche/Freitext.
- Pro Eintrag: Wunschpreis optional („Alarm unter 2,00 €“), Läden (alle/ausgewählte), Verbrauchsrhythmus (58).
- Abgleich nach jedem Import: Name/Marke-Ähnlichkeit (normalisiert, Token-Abgleich) + EAN wenn vorhanden; Treffer → Push (ntfy) „🧴 Dein Shampoo ist bei dm im Angebot: 1,79 € (−25 %)“ → öffnet Angebot; In-App: Badge am Angebote-Tab + Abschnitt „Diese Woche im Angebot“ in der Merkliste.
- Pro Treffer nur 1 Push pro Woche.

**Preisalarm für Zutaten (40)**
- Für Zutaten statt Produkte: „Butter unter 1,49 €“, „Hähnchenbrust unter 7 €/kg“ (Grundpreis-Alarm). Anlegen aus Rezept-Zutat (lange drücken → „Preisalarm“) oder Merkliste „+ Zutat“.
- Gleicher Abgleich/Push wie oben, aber über Zutat-Zuordnung + Grundpreis.

**UI:** S10 Merkliste (überarbeitet): Abschnitte „Diese Woche günstig“, „Beobachtet“, „Preisalarme“; Scanner mit Orange-Eckrahmen.

**Abnahme:** gescanntes Produkt erscheint, Treffer nach Import löst genau einen Push aus; Grundpreis-Alarm greift bei unterschiedlichen Packungsgrößen korrekt.

---

## 41 · Ein-Laden-Modus

- Plan-Generator: Schalter „Nur ein Laden“ + Logo-Auswahl der gewählten Läden.
- Planner bekommt nur Angebote dieses Ladens; Zutaten ohne Angebot = Normalpreis dieses Ladens; Einkaufsliste komplett diesem Laden zugeordnet.

**Abnahme:** Liste enthält nur noch einen Laden.

---

## 42 · Laden-Empfehlung

- Nach Plan/Liste: Rechnung aller Kombinationen aus max. 2 Läden (aus gewählten): Summe Angebote + Normalpreise.
- Karte im Einkauf-Tab: „🏆 Am günstigsten: alles bei Lidl 41,20 € · Rewe+Lidl 38,90 € (2,30 € gespart, +1 Laden)“; Entfernung aus Karte (Weg-Hinweis „+1,2 km“). Knopf „So aufteilen“ ordnet die Liste neu zu.

**Abnahme:** Rechnung stimmt mit Summen der Liste überein; Umverteilen ändert die Laden-Gruppen.

---

## 43 · Budget-Rest-Hinweis

- Nach Plan: Restbudget ≥ 5 € → Karte „💶 Noch 6,80 € übrig – wie wär's mit …“: 3 Ideen (Dessert, Snack, Vorratskauf aus 31) mit Kosten; antippen → einplanen bzw. auf die Liste.
- Über Budget → Karte „⚠️ 3,20 € über Budget – günstigere Alternative für Do?“ (würfelt teuerstes Gericht mit Kostengrenze).

**Abnahme:** beide Fälle erscheinen korrekt, Aktionen wirken.

---

## 49 · Nutri-Score, Bio, Vegan

- Quellen: Titel/Beschreibung („Bio“, „vegan“, „vegetarisch“, EU-Bio-Siegel-Text) + Open Food Facts (Suche nach Marke+Name, nur bei sicherem Treffer ≥ 0,8 Ähnlichkeit; EAN wenn vorhanden), Ergebnis am `product` gecacht.
- UI: kleine Badges auf Karten (Nutri-Score A–E in Originalfarben, 🌱 vegan, „Bio“), Filter-Pillen „Bio · Vegan · Nutri A/B“; im Detail Erklärung + Quelle.
- Planner: bei Ernährungsziel bevorzugt bessere Nutri-Scores (Hinweis im Prompt).

**Abnahme:** Stichprobe 30 Angebote: keine falschen Badges (lieber keins als falsch).

---

## 58 · Verbrauchsrhythmus Drogerie

- Merklisten-Eintrag (27) bekommt „Hält ca. X Wochen“ (Vorschlag aus Kategorie, änderbar) + „zuletzt gekauft“ (automatisch, wenn auf der Liste abgehakt).
- 2 Wochen vor „leer“: im Angebot → Push „Shampoo bald leer – gerade −25 % bei dm“; nicht im Angebot → „bald leer“ auf die Liste (Gruppe Drogerie) erst 3 Tage vorher.

**Abnahme:** simulierte Daten erzeugen die richtigen Hinweise zur richtigen Zeit.

---

## 59 · dm/Rossmann Monatsaktionen & Coupons

- Import dm (Suche) + Rossmann (Monatsprospekt) mit Gültigkeit bis Monatsende → eigener Abschnitt „Monatsaktionen“ unter Angebote (Filter Drogerie).
- App-Coupons von dm/Rossmann (aus deren Apps) gibt es nicht offen → über das Coupon-Wallet (38): Coupon fotografieren/eintragen, Partner dm/Rossmann, wird bei Drogerie-Merkliste und Liste angezeigt.

**Abnahme:** Monatsaktionen sichtbar bis Monatsende; dm-Coupon erscheint beim passenden Artikel.
