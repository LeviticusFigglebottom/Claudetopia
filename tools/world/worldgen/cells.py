"""Scatter placement into 256 m cells.

For every scatter rule a jittered lattice of candidate points is generated across the whole
world at the rule's ideal spacing, then thinned by region membership, slope, moisture, height,
clustering noise and the road/pad/water exclusions. Survivors are bucketed into cells and
written as `cells/<cx>_<cz>.json` in the shape fixed by docs/CONTRACTS.md section 6.
"""
from __future__ import annotations

import json
import math
import os

import numpy as np

from .grid import Grid, sample_bilinear, sample_nearest, smoothstep

HECTARE = 10000.0
## Where the forge puts what it makes. A rule names a kind ("trees/oak"); the forge builds that
## kind once per region with two or three variants ("trees/hearthvale_oak_a"), because a
## region's oaks are its own colour and one oak repeated is a wallpaper.
MODELS_DIR = "game/assets/models"


def load_rules(path: str, recipes=()) -> dict:
    """The scatter rules, with the patches of each named recipe applied.

    A recipe is a block under "recipes" in the rules file, {"dotted.path": value}: the path
    runs through keys and list indices ("rocks.forest_rise.0.density") and its last step may
    name a key that is new. The block is dropped from what is returned, so nothing reads it
    as a rule. The world build turns a recipe on with `--recipe <name>`.
    """
    with open(path, "r", encoding="utf-8") as f:
        rules = json.load(f)
    blocks = rules.pop("recipes", {})
    for name in recipes:
        for dotted, value in blocks.get(name, {}).items():
            _patch(rules, dotted, value)
    return rules


def _patch(rules: dict, dotted: str, value) -> None:
    node = rules
    steps = dotted.split(".")
    for step in steps[:-1]:
        node = node[int(step)] if isinstance(node, list) else node[step]
    if isinstance(node, list):
        node[int(steps[-1])] = value
    else:
        node[steps[-1]] = value


def asset_index(repo_root: str) -> dict:
    """category -> {name: path}, read off what the forge has actually built."""
    out: dict = {}
    base = os.path.join(repo_root, MODELS_DIR)
    if not os.path.isdir(base):
        return out
    for category in sorted(os.listdir(base)):
        cat_dir = os.path.join(base, category)
        if not os.path.isdir(cat_dir):
            continue
        names = {}
        for name in sorted(os.listdir(cat_dir)):
            if os.path.exists(os.path.join(cat_dir, name, name + ".glb")):
                names[name] = "res://assets/models/%s/%s/%s.glb" % (category, name, name)
        if names:
            out[category] = names
    return out


## Where a rule and the forge call the same thing by different names, or where the forge has
## nothing and the nearest honest neighbour will do. A missing plant is a bald hillside, so a
## sundew standing in for a marsh marigold is the better of the two wrongs — but only inside
## the same habit: nothing here substitutes a tree for a herb.
ASSET_ALIASES = {
    "flora/reed": "flora/reeds",
    "flora/briar": "flora/briar_vine",
    "flora/lichen": "flora/lichen_crust",
    "flora/red_poppy": "flora/red_poppy_single",
    "flora/waterlily": "flora/waterlily_pad",
    "flora/hawthorn": "trees/hawthorn",
    "flora/juniper": "trees/juniper",
    "props/char_stump": "trees/char_stump",
    "trees/dead_ash": "trees/dead_ash_tree",
    # No asset of their own; these are the nearest thing growing in the same ground.
    "flora/bladderwort": "flora/marsh_marigold",
    "flora/sundew": "flora/bracket_fungus",
    "flora/cottongrass": "flora/grey_grass",
    "flora/clover": "flora/grass_clump",
    "flora/market_herbs": "flora/cow_parsley",
    # Rocks. The rules name what a place would call the stone underfoot; the forge builds the
    # shapes a stone can take. A chalk boulder and a granite slab are both a slab of rock
    # shouldered out of a hillside, so they map onto the same shape and take their colour from
    # the region that owns them. "rocks/bone" is deliberately a prefix: it catches every bone
    # kind Skerrow has, so the giants' remains are fingers and ribs and skulls, not one bone.
    "rocks/flint_nodule": "rocks/boulder",
    # a chalk boulder is a boulder: the forge's cliff_slab is a 6.5 m upright slab, and
    # scattering that across rolling downland puts white monoliths on a lawn
    "rocks/chalk_boulder": "rocks/boulder",
    "rocks/shore_cobble": "rocks/boulder",
    "rocks/black_stone_shard": "rocks/cliff_slab",
    "rocks/sunken_masonry": "rocks/cliff_slab",
    "rocks/peat_hummock": "rocks/boulder",
    "rocks/mossy_boulder": "rocks/boulder",
    "rocks/granite_slab": "rocks/cliff_slab",
    "rocks/limestone_clint": "rocks/cliff_slab",
    "rocks/scree_rubble": "rocks/scree",
    "rocks/ash_drift": "rocks/scree",
    "rocks/fused_block": "rocks/cliff_slab",
    "rocks/giant_bone": "rocks/bone",
}


