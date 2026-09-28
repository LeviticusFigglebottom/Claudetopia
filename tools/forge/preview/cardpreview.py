"""Hair cards drawn in numpy on the default head, for judging a style without the engine: the cards
alpha-tested against the strand atlas, the cap thinned by its grain, lit roughly as the shader
lights them (wrap diffuse off the mass normal, a band of shine along the strands).

    python3 cardpreview.py <out.png> style[,style...] [--views=front,three_quarter,back] [--size=260]
    python3 cardpreview.py <out.png> --built style,...      # read the cards back out of the GLBs

Styles are built on the fly (tools/forge/hair_cards.py's build, `--dry`) unless `--built`."""
import sys
import math
from pathlib import Path
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "forge"))
import numpy as np
from PIL import Image, ImageDraw
from forge.lib import glb, hair_cards as HC

CHAR = ROOT / "game" / "assets" / "models" / "characters"
TEX = ROOT / "game" / "assets" / "textures" / "characters"
HAIR = np.array([0.40, 0.28, 0.19])


def to_forge(v):
    return np.stack([v[:, 0], -v[:, 2], v[:, 1]], axis=1)


def head_mesh():
    j, b = glb.read_glb(CHAR / "heads" / "default" / "default.glb")
    out = []
    for m in j["meshes"]:
        p = m["primitives"][0]
        V = to_forge(glb.read_array(j, b, p["attributes"]["POSITION"]))
        T = glb.read_array(j, b, p["indices"]).astype(int).reshape(-1, 3)
        out.append((V, T))
    return out


def built_cards(name):
    for sub in ("hair", "beards"):
        path = CHAR / sub / name / (name + ".glb")
        if path.exists():
            j, b = glb.read_glb(path)
            for m in j["meshes"]:
                if m["name"] == name + "_cards":
                    p = m["primitives"][0]
                    a = p["attributes"]
                    return {"P": to_forge(glb.read_array(j, b, a["POSITION"])),
                            "N": to_forge(glb.read_array(j, b, a["NORMAL"])),
                            "T": to_forge(glb.read_array(j, b, a["TANGENT"])[:, :3]),
                            "UV": glb.read_array(j, b, a["TEXCOORD_0"]), "UV2": glb.read_array(j, b, a["TEXCOORD_1"]),
                            "COL": glb.read_array(j, b, a["COLOR_0"]),
                            "tris": glb.read_array(j, b, p["indices"]).astype(int).reshape(-1, 3)}
    return None


VIEWS = {"front": 0.0, "three_quarter": 40.0, "side": 90.0, "back": 180.0}


