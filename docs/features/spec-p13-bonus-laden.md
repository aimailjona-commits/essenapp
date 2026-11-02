# Phase 13 – Bonus, Laden, Ausgaben

---

## 38 · Payback & Rewe Bonus

Keine offiziellen Schnittstellen (A7) → alles über Fotos/Scan/Eingabe, **keine Logins** bei Payback/Rewe.

**a) Coupons erfassen & an der Kasse zeigen**
- „Wallet“ (Einkauf-Tab › Pille „Coupons“): + Coupon → Foto (Haiku liest Partner, Produkt/Kategorie, Vorteil „10fach Punkte“, „0,50 € Bonus“, Mindestumsatz, Gültig-bis) **oder** Barcode scannen (VisionKit liest Code-Typ + Inhalt) **oder** manuell.
- Kasse: Coupon antippen → Vollbild mit Barcode (Code128/EAN13/QR per CoreImage neu gerendert), maximale Helligkeit, Partner-Logo.
- Ablauf: Push 2 Tage vorher (Job `coupon_expiry`), abgelaufene grau unter „Abgelaufen“.

**b) Guthaben & Punkte zählen**
- Karten „Payback: 1.240 °P (≈ 12,40 €)“ und „Rewe Bonus: 8,50 €“ – Wert manuell aktualisieren (schnelles Plus/Minus-Sheet nach dem Einkauf: „Heute bekommen: +60 °P“).
- Fließt in Ersparnis (Dashboard 34, Erfolge 54) als eigene Spalte „Bonus“.

**c) In die Planung einrechnen**
- Aktive Coupons/Bonus-Aktionen werden in Preise umgerechnet: 10fach Punkte auf Obst = 10 % Rabatt (1 °P ≈ 1 Cent pro 2 €), 0,50 € Bonus auf Produkt X = −0,50 €.
- Planner/Pricing nutzen den Effektivpreis; Gerichte mit Coupon-Zutaten werden bevorzugt; Liste zeigt Coupon-Badge am Artikel („🎟 10fach“).

**d) Erinnerung im Laden**
- Mit 36: beim Betreten eines Ladens „Denk an deinen Payback-Coupon für Kaffee (läuft So ab)“; im Laden-Listen-Screen oben Coupon-Leiste der passenden Coupons.

**Abnahme:** Coupon-Foto wird zu ≥ 90 % korrekt gelesen (10 echte Coupons), Barcode an der Kasse lesbar (Testscan mit anderem Handy), Effektivpreis ändert Planwahl nachweisbar, Erinnerung kommt beim Laden.

---

## 39 · Rewe-Bonus-Aktionen erkennen

- Schritt 1 (Recherche): Enthalten die kaufDA-REWE-Daten Bonus-Felder (Deal-Typen, Text „Bonus“)? Ergebnis in `docs/research/datenquellen.md`.
- Erkennung: Deal-Typ oder Texte wie „0,50 € Bonus-Guthaben“, „Bonus-Aktion“ → Feld `bonus_cents` am Angebot.
- UI: Badge „🎁 0,50 € Bonus“ (Rewe-Rot neutralisiert in Orange), Filter „Bonus-Aktionen“, Ersparnis zählt Bonus.
- Planner: Bonus wie Rabatt (Effektivpreis).

**Abnahme:** Bonus-Aktionen der aktuellen Woche (Stichprobe aus der Rewe-App vergleichen) werden erkannt.

---

## 36 · Standort-Erinnerung

- Einstellungen › Benachrichtigungen: „Erinnern, wenn ich in einem Laden bin“ (Erlaubnis „Immer“ wird mit Erklär-Sheet angefragt).
- Überwacht: bis zu 20 gewählte Läden (nächste zuerst), Radius 120 m, nur 8–21 Uhr, max. 1 Erinnerung pro Laden und Tag, nur wenn für diesen Laden offene Artikel/Coupons existieren.
- Nachricht (lokal): „🛒 Du bist bei REWE: 4 Sachen auf der Liste · Coupon Kaffee“ → öffnet Laden-Liste.

**Abnahme:** Testlauf am echten Laden (oder simulierte Region) erzeugt genau eine Nachricht; ohne offene Artikel keine.

---

## 45 · Einkaufsliste per Sprache

- Mikrofon-Knopf im „Artikel hinzufügen“-Feld (Liste + einmalige Listen) → Glas-Overlay mit Pegel, deutsch on-device.
- Gesprochenes „zwei Liter Milch, Eier und ein Brot“ → Aufteilung in Artikel (Komma/„und“, Mengen-Erkennung per Regeln) → Vorschau-Chips (antippen = entfernen) → „Hinzufügen“.
- Laden-Zuordnung automatisch, wenn Artikel im Angebot.

**Abnahme:** 10 Testsätze → ≥ 9 korrekt zerlegt.

---

## 34 · Monats-Dashboard (abgehakte Artikel)

- Neuer Screen über Start (Karte „Ausgaben November“) und Einstellungen.
- Ausgaben = Preis der abgehakten Artikel (Angebotspreis, sonst Normalpreis-Schätzung, markiert „geschätzt“), Datum = Zeitpunkt des Abhakens.
- Inhalte: Monatssumme vs. Budget (Ring), Ersparnis (Angebote + Bonus 38), Balken pro Woche, Torte pro Laden (Logos) und pro Kategorie, Top-5 teuerste Artikel, Vergleich zum Vormonat (+/− %), Monatswahl wischbar.
- Export (CSV) über Teilen.

**Abnahme:** Summen stimmen mit abgehakten Einträgen überein (Test), Diagramme animiert, Monatswechsel funktioniert.
