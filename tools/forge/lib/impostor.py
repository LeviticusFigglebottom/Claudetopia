"""Billboard impostors: render an object to an RGBA texture and build crossed cards.

Used for tree LOD2 (DESIGN.md §7.0: generated LODs; a distant tree is two crossed cards
with a baked picture of itself). The render is lit by a white world only, so the result is
close to albedo x ambient occlusion, which matches how the LOD0 atlas is baked and keeps
the LOD pop small.
"""
from __future__ import annotations

import math
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from PIL import Image

from . import materials as M
from . import scene as S


def render_alpha(objs, out_path, size: int = 512, samples: int = 24, margin: float = 1.04,
                 pad_bottom: float = 0.0) -> dict:
    """Orthographic front render of `objs` with a transparent background.
    Returns the framing so the cards can be built at the right size."""
    objs = [o for o in objs if o is not None]
    lo, hi = S.bounds(objs)
    centre = (lo + hi) * 0.5
    width = max(hi.x - lo.x, hi.y - lo.y)
    height = (hi.z - lo.z) * (1.0 + pad_bottom)
    extent = max(width, height) * margin

    sc = bpy.context.scene
    prev = {
        "engine": sc.render.engine, "samples": sc.cycles.samples, "x": sc.render.resolution_x,
        "y": sc.render.resolution_y, "pct": sc.render.resolution_percentage,
        "transparent": sc.render.film_transparent, "path": sc.render.filepath,
        "fmt": sc.render.image_settings.file_format, "mode": sc.render.image_settings.color_mode,
        "denoise": sc.cycles.use_denoising, "camera": sc.camera,
        "bounces": sc.cycles.max_bounces, "diffuse": sc.cycles.diffuse_bounces,
    }
    cam_data = bpy.data.cameras.new("ImpostorCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = extent
    cam = bpy.data.objects.new("ImpostorCam", cam_data)
    S.link(cam)
    dist = max(10.0, extent * 3.0)
    cam.location = Vector((centre.x, centre.y - dist, centre.z))
    cam.rotation_euler = (math.radians(90), 0.0, 0.0)
    sc.camera = cam

    world = sc.world
    prev_world_nodes = world.use_nodes
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    prev_bg = (tuple(bg.inputs[0].default_value), bg.inputs[1].default_value) if bg else None
    if bg:
        bg.inputs[0].default_value = (1.0, 1.0, 1.0, 1.0)
        bg.inputs[1].default_value = 1.0

    sc.render.engine = "CYCLES"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 2
    sc.cycles.diffuse_bounces = 2
    sc.render.resolution_x = size
    sc.render.resolution_y = size
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.filepath = str(out_path)
    hidden = []
    for o in bpy.context.scene.objects:
        if o.type == "MESH" and o not in objs and not o.hide_render:
            o.hide_render = True
            hidden.append(o)
    try:
        bpy.ops.render.render(write_still=True)
    finally:
        for o in hidden:
            o.hide_render = False
        sc.render.engine = prev["engine"]
        sc.cycles.samples = prev["samples"]
        sc.cycles.use_denoising = prev["denoise"]
        sc.cycles.max_bounces = prev["bounces"]
        sc.cycles.diffuse_bounces = prev["diffuse"]
        sc.render.resolution_x = prev["x"]
        sc.render.resolution_y = prev["y"]
        sc.render.resolution_percentage = prev["pct"]
        sc.render.film_transparent = prev["transparent"]
        sc.render.filepath = prev["path"]
        sc.render.image_settings.file_format = prev["fmt"]
        sc.render.image_settings.color_mode = prev["mode"]
        sc.camera = prev["camera"]
        if bg and prev_bg:
            bg.inputs[0].default_value = prev_bg[0]
            bg.inputs[1].default_value = prev_bg[1]
        world.use_nodes = prev_world_nodes
        S.delete([cam])
        bpy.data.cameras.remove(cam_data)
    return {"extent": extent, "centre": centre, "lo": lo, "hi": hi}


def _trim_and_write(render_path: Path, out_dir: Path, prefix: str, size: int, roughness: float = 0.72) -> dict:
    """Crop the render to its alpha bounds, square it, and write albedo/normal/orm."""
    im = Image.open(render_path).convert("RGBA")
    a = np.asarray(im)[..., 3]
    ys, xs = np.nonzero(a > 6)
    if len(xs) == 0:
        box = (0, 0, im.size[0], im.size[1])
    else:
        box = (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)
    im = im.crop(box)
    w, h = im.size
    side = max(w, h)
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.paste(im, ((side - w) // 2, (side - h) // 2))
    sq = sq.resize((size, size), Image.LANCZOS)
    rgb = sq.convert("RGB")
    alpha = sq.getchannel("A")
    from . import textures as T
    T._margin_bleed(rgb, alpha, iterations=6)
    height = Image.fromarray(np.full((size, size), 128, np.uint8))
    names = T.save_set(out_dir, prefix, rgb, alpha, height, roughness=roughness, normal_strength=0.2)
    try:
        render_path.unlink()
    except OSError:
        pass
    return {"names": names, "aspect": w / float(h) if h else 1.0, "crop": box, "square": side}


def crossed_cards(objs, out_dir, prefix: str, name: str, size: int = 512, samples: int = 24,
                  cards: int = 2, threshold: float = 0.4) -> tuple:
    """Render `objs` and return (card object, textures dict) for a LOD2 impostor."""
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    tmp = out_dir / ("_%s_render.png" % prefix)
    frame = render_alpha(objs, tmp, size=size, samples=samples)
    info = _trim_and_write(tmp, out_dir, prefix, size)
    lo, hi = frame["lo"], frame["hi"]
    # The square render covers the object's larger dimension; rebuild that square in 3D.
    w = hi.x - lo.x
    hgt = hi.z - lo.z
    side = max(w, hgt)
    cx = (lo.x + hi.x) * 0.5
    cz = (lo.z + hi.z) * 0.5
    mat = M.foliage_material("%s_impostor" % name, out_dir / info["names"]["albedo"],
                             out_dir / info["names"]["normal"], out_dir / info["names"]["orm"],
                             threshold=threshold)
    mat["forge_textures"] = dict(info["names"])
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    for i in range(cards):
        ang = math.pi * i / cards
        dx, dy = math.cos(ang), math.sin(ang)
        corners = [(-0.5, 0.0), (0.5, 0.0), (0.5, 1.0), (-0.5, 1.0)]
        verts = []
        for (u, v) in corners:
            x = cx + dx * u * side
            y = dy * u * side
            z = cz - side * 0.5 + v * side
            verts.append(bm.verts.new((x, y, z)))
        f = bm.faces.new(verts)
        for loop, (u, v) in zip(f.loops, corners):
            loop[uv_layer].uv = (u + 0.5, v)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = S.bm_to_object(bm, "%s_LOD2" % name, mat, smooth=False)
    return ob, dict(info["names"])
