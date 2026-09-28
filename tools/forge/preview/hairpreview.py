"""A quick look at a hair style on the default head, ray-marched in numpy off the style's own field:
for judging a groom's shape without a Blender build. Grey head, brown hair, front / side / back.

    python3 hairpreview.py <out.png> style[,style...] [--body]

`--body` combs the hanging hair against the body's field, as the forge does (a few minutes more);
without it long hair hangs through the shoulders."""
import sys
import time
from pathlib import Path
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import numpy as np
from PIL import Image
from forge.lib import rig, body as bodylib, cloth, sdf


def march(fields, O, D, far=0.9):
    t = np.zeros(len(O))
    hit = np.full(len(O), -1)
    for _ in range(300):
        P = O + D * t[:, None]
        ds = np.stack([f(P) for f in fields], axis=1)
        d = ds.min(axis=1)
        new = (hit < 0) & (d < 0.0006)
        hit[new] = ds[new].argmin(axis=1)
        live = hit < 0
        t = np.where(live, t + np.clip(d * 0.9, 0.0006, 0.01), t)
        if not np.any(live & (t < far)):
            break
    return O + D * t[:, None], hit


def view(fields, colours, centre, fwd, up, half=0.28, n=260):
    fwd = fwd / np.linalg.norm(fwd)
    right = np.cross(fwd, up)
    u = np.linspace(-half, half, n)
    U, W = np.meshgrid(u, -u)
    O = centre - fwd * 0.5 + U.ravel()[:, None] * right + W.ravel()[:, None] * up
    D = np.tile(fwd, (len(O), 1))
    P, hit = march(fields, O, D)
    e = 0.0012
    img = np.tile(np.array([0.55, 0.52, 0.48]), (len(O), 1))
    key = np.array([0.4, -0.7, 0.6]); key /= np.linalg.norm(key)
    for i, f in enumerate(fields):
        m = hit == i
        if not m.any():
            continue
        Q = P[m]
        nrm = np.stack([f(Q + [e, 0, 0]) - f(Q - [e, 0, 0]), f(Q + [0, e, 0]) - f(Q - [0, e, 0]),
                        f(Q + [0, 0, e]) - f(Q - [0, 0, e])], axis=1)
        nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)
        lam = 0.35 + 0.65 * np.clip(nrm @ key, 0, 1) + 0.15 * np.clip(-nrm @ fwd, 0, 1)
        img[m] = np.clip(np.asarray(colours[i]) * lam[:, None], 0, 1)
    return (img.reshape(n, n, 3) * 255).astype(np.uint8)


def main():
    out = sys.argv[1]
    styles = sys.argv[2].split(",")
    with_body = "--body" in sys.argv
    skel = rig.Skeleton(rig.Proportions())
    body = cloth.body_field(skel) if with_body else None
    head = bodylib.head_scene(skel, None, with_neck=True, flat=True)
    headf = sdf.SampledField(head, spacing=0.003, margin=0.03)
    torso = sdf.SampledField(bodylib.body_scene(skel), spacing=0.008, margin=0.03) if with_body else None
    L = bodylib.head_landmarks(skel)
    c = np.array([0.0, 0.02, float(L["chin_z"]) - 0.02])
    n = 260
    sheet = Image.new("RGB", (n * 3, n * len(styles)))
    for j, st in enumerate(styles):
        t0 = time.time()
        g = cloth.build_hair(skel, st, body=body)
        hf = sdf.SampledField(g.scene, spacing=0.0028, margin=0.02)
        fields = [headf.eval, hf.eval] + ([torso.eval] if torso is not None else [])
        cols = [(0.86, 0.72, 0.60), (0.45, 0.30, 0.18), (0.70, 0.66, 0.60)]
        for i, (fwd, ) in enumerate([(np.array([0.0, 1.0, 0.0]),), (np.array([-1.0, 0.0, 0.0]),),
                                     (np.array([0.0, -1.0, 0.0]),)]):
            sheet.paste(Image.fromarray(view(fields, cols, c, fwd, np.array([0.0, 0.0, 1.0]), n=n)), (i * n, j * n))
        print("  %s in %.0fs" % (st, time.time() - t0), flush=True)
    sheet.save(out)
    print("wrote", out)


if __name__ == "__main__":
    main()
