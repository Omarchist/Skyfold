"""Shared helpers for the Skyfold model scripts (Blender 5.2, run headless).

Authoring convention (Blender, Z-up):
    Blender +X  = game +X  (direction of flight)
    Blender +Z  = game +Y  (up)
    Blender -Y  = game +Z  (toward the side camera; Blender's "Front" view looks
                            from here, so the front view is the game camera view)

`export_usdz` bakes the Z-up -> Y-up rotation into every object's mesh data and
location, exports with Blender's USD exporter (no orientation conversion, so
the /root prim stays an identity Xform), stamps upAxis = "Y" and
metersPerUnit = 1 on the stage with pxr, and packages the result as .usdz.
In the USD file each part's local axes are therefore the game axes.
"""

import math
import os
import random
import shutil
import sys
import tempfile
import zlib

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector
from mathutils.geometry import tessellate_polygon

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
MODELS_DIR = os.path.join(PROJECT_ROOT, "Skyfold", "Resources", "Models")

ROUGHNESS = 0.9          # matte paper
CARD = 0.02              # default card thickness in meters
TRI_BUDGET = 400
BUILDING_TRI_BUDGET = 160

# Print palette (ART_DIRECTION.md). Default part colors come from here; the
# game replaces most of them at runtime.
INK = {
    "cream": "#F4ECDD", "warm_white": "#FBF6EC", "crease": "#E4D8C3",
    "ochre": "#C48A1E", "sand": "#D6A473", "red": "#D6402B", "blue": "#2C4F9E",
    "ink": "#2A211B", "storm": "#5B5F6B", "amber": "#E5A03A",
    "wall": "#E5D5BD", "roof": "#B89F88", "string": "#76655A", "slate": "#3A3F4B",
}

# Blender Z-up -> USD Y-up: (x, y, z) -> (x, z, -y), a -90 degree turn about X.
Z_UP_TO_Y_UP = Matrix.Rotation(math.radians(-90.0), 4, "X")

# Blender USD exporter settings (bpy.ops.wm.usd_export, Blender 5.2).
# Orientation is NOT converted by the exporter: convert_orientation=True would
# put a rotateX(-90) on /root and leave every part in Z-up local axes, which
# breaks "rotate the door about Y" on the RealityKit side. We bake it instead.
USD_EXPORT_SETTINGS = dict(
    selected_objects_only=False,
    export_animation=False,
    export_hair=False,
    export_uvmaps=False,
    export_mesh_colors=False,
    export_normals=True,
    export_materials=True,
    export_subdivision="IGNORE",
    export_armatures=False,
    export_shapekeys=False,
    use_instancing=False,
    evaluation_mode="RENDER",
    generate_preview_surface=True,
    generate_materialx_network=False,
    convert_orientation=False,
    export_textures_mode="KEEP",
    relative_paths=True,
    xform_op_mode="TRS",
    root_prim_path="/root",
    export_custom_properties=False,
    author_blender_name=False,
    convert_world_material=False,
    allow_unicode=False,
    export_meshes=True,
    export_lights=False,
    export_cameras=False,
    export_curves=False,
    export_points=False,
    export_volumes=False,
    triangulate_meshes=True,
    quad_method="BEAUTY",
    ngon_method="BEAUTY",
    merge_parent_xform=True,
    convert_scene_units="METERS",
    meters_per_unit=1.0,
)


# --------------------------------------------------------------------------
# Scene / arguments
# --------------------------------------------------------------------------

def script_args():
    """Arguments after `--` on the Blender command line."""
    return sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def output_dir():
    """`--out DIR` overrides the default Skyfold/Resources/Models."""
    args = script_args()
    if "--out" in args:
        return os.path.abspath(args[args.index("--out") + 1])
    return MODELS_DIR


