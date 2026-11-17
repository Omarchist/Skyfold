"""Render the app icon and its night study from the game's exported paper dart."""
import argparse
import math
import os
import sys

import bpy
from mathutils import Quaternion, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import common as C  # noqa: E402
import render_previews as R  # noqa: E402

APP_ICON = os.path.join(C.PROJECT_ROOT, "Skyfold", "Assets.xcassets",
                        "AppIcon.appiconset", "AppIcon.png")
NIGHT_ICON = os.path.join(R.PREVIEW_DIR, "icon_night.png")

DAY = dict(card="#F4ECDD", stripes=("#D6402B", "#2C4F9E"), shadow="#9A7B66",
           paper="#FFFDF8", wing="#D6C7AE", fold="#B89F88", ambient="#FFF3E6", key=2.05)
NIGHT = dict(card="#161B28", stripes=("#E5A03A", "#7D93C6"), shadow="#0E1324",
             paper="#E6DEC7", wing="#7CF2C8", fold="#9FB0D6", ambient="#C9D7F4", key=1.65)


def flat_ink(name, color):
    material = bpy.data.materials.new(name)
    nodes = material.node_tree.nodes
    nodes.clear()
    ink = nodes.new("ShaderNodeEmission")
    ink.inputs["Color"].default_value = (*C.hex_to_linear(color), 1.0)
    surface = nodes.new("ShaderNodeOutputMaterial")
    material.node_tree.links.new(ink.outputs["Emission"], surface.inputs["Surface"])
    return material


def camera(scene, parts):
    data = bpy.data.cameras.new("IconCamera")
    data.type = "ORTHO"
    data.ortho_scale = 1.25
    cam = bpy.data.objects.new(data.name, data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    direction = Vector((0.23, -0.48, 0.85)).normalized()
    rotation = direction.to_track_quat("Z", "Y")
    forward = rotation.inverted() @ Vector((1, 0, 0))
    roll = math.atan2(forward.y, forward.x) - math.radians(27)
    cam.rotation_mode = "QUATERNION"
    cam.rotation_quaternion = rotation @ Quaternion((0, 0, 1), roll)
    cam.location = direction * 2.6
    bpy.context.view_layer.update()
    view = cam.matrix_world.inverted()
    points = [view @ obj.matrix_world @ v.co for obj in parts for v in obj.data.vertices]
    mid_x = (min(p.x for p in points) + max(p.x for p in points)) / 2
    mid_y = (min(p.y for p in points) + max(p.y for p in points)) / 2
    cam.location += cam.rotation_quaternion @ Vector((mid_x, mid_y, 0))
    return cam


def print_shape(scene, cam, name, vertices, faces, material):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    obj = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(obj)
    obj.parent = cam
    mesh.materials.append(material)


def airmail_border(scene, cam, colors):
    half = cam.data.ortho_scale / 2
    for parity, color in enumerate(colors):
        vertices, faces = [], []
        for low, high in [(-half - 0.01, -half + 0.105), (half - 0.105, half + 0.01)]:
            for i in range(-7 + parity, 8, 2):
                x = i * 0.115
                start = len(vertices)
                vertices.extend([(x, low, -4.8), (x + 0.080, low, -4.8),
                                 (x + 0.170, high, -4.8), (x + 0.090, high, -4.8)])
                faces.append(tuple(range(start, start + 4)))
        name = f"Airmail{parity}"
        print_shape(scene, cam, name, vertices, faces, flat_ink(name, color))


def shadow(scene, cam, parts, color):
    bpy.context.view_layer.update()
    material = flat_ink("Shadow", color)
    for layer, obj in enumerate(parts):
        to_camera = cam.matrix_world.inverted() @ obj.matrix_world
        points = [to_camera @ vertex.co for vertex in obj.data.vertices]
        shape = [(p.x + 0.023, p.y - 0.043, -3.6 - layer * 0.01) for p in points]
        faces = [face.vertices[:] for face in obj.data.polygons]
        print_shape(scene, cam, f"Shadow{layer}", shape, faces, material)


def render_variant(plane, output, palette):
    C.reset_scene()
    scene = R.setup_render(1024, palette["card"], palette["ambient"], palette["key"])
    parts = R.import_model(plane)
    if {obj.name for obj in parts} != {"Paper", "Crease"}:
        raise RuntimeError("expected the Paper and Crease mesh parts in plane.usdz")
    for obj in parts:
        color = palette["fold"] if obj.name == "Crease" else palette["paper"]
        obj.data.materials.clear()
        obj.data.materials.append(C.flat_material(obj.name + "Ink", color))
        if obj.name == "Paper":
            obj.data.materials.append(C.flat_material("WingInk", palette["wing"]))
            for polygon in obj.data.polygons:
                if (obj.matrix_world @ polygon.center).y < -0.015:
                    polygon.material_index = 1
    cam = camera(scene, parts)
    airmail_border(scene, cam, palette["stripes"])
    shadow(scene, cam, parts, palette["shadow"])
    output = os.path.abspath(output)
    os.makedirs(os.path.dirname(output), exist_ok=True)
    R.render(scene, output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plane", default=os.path.join(C.MODELS_DIR, "plane.usdz"))
    parser.add_argument("--day", default=APP_ICON)
    parser.add_argument("--night", default=NIGHT_ICON)
    args = parser.parse_args(C.script_args())
    plane = os.path.abspath(args.plane)
    render_variant(plane, args.day, DAY)
    render_variant(plane, args.night, NIGHT)


if __name__ == "__main__":
    main()
