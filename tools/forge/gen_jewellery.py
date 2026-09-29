#!/usr/bin/env python3
"""Forge the jewellery (triage 48): small rigid pieces of metal, bone and glass, one GLB each, without
Blender.

    python3 tools/forge/gen_jewellery.py            # every piece
    python3 tools/forge/gen_jewellery.py --only torc,hoop

Each piece is one mesh in its own frame (glTF: +Y up, +Z out of the body at the place it is worn,
metres), untextured: the engine lays it on the body at a landmark and colours it by what the record
says it is made of (game/actors/shared/adornment.gd, assets/shaders/jewellery.gdshader). COLOR_0's red
says which part of a piece is which: 1 the piece's own stuff, 0.5 an accent (a glass bead, a stone),
0 a cord (leather). Pieces worn round something are made at radius 1 and fitted to it in the engine
(`fit` in the meta): a torc to the neck, a ring to the finger, a bracelet to the wrist, a circlet to
the head, a braid's ring to the braid, a bead strung on a necklace.

Frames:
    stud, nose_stud     a dome on the skin at the origin facing +Z, its post into -Z
    hoop                a ring hanging in the XY plane from the origin (the piercing)
    drop                a small ring at the origin and a bead hanging below it
    nose_ring, lip_ring a ring in the YZ plane through the origin, round the edge it pierces
    brooch, pendant     a flat piece facing +Z (the pendant's bail at the origin)
    torc, ring, bracelet, circlet, braid_ring   round the Y axis at radius 1 (`fit`)
    bead                a bead at radius 1 round the origin, strung along X (`fit`)
    hair_pin            a pin from its head at the origin into the hair along -Z
"""
from __future__ import annotations

import argparse
import json
import math
import os
import struct
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(os.path.dirname(HERE)), "game", "assets", "models", "characters", "jewellery")

MAIN, ACCENT, CORD = 1.0, 0.5, 0.0


class Mesh:
    def __init__(self):
        self.V, self.N, self.C, self.T = [], [], [], []

    def add(self, V, N, T, role: float) -> "Mesh":
        base = sum(len(v) for v in self.V)
        self.V.append(np.asarray(V, float))
        self.N.append(np.asarray(N, float))
        self.C.append(np.full((len(V), 4), [role, role, role, 1.0]))
        self.T.append(np.asarray(T, int) + base)
        return self

    def arrays(self):
        return np.concatenate(self.V), np.concatenate(self.N), np.concatenate(self.C), np.concatenate(self.T)


def _norm(v):
    n = np.linalg.norm(v, axis=-1, keepdims=True)
    return v / np.maximum(n, 1e-12)


def _grid(nu: int, nv: int, closed_u: bool = True, closed_v: bool = True):
    T = []
    cu = nu if closed_u else nu - 1
    cv = nv if closed_v else nv - 1
    for i in range(cu):
        for j in range(cv):
            a = i * nv + j
            b = ((i + 1) % nu) * nv + j
            c = ((i + 1) % nu) * nv + (j + 1) % nv
            d = i * nv + (j + 1) % nv
            T += [[a, b, c], [a, c, d]]
    return T


def torus(R: float, r: float, nu: int = 16, nv: int = 6, axis: str = "z", centre=(0, 0, 0),
          arc=(0.0, 2 * math.pi), squash: float = 1.0):
    """A ring of major radius R and tube radius r round `axis` (its plane perpendicular to it)."""
    closed = abs(arc[1] - arc[0] - 2 * math.pi) < 1e-6
    us = np.linspace(arc[0], arc[1], nu, endpoint=not closed)
    vs = np.linspace(0, 2 * math.pi, nv, endpoint=False)
    V, N = [], []
    for u in us:
        cu, su = math.cos(u), math.sin(u)
        for v in vs:
            cv, sv = math.cos(v), math.sin(v)
            n = np.array([cu * cv, su * cv, sv * squash])
            p = np.array([(R + r * cv) * cu, (R + r * cv) * su, r * sv * squash])
            V.append(p)
            N.append(n)
    V, N = np.array(V), _norm(np.array(N))
    # the ring is made round Z; turn it round the axis asked for
    if axis == "y":      # in the XZ plane: (x, y, z) -> (x, z, y), keeping the turn
        V, N = V[:, [0, 2, 1]] * [1, 1, -1], N[:, [0, 2, 1]] * [1, 1, -1]
    elif axis == "x":    # in the YZ plane
        V, N = V[:, [2, 0, 1]], N[:, [2, 0, 1]]
    return V + np.asarray(centre, float), N, _grid(len(us), nv, closed_u=closed)


