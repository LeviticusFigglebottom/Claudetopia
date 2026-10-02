"""Impostors for the forge's trees: the tree drawn from eight sides, for the game to light.

    blender -b --python tools/forge/gen_impostors.py -- --name hearthvale_oak_a_impostor \\
        --category trees --kind oak --palette hearthvale --variant a

It does not rebuild the tree. It reads the committed tree (`<tree>/<tree>.glb`, the name with
`_impostor` taken off), renders its LOD0 from eight directions around it, and writes into the
tree's own folder:

  <tree>_impostor_albedo.png   3x3 atlas, 128 px a view: base colour (sRGB) and coverage
  <tree>_impostor_nrm.png      the same at half size: object-space normal (Godot axes, biased
                               to 0..1) and, in alpha, how much of the sky each point sees

It then replaces the tree's LOD2 in the GLB -- until now four crossed cards carrying one front
view -- with a single quad carrying the atlas, and records the frame in the tree's meta.json
under "impostor". `tools_gd/glb_post_import.gd` turns that quad into a billboard
(`assets/shaders/tree_impostor.gdshader`) and the world streamer draws it past the distance
where a tree is a few dozen pixels tall.

Why eight views and not the old cross. Four crossed cards of one picture are the same tree
from every side, shaded as four flat planes: from the front it reads, from anywhere else the
planes show, and lit by a low sun half of them go dark. A picture of the tree from the side you
are standing on, turned to face you and lit through its own normals, reads as the tree from
every side at two triangles. The views are taken level (the billboard stands upright, rooted at
the trunk, and turns about the trunk), which is what a tree a hundred metres off is seen from.

Colour management: the passes are read as linear floats from an EXR and written through the
sRGB curve here, so Blender's default AgX view transform -- which the old impostor render went
through -- does not shift the impostor's colour away from the mesh it stands in for.

Weight: the atlases replace the old impostor's three textures in the same folder, and the
library's total is pinned by tests/test_output.py; the per-tree cost is printed.
"""
from __future__ import annotations

import json
import math
import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from lib import cli  # noqa: E402
from lib import export as E  # noqa: E402
from lib import glb as G  # noqa: E402
from lib import lod_repair as LR  # noqa: E402

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Vector  # noqa: E402

VIEWS = 8
GRID = 3            # 3x3 cells; the ninth is left empty
CELL = 128          # px a view in the colour atlas (an entry's params may say "cell": 256)
NRM_CELL = 64       # px a view in the normal atlas (half the colour's)
SUPERSAMPLE = 2     # rendered at twice the cell and averaged down
SAMPLES = 48
MARGIN_SIDE = 1.04  # frame width over the widest reach from the trunk
MARGIN_TOP = 1.03
RECIPE = 1          # bump to re-render every impostor (it is in each entry's params)


def parse_args():
    args = cli.parse("Wickmere impostor generator")
    if not args.name or not args.name.endswith("_impostor"):
        raise SystemExit("--name must be <tree>_impostor")
    return args


# --- scene ----------------------------------------------------------------------------------

def load_tree(glb: Path, tree: str):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(glb))
    lod0 = bpy.data.objects.get(tree)
    if lod0 is None:
        raise SystemExit("no LOD0 object %r in %s" % (tree, glb))
    for o in list(bpy.data.objects):
        if o is not lod0:
            bpy.data.objects.remove(o, do_unlink=True)
    return lod0


def frame_of(obj) -> dict:
    """The billboard frame in Godot object space: a vertical axis through the middle of the
    tree's footprint, the widest reach from it, and the height."""
    mw = obj.matrix_world
    co = np.array([tuple(mw @ v.co) for v in obj.data.vertices], dtype=np.float64)
    gx, gy, gz = co[:, 0], co[:, 2], -co[:, 1]          # Blender Z-up -> Godot Y-up
    ax = float((gx.min() + gx.max()) * 0.5)
    az = float((gz.min() + gz.max()) * 0.5)
    reach = float(np.sqrt((gx - ax) ** 2 + (gz - az) ** 2).max())
    y0, y1 = float(gy.min()), float(gy.max())
    width = 2.0 * reach * MARGIN_SIDE
    height = (y1 - y0) * MARGIN_TOP
    bottom = y0 - (y1 - y0) * 0.01
    return {"axis": [round(ax, 4), round(az, 4)], "width": round(width, 4),
            "bottom": round(bottom, 4), "height": round(height, 4)}


