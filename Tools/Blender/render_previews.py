"""Render a 512x512 preview of every exported model, plus a contact sheet.

    Blender --background --factory-startup --python Tools/Blender/render_previews.py \
        -- [model names...] [--models-dir DIR] [--preview-dir DIR] [--extra-views DIR]

Each .usdz is imported back from Skyfold/Resources/Models (so the preview shows
what the game will load), lit with EEVEE (one hard key sun + flat ambient, so the
shadows are crisp like a print offset) over flat cream #F7E6CC and framed from a
3/4 front view (the game camera side, +Z, a bit
above and toward the nose side +X). Writes previews/<name>.png and
previews/_all.png. --extra-views also writes side/back/top/front views
of each model into DIR for closer inspection.
"""
import argparse
import math
import os
import sys

import bpy
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import common as C  # noqa: E402

PREVIEW_DIR = os.path.join(HERE, "previews")
BACKGROUND = "#F7E6CC"
LABEL = "#9A7B66"
SIZE = 512
LENS = 50.0

# View directions (Blender Z-up, pointing from the model toward the camera).
VIEWS = {
    "3q": Vector((0.55, -1.0, 0.42)),    # game: +X nose side, +Z camera side, above
    "side": Vector((0.0, -1.0, 0.08)),   # the game's side camera
    "back": Vector((-1.0, -0.12, 0.18)),  # from behind (-X), slightly above
    "front": Vector((1.0, -0.12, 0.10)),  # from ahead (+X)
    "top": Vector((0.0, -0.02, 1.0)),
}


def setup_world(scene, background_hex, ambient_hex, ambient_strength):
    """Camera rays see the flat background color; shading gets a soft ambient."""
    world = bpy.data.worlds.new("PreviewWorld")
    scene.world = world
    nt = world.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    amb = nt.nodes.new("ShaderNodeBackground")
    amb.inputs["Color"].default_value = (*C.hex_to_linear(ambient_hex), 1.0)
    amb.inputs["Strength"].default_value = ambient_strength
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs["Color"].default_value = (*C.hex_to_linear(background_hex), 1.0)
    bg.inputs["Strength"].default_value = 1.0
    path = nt.nodes.new("ShaderNodeLightPath")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(path.outputs["Is Camera Ray"], mix.inputs["Fac"])
    nt.links.new(amb.outputs["Background"], mix.inputs[1])
    nt.links.new(bg.outputs["Background"], mix.inputs[2])
    nt.links.new(mix.outputs["Shader"], out.inputs["Surface"])
    world.color = C.hex_to_linear(background_hex)
    return world


def add_sun(scene, name, direction, energy, hex_color="#FFFFFF", angle=1.5):
    """direction: vector pointing from the scene toward the light."""
    light = bpy.data.lights.new(name, "SUN")
    light.energy = energy
    light.color = C.hex_to_linear(hex_color)
    light.angle = math.radians(angle)
    obj = bpy.data.objects.new(name, light)
    scene.collection.objects.link(obj)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector(direction).normalized().to_track_quat("Z", "Y")
    return obj


def setup_render(size=SIZE, background=BACKGROUND, ambient="#FFF3E6", key_energy=2.1):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.eevee.taa_render_samples = 32
    scene.eevee.use_shadows = True
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.image_settings.color_depth = "8"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    setup_world(scene, background, ambient, 0.50)
    # Hard key light from the upper front-left, as if the sun is behind the camera.
    add_sun(scene, "Key", (-0.45, -0.75, 1.0), key_energy)
    return scene


def import_model(path):
    before = set(bpy.data.objects)
    bpy.ops.wm.usd_import(filepath=path, import_cameras=False, import_lights=False,
                          create_world_material=False, import_materials=True,
                          read_mesh_uvs=False)
    objs = [o for o in bpy.data.objects if o not in before]
    for o in objs:
        if o.type != "MESH":
            continue
        for mat in o.data.materials:
            if mat is None or not mat.node_tree:
                continue
            mat.use_backface_culling = True  # holes in a preview = flipped normals
            for n in mat.node_tree.nodes:
                if n.bl_idname == "ShaderNodeBsdfPrincipled":
                    mat.diffuse_color = n.inputs["Base Color"].default_value
    return [o for o in objs if o.type == "MESH"]


