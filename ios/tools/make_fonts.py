"""Feste Schnitte aus den variablen Schriften (Redesign v8, docs/ui/redesign-v8.md Abschnitt 2).

SwiftUI kann Gewichts-Achsen variabler Schriften nicht zuverlässig mit Dynamic Type setzen,
darum werden die gebrauchten Gewichte hier einmal als statische TTFs erzeugt.

Aufruf: uv run --no-project --with fonttools python ios/tools/make_fonts.py <quellordner> ios/Sources/Essenapp/Resources/fonts
Quellen (OFL, google/fonts): Manrope[wght].ttf als Manrope.ttf, InterTight[wght].ttf als InterTight.ttf.
DM Serif Display ist statisch und wird unverändert kopiert (DMSerifDisplay-Regular.ttf).
"""
import sys
from pathlib import Path

from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

# PostScript-Name: (Quelle, Achsen)
INSTANCES = {
    "ManropeV8-Medium": ("Manrope.ttf", {"wght": 500}),
    "ManropeV8-SemiBold": ("Manrope.ttf", {"wght": 600}),  # Grundtext
    "ManropeV8-Bold": ("Manrope.ttf", {"wght": 700}),
    "ManropeV8-ExtraBold": ("Manrope.ttf", {"wght": 800}),  # Labels, Knöpfe
    "InterTightV8-Medium": ("InterTight.ttf", {"wght": 500}),
    "InterTightV8-SemiBold": ("InterTight.ttf", {"wght": 600}),  # große Zahlen
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