def assets_for(index: dict, rule_asset: str, region_short: str) -> list:
    """Every file a rule may draw on in this region, best match first.

    A rule asks for `trees/oak`. This region's own oaks win; another region's oaks are better
    than no oak at all (a hawthorn is a hawthorn); an exact name is taken as written, which is
    how a one-off asset with no variants still works.
    """
    rule_asset = ASSET_ALIASES.get(rule_asset, rule_asset)
    category, _, kind = rule_asset.partition("/")
    names = index.get(category, {})
    if not names:
        return []
    if kind in names:
        return [names[kind]]
    mine = [p for n, p in names.items() if n.startswith(region_short + "_" + kind + "_")]
    if mine:
        return mine
    anyones = [p for n, p in names.items() if n.endswith("_" + kind) or ("_" + kind + "_") in n]
    return anyones


def _hex(c) -> str:
    return "#%02x%02x%02x" % (int(c[0] * 255), int(c[1] * 255), int(c[2] * 255))


def _palette_rgb(region) -> np.ndarray:
    pal = region.palette or ["#ffffff"]
    out = []
    for h in pal:
        h = h.lstrip("#")
        out.append([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)])
    return np.array(out, dtype=np.float32)


class ScatterWorld:
    """The sampled fields a scatter pass reads."""

    def __init__(self, grid: Grid, H: np.ndarray, owner: np.ndarray, moisture: np.ndarray,
                 water: np.ndarray, road_d: np.ndarray, road_w: np.ndarray, pad_mask: np.ndarray,
                 slope: np.ndarray, bank, regions: list, water_d=None, field_d=None,
                 pad_t=None, tpi=None, forests=None):
        self.grid = grid
        self.H = H
        self.owner = owner
        self.moisture = moisture
        self.water = water
        self.road_d = road_d
        self.road_w = road_w
        self.pad = pad_mask
        self.slope = slope
        self.bank = bank
        self.regions = regions
        # distance to any water at all (river, mere, sea) and to the nearest field boundary
        self.water_d = water_d if water_d is not None else np.full(H.shape, 1e6, dtype=np.float32)
        self.field_d = field_d if field_d is not None else np.full(H.shape, 1e6, dtype=np.float32)
        # How far across a settlement's flattened platform a point lies: 0 at the place's
        # centre, 1 at the edge of its pad, large out in the country. `pad_mask` alone can
        # only say "a village stands here", and answering that with no scatter at all is what
        # made every village a mown lawn sixty metres across.
        self.pad_t = pad_t if pad_t is not None else np.full(H.shape, 9.0, dtype=np.float32)
        # How far a point stands above (or below) the ground around it, in metres: the crest of
        # a dune ridge, the floor of a sunken street, the lip of a bench. See `topographic_position`.
        self.tpi = tpi if tpi is not None else np.zeros(H.shape, dtype=np.float32)
        # the atlas's woods: {kind: 0..1 at each texel} (geography.forests)
        self.forests = dict(forests or {})

    def sample(self, x, z) -> dict:
        g = self.grid
        woods = {"forest:" + kind: sample_bilinear(w, g, x, z) for kind, w in self.forests.items()}
        return {**woods,
            "h": sample_bilinear(self.H, g, x, z),
            "owner": sample_nearest(self.owner, g, x, z),
            "moisture": sample_bilinear(self.moisture, g, x, z),
            "water": sample_nearest(self.water, g, x, z),
            "road_d": sample_nearest(self.road_d, g, x, z),
            "road_w": sample_nearest(self.road_w, g, x, z),
            "pad": sample_nearest(self.pad.astype(np.uint8), g, x, z),
            "slope": sample_bilinear(self.slope, g, x, z),
            "water_d": sample_bilinear(self.water_d, g, x, z),
            "field_d": sample_bilinear(self.field_d, g, x, z),
            "pad_t": sample_bilinear(self.pad_t, g, x, z),
            "tpi": sample_bilinear(self.tpi, g, x, z),
        }