def sphere(r: float, centre=(0, 0, 0), n: int = 8, scale=(1, 1, 1)):
    V, N = [], []
    for i in range(n + 1):
        th = math.pi * i / n
        for j in range(n):
            ph = 2 * math.pi * j / n
            d = np.array([math.sin(th) * math.cos(ph), math.cos(th), math.sin(th) * math.sin(ph)])
            V.append(d * r * np.asarray(scale))
            N.append(d / np.asarray(scale))
    T = []
    for i in range(n):
        for j in range(n):
            a, b = i * n + j, i * n + (j + 1) % n
            c, d = (i + 1) * n + (j + 1) % n, (i + 1) * n + j
            T += [[a, d, c], [a, c, b]]
    return np.array(V) + np.asarray(centre, float), _norm(np.array(N)), T


def cylinder(a, b, r: float, n: int = 6, caps: bool = True):
    a, b = np.asarray(a, float), np.asarray(b, float)
    ax = _norm(b - a)
    t = np.cross(ax, [0, 1, 0] if abs(ax[1]) < 0.9 else [1, 0, 0])
    t = _norm(t)
    s = np.cross(ax, t)
    V, N = [], []
    for end in (a, b):
        for k in range(n):
            ang = 2 * math.pi * k / n
            d = t * math.cos(ang) + s * math.sin(ang)
            V.append(end + d * r)
            N.append(d)
    T = []
    for k in range(n):
        k2 = (k + 1) % n
        T += [[k, n + k, n + k2], [k, n + k2, k2]]
    V, N = list(V), list(N)
    if caps:
        for end, sign, off in ((a, -1, 0), (b, 1, n)):
            c = len(V)
            V.append(end)
            N.append(ax * sign)
            for k in range(n):
                k2 = (k + 1) % n
                T.append([c, off + k2, off + k] if sign < 0 else [c, off + k, off + k2])
    return np.array(V), _norm(np.array(N)), T


def dome(r: float, h: float, n: int = 10, centre=(0, 0, 0)):
    """A low dome of radius r and height h facing +Z, its rim on z = 0."""
    V, N, T = [np.array([0, 0, h])], [np.array([0, 0, 1.0])], []
    rings = 3
    for i in range(1, rings + 1):
        f = i / rings
        z = h * (1 - f * f)
        for j in range(n):
            ang = 2 * math.pi * j / n
            V.append(np.array([r * f * math.cos(ang), r * f * math.sin(ang), z]))
            N.append(_norm(np.array([f * math.cos(ang) * h / r * 2, f * math.sin(ang) * h / r * 2, 1.0])))
    for j in range(n):
        T.append([0, 1 + j, 1 + (j + 1) % n])
    for i in range(rings - 1):
        for j in range(n):
            a, b = 1 + i * n + j, 1 + i * n + (j + 1) % n
            c, d = 1 + (i + 1) * n + (j + 1) % n, 1 + (i + 1) * n + j
            T += [[a, d, c], [a, c, b]]
    return np.array(V) + np.asarray(centre, float), np.array(N), T


def band(R: float, height: float, thick: float, n: int = 28):
    """A flat band round Y (a circlet's, a braid ring's): outer and inner walls and the two edges."""
    V, N, T = [], [], []
    for ring, (rad, y, nrm) in enumerate([(R + thick, height / 2, 1), (R + thick, -height / 2, 1),
                                          (R, -height / 2, -1), (R, height / 2, -1)]):
        for j in range(n):
            ang = 2 * math.pi * j / n
            d = np.array([math.cos(ang), 0, math.sin(ang)])
            V.append(d * rad + [0, y, 0])
            N.append(d * nrm)
    for k in range(4):
        k2 = (k + 1) % 4
        for j in range(n):
            j2 = (j + 1) % n
            a, b, c, d = k * n + j, k * n + j2, k2 * n + j2, k2 * n + j
            T += [[a, b, c], [a, c, d]]
    return np.array(V), np.array(N), T