def setup_render(sc) -> None:
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = SAMPLES
    sc.cycles.use_denoising = False
    sc.cycles.use_adaptive_sampling = False
    # Leaf cards are layered deep: past the default eight transparent hits a ray stops, and a
    # canopy renders as a dark plate with light only at its rim.
    sc.cycles.transparent_max_bounces = 96
    sc.cycles.max_bounces = 4
    sc.cycles.diffuse_bounces = 2
    sc.render.film_transparent = True
    sc.render.use_compositing = False
    sc.render.use_sequencer = False
    sc.render.image_settings.file_format = "OPEN_EXR_MULTILAYER"
    sc.render.image_settings.color_depth = "32"
    sc.render.image_settings.exr_codec = "ZIP"
    vl = sc.view_layers[0]
    vl.use_pass_diffuse_color = True
    vl.use_pass_diffuse_direct = True
    vl.use_pass_normal = True
    vl.pass_alpha_threshold = 0.5
    _setup_pass_files(sc)
    world = bpy.data.worlds.new("White")
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (1.0, 1.0, 1.0, 1.0)
    bg.inputs[1].default_value = 1.0
    sc.world = world


PASS_SLOTS = ("Image", "DiffCol", "DiffDir", "Normal")


def _have_oiio() -> bool:
    try:
        import OpenImageIO  # noqa: F401
        return True
    except ImportError:
        return False


def _setup_pass_files(sc) -> None:
    """Without OpenImageIO (a distribution's Blender leaves it out) the multilayer EXR cannot be
    read back in Blender's Python. The compositor then writes each pass as its own plain EXR, which
    `bpy.data.images` reads (`read_passes`)."""
    if _have_oiio():
        return
    sc.use_nodes = True
    sc.render.use_compositing = True
    nt = sc.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    rl = nt.nodes.new("CompositorNodeRLayers")
    out = nt.nodes.new("CompositorNodeOutputFile")
    out.name = "PassFiles"
    out.format.file_format = "OPEN_EXR"
    out.format.color_depth = "32"
    out.format.color_mode = "RGBA"
    out.file_slots.clear()
    for name in PASS_SLOTS:
        out.file_slots.new(name)
        nt.links.new(rl.outputs[name], out.inputs[name])
    comp = nt.nodes.new("CompositorNodeComposite")
    nt.links.new(rl.outputs["Image"], comp.inputs["Image"])


def _point_pass_files(sc, path: Path) -> None:
    node = sc.node_tree.nodes.get("PassFiles") if sc.node_tree else None
    if node is None:
        return
    node.base_path = str(path.parent)
    for slot, name in zip(node.file_slots, PASS_SLOTS):
        slot.path = "%s_%s_" % (path.stem, name)


def render_view(sc, frame: dict, azimuth: float, path: Path, cell: int = CELL) -> None:
    """One level view from `azimuth` (radians about Godot +Y, 0 = from +Z)."""
    ax, az = frame["axis"]
    mid_y = frame["bottom"] + frame["height"] * 0.5
    target = Vector((ax, -az, mid_y))                       # Godot -> Blender
    d = Vector((math.sin(azimuth), -math.cos(azimuth), 0.0))
    dist = 3.0 * max(frame["width"], frame["height"]) + 10.0
    cam_data = bpy.data.cameras.new("ImpostorCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = max(frame["width"], frame["height"])
    cam_data.clip_end = dist * 3.0
    cam = bpy.data.objects.new("ImpostorCam", cam_data)
    sc.collection.objects.link(cam)
    cam.location = target + d * dist
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    sc.camera = cam
    big = SUPERSAMPLE * cell
    if frame["width"] >= frame["height"]:
        rx, ry = big, max(8, round(big * frame["height"] / frame["width"]))
    else:
        rx, ry = max(8, round(big * frame["width"] / frame["height"])), big
    sc.render.resolution_x = rx
    sc.render.resolution_y = ry
    sc.render.resolution_percentage = 100
    sc.render.filepath = str(path)
    _point_pass_files(sc, path)
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam, do_unlink=True)
    bpy.data.cameras.remove(cam_data)


