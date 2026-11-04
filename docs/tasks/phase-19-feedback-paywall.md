# Phase 19 – Nutzerwünsche, Lehren aus fremden Rezensionen, Paywall

Stand: 2026-11-04 · Quelle: Wunschliste des Nutzers + schlechte App-Store-Rezensionen einer Konkurrenz-App (Wochenplaner mit Abo).
Status: **aktiv** (2026-11-04). UI ohne Mockup-Freigabe direkt mit v3-Bausteinen (E91), Prüfung per CI-Screenshot.

## Was die Rezensionen lehren (Konkurrenz, 1–2 Sterne)

| # | Beschwerde | Bei uns heute | Folge für den Plan |
|---|---|---|---|
| R1 | Zutaten in der Zubereitung fehlen auf der Einkaufsliste; Mengen falsch (z. B. Limettensaft zweimal gebraucht, einmal gelistet) | Liste summiert, aber „Zwiebel“/„Zwiebeln“ oder stk/g werden nicht zusammengeführt; Schritte werden nicht gegen Zutaten geprüft | 19.5 |
| R2 | Liste nicht auf den gewählten Laden angepasst, Produkte gibt es dort gar nicht, Packungsgrößen falsch (900 g vorgeschlagen, Laden hat 1,1 kg) | Liste zeigt Bedarf, nicht Packungen; Planer-KI darf jedes Angebot jeder Zutat zuordnen, ohne Prüfung | 19.1, 19.5 |
| R3 | Preise unrealistisch niedrig | Packungspreise werden nur für die Laden-Empfehlung gerechnet | 19.5 |
| R4 | Immer die gleichen Rezepte | Abwechslungsregeln existieren | 19.3 (Richtung beim Neu-Würfeln) |
| R5 | Einheiten englisch (tsp/tbsp), Rezepte teils englisch | Planer nutzt g/ml/stk, Import rechnet um; englisch sichtbar nur USDA-Zeile | 19.5 (TL/EL überall), 19.1 |
| R6 | Wochenplan beim Spielen in den Einstellungen plötzlich weg | „Aktueller Plan“ = neuester Plan egal welcher Woche; Plan für nächste Woche ersetzt den laufenden | 19.3 |
| R7 | Eigene Allergie nicht eintragbar (nur feste Liste) | iOS: feste Chips; Allergien nur als Text im KI-Prompt, kein Code-Check | 19.2 |
| R8 | Mindestbudget 65 €/Woche zu hoch für Studierende | Regler 20–200 €, aber kein Hinweis, ob realistisch | 19.7 |
| R9 | Erst alle Daten eingeben, dann Paywall („Quizmaster“); Preis klein versteckt; „als kostenlos gelistet“ | – | 19.7, 19.8 |
| R10 | Abbuchung nach Testphase ohne Erinnerung | – | 19.8 |
| R11 | Familienabo: Partner wird rausgeworfen, Paywall nicht schließbar | Haushalte mit Mitgliedern existieren | 19.8 (Abo je Haushalt, serverseitig) |
| R12 | App bettelt um Bewertung | – | 19.8 |
| R13 | Wunsch: Meldefunktion für falsche Gerichte | Nur Sterne + „Nie“ | 19.9 |
| R14 | Wunsch: Apple-Erinnerungen | Nur Text-Teilen, Web-Liste, Live-Aktivität | 19.5 (optional) |
| R15 | Rezept nach 1-Stern-Bewertung nicht mehr auffindbar | „Nie“-Liste blendet aus | 19.9 |

## 0. Entscheidungen (2026-11-04, E90/E91)

- [x] Kommerziell, App Store: ja → kommerziell nutzbare Angebots-API suchen
- [x] Gratis + Pro; Pro wahlweise mit Werbung oder Abo
- [x] Abo 3 €/Monat
- [x] Alle Pakete jetzt umsetzen, Phase 18 ruht (Design ändert sich noch)
- [x] Recherche Angebots-APIs → [`docs/research/angebots-apis-kommerziell.md`](../research/angebots-apis-kommerziell.md): keine offene API; Empfehlung Shopfully (Publisher-Vertrag), parallel Bonial + marktguru
- [ ] 👤 Anfragen an Shopfully / Bonial / marktguru schicken (Claude entwirft die Texte); bis Vertrag: kaufDA nur privat
- [ ] (C) Aufteilung: **Gratis** = Angebote, Liste, eigene Rezepte, 1 KI-Plan je Woche · **Pro** = weitere Pläne, Neu würfeln mit Richtung, Kühlschrank-Foto, Instagram-Import, Schritt-Bilder, „Keine Lust“, Ersatzzutaten, Preisalarme. Werbung = ein Video je Pro-Nutzung

## 19.1 Angebote fixen (Daten, denen man trauen kann)