# -- the pieces --------------------------------------------------------------------------------

def stud():
    m = Mesh()
    m.add(*dome(0.0022, 0.0012, 10), MAIN)
    m.add(*cylinder([0, 0, 0], [0, 0, -0.004], 0.0005, 5), MAIN)
    return m


def nose_stud():
    m = Mesh()
    m.add(*dome(0.0014, 0.0009, 8), MAIN)
    m.add(*cylinder([0, 0, 0], [0, 0, -0.003], 0.0004, 4), MAIN)
    return m


def hoop():
    return Mesh().add(*torus(0.0075, 0.0008, 22, 6, "z", (0, -0.0065, 0)), MAIN)


def drop():
    m = Mesh()
    m.add(*torus(0.0022, 0.0005, 10, 5, "z", (0, -0.0012, 0)), MAIN)
    m.add(*cylinder([0, -0.0034, 0], [0, -0.0072, 0], 0.00045, 4), MAIN)
    m.add(*sphere(0.0027, (0, -0.0098, 0), 8, (1, 1.25, 1)), ACCENT)
    return m


def nose_ring():
    return Mesh().add(*torus(0.0042, 0.00055, 16, 5, "x", (0, -0.0032, -0.0012)), MAIN)


def lip_ring():
    return Mesh().add(*torus(0.0042, 0.00055, 16, 5, "x", (0, -0.0022, -0.0014)), MAIN)


def brooch():
    m = Mesh()
    # a penannular ring, open at the foot, knobbed at its ends, and its pin across it
    gap = 0.55
    m.add(*torus(0.0105, 0.0014, 22, 6, "z", (0, 0, 0.0016), (-math.pi / 2 + gap / 2, 3 * math.pi / 2 - gap / 2)), MAIN)
    for s in (-1, 1):
        a = -math.pi / 2 + s * gap / 2
        m.add(*sphere(0.0021, (0.0105 * math.cos(a), 0.0105 * math.sin(a), 0.0016), 6), MAIN)
    m.add(*cylinder([-0.004, 0.015, 0.0034], [0.003, -0.016, 0.0034], 0.0007, 5), MAIN)
    m.add(*sphere(0.0022, (0, 0.0105, 0.003), 6), ACCENT)
    return m


def pendant():
    m = Mesh()
    m.add(*torus(0.0022, 0.0005, 10, 5, "x", (0, -0.0018, 0)), MAIN)
    V, N, T = cylinder([0, -0.012, -0.0008], [0, -0.012, 0.0008], 0.0085, 16, caps=True)
    # the disc: its axis is Z
    m.add(V, N, T, MAIN)
    m.add(*dome(0.0034, 0.0016, 10, (0, -0.012, 0.0008)), ACCENT)
    return m


def torc():
    m = Mesh()
    gap = 0.55   # radians open at the front (+Z)
    # made round Z and turned into XZ, where the ring's angle u lands at (cos u, 0, -sin u): the gap
    # at u = -pi/2 is at +Z, the front
    m.add(*torus(1.0, 0.075, 40, 8, "y", (0, 0, 0), (-math.pi / 2 + gap / 2, 3 * math.pi / 2 - gap / 2)), MAIN)
    for s in (-1, 1):
        a = -math.pi / 2 + s * gap / 2
        m.add(*sphere(0.13, (math.cos(a), 0.0, -math.sin(a)), 8), MAIN)
    return m


def ring():
    return Mesh().add(*torus(1.0, 0.16, 16, 6, "y"), MAIN)


def bracelet():
    return Mesh().add(*torus(1.0, 0.09, 26, 6, "y"), MAIN)


def circlet():
    m = Mesh()
    m.add(*band(1.0, 0.07, 0.02, 32), MAIN)
    m.add(*sphere(0.045, (0, 0, 1.03), 8), ACCENT)
    return m


