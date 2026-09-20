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


def mesh_object_name(base: str) -> str:
    """A mesh object name that cannot collide with a bone name.

    Godot makes node names unique on import, so a mesh called "Head" forces the *bone*
    called "Head" to become "Head_2" — which silently breaks CONTRACTS §2 and every
    animation track that targets it."""
    return "%s_Mesh" % base if base in rig.ALL_BONES else base


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
# building the body, the head and the eyes
# ======================================================================================

BODY_TRIS = 7800
HEAD_TRIS = 4200
BODY_TEX = 1024
HEAD_TEX = 1024


def build_body(skel: Skeleton, style: bodylib.BodyStyle, name: str = "Body",
               spacing: float = 0.0080, target_tris: int = BODY_TRIS):
    verts, quads = bodylib.body_mesh(skel, style, spacing=spacing)
    ob = bodylib.to_object(mesh_object_name(name), verts, quads)
    bodylib.decimate(ob, target_tris)
    bodylib.smart_uv(ob, angle_deg=66.0, margin=0.015)
    return ob


def build_head(skel: Skeleton, hs: bodylib.HeadStyle, name: str = "Head",
               spacing: float = 0.0032, target_tris: int = HEAD_TRIS):
    verts, quads = bodylib.head_mesh(skel, hs, spacing=spacing)
    ob = bodylib.to_object(mesh_object_name(name), verts, quads)
    bodylib.decimate(ob, target_tris)
    L = bodylib.head_landmarks(skel, hs)
    bodylib.cylindrical_uv(ob, L["skull_c"], float(L["chin_z"] - 0.10 * L["s"]), float(L["top"][2]))
    return ob


def build_eyes(skel: Skeleton, hs: bodylib.HeadStyle) -> List:
    L = bodylib.head_landmarks(skel, hs)
    out = []
    for side, sx in (("L", 1), ("R", -1)):
        c = np.array([sx * L["eye_x"], L["eye_c_y"], L["eye_z"]])
        v, f, uv = bodylib.eye_mesh(c, L["eye_r"])
        ob = bodylib.to_object("Eye_%s" % side, v, f, uvs=uv)
        out.append(ob)
    return out


def paint_body(ob, skel: Skeleton, hs: bodylib.HeadStyle, out_dir: str, stem: str, appearance: dict,
               size: int = BODY_TEX, scene=None) -> Tuple[str, str, str]:
    """Bake albedo / ORM / normal for a skin mesh and return their paths.

    `scene` is the SDF the mesh came from.  Handing it over is what makes the bake painted
    rather than flat: the armpit, the inside of an elbow, the gap between two fingers and
    the crease under a lip all darken because the field says they are enclosed, and the
    parts that stick out -- knuckles, knees, the nose -- take the warmth and the wear."""
    L = bodylib.head_landmarks(skel, hs)
    maps = paint.surface_maps(ob, size=size, pad=4)
    head = bool(appearance.get("face", True))
    occ_r = 0.022 if head else 0.052
    fn = paint.skin_paint(
        L, tone=appearance.get("skin", "wheat"), seed=int(appearance.get("seed", 0)),
        face=appearance.get("face", True), brow_colour=appearance.get("hair_colour", "dark_brown"),
        age=float(appearance.get("age", 0.3)), hearth=float(appearance.get("hearth", 0.0)),
        hollow=float(appearance.get("hollow", 0.0)), veins=float(appearance.get("veins", 0.0)),
        freckles=float(appearance.get("freckles", 0.0)), stubble=float(appearance.get("stubble", 0.0)),
        beard_colour=appearance.get("beard_colour"),
        scene=scene, occ_radius=occ_r,
        warm_points=None if head else paint.warm_points_for(skel, L))
    albedo = paint.paint(maps, fn, background=(0.72, 0.58, 0.48))
    occ_fn, rough_fn = paint.skin_orm(L, seed=int(appearance.get("seed", 0)),
                                      age=float(appearance.get("age", 0.3)),
                                      scene=scene, occ_radius=occ_r)
    occ = paint.paint(maps, occ_fn, background=(1, 1, 1))[..., 0]
    rough = paint.paint(maps, rough_fn, background=(0.7, 0.7, 0.7))[..., 0]
    orm = paint.orm_image(occ, rough, np.zeros_like(rough))
    # a little painterly surface: pores and creases as a height field -> tangent normal
    # A gentle height field only: skin is smooth, and fine noise here aliases badly at
    # texture resolution and reads as crust rather than as pores.
    n = paint.Noise(int(appearance.get("seed", 0)) + 5, 32)
    h = np.zeros((size, size))
    m = maps["mask"]
    if m.any():
        h[m] = n.fbm(maps["pos"][m], freq=14.0, octaves=2)
    nrm = normal_from_height(h, strength=0.010)
    a_path = paint.save_png(albedo, os.path.join(out_dir, "%s_albedo.png" % stem))
    o_path = paint.save_png(orm, os.path.join(out_dir, "%s_orm.png" % stem))
    n_path = paint.save_png(nrm, os.path.join(out_dir, "%s_normal.png" % stem))
    return a_path, o_path, n_path


