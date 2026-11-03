"""Papierkorn-Kachel für `PaperGrain` (redesign-v3.md Abschnitt 5): 180 px, schwarz, Alpha = Rauschen × 9 %.

Aufruf: uv run --no-project --with pillow python ios/tools/make_grain.py
"""
import random
from pathlib import Path

from PIL import Image

SIZE, ALPHA = 180, 0.09
random.seed(45)  # gleiche Datei bei jedem Lauf
img = Image.new("LA", (SIZE, SIZE))
img.putdata([(0, int(random.random() * ALPHA * 255)) for _ in range(SIZE * SIZE)])
out = Path(__file__).resolve().parents[1] / "Sources/Essenapp/Resources/grain.png"
img.save(out, optimize=True)
print(out, out.stat().st_size)