def braid_ring():
    return Mesh().add(*band(1.0, 0.7, 0.14, 12), MAIN)


def bead():
    return Mesh().add(*sphere(1.0, (0, 0, 0), 6, (1.25, 1, 1)), MAIN)


def hair_pin():
    m = Mesh()
    m.add(*cylinder([0, 0, 0], [0, 0, -0.055], 0.0009, 5), MAIN)
    m.add(*sphere(0.0034, (0, 0, 0.001), 7), ACCENT)
    return m


PIECES = {
    "stud": (stud, None), "nose_stud": (nose_stud, None), "hoop": (hoop, None), "drop": (drop, None),
    "nose_ring": (nose_ring, None), "lip_ring": (lip_ring, None), "brooch": (brooch, None),
    "pendant": (pendant, None), "torc": (torc, "neck"), "ring": (ring, "finger"), "bracelet": (bracelet, "wrist"),
    "circlet": (circlet, "head"), "braid_ring": (braid_ring, "braid"), "bead": (bead, "strung"),
    "hair_pin": (hair_pin, None),
}


def write_glb(path: str, name: str, V, N, C, T) -> None:
    V = np.asarray(V, "<f4")
    N = np.asarray(N, "<f4")
    C = np.asarray(C, "<f4")
    I = np.asarray(T, "<u2").reshape(-1)
    blobs, views, accessors = [], [], []
    off = 0

    def add(data: bytes, target: int, count: int, kind: str, comp: int, bounds=None):
        nonlocal off
        pad = (-off) % 4
        if pad:
            blobs.append(b"\0" * pad)
            off += pad
        views.append({"buffer": 0, "byteOffset": off, "byteLength": len(data), "target": target})
        blobs.append(data)
        off += len(data)
        acc = {"bufferView": len(views) - 1, "componentType": comp, "count": count, "type": kind}
        if bounds is not None:
            acc["min"], acc["max"] = bounds
        accessors.append(acc)
        return len(accessors) - 1

    pos = add(V.tobytes(), 34962, len(V), "VEC3", 5126, ([float(x) for x in V.min(0)], [float(x) for x in V.max(0)]))
    nrm = add(N.tobytes(), 34962, len(N), "VEC3", 5126)
    col = add(C.tobytes(), 34962, len(C), "VEC4", 5126)
    idx = add(I.tobytes(), 34963, len(I), "SCALAR", 5123)
    gltf = {
        "asset": {"version": "2.0", "generator": "wickmere gen_jewellery"},
        "scene": 0, "scenes": [{"nodes": [0]}],
        "nodes": [{"name": name, "mesh": 0}],
        "meshes": [{"name": name, "primitives": [{"attributes": {"POSITION": pos, "NORMAL": nrm, "COLOR_0": col},
                                                  "indices": idx, "mode": 4}]}],
        "accessors": accessors, "bufferViews": views, "buffers": [{"byteLength": off}],
    }
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * ((-len(js)) % 4)
    binary = b"".join(blobs)
    binary += b"\0" * ((-len(binary)) % 4)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(binary)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(binary), 0x004E4942) + binary)


def build(name: str) -> dict:
    fn, fit = PIECES[name]
    V, N, C, T = fn().arrays()
    d = os.path.join(OUT, name)
    os.makedirs(d, exist_ok=True)
    write_glb(os.path.join(d, name + ".glb"), name, V, N, C, T)
    meta = {"name": name, "generator": "gen_jewellery", "kind": "jewellery", "fit": fit,
            "tris": len(T), "vertices": len(V),
            "bounds": {"min": [round(float(x), 5) for x in V.min(0)], "max": [round(float(x), 5) for x in V.max(0)]}}
    with open(os.path.join(d, name + ".meta.json"), "w") as f:
        json.dump(meta, f, indent=1, sort_keys=True)
    return meta


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", default="", help="comma-separated piece names (default: all)")
    args = ap.parse_args(argv)
    only = set(filter(None, args.only.split(",")))
    for name in PIECES:
        if only and name not in only:
            continue
        m = build(name)
        print("%-11s %4d tris %4d vertices  fit=%s" % (name, m["tris"], m["vertices"], m["fit"]), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