def paint_eyes(out_dir: str, stem: str, appearance: dict, size: int = 256) -> str:
    img = paint.iris_texture(size, colour=appearance.get("eye_colour", "brown"),
                             seed=int(appearance.get("seed", 0)),
                             glint=float(appearance.get("hearth", 0.0)),
                             red_eye=float(appearance.get("hollow", 0.0)) * 0.8)
    return paint.save_png(img, os.path.join(out_dir, "%s_albedo.png" % stem))


def skin_parts(objs: Sequence, arm, skel: Skeleton, body_ob=None, body_W=None) -> None:
    """Bind meshes to the armature: the body by bone heat, everything else by transferring
    the body's weights, so every part deforms exactly like the skin underneath it."""
    for ob in objs:
        if ob is body_ob:
            continue
        bodylib.transfer_weights(ob, body_W[0], body_W[1], arm)


# ======================================================================================
# the humanoid rig asset
# ======================================================================================

DEFAULT_APPEARANCE = {
    "skin": "wheat", "eye_colour": "brown", "hair_colour": "dark_brown", "seed": 1,
    "age": 0.3, "freckles": 0.15,
}


def cmd_rig(args) -> None:
    t0 = time.time()
    reset_scene()
    name = "humanoid_rig"
    out_dir = ensure_dir(os.path.join(OUT_ROOT, name))
    skel = Skeleton(rig.Proportions())
    style = bodylib.BodyStyle()
    hs = bodylib.HeadStyle()
    arm = rig.build_armature(skel, name="Armature")
    log("armature: %d bones" % len(arm.data.bones))

    body_ob = build_body(skel, style)
    log("body: %d tris" % bodylib.tri_count(body_ob))
    method = bodylib.skin_to_armature(body_ob, arm, skel)
    log("body weights: %s" % method)
    bv, bn, bt = bodylib.mesh_arrays(body_ob)
    bW = bodylib.weight_matrix(body_ob, rig.DEFORM_NAMES)

    head_ob = build_head(skel, hs)
    log("head: %d tris" % bodylib.tri_count(head_ob))
    eyes = build_eyes(skel, hs)
    bodylib.rigid_weights(head_ob, "Head", arm)
    for e in eyes:
        bodylib.rigid_weights(e, "Head", arm)

    app = dict(DEFAULT_APPEARANCE)
    ba, bo, bnp = paint_body(body_ob, skel, hs, out_dir, "%s_body" % name, dict(app, face=False),
                             scene=bodylib.body_scene(skel, style))
    ha, ho, hn = paint_body(head_ob, skel, hs, out_dir, "%s_head" % name, dict(app, face=True),
                            scene=bodylib.head_scene(skel, hs))
    ea = paint_eyes(out_dir, "%s_eye" % name, app)
    body_ob.data.materials.append(make_material("WM_Skin_Body", ba, bo, bnp, roughness=0.65))
    head_ob.data.materials.append(make_material("WM_Skin_Head", ha, ho, hn, roughness=0.62))
    eye_mat = make_material("WM_Eye", ea, roughness=0.18)
    for e in eyes:
        e.data.materials.append(eye_mat)

    sidecar = bake_all_clips(arm, skel, only=args.clips)
    objs = [arm, body_ob, head_ob] + eyes
    glb = export_glb(os.path.join(out_dir, "%s.glb" % name), objs, with_animation=True)
    with open(os.path.join(out_dir, "%s.clips.json" % name), "w") as f:
        json.dump(sidecar, f, indent=1, sort_keys=True)
    tris = bodylib.tri_count(body_ob) + bodylib.tri_count(head_ob) + sum(bodylib.tri_count(e) for e in eyes)
    write_meta(os.path.join(out_dir, "%s.meta.json" % name), name,
               {"proportions": skel.props.to_dict(), "style": style.to_dict(), "head": hs.to_dict(),
                "appearance": app},
               [tris, 0, 0], collision="capsule", bounds=object_bounds(body_ob), seed=1,
               extra={"rig": rig.RIG_ID, "clips": sorted(sidecar.keys()), "bones": len(arm.data.bones)})
    log("wrote %s (%d tris) in %.1fs" % (glb, tris, time.time() - t0))


