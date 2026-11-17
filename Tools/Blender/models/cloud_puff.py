"""A three-layer scenery cloud with folded paper supports."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import common as C  # noqa: E402

C.reset_scene()

outline = C.scalloped([
    (-0.98, -0.44, 0.08),
    (-0.20, -0.49, 0.06),
    (0.79, -0.42, 0.20),
    (1.05, -0.01, 0.45),
    (0.70, 0.28, 0.39),
    (0.25, 0.35, 0.41),
    (-0.43, 0.52, 0.43),
    (-0.79, 0.25, 0.40),
    (-1.05, 0.04, 0.46),
])
cloud = C.MeshBuilder()
for y, scale, dx, dz, lean, yaw in [
    (0.54, 1.00, 0.02, 0.06, -4.0, -2.0),
    (0.02, 0.91, 0.08, -0.01, 3.0, 1.0),
    (-0.55, 0.74, -0.18, -0.12, 7.0, 4.0),
]:
    cloud.card_xz([(x * scale + dx, z * scale + dz) for x, z in outline],
                  y=y, thickness=0.022, lean=lean, yaw=yaw)
cloud.box((0.12, 1.08, 0.019), center=(0.30, 0.02, -0.21), rot=(0, 11, 2))
cloud.box((0.12, 1.08, 0.019), center=(-0.37, 0.02, -0.07), rot=(0, -11, -4))
cloud.to_object("Cloud", C.flat_material("CloudMat", C.INK["warm_white"]))

C.recenter("center")
C.export_usdz("cloud_puff")
