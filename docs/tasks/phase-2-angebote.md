# Phase 2 – Angebote

Ziel: Aktuelle Angebote von zwei Händlern für die eingestellte PLZ erscheinen in der App.

## Backend

- [ ] Modelle + Migration: `household`, `member`, `household_store`, `offer`, `ingredient` (Basis)
- [ ] Einfache Token-Auth (Haushalt anlegen → Owner-Token)
- [ ] `OfferSource`-Schnittstelle (`app/sources/base.py`)
- [ ] Recherche Händler 1 (Vorschlag Rewe): Datenquelle finden, im Playbook Abschnitt 5 dokumentieren
- [ ] Adapter Händler 1 + Fixture-Test
- [ ] Recherche + Adapter Händler 2 (Vorschlag Aldi Süd/Nord je nach PLZ) + Fixture-Test
- [ ] Normalisierung: Grundpreis, Kategorie, Zutat-Zuordnung (Regeln + Haiku, Cache)
- [ ] Job: wöchentlicher Import pro aktivem Haushalt/Filiale (+ manueller Trigger-Endpunkt)
- [ ] API: Haushalt-Einstellungen lesen/schreiben, Händlerliste, Filialsuche per PLZ, Angebote (Filter: Laden, Kategorie, Suche)

## iOS

- [ ] API-Client + Codable-Modelle
- [ ] Onboarding nach `docs/ui/screens.md` (PLZ, Läden/Filialen, Haushalt)
- [ ] Angebote-Screen nach `docs/ui/screens.md` (Laden-Umschalter, Filter-Chips, Raster, Suche)
- [ ] Angebotsdetail
- [ ] Zustände Laden/Leer/Fehler

## DoD

- Für die eingestellte PLZ zeigt die App die Angebote beider Händler der aktuellen Woche mit Bild, Preis, Grundpreis und Kategorie.
- Adapter-Tests laufen grün mit Fixtures.
