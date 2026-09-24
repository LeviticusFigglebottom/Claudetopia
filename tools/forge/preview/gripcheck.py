"""The closed hand on the rig body, in numpy: the hand's vertices curled by `grip.grip_positions` round
the weapon socket's haft, drawn with the haft, from four sides round the hand, open above and closed below.

    python3 tools/forge/preview/gripcheck.py <out.png> [R|L] [--glb=<rig or body glb>] [--pose=Idle@0]
                                             [--views=0,60,120] [--big]

With --pose the hand is shown posed in that clip (skinned), otherwise in the rest pose."""
import math
import sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(HERE))
import numpy as np
from PIL import Image
from forge.lib import rig, grip, sdf
import lbspreview as LP


def cylinder(c, axis, r, half, n=24):
    axis = sdf._unit(axis)
    a = sdf._unit(np.cross(axis, [0.0, 0.0, 1.0]) if abs(axis[2]) < 0.9 else np.cross(axis, [1.0, 0.0, 0.0]))
    b = np.cross(axis, a)
    V, I = [], []
    for k in range(n):
        t = 2 * math.pi * k / n
        rim = a * math.cos(t) * r + b * math.sin(t) * r
        V.append(c - axis * half + rim)
        V.append(c + axis * half + rim)
    for k in range(n):
        i0, i1 = 2 * k, 2 * ((k + 1) % n)
        I += [[i0, i1, i0 + 1], [i1, i1 + 1, i0 + 1]]
    return np.array(V), np.array(I)


VIEWS = (0, 60, 120, 180, 240, 300)
SIZE, SCALE = 240, 1300.0


def main():
    global VIEWS, SIZE, SCALE
    out = sys.argv[1]
    side = "R"
    glb = str(ROOT / "game/assets/models/characters/humanoid_rig/humanoid_rig.glb")
    pose = None
    for a in sys.argv[2:]:
        if a in ("R", "L"):
            side = a
        elif a.startswith("--glb="):
            glb = a[6:]
        elif a.startswith("--pose="):
            pose = a[7:]
        elif a.startswith("--views="):
            VIEWS = tuple(float(v) for v in a[8:].split(","))
        elif a == "--big":
            SIZE, SCALE = 420, 2600.0
    skel = rig.Skeleton(rig.Proportions())
    meshes = LP.load(glb, "Body")
    name, V, J, Wt, I, names = meshes[0]
    Vg = grip.grip_positions(skel, 1.0, V, side)
    c, axis = grip.haft(skel, side)
    HV, HI = cylinder(c, axis, grip.HAFT_R * 0.96, 0.09)
    wr, d, fwd, up = grip.hand_frame(skel, side)
    centre = wr + d * 0.09
    rows = []
    for verts in (V, Vg):
        if pose:
            clip, t = pose.split("@")
            S = LP.pose_matrices(skel, clip, float(t))
            P = LP.skin(verts, J, Wt, names, S)
            hb = names.index("Hand." + side)
            M = S["Hand." + side]
            H = (np.concatenate([HV, np.ones((len(HV), 1))], axis=1) @ M.T)[:, :3]
            Pc = (np.concatenate([centre[None], [[1.0]]], axis=1) @ M.T)[0, :3]
        else:
            P, H, Pc = verts, HV, centre
        # the hand alone: the triangles within 14 cm of its middle, so the body and the other hand
        # do not stand in front of it
        keep = (np.linalg.norm(P[I] - Pc, axis=2) < 0.14).all(axis=1)
        panels = []
        for view in VIEWS:
            ms = [(P - np.array([Pc[0], Pc[1], 0.0]), I[keep], np.array([0.79, 0.64, 0.49])),
                  (H - np.array([Pc[0], Pc[1], 0.0]), HI, np.array([0.45, 0.30, 0.18]))]
            panels.append(LP.raster(ms, view, size=(SIZE, SIZE), centre_z=float(Pc[2]), scale=SCALE))
        rows.append(np.concatenate(panels, axis=1))
    img = np.concatenate(rows, axis=0)
    Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).save(out)
    moved = np.linalg.norm(Vg - V, axis=1)
    print("wrote", out, "vertices moved:", int((moved > 1e-5).sum()), "max move %.3f m" % moved.max())


if __name__ == "__main__":
    main()
