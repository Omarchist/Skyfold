"""Thunderhead: a big two-lane cloud column with an anvil top and two bolts.

Parts: "Cloud", "Bolt" (both bolts in one part).
Size ~1.8 (X) x 3.1 (Y) x 1.6 (Z). Origin at the bbox center, which sits
between the two lanes it blocks.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import common as C  # noqa: E402

C.reset_scene()

BASE = -1.18
cloud = C.MeshBuilder()
# Base puffs (flat cloud base).
for x, y, r, h, spin in [
    (-0.38, 0.05, 0.52, 1.45, 0),
    (0.40, 0.08, 0.50, 1.40, 25),
    (0.02, -0.30, 0.50, 1.55, 12),
]:
    cloud.dome((x, y, BASE), r, height=h, spin=spin)
# Column, slightly narrower: the waist under the anvil.
cloud.dome((-0.08, 0.06, -0.55), 0.56, height=1.55, segments=6, spin=8)
cloud.dome((0.10, -0.04, 0.02), 0.52, height=1.45, segments=6, spin=40)
# Anvil: a wide, flat-topped cap spreading out over the column.
anvil = [(0.42, 0.0), (0.94, 0.15), (1.0, 0.30), (0.72, 0.46), (0.0, 0.52)]
cloud.lathe([(r * 0.90, z * 0.90) for r, z in anvil], segments=8,
            center=(0.04, 0.0, 0.62), angle_offset=0.2)
cloud.bm.verts.ensure_lookup_table()
for v in cloud.bm.verts:                      # squash the anvil in depth
    if v.co.z > 0.6 and abs(v.co.y) > 0.0:
        v.co.y *= 0.86
cloud.to_object("Cloud", C.flat_material("CloudMat", "#4A4E63"))

bolts = C.MeshBuilder()
bolts.bolt((-0.30, -0.28, BASE + 0.10), 0.47, thickness=0.08)
bolts.bolt((0.42, -0.10, BASE + 0.10), 0.36, thickness=0.08, mirror=True)
bolts.to_object("Bolt", C.flat_material("BoltMat", "#FFE066"))

C.recenter("center")
C.export_usdz("thunderhead")