# --- passes -----------------------------------------------------------------------------------

def _read_plain(path: Path) -> np.ndarray:
    """A plain EXR through Blender's own reader, as (h, w, 4) floats with the first row at the top."""
    img = bpy.data.images.load(str(path), check_existing=False)
    img.colorspace_settings.name = "Non-Color"
    w, h = img.size
    px = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return px.reshape(h, w, 4)[::-1]


def read_passes(path: Path) -> dict:
    if not _have_oiio():
        frame = "%04d" % bpy.context.scene.frame_current
        got = {name: _read_plain(path.parent / ("%s_%s_%s.exr" % (path.stem, name, frame))) for name in PASS_SLOTS}
        return {
            "alpha": got["Image"][:, :, 3],
            "albedo": got["DiffCol"][:, :, :3],
            "sky": got["DiffDir"][:, :, :3].mean(axis=2),
            "normal": got["Normal"][:, :, :3],
        }
    import OpenImageIO as oiio
    inp = oiio.ImageInput.open(str(path))
    if inp is None:
        raise SystemExit("cannot read %s: %s" % (path, oiio.geterror()))
    spec = inp.spec()
    px = inp.read_image(0, 0, 0, spec.nchannels, "float")
    inp.close()
    px = np.asarray(px, dtype=np.float32).reshape(spec.height, spec.width, spec.nchannels)
    names = list(spec.channelnames)

    def ch(suffix: str) -> np.ndarray:
        for i, n in enumerate(names):
            if n.endswith(suffix):
                return px[:, :, i]
        raise SystemExit("%s has no channel *%s (has %s)" % (path, suffix, names))

    return {
        "alpha": ch("Combined.A"),
        "albedo": np.stack([ch("DiffCol.R"), ch("DiffCol.G"), ch("DiffCol.B")], axis=-1),
        "sky": (ch("DiffDir.R") + ch("DiffDir.G") + ch("DiffDir.B")) / 3.0,
        "normal": np.stack([ch("Normal.X"), ch("Normal.Y"), ch("Normal.Z")], axis=-1),
    }


def _resize(a: np.ndarray, size: tuple[int, int]) -> np.ndarray:
    from PIL import Image
    if a.ndim == 2:
        return np.asarray(Image.fromarray(a.astype(np.float32), "F").resize(size, Image.BILINEAR))
    return np.stack([_resize(a[:, :, i], size) for i in range(a.shape[2])], axis=-1)


## How much of each texel's normal is the canopy's rounded envelope rather than the leaf card
## the ray happened to hit. Cards face every way; lit through their own normals alone a crown
## reads as green static with no light side and no shade side, which is exactly what the mesh
## avoids by shadowing itself. The envelope gives it the shape of a crown in the light.
ENVELOPE = 0.6


def view_basis(azimuth: float) -> tuple:
    """The view's right, up and toward-the-camera axes in Godot object space."""
    back = np.array([math.sin(azimuth), 0.0, math.cos(azimuth)])
    up = np.array([0.0, 1.0, 0.0])
    right = np.cross(-back, up)
    return right / np.linalg.norm(right), up, back


def envelope_normals(alpha: np.ndarray, azimuth: float) -> np.ndarray:
    """A rounded normal from the silhouette: blur the coverage, and let its slope tip the normal
    outward at the edge while the dense middle faces the viewer."""
    from PIL import Image, ImageFilter
    h, w = alpha.shape
    sigma = max(1.5, 0.07 * max(h, w))
    img = Image.fromarray((np.clip(alpha, 0, 1) * 255).astype(np.uint8), "L")
    blur = np.asarray(img.filter(ImageFilter.GaussianBlur(sigma)), dtype=np.float32) / 255.0
    gy, gx = np.gradient(blur)                 # rows go down the image
    k = 2.2 * max(h, w) / 64.0
    vx, vy = -gx * k, gy * k                   # outward, in view space (y up)
    vz = np.clip(blur, 0.15, 1.0)
    v = np.stack([vx, vy, vz], axis=-1)
    v = v / np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), 1e-6)
    right, up, back = view_basis(azimuth)
    return v[..., 0:1] * right + v[..., 1:2] * up + v[..., 2:3] * back


