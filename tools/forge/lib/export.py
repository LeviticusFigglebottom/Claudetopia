"""LODs, collision, glTF export, meta.json and Godot .import sidecars (CONTRACTS.md §4).

`finish_asset` is the one call every generator ends with: it joins the procedural parts,
bakes the atlas, builds LOD1/LOD2, exports <name>.glb with external texture uris, writes
<name>.meta.json and the .import files Godot needs.
"""
from __future__ import annotations

import json
import math
import os
import time
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

from . import bake as B
from . import cli
from . import glb as G
from . import godot_import as GI
from . import scene as S
from .godot_import import godot_uid  # noqa: F401  (callers and tests reach it through here)

FORGE_VERSION = cli.FORGE_VERSION
LOD_RATIOS = (0.4, 0.15)
LOD_MIN_TRIS = (300, 120)
COLLISION_KINDS = ("convex", "trimesh", "capsule", "none", "col_glb")


# --- LODs -------------------------------------------------------------------------------

def drop_small_parts(obj, target_tris: int) -> None:
    """Delete the smallest connected pieces of a mesh until it fits a triangle budget.

    Size is the piece's longest bounding-box edge, not its triangle count: a long limb
    built cheaply must outrank a short twig built expensively, because it is the limb the
    silhouette needs.
    """
    me = obj.data
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    seen = set()
    parts = []
    for f0 in bm.faces:
        if f0 in seen:
            continue
        stack = [f0]
        group = []
        while stack:
            f = stack.pop()
            if f in seen:
                continue
            seen.add(f)
            group.append(f)
            for e in f.edges:
                for nf in e.link_faces:
                    if nf not in seen:
                        stack.append(nf)
        lo = [1e18] * 3
        hi = [-1e18] * 3
        tris = 0
        for f in group:
            tris += max(1, len(f.verts) - 2)
            for v in f.verts:
                for k in range(3):
                    lo[k] = min(lo[k], v.co[k])
                    hi[k] = max(hi[k], v.co[k])
        parts.append((max(hi[k] - lo[k] for k in range(3)), tris, group))
    if len(parts) < 2:
        bm.free()
        return
    parts.sort(key=lambda t: t[0], reverse=True)
    kept = 0
    doomed = []
    for (_size, tris, group) in parts:
        if kept and kept + tris > target_tris:
            doomed.extend(group)
        else:
            kept += tris
    if doomed and len(doomed) < len(bm.faces):
        bmesh.ops.delete(bm, geom=doomed, context="FACES")
        loose = [v for v in bm.verts if not v.link_faces]
        if loose:
            bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(me)
    bm.free()
    me.update()


def make_lods(obj, ratios=LOD_RATIOS, floors=LOD_MIN_TRIS, smooth_angle: float = 35.0) -> list:
    """Decimated copies named <obj>_LOD1, _LOD2, hitting a triangle target rather than
    merely asking for one.

    One pass of Blender's collapse decimator does not reach its ratio on a mesh made of
    many disconnected pieces -- a branching trunk is the worst case, and asking for 0.06
    of it returned 0.45. Each pass is relative to the mesh it is given, so repeating until
    the count stops falling converges on the budget. Without this the LOD1 rung is not a
    level of detail at all, just a slightly smaller tree at a third of full price.
    """
    lods = [obj]
    base = S.tri_count(obj)
    for i, r in enumerate(ratios, start=1):
        floor = floors[i - 1] if i - 1 < len(floors) else 100
        target = max(floor, int(base * r))
        d = S.duplicate(obj, "%s_LOD%d" % (obj.name, i))
        tris = base
        if target < base * 0.5:
            # Drop the small pieces before decimating, not after. A collapse cannot take a
            # closed tube below its minimal form, so on a branching trunk it spends its
            # whole budget shattering the trunk into shards while the twigs survive intact.
            # Removing the twigs first leaves the limbs enough triangles to stay limbs.
            drop_small_parts(d, int(target * 2.0))
            tris = S.tri_count(d)
        for _ in range(6):
            if tris <= target:
                break
            S.decimate(d, ratio=max(0.08, target / float(tris)))
            got = S.tri_count(d)
            if got >= tris * 0.97:  # no further progress to be had
                break
            tris = got
        if tris > target * 1.4:
            # Still over: the decimator has stalled on what is left, so drop pieces again.
            drop_small_parts(d, target)
            tris = S.tri_count(d)
        S.shade_smooth(d, smooth_angle)
        got = S.tri_count(d)
        if base > 200 and got < 24:
            # A rung that decimates to nothing is a generator failure, not a cheap level of
            # detail: the far ring renders empty air and nobody notices until a capture is
            # taken. If a budget cannot be met with a silhouette, it must be authored.
            raise RuntimeError("make_lods: %s LOD%d collapsed to %d triangles from %d; "
                               "author that rung instead of decimating it"
                               % (obj.name, i, got, base))
        lods.append(d)
    return lods


