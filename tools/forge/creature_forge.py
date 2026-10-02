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
from forge.lib import creature_rig as cr  # noqa: E402

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

def jaw_weights(ob, sp, bones) -> None:
    """Everything under the mouth's cut and forward of its corner is the jaw's, wholly: bone heat
    shares the lower jaw with the head, and an open bite then stretches the lips into a web."""
    skel = sp.skel
    mod = sp.extra.get("module")
    if mod is not None and hasattr(mod, "mouth_line"):
        corner, tip = mod.mouth_line(skel)
        poll, hu, dn, hl = mod.head_axes(skel)
        k = hl / 0.29
    else:
        corner, tip = bb.mouth_line(skel, sp.style)
        poll, hu, dn, hl = bb.head_axes(skel)
        k = bb.head_k(skel)
    verts, _, _ = bodylib.mesh_arrays(ob)
    W = bodylib.weight_matrix(ob, bones)
    along = tip - corner
    L = float(np.linalg.norm(along))
    d_al = along / L
    n = dn - d_al * float(dn @ d_al)
    n = n / np.linalg.norm(n)
    rel = verts - corner
    u = (rel @ d_al) / L
    below = rel @ n
    reach = 0.07 * k if mod is None else 0.12 * k
    near = np.linalg.norm(rel - np.outer(rel @ d_al, d_al) - np.outer(below, n), axis=1) < reach
    # and only the head's: a foreleg standing under a low-carried head is not its jaw
    d_head, _ = bb._seg(verts, poll, poll + hu * hl)
    near = near & (d_head < 0.36 * hl)
    jw = bb.sm(-0.003 * k, 0.003 * k, below) * bb.sm(-0.35, 0.02, u) * near * (u < 1.3)
    hinge = skel.J["Jaw"]
    jw = np.maximum(jw, near * bb.sm(-0.003 * k, 0.004 * k, below) * (1.0 - bb.sm(0.03 * k, 0.05 * k, np.linalg.norm(verts - hinge, axis=1))) * 0.6)
    head = bones.index("Head")
    jaw = bones.index("Jaw")
    hw = bb.sm(0.2, 0.5, u) * near * (1.0 - jw)
    W = W * (1.0 - hw)[:, None]
    W[:, head] += hw
    W = W * (1.0 - jw)[:, None]
    W[:, jaw] += jw
    W = W / np.maximum(W.sum(axis=1, keepdims=True), 1e-9)
    bodylib.apply_weight_matrix(ob, bones, W)


def skin_free(ob, arm, rig, sp=None) -> str:
    """Bone heat where it solves -- on a bare proxy of the body when spines and bristles stop it
    solving on the body itself -- and the distance to the bones where it does not; smoothed and
    limited."""
    bones = rig.deform_names
    method = "heat"
    if not bodylib.auto_weights(ob, arm):
        method = "segment"
        mod = sp.extra.get("module") if sp is not None else None
        if mod is not None and hasattr(mod, "bare_scene"):
            import bpy
            proxy = hf.mesh_object("Proxy", mod.bare_scene(sp), sp.spacing * 1.3, 6000)
            hf.clean_mesh(proxy)
            bodylib.auto_weights(proxy, arm)
            pv, _, _ = bodylib.mesh_arrays(proxy)
            pW = bodylib.weight_matrix(proxy, bones)
            if float((pW.sum(axis=1) > 1e-6).mean()) > 0.95:
                hole = pW.sum(axis=1) < 1e-6
                if hole.any():
                    pW[hole] = cr.segment_weights(rig, pv[hole], spread=0.15)
                for g in list(ob.vertex_groups):
                    ob.vertex_groups.remove(g)
                bodylib.transfer_weights(ob, pv, pW, arm, bones=bones, k=4, smooth=1)
                method = "heat on the bare body, carried over"
            bpy.data.objects.remove(proxy, do_unlink=True)
    verts, _, tris = bodylib.mesh_arrays(ob)
    W = bodylib.weight_matrix(ob, bones)
    seed = cr.segment_weights(rig, verts, spread=0.15)
    empty = W.sum(axis=1) < 1e-6
    if empty.any():
        W[empty] = seed[empty]
        method += "+%d by distance" % int(empty.sum())
    W = bodylib.smooth_weights(W, tris, iters=2)
    W = bodylib.limit_influences(W, 4)
    bodylib.apply_weight_matrix(ob, bones, W)
    if not any(m.type == 'ARMATURE' for m in ob.modifiers):
        mod = ob.modifiers.new("Armature", 'ARMATURE')
        mod.object = arm
    ob.parent = arm
    return method


