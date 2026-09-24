"""A decimated rung's triangles that stand off the full mesh, found and dropped (pure Python).

Blender's collapse decimator, taken down to a tree's LOD1 budget of 900 triangles, sometimes
closes the gap between two branches with a triangle instead of shortening either: on the
black ash a sheet of 25 square metres standing two metres clear of any bark, drawn dark
across the crown for every metre the tree is at LOD1 (71 to 178 m). Nineteen of the
thirty-five trees the forge ships had at least one; the third black ash's LOD1 bark was 541
square metres of which 387 were bridges, the largest a single triangle of 102. Nothing of the
full tree is there, so taking it out loses no shape the tree has.

The test is distance from the full mesh's bark, not size: a coarse trunk triangle is
legitimately large and lies on the bark, a bridge between two limbs is any size and lies in
the air between them. Each LOD1 triangle is probed at its centroid and its three edge
midpoints; the probe furthest from the LOD0 surface (sampled on a barycentric grid) decides.
The tolerance scales with the tree, because a giant oak's trunk decimated to six sides stands
further off its own bark than a hawthorn's twig does.

numpy, with scipy's k-d tree where the interpreter has one, so the same code runs in Blender's
Python (gen_impostors) and the system one (repair_lod1.py).
"""
from __future__ import annotations

import json
import struct
from pathlib import Path

import numpy as np

from . import glb as G

## Standoff, in metres, beyond which a triangle is not describing the bark: this, or
## TOL_PER_METRE of the tree's height if that is more.
TOL_MIN = 0.5
TOL_PER_METRE = 0.025
RECIPE = 1

_COMPONENTS = {5126: ("f4", 4), 5125: ("u4", 4), 5123: ("u2", 2), 5121: ("u1", 1)}
_WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def accessor_array(gltf: dict, bin_chunk: bytes, index: int) -> np.ndarray:
    """An accessor's values as an (n, width) array (or (n,) for scalars). Tightly packed or
    strided views both read; sparse accessors are not used by the forge's exports."""
    a = gltf["accessors"][index]
    view = gltf["bufferViews"][a["bufferView"]]
    dtype, size = _COMPONENTS[a["componentType"]]
    width = _WIDTH[a["type"]]
    start = view.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = view.get("byteStride", 0) or size * width
    count = a["count"]
    raw = np.frombuffer(bin_chunk, dtype=np.uint8, count=stride * (count - 1) + size * width,
                        offset=start)
    rows = np.lib.stride_tricks.as_strided(raw, shape=(count, size * width), strides=(stride, 1))
    out = np.ascontiguousarray(rows).view("<" + dtype).reshape(count, width)
    return out[:, 0] if width == 1 else out


## The reference surface is sampled at least this finely, so a probe lying on it is never
## further than about half this from a sample: well inside TOL_MIN.
SAMPLE_SPACING = 0.2


def surface_samples(pos: np.ndarray, tris: np.ndarray, spacing: float = SAMPLE_SPACING) -> np.ndarray:
    """Points spread over every triangle on a barycentric grid fine enough that no point of
    the triangle is more than about `spacing` / 2 from one: a long trunk triangle gets many,
    a twig's few."""
    t = pos[tris]
    longest = np.max(np.linalg.norm(t - np.roll(t, 1, axis=1), axis=2), axis=1)
    steps = np.clip(np.ceil(longest / spacing), 1, 64).astype(int)
    pts = []
    for n in np.unique(steps):
        group = t[steps == n]
        ws = [(i, j, n - i - j) for i in range(n + 1) for j in range(n + 1 - i)]
        w = np.array(ws, dtype=float) / n
        pts.append(np.einsum("wk,tkc->twc", w, group).reshape(-1, 3))
    return np.concatenate(pts, 0)


def nearest_distance(points: np.ndarray, cloud: np.ndarray, chunk: int = 64) -> np.ndarray:
    """Distance from each point to the nearest of `cloud`: a k-d tree where scipy is there
    (the system Python), brute force in chunks where it is not (Blender's)."""
    try:
        from scipy.spatial import cKDTree
    except ImportError:
        cKDTree = None
    if cKDTree is not None:
        return cKDTree(cloud).query(points, k=1)[0]
    out = np.empty(len(points))
    c2 = (cloud ** 2).sum(1)
    for s in range(0, len(points), chunk):
        p = points[s:s + chunk]
        d2 = (p ** 2).sum(1)[:, None] - 2.0 * p @ cloud.T + c2[None, :]
        out[s:s + chunk] = np.sqrt(np.maximum(d2.min(1), 0.0))
    return out


def standoff(pos: np.ndarray, tris: np.ndarray, ref_pos: np.ndarray, ref_tris: np.ndarray) -> np.ndarray:
    """Per triangle of (pos, tris): how far its furthest probe is from the reference surface."""
    t = pos[tris]
    probes = np.stack([t.mean(1), (t[:, 0] + t[:, 1]) * 0.5, (t[:, 1] + t[:, 2]) * 0.5,
                       (t[:, 2] + t[:, 0]) * 0.5], 1)
    cloud = surface_samples(ref_pos, ref_tris)
    return nearest_distance(probes.reshape(-1, 3), cloud).reshape(-1, 4).max(1)


