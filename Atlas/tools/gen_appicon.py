"""Genera el icono de la app a partir de la marca, para que no sea un PNG hecho a mano.

La marca: el rayo de Now or Never dentro de su aro abierto, en blanco sobre una baldosa
azul. Exactamente la misma geometría que `Atlas/DesignSystem/Logo.swift`: si se cambia una,
hay que cambiar la otra.

La app por dentro es clara, pero el icono va en azul fuerte a propósito: en la pantalla de
inicio compite con el fondo de pantalla del móvil, y una baldosa casi blanca ahí se pierde.

Uso:  python3 tools/gen_appicon.py
Sale: Atlas/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
"""

import math
import os

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024

# Los azules de la marca, los mismos de DS (0…255).
INDIGO = (84, 69, 224)
CYAN = (13, 133, 184)
# El arranque oscuro de la baldosa, para que el degradado tenga recorrido.
DEEP = (38, 28, 120)
WHITE = (255, 255, 255)

# El rayo en proporción del lienzo (0…1). Los mismos puntos que BrandBolt.
BOLT = [
    (0.566, 0.070), (0.662, 0.070), (0.548, 0.432), (0.742, 0.432),
    (0.430, 0.930), (0.336, 0.930), (0.452, 0.568), (0.258, 0.568),
]
BOLT_SCALE = 0.58      # lo que ocupa el rayo dentro del cuadro, como en BrandBolt
RING_RADIUS = 0.415    # como en BrandRing
RING_WIDTH = 0.058     # como en BrandLogo
RING_GAP = 62          # grados de hueco arriba, como en BrandRing

# En Logo.swift la marca llena su cuadro porque allí la rodea la pantalla. En el icono hay que
# dejarle aire, o parece que se sale de la baldosa.
MARK_SCALE = 0.80


def fit(x, y):
    """Lleva un punto de la marca a su sitio dentro del icono, con margen."""
    return (0.5 + (x - 0.5) * MARK_SCALE, 0.5 + (y - 0.5) * MARK_SCALE)


def gradient(size, c0, c1):
    """Degradado en diagonal, de la esquina de arriba a la izquierda a la de abajo a la derecha."""
    img = Image.new("RGB", (size, size))
    pixels = img.load()
    for y in range(size):
        for x in range(size):
            t = (x / size + y / size) / 2
            pixels[x, y] = tuple(int(c0[i] + (c1[i] - c0[i]) * t) for i in range(3))
    return img


def background(size):
    """La baldosa: azul profundo arriba a la izquierda, azul de la marca abajo a la derecha."""
    img = gradient(size, DEEP, CYAN)
    # Un lavado de índigo por el medio, para que el salto de un azul a otro no se vea como
    # una banda.
    wash = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(wash)
    cx, cy, r = 0.30 * size, 0.22 * size, 0.95 * size
    steps = 90
    for i in range(steps, 0, -1):
        t = i / steps
        draw.ellipse([cx - r * t, cy - r * t, cx + r * t, cy + r * t],
                     fill=int(0.75 * 255 * (1 - t) ** 2))
    return Image.composite(Image.new("RGB", (size, size), INDIGO), img, wash)


def mark_mask(size):
    """La marca (aro + rayo) en blanco sobre negro, para usarla de máscara."""
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)

    # El aro, con el hueco centrado arriba. En PIL los ángulos van en el sentido de las agujas
    # desde las 3 en punto, así que arriba son 270 grados.
    r = RING_RADIUS * MARK_SCALE * size
    w = RING_WIDTH * MARK_SCALE * size
    cx = cy = 0.5 * size
    start, end = 270 + RING_GAP / 2, 270 - RING_GAP / 2 + 360
    draw.arc([cx - r, cy - r, cx + r, cy + r], start=start, end=end, fill=255, width=int(round(w)))
    # PIL no sabe rematar el arco en redondo: los extremos se redondean a mano. Ojo con el
    # radio: PIL pinta el grosor hacia DENTRO del rectángulo, así que la línea media del aro
    # no está en r sino en r - w/2. Poniendo los remates en r sobresalen como alfileres.
    mid = r - w / 2
    for angle in (start, end):
        px = cx + mid * math.cos(math.radians(angle))
        py = cy + mid * math.sin(math.radians(angle))
        draw.ellipse([px - w / 2, py - w / 2, px + w / 2, py + w / 2], fill=255)

    # El rayo, centrado por su caja igual que en BrandBolt.
    xs = [p[0] for p in BOLT]
    ys = [p[1] for p in BOLT]
    bx, by = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    points = []
    for x, y in BOLT:
        fx, fy = fit(0.5 + (x - bx) * BOLT_SCALE, 0.5 + (y - by) * BOLT_SCALE)
        points.append((fx * size, fy * size))
    draw.polygon(points, fill=255)
    return mask


def main():
    img = background(SIZE)
    mask = mark_mask(SIZE)

    # Una sombra muy baja debajo de la marca, para despegarla del azul sin ensuciarlo.
    shadow = mask.filter(ImageFilter.GaussianBlur(SIZE * 0.018)).point(lambda v: int(v * 0.30))
    img = Image.composite(Image.new("RGB", (SIZE, SIZE), DEEP), img, shadow)
    # Y la marca nítida encima, en blanco.
    img = Image.composite(Image.new("RGB", (SIZE, SIZE), WHITE), img, mask)

    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out = os.path.join(here, "Atlas", "Assets.xcassets", "AppIcon.appiconset", "AppIcon-1024.png")
    img.save(out, "PNG")
    print("icono generado:", out)


if __name__ == "__main__":
    main()
