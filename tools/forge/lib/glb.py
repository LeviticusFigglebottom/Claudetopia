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
