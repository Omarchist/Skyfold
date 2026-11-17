"""A broad card house with a hipped, slightly uneven roof."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import architecture as A  # noqa: E402
import common as C  # noqa: E402

C.reset_scene()

wall, window = C.MeshBuilder(), C.MeshBuilder()
A.windowed_block(wall, window, 3.5, 3.0, 3.51,
                 dict(front=(2, 2), right=(1, 2), back=(2, 2), left=(1, 2)), "building_b")
roof = A.folded_roof(3.64, 3.12, 3.49, 4.50, ridge_y=0.18)

A.export_building("building_b", wall, window, roof)
