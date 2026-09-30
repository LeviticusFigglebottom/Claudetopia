"""Minimal GLB reader/writer (pure Python) used to post-process Blender's export.

We bake textures to PNG files next to the model (CONTRACTS.md §4) and want the GLB to
reference them by relative `uri` instead of carrying a second embedded copy. Blender's
exporter embeds images in GLB mode, so `externalise_images` rewrites the JSON chunk and
rebuilds the BIN chunk without the image buffer views.
"""
from __future__ import annotations

import json
import struct
from pathlib import Path
from typing import Optional

GLB_MAGIC = 0x46546C67
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942


def read_glb(path: str | Path) -> tuple[dict, bytes]:
    data = Path(path).read_bytes()
    magic, version, length = struct.unpack_from("<III", data, 0)
    if magic != GLB_MAGIC:
        raise ValueError("%s is not a GLB" % path)
    off = 12
    gltf = None
    bin_chunk = b""
    while off < length:
        clen, ctype = struct.unpack_from("<II", data, off)
        off += 8
        chunk = data[off:off + clen]
        off += clen
        if ctype == CHUNK_JSON:
            gltf = json.loads(chunk.decode("utf-8"))
        elif ctype == CHUNK_BIN:
            bin_chunk = bytes(chunk)
    if gltf is None:
        raise ValueError("GLB without JSON chunk: %s" % path)
    return gltf, bin_chunk


def _pad(b: bytes, pad_byte: bytes) -> bytes:
    rem = len(b) % 4
    return b if rem == 0 else b + pad_byte * (4 - rem)


def write_glb(path: str | Path, gltf: dict, bin_chunk: bytes) -> None:
    js = _pad(json.dumps(gltf, separators=(",", ":")).encode("utf-8"), b" ")
    bn = _pad(bin_chunk, b"\x00")
    total = 12 + 8 + len(js) + (8 + len(bn) if bn else 0)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", GLB_MAGIC, 2, total))
        f.write(struct.pack("<II", len(js), CHUNK_JSON))
        f.write(js)
        if bn:
            f.write(struct.pack("<II", len(bn), CHUNK_BIN))
            f.write(bn)


SLOT_KEYS = ("baseColorTexture", "metallicRoughnessTexture", "normalTexture", "occlusionTexture", "emissiveTexture")


def externalise_images(path: str | Path, material_textures: dict[str, dict[str, str]]) -> list[str]:
    """Point each material's texture slots at external files and drop the embedded copies.

    material_textures: {material_name: {"baseColorTexture": "x_albedo.png",
                        "normalTexture": "x_normal.png", "metallicRoughnessTexture": "x_orm.png",
                        "occlusionTexture": "x_orm.png", "emissiveTexture": ...}}
    Returns the sorted list of uris now referenced."""
    gltf, bin_chunk = read_glb(path)
    images = gltf.get("images", [])
    textures = gltf.get("textures", [])
    if not images:
        return []
    drop: set[int] = set()
    used: list[str] = []
    for mat in gltf.get("materials", []):
        slots = material_textures.get(mat.get("name", ""))
        if not slots:
            continue
        pbr = mat.get("pbrMetallicRoughness", {})
        refs = {
            "baseColorTexture": pbr.get("baseColorTexture"),
            "metallicRoughnessTexture": pbr.get("metallicRoughnessTexture"),
            "normalTexture": mat.get("normalTexture"),
            "occlusionTexture": mat.get("occlusionTexture"),
            "emissiveTexture": mat.get("emissiveTexture"),
        }
        for key, ref in refs.items():
            if ref is None or key not in slots:
                continue
            tex = textures[ref["index"]]
            src = tex.get("source")
            if src is None:
                continue
            img = images[src]
            bv = img.pop("bufferView", None)
            img.pop("mimeType", None)
            img["uri"] = slots[key]
            used.append(slots[key])
            if bv is not None:
                drop.add(bv)
    if drop:
        _compact_buffer_views(gltf, bin_chunk, drop, path)
    else:
        write_glb(path, gltf, bin_chunk)
    return sorted(set(used))


_EXT = {"image/png": ".png", "image/jpeg": ".jpg", "image/webp": ".webp"}


def embedded_images(path: str | Path) -> list[str]:
    """Names of the images a GLB carries inside itself (CONTRACTS §4 says: none)."""
    gltf, _ = read_glb(path)
    return [str(img.get("name", "image%d" % i)) for i, img in enumerate(gltf.get("images", []))
            if "bufferView" in img]


