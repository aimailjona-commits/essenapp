# Phase 12 – Sparen

Details, Abläufe und Abnahmekriterien: [`docs/features/spec-p12-sparen.md`](../features/spec-p12-sparen.md). Jede Aufgabe erst abhaken, wenn die Abnahme des Features erfüllt ist.

## Aufgaben

- [x] Grundlage: `product`-Schlüssel + `price_point` (Rückfüllung aus vorhandenen Angeboten) (E49)
- [~] 28 Preisverlauf-Diagramm, Urteil-Badges, Filter „Nur echte Angebote“ (Diagramm + Urteil im Angebotsdetail fertig; Backend ✓ E64; iOS Badge auf Karten + Filter ✓; offen: Gerät-Abnahme, sobald ≥ 3 Wochen Daten)
- [~] 30 Folgewoche-Angebote, Pille „Nächste Woche“, Start-Karte „nächste Woche günstiger“, Plan für nächste Woche (Backend ✓ E65; iOS ✓ Pillen, Start-Karte, Gruppe „Nächste Woche“, Generator-Schalter; offen: Gerät-Abnahme ab Freitag)
- [~] 31 Vorratskauf-Logik + Karten + „n× auf die Liste“ (Backend ✓ E66; iOS ✓ Start-Karte, Detail-Tipp, Badge, Vorratsplatz; offen: Gerät-Abnahme)
- [~] 27 Merkliste: Barcode-Scan (VisionKit + Open Food Facts), Wunschpreis, Abgleich, ntfy-Push (Backend ✓ E67, Push über APNs; iOS ✓ S10 auf `/watch`, Scanner, Tab-Badge; offen: Gerät-Abnahme Scanner, Ende-zu-Ende-Push nach APNs-Freischaltung)
- [~] 40 Preisalarm für Zutaten (Grundpreis) (Backend ✓ E67; iOS ✓ „+ Zutat“, Rezept-Zutat „Preisalarm“; offen: Gerät-Abnahme)
- [~] 41 Ein-Laden-Modus im Generator (Backend ✓ E68; iOS ✓; offen: Gerät-Abnahme)
- [~] 42 Laden-Empfehlung + „So aufteilen“ (Backend ✓ E68; iOS ✓; offen: Gerät-Abnahme)
- [~] 43 Budget-Rest/Über-Budget-Karten (Backend ✓ E69; iOS ✓; offen: Gerät-Abnahme)
- [~] 49 Bio/Vegan/Nutri-Score-Badges + Filter (Backend ✓ E70, Stichprobe live geprüft; iOS ✓ Badges, Filter, Detail-Erklärung; offen: Gerät-Abnahme)
- [~] 58 Verbrauchsrhythmus + Hinweise (Backend ✓ E67; iOS ✓ Rhythmus im Merklisten-Sheet, Badge „bald leer“; offen: Gerät-Abnahme)
- [~] 59 Monatsaktionen-Abschnitt, Drogerie-Coupons über Wallet (nach 38) (Backend Monatsaktionen ✓ E71; iOS Abschnitt ✓; Drogerie-Coupons Backend ✓ E73 (`ItemOut.coupon`, `WatchOut.coupon`); offen: iOS Coupons)
- [~] `docs/ui/screens.md` + `Demo.swift` + `ios/tools/screenshots.sh` um neue Screens ergänzt (✓), CI-Screenshots geprüft (offen)
- [x] Playbook-Entscheidungslog aktualisiert (E64–E71, Backend)

## DoD

- Abnahme aus 28, 30, 31, 27, 40, 41, 42, 43, 49, 58, 59 erfüllt