def reset_scene():
    """Empty scene: no default cube, camera or light."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.objects,
                 bpy.data.cameras, bpy.data.lights):
        for block in list(coll):
            coll.remove(block)


# --------------------------------------------------------------------------
# Materials
# --------------------------------------------------------------------------

def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_to_srgb(hex_color):
    h = hex_color.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def hex_to_linear(hex_color):
    return tuple(srgb_to_linear(c) for c in hex_to_srgb(hex_color))


def flat_material(name, hex_color, roughness=ROUGHNESS):
    """Principled BSDF with a flat base color; no textures."""
    mat = bpy.data.materials.new(name)
    bsdf = next(n for n in mat.node_tree.nodes
                if n.bl_idname == "ShaderNodeBsdfPrincipled")
    rgb = hex_to_linear(hex_color)
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = 0.0
    # Viewport/Workbench colors match the shader.
    mat.diffuse_color = (*rgb, 1.0)
    mat.roughness = roughness
    mat.metallic = 0.0
    mat.use_backface_culling = True
    return mat


# --------------------------------------------------------------------------
# Geometry
# --------------------------------------------------------------------------

def _mat(center=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    """Translation @ Rotation @ Scale.

    rot: XYZ euler in degrees, or a mathutils Matrix/Quaternion.
    """
    if isinstance(rot, Matrix):
        q = rot.to_quaternion()
    elif hasattr(rot, "to_matrix") and not isinstance(rot, Euler):
        q = rot  # Quaternion
    else:
        q = Euler([math.radians(a) for a in rot], "XYZ").to_quaternion()
    return Matrix.LocRotScale(Vector(center), q, Vector(scale))


def rot_chain(*steps):
    """Rotation matrix from steps applied in order, e.g. rot_chain(("Z", 45), ("Y", -90))."""
    m = Matrix.Identity(3)
    for axis, deg in steps:
        m = Matrix.Rotation(math.radians(deg), 3, axis) @ m
    return m


# --------------------------------------------------------------------------
# Paper-craft helpers
# --------------------------------------------------------------------------

def rng(name):
    """Seeded random source, the same on every run (hash() is not)."""
    return random.Random(zlib.crc32(name.encode("utf-8")))


def scalloped(cusps):
    """Closed, hand-cut outline: circular scallops between cusps.

    cusps: [(x, z, bulge) or (x, z, bulge, steps)], counter-clockwise.
    The cut from one cusp to the next bows outward by bulge * chord length
    (0 = straight snip, negative = a notch). Each scallop is only a few
    straight segments, like scissor cuts. Returns [(x, z), ...].
    """
    pts = []
    n = len(cusps)
    for i in range(n):
        x0, z0, bulge = cusps[i][:3]
        x1, z1 = cusps[(i + 1) % n][:2]
        pts.append((x0, z0))
        if abs(bulge) < 1e-6:
            continue
        theta = 4.0 * math.atan(2.0 * abs(bulge))  # central angle of the arc
        steps = cusps[i][3] if len(cusps[i]) > 3 else max(2, round(math.degrees(theta) / 42.0))
        dx, dz = x1 - x0, z1 - z0
        chord = math.hypot(dx, dz)
        sag = abs(bulge) * chord
        radius = (chord * chord / 4.0 + sag * sag) / (2.0 * sag)
        sgn = 1.0 if bulge > 0 else -1.0
        nx, nz = dz / chord * sgn, -dx / chord * sgn
        cx = (x0 + x1) / 2.0 - nx * (radius - sag)
        cz = (z0 + z1) / 2.0 - nz * (radius - sag)
        a0 = math.atan2(z0 - cz, x0 - cx)
        for k in range(1, steps):
            a = a0 + sgn * theta * k / steps
            pts.append((cx + radius * math.cos(a), cz + radius * math.sin(a)))
    return pts


def face_point(face, s, t):
    """Point on a wall face. face = (bl, br, tr, tl) seen from outside; s, t in 0..1."""
    bl, br, tr, tl = (Vector(c) for c in face)
    return bl.lerp(br, s).lerp(tl.lerp(tr, s), t)


def face_normal(face):
    bl, br, tr, tl = (Vector(c) for c in face)
    return (br - bl).cross(tl - bl).normalized()


def face_size(face):
    """(width, height) of a wall face in meters, measured through its middle."""
    return ((face_point(face, 1, 0.5) - face_point(face, 0, 0.5)).length,
            (face_point(face, 0.5, 1) - face_point(face, 0.5, 0)).length)


def window_grid(face, cols, rows, s0=0.14, s1=0.86, t0=0.08, t1=0.92, gap_s=0.55, gap_t=0.5,
                rnd=None, wobble=0.0, peak=0.0, skip=()):
    """Hand-cut window openings for `MeshBuilder.punched`: a cols x rows grid.

    The grid fills s0..s1 across and t0..t1 up the face (face coordinates,
    0..1). gap_s / gap_t: the card left between openings, as a fraction of
    one opening. wobble: seeded jitter in meters on every corner, so no two
    openings match. peak > 0 gives each opening a pointed top (a fraction of
    its height). skip: (col, row) cells left uncut. Returns outlines in face
    coordinates, counter-clockwise seen from outside.
    """
    fw, fh = face_size(face)
    w = (s1 - s0) / (cols + (cols - 1) * gap_s)
    h = (t1 - t0) / (rows + (rows - 1) * gap_t)

    def j(scale):
        return rnd.uniform(-wobble, wobble) / scale if rnd and wobble else 0.0

    holes = []
    for r in range(rows):
        for c in range(cols):
            if (c, r) in skip:
                continue
            a = s0 + c * w * (1 + gap_s)
            b = t0 + r * h * (1 + gap_t)
            body = h * (1 - peak) if peak else h
            ring = [(a + j(fw), b + j(fh)), (a + w + j(fw), b + j(fh)),
                    (a + w + j(fw), b + body + j(fh))]
            if peak:
                ring.append((a + w / 2 + j(fw), b + h + j(fh)))
            ring.append((a + j(fw), b + body + j(fh)))
            holes.append(ring)
    return holes


def solid(build):
    """A closed piece built on its own so its normals can be made consistent.

    build(builder) adds the geometry; the returned builder is ready for
    `MeshBuilder.merge` into a part that is assembled with recalc=False.
    """
    b = MeshBuilder()
    build(b)
    return b.recalc_normals()


class MeshBuilder:
    """Accumulates low-poly primitives into one bmesh (one part)."""

    def __init__(self):
        self.bm = bmesh.new()

    # Primitives ----------------------------------------------------------
    def box(self, size, center=(0, 0, 0), rot=(0, 0, 0)):
        bmesh.ops.create_cube(self.bm, size=1.0, matrix=_mat(center, rot, size))
        return self

    def box_minmax(self, lo, hi):
        lo, hi = Vector(lo), Vector(hi)
        return self.box(tuple(hi - lo), center=tuple((lo + hi) / 2))

    def cone(self, r1, r2, depth, center=(0, 0, 0), segments=8, rot=(0, 0, 0),
             scale=(1, 1, 1), cap=True):
        """Cone/cylinder along local Z, centered on its depth. r1 = bottom."""
        bmesh.ops.create_cone(self.bm, cap_ends=cap, cap_tris=False,
                              segments=segments, radius1=r1, radius2=r2,
                              depth=depth, matrix=_mat(center, rot, scale))
        return self

    def cylinder(self, r, depth, **kw):
        return self.cone(r, r, depth, **kw)

    def rod(self, p0, p1, r0, r1=None, segments=4, cap=True):
        """Cone/cylinder running from point p0 to point p1."""
        p0, p1 = Vector(p0), Vector(p1)
        axis = p1 - p0
        q = axis.normalized().to_track_quat("Z", "Y")
        return self.cone(r0, r0 if r1 is None else r1, axis.length, center=tuple((p0 + p1) / 2),
                         segments=segments, rot=q, cap=cap)

    def poly(self, verts, faces, matrix=None):
        """Raw vertices + faces (index lists)."""
        m = matrix or Matrix.Identity(4)
        vs = [self.bm.verts.new(m @ Vector(v)) for v in verts]
        for f in faces:
            self.bm.faces.new([vs[i] for i in f])
        return self

    def prism(self, outline, z0, z1, matrix=None):
        """Extrude a closed 2D outline (counter-clockwise, XY) from z0 to z1."""
        n = len(outline)
        verts = [(x, y, z0) for x, y in outline] + [(x, y, z1) for x, y in outline]
        faces = [list(range(n - 1, -1, -1)), list(range(n, 2 * n))]
        for i in range(n):
            j = (i + 1) % n
            faces.append([i, j, n + j, n + i])
        return self.poly(verts, faces, matrix)

    def lathe(self, profile, segments=8, center=(0, 0, 0), angle_offset=0.0):
        """Revolve a (radius, z) profile around Z. Radius 0 points become poles."""
        cx, cy, cz = center
        rings = []
        for r, z in profile:
            if r <= 1e-9:
                rings.append([self.bm.verts.new((cx, cy, cz + z))])
            else:
                ring = []
                for k in range(segments):
                    a = angle_offset + 2 * math.pi * k / segments
                    ring.append(self.bm.verts.new(
                        (cx + r * math.cos(a), cy + r * math.sin(a), cz + z)))
                rings.append(ring)
        for a, b in zip(rings, rings[1:]):
            if len(a) == 1 and len(b) == 1:
                continue
            for k in range(segments):
                k2 = (k + 1) % segments
                if len(a) == 1:
                    self.bm.faces.new([a[0], b[k], b[k2]])
                elif len(b) == 1:
                    self.bm.faces.new([a[k], b[0], a[k2]])
                else:
                    self.bm.faces.new([a[k], a[k2], b[k2], b[k]])
        if len(rings[0]) > 1:
            self.bm.faces.new(list(reversed(rings[0])))
        if len(rings[-1]) > 1:
            self.bm.faces.new(rings[-1])
        return self

    def slab(self, points, thickness, faces=None, direction=(0, 0, 1)):
        """Thin solid from a closed outline of 3D points (in order).

        The outline is the top surface; it is copied `thickness` along
        -direction for the bottom. `faces` (index lists into points) splits
        the top into facets; default is one n-gon. Normals: recalc afterwards.
        """
        n = len(points)
        d = Vector(direction).normalized() * thickness
        verts = [Vector(p) for p in points] + [Vector(p) - d for p in points]
        top = faces or [list(range(n))]
        all_faces = [list(f) for f in top] + [[i + n for i in reversed(f)] for f in top]
        for i in range(n):
            j = (i + 1) % n
            all_faces.append([i, j, j + n, i + n])
        return self.poly(verts, all_faces)

    def loft_x(self, rings, segments=6, angle_offset=0.0):
        """Loft elliptical rings along X. ring = (x, cy, cz, ry, rz); r=0 -> pole."""
        loops = []
        for x, cy, cz, ry, rz in rings:
            if ry <= 1e-9 and rz <= 1e-9:
                loops.append([self.bm.verts.new((x, cy, cz))])
                continue
            loop = []
            for k in range(segments):
                a = angle_offset + 2 * math.pi * k / segments
                loop.append(self.bm.verts.new((x, cy + ry * math.cos(a), cz + rz * math.sin(a))))
            loops.append(loop)
        for a, b in zip(loops, loops[1:]):
            for k in range(segments):
                k2 = (k + 1) % segments
                if len(a) == 1:
                    self.bm.faces.new([a[0], b[k2], b[k]])
                elif len(b) == 1:
                    self.bm.faces.new([a[k], a[k2], b[0]])
                else:
                    self.bm.faces.new([a[k], a[k2], b[k2], b[k]])
        if len(loops[0]) > 1:
            self.bm.faces.new(list(reversed(loops[0])))
        if len(loops[-1]) > 1:
            self.bm.faces.new(loops[-1])
        return self

    # Paper pieces ---------------------------------------------------------
    def card_xz(self, outline, y=0.0, thickness=CARD, lean=0.0, yaw=0.0, pivot=None):
        """A flat piece of card facing the camera (-Y), cut along `outline`.

        outline: [(x, z), ...] counter-clockwise as seen from the camera.
        y: depth of the card's middle. lean: degrees the top tips away from
        the camera; yaw: degrees about the vertical. Both turn about `pivot`
        (default: bottom middle of the outline).
        """
        n = len(outline)
        h = thickness / 2.0
        verts = [(x, y - h, z) for x, z in outline] + [(x, y + h, z) for x, z in outline]
        faces = [list(range(n)), list(range(2 * n - 1, n - 1, -1))]
        for i in range(n):
            j = (i + 1) % n
            faces.append([j, i, i + n, j + n])
        m = None
        if lean or yaw:
            if pivot is None:
                xs = [p[0] for p in outline]
                pivot = ((min(xs) + max(xs)) / 2.0, y, min(p[1] for p in outline))
            pv = Vector(pivot)
            m = (Matrix.Translation(pv)
                 @ Matrix.Rotation(math.radians(yaw), 4, "Z")
                 @ Matrix.Rotation(math.radians(-lean), 4, "X")
                 @ Matrix.Translation(-pv))
        return self.poly(verts, faces, m)

    def block(self, x0, x1, y0, y1, z0, z1, inset=0.0, rnd=None, wobble=0.0,
              lid=True, floor=False, skip=()):
        """A glued card box, slightly out of true. Returns its four wall faces.

        inset: how much each wall leans in at the top (meters). wobble: seeded
        jitter (meters) on the top corners, so edges are not machine-straight.
        Faces are wound outward; build the part with recalc=False if it also
        holds flat sheets. Returned dict: front (-Y, the camera side), back,
        left (-X), right (+X), top; each (bl, br, tr, tl) seen from outside.
        skip: wall names to leave out, so they can be added with `punched`.
        """
        def w(k=1.0):
            return rnd.uniform(-wobble, wobble) * k if rnd and wobble else 0.0

        b = [Vector((x0, y0, z0)), Vector((x1, y0, z0)), Vector((x1, y1, z0)), Vector((x0, y1, z0))]
        t = [Vector((x0 + inset + w(), y0 + inset + w(), z1 + w(0.6))),
             Vector((x1 - inset + w(), y0 + inset + w(), z1 + w(0.6))),
             Vector((x1 - inset + w(), y1 - inset + w(), z1 + w(0.6))),
             Vector((x0 + inset + w(), y1 - inset + w(), z1 + w(0.6)))]
        faces = {
            "front": (b[0], b[1], t[1], t[0]),
            "right": (b[1], b[2], t[2], t[1]),
            "back": (b[2], b[3], t[3], t[2]),
            "left": (b[3], b[0], t[0], t[3]),
            "top": (t[0], t[1], t[2], t[3]),
        }
        walls = {"front": [0, 1, 5, 4], "right": [1, 2, 6, 5],
                 "back": [2, 3, 7, 6], "left": [3, 0, 4, 7]}
        idx = [quad for name, quad in walls.items() if name not in skip]
        if lid:
            idx.append([4, 5, 6, 7])
        if floor:
            idx.append([3, 2, 1, 0])
        self.poly(b + t, idx)
        return faces

    def sheet_on(self, face, s0, s1, t0, t1, lift=0.015, rnd=None, wobble=0.0, peak=0.0):
        """A hand-cut paper rectangle glued on a wall face (a window, a door).

        s0..s1 across and t0..t1 up the face, both 0..1. lift: how far it
        sits off the wall. wobble: seeded corner jitter in meters. peak > 0
        adds a pointed top (a fraction of the height), for arched openings.
        One-sided and wound outward: build the part with recalc=False.
        """
        fw, fh = face_size(face)
        n = face_normal(face) * lift

        def pt(s, t):
            if rnd and wobble:
                s += rnd.uniform(-wobble, wobble) / fw
                t += rnd.uniform(-wobble, wobble) / fh
            return face_point(face, s, t) + n

        ring = [pt(s0, t0), pt(s1, t0), pt(s1, t1)]
        if peak:
            ring.append(pt((s0 + s1) / 2.0, t1 + (t1 - t0) * peak))
        ring.append(pt(s0, t1))
        return self.poly(ring, [list(range(len(ring)))])

    def punched(self, face, holes=(), outline=None):
        """A wall face with openings cut clean through the card.

        face = (bl, br, tr, tl) seen from outside. holes: outlines in face
        coordinates (see `window_grid`). outline: replaces the rectangle, in
        face coordinates, for gables and door surrounds. The result has no
        T-junctions. Wound outward: build the part with recalc=False.
        """
        loops = [list(outline) if outline else [(0, 0), (1, 0), (1, 1), (0, 1)]]
        loops += [list(h) for h in holes]
        flat = [p for loop in loops for p in loop]
        tris = tessellate_polygon([[Vector((s, t, 0.0)) for s, t in loop] for loop in loops])
        n = face_normal(face)
        pts = [face_point(face, s, t) for s, t in flat]
        vs = [self.bm.verts.new(p) for p in pts]
        for a, b, c in tris:
            cross = (pts[b] - pts[a]).cross(pts[c] - pts[a])
            if cross.length < 1e-10:
                continue
            if cross.dot(n) < 0:
                b, c = c, b
            self.bm.faces.new((vs[a], vs[b], vs[c]))
        return self

    def backing(self, face, inset=0.07, margin=0.03):
        """The sheet glued inside a punched wall: what shows through the openings.

        Sits `inset` meters behind the face and stops `margin` meters short of
        its edges, so it stays inside the box. One-sided, wound outward.
        """
        fw, fh = face_size(face)
        ms, mt = margin / fw, margin / fh
        n = face_normal(face) * -inset
        ring = [face_point(face, s, t) + n
                for s, t in ((ms, mt), (1 - ms, mt), (1 - ms, 1 - mt), (ms, 1 - mt))]
        return self.poly(ring, [[0, 1, 2, 3]])

    def card_yz(self, outline, x=0.0, thickness=CARD, lean=0.0, yaw=0.0):
        """A flat piece of card standing across the flight path (facing +-X).

        outline: [(y, z), ...] in Blender coordinates (y < 0 is the camera
        side), counter-clockwise seen from +X. lean: degrees the top tips
        toward +X; yaw: degrees about the vertical. These are the cross
        pieces slotted through cloud layers so they read from any side.
        """
        n = len(outline)
        h = thickness / 2.0
        verts = [(x + h, y, z) for y, z in outline] + [(x - h, y, z) for y, z in outline]
        faces = [list(range(n)), list(range(2 * n - 1, n - 1, -1))]
        for i in range(n):
            j = (i + 1) % n
            faces.append([j, i, i + n, j + n])
        m = None
        if lean or yaw:
            ys = [p[0] for p in outline]
            pv = Vector((x, (min(ys) + max(ys)) / 2.0, min(p[1] for p in outline)))
            m = (Matrix.Translation(pv)
                 @ Matrix.Rotation(math.radians(yaw), 4, "Z")
                 @ Matrix.Rotation(math.radians(lean), 4, "Y")
                 @ Matrix.Translation(-pv))
        return self.poly(verts, faces, m)

    def folded_bolt(self, top, height, y=0.0, thickness=0.014, fold=0.07, flip=False):
        """A lightning bolt cut from card and creased across its jog.

        top: (x, z) of the middle of its top edge. The upper and lower halves
        fold opposite ways in depth (by about `fold` * height), so the two
        facets take the light differently.
        """
        k = height
        sx = -1.0 if flip else 1.0
        # (x, z, depth) in units of height; the crease runs 2 -> 5.
        pts = [(0.10, 0.0, 0.5), (-0.09, -0.44, -0.5), (0.03, -0.42, 0.0),
               (-0.07, -1.0, 1.0), (0.21, -0.32, -0.5), (0.085, -0.34, 0.0),
               (0.25, 0.0, 0.5)]
        front = [(top[0] + sx * (px - 0.175) * k, y - dy * fold * k, top[1] + pz * k)
                 for px, pz, dy in pts]
        upper, lower = [0, 1, 2, 5, 6], [2, 3, 4, 5]
        if flip:
            upper, lower = upper[::-1], lower[::-1]
        return self.slab(front, thickness, faces=[upper, lower], direction=(0, -1, 0))

    # Edits ---------------------------------------------------------------
    def transform(self, matrix):
        bmesh.ops.transform(self.bm, matrix=matrix, verts=self.bm.verts)
        return self

    def mirror_y(self):
        """Add a mirrored copy across the XZ plane (Blender Y -> -Y)."""
        dup = bmesh.ops.duplicate(self.bm, geom=list(self.bm.verts) + list(self.bm.edges)
                                  + list(self.bm.faces))
        verts = [g for g in dup["geom"] if isinstance(g, bmesh.types.BMVert)]
        bmesh.ops.scale(self.bm, vec=(1, -1, 1), verts=verts)
        faces = [g for g in dup["geom"] if isinstance(g, bmesh.types.BMFace)]
        bmesh.ops.reverse_faces(self.bm, faces=faces)
        return self

    def recalc_normals(self):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        return self

    def merge(self, other):
        """Append another builder's geometry (normals kept as they are)."""
        tmp = bpy.data.meshes.new("_merge_tmp")
        other.bm.to_mesh(tmp)
        other.bm.free()
        self.bm.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
        return self

    def extract(self, predicate):
        """Move the faces where predicate(face) is True into a new builder."""
        self.bm.faces.ensure_lookup_table()
        picked = {f.index for f in self.bm.faces if predicate(f)}
        other = MeshBuilder()
        other.bm.free()
        other.bm = self.bm.copy()
        other.bm.faces.ensure_lookup_table()
        bmesh.ops.delete(other.bm, geom=[f for f in other.bm.faces if f.index not in picked],
                         context="FACES")
        bmesh.ops.delete(self.bm, geom=[f for f in self.bm.faces if f.index in picked],
                         context="FACES")
        return other

    def tri_count(self):
        return sum(len(f.verts) - 2 for f in self.bm.faces)

    # Output --------------------------------------------------------------
    def to_object(self, name, material, recalc=True, pivot=None):
        """Create the part object. Object AND mesh-data name are `name`.

        pivot: world-space point to use as the object origin (e.g. a hinge).
        Without a pivot the part's origin ends up at the model origin.
        """
        if recalc:
            self.recalc_normals()
        mesh = bpy.data.meshes.new(name)
        self.bm.to_mesh(mesh)
        self.bm.free()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        mesh.materials.append(material)
        for p in mesh.polygons:
            p.use_smooth = False
        if pivot is not None:
            pv = Vector(pivot)
            mesh.transform(Matrix.Translation(-pv))
            obj.location = pv
            obj["skyfold_pivot"] = 1
        if obj.name != name or mesh.name != name:
            raise RuntimeError(f"name clash for part {name}: {obj.name}/{mesh.name}")
        mesh.update()
        return obj