def externalise_by_name(path: str | Path) -> dict:
    """Move every embedded image out of a GLB to the file its name says it is.

    Blender's GLB export embeds each image under the name of the Blender image it came from,
    and the character forge loads its baked maps as images named after their own files --
    `braid_albedo` is `braid_albedo.png` beside the GLB. So the image can simply be pointed at
    that file and the embedded copy dropped. Where the file is there it must hold the same
    bytes, or the GLB would silently start showing a different texture; where it is missing
    the embedded bytes are written out first, so nothing is ever lost.

    Godot then imports the PNG once, with the forge's own import settings (VRAM compression,
    normal maps flagged), instead of extracting a second, uncompressed copy of every map under
    `<glb>_<image>.png` -- which is what `gltf/embedded_image_handling` did to every character
    part until this existed.

    Returns {"referenced": [uri...], "written": [uri...]}."""
    path = Path(path)
    gltf, bin_chunk = read_glb(path)
    views = gltf.get("bufferViews", [])
    drop: set[int] = set()
    referenced: list[str] = []
    written: list[str] = []
    for i, img in enumerate(gltf.get("images", [])):
        bv = img.get("bufferView")
        if bv is None:
            if "uri" in img:
                referenced.append(img["uri"])
            continue
        view = views[bv]
        start = view.get("byteOffset", 0)
        data = bin_chunk[start:start + view["byteLength"]]
        name = str(img.get("name") or "%s_image%d" % (path.stem, i))
        uri = name + _EXT.get(img.get("mimeType", "image/png"), ".png")
        target = path.parent / uri
        if target.exists():
            if target.read_bytes() != data:
                raise ValueError("%s: embedded image '%s' differs from %s beside it; refusing to "
                                 "point the GLB at a file that is not the same picture" % (path, name, target))
        else:
            target.write_bytes(data)
            written.append(uri)
        img.pop("bufferView", None)
        img.pop("mimeType", None)
        img["uri"] = uri
        referenced.append(uri)
        drop.add(bv)
    if drop:
        _compact_buffer_views(gltf, bin_chunk, drop, path)
    return {"referenced": sorted(set(referenced)), "written": sorted(written)}


def _compact_buffer_views(gltf: dict, bin_chunk: bytes, drop: set[int], path) -> None:
    views = gltf.get("bufferViews", [])
    # Make sure nothing else still uses a dropped view.
    still_used = set()
    for acc in gltf.get("accessors", []):
        if "bufferView" in acc:
            still_used.add(acc["bufferView"])
        sp = acc.get("sparse")
        if sp:
            still_used.add(sp["indices"]["bufferView"])
            still_used.add(sp["values"]["bufferView"])
    for img in gltf.get("images", []):
        if "bufferView" in img:
            still_used.add(img["bufferView"])
    drop = {d for d in drop if d not in still_used}
    remap: dict[int, int] = {}
    new_views = []
    out = bytearray()
    for i, v in enumerate(views):
        if i in drop:
            continue
        start = v.get("byteOffset", 0)
        chunk = bin_chunk[start:start + v["byteLength"]]
        while len(out) % 4:
            out.append(0)
        nv = dict(v)
        nv["byteOffset"] = len(out)
        out.extend(chunk)
        remap[i] = len(new_views)
        new_views.append(nv)
    gltf["bufferViews"] = new_views
    for acc in gltf.get("accessors", []):
        if "bufferView" in acc:
            acc["bufferView"] = remap[acc["bufferView"]]
        sp = acc.get("sparse")
        if sp:
            sp["indices"]["bufferView"] = remap[sp["indices"]["bufferView"]]
            sp["values"]["bufferView"] = remap[sp["values"]["bufferView"]]
    for img in gltf.get("images", []):
        if "bufferView" in img:
            img["bufferView"] = remap[img["bufferView"]]
    if gltf.get("buffers"):
        gltf["buffers"][0]["byteLength"] = len(out)
    write_glb(path, gltf, bytes(out))


def _append_view(gltf: dict, out: bytearray, data: bytes, target: int | None = None) -> int:
    while len(out) % 4:
        out.append(0)
    view = {"buffer": 0, "byteOffset": len(out), "byteLength": len(data)}
    if target is not None:
        view["target"] = target
    out.extend(data)
    gltf.setdefault("bufferViews", []).append(view)
    return len(gltf["bufferViews"]) - 1


