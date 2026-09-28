#!/usr/bin/env python3
"""Repaint the faces' textures on the heads already built, without Blender and without touching
their geometry: each head's mesh is read back out of its GLB (paint.MeshArrays.from_glb) and the
forge's own paint is run over it again.

    python3 tools/forge/face_textures.py [--only round_f,hawk ...] [--what albedo,zones,eyes,hair]
                                         [--out DIR]

What it writes, beside each part (the names the GLBs and HumanoidModel already read):
    heads/<name>/<name>_albedo.png      the face (paint.skin_paint)
    heads/<name>/<name>_zones.png       where skin is warmer, cooler, oilier and thinner
                                        (paint.face_zones, read by skin.gdshader)
    heads/<name>/<name>_eye_albedo.png  the eyeball (paint.iris_texture)
    hair|beards/<name>/<name>_flow.png  which way the hair runs, fine strands and root to tip
                                        (hair_flow, read by hair.gdshader)
and the same for the rig's own head (humanoid_rig_head_*).

A head the forge builds again (`parts --only heads`) gets all of these from the forge itself;
this is for a change of paint alone, which should not need the heads' geometry rebuilt (and so
does not fight with work on their shape). `--out` writes into another folder, for comparing."""
from __future__ import annotations

import argparse
import os
import zlib
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))

import numpy as np

import character_forge as cf
from forge.lib import body as bodylib, paint, rig


def heads():
    """(part name, glb, mesh name, HeadStyle params, feminine, texture stem, out dir)."""
    out = []
    for name, params, fem in cf._head_builds():
        d = os.path.join(cf.OUT_ROOT, cf.PART_DIRS["head"], name)
        out.append((name, os.path.join(d, "%s.glb" % name), "Head_Mesh", params, fem, name, d))
    d = os.path.join(cf.OUT_ROOT, "humanoid_rig")
    out.append(("humanoid_rig", os.path.join(d, "humanoid_rig.glb"), "Head_Mesh", {}, 0.0, "humanoid_rig_head", d))
    return out


def repaint_head(name, glb, mesh, params, fem, stem, part_dir, what, out_dir=None):
    out_dir = out_dir or part_dir
    os.makedirs(out_dir, exist_ok=True)
    skel = cf.variant_skeleton(rig.Proportions(feminine=fem)) if name != "humanoid_rig" else rig.Skeleton(rig.Proportions())
    hs = bodylib.HeadStyle.from_dict(params)
    ob = paint.MeshArrays.from_glb(glb, mesh)
    app = dict(cf.DEFAULT_APPEARANCE)
    done = []
    if "albedo" in what:
        cf.paint_body(ob, skel, hs, out_dir, stem, dict(app, face=True, freckles=0.0) if name != "humanoid_rig"
                      else dict(app, face=True), size=768 if name != "humanoid_rig" else cf.BODY_TEX,
                      scene=bodylib.head_scene(skel, hs, flat=True), albedo_only=True)
        done.append("albedo")
    if "zones" in what and hasattr(cf, "paint_zones"):
        cf.paint_zones(ob, skel, hs, out_dir, stem)
        done.append("zones")
    if "eyes" in what:
        cf.paint_eyes(out_dir, ("%s_eye" % name) if name != "humanoid_rig" else "humanoid_rig_eye", app)
        done.append("eyes")
    return done


def hair_parts():
    """(part name, glb, part dir) for every hair style and beard built."""
    out = []
    for kind in ("hair", "beard"):
        root = os.path.join(cf.OUT_ROOT, cf.PART_DIRS[kind])
        for name in sorted(os.listdir(root)) if os.path.isdir(root) else []:
            glb = os.path.join(root, name, "%s.glb" % name)
            if os.path.exists(glb):
                out.append((name, kind, glb, os.path.join(root, name)))
    return out


