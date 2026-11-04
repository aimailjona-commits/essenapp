# Baut aus redesign-v8.html (Stil + Nav-Skript), _extra.html (Bausteine) und den Teilen:
#   redesign-v8-alle.html  <- a–f.html (alle Screens)
#   animationen-v8.html    <- anim*.html (Animations-Mockups)
from pathlib import Path

here = Path(__file__).parent
v8 = (here.parent / "redesign-v8.html").read_text(encoding="utf-8")
head = v8[: v8.index('<header class="head">')]
script = v8[v8.index("<script>") :]
extra = (here / "_extra.html").read_text(encoding="utf-8")


def page(out, title, h1, intro, files):
    parts = "".join(f.read_text(encoding="utf-8") for f in files)
    hd = head.replace("<title>Essenapp Bogen v8</title>", f"<title>{title}</title>")
    intro = f'<header class="head">\n  <h1>{h1}</h1>\n  <p>{intro}</p>\n</header>\n'
    (here.parent / out).write_text(hd + extra + intro + parts + script, encoding="utf-8")


page("redesign-v8-alle.html", "Essenapp v8 alle Screens", "Essenapp v8 – alle Screens",
     "Jede Ansicht der App im Stil „Tinte &amp; Bogen“: Farbe nur als Pastell-Formen, die aus dem Rand laufen (Kreis, Halbkreis, Tor-Bogen, Blatt, Lasche), große Zahlen mit Haarlinie, Inhalte als Zeilen statt Kästen, Nav mit Mulde. Gleiche Bausteine überall – Knöpfe, Sheets, Schalter, Felder.",
     [here / f"{n}.html" for n in "abcdef" if (here / f"{n}.html").exists()])
page("animationen-v8.html", "Essenapp v8 Animationen", "Essenapp v8 – Animationen",
     "Wie sich die App bewegt. Jede Animation läuft in Schleife; „Nochmal“ startet sie neu. Grundsatz: Bewegung erzählt mit den Zeichnungen, ist kurz (0,2–0,6 s, Warten ausgenommen), federt leicht und entfällt bei „Bewegung reduzieren“.",
     sorted(here.glob("anim*.html")))
print("ok")
