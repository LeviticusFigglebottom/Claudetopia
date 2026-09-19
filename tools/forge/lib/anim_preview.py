"""Stick-figure strips for animation review without Blender or Godot (PIL only).

`render_strip(skel, builder_or_baked, out_png, times=None, views=("front","side","iso"))`
draws the skeleton at several times, one column per time, one row per view.  Left-side
bones are blue, right-side red, axial bones black, the weapon socket's +Y (blade) is
drawn as a brown line so swings can be read.
"""
from __future__ import annotations

import math
from typing import Dict, List, Optional, Sequence, Tuple

import numpy as np
from PIL import Image, ImageDraw

from . import rig
from .anim import BakedClip, ClipBuilder
from .rig import Skeleton

VIEWS = {
    # name: (right vector, up vector) for orthographic projection of Blender-space points
    "front": (np.array([-1.0, 0, 0]), np.array([0, 0, 1.0])),        # camera at -Y looking +Y: character left appears on the right
    "side": (np.array([0, -1.0, 0]), np.array([0, 0, 1.0])),          # camera at +X (character's left side); forward is to the right
    "iso": (rig._unit(np.array([-1.0, -0.6, 0])), rig._unit(np.array([-0.35, 0.2, 1.0]))),
    "top": (np.array([-1.0, 0, 0]), np.array([0, -1.0, 0])),
}


def _colour(name: str) -> Tuple[int, int, int]:
    if name.endswith(".L"):
        return (40, 90, 220)
    if name.endswith(".R"):
        return (220, 60, 50)
    if name.startswith("Socket"):
        return (150, 100, 40)
    return (20, 20, 20)


def local_pose_at(skel: Skeleton, clip, t: float) -> Dict[str, Tuple[np.ndarray, np.ndarray]]:
    if isinstance(clip, ClipBuilder):
        return clip.local_pose(t)
    bc: BakedClip = clip
    i = int(round(t * bc.fps))
    i = max(0, min(bc.frames - 1, i))
    out = {}
    for b in bc.bones:
        out[b] = (rig.quat_to_mat(bc.quats[b][i]), bc.hips_pos[i] if b == "Hips" else None)
    return out


def world_points(skel: Skeleton, local) -> Dict[str, Tuple[np.ndarray, np.ndarray]]:
    W = skel.fk(local)
    pts = {}
    for n in skel.order:
        pts[n] = (skel.joint_world(W, n), skel.tail_world(W, n))
    return pts


def draw_pose(draw: ImageDraw.ImageDraw, skel: Skeleton, local, view: str, ox: int, oy: int,
              scale: float, height_px: int, blade_len: float = 0.8, label: str = "") -> None:
    right, up = VIEWS[view]
    pts = world_points(skel, local)

    def proj(p):
        return (ox + float(np.dot(p, right)) * scale, oy + height_px - float(np.dot(p, up)) * scale)

    # ground line
    g0, g1 = proj(np.array([-0.6, 0, 0])), proj(np.array([0.6, 0, 0]))
    if view != "top":
        draw.line([g0, g1], fill=(120, 160, 120), width=1)
    # draw far side first for a bit of depth: sort by depth
    depth_axis = np.cross(right, up)
    order = sorted(skel.order, key=lambda n: -float(np.dot(pts[n][0], depth_axis)))
    for n in order:
        h, t = pts[n]
        if n.startswith("Socket"):
            if n == "Socket.WeaponR":
                d = (t - h) / max(np.linalg.norm(t - h), 1e-9)
                draw.line([proj(h), proj(h + d * blade_len)], fill=(150, 100, 40), width=3)
            continue
        if n == "Root":
            continue
        w = 5 if n in ("Hips", "Spine", "Chest") else (4 if "Leg" in n or "Arm" in n else 3)
        draw.line([proj(h), proj(t)], fill=_colour(n), width=w)
        if n == "Head":
            c = proj((h + t) / 2)
            r = np.linalg.norm(t - h) * scale * 0.45
            draw.ellipse([c[0] - r, c[1] - r, c[0] + r, c[1] + r], outline=_colour(n), width=2)
            # nose: front direction
            W = skel.fk(local)
            f = W["Head"][:3, :3] @ np.array([0, 0, 1.0])
            nose = proj((h + t) / 2 + f * 0.12)
            draw.line([c, nose], fill=(20, 20, 20), width=2)
        if n.startswith("Foot") or n.startswith("Toe"):
            pass
    # joints
    for n in ("UpperLeg.L", "UpperLeg.R", "LowerLeg.L", "LowerLeg.R", "LowerArm.L", "LowerArm.R", "Hand.L", "Hand.R", "Foot.L", "Foot.R"):
        c = proj(pts[n][0])
        draw.ellipse([c[0] - 3, c[1] - 3, c[0] + 3, c[1] + 3], fill=_colour(n))
    if label:
        draw.text((ox + 4, oy + 4), label, fill=(0, 0, 0))


def render_strip(skel: Skeleton, clip, out_png: str, times: Optional[Sequence[float]] = None,
                 views: Sequence[str] = ("front", "side", "iso"), cell: Tuple[int, int] = (150, 240),
                 blade_len: float = 0.8) -> str:
    length = clip.length
    if times is None:
        n = 8
        times = [length * i / (n - 1) for i in range(n)] if not clip.loop else [length * i / n for i in range(n)]
    cw, ch = cell
    img = Image.new("RGB", (cw * len(times), ch * len(views) + 16), (245, 242, 235))
    draw = ImageDraw.Draw(img)
    scale = (ch - 30) / 2.1
    for col, t in enumerate(times):
        local = local_pose_at(skel, clip, t)
        for row, v in enumerate(views):
            ox, oy = col * cw + cw // 2 if v != "top" else col * cw + cw // 2, row * ch + 16
            if v == "top":
                oy += ch // 2
            draw_pose(draw, skel, local, v, ox, oy, scale, ch - 24 if v != "top" else ch // 2, blade_len,
                      label=f"{v} t={t:.2f}" if row == 0 or True else "")
        # event markers
        names = [n for (te, n) in getattr(clip, "events", []) if abs(te - t) <= length / (2 * max(len(times), 1))]
        if names:
            draw.text((col * cw + 4, 2), ",".join(names), fill=(160, 30, 30))
    draw.text((4, ch * len(views) + 2), f"{clip.name}  len={length:.2f}s loop={clip.loop}", fill=(0, 0, 0))
    img.save(out_png)
    return out_png


def foot_slide_report(skel: Skeleton, clip: ClipBuilder, speed: float, direction=(0.0, 1.0), samples: int = 40) -> Dict[str, float]:
    """For a gait clip: measure max deviation of each planted ankle from ideal constant
    backward motion (m).  0 = perfect foot lock."""
    d = np.array(direction, float)
    d /= np.linalg.norm(d)
    travel = rig.LEFT * d[0] + rig.FWD * d[1]
    out = {}
    for side in ("L", "R"):
        worst = 0.0
        prev = None
        for i in range(samples):
            t = clip.length * i / samples
            fs = clip.feet.state(side, t)
            local = clip.local_pose(t)
            W = skel.fk(local)
            ankle = skel.joint_world(W, f"Foot.{side}")
            if fs.planted and prev is not None and prev[1]:
                dt = t - prev[0]
                expected = prev[2] - travel * speed * dt
                worst = max(worst, float(np.linalg.norm(ankle - expected)))
            prev = (t, fs.planted, ankle)
        out[side] = worst
    return out
