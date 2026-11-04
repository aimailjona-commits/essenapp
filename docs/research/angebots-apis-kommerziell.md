# Angebotsdaten kommerziell nutzen (Recherche 2026-11-04, Phase 19.0)

Keine Rechtsberatung. Anlass: Kochpilot wird kommerziell (E90); bisher holt das Backend Angebote ohne Vertrag von kaufDA.

## Ergebnis

Es gibt **keine offen buchbare Angebots-API** für deutsche Supermärkte. Sauber geht es nur per Vertrag mit einem Aggregator oder Händler.

| Quelle | Liefert | Kommerziell | Anfrage |
|---|---|---|---|
| **Shopfully** (früher Offerista Group) | Prospekte aller DACH-Ketten, spielt sie in Partner-Apps aus (u. a. Chefkoch, Bring!, Payback). Ob strukturierte Einzelangebote (Titel, Preis, Grundpreis, Gültigkeit, PLZ) kommen: **unbestätigt** | nach Vertrag; sucht aktiv App-Publisher, vermutlich Umsatzbeteiligung statt Lizenzgebühr | https://shopfully.com, Team „Publisher/Partner Development Germany“ |
| **Bonial** (kaufDA, MeinProspekt) | alle Ketten, Titel/Preis/Gültigkeit/Filiale | **nein ohne Vertrag** (AGB Ziff. 3e: keine kommerzielle Nutzung der Daten mit Dritten); kein Partnerprogramm sichtbar | https://www.bonial.com/de/kontakt |
| **marktguru** Data Insights | Einzelangebote mit Hersteller, Packung, Preis, Rabattart, PLZ, Gültigkeit | App-Daten: nein (AGB Ziff. 4); B2B-Daten nach Vertrag, Weitergabe an Endnutzer unklar | https://www.data-insights.guru/ |
| **Publitas** (Prospekt-Hosting, u. a. Rewe) | Produkt-Feeds der Prospekte | nach Vertrag, jeder Händler muss freischalten | https://support.publitas.com/partners |
| Händler direkt | keine offizielle Angebots-API; Affiliate (Lidl/Rewe über Awin) nur Onlineshop | nur Einzelvertrag | – |
| **Open Prices** (Open Food Facts) | von Nutzern gemeldete Preise, keine Prospekte, DE-Abdeckung dünn | ja (ODbL, Namensnennung + Share-Alike) | https://openfoodfacts.github.io/open-prices/guides/API/ |
| Apify-Scraper u. ä. | dieselben Daten inoffiziell | nein/riskant | – |

Rechtlich: § 87b UrhG (Datenbankherstellerrecht) + EuGH CV-Online Latvia (C-762/19) und Innoweb (C-202/12) → systematisches Abgreifen einer Aggregator-Datenbank für eine konkurrierende App ist ziemlich sicher unzulässig. Produktfotos/Prospektseiten zusätzlich Lichtbildschutz (§ 72 UrhG).

## Empfehlung

1. **Hauptweg:** Shopfully als App-Publisher anfragen; Kernfrage: strukturierte Einzelangebote je PLZ/Filiale (nicht nur Prospekt-Viewer/Anzeigen).
2. **Parallel:** Bonial (Kontaktformular) und marktguru Data Insights anfragen.
3. Bis ein Vertrag steht: kaufDA-Abruf für die **App-Store-Version abschalten**; privat/Familie weiter wie bisher (E3-Altbetrieb). Open Prices höchstens als Ergänzung (Normalpreise).
4. Der Adapter ist austauschbar (`app/sources/`, ein Adapter je Quelle); Kategorisierung (19.1) arbeitet auf dem Produkttext und bleibt.

Quellen: kaufDA-AGB https://www.kaufda.de/AGB · marktguru-AGB https://info.marktguru.de/agb · Offerista/Shopfully https://lebensmittelpraxis.de/lp-international/189-lpinternational-nachrichten/43252-deutschland-italien-offerista-group-und-shopfully-schliessen-sich-zusammen.html · Publisher-Stelle https://join.com/companies/offerista/14147178-publisher-development-manager-m-f-d-x · Open Prices s. o. · EuGH CV-Online https://www.twobirds.com/en/insights/2021/uk/cv-online-latvia-cjeu-complicates-the-enforcement-of-database-rights
