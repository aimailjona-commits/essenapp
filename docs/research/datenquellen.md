# Datenquellen für Wochenangebote (Prospekt-Angebote)

Stand: 02.11.2026 (KW 45). Beispiel-Standort: Köln, PLZ 50667 (lat 50.9407, lng 6.95991).
Zweck: privater, nicht-kommerzieller Familien-Essensplaner. Keine Anmeldung, keine Accounts und keine personenbezogenen Daten an Dritte. Bot-Schutz wurde nirgends umgangen.

**Legende zur Belegung**
- ✅ **verifiziert**: Ich habe die Anfrage am 02.11.2026 selbst ausgeführt, die Antwort liegt als Fixture vor.
- 📄 **aus Quelle**: Steht so im Quellcode oder in der Doku eines Repos oder Dienstes (verlinkt). Ich habe es nicht selbst abgerufen.
- ❓ **unverifiziert**: Nur ein Hinweis aus Drittquellen oder eine Vermutung. Vor der Nutzung prüfen.

Die Fixtures liegen unter `backend/tests/fixtures/sources/<quelle>/`. Eine Liste steht am Ende des Dokuments.

---

## Übersicht

| Händler | Quelle | Format | Filialbezug | Stabilität | Empfehlung |
|---|---|---|---|---|---|
| **REWE** | kaufDA `brochures/{id}/pages` (Prospekt „Dein Markt“ je Markt) ✅. Daneben Publitas `spreads.json` ✅ (nur Text und Bilder) und die App-API `mobile-clients-api.rewe.de` 📄 (mTLS) | JSON | ja: Marktnummer (`closestStore.externalId` = REWE-Markt-ID) | kaufDA mittel-gut. App-API fragil (Zertifikat aus der APK) | **kaufDA**. App-API nur optional |
| **ALDI SÜD** | kaufDA `/api/search?query=ALDI` ✅. Eigene Website blockt per Akamai (403) ✅ | JSON | regional, nicht filialgenau | mittel | **kaufDA-Suche** |
| **ALDI Nord** | `aldi-nord.de/angebote.html` → `__NEXT_DATA__.props.pageProps.apiData` → `OFFER_GET` ✅ | JSON in HTML | nein, national | gut (SSR, kein Bot-Schutz festgestellt) | **direkt** |
| **Lidl** | kaufDA `brochures/{id}/pages` ✅ (467 Angebote). Lidl-eigenes `endpoints.leaflets.schwarz/v4/flyer` ✅ liefert PDF, Seiten und nur Online-Shop-Artikel | JSON | regional (Lidl `region_id` bzw. kaufDA `closestStore`) | gut | **kaufDA** für Lebensmittel, Lidl-Flyer-API für PDF und Seiten |
| **dm** | kaufDA `/api/search?query=dm-drogerie markt` ✅ („dynamic_brochure“, `pages` ist leer) | JSON | nein | mittel | **kaufDA-Suche**. dm-eigene API nicht gefunden ❓ |
| **Rossmann** | kaufDA `brochures/{id}/pages` ✅ (302 Angebote). rossmann.de hat eine JS-Challenge ✅ | JSON | Filiale über kaufDA | mittel | **kaufDA** |
| **EDEKA** | kaufDA `brochures/{id}/pages` ✅ (`closestStore.externalId` z. B. `EDEKA-RR_10008482`). edeka.de blockt per Akamai ✅. App-API 📄 (OAuth client_credentials) | JSON | ja | kaufDA mittel. App-API riskant | **kaufDA** |
| **Kaufland** | `filiale.kaufland.de/angebote/uebersicht.storeName=DE4130.html` → `window.SSR[...]` (OfferTemplate) ✅. Filialliste `/.klstorefinder.json` ✅ | JSON in HTML | ja (`storeName` = `DE<Nr>`) | gut | **direkt** |
| **Penny** | `penny.de/.rest/market` ✅ und `penny.de/.rest/offers/by-category/{KW}/{kategorie}?region={sellingRegion}` ✅ | JSON | ja (Verkaufsregion des Markts) | gut | **direkt** |
| **Netto Marken-Discount** | kaufDA `brochures/{id}/pages` ✅ (399 Angebote). netto-online.de blockt per Akamai ✅ | JSON | Filiale über kaufDA | mittel | **kaufDA** |
| *(Netto „Scottie“, netto.de)* | `netto.de/angebote/` HTML ✅. **Achtung: anderer Händler (Salling Group)**, nicht Netto Marken-Discount | HTML | nein | mittel | nur falls benötigt |
| **kaufDA/Bonial** (Aggregator) | `kaufda.de/api/shelf` ✅, `kaufda.de/api/search` ✅, `content-viewer-be.kaufda.de/v1/brochures/{id}[/pages]` ✅ | JSON | lat/lng → nächste Filiale je Händler | mittel-gut, ohne Key | **Primärquelle** |
| **Marktguru** (Aggregator) | `api.marktguru.de/api/v1/offers/search` 📄 mit `x-apikey` und `x-clientkey` aus der Startseiten-Config | JSON | PLZ (`zipCode`) | mittel | Fallback. Live-Abruf wurde in dieser Session blockiert (s. u.) |

**Empfehlung in einem Satz:** Zuerst einen **kaufDA-Adapter** bauen, der REWE, Lidl, EDEKA, Kaufland, Penny, Netto MD, Rossmann (Prospekt-Seiten) sowie ALDI SÜD und dm (Suche) abdeckt. Danach Direkt-Adapter für **ALDI Nord, Penny und Kaufland**, weil sie sauberer und robuster sind. Marktguru dient als zweite Aggregator-Quelle.

---

## 0. Gemeinsame Basis: kaufDA / Bonial (Aggregator, empfohlene Primärquelle)

kaufDA (Bonial) veröffentlicht die Prospekte fast aller Händler. Die eigene Web-App nutzt JSON-Endpunkte ohne API-Key. Alle folgenden Abrufe sind ✅ verifiziert, mit einfachem Browser-User-Agent und ohne Cookies.

