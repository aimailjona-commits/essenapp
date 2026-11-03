# Essenapp – Playbook

Arbeitsgrundlage für die Entwicklung. Enthält Ziele, Entscheidungen, Architektur, Datenmodell, Phasen und Arbeitsregeln.
Wird bei jeder Entscheidung aktualisiert (Abschnitt „Entscheidungslog“).

Stand: 2026-11-03

---

## 1. Vision

Eine iOS-App, die die Prospekte der gewählten Supermärkte und Drogerien für die aktuelle Woche auswertet und daraus einen Wochenplan mit Gerichten, Kosten, Nährwerten und Einkaufsliste erstellt. Zusätzlich: Alarme für Lieblingsprodukte, die irgendwo im Angebot sind.

Nutzer: der Entwickler selbst (iOS-App) + Familie/Freunde (Web-Version).

---

## 2. Entscheidungslog

| # | Entscheidung | Begründung / Folge |
|---|---|---|
| E1 | Build mit **xtool** unter **WSL (Ubuntu 24.04)**, kein Mac/Xcode | Keine Simulatoren, Tests direkt auf dem iPhone |
| E2 | **Kostenlose Apple-ID** | App läuft 7 Tage, dann `xtool dev` erneut. Kein APNs-Push, kein iCloud/CloudKit |
| E3 | Zielgruppe **Familie/Freunde**, kein App Store | Inoffizielle Datenquellen vertretbar, trotzdem schonend nutzen |
| E4 | **Option 2:** iOS-App für den Entwickler, **Web-Version (PWA)** für Familie | Teilt sich Backend und Daten. Kein Signier-Problem für andere |
| E5 | **Eigenes Backend**, zuerst lokal in WSL, später VPS | Sammelt Angebote, erzeugt Pläne, hält API-Keys, Sync & Sharing |
| E6 | Rezepte: **KI-generiert + eigene Rezepte** | KI plant rund um Angebote, gespeicherte/bewertete Rezepte werden bevorzugt eingebaut |
| E7 | PLZ/Filialen, Läden, Haushaltsgröße sind **konfigurierbar** | Pro Haushalt in den Einstellungen, nichts hartkodiert |
| E8 | Nutzer muss SwiftUI-Code nicht verstehen | Claude schreibt den iOS-Code eigenständig; Erklärungen nur zu Dingen, die der Nutzer selbst tun muss |
| E9 | ~~Benachrichtigungen über **ntfy** + lokale Notifications~~ → ersetzt durch E52 (APNs) | Ersatz für APNs (E2) |
| E10 | Nährwerte werden **berechnet**, nicht von der KI geschätzt | Zutatendaten aus Open Food Facts / BLS, KI liefert nur Mengen |
| E11 | **PonyTail** (`.claude/skills/ponytail`, Stufe `full`) bei jeder Coding-Aufgabe, auch in Subagents | Als Projekt-Skill eingebunden statt als Plugin: keine fremden Hooks, gilt in jeder Sitzung |
| E12 | UI wird vor dem Bauen vollständig spezifiziert (`docs/ui/`), Phase 0 | Stil „hell & natürlich“: Referenz 01/02, Angebote wie 08, Listen wie 07 |
| E13 | Rezeptbilder: **KI-generiertes, freigestelltes Tellerfoto von oben**, einmal pro Rezept erzeugt und gespeichert | Bild-API im Backend nötig (Anbieter in Phase 3 wählen), Kosten wenige Cent pro Rezept |
| E14 | Mittel-Button der Tab-Bar öffnet **Schnell-Aktionen** (Plan erstellen, Scannen, Zur Liste, Rezept anlegen) | |
| E15 | **Nur heller Modus** in v1, erzwungen per `UIUserInterfaceStyle=Light` + `.preferredColorScheme(.light)` | Ohne Erzwingen wurde Systemtext im Dark Mode weiß auf hellem Grund. Dark Mode später möglich, da alle Farben Tokens sind |
| E16 | **Autonomer Modus** (2026-11-02): Claude arbeitet ohne Rückfragen weiter, entscheidet Offenes selbst mit der empfohlenen Option. Solche Entscheidungen sind mit **(C)** markiert und jederzeit änderbar | Nutzer ist nicht erreichbar. 👤-Schritte bleiben offen, Claude arbeitet an allem, was nicht blockiert ist |
| E17 (C) | Rabatt-Farbe bleibt Orange-Rot (`deal`); Limettengrün bedeutet „ok / im Vorrat / erledigt“ | Klare Trennung: Rot = Angebot, Grün = erledigt |
| E18 (C) | Einkaufslisten in sanften Pastelltönen aus fester Palette, in Reihenfolge der Läden vergeben (keine Markenfarben) | Keine Händler-Branding-Nachahmung |
| E19 (C) | Blüten-Diagramm zeigt Anteile nach **Gewicht**; Kosten stehen in der Zutatenliste | Entspricht Referenz 01 |
| E20 (C) | Wochenplan liegt im Tab „Rezepte“ (Umschalter Wochenplan / Meine Rezepte), zusätzlich über Start erreichbar | |
| E21 (C) | Arbeitstitel **„Essenapp“**, Bundle-ID `de.jsenf.essenapp`; Anzeigename später änderbar | Bundle-ID sollte danach nicht mehr wechseln |
| E22 (C) | Schrift: System-Schrift SF Pro (iOS), Inter/Systemschrift im Web | Keine Schrift-Einbindung, beste Barrierefreiheit |
| E23 | ~~iPhone ↔ WSL über usbipd~~ → ersetzt durch E33 (Installation hing) | Einmalig `usbipd bind --busid <ID>` (Admin). Danach je Sitzung: WSL muss laufen, dann `usbipd attach --wsl --busid <ID>` (BUSID mit `usbipd list`, Apple = `05ac:…`). Gerät ist dann nur noch in WSL sichtbar. Prüfen: `idevice_id -l` |
| E24 | iOS wird in **`~/build/essenapp-ios` (WSL-Dateisystem)** gebaut, Quellen bleiben in `ios/` | xtool scheitert auf `/mnt/c` an Datei-Umbenennungen („Permission denied“). `ios/build.sh` kopiert per rsync und ruft `xtool dev` auf |
| E25 | **Kein SwiftData** (Makro-Plugin `SwiftDataMacros` fehlt unter xtool, getestet). Lokaler Cache als Codable-JSON-Dateien | Backend ist die Quelle der Wahrheit; GRDB nur, falls später echte lokale Abfragen nötig werden |
| E26 | App-Icon über `iconPath: Icon.png` in `xtool.yml` (erzeugt von `ios/tools/make_icon.py`), Info.plist-Ergänzungen über `infoPath` | Bekannte xtool.yml-Keys laut Binary: version, bundleID, product, infoPath, iconPath, entitlementsPath, resources, extensions, minimumVersion, skipLSP |
| E27 | Backend-venv liegt in WSL (`~/.venvs/essenapp-backend`), Aufruf über `backend/dev.sh` | Python-Importe von `/mnt/c` sind ~10× langsamer |
| E28 | Erste Datenquelle: **kaufDA** (ein Adapter für Rewe, Lidl, Kaufland, Penny, Netto, Edeka, Rossmann, Aldi Süd, dm). Details: `research/datenquellen.md` | Ohne Login/Bot-Schutz, live getestet (Köln: 1.067 Angebote für Rewe+Lidl+Aldi Süd). Direkte Adapter (Aldi Nord, Penny, Kaufland) später, wo Daten besser sind |
| E29 | PLZ → Koordinaten über OpenStreetMap Nominatim, einmal pro Haushalt gespeichert. Rewe/Edeka: nächster Markt aus kaufDA wird automatisch als Filiale gesetzt | Filialwahl in der App folgt (S6/S13) |
| E30 | KI-Modell: `claude-opus-5-5` (Standard laut Claude-API-Referenz), Effort `medium`, Server-Fallback bei Ablehnung (`fallbacks: "default"`). Per `.env` änderbar (`MODEL_PLANNER`, `PLANNER_EFFORT`) | Günstigere Modelle sind Nutzerentscheidung. E2E: 3 Gerichte in 34 s |
| E31 | shortcut: Rezept-Zutaten als JSON am Rezept; Einkaufsliste wird in der App aus dem Plan berechnet und lokal abgehakt | Umbauen, wenn Zutaten-Stammdaten (Nährwerte) bzw. gemeinsame Liste (Phase 4) kommen |
| E32 | Wöchentlicher Import ohne Scheduler-Bibliothek: `./dev.sh python -m app.jobs` per cron (Phase 7) | Kein zusätzlicher Dienst nötig |
| E33 | **iPhone hängt an Windows (App „Apple Devices“), nicht mehr per usbipd an WSL.** WSL spricht Apples usbmux-Dienst über `<WSL-Gateway>:27015` an (`USBMUXD_SOCKET_ADDRESS`, setzt `ios/build.sh`). Backend fürs iPhone über `<Windows-IP>:8000` | Mit usbipd hing `xtool dev` bei „Connecting“ (xtool Issue #19). `tools/windows-setup.ps1` (Admin, nach jedem Neustart) richtet Portproxys + Firewall ein. Ersetzt E23 |
| E34 | **UI-Debugging ohne Nutzer:** (1) Cloud-Simulator: GitHub Actions (`.github/workflows/ios-screenshots.yml`, macOS-Runner) baut die App, startet jeden Screen im Demo-Modus (`-demoScreen <name>`, Beispieldaten in `Demo.swift`) und lädt Screenshots als Artefakt hoch. (2) Echtes iPhone: `tools/iphone-shot.ps1` (pymobiledevice3; Nutzer muss `python -m pymobiledevice3 remote tunneld` als Admin laufen lassen) | Kein iOS-Simulator unter Windows/Linux. Repo öffentlich: github.com/aimailjona-commits/essenapp. Händler-Fixtures und `.debug/` sind nicht versioniert |
| E35 | Läden in der Nähe aus OpenStreetMap Overpass (`GET /stores/nearby`, 24 h im Speicher gecacht). Rewe/Edeka mit Kartenposition: kaufDA-Shelf an der Filiale abfragen, `closestStore` = Markt-ID. Ersetzt die Auto-Filiale aus E29 für Filialen mit Koordinaten | Kette über `brand`/`name`-Tag; „ALDI“ ohne Süd/Nord und Netto (Scottie) werden ignoriert |
| E36 | **Design v2 (Nutzerwunsch: cleaner, moderner, mehr Farbe, viele Animationen):** heller Grund `#F5F4F0`, reinweiße Karten mit Haarlinie + leichtem Schatten, SF Pro Rounded für Überschriften/Zahlen, Markenfarbe Basilikum-Grün `#22B573` + Limette als Akzent, Farbe + Emoji pro Kategorie und Laden, Animationen (gleitende Auswahl, Feder-Tippen, Zahlen-Übergänge, Schimmer, Haptik). Werte: `ios/Sources/Essenapp/Theme.swift`, Doku `docs/ui/design-system.md` | Ersetzt die Farbwerte aus E12/E17. Die HTML-Mockups v1 bleiben als Layout-Referenz; der aktuelle Stand wird über die Simulator-Screenshots geprüft (E34) |
| E37 | Overpass-Abfrage mit Rückfall auf offizielle Mirrors (kumi.systems, private.coffee) | Am 02.11.2026 waren alle drei Instanzen gestört (502/Timeout); App zeigt dann Fehler + „Erneut versuchen“ |
| E38 | **Läden in der Nähe aus dem kaufDA-Shelf** (`closestStore` je Prospekt, alle Seiten, 24 h gecacht), `osm_id` = `kaufda/<chain>/<externalId>`. Overpass nur noch, wenn kaufDA nichts liefert (max. 10 s). Beim Import wird die externalId direkt `store_ref` (Rewe/Edeka), regionale Ketten bleiben `""` | Overpass war stundenlang gestört. Limit: kaufDA liefert pro Prospekt nur die nächste Filiale, also meist 1 Laden je regionaler Kette; ALDI SÜD ohne Filialdaten. Ersetzt E35/E37 als Hauptquelle |
| E39 | **KI-Kosten:** Planer-Modell `claude-haiku-5-5` (Nutzerentscheidung), Effort `low`, kein Server-Fallback (nur Opus/Sonnet). Prompt: max. 120 Lebensmittel-Angebote (reihum je Kategorie, Rabatt zuerst), Angebotsblock mit `cache_control` vor dem variablen Teil; 1 Budget-Korrekturrunde. Verbrauch je Plan in `params["usage"]`, `GET /usage`. `POST /plans` nimmt optional `PlanOptions` (nur für diesen Plan, `save_as_default`) | Nutzer hatte ~5 € verbraucht. Kiel: Prompt 51.918 → 3.654 Tokens; 1 Gericht ≈ 0,09 ct, Reroll aus dem Cache ≈ 0,04 ct. Ersetzt E30 |
| E40 | **Teilen (Nutzerwunsch, Entscheidung „Web-Link“):** Einladungscodes (`invite`, 8 Zeichen `secrets.token_urlsafe`, 7 Tage gültig, mehrfach nutzbar): `POST /household/invites` → `/join/<code>`, `GET /household/share` → `/h/<code>` (Plan-Vorschau + Beitritt). Mitglieder: `GET/DELETE /household/members` (Entfernen nur owner). **Gemeinsame Einkaufsliste im Backend** (`shopping_list` household|oneoff, `shopping_item` mit `added_by`/`checked_by`/`source` plan|manual): genau eine Haushaltsliste, `POST /plans` und Neu würfeln rufen `sync-plan` (Zutaten ohne Vorrat, summiert je offer_id bzw. Name+Einheit, Plan-Einträge werden aktualisiert/entfernt, Haken und manuelle Einträge bleiben). Einmalige Listen mit `share_code` für Gäste ohne Konto (`/shared/<code>`, Name per `?guest=`). **Web-Version** `backend/app/web` (Jinja + HTMX 1.9.12 per CDN, PWA-Manifest): `/join/<code>` → Token als HttpOnly-Cookie (SameSite=Lax) → `/app` (Wochenplan, Liste nach Laden, Abhaken ohne Reload, Polling alle 10 s); Gäste unter `/l/<code>` (Name im localStorage) | Andere haben keine iOS-App. Ersetzt das lokale Abhaken aus E31; iOS muss auf `/lists` umgestellt werden. Polling statt WebSocket reicht für gemeinsames Einkaufen |
| E41 | Rezeptfotos: erst frei (TheMealDB, dann Openverse), KI (fal.ai FLUX schnell) nur mit `FAL_KEY`. KI liefert dafür `image_query` (englisch). Treffer werden in `backend/image_cache.json` gecacht | Nutzerentscheidung „erst frei, dann KI“. Ohne `FAL_KEY` bleiben exotische Gerichte ohne Foto (Teller-Platzhalter). Openverse war am 02.11. nicht erreichbar |
| E42 | `store_ref` = kaufDA-Filial-ID für **alle** Ketten (nur Such-Ketten wie ALDI SÜD/dm: `plz:<plz>`); je Kette wird nur die gewählte Filiale geladen | Behebt Vermischung von Angeboten verschiedener Städte (korrigiert die Aussage „regional = \"\"“ aus E38) |
| E43 | **Design v3** nach Nutzer-Vorlagen (DashBite, Pizza Mojo, Spring Vibes, Grilled Chicken): grauer Grund, weiße Karten, Schwarz + Orange `#FF5B2E`, Mischgewicht-Titel, große Fotos (Pexels, `ios/Sources/Essenapp/Resources/hero`, CREDITS.md), Pillen-Umschalter, dunkler Angebots-Kopf | Ersetzt Farben aus E36 |
| E44 | Tab-Leiste mit **Liquid Glass** (`glassEffect`, iOS 26), Fallback dunkle Kapsel. Offizielle Händler-Logos als Wikimedia-Thumbnails, nur verlinkt (nicht im Repo) | Nutzerwunsch; Logos sind PD-textlogo, aber Marken – daher nicht weiterverbreitet |
| E45 | **Feature-Roadmap Phasen 8–16** (44 Features, Nutzerauswahl 2026-11-02), Spezifikationen in `docs/features/`, Annahmen A1–A12 dort zur Bestätigung | Ziel: 100 % wie spezifiziert; Abweichungen nur nach Rückfrage |
| E46 | **Profile & Vorrat (48/60, Backend):** `member_profile` je Mitglied (emoji, goal, kcal 1000–5000, protein_g 0–400, allergies, dislikes, lunchbox_days, eats `{meal_type: [Mo..So]}`), beim ersten `GET /me/profile` bzw. `GET /household/profiles` aus Haushaltswerten angelegt (kcal/Protein-Vorschlag aus dem Ziel). Planner: Esser je Slot = Mitglieder mit eats an; Faktor = kcal/2000 auf 0,25; Mengen für die Summe (`portionen=` je Slot im variablen Prompt-Block); Slot ohne Esser entfällt; Fallback `household.persons` bei < 2 Mitgliedern oder ohne Profile. Allergien/Ausschlüsse = Vereinigung Haushalt + alle Profile. Plan-Eintrag speichert `portions [{member_id, factor}]` + `portions_total` (0 = alter Plan → `recipe.servings`). `pantry_item` (ingredient_key = kleingeschriebener Name ohne Mehrfach-Leerzeichen, Einheit g/ml/stk/leer): Basics `amount` null = vorhanden, 0 = leer gemeldet → Haushaltsliste (source `basics`). Pricing/`sync_plan` über `Stock`: Basic (auch Kompositum wie „Olivenöl“ → „Öl“) vor Vorratsmenge gleicher Einheit vor KI-`in_pantry` (nur noch Fallback ohne Vorrats-Eintrag); Teilmengen anteilig. `POST /pantry/consume` zieht ab (bald ablaufende zuerst, ≤ 0 → gelöscht). Abhaken liefert `pantry_suggest` (source basics, Angebots-Kategorie vorrat oder Begriffsliste haltbarer Sachen), `POST /items/{id}/to-pantry` addiert gleiche Zutat+Einheit (l/kg → ml/g). Standard-Basics: Salz, Pfeffer, Öl, Zucker, Mehl, Essig, Gemüsebrühe (neue Haushalte + Migration für bestehende) | Spezifikation `spec-p08-fundament.md`; `portions_total` zusätzlich, damit iOS „Deine Portion“ = Menge × factor / portions_total auch im Fallback rechnen kann |
| E47 | **Push + Scheduler lokal (bis zum VPS):** ntfy JSON-Publish (`POST <NTFY_URL>/`, Felder topic/title/message/click/tags/actions/delay, Timeout 10 s, Fehler nur geloggt) über `app/services/push.py`; `NTFY_URL` Standard `https://ntfy.sh`. Pro Mitglied `ntfy_topic` (`secrets.token_urlsafe(24)` = 32 Zeichen, Migration füllt bestehende) + Einstellungen `push_enabled`, `plan_prompt_enabled`, `plan_prompt_weekday` (0 = Mo, Standard 6), `plan_prompt_time` (Standard 18:00), `quiet_hours` `{start, end}` oder null (Standard 22:00–07:00): `GET /me/push` (`ntfy_url, topic, subscribe_url` = `ntfy://<host>/<topic>`, `subscribe_url_https`), `POST /me/push/test` (204, click `essenapp://start`, 502 wenn ntfy scheitert), `GET/PATCH /me/push/settings`. **Scheduler** `app/jobs.py`: `SCHEDULER=1` (setzt `dev.sh serve`) startet beim App-Start einen Daemon-Thread, der jede Minute `tick()` ruft; Zeiten Europe/Berlin; Termin = letzter Zeitpunkt ≤ jetzt, fällig wenn kein `job_run` seit dem Termin und höchstens 12 h verpasst (PC aus → wird nachgeholt). Lauf wird **vor** dem Start in `job_run` (name, ran_at UTC, ok, info) eingetragen → keine Doppelausführung, auch nach Neustart; Fehlschläge werden erst zum nächsten Termin wiederholt. Zeitpläne per `JOB_SCHEDULES` (JSON, z. B. `{"import_offers": "Sa 22:00, Mo 06:00"}`). Jobs: `import_offers` (Sa 22:00, Mo/Mi 06:00, `refresh_household` für alle Haushalte mit PLZ; Folgewoche kommt mit, weil kaufDA-Shelf ohne Datumsfilter übernommen wird), danach `price_history`/`watch_alarms`; `plan_prompt` pro Mitglied (Name `plan_prompt:<id>`) „🍽️ Neue Woche – sollen wir deinen Plan für KW xx erstellen?“ (KW: ab Freitag die nächste), click + Aktion „Plan erstellen“ `essenapp://generator`, „Später“ schließt nur (GET `<NTFY_URL>/v1/health`), Erinnerung automatisch nach 2 h, max. 2×, solange seit dem ersten Push kein `meal_plan` entstand; `reinstall_reminder` alle 6 Tage seit `REINSTALL_BASE` um 18:00 an Owner; `coupon_expiry` (täglich 09:00), `week_review` (So 19:00), `achievements` (täglich 03:00), `price_history`, `watch_alarms` = Platzhalter bis Phase 12–14. Ruhezeit: Push geht trotzdem raus, ntfy stellt per `delay` erst zum Ende zu. Manuell: `./dev.sh python -m app.jobs <name>`; ohne Namen läuft die Schleife im Vordergrund (= späterer `scheduler`-Container) | Spezifikation 72 + 17, Annahme A4; „Später“ als echter Snooze-Endpunkt bräuchte ein öffentlich erreichbares Backend (VPS) und ein Token im Push-Text – die automatische Wiederholung ist einfacher und funktioniert schon im Heim-WLAN-Betrieb |
| E49 | **Preisdaten sammeln (Grundlage 28/30/31):** `product` (Schlüssel `key` = normalisierter Titel \| Marke \| Menge+Einheit, Kleinbuchstaben, Sonderzeichen → Leerzeichen; EAN zusätzlich, wenn vorhanden → Treffer per EAN zuerst), `offer.product_id`. `price_point` je product/chain/store_ref/ISO-Woche (`week` = heute, begrenzt auf valid_from…valid_to; gleiche Ware mehrfach → günstigster Preis), `is_offer` = Streichpreis > Preis. Geschrieben von `upsert_offers` (jeder Import) und Job `price_history` (nach jedem Import: alle aktuellen + alle Angebote ohne Produkt = einmalige Rückfüllung, live 5.787 Punkte aus 6.900 Angeboten). `GET /offers/{id}/history`: Punkte der letzten 12 Wochen (je Woche+Kette günstigste Filiale), `median_cents`, `min_cents`, Urteil: < 3 Wochen → `zu_wenig_daten`; ≥ Median oder Mondpreis (Streichpreis gesetzt, aber Preis ≥ Median der Nicht-Angebotswochen) → `kein_echtes`; ≤ Minimum → `bestpreis`; ≤ 85 % Median → `gut`; sonst `normal`. `last_low` = letzte frühere Woche mit Preis ≤ aktuell, `avg_interval_weeks` = mittlerer Abstand der Angebotswochen (gesamte Historie) | Spezifikation 28 + Grundlage Phase 12; UI kommt in Phase 12 |
| E50 | **Meine Rezepte (3, Backend):** `recipe` + `source` (ai\|user\|instagram\|web\|shared), `source_url`, `source_author`, `tags`; `recipe_favorite` (Haushalt, unique je Rezept, member_id = wer), `rating` (eine Zeile je Kochen: stars 1–5, again bald\|irgendwann\|nie, note, cooked_at, member_id). „Meine Rezepte“ = Nicht-KI-Rezepte des Haushalts + favorisierte/bewertete KI-Gerichte. `GET /recipes?filter=&q=` (Suche in Titel+Tags), `GET /recipes/deals`, `GET/PATCH/DELETE /recipes/{id}`, `GET /recipes/{id}/cost`, `POST /recipes` (Einheiten g/kg/ml/l/stk/el/tl/prise, kg/l → g/ml; EL 15 g, TL 5 g, Prise 0,5 g; Foto Base64-JPEG ≤ 2 MB → `backend/media/recipes/<id>.jpg`, `image_url` relativ `/media/recipes/<id>.jpg?v=<zeit>`), `POST /recipes/{id}/favorite` (Umschalter), `POST /recipes/{id}/rate`, `POST /plans/current/entries/{id}/replace` (ohne KI; `meal_plan_entry.scale` = Portionen des Slots / Rezept-Portionen, Kosten neu, Liste synchron). Löschen eines Rezepts, das noch in einem Plan steht: bleibt als Plan-Gericht (`source=ai`). **Live-Kosten:** Zutat → aktuelles Angebot über Namensabgleich (normalisiert, Plural, Kompositum über Wortende, Synonyme; `services/matching.py`, auch für Feature 1), sonst KI-Packungspreis, sonst Normalpreis-Schätzung aus Angeboten der letzten 8 Wochen; `offer_share` = Kostenanteil aus aktuellen Angeboten, Badge/Deals ab 0,4. **Planer:** variabler Prompt-Teil bekommt Top 15 Favoriten/≥ 4★ „Titel (Zutaten)“ („gern einplanen, max. 2 pro Woche“), Nie-Liste (letzte Angabe „nie“ oder Ø ≤ 2★), Gerichte der 2 Vorwochen; Nie/Wiederholung wird zusätzlich im Code geprüft (Titel wortweise enthalten oder ≥ 85 % gleich) → Korrekturrunde | Spezifikation 3; „ähnliche Titel“ bewusst einfach gehalten |
| E51 | **Nährwerte (2, Backend):** Quelle **USDA FoodData Central**, Foundation Foods (CSV 2026-04-30; das Oktober-2026-ZIP auf fdc.nal.usda.gov enthält derzeit kein food.csv) + SR Legacy (2018-04), **gemeinfrei, CC0 1.0** („USDA FoodData Central data are in the public domain“, fdc.nal.usda.gov/api-guide). `python -m app.tools.import_usda` lädt die ZIPs ins Temp-Verzeichnis, liest nur food.csv/food_nutrient.csv → Tabelle `food` (id = fdc_id; kcal 1008→2048→2047, Protein 1003, Fett 1004→1085, KH 1005→1050, Ballaststoffe 1079, Zucker 2000→1063, Salz = Natrium 1093 × 2,5) + SQLite-FTS5 `food_fts` (live 8.219 Lebensmittel). `ingredient_map` (ingredient_key unique, food_id oder null = kein Treffer, grams_per_piece, confidence hoch\|mittel\|niedrig): Haiku (`MODEL_FAST`, Standard jetzt `claude-haiku-5-5`) übersetzt in eine englische Suchanfrage + Stückgewicht-Vorschlag → FTS Top 10 → Haiku wählt (nur IDs aus den Kandidaten zählen); Stückgewicht aus Tabelle `PIECE_G` vor KI; je 25 Zutaten 2 Aufrufe, Kosten geloggt (live 24 Zutaten ≈ 0,2 ct). Zuordnung läuft im Hintergrund-Thread nach Plan/Neu würfeln/Einsetzen/Rezept anlegen; bis dahin `nutrition`/`composition` = null. Rechnung im Code: pro Portion = Summe / `portions_total` (Rezeptmenge × `scale`), pro Person = × factor; ml ≈ g. `MealOut.recipe.nutrition` {kcal, protein, carbs, fat, fiber}, `recipe.composition` [{name, grams (pro Portion), share}] (Summe exakt 1), `GET /plans/current/nutrition` (pro Tag und Mitglied, `complete`, Ziele + Wochenschnitt aus Profil) | Spezifikation 2, A6; ersetzt „Open Food Facts / BLS“ aus E10; FTS5 ist SQLite-spezifisch (auf Postgres ersetzen) |
| E52 | **Apple Push (APNs) statt ntfy** (Nutzerentscheidung: keine externe App, bezahlter Apple-Developer-Account): `push_device` (member_id, token unique, environment development\|production, last_ok), `POST /me/push/device` {token, environment} (Upsert, Token wechselt zum meldenden Mitglied), `DELETE /me/push/device/{token}`, `POST /me/push/test` (422 ohne Gerät, 502 wenn APNs ablehnt). `services/push.send(member, title, message, click_url, thread_id, category)`: HTTP/2 (`httpx[http2]`) an `api.sandbox.push.apple.com` bzw. `api.push.apple.com`, JWT ES256 (`pyjwt[crypto]`, kid = `APNS_KEY_ID`, iss = `APNS_TEAM_ID`, 50 min gecacht), `apns-topic` = `APNS_TOPIC` (de.jsenf.essenapp), push-type alert, priority 10; Payload `aps.alert{title, body}`, `sound default`, `thread-id`, optional `category` (Plan-Erinnerung: `PLAN_PROMPT` mit Aktionen „Plan erstellen“/„Später“ in der App), Zusatzfeld `url` (essenapp://…). 410/BadDeviceToken → Gerät gelöscht; ohne Key: Log „APNs nicht konfiguriert“, False. Ruhezeit: Push landet in `push_outbox` und geht mit dem Scheduler-Tick ab Ende der Ruhezeit raus. Key-Datei unter `backend/secrets/` (gitignored). ntfy-Felder, `GET /me/push`, `NTFY_URL` entfernt (Migration) | Ersetzt E9 und die ntfy-Teile von E47 |
| E48 | **Spike A1 (2026-11-02):** Teilen-Erweiterung (`com.apple.share-services`, Library-Target `EssenappShare`, `extensions:` in xtool.yml) wird mit der kostenlosen Apple-ID signiert. Mit `com.apple.security.application-groups` scheitert die Signatur („Can't find free space of LoadCommands for CodeSignature“, zsign, xtool #379; `-headerpad_max_install_names` hilft nicht) | → **Keine App Group**: Erweiterung meldet sich per Kopplungscode beim Backend an (Nutzerentscheidung A1) |
| E53 | **Kopplungscode (A1-Ersatz, Backend):** `POST /me/pairing-code` → 6 Ziffern (`secrets.randbelow`), 10 min gültig, einmal einlösbar, neuer Code ersetzt ältere des Mitglieds (`pairing_code`, Klartext, weil kurzlebig). `POST /pair {code, label?}` ohne Auth → **eigenes Token** in `member_token` (gleiches Mitglied, `current_member` prüft Haupt-Token und gekoppelte), Antwort wie Haushalt anlegen + `member_id`, `member_name`. Fehler: 404 „Code ungültig“, 410 „Code abgelaufen“/„Code wurde schon benutzt“, 422 Format, 429 nach 5 Fehlversuchen in 10 min je IP (im Speicher). Widerrufen: `GET /me/tokens`, `DELETE /me/tokens/{id}` | Spike E48: keine App Group mit kostenloser Apple-ID. Rate-Limit nur im Prozess-Speicher (reicht für 1 Backend-Prozess) |
| E54 | **Rezept-Import (5, Backend):** `POST /import {url, text?}` (Auth, auch gekoppeltes Token). Instagram-Links (`/p/`, `/reel(s)/`, `/tv/`, auch `/<user>/reel/…`) → kanonisch `https://www.instagram.com/<p\|reel\|tv>/<code>/`; gelesen wird die öffentliche Einbettungsseite `…/<code>/embed/captioned/` (ohne Login, live geprüft 02.11.2026: `div.Caption` mit `a.CaptionUsername`, Bild `img.EmbeddedMediaImage`). Andere Seiten: schema.org/Recipe aus JSON-LD (auch `@graph`, `@id`-Verweise für Bild/Autor aufgelöst), sonst Seitentext (max. 15.000 Zeichen). Abruf: 10 s Timeout, eigener User-Agent, 1 h Cache im Speicher. **Haiku** (`MODEL_FAST`, `messages.parse`) macht immer das strukturierte Rezept (Einheiten g/kg/ml/l/stk/el/tl/prise → wie `POST /recipes`, geschätzte Mengen mit `"estimated": true` an der Zutat). Speichern `source=instagram\|web`, `source_url` (kanonisch), `source_author` (`@user` bzw. JSON-LD-Autor, sonst Domain), Vorschaubild als JPEG nach `/media/recipes/<id>.jpg` (Instagram-URLs verfallen), Web-Bild ohne JPEG bleibt extern, ohne Bild → freie Fotosuche. Gleiche URL im Haushalt → bestehendes Rezept mit **200** statt 201. Kein Rezept (leere Beschreibung ohne Teilen-Text, oder KI: keine Zutaten) → **422 „Kein Rezept gefunden“** (A2, kein Screenshot-Ersatz); Seite nicht erreichbar → 502. Live: chefkoch.de-Rezept 4,7 s, 0,07 ct | Spezifikation 5; JSON-LD wird nicht im Code geparst, weil Zutatenzeilen frei formuliert sind (Brüche, „n. B.“, Cups) – Haiku auf dem kompakten JSON-LD ist genauer und kostet < 0,1 ct |
| E55 | **Schritt-Bilder (9, Backend):** `recipe.step_images` (JSON, `/media/steps/<id>/<n>.jpg`, n ab 1); API liefert `step_images` immer gleich lang wie `steps`, **`""` = noch kein Bild** (nicht null: iOS dekodiert `[String]`). Erzeugung im Hintergrund-Thread beim Öffnen (`GET /recipes/{id}`) oder per `POST /recipes/{id}/step-images` (202, `{step_images, pending}`; 422 ohne `FAL_KEY` oder wenn ausgeschaltet). fal.ai FLUX schnell (`recipe_images.fal_generate`), Prompt „<Titel>: <Schritt>. bright overhead food photography, home kitchen, natural light“, 1024×640 (16:10), JPEG; nie doppelt (laufende Rezepte gemerkt, vorhandene Datei/Spalte wird übersprungen). Schritte geändert → Bilder verworfen. Schalter `household.step_images` (Standard an) in `PATCH /household`, `HouseholdOut.step_images_available` = `FAL_KEY` gesetzt. Kosten 0,3 ct/Bild (0,003 $ je angefangenem Megapixel laut fal.ai) im Kostenprotokoll | Spezifikation 9 |
| E56 | **Kühlschrank-Foto (69, Backend):** `POST /pantry/scan` (multipart `files` 1–5 JPEGs ≤ 5 MB, `mode` kuehlschrank\|vorrat\|gefrierfach) → Haiku Vision → `{items: [{name, amount?, unit (g/ml/stk/""), location, category (Angebots-Kategorien), confidence hoch\|mittel\|niedrig, best_before? (heute + geschätzte Resthaltbarkeit bei Frischem)}], cost_cents}`, **speichert nichts**. Übernehmen: `POST /pantry/bulk [PantryIn]` (gleiche Zutat+Einheit wird addiert wie Abhaken → Vorrat, Basic wieder vorhanden, frühere Haltbarkeit gewinnt). „Was koche ich jetzt?“ = `POST /pantry/cook-now` (POST, weil es KI kostet und Rezepte anlegt): Haiku schlägt 4 Gerichte ≤ 30 min aus Vorrat + Basics vor, der Code rechnet die fehlenden Zutaten (Stock, g≈ml, Löffelmaße), > 2 fehlende fliegen raus, sortiert nach Abdeckung, max. 3 → `[{recipe: RecipeOut (gespeichert, source ai), missing: [{name, amount, unit}]}]`; „Heute kochen“ über `…/replace`. Der Wochenplan bekam den Vorrat schon mit E46 | Spezifikation 69 |
| E57 | **Kostenprotokoll + Angebots-Nährwerte:** Tabelle `ai_cost` (household_id, kind import\|scan\|cook_now\|step_image, model, cost_cents, info) über `planner.log_cost`; `GET /usage` zusätzlich `by_kind` (inkl. `plan`) und `recent` (neueste 20), `cost_cents_total` = alles. `GET /offers/{id}/nutrition` → `{status ok\|pending\|none, food, per_100g, per_pack}`: Zuordnung des Angebotstitels über `ingredient_map` (erste Anfrage startet sie im Hintergrund → `pending`), Werte nur bei confidence `hoch`, Drogerie/Haushalt nie | Spezifikation 2 („Angebote mit Nährwerten, wenn Zuordnung sicher“), 5, 9, 69 |
| E58 | **iOS Import & Kühlschrank-Foto (5/9/69/2):** Oberfläche der Teilen-Erweiterung im eigenen Target `EssenappShareUI` (App und Erweiterung nutzen es: „Link einfügen“ S22 und Demo-Screenshots); dort ein kleines Theme mit **duplizierten Werten** aus `Theme.swift`, weil die Erweiterung das App-Modul nicht importieren kann. Die Erweiterung speichert Server-Adresse + gekoppeltes Token im eigenen Schlüsselbund; die Server-Adresse steht in S21 zum Kopieren und wird in der Erweiterung einmal eingegeben (kein geteilter Speicher). „In App öffnen“ geht aus Share-Erweiterungen nicht → Hinweis „Rezepte › Meine Rezepte“. Schritt-Bilder: Polling `POST /recipes/{id}/step-images` mit Backoff 2→30 s. Kühlschrank-Kamera = System-Kamera (`UIImagePickerController`) je Foto + Fotomediathek, Upload multipart mit Fortschritt (URLSession-Delegate) | Spezifikation 5, 9, 69, 2; kleinster Aufwand ohne eigene AVFoundation-Kamera |
| E59 | **Abwechslung (12) + Reste (19), Backend:** Regeln in `household.variety` (JSON, fehlende Schlüssel = Standard: max_pasta 1, max_rice 2, max_potato 2, min_fish 1, veggie_days 2, max_red_meat 2, repeat_weeks 3, no_same_cuisine_row an) über `PATCH /household {"variety": {...}}`, `HouseholdOut.variety` immer vollständig. Zählen nur Hauptgerichte (mittag/abend/lunchbox); vegetarischer Tag = alle Hauptgerichte vegetarisch/vegan; Fisch-Pflicht entfällt bei vegetarisch/vegan oder „fisch“ in Allergien/Abneigungen; gleiche Küche = gleicher `cuisine`-Text an Kalendertagen d/d+1. KI gibt je Gericht `side` (pasta/reis/kartoffel/brot/andere) + `protein` (fisch/rot/gefluegel/vegetarisch/vegan), gespeichert als `recipe.tags`; eigene Rezepte ohne Tags → Stichwort-Klassifikation. `services/variety.check` liefert Chip-Texte („2× Pasta“, „kein Fisch“, „nur 1 vegetarischer Tag“, „Wiederholung: …“) + Anweisungen je Slot (spätere Gerichte zuerst, fixierte nie). **Planner-Durchgang 2** = EINE Runde nur für betroffene Slots: Regelverstöße + frische Reste. `price()` bricht Packungen chronologisch an (Vorrat → offener Rest → neue Packung); Haltbarkeit nach Anbruch: fleisch_fisch 2, obst_gemuese 3, kuehlung 4 Tage, Vorrat/Lagergemüse egal (Kategorie aus dem Angebot, sonst Stichwörter); Rest lohnt ab 1 Stück bzw. max(30 g/ml, 10 % der Packung). Je Rest ein Folgegericht bis zum Ablauf („verwende Rest 150 g Hähnchen (offer_id=7)“, gleiche offer_id); Fleisch/Fisch nur in Hauptgerichte, deren Proteinwechsel keine Regel bricht (mit `check` simuliert); reine Reste-Slots bekommen „sonst: Beilage/Protein/Küche“ mit. Übernommen nur, wenn (Verstöße inkl. Budget/Nie-Liste, übrige Reste) nicht schlechter. `PlanOut.variety {ok, issues}` live (Vorwochen ab Planwoche, eigener Plan ausgenommen), `PlanOut.leftovers {planned, left[{name, amount, unit, until_day, suggestion}]}`, `MealOut.rests [{name, from_day}]` („♻︎ Rest von Mo“), gespeichert in `meal_plan.params.rests` und bei jedem Neu-Rechnen erneuert. `GET /plans/current/entries/{id}/leftovers` → erwartete Reste nach dem Kochen (`best_before` = Montag der Planwoche + Tag) → `POST /pantry/bulk` mit `source: "rest"`. Live (Köln, 12 Gerichte): 6 frische Reste → 2 übrig, Chip ✓ | Spezifikation 12/19; ein gemeinsamer zweiter Durchgang statt zwei Runden spart einen KI-Aufruf |
| E60 | **Gäste (15), „Keine Lust“ (16), Plan-Erinnerung (17), Backend:** `PlanOptions.guests [{day, meal_type, count 0–20}]` (Gast = 1 Portion, `portions_total` enthält Gäste, `meal_plan_entry.guests`, Prompt „portionen=6 (davon 4 Gäste)“ + Systemregel „gästetauglich“), `guest_budget_cents` erhöht nur das Budget dieses Plans; guests/special/wishes nie als Standard gespeichert. Nachträglich `POST /plans/current/entries/{id}/guests {count}` ohne KI: scale × neu/alt, Kosten + Liste neu. **Keine Lust:** `POST /no-mood {exclude[]}` → 3 `CookIdeaOut` ≤ 15 min aus Vorrat + Basics + abgehakten Listenartikeln, `missing` immer leer (Code prüft; angebrochene Menge zählt als vorhanden, Wasser immer da), Haiku **ohne Denkphase** (`thinking: disabled`, bei Effort low erlaubt) + 3–4 kurze Schritte, Fotos max. 1 s abwarten → live 5,9 s / 6,2 s (Wischen mit exclude), 0,065 ct. Auswahl = bestehendes `…/replace`; „Auf morgen verschieben?“ = `POST /plans/current/postpone {recipe_id, day, meal_type}`: Rezept auf den Tag, spätere nicht fixierte Gerichte derselben Mahlzeit rücken je einen Plan-Tag weiter, das letzte fällt heraus, Mengen auf die Esser des neuen Slots. **17:** Push gab es schon (E47/E52, Kategorie `PLAN_PROMPT`, „Später“ = automatische Erinnerung nach 2 h, max. 2×); der Plan entsteht erst mit `POST /plans`. Neu `GET /plans/generator` → `{week, defaults (PlanOptions des Haushalts), top_offers (3 Lebensmittel mit höchstem Rabatt), banner}` | Spezifikation 15/16/17 |
| E61 | **Frühstück & Snacks (23), Lunchbox (24), Backend:** Tabelle `weekly_basic` (name, amount?, unit), `GET/POST /weekly-basics`, `PATCH/DELETE /weekly-basics/{id}`, `POST /weekly-basics/to-list` (sofort); Job `weekly_basics` „Mo 06:30“: Wochenmenge − Vorrat auf die Haushaltsliste (Quelle `basics`), günstigstes passendes Angebot der eigenen Läden (Grundpreis) setzt `offer_id` + `chain`, offene Einträge werden aktualisiert statt verdoppelt. Wochen-Basics zählen für Kosten und Plan-Liste als vorhanden (ein Vorrat ohne Einheit/Menge gilt für jede Einheit). Neue Mahlzeit `snack` (MEAL_TYPES, `eats`, Rezepte); Systemregeln für fruehstueck (Bausteine, ≤ 10 min, jeden Tag anders), snack (transportierbar, zielbezogen, Vorkochen „Vorkochen am <Tag> für <n> Tage: …“), lunchbox (kalt/aufwärmbar, transportsicher, „Am Vorabend: …“, Suppen nur „im Thermobehälter“); variable Zeilen „Frühstücks-/Snack-Basics …“ und „Snack-Ziel: <Ziele der Profile>“. Code prüft: Frühstück doppelt / > 10 min, Lunchbox-Suppe ohne Thermo-Hinweis → Durchgang 2. **Lunchbox:** Slot `lunchbox` an Plan-Tagen ∩ `lunchbox_days` der Profile, Esser = diese Mitglieder (1 Portion × Faktor). Abend-Push optional: `member.lunchbox_push` HH:MM (null = aus, `PATCH /me/push/settings`), Job je Mitglied `lunchbox:<id>` täglich, nur wenn morgen eine Lunchbox für das Mitglied geplant ist („🥡 Lunchbox für morgen vorbereiten: <Titel>“, `essenapp://recipe/<id>`, thread `lunchbox`) | Spezifikation 23/24, A9 |
| E62 | **Feiertage & Saison (25), Backend:** `services/seasons.py` ohne KI: Ostern (Meeus/Jones/Butcher), Feiertage bundesweit + landesweite je Bundesland (Fronleichnam, Allerheiligen, Reformationstag, Buß- und Bettag …; Gemeinde-Feiertage nicht), Bundesland aus PLZ-Leitbereich (2 Ziffern + bekannte 3-Ziffern-Ausnahmen; shortcut, an Landesgrenzen ungenau), Anlässe Weihnachten (24.12.), Silvester, Ostern, Muttertag (2. Sonntag im Mai), Halloween, Saisons Spargel Apr–Jun, Grill Mai–Aug, Kürbis Sep–Nov, Glühwein/Plätzchen Dez, Saisonkalender je Monat. `GET /specials?date=YYYY-MM-DD` → `{state, banner {key, emoji, name, date, days_until, template, template_name, running, text}, specials[], holidays[] (14 Tage), seasons[], produce[]}`; Banner = nächster Anlass ≤ 14 Tage (vor Saisonbeginn), Text „🎄 Weihnachten in 12 Tagen – Menü planen?“. `PlanOptions.special` = key: festtagsmenue (Vorspeise/Haupt/Dessert am Wochentag des Anlasses, neue meal_type `vorspeise`, Esser wie abend), grillparty (Sa abend, Grillgut + Beilagen als ein Gericht), plaetzchen (Sa+So dessert). Prompt immer: „Saison (leicht bevorzugen): …“, Saison-Hinweise (Spargelzeit: 1–2 Spargelgerichte), Feiertage der Planwoche | Spezifikation 25 |
| E63 | **Ersatzzutaten (7), Backend + Kleinkram:** `services/substitutes.py` Tabelle mit 108 Zutaten (Wirkung + Mengenfaktor, Basis g/ml oder Stück; el/tl/kg/l und Stück über Stückgewicht umgerechnet), sonst Haiku (`kind substitute`, je Zutat/Menge/Rezept/Einschränkungen im Prozess gecacht). Allergien (Gruppen Milch/Laktose, Ei, Gluten, Nüsse, Erdnuss, Soja, Fisch, Krebstiere, Sesam, Sellerie, Senf, Lupine; Pflanzendrinks keine Milch; unbekannte Allergie = Wort selbst), Ernährungsform und Abneigungen (Haushalt + alle Profile) prüft immer der Code. `GET /recipes/{id}/ingredients/{index}/substitutes` → `{ingredient, source tabelle\|ki, options[{note, ingredients[{name, amount, unit, in_pantry, offer{id, chain, price_cents}?}]}]}` (Sahne: 0,7 s, KI 3,6–5,9 s); `POST …/substitute {ingredients[]}` ersetzt im Rezept (globales Rezept → Kopie für den Haushalt), neue Zeilen `"replaces"`, steht es im aktuellen Plan → Kosten + Liste neu. **Vorrat-Ort** (69): `pantry_item.location` kuehlschrank\|vorrat\|gefrierfach\|null in PantryIn/Update/Out, `/pantry/bulk` übernimmt ihn. **Schritt-Bilder** (9): Prompt „Cooking step n of N … Show ONLY the intermediate state … NOT the finished dish“, letzter Schritt zeigt das Gericht (live: Teig in der Schüssel statt Kuchen). Tests blockieren echte Anthropic-Aufrufe und APNs (conftest) | Spezifikation 7, 9, 69 |
| E64 | **Nachbesserungen vor Phase 12:** (1) `GET /offers` liefert je Angebot `verdict` (wie `/offers/{id}/history`), berechnet über `prices.verdicts` mit **einer** Preispunkt-Abfrage für alle Angebote (+ eine für Produkte), keine N+1. (2) **Reste ≥ 70 %:** Durchgang 2 behält bei reinen Reste-Slots das bisherige Gericht („<Titel>“ (Zutaten) behalten und den Rest einbauen“), verbietet neue frische Packungen, die übrig blieben, „verwende Rest … komplett“ (SYSTEM: mindestens diese Menge), große Reste (≥ 400 g/ml bzw. ≥ 4 Stück) auf zwei Folgegerichte verteilt, Ziel-Slots auch später am selben Tag und Snack/Dessert (nicht Fleisch), Reste aus Slots, die wegen einer Regel ersetzt werden, zählen nicht; Erstplan-Regel „keine Großpackung, die die Woche nicht verbraucht“. Live Köln (Frühstück + Abend, 6 Tage): 6 von 8 bzw. 4 von 5 frischen Resten verplant (75 %/80 %; vorher 67 %, ohne Behalten-Regel 22 %). (3) **Vorrats-Abgleich** `pricing.stock_key`: Text vor Komma/Klammer, Wörter gestemmt wie `matching.stem`, Zusätze ohne Produktwechsel (mild, natur, fettarm, frisch, bio …) entfallen → „Joghurt, mild“ = Basic „Joghurt“ (Kosten, Plan-Liste, „Keine Lust“). (4) **Brot in Stück = Scheiben:** KI-Packung „1 stk“ bei …brot/…toast (nicht Fladen-/Pita-/Naanbrot) gilt als ganzes Brot à 15 Scheiben, auch wenn das Angebot eine andere Einheit hat; SYSTEM: Brot/Toast in g, pack_amount in derselben Einheit. Fall „Brot 4 Stück, Packung 1 Stück, 2,79 €“: 1 Brot statt 4 (Frühstück 2,19 € statt 12,61 €). (5) **Abwechslung anteilig:** `variety.scaled(rules, Tage)` – min_fish/veggie_days × Tage/7, kaufmännisch gerundet (1 Tag: 0/0, 2 Tage: 0 Fisch/1 vegetarischer Tag, 4 Tage: 1/1), Höchstregeln bleiben; gilt in Prüfung, Chip und Prompt-Zeile (Neu würfeln: Tage des Plans). Live 2-Tage-Plan: Chip ✓ | Mängel aus der Abnahme Phase 11; Spezifikation 12/19/23 |
| E65 | **Prospekt-Vorschau (30, Backend):** Der Import übernahm Folgewochen-Prospekte schon (Shelf ohne Datumsfilter); live 03.11.2026 Köln: Lidl listet die Woche ab 09.11. bereits am Montag/Dienstag (433 Angebote, Gültig ab 09./12./13.11.), REWE/ALDI SÜD noch nicht. Zusätzlicher Import **Fr 06:00** (`import_offers` jetzt „Sa 22:00, Mo 06:00, Mi 06:00, Fr 06:00“). `GET /offers?week=next` = Gültigkeitsbeginn in der nächsten Woche (Mo–So), `week=this` (Standard) = heute gültig. `GET /offers/next-week-cheaper` → `[{name, item_id, watch_id, offer (nächste Woche), now_price_cents, now_chain, saving_pct}]`: offene Listenartikel (inkl. Plan-Zutaten) + Merkliste, ab **10 %** günstiger; heutiger Preis = heutiges Angebot (auf die Packung der Vorschau umgerechnet), sonst Streichpreis, sonst Normalpreis aus 8 Wochen. „Auf nächste Woche schieben“: `POST /items/{id}/next-week {offer_id?}` (setzt `shopping_item.defer_week` = nächste ISO-Woche; Nicht-Plan-Artikel bekommen Laden/Angebot), `PATCH /items/{id} {next_week}`, `ItemCreate.next_week`; `ItemOut.defer_week` + `next_week` (berechnet: Gruppe „Nächste Woche“ bis diese Woche beginnt). Plan-Generator `PlanOptions.next_week` → Angebote gültig am nächsten Montag, `meal_plan.week` = nächste KW; Neu würfeln/Einsetzen rechnen mit denselben Angeboten (`plan_offers`) | Spezifikation 30 |
| E66 | **Vorratskauf-Tipp (31, Backend):** `services/stockup.py`. Kandidat: haltbar (Kategorie vorrat/getraenke/drogerie/haushalt, TK-Wörter oder haltbare Begriffe wie Nudeln/Reis/Dose), Urteil bestpreis/gut, Rabatt ≥ 25 % gegen Streichpreis bzw. Median. Verbrauch (Packungen/Woche) = Pläne + abgehakte Nicht-Plan-Listenartikel der letzten 8 Wochen ÷ 8 + Wochen-Basics (23) + 1/lasts_weeks der Merkliste (58), Zuordnung über den Namensabgleich (alle Kategorien); ohne Historie konservativ 2 Packungen. Menge = ⌈Verbrauch × Angebotsabstand⌉ (avg_interval_weeks aus 28, ohne Rhythmus **(C) 4 Wochen**), gedeckelt auf 26 Wochen Verbrauch und Vorratsplatz **(C) klein 3 / mittel 6 / gross 12 Packungen** (`household.storage_space`, `PATCH /household`). Ersparnis = (Normalpreis − Angebot) × Menge. `GET /stockup?limit=3` (Start-Karte), `GET /offers/{id}/stockup` (Detail, null = kein Tipp) → `{offer, packs, weeks, weekly_use, saving_cents, normal_price_cents}`; „3× auf die Liste“ = `POST /lists/{id}/items {…, amount: 3, offer_id, chain, source: "stockup"}` (Badge „Vorratskauf“). Live heute keine Tipps: Preisverlauf hat erst 1 Woche (Urteil „zu wenig Daten“) | Spezifikation 31 |
| E67 | **Merkliste + Preisalarm + Verbrauchsrhythmus (27/40/58, Backend):** `watch_item` (kind produkt\|zutat, label, brand, ean, image_url, category, max_price_cents, max_base_price_cents + base_unit kg\|l\|stk, chains, lasts_weeks, last_bought, rhythm_push_at, rhythm_listed_at) und `watch_hit` (watch_item, offer, week, notified_at). `GET/POST /watch`, `PATCH/DELETE /watch/{id}`; Herz = `POST /watch {offer_id}`; Barcode: `GET /products/ean/{ean}` → Open Food Facts (`{ean, found, name, brand, image_url, nutri_score}`, 502 wenn nicht erreichbar) → `POST /watch {label, brand, ean, image_url}`. Abgleich: EAN, sonst Produkte per Token-Abgleich (Marke muss vorkommen, dann ≥ 1/2 der Namenswörter, ohne Marke ≥ 2/3, Mengen zählen nicht), Zutaten über die Zutat-Zuordnung (`Matcher`, wie Feature 1); Wunschpreis auf den Packungspreis, Grundpreis-Alarm nur bei gleicher Basis (g→kg, ml→l, stk) → unabhängig von der Packungsgröße. Job `watch_alarms` nach jedem Import: Treffer speichern, **höchstens 1 Push je Eintrag und ISO-Woche** an alle Mitglieder (APNs über `jobs.notify`, Ruhezeit) „🧴 Dein Shampoo ist bei dm im Angebot: 1,79 € (−25 %)“, `essenapp://offer/<id>`, thread `watch`. `WatchOut.hits` = aktuelle Treffer (Abschnitt „Diese Woche günstig“ + Badge am Tab). **58:** Vorschlag „Hält ca. X Wochen“ nach Stichwort (Shampoo 6, Duschgel 4, Toilettenpapier 3, Waschmittel 8 …), sonst Drogerie 6/Haushalt 8; bei Drogerie/Haushalt-Produkten ohne Angabe gesetzt, `lasts_weeks_suggestion` immer geliefert. Abhaken eines passenden Listenartikels setzt `last_bought`. Job `watch_rhythm` täglich 08:00: 14 Tage vor „leer“ und im Angebot → Push „Shampoo bald leer – gerade −25 % bei dm“ (einmal je Zyklus); 3 Tage vorher → Artikel `source rhythm` auf die Haushaltsliste (Laden des Angebots bzw. der einzigen Merklisten-Kette), nicht doppelt | Spezifikation 27/40/58; Push über APNs statt ntfy (E52) |
| E68 | **Ein-Laden-Modus (41) + Laden-Empfehlung (42), Backend:** `PlanOptions.single_store` (chain eines gewählten Ladens, sonst 422): Planner bekommt nur dessen Angebote, Prompt „Einkauf komplett bei Lidl …, Zutaten ohne Angebot zum Normalpreis von Lidl schätzen“, alle Plan-Artikel der Liste und die Wochen-Basics bekommen diesen Laden. `GET /lists/{id}/stores` → alle Läden einzeln + alle Paare der gewählten Ketten `[{chains, total_cents, per_store, saved_cents, unpriced, distance_km, extra_km}]`, günstigste zuerst; Artikelpreis je Laden = ganze Packungen des günstigsten passenden Angebots, sonst Normalpreis dieses Ladens (8 Wochen), sonst Normalpreis eines anderen Ladens; Weg = Rundweg Zuhause → Läden (Luftlinie, Filial-Koordinaten). `POST /lists/{id}/assign {chains}` („So aufteilen“) ordnet jeden offenen Artikel dem günstigsten Laden zu (chain + offer_id), Summen = Rechnung | Spezifikation 41/42 |
| E69 | **Budget-Rest (43), Backend:** `GET /plans/current/budget` → `{budget_cents, total_cents, rest_cents, state rest (≥ 5 €)\|over\|ok, over {entry_id, day, title, cost_cents, max_cost_cents}}` (teuerstes nicht fixiertes Gericht). `POST /plans/current/budget/ideas` → Haiku (ohne Denkphase, Kostenart `budget`) schlägt Dessert + Snack aus den Angeboten vor, Einkaufspreis rechnet der Code (ganze Packungen, Vorrat abgezogen), nur ≤ Rest; dazu bester Vorratskauf-Tipp (31) passend gekürzt → `[{kind dessert\|snack\|vorrat, title, cost_cents, recipe, stockup}]`. Einplanen: `POST /plans/current/entries {recipe_id, day, meal_type}` (Esser des Slots, Kosten + Liste neu). Über Budget: `POST /plans/current/entries/{id}/reroll {max_cost_cents}` (Prompt „höchstens … ct“). Live: 15,9 s, 0,05 ct | Spezifikation 43 |
| E70 | **Bio, Vegan, Nutri-Score (49), Backend:** `services/labels.py`. Prospekttext (Titel, Marke, Beschreibung aus den Rohdaten): Bio = Wort „Bio“ (nicht „Bio-Baumwolle“), Bioland/Demeter/Naturland, „DE-ÖKO-0xx“, „kontrolliert biologisch“; vegan/vegetarisch per Wort; nur Lebensmittel/Getränke, Textilien nie. **Open Food Facts** (Datenbank **ODbL**, Inhalte DbCL, Bilder CC BY-SA; Quelle in `label_sources`): Job `product_facts` nach jedem Import sucht höchstens 30 noch ungeprüfte Produkte mit Marke über `search.openfoodfacts.org/search` (6,5 s Abstand, Limit 10 Suchen/min), sicherer Treffer = Marke stimmt + „Marke Name“ bzw. Name ≥ 0,8 ähnlich (difflib), widersprüchliche Nutri-Scores → keiner; Ergebnis am `product` (nutri_score, off_code, off_bio/vegan/vegetarian, off_checked_at). `OfferOut` + `bio, vegan, vegetarian, nutri_score (A–E), label_sources, off_code`; Filter `GET /offers?bio=&vegan=&nutri_ab=`. Planner: Zeile „Nutri-Score A/B (bei Ziel „…“ bei ähnlichem Preis bevorzugen): …“. Live: 6 sichere Treffer aus 30 Suchen (200 s); Stichprobe 53 Angebote mit Badge geprüft, falsch waren nur „Bio“ bei Kinder-Socken/Bodys (Bio-Baumwolle) → behoben | Spezifikation 49 |
| E71 | **Monatsaktionen (59), Backend:** dm (Suche) und Rossmann (Prospekte) kamen schon über kaufDA. Monatsaktion = dm/Rossmann-Angebot, das am Monatsletzten endet oder ≥ 3 Wochen gilt → `OfferOut.monthly`, `GET /offers?monthly=true` (sichtbar, solange gültig, also bis Monatsende). Live 03.11. gibt es bei kaufDA keine solche dm/Rossmann-Aktion (dm 01.–15.11., Rossmann bis 13.11.) → Abschnitt leer. **Coupons (Wallet) offen:** setzen das Coupon-Wallet aus 38 (Phase 13) voraus | Spezifikation 59 |

---

## 3. Architektur

```
                 ┌──────────────────────────── Backend (Python) ───────────────────────────┐
 Händler-Quellen │  Collector-Jobs ──► Normalisierung ──► DB ◄── Plan-Generator (Claude)   │
 (APIs/PDFs) ───►│  (pro Händler      (Offer → Zutat,    (SQLite→    Kosten- & Nährwert-   │
                 │   ein Adapter)      Kategorie, €/kg)   Postgres)   rechnung, Validierung │
                 │                              ▲                                          │
                 │        Watchlist-Matcher ────┘──► ntfy (Push)                           │
                 │                       REST-API (FastAPI) + Web-UI (Jinja + HTMX, PWA)   │
                 └───────────────────────────────┬──────────────────────┬──────────────────┘
                                                 │                      │
                                      iOS-App (SwiftUI, xtool)   Browser / Homescreen (Familie)
```

### Komponenten

| Teil | Technik | Aufgabe |
|---|---|---|
| Backend-API | Python 3.12, FastAPI, SQLAlchemy + Alembic, Pydantic | REST-API, Auth, Geschäftslogik |
| Datenbank | SQLite lokal → Postgres auf dem VPS | Über SQLAlchemy austauschbar |
| Jobs | APScheduler im Backend-Prozess (später ggf. separater Worker) | Wöchentliches Sammeln, Watchlist-Abgleich |
| KI | Anthropic API, Modelle per ENV konfigurierbar (`claude-sonnet-5-5` für Pläne, `claude-haiku-5-5` für Zuordnung/Kategorisierung) | Wochenplan, Zutaten-Mapping, PDF-Extraktion |
| Web-UI | Jinja-Templates + HTMX, PWA-Manifest | Familie: Wochenplan, Einkaufsliste, Rezepte, Bewertungen |
| iOS-App | SwiftUI, iOS 17+, xtool | Volle App für den Entwickler |
| Push | ntfy (self-hosted auf VPS oder ntfy.sh) | Angebotsalarme, „Neuer Wochenplan fertig“ |
| Deployment | Docker Compose + Caddy (HTTPS) | Phase 7 |

### Repo-Struktur

```
essenapp/
├── CLAUDE.md               # Einstieg für Claude: Leseordnung, PonyTail-Pflicht, Ablauf
├── .claude/skills/ponytail/
├── docs/
│   ├── PLAYBOOK.md         # dieses Dokument
│   ├── tasks/              # Phasen 0–7 mit Aufgaben und DoD
│   └── ui/                 # Design-System, Screens, Referenzen, Mockups
├── backend/                # + backend/CLAUDE.md
│   ├── app/
│   │   ├── api/            # FastAPI-Router
│   │   ├── core/           # Config, Auth, DB-Session
│   │   ├── models/         # SQLAlchemy-Modelle
│   │   ├── schemas/        # Pydantic-Schemas (= API-Vertrag)
│   │   ├── sources/        # Ein Adapter pro Händler (OfferSource)
│   │   ├── services/       # Planner, Pricing, Nutrition, Matching, Notifications
│   │   ├── jobs/           # Geplante Jobs
│   │   └── web/            # Jinja-Templates, statische Dateien, PWA
│   ├── migrations/
│   ├── tests/
│   ├── pyproject.toml
│   └── .env.example
├── ios/                    # + ios/CLAUDE.md
│   ├── Package.swift
│   ├── xtool.yml
│   └── Sources/Essenapp/   # Views, ViewModels, API-Client, lokaler Cache
└── deploy/                 # docker-compose.yml, Caddyfile (Phase 7)
```

### API-Vertrag

- Die Pydantic-Schemas im Backend sind die Quelle der Wahrheit. FastAPI erzeugt daraus `openapi.json`.
- Die Swift-Modelle werden von Hand passend dazu geschrieben (Codable). Ein Generator lohnt sich bei dieser Größe nicht.
- Auth: Haushalt hat Mitglieder; jedes Gerät / jeder Browser bekommt ein langlebiges Token (Einladungslink/-code statt Passwort-Registrierung).

---

## 4. Konfiguration (pro Haushalt)

Alles in den Einstellungen änderbar, gespeichert im Backend:

- **Ort:** PLZ; pro Händler optional eine konkrete Filiale (Rewe/Edeka haben filialabhängige Angebote)
- **Läden:** Auswahl aus den verfügbaren Adaptern (z.B. Rewe, Aldi Süd, Aldi Nord, Lidl, Edeka, Kaufland, Penny, Netto, dm, Rossmann)
- **Haushalt:** Anzahl Personen (optional Erwachsene/Kinder), Standard-Portionen
- **Ernährung:** Ernährungsform (alles, vegetarisch, vegan, pescetarisch, halal, …), Allergien/Unverträglichkeiten, Ausschluss-Zutaten
- **Küchen-Präferenz:** Mehrfachauswahl (Indisch, Chinesisch, Italienisch, Deutsch, …) oder „keine Präferenz“ / „gemischt“
- **Mahlzeiten:** welche pro Tag geplant werden (Frühstück, Mittag, Abendessen, Dessert, Snack) und an welchen Tagen
- **Budget:** pro Woche (Lebensmittel), optional separat für Drogerie
- **Nährwertziel:** ausgewogen, proteinreich, kalorienarm, eigene Ziele (kcal/Protein pro Tag)
- **Kochaufwand:** max. Zubereitungszeit unter der Woche / am Wochenende
- **Küchengeräte** (später): Heißluftfritteuse, Ofen, Thermomix, …

---

## 5. Datenquellen

Es gibt keine offiziellen APIs. Daher ein **Adapter pro Händler** mit einheitlicher Schnittstelle:

```python
class OfferSource(Protocol):
    chain: str                      # "rewe", "aldi_sued", "dm", ...
    def supports_location(self, plz: str) -> bool: ...
    def list_stores(self, plz: str) -> list[StoreRef]: ...
    def fetch_offers(self, store: StoreRef, week: IsoWeek) -> list[RawOffer]: ...
```

Strategien pro Adapter (in dieser Reihenfolge prüfen):
1. Strukturierte Daten (inoffizielle Händler-API / JSON, das die Händler-Website oder -App nutzt)
2. Aggregator-Daten
3. Prospekt-PDF/-Bilder → Extraktion per Claude Vision zu `RawOffer`-JSON

Regeln:
- Recherche mit allen Endpunkten, Fixtures und Bewertung: [`research/datenquellen.md`](research/datenquellen.md). Neue Quellen dort ergänzen. Nichts erfinden.
- Höflich abrufen: 1× pro Woche pro Filiale/Region, Caching, Rate-Limit, ehrlicher User-Agent.
- Rohdaten (`raw`) speichern, damit Normalisierung ohne erneutes Abrufen wiederholt werden kann.
- Jeder Adapter hat einen Test mit gespeicherter Beispielantwort (Fixture), damit Änderungen beim Händler sofort auffallen.
- Gültigkeit: Lebensmittelangebote gelten typischerweise Mo–Sa. dm/Rossmann haben zusätzlich Monatsaktionen. „Woche“ = ISO-Kalenderwoche.
- Folgewoche (30): der kaufDA-Shelf listet Prospekte der nächsten Woche, sobald der Händler sie freigibt (live 03.11.2026: Lidl schon Montag/Dienstag der Vorwoche); sie werden ohne Datumsfilter mit importiert (E65).
- **Open Food Facts** (49/27, E70): `GET https://world.openfoodfacts.org/api/v2/product/{ean}.json?fields=…` (Barcode, Limit 15/min) und `GET https://search.openfoodfacts.org/search?q=<Marke Name>&langs=de&page_size=10&fields=…` (Suche, Limit 10/min, 6,5 s Abstand), User-Agent „Essenapp/0.1 (privat)“, kein Key. Lizenz: Datenbank **ODbL**, Einzelinhalte DbCL, Bilder CC BY-SA 3.0 → Quelle in der App nennen („Open Food Facts (ODbL)“), Daten nicht als eigene Datenbank weitergeben. Live geprüft 03.11.2026 (Fixtures `tests/fixtures/sources/openfoodfacts/`).

Normalisierung (`RawOffer` → `Offer`):
- Preis, Menge, Einheit → Grundpreis (€/kg, €/l, €/Stück)
- Kategorie: Lebensmittel / Drogerie / Haushalt / Sonstiges
- Zuordnung zu einer **Zutat** (z.B. „Hähnchenbrustfilet 400 g Packung“ → `haehnchenbrust`). Erst regelbasiert, Rest per Haiku; Ergebnisse cachen (gleicher Produktname → gleiche Zutat)
- EAN, falls vorhanden (für Watchlist per Barcode)

---

## 6. Datenmodell (Backend)

| Tabelle | Wichtige Felder |
|---|---|
| `household` | name, plz, persons, diet, allergies[], excluded_ingredients[], cuisines[], meal_types[], plan_days[], budget_food_week, budget_drugstore, nutrition_goal, max_cook_minutes, step_images (E55), variety{} (E59), storage_space klein/mittel/gross (E66) |
| `member` | household_id, name, token_hash, role (owner/member) |
| `household_store` | household_id, chain, store_ref (Filiale), enabled |
| `offer` | chain, store_ref/region, title, brand, category, price, regular_price, amount, unit, base_price, ean, valid_from, valid_to, image_url, ingredient_id?, product_id?, source, raw |
| `product` | key (Titel\|Marke\|Menge), title, brand, amount, unit, ean (E49), nutri_score, off_code, off_bio, off_vegan, off_vegetarian, off_checked_at (Open Food Facts, E70) |
| `price_point` | product_id, chain, store_ref, week, price, regular_price, base_price, is_offer, valid_from, valid_to (E49) |
| `ingredient` | slug, name, category, default_unit, default_price_per_unit (Normalpreis-Schätzung), nutrition_per_100 (kcal, protein, fett, kh, ballaststoffe, …), typical_pack_size |
| `recipe` | title, description, cuisine, meal_type, servings, prep_minutes, steps[], ingredients[] (JSON, Import: estimated), source (ai/user/instagram/web/shared), source_url, source_author, image_url, household_id (null = global), tags[] (E50), step_images[] (E55) |
| `recipe_favorite` | household_id, recipe_id (unique je Haushalt), member_id (E50) |
| `recipe_ingredient` | recipe_id, ingredient_id, amount, unit, optional |
| `meal_plan` | household_id, iso_week, status (draft/active), total_cost, generated_with (Parameter-Snapshot) |
| `meal_plan_entry` | plan_id, day, meal_type (+ snack/lunchbox/vorspeise), recipe_id, portions[], portions_total, scale (E50), guests (E60), cost_cents, locked |
| `shopping_list` | household_id, name, kind (household/oneoff), share_code (nur oneoff) |
| `shopping_item` | list_id, name, amount, unit, chain, offer_id?, checked, added_by, checked_by, source (plan/manual/basics/stockup/rhythm), defer_week? (Gruppe „Nächste Woche“, E65) |
| `invite` | household_id, code, expires_at |
| `rating` | recipe_id, member_id, stars (1–5), again (bald/irgendwann/nie), note, cooked_at (E50) |
| `food` | id = USDA fdc_id, description, data_type, kcal, protein, fat, carbs, fiber, sugar, salt pro 100 g (E51) |
| `ingredient_map` | ingredient_key (unique), food_id?, grams_per_piece?, confidence (E51) |
| `watch_item` | household_id, kind (produkt/zutat), label, brand, ean, image_url, category, max_price_cents?, max_base_price_cents? + base_unit (kg/l/stk), chains[], lasts_weeks?, last_bought?, rhythm_push_at?, rhythm_listed_at?, created_by (E67) |
| `watch_hit` | watch_item_id, offer_id, week, notified_at (1 Push je Eintrag und Woche, E67) |
| `member_profile` | member_id (unique), emoji, goal, kcal, protein_g, allergies[], dislikes[], lunchbox_days[], eats{meal_type: [7× bool]} (E46) |
| `pantry_item` | household_id, name, ingredient_key, amount?, unit, best_before?, is_basic, source (manual/list/scan/barcode/rest), location? (E63), updated_at (E46) |
| `member` (Push) | push_enabled, plan_prompt_enabled, plan_prompt_weekday, plan_prompt_time, quiet_hours{start,end}? (E47), lunchbox_push? (E61) |
| `push_device` | member_id, token (unique), environment, created_at, last_ok (E52) |
| `push_outbox` | member_id, title, message, click_url, thread_id, category, send_at (Ruhezeit, E52) |
| `job_run` | name (Job bzw. `plan_prompt:<member_id>`), ran_at (UTC), ok, info (E47) |
| `member_token` | member_id, token_hash (unique), label, created_at – gekoppelte Tokens (E53) |
| `pairing_code` | member_id, code (6 Ziffern, unique), expires_at, used_at (E53) |
| `ai_cost` | household_id?, kind (import/scan/cook_now/step_image/no_mood/substitute/budget), model, cost_cents, info, created_at (E57) |
| `weekly_basic` | household_id, name, amount?, unit – Frühstück & Snacks, jede Woche auf die Liste (E61) |

iOS speichert lokal nur einen Cache (aktueller Plan, Einkaufsliste offline abhakbar, Rezepte). Speicher: SwiftData, falls es unter xtool läuft, sonst GRDB (siehe Phase 1).

---

## 7. Plan-Generator (Kernlogik)

Eingabe: Haushalt-Einstellungen, Woche, gewählte Läden, Mahlzeiten-Slots, ggf. fixierte/gesperrte Gerichte.

1. **Angebote laden:** gültige Lebensmittel-Angebote der gewählten Läden für die Woche, mit Zutat-Zuordnung.
2. **Kandidaten aus eigenen Rezepten:** Score = Anteil der Zutatkosten, die im Angebot sind × Bewertungsgewicht × Wiederholungs-Malus (nicht öfter als alle N Wochen). Top-Kandidaten fest einplanen.
3. **KI ergänzt den Rest:** Claude bekommt kompakt: Angebotsliste (Zutat, Preis, Packungsgröße, Laden), Einstellungen, schon eingeplante Gerichte, Vorrat. Ausgabe als **strukturiertes JSON** (Tool-Schema): Gerichte mit Zutaten in Mengen, Schritten, Zeit, Küche, Mahlzeit.
4. **Validieren und Rechnen (deterministisch):**
   - Zutaten auf `ingredient` mappen (unbekannte → anlegen, Nährwerte nachschlagen)
   - **Kosten:** Angebotspreis oder Normalpreis; ganze Packungen werden gekauft → „Einkaufskosten“ vs. „Verbrauchskosten“, Reste werden ausgewiesen und bevorzugt in späteren Gerichten verwendet
   - **Nährwerte** pro Portion und pro Tag
   - Allergien/Ausschlüsse prüfen
5. **Reparaturschleife:** Budget überschritten oder Regeln verletzt → gezielte Rückmeldung an Claude, max. 2 Runden.
6. **Einkaufsliste** erzeugen, gruppiert nach Laden, mit Ersparnis gegenüber Normalpreis.

Weitere Operationen: einzelnes Gericht neu würfeln, Gericht fixieren, Gericht aus „Meine Rezepte“ einsetzen.

Lieblingsgerichte: Bewertung 4–5 Sterne → höheres Gewicht in Schritt 2; 1–2 Sterne → Rezept wird nicht mehr vorgeschlagen (ähnliche KI-Gerichte werden im Prompt als „nicht mögen“ übergeben).

„Rezept im Angebot“: Nach jedem Angebotsimport wird pro gespeichertem Rezept der Angebotsanteil berechnet; ab Schwelle (konfigurierbar, z.B. ≥ 40 % der Kosten) → Hinweis in der App / ntfy.

---

## 8. Benachrichtigungen

- **ntfy:** Backend sendet an ein Topic pro Mitglied (zufälliger, nicht erratbarer Name). Nutzer installiert die ntfy-App und abonniert das Topic (QR-Code in den Einstellungen).
- **Lokal (iOS):** Beim App-Start und per `BGAppRefreshTask` neue Treffer holen und lokal melden. Hintergrund-Zeitpunkt bestimmt iOS.
- Auslöser: Watchlist-Treffer, Rezept-im-Angebot, „Neuer Wochenplan bereit“ (z.B. Sonntag 18 Uhr, konfigurierbar).

---

## 9. xtool – bekannte Einschränkungen und Workarounds

Quelle: xtool-README, Docs und Issues (geprüft 2026-11-02, xtool v1.24.0).

| Thema | Stand | Vorgehen |
|---|---|---|
| Voraussetzungen | Swift **6.4** Toolchain, `usbmuxd`, **Xcode 27.1 .xip** (Download nur mit Apple-ID-Login im Browser) | Nutzer lädt das .xip herunter |
| iPhone in WSL | USB-Passthrough per **usbipd-win**; bei `AFCClient.Error.muxError` Verbindung über Windows-iTunes/Apple-Geräte-Dienst weiterleiten (`USBMUXD_SOCKET_ADDRESS` → Windows-Host:27015, siehe xtool Issue #19) | In Phase 1 beides ausprobieren |
| `xtool setup` auf WSL | kann bei 72 % beim Entpacken hängen (Issue #316); SDK braucht ~7 GB (`--slim` möglich) | Genug Platz in WSL, ggf. erneut starten |
| Login | Kostenlose Apple-ID über „Password“-Modus (nutzt private APIs). Einige Login/2FA-Probleme gemeldet | Ggf. xtool aktualisieren; Nutzer gibt Login selbst ein |
| **Asset-Catalogs (.xcassets)** | Funktionieren auf Linux nicht (kein `actool`, Issue #310, PR #325 offen) | Kein `.xcassets`. Bilder als normale Ressourcen; App-Icon per `iconPath` (E26) |
| **SwiftData `@Model`** | **Geht nicht** (Plugin `SwiftDataMacros` fehlt, getestet mit 1.24.0) | JSON-Cache (E25) |
| Widgets/Extensions | Unterstützt, aber offene Bugs (#313, #379) | Erst Phase 6, vorher Issue-Stand prüfen |
| Simulator | Gibt es nicht | Tests direkt auf dem iPhone, Logik in testbare Swift-Pakete auslagern |
| `xtool.yml` | Bekannte Keys: `version`, `bundleID`, `product`, `entitlementsPath`, `extensions`. Falsch geschriebene Keys werden **still ignoriert** | Keys genau prüfen |
| Entitlements | Nicht unterstützte Capabilities scheitern erst bei der Installation | Nur nötige Entitlements, keine Push/iCloud |
| 7-Tage-Signatur | Kostenlose Apple-ID | Erinnerung (ntfy) alle 6 Tage: „App neu installieren“ |

---

## 10. Phasen

Aufgaben, 👤-Schritte und Definition of Done je Phase stehen in [`tasks/`](tasks/README.md):
0 UI-Planung · 1 Fundament · 2 Angebote · 3 Wochenplan · 4 Personalisierung + Web · 5 Drogerie & Alarme · 6 Extras · 7 VPS.

---

## 11. Arbeitsregeln (für Claude)

- iOS-Code eigenständig schreiben; dem Nutzer nur erklären, **was er selbst tun muss** (Gerät anschließen, Vertrauen bestätigen, Login, Downloads).
- Passwörter, Apple-ID-Logins und 2FA-Codes gibt der Nutzer **selbst** ein.
- Secrets nur in `backend/.env` (nicht ins Git), `.env.example` pflegen.
- Backend-Logik mit pytest testen; Händler-Adapter mit gespeicherten Fixtures.
- iOS: Logik (Rechnen, Parsen) in reine Swift-Typen ohne UI auslagern, damit sie testbar ist; UI auf dem Gerät prüfen.
- Kein `.xcassets`, keine Push/iCloud-Entitlements (siehe Abschnitt 9).
- Datenquellen: nichts erfinden, Endpunkte recherchieren und in Abschnitt 5 dokumentieren; schonend abrufen.
- KI-Kosten im Blick: Prompts kompakt, Zuordnungen cachen, Modell per ENV.
- Nach jeder Phase: Playbook aktualisieren (Entscheidungslog, Erkenntnisse, Phase abhaken).

---

## 12. Offene Punkte / Risiken

- [ ] Welche Händler-Datenquellen funktionieren für die konfigurierte PLZ stabil? (Phase 2)
- [ ] SwiftData oder GRDB? (Phase 1)
- [ ] App-Icon ohne Asset-Catalog (Phase 1)
- [ ] WSL ↔ iPhone: usbipd oder iTunes-Relay? (Phase 1)
- [ ] Normalpreise für Zutaten ohne Angebot: Quelle/Schätzung (Phase 3)
- [x] Datenquelle Nährwerte: USDA FoodData Central, gemeinfrei/CC0 (E51)
- [ ] VPS-Anbieter und Domain (Phase 7)

## 13. Fortschritt

Siehe [`tasks/README.md`](tasks/README.md).
