"""Storm cloud: three cut-paper layers standing one behind the other, like a
cloud in a pop-up book, with a folded paper bolt hanging off the front layer.

Parts: "Cloud" (the three layers and the two paper struts that hold them
apart), "Bolt". Size ~1.3 (X) x 1.05 (Y) x 0.95 (Z). Origin at the bbox center.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import common as C  # noqa: E402

C.reset_scene()
rnd = C.rng("storm_cloud")

# Outlines as cusps (x, z, bulge), counter-clockwise from the bottom left.
# Scallops are different sizes on purpose: cut by eye, not stamped.
BACK = [
    (-0.48, -0.04, 0.0),
    (0.56, -0.02, 0.50),
    (0.56, 0.21, 0.40),
    (0.27, 0.35, 0.44),
    (-0.20, 0.32, 0.40),
    (-0.50, 0.18, 0.50),
]
MIDDLE = [
    (-0.56, -0.17, 0.10),
    (-0.18, -0.21, 0.12),
    (0.22, -0.19, 0.09),
    (0.52, -0.13, 0.50),
    (0.50, 0.10, 0.38),
    (0.24, 0.21, 0.42),
    (-0.16, 0.19, 0.40),
    (-0.46, 0.08, 0.48),
]
FRONT = [
    (-0.50, -0.27, 0.08),
    (-0.10, -0.30, 0.10),
    (0.26, -0.26, 0.50),
    (0.24, -0.06, 0.40),
    (-0.08, 0.04, 0.42),
    (-0.42, -0.06, 0.50),
]

cloud = C.MeshBuilder()
# (outline, depth, lean, yaw): the back layer tips toward the camera and the
# front one away from it, so each takes the light differently.
for outline, y, lean, yaw in [
    (BACK, 0.42, -6.0, 3.0),
    (MIDDLE, 0.0, 2.0, -2.5),
    (FRONT, -0.42, 9.0, 4.0),
]:
    cloud.card_xz(C.scalloped(outline), y=y, thickness=0.022,
                  lean=lean + rnd.uniform(-1.0, 1.0), yaw=yaw + rnd.uniform(-0.8, 0.8))
# Paper struts between the layers (the tabs of a pop-up).
cloud.box((0.075, 0.41, 0.012), center=(-0.12, -0.21, -0.11), rot=(0, 14, 3))
cloud.box((0.075, 0.41, 0.012), center=(0.16, 0.21, 0.06), rot=(0, -11, -2))
cloud.to_object("Cloud", C.flat_material("CloudMat", C.INK["storm"]))

C.MeshBuilder().folded_bolt((0.04, -0.235), 0.29, y=-0.455) \
    .to_object("Bolt", C.flat_material("BoltMat", C.INK["amber"]))

C.recenter("center")
C.export_usdz("storm_cloud")
