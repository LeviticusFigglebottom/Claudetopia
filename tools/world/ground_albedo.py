#!/usr/bin/env python3
"""How bright each terrain material really is, and what the ground is made of at a point.

    python3 tools/world/ground_albedo.py                      # every slot, darkest first
    python3 tools/world/ground_albedo.py --at -1922,3708      # plus the ground at a point (x,z)
    python3 tools/world/ground_albedo.py --regions            # plus each region's mix
    python3 tools/world/ground_albedo.py --floor 0.02         # exit 1 if a slot is darker

Terrain3D draws a slot as its albedo texture times the asset's `albedo_color`
(game/world/terrain_assets.tres, from the `value` column in game/tools_gd/import_terrain.gd), so
the albedo the sun meets is the texture's mean *linear* value times that multiplier. A slot whose
texture was painted near black and then multiplied down again draws as a hole in the ground on any
renderer: that is what the Stair Head's ash did (texture 0.017, times 0.45).

The point and region reports read the builder's full-resolution maps
(game/world/generated/texture_base.u8, texture_overlay.u8, texture_blend.u8, region_mask.u8), which
exist only where the world was built (`./run.sh world`); they are not in the repository.
"""
from __future__ import annotations

import argparse
import os
import re
import sys

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GAME = os.path.join(ROOT, "game")
ASSETS = os.path.join(GAME, "world", "terrain_assets.tres")
GENERATED = os.path.join(GAME, "world", "generated")
LUMA = np.array([0.2126, 0.7152, 0.0722])
REGIONS = {0: "brightwater", 1: "hearthvale", 2: "sedgemire", 3: "briarwold", 4: "skerrow", 5: "cinderlea",
           255: "open water"}


def read_slots(path: str = ASSETS) -> list[dict]:
    """[{id, name, value, texture}] from the Terrain3DAssets resource."""
    text = open(path, encoding="utf-8").read()
    ext = dict((m.group(2), m.group(1)) for m in re.finditer(r'\[ext_resource [^\]]*path="([^"]+)" id="([^"]+)"\]', text))
    slots = []
    for block in re.split(r"\n(?=\[sub_resource )", text):
        if 'type="Terrain3DTextureAsset"' not in block.split("\n", 1)[0]:
            continue
        name = re.search(r'^name = "([^"]+)"', block, re.M)
        sid = re.search(r"^id = (\d+)", block, re.M)
        col = re.search(r"^albedo_color = Color\(([^)]+)\)", block, re.M)
        tex = re.search(r'^albedo_texture = ExtResource\("([^"]+)"\)', block, re.M)
        rgb = [float(v) for v in col.group(1).split(",")[:3]] if col else [1.0, 1.0, 1.0]
        slots.append({"id": int(sid.group(1)) if sid else 0, "name": name.group(1) if name else "?",
                      "value": float(np.dot(rgb, LUMA)),
                      "texture": ext.get(tex.group(1), "") if tex else ""})
    return sorted(slots, key=lambda s: s["id"])


def texture_albedo(res_path: str) -> float:
    """Mean linear luminance of an albedo texture (every 4th texel is plenty)."""
    path = os.path.join(GAME, res_path.replace("res://", ""))
    a = np.asarray(Image.open(path).convert("RGB"))[::4, ::4].astype(np.float32) / 255.0
    lin = np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)
    return float(lin.reshape(-1, 3).mean(0) @ LUMA)


def slot_albedos() -> list[dict]:
    out = []
    for s in read_slots():
        t = texture_albedo(s["texture"]) if s["texture"] else 0.0
        out.append(dict(s, texture_albedo=t, albedo=t * s["value"]))
    return out


def _maps():
    need = ["texture_base.u8", "texture_overlay.u8", "texture_blend.u8", "region_mask.u8"]
    if not all(os.path.exists(os.path.join(GENERATED, f)) for f in need):
        return None
    n = int(round((os.path.getsize(os.path.join(GENERATED, "texture_base.u8"))) ** 0.5))
    return n, [np.memmap(os.path.join(GENERATED, f), np.uint8, "r", shape=(n, n)) for f in need]


def _shares(base, over, blend) -> np.ndarray:
    w = np.zeros(32)
    bl = np.asarray(blend, dtype=np.float32) / 255.0
    np.add.at(w, np.asarray(base).ravel(), (1.0 - bl).ravel())
    np.add.at(w, np.asarray(over).ravel(), bl.ravel())
    return w / max(w.sum(), 1e-9)


def _describe(w: np.ndarray, by_id: dict) -> str:
    parts, mean = [], 0.0
    for i in np.argsort(-w):
        if w[i] < 0.01:
            break
        s = by_id.get(int(i))
        parts.append("%s %.0f%%" % (s["name"] if s else i, 100 * w[i]))
    for i, s in by_id.items():
        mean += w[i] * s["albedo"]
    return "%s  -> albedo %.3f" % (", ".join(parts), mean)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--at", action="append", default=[], help="x,z in metres (repeatable)")
    ap.add_argument("--radius", type=float, default=50.0, help="metres round each point")
    ap.add_argument("--regions", action="store_true")
    ap.add_argument("--floor", type=float, default=0.0, help="fail if any slot's albedo is below this")
    args = ap.parse_args()

    slots = slot_albedos()
    by_id = {s["id"]: s for s in slots}
    print("slot            texture  x value  = albedo (linear)")
    for s in sorted(slots, key=lambda s: s["albedo"]):
        flag = "   <-- below the floor" if s["albedo"] < args.floor else ""
        print("%2d %-13s %7.3f  x %.2f  = %.4f%s" % (s["id"], s["name"], s["texture_albedo"], s["value"], s["albedo"], flag))

    if args.at or args.regions:
        maps = _maps()
        if maps is None:
            print("\n(no builder maps in %s: build the world to see what the ground is made of)" % GENERATED)
        else:
            n, (base, over, blend, regions) = maps
            size = 8192.0
            spacing = size / n
            for p in args.at:
                x, z = (float(v) for v in p.split(","))
                r, c = int((z + size / 2) / spacing), int((x + size / 2) / spacing)
                k = max(1, int(args.radius / spacing))
                sl = (slice(max(r - k, 0), r + k + 1), slice(max(c - k, 0), c + k + 1))
                print("\n(%.0f, %.0f) %s, %.0f m round: %s" % (x, z, REGIONS.get(int(regions[r, c]), regions[r, c]),
                                                          args.radius, _describe(_shares(base[sl], over[sl], blend[sl]), by_id)))
            if args.regions:
                sub = (slice(None, None, 4), slice(None, None, 4))
                rb = np.asarray(regions[sub])
                bb, ob, lb = np.asarray(base[sub]), np.asarray(over[sub]), np.asarray(blend[sub])
                print()
                for reg in np.unique(rb):
                    m = rb == reg
                    print("%-12s %s" % (REGIONS.get(int(reg), reg), _describe(_shares(bb[m], ob[m], lb[m]), by_id)))

    dark = [s["name"] for s in slots if s["albedo"] < args.floor]
    if dark:
        print("\nFAIL: %s below the floor of %.3f" % (", ".join(dark), args.floor))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
