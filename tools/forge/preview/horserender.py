#!/usr/bin/env python3
"""Renders of the forged horse in Blender (Cycles, CPU): turntable views, clip frames, and a
person beside it for scale.

    blender -b --python tools/forge/preview/horserender.py -- <horse.glb> <out_dir> \\
        [--clips Idle@0,Walk@0.25,Gallop@0.5] [--views 0,60,180,270] [--size 640x420] [--person]

Each image is <out_dir>/<clip>_<frame>_<view>.png, and <out_dir>/sheet.png tiles them. `--person`
stands the humanoid rig (game/assets/models/characters/humanoid_rig) at the horse's near
shoulder, facing the same way, which is how the saddle's height and the horse's size are judged.
"""
from __future__ import annotations

import math
import os
import sys

import bpy  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))


def args():
    a = sys.argv[sys.argv.index("--") + 1:]
    out = {"glb": a[0], "out": a[1], "clips": "Idle@0", "views": "0,50,180,300", "size": "640x420", "person": False,
           "samples": 24, "lod": ""}
    i = 2
    while i < len(a):
        k = a[i].lstrip("-")
        if k == "person":
            out["person"] = True
            i += 1
            continue
        out[k] = a[i + 1]
        i += 2
    return out


def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


def main():
    A = args()
    os.makedirs(A["out"], exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = int(A["samples"])
    sc.cycles.use_denoising = False
    w, h = [int(x) for x in A["size"].split("x")]
    sc.render.resolution_x, sc.render.resolution_y = w, h
    sc.render.film_transparent = False
    sc.view_settings.view_transform = 'Filmic' if 'Filmic' in [v.identifier for v in sc.view_settings.bl_rna.properties['view_transform'].enum_items] else 'Standard'
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.62, 0.68, 0.76, 1.0)
    bg.inputs[1].default_value = 0.7
    sc.world = world
    objs = import_glb(A["glb"])
    arm = next((o for o in objs if o.type == 'ARMATURE'), None)
    meshes = [o for o in objs if o.type == 'MESH']
    lod = A.get("lod", "")
    for m in meshes:
        n = m.name.lower()
        is_lod = "lod1" in n or "lod2" in n
        show = (lod and lod in n) or (not lod and not is_lod)
        m.hide_render = not show
    if A["person"]:
        pobjs = import_glb(os.path.join(ROOT, "game", "assets", "models", "characters", "humanoid_rig", "humanoid_rig.glb"))
        for o in pobjs:
            if o.parent is None:
                # glTF: the horse faces +Z in Y-up, which Blender's importer turns back to -Y
                o.location = (1.0, -0.35, 0.0)
        parm = next((o for o in pobjs if o.type == 'ARMATURE'), None)
        if parm is not None and parm.animation_data is not None:
            idle = bpy.data.actions.get("Idle")
            parm.animation_data.action = idle
            for t in parm.animation_data.nla_tracks:
                t.mute = True
    # ground
    bpy.ops.mesh.primitive_plane_add(size=30.0, location=(0, 0, 0))
    g = bpy.context.active_object
    gm = bpy.data.materials.new("Ground")
    gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.36, 0.40, 0.26, 1)
    g.data.materials.append(gm)
    # sun and fill
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", 'SUN'))
    sun.data.energy = 3.2
    sun.data.angle = math.radians(6)
    sun.rotation_euler = (math.radians(50), 0.0, math.radians(35))
    bpy.context.collection.objects.link(sun)
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    cam.data.lens = 50
    bpy.context.collection.objects.link(cam)
    sc.camera = cam
    target = (0.0, 0.0, 1.05)
    dist = 5.6
    tiles = []
    for spec in A["clips"].split(","):
        clip, _, frac = spec.partition("@")
        frac = float(frac or 0.0)
        act = bpy.data.actions.get(clip)
        if arm is not None and arm.animation_data is not None:
            for t in arm.animation_data.nla_tracks:
                t.mute = True
            arm.animation_data.action = act
        frame = 0
        if act is not None:
            lo, hi = act.frame_range
            frame = int(round(lo + (hi - lo) * frac))
        sc.frame_set(frame)
        for v in A["views"].split(","):
            yaw = math.radians(float(v))
            # view 0: from the horse's near (left) side, which is +X in Blender after import
            cx = target[0] + dist * math.cos(yaw)
            cy = target[1] - dist * math.sin(yaw)
            cam.location = (cx, cy, target[2] + 0.55)
            d = (target[0] - cx, target[1] - cy, target[2] - cam.location[2])
            pitch = math.atan2(d[2], math.hypot(d[0], d[1]))
            cam.rotation_euler = (math.pi / 2 + pitch, 0.0, math.atan2(d[1], d[0]) - math.pi / 2)
            path = os.path.join(A["out"], "%s_%03d_%s.png" % (clip, frame, v))
            sc.render.filepath = path
            bpy.ops.render.render(write_still=True)
            tiles.append(path)
            print("[render] %s" % path, flush=True)
    try:
        from PIL import Image
        ims = [Image.open(p) for p in tiles]
        cols = min(len(A["views"].split(",")), 4)
        rows = (len(ims) + cols - 1) // cols
        sheet = Image.new("RGB", (w * cols, h * rows), (30, 30, 30))
        for i, im in enumerate(ims):
            sheet.paste(im, ((i % cols) * w, (i // cols) * h))
        sheet.save(os.path.join(A["out"], "sheet.png"))
    except Exception as e:  # PIL may not be in Blender's Python
        print("[render] no sheet: %s" % e)


main()
