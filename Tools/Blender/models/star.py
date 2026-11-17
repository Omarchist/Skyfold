"""A gold paper star, creased from each tip to the middle, facing +Z in USD."""
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import common as C  # noqa: E402

C.reset_scene()

ring = []
for i in range(10):
    angle = math.pi / 2 + i * math.tau / 10
    radius = 0.24 if i % 2 == 0 else 0.105
    ring.append((radius * math.cos(angle), radius * math.sin(angle)))

vertices = [(x, -0.009, z) for x, z in ring] + [(x, 0.009, z) for x, z in ring]
front, back = len(vertices), len(vertices) + 1
vertices.extend([(0.008, -0.09, 0.014), (-0.01, 0.09, 0.01)])
faces = []
for i in range(10):
    nxt = (i + 1) % 10
    faces.extend([(i, nxt, front), (nxt + 10, i + 10, back), (nxt, i, i + 10, nxt + 10)])

C.MeshBuilder().poly(vertices, faces).to_object("Star", C.flat_material("StarMat", C.INK["amber"]))
C.recenter("center")
C.export_usdz("star")
