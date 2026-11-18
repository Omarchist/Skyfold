"""Fuselage of the fighter jet: radome, forward fuselage, canopy, spine, speed brake, upper deck.

Component of `models/jet.py` (see `jet/spec.py` for the shared stations). Exposes
`build() -> {part: MeshBuilder}` with "Paper", "Crease", "Canopy" and "Marking".

The body is one long `loft_x` of faceted rings: a drooped tangent-ogive radome, then a chined
rounded-box section that is round at the radome base and boxy at the cockpit, a raised spine behind
the canopy and a low flat deck between the engines, ending in a short tail stinger. The canopy is a
separate faceted half-bubble that sits high and forward. Everything is a closed shell so normals
come out right.

Spec deviations: spec.FORWARD_SECTION width is 0.080, which would swallow the intake trunks
(inner wall at |Y| 0.045); the cockpit section here is 0.048 half-width instead.
"""
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import common as C  # noqa: E402
from jet import spec  # noqa: E402

SEG = 8                          # facets round the body
HALF = math.pi / SEG
TAN = math.tan(HALF)
COS = math.cos(HALF)

R_LEN, R_BASE, DROOP = spec.RADOME_END, 0.034, 0.004


def _radome_rings():
    """Tangent ogive from the tip to the radome base, nose drooped by DROOP."""
    rho = (R_BASE ** 2 + R_LEN ** 2) / (2 * R_BASE)
    rows = []
    for d in (0.0, 0.012, 0.030, 0.055, 0.090, 0.140):
        hw = 0.0 if d == 0 else math.sqrt(rho ** 2 - (R_LEN - d) ** 2) + R_BASE - rho
        cz = -DROOP * (1 - d / R_LEN) ** 1.3
        hz = 0.91 * hw
        rows.append((d, hw, cz + hz, cz - hz))
    return rows


# (d from nose, half-width, top Z, bottom Z). Station 0.30 matches spec.FORWARD_SECTION top/bottom.
BODY = _radome_rings() + [
    (0.200, 0.034, 0.031, -0.031),
    (0.260, 0.044, 0.037, -0.034),
    (0.300, 0.048, spec.FORWARD_SECTION["top"], spec.FORWARD_SECTION["bottom"]),
    # From d = 0.33 the sides reach out to the intake trunks' inner walls (measured on the
    # engines module: 0.0535 at 0.36, 0.0505 at 0.42, 0.0481 at 0.50, 0.0452 at 0.60) so no
    # daylight shows between the fuselage and the intakes.
    (0.330, 0.0515, 0.0405, -0.037),
    (0.360, 0.0535, 0.041, -0.038),
    (0.420, 0.0515, 0.0445, -0.039),   # spine rises behind the canopy
    (0.460, 0.0500, 0.047, -0.040),
    (0.500, 0.0488, 0.0478, -0.040),
    (0.540, 0.0475, 0.048, -0.040),
    (0.600, 0.0455, 0.0425, -0.040),
    (spec.SPINE_END, 0.0452, 0.040, -0.040),
    (0.720, 0.0415, 0.032, -0.038),    # spine flattens into the deck between the engines
    (0.850, 0.038, 0.030, -0.034),
    (1.000, 0.033, 0.030, -0.030),
    (spec.FUSELAGE_END, 0.026, 0.028, -0.024),
    (1.075, 0.016, 0.022, -0.014),
    (1.092, 0.007, 0.013, -0.001),
]
TAIL_POLE = (1.100, 0.0, 0.007, 0.007)


def _lerp_row(d, col):
    rows = BODY
    if d <= rows[0][0]:
        return rows[0][col]
    for a, b in zip(rows, rows[1:]):
        if a[0] <= d <= b[0]:
            t = (d - a[0]) / (b[0] - a[0])
            return a[col] + (b[col] - a[col]) * t
    return rows[-1][col]


def hw(d):
    return _lerp_row(d, 1)


def top(d):
    return _lerp_row(d, 2)


def bot(d):
    return _lerp_row(d, 3)


# Chamfer fractions: the side facet spans +-CS*half-height, the top/bottom facet +-CS*half-width.
# 0.414 is a regular octagon; the cockpit and mid-body get boxier (0.62) like the real F-15.
CHAMFER = [(0.0, 0.414), (0.20, 0.414), (0.28, 0.52), (0.34, 0.62), (0.62, 0.62),
           (0.80, 0.50), (1.10, 0.50)]


