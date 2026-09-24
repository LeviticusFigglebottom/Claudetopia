"""Mesh one garment in numpy against the cached body field, weight it (its weight_fn, or the committed
body's weights by nearest vertex), pose it with the committed body in a clip and rasterise both, with
the garment's woven pattern as per-triangle colour when it has one.

    python3 garmenttest.py <out.png> <garment> [--clip=Idle@0] [--views=0,35,180] [--under=<part>,...]"""
import sys
import time
from pathlib import Path
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(HERE))
import numpy as np
from PIL import Image
from forge.lib import rig, sdf, cloth, body as bodylib
import lbspreview as LP
from bodycache import body as cached_body

R = str(ROOT / "game/assets/models/characters") + "/"
out, name = sys.argv[1], sys.argv[2]
clip, t = "Idle", 0.0
views = [0, 35, 180]
under = []
for a in sys.argv[3:]:
    if a.startswith("--clip="):
        clip, t = a[7:].split("@"); t = float(t)
    elif a.startswith("--views="):
        views = [float(v) for v in a[8:].split(",")]
    elif a.startswith("--under="):
        under = a[8:].split(",")
skel = rig.Skeleton(rig.Proportions())
t0 = time.time()
body = cached_body(skel)
print("body field %.1fs" % (time.time() - t0))
g = cloth.CLOTHING_BUILDERS[name](skel, body)
names = list(rig.DEFORM_NAMES)
S = LP.pose_matrices(skel, clip, t)
meshes = []
# the committed body (and any committed parts under the garment), posed
for nm, V, J, Wt, I, bn in LP.load(R + "humanoid_rig/humanoid_rig.glb", "body"):
    meshes.append((LP.skin(V, J, Wt, bn, S), I, np.array([0.79, 0.64, 0.49])))
    body_V, body_J, body_W, body_names = V, J, Wt, bn
for u in under:
    for nm, V, J, Wt, I, bn in LP.load(R + "clothing/%s/%s.glb" % (u, u)):
        meshes.append((LP.skin(V, J, Wt, bn, S), I, np.array([0.80, 0.76, 0.66])))
# the body's weights in rig.DEFORM_NAMES order, which is what the forge's weight functions index
col = {n: i for i, n in enumerate(names)}
full = np.zeros((len(body_V), len(names)))
for k in range(body_J.shape[1]):
    for ji in np.unique(body_J[:, k]):
        if body_names[ji] in col:
            sel = body_J[:, k] == ji
            full[sel, col[body_names[ji]]] += body_W[sel, k]
for piece in [g] + list(g.layers):
    V, Q = piece.mesh()
    Q = np.asarray(Q)
    if piece.trim is not None:
        Qc = V[Q].mean(axis=1)
        Q = Q[piece.trim.eval(Qc) >= -piece.trim_depth]
    I = np.concatenate([Q[:, [0, 1, 2]], Q[:, [0, 2, 3]]]) if Q.shape[1] == 4 else Q
    print("%s: %d verts %d tris (%.1fs)" % (piece.name, len(V), len(I), time.time() - t0))
    if piece.weight_fn is not None:
        W = piece.weight_fn(V)
        wn = names
    else:
        W = bodylib.nearest_weights(V, body_V, full, 4)
        wn = names
    if piece.weight_adjust is not None:
        W = piece.weight_adjust(V, W)
    W = bodylib.limit_influences(np.asarray(W, float))
    if getattr(piece, "rebind", False):
        V = cloth.rebind_from_idle(skel, V, W)
    idx = np.argsort(-W, axis=1)[:, :4]
    w = np.take_along_axis(W, idx, axis=1)
    w /= np.maximum(w.sum(axis=1, keepdims=True), 1e-9)
    P = LP.skin(V, idx, w, wn, S)
    col = np.array([0.66, 0.62, 0.55]) if piece.material != "iron" else np.array([0.62, 0.64, 0.68])
    if piece.pattern is not None:
        C = V[I].mean(axis=1)
        col = piece.pattern(C, np.zeros_like(C))
    meshes.append((P, I, col))
panels = [LP.raster(meshes, v) for v in views]
img = np.concatenate(panels, axis=1)
Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).save(out)
print("wrote", out, "%.1fs" % (time.time() - t0))
