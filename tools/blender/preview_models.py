"""Render a three-quarter preview of every model in models/ for a quick visual check.

    blender --background --factory-startup --python tools/blender/preview_models.py -- <out_dir> [name ...]

Uses Workbench with material colours, from the same fixed three-quarter view
the kitchen uses (front and above, looking down).
"""

import math
import os
import sys

import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def render(name, out_dir):
    bpy.ops.wm.open_mainfile(filepath=os.path.join(ROOT, "models", name + ".blend"))
    scene = bpy.context.scene
    meshes = [o for o in scene.objects if o.type == "MESH"]
    pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
    lo = Vector((min(p[i] for p in pts) for i in range(3)))
    hi = Vector((max(p[i] for p in pts) for i in range(3)))
    centre, radius = (lo + hi) / 2, (hi - lo).length / 2
    cam_data = bpy.data.cameras.new("preview")
    cam_data.lens = 50
    cam_data.clip_start = radius * 0.01
    cam_data.clip_end = radius * 100
    cam = bpy.data.objects.new("preview", cam_data)
    scene.collection.objects.link(cam)
    direction = Vector((0.55, -1.0, 0.75)).normalized()
    cam.location = centre + direction * radius * 3.2
    cam.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.engine = "BLENDER_WORKBENCH"
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "MATERIAL"
    shading.show_object_outline = True
    shading.show_cavity = True
    scene.render.resolution_x = scene.render.resolution_y = 400
    scene.render.film_transparent = False
    scene.world = scene.world or bpy.data.worlds.new("w")
    scene.render.filepath = os.path.join(out_dir, name + ".png")
    bpy.ops.render.render(write_still=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:]
    out_dir, names = argv[0], argv[1:]
    os.makedirs(out_dir, exist_ok=True)
    names = names or sorted(f[:-6] for f in os.listdir(os.path.join(ROOT, "models")) if f.endswith(".blend"))
    for name in names:
        render(name, out_dir)


main()