def render(head, cards, view, n=260, centre=None, half=0.16):
    atlas = np.asarray(Image.open(TEX / "hair_strands.png"), float) / 255.0
    grain = np.asarray(Image.open(TEX / "hair_grain.png"), float) / 255.0
    ang = math.radians(VIEWS[view])
    # the camera looks at the face (-Y is forward), turned `ang` round to the head's left
    fwd = np.array([math.sin(ang), math.cos(ang), 0.0])          # camera looks along +fwd
    right = np.cross(fwd, [0.0, 0.0, 1.0])
    up = np.array([0.0, 0.0, 1.0])
    key = np.array([0.5, -0.6, 0.62]); key /= np.linalg.norm(key)
    V_eye = -fwd
    img = np.zeros((n, n, 3)); img[:] = [0.30, 0.31, 0.33]
    zb = np.full((n, n), np.inf)
    c = centre

    def project(P):
        rel = P - c
        return ((rel @ right) + half) / (2 * half) * n, (half - rel @ up) / (2 * half) * n, rel @ fwd

    def raster(P, T, shade_fn, cull=True):
        X, Y, D = project(P)
        for ti, tri in enumerate(T):
            xs, ys = X[tri], Y[tri]
            x0, x1 = int(max(np.floor(xs.min()), 0)), int(min(np.ceil(xs.max()), n - 1))
            y0, y1 = int(max(np.floor(ys.min()), 0)), int(min(np.ceil(ys.max()), n - 1))
            if x1 < x0 or y1 < y0:
                continue
            d = (ys[1] - ys[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (ys[0] - ys[2])
            if abs(d) < 1e-9 or (cull and d > 0):
                continue
            gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
            a = ((ys[1] - ys[2]) * (gx - xs[2]) + (xs[2] - xs[1]) * (gy - ys[2])) / d
            b_ = ((ys[2] - ys[0]) * (gx - xs[2]) + (xs[0] - xs[2]) * (gy - ys[2])) / d
            cc = 1 - a - b_
            inside = (a >= 0) & (b_ >= 0) & (cc >= 0)
            if not inside.any():
                continue
            w = np.stack([a[inside], b_[inside], cc[inside]], 1)
            z = w @ D[tri]
            iy, ix = np.nonzero(inside)
            py, px = iy + y0, ix + x0
            col, keep = shade_fn(tri, w)
            closer = (z < zb[py, px]) & keep
            zb[py[closer], px[closer]] = z[closer]
            img[py[closer], px[closer]] = col[closer]

    for V, T in head:
        fn = np.cross(V[T[:, 1]] - V[T[:, 0]], V[T[:, 2]] - V[T[:, 0]])
        N = np.zeros_like(V)
        for k in range(3):
            np.add.at(N, T[:, k], fn)
        N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-12)
        sh = np.clip(N @ key, 0, 1) * 0.7 + 0.25

        def skin(tri, w, sh=sh):
            s_ = w @ sh[tri]
            return np.array([0.78, 0.60, 0.50])[None] * s_[:, None], np.ones(len(w), bool)
        raster(V, T, skin, cull=False)

    if cards:
        P, N, Tg, UV, UV2, COL = cards["P"], cards["N"], cards["T"], cards["UV"], cards["UV2"], cards["COL"]
        H, W = atlas.shape[:2]
        G = grain.shape[0]

        def hair(tri, w):
            uv = w @ UV[tri]
            u2 = w @ UV2[tri]
            nrm = w @ N[tri]
            nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)
            t = w @ Tg[tri]
            t /= np.maximum(np.linalg.norm(t, axis=1, keepdims=True), 1e-9)
            layer = w @ COL[tri, 2]
            if uv[0, 0] >= 2.0:        # the cap
                g = grain[(np.mod(uv[:, 1], 1) * G).astype(int) % G, (np.mod(uv[:, 0] - 2, 1) * G).astype(int) % G]
                dens = u2[:, 1]
                keep = (g[:, 0] + dens - 1.0 > 0.0) | (dens > 0.98)
                val = 0.55 * (0.7 + 0.6 * g[:, 1])
                ao = 0.8
            else:
                solid = uv[0, 0] >= 1.0
                uu = np.mod(uv[:, 0], 1.0)
                tx = atlas[np.clip(np.mod(uv[:, 1], 1) * H, 0, H - 1).astype(int), np.clip(uu * W, 0, W - 1).astype(int)]
                keep = np.ones(len(uv), bool) if solid else tx[:, 3] > 0.5
                val = tx[:, 0] * (0.7 + 0.3 * np.clip(u2[:, 0] * 3, 0, 1)) * 1.25
                ao = 0.55 + 0.45 * layer
            diff = np.clip((nrm @ key + 0.35) / 1.35, 0, 1)
            h = key + V_eye
            h /= np.linalg.norm(h)
            th = t @ h
            spec = np.sqrt(np.clip(1 - th * th, 0, 1)) ** 60 * 0.35 * (diff > 0.1)
            col = HAIR[None] * (val * ao * (0.25 + 0.95 * diff))[:, None] + spec[:, None] * 0.8
            return np.clip(col, 0, 1), keep
        raster(P, cards["tris"], hair, cull=False)
    return (np.clip(img, 0, 1) * 255).astype(np.uint8)


def main():
    out = sys.argv[1]
    args = sys.argv[2:]
    views = ["front", "three_quarter", "back"]
    size = 260
    built = False
    names = []
    for a in args:
        if a.startswith("--views="):
            views = a[8:].split(",")
        elif a.startswith("--size="):
            size = int(a[7:])
        elif a == "--built":
            built = True
        else:
            names += a.split(",")
    head = head_mesh()
    allV = np.concatenate([h[0] for h in head])
    centre = np.array([0.0, allV[:, 1].mean(), allV[:, 2].max() - 0.13])
    sheet = Image.new("RGB", (size * len(views), size * len(names) + 16 * len(names)), (20, 20, 20))
    dr = ImageDraw.Draw(sheet)
    rep = {}
    if not built:
        import hair_cards as tool
        rep = tool.build(names, dry=True)
    for r, name in enumerate(names):
        cards = built_cards(name) if built else rep.get(name, {}).get("arrays")
        long_ = name in ("long", "long_loose", "shoulder", "twin_braids", "braid", "ponytail", "long_beard", "curly")
        c = centre - np.array([0.0, 0.0, 0.07]) if long_ else centre
        for k, v in enumerate(views):
            im = render(head, cards, v, size, c, half=0.22 if long_ else 0.15)
            sheet.paste(Image.fromarray(im), (k * size, r * (size + 16) + 16))
        tri = len(cards["tris"]) if cards else 0
        dr.text((4, r * (size + 16) + 2), "%s  %d tris" % (name, tri), fill=(230, 230, 230))
        print(" ", name, flush=True)
    sheet.save(out)
    print("wrote", out)


if __name__ == "__main__":
    main()