def chamfer(d):
    for a, b in zip(CHAMFER, CHAMFER[1:]):
        if a[0] <= d <= b[0]:
            return a[1] + (b[1] - a[1]) * (d - a[0]) / (b[0] - a[0])
    return CHAMFER[-1][1]


def flat_top(d):
    """Half-width of the flat top facet at station d."""
    return hw(d) * chamfer(d)


def flat_side(d):
    """Half-height of the flat side facet at station d."""
    return (top(d) - bot(d)) / 2 * chamfer(d)


def ring_pts(d, grow=0.0):
    """Eight points of the chamfered-rectangle section at station d (right side first)."""
    w, t, b = hw(d) + grow, top(d) + grow, bot(d) - grow
    c = chamfer(d)
    zc, hz = (t + b) / 2, (t - b) / 2
    x = spec.x(d)
    return [(x, w, zc - c * hz), (x, w, zc + c * hz), (x, c * w, t), (x, -c * w, t),
            (x, -w, zc + c * hz), (x, -w, zc - c * hz), (x, -c * w, b), (x, c * w, b)]


def loft_rings(rings):
    """Close-skinned loft through rings (lists of points, or a single (x, y, z) point as a pole)."""
    m = C.MeshBuilder()
    vs = []
    for r in rings:
        if isinstance(r[0], tuple):
            vs.append([m.bm.verts.new(p) for p in r])
        else:
            vs.append([m.bm.verts.new(r)])
    for a, b in zip(vs, vs[1:]):
        n = max(len(a), len(b))
        for k in range(n):
            j = (k + 1) % n
            if len(a) == 1:
                m.bm.faces.new([a[0], b[j], b[k]])
            elif len(b) == 1:
                m.bm.faces.new([a[k], a[j], b[0]])
            else:
                m.bm.faces.new([a[k], a[j], b[j], b[k]])
    for r in (vs[0], vs[-1]):
        if len(r) > 1:
            m.bm.faces.new(r)
    return m


def body():
    rings = []
    for d, w, t, b in BODY + [TAIL_POLE]:
        rings.append(ring_pts(d) if w > 1e-9 else (spec.x(d), 0.0, (t + b) / 2))
    return loft_rings(rings)


# --- Canopy ----------------------------------------------------------------------------------
CAN = spec.CANOPY
SINK = 0.016                     # the glass bubble's base sits this far inside the body top
# (d, half-width, height of the glass above the body top); poles at both ends.
CANOPY_RINGS = [
    (0.199, 0.0, 0.002),
    (0.212, 0.016, 0.012),
    (0.232, 0.025, 0.030),
    (0.255, 0.030, 0.044),
    (0.285, CAN["width"] / 2, CAN["height"] + 0.006),
    (0.325, 0.029, 0.046),
    (0.360, 0.022, 0.030),
    (0.388, 0.012, 0.014),
    (0.405, 0.0, 0.004),
]
CSEG = 6
WINDOWS = (3, 6)   # ring-pair range whose side facets are left open (cockpit shows through)


def _can_at(d):
    rows = CANOPY_RINGS
    for a, b in zip(rows, rows[1:]):
        if a[0] <= d <= b[0]:
            t = (d - a[0]) / (b[0] - a[0])
            return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t
    return 0.0, 0.0


def _half_ring(d, w, h, scale=1.0):
    base = top(d) - SINK
    pts = []
    for k in range(CSEG + 1):
        a = math.pi * k / CSEG
        pts.append((spec.x(d), w * scale * math.cos(a), base + (h + SINK) * scale * math.sin(a)))
    return pts


def canopy():
    """Faceted glass half-bubble, closed underneath (the base is buried in the body)."""
    verts, faces, rings = [], [], []
    for d, w, h in CANOPY_RINGS:
        if w <= 1e-9:
            verts.append((spec.x(d), 0.0, top(d) + h))
            rings.append([len(verts) - 1])
        else:
            idx = []
            for p in _half_ring(d, w, h):
                verts.append(p)
                idx.append(len(verts) - 1)
            rings.append(idx)
    for a, b in zip(rings, rings[1:]):
        if len(a) == 1:
            faces += [[a[0], b[k + 1], b[k]] for k in range(CSEG)]
            faces.append([a[0], b[0], b[-1]])
        elif len(b) == 1:
            faces += [[a[k], a[k + 1], b[0]] for k in range(CSEG)]
            faces.append([a[0], b[0], a[-1]])
        else:
            ring_i = rings.index(a)
            win = WINDOWS[0] <= ring_i < WINDOWS[1]
            faces += [[a[k], a[k + 1], b[k + 1], b[k]] for k in range(CSEG)
                      if not (win and k in (1, 4))]
            faces.append([a[0], b[0], b[-1], a[-1]])
    return C.MeshBuilder().poly(verts, faces)


