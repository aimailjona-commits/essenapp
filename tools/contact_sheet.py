# Fügt Screenshots zu einem Übersichtsbild zusammen. Aufruf: uv run --no-project --with pillow tools/contact_sheet.py <ordner> <ausgabe.png> [namen...]
import sys
from pathlib import Path

from PIL import Image, ImageDraw

folder, out, *names = sys.argv[1:]
files = [Path(folder) / f"{n}.png" for n in names] if names else sorted(Path(folder).glob("*.png"))
W = 360
thumbs = []
for f in files:
    im = Image.open(f).convert("RGB")
    im = im.resize((W, int(im.height * W / im.width)))
    thumbs.append((f.stem, im))
H = max(t.height for _, t in thumbs) + 30
cols = min(4, len(thumbs))
rows = (len(thumbs) + cols - 1) // cols
sheet = Image.new("RGB", (cols * (W + 10), rows * H), "#888888")
draw = ImageDraw.Draw(sheet)
for i, (name, im) in enumerate(thumbs):
    x, y = (i % cols) * (W + 10), (i // cols) * H
    sheet.paste(im, (x, y + 26))
    draw.text((x + 4, y + 6), name, fill="white")
sheet.save(out)
