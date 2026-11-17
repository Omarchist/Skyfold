"""A low terminal with a folded roof and an offset canopy."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import architecture as A  # noqa: E402
import common as C  # noqa: E402

C.reset_scene()

wall, window = C.MeshBuilder(), C.MeshBuilder()
A.windowed_block(wall, window, 5.0, 2.8, 2.10,
                 dict(front=(4, 1), right=(2, 1), back=(4, 1), left=(2, 1)), "building_d",
                 taper=0.02)
roof = A.folded_roof(5.11, 2.99, 2.08, 2.51, ridge_y=0.40)
roof.box((3.45, 0.37, 0.07), center=(-0.25, -1.52, 1.94), rot=(7, 0, 0))

A.export_building("building_d", wall, window, roof)
