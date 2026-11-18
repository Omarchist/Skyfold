"""Fighter jet component: intakes, intake trunks, engine nacelles, nozzles and stores.

Follows `jet/spec.py` (INTAKE, ENGINES, WING, STORES). Everything is built for the +Y side and
mirrored with `mirror_y`. Every solid is closed on its own (the part builders get recalculated
normals in `to_object`, which needs closed shells to orient them), so details such as the dark
intake throat are separate closed plugs that sit in a cavity of the skin rather than open tubes.

Parts: "Paper" skin, "Crease" panel bands and alternate nozzle petals, "Metal" intake throats,
nozzle interiors and missile seeker heads, "Marking" the missile bands.
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
import common as C  # noqa: E402
from jet import spec  # noqa: E402

N = 12  # segments of the trunk and nacelle rings (corners of the box sit at 45 degrees)


def _sg(v):
    return (v > 0) - (v < 0)


def ring_pts(d, cy, cz, ry, rz, e=1.0, rake=0.0, z_lo=0.0, z_hi=1.0, n=N):
    """Ring at station d. e=1 is a circle, small e a box with chamfered corners. `rake` moves the
    upper vertices forward (the slanted ramp lip) in proportion to height between z_lo and z_hi."""
    pts = []
    for k in range(n):
        a = math.radians(15 + 360.0 * k / n)
        c, s = math.cos(a), math.sin(a)
        y = cy + ry * _sg(c) * abs(c) ** e
        z = cz + rz * _sg(s) * abs(s) ** e
        t = 0.0 if rake == 0.0 else max(0.0, min(1.0, (z - z_lo) / (z_hi - z_lo)))
        pts.append((spec.x(d) + rake * t, y, z))
    return pts


def mk(b, pts):
    return [b.bm.verts.new(p) for p in pts]


def strip(b, A, B):
    n = len(A)
    for k in range(n):
        j = (k + 1) % n
        b.bm.faces.new([A[k], A[j], B[j], B[k]])


def cap(b, R):
    b.bm.faces.new(R)


def solid_loft(b, ring_list, caps=True):
    rs = [mk(b, p) for p in ring_list]
    for a, c in zip(rs, rs[1:]):
        strip(b, a, c)
    if caps:
        cap(b, rs[0])
        cap(b, rs[-1])
    return rs


# --- Intake, trunk, nacelle ---------------------------------------------------------------------
def build_skin(paper, metal, crease):
    I, E = spec.INTAKE, spec.ENGINES
    # Shrunk about 17% from the spec box (outer_y 0.103, top 0.028, bottom -0.048) after the
    # first assembled render showed the intakes too big for the fuselage.
    I = dict(I, outer_y=0.103, top=0.028, bottom=-0.048)
    yc, ry = (I["inner_y"] + I["outer_y"]) / 2, (I["outer_y"] - I["inner_y"]) / 2
    zc, rz = (I["top"] + I["bottom"]) / 2, (I["top"] - I["bottom"]) / 2
    d0, rake = I["start"], I["ramp_rake"]
    kw = dict(rake=rake, z_lo=I["bottom"], z_hi=I["top"])
    ey, er = E["y"], E["radius"]
    e_box = 0.12

    lip = 0.006
    A = ring_pts(d0, yc, zc, ry, rz, e_box, **kw)
    A_in = ring_pts(d0, yc, zc, ry - lip, rz - lip, e_box, **kw)
    cav = d0 + 0.05
    A_back = ring_pts(cav, yc, zc, ry - lip - 0.002, rz - lip - 0.002, e_box, **kw)
    # Trunk keeps its outer wall at |Y| >= 0.09 along the wing root (d to 0.86), then narrows
    # into the round nacelle; nacelle tops stay above Z 0.012 at |Y| 0.07 under the fins.
    body = [
        ring_pts(0.66, 0.068, -0.006, 0.029, 0.036, 0.3),
        ring_pts(0.86, 0.062, -0.002, 0.028, 0.035, 0.6),
        ring_pts(0.96, ey, 0.0, er + 0.002, er + 0.002, 1.0),
        ring_pts(1.05, ey, 0.0, er + 0.001, er + 0.001, 1.0),
    ]
    rA, rIn, rBack = mk(paper, A), mk(paper, A_in), mk(paper, A_back)
    rb = [mk(paper, p) for p in body]
    # outer skin from the raked lip to the nacelle exit, with the extra ring at d=0.55 straight
    strip(paper, rA, rb[0])
    for a, c in zip(rb, rb[1:]):
        strip(paper, a, c)
    cap(paper, rb[-1])
    # lip frame, cavity walls and cavity floor (cavity faces point into the hole)
    for k in range(N):
        j = (k + 1) % N
        paper.bm.faces.new([rA[k], rIn[k], rIn[j], rA[j]])
    strip(paper, rIn, rBack)
    cap(paper, rBack)
    # panel seam bands (Crease): thin closed rings around the trunk and nacelle
    seam = lambda d, cy, cz, ry_, rz_, e, w: solid_loft(
        crease, [ring_pts(d, cy, cz, ry_ + 0.0012, rz_ + 0.0012, e),
                 ring_pts(d + w, cy, cz, ry_ + 0.0012, rz_ + 0.0012, e)])
    seam(0.97, ey, 0.0, er + 0.0005, er + 0.0005, 1.0, 0.012)

    # dark throat plug: fills the cavity, slightly smaller than it
    sh = 0.0004
    p0 = ring_pts(d0 + 0.004, yc, zc, ry - lip - sh, rz - lip - sh, e_box, **kw)
    p1 = ring_pts(cav - 0.002, yc, zc, ry - lip - 0.002 - sh, rz - lip - 0.002 - sh, e_box, **kw)
    solid_loft(metal, [p0, p1])


# --- Nozzle -------------------------------------------------------------------------------------
def build_nozzle(paper, crease, metal):
    E = spec.ENGINES
    ey = E["y"]
    x0, x1 = spec.x(E["nozzle_start"]), spec.x(E["nozzle_end"])
    n = 8
    for k in range(n):
        odd = k % 2
        tgt = crease if odd else paper
        th0, th1 = 2 * math.pi * k / n, 2 * math.pi * (k + 1) / n
        r_out_b = 0.0298 if odd else 0.0305
        r_in_b = 0.0255 if odd else 0.0262
        prof = [(x0, 0.0348), (x1, r_out_b), (x0, 0.0290), (x1, r_in_b)]
        vs = []
        for th in (th0, th1):
            for (xx, r) in prof:
                vs.append(tgt.bm.verts.new((xx, ey + r * math.cos(th), r * math.sin(th))))
        # vs: [th0: of, ob, if, ib, th1: of, ob, if, ib]
        of0, ob0, if0, ib0, of1, ob1, if1, ib1 = vs
        for f in ([of0, of1, ob1, ob0], [if0, ib0, ib1, if1], [of0, if0, if1, of1],
                  [ob0, ob1, ib1, ib0], [of0, ob0, ib0, if0], [of1, if1, ib1, ob1]):
            tgt.bm.faces.new(f)
    # dark interior: a recessed cylinder inside the petals
    solid_loft(metal, [ring_pts_x(ey, spec.x(E["nozzle_end"] - 0.014), 0.0245),
                       ring_pts_x(ey, spec.x(E["nozzle_start"] - 0.02), 0.0245)])


def ring_pts_x(cy, xx, r, n=8):
    return [(xx, cy + r * math.cos(2 * math.pi * k / n), r * math.sin(2 * math.pi * k / n))
            for k in range(n)]


# --- Stores -------------------------------------------------------------------------------------
def missile(paper, crease, metal, mark, x_tail, length, cy, cz, r=0.0045, band=True):
    seg = 6
    L = length
    paper.loft_x([(x_tail, cy, cz, r * 0.9, r * 0.9),
                  (x_tail + 0.72 * L, cy, cz, r, r)], segments=seg)
    metal.loft_x([(x_tail + 0.72 * L, cy, cz, r * 0.98, r * 0.98),
                  (x_tail + 0.92 * L, cy, cz, r * 0.55, r * 0.55),
                  (x_tail + L, cy, cz, 0, 0)], segments=seg)
    if band:
        mark.loft_x([(x_tail + 0.40 * L, cy, cz, r * 1.1, r * 1.1),
                     (x_tail + 0.46 * L, cy, cz, r * 1.1, r * 1.1)], segments=seg)

    def fins(xb, chord, root, tip_r, sweep):
        for k in range(4):
            phi = math.radians(45 + 90 * k)
            u = (0.0, math.cos(phi), math.sin(phi))
            w = (0.0, -math.sin(phi), math.cos(phi))
            pts = [(xb + chord, cy + u[1] * root, cz + u[2] * root),
                   (xb, cy + u[1] * root, cz + u[2] * root),
                   (xb + sweep, cy + u[1] * tip_r, cz + u[2] * tip_r)]
            crease.slab(pts, 0.0012, direction=w)
    fins(x_tail, 0.22 * L, r * 0.8, r * 3.2, 0.0)


def build_stores(paper, crease, metal, mark):
    I, W = spec.INTAKE, spec.WING
    # four fuselage missiles (two per side, in tandem), half sunk into the lower intake corners
    cy, cz = 0.068, -0.048 + 0.0005  # lower intake edge (intake shrunk, see build_skin)
    for d_nose, d_tail in ((0.345, 0.430), (0.445, 0.530)):
        missile(paper, crease, metal, mark, spec.x(d_tail), d_tail - d_nose, cy, cz, band=False)
    # one wing pylon and slim missile per side
    yp = 0.215
    t = W["root_thickness"] + (W["tip_thickness"] - W["root_thickness"]) * \
        (yp - W["root_y"]) / (W["tip_y"] - W["root_y"])
    zw = -(yp - W["root_y"]) * math.tan(math.radians(-W["anhedral_deg"])) - 0.5 * t
    z_bot = zw - 0.016
    pts = [(spec.x(0.665), yp + 0.0020, zw + 0.002), (spec.x(0.775), yp + 0.0020, zw + 0.002),
           (spec.x(0.745), yp + 0.0020, z_bot), (spec.x(0.690), yp + 0.0020, z_bot)]
    paper.slab(pts, 0.004, direction=(0, 1, 0))
    r = 0.0042
    zc = z_bot - r + 0.0008
    missile(paper, crease, metal, mark, spec.x(0.790), 0.150, yp, zc, r=r)


def build():
    paper, crease, metal, mark = (C.MeshBuilder() for _ in range(4))
    build_skin(paper, metal, crease)
    build_nozzle(paper, crease, metal)
    build_stores(paper, crease, metal, mark)
    parts = {"Paper": paper, "Crease": crease, "Metal": metal, "Marking": mark}
    for b in parts.values():
        b.mirror_y()
    total = sum(b.tri_count() for b in parts.values())
    assert total <= spec.BUDGET["engines"], f"engines: {total} triangles over budget"
    return parts


if __name__ == "__main__":
    C.reset_scene()
    for name, b in build().items():
        print(name, b.tri_count())