def _append_accessor(gltf: dict, out: bytearray, values: list, kind: str, component: int,
                     target: int | None, with_bounds: bool = False) -> int:
    fmt = {5126: "f", 5123: "H", 5125: "I"}[component]
    width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3}[kind]
    flat = [v for row in values for v in (row if isinstance(row, (list, tuple)) else [row])]
    view = _append_view(gltf, out, struct.pack("<%d%s" % (len(flat), fmt), *flat), target)
    acc = {"bufferView": view, "componentType": component, "count": len(values), "type": kind}
    if with_bounds:
        acc["min"] = [min(r[i] for r in values) for i in range(width)]
        acc["max"] = [max(r[i] for r in values) for i in range(width)]
    gltf.setdefault("accessors", []).append(acc)
    return len(gltf["accessors"]) - 1


def replace_mesh_geometry(gltf: dict, bin_chunk: bytes, mesh_name: str, positions: list,
                          normals: list, uvs: list, indices: list, material: int) -> bytes:
    """Give the mesh called `mesh_name` one new primitive, drawn with material `material`.

    The old primitive's data is left in the buffer; `prune` takes it out. Returns the new BIN
    chunk (the glTF dict is edited in place)."""
    mesh = next((m for m in gltf.get("meshes", []) if m.get("name") == mesh_name), None)
    if mesh is None:
        raise KeyError("no mesh %r in the GLB" % mesh_name)
    out = bytearray(bin_chunk)
    pos = _append_accessor(gltf, out, positions, "VEC3", 5126, 34962, with_bounds=True)
    nrm = _append_accessor(gltf, out, normals, "VEC3", 5126, 34962)
    uv = _append_accessor(gltf, out, uvs, "VEC2", 5126, 34962)
    idx = _append_accessor(gltf, out, indices, "SCALAR", 5123, 34963)
    mesh["primitives"] = [{"attributes": {"POSITION": pos, "NORMAL": nrm, "TEXCOORD_0": uv},
                           "indices": idx, "material": material, "mode": 4}]
    if gltf.get("buffers"):
        gltf["buffers"][0]["byteLength"] = len(out)
    return bytes(out)


def prune(gltf: dict, bin_chunk: bytes) -> bytes:
    """Drop every accessor, buffer view, material, texture and image nothing refers to any more,
    and compact the buffer. Static meshes only: a file with skins or animations is refused
    rather than half-understood. Returns the new BIN chunk."""
    if gltf.get("skins") or gltf.get("animations"):
        raise ValueError("prune: skins and animations are not handled")
    meshes = gltf.get("meshes", [])
    used_acc, used_mat = set(), set()
    for m in meshes:
        for p in m.get("primitives", []):
            used_acc.update(p.get("attributes", {}).values())
            if "indices" in p:
                used_acc.add(p["indices"])
            for t in p.get("targets", []):
                used_acc.update(t.values())
            if "material" in p:
                used_mat.add(p["material"])
    mats = gltf.get("materials", [])

    def tex_refs(mat: dict) -> list:
        pbr = mat.get("pbrMetallicRoughness", {})
        return [r for r in (pbr.get("baseColorTexture"), pbr.get("metallicRoughnessTexture"),
                            mat.get("normalTexture"), mat.get("occlusionTexture"),
                            mat.get("emissiveTexture")) if r is not None]

    used_tex = {r["index"] for i in used_mat for r in tex_refs(mats[i])}
    textures = gltf.get("textures", [])
    used_img = {textures[t]["source"] for t in used_tex if "source" in textures[t]}
    images = gltf.get("images", [])
    accessors = gltf.get("accessors", [])
    used_view = {accessors[a]["bufferView"] for a in used_acc if "bufferView" in accessors[a]}
    used_view |= {images[i]["bufferView"] for i in used_img if "bufferView" in images[i]}

    def remap(items: list, used: set) -> tuple[list, dict]:
        kept, table = [], {}
        for i, item in enumerate(items):
            if i in used:
                table[i] = len(kept)
                kept.append(item)
        return kept, table

    new_views, vmap = [], {}
    out = bytearray()
    for i, v in enumerate(gltf.get("bufferViews", [])):
        if i not in used_view:
            continue
        start = v.get("byteOffset", 0)
        while len(out) % 4:
            out.append(0)
        nv = dict(v)
        nv["byteOffset"] = len(out)
        out.extend(bin_chunk[start:start + v["byteLength"]])
        vmap[i] = len(new_views)
        new_views.append(nv)
    gltf["bufferViews"] = new_views
    accessors, amap = remap(accessors, used_acc)
    for a in accessors:
        if "bufferView" in a:
            a["bufferView"] = vmap[a["bufferView"]]
    gltf["accessors"] = accessors
    images, imap = remap(images, used_img)
    for img in images:
        if "bufferView" in img:
            img["bufferView"] = vmap[img["bufferView"]]
    textures, tmap = remap(textures, used_tex)
    for t in textures:
        if "source" in t:
            t["source"] = imap[t["source"]]
    mats, mmap = remap(mats, used_mat)
    for mat in mats:
        for r in tex_refs(mat):
            r["index"] = tmap[r["index"]]
    for m in meshes:
        for p in m.get("primitives", []):
            p["attributes"] = {k: amap[v] for k, v in p.get("attributes", {}).items()}
            if "indices" in p:
                p["indices"] = amap[p["indices"]]
            if "targets" in p:
                p["targets"] = [{k: amap[v] for k, v in t.items()} for t in p["targets"]]
            if "material" in p:
                p["material"] = mmap[p["material"]]
    for key, items in (("images", images), ("textures", textures), ("materials", mats)):
        if items:
            gltf[key] = items
        else:
            gltf.pop(key, None)
    if gltf.get("buffers"):
        gltf["buffers"][0]["byteLength"] = len(out)
    return bytes(out)