def to_cell(p: dict, cell: int, azimuth: float) -> dict:
    """The passes as one view's cell: premultiplied, resampled to the cell, unpremultiplied."""
    a = np.clip(p["alpha"], 0.0, 1.0)
    size = (cell, cell)
    a_c = np.clip(_resize(a, size), 0.0, 1.0)
    safe = np.maximum(a_c, 1e-4)[..., None]
    # DiffCol and the light passes are accumulated with coverage; divide it back out
    albedo = _resize(p["albedo"], size) / safe
    sky = _resize(p["sky"], size) / safe[..., 0]
    # the normal pass comes from surfaces over the alpha threshold only; weight it by coverage
    n = _resize(p["normal"] * a[..., None], size)
    n_len = np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-6)
    n = n / n_len
    # Blender Z-up -> Godot Y-up
    n = np.stack([n[..., 0], n[..., 2], -n[..., 1]], axis=-1)
    n = (1.0 - ENVELOPE) * n + ENVELOPE * envelope_normals(a_c, azimuth)
    n = n / np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-6)
    return {"alpha": a_c, "albedo": np.clip(albedo, 0.0, 1.0), "sky": np.clip(sky, 0.0, 1.0),
            "normal": n}


def bleed(values: np.ndarray, alpha: np.ndarray, iterations: int = 3) -> np.ndarray:
    """Grow the covered texels' values a few texels outward, so filtering at the silhouette
    never reaches the black behind it, and fill the rest of the transparent area with the
    covered texels' mean. Not further: a colour bled across the whole empty cell is noise to
    PNG and doubled the atlas's weight, and past a few texels nothing ever samples it (Godot's
    importer fixes the alpha border again on import)."""
    v = values.copy()
    covered = alpha > 0.02
    mask = covered.copy()
    for _ in range(iterations):
        if mask.all():
            break
        grown = mask.copy()
        acc = np.zeros_like(v)
        cnt = np.zeros(mask.shape, dtype=np.float32)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            sv = np.roll(np.roll(v, dy, 0), dx, 1)
            sm = np.roll(np.roll(mask, dy, 0), dx, 1)
            take = sm & ~mask
            acc[take] += sv[take]
            cnt[take] += 1.0
            grown |= sm
        new = grown & ~mask
        v[new] = acc[new] / cnt[new][..., None] if v.ndim == 3 else acc[new] / cnt[new]
        mask = grown
    if covered.any():
        v[~mask] = v[covered].mean(axis=0)
    return v


def srgb(c: np.ndarray) -> np.ndarray:
    c = np.clip(c, 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1.0 / 2.4) - 0.055)


def atlas(cells: list, cell: int, key: str) -> np.ndarray:
    size = GRID * cell
    ch = 4
    out = np.zeros((size, size, ch), dtype=np.float32)
    for i, c in enumerate(cells):
        col, row = i % GRID, i // GRID
        y, x = row * cell, col * cell
        if key == "albedo":
            rgb = srgb(bleed(c["albedo"], c["alpha"]))
            out[y:y + cell, x:x + cell, :3] = rgb
            out[y:y + cell, x:x + cell, 3] = c["alpha"]
        else:
            n = bleed(c["normal"], c["alpha"])
            n = n / np.maximum(np.linalg.norm(n, axis=-1, keepdims=True), 1e-6)
            out[y:y + cell, x:x + cell, :3] = n * 0.5 + 0.5
            out[y:y + cell, x:x + cell, 3] = bleed(c["sky"], c["alpha"])
    # the empty ninth cell: a flat, fully lit, uncovered block
    if key != "albedo":
        for i in range(len(cells), GRID * GRID):
            col, row = i % GRID, i // GRID
            out[row * cell:(row + 1) * cell, col * cell:(col + 1) * cell] = (0.5, 1.0, 0.5, 1.0)
    return out