# --------------------------------------------------------------------------
# Scene-level helpers
# --------------------------------------------------------------------------

def mesh_objects():
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def world_bbox(objs=None):
    objs = objs or mesh_objects()
    bpy.context.view_layer.update()  # matrix_world is stale until updated
    lo = Vector((math.inf,) * 3)
    hi = Vector((-math.inf,) * 3)
    for o in objs:
        mw = o.matrix_world
        for v in o.data.vertices:
            p = mw @ v.co
            lo = Vector(map(min, lo, p))
            hi = Vector(map(max, hi, p))
    return lo, hi


def apply_transforms(objs=None):
    """Bake rotation and scale into mesh data (location is kept as the origin)."""
    for o in objs or mesh_objects():
        if o.parent:
            raise RuntimeError(f"{o.name}: parenting is not supported")
        mb = o.matrix_basis.copy()  # from location/rotation/scale, never stale
        loc = mb.to_translation()
        o.data.transform(Matrix.Translation(-loc) @ mb)
        o.rotation_mode = "XYZ"
        o.rotation_euler = (0.0, 0.0, 0.0)
        o.scale = (1.0, 1.0, 1.0)
        o.location = loc


def bake_location(obj):
    obj.data.transform(Matrix.Translation(obj.location))
    obj.location = (0.0, 0.0, 0.0)


