"""A narrow postcard spire with a four-sided folded roof."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import architecture as A  # noqa: E402
import common as C  # noqa: E402

C.reset_scene()

wall, window = C.MeshBuilder(), C.MeshBuilder()
A.windowed_block(wall, window, 1.6, 1.6, 6.64,
                 dict(front=(1, 4), right=(1, 3), back=(1, 4), left=(1, 3)), "building_c",
                 taper=0.06)
roof = C.MeshBuilder()
roof.box((1.62, 1.62, 0.14), center=(0, 0, 6.64))
roof.box((1.35, 1.35, 0.36), center=(0, 0, 6.88))
roof.cone(0.89, 0, 1.96, segments=4, rot=(0, 0, 45), center=(0, 0, 8.02))

A.export_building("building_c", wall, window, roof)
