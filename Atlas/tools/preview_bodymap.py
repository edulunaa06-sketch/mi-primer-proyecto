"""Vista previa del mapa del cuerpo leyendo las coordenadas de BodyMap.swift.

No duplica los datos: los saca del propio archivo Swift, así que lo que se ve aquí es
exactamente lo que dibuja la app. Sirve para colocar los músculos sin esperar al CI.

Uso:  python3 tools/preview_bodymap.py [salida.png]
"""

import os
import re
import sys
from PIL import Image, ImageDraw

W, H = 420, 903  # 1 : 2.15, el mismo lienzo que usa la app
COLORS = {
    None: (26, 28, 34),
    "low": (60, 64, 78),
    "mid": (86, 110, 220),
    "high": (64, 196, 228),
}

PIECE = re.compile(
    r'Piece\("(?P<name>[^"]+)",\s*(?P<group>nil|\.\w+)(?P<mirror>,\s*mirrored:\s*(?:true|false))?,\s*\[(?P<pts>[^\]]*)\]',
    re.S,
)
PAIR = re.compile(r"\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*\)")


def sections(text):
    """Devuelve {nombre de la lista: trozo de texto} para silhouette, front y back."""
    out = {}
    for key in ("silhouette", "front", "back"):
        m = re.search(r"static let %s: \[Piece\] = \[(.*?)\n    \]" % key, text, re.S)
        if m:
            out[key] = m.group(1)
    return out


def parse(block):
    pieces = []
    for m in PIECE.finditer(block):
        pts = [(float(a), float(b)) for a, b in PAIR.findall(m.group("pts"))]
        mirrored = "false" not in (m.group("mirror") or "")
        pieces.append((m.group("name"), m.group("group"), mirrored, pts))
    return pieces


def draw_side(img, pieces, silhouette, x0):
    d = ImageDraw.Draw(img, "RGBA")

    def poly(points, fill, outline=None):
        xy = [(x0 + x * W, y * H) for x, y in points]
        d.polygon(xy, fill=fill, outline=outline)

    for _, _, mirrored, pts in silhouette:
        poly(pts, COLORS[None])
        if mirrored:
            poly([(1 - x, y) for x, y in pts], COLORS[None])

    # Colores de ejemplo para ver que cada músculo se distingue del de al lado.
    palette = ["low", "mid", "high"]
    for i, (name, _group, mirrored, pts) in enumerate(pieces):
        color = COLORS[palette[i % len(palette)]]
        poly(pts, color, outline=(10, 11, 14))
        if mirrored:
            poly([(1 - x, y) for x, y in pts], color, outline=(10, 11, 14))
        cx = x0 + sum(x for x, _ in pts) / len(pts) * W
        cy = sum(y for _, y in pts) / len(pts) * H
        d.text((cx - 18, cy - 4), name.split("-")[0][:9], fill=(255, 255, 255, 200))


def main():
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    swift = open(os.path.join(here, "Atlas", "Models", "BodyMap.swift"), encoding="utf-8").read()
    blocks = sections(swift)
    silhouette = parse(blocks["silhouette"])
    img = Image.new("RGB", (W * 2 + 30, H), (6, 7, 10))
    draw_side(img, parse(blocks["front"]), silhouette, 0)
    draw_side(img, parse(blocks["back"]), silhouette, W + 30)
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "tools", "bodymap-preview.png")
    img.save(out)
    print("vista previa:", out)


if __name__ == "__main__":
    main()
