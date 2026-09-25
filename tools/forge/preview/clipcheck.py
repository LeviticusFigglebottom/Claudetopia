"""Where the body comes out through its clothes in a clip, measured on the built GLBs with the rig's
own animations (the clips the game plays, not the forge's Python ones), in numpy.

    python3 tools/forge/preview/clipcheck.py [--clips=Run,Sprint] [--steps=12] [--body=heavy]
        [--parts=tunic,kilt] [--under=trousers] [--bones=UpperLeg,LowerLeg] [--png=<dir>]
        [--tol=0.002] [--rig=<rig.glb>] [--reweight=<cloth fn>[:k=v,...]] [--open-hem] [--novis]
        [--reweight-cloak=_cloak_weights:hooded=0,hang=1,hand=0.18]
        [--hold=0.7] [--arm-out=7] [--cover=Idle@0]

--under wears parts under the one measured (the trousers under a tunic), --bones counts only the
body vertices those bones move most, --reweight skins the part again in numpy as the forge would
(the body's weights by nearest vertex, then the named cloth weight_adjust, "" for none),
--reweight-cloak weights a cloak modelled round the Idle's arms by a cloth weight_fn, and
--cover takes what is under the cloth in that pose rather than the bind pose (a cloak is modelled
round the Idle's hanging arms), --hold and --arm-out pose the arms as the game's ArmRoom does (HumanoidModel.ARM_HOLD under a
cloak, ARM_ROOM for padding), --open-hem drops a skirt's flat cap at its hem before measuring (to judge a part built before the
forge left it open), and --novis counts vertices that came through even where the rest of the figure hides them (a covered
point is otherwise counted only when it is drawn, seen from the front, back or either side).

Every garment is one sheet, its outer surface, facing out (the forge trims what lies under it). A
body vertex is *covered* when its nearest garment point at rest is inside the sheet (not on an open
edge: a hem, a cuff, a neckline), within 6 cm, and the vertex is under it. In a pose it has *come
through* when its nearest garment point is again inside the sheet and the vertex stands more than
--tol outside it: the body drawn over the cloth that should hide it. A covered vertex whose nearest
point is an open edge has left under the hem, which a stride may do; that is not counted.

Per part and clip it prints the worst sample: how many vertices came through, how deep, and on which
bones. With --png it draws the worst sample of each part front, side and back, the body red where it
came through."""
from __future__ import annotations

import math
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(HERE))
import numpy as np
from scipy.spatial import cKDTree
from forge.lib import glb
import lbspreview as LP

CHARS = ROOT / "game" / "assets" / "models" / "characters"
RIG = CHARS / "humanoid_rig" / "humanoid_rig.glb"
GAITS = ["Walk", "Trot", "Run", "Sprint", "Walk_Back", "Strafe_L", "Strafe_R", "Sneak_Walk", "Dodge_F",
         "Jump_Start", "Jump_Loop", "Jump_Land"]


# ---------------------------------------------------------------------------- glTF

