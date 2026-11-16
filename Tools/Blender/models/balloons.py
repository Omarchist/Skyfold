"""Balloons: a bunch of 3 party balloons whose strings meet below.

Parts: "BalloonA" (red, left), "BalloonB" (yellow, right), "BalloonC" (blue,
top middle, slightly toward the camera), "String" (all three strings).
Size ~0.9 (X) x 1.2 (Y) x ~0.5 (Z). Origin at the bbox center.
"""
import os
import sys

from mathutils import Matrix, Vector

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import common as C  # noqa: E402

C.reset_scene()

# Egg-shaped balloon profile (radius, z) around its own center; the knot
# is a tiny cone under the bottom pole.
PROFILE = [(0.0, 0.245), (0.135, 0.205), (0.198, 0.075), (0.180, -0.075),
           (0.090, -0.200), (0.0, -0.250)]
KNOT_TOP, KNOT_BOTTOM = -0.245, -0.292

JUNCTION = Vector((0.03, 0.0, -0.60))

BALLOONS = [
    # name, hex, center, tilt (deg about Y, about X)
    ("BalloonA", "#FF6B6B", Vector((-0.235, 0.03, -0.02)), (-18, 4)),
    ("BalloonB", "#FFC94A", Vector((0.245, 0.06, 0.03)), (16, 6)),
    ("BalloonC", "#5EC8F2", Vector((0.0, -0.10, 0.30)), (2, -8)),
]

strings = C.MeshBuilder()
for name, hex_color, center, (tilt_y, tilt_x) in BALLOONS:
    rot = C.rot_chain(("X", tilt_x), ("Y", tilt_y)).to_4x4()
    place = Matrix.Translation(center) @ rot
    b = C.MeshBuilder().lathe(PROFILE, segments=8)
    b.cone(0.028, 0.006, KNOT_BOTTOM - KNOT_TOP, center=(0, 0, (KNOT_TOP + KNOT_BOTTOM) / 2),
           segments=4)
    b.transform(place)
    b.to_object(name, C.flat_material(name + "Mat", hex_color))

    # String: knot -> gentle bend -> junction.
    knot = place @ Vector((0, 0, KNOT_BOTTOM + 0.004))
    mid = knot.lerp(JUNCTION, 0.5) + Vector((0.035 if knot.x < 0.1 else -0.03, 0.0, 0.0))
    strings.rod(knot, mid, 0.007, segments=3)
    strings.rod(mid, JUNCTION, 0.007, segments=3)

# A short tail of string hanging below the junction, with a tiny knot.
strings.rod(JUNCTION + Vector((0, 0, 0.01)), JUNCTION + Vector((-0.02, 0, -0.07)), 0.009, segments=3)
strings.ico(0.017, center=tuple(JUNCTION), subdiv=1)
strings.to_object("String", C.flat_material("StringMat", "#7A6A5A"))

C.recenter("center")
C.export_usdz("balloons")
