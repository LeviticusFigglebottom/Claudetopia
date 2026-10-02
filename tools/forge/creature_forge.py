#!/usr/bin/env python3
"""The creature forge: the country's common foes, rigged and animated (lib/foe_specs.py).

    blender -b --python tools/forge/creature_forge.py -- <foe> [--out DIR] [--quick] [--no-clips]
    blender -b --python tools/forge/creature_forge.py -- --list

Each foe is built the way the horse and the deer are (horse_forge.py): a signed-distance body meshed
by surface nets and decimated, unwrapped, skinned by bone heat with the forge's corrections, painted
texel by texel from its 3D points (lib/foe_paint.py), two far levels of detail, and its clips
(lib/foe_clips.py, or the family's own) baked as one NLA track each.

Output (CONTRACTS §4), in game/assets/models/creatures/<foe>/:
    <foe>.glb            the armature, <Foe>_Body (LOD0), <Foe>_Body_LOD1, <Foe>_Body_LOD2, the clips
    <foe>.clips.json     the clips' sidecar: length, loop, events, a gait's `speed`
    <foe>_hide_{albedo,orm,normal}.png
    <foe>.meta.json      what it is: the rig, the def scale it was built for, its hurt volumes
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
for p in (HERE, os.path.dirname(HERE)):
    if p not in sys.path:
        sys.path.insert(0, p)

import numpy as np  # noqa: E402

import character_forge as cf  # noqa: E402
import horse_forge as hf  # noqa: E402
from forge.lib import sdf  # noqa: E402
from forge.lib import body as bodylib  # noqa: E402
from forge.lib import quadruped as quad  # noqa: E402
from forge.lib import foe_specs  # noqa: E402
from forge.lib import foe_paint  # noqa: E402
from forge.lib import beast_body as bb  # noqa: E402

OUT_ROOT = os.path.join(cf.ROOT, "game", "assets", "models", "creatures")
GENERATOR = "creature_forge"
VERSION = 1


def log(msg: str) -> None:
    print("[creature] %s" % msg, flush=True)


def cap(name: str) -> str:
    return "".join(w.capitalize() for w in name.split("_"))


def godot(p) -> list:
    """Blender space to the GLB's (Godot's): x, z, -y."""
    return [round(float(p[0]), 4), round(float(p[2]), 4), round(float(-p[1]), 4)]


# --------------------------------------------------------------------------------------
# skinning: the quadruped's, and the jaw its own
# --------------------------------------------------------------------------------------

def jaw_weights(ob, skel, style, bones) -> None:
    """Everything under the mouth's cut and forward of its corner is the jaw's, wholly: bone heat
    shares the lower jaw with the head, and an open bite then stretches the lips into a web."""
    verts, _, _ = bodylib.mesh_arrays(ob)
    W = bodylib.weight_matrix(ob, bones)
    corner, tip = bb.mouth_line(skel, style)
    poll, hu, dn, hl = bb.head_axes(skel)
    along = tip - corner
    L = float(np.linalg.norm(along))
    d_al = along / L
    n = dn - d_al * float(dn @ d_al)
    n = n / np.linalg.norm(n)
    rel = verts - corner
    u = (rel @ d_al) / L
    below = rel @ n
    k = bb.head_k(skel)
    near = np.linalg.norm(rel - np.outer(rel @ d_al, d_al) - np.outer(below, n), axis=1) < 0.07 * k
    jw = bb.sm(-0.003 * k, 0.003 * k, below) * bb.sm(-0.35, 0.02, u) * near * (u < 1.3)
    # the lower jaw's back, under the cheek, belongs with it as far as the hinge
    hinge = skel.J["Jaw"]
    jw = np.maximum(jw, near * bb.sm(-0.003 * k, 0.004 * k, below) * (1.0 - bb.sm(0.03 * k, 0.05 * k, np.linalg.norm(verts - hinge, axis=1))) * 0.6)
    head = bones.index("Head")
    jaw = bones.index("Jaw")
    # the upper jaw ahead of the eyes is the head's alone
    hw = bb.sm(0.2, 0.5, u) * near * (1.0 - jw)
    W = W * (1.0 - hw)[:, None]
    W[:, head] += hw
    W = W * (1.0 - jw)[:, None]
    W[:, jaw] += jw
    W = W / np.maximum(W.sum(axis=1, keepdims=True), 1e-9)
    bodylib.apply_weight_matrix(ob, bones, W)


def skin(ob, arm, sp) -> str:
    method = hf.skin_body(ob, arm, sp.skel)
    if method.startswith("segment") and sp.family == "canid":
        # bone heat does not solve over a hull broken by thorns and plates: solve it on the bare
        # dog under them and give each vertex its nearest bare neighbours' weights
        import bpy
        bare = bb.CanidStyle(**{**sp.style.to_dict(), "thorns": 0.0, "bark": 0.0, "fur": 0.0})
        proxy = hf.mesh_object("Proxy", bb.canid_scene(sp.skel, bare, sp.extra["trunk"]), sp.spacing * 1.4, 5000)
        hf.clean_mesh(proxy)
        pm = hf.skin_body(proxy, arm, sp.skel)
        if not pm.startswith("segment"):
            pv, _, _ = bodylib.mesh_arrays(proxy)
            pW = bodylib.weight_matrix(proxy, quad.DEFORM_NAMES)
            for g in list(ob.vertex_groups):
                ob.vertex_groups.remove(g)
            hf.skin_to_body(ob, arm, pv, pW)
            method = "heat on the bare body (%s), carried over" % pm
        bpy.data.objects.remove(proxy, do_unlink=True)
    if sp.family == "canid":
        jaw_weights(ob, sp.skel, sp.style, quad.DEFORM_NAMES)
    return method


# --------------------------------------------------------------------------------------
# hurt volumes
# --------------------------------------------------------------------------------------

def hurt_volumes(sp, body) -> list:
    """Where a blow lands on it, in the model's own (Godot) space at rest: the trunk as a capsule
    lying along it, the head as a sphere. CreatureModel lays the actor's hurtbox on these."""
    J = sp.skel.J
    verts, _, _ = bodylib.mesh_arrays(body)
    trunk = sp.extra.get("trunk")
    if sp.family in ("canid", "boar", "reptile") and trunk:
        ys = [t[0] for t in trunk]
        mid = [0.5 * (t[1] + t[2]) for t in trunk]
        half = max(0.5 * (t[1] - t[2]) for t in trunk)
        r = half * 0.95
        a = np.array([0.0, ys[0] + r, float(np.interp(ys[0] + r, ys, mid))])
        b = np.array([0.0, ys[-1] - r * 0.6, float(np.interp(ys[-1] - r * 0.6, ys, mid))])
        poll, hu, dn, hl = bb.head_axes(sp.skel)
        head_c = poll + hu * hl * 0.45 + dn * 0.03 * bb.head_k(sp.skel)
        return [{"kind": "capsule", "a": godot(a), "b": godot(b), "r": round(float(r), 4)},
                {"kind": "sphere", "c": godot(head_c), "r": round(float(0.42 * hl), 4)}]
    lo, hi = verts.min(axis=0), verts.max(axis=0)
    c = 0.5 * (lo + hi)
    r = 0.5 * float(min(hi[0] - lo[0], hi[1] - lo[1]))
    return [{"kind": "capsule", "a": godot([c[0], c[1], lo[2] + r]), "b": godot([c[0], c[1], hi[2] - r]), "r": round(r, 4)}]


