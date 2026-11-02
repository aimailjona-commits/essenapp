# Erzeugt ios/Icon.png (1024 px). Aufruf in WSL: uv run --with pillow ios/tools/make_icon.py
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

S = 1024
img = Image.new("RGB", (S, S), "#111111")
shadow = Image.new("L", (S, S), 0)
ImageDraw.Draw(shadow).ellipse((212, 252, 812, 852), fill=140)
img.paste("#000000", mask=shadow.filter(ImageFilter.GaussianBlur(40)))
d = ImageDraw.Draw(img)
d.ellipse((212, 212, 812, 812), fill="#FFFFFF")  # Teller
d.ellipse((262, 262, 762, 762), fill="#ECEBE7")  # Tellerrand
d.ellipse((312, 312, 712, 712), fill="#9FE05A")  # Gericht in Limettengrün
img.save(Path(__file__).parent.parent / "Icon.png")