def lean_of(cfg: dict, shape: str, water_d: np.ndarray, rng: np.random.Generator) -> tuple:
    """(lean_deg, toward_deg) per instance, or (None, None) for a rule that stands upright.

    A rule's `lean` is {shape: [min_deg, max_deg]}: on that landform its trees are bent by the
    prevailing wind, most where they stand exposed at the water (within 30 m, fading to nothing
    by 450 m) and each a little differently. They lean the way the wind blows: `wind_toward`,
    the ground direction [x, z] the atmosphere blows its wind (`wm_wind_dir` in
    systems/atmosphere/atmosphere.gd; a test keeps the two the same), give or take ten degrees.
    """
    band = (cfg.get("lean") or {}).get(shape)
    if not band:
        return None, None
    lo, hi = float(band[0]), float(band[1])
    n = int(np.asarray(water_d).size)
    exposed = 1.0 - smoothstep(30.0, 450.0, np.asarray(water_d, dtype=np.float32))
    lean = (lo + (hi - lo) * exposed) * rng.uniform(0.7, 1.0, n)
    wx, wz = (float(v) for v in cfg.get("wind_toward", (0.8, 0.6)))
    toward = math.degrees(math.atan2(wz, wx)) + rng.normal(0.0, 10.0, n)
    return lean.astype(np.float32), toward.astype(np.float32)


def topographic_position(H: np.ndarray, spacing: float, radius_m: float = 30.0) -> np.ndarray:
    """Height above the ground's own local mean, in metres: positive on crests and lips,
    negative in hollows and trenches.

    Structure is where things grow relative to the shape of the land, not only to its slope:
    marram on the crests of the dune ridges and not in the slacks between them, ash lying in
    the sunken streets and not on the blocks. Density per hectare cannot say "on the crest".
    """
    from scipy import ndimage

    smooth = ndimage.gaussian_filter(H.astype(np.float32), sigma=radius_m / spacing, mode="nearest")
    return (H - smooth).astype(np.float32)


def _candidates(rng: np.random.Generator, box: tuple, spacing: float) -> tuple:
    """Jittered lattice over `box` (x0, x1, z0, z1) in world metres; spacing is the mean distance
    between candidates. The lattice is the world's own, cut to the box, so a province's
    candidates stand where the whole world's would have."""
    x0, x1, z0, z1 = box
    step = float(spacing)
    j0, j1 = int(np.floor(x0 / step)), int(np.ceil(x1 / step))
    i0, i1 = int(np.floor(z0 / step)), int(np.ceil(z1 / step))
    bx = (np.arange(j0, j1, dtype=np.float64) + 0.5) * step
    bz = (np.arange(i0, i1, dtype=np.float64) + 0.5) * step
    gx, gz = np.meshgrid(bx.astype(np.float32), bz.astype(np.float32), indexing="xy")
    jitter = step * 0.5
    x = (gx + rng.uniform(-jitter, jitter, gx.shape)).astype(np.float32).ravel()
    z = (gz + rng.uniform(-jitter, jitter, gz.shape)).astype(np.float32).ravel()
    return x, z


def _boxes(world, regions: list) -> dict:
    """{province index: (x0, x1, z0, z1)} the world metres each province's texels span."""
    g = world.grid
    out: dict = {}
    for r in regions:
        m = world.owner == r.index
        if not m.any():
            continue
        ii = np.flatnonzero(m.any(axis=1))
        jj = np.flatnonzero(m.any(axis=0))
        out[r.index] = (g.x0 + (jj[0] - 1) * g.spacing, g.x0 + (jj[-1] + 1) * g.spacing,
                        g.z0 + (ii[0] - 1) * g.spacing, g.z0 + (ii[-1] + 1) * g.spacing)
    return out


## What a wood of each kind is made of, per hectare, where the atlas draws one: tree rules
## and their understory (scatter_rules.json `forests`). A forest entry ignores its rule's height,
## moisture and attraction bands -- the atlas says there is a wood here -- and keeps its slope
## limit and the exclusions (water, roads, pads).
FOREST_IGNORES = ("height", "moisture", "region_density", "near_water", "near_hedge", "near_lane", "tpi")


