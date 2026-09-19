#!/usr/bin/env python3
"""Wickmere character forge — builds the humanoid rig, its body, and every modular part.

    blender -b --python tools/forge/character_forge.py -- <command> [options]

Commands
    rig        game/assets/models/characters/humanoid_rig/  (rig + default body + all clips)
    parts      heads, hair, beards, clothing, attachments — each its own GLB
    presets    tools/forge/characters.json (the preset table the game composes from)
    all        everything

Everything is generated: geometry from SDF fields (lib/sdf.py, lib/body.py, lib/cloth.py),
skin and cloth colour from 3D paint functions baked through the UV layout (lib/paint.py),
and animation from the clip library (lib/anim.py, lib/anim_clips.py).  No third-party
models, textures or motion data of any kind.

Outputs follow docs/CONTRACTS.md §4; the rig follows §2 and the clips §3.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys
import time
from typing import Dict, List, Optional, Sequence, Tuple

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
if os.path.dirname(HERE) not in sys.path:
    sys.path.insert(0, os.path.dirname(HERE))

import numpy as np

try:
    import bpy
    from mathutils import Quaternion, Vector
    HAVE_BPY = True
except ImportError:                                   # allows --help and unit imports
    HAVE_BPY = False

from forge.lib import rig, sdf, body as bodylib, paint, anim, anim_clips, cloth as clothlib
from forge.lib.rig import Skeleton, FWD, UP, LEFT

OUT_ROOT = os.path.join(ROOT, "game", "assets", "models", "characters")
GENERATOR = "character_forge"
VERSION = 1
FPS = 30


# ======================================================================================
# small local helpers (the shared materials/bake/export library belongs to another stream)
# ======================================================================================

def log(msg: str) -> None:
    print("[forge] %s" % msg, flush=True)


def reset_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS
    bpy.context.scene.unit_settings.system = 'METRIC'


def ensure_dir(path: str) -> str:
    os.makedirs(path, exist_ok=True)
    return path


def make_material(name: str, albedo_png: Optional[str] = None, orm_png: Optional[str] = None,
                  normal_png: Optional[str] = None, base_colour=(0.8, 0.8, 0.8, 1.0),
                  roughness: float = 0.7, metallic: float = 0.0, alpha_blend: bool = False):
    """Principled BSDF only, so Godot imports it as a StandardMaterial3D (CONTRACTS §4)."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = tuple(base_colour)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    x = -600
    if albedo_png:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(albedo_png)
        tex.image.colorspace_settings.name = 'sRGB'
        tex.location = (x, 300)
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        if alpha_blend:
            nt.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
            mat.blend_method = 'CLIP'
            mat.alpha_threshold = 0.5
    if orm_png:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(orm_png)
        tex.image.colorspace_settings.name = 'Non-Color'
        tex.location = (x, 0)
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        sep.location = (x + 250, 0)
        nt.links.new(tex.outputs["Color"], sep.inputs["Color"])
        nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
        nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
    if normal_png:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(normal_png)
        tex.image.colorspace_settings.name = 'Non-Color'
        tex.location = (x, -300)
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.location = (x + 250, -300)
        nm.inputs["Strength"].default_value = 0.8
        nt.links.new(tex.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def normal_from_height(height: np.ndarray, strength: float = 1.0) -> np.ndarray:
    """Tangent-space normal map from a height field in UV space (OpenGL +Y, CONTRACTS §4)."""
    gy, gx = np.gradient(np.asarray(height, float))
    n = np.stack([-gx * strength * 40.0, -gy * strength * 40.0, np.ones_like(gx)], axis=-1)
    n /= np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-9)
    return n * 0.5 + 0.5


def export_glb(path: str, objects: Sequence, with_animation: bool = False) -> str:
    """Export the given objects as a GLB.  Blender's -Y forward becomes Godot's +Z
    (CONTRACTS §1) through the standard Y-up conversion."""
    ensure_dir(os.path.dirname(path))
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(
        filepath=path, export_format='GLB', use_selection=True, export_yup=True,
        export_apply=False, export_skins=True, export_def_bones=False,
        export_animations=with_animation,
        export_animation_mode='ACTIONS' if with_animation else 'ACTIONS',
        export_nla_strips=with_animation, export_frame_range=False,
        export_anim_slide_to_zero=False, export_bake_animation=False,
        export_optimize_animation_size=False, export_optimize_animation_keep_anim_armature=True,
        export_normals=True, export_tangents=False, export_materials='EXPORT',
        export_image_format='AUTO', export_texcoords=True, export_extras=False,
        export_cameras=False, export_lights=False)
    return path


