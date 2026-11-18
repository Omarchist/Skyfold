"""A narrow postcard clock tower: banded shaft, a clock stage, corner pinnacles and a spire."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import architecture as A  # noqa: E402
import common as C  # noqa: E402

C.reset_scene()
rnd = C.rng("building_c.trim")

wall, window, roof = C.MeshBuilder(), C.MeshBuilder(), C.MeshBuilder()
shaft = A.windowed_block(
    wall, window, 1.6, 1.6, 6.50,
    dict(front=(1, 5, {(0, 0)}), right=(1, 5), back=(1, 5), left=(1, 5)), "building_c",
    taper=0.06, t0=0.06, t1=0.94, gap_t=0.75, span=(0.31, 0.69), peak=0.14, door=dict(s=0.5, w=0.50, h=0.95, z=0.22, peak=0.22))
shaft.plinth(roof, height=0.22)
for z in shaft.floor_lines()[::2]:
    shaft.course(roof, z, thick=0.07, out=0.04, rnd=rnd)
shaft.cornice(roof, out=0.08, thick=0.10, under=0.06)

# Clock stage: a plain card drum with a face on the front and back.
wall.box((1.30, 1.30, 0.80), center=(0, 0, 6.95))
for sign in (-1, 1):
    A.disc(window, (0.0, sign * 0.65, 6.97), sign, 0.36, sides=8, lift=0.012)
roof.box((1.46, 1.46, 0.10), center=(0, 0, 7.38))

# Spire, with a pinnacle on each corner of the stage.
roof.cone(0.86, 0.0, 1.40, segments=4, rot=(0, 0, 45), center=(0, 0, 8.13))
for x in (-0.62, 0.62):
    for y in (-0.62, 0.62):
        A.pinnacle(roof, x, y, 7.43, r=0.07, h=0.36)
roof.rod((0, 0, 8.70), (0, 0, 9.05), 0.02, segments=3)

A.export_building("building_c", wall, window, roof)
