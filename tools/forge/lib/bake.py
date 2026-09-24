"""Baking: smart UV unwrap, one atlas per asset, Cycles CPU bake to albedo / normal / ORM.

Channels are read straight off each material's Principled BSDF by temporarily routing the
socket into an Emission shader (deterministic, 1-4 samples; more when a material uses the
stochastic AO node). Normals use the NORMAL bake in tangent space with +Y green (OpenGL).
Occlusion uses the AO bake. The three PNGs land next to the model and the object's
materials are replaced by one image-based Principled material, so the glTF export is
plain StandardMaterial3D input for Godot.
"""
from __future__ import annotations

import contextlib
import math
import os
import sys
import time
from pathlib import Path

import bpy
import numpy as np

from .atlas_fill import fill_uncovered, shrink_mask

from . import materials as M
from . import scene as S

try:
    from PIL import Image
except ImportError:  # pragma: no cover - lib/__init__ puts the project's Pillow on the path
    Image = None


# --- resolution -------------------------------------------------------------------------

def pick_resolution(radius_m: float, override: int = 0, quick: bool = False, tier: str | None = None) -> int:
    """Texture size by asset size (CONTRACTS.md §4 allows 512-2048).

    Only hero pieces get 2048: a tree or a boulder carries a repeating surface, so past
    1024 the extra texels buy nothing visible and cost four times the bake. Anything under
    a third of a metre (a mug, a candle) is fine at 256."""
    if override:
        size = int(override)
    elif tier == "hero":
        # 2048 costs five megabytes of PNG per landmark and the forge commits its output.
        # 1536 over a forty-metre bell is still forty texels to the metre, which is more
        # than a painterly surface with no micro-detail can use.
        size = 1536
    elif tier == "tiny" or radius_m < 0.32:
        size = 256
    elif radius_m < 2.4:
        size = 512
    else:
        size = 1024
    if quick:
        size = max(128, size // 2)
    return size


# --- UV ---------------------------------------------------------------------------------

def unwrap(obj, angle_deg: float = 66.0, margin: float = 0.006, mode: str = "smart") -> None:
    """Lay the object out in one 0..1 atlas.

    `mode` picks the projection, because one strategy does not fit every shape:

    * ``smart`` - smart UV project. Right for anything with flat panels (crates, tables,
      walls): those give a few large islands. On a displaced rock it degenerates into a
      thousand face-sized islands.
    * ``sphere`` - spherical projection. Right for blobs: a boulder, a bone, a lathed
      stone. One seam and some pole stretch, which a painterly noise surface does not
      show, in exchange for ~80% coverage in three islands instead of 45% in nine hundred.
    * ``cylinder`` - cylindrical projection about the object's Z. Right for a tree: bark
      is a repeating surface, and smart project on a branching trunk makes thousands of
      face-sized islands whose seams triple the exported vertex count.
    * ``cube`` - box projection, for rectilinear assets whose faces are axis-aligned.

    In every mode island scale is averaged first, so texel density is even across parts
    (the trunk of a tree gets the texels, not its twigs), and the islands are then packed
    with rotation so the sheet is actually filled.
    """
    S.select_only([obj])
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    if mode == "sphere":
        bpy.ops.uv.sphere_project(direction="ALIGN_TO_OBJECT", correct_aspect=True)
    elif mode == "cylinder":
        bpy.ops.uv.cylinder_project(direction="ALIGN_TO_OBJECT", align="POLAR_ZX",
                                    radius=1.0, correct_aspect=True)
    elif mode == "cube":
        bpy.ops.uv.cube_project(cube_size=1.0, correct_aspect=True)
    else:
        bpy.ops.uv.smart_project(angle_limit=math.radians(angle_deg), island_margin=0.0,
                                 area_weight=1.0, correct_aspect=True, scale_to_bounds=False)
    bpy.ops.uv.select_all(action="SELECT")
    projected = mode in ("sphere", "cylinder")
    if not projected:
        bpy.ops.uv.average_islands_scale()
    try:
        bpy.ops.uv.pack_islands(rotate=not projected, margin=margin, scale=True)
    except TypeError:  # older signature
        bpy.ops.uv.pack_islands(rotate=not projected, margin=margin)
    bpy.ops.object.mode_set(mode="OBJECT")


def has_uv(obj) -> bool:
    return obj.type == "MESH" and len(obj.data.uv_layers) > 0


# --- channel routing --------------------------------------------------------------------

def _principled(mat):
    for n in mat.node_tree.nodes:
        if n.type == "BSDF_PRINCIPLED":
            return n
    raise RuntimeError("material %s has no Principled BSDF" % mat.name)


def _output(mat):
    for n in mat.node_tree.nodes:
        if n.type == "OUTPUT_MATERIAL" and n.is_active_output:
            return n
    for n in mat.node_tree.nodes:
        if n.type == "OUTPUT_MATERIAL":
            return n
    raise RuntimeError("material %s has no output" % mat.name)


@contextlib.contextmanager
def channel_as_emission(mats, socket_name: str):
    """Temporarily make each material emit the value feeding `socket_name` of its BSDF."""
    saved = []
    for mat in mats:
        nt = mat.node_tree
        bsdf = _principled(mat)
        out = _output(mat)
        sock = bsdf.inputs[socket_name]
        em = nt.nodes.new("ShaderNodeEmission")
        em.inputs["Strength"].default_value = 1.0
        if sock.is_linked:
            nt.links.new(sock.links[0].from_socket, em.inputs["Color"])
        else:
            em.inputs["Color"].default_value = M.rgba(sock.default_value)
        prev = out.inputs["Surface"].links[0].from_socket if out.inputs["Surface"].is_linked else None
        nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
        saved.append((nt, em, prev, out))
    try:
        yield
    finally:
        for nt, em, prev, out in saved:
            nt.nodes.remove(em)
            if prev is not None:
                nt.links.new(prev, out.inputs["Surface"])


def _emissive(mats) -> bool:
    for mat in mats:
        b = _principled(mat)
        s = b.inputs["Emission Strength"]
        if s.is_linked or s.default_value > 0.0:
            c = b.inputs["Emission Color"]
            if c.is_linked or max(c.default_value[:3]) > 0.0:
                return True
    return False


def _attach_bake_targets(mats, img):
    added = []
    for mat in mats:
        nt = mat.node_tree
        node = nt.nodes.new("ShaderNodeTexImage")
        node.image = img
        node.name = "FORGE_BAKE_TARGET"
        nt.nodes.active = node
        added.append((nt, node))
    return added


def _retarget(added, img):
    """Point the bake-target nodes at a different image (used for the half-size ORM pass)."""
    for nt, node in added:
        node.image = img
        nt.nodes.active = node


def _detach(added):
    for nt, node in added:
        nt.nodes.remove(node)


TRACE = bool(os.environ.get("FORGE_TRACE"))


def _bake(kind: str, samples: int, margin: int, **kw) -> None:
    sc = bpy.context.scene
    sc.cycles.samples = samples
    t = time.time()
    bpy.ops.object.bake(type=kind, margin=margin, margin_type="EXTEND", use_clear=True, **kw)
    if TRACE:
        print("FORGE_BAKE  %-7s %2d samples %5.1fs" % (kind, samples, time.time() - t), flush=True)


def _read(img, size: int) -> np.ndarray:
    buf = np.empty(size * size * 4, dtype=np.float32)
    img.pixels.foreach_get(buf)
    return buf.reshape(size, size, 4)[::-1]  # Blender rows run bottom-up; PIL top-down


def _to_srgb8(lin: np.ndarray) -> np.ndarray:
    lin = np.clip(lin, 0.0, 1.0)
    srgb = np.where(lin <= 0.0031308, lin * 12.92, 1.055 * np.power(lin, 1 / 2.4) - 0.055)
    return (np.clip(srgb, 0, 1) * 255.0 + 0.5).astype(np.uint8)


def _to_lin8(v: np.ndarray) -> np.ndarray:
    return (np.clip(v, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)


def save_png(arr: np.ndarray, path, size: int | None = None) -> None:
    if Image is None:
        # Said here rather than as an AttributeError on None, which is what it used to be:
        # the bake had already run, so the failure arrived twenty seconds of Cycles after
        # its cause and named neither Pillow nor Blender's interpreter.
        raise RuntimeError(
            "no Pillow in this interpreter (%s). It is in tools/requirements.txt; "
            "lib/__init__ looks for it on the usual site-packages paths, or set "
            "FORGE_SITE_PACKAGES to the directory that holds PIL." % sys.executable)
    im = Image.fromarray(arr)
    if size and size != im.size[0]:
        im = im.resize((size, size), Image.LANCZOS)
    # Written to a neighbour and moved into place, so the destination either holds the last
    # good map or the new one and never half of one. PIL truncates the file it is given
    # before it writes a byte, so a build killed here -- which is how a container dies --
    # left a 0-byte albedo behind, and a 0-byte albedo stops the whole .glb loading in
    # Godot and takes down every interior that asked for the prop.
    path = Path(path)
    tmp = path.with_name(path.name + ".part")
    # optimize= re-runs the deflate filters; worth it on small maps, far too slow on large.
    im.save(str(tmp), format="PNG", optimize=im.size[0] <= 1024, compress_level=6)
    os.replace(tmp, path)


# --- main entry -------------------------------------------------------------------------

@contextlib.contextmanager
def only_visible(obj, occluders=()):
    """Hide every other mesh from the ray-traced passes.

    The AO bake traces against the whole scene, so a tree's leaf cards (alpha-tested, and
    hundreds of them) or an impostor billboard standing next to the model would both
    falsify the occlusion and make the bake orders of magnitude slower. Objects listed in
    `occluders` stay visible on purpose."""
    keep = {obj, *occluders}
    hidden = []
    for o in bpy.context.scene.objects:
        if o.type == "MESH" and o not in keep and not o.hide_render:
            o.hide_render = True
            hidden.append(o)
    try:
        yield
    finally:
        for o in hidden:
            o.hide_render = False


def bake_atlas(obj, out_dir, name: str, size: int, quick: bool = False, ao_distance: float | None = None,
               orm_scale: float = 0.0, alpha: bool = False, samples: int | None = None,
               texture_prefix: str | None = None, occluders=(), keep_uv: bool = False,
               unwrap_mode: str = "smart", normal_scale: float = 0.0) -> dict:
    """Bake `obj` (all material slots) into <out_dir>/<prefix>_{albedo,normal,orm}.png and
    replace its materials with one baked Principled material named <name>_mat."""
    t0 = time.time()
    out_dir = Path(out_dir)
    prefix = texture_prefix or name
    mats = [m for m in obj.data.materials if m is not None]
    if not mats:
        raise RuntimeError("bake_atlas: %s has no materials" % obj.name)
    # Always unwrap unless the caller authored the UVs. Trusting an existing layer is a
    # trap: joining a primitive (which carries a default UV layer) with a bmesh-built part
    # (which does not) yields an object that *has* a UV layer while half its faces sit at
    # (0, 0) - which bakes as a black model.
    if keep_uv and has_uv(obj):
        if TRACE:
            print("FORGE_BAKE  unwrap skipped (authored UVs)", flush=True)
    else:
        t_uv = time.time()
        unwrap(obj, mode=unwrap_mode)
        if TRACE:
            print("FORGE_BAKE  unwrap %-6s %5.1fs" % (unwrap_mode, time.time() - t_uv), flush=True)
    # A procedural material without the AO node is deterministic, so a couple of samples
    # only serve to antialias within a texel; materials that do trace AO need more.
    uses_ao = any(bool(m.get("forge_uses_ao")) for m in mats)
    col_samples = samples or (12 if uses_ao else 2)
    sc = bpy.context.scene
    radius = S.radius_of([obj])
    sc.world.light_settings.distance = ao_distance or max(0.12, min(4.0, radius * 0.35))
    margin = max(2, size // 128)

    # Albedo and normal carry the detail and are baked at full size. Occlusion, roughness
    # and metallic are low-frequency and are written to the ORM map at half size anyway, so
    # they are baked at that size: the AO pass is the most expensive one by far and this
    # cuts it to a quarter of the rays for no visible loss.
    # Occlusion, roughness and metallic are all slow-varying, so a large atlas keeps them
    # at a quarter: it is a quarter of the ray cost as well as a quarter of the bytes.
    orm_size = max(64, int(size * (orm_scale or (0.25 if size >= 1024 else 0.5))))

    img = bpy.data.images.new("%s_bake" % name, size, size, alpha=True, float_buffer=True)
    img.colorspace_settings.name = "Non-Color"
    img_small = bpy.data.images.new("%s_bake_orm" % name, orm_size, orm_size, alpha=True, float_buffer=True)
    img_small.colorspace_settings.name = "Non-Color"
    added = _attach_bake_targets(mats, img)
    S.select_only([obj])
    small_margin = max(2, orm_size // 128)
    try:
        with only_visible(obj, occluders):
            with channel_as_emission(mats, "Base Color"):
                _bake("EMIT", col_samples, margin)
                albedo = _read(img, size)
            alpha_arr = None
            if alpha:
                with channel_as_emission(mats, "Alpha"):
                    _bake("EMIT", 2, margin)
                    alpha_arr = _read(img, size)[..., 0]
            _bake("NORMAL", 1, margin, normal_space="TANGENT", normal_r="POS_X", normal_g="POS_Y",
                  normal_b="POS_Z")
            normal = _read(img, size)
            emis = None
            if _emissive(mats):
                _bake("EMIT", 4, margin)
                emis = _read(img, size)
            _retarget(added, img_small)
            with channel_as_emission(mats, "Roughness"):
                _bake("EMIT", col_samples, small_margin)
                rough = _read(img_small, orm_size)[..., 0]
            with channel_as_emission(mats, "Metallic"):
                _bake("EMIT", col_samples, small_margin)
                metal = _read(img_small, orm_size)[..., 0]
            if quick:
                ao = np.ones((orm_size, orm_size), dtype=np.float32)
            else:
                _bake("AO", 10 if orm_size <= 512 else 14, small_margin)
                ao = _read(img_small, orm_size)[..., 0]
    finally:
        _detach(added)
        bpy.data.images.remove(img)
        bpy.data.images.remove(img_small)

    # Unbaked texels stay black in the normal map; make them flat so mip blending is clean.
    covered = (normal[..., 3] > 0.5) if normal.shape[2] == 4 else np.ones(normal.shape[:2], bool)
    nrm = normal[..., :3].copy()
    nrm[~covered] = (0.5, 0.5, 1.0)
    # And in the colour and the ORM maps they take the islands' own colours, pushed outward,
    # so a far mip of an atlas of hundreds of small islands is not darkened toward black
    # (lib/atlas_fill.py: the well's stones read as a chequer, Skerrow's walls as dark rubble).
    albedo = albedo.copy()
    albedo[..., :3] = fill_uncovered(albedo[..., :3], covered)
    small = shrink_mask(covered, (orm_size, orm_size))
    ao = fill_uncovered(ao[..., None], small)[..., 0]
    rough = fill_uncovered(rough[..., None], small)[..., 0]
    metal = fill_uncovered(metal[..., None], small)[..., 0]

    out_dir.mkdir(parents=True, exist_ok=True)
    paths = {
        "albedo": out_dir / ("%s_albedo.png" % prefix),
        "normal": out_dir / ("%s_normal.png" % prefix),
        "orm": out_dir / ("%s_orm.png" % prefix),
    }
    alb8 = np.dstack([_to_srgb8(albedo[..., :3]), _to_lin8(alpha_arr) if alpha_arr is not None else np.full((size, size), 255, np.uint8)])
    if not alpha:
        alb8 = alb8[..., :3]
    save_png(alb8, paths["albedo"])
    # The normal map is written smaller than the albedo. These surfaces carry broad, soft
    # relief rather than fine engraving, so the detail survives a downscale that also
    # supersamples it, and a normal map is otherwise the second largest file in the repo.
    nscale = normal_scale or (0.25 if size >= 1024 else 0.5)
    save_png(_to_lin8(nrm), paths["normal"], size=max(128, int(size * nscale)))
    orm8 = np.dstack([_to_lin8(ao), _to_lin8(rough), _to_lin8(metal)])
    save_png(orm8, paths["orm"])
    if emis is not None:
        paths["emission"] = out_dir / ("%s_emission.png" % prefix)
        save_png(_to_srgb8(np.clip(emis[..., :3] / max(1.0, float(emis[..., :3].max())), 0, 1)), paths["emission"])

    baked = M.image_material("%s_mat" % name, paths["albedo"], paths["normal"], paths["orm"],
                             alpha_clip=alpha, double_sided=False, emission_path=paths.get("emission"))
    obj.data.materials.clear()
    obj.data.materials.append(baked)
    for p in obj.data.polygons:
        p.material_index = 0
    return {
        "material": baked.name,
        "textures": {k: v.name for k, v in paths.items()},
        "size": size,
        "orm_size": orm_size,
        "seconds": round(time.time() - t0, 2),
        "ao_nodes": uses_ao,
    }
