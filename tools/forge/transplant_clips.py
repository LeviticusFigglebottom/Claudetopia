#!/usr/bin/env python3
"""Put a re-baked rig's animations onto an existing rig GLB, and change nothing else.

    python3 tools/forge/transplant_clips.py <base.glb> <donor.glb> <out.glb>

`character_forge.py rig` rebuilds everything: the armature, the body, the head, their paint and
every clip. A change to the clips alone therefore also rewrites the body, and under a different
Blender that is not the same body. Rebuilt under 4.2, the rig committed from 4.0 came back with
a different UV layout and repainted textures, though the vertex positions were identical. This
writes <out.glb> as <base.glb> in every respect except its animations, which are the donor's.
Bake the clips into a scratch copy (the whole rig), then transplant them onto the committed GLB.

Both files must have the same nodes in the same order with the same rest transforms, because a
glTF animation channel addresses its bone by node index. The script refuses otherwise. It then
reads the result back and checks that every mesh attribute, index list, skin and image is
byte-for-byte the base's and every animation is the donor's.

Pure Python (json, struct, numpy); no Blender.
"""
from __future__ import annotations

import copy
import json
import struct
import sys
from typing import Dict, List, Tuple

import numpy as np

_COMP = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32,
         5126: np.float32}
_NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}


def load(path: str) -> Tuple[dict, bytes]:
    data = open(path, "rb").read()
    magic, _version, length = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF":
        raise SystemExit("%s is not a GLB" % path)
    off, js, binc = 12, None, b""
    while off < length:
        clen, ctype = struct.unpack_from("<II", data, off)
        chunk = data[off + 8: off + 8 + clen]
        if ctype == 0x4E4F534A:
            js = json.loads(chunk.decode("utf-8"))
        elif ctype == 0x004E4942:
            binc = chunk
        off += 8 + clen
    if js is None:
        raise SystemExit("%s has no JSON chunk" % path)
    return js, binc


def _accessor_bytes(js: dict, binc: bytes, i: int) -> bytes:
    a = js["accessors"][i]
    v = js["bufferViews"][a["bufferView"]]
    dt = np.dtype(_COMP[a["componentType"]])
    n = _NCOMP[a["type"]]
    start = v.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = v.get("byteStride", 0)
    item = dt.itemsize * n
    if stride and stride != item:
        return b"".join(binc[start + k * stride: start + k * stride + item] for k in range(a["count"]))
    return binc[start: start + a["count"] * item]


def _view_bytes(js: dict, binc: bytes, vi: int) -> bytes:
    v = js["bufferViews"][vi]
    return binc[v.get("byteOffset", 0): v.get("byteOffset", 0) + v["byteLength"]]


def same_skeleton(jb: dict, jd: dict) -> str:
    nb, nd = jb["nodes"], jd["nodes"]
    if len(nb) != len(nd):
        return "node counts differ: %d vs %d" % (len(nb), len(nd))
    for a, b in zip(nb, nd):
        if a.get("name") != b.get("name"):
            return "node %s vs %s" % (a.get("name"), b.get("name"))
        for k in ("translation", "rotation", "scale"):
            va, vb = a.get(k), b.get(k)
            if (va is None) != (vb is None):
                return "node %s: %s is in one file only" % (a.get("name"), k)
            if va is not None and max(abs(x - y) for x, y in zip(va, vb)) > 1e-6:
                return "node %s: %s differs" % (a.get("name"), k)
        if a.get("children") != b.get("children"):
            return "node %s: children differ" % a.get("name")
    if [s["joints"] for s in jb.get("skins", [])] != [s["joints"] for s in jd.get("skins", [])]:
        return "skin joints differ"
    return ""


def transplant(jb: dict, bb: bytes, jd: dict, bd: bytes) -> Tuple[dict, bytes]:
    why = same_skeleton(jb, jd)
    if why:
        raise SystemExit("not the same skeleton: " + why)
    out = copy.deepcopy(jb)
    out_bin = bytearray()
    views: List[dict] = []
    accs: List[dict] = []

    def add_view(src: dict, src_bin: bytes, vi: int, cache: Dict[int, int]) -> int:
        if vi not in cache:
            v = dict(src["bufferViews"][vi])
            data = _view_bytes(src, src_bin, vi)
            out_bin.extend(b"\0" * ((-len(out_bin)) % 4))
            v["buffer"] = 0
            v["byteOffset"] = len(out_bin)
            out_bin.extend(data)
            views.append(v)
            cache[vi] = len(views) - 1
        return cache[vi]

    def add_acc(src: dict, src_bin: bytes, ai: int, acache: Dict[int, int], vcache: Dict[int, int]) -> int:
        if ai not in acache:
            a = dict(src["accessors"][ai])
            if "sparse" in a:
                raise SystemExit("sparse accessors are not handled")
            if "bufferView" in a:
                a["bufferView"] = add_view(src, src_bin, a["bufferView"], vcache)
            accs.append(a)
            acache[ai] = len(accs) - 1
        return acache[ai]

    ab: Dict[int, int] = {}
    vb: Dict[int, int] = {}
    for m in out.get("meshes", []):
        for p in m["primitives"]:
            p["attributes"] = {k: add_acc(jb, bb, i, ab, vb) for k, i in p["attributes"].items()}
            if "indices" in p:
                p["indices"] = add_acc(jb, bb, p["indices"], ab, vb)
            if "targets" in p:
                p["targets"] = [{k: add_acc(jb, bb, i, ab, vb) for k, i in t.items()} for t in p["targets"]]
    for s in out.get("skins", []):
        if "inverseBindMatrices" in s:
            s["inverseBindMatrices"] = add_acc(jb, bb, s["inverseBindMatrices"], ab, vb)
    for im in out.get("images", []):
        if "bufferView" in im:
            im["bufferView"] = add_view(jb, bb, im["bufferView"], vb)
    ad: Dict[int, int] = {}
    vd: Dict[int, int] = {}
    anims = copy.deepcopy(jd.get("animations", []))
    for an in anims:
        for s in an["samplers"]:
            s["input"] = add_acc(jd, bd, s["input"], ad, vd)
            s["output"] = add_acc(jd, bd, s["output"], ad, vd)
    out["animations"] = anims
    out["accessors"] = accs
    out["bufferViews"] = views
    out_bin.extend(b"\0" * ((-len(out_bin)) % 4))
    out["buffers"] = [{"byteLength": len(out_bin)}]
    return out, bytes(out_bin)


