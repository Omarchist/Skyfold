"""An octagonal paper dome on a windowed drum, above hand-cut pointed windows and an arched door."""
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import architecture as A  # noqa: E402
import common as C  # noqa: E402

C.reset_scene()

wall, window, trim = C.MeshBuilder(), C.MeshBuilder(), C.MeshBuilder()
hall = A.windowed_block(
    wall, window, 3.55, 3.55, 2.80,
    dict(front=(3, 1, {(1, 0)}), right=(2, 1), back=(3, 1), left=(2, 1)), "landmark_dome",
    taper=0.01, peak=0.28, door=dict(s=0.5, w=0.62, h=1.30, z=0.26, peak=0.30))
hall.plinth(trim, height=0.26, out=0.06)
hall.cornice(trim, out=0.10, thick=0.12, under=0.07)
trim.box((1.10, 0.36, 0.13), center=(0.0, -1.94, 0.065))  # the front step
for x in (-1.72, 1.72):
    for y in (-1.72, 1.72):
        A.pinnacle(trim, x, y, 2.86, r=0.11, h=0.46)

# Drum: an eight-sided band of card with a pane on every face.
DRUM_R, DRUM_Z0, DRUM_Z1 = 1.48, 2.86, 3.38
wall.lathe([(DRUM_R, 0.0), (DRUM_R, DRUM_Z1 - DRUM_Z0)], segments=8, center=(0, 0, DRUM_Z0))
apothem = DRUM_R * math.cos(math.pi / 8) + 0.012
for k in range(8):
    a = (k + 0.5) * math.pi / 4
    cx, cy = apothem * math.cos(a), apothem * math.sin(a)
    tx, ty = -math.sin(a) * 0.15, math.cos(a) * 0.15
    z0, z1 = DRUM_Z0 + 0.12, DRUM_Z1 - 0.12
    window.poly([(cx - tx, cy - ty, z0), (cx + tx, cy + ty, z0),
                 (cx + tx, cy + ty, z1), (cx - tx, cy - ty, z1)], [[0, 1, 2, 3]])

# The dome, then a small lantern and finial on its crown.
trim.lathe([(1.60, 0.0), (1.58, 0.30), (1.41, 0.80), (1.05, 1.34),
            (0.55, 1.80), (0.18, 2.02), (0.0, 2.10)],
           segments=8, center=(0, 0, DRUM_Z1 + 0.05))
crown = DRUM_Z1 + 0.05 + 2.02
trim.cylinder(0.20, 0.34, segments=6, center=(0, 0, crown + 0.17))
trim.cone(0.28, 0.0, 0.34, segments=6, center=(0, 0, crown + 0.51))
trim.rod((0, 0, crown + 0.66), (0, 0, crown + 0.92), 0.02, segments=3)

wall.to_object("Wall", C.flat_material("WallMat", C.INK["wall"]), recalc=False)
window.to_object("Window", C.flat_material("WindowMat", C.INK["ink"]), recalc=False)
trim.to_object("Dome", C.flat_material("DomeMat", C.INK["roof"]))

C.recenter("bottom")
C.export_usdz("landmark_dome")
