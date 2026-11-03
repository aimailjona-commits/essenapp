# Erzeugt ios/Icon.png und das PWA-Icon (1024 px): Kochpilot-Banner-Flieger (E88).
# Aufruf in WSL: uv run --no-project --with pillow ios/tools/make_icon.py
import math
from pathlib import Path

from PIL import Image, ImageDraw

K = 4096 / 100  # Entwurf im 100er-Raster, 4-fach gezeichnet und verkleinert = glatte Kanten
BG, LIME, LIME2, LIME3, DEAL, WHITE = "#14161A", "#C6F36B", "#9FD24A", "#7FB33A", "#FF5A36", "#FFFFFF"

img = Image.new("RGB", (4096, 4096), BG)
d = ImageDraw.Draw(img)


def px(pts):
    return [(x * K, y * K) for x, y in pts]


def tag(x, y):  # Preisschild: um -25° gedreht, nach (14, 58) verschoben
    a = math.radians(-25)
    return (14 + x * math.cos(a) - y * math.sin(a), 58 + x * math.sin(a) + y * math.cos(a))


def dot(c, r, fill):
    d.ellipse(((c[0] - r) * K, (c[1] - r) * K, (c[0] + r) * K, (c[1] + r) * K), fill=fill)


d.line(px([(45, 53.5), (64, 46)]), fill=WHITE, width=round(1.5 * K))  # Schleppseil
d.polygon(px([tag(*p) for p in [(0, 0), (22, 0), (30, 9), (22, 18), (0, 18)]]), fill=DEAL)
dot(tag(24, 9), 2, BG)  # Loch
for c in [(7.5, 5.5), (14.5, 13)]:  # Prozentzeichen
    dot(tag(*c), 2.4, WHITE)
    dot(tag(*c), 1.1, DEAL)
d.line(px([tag(15, 4), tag(7, 14.5)]), fill=WHITE, width=round(2.2 * K))

plane = lambda pts: px([(38 + 0.6 * x, 4 + 0.6 * y) for x, y in pts])  # noqa: E731
d.polygon(plane([(16, 48), (82, 22), (46, 58)]), fill=LIME)
d.polygon(plane([(46, 58), (82, 22), (60, 78)]), fill=LIME2)
d.polygon(plane([(46, 58), (44, 72), (53, 64)]), fill=LIME3)

img = img.resize((1024, 1024), Image.LANCZOS)
root = Path(__file__).parent.parent
img.save(root / "Icon.png")
img.save(root.parent / "backend/app/web/static/icon.png")
