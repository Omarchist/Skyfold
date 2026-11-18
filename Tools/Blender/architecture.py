"""Punched card walls and printed trim shared by the tower and the city models.

A building is three parts: the card `Wall` with its openings punched through, the
`Window` sheet glued behind them (dark by day, sodium amber at night), and the trim
(`Roof`, or `Dome` on the landmark): roofs, floor bands, cornices, canopies and the
small things on top. Trim is cut from a darker card so floors read at a glance.
"""
import math

import common as C


class Block:
    """One tapered card box with its window rows, for placing trim against it."""

    def __init__(self, width, depth, bottom, height, taper, rows, t0, t1, gap_t):
        self.width, self.depth = width, depth
        self.bottom, self.height, self.taper = bottom, height, taper
        self.rows, self.t0, self.t1, self.gap_t = rows, t0, t1, gap_t

    def size_at(self, z):
        """(width, depth) of the box at height z; the walls lean in toward the top."""
        k = (z - self.bottom) / (self.height - self.bottom)
        return self.width - 2 * self.taper * k, self.depth - 2 * self.taper * k

    def z_at(self, t):
        return self.bottom + t * (self.height - self.bottom)

    def floor_lines(self):
        """Heights midway between window rows: where one floor ends and the next starts."""
        h = (self.t1 - self.t0) / (self.rows + (self.rows - 1) * self.gap_t)
        return [self.z_at(self.t0 + r * h * (1 + self.gap_t) + h + h * self.gap_t / 2)
                for r in range(self.rows - 1)]

    def course(self, trim, z, thick=0.08, out=0.05, rnd=None):
        """A flat band of card wrapped round the box at height z (its middle)."""
        w, d = self.size_at(z)
        tilt = rnd.uniform(-0.6, 0.6) if rnd else 0.0
        trim.box((w + 2 * out, d + 2 * out, thick), center=(0, 0, z), rot=(0, tilt, 0))
        return self

    def sills(self, trim, cols, skip=(), s0=0.14, s1=0.86, gap_s=0.55, rows=None):
        """A card sill under each front window, matching `C.window_grid`'s defaults."""
        rows = rows or self.rows
        w = (s1 - s0) / (cols + (cols - 1) * gap_s)
        h = (self.t1 - self.t0) / (rows + (rows - 1) * self.gap_t)
        for r in range(rows):
            z = self.z_at(self.t0 + r * h * (1 + self.gap_t))
            fw, fd = self.size_at(z)
            for c in range(cols):
                if (c, r) in skip:
                    continue
                s = s0 + c * w * (1 + gap_s) + w / 2
                trim.box((w * fw + 0.10, 0.10, 0.05), center=(-fw / 2 + s * fw, -fd / 2 - 0.03, z - 0.03))
        return self

    def plinth(self, trim, height=0.24, out=0.045):
        """The darker base course the walls stand on."""
        trim.box((self.width + 2 * out, self.depth + 2 * out, height),
                 center=(0, 0, self.bottom + height / 2))
        return self

    def cornice(self, trim, out=0.10, thick=0.10, under=0.07):
        """A stepped cornice: a narrow corbel under a wider cap, at the top of the walls."""
        z = self.height
        w, d = self.size_at(z)
        trim.box((w + out, d + out, under), center=(0, 0, z - thick / 2 - under / 2 + 0.005))
        trim.box((w + 2 * out, d + 2 * out, thick), center=(0, 0, z))
        return self


def windowed_block(wall, window, width, depth, height, openings, name,
                   *, taper=0.035, peak=0.0, bottom=0.0, t0=0.16, t1=0.89, gap_t=0.80,
                   span=(0.14, 0.86), gap_s=0.55, door=None):
    """A card box with openings punched through each wall and a backing sheet behind.

    openings: per side, (cols, rows) or (cols, rows, skip) where skip is a set of
    (col, row) cells left uncut. span: the window grid's extent across each wall. door: dict(s=0.5, w=0.7, h=1.2, z=0.24, peak=0.0)
    cuts a doorway in the front wall, centred at s across, w wide and h tall
    (meters) from height z. Returns a `Block` for placing trim.
    """
    rnd = C.rng(name)
    sides = ("front", "right", "back", "left")
    faces = wall.block(-width / 2, width / 2, -depth / 2, depth / 2,
                       bottom, height, inset=taper, rnd=rnd, wobble=0.018,
                       floor=True, skip=sides)
    rows_seen = 1
    for side in sides:
        cols, rows, *rest = openings[side]
        skip = rest[0] if rest else ()
        rows_seen = max(rows_seen, rows)
        face = faces[side]
        holes = C.window_grid(face, cols, rows, s0=span[0], s1=span[1], t0=t0, t1=t1, gap_s=gap_s, gap_t=gap_t,
                              rnd=rnd, wobble=0.015, peak=peak, skip=skip)
        if door and side == "front":
            holes.append(door_hole(face, height - bottom, rnd=rnd, **door))
        wall.punched(face, holes)
        window.backing(face, inset=0.045, margin=0.04)
    return Block(width, depth, bottom, height, taper, rows_seen, t0, t1, gap_t)