def card_lods(obj, keep=(0.55, 0.25), rng=None, grow=True) -> list:
    """LODs for card meshes (leaf clusters, grass): drop a share of the cards and grow the
    rest so the volume reads the same from afar."""
    import random
    rng = rng or random.Random(7)
    lods = [obj]
    for i, k in enumerate(keep, start=1):
        d = S.duplicate(obj, "%s_LOD%d" % (obj.name, i))
        bm = bmesh.new()
        bm.from_mesh(d.data)
        bm.faces.ensure_lookup_table()
        # a card = one face (quad) or a pair of triangles sharing an edge; treat faces independently
        faces = list(bm.faces)
        rng.shuffle(faces)
        n_keep = max(1, int(len(faces) * k))
        drop = faces[n_keep:]
        keep_faces = faces[:n_keep]
        bmesh.ops.delete(bm, geom=drop, context="FACES")
        if grow:
            s = 1.0 / math.sqrt(max(k, 0.05))
            s = min(s, 1.8)
            for f in keep_faces:
                if not f.is_valid:
                    continue
                c = f.calc_center_median()
                for v in f.verts:
                    v.co = c + (v.co - c) * s
        bm.to_mesh(d.data)
        bm.free()
        d.data.update()
        lods.append(d)
    return lods


# --- collision ---------------------------------------------------------------------------

