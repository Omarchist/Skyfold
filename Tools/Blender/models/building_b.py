"""A broad card townhouse: hipped roof with a dormer and chimney, porch over the door."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import architecture as A  # noqa: E402
import common as C  # noqa: E402

C.reset_scene()
rnd = C.rng("building_b.trim")

wall, window, roof = C.MeshBuilder(), C.MeshBuilder(), C.MeshBuilder()
body = A.windowed_block(
    wall, window, 3.5, 3.0, 3.51,
    dict(front=(3, 2, {(1, 0)}), right=(2, 2), back=(2, 2), left=(2, 2)), "building_b",
    t0=0.14, t1=0.88, gap_t=0.95, door=dict(s=0.5, w=0.56, h=1.18, z=0.22))
body.plinth(roof, height=0.22)
for z in body.floor_lines():
    body.course(roof, z, thick=0.08, out=0.045, rnd=rnd)
body.sills(roof, 3, skip={(1, 0)})
body.cornice(roof, out=0.07, thick=0.08, under=0.05)
roof.merge(A.folded_roof(3.70, 3.18, 3.53, 4.50, ridge_y=0.18))

# Porch: a little pitched hood on two brackets over the door.
A.gable(roof, -0.48, 0.48, -1.74, -1.42, 1.50, 1.82, axis="y")
roof.box((0.07, 0.30, 0.07), center=(-0.40, -1.58, 1.46))
roof.box((0.07, 0.30, 0.07), center=(0.40, -1.58, 1.46))

# Dormer on the front slope, with its own window.
wall.box((0.62, 0.70, 0.52), center=(-0.62, -0.92, 3.94))
A.gable(roof, -0.98, -0.26, -1.30, -0.54, 4.18, 4.46, axis="y")
window.poly([(-0.80, -1.28, 3.76), (-0.44, -1.28, 3.76), (-0.44, -1.28, 4.08),
             (-0.80, -1.28, 4.08)], [[0, 1, 2, 3]])

A.chimney(roof, 1.05, 0.55, 3.9, 4.72)

A.export_building("building_b", wall, window, roof)
