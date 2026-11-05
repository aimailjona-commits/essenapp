# Baut redesign-v8-dunkel.html aus redesign-v8.html (Kopf, 9 Kern-Screens, Nav-Skript),
# v8-parts/_extra.html (Bausteine) und _dunkel.html (Dunkel-Tokens, Kopftext, Bausteine-Leiste).
# Hell/Dunkel-Paare entstehen im Browser: jedes .phone/.kit wird geklont und bekommt .dark.
from pathlib import Path

here = Path(__file__).parent
mock = here.parent
v8 = (mock / "redesign-v8.html").read_text(encoding="utf-8")
extra = (mock / "v8-parts" / "_extra.html").read_text(encoding="utf-8")
top, tail = (here / "_dunkel.html").read_text(encoding="utf-8").split("<!-- SCREENS -->")

head = v8[: v8.index('<header class="head">')].replace(
    "<title>Essenapp Bogen v8</title>", "<title>Essenapp v8 Dunkel</title>")
screens = v8[v8.index('<div class="screens">') : v8.index("<script>")]
script = v8[v8.index("<script>") :]
(mock / "redesign-v8-dunkel.html").write_text(head + extra + top + screens + tail + script, encoding="utf-8")
print("ok")
