"""An origami lucky star in gold paper, facing +Z in USD.

Folded from a strip: five puffed arms, a raised pentagon in the middle and
creased valleys between the arms, folded the same on both faces. Blender
authors it in the XZ plane (thickness along Y; the front is -Y).
"""
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import common as C  # noqa: E402

C.reset_scene()
rnd = C.rng("star")
N = 5
TILT = math.radians(2.5)  # hand-folded: the whole star sits a touch off true


def polar(r, a, depth):
    return (r * math.cos(a + TILT), -depth, r * math.sin(a + TILT))


verts, faces = [], []


def add(p):
    verts.append(p)
    return len(verts) - 1


arm = [math.pi / 2 + i * math.tau / N for i in range(N)]
half = math.pi / N
tip_r = [0.225 * (1 + rnd.uniform(-0.035, 0.035)) for _ in range(N)]
shoulder_r = [0.092 * (1 + rnd.uniform(-0.05, 0.05)) for _ in range(N)]

# side +1 is the front (-Y), side -1 the back; the rim is shared and has card thickness.
rim = {}
for side in (1, -1):
    T = [add(polar(tip_r[i], arm[i], side * 0.010)) for i in range(N)]
    V = [add(polar(0.112, arm[i] + half, side * 0.022)) for i in range(N)]
    S = [add(polar(shoulder_r[i], arm[i], side * 0.088)) for i in range(N)]
    P = [add(polar(0.052, arm[i] + half, side * 0.074)) for i in range(N)]
    rim[side] = (T, V)
    quad = []
    for i in range(N):
        j = (i + 1) % N
        k = (i - 1) % N
        quad += [[T[i], V[k], S[i]], [T[i], S[i], V[i]],        # the two facets of the arm
                 [S[i], V[i], P[i]], [V[i], S[j], P[i]],        # the shoulder beside the valley
                 [S[i], P[k], P[i]]]                            # the slope into the pentagon
    quad += [[P[0], P[1], P[2]], [P[0], P[2], P[3]], [P[0], P[3], P[4]]]
    if side == -1:
        quad = [f[::-1] for f in quad]
    faces += quad

# Card edge around the rim.
(Tf, Vf), (Tb, Vb) = rim[1], rim[-1]
for i in range(N):
    j = (i + 1) % N
    faces.append([Tf[i], Vf[i], Vb[i], Tb[i]])
    faces.append([Vf[i], Tf[j], Tb[j], Vb[i]])

C.MeshBuilder().poly(verts, faces).to_object("Star", C.flat_material("StarMat", C.INK["amber"]))
C.recenter("center")
C.export_usdz("star")