def tolerance(height: float) -> float:
    return max(TOL_MIN, TOL_PER_METRE * float(height))


def _bark_primitives(gltf: dict, mesh_name: str) -> list:
    mesh = next((m for m in gltf.get("meshes", []) if m.get("name") == mesh_name), None)
    if mesh is None:
        return []
    mats = gltf.get("materials", [])
    out = []
    for p in mesh.get("primitives", []):
        name = mats[p["material"]].get("name", "") if "material" in p and p["material"] < len(mats) else ""
        if "foliage" in name or "indices" not in p:
            continue
        out.append(p)
    return out


def _triangles(gltf: dict, bin_chunk: bytes, prims: list) -> tuple[np.ndarray, np.ndarray]:
    pos_all, tri_all, base = [], [], 0
    for p in prims:
        pos = accessor_array(gltf, bin_chunk, p["attributes"]["POSITION"]).astype(float)
        idx = accessor_array(gltf, bin_chunk, p["indices"]).astype(np.int64).reshape(-1, 3)
        pos_all.append(pos)
        tri_all.append(idx + base)
        base += len(pos)
    if not pos_all:
        return np.zeros((0, 3)), np.zeros((0, 3), dtype=np.int64)
    return np.concatenate(pos_all, 0), np.concatenate(tri_all, 0)


def replace_indices(gltf: dict, bin_chunk: bytes, prim: dict, tris: np.ndarray) -> bytes:
    """Point a primitive at a new index list, keeping every vertex attribute it had; `prune`
    takes the old list out of the buffer."""
    out = bytearray(bin_chunk)
    old = gltf["accessors"][prim["indices"]]
    component = 5125 if old["componentType"] == 5125 or (len(tris) and tris.max() > 65535) else 5123
    fmt = "I" if component == 5125 else "H"
    flat = [int(v) for v in tris.reshape(-1)]
    view = G._append_view(gltf, out, struct.pack("<%d%s" % (len(flat), fmt), *flat), 34963)
    gltf["accessors"].append({"bufferView": view, "componentType": component, "count": len(flat),
                              "type": "SCALAR"})
    prim["indices"] = len(gltf["accessors"]) - 1
    if gltf.get("buffers"):
        gltf["buffers"][0]["byteLength"] = len(out)
    return bytes(out)


def repair_lod1(glb_path: str | Path, tree: str, height: float) -> dict:
    """Drop the LOD1 bark triangles of `tree` that stand off its LOD0 bark. Rewrites the GLB
    only when something is dropped. Returns what was done, for the meta."""
    gltf, bin_chunk = G.read_glb(glb_path)
    ref_pos, ref_tris = _triangles(gltf, bin_chunk, _bark_primitives(gltf, tree))
    tol = tolerance(height)
    report = {"recipe": RECIPE, "tol_m": round(tol, 3), "dropped": 0, "area_m2": 0.0}
    if len(ref_tris) == 0:
        return report
    changed = False
    for prim in _bark_primitives(gltf, "%s_LOD1" % tree):
        pos = accessor_array(gltf, bin_chunk, prim["attributes"]["POSITION"]).astype(float)
        tris = accessor_array(gltf, bin_chunk, prim["indices"]).astype(np.int64).reshape(-1, 3)
        off = standoff(pos, tris, ref_pos, ref_tris)
        bad = off > tol
        if not bad.any() or bad.all():
            continue
        t = pos[tris[bad]]
        area = 0.5 * np.linalg.norm(np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0]), axis=1)
        report["dropped"] += int(bad.sum())
        report["area_m2"] = round(report["area_m2"] + float(area.sum()), 2)
        bin_chunk = replace_indices(gltf, bin_chunk, prim, tris[~bad])
        changed = True
    if changed:
        bin_chunk = G.prune(gltf, bin_chunk)
        G.write_glb(glb_path, gltf, bin_chunk)
    return report


def repair_tree(glb_path: str | Path, meta_path: str | Path, tree: str) -> dict:
    """`repair_lod1` and the meta brought up to date: the mesh triangle counts, LOD1's total,
    and a `lod1_repair` record that accumulates across runs (a second run finds nothing)."""
    meta_path = Path(meta_path)
    meta = json.loads(meta_path.read_text(encoding="utf-8"))
    height = float(meta.get("bounds", {}).get("height", meta.get("height_m", 4.0)))
    rep = repair_lod1(glb_path, tree, height)
    prior = meta.get("lod1_repair", {})
    rep["dropped"] += int(prior.get("dropped", 0))
    rep["area_m2"] = round(rep["area_m2"] + float(prior.get("area_m2", 0.0)), 2)
    summary = G.summary(glb_path)
    meta["meshes"] = summary["meshes"]
    by_name = {m["name"]: m["tris"] for m in summary["meshes"]}
    tris = list(meta.get("tris", [0, 0, 0]))
    if len(tris) > 1:
        tris[1] = by_name.get("%s_LOD1" % tree, 0) + by_name.get("%s_cards_LOD1" % tree, 0)
        meta["tris"] = tris
    meta["lod1_repair"] = rep
    # the format lib/export.write_meta writes (that module needs Blender to import)
    meta_path.write_text(json.dumps(meta, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    return rep
