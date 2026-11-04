# Phase 20 – Woche per Swipe planen

Stand: 2026-11-04 · Quelle: Nutzerwunsch („Gerichte nicht direkt schreiben lassen, sondern wie bei Tinder durchswipen“).
Status: **aktiv** – Mockup freigegeben 2026-11-04, Backend (20.1/20.2) gebaut, iOS (20.3) als Nächstes.

## Idee

Statt dass die KI sofort eine fertige Woche schreibt, swipet der Haushalt durch einen Kartenstapel aus Gerichten der
aktuellen Angebote. Gemochte Gerichte werden danach automatisch auf die Woche verteilt oder selbst eingetragen.
Nebeneffekt: schneller. Eine Karte braucht nur Titel, Foto, Preis und Zeit. Das ganze Rezept (Zutaten, Schritte)
entsteht erst für die gewählten Gerichte, parallel.

## 0. Entscheidungen (2026-11-04, E97)

- [x] Karten: KI-Vorschläge aus den Angeboten **plus** eigene Rezepte (Favoriten, ≥ 4 ★, gerade günstig)
- [x] Familie swipet mit, **Match** = alle, die diese Karte gesehen haben, mögen sie; Matches kommen zuerst in den Plan
- [x] Alter Weg bleibt als **„Überrasch mich“** (KI plant die ganze Woche wie heute)
- [x] **Alle Mahlzeiten** werden geswipet (je Mahlzeitart ein Stapel: Frühstück, Mittag, Abend, Snack, Dessert, Lunchbox)
- [x] Zu wenig gemocht → **weiter swipen**: „Fertig“ erst, wenn jede Mahlzeitart genug Gerichte hat; der Stapel lädt nach
- [x] Gesten: rechts = diese Woche, links = diese Woche nicht, **oben = „Mag ich nicht“ mit Grund** (Zutaten mag ich nicht → Zutat wählen / Schmeckt mir einfach nicht / Keine Lust / Sonstiges, wie im Rezeptdetail seit 2026-11-04); dazu drei Knöpfe unter der Karte
- [x] Frühstück/Snack: ein gemochtes Gericht darf mehrfach in die Woche (Zähler auf der Karte „2×“)
- [x] Lunchbox: ein Stapel für alle, verteilt nur auf die Lunchbox-Tage
- [x] Vorlieben schon im Onboarding (20.4)
- [x] Swipen **nur in der iOS-App**; die Web-App zeigt weiter den fertigen Plan
- [x] **Erst Mockup, dann bauen** (anders als E91 in Phase 19)

## Ablauf

1. **Woche planen** → Stapel der ersten offenen Mahlzeitart. Oben je Art ein Fortschritt, z. B. „Abend 3/7 · Mittag 1/5“.
2. **Karte:** Foto, Titel, Preis pro Portion, Kochzeit, Anzahl Zutaten im Angebot, Laden. Antippen = Kurzbeschreibung.
3. **Wischen:** rechts / links / oben, mit Rückgängig für die letzte Karte. Oben = „Mag ich nicht“ → Grund (`DislikeDialog`): Zutat → „Mag nicht“-Liste; schmeckt nicht / Sonstiges → Nie-Liste (E96, unter „Ausgeblendet“ wieder holbar); keine Lust → nur diese Woche.
4. **Familie:** Jedes Mitglied sieht denselben Stapel und nur Karten, über die es noch nicht entschieden hat. Mögen zwei
   dasselbe → Match-Animation. „Nie wieder“ von einer Person nimmt die Karte für alle raus (Allergien, Abneigungen).
5. **Fertig** (sobald jede Art genug hat) → **Wochenübersicht**: gewählte Gerichte, Matches zuerst, überzählige als Reserve.
   - **Verteilen**: Code verteilt nach Regeln, kein KI-Aufruf. Frischfisch und Fleisch kommen früh in die Woche, Reste-Ketten (E19) und Abwechslungsregeln (Phase 11) gelten, und der Zufall entscheidet bei Gleichstand.
   - **Selbst eintragen**: Gerichte auf Tage ziehen, tauschen, Reserve einwechseln.
