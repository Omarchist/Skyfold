"""An octagonal paper dome above hand-cut pointed windows."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import architecture as A  # noqa: E402
import common as C  # noqa: E402

C.reset_scene()

wall, window = C.MeshBuilder(), C.MeshBuilder()
A.windowed_block(wall, window, 3.55, 3.55, 2.80,
                 dict(front=(3, 1), right=(2, 1), back=(3, 1), left=(2, 1)), "landmark_dome",
                 taper=0.01, peak=0.28)
wall.to_object("Wall", C.flat_material("WallMat", C.INK["wall"]), recalc=False)
window.to_object("Window", C.flat_material("WindowMat", C.INK["ink"]), recalc=False)
dome = C.MeshBuilder()
dome.lathe([(1.88, 0), (2.0, 0.18), (1.87, 0.58), (1.58, 1.24),
            (1.08, 1.89), (0.46, 2.55), (0.12, 2.74), (0, 2.96)],
           segments=8, center=(0, 0, 2.76))
dome.to_object("Dome", C.flat_material("DomeMat", C.INK["roof"]))

C.recenter("bottom")
C.export_usdz("landmark_dome")