def read_accessor(gltf: dict, bin_chunk: bytes, index: int) -> list:
    """A float or integer accessor's values as a list of rows (sparse accessors are not read)."""
    acc = gltf["accessors"][index]
    fmt = {5126: "f", 5123: "H", 5125: "I", 5121: "B"}[acc["componentType"]]
    width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[acc["type"]]
    view = gltf["bufferViews"][acc["bufferView"]]
    size = struct.calcsize("<" + fmt)
    stride = view.get("byteStride", size * width)
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    return [list(struct.unpack_from("<%d%s" % (width, fmt), bin_chunk, start + i * stride))
            for i in range(acc["count"])]


def set_morph_target(gltf: dict, bin_chunk: bytes, mesh_index: int, name: str, deltas: list,
                     normals: Optional[list] = None) -> bytes:
    """Give every primitive of mesh `mesh_index` the morph target `name`: `deltas` are POSITION
    offsets, one row per vertex of each primitive in turn. A target of that name already there is
    written over in place; a new one goes after the others. Where the mesh's other targets carry a
    NORMAL, the new one carries a zero NORMAL, so every target has the same attributes -- or
    `normals`, NORMAL offsets row for row like `deltas`, when given (a fit that moves cloth over a
    bust has to turn its normals too, or it is lit as the chest it was built on). Returns the new BIN
    chunk (the glTF dict is edited in place)."""
    mesh = gltf["meshes"][mesh_index]
    extras = mesh.setdefault("extras", {})
    names = list(extras.get("targetNames", []))
    out = bytearray(bin_chunk)
    at = 0
    for p in mesh["primitives"]:
        count = gltf["accessors"][p["attributes"]["POSITION"]]["count"]
        rows = [[float(c) for c in r] for r in deltas[at:at + count]]
        nrows = None if normals is None else [[float(c) for c in r] for r in normals[at:at + count]]
        at += count
        if len(rows) != count:
            raise ValueError("set_morph_target: %d deltas for a primitive of %d vertices" % (len(rows), count))
        targets = p.setdefault("targets", [])
        if name in names and names.index(name) < len(targets):
            t = targets[names.index(name)]
            if nrows is not None:
                # written fresh: an old zero NORMAL may be an accessor with no data of its own
                t["NORMAL"] = _append_accessor(gltf, out, nrows, "VEC3", 5126, 34962)
            acc = gltf["accessors"][t["POSITION"]]
            if "bufferView" not in acc:
                # the exporter writes a target that moves nothing as an accessor with no data at
                # all (every row zero); it gets data of its own now
                t["POSITION"] = _append_accessor(gltf, out, rows, "VEC3", 5126, 34962, with_bounds=True)
                continue
            view = gltf["bufferViews"][acc["bufferView"]]
            flat = [v for r in rows for v in r]
            struct.pack_into("<%df" % len(flat), out, view.get("byteOffset", 0) + acc.get("byteOffset", 0), *flat)
            acc["min"] = [min(r[i] for r in rows) for i in range(3)]
            acc["max"] = [max(r[i] for r in rows) for i in range(3)]
            continue
        target = {"POSITION": _append_accessor(gltf, out, rows, "VEC3", 5126, 34962, with_bounds=True)}
        if nrows is not None or any("NORMAL" in t for t in targets):
            target["NORMAL"] = _append_accessor(gltf, out, nrows or [[0.0, 0.0, 0.0]] * count, "VEC3", 5126, 34962)
        targets.append(target)
    if at != len(deltas):
        raise ValueError("set_morph_target: %d deltas for %d vertices" % (len(deltas), at))
    if name not in names:
        names.append(name)
    extras["targetNames"] = names
    if "weights" in mesh:
        mesh["weights"] = (list(mesh["weights"]) + [0.0] * len(names))[:len(names)]
    if gltf.get("buffers"):
        gltf["buffers"][0]["byteLength"] = len(out)
    return bytes(out)


