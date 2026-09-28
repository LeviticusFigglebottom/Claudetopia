"""The ground painted round the cliff pieces: rock where they stand and between them, rubble below
(triage 42's leftovers, 2026-09-28).

The terrain's textures are painted (surface.control_maps) before the cliff pieces are laid
(crags.cliff_faces, cliff_seat.fill_gaps), so they cannot know where a piece's foot is. Two things
showed:

* where a face ended in turf, the rock met the grass with a hard edge: a slab of pale rock straight
  onto green;
* the bare face between two pieces read as dark earth, not rock: the regions' steep textures
  (granite, limestone, fused stone) draw at about a tenth in linear light, and the Skerrow's and the
  Hearthvale's cliff pieces at a third. On the Skerrow wall that was "parallel columns of rock with
  bare dark terrain between them".

So once every piece is down (the build's last scatter pass, or tools/world/paint_rock.py over an
installed world), the control and colour maps are painted:

* **crag** (slot 21, pale neutral bedrock) under each piece and CRAG_EDGE_M round it, feathered out
  over CRAG_FEATHER_M with noise so the edge wanders; and over the steep ground (CRAG_SLOPE_DEG)
  within CRAG_REACH_M of rock, so a gap between pieces reads as the same rock;
* **talus** (slot 22, pale rubble) below a piece's lower edge, out to TALUS_M down the slope
  (less to its sides), thinning out into the ground's own texture with noise;
* the colour map at both tinted toward the pieces' own rock (the mean of the nearest piece's albedo
  texture, times CRAG_TONE or TALUS_TONE: a gap a little darker than the face round it), so the crag
  under Cinderlea's dark basalt is dark and under the Skerrow's pale limestone pale.

Only the cliff pieces and ledges count (PAINT_PARTS), not the boulders in the fields.
"""
from __future__ import annotations

import math
import os

import numpy as np

from . import cliff_seat as CS
from .grid import Grid, sample_bilinear
from .surface import SLOTS

CRAG = SLOTS["crag"]
TALUS = SLOTS["talus"]
PAINT_PARTS = ("_cliff_face_", "_cliff_ledge_", "_cliff_slab_", "_basalt_columns_")

## the rock under a piece reaches this far past its footprint at full strength, then feathers out
## over CRAG_FEATHER_M (half again, or less, with the noise)
CRAG_EDGE_M = 0.8
CRAG_FEATHER_M = 2.5
## the steep ground within CRAG_REACH_M of rock is rock (fading over CRAG_REACH_FEATHER_M): the
## gaps in a face; from CRAG_SLOPE_DEG[0] to full at [1]
CRAG_REACH_M = 10.0
CRAG_REACH_FEATHER_M = 8.0
CRAG_SLOPE_DEG = (38.0, 46.0)
## the rubble below a piece's lower edge: down the slope this far (times 0.7-1.3 with the noise),
## at its sides TALUS_SIDE_M; ground lower than the rock's edge by TALUS_BELOW_M is below it
TALUS_M = 9.0
TALUS_SIDE_M = 2.5
TALUS_BELOW_M = 0.3
TALUS_MAX_W = 0.85
## how dark the ground is against the rock of the pieces round it, in linear light
CRAG_TONE = 0.8
TALUS_TONE = 0.72
## what the two slots draw at: their textures' means in linear light (measured off the PNGs) times
## their `value` (game/tools_gd/import_terrain.gd SLOTS; tests/test_rock_paint.py keeps them in step)
CRAG_VALUE = 0.75
TALUS_VALUE = 0.80
TEXTURE_DIR = os.path.join("game", "assets", "textures", "terrain")
## the noise the edges wander by: two octaves, this many metres a cell
NOISE_M = (14.0, 4.0)
## less than this, and a texel is left as it was
MIN_W = 0.04

_MEANS: dict = {}


def _lin(a: np.ndarray) -> np.ndarray:
    return np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)


def _srgb(a: np.ndarray) -> np.ndarray:
    a = np.clip(a, 0.0, 1.0)
    return np.where(a <= 0.0031308, a * 12.92, 1.055 * np.power(a, 1.0 / 2.4) - 0.055)