def door_hole(face, wall_height, s=0.5, w=0.7, h=1.2, z=0.24, peak=0.0, rnd=None):
    """A doorway outline in face coordinates (see `C.window_grid`)."""
    fw, _ = C.face_size(face)
    a, b = s - w / 2 / fw, s + w / 2 / fw
    lo, hi = z / wall_height, (z + h) / wall_height

    def j():
        return rnd.uniform(-0.01, 0.01) / fw if rnd else 0.0

    ring = [(a + j(), lo), (b + j(), lo), (b + j(), hi)]
    if peak:
        ring.append(((a + b) / 2, hi + peak / wall_height))
    ring.append((a + j(), hi))
    return ring


def gable(builder, x0, x1, y0, y1, z0, z1, axis="x"):
    """A small pitched roof: a triangular prism whose ridge runs along `axis`."""
    if axis == "x":
        ym = (y0 + y1) / 2
        verts = [(x0, y0, z0), (x0, y1, z0), (x0, ym, z1), (x1, y0, z0), (x1, y1, z0), (x1, ym, z1)]
    else:
        xm = (x0 + x1) / 2
        verts = [(x1, y0, z0), (x0, y0, z0), (xm, y0, z1), (x1, y1, z0), (x0, y1, z0), (xm, y1, z1)]
    builder.merge(C.solid(lambda b: b.poly(verts, [
        (0, 2, 1), (3, 4, 5), (0, 1, 4, 3), (1, 2, 5, 4), (2, 0, 3, 5),
    ])))
    return builder


def canopy(trim, x, y, z, width, reach, thick=0.06, droop=6.0):
    """A flat card canopy over a doorway on the front wall, its outer edge dipping a little."""
    trim.box((width, reach, thick), center=(x, y - reach / 2, z), rot=(-droop, 0, 0))
    return trim


def water_tank(trim, x, y, z, r=0.30, h=0.55, legs=0.30):
    """A rooftop water tank: a six-sided drum on a slab, under a low paper cone."""
    trim.box((2 * r + 0.06, 2 * r + 0.06, legs), center=(x, y, z + legs / 2))
    trim.cylinder(r, h, segments=6, center=(x, y, z + legs + h / 2))
    trim.cone(r * 1.12, 0.0, r * 0.7, segments=6, center=(x, y, z + legs + h + r * 0.35))
    return trim


def chimney(trim, x, y, z0, z1, w=0.26, d=0.22):
    """A brick chimney stack with a wider cap."""
    trim.box((w, d, z1 - z0), center=(x, y, (z0 + z1) / 2))
    trim.box((w + 0.08, d + 0.08, 0.07), center=(x, y, z1))
    return trim


def pinnacle(trim, x, y, z, r=0.10, h=0.42):
    """A four-sided paper spike on a small square foot."""
    trim.box((2 * r, 2 * r, 0.08), center=(x, y, z + 0.04))
    trim.cone(r * 1.1, 0.0, h, segments=4, rot=(0, 0, 45), center=(x, y, z + 0.08 + h / 2))
    return trim


def disc(builder, center, normal_y, r, sides=8, lift=0.0):
    """A flat polygon facing -Y (normal_y=-1) or +Y (normal_y=1): a clock face, a porthole."""
    cx, cy, cz = center
    pts = [(cx + r * math.cos(2 * math.pi * k / sides + math.pi / sides), cy + normal_y * lift,
            cz + r * math.sin(2 * math.pi * k / sides + math.pi / sides)) for k in range(sides)]
    if normal_y > 0:
        pts.reverse()
    return builder.poly(pts, [list(range(sides))])


def folded_roof(width, depth, bottom, top, ridge_y=0.0):
    """A hipped roof made from four card planes meeting at a ridge."""
    x, y = width / 2, depth / 2
    verts = [(-x, -y, bottom), (x, -y, bottom), (x, y, bottom), (-x, y, bottom),
             (-x * 0.64, ridge_y, top), (x * 0.56, ridge_y, top)]
    return C.solid(lambda roof: roof.poly(verts, [
        (0, 3, 2, 1), (0, 1, 5, 4), (1, 2, 5), (2, 3, 4, 5), (3, 0, 4),
    ]))


def export_building(name, wall, window, roof):
    wall.to_object("Wall", C.flat_material("WallMat", C.INK["wall"]), recalc=False)
    window.to_object("Window", C.flat_material("WindowMat", C.INK["amber"]), recalc=False)
    roof.to_object("Roof", C.flat_material("RoofMat", C.INK["roof"]))
    C.recenter("bottom")
    C.export_usdz(name, max_tris=C.BUILDING_TRI_BUDGET)
