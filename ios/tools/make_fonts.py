"""Feste Schnitte aus den variablen Schriften (Redesign v3, docs/ui/redesign-v3.md Abschnitt 3).

SwiftUI kann Fraunces-Achsen (SOFT, WONK, opsz) nicht setzen, ohne Dynamic Type zu verlieren.
Darum werden die gebrauchten Achsen-Werte hier einmal als statische TTFs erzeugt.

Aufruf: uv run --no-project --with fonttools python ios/tools/make_fonts.py <quellordner> ios/Sources/Essenapp/Resources/fonts
Quellen (OFL, google/fonts): Fraunces[SOFT,WONK,opsz,wght].ttf als Fraunces-Roman.ttf,
Fraunces-Italic[...].ttf als Fraunces-Italic.ttf, JetBrainsMono[wght].ttf als JetBrainsMono.ttf.
"""
import sys
from pathlib import Path

from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

# PostScript-Name: (Quelle, Achsen)
INSTANCES = {
    "FrauncesV3-Display": ("Fraunces-Roman.ttf", {"wght": 800, "opsz": 144, "SOFT": 100, "WONK": 1}),  # DisplayHeader
    "FrauncesV3-Title": ("Fraunces-Roman.ttf", {"wght": 800, "opsz": 28, "SOFT": 100, "WONK": 1}),  # Karten-Titel
    "FrauncesV3-Bold": ("Fraunces-Roman.ttf", {"wght": 700, "opsz": 72, "SOFT": 100, "WONK": 0}),  # Satz, hervorgehoben
    "FrauncesV3-Black": ("Fraunces-Roman.ttf", {"wght": 900, "opsz": 20, "SOFT": 0, "WONK": 0}),  # Preis-Stern
    "FrauncesV3-Italic": ("Fraunces-Italic.ttf", {"wght": 400, "opsz": 144, "SOFT": 100, "WONK": 1}),  # DisplayHeader Zeile 2
    "FrauncesV3-TextItalic": ("Fraunces-Italic.ttf", {"wght": 400, "opsz": 72, "SOFT": 100, "WONK": 0}),  # Satz
    "JetBrainsMonoV3-Medium": ("JetBrainsMono.ttf", {"wght": 500}),
    "JetBrainsMonoV3-Bold": ("JetBrainsMono.ttf", {"wght": 700}),
}


def rename(font: TTFont, ps: str) -> None:
    family, style = ps.split("-")
    for rec in list(font["name"].names):
        if rec.nameID in (1, 2, 3, 4, 6, 16, 17, 25):
            font["name"].removeNames(nameID=rec.nameID)
    for nid, value in ((1, f"{family} {style}"), (2, "Regular"), (3, ps), (4, f"{family} {style}"), (6, ps)):
        font["name"].setName(value, nid, 3, 1, 0x409)
        font["name"].setName(value, nid, 1, 0, 0)


def main(src: Path, out: Path) -> None:
    out.mkdir(parents=True, exist_ok=True)
    for ps, (file, axes) in INSTANCES.items():
        font = instantiateVariableFont(TTFont(src / file), axes)
        rename(font, ps)
        font.save(out / f"{ps}.ttf")
        check = TTFont(out / f"{ps}.ttf")
        assert "fvar" not in check and check["name"].getDebugName(6) == ps, ps
        print(ps, (out / f"{ps}.ttf").stat().st_size)


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
