# Baut redesign-v9-entwurf.html aus Stil + Nav-Skript von redesign-v8.html, v8-parts/_extra.html und den Teilen a–f.html.
# v9 = E99: Crimson Pro statt DM Serif Display, Weiß statt Beige.
from pathlib import Path

here = Path(__file__).parent
v8 = (here.parent / "redesign-v8.html").read_text(encoding="utf-8")
head = v8[: v8.index('<header class="head">')]
script = v8[v8.index("<script>") :]
extra = (here.parent / "v8-parts" / "_extra.html").read_text(encoding="utf-8")
head = (head.replace("family=DM+Serif+Display", "family=Crimson+Pro:wght@500")
        .replace("--bg:#F3EEE4", "--bg:#FFFFFF").replace("--card:#FBF8F2", "--card:#F5F5F3").replace("--page:#E2DCD0", "--page:#E9E9E9")
        .replace("<title>Essenapp Bogen v8</title>", "<title>Essenapp v9 Entwurf</title>"))
fix = '<style>/* v9: Titel-Serife Crimson Pro 500 */ .t1,.t2,.head h1,.caption b,.irow .nm,.sec h2{font-family:"Crimson Pro",serif!important;font-weight:500!important}</style>\n'
parts = "".join((here / f"{n}.html").read_text(encoding="utf-8") for n in "abcdef" if (here / f"{n}.html").exists())
intro = ('<header class="head">\n  <h1>Essenapp v9 – Entwurf zur Bewertung</h1>\n'
         '  <p>Neue Ideen nach dem iPhone-Test: Nährwert-Statistik, Woche zum Durchscrollen, Angebote mit Markt-Knöpfen, Einkaufstaschen, '
         'neues Swipen (links = mag ich), Übersicht aller Funktionen. Je Bereich mehrere Varianten (A/B/C) – bitte pro Bereich eine wählen.</p>\n</header>\n')
(here.parent / "redesign-v9-entwurf.html").write_text((head + extra + intro + parts + script).replace('"DM Serif Display"', '"Crimson Pro"'), encoding="utf-8")
print("ok")