def frame_band(d0, d1):
    """A thin half-ring of frame standing a hair proud of the glass."""
    verts, faces = [], []
    for d in (d0, d1):
        w, h = _can_at(d)
        verts += _half_ring(d, w, h, scale=1.07)
    n = CSEG + 1
    faces += [[k, k + 1, n + k + 1, n + k] for k in range(CSEG)]
    faces.append([0, n, n + CSEG, CSEG])
    faces.append(list(range(n - 1, -1, -1)))
    faces.append(list(range(n, 2 * n)))
    return C.MeshBuilder().poly(verts, faces)


# --- Surface details ----------------------------------------------------------------------------
LIFT = 0.0008


def top_strip(d0, d1, y0, y1, lift=LIFT, t=0.002):
    pts = [(spec.x(d0), y0, top(d0) + lift), (spec.x(d1), y0, top(d1) + lift),
           (spec.x(d1), y1, top(d1) + lift), (spec.x(d0), y1, top(d0) + lift)]
    return C.MeshBuilder().slab(pts, t)


def side_strip(s, d0, d1, z0, z1, lift=LIFT, t=0.002):
    pts = [(spec.x(d0), s * (hw(d0) + lift), z0), (spec.x(d1), s * (hw(d1) + lift), z0),
           (spec.x(d1), s * (hw(d1) + lift), z1), (spec.x(d0), s * (hw(d0) + lift), z1)]
    return C.MeshBuilder().slab(pts, t, direction=(0, s, 0))


def roundel(s, d, r, lift):
    """Flat disc on the fuselage side, tilted to follow the taper of the side facet."""
    slope = (hw(d + 0.01) - hw(d - 0.01)) / 0.02
    pts = []
    for k in range(10):
        a = 2 * math.pi * k / 10
        dd = d + r * math.cos(a)
        pts.append((spec.x(dd), s * (hw(d) + slope * (dd - d) + lift), r * math.sin(a)))
    return C.MeshBuilder().slab(pts, 0.002, direction=(0, s, 0))


def speed_brake():
    """The big panel on the spine behind the canopy: hinged at the front, rear edge cracked open."""
    d0, d1 = 0.450, 0.600
    wf, wr = 0.7 * flat_top(d0), 0.8 * flat_top(d1)
    z0, z1 = top(d0) + 0.0012, top(d1) + 0.0055
    paper = C.MeshBuilder().slab([
        (spec.x(d0), wf, z0), (spec.x(d1), wr, z1),
        (spec.x(d1), -wr, z1), (spec.x(d0), -wf, z0)], 0.003)
    pad = 0.0025
    well = C.MeshBuilder().slab([
        (spec.x(d0 - pad), wf + pad, top(d0 - pad) + 0.0004),
        (spec.x(d1 + pad), wr + pad, top(d1 + pad) + 0.0004),
        (spec.x(d1 + pad), -wr - pad, top(d1 + pad) + 0.0004),
        (spec.x(d0 - pad), -wf - pad, top(d0 - pad) + 0.0004)], 0.002)
    # Ribs and the hinge line on the panel, and the two actuator housings at its rear edge.
    ribs = C.MeshBuilder()
    lift = 0.0007
    for f in (-0.5, 0.0, 0.5):
        ya, yb = f * wf, f * wr
        ribs.merge(C.MeshBuilder().slab([
            (spec.x(d0 + 0.012), ya - 0.0005, z0 + (z1 - z0) * 0.08 + lift),
            (spec.x(d1 - 0.004), yb - 0.0005, z0 + (z1 - z0) * 0.97 + lift),
            (spec.x(d1 - 0.004), yb + 0.0005, z0 + (z1 - z0) * 0.97 + lift),
            (spec.x(d0 + 0.012), ya + 0.0005, z0 + (z1 - z0) * 0.08 + lift)], 0.0016))
    ribs.merge(C.MeshBuilder().slab([
        (spec.x(d0 + 0.004), wf, z0 + lift), (spec.x(d0 + 0.0075), wf, z0 + lift),
        (spec.x(d0 + 0.0075), -wf, z0 + lift), (spec.x(d0 + 0.004), -wf, z0 + lift)], 0.0016))
    return paper, well, ribs