### 0.1 Prospekte am Standort: `GET https://www.kaufda.de/api/shelf`
```
GET https://www.kaufda.de/api/shelf?lat=50.940700&lng=6.959910&size=50&page=0&sectorIds=
```
- Liefert `{"contents":[...], "page":{"size":50,"totalElements":101,"totalPages":3,"number":0}}`.
- Pro Eintrag gibt es `contentType` (`brochure`, `brochurePremium`, …) und `content` mit `contentId` (UUID), `title`, `publisher {id,name}`, `validFrom`, `validUntil`, `pageCount` und **`closestStore`** mit `id`, `externalId`, `street`, `zip`, `city`, `latitude`, `longitude`.
- **`closestStore.externalId` ist die händlereigene Filial-ID**, zum Beispiel REWE `1763159`, Penny `1930734`, Lidl `5741`, Kaufland `4130`, EDEKA `EDEKA-RR_10008482`, Rossmann `2815`, Netto MD `2575`.
- Publisher-IDs (gesehen): REWE `DE-1062`, Lidl `DE-1013`, Penny `DE-1050`, Netto Marken-Discount `DE-1034`, EDEKA `DE-220164`, E center `DE-3443181`, Marktkauf `DE-1017`, Kaufland `DE-424316869`, dm `DE-909`, Rossmann `DE-1064`.
- In Köln waren am 02.11.2026 kein ALDI-Prospekt im Shelf, wohl aber ALDI-SÜD-Angebote in der Suche (siehe 0.3).

Gekürztes Beispiel (`kaufda/shelf_koeln_50667_page0.json`):
```json
{"placement":"ad_placement__shelf_fixed_position_1","contentType":"brochure",
 "content":{"id":2501310791,"contentId":"781ac646-cf5a-47a2-bc27-dec0ad1cc59f",
  "closestStore":{"id":171808550,"externalId":"5741","name":"Lidl","street":"Neumarkt",
                  "streetNumber":"8-10","zip":"50667","city":"Köln-Altstadt-Süd"},
  "title":"LIDL LOHNT SICH","type":"BROCHURE",
  "validFrom":"2026-11-01T23:00:00.000+0000","validUntil":"2026-11-07T22:00:00.000+0000",
  "publisher":{"id":"DE-1013","name":"Lidl","type":"RETAILER"},"pageCount":79}}
```

### 0.2 Strukturierte Angebote eines Prospekts: `GET content-viewer-be.kaufda.de/v1/brochures/{contentId}/pages`
```
GET https://content-viewer-be.kaufda.de/v1/brochures/{contentId}/pages?partner=kaufda_web&brochureKey=&lat=50.940700&lng=6.959910
GET https://content-viewer-be.kaufda.de/v1/brochures/{contentId}?partner=kaufda_web&lat=...&lng=...   (nur Metadaten)
```
Die Antwort ist `{"contents":[{number, images, linkOuts, offers:[{content:{...}}]}]}`.

Zählung vom 02.11.2026 in Köln:

| Prospekt | Seiten | Angebote | davon mit `SALES_PRICE` |
|---|---|---|---|
| REWE „Dein Markt“ (Markt 1763159) | 24 | 74 | 74 |
| Lidl „LIDL LOHNT SICH“ | 79 | 467 | 460 |
| Kaufland | 68 | 418 | 395 |
| Netto MD | 72 | 399 | 369 |
| Rossmann | 22 | 302 | 286 |
| Penny | 50 | 297 | 285 |
| EDEKA | 8 | 75 | 72 |
| dm („dynamic_brochure“) | 0 | 0 | 0 |

Felder eines Angebots: `content.id`, `content.image`, `publisher`, `parentContent.page.number`, außerdem:
- `products[]` mit `name`, `brandName`, `description[].paragraph` (Menge und Einheit stehen im Freitext), `images[]` und `categoryPaths[]`
- `deals[]` mit `type` ∈ `SALES_PRICE | REGULAR_PRICE | SPECIAL_PRICE | RECOMMENDED_RETAIL_PRICE | OTHER`, `min`, `max`, `currencyCode`, `priceByBaseUnit` (Grundpreis als Text), `conditions` und `description` (zum Beispiel „0,20 € Bonus“)
- `publicationProfiles[].validity.startDate` und `endDate`

EAN gibt es nicht.

Gekürztes Beispiel (`kaufda/brochure_pages_edeka.json`):
```json
{"id":"32d096d4-9651-4bbe-8925-71c7c787c7cc","publisher":"EDEKA",
 "product":{"name":"Bree","brandName":null,
   "description":[{"paragraph":"Frankreich / Deutschland versch. Sorten 0,75 l Flasche"}]},
 "deals":[
   {"type":"SALES_PRICE","conditions":[{"other":"Je"}],"currencyCode":"EUR",
    "max":2.88,"min":2.88,"priceByBaseUnit":"(1 l = € 3.84)"},
   {"type":"REGULAR_PRICE","currencyCode":"EUR","max":5.49,"min":5.49}],
 "publicationProfiles":[{"validity":{"startDate":"2026-11-01T23:00:00.000+0000",
                                     "endDate":"2026-11-07T22:59:59.000+0000"}}],
 "image":"https://content-media.bonial.biz/32d096d4-.../main.jpg"}
```

### 0.3 Suche: `GET https://www.kaufda.de/api/search`
```
GET https://www.kaufda.de/api/search?query=ALDI&lat=50.940700&lng=6.959910&offset=0&limit=24
```
- Antwort: `{"searchResults":{"contents":{"brochures":[...],"offers":[...]},"metadata":{"contentCount":{"offer":150,"brochure":10},"filters":[...]}}}`.
- Ein Offer hat `title`, `brand`, `description`, `categoryPaths`, `validFrom`, `validUntil`, `prices{mainPrice, secondaryPrice, mainPriceFormatted, priceByBaseUnit, conditions}`, `offerImages.url{thumbnail,normal,large}`, `publisherName` und `parentContent{id,type,page}`.
- Über die Suche kommen die Händler, deren Prospekt nicht über `pages` erreichbar ist: **dm** (`query=dm-drogerie markt`, 150 Angebote) und **ALDI SÜD** (`query=ALDI`). Blättern geht über `offset`.
- ❓ Den Parameternamen für den Publisher-Filter (die Werte stehen in `metadata.filters`) habe ich nicht verifiziert. Bis dahin clientseitig nach `publisherName` filtern.

