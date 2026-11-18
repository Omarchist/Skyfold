"""Fighter jet wings and tails: main wing, all-moving stabilators, twin vertical fins.

Each surface is a lofted card with a faceted airfoil (a thin diamond with a flat ridge line),
built as one closed solid, then split into "Paper" (top skin) and "Crease" (undersides, hinge
lines, panel strips). One side is built and mirrored with mirror_y. Follows jet/spec.py with
these local changes (the spec numbers would put the stabilator tips well behind the nozzles and
the fin roots on the nacelle's shoulder):
  - stabilator: tip leading edge at d=1.09 (about 44 deg effective sweep, with the dogtooth step)
    and a forward-swept trailing edge ending at d=1.13, so the tip stays close to the nozzle plane;
  - fin: root is sunk 0.018 below base_z (same sweep lines) so it is embedded in the nacelle.
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
import common as C  # noqa: E402
from mathutils import Matrix  # noqa: E402
from jet import spec  # noqa: E402

X = spec.x

# Wing airfoil: heights as a fraction of local thickness at chord fractions u.
WING_TOP = [(0.0, 0.0), (0.14, 0.36), (0.38, 0.50), (0.74, 0.30), (0.77, 0.27), (1.0, 0.06)]
WING_BOT = [(0.0, 0.0), (0.40, -0.34), (1.0, -0.06)]
FIN_HEIGHT = 0.178   # spec says 0.170; a real F-15C fin tops out about 3.7 m over the centreline


def _interp(table, u):
    for (u0, v0), (u1, v1) in zip(table, table[1:]):
        if u <= u1:
            return v0 + (v1 - v0) * (u - u0) / (u1 - u0)
    return table[-1][1]


def wing_thick(y):
    w = spec.WING
    f = (y - w["root_y"]) / (w["tip_y"] - w["root_y"])
    return w["root_thickness"] + (w["tip_thickness"] - w["root_thickness"]) * f


def wing_le(y):
    w = spec.WING
    return w["root_le"] + (y - w["root_y"]) * math.tan(math.radians(w["le_sweep_deg"]))


def wing_u(d, y):
    return (d - wing_le(y)) / (spec.WING["root_te"] - wing_le(y))


def wing_z(d, y, top=True):
    """Z of the wing skin at station d, span y (inboard of the raked tip)."""
    w = spec.WING
    u = wing_u(d, y)
    anh = math.tan(math.radians(w["anhedral_deg"]))
    f = _interp(WING_TOP if top else WING_BOT, u)
    return w["z"] + (y - w["root_y"]) * anh + f * wing_thick(y)


def pad(zfn, outline, up=True, lift=0.0012, sink=0.0008):
    """A thin closed plate hugging a surface: outline is [(d, y)], zfn(d, y) the skin height.

    Raised `lift` out of the skin and sunk `sink` into it, so nothing is coplanar. `up` False puts
    the plate on the underside.
    """
    sgn = 1 if up else -1
    n = len(outline)
    verts = [(X(d), y, zfn(d, y) + sgn * lift) for d, y in outline] + \
            [(X(d), y, zfn(d, y) - sgn * sink) for d, y in outline]
    faces = [list(range(n)), list(range(2 * n - 1, n - 1, -1))]
    for i in range(n):
        j = (i + 1) % n
        faces.append([i, j, n + j, n + i])
    b = C.MeshBuilder().poly(verts, faces)
    return b.recalc_normals()


def roundel(zfn, cd, cy, r_out, r_in, up=True, n=12):
    """National insignia ring: a closed annulus on the skin."""
    sgn = 1 if up else -1
    lift, sink = 0.0012, 0.0008
    o = [(cd + r_out * math.cos(2 * math.pi * k / n), cy + r_out * math.sin(2 * math.pi * k / n))
         for k in range(n)]
    i_ = [(cd + r_in * math.cos(2 * math.pi * k / n), cy + r_in * math.sin(2 * math.pi * k / n))
          for k in range(n)]
    pts = o + i_
    top = [(X(d), y, zfn(d, y) + sgn * lift) for d, y in pts]
    bot = [(X(d), y, zfn(d, y) - sgn * sink) for d, y in pts]
    verts = top + bot
    N2 = 2 * n
    faces = []
    for k in range(n):
        j = (k + 1) % n
        faces.append([k, j, n + j, n + k])                       # top annulus
        faces.append([N2 + n + k, N2 + n + j, N2 + j, N2 + k])   # bottom annulus
        faces.append([N2 + k, N2 + j, j, k])                      # outer wall
        faces.append([n + k, n + j, N2 + n + j, N2 + n + k])      # inner wall
    return C.MeshBuilder().poly(verts, faces).recalc_normals()


def _volume(b):
    """Signed volume of a closed builder (positive when the faces point outward)."""
    vol = 0.0
    for f in b.bm.faces:
        vs = [v.co for v in f.verts]
        for i in range(1, len(vs) - 1):
            vol += vs[0].dot(vs[i].cross(vs[i + 1])) / 6
    return vol


def _loft(sections, seg_tags, interval_tags=None, caps=("Paper", "Paper")):
    """Closed solid from rings of 3D points (same ring length). Returns (Paper, Crease).

    seg_tags[i] tags the quad strip between ring point i and i+1. interval_tags maps a section
    interval index to {segment: tag} overrides. Points that coincide are welded, so a step in
    the planform (two sections at the same span) collapses its degenerate faces.
    """
    b = C.MeshBuilder()
    cache = {}
    tags = []

    def vert(p):
        k = tuple(round(c, 6) for c in p)
        if k not in cache:
            cache[k] = b.bm.verts.new(p)
        return cache[k]

    def face(pts, tag):
        vs = []
        for p in pts:
            v = vert(p)
            if v not in vs:
                vs.append(v)
        if len(vs) < 3:
            return
        try:
            b.bm.faces.new(vs)
        except ValueError:
            return
        tags.append(tag)

    n = len(sections[0])
    for k in range(len(sections) - 1):
        a, c = sections[k], sections[k + 1]
        for i in range(n):
            j = (i + 1) % n
            tag = (interval_tags or {}).get(k, {}).get(i, seg_tags[i])
            face([a[i], a[j], c[j], c[i]], tag)
    face(list(sections[0]), caps[0])
    face(list(reversed(sections[-1])), caps[1])
    b.recalc_normals()
    assert _volume(b) > 0, "loft solid is inside out"
    crease = b.extract(lambda f: tags[f.index] == "Crease")
    return b, crease


def _wing():
    w = spec.WING
    t45 = math.tan(math.radians(w["le_sweep_deg"]))
    anh = math.tan(math.radians(w["anhedral_deg"]))
    y0 = w["root_y"] - 0.018          # sunk into the intake trunk
    te_d = w["root_te"]

    def le(y):
        return w["root_le"] + (y - w["root_y"]) * t45

    def thick(y):
        f = (y - w["root_y"]) / (w["tip_y"] - w["root_y"])
        return w["root_thickness"] + (w["tip_thickness"] - w["root_thickness"]) * f

    def section(y_le, y_te, y_ref):
        d_le, d_te = le(y_le), te_d
        t = thick(y_ref)

        def at(u, zf):
            y = y_le + u * (y_te - y_le)
            return (X(d_le + u * (d_te - d_le)), y, w["z"] + (y - w["root_y"]) * anh + zf * t)

        # ring: LE, LE panel line, ridge, flap start, hinge line, TE top, TE bottom, bottom ridge
        return [at(u, v) for u, v in WING_TOP] + [at(1.0, -0.06), at(0.40, -0.34)]

    secs = [section(y0, y0, y0)]
    ys = [0.19, 0.265]
    for y in ys:
        secs.append(section(y, y, y))
    ya = 0.300                            # aileron split line (a Crease gap across the rear)
    secs.append(section(ya, ya, ya))
    secs.append(section(ya + 0.007, ya + 0.007, ya + 0.007))
    yr = 0.315                            # start of the raked tip
    secs.append(section(yr, yr, yr))
    secs.append(section(yr, w["tip_y"], w["tip_y"]))
    tags = ["Paper", "Crease", "Paper", "Paper", "Crease", "Paper", "Paper", "Crease"]
    # interval 3 (the aileron gap): the whole rear of the top skin shows as a crease
    over = {3: {3: "Crease", 5: "Crease"}}
    return _loft(secs, tags, over)


def _stabilator():
    s = spec.STABILATOR
    z = s["z"]
    t = s["thickness"]
    d = s["dogtooth"]

    def sec(y, le, te, yle=None):
        yle = y if yle is None else yle
        def at(u, zf):
            return (X(le + u * (te - le)), yle + u * (y - yle), z + zf * t)
        return [at(0, 0.0), at(0.40, 0.50), at(1, 0.08), at(1, -0.08), at(0.40, -0.40)]

    y_root, y_dog, y_tip = s["root_y"] - 0.012, 0.150, s["tip_y"]
    sweep = math.tan(math.radians(s["le_sweep_deg"]))

    def le_in(y):
        return s["root_le"] + (y - s["root_y"]) * sweep

    le_dog = le_in(y_dog)
    le_out = le_dog - d                    # the dogtooth: outer panel stands forward of the notch
    tip_le = 1.09
    te_root, te_tip = s["root_te"], 1.13
    def te(y):
        return te_root + (te_tip - te_root) * (y - s["root_y"]) / (y_tip - s["root_y"])
    yr = 0.222
    le_r = le_out + (tip_le - le_out) * (yr - y_dog) / (y_tip - y_dog) * 0.88
    secs = [
        sec(y_root, le_in(y_root), te(y_root)),
        sec(y_dog, le_dog, te(y_dog)),
        sec(y_dog, le_out, te(y_dog)),
        sec(yr, le_r, te(yr)),
        sec(y_tip, tip_le, te(y_tip), yle=yr + 0.004),   # raked, clipped tip
    ]
    tags = ["Paper", "Paper", "Crease", "Crease", "Crease"]
    return _loft(secs, tags)


def _fin():
    f = spec.FIN
    t = f["thickness"]
    t36 = math.tan(math.radians(f["le_sweep_deg"]))
    z0 = f["base_z"] - 0.018
    height = FIN_HEIGHT
    zt = f["base_z"] + height
    ycen = f["y"]
    clip = 0.024
    z1 = zt - clip

    def le(z):
        return f["root_le"] + (z - f["base_z"]) * t36

    te_of = lambda z: f["root_te"] - 0.0265 * (z - f["base_z"]) / height  # leans forward

    def sec(z, le_d, te_d):
        def at(u, side, zf):
            return (X(le_d + u * (te_d - le_d)), ycen + side * zf * t / 2, z)
        # ring: LE, ridge+, hinge start+, hinge end+, TE+, TE-, hinge end-, hinge start-, ridge-
        return [at(0, 0, 0), at(0.40, 1, 1.0), at(0.70, 1, 0.55), at(0.73, 1, 0.47),
                at(1, 1, 0.12), at(1, -1, 0.12), at(0.73, -1, 0.47), at(0.70, -1, 0.55),
                at(0.40, -1, 1.0)]

    secs = [
        sec(z0, le(z0), te_of(z0)),
        sec(z1, le(z1), te_of(z1)),
        sec(zt, le(z1) + 0.022, te_of(zt)),     # raked, clipped top edge
    ]
    # rudder hinge strip: ring segments 2 and 6 (one per side) are Crease
    tags = ["Paper", "Paper", "Crease", "Paper", "Paper", "Paper", "Crease", "Paper", "Paper"]
    paper, crease = _loft(secs, tags)

    # fin-tip detail: a small wedge fairing on the tip, sticking forward past the leading edge
    # (the F-15's ECM / antenna fairing).
    tz = zt - 0.020
    tip = C.MeshBuilder()
    xa = X(le(z1) + 0.022 - 0.000)
    h = 0.0045
    # side profile polygon (X, Z) extruded across Y
    pts = [(xa + 0.014, tz + 0.012), (xa + 0.002, tz + 0.021), (xa - 0.036, tz + 0.021),
           (xa - 0.036, tz + 0.006), (xa - 0.004, tz + 0.004)]
    n = len(pts)
    vv = [(px, ycen - h, pz) for px, pz in pts] + [(px, ycen + h, pz) for px, pz in pts]
    ff = [list(range(n - 1, -1, -1)), list(range(n, 2 * n))]
    for i in range(n):
        j = (i + 1) % n
        ff.append([i, j, n + j, n + i])
    tip.poly(vv, ff)
    tip.recalc_normals()
    crease.merge(tip)

    def at_z(z, u):
        return le(z) + u * (te_of(z) - le(z))

    def box(x0, x1, y0, y1, z0, z1):
        return C.MeshBuilder().box_minmax((X(x1), y0, z0), (X(x0), y1, z1)).recalc_normals()

    marking = C.MeshBuilder()
    for side in (1, -1):
        def ysp(a, b):
            lo, hi = sorted((ycen + side * a, ycen + side * b))
            return lo, hi
        # rudder actuator bumps on the hinge line, two per face
        for zb in (f["base_z"] + 0.050, f["base_z"] + 0.112):
            y0, y1 = ysp(0.0012, 0.0031)
            crease.merge(box(at_z(zb, 0.64), at_z(zb, 0.76), y0, y1, zb, zb + 0.016))
        # formation light strip (Marking) on the forward fin, and a lower one at the root
        for zc_ in (f["base_z"] + 0.092,):
            y0, y1 = ysp(0.0010, 0.0034)
            marking.merge(box(at_z(zc_, 0.44), at_z(zc_, 0.58), y0, y1, zc_, zc_ + 0.0035))
    # aft tip fairing (antenna / static discharge housing) and a blade antenna on the tip
    fa = C.MeshBuilder()
    te_top = te_of(zt)
    fa.merge(box(te_top - 0.020, te_top + 0.003, ycen - 0.0040, ycen + 0.0040, zt - 0.003, zt + 0.0045))
    crease.merge(fa)
    ant = box(at_z(zt, 0.40) - 0.005, at_z(zt, 0.40) + 0.005, ycen - 0.0008, ycen + 0.0008,
              zt - 0.001, zt + 0.013)
    paper.merge(ant)
    return paper, crease, marking


def _wing_details():
    """Insignia, nav light, fuel dump, pylon plate, formation strip. Returns (crease, marking, metal)
    for the +Y side, plus the unmirrored insignia."""
    w = spec.WING
    crease, marking, metal = C.MeshBuilder(), C.MeshBuilder(), C.MeshBuilder()
    top = lambda d, y: wing_z(d, y, True)
    bot = lambda d, y: wing_z(d, y, False)

    # hardpoint plate under the wing where the pylon (engines.py, y = 0.215) attaches
    yp = 0.215
    u0, u1 = 0.46, 0.74
    d0, d1 = wing_le(yp) + u0 * (w["root_te"] - wing_le(yp)), wing_le(yp) + u1 * (w["root_te"] - wing_le(yp))
    crease.merge(pad(bot, [(d0, yp - 0.011), (d1, yp - 0.011), (d1, yp + 0.011), (d0, yp + 0.011)],
                     up=False))
    # chaff-free panel: a long access-panel strip under the wing root (Crease)
    # nav light on the raked tip's leading corner (Marking)
    ty = 0.3216
    zc = wing_z(0.715, 0.315) - 0.0005
    marking.merge(C.MeshBuilder().box_minmax((X(0.730), 0.3130, zc - 0.0024), (X(0.700), 0.3250, zc + 0.0024))
                  .recalc_normals())
    # fuel dump outlet: a short metal tube trailing from the wing TE near the tip
    zt_ = wing_z(0.86, 0.350, True) - 0.0005
    metal.merge(C.MeshBuilder().rod((X(0.855), 0.350, zt_), (X(0.872), 0.350, zt_), 0.0022, 0.0016,
                                    segments=6))
    # formation light strip on the wing top near the root, behind the intake
    yb = 0.150
    ub0, ub1 = 0.52, 0.66
    lb = wing_le(yb)
    marking.merge(pad(top, [(lb + ub0 * (w["root_te"] - lb), yb - 0.0022),
                            (lb + ub1 * (w["root_te"] - lb), yb - 0.0022),
                            (lb + ub1 * (w["root_te"] - lb), yb + 0.0022),
                            (lb + ub0 * (w["root_te"] - lb), yb + 0.0022)]))
    return crease, marking, metal


def _stab_details():
    s = spec.STABILATOR
    paper, metal, crease = C.MeshBuilder(), C.MeshBuilder(), C.MeshBuilder()
    # pivot fairing: the spindle barrel the all-moving stabilator turns on
    dp = 0.985
    paper.merge(C.MeshBuilder().rod((X(dp), 0.071, s["z"]), (X(dp), 0.098, s["z"]), 0.0072, 0.0066,
                                    segments=8))
    metal.merge(C.MeshBuilder().rod((X(dp), 0.098, s["z"]), (X(dp), 0.1035, s["z"]), 0.0048, 0.0040,
                                    segments=8))
    crease.merge(C.MeshBuilder().rod((X(dp - 0.020), 0.082, s["z"] - 0.0006),
                                     (X(dp + 0.050), 0.082, s["z"] - 0.0006), 0.0028, 0.0028, segments=6))
    return paper, crease, metal


def build():
    P, Cr, Mk, Me = (C.MeshBuilder() for _ in range(4))
    side = {"Paper": P, "Crease": Cr, "Marking": Mk, "Metal": Me}

    def add(parts, mirror=True):
        for name, b in zip(("Paper", "Crease", "Marking", "Metal"), parts):
            if b is None:
                continue
            if mirror:
                b.mirror_y()
            side[name].merge(b)

    wp, wc = _wing()
    wcc, wm, wme = _wing_details()
    add((wp, wc, None, None))
    add((None, wcc, wm, wme))
    sp, sc = _stabilator()
    add((sp, sc, None, None))
    spp, spc, spm = _stab_details()
    add((spp, spc, None, spm))
    fp, fc, fm = _fin()
    add((fp, fc, fm, None))

    # insignia: upper surface of the left (+Y) wing, lower surface of the right (-Y) wing
    top = lambda d, y: wing_z(d, y, True)
    bot = lambda d, y: wing_z(d, y, False)
    Mk.merge(roundel(top, 0.665, 0.215, 0.024, 0.012, up=True))
    under = roundel(bot, 0.745, 0.150, 0.022, 0.011, up=False)
    under.transform(Matrix.Diagonal((1, -1, 1, 1)))
    Mk.merge(under.recalc_normals())

    parts = {"Paper": P, "Crease": Cr, "Marking": Mk, "Metal": Me}
    for b in parts.values():
        b.recalc_normals()
    total = sum(b.tri_count() for b in parts.values())
    assert total <= spec.BUDGET["wings"], f"wings over budget: {total}"
    return parts


if __name__ == "__main__":
    C.reset_scene()
    parts = build()
    for name, b in parts.items():
        print(f"wings: {name} {b.tri_count()} triangles")