def write_png(a: np.ndarray, path: Path) -> None:
    from PIL import Image
    img = Image.fromarray(np.clip(np.round(a * 255.0), 0, 255).astype(np.uint8), "RGBA")
    img.save(path, optimize=True)


def write_palette_png(a: np.ndarray, path: Path) -> None:
    """The colour atlas as 255 median-cut colours and one transparent index.

    Foliage at 128 px is nearly incompressible as RGBA -- 180 KB a tree, which the library's
    weight ceiling cannot carry thirty-five times. The impostor is alpha-tested, so its coverage
    is binary on screen whatever the file holds, and 255 colours chosen by median cut keep the
    bark's highlights where the octree quantiser dulled them: 54 KB, and side by side at four
    times its size nothing but the hard alpha edge tells the two apart."""
    from PIL import Image
    rgba = np.clip(np.round(a * 255.0), 0, 255).astype(np.uint8)
    rgb = Image.fromarray(rgba[..., :3], "RGB")
    q = rgb.quantize(255, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    idx = np.asarray(q).copy()
    idx[rgba[..., 3] < 128] = 255
    pal = (q.getpalette() or [])[:255 * 3]
    pal += [0] * (255 * 3 - len(pal)) + [0, 0, 0]
    out = Image.fromarray(idx.astype(np.uint8), "P")
    out.putpalette(pal)
    out.save(path, optimize=True, transparency=255)


# --- the GLB and the meta -----------------------------------------------------------------------

def rewrite_lod2(glb_path: Path, tree: str, frame: dict, albedo_uri: str) -> None:
    """LOD2 becomes one upright quad facing +Z, the width and height of the frame, rooted at
    the frame's bottom on the trunk axis. Its material is `<tree>_impostor`; the post-import
    step gives it the billboard shader."""
    gltf, bin_chunk = G.read_glb(glb_path)
    lod2 = "%s_LOD2" % tree
    ax, az = frame["axis"]
    hw = frame["width"] * 0.5
    y0 = frame["bottom"]
    y1 = y0 + frame["height"]
    positions = [[ax - hw, y0, az], [ax + hw, y0, az], [ax + hw, y1, az], [ax - hw, y1, az]]
    normals = [[0.0, 0.0, 1.0]] * 4
    uvs = [[0.0, 1.0], [1.0, 1.0], [1.0, 0.0], [0.0, 0.0]]
    indices = [0, 1, 2, 0, 2, 3]
    # the material: the old impostor's, renamed, with only the atlas left on it
    mats = gltf.setdefault("materials", [])
    name = "%s_impostor" % tree
    mi = next((i for i, m in enumerate(mats) if m.get("name", "").startswith(name)), None)
    images = gltf.setdefault("images", [])
    images.append({"uri": albedo_uri})
    textures = gltf.setdefault("textures", [])
    tex = {"source": len(images) - 1}
    if gltf.get("samplers"):
        tex["sampler"] = 0
    textures.append(tex)
    mat = {"name": name, "doubleSided": True, "alphaMode": "MASK", "alphaCutoff": 0.5,
           "pbrMetallicRoughness": {"baseColorTexture": {"index": len(textures) - 1},
                                    "metallicFactor": 0.0, "roughnessFactor": 0.85}}
    if mi is None:
        mats.append(mat)
        mi = len(mats) - 1
    else:
        mats[mi] = mat
    bin_chunk = G.replace_mesh_geometry(gltf, bin_chunk, lod2, positions, normals, uvs, indices, mi)
    bin_chunk = G.prune(gltf, bin_chunk)
    G.write_glb(glb_path, gltf, bin_chunk)


def main() -> None:
    args = parse_args()
    tree = args.name[: -len("_impostor")]
    cli.validate_name(tree)
    category = args.category or "trees"
    paths = cli.output_paths(args.out, category, tree)
    meta_path, glb_path, d = paths["meta"], paths["glb"], paths["dir"]
    if not meta_path.exists() or not glb_path.exists():
        print("FORGE_FAIL %s/%s (no tree to draw an impostor of)" % (category, args.name))
        sys.exit(2)
    meta = json.loads(meta_path.read_text(encoding="utf-8"))
    # A tree whose picture is drawn nearer (world/scatter_lod.gd puts the line where the picture's
    # texels match the screen's, so twice the cell is half the distance) has a larger cell: the
    # Greatwood's giant oaks and black ash, whose mid rung out to ten heights was most of the
    # wood's primitives (PROGRESS, "Far-tree impostors").
    cell = int(dict(args.params).get("cell", CELL))
    nrm_cell = cell // 2
    lod0 = load_tree(glb_path, tree)
    frame = frame_of(lod0)
    sc = bpy.context.scene
    setup_render(sc)
    cells_c, cells_n = [], []
    with tempfile.TemporaryDirectory() as td:
        for k in range(VIEWS):
            exr = Path(td) / ("view_%d.exr" % k)
            azimuth = 2.0 * math.pi * k / VIEWS
            render_view(sc, frame, azimuth, exr, cell)
            p = read_passes(exr)
            cells_c.append(to_cell(p, cell, azimuth))
            cells_n.append(to_cell(p, nrm_cell, azimuth))
    albedo_name = "%s_impostor_albedo.png" % tree
    nrm_name = "%s_impostor_nrm.png" % tree
    write_palette_png(atlas(cells_c, cell, "albedo"), d / albedo_name)
    write_png(atlas(cells_n, nrm_cell, "normal"), d / nrm_name)
    rewrite_lod2(glb_path, tree, frame, albedo_name)
    # The picture is the far rung; the mid rung is repaired on the same pass, because it is
    # the ladder's weakest step: see lib/lod_repair.py.
    lod1_repair = LR.repair_lod1(glb_path, tree, float(meta.get("bounds", {}).get("height", frame["height"])))
    # The old impostor's normal and ORM maps are nobody's now.
    old = ["%s_impostor_normal.png" % tree, "%s_impostor_orm.png" % tree]
    for f in old:
        for p in (d / f, d / (f + ".import")):
            if p.exists():
                p.unlink()
    meta["textures"] = [t for t in meta.get("textures", []) if t not in old]
    if nrm_name not in meta["textures"]:
        meta["textures"].append(nrm_name)
    if albedo_name not in meta["textures"]:
        meta["textures"].append(albedo_name)
    summary = G.summary(glb_path)
    meta["meshes"] = summary["meshes"]
    meta["materials"] = summary["materials"]
    lod2_tris = next((m["tris"] for m in summary["meshes"] if m["name"] == "%s_LOD2" % tree), 2)
    tris = list(meta.get("tris", [0, 0, 0]))
    while len(tris) < 3:
        tris.append(tris[-1] if tris else 0)
    tris[2] = lod2_tris
    by_name = {m["name"]: m["tris"] for m in summary["meshes"]}
    tris[1] = by_name.get("%s_LOD1" % tree, 0) + by_name.get("%s_cards_LOD1" % tree, 0)
    meta["tris"] = tris
    prior = meta.get("lod1_repair", {})
    lod1_repair["dropped"] += int(prior.get("dropped", 0))
    lod1_repair["area_m2"] = round(lod1_repair["area_m2"] + float(prior.get("area_m2", 0.0)), 2)
    meta["lod1_repair"] = lod1_repair
    params = dict(args.params)
    meta["impostor"] = {
        "generator": "gen_impostors", "recipe": RECIPE,
        "hash": cli.asset_hash("gen_impostors", cli.FORGE_VERSION, args.name, args.kind or "",
                               params, args.seed, args.palette),
        "source_hash": meta.get("hash", ""),
        "views": VIEWS, "grid": GRID, "cell": cell, "normal_cell": nrm_cell,
        "billboard": "upright", "elevation_deg": 0.0,
        "albedo": albedo_name, "normal": nrm_name, **frame,
    }
    E.write_meta(meta_path, meta)
    E.write_import_sidecars(d, glb_path.name, [albedo_name, nrm_name])
    kb = ((d / albedo_name).stat().st_size + (d / nrm_name).stat().st_size) / 1024.0
    print("FORGE_OK %s/%s views=%d frame=%.2fx%.2f m atlases=%.0f KB tris=%s"
          % (category, args.name, VIEWS, frame["width"], frame["height"], kb, tris))


if __name__ == "__main__":
    main()
