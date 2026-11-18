"""Verify every Skyfold .usdz against the model contract.

Run it inside Blender, which ships pxr:
    blender --background --factory-startup --python-exit-code 1 \
        --python Tools/Blender/verify_usdz.py -- [models_dir] [--allow-missing]

Prints one table row per model and exits 1 if any rule is broken.
"""
import os
import sys

from pxr import Gf, Usd, UsdGeom, UsdShade

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_DIR = os.path.abspath(os.path.join(HERE, "..", "..", "Skyfold", "Resources", "Models"))

TOL = 0.15  # +-15% on the sizes in the spec

# size = (X, Y, Z) in meters, None = not specified. size_part: check one part's
# bbox instead of the whole model (e.g. the kite's sail without its tail).
SPEC = {
    "plane": dict(size=(0.9, 0.22, 0.75), origin="center", parts=["Paper", "Crease"]),
    "jet": dict(size=(1.15, 0.31, 0.74), origin="center", budget=7000,
                parts=["Paper", "Crease", "Canopy", "Metal", "Marking"]),
    "bird": dict(size=(0.45, None, 0.7), origin="center",
                 parts=["Body", "WingL", "WingR", "Beak"]),
    "balloons": dict(size=(0.9, 1.2, None), origin="center",
                     parts=["BalloonA", "BalloonB", "BalloonC", "String"]),
    "kite": dict(size=None, size_part=("Sail", (0.8, 1.0, None)), origin="center",
                 parts=["Sail", "Spar", "Tail"]),
    "storm_cloud": dict(size=(1.4, 1.0, 1.0), origin="center", parts=["Cloud", "Bolt"]),
    "thunderhead": dict(size=(1.8, 3.1, 1.6), origin="center", parts=["Cloud", "Bolt"]),
    "tower": dict(size=(1.2, 4.1, 1.2), origin="bottom", parts=["Wall", "Window", "Beacon"]),
    "star": dict(size=(0.45, 0.45, 0.18), origin="center", parts=["Star"]),
    "cloud_puff": dict(size=(2.4, 1.2, 1.2), origin="center", parts=["Cloud"]),
    "building_a": dict(size=(2.5, 8.0, 2.5), origin="bottom", budget=160,
                       parts=["Wall", "Window", "Roof"]),
    "building_b": dict(size=(3.5, 4.5, 3.0), origin="bottom", budget=160,
                       parts=["Wall", "Window", "Roof"]),
    "building_c": dict(size=(1.6, 9.0, None), origin="bottom", budget=160,
                       parts=["Wall", "Window", "Roof"]),
    "building_d": dict(size=(5.0, 2.5, 3.0), origin="bottom", budget=160,
                       parts=["Wall", "Window", "Roof"]),
    "landmark_dome": dict(size=(4.0, 6.0, None), origin="bottom",
                          parts=["Wall", "Dome", "Window"]),
    "gate": dict(size=(1.8, 2.6, 0.3), origin="bottom",
                 parts=["Frame", "DoorL", "DoorR", "Sign", "Glow"]),
}
DEFAULT_BUDGET = 400


def mesh_tris(mesh):
    counts = mesh.GetFaceVertexCountsAttr().Get() or []
    return sum(max(0, c - 2) for c in counts)


def world_range(cache, prim):
    r = cache.ComputeWorldBound(prim).ComputeAlignedRange()
    return r.GetMin(), r.GetMax()


def local_points_range(mesh):
    pts = mesh.GetPointsAttr().Get()
    lo = Gf.Vec3d(*[min(p[i] for p in pts) for i in range(3)])
    hi = Gf.Vec3d(*[max(p[i] for p in pts) for i in range(3)])
    return lo, hi


def fmt3(v, nd=2):
    return "(" + ", ".join(f"{c:.{nd}f}" for c in v) + ")"


