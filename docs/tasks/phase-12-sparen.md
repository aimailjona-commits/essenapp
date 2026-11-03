# Phase 12 – Sparen

Details, Abläufe und Abnahmekriterien: [`docs/features/spec-p12-sparen.md`](../features/spec-p12-sparen.md). Jede Aufgabe erst abhaken, wenn die Abnahme des Features erfüllt ist.

## Aufgaben

- [x] Grundlage: `product`-Schlüssel + `price_point` (Rückfüllung aus vorhandenen Angeboten) (E49)
- [~] 28 Preisverlauf-Diagramm, Urteil-Badges, Filter „Nur echte Angebote“ (Diagramm + Urteil im Angebotsdetail fertig; Backend: `verdict` in `GET /offers` + `?real=true` ✓ E64; offen: iOS Badge auf Karten + Filter)
- [~] 30 Folgewoche-Angebote, Pille „Nächste Woche“, Start-Karte „nächste Woche günstiger“, Plan für nächste Woche (Backend ✓ E65; offen: iOS)
- [~] 31 Vorratskauf-Logik + Karten + „n× auf die Liste“ (Backend ✓ E66; offen: iOS)
- [~] 27 Merkliste: Barcode-Scan (VisionKit + Open Food Facts), Wunschpreis, Abgleich, ntfy-Push (Backend ✓ E67, Push über APNs; offen: iOS Scanner + S10, Ende-zu-Ende-Push nach APNs-Freischaltung)
- [~] 40 Preisalarm für Zutaten (Grundpreis) (Backend ✓ E67; offen: iOS)
- [~] 41 Ein-Laden-Modus im Generator (Backend ✓ E68; offen: iOS)
- [~] 42 Laden-Empfehlung + „So aufteilen“ (Backend ✓ E68; offen: iOS)
- [~] 43 Budget-Rest/Über-Budget-Karten (Backend ✓ E69; offen: iOS)
- [~] 49 Bio/Vegan/Nutri-Score-Badges + Filter (Backend ✓ E70, Stichprobe live geprüft; offen: iOS)
- [~] 58 Verbrauchsrhythmus + Hinweise (Backend ✓ E67; offen: iOS)
- [~] 59 Monatsaktionen-Abschnitt, Drogerie-Coupons über Wallet (nach 38) (Backend Monatsaktionen ✓ E71; offen: iOS, Coupons nach 38)
- [ ] `docs/ui/screens.md` + `Demo.swift` + `ios/tools/screenshots.sh` um neue Screens ergänzt, CI-Screenshots geprüft
- [x] Playbook-Entscheidungslog aktualisiert (E64–E71, Backend)

## DoD

- Abnahme aus 28, 30, 31, 27, 40, 41, 42, 43, 49, 58, 59 erfüllt