def recenter(mode="center"):
    """Move the whole model so its reference point sits at the world origin.

    mode "center": bounding-box center (flying things).
    mode "bottom": bottom center of the bounding box (ground-standing things).
    Parts with a pivot keep that pivot as their origin; all other parts get
    their origin at the model origin.
    """
    apply_transforms()
    lo, hi = world_bbox()
    ref = (lo + hi) / 2
    if mode == "bottom":
        ref.z = lo.z
    for o in mesh_objects():
        o.location = o.location - ref
        if "skyfold_pivot" not in o:
            bake_location(o)
    return ref


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def set_flat_shading(objs=None):
    for o in objs or mesh_objects():
        for p in o.data.polygons:
            p.use_smooth = False


# --------------------------------------------------------------------------
# Images
# --------------------------------------------------------------------------

def write_png(path, rgb):
    """Write an opaque 8-bit RGB PNG. rgb: numpy uint8 array (H, W, 3), top row first."""
    import struct
    import zlib

    import numpy as np

    rgb = np.ascontiguousarray(rgb, dtype=np.uint8)
    h, w, ch = rgb.shape
    if ch != 3:
        raise ValueError("write_png expects an RGB array")
    raw = np.concatenate([np.zeros((h, 1), np.uint8), rgb.reshape(h, w * 3)], axis=1)

    def chunk(tag, data):
        body = tag + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"sRGB", b"\x00")
    png += chunk(b"IDAT", zlib.compress(raw.tobytes(), 9))
    png += chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(png)


