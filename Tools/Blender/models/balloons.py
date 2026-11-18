"""Balloons: three folded paper balloons (origami water-bomb style) on twine.

Each balloon is a six-sided paper shell whose rings are turned half a side
against each other, so every face is a flat triangle with a diagonal crease,
and it ends in a pinched flat tab where the paper was tucked. They hang in a
bunch: three different colors, three slightly different sizes and tilts.

Parts: "BalloonA", "BalloonB", "BalloonC", "String". Size ~0.9 (X) x 1.2 (Y)
x ~0.5 (Z). Origin at the bbox center.
"""
import math
import os
import sys

from mathutils import Matrix, Vector

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import common as C  # noqa: E402

C.reset_scene()
rnd = C.rng("balloons")

SIDES = 4
# (radius, z). Four-sided shell like the origami water-bomb: a squared-off
# body with flat faces and straight creases, pinched to a point at the top
# and tucked at the bottom.
RINGS = [(0.085, 0.185), (0.215, 0.085), (0.222, -0.045), (0.150, -0.165)]
TOP_Z, BOTTOM_Z = 0.265, -0.262

JUNCTION = Vector((0.03, 0.0, -0.62))
TAB_Z = BOTTOM_Z - 0.035

BALLOONS = [
    # name, color, center, tilt (deg about X, about Y), size jitter
    ("BalloonA", C.INK["red"], Vector((-0.235, 0.03, -0.02)), (4, -18), 1.00),
    ("BalloonB", C.INK["ochre"], Vector((0.245, 0.06, 0.03)), (6, 16), 0.94),
    ("BalloonC", C.INK["blue"], Vector((0.0, -0.10, 0.30)), (-8, 2), 1.05),
]


def folded_balloon(scale, twist0):
    verts = [(0.0, 0.0, TOP_Z)]
    for r, z in RINGS:
        for k in range(SIDES):
            a = twist0 + math.tau * k / SIDES
            wob = 1.0 + rnd.uniform(-0.04, 0.04)   # hand-folded, never quite even
            verts.append((r * wob * math.cos(a), r * wob * math.sin(a), z))
    verts.append((0.0, 0.0, BOTTOM_Z))
    ring = lambda i, k: 1 + i * SIDES + k % SIDES  # noqa: E731
    faces = [[0, ring(0, k), ring(0, k + 1)] for k in range(SIDES)]
    for i in range(len(RINGS) - 1):
        for k in range(SIDES):
            faces.append([ring(i, k), ring(i + 1, k), ring(i + 1, k + 1), ring(i, k + 1)])
    last, bottom = len(RINGS) - 1, len(verts) - 1
    faces += [[ring(last, k), bottom, ring(last, k + 1)] for k in range(SIDES)]
    b = C.MeshBuilder().poly([(x * scale, y * scale, z * scale) for x, y, z in verts], faces)
    # The tucked tab: a small flat flap of paper at the bottom.
    b.box((0.07 * scale, 0.006, 0.05 * scale), center=(0, 0, (BOTTOM_Z - 0.018) * scale),
          rot=(0, 0, rnd.uniform(-25, 25)))
    return b


strings = C.MeshBuilder()
for name, color, center, (tilt_x, tilt_y), size in BALLOONS:
    rot = C.rot_chain(("X", tilt_x), ("Y", tilt_y)).to_4x4()
    place = Matrix.Translation(center) @ rot
    b = folded_balloon(size, math.radians(rnd.uniform(18, 38)))
    b.transform(place)
    b.to_object(name, C.flat_material(name + "Mat", color))

    knot = place @ Vector((0, 0, (BOTTOM_Z - 0.04) * size))
    mid = knot.lerp(JUNCTION, 0.5) + Vector((0.035 if knot.x < 0.1 else -0.03, 0.0, 0.0))
    strings.rod(knot, mid, 0.007, segments=3)
    strings.rod(mid, JUNCTION, 0.007, segments=3)

# A short tail of twine below the junction, with a tiny paper-bead knot.
strings.rod(JUNCTION + Vector((0, 0, 0.01)), JUNCTION + Vector((-0.02, 0, -0.07)), 0.009, segments=3)
strings.ico(0.017, center=tuple(JUNCTION), subdiv=1)
strings.to_object("String", C.flat_material("StringMat", C.INK["string"]))

C.recenter("center")
C.export_usdz("balloons")