_COMP = {5121: ("B", 1), 5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
_WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def _elements(gltf: dict, acc_i: int) -> tuple[str, int, int, int, int]:
    """(struct code, component size, width, first byte, stride) of an accessor's elements."""
    acc = gltf["accessors"][acc_i]
    view = gltf["bufferViews"][acc["bufferView"]]
    code, size = _COMP[acc["componentType"]]
    width = _WIDTH[acc["type"]]
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    return code, size, width, start, view.get("byteStride", size * width)


def drop_unweighted_joints(path: str | Path, names) -> list[str]:
    """Take the joints named in `names` out of every skin in which no vertex is weighted to them,
    and renumber the meshes' JOINTS_0 to match. The bones stay in the node tree.

    A part is bound to the rig's skeleton by its skin's joint names, and a joint the rig lacks
    is an error on every load. The skirt's bones (rig.CLOTH_NAMES) are in every armature the
    forge builds, and so in every part's skin; a part not weighted to them now leaves them out,
    so it binds on a rig built before them as well as after. Returns the names dropped."""
    gltf, bin_chunk = read_glb(path)
    data = bytearray(bin_chunk)
    names = set(names)
    dropped: list[str] = []
    done_acc: set[int] = set()
    for si, skin in enumerate(gltf.get("skins", [])):
        joints = skin["joints"]
        cand = [k for k, j in enumerate(joints) if gltf["nodes"][j].get("name") in names]
        if not cand:
            continue
        prims = [p for n in gltf["nodes"] if n.get("skin") == si and "mesh" in n
                 for p in gltf["meshes"][n["mesh"]]["primitives"]]
        pairs = []
        for p in prims:
            a = p["attributes"]
            k = 0
            while "JOINTS_%d" % k in a:
                pairs.append((a["JOINTS_%d" % k], a["WEIGHTS_%d" % k]))
                k += 1
        used = set()
        for ja, wa in pairs:
            jc, js, jw, j0, jst = _elements(gltf, ja)
            wc, ws, ww, w0, wst = _elements(gltf, wa)
            wscale = {"f": 1.0, "B": 255.0, "H": 65535.0}[wc]
            for i in range(gltf["accessors"][ja]["count"]):
                jv = struct.unpack_from("<%d%s" % (jw, jc), data, j0 + i * jst)
                wv = struct.unpack_from("<%d%s" % (ww, wc), data, w0 + i * wst)
                used.update(j for j, w in zip(jv, wv) if w / wscale > 1e-6)
        drop = [k for k in cand if k not in used]
        if not drop:
            continue
        keep = [k for k in range(len(joints)) if k not in drop]
        new_of = {old: new for new, old in enumerate(keep)}
        for ja, _ in pairs:
            if ja in done_acc:
                continue
            done_acc.add(ja)
            jc, js, jw, j0, jst = _elements(gltf, ja)
            for i in range(gltf["accessors"][ja]["count"]):
                off = j0 + i * jst
                jv = struct.unpack_from("<%d%s" % (jw, jc), data, off)
                # a dropped joint's slot carries no weight: point it at joint 0
                struct.pack_into("<%d%s" % (jw, jc), data, off, *[new_of.get(j, 0) for j in jv])
            gltf["accessors"][ja].pop("min", None)
            gltf["accessors"][ja].pop("max", None)
        if "inverseBindMatrices" in skin:
            ia = skin["inverseBindMatrices"]
            _, _, _, i0, ist = _elements(gltf, ia)
            mats = [bytes(data[i0 + k * ist:i0 + k * ist + 64]) for k in keep]
            for n, m in enumerate(mats):
                data[i0 + n * ist:i0 + n * ist + 64] = m
            gltf["accessors"][ia]["count"] = len(keep)
        dropped += [gltf["nodes"][joints[k]]["name"] for k in drop]
        skin["joints"] = [joints[k] for k in keep]
    if dropped:
        write_glb(path, gltf, bytes(data))
    return dropped


def drop_channels(path: str | Path, names) -> int:
    """Take out of every animation the channels that key a node named in `names`, and the
    samplers only they used. The exporter samples every bone of the armature into every clip,
    and a channel on a skirt's bone (rig.CLOTH_NAMES) would pose it to rest under SkirtDrive:
    no clip keys those bones (docs/CONTRACTS.md §2). The data they pointed at is left unreferenced
    in the buffer. Returns how many channels went."""
    gltf, bin_chunk = read_glb(path)
    names = set(names)
    gone = 0
    for an in gltf.get("animations", []):
        keep = [c for c in an["channels"] if gltf["nodes"][c["target"]["node"]].get("name") not in names]
        gone += len(an["channels"]) - len(keep)
        used = sorted({c["sampler"] for c in keep})
        new_of = {old: new for new, old in enumerate(used)}
        an["samplers"] = [an["samplers"][k] for k in used]
        for c in keep:
            c["sampler"] = new_of[c["sampler"]]
        an["channels"] = keep
    if gone:
        write_glb(path, gltf, bin_chunk)
    return gone


def mesh_triangles(path: str | Path) -> int:
    """Triangles across every mesh in a GLB; 0 for a file that is only a skeleton."""
    return sum(m["tris"] for m in summary(path)["meshes"])


def summary(path: str | Path) -> dict:
    """Quick facts for tests and meta: mesh names, triangle counts, image uris, materials."""
    gltf, _ = read_glb(path)
    accessors = gltf.get("accessors", [])
    meshes = []
    for m in gltf.get("meshes", []):
        tris = 0
        for p in m.get("primitives", []):
            if "indices" in p:
                tris += accessors[p["indices"]]["count"] // 3
            else:
                tris += accessors[p["attributes"]["POSITION"]]["count"] // 3
        meshes.append({"name": m.get("name", ""), "tris": tris})
    return {
        "meshes": meshes,
        "nodes": [n.get("name", "") for n in gltf.get("nodes", [])],
        "images": [i.get("uri", "<embedded>") for i in gltf.get("images", [])],
        "materials": [m.get("name", "") for m in gltf.get("materials", [])],
    }


# -- sparse morph targets and extra attributes (triage 39: the face sliders) --------------------

def read_array(gltf: dict, bin_chunk: bytes, index: int):
    """An accessor as a float numpy array (count, width), sparse substitutions applied; an accessor
    with no buffer view is zeros."""
    import numpy as np
    acc = gltf["accessors"][index]
    dt = {5126: "<f4", 5123: "<u2", 5125: "<u4", 5121: "u1"}[acc["componentType"]]
    width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}[acc["type"]]
    n = acc["count"]
    if "bufferView" in acc:
        view = gltf["bufferViews"][acc["bufferView"]]
        size = np.dtype(dt).itemsize * width
        stride = view.get("byteStride", size)
        start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        if stride == size:
            out = np.frombuffer(bin_chunk, dtype=dt, count=n * width, offset=start).reshape(n, width).astype(float)
        else:
            out = np.stack([np.frombuffer(bin_chunk, dtype=dt, count=width, offset=start + i * stride)
                            for i in range(n)]).astype(float)
    else:
        out = np.zeros((n, width))
    sp = acc.get("sparse")
    if sp:
        iv = gltf["bufferViews"][sp["indices"]["bufferView"]]
        idt = {5123: "<u2", 5125: "<u4", 5121: "u1"}[sp["indices"]["componentType"]]
        idx = np.frombuffer(bin_chunk, dtype=idt, count=sp["count"],
                            offset=iv.get("byteOffset", 0) + sp["indices"].get("byteOffset", 0)).astype(int)
        vv = gltf["bufferViews"][sp["values"]["bufferView"]]
        vals = np.frombuffer(bin_chunk, dtype=dt, count=sp["count"] * width,
                             offset=vv.get("byteOffset", 0) + sp["values"].get("byteOffset", 0)).reshape(-1, width)
        out = out.copy()
        out[idx] = vals
    return out


