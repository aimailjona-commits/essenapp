# Phase 15 – Komfort · Phase 16 – Erweiterungen (am Ende)

---

## 66 · Offline-Modus

- Lokaler Cache (Codable-JSON, E25): Haushalt, Plan, Rezepte des Plans, Haushaltsliste, einmalige Listen, Angebote der Woche (ohne Bilder > 2 MB), Vorrat, Coupons.
- Offline (NWPathMonitor): Glas-Banner oben „Offline – Änderungen werden später übertragen“.
- Änderungen (abhaken, hinzufügen, Vorrat) gehen in eine Warteschlange und werden beim nächsten Netz gesendet; Konflikte: letzter Stand gewinnt pro Feld, abgehakt bleibt abgehakt.
- Bilder über URLCache (E-Wert) verfügbar, wenn vorher gesehen.

**Abnahme:** Flugmodus: Liste abhaken, Artikel hinzufügen → nach Netz-Rückkehr im Backend/Web sichtbar.

---

## 68 · Dark Mode

- Alle Tokens in `Theme.swift` mit dunkler Variante (Grund #0F0F10, Karten #1C1C1E, Text #F5F5F5/#A0A0A5, Orange bleibt, Glas-Leiste dunkel), Fotos mit leichter Abdunklung, Logos auf weißen Plättchen.
- Einstellung: System · Hell · Dunkel (ersetzt die Zwangs-Hell-Regel E15).
- CI-Screenshots aller Screens zusätzlich dunkel (E34).

**Abnahme:** jeder Screen in Dunkel lesbar (Kontrast ≥ 4,5:1), keine weißen Flächen.

---

## 65 · Widget „Heute“ (Phase 16)

- Spike zuerst: Widget-Erweiterung mit xtool (Issues #313, #379) – geht es mit der kostenlosen Apple-ID?
- Klein: heutiges Gericht (Foto, Titel, Zeit); Mittel: + nächste Mahlzeit + offene Artikel; Sperrbildschirm: „🍛 Tikka Masala · 35 min“.
- Daten über App Group (falls verfügbar) bzw. Widget lädt selbst vom Server (Token-Kopplung wie A1).

## 37 · Live-Aktivität beim Einkaufen (Phase 16)

- Start in Laden-Liste: „Einkauf starten“ → Live-Aktivität auf Sperrbildschirm/Dynamic Island: Laden-Logo, „5 von 12“, nächste Artikel; Abhaken per Knopf in der Live-Aktivität (App Intents).
- Ende automatisch, wenn alles abgehakt oder nach 2 h.
- Gleicher Spike wie 65; Ersatz falls nicht möglich: dauerhafte Mitteilung mit Liste.

**Abnahme 65/37:** auf dem iPhone sichtbar und aktuell; sonst dokumentierter Ersatz.
