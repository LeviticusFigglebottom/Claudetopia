"""LODs, collision, glTF export, meta.json and Godot .import sidecars (CONTRACTS.md §4).

`finish_asset` is the one call every generator ends with: it joins the procedural parts,
bakes the atlas, builds LOD1/LOD2, exports <name>.glb with external texture uris, writes
<name>.meta.json and the .import files Godot needs.
"""
from __future__ import annotations

import hashlib
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
from . import scene as S

FORGE_VERSION = cli.FORGE_VERSION
LOD_RATIOS = (0.4, 0.15)
LOD_MIN_TRIS = (300, 120)
COLLISION_KINDS = ("convex", "trimesh", "capsule", "none", "col_glb")


# --- LODs -------------------------------------------------------------------------------

def make_lods(obj, ratios=LOD_RATIOS, floors=LOD_MIN_TRIS, smooth_angle: float = 35.0) -> list:
    """Decimated copies named <obj>_LOD1, _LOD2. Small meshes get lighter decimation so
    they keep their silhouette."""
    lods = [obj]
    base = S.tri_count(obj)
    for i, r in enumerate(ratios, start=1):
        floor = floors[i - 1] if i - 1 < len(floors) else 100
        target = max(floor, int(base * r))
        d = S.duplicate(obj, "%s_LOD%d" % (obj.name, i))
        if target < base:
            S.decimate(d, ratio=target / float(base))
        S.shade_smooth(d, smooth_angle)
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

def export_glb(objs, path, material_textures: dict | None = None) -> dict:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    for o in objs:
        o.hide_set(False)
        o.hide_viewport = False
        o.hide_render = False
        # Baking leaves the pre-bake UV layer behind, and the exporter writes it as
        # TEXCOORD_1 that nothing ever samples: eight bytes a vertex, which on a tree is a
        # fifth of the file. Only the active layer survives to the GLB.
        if o.type == "MESH" and len(o.data.uv_layers) > 1:
            # The bake reads the render layer, so that is the one that must survive. Work
            # by name: removing a layer reshuffles the collection, and holding a reference
            # across a removal deletes the wrong one (which strips every UV off the mesh).
            uvs = o.data.uv_layers
            keep = next((u.name for u in uvs if u.active_render), None) or uvs.active.name
            for name in [u.name for u in uvs if u.name != keep]:
                layer = uvs.get(name)
                if layer is not None:
                    uvs.remove(layer)
            if uvs.get(keep) is not None:
                uvs.active = uvs[keep]
    S.select_only(objs)
    bpy.ops.export_scene.gltf(
        filepath=str(path), export_format="GLB", use_selection=True, export_apply=True, export_yup=True,
        export_texcoords=True, export_normals=True, export_tangents=False, export_materials="EXPORT",
        export_image_format="AUTO", export_animations=False, export_skins=False, export_morph=False,
        export_lights=False, export_cameras=False, export_extras=False, export_draco_mesh_compression_enable=False,
        export_attributes=False, export_colors=False,
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

_UID_CHARS = "abcdefghijklmnopqrstuvwxyz"


def godot_uid(res_path: str) -> str:
    """Stable ResourceUID text from the res:// path (Godot's base-34 a..y/0..8 encoding)."""
    n = int(hashlib.sha1(res_path.encode("utf-8")).hexdigest()[:16], 16) & 0x7FFFFFFFFFFFFFFF
    base = 25 + 9
    s = ""
    while n:
        c = n % base
        s = (chr(ord("a") + c) if c < 25 else chr(ord("0") + c - 25)) + s
        n //= base
    return "uid://" + s


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
meshes/generate_lods=false
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
    VRAM-compressed textures (normal maps flagged). Godot fills in path/dest_files itself."""
    defaults = _load_import_defaults()
    written = []
    for g in [glb_name, *extra_glbs]:
        res = cli.res_path(None, asset_dir / g)
        text = ("[remap]\n\nimporter=\"scene\"\nimporter_version=1\ntype=\"PackedScene\"\nuid=\"%s\"\n\n"
                "[deps]\n\nsource_file=\"%s\"\n\n[params]\n\n%s" % (godot_uid(res), res, defaults["scene"]))
        p = asset_dir / (g + ".import")
        p.write_text(text, encoding="utf-8")
        written.append(p)
    for t in texture_names:
        res = cli.res_path(None, asset_dir / t)
        is_normal = t.endswith("_normal.png")
        is_data = is_normal or t.endswith("_orm.png")
        params = defaults["texture"].replace("{normal_map}", "1" if is_normal else "2").replace("{channel_pack}", "1" if is_data else "0")
        text = ("[remap]\n\nimporter=\"texture\"\ntype=\"CompressedTexture2D\"\nuid=\"%s\"\n\n"
                "[deps]\n\nsource_file=\"%s\"\n\n[params]\n\n%s" % (godot_uid(res), res, params))
        p = asset_dir / (t + ".import")
        p.write_text(text, encoding="utf-8")
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
        obj, textures = bo if isinstance(bo, tuple) else (bo, {})
        if textures:
            for m in obj.data.materials:
                if m is not None:
                    slot_map.update(texture_slots(m.name, textures))
            meta_textures += [t for t in textures.values() if t not in meta_textures]
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
    all_objs = [o for chain in parts for o in chain]
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
