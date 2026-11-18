"""Fighter jet component: intakes, intake trunks, engine nacelles, nozzles, hook and stores.

Follows `jet/spec.py` (INTAKE, ENGINES, WING, STORES). Everything is built for the +Y side and
mirrored with `mirror_y`, except the centreline parts (arresting hook, fuel tank and its pylon),
which are added after the mirror. Every solid is closed on its own (the part builders get
recalculated normals in `to_object`, which needs closed shells to orient them), so details such as
the dark intake throat are closed plugs and liners that sit in a cavity of the skin.

Parts: "Paper" skin, "Crease" panel lines, ramps, alternate nozzle petals, "Metal" intake throats,
bleed slots, nozzle interiors, hook and missile seeker heads, "Marking" the missile bands.

Spec deviations (all made after looking at renders and the real F-15C):
  * the intake box is 0.052 x 0.076 (spec 0.070 x 0.093) and its inner wall stands 0.006 off the
    fuselage side (inner_y 0.054, spec 0.045) with a splitter plate in the gap, as on the real jet;
  * nacelle rear radius 0.035 (spec 0.034) so the nacelle tops stay above Z 0.012 under the fins.
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
import common as C  # noqa: E402
from mathutils import Vector  # noqa: E402
from jet import spec  # noqa: E402

N = 12  # segments of the trunk and nacelle rings (corners of the box sit at 45 degrees)

# Intake box (see module docstring for the deviation from spec.INTAKE).
I = dict(spec.INTAKE, inner_y=0.054, outer_y=0.106, top=0.028, bottom=-0.048)
E = spec.ENGINES
YC, RY = (I["inner_y"] + I["outer_y"]) / 2, (I["outer_y"] - I["inner_y"]) / 2
ZC, RZ = (I["top"] + I["bottom"]) / 2, (I["top"] - I["bottom"]) / 2
D0, RAKE = I["start"], I["ramp_rake"]
KW = dict(rake=RAKE, z_lo=I["bottom"], z_hi=I["top"])
EY, ER = E["y"], E["radius"]
E_BOX = 0.12
LIP = 0.005
CAV = 0.060            # cavity depth behind the lip plane


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


def tube_solid(b, outer, inner):
    """Closed hollow tube (genus 1) from two matching ring lists: outer wall, inner wall, both end
    annuli. `outer` and `inner` are lists of rings of equal point count."""
    O = [mk(b, p) for p in outer]
    Ii = [mk(b, p) for p in inner]
    n = len(O[0])
    for a, c in zip(O, O[1:]):
        strip(b, a, c)
    for a, c in zip(Ii, Ii[1:]):
        strip(b, a, c)
    for k in range(n):
        j = (k + 1) % n
        for ro, ri in ((O[0], Ii[0]), (O[-1], Ii[-1])):
            b.bm.faces.new([ro[k], ro[j], ri[j], ri[k]])


def scaled(pts, f):
    """Scale a ring about its own centroid in Y/Z (for proud seam bands)."""
    cy = sum(p[1] for p in pts) / len(pts)
    cz = sum(p[2] for p in pts) / len(pts)
    return [(p[0], cy + (p[1] - cy) * f, cz + (p[2] - cz) * f) for p in pts]


# --- Skin sections (the loft the whole trunk and nacelle is built from) ---------------------------
# Trunk keeps its outer wall at |Y| >= 0.09 along the wing root (d to 0.86), then narrows into the
# round nacelle (top-view taper of the real jet); the nacelle tops stay above Z 0.012 at |Y| 0.07.
SECTIONS = [
    (D0, ring_pts(D0, YC, ZC, RY, RZ, E_BOX, **KW)),
    (0.66, ring_pts(0.66, 0.070, -0.006, 0.027, 0.036, 0.3)),
    (0.86, ring_pts(0.86, 0.0645, -0.002, 0.026, 0.035, 0.6)),
    (0.96, ring_pts(0.96, EY, 0.0, ER + 0.002, ER + 0.002, 1.0)),
    (1.05, ring_pts(1.05, EY, 0.0, ER + 0.001, ER + 0.001, 1.0)),
]


def ring_at(d):
    """The skin ring at station d, interpolated vertex by vertex exactly as the loft is."""
    for (da, ra), (db, rb) in zip(SECTIONS, SECTIONS[1:]):
        if da <= d <= db:
            t = (d - da) / (db - da)
            return [tuple(a[i] + (b[i] - a[i]) * t for i in range(3)) for a, b in zip(ra, rb)]
    raise ValueError(d)


def surf_z(d, y, top=True):
    """Z of the skin surface at station d and lateral position y (upper or lower side)."""
    pts = ring_at(d)
    best = None
    for a, b in zip(pts, pts[1:] + pts[:1]):
        lo, hi = min(a[1], b[1]), max(a[1], b[1])
        if lo - 1e-9 <= y <= hi + 1e-9 and hi - lo > 1e-9:
            z = a[2] + (b[2] - a[2]) * (y - a[1]) / (b[1] - a[1])
            if best is None or (z > best if top else z < best):
                best = z
    if best is None:
        raise ValueError((d, y))
    return best


def on_skin(b, d0, d1, y0, y1, lift=0.0007, t=0.0016, top=True):
    """Thin flat plate lying on the trunk/nacelle skin (panel lines, hatches, slots)."""
    sgn = 1 if top else -1
    pts = [(spec.x(d0), y0, surf_z(d0, y0, top) + sgn * lift),
           (spec.x(d1), y0, surf_z(d1, y0, top) + sgn * lift),
           (spec.x(d1), y1, surf_z(d1, y1, top) + sgn * lift),
           (spec.x(d0), y1, surf_z(d0, y1, top) + sgn * lift)]
    b.slab(pts, t, direction=(0, 0, sgn))


def wedge(b, y0, y1, F, R, B):
    """Closed triangular prism between y0 and y1; F, R, B are (x, z) corners."""
    vs = [(p[0], y, p[1]) for y in (y0, y1) for p in (F, R, B)]
    faces = [[0, 1, 2], [3, 5, 4], [0, 3, 4, 1], [1, 4, 5, 2], [2, 5, 3, 0]]
    b.poly(vs, faces)


# --- Intake, trunk, nacelle ---------------------------------------------------------------------
def build_skin(paper, metal, crease):
    A = SECTIONS[0][1]
    A_in = ring_pts(D0, YC, ZC, RY - LIP, RZ - LIP, E_BOX, **KW)
    A_back = ring_pts(D0 + CAV, YC, ZC, RY - LIP - 0.002, RZ - LIP - 0.002, E_BOX, **KW)
    rA, rIn, rBack = mk(paper, A), mk(paper, A_in), mk(paper, A_back)
    rb = [mk(paper, p) for _, p in SECTIONS[1:]]
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

    # --- dark throat: a hollow liner along the cavity walls plus a back plate -----------------
    sh = 0.0004
    out0 = ring_pts(D0 + 0.003, YC, ZC, RY - LIP - sh, RZ - LIP - sh, E_BOX, **KW)
    out1 = ring_pts(D0 + CAV - 0.002, YC, ZC, RY - LIP - 0.002 - sh, RZ - LIP - 0.002 - sh,
                    E_BOX, **KW)
    ins0 = ring_pts(D0 + 0.003, YC, ZC, RY - LIP - 0.004, RZ - LIP - 0.004, E_BOX, **KW)
    ins1 = ring_pts(D0 + CAV - 0.002, YC, ZC, RY - LIP - 0.006, RZ - LIP - 0.006, E_BOX, **KW)
    tube_solid(metal, [out0, out1], [ins0, ins1])
    face_d = D0 + 0.036
    plate_in = [ring_pts(face_d, YC, ZC, RY - LIP - 0.0035, RZ - LIP - 0.0035, E_BOX, **KW),
                ring_pts(D0 + CAV - 0.003, YC, ZC, RY - LIP - 0.0055, RZ - LIP - 0.0055,
                         E_BOX, **KW)]
    solid_loft(metal, plate_in)

    # --- variable ramp: a sloped Crease panel under the top lip, with two bleed slots ---------
    zt = ZC + (RZ - LIP - 0.004) * 0.985
    zlo, zhi = I["bottom"], I["top"]

    def xl(z):                        # X of the lip plane at height z
        return spec.x(D0) + RAKE * max(0.0, min(1.0, (z - zlo) / (zhi - zlo)))

    def xf(z):                        # X of the throat back plate at height z
        return xl(z) - (face_d - D0)

    yw = RY - LIP - 0.005
    h = 0.017
    F = (xl(zt) - 0.002, zt + 0.0006)
    R = (xf(zt), zt + 0.0006)
    B = (xf(zt - h), zt - h)
    wedge(crease, YC - yw, YC + yw, F, R, B)
    # bleed slots: two dark bars across the ramp slope
    fv, bv = Vector((F[0], 0, F[1])), Vector((B[0], 0, B[1]))
    slope = bv - fv
    nrm = Vector((slope.z, 0, -slope.x)).normalized()       # perpendicular, in the XZ plane
    if nrm.z < 0:
        nrm = -nrm
    for u0, u1 in ((0.30, 0.40), (0.62, 0.72)):
        p0, p1 = fv + slope * u0 + nrm * 0.0005, fv + slope * u1 + nrm * 0.0005
        pts = [(p0.x, YC - yw * 0.8, p0.z), (p1.x, YC - yw * 0.8, p1.z),
               (p1.x, YC + yw * 0.8, p1.z), (p0.x, YC + yw * 0.8, p0.z)]
        metal.slab(pts, 0.0012, direction=tuple(nrm))

    # --- splitter plate in the gap between the intake and the fuselage side -------------------
    yp = I["inner_y"] - 0.003
    xlead = 0.014
    pts = [(xl(zlo) + xlead, yp, zlo + 0.002), (xl(zhi) + xlead, yp, zhi - 0.002),
           (spec.x(D0 + 0.06), yp, zhi - 0.002), (spec.x(D0 + 0.06), yp, zlo + 0.002)]
    metal.slab(pts, 0.0045, direction=(0, 1, 0))

    # --- bleed-air slots on the top of the intake behind the lip -----------------------------
    for d in (0.398, 0.414):
        on_skin(metal, d, d + 0.0025, YC - RY * 0.72, YC + RY * 0.72)
    on_skin(metal, 0.398, 0.4005, YC - RY * 0.5, YC + RY * 0.5, top=False)   # lower louvre

    # --- panel lines: transverse seams as thin closed bands, longitudinal lines on the skin ---
    for d, w, f in ((0.47, 0.007, 1.025), (0.97, 0.012, 1.035)):
        solid_loft(crease, [scaled(ring_at(d), f), scaled(ring_at(d + w), f)])
    for y0 in (0.052, 0.078):
        on_skin(crease, 0.50, 0.90, y0, y0 + 0.0012)
    # engine-bay access panels and chaff/flare dispenser panels on the upper trunk
    for d0, d1 in ((0.56, 0.62), (0.74, 0.80)):
        on_skin(crease, d0, d1, 0.056, 0.074, lift=0.0006, t=0.0014)
    for dd in (0.808, 0.832):                                    # dispenser slots, dark
        on_skin(metal, dd, dd + 0.012, 0.053, 0.077, lift=0.0010, t=0.0014)
    on_skin(crease, 0.80, 0.86, 0.049, 0.081, lift=0.0006, t=0.0014)


# --- Nozzle -------------------------------------------------------------------------------------
PETALS = 12


def build_nozzle(paper, crease, metal):
    x0, x1 = spec.x(E["nozzle_start"]), spec.x(E["nozzle_end"])
    n = PETALS
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
                vs.append(tgt.bm.verts.new((xx, EY + r * math.cos(th), r * math.sin(th))))
        of0, ob0, if0, ib0, of1, ob1, if1, ib1 = vs
        for f in ([of0, of1, ob1, ob0], [if0, ib0, ib1, if1], [of0, if0, if1, of1],
                  [ob0, ob1, ib1, ib0], [of0, ob0, ib0, if0], [of1, if1, ib1, ob1]):
            tgt.bm.faces.new(f)
        # outer "turkey feather": a thin overlapping plate across the seam to the next petal
        thm = th1
        half = math.pi / n * 0.8
        feather = tgt if not odd else paper
        pts = [(x0 + 0.004, EY + 0.0356 * math.cos(thm - half), 0.0356 * math.sin(thm - half)),
               (x1 - 0.001, EY + 0.0316 * math.cos(thm), 0.0316 * math.sin(thm)),
               (x0 + 0.004, EY + 0.0356 * math.cos(thm + half), 0.0356 * math.sin(thm + half))]
        rad = (0.0, math.cos(thm), math.sin(thm))
        feather.slab(pts, 0.0012, direction=rad)
    # dark interior: a recessed plug with a flame-holder ring and hub standing in front of it
    xf = spec.x(E["nozzle_end"] - 0.020)
    solid_loft(metal, [ring_pts_x(EY, xf, 0.0245, 8),
                       ring_pts_x(EY, spec.x(E["nozzle_start"] - 0.02), 0.0245, 8)])
    # (aft is -X, so these stand out from the plug face toward the exit)
    ring_x = xf - 0.0045
    tube_solid(crease, [ring_pts_x(EY, ring_x, 0.0215, 8), ring_pts_x(EY, ring_x + 0.005, 0.0215, 8)],
               [ring_pts_x(EY, ring_x, 0.0165, 8), ring_pts_x(EY, ring_x + 0.005, 0.0165, 8)])
    crease.loft_x([(xf - 0.010, EY, 0, 0, 0), (xf - 0.004, EY, 0, 0.0070, 0.0070),
                   (xf + 0.0005, EY, 0, 0.0070, 0.0070)], segments=6)


def ring_pts_x(cy, xx, r, n=12):
    return [(xx, cy + r * math.cos(2 * math.pi * k / n), r * math.sin(2 * math.pi * k / n))
            for k in range(n)]


# --- Stores -------------------------------------------------------------------------------------
def fins(crease, xb, cy, cz, chord, root, tip_r, sweep, offset_deg=45):
    for k in range(4):
        phi = math.radians(offset_deg + 90 * k)
        u = (0.0, math.cos(phi), math.sin(phi))
        w = (0.0, -math.sin(phi), math.cos(phi))
        pts = [(xb + chord, cy + u[1] * root, cz + u[2] * root),
               (xb, cy + u[1] * root, cz + u[2] * root),
               (xb + sweep, cy + u[1] * tip_r, cz + u[2] * tip_r)]
        crease.slab(pts, 0.0012, direction=w)


def missile(paper, crease, metal, mark, x_tail, length, cy, cz, r=0.0045, mid_fins=False,
            canards=False):
    seg = 6
    L = length
    paper.loft_x([(x_tail, cy, cz, r * 0.9, r * 0.9),
                  (x_tail + 0.72 * L, cy, cz, r, r)], segments=seg)
    metal.loft_x([(x_tail + 0.72 * L, cy, cz, r * 0.98, r * 0.98),
                  (x_tail + 0.92 * L, cy, cz, r * 0.55, r * 0.55),
                  (x_tail + L, cy, cz, 0, 0)], segments=seg)
    mark.loft_x([(x_tail + 0.40 * L, cy, cz, r * 1.12, r * 1.12),
                 (x_tail + 0.46 * L, cy, cz, r * 1.12, r * 1.12)], segments=seg)
    fins(crease, x_tail, cy, cz, 0.22 * L, r * 0.8, r * 3.2, 0.0)
    if mid_fins:
        fins(crease, x_tail + 0.50 * L, cy, cz, 0.14 * L, r * 0.8, r * 2.6, 0.012 * L)
    if canards:
        fins(crease, x_tail + 0.76 * L, cy, cz, 0.08 * L, r * 0.8, r * 2.2, 0.03 * L)


def build_stores(paper, crease, metal, mark):
    W = spec.WING
    # four fuselage missiles (two per side, in tandem), half sunk into the lower intake corners
    cy, cz = 0.074, I["bottom"] + 0.0005
    for d_nose, d_tail in ((0.345, 0.430), (0.445, 0.530)):
        missile(paper, crease, metal, mark, spec.x(d_tail), d_tail - d_nose, cy, cz,
                mid_fins=True)
    # a dark recess pocket plate under each, so the missile reads as set into the intake
    pts = [(spec.x(0.340), cy - 0.0055, cz + 0.0035), (spec.x(0.536), cy - 0.0055, cz + 0.0035),
           (spec.x(0.536), cy + 0.0055, cz + 0.0035), (spec.x(0.340), cy + 0.0055, cz + 0.0035)]
    metal.slab(pts, 0.0008, direction=(0, 0, 1))
    # one wing pylon, AIM-9 launch rail and slim missile per side
    yp = 0.215
    t = W["root_thickness"] + (W["tip_thickness"] - W["root_thickness"]) * \
        (yp - W["root_y"]) / (W["tip_y"] - W["root_y"])
    zw = -(yp - W["root_y"]) * math.tan(math.radians(-W["anhedral_deg"])) - 0.5 * t
    z_bot = zw - 0.014
    pts = [(spec.x(0.665), yp + 0.0020, zw + 0.002), (spec.x(0.775), yp + 0.0020, zw + 0.002),
           (spec.x(0.745), yp + 0.0020, z_bot), (spec.x(0.690), yp + 0.0020, z_bot)]
    paper.slab(pts, 0.004, direction=(0, 1, 0))
    crease.box_minmax((spec.x(0.752), yp - 0.0020, z_bot - 0.0042),
                      (spec.x(0.668), yp + 0.0020, z_bot + 0.0004))       # launch rail
    r = 0.0042
    zc = z_bot - 0.0042 - r + 0.0006
    missile(paper, crease, metal, mark, spec.x(0.790), 0.150, yp, zc, r=r)


def build_centreline(paper, crease, metal, mark):
    """Parts on the aircraft centreline: fuel tank on its pylon, arresting hook. Not mirrored."""
    # --- centreline tank under the belly between the trunks -----------------------------------
    zt, r = -0.066, 0.0115
    xn, xt = spec.x(0.575), spec.x(0.745)
    L = xn - xt
    paper.loft_x([(xt, 0, zt, r * 0.35, r * 0.35), (xt + 0.14 * L, 0, zt, r * 0.8, r * 0.8),
                  (xt + 0.30 * L, 0, zt, r, r), (xt + 0.74 * L, 0, zt, r, r),
                  (xt + 0.90 * L, 0, zt, r * 0.78, r * 0.78), (xn, 0, zt, 0, 0)], segments=8)
    mark.loft_x([(xt + 0.45 * L, 0, zt, r * 1.06, r * 1.06),
                 (xt + 0.50 * L, 0, zt, r * 1.06, r * 1.06)], segments=8)
    fins(crease, xt - 0.002, 0, zt, 0.022, r * 0.8, r * 2.3, 0.0, offset_deg=0)
    belly = -0.037
    pts = [(spec.x(0.610), 0.0023, belly), (spec.x(0.700), 0.0023, belly),
           (spec.x(0.690), 0.0023, zt + r - 0.001), (spec.x(0.625), 0.0023, zt + r - 0.001)]
    paper.slab(pts, 0.0046, direction=(0, 1, 0))
    # --- arresting hook, stowed under the tail between the nacelles ---------------------------
    pts = [(spec.x(1.000), 0.002, -0.026), (spec.x(1.090), 0.002, -0.0315),
           (spec.x(1.102), 0.002, -0.0395), (spec.x(1.075), 0.002, -0.0360),
           (spec.x(1.000), 0.002, -0.0320)]
    metal.slab(pts, 0.004, direction=(0, 1, 0))
    crease.box_minmax((spec.x(1.030), -0.004, -0.0335), (spec.x(0.980), 0.004, -0.0235))


def build():
    paper, crease, metal, mark = (C.MeshBuilder() for _ in range(4))
    build_skin(paper, metal, crease)
    build_nozzle(paper, crease, metal)
    build_stores(paper, crease, metal, mark)
    parts = {"Paper": paper, "Crease": crease, "Metal": metal, "Marking": mark}
    for b in parts.values():
        b.mirror_y()
    build_centreline(paper, crease, metal, mark)
    total = sum(b.tri_count() for b in parts.values())
    assert total <= spec.BUDGET["engines"], f"engines: {total} triangles over budget"
    return parts


if __name__ == "__main__":
    C.reset_scene()
    for name, b in build().items():
        print(name, b.tri_count())