def _sparse_vec3(gltf: dict, out: bytearray, count: int, idx, vals) -> int:
    """A VEC3 float accessor of `count` rows that is zero but at `idx`, where it is `vals`."""
    import numpy as np
    idx = np.asarray(idx, dtype="<u4")
    vals = np.asarray(vals, dtype="<f4").reshape(-1, 3)
    acc = {"componentType": 5126, "count": int(count), "type": "VEC3"}
    if len(idx):
        iv = _append_view(gltf, out, idx.tobytes())
        vv = _append_view(gltf, out, vals.tobytes())
        acc["sparse"] = {"count": int(len(idx)), "indices": {"bufferView": iv, "componentType": 5125},
                         "values": {"bufferView": vv}}
        acc["min"] = [float(min(0.0, v)) for v in vals.min(axis=0)]
        acc["max"] = [float(max(0.0, v)) for v in vals.max(axis=0)]
    else:
        acc["min"] = [0.0, 0.0, 0.0]
        acc["max"] = [0.0, 0.0, 0.0]
    gltf.setdefault("accessors", []).append(acc)
    return len(gltf["accessors"]) - 1


def morph_target_names(gltf: dict, mesh_index: int) -> list:
    return list((gltf["meshes"][mesh_index].get("extras") or {}).get("targetNames", []))