- [x] Feinere Kategorien statt 7 grober (Joghurt ≠ Käse, Milch, Süßes, Snacks, Saucen, Tiefkühl …); Testliste mit den bekannten Fehlgriffen („Milchschokolade“, „Tomatensauce“, „Kartoffelchips“, „Pizza Salami“, Joghurt → Käse)
- [x] Erkennung: kaufDA-Produktkategorie (Nicht-Lebensmittel raus) → Stichwörter im Namen → in der Beschreibung → Haiku einmal je Titel (`importer.classify_unknown`, Kosten `ai_cost` kind classify)
- [x] Planer: zugeordnetes `offer_id` im Code gegen die Zutat prüfen (Name/Kategorie passt); passt nicht → Angebot verwerfen, Normalpreis
- [x] Namens-Abgleich `matching.py`: „Käse“ darf nicht „Frischkäse“-Angebote für jede Käse-Zutat liefern (Wortende-Regel schärfen + Tests)
- [x] Nur Produkte aus den gewählten Läden: war schon so (Angebote nur der Haushalts-Filialen, Zutaten ohne Angebot sind generisch „Überall“)
- Abnahme: Fehlgriff-Testliste grün ✓; Stichprobe 100 echte Angebote (KW 45): 2 Fehler (Lachsbraten, Lamm-Lachs → behoben) ✓
- [ ] 👤 „Joghurt als Cherrygold-Käse“ lokal nicht nachstellbar (Daten liegen auf dem VPS): wo genau gesehen? (Angebote-Liste, Plan-Zutat, Einkaufsliste?)

## 19.2 Präferenzen, „mag ich nicht“, Allergien

- [x] **Produkt-Regeln** je Haushalt: „immer X statt Y“ (`household.product_rules`, Einstellungen › Präferenzen › „Immer statt“); Planer bekommt sie als Regel und der Code benennt Zutaten danach um (`planner.apply_rules`), Liste folgt dem Plan. „nie X“ = „Mag nicht“. „nur Marke/Bio“ weggelassen (nicht verlangt)
- [x] **„Mag ich nicht“**: Zutat lange drücken im Rezept → Abneigungen; Gericht: Würfel › „Mag ich nicht – nie wieder vorschlagen“ (Bewertung „nie“ + neues Gericht)
- [x] Allergien: feste Chips **plus freie Eingabe** (Präferenzen; Onboarding folgt mit 19.7)
- [x] Code-Prüfung nach der KI: Gerichte mit Allergenen/Abneigungen/„nie“-Zutaten werden verworfen und neu erzeugt (`substitutes.forbidden` wiederverwenden), nicht nur Prompt-Text
- [x] **Kalorien fixen:** echte Pläne nachgerechnet → Fehlzuordnungen (Tortilla = Backmischung, Dosenbohnen = getrocknet, 2,5× kcal). Prompts korrigiert, unsichere/betroffene Zuordnungen per Migration neu, Nährwert-Abruf ordnet Fehlendes nach; Stück ohne Gewicht zählt 100 g statt den Tag leer zu lassen. ml ≈ g bleibt (Abweichung < 10 %)
- Abnahme: Testhaushalt mit Hafermilch-Regel + freier Allergie → 5 Pläne ohne Verstoß; kcal je Tag innerhalb ± 15 % des Ziels

## 19.3 Einzelne Gerichte neu generieren, Plan nie verlieren

- [x] „Neu würfeln“ mit Richtung: schneller · günstiger · ohne Fleisch · anderes Gericht · eigener Wunsch (Text); neues Gericht läuft durch Allergie- und Abwechslungsprüfung
- [x] Rückgängig nach dem Würfeln (Toast „Rückgängig“, `POST /plans/current/entries/{id}/undo`) und nach einem neuen Plan (`POST /plans/current/undo`)
- [x] Plan nie verlieren (R6): aktueller Plan = zuletzt aktivierter (`meal_plan.active_at`), alte Pläne bleiben gespeichert und kommen per „Rückgängig“ zurück. Plan für nächste Woche bleibt bewusst der aktuelle (Einkauf am Wochenende)
- [x] Einstellungen ändern nie den bestehenden Plan (geprüft: `PATCH /household`); „neu einrichten“ fragt jetzt nach
- Abnahme: Test „Plan nächste Woche erzeugen“ lässt den laufenden Plan + Liste unverändert

## 19.4 Angebote: Laden wählen, nach Kategorien filtern

- [x] Laden-Leiste sichtbar oben im Angebote-Screen (Logos wie S5, „Alle“ + je Laden), nicht im Filter-Sheet versteckt
- [x] Kategorie-Chips + zweite Reihe mit feinen Kategorien aus 19.1, kombinierbar mit Laden; Nicht-Lebensmittel ausgeblendet
- [x] Auswahl merken (`@AppStorage`)
- [x] ~~Mockup~~ entfällt (E91); CI-Screenshot am Ende von Phase 19

## 19.5 Einkaufsliste = Rezept, in Packungen des Ladens