def collision_mesh(obj, name: str, max_tris: int = 96):
    """Simplified convex hull for <name>_col.glb."""
    d = S.duplicate(obj, name)
    bm = bmesh.new()
    bm.from_mesh(d.data)
    hull = bmesh.ops.convex_hull(bm, input=bm.verts, use_existing_faces=False)
    interior = [e for e in hull["geom_interior"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.delete(bm, geom=interior, context="VERTS")
    bm.to_mesh(d.data)
    bm.free()
    d.data.materials.clear()
    tris = S.tri_count(d)
    if tris > max_tris:
        S.decimate(d, ratio=max_tris / float(tris))
    S.shade_flat(d)
    return d


def capsule_params(objs) -> dict:
    lo, hi = S.bounds(objs)
    r = max(hi.x - lo.x, hi.y - lo.y) * 0.5
    return {"radius": round(r, 3), "height": round(hi.z - lo.z, 3)}


# --- glTF ----------------------------------------------------------------------------------

UV_LAYER = "UVMap"


def single_uv(obj) -> None:
    """Leave the mesh with exactly one UV layer, the one the bake reads, called UVMap.

    Two reasons, and both of them have cost a day. Baking leaves the pre-bake layer behind
    and the exporter writes it as a TEXCOORD_1 nothing samples -- eight bytes a vertex,
    a fifth of a tree's file. Worse, joining two meshes whose UV layers have different
    names gives the result *both* layers with half the loops blank in each, so when the
    stale one is dropped a leaf card ends up reading the bark atlas. Normalising the name
    first means a join merges the layers instead of stacking them.

    Removing a layer reshuffles the collection, so this works by name throughout: holding a
    reference across a removal deletes the wrong one and strips every UV off the mesh.
    """
    if obj.type != "MESH":
        return
    uvs = obj.data.uv_layers
    if not len(uvs):
        return
    keep = next((u.name for u in uvs if u.active_render), None) or uvs.active.name
    for name in [u.name for u in uvs if u.name != keep]:
        layer = uvs.get(name)
        if layer is not None:
            uvs.remove(layer)
    layer = uvs.get(keep)
    if layer is not None:
        layer.name = UV_LAYER
        uvs.active = uvs[UV_LAYER]


## `export_colors=False` said "no vertex colours" to Blender 4.0's glTF exporter. The
## option was replaced by `export_vertex_color`, an enum, and passing the old name to 4.2
## is not ignored -- the operator refuses the call. The forge wants no vertex colours in
## either spelling: its colour lives in the baked atlas, and a COLOR_0 nothing samples is
## four more bytes on every vertex.
_GLTF_COLOR_KW = ({"export_colors": False}
                  if "export_colors" in {p.identifier
                                         for p in bpy.ops.export_scene.gltf.get_rna_type().properties}
                  else {"export_vertex_color": "NONE"})


def export_glb(objs, path, material_textures: dict | None = None) -> dict:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    for o in objs:
        o.hide_set(False)
        o.hide_viewport = False
        o.hide_render = False
        single_uv(o)
    S.select_only(objs)
    bpy.ops.export_scene.gltf(
        filepath=str(path), export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
        export_texcoords=True, export_normals=True, export_tangents=False, export_materials="EXPORT",
        export_image_format="AUTO", export_animations=False, export_skins=False, export_morph=False,
        export_lights=False, export_cameras=False, export_extras=False, export_draco_mesh_compression_enable=False,
        export_attributes=False, **_GLTF_COLOR_KW,
    )
    uris = G.externalise_images(path, material_textures or {})
    return {"uris": uris, "summary": G.summary(path)}


def texture_slots(material_name: str, textures: dict) -> dict:
    """Build the slot map export_glb needs from bake_atlas' texture dict."""
    slots = {}
    if "albedo" in textures:
        slots["baseColorTexture"] = textures["albedo"]
    if "normal" in textures:
        slots["normalTexture"] = textures["normal"]
    if "orm" in textures:
        slots["metallicRoughnessTexture"] = textures["orm"]
        slots["occlusionTexture"] = textures["orm"]
    if "emission" in textures:
        slots["emissiveTexture"] = textures["emission"]
    return {material_name: slots}


# --- Godot .import sidecars -----------------------------------------------------------------

SCENE_PARAMS = """nodes/root_type=""
nodes/root_name=""
nodes/root_script=null
mesh_library/use_node_names_as_mesh_names=false
array_mesh/deduplicate_surfaces=true
nodes/apply_root_scale=true
nodes/root_scale=1.0
nodes/import_as_skeleton_bones=false
nodes/use_name_suffixes=true
nodes/use_node_type_suffixes=true
meshes/ensure_tangents=true
meshes/generate_lods=true
meshes/create_shadow_meshes=true
meshes/light_baking=1
meshes/lightmap_texel_size=0.2
meshes/force_disable_compression=false
skins/use_named_skins=true
animation/import=true
animation/fps=30
animation/trimming=false
animation/remove_immutable_tracks=true
animation/import_rest_as_RESET=false
import_script/path="res://tools_gd/glb_post_import.gd"
materials/extract=0
materials/extract_format=0
materials/extract_path=""
_subresources={}
gltf/naming_version=2
gltf/embedded_image_handling=1
gltf/texture_map_mode=1
"""

TEXTURE_PARAMS = """compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map={normal_map}
compress/channel_pack={channel_pack}
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=1
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""


def _load_import_defaults() -> dict:
    """Optional override of the param blocks from game/assets/import_defaults.cfg."""
    cfg = cli.REPO_ROOT / "game" / "assets" / "import_defaults.cfg"
    out = {"scene": SCENE_PARAMS, "texture": TEXTURE_PARAMS}
    if not cfg.exists():
        return out
    section = None
    blocks: dict[str, list[str]] = {}
    for line in cfg.read_text(encoding="utf-8").splitlines():
        t = line.strip()
        if not t or t.startswith(";") or t.startswith("#"):
            continue
        if t.startswith("[") and t.endswith("]"):
            section = t[1:-1]
            blocks[section] = []
            continue
        if section:
            blocks[section].append(t)
    if blocks.get("scene"):
        out["scene"] = "\n".join(blocks["scene"]) + "\n"
    if blocks.get("texture"):
        out["texture"] = "\n".join(blocks["texture"]) + "\n"
    return out


def write_import_sidecars(asset_dir: Path, glb_name: str, texture_names: list[str], extra_glbs: list[str] = ()) -> list[Path]:
    """<file>.import next to each output so Godot imports GLBs with our settings and PNGs as
    VRAM-compressed textures (normal maps flagged), in the complete form Godot writes: with the
    path and dest_files lines it would otherwise add on every checkout's first import
    (lib/godot_import.py)."""
    defaults = _load_import_defaults()
    formats = GI.vram_formats(cli.REPO_ROOT / "game" / "project.godot")
    written = []
    for g in [glb_name, *extra_glbs]:
        res = cli.res_path(None, asset_dir / g)
        text = ("[remap]\n\nimporter=\"scene\"\nimporter_version=1\ntype=\"PackedScene\"\nuid=\"%s\"\n\n"
                "[deps]\n\nsource_file=\"%s\"\n\n[params]\n\n%s" % (godot_uid(res), res, defaults["scene"]))
        p = asset_dir / (g + ".import")
        p.write_text(GI.complete(text, formats), encoding="utf-8")
        written.append(p)
    for t in texture_names:
        # a texture shared from another folder (a species' bark, "../_species/...") is named by
        # its own path, so every tree that shares it writes the same sidecar and the same uid
        res = cli.res_path(None, Path(os.path.normpath(asset_dir / t)))
        is_normal = t.endswith("_normal.png")
        # `_nrm.png` is an impostor's object-space normal atlas (gen_impostors.py): data, but not a
        # tangent-space normal map, which Godot would compress to two channels and rebuild.
        is_data = is_normal or t.endswith("_orm.png") or t.endswith("_nrm.png")
        params = defaults["texture"].replace("{normal_map}", "1" if is_normal else "2").replace("{channel_pack}", "1" if is_data else "0")
        text = ("[remap]\n\nimporter=\"texture\"\ntype=\"CompressedTexture2D\"\nuid=\"%s\"\n\n"
                "[deps]\n\nsource_file=\"%s\"\n\n[params]\n\n%s" % (godot_uid(res), res, params))
        p = Path(os.path.normpath(asset_dir / (t + ".import")))
        p.write_text(GI.complete(text, formats), encoding="utf-8")
        written.append(p)
    return written


# --- meta -------------------------------------------------------------------------------------

def write_meta(path: Path, meta: dict) -> None:
    path.write_text(json.dumps(meta, indent=1, sort_keys=True) + "\n", encoding="utf-8")


def bounds_dict(objs) -> dict:
    lo, hi = S.bounds(objs)
    # Godot space: x = x, y = z, z = -y
    return {"min": [round(lo.x, 3), round(lo.z, 3), round(-hi.y, 3)],
            "max": [round(hi.x, 3), round(hi.z, 3), round(-lo.y, 3)],
            "radius": round((hi - lo).length * 0.5, 3), "height": round(hi.z - lo.z, 3)}


# --- the one call -------------------------------------------------------------------------------

def finish_asset(*, out_root, category: str, name: str, generator: str, seed: int, kind: str, params: dict,
                 pal, opaque_objs=None, card_objs=None, baked_objs=None, collision: str = "convex",
                 collision_params: dict | None = None, quick: bool = False, res: int = 0, tier: str | None = None,
                 lods: bool = True, lod_ratios=LOD_RATIOS, card_keep=(0.55, 0.25), smooth_angle: float = 35.0,
                 alpha: bool = False, orm_scale: float = 0.0, write_import: bool = True, extra_meta: dict | None = None,
                 version: int = FORGE_VERSION, rng=None, materials_used: list[str] | None = None,
                 impostor=None, impostor_textures: dict | None = None,
                 unwrap_mode: str = "smart", ground: bool = True) -> dict:
    """Bake, LOD, export and describe one asset. Returns the meta dict written to disk.

    opaque_objs: procedural-material parts, joined into one mesh and baked to one atlas.
    card_objs:   alpha-card parts that already carry image (foliage) materials.
    baked_objs:  parts that were baked separately already (own textures), exported as-is.
    impostor:    an object that *replaces* the whole asset at LOD2 (crossed-card billboard);
                 when given, only one decimated level is generated below LOD0.
    """
    t0 = time.time()
    verbose = bool(os.environ.get("FORGE_TRACE"))

    def stage(label):
        if verbose:
            print("FORGE_STAGE %6.1fs %s" % (time.time() - t0, label), flush=True)

    if collision not in COLLISION_KINDS:
        raise ValueError("collision must be one of %s" % (COLLISION_KINDS,))
    out_dir = cli.asset_dir(out_root, category, name)
    if impostor is not None:
        lod_ratios = lod_ratios[:1]
        card_keep = card_keep[:1]
    # Grounding is settled once, here, over every part of the asset together. Generators
    # that drop their own parts can still be wrong: a part added after the drop, or one
    # whose transform is applied later, leaves the asset hovering, and a floating barrel
    # is not something a placement can correct.
    if ground:
        incoming = list(opaque_objs or []) + list(card_objs or [])
        incoming += [b[0] if isinstance(b, tuple) else b for b in (baked_objs or [])]
        if incoming:
            S.drop_to_ground(incoming)
    meta_textures: list[str] = []
    slot_map: dict = {}
    parts: list[list] = []  # list of LOD chains
    main = None

    if opaque_objs:
        stage("join %d opaque parts" % len(opaque_objs))
        main = S.join(list(opaque_objs), name)
        S.shade_smooth(main, smooth_angle)
        radius = S.radius_of([main])
        size = B.pick_resolution(radius, res, quick, tier)
        stage("bake atlas %d px (%d tris)" % (size, S.tri_count(main)))
        info = B.bake_atlas(main, out_dir, name, size, quick=quick, alpha=alpha, orm_scale=orm_scale,
                            unwrap_mode=unwrap_mode)
        stage("baked in %ss" % info["seconds"])
        meta_textures += list(info["textures"].values())
        slot_map.update(texture_slots(info["material"], info["textures"]))
        stage("lods")
        parts.append(make_lods(main, lod_ratios, smooth_angle=smooth_angle) if (lods and not quick) else [main])
    for bo in (baked_objs or []):
        # (obj, textures) or (obj, textures, [LOD1, ...]): a part whose lower levels its generator
        # authored itself -- a grown tree's wood trimmed of whole twigs -- is never decimated here.
        authored = None
        if isinstance(bo, tuple) and len(bo) == 3:
            obj, textures, authored = bo
        else:
            obj, textures = bo if isinstance(bo, tuple) else (bo, {})
        if textures:
            for m in obj.data.materials:
                if m is not None:
                    slot_map.update(texture_slots(m.name, textures))
            meta_textures += [t for t in textures.values() if t not in meta_textures]
        if authored is not None:
            parts.append([obj] + (list(authored)[:len(lod_ratios)] if (lods and not quick) else []))
        else:
            parts.append(make_lods(obj, lod_ratios, smooth_angle=smooth_angle) if (lods and not quick) else [obj])
    if card_objs:
        stage("join %d card parts" % len(card_objs))
        cards = S.join(list(card_objs), "%s_cards" % name)
        for m in cards.data.materials:
            if m is None:
                continue
            tex = m.get("forge_textures")
            if tex:
                slot_map.update(texture_slots(m.name, dict(tex)))
                meta_textures += [t for t in dict(tex).values() if t not in meta_textures]
        parts.append(card_lods(cards, card_keep, rng=rng) if (lods and not quick) else [cards])

    lod0 = [chain[0] for chain in parts]
    if not lod0:
        raise RuntimeError("finish_asset: nothing to export")
    bnd = bounds_dict(lod0)

    # Collision and the triangle counts are settled here, before LOD0 is merged below,
    # because both of them need the parts as the separate objects they were built as.
    extra_glbs = []
    col_value = collision
    col_params = dict(collision_params or {})
    if collision == "col_glb":
        src = main or lod0[0]
        col = collision_mesh(src, "%s_col" % name)
        col_path = out_dir / ("%s_col.glb" % name)
        export_glb([col], col_path, {})
        extra_glbs.append(col_path.name)
        col_value = col_path.name
    elif collision == "capsule" and not col_params:
        col_params = capsule_params(lod0)

    n_lods = max(len(chain) for chain in parts)
    tris = []
    for i in range(n_lods):
        tris.append(sum(S.tri_count(chain[min(i, len(chain) - 1)]) for chain in parts))
    if impostor is not None:
        tris.append(S.tri_count(impostor))
    while len(tris) < 3:
        tris.append(tris[-1])

    # LOD0 is exported as ONE mesh with one surface per material. The world streamer
    # scatters an asset by taking the first MeshInstance3D out of the imported scene and
    # handing its mesh to a MultiMesh, so a tree split into a trunk mesh and a leaf-card
    # mesh arrived in the world as a bare trunk -- four hundred thousand bare trunks, as it
    # turned out. Merging costs nothing (the surfaces are what the materials were anyway)
    # and it means whatever the streamer grabs is the whole plant. The LOD1/LOD2 meshes
    # stay as separate nodes, for whatever instantiates the scene and uses their
    # visibility ranges.
    tails = [o for chain in parts for o in chain[1:]]
    if len(lod0) > 1:
        # Every part must carry the same, singular UV layer before they are joined, or the
        # join stacks two layers and the cards end up reading the trunk's atlas.
        for o in lod0:
            single_uv(o)
        all_objs = [S.join(lod0, name)] + tails
    else:
        all_objs = lod0 + tails
    if impostor is not None:
        impostor.name = "%s_LOD%d" % (name, len(lod_ratios) + 1)
        impostor.data.name = impostor.name
        if impostor_textures:
            for m in impostor.data.materials:
                if m is not None:
                    slot_map.update(texture_slots(m.name, dict(impostor_textures)))
            meta_textures += [t for t in impostor_textures.values() if t not in meta_textures]
        all_objs.append(impostor)
    glb_path = out_dir / ("%s.glb" % name)
    stage("export %d objects" % len(all_objs))
    export_info = export_glb(all_objs, glb_path, slot_map)
    stage("exported")

    meta = {
        "name": name,
        "category": category,
        "generator": generator,
        "version": version,
        "kind": kind,
        "seed": seed,
        "params": params,
        "hash": cli.asset_hash(generator, version, name, kind, params, seed, pal.id if pal else None),
        "region_palette": pal.to_meta() if pal else None,
        "tris": tris[:3],
        "collision": col_value,
        "collision_params": col_params,
        "bounds": bnd,
        "textures": meta_textures,
        "materials": export_info["summary"]["materials"],
        "materials_used": materials_used or [],
        "meshes": export_info["summary"]["meshes"],
        "glb": glb_path.name,
        "built_seconds": round(time.time() - t0, 2),
    }
    if extra_meta:
        meta.update(extra_meta)
    write_meta(out_dir / ("%s.meta.json" % name), meta)
    if write_import:
        write_import_sidecars(out_dir, glb_path.name, meta_textures, extra_glbs)
    print("FORGE_OK %s/%s tris=%s tex=%d %.1fs" % (category, name, tris[:3], len(meta_textures), time.time() - t0))
    return meta