def drop_morph_targets(gltf: dict, mesh_index: int, keep) -> None:
    """Take the targets whose names fail `keep(name)` off every primitive of a mesh (their data is
    left in the buffer until `compact`)."""
    mesh = gltf["meshes"][mesh_index]
    extras = mesh.setdefault("extras", {})
    names = list(extras.get("targetNames", []))
    kept = [i for i, n in enumerate(names) if keep(n)]
    for p in mesh["primitives"]:
        if "targets" in p:
            p["targets"] = [p["targets"][i] for i in kept if i < len(p["targets"])]
            if not p["targets"]:
                del p["targets"]
    extras["targetNames"] = [names[i] for i in kept]
    if not extras["targetNames"]:
        del extras["targetNames"]
    if not extras:
        del mesh["extras"]
    if "weights" in mesh:
        w = list(mesh["weights"])
        mesh["weights"] = [w[i] if i < len(w) else 0.0 for i in kept]
        if not mesh["weights"]:
            del mesh["weights"]


def add_sparse_morph_target(gltf: dict, bin_chunk: bytes, mesh_index: int, name: str, pos, nrm=None,
                            eps: float = 2e-5) -> bytes:
    """A morph target on a mesh of one primitive, stored sparse: only rows that move more than `eps`
    are written. `pos` and `nrm` are (count, 3) deltas in the glTF frame. If this or any other target
    carries NORMAL, all of them do (zero where there is none), as glTF asks. A target of the same
    name is replaced. Returns the new BIN chunk."""
    import numpy as np
    drop_morph_targets(gltf, mesh_index, lambda n: n != name)
    mesh = gltf["meshes"][mesh_index]
    if len(mesh["primitives"]) != 1:
        raise ValueError("add_sparse_morph_target: %s has %d primitives" % (mesh.get("name"), len(mesh["primitives"])))
    p = mesh["primitives"][0]
    count = gltf["accessors"][p["attributes"]["POSITION"]]["count"]
    pos = np.asarray(pos, float)
    if pos.shape != (count, 3):
        raise ValueError("add_sparse_morph_target: %s deltas for %d vertices" % (pos.shape, count))
    moved = np.linalg.norm(pos, axis=1) > eps
    if nrm is not None:
        nrm = np.asarray(nrm, float)
        moved &= True
        moved |= np.linalg.norm(nrm, axis=1) > 2e-3
    idx = np.nonzero(moved)[0]
    out = bytearray(bin_chunk)
    targets = p.setdefault("targets", [])
    with_normals = nrm is not None or any("NORMAL" in t for t in targets)
    t = {"POSITION": _sparse_vec3(gltf, out, count, idx, pos[idx])}
    if with_normals:
        n_ = nrm if nrm is not None else np.zeros((count, 3))
        t["NORMAL"] = _sparse_vec3(gltf, out, count, idx, n_[idx])
        for other in targets:
            if "NORMAL" not in other:
                other["NORMAL"] = _sparse_vec3(gltf, out, count, [], np.zeros((0, 3)))
    targets.append(t)
    extras = mesh.setdefault("extras", {})
    extras["targetNames"] = list(extras.get("targetNames", [])) + [name]
    if "weights" in mesh:
        mesh["weights"] = list(mesh["weights"]) + [0.0]
    if gltf.get("buffers"):
        gltf["buffers"][0]["byteLength"] = len(out)
    return bytes(out)