def albedo_mean(png: str) -> np.ndarray | None:
    """The mean of an albedo texture in linear light, RGB (None where there is none)."""
    if png in _MEANS:
        return _MEANS[png]
    out = None
    try:
        from PIL import Image

        a = np.asarray(Image.open(png).convert("RGB"))[::8, ::8].astype(np.float32) / 255.0
        out = _lin(a).reshape(-1, 3).mean(axis=0)
    except (OSError, ValueError, ImportError):
        pass
    _MEANS[png] = out
    return out


def rock_tint(asset: str, repo_root: str) -> np.ndarray:
    """The piece's rock in linear light: its albedo texture's mean (a mid grey where it has none)."""
    rel = asset.replace("res://", "game/", 1)
    base = os.path.join(repo_root, os.path.splitext(rel)[0])
    m = albedo_mean(base + "_albedo.png")
    return m if m is not None else np.array([0.2, 0.2, 0.2])


def slot_draws() -> tuple:
    """(crag, talus): what the two slots draw at, linear RGB (their textures are this checkout's)."""
    repo = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
    out = []
    for name, value, fallback in (("crag", CRAG_VALUE, 0.5), ("talus", TALUS_VALUE, 0.4)):
        m = albedo_mean(os.path.join(repo, TEXTURE_DIR, "%s_albedo_height.png" % name))
        out.append((m if m is not None else np.full(3, fallback)) * value)
    return out[0], out[1]


def _noise(g: Grid, x: np.ndarray, z: np.ndarray, seed: int) -> np.ndarray:
    """Smooth noise in [0, 1] at the world points, two octaves (NOISE_M)."""
    total = np.zeros(x.shape, dtype=np.float32)
    amp = (0.65, 0.35)
    for k, cell in enumerate(NOISE_M):
        n = max(4, int(math.ceil(g.size_m / cell)) + 1)
        rng = np.random.default_rng(np.random.SeedSequence([seed, 7100 + k]))
        field = rng.random((n, n), dtype=np.float32)
        total += amp[k] * sample_bilinear(field, Grid(g.size_m, n, g.cell_size_m), x, z)
    return total


def weights(buckets: dict, H: np.ndarray, g: Grid, repo_root: str = ".", seed: int = 0) -> dict:
    """What to paint where: {i, j (the texels), crag, talus (their weights, 0..1), tint (the rock
    round them, linear RGB)}; empty where there is no rock."""
    from scipy import ndimage

    R = np.zeros((g.n, g.n), dtype=np.int32)
    tints = []
    for asset, r in CS.rock_rows(buckets, PAINT_PARTS):
        ii, jj = CS.raster(CS.footprint(r, CS.profile(asset, repo_root), CS.FACE_PART in asset), g)
        if ii.size:
            tints.append(rock_tint(asset, repo_root))
            R[ii, jj] = len(tints)
    if not tints:
        return {}
    d, ind = ndimage.distance_transform_edt(R == 0, return_indices=True)
    reach = max(CRAG_REACH_M + CRAG_REACH_FEATHER_M, TALUS_M * 1.3, CRAG_EDGE_M + CRAG_FEATHER_M * 1.5)
    ii, jj = np.nonzero(d * g.spacing <= reach)
    dd = (d[ii, jj] * g.spacing).astype(np.float32)
    ni, nj = ind[0][ii, jj], ind[1][ii, jj]
    del d, ind
    x = (g.x0 + jj * g.spacing).astype(np.float64)
    z = (g.z0 + ii * g.spacing).astype(np.float64)
    nz = _noise(g, x, z, seed)
    gx, gz = CS.smoothed_grad(H, g)
    deg = np.degrees(np.arctan(np.hypot(gx[ii, jj], gz[ii, jj]))).astype(np.float32)
    del gx, gz

    def fall(a, b, v):
        """1 up to a, 0 from b, smooth between."""
        t = np.clip((v - a) / np.maximum(b - a, 1e-3), 0.0, 1.0)
        return 1.0 - t * t * (3.0 - 2.0 * t)

    # under the piece and its edge, the edge wandering with the noise
    crag = fall(CRAG_EDGE_M, CRAG_EDGE_M + CRAG_FEATHER_M * (0.5 + nz), dd)
    # the steep ground near rock
    t = np.clip((deg - CRAG_SLOPE_DEG[0]) / (CRAG_SLOPE_DEG[1] - CRAG_SLOPE_DEG[0]), 0.0, 1.0)
    steep = t * t * (3.0 - 2.0 * t)
    crag = np.maximum(crag, steep * fall(CRAG_REACH_M, CRAG_REACH_M + CRAG_REACH_FEATHER_M * (0.6 + 0.8 * nz), dd))
    # the rubble below the rock's edge, and a little at its sides
    below = H[ii, jj] < H[ni, nj] - TALUS_BELOW_M
    out_m = np.where(below, TALUS_M * (0.7 + 0.6 * nz), TALUS_SIDE_M * (0.6 + 0.8 * nz))
    talus = (dd > 0.0) * fall(0.3 * out_m, out_m, dd) * TALUS_MAX_W * (0.75 + 0.5 * nz)
    talus = np.clip(talus, 0.0, 1.0) * (1.0 - crag)
    keep = (crag >= MIN_W) | (talus >= MIN_W)
    T = np.array(tints, dtype=np.float32)
    return {"i": ii[keep], "j": jj[keep], "crag": crag[keep].astype(np.float32),
            "talus": talus[keep].astype(np.float32), "tint": T[R[ni[keep], nj[keep]] - 1]}