def _quat_mat(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def _qmul(a, b):
    x1, y1, z1, w1 = a
    x2, y2, z2, w2 = b
    return np.array([w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2, w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2,
                     w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2, w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2])


def _trs(t, r, s):
    M = np.eye(4)
    M[:3, :3] = _quat_mat(r) * np.asarray(s, float)[None, :]
    M[:3, 3] = t
    return M


class Rig:
    """The rig GLB's node tree and its animations, sampled to world matrices by node name."""

    def __init__(self, path=RIG):
        g, b = glb.read_glb(path)
        self.g, self.b = g, b
        self.nodes = g["nodes"]
        self.parent = {}
        for i, n in enumerate(self.nodes):
            for c in n.get("children", []):
                self.parent[c] = i
        self.clips = {}
        for an in g.get("animations", []):
            ch = {}
            length = 0.0
            for c in an["channels"]:
                s = an["samplers"][c["sampler"]]
                ti = LP.acc(g, b, s["input"])[:, 0]
                vo = LP.acc(g, b, s["output"])
                ch[(c["target"]["node"], c["target"]["path"])] = (ti, vo)
                length = max(length, float(ti[-1]))
            self.clips[an["name"]] = (ch, length)

    ARMS = ("UpperArm.L", "UpperArm.R", "LowerArm.L", "LowerArm.R")
    hold = 0.0          # ArmRoom.hold: the share of the arms' pose taken back to the Idle's hang
    arm_out = 0.0       # ArmRoom.degrees: the upper arms turned out about the body's forward axis

    def _sample(self, ch, i, path, t, default):
        if (i, path) not in ch:
            return default
        ti, vo = ch[(i, path)]
        if t <= ti[0]:
            return vo[0]
        if t >= ti[-1]:
            return vo[-1]
        k = int(np.searchsorted(ti, t)) - 1
        f = (t - ti[k]) / max(ti[k + 1] - ti[k], 1e-9)
        a, bb = vo[k], vo[k + 1]
        if path == "rotation":
            if np.dot(a, bb) < 0:
                bb = -bb
            v = a * (1 - f) + bb * f
            return v / np.linalg.norm(v)
        return a * (1 - f) + bb * f

    def world_cache_parent(self, i, clip, t):
        """The world matrix of node i's parent in the clip, unmodified (a shoulder is never held)."""
        saved, self.hold, self.arm_out = (self.hold, self.arm_out), 0.0, 0.0
        try:
            return self.world(clip, t)[self.nodes[self.parent[i]]["name"]]
        finally:
            self.hold, self.arm_out = saved

    def world(self, clip=None, t=0.0):
        ch = self.clips[clip][0] if clip else {}
        idle = self.clips["Idle"][0] if "Idle" in self.clips else {}
        local = []
        for i, n in enumerate(self.nodes):
            if clip and n["name"] in self.ARMS and (self.hold > 0 or self.arm_out):
                r = np.asarray(self._sample(ch, i, "rotation", t, n.get("rotation", [0, 0, 0, 1])), float)
                if self.hold > 0:
                    h = np.asarray(self._sample(idle, i, "rotation", 0.0, r), float)
                    if np.dot(r, h) < 0:
                        h = -h
                    r = r * (1 - self.hold) + h * self.hold
                    r = r / np.linalg.norm(r)
                if self.arm_out and n["name"].startswith("UpperArm"):
                    # about the body's forward axis (+Z) as the parent's frame sees it
                    par = self.world_cache_parent(i, clip, t)
                    ax = np.linalg.inv(par[:3, :3]) @ np.array([0.0, 0.0, 1.0])
                    ax /= np.linalg.norm(ax)
                    ang = math.radians(self.arm_out) * (1 if n["name"].endswith(".L") else -1)
                    qa = np.concatenate([ax * math.sin(ang / 2), [math.cos(ang / 2)]])
                    r = _qmul(qa, r)
                local.append(_trs(self._sample(ch, i, "translation", t, n.get("translation", [0, 0, 0])), r,
                                  self._sample(ch, i, "scale", t, n.get("scale", [1, 1, 1]))))
                continue
            trs = {"translation": n.get("translation", [0, 0, 0]), "rotation": n.get("rotation", [0, 0, 0, 1]),
                   "scale": n.get("scale", [1, 1, 1])}
            for path in trs:
                if (i, path) in ch:
                    ti, vo = ch[(i, path)]
                    if t <= ti[0]:
                        v = vo[0]
                    elif t >= ti[-1]:
                        v = vo[-1]
                    else:
                        k = int(np.searchsorted(ti, t)) - 1
                        f = (t - ti[k]) / max(ti[k + 1] - ti[k], 1e-9)
                        a, bb = vo[k], vo[k + 1]
                        if path == "rotation":
                            if np.dot(a, bb) < 0:
                                bb = -bb
                            v = a * (1 - f) + bb * f
                            v = v / np.linalg.norm(v)
                        else:
                            v = a * (1 - f) + bb * f
                    trs[path] = v
            local.append(_trs(trs["translation"], trs["rotation"], trs["scale"]))
        out = [None] * len(self.nodes)

        def get(i):
            if out[i] is None:
                out[i] = local[i] if i not in self.parent else get(self.parent[i]) @ local[i]
            return out[i]
        return {self.nodes[i]["name"]: get(i) for i in range(len(self.nodes))}


class Merged:
    """Several parts drawn as one inner surface (the body with trousers over it)."""

    def __init__(self, parts):
        self.parts = parts
        off = np.cumsum([0] + [len(p.V) for p in parts])
        self.V = np.concatenate([p.V for p in parts])
        self.I = np.concatenate([p.I + o for p, o in zip(parts, off)])
        self.bone = np.concatenate([p.top_bone() for p in parts])

    def pose(self, world):
        out = [p.pose(world) for p in self.parts]
        return np.concatenate([o[0] for o in out]), np.concatenate([o[1] for o in out])

    def top_bone(self):
        return self.bone


class Part:
    """One skinned mesh of a part GLB: rest positions and normals (glTF space), weights, triangles."""

    def __init__(self, path, want=None, morph=None):
        g, b = glb.read_glb(path)
        sk = g["skins"][0]
        self.joints = [g["nodes"][j]["name"] for j in sk["joints"]]
        self.ibm = LP.acc(g, b, sk["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)
        Vs, Ns, Js, Ws, Is = [], [], [], [], []
        n0 = 0
        for m in g["meshes"]:
            if want and m["name"] not in want:
                continue
            names = (m.get("extras") or {}).get("targetNames", [])
            for p in m["primitives"]:
                at = p["attributes"]
                if "JOINTS_0" not in at:
                    continue
                V = LP.acc(g, b, at["POSITION"])
                N = LP.acc(g, b, at["NORMAL"])
                if morph and morph in names:
                    tg = p["targets"][names.index(morph)]
                    V = V + LP.acc(g, b, tg["POSITION"])
                    if "NORMAL" in tg:
                        N = N + LP.acc(g, b, tg["NORMAL"])
                Vs.append(V)
                Ns.append(N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-12))
                Js.append(LP.acc(g, b, at["JOINTS_0"]).astype(int))
                Ws.append(LP.acc(g, b, at["WEIGHTS_0"]))
                Is.append(LP.acc(g, b, p["indices"]).astype(int).reshape(-1, 3) + n0)
                n0 += len(V)
        self.V, self.N = np.concatenate(Vs), np.concatenate(Ns)
        self.J, self.W, self.I = np.concatenate(Js), np.concatenate(Ws), np.concatenate(Is)
        self.W = self.W / np.maximum(self.W.sum(axis=1, keepdims=True), 1e-9)

    def open_hem(self, tol=0.004):
        """Drop the flat cap a skirt's solid is closed with at its hem, as the forge now does:
        the faces facing down that lie within `tol` of the part's lowest point. Returns how many."""
        n = tri_normals(self.V, self.I, self.N)
        low = (self.V[self.I, 1] < self.V[:, 1].min() + tol).all(axis=1) & (n[:, 1] < -0.5)
        self.I = self.I[~low]
        return int(low.sum())

    def set_weights(self, names, W):
        """Replace the skin with a full weight matrix over `names` (four influences kept)."""
        W = np.asarray(W, float)
        idx = np.argsort(-W, axis=1)[:, :4]
        w = np.take_along_axis(W, idx, axis=1)
        w /= np.maximum(w.sum(axis=1, keepdims=True), 1e-9)
        col = {n: k for k, n in enumerate(self.joints)}
        self.J = np.vectorize(lambda i: col[names[i]])(idx)
        self.W = w

    def full_weights(self, names):
        out = np.zeros((len(self.V), len(names)))
        col = {n: k for k, n in enumerate(names)}
        for k in range(self.J.shape[1]):
            jn = np.array([col.get(self.joints[j], -1) for j in range(len(self.joints))])[self.J[:, k]]
            ok = jn >= 0
            np.add.at(out, (np.nonzero(ok)[0], jn[ok]), self.W[ok, k])
        return out

    def pose(self, world):
        M = np.stack([world[n] @ self.ibm[k] for k, n in enumerate(self.joints)])
        B = np.einsum("nk,nkij->nij", self.W, M[self.J])
        Vh = np.concatenate([self.V, np.ones((len(self.V), 1))], axis=1)
        V = np.einsum("nij,nj->ni", B, Vh)[:, :3]
        N = np.einsum("nij,nj->ni", B[:, :3, :3], self.N)
        return V, N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-12)

    def top_bone(self):
        return np.array(self.joints)[self.J[np.arange(len(self.J)), self.W.argmax(axis=1)]]


# ---------------------------------------------------------------------------- geometry

def closest_on_tris(P, A, B, C):
    """Closest points to P[i] on triangles (A[i], B[i], C[i]) (Ericson, vectorised)."""
    ab, ac, ap = B - A, C - A, P - A
    d1, d2 = (ab * ap).sum(1), (ac * ap).sum(1)
    bp = P - B
    d3, d4 = (ab * bp).sum(1), (ac * bp).sum(1)
    cp = P - C
    d5, d6 = (ab * cp).sum(1), (ac * cp).sum(1)
    va = d3 * d6 - d5 * d4
    vb = d5 * d2 - d1 * d6
    vc = d1 * d4 - d3 * d2
    den = np.where(np.abs(va + vb + vc) < 1e-18, 1e-18, va + vb + vc)
    v = vb / den
    w = vc / den
    out = A + ab * v[:, None] + ac * w[:, None]
    # regions, from the last to take precedence to the first
    cond = (va <= 0) & ((d4 - d3) >= 0) & ((d5 - d6) >= 0)
    t = (d4 - d3) / np.where((d4 - d3) + (d5 - d6) == 0, 1e-18, (d4 - d3) + (d5 - d6))
    out = np.where(cond[:, None], B + (C - B) * t[:, None], out)
    cond = (vb <= 0) & (d2 >= 0) & (d6 <= 0)
    t = d2 / np.where(d2 - d6 == 0, 1e-18, d2 - d6)
    out = np.where(cond[:, None], A + ac * t[:, None], out)
    cond = (vc <= 0) & (d1 >= 0) & (d3 <= 0)
    t = d1 / np.where(d1 - d3 == 0, 1e-18, d1 - d3)
    out = np.where(cond[:, None], A + ab * t[:, None], out)
    out = np.where(((d6 >= 0) & (d5 <= d6))[:, None], C, out)
    out = np.where(((d3 >= 0) & (d4 <= d3))[:, None], B, out)
    out = np.where(((d1 <= 0) & (d2 <= 0))[:, None], A, out)
    return out


def nearest(P, V, I, k=16):
    """For each point, the nearest point on the mesh (V, I), its triangle, and that triangle's normal."""
    A, B, C = V[I[:, 0]], V[I[:, 1]], V[I[:, 2]]
    tree = cKDTree((A + B + C) / 3.0)
    _, cand = tree.query(P, k=min(k, len(I)))
    best_d = np.full(len(P), np.inf)
    best_q = np.zeros_like(P)
    best_t = np.zeros(len(P), int)
    for j in range(cand.shape[1]):
        ti = cand[:, j]
        q = closest_on_tris(P, A[ti], B[ti], C[ti])
        d = np.linalg.norm(P - q, axis=1)
        better = d < best_d
        best_d[better], best_q[better], best_t[better] = d[better], q[better], ti[better]
    return best_q, best_t, best_d


def tri_normals(V, I, VN):
    """Face normals, turned to agree with the exported vertex normals (the exporter's outward)."""
    A, B, C = V[I[:, 0]], V[I[:, 1]], V[I[:, 2]]
    n = np.cross(B - A, C - A)
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
    vn = VN[I].sum(axis=1)
    return np.where(((n * vn).sum(1) < 0)[:, None], -n, n)


def boundary_distance(q, tri, V, I):
    """How far each point q (on triangle tri) is from the mesh's open edges on that triangle
    (inf when the triangle has none): a hem, a cuff, a neckline, an armhole."""
    E = np.sort(np.stack([I[:, [0, 1]], I[:, [1, 2]], I[:, [2, 0]]], axis=1), axis=2)   # (t, 3, 2)
    flat = E.reshape(-1, 2)
    _, inv, cnt = np.unique(flat, axis=0, return_inverse=True, return_counts=True)
    open_ = (cnt[inv.ravel()] == 1).reshape(-1, 3)
    out = np.full(len(q), np.inf)
    for k in range(3):
        sel = open_[tri, k]
        if not sel.any():
            continue
        a = V[E[tri[sel], k, 0]]
        b = V[E[tri[sel], k, 1]]
        ab = b - a
        t = np.clip(((q[sel] - a) * ab).sum(1) / np.maximum((ab * ab).sum(1), 1e-12), 0, 1)
        d = np.linalg.norm(q[sel] - (a + t[:, None] * ab), axis=1)
        out[sel] = np.minimum(out[sel], d)
    return out


# ---------------------------------------------------------------------------- the check

def part_path(name):
    for kind in ("clothing", "hair", "beards", "attachments"):
        p = CHARS / kind / name / (name + ".glb")
        if p.exists():
            return p
    raise SystemExit("no part " + name)


def measure(rig, body, part, clip, steps, tol, cover=0.06, edge=0.001, see=True, only=None, cover_pose=None):
    """`cover_pose` (clip, t) is the pose in which a vertex under the cloth counts as covered: the
    bind pose by default, the Idle for a part modelled round the Idle's hanging arms (a cloak)."""
    rest = rig.world(*cover_pose) if cover_pose else rig.world(None)
    BV0, _ = body.pose(rest)
    GV0, GN0 = part.pose(rest)
    q, t, d = nearest(BV0, GV0, part.I)
    s = ((BV0 - q) * tri_normals(GV0, part.I, GN0)[t]).sum(1)
    inner = boundary_distance(q, t, GV0, part.I) > edge
    covered = inner & (d < cover) & (s < 0)
    if only:
        covered &= np.array([any(b.startswith(o) for o in only) for b in body.top_bone()])
    rest_through = inner & (d < cover) & (s > tol)
    length = rig.clips[clip][1] if clip else 0.0
    samples = []
    times = [0.0] if not clip else [length * i / steps for i in range(steps)]
    idx = np.nonzero(covered)[0]
    for tt in times:
        W = rig.world(clip, tt)
        BV, _ = body.pose(W)
        GV, GN = part.pose(W)
        q, tri, _ = nearest(BV[idx], GV, part.I)
        s = ((BV[idx] - q) * tri_normals(GV, part.I, GN)[tri]).sum(1)
        on_edge = boundary_distance(q, tri, GV, part.I) <= edge
        hit = (~on_edge) & (s > tol)
        if hit.any() and see:
            vis = visible(gl_to_forge(BV[idx[hit]]), [(gl_to_forge(BV), body.I, gl_to_forge(BV0)),
                                                      (gl_to_forge(GV), part.I, gl_to_forge(GV0))])
            h = np.nonzero(hit)[0]
            hit[h[~vis]] = False
        through = idx[hit]
        depth = float(s[hit].max()) if hit.any() else 0.0
        samples.append(dict(t=tt, through=through, depth=depth, out=int(on_edge.sum()), BV=BV, GV=GV))
    return covered, rest_through, samples


_SPLAT = {}


def _splat_samples(I, V0, key, area=8e-6):
    """Fixed barycentric samples over each triangle, about one per `area` m^2 of it at rest."""
    if key not in _SPLAT:
        A, B, C = V0[I[:, 0]], V0[I[:, 1]], V0[I[:, 2]]
        ar = 0.5 * np.linalg.norm(np.cross(B - A, C - A), axis=1)
        n = np.maximum(1, np.ceil(ar / area)).astype(int)
        tri = np.repeat(np.arange(len(I)), n)
        rng = np.random.default_rng(7)
        u, v = rng.random(len(tri)), rng.random(len(tri))
        flip = u + v > 1
        u[flip], v[flip] = 1 - u[flip], 1 - v[flip]
        bary = np.stack([1 - u - v, u, v], axis=1)
        # the corners too, so a thin sliver is never missed
        tri = np.concatenate([tri, np.repeat(np.arange(len(I)), 3)])
        bary = np.concatenate([bary, np.tile(np.eye(3), (len(I), 1))])
        _SPLAT[key] = (I[tri], bary)
    return _SPLAT[key]


def visible(points, meshes, views=(0, 90, 180, 270), scale=260.0, eps=0.008):
    """Which points (forge frame) are drawn, not hidden, from any of the views. Each view's depth
    buffer is splatted from points sampled densely over the meshes ((V, I, V at rest) in the forge
    frame) and read round the point's pixel."""
    clouds = []
    for V, I, V0 in meshes:
        corners, bary = _splat_samples(I, V0, (id(I), len(I)))
        clouds.append(bary[:, 0:1] * V[corners[:, 0]] + bary[:, 1:2] * V[corners[:, 1]]
                      + bary[:, 2:3] * V[corners[:, 2]])
    cloud = np.concatenate(clouds)
    Ww, Hh, cz = 520, 760, 0.95
    seen = np.zeros(len(points), bool)
    for view in views:
        a = math.radians(view)
        R = np.array([[math.cos(a), -math.sin(a), 0], [math.sin(a), math.cos(a), 0], [0, 0, 1]])
        zb = np.full((Hh, Ww), -1e9)
        Q = cloud @ R.T
        sx = np.clip((Q[:, 0] * scale + Ww / 2).astype(int), 0, Ww - 1)
        sy = np.clip(((cz - Q[:, 2]) * scale + Hh / 2).astype(int), 0, Hh - 1)
        np.maximum.at(zb, (sy, sx), -Q[:, 1])
        # close the splat's pinholes: a pixel no sample landed in takes its neighbours' nearest
        hole = zb < -1e8
        if hole.any():
            nb = np.max(np.stack([np.roll(zb, (dy, dx), (0, 1)) for dy in (-1, 0, 1) for dx in (-1, 0, 1)]), axis=0)
            zb = np.where(hole, nb, zb)
        Q = points @ R.T
        px = (Q[:, 0] * scale + Ww / 2).astype(int)
        py = ((cz - Q[:, 2]) * scale + Hh / 2).astype(int)
        ok = (px >= 0) & (px < Ww) & (py >= 0) & (py < Hh)
        px, py = np.clip(px, 0, Ww - 1), np.clip(py, 0, Hh - 1)
        seen |= ok & (-Q[:, 1] >= zb[py, px] - eps)
    return seen


def gl_to_forge(V):
    return np.stack([V[:, 0], -V[:, 2], V[:, 1]], axis=1)


def draw(path, body, part, sample, views=(0, 90, 180, 270)):
    red = np.zeros(len(body.V), bool)
    red[sample["through"]] = True
    col = np.where(red[body.I].any(axis=1)[:, None], np.array([0.95, 0.15, 0.1]), np.array([0.80, 0.66, 0.54]))
    meshes = [(gl_to_forge(sample["BV"]), body.I, col),
              (gl_to_forge(sample["GV"]), part.I, np.array([0.45, 0.55, 0.72]))]
    from PIL import Image
    img = np.concatenate([LP.raster(meshes, v, size=(300, 620), centre_z=0.95, scale=290.0) for v in views], axis=1)
    Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).save(path)


