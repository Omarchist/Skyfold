"""Three cut-card layers rise into an anvil cloud above two folded bolts."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import common as C  # noqa: E402

C.reset_scene()

# A narrow column under a broad cap distinguishes it from the storm cloud.
outline = C.scalloped([
    (-0.35, -1.15, 0.08),
    (0.29, -1.11, 0.11),
    (0.38, -0.56, 0.24),
    (0.32, 0.34, 0.04),
    (0.68, 0.60, 0.33),
    (0.78, 1.01, 0.30, 2),
    (0.46, 1.30, 0.31, 2),
    (-0.15, 1.34, 0.37),
    (-0.70, 1.23, 0.35),
    (-0.82, 0.85, 0.27),
    (-0.31, 0.47, 0.04),
    (-0.43, -0.32, 0.19),
])
cloud = C.MeshBuilder()
for y, scale, dx, dz, lean, yaw in [
    (0.73, 1.00, 0.02, 0.04, -9.0, 0.0),
    (0.05, 0.86, 0.11, -0.09, 3.0, -3.0),
    (-0.68, 0.76, -0.08, -0.25, 10.0, 3.0),
]:
    pts = [(x * scale + dx, z * scale + dz) for x, z in outline]
    if y < -0.3:   # the back layer is the same cut flipped over: no two layers match
        pts = [(-x, z) for x, z in reversed(pts)]
    cloud.card_xz(pts,
                  y=y, thickness=0.045, lean=lean, yaw=yaw)
cloud.box((0.15, 1.42, 0.035), center=(-0.07, 0.06, 0.64), rot=(0, 11, 2))
cloud.box((0.12, 1.42, 0.035), center=(0.02, 0.04, -0.50), rot=(0, -8, -2))
cloud.to_object("Cloud", C.flat_material("CloudMat", C.INK["storm"]))

bolts = C.MeshBuilder()
bolts.folded_bolt((-0.17, -1.02), 0.62, y=-0.73)
bolts.folded_bolt((0.24, -0.98), 0.44, y=-0.24, flip=True)
bolts.to_object("Bolt", C.flat_material("BoltMat", C.INK["amber"]))

C.recenter("center")
C.export_usdz("thunderhead")