# --------------------------------------------------------------------------------------
# the build
# --------------------------------------------------------------------------------------

def bake_foe_clips(arm, sp) -> dict:
    from forge.lib import foe_clips
    clips = foe_clips.build(sp)
    solver = foe_clips.make_solver(sp.skel)
    sidecar = {}
    t0 = time.time()
    for name in sorted(clips):
        baked = clips[name].bake(solver)
        cf.push_clip(arm, baked)
        sidecar[name] = baked.sidecar()
    log("baked %d clips in %.1fs (worst reach %.3f m)" % (len(sidecar), time.time() - t0, solver.reach_error))
    return sidecar


def build(name: str, args) -> None:
    t0 = time.time()
    cf.reset_scene()
    sp = foe_specs.spec(name)
    C = cap(name)
    out_dir = cf.ensure_dir(args.out or os.path.join(OUT_ROOT, name))
    arm = quad.build_armature(sp.skel, name="Armature")
    log("%s: armature %d bones" % (name, len(arm.data.bones)))
    grid = []
    spacing = sp.spacing * (1.8 if args.quick else 1.0)
    body = hf.mesh_object("%s_Body" % C, sp.scene(), spacing, sp.tris, grid_out=grid)
    hf.clean_mesh(body)
    hf.decimate_to(body, sp.tris)
    field = sdf.SampledField.from_grid(*grid)
    log("body: %d tris (%.0fs)" % (bodylib.tri_count(body), time.time() - t0))
    bodylib.smart_uv(body, angle_deg=60.0, margin=0.008)
    log("weights: %s" % skin(body, arm, sp))
    size = 256 if args.quick else sp.tex
    albedo, orm, height = foe_paint.painter(sp, field)
    a, o, n = hf.bake_maps(body, out_dir, "%s_hide" % name, albedo, orm, height, size=size)
    half_size(o, n)
    body.data.materials.append(cf.make_material("WM_%s_Hide" % C, a, o, n, roughness=0.8))
    log("painted (%.0fs)" % (time.time() - t0))
    lods = []
    for lname, target in (("%s_Body_LOD1" % C, sp.lod1), ("%s_Body_LOD2" % C, sp.lod2)):
        lob = hf.duplicate_joined([body if not lods else lods[-1]], lname)
        hf.decimate_to(lob, target)
        hf.clean_mesh(lob)
        lods.append(lob)
        log("%s: %d tris" % (lname, bodylib.tri_count(lob)))
    sidecar = {} if args.no_clips else bake_foe_clips(arm, sp)
    glb = cf.export_glb(os.path.join(out_dir, "%s.glb" % name), [arm, body] + lods, with_animation=bool(sidecar))
    with open(os.path.join(out_dir, "%s.clips.json" % name), "w") as f:
        json.dump(sidecar, f, indent=1, sort_keys=True)
    tris = [bodylib.tri_count(body)] + [bodylib.tri_count(lo) for lo in lods]
    bounds = cf.object_bounds(body)
    cf.write_meta(os.path.join(out_dir, "%s.meta.json" % name), name,
                  {"style": sp.style.to_dict(), "family": sp.family},
                  tris, collision="capsule", bounds=bounds, seed=getattr(sp.style, "seed", 0),
                  extra={"generator": GENERATOR, "version": VERSION, "rig": quad.RIG_ID, "def_scale": sp.def_scale,
                         "clips": sorted(sidecar.keys()), "bones": len(arm.data.bones),
                         "hurt": hurt_volumes(sp, body), "mesh": "%s_Body" % C,
                         "height": round(float(bounds[5]), 4), "tint": sp.extra.get("tint", "#ffffff"),
                         "rig_manifest": quad.rig_manifest(sp.skel)})
    write_sidecars(out_dir, name)
    log("wrote %s: %s tris, in %.0fs" % (glb, tris, time.time() - t0))


