"""A tall card tower with a setback and a small cap."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import architecture as A  # noqa: E402
import common as C  # noqa: E402

C.reset_scene()

wall, window = C.MeshBuilder(), C.MeshBuilder()
A.windowed_block(wall, window, 2.5, 2.5, 5.9,
                 dict(front=(2, 2), right=(1, 2), back=(2, 2), left=(1, 2)), "building_a")
wall.box((1.7, 1.65, 1.95), center=(0.05, 0.06, 6.86))
roof = C.MeshBuilder()
roof.box((2.56, 2.56, 0.12), center=(0, 0, 5.90))
roof.box((1.85, 1.80, 0.19), center=(0.05, 0.06, 7.91))

A.export_building("building_a", wall, window, roof)