6. **Plan übernehmen** → ganze Rezepte für KI-Karten entstehen parallel → Preise, Reste, Einkaufsliste wie bisher.
7. **„Überrasch mich“** bleibt als kleiner Knopf auf dem Stapel-Screen (heutiger `POST /plans/job`).

## 20.0 Mockup + Spezifikation

- [x] Screens in `docs/ui/screens.md`: S41 Stapel, S42 Match, S43 Auswahl, S44 Woche verteilen (inkl. Laden, Leer, Fehler, „Stapel lädt nach“), Onboarding „Deine Gewohnheiten“, Angebote „Für dich“ (S45, S46)
- [x] HTML-Mockup [`docs/ui/mockups/swipe-v1.html`](../ui/mockups/swipe-v1.html): Karte, Gesten-Feedback (Stempel „Diese Woche“ / „Nicht“ / „Mag ich nicht“), Fortschritt je Mahlzeitart, Match, Verteilen per Ziehen
- [x] 👤 Mockup freigeben (2026-11-04: „Passt so, Pillen behalten“)

## 20.1 Backend: Kartenstapel

- [x] Tabellen `swipe_deck` (Haushalt, Woche, Stand offen/fertig), `swipe_card` (Deck, Mahlzeitart, Quelle ki/rezept, `recipe_id` bzw. Entwurf JSON, Reihenfolge), `swipe_vote` (Karte, Mitglied, ja/nein/nie, Zeit); Migration
- [x] KI-Karten: neues schlankes Schema `CardDraft` (Titel, Beschreibung, Küche, Zeit, Beilage, Protein, `image_query`, Haupt-Angebote mit Menge) → Kosten je Portion schätzt der Code aus den Angeboten; Haiku ohne Denkphase, mehrere Arten parallel
- [x] Eigene Rezepte mischen: Favoriten / ≥ 4 ★ / nicht in den letzten Wochen, nach Angebotsanteil sortiert; nie: Nie-Liste, Allergien/Ernährung (`forbid`)
- [x] Stapelgröße je Art = 2 × Plätze, Nachladen bei < 5 offenen Karten (eigener Hintergrund-Job wie E94); keine Titel-Dubletten im Deck; KI in parallelen Paketen à 3 mit Schwerpunkt (live 10–12 Karten in 5,0 s)
- [x] Fotos für Karten im Hintergrund (`_fill_image`), Karte erscheint sofort mit Teller-Platzhalter
- [x] API: `POST /swipe` (Deck der Woche anlegen/holen), `GET /swipe` (Karten, die dieses Mitglied noch nicht entschieden hat + Fortschritt + Matches), `POST /swipe/cards/{id}/vote`, `POST /swipe/undo`, `POST /swipe/more/{meal_type}`
- [x] Gewählt = ≥ 1 „ja“ und kein „nie“; Rang = Match (alle Abstimmenden ja) > Anzahl ja > Preis
- [x] Pro (E95): ein Deck zählt wie ein KI-Plan; Nachladen kostet nichts extra
- [x] Tests: Abstimmung mehrerer Mitglieder, Match, „nie“ blendet aus, Fortschritt, Nachladen, Dubletten

## 20.2 Backend: Verteilen + Plan erzeugen

- [x] `distribute(chosen, slots, rules)` im Code: Haltbarkeit (`shelf_days`), Abwechslung (`variety.check`), Reste-Ketten, Zufall bei Gleichstand; Test mit festem Seed
- [x] `POST /swipe/finish` mit Zuordnung `{Karte: (Tag, Art)}` (selbst eingetragen) oder leer (= verteilen) → Plan-Job (E94): KI-Karten → volle Rezepte (Prompt mit dem Kartentitel, parallel je Karte bzw. Tagesblock), eigene Rezepte direkt; dann `price`, Reste, Einkaufsliste wie `create_plan`
- [x] Reste-Badges und Budgetwarnung (S7) wie beim KI-Plan
- [x] Tests: Verteilung hält Regeln, selbst eingetragene Tage bleiben, Plan + Liste entstehen

## 20.3 iOS