# ======================================================================================
# modular parts
# ======================================================================================

PART_DIRS = {
    "head": "heads", "hair": "hair", "beard": "beards", "clothing": "clothing",
    "attachment": "attachments", "body": "bodies",
}
HEAD_PRESETS: Dict[str, dict] = {
    # the five cultures of WORLD_BIBLE §3 plus the shapes character creation offers
    "default": {},
    "broad": {"skull_width": 1.08, "jaw_width": 1.14, "chin": 1.10, "brow": 1.15, "nose": 1.05},
    "narrow": {"skull_width": 0.94, "jaw_width": 0.88, "chin": 0.92, "cheeks": 0.90, "nose": 0.95},
    "round": {"skull_width": 1.05, "skull_depth": 0.96, "jaw_width": 1.02, "cheeks": 1.20, "chin": 0.88},
    "angular": {"jaw_width": 1.10, "chin": 1.18, "cheeks": 1.15, "brow": 1.20, "nose_bridge": 1.15},
    "soft": {"jaw_width": 0.90, "chin": 0.85, "cheeks": 1.15, "lips": 1.25, "brow": 0.78, "eye_size": 1.06},
    "hawk": {"nose": 1.30, "nose_bridge": 1.25, "cheeks": 0.88, "jaw_width": 0.95, "brow": 1.10},
    "heavy_brow": {"brow": 1.35, "skull_depth": 1.05, "jaw_width": 1.08, "eye_spacing": 1.05},
}
BODY_VARIANTS: Dict[str, dict] = {
    # runtime bone scaling would break clips authored on the default proportions
    # (CONTRACTS §2), so a few baked variants cover the range instead
    "default": {},
    "slight": {"bulk": 0.90, "build": 0.15, "shoulder_width": 0.92},
    "heavy": {"bulk": 1.12, "build": 0.85, "hip_width": 1.10},
    "child": {"height": 1.30, "head_size": 1.18, "limb_length": 0.90, "bulk": 0.92, "build": 0.45,
              "shoulder_width": 0.88},
}


def part_dir(kind: str, name: str) -> str:
    return ensure_dir(os.path.join(OUT_ROOT, PART_DIRS[kind], name))


def export_part(name: str, kind: str, objs: Sequence, arm, params: dict, seed: int = 0,
                extra: Optional[dict] = None) -> str:
    out_dir = part_dir(kind, name)
    glb = export_glb(os.path.join(out_dir, "%s.glb" % name), [arm] + list(objs), with_animation=False)
    tris = sum(bodylib.tri_count(o) for o in objs)
    write_meta(os.path.join(out_dir, "%s.meta.json" % name), name, params, [tris, 0, 0],
               collision="none", bounds=object_bounds(objs[0]), seed=seed,
               extra=dict(extra or {}, rig=rig.RIG_ID, kind=kind))
    log("part %-16s %-11s %5d tris -> %s" % (name, kind, tris, os.path.relpath(glb, ROOT)))
    return glb


