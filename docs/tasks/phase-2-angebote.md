# Phase 2 – Angebote

Ziel: Aktuelle Angebote von zwei Händlern für die eingestellte PLZ erscheinen in der App.

## Backend

- [x] Modelle + Migration: `household`, `member`, `household_store`, `offer`, `ingredient` (Basis)
- [x] Einfache Token-Auth (Haushalt anlegen → Owner-Token, Token im iOS-Schlüsselbund)
- [-] `OfferSource`-Schnittstelle: nicht nötig, solange kaufDA die einzige Quelle ist (PonyTail)
- [x] Recherche aller Händler (`docs/research/datenquellen.md`) → kaufDA zuerst (E28)
- [x] kaufDA-Adapter + Fixture-Tests (`app/sources/kaufda.py`)
- [ ] Direkte Adapter Aldi Nord / Penny / Kaufland (bessere Daten, optional)
- [~] Normalisierung: Grundpreis ✓, Kategorie grob (≈50 % „sonstiges“ → verbessern), Zutat-Zuordnung offen
- [x] Import: `POST /offers/refresh` + `python -m app.jobs` (cron in Phase 7)
- [~] API: Einstellungen ✓, Angebote mit Filtern ✓; Filialsuche/-wahl offen (automatisch nächster Markt, E29)

## iOS

- [x] API-Client + Codable-Modelle
- [x] Onboarding nach `docs/ui/screens.md` (4 Schritte; Server-Adresse auf dem Willkommens-Screen)
- [x] Angebote-Screen (Laden- und Kategorie-Chips, Raster, Suche, Pull-to-Refresh lädt neu)
- [ ] Angebotsdetail
- [~] Zustände Leer/Fehler ✓, Lade-Skeleton auf Start

## DoD

- Für die eingestellte PLZ zeigt die App die Angebote beider Händler der aktuellen Woche mit Bild, Preis, Grundpreis und Kategorie.
- Adapter-Tests laufen grün mit Fixtures.
