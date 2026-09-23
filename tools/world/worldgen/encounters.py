"""Where things that fight you stand.

The scatter pass decides where a plant grows; this decides where a wolf waits. The rules are
the ones a person would use walking the map: nothing inside a settlement's pad or on the road
itself, more of it the further you are from a hearth, the region's own creatures and nobody
else's, and packs that stand together rather than a list of lone animals sprinkled evenly.

Written into each cell as `spawns` (CONTRACTS §6):
    {"kind": "enemy", "def": "core:enemy/x", "pos": [x, y, z], "yaw": deg, "group": "g12_3"}
"""
from __future__ import annotations

import json
import math
import os

import numpy as np

from .grid import Grid, sample_bilinear, sample_nearest

# How much ground one encounter wants, per region danger step. A dangerous country is not only
# fought by harder things, it is fought more often.
AREA_PER_ENCOUNTER_M2 = {1: 210_000.0, 2: 170_000.0, 3: 140_000.0, 4: 120_000.0, 5: 100_000.0}
# Nobody camps in the square outside the inn, and the verge of a road is walked too often.
PAD_CLEAR_M = 40.0
ROAD_CLEAR_M = 14.0
# Within this of a settlement the country is worked, patrolled and safe; it fades out to
# SAFE_FADE_M, beyond which the full density applies.
SAFE_M = 120.0
SAFE_FADE_M = 420.0
## Group shapes by archetype: how many stand together, and how far apart.
GROUPS = {
    "pack": (3, 5, 7.0),
    "swarm": (4, 7, 6.0),
    "skirmisher": (2, 3, 6.0),
    "bandit": (2, 4, 8.0),
    "charger": (1, 2, 9.0),
    "brute": (1, 1, 0.0),
    "sentinel": (1, 1, 0.0),
    "ambusher": (1, 2, 12.0),
    "caster": (1, 2, 9.0),
    "elite": (1, 1, 0.0),
    "lure": (1, 1, 0.0),
}
DEFAULT_GROUP = (1, 2, 8.0)


def _ecology(regions: list) -> dict:
    """region id -> [enemy def], off the region defs the builder already loaded."""
    return {r.id: list(getattr(r, "ecology", []) or []) for r in regions}


def _enemy_defs(packs_dir: str) -> dict:
    """enemy id -> def, for archetype and whether it belongs out in the country at all."""
    out = {}
    enemies_dir = os.path.join(packs_dir, "enemies")
    if not os.path.isdir(enemies_dir):
        return out
    for name in sorted(os.listdir(enemies_dir)):
        if not name.endswith(".json"):
            continue
        with open(os.path.join(enemies_dir, name), "r", encoding="utf-8") as f:
            data = json.load(f)
        for e in (data if isinstance(data, list) else data.get("entries", [])):
            if isinstance(e, dict) and "id" in e:
                out[str(e["id"])] = e
    return out


def _danger(regions: list) -> dict:
    return {r.id: int(getattr(r, "danger", 1) or 1) for r in regions}


def place(world, regions: list, places: list, packs_dir: str, seed: int) -> dict:
    """Returns {(cx, cz): [spawn, ...]}."""
    grid: Grid = world.grid
    rng = np.random.default_rng(seed ^ 0x5CA1AB1E)
    ecology = _ecology(regions)
    defs = _enemy_defs(packs_dir)
    danger = _danger(regions)

    hearths = np.array([[float(p["position"][0]), float(p["position"][1])] for p in places
                        if str(p.get("kind", "")) in
                        ("city", "town", "village", "hamlet", "fort", "camp", "lodge")],
                       dtype=np.float32)

    out: dict = {}
    for r in regions:
        pool = [e for e in ecology.get(r.id, []) if e in defs]
        if not pool:
            continue
        area = float(AREA_PER_ENCOUNTER_M2.get(danger.get(r.id, 1), 180_000.0))
        # Candidate points over the whole world, thinned to this region below: a jittered
        # lattice, so encounters are spread rather than clumped by luck.
        step = math.sqrt(area)
        n = max(int(grid.size_m / step), 2)
        gx, gz = np.meshgrid(np.linspace(0, grid.size_m, n, endpoint=False),
                             np.linspace(0, grid.size_m, n, endpoint=False))
        x = (gx.ravel() + rng.uniform(0.0, step, gx.size)) - grid.size_m * 0.5
        z = (gz.ravel() + rng.uniform(0.0, step, gz.size)) - grid.size_m * 0.5
        s = world.sample(x.astype(np.float32), z.astype(np.float32))
        # `regions` are the atlas's provinces, several of which may share a region's creatures
        keep = s["owner"] == r.index
        keep &= s["water"] < 0.5
        keep &= s["pad"] == 0
        keep &= s["road_d"] > (s["road_w"] * 0.5 + ROAD_CLEAR_M)
        keep &= s["slope"] < 0.7
        if hearths.size:
            d = np.sqrt(((x[:, None] - hearths[None, :, 0]) ** 2
                         + (z[:, None] - hearths[None, :, 1]) ** 2)).min(axis=1)
            keep &= d > PAD_CLEAR_M
            # Thin out what stands near a settlement rather than cutting it off sharply.
            near = np.clip((d - SAFE_M) / (SAFE_FADE_M - SAFE_M), 0.0, 1.0)
            keep &= rng.random(x.shape) < near
        x, z, y = x[keep], z[keep], s["h"][keep]
        if x.size == 0:
            continue
        picks = rng.integers(0, len(pool), x.size)
        for i in range(x.size):
            enemy_id = pool[int(picks[i])]
            edef = defs[enemy_id]
            lo, hi, spread = GROUPS.get(_group_key(edef), DEFAULT_GROUP)
            count = int(rng.integers(lo, hi + 1))
            group = "g%d_%d" % (int(x[i]) & 0xFFFF, i)
            for k in range(count):
                if k == 0 or spread <= 0.0:
                    px, pz = float(x[i]), float(z[i])
                else:
                    a = rng.random() * math.tau
                    rad = spread * (0.4 + 0.6 * rng.random())
                    px, pz = float(x[i] + math.cos(a) * rad), float(z[i] + math.sin(a) * rad)
                ph = float(sample_bilinear(world.H, grid, np.array([px], dtype=np.float32),
                                           np.array([pz], dtype=np.float32))[0])
                cx, cz = grid.cell_of(np.array([px]), np.array([pz]))
                key = (int(np.clip(cx[0], 0, grid.cells - 1)), int(np.clip(cz[0], 0, grid.cells - 1)))
                out.setdefault(key, []).append({
                    "kind": "enemy",
                    "def": enemy_id,
                    "pos": [round(px, 2), round(ph, 2), round(pz, 2)],
                    "yaw": round(float(rng.random() * 360.0), 1),
                    "group": group,
                })
    return out


def _group_key(edef: dict) -> str:
    """What shape this creature stands in: its tags first, then its archetype."""
    tags = edef.get("tags", [])
    for t in ("pack", "swarm", "bandit"):
        if t in tags:
            return t
    return str(edef.get("archetype", ""))