def _fresh_rig(props: Optional[rig.Proportions] = None):
    """A scene holding only the armature, for building one part against."""
    reset_scene()
    skel = Skeleton(props or rig.Proportions())
    arm = rig.build_armature(skel, name="Armature")
    return skel, arm


def _garment_material(g, out_dir: str, stem: str, seed: int, scene=None):
    """Painted material for a garment: the colour comes from the game at runtime, so the
    texture carries value, weave and wear rather than hue.

    Three things stop a garment being a coloured layer of skin.  Occlusion from the cloth's
    own field, which darkens the inside of every fold and the shadow under a hem.  A weave
    at two scales, because one scale is noise and two is fabric.  And wear on the parts that
    stick out and the parts that face up, where a real garment is rubbed pale and where dust
    settles -- an elbow and a shoulder are never the same value as a chest."""
    defaults = clothlib.MATERIAL_DEFAULTS.get(g.material, clothlib.MATERIAL_DEFAULTS["cloth"])
    leather = g.material in ("leather", "horn")
    metal = float(defaults["metallic"]) > 0.5
    n = paint.Noise(seed + 31, 32)
    radius = 0.026 if metal else 0.034

    def _occ(p, nrm):
        if scene is None:
            return np.ones(len(p))
        return paint.sdf_occlusion(scene, p, nrm, radius=radius, samples=5)

    def albedo(p, nrm):
        base = np.full((len(p), 3), 0.82)
        # two scales of weave: the thread and the bolt it was cut from
        thread = n.fbm(p, freq=190.0 if not leather else 120.0, octaves=2)
        cloth = n.fbm(p, freq=26.0, octaves=3)
        bolt = n.fbm(p, freq=6.0, octaves=2)
        c = base * (0.88 + 0.16 * bolt)[:, None] * (0.93 + 0.12 * cloth)[:, None] \
            * (0.96 + 0.07 * thread)[:, None]
        occ = _occ(p, nrm)
        # creases: value, not hue, so the game can tint the garment any colour it likes
        c = c * (0.62 + 0.38 * occ)[:, None]
        # dust settles on what faces up; the underside of a hem stays dark
        up = np.clip(nrm[:, 2], 0, 1)
        c = paint.mix(c, np.full((len(p), 3), 0.90), 0.10 * up * (0.4 + 0.6 * occ))
        c = paint.mix(c, np.full((len(p), 3), 0.58), 0.20 * np.clip(-nrm[:, 2], 0, 1))
        # wear: the proud parts rub pale, and unevenly, so it does not look sprayed on
        proud = paint.exposure(occ, 3.0) * (0.55 + 0.45 * n.fbm(p, freq=13.0, octaves=2))
        c = paint.mix(c, np.full((len(p), 3), 0.97 if not leather else 0.88), 0.26 * proud)
        return np.clip(c, 0, 1)

    def orm(p, nrm):
        occ = _occ(p, nrm)
        r = defaults["roughness"] + 0.10 * (n.fbm(p, freq=44.0, octaves=2) - 0.5)
        # worn patches are smoother than the cloth around them; creases are rougher
        r = r - 0.14 * paint.exposure(occ, 3.0) + 0.06 * (1.0 - occ)
        o = np.clip(occ, 0, 1) * (1.0 - 0.16 * np.clip(-nrm[:, 2], 0, 1))
        m = np.full(len(p), float(defaults["metallic"]))
        return np.stack([np.clip(o, 0, 1), np.clip(r, 0.05, 1), m], axis=1)
    return albedo, orm


