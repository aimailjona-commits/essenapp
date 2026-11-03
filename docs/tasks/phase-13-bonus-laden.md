# Phase 13 – Bonus, Laden, Ausgaben

Details, Abläufe und Abnahmekriterien: [`docs/features/spec-p13-bonus-laden.md`](../features/spec-p13-bonus-laden.md). Jede Aufgabe erst abhaken, wenn die Abnahme des Features erfüllt ist.

## Aufgaben

- [~] 38a Coupon-Wallet (Foto/Barcode/manuell), Kassen-Vollbild, Ablauf-Push (Backend ✓ E73: `/coupons`, `/coupons/scan`, Job `coupon_expiry`; offen: iOS Wallet/Kasse/Barcode, Abnahme mit 10 echten Coupons)
- [~] 38b Payback-Punkte/Rewe-Bonus-Guthaben, in Ersparnis (Backend ✓ E73: `/bonus`; offen: iOS Karten + Plus/Minus-Sheet)
- [~] 38c Effektivpreise im Planner/Pricing, Coupon-Badges auf der Liste (Backend ✓ E73, Test zeigt geänderten Preis/Prompt; offen: iOS Badge)
- [~] 39 Recherche Bonus-Felder → `bonus_cents`, Badge, Filter, Effektivpreis (Recherche + Backend ✓ E72, live 149 Bonus-Angebote; offen: iOS Badge/Filter, Stichprobe mit der Rewe-App)
- [x] 36 Region-Überwachung (20 Läden, 120 m, 8–21 Uhr), lokale Mitteilung
- [~] 38d Coupon-Erinnerung beim Laden (mit 36) (Backend ✓: `GET /coupons?chain=`; offen: iOS Mitteilungszusatz + Coupon-Leiste)
- [x] 45 Sprach-Eingabe für Listen
- [~] 34 Monats-Dashboard (Swift Charts), CSV-Export (Backend ✓ E74: Kauf beim Abhaken, `/spending`, `/spending/export`; offen: iOS)
- [ ] `docs/ui/screens.md` + `Demo.swift` + `ios/tools/screenshots.sh` um neue Screens ergänzt, CI-Screenshots geprüft
- [x] Playbook-Entscheidungslog aktualisiert (E72–E74, Backend)

## DoD

- Abnahme aus 38, 39, 36, 45, 34 erfüllt
