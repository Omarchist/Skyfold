"""Draw the app icon: a flat airmail graphic, no 3D render.

Cream card, diagonal red and blue airmail stripes round the edge, one folded
paper dart made of flat facets, and a hard offset shadow (no blur). The day
icon ships as an opaque 1024 x 1024 RGB PNG; the night study is for reference.
Pure numpy (supersampled, so the edges are clean), run through Blender's Python:

    blender --background --factory-startup --python Tools/Blender/render_icon.py
"""
import argparse
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import common as C  # noqa: E402

APP_ICON = os.path.join(C.PROJECT_ROOT, "Skyfold", "Assets.xcassets",
                        "AppIcon.appiconset", "AppIcon.png")
NIGHT_ICON = os.path.join(HERE, "previews", "icon_night.png")

SIZE = 1024
SS = 3                      # supersampling factor
BORDER = 104                # width of the striped border in px
STRIPE, GAP = 46, 18        # diagonal stripe and cream gap, measured along x + y (/ sqrt 2)

# The dart in its own frame (nose along +x, y up), in px at 1024. Each facet is
# a flat triangle of one tone: lit wing, shaded wing, and the inner fold.
NOSE, TAIL = (330, 34), (-262, -14)
TIP_UP, TIP_DOWN = (-246, 262), (-176, -214)
FOLD_UP, FOLD_DOWN = (-256, 116), (-232, -112)
FACETS = [  # (triangle, tone)
    ((NOSE, TIP_UP, FOLD_UP), "lit"),
    ((NOSE, FOLD_UP, TAIL), "wing"),
    ((NOSE, TAIL, FOLD_DOWN), "fold"),
    ((NOSE, FOLD_DOWN, TIP_DOWN), "shade"),
]
ANGLE = 31.0                # degrees the dart climbs, nose up and to the right
CENTER = (500, 520)         # where the dart's middle sits on the canvas
SHADOW = (30, 36)           # hard offset, down and to the right

DAY = dict(card="#F4ECDD", stripes=("#D6402B", "#2C4F9E"), shadow="#CCC3B6", crease="#9C8466",
           lit="#FFFFFF", wing="#E8DCC4", fold="#B9A47E", shade="#D3C3A0")
NIGHT = dict(card="#161B28", stripes=("#E5A03A", "#7D93C6"), shadow="#0F1320", crease="#6E7585",
             lit="#F1EAD8", wing="#D3CBB7", fold="#8E8C83", shade="#B6AE9D")


def rgb(hex_color):
    h = hex_color.lstrip("#")
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], np.float32)


def place(point, shift=(0, 0)):
    """Dart frame to canvas pixels (y down), rotated, with an optional offset."""
    a = math.radians(ANGLE)
    x, y = point
    rx, ry = x * math.cos(a) - y * math.sin(a), x * math.sin(a) + y * math.cos(a)
    return CENTER[0] + rx + shift[0], CENTER[1] - ry + shift[1]


def fill_triangle(img, tri, color):
    n = img.shape[0]
    pts = np.array(tri, np.float32) * SS
    x0, y0 = np.floor(pts.min(axis=0)).astype(int).clip(0, n - 1)
    x1, y1 = np.ceil(pts.max(axis=0)).astype(int).clip(0, n - 1)
    ys, xs = np.mgrid[y0:y1 + 1, x0:x1 + 1]
    px, py = xs + 0.5, ys + 0.5
    inside = np.ones(px.shape, bool)
    signs = []
    for i in range(3):
        ax, ay = pts[i]
        bx, by = pts[(i + 1) % 3]
        signs.append((bx - ax) * (py - ay) - (by - ay) * (px - ax))
    pos = np.all([s >= 0 for s in signs], axis=0)
    neg = np.all([s <= 0 for s in signs], axis=0)
    inside = pos | neg
    region = img[y0:y1 + 1, x0:x1 + 1]
    region[inside] = color


def draw(palette, path):
    n = SIZE * SS
    img = np.empty((n, n, 3), np.float32)
    img[:] = rgb(palette["card"])

    # Airmail border: 45 degree stripes, red and blue with cream between.
    ys, xs = np.mgrid[0:n, 0:n]
    u = ((xs + ys) / SS / math.sqrt(2.0)) % (2 * (STRIPE + GAP))
    red = u < STRIPE
    blue = (u >= STRIPE + GAP) & (u < 2 * STRIPE + GAP)
    edge = np.minimum(np.minimum(xs, n - 1 - xs), np.minimum(ys, n - 1 - ys)) / SS
    border = edge < BORDER
    img[border & red] = rgb(palette["stripes"][0])
    img[border & blue] = rgb(palette["stripes"][1])
    del ys, xs, u, red, blue, edge, border

    # Hard offset shadow first, then the folded dart on top.
    for tri, _ in FACETS:
        fill_triangle(img, [place(p, SHADOW) for p in tri], rgb(palette["shadow"]))
    for tri, tone in FACETS:
        fill_triangle(img, [place(p) for p in tri], rgb(palette[tone]))
    # The centre crease: a thin sliver along the fold from nose to tail.
    nose, tail = np.array(NOSE, float), np.array(TAIL, float)
    side = np.array([0.0, 4.0])
    fill_triangle(img, [place(tuple(nose)), place(tuple(tail + side)), place(tuple(tail - side))],
                  rgb(palette["crease"]))

    small = img.reshape(SIZE, SS, SIZE, SS, 3).mean(axis=(1, 3))
    out = np.clip(small + 0.5, 0, 255).astype(np.uint8)
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    C.write_png(path, out)
    print(f"[icon] {path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plane", help="unused, kept so older command lines still work")
    parser.add_argument("--day", default=APP_ICON)
    parser.add_argument("--night", default=NIGHT_ICON)
    args = parser.parse_args(C.script_args())
    draw(DAY, args.day)
    draw(NIGHT, args.night)


if __name__ == "__main__":
    main()