def skin(ob, arm, sp) -> str:
    if sp.family not in foe_specs.QUADS:
        return skin_free(ob, arm, sp.skel, sp)
    method = hf.skin_body(ob, arm, sp.skel)
    mod = sp.extra.get("module")
    if method.startswith("segment") and (sp.family == "canid" or (mod is not None and hasattr(mod, "bare_scene"))):
        # bone heat does not solve over a hull broken by thorns and plates: solve it on the bare
        # beast under them and give each vertex its nearest bare neighbours' weights
        import bpy
        if sp.family == "canid":
            bare = bb.CanidStyle(**{**sp.style.to_dict(), "thorns": 0.0, "bark": 0.0, "fur": 0.0})
            bare_sc = bb.canid_scene(sp.skel, bare, sp.extra["trunk"])
        else:
            bare_sc = mod.bare_scene(sp)
        proxy = hf.mesh_object("Proxy", bare_sc, sp.spacing * 1.4, 5000)
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
    if sp.extra.get("keep_barrel"):
        # the belly and the brisket the trunk's, not the legs' (horse_forge.keep_barrel)
        method += ", %d to the barrel" % hf.keep_barrel(ob, sp.skel)
    jaw_weights(ob, sp, quad.DEFORM_NAMES)
    return method


# --------------------------------------------------------------------------------------
# hurt volumes
# --------------------------------------------------------------------------------------