- [x] Zusammenführen über den normalisierten Zutatenschlüssel (Singular/Plural, Einheiten umrechnen) – `stock_key`, kg/l → g/ml (E93)
- [x] Prüfung: jede in den Schritten genannte Zutat steht in der Zutatenliste (KI-Ausgabe im Code prüfen, sonst nachfordern) (R1) – `planner.unlisted`, an 120 echten Rezepten: 2 echte Lücken, 1 Fehlalarm
- [x] Liste zeigt **Packungen** des gewählten Ladens („1 × 1,1 kg Hähnchenschenkel, 900 g gebraucht“), Rest geht in den Vorrat (R2) – iOS + Web
- [x] Plan-Kosten = Packungspreise, nicht anteilige Preise (R3) – war schon so; doppelte Packungen durch „Zwiebel/Zwiebeln“ behoben
- [x] Einheiten überall deutsch: TL, EL, Prise, Bund, Dose; nie tsp/tbsp – Schemas lassen nur deutsche Einheiten zu; Web zeigte „el“, jetzt „EL“
- [ ] (optional) Export in Apple Erinnerungen per EventKit (R14) – 👤 sagen, ob gewünscht
- Abnahme: 3 echte Pläne nachgezählt, keine fehlende Zutat, Packungen passen zum Laden

## 19.6 Performance

- [ ] App-Start: `loadAll` parallel statt ~10 Anfragen nacheinander; Cache sofort anzeigen
- [ ] Plan erzeugen als Hintergrund-Job mit Fortschritt (Status abfragen), statt 1 Anfrage bis zu 300 s
- [ ] Bildsuche nie im Anfrage-Pfad (auch beim Neu-Würfeln)
- [ ] KI-Aufrufe zusammenlegen: Reparatur-/Zweit-Durchgang nur wenn nötig, Prompt-Cache besser nutzen
- [ ] Messen vorher/nachher (Startzeit, Plan-Dauer) und im Playbook festhalten
- Abnahme: Start mit Cache < 1 s bis Inhalt, Plan < 30 s im Mittel

## 19.7 Besseres Onboarding

- [ ] Server-Adresse aus dem Willkommens-Screen raus (fest, nur versteckt für Entwicklung)
- [ ] Weniger Fragen am Anfang: PLZ, Läden, Personen – Rest (Ziele, Küchen, Allergien) später/optional; erst Wert zeigen (Angebote der Woche), dann fragen (R9)
- [ ] Budget: realistische Spanne je Person anzeigen („für 2 Personen meist 40–70 €“), niedrige Budgets erlaubt, aber mit ehrlichem Hinweis statt Sperre (R8)
- [ ] **Preis/Abo vor dem ersten Dateneingeben zeigen**, nicht danach (R9)
- [ ] Mockup Onboarding 1–4 → 👤 Freigabe → Bau

## 19.8 Paywall (nach Entscheidung 0)

- [ ] Spike: StoreKit 2 mit xtool bauen, Sandbox-Kauf auf dem iPhone; Upload zu TestFlight über den macOS-Runner (GitHub Actions)
- [ ] App-Store-Connect: Abo-Produkte anlegen 👤 (Bankdaten, Steuer, Verträge macht der Nutzer)
- [ ] Abo gilt **je Haushalt**, Prüfung serverseitig (App Store Server API / signierte Transaktionen) → alle Mitglieder + Web-PWA freigeschaltet, kein Rauswerfen (R11)
- [ ] Paywall immer schließbar; Freemium-Grenzen klar, Preis groß, „Abo jederzeit in den iOS-Einstellungen kündbar“ (R9)
- [ ] Testphase: eigene Push-Erinnerung 2 Tage vor Ende mit Preis und Kündigen-Link (R10)
- [ ] Bewertungs-Abfrage nur über `SKStoreReviewController`, höchstens nach einem Erfolgsmoment (z. B. 3. gekochtes Gericht), nie im Onboarding (R12)
- [ ] App-Store-Text: „Kostenlos laden, Plus-Abo optional“ statt „kostenlos“
- [ ] KI-Kosten je Haushalt (`ai_cost`) gegen Abo-Preis prüfen, Grenzen für Gratis-Nutzer festlegen
- [ ] Mockup Paywall + Abo-Verwaltung → 👤 Freigabe → Bau

## 19.9 Melden & Qualität

- [ ] „Fehler melden“ am Gericht/Rezept (Zutat fehlt, Menge falsch, Angebot falsch, Schritt unklar) → Tabelle im Backend + Übersicht für den Entwickler
- [ ] Gemeldete Angebots-Fehlzuordnungen fließen in die Testliste von 19.1
- [ ] 1-Stern-/„Nie“-Rezepte bleiben unter „Ausgeblendet“ auffindbar und wiederherstellbar (R15)

## DoD

- Alle Abnahmen oben erfüllt, Tests grün, CI-Screenshots neben freigegebenen Mockups
- Rezensions-Tabelle: jede Zeile R1–R15 ist erledigt oder bewusst verworfen (Grund dahinter)
- Neue Entscheidungen im Playbook (E90 ff.)
