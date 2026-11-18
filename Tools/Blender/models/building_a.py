"""A tall card office block: shopfront and doorway, banded floors, a setback crown and a tank."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import architecture as A  # noqa: E402
import common as C  # noqa: E402

C.reset_scene()
rnd = C.rng("building_a.trim")

wall, window, roof = C.MeshBuilder(), C.MeshBuilder(), C.MeshBuilder()
body = A.windowed_block(
    wall, window, 2.5, 2.5, 5.9,
    dict(front=(3, 4, {(1, 0)}), right=(1, 4), back=(1, 4), left=(1, 4)), "building_a",
    t0=0.07, t1=0.93, gap_t=0.62, door=dict(s=0.5, w=0.52, h=1.05, z=0.24))
body.plinth(roof)
for z in body.floor_lines():
    body.course(roof, z, thick=0.07, out=0.04, rnd=rnd)
body.cornice(roof)
A.canopy(roof, 0.0, -1.27, 1.42, 0.95, 0.26)

crown = A.windowed_block(
    wall, window, 1.70, 1.62, 7.18,
    dict(front=(2, 1), right=(0, 0), back=(2, 1), left=(0, 0)), "building_a.crown",
    bottom=5.98, taper=0.02, t0=0.22, t1=0.78)
roof.box((1.86, 1.78, 0.12), center=(0.0, 0.0, 7.22))
A.water_tank(roof, 0.38, 0.22, 7.28, r=0.25, h=0.42, legs=0.20)
roof.rod((-0.55, -0.4, 7.28), (-0.55, -0.4, 8.05), 0.025, segments=3)

A.export_building("building_a", wall, window, roof)
