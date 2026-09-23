"""Candidate cloak weight rules for cloakreweight.py: variations of cloth._cloak_weights(hang=True)."""
import sys
from pathlib import Path
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(HERE))
import numpy as np
from forge.lib import rig, cloth, body as bodylib

_ss = cloth._ss
_s = cloth._s


def _near(V, sh, el, wr, s, ysq, reach, fade):
    """How near each point is to the hanging arm, with distance along y (ahead/behind) counted at `ysq` of
    itself: the cloth in front of and behind an arm is what it pushes when it swings."""
    Q = V * np.array([1.0, ysq, 1.0])
    k = np.array([1.0, ysq, 1.0])
    d_u, _ = cloth._near_segments(Q, sh * k, el * k)
    d_l, _ = cloth._near_segments(Q, el * k, wr * k)
    near = 1.0 - _ss((np.minimum(d_u, d_l) - reach * s) / (fade * s))
    fore = _ss((d_u - d_l) / (0.03 * s))
    return near, fore


def make(ysq=0.5, reach=0.075, fade=0.05, share=0.85, below=0.0, back=0.0, back_from=0.0, centre=0.08):
    """`back`: the share of the thigh the back panels take below `back_from` m under the hips, blended
    from one thigh to the other across `centre` m either side of the centre line."""
    def fn(skel, V, hooded):
        bones = list(rig.DEFORM_NAMES)
        B = {b: i for i, b in enumerate(bones)}
        s = _s(skel)
        L = bodylib.head_landmarks(skel)
        J = skel.J
        neck_z, chest_z = float(J["Neck"][2]), float(J["Chest"][2])
        spine_z, hips_z = float(J["Spine"][2]), float(J["Hips"][2])
        arms = {side: cloth.hanging_arm(skel, side) for side in ("L", "R")}
        W = np.zeros((len(V), len(bones)))
        x, y, z = V[:, 0], V[:, 1], V[:, 2]
        ax = np.abs(x)
        w_head = _ss((z - (L["chin_z"] - 0.010 * s)) / (0.050 * s)) if hooded else np.zeros(len(V))
        w_neck = (_ss((z - (neck_z - 0.010 * s)) / (0.035 * s)) * (1.0 - w_head)
                  * np.clip((0.13 * s - ax) / (0.05 * s), 0.0, 1.0))
        rest = 1.0 - w_head - w_neck
        w_sh = rest * 0.40 * np.clip((ax - 0.09 * s) / (0.12 * s), 0.0, 1.0) * _ss((z - (chest_z - 0.06 * s)) / (0.12 * s))
        left = x >= 0
        w_ua, w_la = np.zeros(len(V)), np.zeros(len(V))
        for side, m in (("L", left), ("R", ~left)):
            sh, el, wr = arms[side]
            # the arm carried on past the wrist, so the cloth that hangs below the hand goes with it too
            wr2 = wr + (wr - el) * below
            near, fore = _near(V[m], sh, el, wr2, s, ysq, reach, fade)
            sh_ = share * near * (rest[m] - w_sh[m])
            w_ua[m] = sh_ * (1.0 - fore)
            w_la[m] = sh_ * fore
        rest = rest - w_sh - w_ua - w_la
        w_ch = rest * _ss((z - spine_z) / (chest_z - spine_z))
        w_hip = rest * _ss((spine_z - z) / (spine_z - hips_z))
        w_sp = rest - w_ch - w_hip
        w_leg = w_hip * 0.45 * _ss((hips_z - 0.10 * s - z) / (0.25 * s)) * np.clip(-y / (0.10 * s), 0.0, 1.0)
        w_back = w_hip * back * _ss((hips_z - back_from * s - z) / (0.25 * s)) * np.clip(y / (0.10 * s), 0.0, 1.0)
        to_left = _ss((x / (centre * s) + 1.0) * 0.5)
        w_hip = w_hip - w_leg - w_back
        for side, m in (("L", left), ("R", ~left)):
            W[m, B["Shoulder." + side]] = w_sh[m]
            W[m, B["UpperArm." + side]] = w_ua[m]
            W[m, B["LowerArm." + side]] = w_la[m]
            W[m, B["UpperLeg." + side]] = w_leg[m]
        W[:, B["UpperLeg.L"]] += w_back * to_left
        W[:, B["UpperLeg.R"]] += w_back * (1.0 - to_left)
        W[:, B["Head"]] = w_head
        W[:, B["Neck"]] = w_neck
        W[:, B["Chest"]] = w_ch
        W[:, B["Spine"]] = w_sp
        W[:, B["Hips"]] = w_hip
        return W
    return fn


iso = make(ysq=1.0)
aniso = make(ysq=0.5)
aniso2 = make(ysq=0.4, reach=0.09, fade=0.06)
aniso3 = make(ysq=0.4, reach=0.09, fade=0.06, share=0.95)
aniso4 = make(ysq=0.4, reach=0.09, fade=0.06, share=0.95, below=0.3)
legs1 = make(ysq=0.4, reach=0.09, fade=0.06, share=0.95, back=0.35, back_from=0.0)
legs2 = make(ysq=0.4, reach=0.09, fade=0.06, share=0.95, back=0.50, back_from=0.05)