- [ ] Stapel-Screen S41: Karten-Geste (rechts/links/oben, Schwelle + Haptik), Knöpfe ✗ / 👎 Mag ich nicht / ✓, Rückgängig, Fortschritt je Art, Art wechseln, „Überrasch mich“
- [ ] Match S42: Animation + „Weiter swipen“
- [ ] Auswahl S43 + Woche S44: Verteilen, Ziehen auf Tage, Reserve, „Plan übernehmen“ → Fortschritt wie heute (Abfrage `GET /plans/job`)
- [ ] Einstieg: „Woche planen“ auf Start/Plan führt zum Stapel; läuft ein Deck, geht es dort weiter
- [ ] VoiceOver: Aktionen „Diese Woche“, „Nicht“, „Nie wieder“ ohne Geste
- [ ] Demo-Fälle in `Demo.swift` + `ios/tools/screenshots.sh` (`swipe`, `match`, `verteilen`)
- [ ] Push an die anderen Mitglieder „Jona plant die Woche – swipe mit“ (APNs, sobald verfügbar)

## 20.4 Vorlieben (Onboarding, Planer, Angebote)

Heute: „Hafermilch statt Milch“ gibt es nur in den Einstellungen (19.2, `product_rules`), „isst gern“ nur als Favoriten
und Freitext-Wünsche. Neu:

- [ ] Onboarding-Schritt **„Deine Gewohnheiten“** (nach Ernährung/Allergien), überspringbar:
  - **Statt … nehme ich …**: Vorschlags-Chips (Hafermilch statt Milch, Vollkorn statt Weißmehl, Tofu statt Hackfleisch, laktosefrei, Skyr statt Joghurt …) + eigene Regel → `product_rules`
  - **Immer dabei** je Mahlzeitart: z. B. Frühstück „Müsli mit Hafermilch“, Snack „Apfel“ → neue Liste `staples` [{meal_type, name, tage}] (Haushalt bzw. Person)
  - **Esse ich gern**: Gerichte/Zutaten als Chips + Freitext → `likes` (Zutaten, Gerichte, Küchen)
- [ ] Einstellungen: dieselben drei Bereiche bearbeiten (Vorlieben-Screen erweitern)
- [ ] Planer + Swipe: `staples` füllen ihre Mahlzeiten direkt (kein KI-Aufruf, Karte vorab als „gemocht“ im Stapel); `likes` kommen in den Prompt und heben Karten nach vorn; `product_rules` wie bisher
- [ ] Angebote: Bereich **„Für dich“** oben – Angebote zu `staples`, `likes` und dem „use“-Teil der Regeln (z. B. Hafermilch im Angebot); Angebote zur „instead“-Seite (Kuhmilch) blass bzw. ans Ende
- [ ] Einkaufsliste: `staples` für die Woche automatisch drauf (Menge aus Tagen × Portion), mit Angebot, wenn vorhanden
- [ ] Tests: Regeln/Staples/Likes im Prompt, Staples belegen Slots ohne KI, „Für dich“-Auswahl

## Offene Punkte (geklärt 2026-11-04, Vorschläge angenommen)

- [x] Wer darf „Fertig“ drücken: jedes Mitglied oder nur, wer das Deck gestartet hat? (Vorschlag: jedes Mitglied)
- [x] `staples`/`likes` je Haushalt oder je Person? (Vorschlag: je Person, Planer fasst zusammen; Hafermilch gilt dann nur für die Portion dieser Person – oder für alle, wenn nur einer im Haushalt)

## DoD

- Ganze Woche per Swipe planbar (alle gewählten Mahlzeitarten), mit zwei Mitgliedern und Match getestet (Tests + iPhone)
- Erste Karten < 5 s nach „Woche planen“, Plan nach „Übernehmen“ < 60 s (gemessen in `params.seconds`)
- Verteilen hält Abwechslungs- und Reste-Regeln (Test), selbst eingetragene Tage bleiben unverändert
- „Überrasch mich“ funktioniert wie bisher
- Screens entsprechen dem freigegebenen Mockup (CI- bzw. iPhone-Screenshot)