# --- Cockpit interior, seen through the open side windows --------------------------------------
def cockpit():
    """Returns (metal, crease, marking, glass_extra, paper) pieces of the cockpit."""
    metal, crease, mark, glass, paper = (C.MeshBuilder() for _ in range(5))

    def box(b, d0, d1, y0, y1, z0, z1):
        b.box_minmax((spec.x(d1), y0, z0), (spec.x(d0), y1, z1))

    t = lambda d: top(d)
    # tub floor and side consoles
    box(metal, 0.226, 0.372, -0.021, 0.021, t(0.3) - 0.004, t(0.3) + 0.0005)
    for s in (1, -1):
        y0, y1 = (0.0145, 0.0205) if s > 0 else (-0.0205, -0.0145)
        box(metal, 0.270, 0.318, y0, y1, t(0.3), t(0.3) + 0.0065)
    # instrument panel and glareshield (coaming) under the windscreen
    box(metal, 0.226, 0.246, -0.0185, 0.0185, t(0.236), t(0.236) + 0.0035)
    glass.slab([(spec.x(0.2465), -0.0185, t(0.236) + 0.0035), (spec.x(0.2465), 0.0185, t(0.236) + 0.0035),
                (spec.x(0.2465), 0.0185, t(0.236) + 0.0105), (spec.x(0.2465), -0.0185, t(0.236) + 0.0105)],
               0.0008, direction=(1, 0, 0))
    box(metal, 0.2465, 0.2515, -0.0185, 0.0185, t(0.236) + 0.0035, t(0.236) + 0.0055)
    # HUD: a frame of two posts and a top bar with a combiner pane of glass
    for y in (-0.0085, 0.0085):
        box(metal, 0.2515, 0.2565, y - 0.0008, y + 0.0008, t(0.25) + 0.0035, t(0.25) + 0.0155)
    box(metal, 0.2515, 0.2565, -0.0093, 0.0093, t(0.25) + 0.0155, t(0.25) + 0.0172)
    glass.slab([(spec.x(0.2555), -0.0078, t(0.25) + 0.0035), (spec.x(0.2555), 0.0078, t(0.25) + 0.0035),
                (spec.x(0.2545), 0.0078, t(0.25) + 0.0155), (spec.x(0.2545), -0.0078, t(0.25) + 0.0155)],
               0.0008, direction=(1, 0, 0))
    # control stick
    metal.rod((spec.x(0.281), 0.0, t(0.28) + 0.0005), (spec.x(0.283), 0.0, t(0.28) + 0.0105),
              0.0011, 0.0007, segments=4)
    # ejection seat: pan, back, headrest, and the pilot's helmet
    zt = t(0.305)
    box(crease, 0.296, 0.316, -0.0072, 0.0072, zt - 0.001, zt + 0.0022)
    box(crease, 0.312, 0.3185, -0.0072, 0.0072, zt, zt + 0.0245)
    box(mark, 0.3105, 0.3205, -0.0058, 0.0058, zt + 0.0245, zt + 0.0345)
    box(metal, 0.3185, 0.3225, -0.0075, 0.0075, zt + 0.003, zt + 0.0185)    # parachute and rails
    paper.ico(0.0058, center=(spec.x(0.3045), 0.0, zt + 0.0262), subdiv=1)
    # centre bulkhead: dark panel between the two windows so nothing shows through both sides
    d0, d1 = 0.252, 0.362
    zb = lambda d: t(d) - 0.003
    zr = lambda d: (t(d) - SINK) + (_can_at(d)[1] + SINK) - 0.0035
    pts = [(spec.x(d0), 0.0, zb(d0)), (spec.x(d1), 0.0, zb(d1)),
           (spec.x(d1), 0.0, zr(d1)), (spec.x(0.285), 0.0, zr(0.285)), (spec.x(d0), 0.0, zr(d0))]
    glass.slab(pts, 0.002, direction=(0, 1, 0))
    return metal, crease, mark, glass, paper


