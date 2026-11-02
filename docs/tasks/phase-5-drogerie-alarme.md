# Phase 5 – Drogerie & Alarme

Ziel: Lieblingsprodukte werden überwacht, Treffer kommen als Push.

- [ ] Recherche + Adapter dm (inkl. Monatsaktionen) + Fixture-Test
- [ ] Recherche + Adapter Rossmann + Fixture-Test
- [ ] Modelle `watch_item`, `watch_hit`
- [ ] Watchlist-Matcher nach jedem Import (Name/Marke/EAN, optional Maximalpreis)
- [ ] ntfy-Versand, Topic pro Mitglied, QR-Code in den Einstellungen
- [ ] iOS: Merkliste-Screen, Produkt per Suche oder Barcode-Scan (VisionKit) anlegen
- [ ] iOS: lokale Notifications beim App-Start / `BGAppRefreshTask`
- [ ] Weitere Lebensmittel-Händler nach Konfiguration (Lidl, Edeka, Kaufland, Penny, Netto)
- [ ] Erinnerung „App neu installieren“ alle 6 Tage per ntfy (7-Tage-Signatur)

## DoD

- Ein Lieblingsprodukt im Angebot löst innerhalb eines Import-Laufs eine ntfy-Nachricht aus.
