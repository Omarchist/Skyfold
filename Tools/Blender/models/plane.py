"""Paper plane: a classic folded dart. Nose points +X.

Parts: "Paper" (wing tops, the folded-over flaps, the paper edges), "Crease"
(wing undersides and the keel, the shaded side of every fold).
Size ~0.90 (X) x 0.22 (Y, up) x 0.75 (Z, span). Origin at the bbox center.

Folded by hand, so nothing is mirrored exactly: the left wing is a hair
longer, its tip a hair higher, and the two tail flaps are not the same size.
"""
import os
import sys

from mathutils import Vector

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import common as C  # noqa: E402

C.reset_scene()

NOSE_X, TAIL_X = 0.45, -0.40
T = 0.009  # card thickness of the folded sheet (two layers hold the keel)

# Blender: +X nose, +Z up, Y = span (+Y is the game's -Z side).
# Each side: fold point on the trailing edge, wingtip, leading-edge flap tip.
SIDES = {
    +1: dict(fold=(TAIL_X, 0.125, 0.012), tip=(TAIL_X + 0.045, 0.385, 0.074)),
    -1: dict(fold=(TAIL_X + 0.004, -0.133, 0.010), tip=(TAIL_X + 0.058, -0.366, 0.067)),
}

nose = (NOSE_X, 0.0, 0.0)
tail = (TAIL_X, 0.0, 0.0)
(fl, tl) = SIDES[+1]["fold"], SIDES[+1]["tip"]
(fr, tr) = SIDES[-1]["fold"], SIDES[-1]["tip"]

# Wing sheet: four flat facets, two a side, creased from the nose to the
# trailing edge. The outer facet climbs, so the plane reads as a shallow V.
outline = [nose, tl, fl, tail, fr, tr]
wings = C.MeshBuilder().slab(outline, T, faces=[[0, 1, 2], [0, 2, 3], [0, 3, 4], [0, 4, 5]])
wings.recalc_normals()
under = wings.extract(lambda f: f.normal.z < -0.5)

# Leading-edge flaps: the strip folded back over each wing. A real dart shows
# it as a second, slightly steeper triangle on top of the outer facet.
paper = wings
for s in (+1, -1):
    sd = SIDES[s]
    fx, fy, fz = sd["fold"]
    tx, ty, tz = sd["tip"]
    # flap corners: near the nose on the leading edge, out to the tip, back
    # in along the fold. Lifted one card thickness off the facet.
    a = Vector((NOSE_X - 0.115, s * 0.012, 0.0))
    b = Vector((tx + 0.02, ty * 0.97, tz + 0.001))
    c = Vector((fx + 0.17, fy * 0.9 + s * 0.02, fz + 0.5 * (tz - fz) * 0.7))
    lift = Vector((0, 0, T * 1.25))
    pts = [tuple(a + lift), tuple(b + lift), tuple(c + lift)]
    if s < 0:
        pts = pts[::-1]
    flap = C.solid(lambda bld, pts=pts: bld.slab(pts, T * 0.9))
    paper.merge(flap)

# Tail flaps: the elevators, each tipped up a few degrees. Different sizes.
for s, depth, rise in ((+1, 0.060, 0.030), (-1, 0.047, 0.022)):
    sd = SIDES[s]
    fx, fy, fz = sd["fold"]
    tx, ty, tz = sd["tip"]
    p0 = Vector((fx + 0.07, fy + (ty - fy) * 0.15, fz + 0.002))
    p1 = Vector((tx - 0.025, fy + (ty - fy) * 0.78, tz - 0.012))
    q0 = p0 + Vector((-depth, 0.0, rise))
    q1 = p1 + Vector((-depth * 0.85, 0.0, rise * 0.9))
    quad = [tuple(p0), tuple(p1), tuple(q1), tuple(q0)] if s > 0 else \
           [tuple(p1), tuple(p0), tuple(q0), tuple(q1)]
    paper.merge(C.solid(lambda bld, quad=quad: bld.slab(quad, T * 0.8)))

# Keel: the two layers of the centre fold, a narrow wedge that is deepest at the
# tail. Each side has its own diagonal facet so it catches the light.
kz = -T * 0.5
bottom = (TAIL_X + 0.035, 0.002, -0.148)
keel_verts = [
    (NOSE_X - 0.012, 0.0, kz),           # 0 nose
    (TAIL_X + 0.004, 0.019, kz),         # 1 rear top +Y
    (TAIL_X + 0.004, -0.017, kz),        # 2 rear top -Y
    bottom,                              # 3 rear bottom
    (-0.10, 0.013, -0.074),              # 4 fold point +Y
    (-0.10, -0.011, -0.078),             # 5 fold point -Y
]
keel_faces = [
    [0, 1, 4], [4, 1, 3], [0, 4, 3],     # +Y side
    [0, 5, 2], [5, 3, 2], [0, 3, 5],     # -Y side
    [1, 2, 3],                           # back
    [0, 2, 1],                           # top (hidden under the wings)
]
under.merge(C.solid(lambda bld: bld.poly(keel_verts, keel_faces)))

paper.to_object("Paper", C.flat_material("PaperMat", C.INK["warm_white"]), recalc=False)
under.to_object("Crease", C.flat_material("CreaseMat", C.INK["crease"]), recalc=False)

C.recenter("center")
C.export_usdz("plane")