# --- Small parts --------------------------------------------------------------------------------
def blade(d0, length, height, sweep, upward=True, thick=0.0016):
    """Antenna blade standing on the centreline (sweeps back)."""
    if upward:
        z0, sgn = top(d0 + length / 2) - 0.0008, 1
    else:
        z0, sgn = bot(d0 + length / 2) + 0.0008, -1
    pts = [(spec.x(d0), 0.0008, z0), (spec.x(d0 + length), 0.0008, z0),
           (spec.x(d0 + length + sweep), 0.0008, z0 + sgn * height),
           (spec.x(d0 + sweep * 0.8), 0.0008, z0 + sgn * height)]
    return C.MeshBuilder().slab(pts, thick, direction=(0, 1, 0))


def rect_outline(s, d0, d1, z0, z1, w=0.0012, lift=LIFT):
    """Four thin strips forming a panel outline on the side facet."""
    b = C.MeshBuilder()
    b.merge(side_strip(s, d0, d1, z0, z0 + w, lift))
    b.merge(side_strip(s, d0, d1, z1 - w, z1, lift))
    b.merge(side_strip(s, d0, d0 + w, z0, z1, lift))
    b.merge(side_strip(s, d1 - w, d1, z0, z1, lift))
    return b


def top_outline(d0, d1, y0, y1, w=0.0010):
    b = C.MeshBuilder()
    b.merge(top_strip(d0, d1, y0, y0 + w))
    b.merge(top_strip(d0, d1, y1 - w, y1))
    b.merge(top_strip(d0, d0 + w, y0, y1))
    b.merge(top_strip(d1 - w, d1, y0, y1))
    return b


def gun_port():
    """M61 gun fairing and muzzle on the right (-Y) wing root, on the trunk shoulder ahead of
    the wing's leading edge. Returns (paper, crease, metal). The trunk top there is Z 0.0285."""
    zb = 0.0278
    d0, d1, zf, zr = 0.432, 0.482, 0.0325, 0.0352
    yo0, yo1, yi0, yi1 = -0.0975, -0.0805, -0.0955, -0.0825   # base edges, top edges
    ztop = lambda d: zf + (zr - zf) * (d - d0) / (d1 - d0)
    v = [(spec.x(d0), yo0, zb), (spec.x(d0), yo1, zb), (spec.x(d1), yo1, zb), (spec.x(d1), yo0, zb),
         (spec.x(d0), yi0, zf), (spec.x(d0), yi1, zf), (spec.x(d1), yi1, zr), (spec.x(d1), yi0, zr)]
    f = [[3, 2, 1, 0], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]
    paper = C.MeshBuilder().poly(v, f)
    metal = C.MeshBuilder().slab([(spec.x(d0 - 0.0006), -0.0935, 0.0289), (spec.x(d0 - 0.0006), -0.0845, 0.0289),
                                  (spec.x(d0 - 0.0006), -0.0845, 0.0318), (spec.x(d0 - 0.0006), -0.0935, 0.0318)],
                                 0.0020, direction=(1, 0, 0))
    crease = C.MeshBuilder()
    for d in (0.4515, 0.4595, 0.4675):
        crease.merge(C.MeshBuilder().slab([
            (spec.x(d), -0.0945, ztop(d) + 0.0006), (spec.x(d + 0.0022), -0.0945, ztop(d + 0.0022) + 0.0006),
            (spec.x(d + 0.0022), -0.0835, ztop(d + 0.0022) + 0.0006), (spec.x(d), -0.0835, ztop(d) + 0.0006)],
            0.0015))
    return paper, crease, metal