def set_attribute(gltf: dict, bin_chunk: bytes, mesh_index: int, attr: str, rows) -> bytes:
    """Give the one primitive of a mesh the float attribute `attr` (TEXCOORD_1, say), replacing it."""
    import numpy as np
    mesh = gltf["meshes"][mesh_index]
    p = mesh["primitives"][0]
    rows = np.asarray(rows, dtype="<f4")
    kind = {1: "SCALAR", 2: "VEC2", 3: "VEC3", 4: "VEC4"}[rows.shape[1]]
    out = bytearray(bin_chunk)
    view = _append_view(gltf, out, rows.tobytes(), 34962)
    gltf.setdefault("accessors", []).append({"bufferView": view, "componentType": 5126,
                                             "count": int(rows.shape[0]), "type": kind})
    p["attributes"][attr] = len(gltf["accessors"]) - 1
    if gltf.get("buffers"):
        gltf["buffers"][0]["byteLength"] = len(out)
    return bytes(out)


def compact(gltf: dict, bin_chunk: bytes) -> bytes:
    """Drop the accessors and buffer views nothing refers to any more and pack the buffer: what
    replacing a morph target or an attribute leaves behind. Skins, animations, sparse accessors
    and images are followed. Returns the new BIN chunk."""
    accessors = gltf.get("accessors", [])
    used = set()
    for m in gltf.get("meshes", []):
        for p in m.get("primitives", []):
            used.update(p.get("attributes", {}).values())
            if "indices" in p:
                used.add(p["indices"])
            for t in p.get("targets", []):
                used.update(t.values())
    for sk in gltf.get("skins", []):
        if "inverseBindMatrices" in sk:
            used.add(sk["inverseBindMatrices"])
    for an in gltf.get("animations", []):
        for smp in an.get("samplers", []):
            used.update((smp["input"], smp["output"]))
    amap, kept = {}, []
    for i, a in enumerate(accessors):
        if i in used:
            amap[i] = len(kept)
            kept.append(a)
    views_used = set()
    for a in kept:
        if "bufferView" in a:
            views_used.add(a["bufferView"])
        if "sparse" in a:
            views_used.update((a["sparse"]["indices"]["bufferView"], a["sparse"]["values"]["bufferView"]))
    for img in gltf.get("images", []):
        if "bufferView" in img:
            views_used.add(img["bufferView"])
    vmap, new_views = {}, []
    out = bytearray()
    for i, v in enumerate(gltf.get("bufferViews", [])):
        if i not in views_used:
            continue
        while len(out) % 4:
            out.append(0)
        nv = dict(v)
        start = v.get("byteOffset", 0)
        nv["byteOffset"] = len(out)
        out.extend(bin_chunk[start:start + v["byteLength"]])
        vmap[i] = len(new_views)
        new_views.append(nv)
    for a in kept:
        if "bufferView" in a:
            a["bufferView"] = vmap[a["bufferView"]]
        if "sparse" in a:
            a["sparse"]["indices"]["bufferView"] = vmap[a["sparse"]["indices"]["bufferView"]]
            a["sparse"]["values"]["bufferView"] = vmap[a["sparse"]["values"]["bufferView"]]
    for img in gltf.get("images", []):
        if "bufferView" in img:
            img["bufferView"] = vmap[img["bufferView"]]
    gltf["accessors"] = kept
    gltf["bufferViews"] = new_views
    for m in gltf.get("meshes", []):
        for p in m.get("primitives", []):
            p["attributes"] = {k: amap[v] for k, v in p.get("attributes", {}).items()}
            if "indices" in p:
                p["indices"] = amap[p["indices"]]
            if "targets" in p:
                p["targets"] = [{k: amap[v] for k, v in t.items()} for t in p["targets"]]
    for sk in gltf.get("skins", []):
        if "inverseBindMatrices" in sk:
            sk["inverseBindMatrices"] = amap[sk["inverseBindMatrices"]]
    for an in gltf.get("animations", []):
        for smp in an.get("samplers", []):
            smp["input"], smp["output"] = amap[smp["input"]], amap[smp["output"]]
    while len(out) % 4:
        out.append(0)
    if gltf.get("buffers"):
        gltf["buffers"][0]["byteLength"] = len(out)
    return bytes(out)