def build_garment_part(g, skel: Skeleton, arm, body_ob, bW, seed: int, kind: str = "clothing") -> str:
    verts, quads = g.mesh()
    if len(verts) == 0:
        log("part %s produced no geometry" % g.name)
        return ""
    ob = bodylib.to_object(mesh_object_name(g.name), verts, quads)
    bodylib.decimate(ob, g.target_tris)
    bodylib.smart_uv(ob, angle_deg=66.0, margin=0.02)
    if g.bone:
        bodylib.rigid_weights(ob, g.bone, arm)
    else:
        bodylib.transfer_weights(ob, bW[0], bW[1], arm)
    out_dir = part_dir(kind, g.name)
    tex = 256 if g.material in ("hair", "horn", "glow") else 384
    maps = paint.surface_maps(ob, size=tex, pad=3)
    occ_map = np.ones((tex, tex))
    if g.material == "hair":
        fn = paint.hair_paint("brown", seed=seed)
        alb = paint.paint(maps, fn, background=(0.35, 0.25, 0.18))
        rough = np.full((tex, tex), 0.52)
    else:
        a_fn, o_fn = _garment_material(g, out_dir, g.name, seed, scene=g.scene)
        alb = paint.paint(maps, a_fn, background=(0.8, 0.8, 0.8))
        orm3 = paint.paint(maps, o_fn, background=(1.0, 0.8, 0.0))
        rough = orm3[..., 1]
        occ_map = orm3[..., 0]
    defaults = clothlib.MATERIAL_DEFAULTS.get(g.material, clothlib.MATERIAL_DEFAULTS["cloth"])
    # the occlusion channel used to be discarded here for a flat white, which threw away
    # every crease the material had just worked out
    occ = occ_map if g.material != "hair" else np.ones((tex, tex))
    met = np.full((tex, tex), float(defaults["metallic"]))
    a_path = paint.save_png(alb, os.path.join(out_dir, "%s_albedo.png" % g.name))
    o_path = paint.save_png(paint.orm_image(occ, rough, met), os.path.join(out_dir, "%s_orm.png" % g.name))
    mat = make_material("WM_%s" % g.name, a_path, o_path,
                        roughness=float(defaults["roughness"]), metallic=float(defaults["metallic"]))
    ob.data.materials.append(mat)
    return export_part(g.name, kind, [ob], arm, {"material": g.material, "bone": g.bone},
                       seed=seed, extra={"material": g.material, "slot_hint": _slot_hint(g.name)})


def _slot_hint(name: str) -> str:
    if name in ("tunic", "shirt", "dress", "robe", "gambeson", "plate_torso", "brigandine", "apron",
                "coat", "wrap_torso"):
        return "torso"
    if name in ("trousers", "skirt", "wrap_skirt", "kilt", "leg_wraps"):
        return "legs"
    if name in ("boots", "shoes", "greaves"):
        return "feet"
    if name in ("gloves",):
        return "hands"
    if name in ("belt",):
        return "belt"
    if name in ("cloak", "hooded_cloak", "ragged_cloak", "plaid", "shoulder_cape"):
        return "back"
    if name in ("helm", "hood", "pauldrons"):
        return "headgear" if name in ("helm", "hood") else "torso"
    return "attachment"