def build():
    paper = body()
    paper.recalc_normals()
    # Belly and chin facets are the shaded colour.
    crease = paper.extract(lambda f: f.normal.z < -0.3)
    metal, marking = C.MeshBuilder(), C.MeshBuilder()

    # Radome seam: a thin proud ring where the radome joins the forward fuselage.
    seam = loft_rings([ring_pts(R_LEN - 0.003, 0.0016), ring_pts(R_LEN + 0.003, 0.0016)])
    crease.merge(seam)

    # Nose pitot (air-data probe) on the radome tip, tipped slightly down with the droop.
    zt = -DROOP
    metal.rod((spec.x(-0.020), 0.0, zt - 0.0004), (spec.x(0.006), 0.0, zt), 0.0004, 0.0013, segments=4)

    glass = canopy()
    # Windscreen arch, canopy bows and rear fairing frame.
    for d0, d1 in ((0.203, 0.209), (0.255, 0.261), (0.318, 0.324), (0.372, 0.378)):
        crease.merge(frame_band(d0, d1))

    # Cockpit seen through the side windows.
    c_metal, c_crease, c_mark, c_glass, c_paper = cockpit()
    metal.merge(c_metal)
    crease.merge(c_crease)
    marking.merge(c_mark)
    glass.merge(c_glass)
    paper.merge(c_paper)

    brake, well, ribs = speed_brake()
    paper.merge(brake)
    crease.merge(well)
    crease.merge(ribs)

    # Refuelling receptacle door on the spine just ahead of the speed brake, with its slot.
    fw = flat_top(0.424) * 0.9
    crease.merge(top_outline(0.4125, 0.4385, -fw, fw))
    metal.merge(top_strip(0.4195, 0.4315, -fw * 0.45, fw * 0.45, lift=0.0006, t=0.0016))

    # Antenna blades: UHF and IFF on the spine, two more under the belly.
    paper.merge(blade(0.628, 0.016, 0.0125, 0.010))
    paper.merge(blade(0.676, 0.012, 0.0085, 0.008))
    crease.merge(blade(0.285, 0.014, 0.0105, 0.009, upward=False))
    crease.merge(blade(0.640, 0.012, 0.0085, 0.008, upward=False))

    g_paper, g_crease, g_metal = gun_port()
    paper.merge(g_paper)
    crease.merge(g_crease)
    metal.merge(g_metal)

    # Deck panel lines: centre seam, cross seams, two engine-bay access panels.
    crease.merge(top_strip(0.655, 1.0, -0.0006, 0.0006))
    for d in (0.70, 0.80, 0.90, 0.975):
        f = flat_top(d) * 0.85
        crease.merge(top_strip(d, d + 0.002, -f, f))
    for d0, d1 in ((0.712, 0.788), (0.912, 0.968)):
        f = flat_top((d0 + d1) / 2) * 0.7
        crease.merge(top_outline(d0, d1, -f, f, 0.0008))

    # Forward side details: avionics bay and access panels, formation lights, tail code, insignia.
    for s in (1, -1):
        zl = flat_side(0.23) * 0.85
        crease.merge(rect_outline(s, 0.208, 0.246, -zl, zl))                      # avionics bay
        for dz in (-0.7, 0.7):
            metal.merge(side_strip(s, 0.2105, 0.2125, dz * zl - 0.0007, dz * zl + 0.0007, 0.0006, 0.0016))
            metal.merge(side_strip(s, 0.2415, 0.2435, dz * zl - 0.0007, dz * zl + 0.0007, 0.0006, 0.0016))
        zl2 = flat_side(0.31) * 0.85
        crease.merge(rect_outline(s, 0.299, 0.327, -zl2, zl2))                    # access panel
        marking.merge(side_strip(s, 0.2775, 0.2955, 0.0035, 0.0062, 0.0006, 0.0016))  # formation light
        for k in range(3):                                                          # tail code
            d = 0.2775 + k * 0.0065
            marking.merge(side_strip(s, d, d + 0.0022, -0.0125, -0.0065, 0.0006, 0.0016))
    # Tail-stinger colour band and a seam in front of it.
    marking.merge(loft_rings([ring_pts(1.0605, 0.0009), ring_pts(1.0675, 0.0009)]))

    # National marking: red disc with a cream centre on each side of the forward fuselage.
    for s in (1, -1):
        marking.merge(roundel(s, 0.262, 0.0105, 0.0006))
        paper.merge(roundel(s, 0.262, 0.0055, 0.0016))

    parts = {"Paper": paper, "Crease": crease, "Canopy": glass, "Marking": marking, "Metal": metal}
    total = sum(b.tri_count() for b in parts.values())
    assert total <= spec.BUDGET["fuselage"], f"fuselage: {total} triangles over budget"
    return parts


if __name__ == "__main__":
    C.reset_scene()
    for name, b in build().items():
        print(name, b.tri_count())