def write(path: str, js: dict, binc: bytes) -> int:
    text = json.dumps(js, separators=(",", ":")).encode("utf-8")
    text += b" " * ((-len(text)) % 4)
    total = 12 + 8 + len(text) + 8 + len(binc)
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, total))
        f.write(struct.pack("<II", len(text), 0x4E4F534A))
        f.write(text)
        f.write(struct.pack("<II", len(binc), 0x004E4942))
        f.write(binc)
    return total


def verify(jb: dict, bb: bytes, jd: dict, bd: bytes, jo: dict, bo: bytes) -> List[str]:
    """Everything but the animations is the base's, byte for byte; the animations are the donor's."""
    bad: List[str] = []
    for mi, (mb, mo) in enumerate(zip(jb.get("meshes", []), jo.get("meshes", []))):
        for pi, (pb, po) in enumerate(zip(mb["primitives"], mo["primitives"])):
            for k in pb["attributes"]:
                if _accessor_bytes(jb, bb, pb["attributes"][k]) != _accessor_bytes(jo, bo, po["attributes"][k]):
                    bad.append("mesh %d primitive %d %s" % (mi, pi, k))
            if "indices" in pb and _accessor_bytes(jb, bb, pb["indices"]) != _accessor_bytes(jo, bo, po["indices"]):
                bad.append("mesh %d primitive %d indices" % (mi, pi))
    for si, (sb, so) in enumerate(zip(jb.get("skins", []), jo.get("skins", []))):
        if "inverseBindMatrices" in sb and _accessor_bytes(jb, bb, sb["inverseBindMatrices"]) != \
                _accessor_bytes(jo, bo, so["inverseBindMatrices"]):
            bad.append("skin %d inverse bind matrices" % si)
    for ii, (ib, io) in enumerate(zip(jb.get("images", []), jo.get("images", []))):
        if "bufferView" in ib and _view_bytes(jb, bb, ib["bufferView"]) != _view_bytes(jo, bo, io["bufferView"]):
            bad.append("image %d" % ii)
    for ad_, ao in zip(jd.get("animations", []), jo.get("animations", [])):
        if ad_.get("name") != ao.get("name") or len(ad_["samplers"]) != len(ao["samplers"]):
            bad.append("animation %s" % ad_.get("name"))
            continue
        for sd, so in zip(ad_["samplers"], ao["samplers"]):
            if _accessor_bytes(jd, bd, sd["input"]) != _accessor_bytes(jo, bo, so["input"]) or \
                    _accessor_bytes(jd, bd, sd["output"]) != _accessor_bytes(jo, bo, so["output"]):
                bad.append("animation %s" % ad_.get("name"))
                break
    for key in ("nodes", "skins", "materials", "textures", "samplers", "scenes"):
        strip = lambda xs: [{k: v for k, v in x.items() if k not in ("inverseBindMatrices", "bufferView")}
                            for x in xs]
        if strip(jb.get(key, [])) != strip(jo.get(key, [])):
            bad.append(key)
    return bad


def main(argv: List[str]) -> int:
    if len(argv) != 3:
        print(__doc__)
        return 2
    base, donor, out_path = argv
    jb, bb = load(base)
    jd, bd = load(donor)
    jo, bo = transplant(jb, bb, jd, bd)
    total = write(out_path, jo, bo)
    jo, bo = load(out_path)
    bad = verify(jb, bb, jd, bd, jo, bo)
    before = {a["name"] for a in jb.get("animations", [])}
    after = {a["name"] for a in jd.get("animations", [])}
    print("wrote %s (%d bytes): %d animations from %s; the rest is %s" % (
        out_path, total, len(after), donor, base))
    if after - before:
        print("  new clips: %s" % ", ".join(sorted(after - before)))
    if before - after:
        print("  clips dropped: %s" % ", ".join(sorted(before - after)))
    if bad:
        print("  NOT AS INTENDED: %s" % ", ".join(bad))
        return 1
    print("  meshes, skins, images, materials and nodes are the base's byte for byte; the animations are the donor's")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
