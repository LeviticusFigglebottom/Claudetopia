"""A head as the forge builds it, in numpy, without Blender: meshed from its field, its eyes in
place with their painted iris, the skin painted at its vertices by the forge's own skin paint
(occlusion included) and, if asked, a hair style over it; drawn flat-lit from the front, the
three-quarter and the side. For judging the lids, the eyes, the paint and the hair between
Blender builds, which take forty minutes for the eight heads.

    python3 tools/forge/preview/headpreview.py <out.png> [head preset] [--hair=short] [--spacing=0.0030]
        [--tone=wheat] [--hair-colour=dark_brown] [--views=0,35,90] [--scale=2600] [--neck]

--neck draws the default body under the head, to judge the neck and the shoulders."""
import math
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "forge"))
sys.path.insert(0, str(HERE))
import numpy as np
from PIL import Image
from forge.lib import rig, body as bodylib, paint, sdf, cloth
import lbspreview as LP


def head_style(name):
    if name in ("", "default"):
        return bodylib.HeadStyle()
    import character_forge as CF
    return bodylib.HeadStyle.from_dict(CF.HEAD_PRESETS[name])


def tri(quads):
    q = np.asarray(quads)
    return np.concatenate([q[:, [0, 1, 2]], q[:, [0, 2, 3]]]) if q.shape[1] == 4 else q


def vertex_normals(V, I):
    n = np.cross(V[I[:, 1]] - V[I[:, 0]], V[I[:, 2]] - V[I[:, 0]])
    N = np.zeros_like(V)
    for k in range(3):
        np.add.at(N, I[:, k], n)
    return N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-12)


def main():
    args = dict(a[2:].split("=", 1) for a in sys.argv[1:] if a.startswith("--") and "=" in a)
    flags = {a for a in sys.argv[1:] if a.startswith("--") and "=" not in a}
    pos = [a for a in sys.argv[1:] if not a.startswith("--")]
    out = pos[0]
    name = pos[1] if len(pos) > 1 else "default"
    spacing = float(args.get("spacing", 0.0030))
    t0 = time.time()
    skel = rig.Skeleton(rig.Proportions())
    hs = head_style(name)
    L = bodylib.head_landmarks(skel, hs)
    v, q = bodylib.head_mesh(skel, hs, spacing=spacing)
    I = tri(q)
    N = vertex_normals(v, I)
    print("meshed %d verts in %.0fs" % (len(v), time.time() - t0), flush=True)
    scene = bodylib.head_scene(skel, hs, flat=True).near(0.08)
    fn = paint.skin_paint(L, tone=args.get("tone", "wheat"), seed=0, face=True,
                          brow_colour=args.get("hair-colour", "dark_brown"), age=0.3,
                          scene=scene, occ_radius=0.022)
    col = np.clip(fn(v, N), 0, 1) ** 2.2          # sRGB paint to linear for the flat shade
    print("painted in %.0fs" % (time.time() - t0), flush=True)
    meshes = [(v, I, col[I].mean(axis=1))]
    # the eyes, their iris painted as the forge paints them (v = polar angle / pi)
    tex = paint.iris_texture(128, colour="brown")
    for sx in (1, -1):
        c = np.array([sx * L["eye_x"], L["eye_c_y"], L["eye_z"]])
        ev, ef, euv = bodylib.eye_mesh(c, L["eye_r"], nu=48, nv=36)
        eI = tri(ef)
        uvc = euv[eI].mean(axis=1)
        px = np.clip((uvc[:, 0] * 128).astype(int), 0, 127)
        py = np.clip((uvc[:, 1] * 128).astype(int), 0, 127)
        meshes.append((ev, eI, np.clip(tex[py, px], 0, 1) ** 2.2))
    if args.get("hair"):
        g = cloth.build_hair(skel, args["hair"], body=None, hs=hs)
        hv, hq = g.mesh()
        base = paint.hex_rgb(paint.HAIR_COLOURS.get(args.get("hair-colour", "dark_brown"), "#3b2a1e"))
        meshes.append((hv, tri(hq), np.clip(base * 1.2, 0, 1) ** 2.2))
        print("hair in %.0fs" % (time.time() - t0), flush=True)
    if "--neck" in flags:
        from bodycache import body as cached
        bv, bq = sdf.mesh_from_scene(bodylib.body_scene(skel, bodylib.BodyStyle()), 0.008, smooth_iters=3, project=1)
        keep = bv[:, 2] > float(L["chin_z"]) - 0.30
        bI = tri(bq)
        bI = bI[keep[bI].all(axis=1)]
        meshes.append((bv, bI, np.array([0.55, 0.42, 0.34])))
    views = [float(x) for x in args.get("views", "0,35,90").split(",")]
    scale = float(args.get("scale", 2600))
    cz = float(args.get("centre", L["eye_z"] - 0.03))
    panels = [LP.raster(meshes, vw, size=(int(0.26 * scale), int(0.30 * scale)), centre_z=cz, scale=scale)
              for vw in views]
    img = np.clip(np.concatenate(panels, axis=1), 0, 1) ** (1 / 2.2)
    Image.fromarray((img * 255).astype(np.uint8)).save(out)
    print("wrote %s in %.0fs" % (out, time.time() - t0))


if __name__ == "__main__":
    main()
