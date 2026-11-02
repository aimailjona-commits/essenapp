# Phase 4 – Personalisierung + Web-Version

Ziel: Lieblingsgerichte prägen die Pläne, die Familie nutzt Plan und Liste im Browser.

## Personalisierung

- [ ] Rezepte speichern, eigene Rezepte anlegen
- [ ] Bewertung nach dem Kochen (Sheet), Modell `rating`
- [ ] Planner: Gewichtung nach Bewertung, Wiederholungs-Malus, schlecht bewertete ausschließen
- [ ] „Rezept im Angebot“: Abgleich nach jedem Import, Hinweis auf Start-Screen
- [ ] iOS: Meine Rezepte, Favoriten, Bewertungsverlauf

## Web-PWA (`backend/app/web/`)

- [x] Einladung per Link → Mitglied-Token im Browser (`/join/<code>`, HttpOnly-Cookie, E40)
- [x] Gemeinsame Einkaufsliste im Backend (`/lists`, `sync-plan` bei neuem Plan), einmalige Listen mit Gast-Link `/l/<code>` (E40)
- [ ] iOS: Einkaufsliste auf `/lists` umstellen, Einladen/Teilen-Button (`POST /household/invites`, `GET /household/share`), Mitglieder
- [x] Layout + CSS-Variablen aus dem Design-System (v3), PWA-Manifest, Homescreen-Icon
- [x] Wochenplan, Rezeptdetail (aufklappbar), Einkaufsliste (gemeinsam abhaken, 10-s-Polling)
- [ ] Bewertungen im Web
- [ ] Mobile-first, getestet auf iPhone-Safari

## DoD

- Ein zweites Familienmitglied tritt per Link bei, hakt im Browser ab, die Änderung erscheint in der iOS-App.
