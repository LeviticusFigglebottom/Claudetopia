"""Regions and provinces: the content packs' region definitions, and the membership fields.

A region of the content packs is an identity (its name, palette, light, music, danger and
creatures); the land is divided among the atlas's provinces, each belonging to a region
(worldgen/geography.provinces_from_atlas makes a RegionDef per province and
`geography.province_field` the weights and owner a `RegionField` holds).
"""
from __future__ import annotations

import json
from dataclasses import dataclass, field

import numpy as np

from .grid import Grid
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
    ## Built from an atlas province (worldgen/geography.provinces_from_atlas), a RegionDef is one
    ## province: `id` is still its content region's, so everything the game reads by region is
    ## unchanged, and `index` is the province's own. `shape` is its biome.
    province: str = ""
    region_index: int = -1
    character: str = ""
    landforms: list = field(default_factory=list)
    grain_deg: float | None = None
    blend_m: float = 300.0
    ## the region whose art the biome's flora and rocks were made for (its `short`)
    art: str = ""

    @property
    def short(self) -> str:
        return self.id.split("/")[-1]

    @property
    def art_short(self) -> str:
        """Whose trees and rocks to draw on: the biome's home region, else this one's own."""
        return self.art or self.short


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
    scores: np.ndarray | None = None   # [R, n, n] float32, where the builder kept them

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
