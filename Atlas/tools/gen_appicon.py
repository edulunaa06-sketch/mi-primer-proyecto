"""Genera el icono de la app a partir de la marca, para que no sea un PNG hecho a mano.

La marca: una «N» (la inicial que comparten NEVER y NOW) atravesada por una barra olímpica
con sus discos. Misma construcción que tenía la «A» anterior, así que la marca evoluciona
en lugar de empezar de cero.

Uso:  python3 tools/gen_appicon.py
Sale: Atlas/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
"""

import os
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
BG = (6, 7, 10)
INDIGO = (115, 97, 255)
CYAN = (41, 212, 242)

# Geometría de la marca, en proporción del lienzo (0…1). La misma que usa Logo.swift.
STROKE = 0.085
N_LEFT, N_RIGHT = 0.27, 0.73
N_TOP, N_BOTTOM = 0.14, 0.62
BAR_Y = 0.80
BAR_LEFT, BAR_RIGHT = 0.10, 0.90
# (x del centro, alto) de cada disco.
PLATES = [(0.14, 0.24), (0.20, 0.17), (0.80, 0.17), (0.86, 0.24)]
PLATE_W = 0.045


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
    img = Image.new("RGB", (size, size), BG)
    for center, radius, color, alpha in [
        ((0.16, 0.06), 0.95, INDIGO, 0.42),
        ((0.98, 0.98), 0.75, CYAN, 0.16),
    ]:
        tinted, mask = radial(size, center, radius, color, alpha)
        img = Image.composite(tinted, img, mask)
    return img


def thick_line(draw, a, b, width, size):
    """Línea gruesa con las puntas redondeadas (Pillow no tiene lineCap)."""
    ax, ay = a[0] * size, a[1] * size
    bx, by = b[0] * size, b[1] * size
    w = width * size
    draw.line([ax, ay, bx, by], fill=255, width=int(w))
    r = w / 2
    for x, y in [(ax, ay), (bx, by)]:
        draw.ellipse([x - r, y - r, x + r, y + r], fill=255)


def mark_mask(size):
    """La marca en blanco sobre negro, para usarla de máscara."""
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    # La N: dos verticales y la diagonal.
    thick_line(draw, (N_LEFT, N_BOTTOM), (N_LEFT, N_TOP), STROKE, size)
    thick_line(draw, (N_LEFT, N_TOP), (N_RIGHT, N_BOTTOM), STROKE, size)
    thick_line(draw, (N_RIGHT, N_BOTTOM), (N_RIGHT, N_TOP), STROKE, size)
    # La barra, que la cruza y sobresale por los dos lados.
    thick_line(draw, (BAR_LEFT, BAR_Y), (BAR_RIGHT, BAR_Y), STROKE, size)
    # Los discos.
    for x, height in PLATES:
        half_w, half_h = PLATE_W / 2 * size, height / 2 * size
        cx, cy = x * size, BAR_Y * size
        draw.rounded_rectangle(
            [cx - half_w, cy - half_h, cx + half_w, cy + half_h],
            radius=half_w * 0.6, fill=255,
        )
    return mask


def gradient(size):
    """Degradado índigo → cian en diagonal, el de la marca."""
    img = Image.new("RGB", (size, size))
    pixels = img.load()
    for y in range(size):
        for x in range(size):
            t = (x / size + y / size) / 2
            pixels[x, y] = tuple(int(INDIGO[i] + (CYAN[i] - INDIGO[i]) * t) for i in range(3))
    return img


def main():
    img = background(SIZE)
    mask = mark_mask(SIZE)
    grad = gradient(SIZE)

    # Resplandor de la marca: la propia marca desenfocada por debajo.
    glow = mask.filter(ImageFilter.GaussianBlur(SIZE * 0.045)).point(lambda v: int(v * 0.75))
    img = Image.composite(grad, img, glow)
    # Y la marca nítida encima.
    img = Image.composite(grad, img, mask)

    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(here, "Atlas", "Assets.xcassets", "AppIcon.appiconset", "AppIcon-1024.png")
    img.save(out, "PNG")
    print("icono generado:", out)


if __name__ == "__main__":
    main()
