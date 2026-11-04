# Baut redesign-v8-alle.html aus redesign-v8.html (Stil + Nav-Skript), _extra.html (Bausteine) und den Teilen a–f.
from pathlib import Path

here = Path(__file__).parent
v8 = (here.parent / "redesign-v8.html").read_text(encoding="utf-8")
head = v8[: v8.index('<header class="head">')].replace("<title>Essenapp Bogen v8</title>", "<title>Essenapp v8 alle Screens</title>")
script = v8[v8.index("<script>") :]
intro = """<header class="head">
  <h1>Essenapp v8 – alle Screens</h1>
  <p>Jede Ansicht der App im Stil „Tinte &amp; Bogen“: Farbe nur als Pastell-Formen, die aus dem Rand laufen (Kreis, Halbkreis, Tor-Bogen, Blatt, Lasche), große Zahlen mit Haarlinie, Inhalte als Zeilen statt Kästen, Nav mit Mulde. Gleiche Bausteine überall – Knöpfe, Sheets, Schalter, Felder.</p>
</header>
"""
parts = "".join((here / f"{n}.html").read_text(encoding="utf-8") for n in "abcdef" if (here / f"{n}.html").exists())
(here.parent / "redesign-v8-alle.html").write_text(head + (here / "_extra.html").read_text(encoding="utf-8") + intro + parts + script, encoding="utf-8")
print("ok")
