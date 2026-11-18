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
from jet import spec  # noqa: E402

X = spec.x


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
        return [at(0.0, 0.0), at(0.14, 0.36), at(0.38, 0.50), at(0.74, 0.30), at(0.77, 0.27),
                at(1.0, 0.06), at(1.0, -0.06), at(0.40, -0.34)]

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
    zt = f["base_z"] + f["height"]
    ycen = f["y"]
    clip = 0.024
    z1 = zt - clip

    def le(z):
        return f["root_le"] + (z - f["base_z"]) * t36

    te_of = lambda z: f["root_te"] - 0.0265 * (z - f["base_z"]) / f["height"] * 1.0  # leans forward

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
    return paper, crease


def build():
    paper, crease = C.MeshBuilder(), C.MeshBuilder()
    for p, c in (_wing(), _stabilator(), _fin()):
        for src, dst in ((p, paper), (c, crease)):
            src.mirror_y()
            dst.merge(src)
    paper.recalc_normals()
    crease.recalc_normals()
    total = paper.tri_count() + crease.tri_count()
    assert total <= spec.BUDGET["wings"], f"wings over budget: {total}"
    return {"Paper": paper, "Crease": crease}


if __name__ == "__main__":
    C.reset_scene()
    parts = build()
    for name, b in parts.items():
        print(f"wings: {name} {b.tri_count()} triangles")
