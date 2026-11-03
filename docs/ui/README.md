# UI

Status: **Entwurf, wird mit dem Nutzer abgestimmt (Phase 0)**

Das UI ist verbindlich. Gebaut wird nur, was hier beschrieben und freigegeben ist.

| Datei | Inhalt |
|---|---|
| [references/README.md](references/README.md) | Referenz-Screenshots und was wir davon übernehmen |
| [design-system.md](design-system.md) | Farben, Schrift, Abstände, Radien, Schatten, Icons, Komponenten |
| [screens.md](screens.md) | Navigation und jeder Screen: Inhalt, Aktionen, Zustände |
| [redesign-v3.md](redesign-v3.md) | **Redesign v3 (E87): Bauanleitung 1:1 – gilt vor allen anderen Dateien, bis Phase 18 fertig ist** |
| `mockups/` | HTML-Mockups. Freigegebene Mockups sind die visuelle Vorlage (`redesign-v3.html` = v3; `kern-screens-v1.html`, `weitere-screens-v1.html` werden mit Phase 18 abgelöst) |

## Regeln für Claude

- Werte nur aus `design-system.md` (während Phase 18: aus `redesign-v3.md`). Fehlt ein Wert: fragen, nicht erfinden.
- Screens so bauen, wie in `screens.md` und dem freigegebenen Mockup. Abweichungen nur nach Rückfrage.
- Neue Screens oder Komponenten: erst hier spezifizieren, Nutzer freigeben lassen, dann bauen.
- iOS (`Theme.swift`) und Web-PWA (CSS-Variablen) nutzen dieselben Werte.
- Händler-Logos: offizielle Logos als Wikimedia-Thumbnails, nur verlinkt, nie ins Repo (E44), immer ganz sichtbar auf weißem Plättchen. Markenfarben nicht nachbauen; Ordner-/Chipfarben aus der eigenen Palette.