### 0.4 SEO-Seiten mit `__NEXT_DATA__` (Alternative, ✅)
`https://www.kaufda.de/{Stadt}/Angebote/{Stichwort}`, zum Beispiel `/Koeln/Angebote/Milch`. Das HTML enthält `<script id="__NEXT_DATA__">`. Unter `props.pageProps.pageInformation` stehen `offers.main.items[]` (gleiche Felder wie in 0.3), `brochures` und `location` mit `{city, zip:"50667", lat, lng}`. Die Seite eignet sich, um aus einem Stadtnamen Koordinaten zu bekommen. Händler-Filialseiten haben das Muster `/Filialen/{Stadt}/{Händler-Straße}/v-f{id}`.

### PLZ → Koordinaten
kaufDA braucht `lat` und `lng`. Die Repos lösen das unterschiedlich:
- `smlfg/angebote-cli` nutzt `api.zippopotam.us/de/{plz}` 📄.
- `vertexitde/kaufda-mcp` nutzt Nominatim 📄.

Für eine Familien-App reicht es, die Koordinaten **einmal in der Konfiguration** zu hinterlegen. Dann geht keine PLZ an Dritte.

### Open-Source-Projekte
| Projekt | Letzte Aktivität | Erkenntnis |
|---|---|---|
| [vertexitde/kaufda-mcp](https://github.com/vertexitde/kaufda-mcp) (Python) | 14.10.2026 | `client.py` nutzt `/api/search`, `/api/suggest`, `/api/shelf` und `content-viewer-be…/v1/brochures/{id}` sowie `/pages` mit `partner=kaufda_web`. Hat Caching und begrenzt auf 6 parallele Anfragen |
| [smlfg/angebote-cli](https://github.com/smlfg/angebote-cli) (Python) | 30.10.2026 | `__NEXT_DATA__`-Parser, `/api/search`, Brochure-API. Rate-Limit 1 Anfrage/s |
| [mwurm/kaufda-scraper](https://github.com/mwurm/kaufda-scraper) (Python) | 27.05.2026 | Ältere Endpunkte `/webapp/api/slots/offerSearch` und `brochureSearch` (laut robots.txt **disallowed**) sowie `/pages` für ALDI SÜD |
| [mreimbold/kaufda-cli](https://github.com/mreimbold/kaufda-cli) (Go) | 03.01.2026 | Nur `__NEXT_DATA__` der SEO-Seiten |

### Stabilität, Schutz und ToS
- Kein Key, keine Cookies, kein Cloudflare- oder Akamai-Block bei allen Abrufen dieser Session.
- Die Endpunkte sind intern und können sich ändern. Die Feldnamen sind aber über mehrere Repos hinweg konsistent.
- `robots.txt` von kaufda.de verbietet `/webapp/`, `/api/febe/`, `/api/frontend/` und `/contentViewer/`. Für `/api/search` und `/api/shelf` gibt es keine explizite Regel. `content-viewer-be.kaufda.de` ist ein eigener Host.
- Die AGB von kaufDA habe ich nicht geprüft. Die Daten gehören Bonial und den Händlern. Deshalb nur privat nutzen, nicht weiterverbreiten und sparsam abrufen: 1× pro Tag Shelf, danach nur neue `contentId`s abrufen und cachen. Wenige Anfragen mit 1–2 s Abstand.
- Die Prospekt-Angebote sind teils **unvollständig** gegenüber dem Händler. REWE kommt zum Beispiel auf 74 Angebote, die REWE-App zeigt typischerweise deutlich mehr.

---

## 1. REWE

**Filialbezug:** Angebote sind marktspezifisch. Die Markt-ID (REWE „wwIdent“, z. B. `1763159`) liefert kaufDA als `closestStore.externalId` (0.1).

### 1a. kaufDA (empfohlen) ✅
Im Shelf alle Einträge mit `publisher.id == "DE-1062"` nehmen. Es gibt mehrere „Dein Markt“-Prospekte, je einen pro nahem Markt mit eigener `closestStore.externalId`. Die Angebote kommen über `/v1/brochures/{contentId}/pages` (siehe 0.2). Fixture: `kaufda/brochure_pages_rewe_ceb30b11.json` (74 Angebote, alle mit Preis).

### 1b. Publitas-Prospekt (Seitenbilder und OCR-Text) ✅
```
GET https://view.publitas.com/rewe-markt/rewe_{JJJJ}_wk{KW}_{marktId}/spreads.json
   z. B. rewe_2026_wk45_1763159
```
- Quelle: [beihnaheohnmacht/kaufland-angebote `rewe.mjs`](https://github.com/beihnaheohnmacht/kaufland-angebote), letzte Aktivität 02.11.2026. Laut Kommentar im Code wird die KW sowohl mit als auch ohne führende Null probiert.
- Antwort: Liste von Spreads `{pages:[{images:{at2400..at600}, screenshots, text, number, id}]}`.
- `text` ist **unstrukturierter OCR-Text**, zum Beispiel `"Aktion\nQuäse\nKörniger Frischkäse\nje 200-g-Becher\n(1 kg = 8.45)\n…1.69"`. Preise und Produkte müssen heuristisch zugeordnet werden. Das Repo prüft die Preise gegen den Grundpreis.
- Gut für die Anzeige des Prospekts. Als Datenquelle nur zweite Wahl.

### 1c. REWE-App-API (`mobile-clients-api.rewe.de`) 📄, ohne Zertifikat ✅ 403
- Endpunkte laut [ByteSizedMarius/rewerse-engineering](https://github.com/ByteSizedMarius/rewerse-engineering) (`pkg/util.go`, `markets.go`, `discounts.go`; 93★; letzte Aktivität 29.09.2026; „Supported APK 5.18.1“) und [FaserF/ha-rewe](https://github.com/FaserF/ha-rewe) (`custom_components/rewe/api.py`; 02.11.2026):
  - Marktsuche: `GET https://mobile-clients-api.rewe.de/api/stationary-markets?search=<PLZ|Ort>`. Liefert `data.marketSearch.markets[]` mit `wwIdent`, `name`, `street`, `zipCode`, `city`, `location{latitude,longitude}`, `openingInfo`, …
  - Marktdetails: `GET …/api/stationary-markets/{marketId}`
  - Angebote: `GET …/api/stationary-offers/{marketId}`. Liefert `data.offers{defaultWeek, current{fromDate,untilDate,handout{images[]},categories[{title,offers[]}]}, next}`. Ein Offer hat `title`, `subtitle`, `images[]`, `priceData{price:"1,99 €", regularPrice}`, `loyaltyBonus{bonusType,bonusValue}`, `detail{contents[{header,titles}], nutriScore}` und `rawValues{categoryTitle, nan (Artikelnr.), flyerPage}`.
  - Header: `user-agent: REWE-Mobile-Client/5.18.1.54501 Android/14 Phone/<Gerät>`, `x-instana-android: <uuid>`, bei manchen Endpunkten zusätzlich `rdfa` und `correlation-id`.
- **Seit März 2024 Cloudflare-mTLS.** Man braucht das Client-Zertifikat `res/raw/mtls_prod.pfx` aus der REWE-APK. Die Extraktion ist in rewerse `docs/readme.md` beschrieben, ha-rewe automatisiert sie per CI-Workflow. Ohne Zertifikat antwortet der Server mit **403** (✅ selbst geprüft).
- Die ältere API `mobile-api.rewe.de/api/v3/all-offers?marketCode=…` ([3nt3/monster-discount](https://github.com/3nt3/monster-discount), 2023; [foo-git/rewe-discounts](https://github.com/foo-git/rewe-discounts), 105★, letzte Aktivität 06/2024) ist laut rewerse seit dem mTLS-Wechsel kaputt.
- Python: `pip install rewerse` (FFI auf Go-Lib, nur Linux x86_64 und Windows x86_64) oder `curl_cffi` mit `cert=(pem,key)` wie in ha-rewe.
- **Bewertung:** Diese Variante liefert die vollständigsten und besten Daten (inkl. Kategorien und Bonus). Sie verlangt aber, ein aus der App extrahiertes Zertifikat zu verwenden. Das ist eine ToS-Grauzone und wohl nicht im Sinne von REWE, zudem fragil (Zertifikat- und App-Updates). **Nicht als Erstes umsetzen.** Allenfalls als optionaler Adapter, wenn der Nutzer das Zertifikat selbst bereitstellt.
- rewe.de selbst liefert ✅ 403 mit Captcha- und Challenge-Seite (`/angebote/`). Die alte Route `www.rewe.de/api/marketsearch` gibt ✅ 404.

---

## 2. ALDI SÜD und ALDI NORD

### 2a. ALDI Nord: direkt (empfohlen) ✅
```
GET https://www.aldi-nord.de/angebote.html
→ <script id="__NEXT_DATA__"> → props.pageProps.apiData (JSON-String!) → json.loads → [["OFFER_GET", {req:{locale:"de",week:"current"}, res:{...}}]]
```
- `res.categories[]` enthält `title` (z. B. „Aktion Mo. 2.11.“), `startDate`, `endDate` und `content[]` mit `title` und `productIds[]`.
- `res.algoliaDataMap{productId: {...}}` hat 284 Produkte. Felder pro Produkt: `name`, `brandName`, `salesUnit` (z. B. „180-g-Dose“), `currentPrice{priceValue, strikePrice.strikePriceValue, basePrice[{basePriceValue, basePriceScale}], validFrom/validUntil (Unix)}`, `promotionPrices[]` mit `validFromLocalDate` und `validUntilLocalDate`, `assets[{type,url}]`, `categoryIDs`, `productSlug`, `isDepositProduct` und `depositValue`. Eine EAN gibt es nicht.
- `res.weekSwitchPer = "Sunday"`.
- National, kein Filialbezug. `robots.txt` sperrt `/angebote.html` nicht. Bot-Schutz habe ich nicht festgestellt.
- Quelle: Beschreibung im Apify-Actor [nerdrx/de-supermarket-offers](https://apify.com/nerdrx/de-supermarket-offers) 📄, von mir ✅ verifiziert.
- Fixture: `aldi-nord/angebote_current_apiData.json`

```json
{"name":"Erdnüsse","brandName":"ÜLTJE","salesUnit":"180-g-Dose","productSlug":"erdnuesse-287",
 "currentPrice":{"priceValue":1.39,"strikePrice":{"strikePriceValue":2.49},
   "basePrice":[{"basePriceValue":7.72,"basePriceScale":"kg"}],
   "priceTagLabels":{"promoText1":"-44 %"},"validFrom":1793574000,"validUntil":1794092399},
 "promotionPrices":[{"priceValue":1.39,"validFromLocalDate":"2026-11-02","validUntilLocalDate":"2026-11-07"}],
 "assets":[{"type":"primary","url":"https://s7g10.scene7.com/is/image/aldinord/0287_45_2026_..."}],
 "categoryIDs":["Angebote"],"objectID":"287"}
```
Alternativ ist ALDI Nord bei kaufDA gelistet. In Köln war nur eine Filiale in Solingen in der Nähe.

### 2b. ALDI SÜD
- `www.aldi-sued.de` (Seite und sogar `robots.txt`) antwortet ✅ mit **403 Akamai „Access Denied“** auf Skript-Clients. Nicht umgehen.
- ❓ `api.aldi-sued.de/v3/product-search` mit Kategorie „Wochenangebote“ und optionalem `servicePoint` wird nur in der Apify-Beschreibung (nerdrx) genannt. Parameter, Header und Erreichbarkeit habe ich **nicht verifiziert**.
- **Empfehlung: kaufDA-Suche** `query=ALDI` (✅ 25 ALDI-SÜD-Treffer in der ersten Seite, Fixture `kaufda/api_search_ALDI_koeln.json`). Alternativ Marktguru (`advertisers[].uniqueName == "aldi-sued"` 📄).
- [Tech-FZ/Cheapie-Scraper](https://github.com/Tech-FZ/Cheapie-Scraper) hat einen ALDI-SÜD-Scraper, ist aber seit 02/2024 inaktiv und stammt aus der Zeit vor dem Website-Relaunch.

---

## 3. Lidl Deutschland

### 3a. kaufDA (empfohlen für Lebensmittel) ✅
Im Shelf `publisher.id == "DE-1013"`, darunter auch der Folgewochen-Prospekt. `/pages` liefert 467 Angebote mit Preisen. Fixture: `kaufda/brochure_pages_lidl.json`.

### 3b. Lidl-eigene Flyer-API (Schwarz-Gruppe „leaflets“) ✅
1. Die Übersicht `GET https://www.lidl.de/c/online-prospekte/s10005610` enthält Links wie `/l/prospekte/aktionsprospekt-02-11-2026-07-11-2026-d34d64/ar/0`. Der Slug ist der `flyer_identifier`.
2. Abruf: `GET https://endpoints.leaflets.schwarz/v4/flyer?flyer_identifier=aktionsprospekt-02-11-2026-07-11-2026-d34d64`
   - Laut Viewer-JS (`lidl.leaflets.schwarz/assets/index-*.js`, Funktion mit `flyer_identifier`) sind optional `region_id`, `region_code` und `store_id` möglich. `VITE_API_URL="https://endpoints.leaflets.schwarz"`.
3. Antwort `flyer`: `id`, `name`, `title`, `startDate`, `endDate`, `offerStartDate`, `offerEndDate`, `pdfUrl` und `hiResPdfUrl` (ca. 84 MB), `pages[75]{number,image,thumbnail,links,keyWords,altText}`, `regions[{code:"0"}]`, `relatedFlyers[]` sowie **`products{}`** (192 Einträge) mit `productId`, `title`, `brand`, `price` (String), `image`, `url`, `categoryPrimary`, `wonCategoryPrimary` und `description`.
4. **Einschränkung:** `products` enthält fast nur **Online-Shop-Artikel** (Non-Food, Wein). Lebensmittel-Angebote stehen dort nicht strukturiert, ich habe nur 1 Treffer gefunden. Die Quelle eignet sich für PDF, Seitenbilder und Gültigkeit, nicht für Lebensmittel.
- Quelle für das Muster: [beihnaheohnmacht/kaufland-angebote `lidl.mjs`](https://github.com/beihnaheohnmacht/kaufland-angebote) und nerdrx/Apify 📄, von mir ✅ verifiziert.
- Fixture: `lidl/leaflets_v4_flyer_aktionsprospekt_2026-11-02.json`
- ❓ Die Produktsuche-API von lidl.de (laut Apify-Actors „Lidl's own JSON search API“) habe ich nicht verifiziert.
- Bot-Schutz: keiner festgestellt. `robots.txt` sperrt nur `/user-api/*` und `/cdn/assets/cwv/`.

---

## 4. dm-drogerie markt

- dm arbeitet nicht mit einem klassischen Wochenprospekt. Es gibt „Aktuelle Angebote“ (bei kaufDA gültig 01.11.–15.11.2026, also etwa 2 Wochen) und Monatsaktionen.
- **kaufDA:** Der dm-Prospekt ist eine `dynamic_brochure`. `/pages` liefert `{"contents":[]}` ✅. Die **Suche** `GET https://www.kaufda.de/api/search?query=dm-drogerie%20markt&lat=…&lng=…&offset=0&limit=24` liefert dagegen dm-Angebote ✅ (`contentCount.offer: 150`, `publisherName: "dm-drogerie markt"`, `parentContent.type: "dynamic_brochure"`). Fixture: `kaufda/api_search_dm_koeln.json`.
- **dm.de direkt:** `https://www.dm.de/angebote` ist eine SPA-Hülle (11 KB) mit reCAPTCHA-Enterprise-Script. Der Content wird über `window.contentConfig` und Fetcher geladen, die zur Laufzeit registriert werden (Kontext `rootpage-dm-shop-de-de` im Bundle `assets.dm.de/content-ui/…/content-full.min.js`). Meine Vermutung `content.services.dmtech.com/rootpage-dm-shop-de-de/angebote` ergab ✅ **404**. Den echten Endpunkt habe ich nicht gefunden ❓. Auch auf GitHub gab es keinen aktuellen dm-Angebots-Client.
- Marktguru führt dm laut eigener Retailer-Liste wahrscheinlich ebenfalls ❓.
- **Empfehlung:** kaufDA-Suche. Für den Essensplaner ist dm ohnehin nachrangig (wenig Lebensmittel).

---

## 5. Rossmann

- `https://www.rossmann.de/de/angebote` liefert ✅ eine **JS-Bot-Challenge** (`/_fs-ch-…/script.js`, ca. 3 KB) und keine Inhalte. Nicht umgehen.
- **kaufDA:** Rossmann `DE-1064` mit zwei Prospekten „Mein Drogeriemarkt“ (01.–06.11. und 01.–13.11.), `closestStore.externalId: "2815"`. `/pages` liefert ✅ 302 Angebote mit Preisen. Fixture: `kaufda/brochure_pages_rossmann.json`.
- GitHub: nur Sales-Forecasting-Projekte (Kaggle-„Rossmann“), kein Angebots-Client gefunden. Apify-Actors erwähnen „anti-bot protection“ 📄.
- **Empfehlung:** kaufDA.

---

## 6. Weitere Händler

### 6.1 Penny: direkt (empfohlen) ✅
1. **Marktliste (alle Märkte, ohne PLZ-Parameter):** `GET https://www.penny.de/.rest/market` liefert ca. 3,8 MB und 2128 Märkte mit `wwIdent`, `marketName`, `zipCode`, `city`, `latitude`, `longitude`, **`sellingRegion`** (z. B. `15A-02-35`), `nextWeekSellingRegion`, `handoutRegion` und Öffnungszeiten. Filtern nach PLZ oder Distanz passiert lokal, die Liste wird gecacht.
2. **Kategorien und KW** stehen im HTML von `GET https://www.penny.de/angebote`: `data-current-week="2026-45"`, `data-next-week="2026-46"`, `data-category-name="fleisch-und-wurst"` usw. Das Pfadmuster stammt aus dem JS-Chunk `category-offers.*.js`: `${restUri}/offers/by-category/${week}/${categoryName}?region=${sellingRegion}`.
3. **Angebote:** `GET https://www.penny.de/.rest/offers/by-category/2026-45/fleisch-und-wurst?region=15A-02-35`
   - `offerTiles[]` mit `title`, `quantity` („je 1.000-g-Packung“), `price` („3.99“), `originalPrice`, `discountPercentage`, `basePrice`, `lowestPrice30Days`, `imageRendition{tileXs…tileXl}` und `productData` (JSON-String mit `id`, `category`, `price`, `rrp`, `savingsPercent`, `promotion`).
- `robots.txt` erlaubt alles (`Allow: /`). Kein Bot-Schutz festgestellt.
- Die Gültigkeit pro Kachel ist nicht explizit angegeben. Sie ergibt sich aus der KW und dem Kategorie-Präfix (`ab-montag--`, `ab-donnerstag--`, `ab-freitag--`, siehe `data-category-id`).
- Hinweis: Meine erste Variante mit der `data-category-id` (`ab-montag--fleisch-und-wurst`) ergab 404. Richtig ist `data-category-name`.
- Fixtures: `penny/rest_market_trimmed.json` (gekürzt), `penny/rest_offers_by-category_2026-45_fleisch-und-wurst_region_15A-02-35.json`

```json
{"title":"MÜHLENHOF Frische Chicken-Wings*","type":"food","quantity":"je 1.000-g-Packung",
 "price":"3.99","originalPrice":"4.99","discountPercentage":"-20%","basePrice":null,
 "productData":"{\"id\":\"6bea4df5-…\",\"category\":\"fleisch-und-wurst\",\"price\":\"3.9900\",\"rrp\":\"4.9900\",\"promotion\":\"reduzierter Preis\"}",
 "imageRendition":{"tileMd":"https://cdn.penny.de/dam/jcr:…/42360083.png?impolicy=…"}}
```

### 6.2 Kaufland: direkt (empfohlen) ✅
1. **Filialliste:** `GET https://filiale.kaufland.de/.klstorefinder.json` liefert 788 Filialen. Kurz-Keys: `n` = storeName (z. B. `DE1300`), `cn` = Name, `pc` = PLZ, `t` = Ort, `sn` = Straße, `lat`, `lng`, `wod` = Öffnungszeiten.
2. **Angebote einer Filiale:** `GET https://filiale.kaufland.de/angebote/uebersicht.storeName=DE4130.html?kloffer-week=current` (`next` für die Folgewoche). Das HTML enthält `<script>window.SSR['<uuid>'] = {"component":"OfferTemplate","props":{weekData, offerData:{cycles:[{categories:[{displayName, offers:[...]}]}]}}}`. Für DE4130 (Köln-Ehrenfeld) waren das 860 Angebote.
   - Felder: `offerId`, `klNr`, `title` (Marke), `subtitle`, `detailTitle`, `detailDescription`, `price`, `formattedPrice`, `formattedOldPrice`, `discount`, `unit` („je 1,5-kg-Packg.“), `basePrice`/`formattedBasePrice` („(1 kg = 2.00)“), `dateFrom`, `dateTo`, `salesFrom`, `salesTo`, `loyaltyDiscount`, `listImage` und `label`.
   - Ohne `storeName` liefert `/angebote/aktuelle-woche.html` eine Weiterleitung auf `uebersicht.html?kloffer-week=current` mit einer Default-Filiale ✅.
   - 📄 Im Settings-JSON gibt es außerdem `apiUrl: "/.kloffers.storeName={storeName}.json"` und `storeInfoUrl: "/.klstorebygeo.storeName={storeName}.json"`. Beide habe ich nicht abgerufen ❓.
- Quelle: [beihnaheohnmacht/kaufland-angebote `abholen.mjs`](https://github.com/beihnaheohnmacht/kaufland-angebote) (Familien-Haushalts-App, ruft 1× täglich ab), von mir ✅ verifiziert.
- Kein Cloudflare auf `filiale.kaufland.de` bei diesen Abrufen. Laut nerdrx ist dagegen `kaufland.de/angebote/…` (ohne `filiale.`) per Cloudflare geschützt. `robots.txt` sperrt nur `/angebote/*/detail`.
- Fixtures: `kaufland/klstorefinder.json`, `kaufland/uebersicht_storeName_DE4130_OfferTemplate_SSR.json` (aus dem HTML extrahiertes JSON)

```json
{"offerId":"ART.1326051_KAV.3712314","dateFrom":"2026-11-01","dateTo":"2026-11-07",
 "title":"Span. Clementinen ","price":2.99,"discount":25,"basePrice":"(1 kg = 2.00)",
 "unit":"je 1,5-kg-Packg.","detailDescription":"Sorte laut Auszeichnung, Kl. I",
 "listImage":"https://kaufland.media.schwarz/is/image/schwarz/00372573-4","klNr":"00373019",
 "salesFrom":"2026-11-02","salesTo":"2026-11-07","formattedOldPrice":"3.99","formattedPrice":"2.99"}
```

### 6.3 EDEKA (inkl. E center, Marktkauf)
- **kaufDA (empfohlen) ✅:** EDEKA `DE-220164`, E center `DE-3443181`, Marktkauf `DE-1017`. `closestStore.externalId` hat das Format `EDEKA-RR_<nr>` (Region Rhein-Ruhr). `/pages` liefert 75 Angebote mit `SALES_PRICE` und `REGULAR_PRICE`. Fixture: `kaufda/brochure_pages_edeka.json`.
- **edeka.de:** `GET https://www.edeka.de/eh/service/eh/offers?limit=5&marketId=1` (laut nerdrx 📄) liefert ✅ **403 Akamai**. Nicht umgehen.
- **EDEKA-App-API** 📄 ([ByteSizedMarius/edekompile](https://github.com/ByteSizedMarius/edekompile), Go, 22.08.2026): Angebote über `GET https://b2c-gw.api.edeka/v2/offers/mobile` (Markt per GLN, Seiten à 200) mit einem Bearer per OAuth-`client_credentials` von `https://b2b-login.api.edeka/auth/realms/b2b/protocol/openid-connect/token` (App-Client-Daten). Die Marktsuche läuft per SOAP über `myvaluephone.com` und **braucht ein Login**. Felder: `title`, `descriptions[]`, `price{value,currency}`, `priceType`, `discount`, `category`, `validFrom`, `validTill`, `lowestPrice`, `image.imageUrl`. Nicht umgesetzt, weil eingebettete App-Credentials genutzt werden.
- Älter: [VinceDerPrince/Edeka-API](https://github.com/VinceDerPrince/Edeka-API) (2022, 9★), [m4schini/edeka-angebote](https://github.com/m4schini/edeka-angebote) (2021).

### 6.4 Netto Marken-Discount
- `https://www.netto-online.de/filialangebote` liefert ✅ **403 Akamai**. Laut nerdrx 📄 erscheinen die Angebote erst nach einer Filialwahl in der Session, und `robots.txt` sperrt `/INTERSHOP/`.
- [vwkd/netto-angebote-scrape](https://github.com/vwkd/netto-angebote-scrape) (Deno, 20.12.2025) nutzt **patchright/Chromium**, also Browser-Automatisierung mit Stealth. Das ist nicht empfehlenswert, weil es faktisch den Bot-Schutz umgeht.
- **kaufDA (empfohlen) ✅:** `DE-1034`, `closestStore.externalId: "2575"`, 399 Angebote. Fixture: `kaufda/brochure_pages_netto.json`.
- ⚠️ **Verwechslungsgefahr:** `https://netto.de/angebote/` (✅ 200, HTML, Karten mit `aria-label="product-N"`, `<h4>` als Titel und `<h3>` als Preis) gehört zu **Netto „mit dem Scottie“** (Salling Group, Bildpfade `media.umbraco.io/salling-group/…`, Text „Scottie im Logo“), **nicht** zu Netto Marken-Discount. Das Repo `beihnaheohnmacht/kaufland-angebote` (`netto.mjs`) bezeichnet die Seite fälschlich als Marken-Discount. Fixture: `netto-scottie/netto.de_angebote.html`.

---

## 7. Aggregatoren als Fallback

### 7.1 kaufDA / Bonial
Siehe Abschnitt 0. Das ist die **Primärquelle**.

### 7.2 Marktguru 📄 (Live-Abruf in dieser Session nicht möglich)
- **Key-Beschaffung:** Die Startseite `https://www.marktguru.de/` enthält ein `<script type="application/json">` mit `config.apiKey`, `config.clientKey`, `config.apiHostAddress` und `config.mediaHostAddress`. Am 02.11.2026 habe ich ✅ geprüft, dass diese Keys im HTML stehen. Die Keys sind öffentliche Web-Client-Keys, sollten aber **zur Laufzeit gelesen und nicht hart codiert** werden.
- **Suche:** `GET https://api.marktguru.de/api/v1/offers/search?as=web&q=<Suchbegriff>&limit=<n>&offset=0&zipCode=<PLZ>` mit den Headern `x-apikey` und `x-clientkey`.
- Antwort laut [npm `marktguru@0.0.6`](https://unpkg.com/marktguru@0.0.6/src/@types/marktguru.d.ts): `results[]` mit `id`, `description`, `price`, `oldPrice`, `referencePrice`, `validityDates[{from,to}]`, `brand{name}`, `advertisers[{uniqueName (z. B. lidl, aldi-sued, aldi-nord, penny, netto-marken-discount), name}]`, `categories[]`, `product{name,description}`, `unit{shortName,name}`, `images{urls{small…xxlarge}}` und `requiresLoyalityMembership`. Eine EAN gibt es nicht.
- Bild-URL-Muster laut ha-marktguru: `https://mg2de.b-cdn.net/api/v1/offers/{id}/images/default/0/small.webp`.
- Quellen:
  - [npm marktguru](https://www.npmjs.com/package/marktguru) (0.0.6, 05/2022): Key-Extraktion per Regex und `baseURL https://api.marktguru.de/api/v1`
  - [thorschtn/ha-marktguru](https://github.com/thorschtn/ha-marktguru) (21.09.2026, 9★): `const.py` mit hart codierten Keys und Parametern `as=web, limit=24, offset=0, q, zipCode`
  - [N0tMaggi/OFFHUNTER](https://github.com/N0tMaggi/OFFHUNTER) (28.07.2026): nutzt das npm-Paket
  - [Nusscookie/offers-api](https://github.com/Nusscookie/offers-api) (01/2026)
  - [AdeAnima/food-planner](https://github.com/AdeAnima/food-planner) (07/2026): ein ähnliches Meal-Planning-Projekt mit Marktguru
- **Wichtig:** Mein Testabruf der Such-API mit den aus der Seite gelesenen Keys wurde in dieser Session vom **Berechtigungs-Klassifikator des Agenten** abgelehnt. Es gibt daher **keine Marktguru-Fixture**. Vor einer Umsetzung sollte der Nutzer selbst entscheiden, ob die Nutzung der Web-Client-Keys für ihn in Ordnung ist (ToS-Grauzone).
- Einschränkung: Marktguru ist **suchbasiert** (`q`). Einen kompletten Prospekt je Händler bekommt man nur mit leerem oder generischem `q` und Paging. Ob `q=""` alle Angebote liefert, ist unverifiziert ❓ (das npm-Paket setzt `q=''` und `limit 1000` als Default).

---

## 8. Stabilität, Rate-Limits, Rechtliches

| Quelle | Schutz (beobachtet am 02.11.2026) | Hinweise |
|---|---|---|
| kaufDA `api/shelf`, `api/search`, `content-viewer-be` | keiner | `/webapp/` und `/contentViewer/` laut robots.txt gesperrt, also nicht nutzen |
| aldi-nord.de | keiner | SSR-HTML ca. 600 KB, 1×/Tag reicht (Wochenwechsel sonntags) |
| penny.de `.rest` | keiner | Marktliste 3,8 MB, wöchentlich cachen |
| filiale.kaufland.de | keiner | Seite 2,7–3,2 MB, 1×/Tag |
| endpoints.leaflets.schwarz | keiner | — |
| view.publitas.com | keiner | — |
| aldi-sued.de, edeka.de, netto-online.de | **Akamai 403** | nicht umgehen |
| rewe.de | **Cloudflare-Challenge/Captcha 403** | nicht umgehen |
| mobile-clients-api.rewe.de | **mTLS** (403 ohne Zertifikat) | nur mit App-Zertifikat, Grauzone |
| rossmann.de | **JS-Challenge** | nicht umgehen |
| dm.de | SPA + reCAPTCHA-Script | Endpunkt unbekannt |

**Regeln für den Backend-Abruf:**
- Abruf **1× täglich** (morgens), außerdem nach dem Wochenwechsel (So/Mo). Ergebnisse mit `contentId` und KW in der DB cachen. Nur neue Prospekte nachladen.
- Höchstens 1 Anfrage pro Sekunde pro Host, keine Parallelität über 2. Retry mit Backoff, bei 403/429 abbrechen und **nicht** auf Umgehungstechniken eskalieren (Proxy, Headless-Stealth, TLS-Fingerprint-Spoofing).
- Normaler Browser-User-Agent mit `Accept-Language: de-DE`. Keine Cookies, keine Logins.
- Daten nur privat und intern nutzen, nicht veröffentlichen oder weiterverteilen. Bilder per URL referenzieren statt zu spiegeln.
- Die Nutzungsbedingungen der einzelnen Anbieter habe ich **nicht juristisch geprüft**. Scraping interner Endpunkte kann gegen AGB verstoßen. Bei rein privater Nutzung in geringer Frequenz ist das Risiko gering, aber nicht null.
- Alle Endpunkte sind inoffiziell und können sich jederzeit ändern. Deshalb pro Quelle einen Adapter mit Fixture-basierten Parser-Tests bauen und einen Health-Check einrichten („0 Angebote“ führt zu einer Warnung).

---

## 9. Empfehlung: Umsetzungsreihenfolge

1. **kaufDA-Adapter (Prio 1):** Er deckt mit **einem** Parser REWE (marktgenau), Lidl, EDEKA/E center/Marktkauf, Kaufland, Penny, Netto MD und Rossmann ab (`shelf` → `pages`), dazu ALDI SÜD und dm über `/api/search`. Er braucht keinen Key und hat einheitliche Felder (`products[].name/brandName/description`, `deals[]`, `publicationProfiles`). Konfiguration: Wohnort-Koordinaten plus pro Händler die gewünschte `closestStore.externalId` (wählbar aus dem Shelf).
2. **Direkt-Adapter mit besserer Datenqualität (Prio 2):**
   - **ALDI Nord** (`__NEXT_DATA__`, Grundpreis und Streichpreis strukturiert)
   - **Penny** (`.rest`, regional)
   - **Kaufland** (SSR-JSON, filialgenau, 860 statt 418 Angebote)
3. **Optional (Prio 3):** Marktguru als zweite Aggregator-Quelle, zum Abgleich und als Ausfallsicherung. REWE-App-API nur, wenn der Nutzer bewusst ein selbst extrahiertes Zertifikat bereitstellt. Lidl-Flyer-API und REWE-Publitas für die Prospekt-Ansicht (PDF und Seitenbilder).
4. **Nicht umsetzen:** Umgehung von Akamai, Cloudflare oder JS-Challenges (ALDI SÜD, EDEKA, Netto MD, rewe.de, Rossmann), Headless-Stealth-Browser.

**Normalisiertes Zielschema** (Vorschlag):
`retailer, store_id, source, source_offer_id, title, brand, description, price, regular_price, unit_text, base_price_text, image_url, valid_from, valid_to, category_path[], loyalty_note, fetched_at`.
Eine EAN liefert keine der verifizierten Quellen.

---

## 10. Gespeicherte Fixtures

Alle Dateien stammen aus Antworten, die ich am 02.11.2026 selbst abgerufen habe (Standort Köln 50667). Eintrag „extrahiert“ bedeutet: JSON aus dem abgerufenen HTML herausgelöst, sonst unverändert.

| Datei (`backend/tests/fixtures/sources/…`) | Ursprung |
|---|---|
| `kaufda/shelf_koeln_50667_page0.json` | `GET kaufda.de/api/shelf?lat=50.940700&lng=6.959910&size=50&page=0` |
| `kaufda/brochure_meta_rewe_ceb30b11.json` | `GET content-viewer-be.kaufda.de/v1/brochures/ceb30b11-…` |
| `kaufda/brochure_pages_rewe_ceb30b11.json` | `…/v1/brochures/ceb30b11-…/pages` (REWE Markt 1763159) |
| `kaufda/brochure_pages_{lidl,penny,netto,edeka,kaufland,rossmann}.json` | `…/v1/brochures/{id}/pages` |
| `kaufda/brochure_pages_dm.json` | `…/pages` für dm, Antwort `{"contents":[]}` (dynamic_brochure) |
| `kaufda/api_search_ALDI_koeln.json` | `GET kaufda.de/api/search?query=ALDI&…` |
| `kaufda/api_search_dm_koeln.json` | `GET kaufda.de/api/search?query=dm-drogerie markt&…` |
| `kaufda/seo_page_koeln_milch_pageInformation.json` | extrahiert aus `kaufda.de/Koeln/Angebote/Milch` (`__NEXT_DATA__`) |
| `rewe/publitas_rewe_2026_wk45_1763159_spreads.json` | `GET view.publitas.com/rewe-markt/rewe_2026_wk45_1763159/spreads.json` |
| `aldi-nord/angebote_current_apiData.json` | extrahiert aus `aldi-nord.de/angebote.html` (`apiData`) |
| `lidl/leaflets_v4_flyer_aktionsprospekt_2026-11-02.json` | `GET endpoints.leaflets.schwarz/v4/flyer?flyer_identifier=…` |
| `penny/rest_market_trimmed.json` | `GET penny.de/.rest/market`, **gekürzt** (erste 10 + alle PLZ 50xxx) |
| `penny/rest_offers_by-category_2026-45_fleisch-und-wurst_region_15A-02-35.json` | `GET penny.de/.rest/offers/by-category/…` |
| `kaufland/klstorefinder.json` | `GET filiale.kaufland.de/.klstorefinder.json` |
| `kaufland/uebersicht_storeName_DE4130_OfferTemplate_SSR.json` | extrahiert aus `uebersicht.storeName=DE4130.html` |
| `netto-scottie/netto.de_angebote.html` | `GET netto.de/angebote/` (Netto Scottie, nicht Marken-Discount) |

Keine Fixtures gibt es für **Marktguru** (Abruf blockiert), **REWE-App-API** (mTLS), **ALDI SÜD direkt**, **EDEKA direkt**, **Netto MD direkt** (Akamai), **Rossmann direkt** (Challenge) und **dm direkt** (Endpunkt unbekannt). Die Testdaten in `rewerse-engineering/pkg/testdata/*.json` stammen aus einem fremden Repo und wurden nicht übernommen. Für Struktur-Referenzen siehe dort.