def paint_control(base: np.ndarray, overlay: np.ndarray, blend: np.ndarray, w: dict) -> int:
    """In place: the crag and talus laid over the control maps (base and overlay ids, blend 0..255,
    the overlay's weight). Where the new texture is the stronger it goes in as the base, with the
    old ground's stronger texture as the overlay; where weaker, the other way round. Returns the
    number of texels painted."""
    if not w:
        return 0
    i, j = w["i"], w["j"]
    cw, tw = w["crag"], w["talus"]
    T = np.where(cw >= tw, CRAG, TALUS).astype(np.uint8)
    wt = np.clip(np.maximum(cw, tw), 0.0, 1.0)
    b0, o0, bl0 = base[i, j], overlay[i, j], blend[i, j]
    D = np.where(bl0 >= 128, o0, b0).astype(np.uint8)
    strong = wt >= 0.5
    base[i, j] = np.where(strong, T, D)
    overlay[i, j] = np.where(strong, D, T)
    blend[i, j] = np.round(np.where(strong, 1.0 - wt, wt) * 255.0).astype(np.uint8)
    return int(i.size)


def paint_colour(colour: np.ndarray, w: dict) -> None:
    """In place: the colour map (RGBA8, sRGB; Terrain3D multiplies the ground's albedo by it) under
    the crag and talus tinted so they draw at the pieces' own rock times CRAG_TONE and TALUS_TONE."""
    if not w:
        return
    crag_draw, talus_draw = slot_draws()
    i, j = w["i"], w["j"]
    cw, tw = w["crag"][:, None], w["talus"][:, None]
    tint = w["tint"]
    mc = np.clip(tint * CRAG_TONE / crag_draw[None, :], 0.0, 1.0)
    mt = np.clip(tint * TALUS_TONE / talus_draw[None, :], 0.0, 1.0)
    s = np.maximum(cw + tw, 1e-6)
    target = (mc * cw + mt * tw) / s
    k = np.clip(cw + tw, 0.0, 1.0)
    old = _lin(colour[i, j, :3].astype(np.float32) / 255.0)
    new = old * (1.0 - k) + target * k
    colour[i, j, :3] = np.round(_srgb(new) * 255.0).astype(np.uint8)


def unpack_control(ctrl: np.ndarray) -> tuple:
    """(base, overlay, blend) of Terrain3D's packed control words (output.pack_control)."""
    c = ctrl.astype(np.uint32)
    return ((c >> 27) & 0x1F).astype(np.uint8), ((c >> 22) & 0x1F).astype(np.uint8), ((c >> 14) & 0xFF).astype(np.uint8)


def repack_control(ctrl: np.ndarray, base: np.ndarray, overlay: np.ndarray, blend: np.ndarray) -> np.ndarray:
    """The control words with their base, overlay and blend replaced, every other bit (uv angle and
    scale, hole, navigation, autoshader) kept."""
    keep = ctrl.astype(np.uint32) & np.uint32(0x3FFF)
    return (keep | ((base.astype(np.uint32) & 0x1F) << 27) | ((overlay.astype(np.uint32) & 0x1F) << 22)
            | ((blend.astype(np.uint32) & 0xFF) << 14)).astype("<u4")
