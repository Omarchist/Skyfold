"""Kite: a diamond kite facing the camera (+Z), leaning forward (top toward
+X, the direction of flight), with a short tail of 3 bows streaming back.

Parts: "Sail" (4 folded facets), "Spar" (the cross sticks on the camera side
and the tail string), "Tail" (the 3 bows).
Sail ~0.8 wide x 1.0 tall before the lean. Origin at the bbox center.
"""
import math
import os
import sys

from mathutils import Matrix, Vector

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import common as C  # noqa: E402

C.reset_scene()

LEAN = 15.0   # degrees, top toward +X
PITCH = 8.0   # degrees, face tipped up toward the sky (top away from camera)
place = (Matrix.Rotation(math.radians(LEAN), 4, "Y")
         @ Matrix.Rotation(math.radians(-PITCH), 4, "X"))

# Kite frame: X across, Z up, -Y toward the camera.
TOP, BOTTOM = Vector((0, 0, 0.38)), Vector((0, 0, -0.62))
LEFT, RIGHT = Vector((-0.40, 0, 0.08)), Vector((0.40, 0, 0.08))
CENTER = Vector((0, -0.06, 0.08))   # the cross bulges toward the camera
THICK = 0.012

front = [TOP, RIGHT, BOTTOM, LEFT, CENTER]
back = [v + Vector((0, THICK, 0)) for v in front]
verts = front + back
faces = [[4, 0, 1], [4, 1, 2], [4, 2, 3], [4, 3, 0],            # front facets
         [9, 6, 5], [9, 7, 6], [9, 8, 7], [9, 5, 8]]            # back facets
for i in range(4):
    j = (i + 1) % 4
    faces.append([i, j, j + 5, i + 5])
sail = C.MeshBuilder().poly(verts, faces)
sail.transform(place)
sail.to_object("Sail", C.flat_material("SailMat", "#FF7A45"))

# Spars: the classic cross, sitting on the camera side of the sail.
lift = Vector((0, -0.014, 0))
spar = C.MeshBuilder()
for corner in (TOP, BOTTOM, LEFT, RIGHT):
    inward = (CENTER - corner).normalized()
    spar.rod(corner + inward * 0.025 + lift, CENTER + lift, 0.012, segments=4)
spar.transform(place)

# Tail: a string from the bottom corner streaming back (-X) and down, with
# three bows along it.
bottom = place @ BOTTOM
tail_pts = [bottom,
            bottom + Vector((-0.10, 0.0, -0.13)),
            bottom + Vector((-0.24, 0.0, -0.20)),
            bottom + Vector((-0.38, 0.0, -0.22)),
            bottom + Vector((-0.50, 0.0, -0.28))]
for a, b in zip(tail_pts, tail_pts[1:]):
    spar.rod(a, b, 0.006, segments=3)
spar.to_object("Spar", C.flat_material("SparMat", "#6B4E3D"))

bows = C.MeshBuilder()
for i, t in enumerate((1, 2, 3)):
    p = tail_pts[t]
    d = (tail_pts[t + 1] - tail_pts[t - 1]).normalized()   # along the string
    n = Vector((d.z, 0, -d.x))                              # across, in the XZ plane
    w, h = 0.085, 0.050
    # bow-tie: two triangles meeting at the knot
    for sgn in (1, -1):
        tri = [p, p + n * w * sgn + d * h, p + n * w * sgn - d * h]
        bows.slab([tuple(v + Vector((0, -0.006, 0))) for v in tri], 0.012,
                  direction=(0, -1, 0))
    bows.box((0.028, 0.026, 0.028), center=tuple(p + Vector((0, -0.006, 0))), rot=(0, 30, 0))
bows.to_object("Tail", C.flat_material("TailMat", "#FFD166"))

C.recenter("center")
C.export_usdz("kite")
