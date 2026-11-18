"""A narrow airfield tower with punched openings and a red paper beacon."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import architecture as A  # noqa: E402
import common as C  # noqa: E402

C.reset_scene()

wall, window = C.MeshBuilder(), C.MeshBuilder()
shaft = A.windowed_block(
    wall, window, 0.88, 0.88, 2.89,
    dict(front=(1, 3, {(0, 0)}), right=(1, 3), back=(1, 3), left=(1, 3)), "tower",
    door=dict(s=0.5, w=0.30, h=0.62, z=0.12))
shaft.plinth(wall, height=0.12, out=0.04)
wall.box((1.20, 1.20, 0.18), center=(0, 0, 2.90))
A.windowed_block(wall, window, 1.10, 1.07, 3.55,
                 dict(front=(2, 1), right=(2, 1), back=(2, 1), left=(2, 1)), "tower.cab",
                 taper=0.035, bottom=2.99)
# Catwalk rail round the cab: four thin card strips on corner posts.
for k in (-1, 1):
    wall.box((1.18, 0.025, 0.03), center=(0, k * 0.58, 3.22))
    wall.box((0.025, 1.18, 0.03), center=(k * 0.58, 0, 3.22))
    for j in (-1, 1):
        wall.box((0.03, 0.03, 0.24), center=(k * 0.575, j * 0.575, 3.10))
wall.box((1.17, 1.17, 0.13), center=(0, 0, 3.61))
wall.box((0.36, 0.02, 0.02), center=(0, 0, 3.86))
wall.box((0.05, 0.05, 0.32), center=(0, 0, 3.81))
wall.to_object("Wall", C.flat_material("WallMat", C.INK["wall"]), recalc=False)
window.to_object("Window", C.flat_material("WindowMat", C.INK["amber"]), recalc=False)
C.MeshBuilder().box((0.18, 0.18, 0.16), center=(0, 0, 4.02), rot=(0, 0, 45)) \
    .to_object("Beacon", C.flat_material("BeaconMat", C.INK["red"]))

C.recenter("bottom")
C.export_usdz("tower")