def half_size(*paths) -> None:
    """The ORM and the normal at half the albedo's size (README, "Costs and weight"): both vary
    slowly over a body, and the downscale supersamples the relief rather than losing it."""
    from PIL import Image
    for p in paths:
        if p and os.path.exists(p):
            im = Image.open(p)
            if im.width > 256:
                im.resize((im.width // 2, im.height // 2), Image.LANCZOS).save(p, optimize=True)


def write_sidecars(out_dir: str, name: str) -> None:
    from pathlib import Path
    from forge.lib import export as E
    d = Path(out_dir)
    textures = sorted(p.name for p in d.glob("%s_*.png" % name))
    E.write_import_sidecars(d, "%s.glb" % name, textures)


def main(argv=None) -> int:
    if argv is None:
        argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    ap = argparse.ArgumentParser(prog="creature_forge")
    ap.add_argument("foes", nargs="*")
    ap.add_argument("--out", default="")
    ap.add_argument("--quick", action="store_true", help="coarse mesh and small maps, for looking")
    ap.add_argument("--no-clips", action="store_true")
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args(list(argv))
    if args.list:
        print("\n".join(foe_specs.FOES))
        return 0
    if not cf.HAVE_BPY:
        raise SystemExit("creature_forge must run inside Blender")
    for name in args.foes:
        build(name, args)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
