# Phase 13 – Bonus, Laden, Ausgaben

Details, Abläufe und Abnahmekriterien: [`docs/features/spec-p13-bonus-laden.md`](../features/spec-p13-bonus-laden.md). Jede Aufgabe erst abhaken, wenn die Abnahme des Features erfüllt ist.

## Aufgaben

- [~] 38a Coupon-Wallet (Foto/Barcode/manuell), Kassen-Vollbild, Ablauf-Push (Backend ✓ E73: `/coupons`, `/coupons/scan`, Job `coupon_expiry`; iOS ✓ Wallet S31, Foto/Barcode/manuell S31c, Kasse S31b mit Code128/QR/EAN; offen: Abnahme mit 10 echten Coupons, Testscan an der Kasse)
- [~] 38b Payback-Punkte/Rewe-Bonus-Guthaben, in Ersparnis (Backend ✓ E73: `/bonus`; iOS ✓ Konto-Karten + Plus/Minus-Sheet S31d; offen: Gerät-Abnahme)
- [~] 38c Effektivpreise im Planner/Pricing, Coupon-Badges auf der Liste (Backend ✓ E73, Test zeigt geänderten Preis/Prompt; iOS ✓ Badge „🎟 10fach“ am Artikel → Kasse; offen: Gerät-Abnahme Planwahl)
- [~] 39 Recherche Bonus-Felder → `bonus_cents`, Badge, Filter, Effektivpreis (Recherche + Backend ✓ E72, live 149 Bonus-Angebote; iOS ✓ Badge „🎁 0,50 € Bonus“ + Filter; offen: Stichprobe mit der Rewe-App)
- [x] 36 Region-Überwachung (20 Läden, 120 m, 8–21 Uhr), lokale Mitteilung
- [~] 38d Coupon-Erinnerung beim Laden (mit 36) (Backend ✓: `GET /coupons?chain=`; iOS ✓ Mitteilung „· Coupon Kaffee“ bzw. nur Coupon, Coupon-Leiste in S5b; offen: Gerät-Abnahme im Laden)
- [x] 45 Sprach-Eingabe für Listen
- [~] 34 Monats-Dashboard (Swift Charts), CSV-Export (Backend ✓ E74: Kauf beim Abhaken, `/spending`, `/spending/export`; iOS ✓ S32 mit Ring, Wochenbalken, Torten, Top 5, Monat wischen, CSV teilen, Start-Karte; offen: Gerät-Abnahme)
- [~] `docs/ui/screens.md` + `Demo.swift` + `ios/tools/screenshots.sh` um neue Screens ergänzt (✓ S31–S32, Demos wallet/bonus/coupon/couponadd/spending), CI-Screenshots geprüft (offen)
- [x] Playbook-Entscheidungslog aktualisiert (E72–E74, Backend)

## DoD

- Abnahme aus 38, 39, 36, 45, 34 erfüllt
