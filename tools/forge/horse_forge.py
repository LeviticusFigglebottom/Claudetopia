#!/usr/bin/env python3
"""The horse forge: the Wardens' cob on WM_Quadruped_v1, with its tack, LODs, paint and clips.

    blender -b --python tools/forge/horse_forge.py -- [--out DIR] [--quick] [--no-clips]
    blender -b --python tools/forge/horse_forge.py -- clips --out DIR     # the clips alone

The body and the tack are signed-distance scenes (`lib/horse_body.py`) meshed by surface nets,
decimated, unwrapped and painted texel by texel from their 3D positions (`lib/paint.py`), the way
the character forge makes its people. The skin is bone heat where it solves and distance to the
bones where it does not. The clips come from `lib/quad_clips.py`, baked onto the armature as one
NLA track each (the humanoid's `push_clip`).

Output (CONTRACTS §4), in `game/assets/models/creatures/horse_cob/` by default:
    horse_cob.glb          the armature, Horse_Body and Horse_Tack (LOD0), Horse_LOD1, Horse_LOD2, the clips
    horse_cob.clips.json   the sidecar (CONTRACTS §3b)
    horse_cob_coat_{albedo,orm,normal}.png, horse_cob_tack_{albedo,orm}.png
    horse_cob.meta.json

`clips --out DIR` bakes the clips alone onto the bare armature as DIR/horse_cob_clips.glb with its
sidecar, for `transplant_clips.py` to move onto the committed horse without rebuilding the body.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
for p in (HERE, os.path.dirname(HERE)):
    if p not in sys.path:
        sys.path.insert(0, p)

import numpy as np  # noqa: E402

import character_forge as cf  # noqa: E402  (its Blender helpers, not its command line)
from forge.lib import sdf, paint  # noqa: E402
from forge.lib import body as bodylib  # noqa: E402
from forge.lib import quadruped as quad  # noqa: E402
from forge.lib import quad_clips as qc  # noqa: E402
from forge.lib import horse_body as hb  # noqa: E402
from forge.lib import sheep_body as sb  # noqa: E402

NAME = "horse_cob"
OUT_ROOT = os.path.join(cf.ROOT, "game", "assets", "models", "creatures")
GENERATOR = "horse_forge"
VERSION = 1

BODY_TRIS = 12000
TACK_TRIS = 5200
LOD1_TRIS = 4200
LOD2_TRIS = 1300
TEX = 1024

# The Wardens' cob, Hollin: a dun mare. Colours are sRGB.
COAT = {
    "body": (0.70, 0.55, 0.36),      # the dun
    "shade": (0.50, 0.37, 0.23),     # the back and the quarters' shadowed side, sun-dark
    "light": (0.84, 0.74, 0.55),     # the belly, the inside of the legs, the flank's sheen
    "points": (0.14, 0.10, 0.08),    # the legs, the mane, the tail, the dorsal stripe
    "muzzle": (0.24, 0.20, 0.17),
    "hoof": (0.20, 0.18, 0.17),
    "eye": (0.05, 0.035, 0.03),
}
TACK = {
    "leather": (0.36, 0.21, 0.11),
    "leather_edge": (0.55, 0.36, 0.19),
    "cloth": (0.24, 0.33, 0.20),     # the Wardens' green wool
    "cloth_border": (0.74, 0.55, 0.20),   # and its ochre border
    "iron": (0.30, 0.30, 0.31),
    "eye": (0.04, 0.03, 0.025),
}


def log(msg: str) -> None:
    print("[horse] %s" % msg, flush=True)


# --------------------------------------------------------------------------------------
# meshes
# --------------------------------------------------------------------------------------

def mesh_object(name: str, scene: sdf.Scene, spacing: float, target: int, grid_out=None, smooth_iters: int = 6):
    v, q = sdf.mesh_from_scene(scene, spacing, smooth_iters=smooth_iters, grid_out=grid_out)
    if len(q) == 0:
        return None
    ob = bodylib.to_object(name, v, q)
    bodylib.decimate(ob, target)
    return ob


def eye_objects(skel: quad.QuadSkeleton):
    out = []
    hs = skel.props.head_size * skel.props.withers / quad.DEFAULT_WITHERS
    for side, sx in (("L", 1.0), ("R", -1.0)):
        c = hb.eye_centre(skel, sx) + np.array([sx * 0.006, -0.004, 0.0]) * hs
        v, f, uv = bodylib.eye_mesh(c, 0.024 * hs, nu=14, nv=10)
        # a horse's eye is an almond, wider than tall: squash the sphere
        v = c + (v - c) * np.array([0.75, 1.15, 0.85])
        out.append(bodylib.to_object("Horse_Eye_%s" % side, v, f))
    return out


# --------------------------------------------------------------------------------------
# skinning
# --------------------------------------------------------------------------------------

def skin_body(ob, arm, skel) -> str:
    bones = quad.DEFORM_NAMES
    method = "heat"
    if not bodylib.auto_weights(ob, arm):
        method = "segment"
    verts, normals, tris = bodylib.mesh_arrays(ob)
    W = bodylib.weight_matrix(ob, bones)
    seed = bodylib.segment_weights(verts, skel, bones, sharpness=2.6)
    empty = W.sum(axis=1) < 1e-6
    if empty.any():
        W[empty] = seed[empty]
        method += "+%d by distance" % int(empty.sum())
    # a leg's vertex belongs to its own leg: heat bleeds between the forelegs where they stand
    # close, and a planted hoof then drags its neighbour
    W = _keep_to_own_leg(verts, W, skel, bones)
    W = bodylib.smooth_weights(W, tris, iters=3)
    W = bodylib.limit_influences(W, 4)
    bodylib.apply_weight_matrix(ob, bones, W)
    if not any(m.type == 'ARMATURE' for m in ob.modifiers):
        mod = ob.modifiers.new("Armature", 'ARMATURE')
        mod.object = arm
    ob.parent = arm
    return method


def _keep_to_own_leg(verts, W, skel, bones):
    s = skel.props.withers / quad.DEFAULT_WITHERS
    low = verts[:, 2] < skel.J["Humerus.L"][2] - 0.10 * s
    idx = {b: i for i, b in enumerate(bones)}
    for foot in quad.FEET:
        side = foot[1]
        fore = foot[0] == "F"
        mine = [idx[b] for b in quad.foot_bones(foot)]
        other_side = [idx[quad.mirror_name(b)] for b in quad.foot_bones(foot)]
        other_end = [idx[b] for b in quad.foot_bones(("H" if fore else "F") + side)]
        sx = 1.0 if side == "L" else -1.0
        mid_y = 0.5 * (skel.J["Forearm.L"][1] + skel.J["Gaskin.L"][1])
        sel = low & (np.sign(verts[:, 0]) == sx) & ((verts[:, 1] < mid_y) if fore else (verts[:, 1] >= mid_y))
        for j in other_side + other_end:
            W[sel, j] = 0.0
        del mine
    # the barrel is the trunk's: bone heat gave the belly to the thighs and the upper arms, and a
    # gathered gallop, which swings the hind legs forward under it, dragged the belly with them
    J = skel.J
    v = verts
    def ramp(x, a, b):
        return np.clip((x - a) / (b - a), 0.0, 1.0)
    # ahead of the stifle, above the stifle, and inboard of the thigh's outside: barrel, not thigh
    hind_keep = 1.0 - ramp(J["Gaskin.L"][1] - v[:, 1], 0.02 * s, 0.16 * s) * ramp(v[:, 2], J["Gaskin.L"][2] - 0.02 * s, J["Gaskin.L"][2] + 0.10 * s)
    # behind the elbow and above it: barrel, not upper arm
    fore_keep = 1.0 - ramp(v[:, 1] - J["Forearm.L"][1], 0.04 * s, 0.18 * s) * ramp(v[:, 2], J["Forearm.L"][2] - 0.02 * s, J["Forearm.L"][2] + 0.10 * s)
    for side in ("L", "R"):
        for b in ("Thigh", "Gaskin"):
            W[:, idx["%s.%s" % (b, side)]] *= hind_keep
        for b in ("Scapula", "Humerus", "Forearm"):
            W[:, idx["%s.%s" % (b, side)]] *= fore_keep
    trunk = [idx["Spine1"], idx["Spine2"], idx["Chest"], idx["Hips"]]
    lost = W.sum(axis=1) < 1e-6
    if lost.any():
        seed = bodylib.segment_weights(v[lost], skel, [bones[i] for i in trunk], sharpness=2.6)
        for k, i in enumerate(trunk):
            W[lost, i] = seed[:, k]
    return W / np.maximum(W.sum(axis=1, keepdims=True), 1e-9)


def skin_to_body(ob, arm, body_verts, body_W, bones=quad.DEFORM_NAMES):
    bodylib.transfer_weights(ob, body_verts, body_W, arm, bones=bones, k=4, smooth=1)


# --------------------------------------------------------------------------------------
# paint
# --------------------------------------------------------------------------------------

def coat_paint(skel, field: sdf.SampledField, seed: int = 7):
    n1 = paint.Noise(seed, 64)
    n2 = paint.Noise(seed + 11, 64)
    n3 = paint.Noise(seed + 23, 64)
    s = skel.props.withers / quad.DEFAULT_WITHERS
    C = {k: np.array(v) for k, v in COAT.items()}

    def flow(P):
        # the coat lies back along the body and down the legs and the neck
        f = np.tile(np.array([0.0, 1.0, -0.35]), (len(P), 1))
        legs = P[:, 2] < skel.J["Humerus.L"][2] - 0.05 * s
        f[legs] = np.array([0.0, 0.1, -1.0])
        neck = P[:, 1] < skel.J["Neck1"][1]
        f[neck] = np.array([0.0, 0.6, -1.0])
        return f

    def grain(P, nrm):
        f = paint.strand_directions(P, nrm, flow)
        Q = P - f * np.sum(P * f, axis=1, keepdims=True)
        return n2.fbm(Q, freq=160.0 / s, octaves=2), n3.at(Q, 600.0 / s)

    def albedo(P, nrm):
        R = hb.regions(skel, P)
        occ = paint.sdf_occlusion(field, P, nrm, radius=0.10 * s, samples=5, strength=1.1)
        big = n1.fbm(P, freq=2.2 / s, octaves=3)
        clump, strand = grain(P, nrm)
        up = np.clip(nrm[:, 2], -1, 1)
        c = np.broadcast_to(C["body"], (len(P), 3)).copy()
        # blocks of colour: sun-dark along the top, pale underneath, a soft sheen on the flank
        c = paint.mix(c, C["shade"], np.clip(0.55 * paint.smoothstep(0.2, 0.9, up) * (0.6 + 0.8 * big), 0, 1))
        c = paint.mix(c, C["light"], np.clip(0.75 * (1.0 - paint.smoothstep(-0.8, -0.2, up)) + 0.6 * R["belly"], 0, 1))
        c = paint.mix(c, C["light"], 0.25 * paint.smoothstep(0.55, 0.8, big))
        # dapples: a cob in good condition shows faint rings on the quarters
        dap = n2.fbm(P, freq=9.0 / s, octaves=2)
        quarters = paint.smoothstep(0.1 * s, 0.5 * s, P[:, 1]) * paint.smoothstep(0.0, 0.5, up + 0.3)
        c = paint.mix(c, C["light"], 0.18 * quarters * paint.smoothstep(0.52, 0.66, dap))
        # the dun's dark points: legs, dorsal stripe, mane, tail; the face a shade darker
        c = paint.mix(c, C["points"], np.clip(R["points"] * (0.85 + 0.15 * big), 0, 1))
        c = paint.mix(c, C["points"] * 1.3, R["dorsal"] * 0.85)
        # zebra bars on the forearms and gaskins, the primitive dun marking, faint
        bars = 0.5 + 0.5 * np.sin(P[:, 2] * 70.0 / s + n1.at(P, 8.0) * 2.0)
        legband = paint.smoothstep(0.30 * s, 0.45 * s, P[:, 2]) * (1.0 - paint.smoothstep(0.62 * s, 0.85 * s, P[:, 2]))
        c = paint.mix(c, C["points"], 0.16 * legband * paint.smoothstep(0.8, 0.97, bars))
        hair = np.clip(R["mane"] + R["tail"] + R["feather"], 0, 1)
        hair_col = C["points"] * (0.8 + 0.6 * clump[:, None]) + 0.06 * paint.smoothstep(0.5, 0.95, up)[:, None]
        c = paint.mix(c, hair_col, hair)
        c = paint.mix(c, C["muzzle"], R["muzzle"] * 0.9)
        c = paint.mix(c, C["points"] * 1.1, R["ear"] * 0.8)
        hoof_col = C["hoof"] * (0.8 + 0.5 * n2.at(P * np.array([30.0, 30.0, 3.0]) / s, 1.0)[:, None])
        c = paint.mix(c, hoof_col, R["hoof"])
        c = paint.mix(c, C["eye"], R["eye"])
        # the coat's grain, and value from the shape: dark in the creases, light on what stands out
        v = 0.90 + 0.14 * (clump - 0.5) + 0.05 * (strand - 0.5)
        v = v * (0.55 + 0.45 * occ) + 0.12 * paint.exposure(occ, 4.0) * paint.smoothstep(-0.1, 0.6, up)
        return np.clip(c * v[:, None], 0, 1)

    def orm(P, nrm):
        R = hb.regions(skel, P)
        occ = paint.sdf_occlusion(field, P, nrm, radius=0.10 * s, samples=5, strength=1.1)
        rough = 0.62 - 0.10 * R["hoof"] - 0.45 * R["eye"] + 0.1 * R["mane"] + 0.08 * R["tail"]
        return np.stack([0.5 + 0.5 * occ, np.clip(rough, 0.08, 0.95), np.zeros(len(P))], axis=1)

    def height(P, nrm):
        clump, strand = grain(P, nrm)
        R = hb.regions(skel, P)
        hairy = np.clip(R["mane"] + R["tail"] + R["feather"], 0, 1)
        return (0.3 + 0.7 * hairy) * (0.6 * clump + 0.4 * strand)

    return albedo, orm, height


def tack_paint(skel, pieces: dict, seed: int = 9):
    """pieces: name -> (field, region); eyes are found by distance to the eye centres."""
    n1 = paint.Noise(seed, 64)
    n2 = paint.Noise(seed + 5, 64)
    s = skel.props.withers / quad.DEFAULT_WITHERS
    T = {k: np.array(v) for k, v in TACK.items()}
    eyes = [hb.eye_centre(skel, 1.0), hb.eye_centre(skel, -1.0)]
    seat = hb.saddle_point(skel)

    def which(P):
        names = list(pieces.keys())
        D = np.stack([pieces[n][0].eval(P) for n in names], axis=1)
        k = np.argmin(D, axis=1)
        reg = np.array([pieces[n][1] for n in names])[k]
        e = np.minimum(np.linalg.norm(P - eyes[0], axis=1), np.linalg.norm(P - eyes[1], axis=1))
        reg = np.where(e < 0.04 * s, "eye", reg)
        return reg

    def albedo(P, nrm):
        reg = which(P)
        big = n1.fbm(P, freq=6.0 / s, octaves=3)
        fine = n2.fbm(P, freq=80.0 / s, octaves=2)
        up = np.clip(nrm[:, 2], -1, 1)
        c = np.zeros((len(P), 3))
        lea = reg == "leather"
        if lea.any():
            v = (0.8 + 0.4 * big[lea] + 0.12 * (fine[lea] - 0.5))
            col = T["leather"] * v[:, None]
            # worn light where it rubs and where the sun has had it
            col = paint.mix(col, T["leather_edge"], 0.45 * paint.smoothstep(0.55, 0.85, fine[lea]) * paint.smoothstep(0.2, 0.9, up[lea]))
            c[lea] = col
        clo = reg == "cloth"
        if clo.any():
            p = P[clo]
            # the border and the stripe: by distance from the cloth's edge, found as depth below
            # the seat and distance behind it
            d_down = seat[2] - p[:, 2]
            d_back = np.abs(p[:, 1] - (seat[1] + 0.06 * s))
            # the cloth hangs from under the saddle (d_down about 0.10) to its hem (about 0.56): a
            # narrow ochre border at the hem and the back edge, one stripe inside it
            edge = np.maximum(paint.smoothstep(0.515 * s, 0.53 * s, d_down), paint.smoothstep(0.285 * s, 0.30 * s, d_back))
            stripe = 1.0 - paint.smoothstep(0.004 * s, 0.009 * s, np.abs(d_down - 0.475 * s))
            weave = 0.5 + 0.5 * np.sin(p[:, 1] * 900.0 / s) * np.sin(p[:, 2] * 900.0 / s)
            col = paint.mix(np.broadcast_to(T["cloth"], (len(p), 3)), T["cloth_border"], np.clip(edge + stripe, 0, 1))
            col = col * (0.85 + 0.25 * big[clo] + 0.06 * weave)[:, None]
            # bleached where the sun lies on it, darker where it is sweated under the saddle
            col = paint.mix(col, col * 1.25 + 0.05, 0.3 * paint.smoothstep(0.3, 0.9, up[clo]))
            c[clo] = col
        irn = reg == "iron"
        if irn.any():
            c[irn] = T["iron"] * (0.8 + 0.5 * fine[irn])[:, None]
        eye = reg == "eye"
        if eye.any():
            c[eye] = T["eye"] + 0.05 * paint.smoothstep(0.6, 0.9, up[eye])[:, None]
        return np.clip(c, 0, 1)

    def orm(P, nrm):
        reg = which(P)
        rough = np.full(len(P), 0.55)
        met = np.zeros(len(P))
        rough[reg == "cloth"] = 0.92
        rough[reg == "iron"] = 0.42
        met[reg == "iron"] = 0.85
        rough[reg == "eye"] = 0.06
        return np.stack([np.ones(len(P)), rough, met], axis=1)

    return albedo, orm


def bake_maps(ob, out_dir, stem, albedo_fn, orm_fn, height_fn=None, size=TEX, background=(0.5, 0.4, 0.3)):
    maps = paint.surface_maps(ob, size=size, pad=4)
    a = paint.paint(maps, albedo_fn, background=background)
    o = paint.paint(maps, orm_fn, background=(1.0, 0.6, 0.0))
    a_path = paint.save_png(a, os.path.join(out_dir, "%s_albedo.png" % stem))
    o_path = paint.save_png(o, os.path.join(out_dir, "%s_orm.png" % stem))
    n_path = None
    if height_fn is not None:
        h = np.zeros((size, size))
        m = maps["mask"]
        h[m] = height_fn(maps["pos"][m], maps["nrm"][m])
        n_path = paint.save_png(cf.normal_from_height(h, strength=0.02), os.path.join(out_dir, "%s_normal.png" % stem))
    return a_path, o_path, n_path


# --------------------------------------------------------------------------------------
# clips
# --------------------------------------------------------------------------------------

def bake_clips(arm, skel, only=None) -> dict:
    solver = qc.make_solver(skel)
    clips = qc.build_clips(solver)
    problems = qc.check_contract(clips)
    if problems:
        for p in problems:
            log("CONTRACT: %s" % p)
        raise SystemExit("the mount's clips break CONTRACTS §3b")
    sidecar = {}
    t0 = time.time()
    for name in qc.MOUNT_CLIPS:
        if only and name not in only:
            continue
        baked = clips[name].bake(solver)
        cf.push_clip(arm, baked)
        sidecar[name] = baked.sidecar()
    log("baked %d clips in %.1fs (worst reach %.3f m)" % (len(sidecar), time.time() - t0, solver.reach_error))
    return sidecar


# --------------------------------------------------------------------------------------
# commands
# --------------------------------------------------------------------------------------

def clean_mesh(ob) -> None:
    """Degenerate faces and loose bits out, and the mesh validated: the glTF exporter drops a mesh
    it judges invalid (with a warning and nothing else), which is what the joined tack was."""
    import bpy
    bodylib.select_only(ob)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.dissolve_degenerate(threshold=1e-5)
    bpy.ops.mesh.delete_loose()
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.quads_convert_to_tris(quad_method='BEAUTY', ngon_method='BEAUTY')
    bpy.ops.object.mode_set(mode='OBJECT')
    changed = ob.data.validate(verbose=True, clean_customdata=True)
    if changed:
        log("%s: validate fixed its mesh" % ob.name)


def decimate_to(ob, target: int) -> None:
    """Down to about `target` triangles: the collapse stops short on many small pieces, so it is
    asked again, without symmetry, until it gets there or stops moving."""
    bodylib.decimate(ob, target, symmetry=True)
    for _ in range(3):
        n = bodylib.tri_count(ob)
        if n <= target * 1.1:
            return
        bodylib.decimate(ob, target, symmetry=False)
        if bodylib.tri_count(ob) >= n * 0.98:
            return


def duplicate_joined(objs, name):
    import bpy
    bpy.ops.object.select_all(action='DESELECT')
    copies = []
    for o in objs:
        c = o.copy()
        c.data = o.data.copy()
        bpy.context.collection.objects.link(c)
        copies.append(c)
    bodylib.join_into(copies[0], copies[1:])
    copies[0].name = name
    copies[0].data.name = name
    return copies[0]


def cmd_build(args) -> None:
    import bpy
    t0 = time.time()
    cf.reset_scene()
    out_dir = cf.ensure_dir(args.out or os.path.join(OUT_ROOT, NAME))
    skel = quad.QuadSkeleton()
    style = hb.HorseStyle()
    arm = quad.build_armature(skel, name="Armature")
    log("armature: %d bones" % len(arm.data.bones))
    spacing = 0.016 if args.quick else 0.010
    grid = []
    body = mesh_object("Horse_Body", hb.horse_scene(skel, style), spacing, BODY_TRIS, grid_out=grid)
    clean_mesh(body)
    field = sdf.SampledField.from_grid(*grid)
    log("body: %d tris (%.0fs)" % (bodylib.tri_count(body), time.time() - t0))
    bodylib.smart_uv(body, angle_deg=60.0, margin=0.008)
    method = skin_body(body, arm, skel)
    log("body weights: %s" % method)
    bv, _, _ = bodylib.mesh_arrays(body)
    bW = bodylib.weight_matrix(body, quad.DEFORM_NAMES)

    # the tack, one object: its pieces meshed apart and joined
    scenes = hb.tack_scenes(skel, field)
    budgets = {"cloth": 700, "saddle": 1500, "straps": 800, "irons": 700, "bridle": 1500}
    pieces = []
    piece_fields = {}
    for name, sc in scenes.items():
        g = []
        ob = mesh_object("Tack_%s" % name, sc, 0.009 if args.quick else 0.0045, budgets[name], grid_out=g, smooth_iters=3)
        if ob is None:
            log("tack %s: empty" % name)
            continue
        piece_fields[name] = (sdf.SampledField.from_grid(*g), hb.tack_region(name))
        pieces.append(ob)
        log("tack %s: %d tris" % (name, bodylib.tri_count(ob)))
    eyes = eye_objects(skel)
    tack = pieces[0]
    bodylib.join_into(tack, pieces[1:] + eyes)
    tack.name = "Horse_Tack"
    tack.data.name = "Horse_Tack"
    clean_mesh(tack)
    bodylib.smart_uv(tack, angle_deg=60.0, margin=0.01)
    skin_to_body(tack, arm, bv, bW)
    # the eyes go with the head, whatever the nearest skin says
    log("tack: %d tris" % bodylib.tri_count(tack))

    size = 512 if args.quick else TEX
    a, o, n = bake_maps(body, out_dir, "%s_coat" % NAME, *coat_paint(skel, field), size=size)
    body.data.materials.append(cf.make_material("WM_Horse_Coat", a, o, n, roughness=0.6))
    ta, to, _ = bake_maps(tack, out_dir, "%s_tack" % NAME, *tack_paint(skel, piece_fields), size=size)
    tack.data.materials.append(cf.make_material("WM_Horse_Tack", ta, to, None, roughness=0.6))
    log("painted (%.0fs)" % (time.time() - t0))

    lods = []
    for lname, target in (("Horse_LOD1", LOD1_TRIS), ("Horse_LOD2", LOD2_TRIS)):
        # LOD2 from LOD1: collapsed from the full mesh at a fourteenth, the tack's many small
        # shells stopped the decimator at three times the budget
        lob = duplicate_joined([body, tack] if not lods else [lods[-1]], lname)
        decimate_to(lob, target)
        clean_mesh(lob)
        lods.append(lob)
        log("%s: %d tris" % (lname, bodylib.tri_count(lob)))

    sidecar = {} if args.no_clips else bake_clips(arm, skel)
    objs = [arm, body, tack] + lods
    glb = cf.export_glb(os.path.join(out_dir, "%s.glb" % NAME), objs, with_animation=bool(sidecar))
    with open(os.path.join(out_dir, "%s.clips.json" % NAME), "w") as f:
        json.dump(sidecar, f, indent=1, sort_keys=True)
    tris = [bodylib.tri_count(body) + bodylib.tri_count(tack)] + [bodylib.tri_count(l) for l in lods]
    bounds = cf.object_bounds(body)
    cf.write_meta(os.path.join(out_dir, "%s.meta.json" % NAME), NAME,
                  {"proportions": skel.props.to_dict(), "style": style.to_dict(), "coat": COAT, "tack": TACK},
                  tris, collision="capsule", bounds=bounds, seed=7,
                  extra={"generator": GENERATOR, "version": VERSION, "rig": quad.RIG_ID,
                         "clips": sorted(sidecar.keys()), "bones": len(arm.data.bones),
                         "sockets": {k: [round(float(x), 4) for x in skel.bones[k].head] for k in quad.SOCKET_BONES},
                         "rig_manifest": quad.rig_manifest(skel)})
    log("wrote %s: %s tris, in %.0fs" % (glb, tris, time.time() - t0))


SHEEP = "sheep_ewe"
SHEEP_TRIS = 5200
SHEEP_LOD1 = 1800
SHEEP_LOD2 = 600
SHEEP_TEX = 512
FLEECE = {"wool": (0.87, 0.83, 0.74), "wool_shade": (0.66, 0.60, 0.50), "wool_tip": (0.95, 0.93, 0.86),
          "dark": (0.16, 0.13, 0.12), "white": (0.86, 0.80, 0.72), "hoof": (0.18, 0.16, 0.15), "eye": (0.10, 0.08, 0.04),
          "nose": (0.10, 0.08, 0.08)}


def sheep_paint(skel, field: sdf.SampledField, style, seed: int = 5):
    """A ewe's paint: cream wool in locks, sun-warm on the back, grey-brown in the creases between
    locks and under the belly; the face, ears and legs black (or white, for a white-faced ewe),
    with a lighter nose and dark hooves."""
    n1 = paint.Noise(seed, 64)
    n2 = paint.Noise(seed + 7, 64)
    C = {k: np.array(v) for k, v in FLEECE.items()}
    skin = C["dark"] if style.face == "dark" else C["white"]

    def albedo(P, nrm):
        R = sb.regions(skel, P, style)
        occ = paint.sdf_occlusion(field, P, nrm, radius=0.05, samples=4, strength=1.2)
        up = np.clip(nrm[:, 2], -1, 1)
        curl = n2.fbm(P, freq=55.0, octaves=3)
        big = n1.fbm(P, freq=5.0, octaves=2)
        c = np.broadcast_to(C["wool"], (len(P), 3)).copy()
        c = paint.mix(c, C["wool_tip"], 0.5 * paint.smoothstep(0.45, 0.8, curl) * paint.smoothstep(-0.2, 0.7, up))
        c = paint.mix(c, C["wool_shade"], np.clip(0.8 * (1.0 - occ) + 0.4 * (1.0 - paint.smoothstep(-0.9, -0.2, up)), 0, 1))
        c = c * (0.9 + 0.2 * big)[:, None]
        k = np.clip(R["skin"], 0, 1)
        skin_c = skin * (0.85 + 0.3 * n1.fbm(P, freq=20.0, octaves=2))[:, None]
        c = paint.mix(c, skin_c, k)
        c = paint.mix(c, C["nose"] if style.face == "dark" else C["dark"] * 2.0, R["nose"] * 0.6)
        c = paint.mix(c, C["hoof"], R["hoof"])
        c = paint.mix(c, C["eye"], R["eye"])
        return np.clip(c * (0.6 + 0.4 * occ)[:, None], 0, 1)

    def orm(P, nrm):
        R = sb.regions(skel, P, style)
        occ = paint.sdf_occlusion(field, P, nrm, radius=0.05, samples=4, strength=1.2)
        rough = 0.9 - 0.3 * R["skin"] - 0.6 * R["eye"]
        return np.stack([0.5 + 0.5 * occ, np.clip(rough, 0.1, 0.95), np.zeros(len(P))], axis=1)

    def height(P, nrm):
        R = sb.regions(skel, P, style)
        return R["wool"] * n2.fbm(P, freq=70.0, octaves=3)

    return albedo, orm, height


def cmd_sheep(args) -> None:
    """The ewe on WM_Quadruped_v1: body, LODs, paint, skin and her clips, one GLB."""
    t0 = time.time()
    cf.reset_scene()
    out_dir = cf.ensure_dir(args.out or os.path.join(OUT_ROOT, SHEEP))
    skel = quad.QuadSkeleton(sb.EWE)
    style = sb.SheepStyle(face=args.face)
    arm = quad.build_armature(skel, name="Armature")
    grid = []
    body = mesh_object("Sheep_Body", sb.sheep_scene(skel, style), 0.009 if args.quick else 0.0055, SHEEP_TRIS, grid_out=grid)
    clean_mesh(body)
    field = sdf.SampledField.from_grid(*grid)
    log("sheep body: %d tris (%.0fs)" % (bodylib.tri_count(body), time.time() - t0))
    bodylib.smart_uv(body, angle_deg=60.0, margin=0.01)
    log("sheep weights: %s" % skin_body(body, arm, skel))
    a, o, n = bake_maps(body, out_dir, SHEEP, *sheep_paint(skel, field, style), size=256 if args.quick else SHEEP_TEX)
    body.data.materials.append(cf.make_material("WM_Sheep_Fleece", a, o, n, roughness=0.9))
    lods = []
    for lname, target in (("Sheep_Body_LOD1", SHEEP_LOD1), ("Sheep_Body_LOD2", SHEEP_LOD2)):
        lob = duplicate_joined([body if not lods else lods[-1]], lname)
        decimate_to(lob, target)
        clean_mesh(lob)
        lods.append(lob)
        log("%s: %d tris" % (lname, bodylib.tri_count(lob)))
    solver = qc.make_solver(skel)
    clips = qc.build_sheep_clips(solver)
    sidecar = {}
    for name in qc.SHEEP_CLIPS:
        baked = clips[name].bake(solver)
        cf.push_clip(arm, baked)
        sidecar[name] = baked.sidecar()
    glb = cf.export_glb(os.path.join(out_dir, "%s.glb" % SHEEP), [arm, body] + lods, with_animation=True)
    with open(os.path.join(out_dir, "%s.clips.json" % SHEEP), "w") as f:
        json.dump(sidecar, f, indent=1, sort_keys=True)
    tris = [bodylib.tri_count(body)] + [bodylib.tri_count(l) for l in lods]
    cf.write_meta(os.path.join(out_dir, "%s.meta.json" % SHEEP), SHEEP,
                  {"proportions": skel.props.to_dict(), "style": style.to_dict(), "fleece": FLEECE},
                  tris, collision="none", bounds=cf.object_bounds(body), seed=style.seed,
                  extra={"generator": GENERATOR, "version": VERSION, "rig": quad.RIG_ID,
                         "clips": sorted(sidecar.keys()), "bones": len(arm.data.bones)})
    log("wrote %s: %s tris, in %.0fs" % (glb, tris, time.time() - t0))


def cmd_clips(args) -> None:
    t0 = time.time()
    cf.reset_scene()
    skel = quad.QuadSkeleton()
    arm = quad.build_armature(skel, name="Armature")
    sidecar = bake_clips(arm, skel)
    os.makedirs(args.out, exist_ok=True)
    glb = cf.export_glb(os.path.join(args.out, "%s_clips.glb" % NAME), [arm], with_animation=True)
    with open(os.path.join(args.out, "%s.clips.json" % NAME), "w") as f:
        json.dump(sidecar, f, indent=1, sort_keys=True)
    log("baked %d clips onto the bare armature in %.1fs: %s" % (len(sidecar), time.time() - t0, glb))


def main(argv=None) -> int:
    if argv is None:
        argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    ap = argparse.ArgumentParser(prog="horse_forge")
    ap.add_argument("command", nargs="?", default="build", choices=["build", "clips", "sheep"])
    ap.add_argument("--face", default="dark", choices=["dark", "white"])
    ap.add_argument("--out", default="")
    ap.add_argument("--quick", action="store_true", help="coarse mesh and half-size maps, for looking")
    ap.add_argument("--no-clips", action="store_true")
    args = ap.parse_args(list(argv))
    if not cf.HAVE_BPY:
        raise SystemExit("horse_forge must run inside Blender")
    if args.command == "sheep":
        cmd_sheep(args)
    elif args.command == "clips":
        if not args.out:
            raise SystemExit("clips needs --out")
        cmd_clips(args)
    else:
        cmd_build(args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