def read_image(path):
    """Load an image file as a float numpy array (H, W, 4), top row first, values 0..1."""
    import numpy as np

    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    buf = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(buf)
    bpy.data.images.remove(img)
    return buf.reshape(h, w, 4)[::-1].copy()


# --------------------------------------------------------------------------
# Export
# --------------------------------------------------------------------------

def _postprocess_usd(path):
    """Stamp Y-up / meters and strip Blender-only metadata."""
    from pxr import Sdf, Usd, UsdGeom

    stage = Usd.Stage.Open(path)
    UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
    UsdGeom.SetStageMetersPerUnit(stage, 1.0)
    layer = stage.GetRootLayer()
    for prim in stage.Traverse():
        spec = layer.GetPrimAtPath(prim.GetPath())
        if spec is None:
            continue
        if spec.HasInfo("apiSchemas"):
            listop = spec.GetInfo("apiSchemas")
            keep = [s for s in listop.prependedItems if s != "ColorSpaceAPI"]
            if not keep:
                spec.ClearInfo("apiSchemas")
            elif keep != list(listop.prependedItems):
                spec.SetInfo("apiSchemas", Sdf.TokenListOp.Create(prependedItems=keep))
        if "colorSpace:name" in spec.properties:
            spec.RemoveProperty(spec.properties["colorSpace:name"])
        if spec.HasInfo("customData"):
            spec.ClearInfo("customData")
    layer.Save()