def hurt_volumes(sp, body) -> list:
    """Where a blow lands on it, in the model's own (Godot) space at rest: the trunk as a capsule
    lying along it, the head as a sphere. CreatureModel lays the actor's hurtbox on these."""
    verts, _, _ = bodylib.mesh_arrays(body)
    mod = sp.extra.get("module")
    if mod is not None and hasattr(mod, "hurt"):
        out = []
        for v in mod.hurt():
            if v[0] == "sphere":
                out.append({"kind": "sphere", "c": godot(v[1]), "r": round(float(v[2]), 4)})
            else:
                out.append({"kind": "capsule", "a": godot(v[1]), "b": godot(v[2]), "r": round(float(v[3]), 4)})
        return out
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
    if sp.family not in foe_specs.QUADS:
        clips = sp.extra["module"].build_clips()
        sidecar = {}
        for name in sorted(clips):
            baked = clips[name].bake(sp.skel)
            cf.push_clip(arm, baked)
            sidecar[name] = baked.sidecar()
        log("baked %d clips" % len(sidecar))
        return sidecar
    from forge.lib import foe_clips
    clips = foe_clips.build(sp)
    solver = foe_clips.solver_for(sp)
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
    quadish = sp.family in foe_specs.QUADS
    arm = quad.build_armature(sp.skel, name="Armature") if quadish else cr.build_armature(sp.skel, name="Armature")
    log("%s: armature %d bones" % (name, len(arm.data.bones)))
    grid = []
    spacing = sp.spacing * (1.8 if args.quick else 1.0)
    parts = sp.extra.get("parts")
    if parts:
        body, field = mesh_parts(C, sp, parts(), spacing)
    else:
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
    mat = cf.make_material("WM_%s_Hide" % C, a, o, n, roughness=0.8)
    log("painted (%.0fs)" % (time.time() - t0))
    if parts:
        pieces = split_parts(body, C, sp, mat)
        body = pieces[0]
    else:
        body.data.materials.append(mat)
        pieces = [body]
    lods = []
    total = sum(bodylib.tri_count(pc) for pc in pieces)
    for pc in pieces:
        prev = pc
        share = bodylib.tri_count(pc) / max(total, 1)
        for lvl, target in ((1, sp.lod1), (2, sp.lod2)):
            lob = hf.duplicate_joined([prev], "%s_LOD%d" % (pc.name, lvl))
            # bristles, spines and thorns are many small shells the decimator cannot collapse: past
            # the first level they go, and the hull carries the read
            if bare_for(sp) is not None:
                drop_small_islands(lob, 40 if lvl == 1 else 160)
            want = max(int(target * share), 60)
            hf.decimate_to(lob, want)
            if lvl == 2 and bodylib.tri_count(lob) > want * 1.4 and len(pieces) == 1 and bare_for(sp) is not None:
                # spines and bristles stop the collapse well short: this level is the bare hull
                # under them, its UVs and weights carried over from the full body
                import bpy
                bpy.data.objects.remove(lob, do_unlink=True)
                lob = bare_lod(sp, pc, arm, "%s_LOD%d" % (pc.name, lvl), want, out_dir, name, field)
            hf.clean_mesh(lob)
            lods.append(lob)
            prev = lob
            log("%s: %d tris" % (lob.name, bodylib.tri_count(lob)))
    sidecar = {} if args.no_clips else bake_foe_clips(arm, sp)
    glb = cf.export_glb(os.path.join(out_dir, "%s.glb" % name), [arm] + pieces + lods, with_animation=bool(sidecar))
    with open(os.path.join(out_dir, "%s.clips.json" % name), "w") as f:
        json.dump(sidecar, f, indent=1, sort_keys=True)
    tris = [sum(bodylib.tri_count(pc) for pc in pieces)] + \
        [sum(bodylib.tri_count(lo) for lo in lods if lo.name.endswith("LOD%d" % k)) for k in (1, 2)]
    bounds = cf.object_bounds(body)
    cf.write_meta(os.path.join(out_dir, "%s.meta.json" % name), name,
                  {"style": sp.style.to_dict(), "family": sp.family},
                  tris, collision="capsule", bounds=bounds, seed=getattr(sp.style, "seed", 0),
                  extra={"generator": GENERATOR, "version": VERSION, "rig": quad.RIG_ID if quadish else sp.skel.rig_id,
                         "def_scale": sp.def_scale,
                         "clips": sorted(sidecar.keys()), "bones": len(arm.data.bones),
                         "hurt": hurt_volumes(sp, body), "mesh": "%s_Body" % C,
                         "height": round(float(bounds[5]), 4), "tint": sp.extra.get("tint", "#ffffff"),
                         "limbs": sp.extra.get("limbs", []), "parts": [pc.name for pc in pieces],
                         "look": sp.extra.get("look", ""),
                         "origin": godot(sp.extra["module"].origin()) if hasattr(sp.extra.get("module"), "origin") else None,
                         "rig_manifest": quad.rig_manifest(sp.skel) if quadish else cr.manifest(sp.skel)})
    write_sidecars(out_dir, name)
    log("wrote %s: %s tris, in %.0fs" % (glb, tris, time.time() - t0))