def fit_camera(scene, objs, direction, margin=1.12):
    lo, hi = C.world_bbox(objs)
    center = (lo + hi) / 2
    d = direction.normalized()
    cam_data = bpy.data.cameras.new("PreviewCam")
    cam_data.lens = LENS
    cam_data.sensor_fit = "AUTO"
    cam = bpy.data.objects.new("PreviewCam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    rot = d.to_track_quat("Z", "Y")  # camera local +Z = back toward the camera
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = rot
    inv = rot.inverted()
    t = math.tan(math.atan(18.0 / LENS)) / margin
    dist = 0.0
    points = [o.matrix_world @ v.co for o in objs for v in o.data.vertices]
    for c in points:
        p = inv @ (c - center)  # camera space, +Z toward the camera
        dist = max(dist, abs(p.x) / t + p.z, abs(p.y) / t + p.z)
    cam.location = center + d * dist
    cam_data.clip_start = max(0.01, dist * 0.01)
    cam_data.clip_end = dist * 10
    return cam, dist


def add_label(scene, cam, text):
    curve = bpy.data.curves.new("Label", "FONT")
    curve.body = text
    curve.size = 0.032
    curve.align_x = "LEFT"
    obj = bpy.data.objects.new("Label", curve)
    scene.collection.objects.link(obj)
    mat = C.flat_material("LabelMat", LABEL)
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Emission Color"].default_value = (*C.hex_to_linear(LABEL), 1.0)
    bsdf.inputs["Emission Strength"].default_value = 1.0
    bsdf.inputs["Base Color"].default_value = (0, 0, 0, 1)
    curve.materials.append(mat)
    obj.parent = cam
    half = math.tan(math.atan(18.0 / LENS))  # half-width at distance 1
    obj.location = (-half + 0.03, -half + 0.03, -1.0)


def render(scene, out_path):
    scene.render.filepath = out_path
    bpy.ops.render.render(write_still=True)


def model_tris(objs):
    return sum(C.tri_count(o) for o in objs)


def render_model(path, preview_dir, extra_dir=None):
    name = os.path.splitext(os.path.basename(path))[0]
    C.reset_scene()
    scene = setup_render()
    objs = import_model(path)
    tris = model_tris(objs)
    cam, _ = fit_camera(scene, objs, VIEWS["3q"])
    add_label(scene, cam, f"{name}  {tris} tris")
    out = os.path.join(preview_dir, f"{name}.png")
    render(scene, out)
    print(f"[preview] {out}")
    if extra_dir:
        os.makedirs(extra_dir, exist_ok=True)
        for view, direction in VIEWS.items():
            if view == "3q":
                continue
            for o in list(scene.objects):
                if o.type in ("CAMERA", "FONT"):
                    bpy.data.objects.remove(o, do_unlink=True)
            fit_camera(scene, objs, direction)
            render(scene, os.path.join(extra_dir, f"{name}_{view}.png"))
    return out


def contact_sheet(paths, out_path, cols=4, tile=256):
    rows = math.ceil(len(paths) / cols)
    bg = np.array(C.hex_to_srgb(BACKGROUND)) * 255
    sheet = np.empty((rows * tile, cols * tile, 3), np.float32)
    sheet[:] = bg
    for i, p in enumerate(paths):
        img = C.read_image(p)[:, :, :3] * 255.0
        h, w = img.shape[:2]
        f = h // tile
        small = img[: tile * f, : tile * f].reshape(tile, f, tile, f, 3).mean(axis=(1, 3))
        r, c = divmod(i, cols)
        sheet[r * tile:(r + 1) * tile, c * tile:(c + 1) * tile] = small
    # thin separators
    for c in range(1, cols):
        sheet[:, c * tile - 1: c * tile + 1] = bg * 0.93
    for r in range(1, rows):
        sheet[r * tile - 1: r * tile + 1, :] = bg * 0.93
    C.write_png(out_path, np.clip(sheet + 0.5, 0, 255).astype(np.uint8))
    print(f"[preview] {out_path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("models", nargs="*")
    parser.add_argument("--models-dir", default=C.MODELS_DIR)
    parser.add_argument("--preview-dir", default=PREVIEW_DIR)
    parser.add_argument("--extra-views")
    args = parser.parse_args(C.script_args())
    model_names = sorted(f[:-5] for f in os.listdir(args.models_dir) if f.endswith(".usdz"))
    if not model_names:
        parser.error(f"no USDZ files in {args.models_dir}")
    missing = sorted(set(args.models) - set(model_names))
    if missing:
        parser.error(f"unknown models: {', '.join(missing)}")

    preview_dir = os.path.abspath(args.preview_dir)
    os.makedirs(preview_dir, exist_ok=True)
    for name in args.models or model_names:
        render_model(os.path.abspath(os.path.join(args.models_dir, f"{name}.usdz")),
                     preview_dir, args.extra_views)
    all_previews = [os.path.join(preview_dir, f"{name}.png") for name in model_names]
    contact_sheet([path for path in all_previews if os.path.isfile(path)],
                  os.path.join(preview_dir, "_all.png"))


if __name__ == "__main__":
    main()
