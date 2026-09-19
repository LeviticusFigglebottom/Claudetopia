"""Region membership: weighted, domain-warped Voronoi around each region's map centre.

score_r(p) = |p + warp(p) - centre_r| / radius_r + bias_r ; owner = argmin score ;
blend weights = softmax(-score / tau) so borders blend over roughly 300-500 m.
"""
from __future__ import annotations

import json
from dataclasses import dataclass, field

import numpy as np

from .grid import Grid, smoothstep
from .noise import NoiseBank, upsample


@dataclass
class RegionDef:
    id: str
    name: str
    index: int
    center: tuple
    radius: float
    base_height: float
    relief: float
    roughness: float
    shape: str
    water_table: float
    lake_radius: float
    palette: list
    flora: list
    light: dict = field(default_factory=dict)
    ## How hard the country is, 1 (the starting valley) to 5 (the ash). Encounter density
    ## reads it: a dangerous region is not only fought by worse things, it is fought oftener.
    danger: int = 1
    ecology: list = field(default_factory=list)

    @property
    def short(self) -> str:
        return self.id.split("/")[-1]


def load_regions(path: str) -> list[RegionDef]:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    out: list[RegionDef] = []
    for i, r in enumerate(data):
        m = r["map"]
        ident = r.get("identity", {})
        out.append(RegionDef(
            id=r["id"], name=r.get("name", r["id"]), index=i,
            center=(float(m["center"][0]), float(m["center"][1])), radius=float(m["radius"]),
            base_height=float(m.get("base_height", 20)), relief=float(m.get("relief", 20)),
            roughness=float(m.get("roughness", 0.3)), shape=str(m.get("shape", "downs")),
            water_table=float(m.get("water_table", 0)), lake_radius=float(m.get("lake_radius", 0)),
            palette=list(ident.get("palette", [])), flora=list(ident.get("flora", [])),
            light=dict(ident.get("light", {})),
            danger=int(r.get("danger", 1) or 1), ecology=list(r.get("enemy_ecology", [])),
        ))
    return out


def load_places(path: str) -> list[dict]:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


@dataclass
class RegionField:
    grid: Grid
    weights: np.ndarray   # [R, n, n] float32, sums to 1
    owner: np.ndarray     # [n, n] uint8
    scores: np.ndarray    # [R, n, n] float32

    def owner_at(self, n: int) -> np.ndarray:
        """Nearest-neighbour owner mask at another resolution."""
        if n == self.grid.n:
            return self.owner
        if n > self.grid.n:
            f = n // self.grid.n
            return np.repeat(np.repeat(self.owner, f, axis=0), f, axis=1)
        f = self.grid.n // n
        return self.owner[::f, ::f].copy()

    def weight_at(self, r: int, n: int) -> np.ndarray:
        return upsample(self.weights[r], n, order=1)


BORDER_TAU = 0.045


def compute_regions(regions: list[RegionDef], grid: Grid, bank: NoiseBank, lake_sd: np.ndarray | None = None,
                    places: list | None = None) -> RegionField:
    n = grid.n
    X, Z = grid.mesh()
    # domain warp: big slow wobble plus a finer one, in metres
    w1 = bank.field_at(201, n, beta=2.0, wl_min=700, wl_max=2200)
    w2 = bank.field_at(202, n, beta=2.0, wl_min=700, wl_max=2200)
    w3 = bank.field_at(203, n, beta=1.8, wl_min=150, wl_max=450)
    w4 = bank.field_at(204, n, beta=1.8, wl_min=150, wl_max=450)
    px = X + 230.0 * w1 + 55.0 * w3
    pz = Z + 230.0 * w2 + 55.0 * w4
    del w1, w2, w3, w4
    scores = np.empty((len(regions), n, n), dtype=np.float32)
    for r in regions:
        d = np.sqrt((px - r.center[0]) ** 2 + (pz - r.center[1]) ** 2)
        s = d / r.radius
        if r.shape == "lake_basin":
            s -= 0.18
            if lake_sd is not None:
                # the lake and a shore band always belong to the lake region
                s = s - 0.6 * (1.0 - smoothstep(-50.0, 260.0, lake_sd))
                s = s - 0.25 * (1.0 - smoothstep(200.0, 800.0, lake_sd))
        # every named place pulls its declared region toward itself
        for p in places or []:
            if p.get("region") == r.id:
                qx, qz = p["position"]
                pull = 420.0 if p.get("kind") in ("city", "town") else 330.0
                s = s - 0.45 * np.exp(-(((X - qx) ** 2 + (Z - qz) ** 2) / (pull * pull)))
        scores[r.index] = s
    owner = np.argmin(scores, axis=0).astype(np.uint8)
    smin = scores.min(axis=0)
    weights = np.exp(-(scores - smin[None]) / BORDER_TAU).astype(np.float32)
    weights /= weights.sum(axis=0)[None]
    return RegionField(grid=grid, weights=weights, owner=owner, scores=scores)


def dithered_owner(rf: RegionField, n: int, bank: NoiseBank, amount: float = 0.30) -> np.ndarray:
    """Owner mask where borders dissolve into patches (for texture rules and scatter)."""
    R = rf.weights.shape[0]
    best = np.full((n, n), -1e9, dtype=np.float32)
    out = np.zeros((n, n), dtype=np.uint8)
    for r in range(R):
        w = rf.weight_at(r, n)
        if r > 0:
            w = w + amount * (0.7 * bank.field_at(300 + r, n, beta=1.7, wl_min=45, wl_max=260)
                              + 0.3 * bank.field_at(320 + r, n, beta=1.6, wl_min=18, wl_max=80))
        better = w > best
        out[better] = r
        best = np.where(better, w, best)
    return out