def hair_flow(normal_png: str, mesh: "paint.MeshArrays", kind: str, seed: int = 0) -> np.ndarray:
    """The hair's flow map (RGBA, the size of its normal map), read by hair.gdshader:

      RG  which way the strands run, in the normal map's own tangent frame, as the doubled angle
          (so that filtering between a strand running one way and the same strand read the other
          way does not cancel), scaled by how sure the grain is of it
      B   fine strands: noise drawn out along that direction (a line-integral convolution), a
          few texels across, which the shader lays over the painted clumps and uses to break the
          silhouette into strands
      A   root to tip: 0 by the scalp, 1 at the ends of long hair (from the part's own geometry)

    The direction is the grain the forge painted (paint.hair_strands smears noise along each
    strand), read back as the structure tensor of the normal map: the bumps run across the
    strands, so the strands run across the bumps."""
    from PIL import Image
    from scipy import ndimage
    # the grain read off the albedo: its stripes are the painted strands (the normal map's
    # bumps are finer and read as noise at this scale)
    alb = np.asarray(Image.open(normal_png.replace("_normal.png", "_albedo.png")).convert("L"), float) / 255.0
    H, W = alb.shape[:2]
    gx = ndimage.sobel(alb, axis=1)
    gy = -ndimage.sobel(alb, axis=0)           # the tangent frame's y runs up the image
    sig = max(3.0, W / 80.0)
    jxx = ndimage.gaussian_filter(gx * gx, sig)
    jyy = ndimage.gaussian_filter(gy * gy, sig)
    jxy = ndimage.gaussian_filter(gx * gy, sig)
    across = 0.5 * np.arctan2(2 * jxy, jxx - jyy)
    theta = across + 0.5 * np.pi
    tr = jxx + jyy
    coh = np.sqrt((jxx - jyy) ** 2 + 4 * jxy * jxy) / np.maximum(tr, 1e-9)
    coh = np.clip(coh * 1.6, 0, 1) * (tr > 1e-7)
    # fine strands: white noise smeared along the strands. Image rows run down while the normal
    # map's y runs up the texture, hence the sign on the row step.
    rng = np.random.default_rng(seed)
    noise = ndimage.gaussian_filter(rng.random((H, W)), 0.6)
    dx, dy = np.cos(theta), -np.sin(theta)
    yy, xx = np.mgrid[0:H, 0:W].astype(float)
    acc = noise.copy()
    wsum = np.ones((H, W))
    steps = max(6, W // 40)
    for sgn in (1.0, -1.0):
        px, py = xx.copy(), yy.copy()
        for k in range(1, steps):
            ix = np.clip(px.round().astype(int), 0, W - 1)
            iy = np.clip(py.round().astype(int), 0, H - 1)
            px = px + sgn * dx[iy, ix]
            py = py + sgn * dy[iy, ix]
            w = 1.0 - k / steps
            acc += w * ndimage.map_coordinates(noise, [py, px], order=1, mode="wrap")
            wsum += w
    fine = acc / wsum
    fine = (fine - fine.mean()) / max(fine.std(), 1e-6)
    fine = np.clip(0.5 + 0.22 * fine, 0, 1)
    # root to tip, from the geometry behind each texel
    maps = paint.surface_maps(mesh, size=W, pad=3)
    z = maps["pos"][..., 2]
    L = bodylib.head_landmarks(rig.Skeleton(rig.Proportions()))
    if kind == "beard":
        tip = 1.0 - paint.smoothstep(float(L["chin_z"]) - 0.08, float(L["mouth_z"]), z)
    else:
        tip = 1.0 - paint.smoothstep(float(L["eye_z"]) - 0.34, float(L["eye_z"]) - 0.02, z)
    tip = np.where(maps["mask"], tip, 0.0)
    tip = np.flipud(tip)          # surface_maps' rows run up v (Blender), the image's down
    out = np.stack([0.5 + 0.5 * np.cos(2 * theta) * coh, 0.5 + 0.5 * np.sin(2 * theta) * coh, fine, tip], axis=-1)
    return np.clip(out, 0, 1)


def repaint_hair(name, kind, glb, part_dir, out_dir=None):
    out_dir = out_dir or part_dir
    os.makedirs(out_dir, exist_ok=True)
    from forge.lib import glb as glbfile
    gltf, _ = glbfile.read_glb(glb)
    written = []
    for m in gltf["meshes"]:
        prim = m["primitives"][0]
        mat = gltf["materials"][prim["material"]] if "material" in prim else {}
        ni = mat.get("normalTexture", {}).get("index")
        if ni is None:
            continue
        uri = gltf["images"][gltf["textures"][ni]["source"]]["uri"]
        stem = uri.replace("_normal.png", "")
        flow = hair_flow(os.path.join(part_dir, uri), paint.MeshArrays.from_glb(glb, m["name"]), kind,
                         seed=zlib.crc32(stem.encode()) % 9973)
        # already in the image's own orientation (read off the normal map), so not flipped again
        path = os.path.join(out_dir, "%s_flow.png" % stem)
        from PIL import Image
        Image.fromarray((flow * 255.0 + 0.5).astype(np.uint8), mode="RGBA").save(path)
        written.append(path)
    return written


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--only", default="", help="comma-separated part names")
    ap.add_argument("--what", default="albedo,zones,eyes,hair")
    ap.add_argument("--out", default=None, help="write here instead of beside each part")
    a = ap.parse_args(argv)
    only = set(x for x in a.only.split(",") if x)
    what = set(a.what.split(","))
    for name, glb, mesh, params, fem, stem, d in heads():
        if (only and name not in only) or not what & {"albedo", "zones", "eyes"}:
            continue
        if not os.path.exists(glb):
            continue
        t0 = time.time()
        done = repaint_head(name, glb, mesh, params, fem, stem, d, what,
                            os.path.join(a.out, name) if a.out else None)
        print("head %-14s %s  %.0fs" % (name, ",".join(done), time.time() - t0), flush=True)
    if "hair" in what:
        for name, kind, glb, d in hair_parts():
            if only and name not in only and kind not in only:
                continue
            t0 = time.time()
            w = repaint_hair(name, kind, glb, d, os.path.join(a.out, name) if a.out else None)
            print("%s %-14s %s  %.0fs" % (kind, name, " ".join(os.path.basename(x) for x in w), time.time() - t0),
                  flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