def cmd_parts(args) -> None:
    only = set(args.only) if getattr(args, "only", None) else None
    t0 = time.time()

    def want(n: str) -> bool:
        return only is None or n in only

    # -- heads ---------------------------------------------------------------------------
    for name, params in HEAD_PRESETS.items():
        if not want(name) and not want("heads"):
            continue
        skel, arm = _fresh_rig()
        hs = bodylib.HeadStyle.from_dict(params)
        ob = build_head(skel, hs)
        eyes = build_eyes(skel, hs)
        bodylib.rigid_weights(ob, "Head", arm)
        for e in eyes:
            bodylib.rigid_weights(e, "Head", arm)
        out_dir = part_dir("head", name)
        app = dict(DEFAULT_APPEARANCE)
        a, o, nmap = paint_body(ob, skel, hs, out_dir, name, dict(app, face=True), size=768,
                                scene=bodylib.head_scene(skel, hs))
        ea = paint_eyes(out_dir, "%s_eye" % name, app)
        ob.data.materials.append(make_material("WM_Skin_%s" % name, a, o, nmap, roughness=0.62))
        em = make_material("WM_Eye_%s" % name, ea, roughness=0.18)
        for e in eyes:
            e.data.materials.append(em)
        export_part(name, "head", [ob] + eyes, arm, {"head": hs.to_dict()}, seed=1,
                    extra={"slot_hint": "head"})

    # -- body variants --------------------------------------------------------------------
    for name, params in BODY_VARIANTS.items():
        if name == "default" or (not want(name) and not want("bodies")):
            continue
        props = rig.Proportions.from_dict(params)
        skel, arm = _fresh_rig(props)
        style = bodylib.BodyStyle()
        ob = build_body(skel, style)
        bodylib.skin_to_armature(ob, arm, skel)
        out_dir = part_dir("body", name)
        app = dict(DEFAULT_APPEARANCE)
        a, o, nmap = paint_body(ob, skel, bodylib.HeadStyle(), out_dir, name, dict(app, face=False),
                                scene=bodylib.body_scene(skel, style))
        ob.data.materials.append(make_material("WM_Skin_%s" % name, a, o, nmap, roughness=0.65))
        export_part(name, "body", [ob], arm, {"proportions": props.to_dict()}, seed=1,
                    extra={"slot_hint": "body"})

    # -- everything that is built against the default body --------------------------------
    skel, arm = _fresh_rig()
    style = bodylib.BodyStyle()
    body_ob = build_body(skel, style)
    bodylib.skin_to_armature(body_ob, arm, skel)
    bv, bn, bt = bodylib.mesh_arrays(body_ob)
    bW = (bv, bodylib.weight_matrix(body_ob, rig.DEFORM_NAMES))
    field = clothlib.body_field(skel, style)
    log("body field cached %s" % (field.F.shape,))
    bpy.data.objects.remove(body_ob, do_unlink=True)

    for name, builder in clothlib.CLOTHING_BUILDERS.items():
        if not want(name) and not want("clothing"):
            continue
        g = builder(skel, field)
        build_garment_part(g, skel, arm, None, bW, seed=abs(hash(name)) % 9999, kind="clothing")
    for name in clothlib.HAIR_STYLES:
        if not want(name) and not want("hair"):
            continue
        g = clothlib.build_hair(skel, name)
        build_garment_part(g, skel, arm, None, bW, seed=abs(hash(name)) % 9999, kind="hair")
    for name in clothlib.BEARD_STYLES:
        if not want(name) and not want("beards"):
            continue
        g = clothlib.build_beard(skel, name)
        build_garment_part(g, skel, arm, None, bW, seed=abs(hash(name)) % 9999, kind="beard")
    for name, builder in clothlib.ATTACHMENT_BUILDERS.items():
        if not want(name) and not want("attachments"):
            continue
        g = builder(skel)
        build_garment_part(g, skel, arm, None, bW, seed=abs(hash(name)) % 9999, kind="attachment")
    log("parts done in %.1fs" % (time.time() - t0))


# ======================================================================================
# presets
# ======================================================================================

CALLINGS = ["hearthkeeper", "wayfarer", "reedborn", "cragborn", "ashwalker", "lantern_clerk"]


def _preset(culture: str, **kw) -> dict:
    d = {"culture": culture, "seed": abs(hash(culture + str(kw.get("_n", "")))) % 99991}
    d.update({k: v for k, v in kw.items() if not k.startswith("_")})
    return d