def mesh_parts(C: str, sp, scenes: dict, spacing: float):
    """Each part meshed alone, marked by a material slot of its own, and joined into one object to
    be unwrapped, skinned and painted as one; split_parts parts them again afterwards."""
    import bpy
    obs = []
    total_tris = sp.tris
    names = list(scenes.keys())
    union = sdf.Scene()
    for i, pname in enumerate(names):
        sc = scenes[pname]
        budget = int(total_tris * sp.extra.get("part_share", {}).get(pname, 1.0 / len(names)))
        ob = hf.mesh_object("%s_%s" % (C, pname), sc, spacing, budget)
        if ob is None:
            continue
        hf.clean_mesh(ob)
        hf.decimate_to(ob, budget)
        tag = bpy.data.materials.new("part_%s" % pname)
        ob.data.materials.append(tag)
        obs.append(ob)
        union.prims += list(getattr(sc, "base", sc).prims)
        log("part %s: %d tris" % (pname, bodylib.tri_count(ob)))
    body = obs[0]
    bodylib.join_into(body, obs[1:])
    body.name = body.data.name = "%s_Body" % C
    field = sdf.SampledField(union, spacing=max(spacing, 0.012), margin=0.1)
    return body, field


def split_parts(body, C: str, sp, mat) -> list:
    """The joined body cut back into its parts by their slots, each wearing the one painted material."""
    import bpy
    bodylib.select_only(body)
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.separate(type='MATERIAL')
    bpy.ops.object.mode_set(mode='OBJECT')
    out = []
    for ob in list(bpy.context.selected_objects):
        if ob.type != 'MESH' or not ob.data.materials:
            continue
        pname = ob.data.materials[0].name.replace("part_", "").split(".")[0]
        ob.name = ob.data.name = "%s_%s" % (C, pname)
        ob.data.materials.clear()
        ob.data.materials.append(mat)
        out.append(ob)
    out.sort(key=lambda o: (0 if o.name.endswith("_Body") else 1, o.name))
    return out


def bare_for(sp):
    mod = sp.extra.get("module")
    if sp.family == "canid" and (sp.style.thorns > 0 or sp.style.bark > 0):
        bare = bb.CanidStyle(**{**sp.style.to_dict(), "thorns": 0.0, "bark": 0.0, "fur": 0.0})
        return bb.canid_scene(sp.skel, bare, sp.extra["trunk"])
    if mod is not None and hasattr(mod, "bare_scene"):
        return mod.bare_scene(sp)
    return None


def bare_lod(sp, body, arm, name: str, target: int, out_dir: str, stem: str, field):
    """A far level made from the bare hull: meshed coarse, decimated, unwrapped and painted on a
    small map of its own by the same painter (UVs carried over from the body smear across its
    seams), and skinned with the body's weights."""
    ob = hf.mesh_object(name, bare_for(sp), sp.spacing * 2.2, target)
    hf.clean_mesh(ob)
    hf.decimate_to(ob, target)
    bodylib.smart_uv(ob, angle_deg=60.0, margin=0.02)
    albedo, orm, _ = foe_paint.painter(sp, field)
    a, o, _ = hf.bake_maps(ob, out_dir, "%s_far" % stem, albedo, orm, None, size=256)
    ob.data.materials.append(cf.make_material("WM_%s_Far" % cap(stem), a, o, None, roughness=0.85))
    bones = quad.DEFORM_NAMES if sp.family in foe_specs.QUADS else sp.skel.deform_names
    bv, _, _ = bodylib.mesh_arrays(body)
    bW = bodylib.weight_matrix(body, bones)
    bodylib.transfer_weights(ob, bv, bW, arm, bones=bones, k=4, smooth=1)
    return ob


def drop_small_islands(ob, min_verts: int) -> int:
    """Deletes the mesh's loose pieces of fewer than `min_verts` vertices; returns how many went."""
    import bmesh
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.verts.ensure_lookup_table()
    seen = set()
    doomed = []
    for v in bm.verts:
        if v.index in seen:
            continue
        stack = [v]
        island = []
        seen.add(v.index)
        while stack:
            cur = stack.pop()
            island.append(cur)
            for e in cur.link_edges:
                o = e.other_vert(cur)
                if o.index not in seen:
                    seen.add(o.index)
                    stack.append(o)
        if len(island) < min_verts:
            doomed.extend(island)
    if doomed:
        bmesh.ops.delete(bm, geom=doomed, context='VERTS')
        bm.to_mesh(ob.data)
    bm.free()
    return len(doomed)


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
