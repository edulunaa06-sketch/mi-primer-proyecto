"""Genera el icono de la app a partir de la marca, para que no sea un PNG hecho a mano.

La marca: la «N» que comparten NOW y NEVER, maciza y geométrica, en oro sobre negro, con el
filo de oro debajo. Exactamente la misma geometría que `Atlas/DesignSystem/Logo.swift`: si se
cambia una, hay que cambiar la otra.

Uso:  python3 tools/gen_appicon.py
Sale: Atlas/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
"""

import os
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
# Negro cálido, el mismo de DS.bg.
BG = (9, 8, 7)
BRONZE = (107, 77, 23)
GOLD_DARK = (184, 138, 46)
GOLD = (222, 181, 84)
CHAMPAGNE = (247, 230, 186)

# Contorno de la N, en proporción del lienzo (0…1). Los mismos puntos que BrandMark.
N_OUTLINE = [
    (0.200, 0.060), (0.355, 0.060), (0.645, 0.551), (0.645, 0.060),
    (0.800, 0.060), (0.800, 0.720), (0.645, 0.720), (0.355, 0.229),
    (0.355, 0.720), (0.200, 0.720),
]
# El filo de debajo: (izquierda, arriba, derecha, abajo).
RULE = (0.20, 0.845, 0.80, 0.863)

# En Logo.swift la marca vive dentro de un cuadrado pegado al borde porque allí la rodea la
# pantalla. En el icono no: hay que dejarle aire, o parece que se sale de la baldosa. Esto
# encoge el conjunto y lo centra, sin tocar la geometría de la letra.
MARK_SCALE = 0.84
_MARK_CY = (0.060 + RULE[3]) / 2


def fit(x, y):
    """Lleva un punto de la marca a su sitio dentro del icono, con margen."""
    return (0.5 + (x - 0.5) * MARK_SCALE, 0.5 + (y - _MARK_CY) * MARK_SCALE)


def radial(size, center, radius, color, alpha):
    """Un resplandor redondo y suave, como los del fondo de la app."""
    layer = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(layer)
    cx, cy = center[0] * size, center[1] * size
    r = radius * size
    steps = 90
    for i in range(steps, 0, -1):
        t = i / steps
        value = int(alpha * 255 * (1 - t) ** 2)
        rr = r * t
        draw.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=value)
    tinted = Image.new("RGB", (size, size), color)
    return tinted, layer


def background(size):
    """Negro con una luz cálida arriba a la izquierda y un reflejo de oro abajo."""
    img = Image.new("RGB", (size, size), BG)
    for center, radius, color, alpha in [
        ((0.16, 0.06), 0.95, BRONZE, 0.52),
        ((0.98, 0.98), 0.70, GOLD_DARK, 0.14),
    ]:
        tinted, mask = radial(size, center, radius, color, alpha)
        img = Image.composite(tinted, img, mask)
    return img


def mark_mask(size):
    """La marca en blanco sobre negro, para usarla de máscara."""
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.polygon([tuple(v * size for v in fit(x, y)) for x, y in N_OUTLINE], fill=255)
    left, top = fit(RULE[0], RULE[1])
    right, bottom = fit(RULE[2], RULE[3])
    draw.rectangle([left * size, top * size, right * size, bottom * size], fill=255)
    return mask


def gradient(size):
    """El degradado de la marca en diagonal: oro oscuro → oro → champán."""
    stops = [(0.0, GOLD_DARK), (0.5, GOLD), (1.0, CHAMPAGNE)]
    img = Image.new("RGB", (size, size))
    pixels = img.load()
    for y in range(size):
        for x in range(size):
            t = (x / size + y / size) / 2
            for i in range(len(stops) - 1):
                t0, c0 = stops[i]
                t1, c1 = stops[i + 1]
                if t <= t1 or i == len(stops) - 2:
                    k = 0 if t1 == t0 else min(max((t - t0) / (t1 - t0), 0), 1)
                    pixels[x, y] = tuple(int(c0[j] + (c1[j] - c0[j]) * k) for j in range(3))
                    break
    return img


def main():
    img = background(SIZE)
    mask = mark_mask(SIZE)
    grad = gradient(SIZE)

    # Resplandor de la marca: la propia marca desenfocada por debajo, para que el oro «caliente»
    # el negro de alrededor en vez de quedarse pegado encima.
    glow = mask.filter(ImageFilter.GaussianBlur(SIZE * 0.03)).point(lambda v: int(v * 0.38))
    img = Image.composite(grad, img, glow)
    # Y la marca nítida encima.
    img = Image.composite(grad, img, mask)

    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(here, "Atlas", "Assets.xcassets", "AppIcon.appiconset", "AppIcon-1024.png")
    img.save(out, "PNG")
    print("icono generado:", out)


if __name__ == "__main__":
    main()