def scatter(world: ScatterWorld, rules: dict, regions: list, seed: int, cluster_noise_salt: int = 700,
            repo_root: str = ".") -> dict:
    """Returns {(cx, cz): {asset_path: [[x, y, z, yaw, scale, tint], ...]}}."""
    grid = world.grid
    index = asset_index(repo_root)
    unmatched: set = set()
    defaults = rules.get("defaults", {})
    region_mult = rules.get("region_density", {})
    woods = {k: v for k, v in rules.get("forests", {}).items() if not k.startswith("_")}
    boxes = _boxes(world, regions)
    out: dict = {}
    entries: list = []
    for r in regions:
        mult = float(region_mult.get(r.shape, 1.0))
        for key in r.flora:
            rule = rules["flora"].get(key)
            if rule is None:
                continue
            entries.append((r, key, rule, mult, None))
        for i, rule in enumerate(rules.get("rocks", {}).get(r.shape, [])):
            entries.append((r, "rock_%d" % i, rule, mult, None))
        # the atlas's woods, in this province
        for kind in sorted(world.forests):
            for key, per_ha in sorted(woods.get(kind, {}).items()):
                rule = rules["flora"].get(key)
                if rule is None:
                    continue
                wood = {k: v for k, v in rule.items() if k not in FOREST_IGNORES}
                wood["density"] = float(per_ha)
                wood.setdefault("cluster", 0.25)
                entries.append((r, "forest_%s_%s" % (kind, key), wood, 1.0, kind))
    for n, (region, key, rule, mult, wood_kind) in enumerate(entries):
        if region.index not in boxes:
            continue
        cfg = dict(defaults)
        cfg.update(rule)
        if wood_kind is not None:
            for k in FOREST_IGNORES:
                cfg.pop(k, None)
        # a rule may say what it is worth in a particular region: a wood is not a downland
        # copse at a slightly higher density, it is a different order of thing
        per_region = cfg.get("region_density", {})
        density = float(cfg.get("density", 1.0)) * float(per_region.get(region.shape, mult))
        if density <= 0.0:
            continue
        spacing = math.sqrt(HECTARE / density)
        rng = np.random.default_rng(np.random.SeedSequence([seed, 900 + n]))
        x, z = _candidates(rng, boxes[region.index], spacing)
        if x.size == 0:
            continue
        s = world.sample(x, z)
        keep = s["owner"] == region.index
        if wood_kind is not None:
            keep &= s["forest:" + wood_kind] > 0.01
        if not keep.any():
            continue
        x, z = x[keep], z[keep]
        for k in list(s.keys()):
            s[k] = s[k][keep]
        want_water = bool(cfg.get("water", False))
        acc = np.ones(x.shape, dtype=np.float32)
        if wood_kind is not None:
            acc *= s["forest:" + wood_kind]
        acc *= (s["water"] > 0) if want_water else (s["water"] == 0)
        acc *= 1.0 - smoothstep(float(cfg.get("slope_max", 0.55)) * 0.75, float(cfg.get("slope_max", 0.55)), s["slope"])
        if "slope_min" in cfg:
            acc *= smoothstep(float(cfg["slope_min"]) * 0.6, float(cfg["slope_min"]), s["slope"])
        mo = cfg.get("moisture", [0.0, 1.0])
        acc *= smoothstep(mo[0] - 0.12, mo[0] + 0.05, s["moisture"])
        acc *= 1.0 - smoothstep(mo[1] - 0.05, mo[1] + 0.12, s["moisture"])
        hr = cfg.get("height", [-40, 900])
        acc *= smoothstep(hr[0] - 12.0, hr[0] + 6.0, s["h"])
        acc *= 1.0 - smoothstep(hr[1] - 6.0, hr[1] + 12.0, s["h"])
        # keep off the carriageway and its immediate verge
        acc *= s["road_d"] > (s["road_w"] * 0.5 + 2.5)
        # A settlement's pad is flattened ground the size of the town, and excluding every
        # plant from all of it made each village the middle of a mown lawn: the Merrowby
        # street shot is taken 46 m from the centre of a 64 m pad, so nothing whatever grew
        # in the frame. Houses and the green want clear ground, but the outer part of the pad
        # is the verge -- rough grass at the foot of a wall, nettles along a fence -- and only
        # low cover belongs there. `pad_keep` is the fraction that survives out there, and
        # `pad_from` is how far across the pad the verge starts, as a fraction of its radius.
        # The settlement builder rings its houses from `ring` metres out to `pad_radius - 8`
        # (exteriors/settlement.gd), which for a town is 20 m to 56 m of a 64 m pad. So the
        # two bands that are reliably free of buildings are the green in the middle and the
        # verge outside the last house, and cover goes in both: a village green is grass, and
        # the foot of the outermost wall is rough grass and nettles.
        low = str(cfg.get("kind", "")) in ("herb", "bush")
        if low and float(cfg.get("pad_keep", 0.0)) > 0.0:
            green = float(cfg.get("pad_green", 0.22))
            outer = float(cfg.get("pad_from", 0.90))
            on_green = 1.0 - smoothstep(green - 0.07, green, s["pad_t"])
            on_verge = smoothstep(outer, outer + 0.08, s["pad_t"])
            acc *= np.where(s["pad"] > 0,
                            np.maximum(on_green, on_verge) * float(cfg["pad_keep"]), 1.0)
        else:
            acc *= s["pad"] == 0
        # Attraction bands. A landscape's strongest line-work is what grows *along* things:
        # willows and alders following every watercourse, thorn along a field boundary, a row
        # of trees marking a lane. Exclusion alone can only ever produce an even sprinkle.
        for field_key, band_key in (("water_d", "near_water"), ("field_d", "near_hedge"),
                                    ("road_d", "near_lane")):
            band = cfg.get(band_key)
            if not band:
                continue
            lo, hi = float(band[0]), float(band[1])
            strength = float(band[2]) if len(band) > 2 else 1.0
            d = s[field_key]
            # 1 inside the band, falling away either side over a third of its width
            soft = max((hi - lo) * 0.35, 1.5)
            inside = smoothstep(lo - soft, lo + soft * 0.3, d) * (1.0 - smoothstep(hi - soft * 0.3, hi + soft, d))
            acc *= (1.0 - strength) + strength * inside
        # where it stands in the shape of the land: `tpi` [from_m, to_m, strength] of height
        # above the local mean (a crest is positive, a hollow negative)
        band = cfg.get("tpi")
        if band:
            lo, hi = float(band[0]), float(band[1])
            strength = float(band[2]) if len(band) > 2 else 1.0
            inside = smoothstep(lo - 0.3, lo + 0.1, s["tpi"]) * (1.0 - smoothstep(hi - 0.1, hi + 0.3, s["tpi"]))
            acc *= (1.0 - strength) + strength * inside
        # clustering: a low-frequency field decides where this species actually grows
        cl = float(cfg.get("cluster", 0.35))
        if cl > 0.0:
            field = world.bank.field_at(cluster_noise_salt + n, min(grid.n, 1024), beta=1.8,
                                        wl_min=float(cfg.get("rows", 60.0)), wl_max=420.0)
            g2 = grid.with_n(field.shape[0])
            cf = 0.5 + 0.5 * np.tanh(sample_bilinear(field, g2, x, z))
            # A gate, not a gentle multiplier. Trees come in copses and shelter belts with real
            # open ground between them; scaling every candidate by 0.45 to 1.45 only produces an
            # even sprinkle that is slightly lumpy. Below the threshold the species is simply
            # absent, above it the ground is thick with it.
            thresh = float(cfg.get("cluster_threshold", 0.46))
            gate = smoothstep(thresh, thresh + float(cfg.get("cluster_edge", 0.16)), cf)
            acc *= (1.0 - cl) + cl * gate * float(cfg.get("cluster_boost", 2.6))
        draw = rng.random(x.shape).astype(np.float32)
        take = draw < np.clip(acc, 0.0, 1.0)
        if not take.any():
            continue
        x, z = x[take], z[take]
        y = s["h"][take]
        scale_lo, scale_hi = cfg.get("scale", [0.85, 1.2])
        scale = rng.uniform(scale_lo, scale_hi, x.shape).astype(np.float32)
        yaw = rng.uniform(0.0, 360.0, x.shape).astype(np.float32) if cfg.get("yaw_random", True) else np.zeros_like(x)
        pal = _palette_rgb(region)
        # Which of the region's six colours this species is painted from. Everything used to
        # take entry 1, so a region's grass, its ferns and its heather were all the same
        # colour and the ground read as one flat wash; a rule now names its own voice, and
        # flowers take the accent that makes them worth seeing.
        idx = int(cfg.get("tint_index", 1))
        if idx < 0 or pal.shape[0] == 0:
            # the one red poppy in Cinderlea is the colour the forge made it, and multiplying
            # it by an ash-grey palette entry is how you lose the only red in a region
            base_col = np.ones(3, dtype=np.float32)
        else:
            # A modulation, not a coat of paint. The forge already builds every asset from
            # its region's palette, so multiplying that palette over it again doubles the
            # colour: gold barley times gold, red poppies times red, and a downland vista
            # came back littered with orange slabs. `tint_strength` is how far from white the
            # multiplier is allowed to travel.
            strength = float(cfg.get("tint_strength", 0.45))
            base_col = (1.0 - strength) + strength * pal[idx % pal.shape[0]]
        # Jitter one plant against the next. Almost all of it is *lightness*: a field of grass
        # varies from tuft to tuft in how pale and how dry it is, not in hue. Drawing three
        # independent normals, one per channel, moves the hue instead -- at a sigma of 0.12
        # that is a third of a channel, and the moor came back scattered with yellow, orange,
        # violet and blue clumps like confetti. It had always been written that way and never
        # showed, because the foliage shader ignored the instance colour until today.
        jit = float(cfg.get("tint_jitter", 0.07))
        light = rng.normal(0.0, jit, (x.size, 1))
        hue = rng.normal(0.0, jit * 0.28, (x.size, 3))
        tints = np.clip(base_col[None, :] * (1.0 + light + hue), 0.25, 1.0)
        # A tree the wind has worked on for a hundred years leans away from it.
        # (its own draws, so bending a species changes nothing else about where it stands)
        lean, toward = lean_of(cfg, region.shape, s["water_d"][take],
                               np.random.default_rng(np.random.SeedSequence([seed, 9900 + n])))
        # This region's own variants of the thing the rule names. Spreading the instances over
        # them is what stops a hillside being one tree printed four hundred times.
        variants = assets_for(index, str(cfg["asset"]), region.art_short)
        if not variants:
            unmatched.add(str(cfg["asset"]))
            continue
        pick = rng.integers(0, len(variants), x.shape)
        cx, cz = grid.cell_of(x, z)
        cx = np.clip(cx, 0, grid.cells - 1)
        cz = np.clip(cz, 0, grid.cells - 1)
        keys = cx.astype(np.int64) * grid.cells + cz.astype(np.int64)
        order = np.argsort(keys, kind="stable")
        keys_s = keys[order]
        bounds = np.searchsorted(keys_s, np.unique(keys_s))
        uniq = np.unique(keys_s)
        for bi, k in enumerate(uniq):
            lo = bounds[bi]
            hi = bounds[bi + 1] if bi + 1 < bounds.size else keys_s.size
            sel = order[lo:hi]
            ccx, ccz = int(k // grid.cells), int(k % grid.cells)
            bucket = out.setdefault((ccx, ccz), {})
            for t in sel:
                lst = bucket.setdefault(variants[int(pick[t])], [])
                row = [round(float(x[t]), 2), round(float(y[t]), 2), round(float(z[t]), 2),
                       round(float(yaw[t]), 1), round(float(scale[t]), 3), _hex(tints[t])]
                if lean is not None:
                    row += [round(float(lean[t]), 1), round(float(toward[t]), 1)]
                lst.append(row)
    if unmatched:
        print("[world] no asset for: %s" % ", ".join(sorted(unmatched)), flush=True)
    return out


def cell_region_ids(world: ScatterWorld, regions: list) -> dict:
    """Dominant region id per cell: the content region most of the cell's provinces belong to."""
    grid = world.grid
    per = grid.texels_per_cell
    ids = sorted({r.id for r in regions})
    of_province = np.array([ids.index(r.id) for r in sorted(regions, key=lambda r: r.index)], dtype=np.int32)
    own = of_province[world.owner]
    out = {}
    view = own.reshape(grid.cells, per, grid.cells, per)
    for cz in range(grid.cells):
        for cx in range(grid.cells):
            block = view[cz, :, cx, :]
            vals, cnt = np.unique(block, return_counts=True)
            out[(cx, cz)] = ids[int(vals[int(np.argmax(cnt))])]
    return out
