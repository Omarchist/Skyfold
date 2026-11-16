"""Bird: a stylized swallow/gull flying toward the player (faces -X).

Parts: "Body" (with forked tail), "WingL", "WingR", "Beak".
WingL is the bird's own left wing, on the game +Z side (toward the camera);
WingR is on -Z. Each wing's origin is at its shoulder so it flaps by rotating
about the X axis. Size ~0.47 (X) x 0.7 (Z, span). Origin at the bbox center.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import common as C  # noqa: E402

C.reset_scene()

body_mat = C.flat_material("BodyMat", "#4A4A58")
wing_mat = C.flat_material("WingMat", "#4A4A58")
beak_mat = C.flat_material("BeakMat", "#F2A33A")

# Body: a faceted spindle, big round head at -X (front), tapering to the tail.
body = C.MeshBuilder().loft_x([
    (-0.185, 0.0, 0.040, 0.0, 0.0),
    (-0.155, 0.0, 0.040, 0.050, 0.050),   # head
    (-0.085, 0.0, 0.022, 0.064, 0.064),   # chest
    (0.030, 0.0, 0.004, 0.064, 0.058),    # belly
    (0.135, 0.0, 0.004, 0.034, 0.030),    # rump
    (0.190, 0.0, 0.006, 0.0, 0.0),
], segments=6, angle_offset=0.5236)
# Forked swallow tail: a thin V-notched slab behind the body.
tail = [(0.13, -0.028, 0.010), (0.255, -0.072, 0.020), (0.205, 0.0, 0.012),
        (0.255, 0.072, 0.020), (0.13, 0.028, 0.010)]
body.slab(tail, 0.012, faces=[[0, 1, 2], [0, 2, 4], [2, 3, 4]])
body.to_object("Body", body_mat)

# Beak: a small 4-sided cone pointing -X out of the head.
C.MeshBuilder().cone(0.026, 0.0, 0.062, center=(-0.196, 0.0, 0.036), segments=4,
                     rot=C.rot_chain(("Z", 45), ("Y", -90))).to_object("Beak", beak_mat)


def wing(side):
    """side=-1: Blender -Y = game +Z (left wing). side=+1: game -Z (right)."""
    s = side
    shoulder = (0.0, s * 0.045, 0.040)
    pts = [
        (-0.075, s * 0.040, 0.044),   # 0 root, leading edge
        (-0.060, s * 0.190, 0.088),   # 1 elbow, leading edge (gull bend up)
        (0.130, s * 0.350, 0.050),    # 2 tip, swept back
        (0.080, s * 0.200, 0.070),    # 3 elbow, trailing edge
        (0.060, s * 0.040, 0.040),    # 4 root, trailing edge
    ]
    b = C.MeshBuilder().slab(pts, 0.016, faces=[[0, 1, 3, 4], [1, 2, 3]])
    return b.to_object("WingL" if s < 0 else "WingR", wing_mat, pivot=shoulder)


wing(-1)
wing(+1)

C.recenter("center")
C.export_usdz("bird")
