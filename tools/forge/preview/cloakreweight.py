"""Try a cloak weight rule on a built cloak without Blender: take the glb's rest vertices back to where
they were modelled (the inverse of rebind_from_idle), weight them by the candidate rule, rebind, and pose
them with the rig body.

    python3 cloakreweight.py <out.png> <part> <rule> <clip@t>[,<clip@t>...] [--views=0,90,180] [--hold=0.5]

rule: "built" (the glb's own weights) or a name in RULES below or in cloakrules.py.
--hold takes that share of the clip's arm pose back to the arms' hang in the Idle (the upper arms and
forearms), as a modifier holding the arms in under a cloak would."""
import sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(HERE))
import numpy as np
from PIL import Image
from forge.lib import rig, cloth, body as bodylib
import lbspreview as LP

M = str(ROOT / "game/assets/models/characters") + "/"
names = list(rig.DEFORM_NAMES)
skel = rig.Skeleton(rig.Proportions())


def dense(J, Wt, bones):
    full = np.zeros((len(J), len(names) + 1))
    for k in range(J.shape[1]):
        cols = np.array([names.index(bones[j]) if bones[j] in names else len(names) for j in J[:, k].astype(int)])
        np.add.at(full, (np.arange(len(J)), cols), Wt[:, k])
    assert full[:, -1].max() < 1e-3, full[:, -1].max()
    return full[:, :-1]


def modelled(V, W):
    """Undo rebind_from_idle: V_model = inv(body blend) . (all-weights blend) . V_rest."""
    Mi = cloth._idle_matrices(skel)
    Vh = np.concatenate([V, np.ones((len(V), 1))], axis=1)
    blend = np.zeros((len(V), 4, 4))
    body = np.zeros((len(V), 4, 4))
    bw = np.zeros(len(V))
    for i, b in enumerate(names):
        if b not in Mi:
            continue
        w = W[:, i]
        blend += w[:, None, None] * Mi[b][None]
        if b not in cloth.ARM_BONES:
            body += w[:, None, None] * Mi[b][None]
            bw += w
    free = bw < 1e-6
    body[free] = Mi["Chest"]
    body[~free] /= bw[~free, None, None]
    idle = np.einsum("nij,nj->ni", blend, Vh)
    return np.linalg.solve(body, idle[:, :, None])[:, :3, 0]


def held_pose_matrices(clip, t, hold):
    """LP.pose_matrices with the arms taken `hold` of the way back to how they hang in the Idle."""
    if hold <= 0.0:
        return LP.pose_matrices(skel, clip, t)
    from forge.lib import anim, anim_clips
    clips = dict(anim_clips.locomotion_clips(skel))
    local = clips[clip].local_pose(t)
    cb = anim.ClipBuilder(skel, "hang", 1.0, loop=True, grounded=False)
    cb.key(0.0, anim_clips.RELAXED)
    hang = cb.local_pose(0.0)
    for b in ("UpperArm.L", "UpperArm.R", "LowerArm.L", "LowerArm.R"):
        R, tr = local[b]
        q = rig.quat_slerp(rig.mat_to_quat(R), rig.mat_to_quat(hang[b][0]), hold)
        local[b] = (rig.quat_to_mat(q), tr)
    W = skel.fk(local)
    return {b: W[b] @ np.linalg.inv(skel.bones[b].rest) for b in skel.bones if b in W}


def to_sparse(W):
    W = bodylib.limit_influences(W)
    idx = np.argsort(-W, axis=1)[:, :4]
    w = np.take_along_axis(W, idx, axis=1)
    w /= np.maximum(w.sum(axis=1, keepdims=True), 1e-9)
    return idx, w


RULES = {}


def rule(fn):
    RULES[fn.__name__] = fn
    return fn


@rule
def current(skel, V, hooded):
    return cloth._cloak_weights(skel, hooded, hang=True)(V)


def main():
    out, part, rname, poses = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4].split(",")
    views = [0, 90, 180]
    hold = 0.0
    for a in sys.argv[5:]:
        if a.startswith("--views="):
            views = [float(v) for v in a[8:].split(",")]
        elif a.startswith("--hold="):
            hold = float(a[7:])
    hooded = "hood" in part
    meshes_in = LP.load(M + "clothing/%s/%s.glb" % (part, part))
    body = LP.load(M + "humanoid_rig/humanoid_rig.glb", "Body")
    rows = []
    for pose in poses:
        clip, t = pose.split("@")
        S = held_pose_matrices(clip, float(t), hold)
        meshes = []
        for name, V, J, Wt, I, bones in body:
            meshes.append((LP.skin(V, J, Wt, bones, S), I, np.array([0.79, 0.64, 0.49])))
        for name, V, J, Wt, I, bones in meshes_in:
            if rname == "built":
                P = LP.skin(V, J, Wt, bones, S)
            else:
                Wd = dense(J, Wt, bones)
                Vm = modelled(V, Wd)
                import cloakrules
                fn = RULES.get(rname) or getattr(cloakrules, rname)
                Wn = fn(skel, Vm, hooded)
                Vr = cloth.rebind_from_idle(skel, Vm, bodylib.limit_influences(Wn))
                idx, w = to_sparse(Wn)
                P = LP.skin(Vr, idx, w, names, S)
            meshes.append((P, I, np.array([0.35, 0.43, 0.55])))
        rows.append(np.concatenate([LP.raster(meshes, v) for v in views], axis=1))
    img = np.concatenate(rows, axis=0)
    Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).save(out)
    print("wrote", out)


if __name__ == "__main__":
    main()