def export_usdz(name, max_tris=TRI_BUDGET, out_dir=None):
    """Validate the scene, convert to Y-up and write <out_dir>/<name>.usdz."""
    from pxr import Sdf, UsdUtils

    # Nothing but meshes goes into the file.
    for o in list(bpy.context.scene.objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    objs = mesh_objects()
    apply_transforms(objs)
    set_flat_shading(objs)

    total = 0
    for o in objs:
        if o.data.name != o.name:
            raise RuntimeError(f"{o.name}: mesh data is named {o.data.name}")
        mats = [m for m in o.data.materials if m]
        if len(mats) != 1:
            raise RuntimeError(f"{o.name}: expected exactly one material, got {len(mats)}")
        if o.data.shape_keys or o.modifiers or o.animation_data:
            raise RuntimeError(f"{o.name}: modifiers/shape keys/animation not allowed")
        total += tri_count(o)
    if total > max_tris:
        raise RuntimeError(f"{name}: {total} triangles exceeds budget {max_tris}")

    # Bake Z-up -> Y-up into data and locations (rotation stays identity).
    for o in objs:
        o.data.transform(Z_UP_TO_Y_UP)
        o.location = (Z_UP_TO_Y_UP @ o.location.to_4d()).to_3d()
        o.data.update()

    out_dir = out_dir or output_dir()
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, f"{name}.usdz")
    tmp = tempfile.mkdtemp(prefix="skyfold_usd_")
    try:
        usdc = os.path.join(tmp, f"{name}.usdc")
        result = bpy.ops.wm.usd_export(filepath=usdc, **USD_EXPORT_SETTINGS)
        if "FINISHED" not in result:
            raise RuntimeError(f"USD export failed: {result}")
        _postprocess_usd(usdc)
        if os.path.exists(out_path):
            os.remove(out_path)
        if not UsdUtils.CreateNewUsdzPackage(Sdf.AssetPath(usdc), out_path):
            raise RuntimeError("USDZ packaging failed")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    lo, hi = world_bbox(objs)  # now in Y-up game coordinates
    size = hi - lo
    print(f"[skyfold] {name}: {total} tris, size (X,Y,Z) = "
          f"{size.x:.3f} x {size.y:.3f} x {size.z:.3f} m, "
          f"bbox min {tuple(round(c, 3) for c in lo)} max {tuple(round(c, 3) for c in hi)}")
    for o in sorted(objs, key=lambda o: o.name):
        print(f"[skyfold]   part {o.name:10s} {tri_count(o):4d} tris  "
              f"origin {tuple(round(c, 3) for c in o.location)}")
    print(f"[skyfold] wrote {out_path}")
    return out_path