def reweight(part, body, rule):
    """Skin the part again as the forge would, in numpy: the body's weights by nearest vertex,
    smoothed, then `rule` -- "" for none, or "<cloth function>[:key=value,...]" called with the
    default skeleton and its keywords, returning a weight_adjust (V forge frame, W) -> W."""
    from forge.lib import rig as R, cloth, body as bodylib
    names = list(R.DEFORM_NAMES)
    bW = body.full_weights(names)
    V = gl_to_forge(part.V)
    W = bodylib.nearest_weights(V, gl_to_forge(body.V), bW, 4)
    W = bodylib.smooth_weights(W, part.I, iters=2, factor=0.4)
    W = bodylib.limit_influences(W)
    if rule:
        fn, _, kw = rule.partition(":")
        kwargs = {k: float(v) for k, v in (x.split("=") for x in kw.split(",") if x)}
        W = getattr(cloth, fn)(R.Skeleton(R.Proportions()), **kwargs)(V, W)
    part.set_weights(names, W)


def reweight_cloak(part, rule):
    """Weight a cloak (a part modelled round the Idle's hanging arms, `rebind`) again by a cloth
    weight_fn: back to where it was modelled, weighted, and rebound. `rule` is
    "<cloth fn>[:key=value,...]", called with the default skeleton and its keywords."""
    from forge.lib import rig as R, cloth
    import cloakreweight as CR
    names = list(R.DEFORM_NAMES)
    skel = R.Skeleton(R.Proportions())
    V = gl_to_forge(part.V)
    Vm = CR.modelled(V, part.full_weights(names))
    fn, _, kw = rule.partition(":")
    kwargs = {}
    for x in (y for y in kw.split(",") if y):
        k, v = x.split("=")
        kwargs[k] = v in ("1", "true", "True") if k in ("hooded", "hang") else float(v)
    W = getattr(cloth, fn)(skel, **kwargs)(Vm)
    W = W / np.maximum(W.sum(axis=1, keepdims=True), 1e-9)
    Vr = cloth.rebind_from_idle(skel, Vm, W)
    part.V = np.stack([Vr[:, 0], Vr[:, 2], -Vr[:, 1]], axis=1)
    part.set_weights(names, W)


