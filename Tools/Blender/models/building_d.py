"""A low terminal hall: entrance doors under a canopy on posts, a sign board, roof vents."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import architecture as A  # noqa: E402
import common as C  # noqa: E402

C.reset_scene()

wall, window, roof = C.MeshBuilder(), C.MeshBuilder(), C.MeshBuilder()
hall = A.windowed_block(
    wall, window, 5.0, 2.8, 2.10,
    dict(front=(5, 1, {(2, 0)}), right=(2, 1), back=(4, 1), left=(2, 1)), "building_d",
    taper=0.02, t0=0.18, t1=0.80, gap_s=0.40, door=dict(s=0.5, w=0.78, h=1.20, z=0.20))
hall.plinth(roof, height=0.20, out=0.04)
hall.sills(roof, 5, skip={(2, 0)}, gap_s=0.40)
hall.cornice(roof, out=0.06, thick=0.08, under=0.05)
roof.merge(A.folded_roof(5.14, 2.96, 2.12, 2.51, ridge_y=0.40))

# Entrance: a flat canopy on two posts, and a sign board on the wall above it.
A.canopy(roof, 0.0, -1.38, 1.50, 1.12, 0.30, droop=4.0)
for x in (-0.48, 0.48):
    roof.rod((x, -1.62, 0.0), (x, -1.62, 1.50), 0.035, segments=4, cap=False)
roof.box((1.00, 0.05, 0.24), center=(0.0, -1.43, 1.80))

# Two vent boxes on the back slope, offset so the roofline is not symmetric.
for x, w in ((-1.30, 0.42), (0.90, 0.30)):
    roof.box((w, w, 0.30), center=(x, 0.70, 2.38))
    roof.box((w + 0.08, w + 0.08, 0.05), center=(x, 0.70, 2.55))

A.export_building("building_d", wall, window, roof)