def check_model(path):
    name = os.path.splitext(os.path.basename(path))[0]
    errors = []
    stage = Usd.Stage.Open(path)
    if stage is None:
        return dict(name=name, errors=["cannot open"]), None

    spec = SPEC.get(name)
    if spec is None:
        errors.append("not in SPEC table (unknown model)")
        spec = dict(size=None, origin="center", parts=[])

    up = UsdGeom.GetStageUpAxis(stage)
    mpu = UsdGeom.GetStageMetersPerUnit(stage)
    if up != "Y":
        errors.append(f"upAxis is {up}, expected Y")
    if abs(mpu - 1.0) > 1e-9:
        errors.append(f"metersPerUnit is {mpu}, expected 1")
    root = stage.GetDefaultPrim()
    if not root:
        errors.append("no defaultPrim")
        root = stage.GetPseudoRoot()

    cache = UsdGeom.BBoxCache(Usd.TimeCode.Default(), [UsdGeom.Tokens.default_])
    meshes = {}
    tris = 0
    for prim in stage.Traverse():
        t = prim.GetTypeName()
        if t in ("Camera",) or prim.IsA(UsdGeom.Camera) or "Light" in t:
            errors.append(f"{prim.GetPath()}: {t} prims are not allowed")
        if t.startswith("Skel"):
            errors.append(f"{prim.GetPath()}: skeleton/animation prims are not allowed")
        for attr in prim.GetAttributes():
            if attr.GetNumTimeSamples() > 0:
                errors.append(f"{attr.GetPath()}: animated (time samples)")
        if prim.IsA(UsdGeom.Xformable):
            xf = UsdGeom.Xformable(prim)
            m = xf.GetLocalTransformation()
            rot_scale = Gf.Matrix3d(m.ExtractRotationMatrix())
            ident = Gf.Matrix3d(1)
            if any(abs(rot_scale[i][j] - ident[i][j]) > 1e-5 for i in range(3) for j in range(3)):
                errors.append(f"{prim.GetPath()}: has rotation/scale (transforms not applied)")
        if prim.IsA(UsdGeom.Mesh):
            mesh = UsdGeom.Mesh(prim)
            meshes[prim.GetName()] = prim
            tris += mesh_tris(mesh)
            if mesh.GetSubdivisionSchemeAttr().Get() != UsdGeom.Tokens.none:
                errors.append(f"{prim.GetName()}: subdivisionScheme is not 'none'")
            if UsdGeom.Subset.GetAllGeomSubsets(mesh):
                errors.append(f"{prim.GetName()}: has GeomSubsets (more than one material)")
            mat, _ = UsdShade.MaterialBindingAPI(prim).ComputeBoundMaterial()
            if not mat:
                errors.append(f"{prim.GetName()}: no material bound")
        if prim.IsA(UsdShade.Shader):
            shader_id = UsdShade.Shader(prim).GetIdAttr().Get() or ""
            for inp, want in (("roughness", 0.9), ("metallic", 0.0)):
                attr = prim.GetAttribute(f"inputs:{inp}")
                if attr and attr.HasAuthoredValue() and not attr.GetConnections() \
                        and abs(float(attr.Get()) - want) > 0.05:
                    errors.append(f"{prim.GetPath()}: {inp} = {attr.Get()}, expected {want} (matte paper)")
            if "Texture" in shader_id or "PrimvarReader" in shader_id:
                errors.append(f"{prim.GetPath()}: textures are not allowed ({shader_id})")

    budget = spec.get("budget", DEFAULT_BUDGET)
    if tris > budget:
        errors.append(f"{tris} triangles > budget {budget}")

    for part in spec["parts"]:
        if part not in meshes:
            errors.append(f"missing part '{part}'")

    lo, hi = world_range(cache, root)
    size = hi - lo
    center = (lo + hi) / 2

    def check_size(actual, expected, label):
        for axis, a, e in zip("XYZ", actual, expected):
            if e is not None and abs(a - e) > TOL * e:
                errors.append(f"{label} size {axis} = {a:.2f} m, expected {e} +-15%")

    if spec.get("size"):
        check_size(size, spec["size"], "model")
    if spec.get("size_part"):
        pname, psize = spec["size_part"]
        if pname in meshes:
            plo, phi = world_range(cache, meshes[pname])
            check_size(phi - plo, psize, pname)

    eps = 0.02
    if spec["origin"] == "center":
        for axis in range(3):
            if abs(center[axis]) > max(eps, 0.04 * size[axis]):
                errors.append(f"origin not at bbox center (center = {fmt3(center)})")
                break
    else:
        if abs(lo[1]) > eps or abs(center[0]) > max(eps, 0.04 * size[0]) \
                or abs(center[2]) > max(eps, 0.04 * size[2]):
            errors.append(f"origin not at bottom center (min Y = {lo[1]:.3f}, "
                          f"center XZ = {center[0]:.3f}, {center[2]:.3f})")

    # Pivots and facing.
    def translate(pname):
        m = UsdGeom.Xformable(meshes[pname]).GetLocalTransformation()
        return m.ExtractTranslation()

    def part_center(pname):
        a, b = world_range(cache, meshes[pname])
        return (a + b) / 2

    if name == "bird" and all(p in meshes for p in spec["parts"]):
        for wing, sign in (("WingL", 1), ("WingR", -1)):
            llo, lhi = local_points_range(UsdGeom.Mesh(meshes[wing]))
            near, far = (llo[2], lhi[2]) if sign > 0 else (-lhi[2], -llo[2])
            if abs(near) > 0.03 or far < 0.15:
                errors.append(f"{wing}: origin is not at the shoulder (local Z {llo[2]:.2f}..{lhi[2]:.2f})")
        if part_center("Beak")[0] >= part_center("Body")[0]:
            errors.append("bird does not face -X (beak is not on the -X side)")
    if name == "gate" and all(p in meshes for p in spec["parts"]):
        for door, sign in (("DoorL", -1), ("DoorR", 1)):
            llo, lhi = local_points_range(UsdGeom.Mesh(meshes[door]))
            t = translate(door)
            hinge_ok = (abs(llo[0]) < 0.01 and lhi[0] > 0.3) if sign < 0 else \
                       (abs(lhi[0]) < 0.01 and llo[0] < -0.3)
            if not hinge_ok or t[0] * sign <= 0:
                errors.append(f"{door}: origin is not at its outer hinge "
                              f"(origin x = {t[0]:.2f}, local X {llo[0]:.2f}..{lhi[0]:.2f})")
        if part_center("Glow")[2] >= part_center("DoorL")[2]:
            errors.append("gate does not face +Z (Glow is not behind the doors)")
        if part_center("Sign")[1] <= part_center("DoorL")[1]:
            errors.append("Sign is not above the doors")
    if name == "plane" and "Paper" in meshes:
        pts = []
        for p in meshes.values():
            pts += list(UsdGeom.Mesh(p).GetPointsAttr().Get())
        front = [p for p in pts if p[0] > lo[0] + 0.85 * size[0]]
        back = [p for p in pts if p[0] < lo[0] + 0.15 * size[0]]
        spread = lambda ps: max(p[2] for p in ps) - min(p[2] for p in ps) if ps else 0
        if not front or spread(front) >= spread(back):
            errors.append("plane nose does not point +X")

    children = [c.GetName() for c in root.GetChildren() if c.GetName() != "_materials"]
    nested = any(len([g for g in meshes[c].GetChildren() if g.IsA(UsdGeom.Imageable)]) for c in meshes)
    row = dict(name=name, up=up, mpu=mpu, tris=tris, budget=budget, size=size, lo=lo, hi=hi,
               root=str(root.GetPath()), children=children, errors=errors, nested=nested)
    return row, stage


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    allow_missing = "--allow-missing" in args  # while iterating on a few models
    args = [a for a in args if not a.startswith("--")]
    models_dir = os.path.abspath(args[0]) if args else DEFAULT_DIR
    files = sorted(f for f in os.listdir(models_dir) if f.endswith(".usdz")) \
        if os.path.isdir(models_dir) else []
    if not files:
        print(f"no .usdz files in {models_dir}")
        return 1

    rows = [check_model(os.path.join(models_dir, f))[0] for f in files]
    missing = [] if allow_missing else sorted(set(SPEC) - {r["name"] for r in rows})

    hdr = f"{'model':14s} {'up':2s} {'m/u':>3s} {'tris':>8s}  {'size X x Y x Z (m)':20s} {'bbox min':22s} {'bbox max':22s} children of root"
    print(hdr)
    print("-" * len(hdr))
    for r in rows:
        if "size" not in r:
            print(f"{r['name']:14s} ERROR {r['errors']}")
            continue
        s = r["size"]
        print(f"{r['name']:14s} {r['up']:2s} {r['mpu']:3.0f} {r['tris']:4d}/{r['budget']:<3d}  "
              f"{s[0]:5.2f} x {s[1]:5.2f} x {s[2]:5.2f}  {fmt3(r['lo']):22s} {fmt3(r['hi']):22s} "
              f"{r['root']}/{{{', '.join(r['children'])}}}")
    print()
    failed = False
    for r in rows:
        for e in r["errors"]:
            print(f"FAIL {r['name']}: {e}")
            failed = True
    for m in missing:
        print(f"FAIL {m}: missing {m}.usdz")
        failed = True
    print("RESULT:", "FAIL" if failed else f"PASS ({len(rows)} models)")
    return 1 if failed else 0


if __name__ == "__main__":
    code = main()
    sys.stdout.flush()
    sys.exit(code)