def main():
    args = dict(a[2:].split("=", 1) for a in sys.argv[1:] if a.startswith("--") and "=" in a)
    clips = args.get("clips", ",".join(GAITS)).split(",")
    steps = int(args.get("steps", 12))
    tol = float(args.get("tol", 0.002))
    variant = args.get("body", "")
    rig = Rig(args.get("rig", RIG))
    rig.hold = float(args.get("hold", 0.0))
    rig.arm_out = float(args.get("arm-out", 0.0))
    body = Part(CHARS / "bodies" / variant / (variant + ".glb"), want={"Body"}) if variant else Part(args.get("rig", RIG), want={"Body"})
    skin_src = body
    if args.get("under"):
        body = Merged([body] + [Part(part_path(u), morph=variant or None) for u in args["under"].split(",")])
    see = "--novis" not in sys.argv
    cover_pose = None
    if args.get("cover"):
        c, _, t = args["cover"].partition("@")
        cover_pose = (c, float(t or 0))
    rule = args.get("reweight")
    if args.get("parts"):
        parts = args["parts"].split(",")
    else:
        parts = sorted(p.name for p in (CHARS / "clothing").iterdir() if (p / (p.name + ".glb")).exists()
                       and not p.name.endswith("_child"))
    png = args.get("png")
    if png:
        os.makedirs(png, exist_ok=True)
    bone_of = body.top_bone()
    print("body %s, tol %.1f mm, %d samples a clip" % (variant or "default", tol * 1000, steps))
    for name in parts:
        part = Part(part_path(name), morph=variant or None)
        if "--open-hem" in sys.argv:
            print("  %s: %d cap faces dropped" % (name, part.open_hem()))
        if rule is not None:
            reweight(part, skin_src, rule)
        if args.get("reweight-cloak"):
            reweight_cloak(part, args["reweight-cloak"])
        worst_all = None
        lines = []
        for clip in clips:
            if clip not in rig.clips:
                continue
            covered, rest_through, samples = measure(rig, body, part, clip, steps, tol, see=see,
                                                     only=args["bones"].split(",") if args.get("bones") else None,
                                                     cover_pose=cover_pose)
            w = max(samples, key=lambda s: (len(s["through"]), s["depth"]))
            bones = {}
            for b in bone_of[w["through"]]:
                bones[b] = bones.get(b, 0) + 1
            bl = ", ".join("%s %d" % kv for kv in sorted(bones.items(), key=lambda kv: -kv[1])[:3])
            lines.append("  %-11s worst t=%.2f: %4d through, %5.1f mm deep  [%s]   samples with any: %d/%d"
                         % (clip, w["t"], len(w["through"]), w["depth"] * 1000, bl,
                            sum(1 for s in samples if len(s["through"])), len(samples)))
            if worst_all is None or len(w["through"]) > len(worst_all[1]["through"]):
                worst_all = (clip, w)
        print("%s: %d body vertices covered, %d through at rest" % (name, int(covered.sum()), int(rest_through.sum())))
        for ln in lines:
            print(ln)
        if png and worst_all and len(worst_all[1]["through"]):
            p = os.path.join(png, "%s_%s_%s%.2f.png" % (variant or "default", name, worst_all[0], worst_all[1]["t"]))
            draw(p, body, part, worst_all[1])
            print("  drew", p)
        sys.stdout.flush()


if __name__ == "__main__":
    main()
