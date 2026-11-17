"""A double boarding gate facing the side camera, with outer door hinges."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import common as C  # noqa: E402

C.reset_scene()

frame = C.MeshBuilder()
for x in (-0.82, 0.82):
    frame.box((0.16, 0.30, 2.19), center=(x, 0, 1.095))
frame.box((1.80, 0.30, 0.18), center=(0, 0, 2.10))
frame.to_object("Frame", C.flat_material("FrameMat", C.INK["wall"]))

door_mat = C.flat_material("DoorMat", C.INK["blue"])
for name, x0, x1, hinge in [
    ("DoorL", -0.74, -0.009, -0.74),
    ("DoorR", 0.009, 0.74, 0.74),
]:
    panel = C.MeshBuilder()
    panel.box_minmax((x0, -0.068, 0.025), (x1, -0.032, 2.0))
    panel.card_xz([(x0 + 0.055, 0.16), (x1 - 0.053, 0.17),
                   (x1 - 0.060, 1.74), (x0 + 0.057, 1.77)],
                  y=-0.073, thickness=0.018)
    panel.to_object(name, door_mat, pivot=(hinge, -0.05, 0.0))

C.MeshBuilder().card_xz([(-0.79, 2.17), (0.80, 2.20), (0.74, 2.58), (-0.76, 2.60)],
                        y=-0.095, thickness=0.05) \
    .to_object("Sign", C.flat_material("SignMat", C.INK["red"]))
C.MeshBuilder().box((1.47, 0.026, 2.01), center=(0, 0.095, 1.005)) \
    .to_object("Glow", C.flat_material("BackingMat", C.INK["cream"]))

C.recenter("bottom")
C.export_usdz("gate")