def write_meta(path: str, name: str, params: dict, tris: Sequence[int], collision: str = "capsule",
               bounds: Optional[Sequence[float]] = None, seed: int = 0, extra: Optional[dict] = None) -> str:
    meta = {"generator": GENERATOR, "version": VERSION, "seed": seed, "params": params,
            "tris": list(tris), "collision": collision,
            "bounds": list(bounds) if bounds is not None else None}
    if extra:
        meta.update(extra)
    with open(path, "w") as f:
        json.dump(meta, f, indent=1, sort_keys=True)
    return path


def object_bounds(ob) -> List[float]:
    v = np.array([v.co[:] for v in ob.data.vertices])
    if len(v) == 0:
        return [0, 0, 0, 0, 0, 0]
    return [round(float(x), 4) for x in list(v.min(axis=0)) + list(v.max(axis=0))]


# ======================================================================================
# animation baking
# ======================================================================================

def push_clip(arm, clip: anim.BakedClip) -> None:
    """Bake one clip onto the armature as an action on its own NLA track."""
    action = bpy.data.actions.new(clip.name)
    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = action
    for pb in arm.pose.bones:
        pb.rotation_mode = 'QUATERNION'
    n = clip.frames
    for bone in clip.bones:
        pb = arm.pose.bones[bone]
        data_path = pb.path_from_id("rotation_quaternion")
        curves = [action.fcurves.new(data_path, index=i, action_group=bone) for i in range(4)]
        q = clip.quats[bone]
        for i, fc in enumerate(curves):
            fc.keyframe_points.add(n)
            pts = np.empty(n * 2)
            pts[0::2] = np.arange(n) + 1
            pts[1::2] = q[:, i]
            fc.keyframe_points.foreach_set("co", pts)
            for kp in fc.keyframe_points:
                kp.interpolation = 'LINEAR'
            fc.update()
        if bone == "Hips":
            dp = pb.path_from_id("location")
            for i in range(3):
                fc = action.fcurves.new(dp, index=i, action_group=bone)
                fc.keyframe_points.add(n)
                pts = np.empty(n * 2)
                pts[0::2] = np.arange(n) + 1
                pts[1::2] = clip.hips_pos[:, i]
                fc.keyframe_points.foreach_set("co", pts)
                for kp in fc.keyframe_points:
                    kp.interpolation = 'LINEAR'
                fc.update()
    track = arm.animation_data.nla_tracks.new()
    track.name = clip.name
    strip = track.strips.new(clip.name, 1, action)
    strip.name = clip.name
    track.mute = False
    arm.animation_data.action = None


def bake_all_clips(arm, skel: Skeleton, only: Optional[Sequence[str]] = None) -> Dict[str, dict]:
    clips = anim_clips.build_clips(skel)
    problems = anim_clips.check_contract(clips)
    if problems:
        for p in problems:
            log("CONTRACT: %s" % p)
        raise SystemExit("clip library violates CONTRACTS.md §3")
    sidecar: Dict[str, dict] = {}
    names = [n for n in anim_clips.REQUIRED_CLIPS if (only is None or n in only)]
    t0 = time.time()
    for name in names:
        baked = clips[name].bake()
        push_clip(arm, baked)
        sidecar[name] = baked.sidecar()
    log("baked %d clips in %.1fs" % (len(names), time.time() - t0))
    return sidecar


# ======================================================================================
# CLI
# ======================================================================================

def main(argv: Optional[Sequence[str]] = None) -> int:
    if argv is None:
        argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    ap = argparse.ArgumentParser(prog="character_forge", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="command", required=True)
    p = sub.add_parser("rig", help="build humanoid_rig.glb (rig + default body + all clips)")
    p.add_argument("--clips", nargs="*", default=None, help="only these clips (default: all)")
    p.set_defaults(func=cmd_rig)
    p = sub.add_parser("parts", help="build the modular parts")
    p.add_argument("--only", nargs="*", default=None)
    p.set_defaults(func=lambda a: cmd_parts(a))
    p = sub.add_parser("presets", help="write tools/forge/characters.json")
    p.set_defaults(func=lambda a: cmd_presets(a))
    p = sub.add_parser("all", help="rig + parts + presets")
    p.add_argument("--clips", nargs="*", default=None)
    p.add_argument("--only", nargs="*", default=None)
    p.set_defaults(func=lambda a: (cmd_rig(a), cmd_parts(a), cmd_presets(a)))
    args = ap.parse_args(list(argv))
    if not HAVE_BPY:
        raise SystemExit("character_forge must run inside Blender: "
                         "blender -b --python tools/forge/character_forge.py -- <command>")
    args.func(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
