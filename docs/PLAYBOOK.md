# Essenapp – Playbook

Arbeitsgrundlage für die Entwicklung. Enthält Ziele, Entscheidungen, Architektur, Datenmodell, Phasen und Arbeitsregeln.
Wird bei jeder Entscheidung aktualisiert (Abschnitt „Entscheidungslog“).

Stand: 2026-11-02

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
| E9 | Benachrichtigungen über **ntfy** + lokale Notifications | Ersatz für APNs (E2) |
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

Normalisierung (`RawOffer` → `Offer`):
- Preis, Menge, Einheit → Grundpreis (€/kg, €/l, €/Stück)
- Kategorie: Lebensmittel / Drogerie / Haushalt / Sonstiges
- Zuordnung zu einer **Zutat** (z.B. „Hähnchenbrustfilet 400 g Packung“ → `haehnchenbrust`). Erst regelbasiert, Rest per Haiku; Ergebnisse cachen (gleicher Produktname → gleiche Zutat)
- EAN, falls vorhanden (für Watchlist per Barcode)

---

## 6. Datenmodell (Backend)

| Tabelle | Wichtige Felder |
|---|---|
| `household` | name, plz, persons, diet, allergies[], excluded_ingredients[], cuisines[], meal_types[], plan_days[], budget_food_week, budget_drugstore, nutrition_goal, max_cook_minutes |
| `member` | household_id, name, token_hash, role (owner/member) |
| `household_store` | household_id, chain, store_ref (Filiale), enabled |
| `offer` | chain, store_ref/region, title, brand, category, price, regular_price, amount, unit, base_price, ean, valid_from, valid_to, image_url, ingredient_id?, source, raw |
| `ingredient` | slug, name, category, default_unit, default_price_per_unit (Normalpreis-Schätzung), nutrition_per_100 (kcal, protein, fett, kh, ballaststoffe, …), typical_pack_size |
| `recipe` | title, description, cuisine, meal_type, servings, prep_minutes, difficulty, steps[], source (ai/user/import), household_id (null = global), tags[] |
| `recipe_ingredient` | recipe_id, ingredient_id, amount, unit, optional |
| `meal_plan` | household_id, iso_week, status (draft/active), total_cost, generated_with (Parameter-Snapshot) |
| `meal_plan_entry` | plan_id, day, meal_type, recipe_id, servings, uses_leftover_from? |
| `shopping_item` | plan_id/household_id, ingredient_id?, offer_id?, chain, text, amount, checked, added_by |
| `rating` | recipe_id, member_id, stars (1–5), cooked_at, comment |
| `watch_item` | household_id, label, query / ean / brand, category, max_price?, chains[] |
| `watch_hit` | watch_item_id, offer_id, notified_at |
| `pantry_item` | household_id, ingredient_id, amount?, unit? (Phase 6) |

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
- [ ] Datenquelle Nährwerte: Open Food Facts vs. BLS (Lizenz prüfen) (Phase 3)
- [ ] VPS-Anbieter und Domain (Phase 7)

## 13. Fortschritt

Siehe [`tasks/README.md`](tasks/README.md).
