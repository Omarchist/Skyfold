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
    (0.400, 0.048, 0.041, -0.038),
    (0.460, 0.046, 0.047, -0.040),     # spine rises behind the canopy
    (0.540, 0.045, 0.048, -0.040),
    (spec.SPINE_END, 0.043, 0.040, -0.040),
    (0.720, 0.040, 0.032, -0.038),     # spine flattens into the deck between the engines
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


def flat_top(d):
    """Half-width of the flat top facet at station d."""
    return hw(d) * TAN


def flat_side(d):
    """Half-height of the flat side facet at station d."""
    return (top(d) - bot(d)) / 2 * TAN


def body():
    rings = []
    for d, w, t, b in BODY + [TAIL_POLE]:
        if w <= 1e-9:
            rings.append((spec.x(d), 0.0, (t + b) / 2, 0.0, 0.0))
        else:
            rings.append((spec.x(d), 0.0, (t + b) / 2, w / COS, (t - b) / 2 / COS))
    return C.MeshBuilder().loft_x(rings, segments=SEG, angle_offset=HALF)


# --- Canopy ----------------------------------------------------------------------------------
CAN = spec.CANOPY
SINK = 0.016                     # the glass bubble's base sits this far inside the body top
# (d, half-width, height of the glass above the body top); poles at both ends.
CANOPY_RINGS = [
    (CAN["start"] + 0.003, 0.0, 0.002),
    (0.186, 0.014, 0.010),
    (0.205, 0.024, 0.026),
    (0.235, 0.030, 0.045),
    (0.270, CAN["width"] / 2, CAN["height"] + 0.006),
    (0.320, 0.029, 0.046),
    (0.365, 0.021, 0.026),
    (0.392, 0.011, 0.012),
    (CAN["end"] + 0.010, 0.0, 0.004),
]
CSEG = 6


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
            faces += [[a[k], a[k + 1], b[k + 1], b[k]] for k in range(CSEG)]
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
    d0, d1 = 0.435, 0.595
    wf, wr = 0.7 * flat_top(d0), 0.8 * flat_top(d1)
    paper = C.MeshBuilder().slab([
        (spec.x(d0), wf, top(d0) + 0.0012), (spec.x(d1), wr, top(d1) + 0.0055),
        (spec.x(d1), -wr, top(d1) + 0.0055), (spec.x(d0), -wf, top(d0) + 0.0012)], 0.003)
    pad = 0.0025
    well = C.MeshBuilder().slab([
        (spec.x(d0 - pad), wf + pad, top(d0 - pad) + 0.0004),
        (spec.x(d1 + pad), wr + pad, top(d1 + pad) + 0.0004),
        (spec.x(d1 + pad), -wr - pad, top(d1 + pad) + 0.0004),
        (spec.x(d0 - pad), -wf - pad, top(d0 - pad) + 0.0004)], 0.002)
    return paper, well


def build():
    paper = body()
    paper.recalc_normals()
    # Belly and chin facets are the shaded colour.
    crease = paper.extract(lambda f: f.normal.z < -0.3)

    # Radome seam: a thin proud ring where the radome joins the forward fuselage.
    seam_rings = [(spec.x(R_LEN - 0.003), 0.0, 0.0, (R_BASE + 0.0016) / COS, 0.031 * 1.0 / COS + 0.0016),
                  (spec.x(R_LEN + 0.003), 0.0, 0.0, (R_BASE + 0.0016) / COS, 0.031 * 1.0 / COS + 0.0016)]
    crease.merge(C.MeshBuilder().loft_x(seam_rings, segments=SEG, angle_offset=HALF))

    glass = canopy()
    # Windscreen frame, the front and rear bows of the canopy.
    for d0, d1 in ((0.196, 0.203), (0.268, 0.274), (0.342, 0.349)):
        crease.merge(frame_band(d0, d1))

    brake, well = speed_brake()
    paper.merge(brake)
    crease.merge(well)

    # Panel lines on the deck and the forward sides.
    crease.merge(top_strip(0.655, 1.0, -0.0006, 0.0006))
    for d in (0.70, 0.80, 0.90):
        f = flat_top(d) * 0.85
        crease.merge(top_strip(d, d + 0.002, -f, f))
    for s in (1, -1):
        zl = flat_side(0.235) * 0.85
        crease.merge(side_strip(s, 0.232, 0.2345, -zl, zl))
        zl = flat_side(0.31) * 0.85
        crease.merge(side_strip(s, 0.309, 0.3115, -zl, zl))

    # National marking: red disc with a cream centre on each side of the forward fuselage.
    marking = C.MeshBuilder()
    for s in (1, -1):
        marking.merge(roundel(s, 0.262, 0.0105, 0.0006))
        paper.merge(roundel(s, 0.262, 0.0055, 0.0011))

    return {"Paper": paper, "Crease": crease, "Canopy": glass, "Marking": marking}


if __name__ == "__main__":
    C.reset_scene()
    for name, b in build().items():
        print(name, b.tri_count())