def cmd_presets(args) -> None:
    pal = clothlib.CULTURE_PALETTES
    presets: Dict[str, dict] = {}

    def add(pid: str, culture: str, parts: dict, **kw) -> None:
        p = _preset(culture, _n=pid, parts=parts, **kw)
        presets[pid] = p

    # -- the six Callings (DESIGN.md §5.1): the player's starting look ---------------------
    add("player_hearthkeeper", "vale",
        {"head": "round", "hair": "short", "torso": "tunic", "legs": "trousers", "feet": "shoes", "belt": "belt"},
        skin="fair", hair_colour="sand", eye_colour="blue", build=0.50, age=0.22)
    add("player_wayfarer", "vale",
        {"head": "angular", "hair": "tousled", "torso": "shirt", "legs": "trousers", "feet": "boots",
         "belt": "belt", "back": "cloak"},
        skin="wheat", hair_colour="brown", eye_colour="hazel", build=0.45, age=0.30)
    add("player_reedborn", "reedfolk",
        {"head": "narrow", "hair": "long", "torso": "wrap_torso", "legs": "wrap_skirt",
         "feet": "shoes", "belt": "belt"},
        skin="olive", hair_colour="black", eye_colour="dark_brown", build=0.36, age=0.26)
    add("player_cragborn", "clans",
        {"head": "broad", "hair": "braid", "beard": "short_beard", "torso": "gambeson", "legs": "kilt",
         "feet": "boots", "belt": "belt", "back": "plaid"},
        skin="fair", hair_colour="ginger", eye_colour="grey_green", build=0.70, bulk=1.10,
        shoulder_width=1.12, age=0.34)
    add("player_ashwalker", "ash_pilgrims",
        {"head": "hawk", "hair": "cropped", "torso": "robe", "feet": "boots", "back": "hooded_cloak"},
        skin="amber", hair_colour="soot", eye_colour="grey", build=0.38, age=0.44)
    add("player_lantern_clerk", "lakefolk",
        {"head": "soft", "hair": "bun", "torso": "coat", "legs": "trousers", "feet": "shoes",
         "belt": "belt", "hands": "gloves"},
        skin="porcelain", hair_colour="ash_blond", eye_colour="pale_blue", build=0.40, age=0.28,
        feminine=1.0, height=1.66)

    # -- one archetype per culture (WORLD_BIBLE §3) ----------------------------------------
    add("vale_villager", "vale",
        {"head": "round", "hair": "short", "torso": "tunic", "legs": "trousers", "feet": "shoes", "belt": "belt"},
        skin="fair", hair_colour="chestnut", eye_colour="brown", build=0.55, age=0.42, freckles=0.4)
    # Each culture gets ONE shape you could name from across a field: the Vale is belted and
    # knee-length, Lakefolk are a straight column with square shoulders, Reedfolk are
    # asymmetric over a long wrap, the Clans are a diagonal drape over bare knees, Woodfolk
    # are hooded with banded legs and a torn hem.  Recolouring a tunic six times does not
    # make six peoples (DESIGN.md §7, WORLD_BIBLE.md §3).
    add("lakefolk_clerk", "lakefolk",
        {"head": "narrow", "hair": "bun", "torso": "coat", "legs": "trousers", "feet": "shoes",
         "back": "shoulder_cape", "hands": "gloves"},
        skin="wheat", hair_colour="dark_brown", eye_colour="grey", build=0.40, age=0.50)
    add("reedfolk_eeler", "reedfolk",
        {"head": "angular", "hair": "long", "torso": "wrap_torso", "legs": "wrap_skirt",
         "feet": "shoes", "belt": "belt"},
        skin="umber", hair_colour="black", eye_colour="dark_brown", build=0.44, age=0.38)
    add("clans_herder", "clans",
        {"head": "broad", "hair": "braid", "beard": "long_beard", "torso": "shirt", "legs": "kilt",
         "feet": "boots", "belt": "belt", "back": "plaid"},
        skin="fair", hair_colour="auburn", eye_colour="green", build=0.68, bulk=1.08, age=0.55)
    add("woodfolk_forester", "woodfolk",
        {"head": "hawk", "hair": "tousled", "torso": "shirt", "legs": "leg_wraps",
         "feet": "boots", "belt": "belt", "back": "ragged_cloak"},
        skin="olive", hair_colour="soot", eye_colour="grey_green", build=0.42, age=0.36)
    add("ash_pilgrim", "ash_pilgrims",
        {"head": "heavy_brow", "hair": "cropped", "beard": "long_beard", "torso": "robe",
         "feet": "boots", "back": "hooded_cloak"},
        skin="deep", hair_colour="grey", eye_colour="grey", build=0.46, age=0.72)

    # -- the named roles the world needs ----------------------------------------------------
    # A breastplate with bare shoulders reads as a corset, so plate wearers get pauldrons.
    add("warden_guard", "vale",
        {"head": "broad", "hair": "cropped", "torso": "brigandine", "legs": "trousers", "feet": "boots",
         "belt": "belt", "headgear": "helm", "hands": "gloves", "back": "pauldrons"},
        skin="wheat", hair_colour="dark_brown", eye_colour="brown", build=0.62, bulk=1.06,
        shoulder_width=1.10, age=0.40)
    add("bandit", "vale",
        {"head": "angular", "hair": "tousled", "beard": "stubble", "torso": "gambeson", "legs": "trousers",
         "feet": "boots", "belt": "belt"},
        skin="olive", hair_colour="soot", eye_colour="hazel", build=0.52, age=0.35, stubble=0.7)
    add("tolling_knight", "ash_pilgrims",
        {"head": "heavy_brow", "hair": "cropped", "torso": "plate_torso", "legs": "trousers", "feet": "boots",
         "belt": "belt", "headgear": "helm", "hands": "gloves", "back": "pauldrons"},
        skin="amber", hair_colour="grey", eye_colour="grey", build=0.66, bulk=1.10,
        shoulder_width=1.14, height=1.84, age=0.58)
    add("sayer", "lakefolk",
        {"head": "soft", "hair": "long", "torso": "robe", "feet": "shoes", "back": "cloak"},
        skin="porcelain", hair_colour="white", eye_colour="pale_blue", build=0.34, age=0.80,
        feminine=1.0, height=1.63)
    add("merchant", "lakefolk",
        {"head": "round", "hair": "short", "beard": "moustache", "torso": "tunic", "legs": "trousers",
         "feet": "shoes", "belt": "belt", "back": "cloak"},
        skin="wheat", hair_colour="brown", eye_colour="brown", build=0.78, bulk=1.12, age=0.52)
    add("child", "vale",
        {"head": "round", "hair": "tousled", "torso": "tunic", "legs": "trousers", "feet": "shoes"},
        skin="fair", hair_colour="sand", eye_colour="blue", build=0.45, age=0.05,
        height=1.30, head_size=1.18, limb_length=0.90, shoulder_width=0.88)

    # morality showcases (DESIGN.md §5.11)
    add("hollow_touched", "vale",
        {"head": "angular", "hair": "cropped", "torso": "gambeson", "legs": "trousers", "feet": "boots"},
        skin="porcelain", hair_colour="soot", eye_colour="red", build=0.48, age=0.40,
        hollow=0.85, veins=0.9)
    add("hearth_touched", "vale",
        {"head": "soft", "hair": "long", "torso": "tunic", "legs": "trousers", "feet": "shoes"},
        skin="wheat", hair_colour="flax", eye_colour="amber", build=0.45, age=0.28,
        hearth=0.85, feminine=1.0, height=1.68)

    data = {
        "generator": GENERATOR, "version": VERSION, "rig": rig.RIG_ID,
        "callings": CALLINGS,
        "culture_palettes": pal,
        "head_presets": sorted(HEAD_PRESETS.keys()),
        "body_variants": sorted(BODY_VARIANTS.keys()),
        "hair_styles": sorted(clothlib.HAIR_STYLES.keys()),
        "beard_styles": sorted(clothlib.BEARD_STYLES.keys()),
        "clothing": sorted(clothlib.CLOTHING_BUILDERS.keys()),
        "attachments": sorted(clothlib.ATTACHMENT_BUILDERS.keys()),
        "presets": presets,
    }
    # a preset carries its culture's palette unless it overrides one
    for pid, p in presets.items():
        culture_pal = pal.get(p["culture"], pal["vale"])
        p.setdefault("palette", {k: v for k, v in culture_pal.items() if k != "note"})
    path = os.path.join(ROOT, "tools", "forge", "characters.json")
    with open(path, "w") as f:
        json.dump(data, f, indent=1, sort_keys=True)
    log("wrote %s (%d presets)" % (os.path.relpath(path, ROOT), len(presets)))


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
