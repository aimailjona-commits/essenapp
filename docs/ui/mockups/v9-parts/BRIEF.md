# v9-Entwurf – gemeinsame Regeln für alle Teile

Ziel: Der Nutzer bewertet neue Mockups. Pro Bereich 2–3 klar verschiedene Varianten (A/B/C), jede als echtes Handy-Mockup.

## Technik
- Du schreibst NUR deine Datei `docs/ui/mockups/v9-parts/<buchstabe>.html` (ein HTML-Fragment, kein <html>/<head>).
- Sie wird von `v9-parts/build.py` zwischen Kopf/Stil aus `docs/ui/mockups/redesign-v8.html` + `docs/ui/mockups/v8-parts/_extra.html` und das Nav-Skript gesetzt. Diese Klassen (`.phone .sb .scr .nav .t1 .t2 .num .stat .irow .chip .btn .plate .blob .arch .leaf .lbl .small .screens .screen .caption .sec` …) darfst du nutzen – lies beide Dateien vorher.
- Aufbau wie in `docs/ui/mockups/v8-parts/a.html`: eigenes `<style>` mit Präfix-Klassen (z. B. `.a9-…`), dann `<section class="sec"><h2>…</h2><p>…</p></section><div class="screens"> <div class="screen"><div class="phone">…</div><div class="caption"><b>Variante A – Name</b>Erklärung …</div></div> …</div>`.
- Statusleiste, Nav mit Mulde, Homebar genau wie in den v8-Teilen kopieren.
- Bilder: `../../../ios/Sources/Essenapp/Resources/hero/*.jpg` (Gerichte), `../../../ios/Sources/Essenapp/Resources/ill/*.webp` (Zeichnungen). Marktlogos per URL aus `ios/Sources/Essenapp/API.swift` (Zeile ~591, `logos`).
- Interaktion (Scrollen, Swipen) gern mit kleinem Inline-`<script>` (Vanilla-JS, IIFE, nur auf eigene Elemente per ID/Präfix zugreifen). Muss mit Maus UND Touch gehen.
- NICHT bauen, KEINE WSL-/Build-Befehle, KEIN git. Nur deine Datei schreiben. Zum Prüfen darfst du `python docs/ui/mockups/v9-parts/build.py` ausführen und `docs/ui/mockups/redesign-v9-entwurf.html` ansehen.

## Stil v9 (gilt ab jetzt)
- Weißer Hintergrund (`--bg:#FFFFFF`), Felder `--card:#F5F5F3`, Titel-Serife Crimson Pro 500 (wird automatisch gesetzt, wenn du `"DM Serif Display"` oder `.t1/.t2` nutzt).
- Pastellblau `--blue` ist Hauptfarbe; dazu `--sage --rose --sand --blue1 --deal`. Pastell-Formen laufen aus dem Bildschirmrand. Große Zahlen in Inter Tight mit Haarlinie. Schwarze Pill-Knöpfe. Keine L-Formen.
- Der Nutzer findet die App teils „zu gestapelt, zu langweilig, nicht gruppiert“: Inhalte sichtbar gruppieren (Gruppen mit Überschrift, Karten/Flächen wo es hilft), Rhythmus, nicht alles als gleichförmige Zeilen untereinander.
- Texte Deutsch, Beträge `12,49 €`. Echt wirkende Inhalte (Rosenkohl-Pfanne mit Paprika-Chili-Reis, Rewe/Edeka/Aldi/Penny/Lidl, KW 45 · 2.–8. Nov).

## Ergebnis
Am Ende kurz (max. 10 Zeilen) melden: welche Varianten, was jeweils die Idee ist, offene Fragen an den Nutzer.
