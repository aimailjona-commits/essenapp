"""Icons aus dem v8-Mockup (<symbol id="i-…"> in redesign-v8.html + v8-parts/_extra.html) als SwiftUI-Pfade.

Aufruf: uv run --no-project --with svgelements python ios/tools/make_icons.py
Schreibt ios/Sources/Essenapp/Icons8.swift. Bögen werden zu Kubik-Kurven (svgelements).
"""
import io
import re
from pathlib import Path

from svgelements import SVG, Arc, Close, CubicBezier, Line, Move, Path as SPath, QuadraticBezier, Shape

root = Path(__file__).resolve().parents[2]
html = (root / "docs/ui/mockups/redesign-v8.html").read_text(encoding="utf-8") + (root / "docs/ui/mockups/v8-parts/_extra.html").read_text(encoding="utf-8")
symbols = dict(re.findall(r'<symbol id="i-([a-z0-9]+)" viewBox="0 0 24 24">(.*?)</symbol>', html, re.S))
assert len(symbols) >= 40, len(symbols)


def f(v: float) -> str:
    return f"{v:.3f}".rstrip("0").rstrip(".")


def swift_path(shape: Shape) -> list[str]:
    out = []
    for seg in SPath(shape).segments():
        if isinstance(seg, Move):
            out.append(f"p.move(to: .init(x: {f(seg.end.x)}, y: {f(seg.end.y)}))")
        elif isinstance(seg, Close):
            out.append("p.closeSubpath()")
        elif isinstance(seg, Line):
            out.append(f"p.addLine(to: .init(x: {f(seg.end.x)}, y: {f(seg.end.y)}))")
        elif isinstance(seg, QuadraticBezier):
            out.append(f"p.addQuadCurve(to: .init(x: {f(seg.end.x)}, y: {f(seg.end.y)}), control: .init(x: {f(seg.control.x)}, y: {f(seg.control.y)}))")
        elif isinstance(seg, CubicBezier):
            out.append(f"p.addCurve(to: .init(x: {f(seg.end.x)}, y: {f(seg.end.y)}), control1: .init(x: {f(seg.control1.x)}, y: {f(seg.control1.y)}), control2: .init(x: {f(seg.control2.x)}, y: {f(seg.control2.y)}))")
        elif isinstance(seg, Arc):
            for c in seg.as_cubic_curves():
                out.append(f"p.addCurve(to: .init(x: {f(c.end.x)}, y: {f(c.end.y)}), control1: .init(x: {f(c.control1.x)}, y: {f(c.control1.y)}), control2: .init(x: {f(c.control2.x)}, y: {f(c.control2.y)}))")
        else:
            raise ValueError(seg)
    return out


cases, bodies = [], []
for name, inner in symbols.items():
    doc = SVG.parse(io.StringIO(
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000" stroke-width="1.8">{inner}</svg>'))
    parts = {"stroke": [], "bold": [], "fill": []}
    for el in doc.elements():
        if not isinstance(el, Shape):
            continue
        filled = el.fill is not None and el.fill.value is not None and el.fill.alpha > 0
        stroked = el.stroke is not None and el.stroke.value is not None and el.stroke.alpha > 0
        if filled:
            parts["fill"] += swift_path(el)
        if stroked:
            parts["bold" if (el.stroke_width or 1.8) > 2 else "stroke"] += swift_path(el)
    ident = name
    cases.append(ident)
    for kind in ("stroke", "bold", "fill"):
        if parts[kind]:
            body = "\n            ".join(parts[kind])
            bodies.append(f"        case (.{ident}, .{kind}):\n            {body}")

swift = f'''// Erzeugt von ios/tools/make_icons.py aus dem v8-Mockup – nicht von Hand ändern.
import SwiftUI

/// Icons des v8-Mockups (`#i-…`), Strich 1.8 auf 24er-Raster, rund.
enum Icon8: String, CaseIterable {{
    case {", ".join(cases)}

    enum Part {{ case stroke, bold, fill }}

    func path(_ part: Part) -> Path {{
        var p = Path()
        switch (self, part) {{
{chr(10).join(bodies)}
        default: break
        }}
        return p
    }}
}}
'''
out = root / "ios/Sources/Essenapp/Icons8.swift"
out.write_text(swift, encoding="utf-8")
print(len(cases), "Icons ->", out)
