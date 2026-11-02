# UI

Status: **Entwurf, wird mit dem Nutzer abgestimmt (Phase 0)**

Das UI ist verbindlich. Gebaut wird nur, was hier beschrieben und freigegeben ist.

| Datei | Inhalt |
|---|---|
| [references/README.md](references/README.md) | Referenz-Screenshots und was wir davon übernehmen |
| [design-system.md](design-system.md) | Farben, Schrift, Abstände, Radien, Schatten, Icons, Komponenten |
| [screens.md](screens.md) | Navigation und jeder Screen: Inhalt, Aktionen, Zustände |
| `mockups/` | HTML-Mockups. Freigegebene Mockups sind die visuelle Vorlage |

## Regeln für Claude

- Werte nur aus `design-system.md`. Fehlt ein Wert: fragen, nicht erfinden.
- Screens so bauen, wie in `screens.md` und dem freigegebenen Mockup. Abweichungen nur nach Rückfrage.
- Neue Screens oder Komponenten: erst hier spezifizieren, Nutzer freigeben lassen, dann bauen.
- iOS (`Theme.swift`) und Web-PWA (CSS-Variablen) nutzen dieselben Werte.
- Keine Logos oder Markenfarben der Händler nachbauen; Händler werden mit Namen und neutralem Chip angezeigt.
