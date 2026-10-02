"""The forged foes' paint: albedo, ORM and a height for the normal, texel by texel from the 3D point
at rest (lib/paint.py's way, as the horse's and the deer's coats are painted).

The look is the house's (README, "How a material is painterly"): big blocks of value laid in as a
painter would -- the back dark against the sky, the belly pale, the shadowed planes cool -- then the
pattern (a coat's lie, bark's plates, a hide's rings), wear on what stands out, dirt in the creases,
and only a low grain under it. The maps are plain PBR, so a model reads the same under Forward+
and Compatibility.

    painter(spec, field) -> (albedo(P, N), orm(P, N), height(P, N))
"""
from __future__ import annotations

from typing import Dict

import numpy as np

from . import paint, sdf
from . import beast_body as bb

C = lambda *v: np.array(v, float)  # noqa: E731

# Colours are sRGB, as the forge's other coats.
COATS: Dict[str, Dict[str, np.ndarray]] = {
    # the Vale's wolf: grey-gold, the saddle grizzled dark, cream under, a black tip to the tail
    "wolf": {"body": C(0.58, 0.50, 0.39), "saddle": C(0.30, 0.27, 0.24), "pale": C(0.86, 0.80, 0.68),
             "legs": C(0.66, 0.54, 0.38), "muzzle": C(0.66, 0.55, 0.40), "mask": C(0.42, 0.36, 0.30),
             "ear": C(0.40, 0.32, 0.24), "ear_in": C(0.86, 0.80, 0.70), "tip": C(0.10, 0.09, 0.08),
             "guard": C(0.08, 0.07, 0.06), "iris": C(0.78, 0.55, 0.16)},
    # the Skerrow wolf: white the year round, a grey breath of a saddle, cream on the legs
    "crag": {"body": C(0.86, 0.86, 0.84), "saddle": C(0.66, 0.67, 0.69), "pale": C(0.95, 0.94, 0.91),
             "legs": C(0.84, 0.80, 0.72), "muzzle": C(0.88, 0.86, 0.82), "mask": C(0.70, 0.70, 0.70),
             "ear": C(0.60, 0.60, 0.62), "ear_in": C(0.90, 0.86, 0.82), "tip": C(0.50, 0.50, 0.52),
             "guard": C(0.42, 0.43, 0.46), "iris": C(0.80, 0.70, 0.36)},
    # the thornhound: bark, cracked to the dark wood, lichen on the back, pale thorns black at the point
    "thorn": {"body": C(0.33, 0.26, 0.19), "saddle": C(0.24, 0.19, 0.14), "pale": C(0.40, 0.33, 0.24),
              "legs": C(0.30, 0.24, 0.18), "muzzle": C(0.36, 0.28, 0.20), "mask": C(0.20, 0.15, 0.11),
              "ear": C(0.26, 0.20, 0.15), "ear_in": C(0.42, 0.28, 0.22), "tip": C(0.18, 0.13, 0.09),
              "guard": C(0.10, 0.07, 0.05), "iris": C(0.92, 0.62, 0.14),
              "crack": C(0.09, 0.06, 0.045), "lichen": C(0.48, 0.52, 0.34), "thorn": C(0.70, 0.60, 0.42),
              "thorn_tip": C(0.14, 0.09, 0.06)},
    # the leech-hound: a slick dusk-purple hide, darker along the back, mottled pale under, ringed
    "leech": {"body": C(0.33, 0.27, 0.35), "saddle": C(0.17, 0.14, 0.19), "pale": C(0.58, 0.50, 0.48),
              "legs": C(0.28, 0.23, 0.30), "muzzle": C(0.36, 0.28, 0.34), "mask": C(0.20, 0.15, 0.20),
              "ear": C(0.22, 0.17, 0.23), "ear_in": C(0.55, 0.36, 0.40), "tip": C(0.14, 0.11, 0.15),
              "guard": C(0.12, 0.09, 0.12), "iris": C(0.86, 0.80, 0.42), "ring": C(0.12, 0.09, 0.13),
              "spot": C(0.62, 0.48, 0.30)},
}
FIXED = {"nose": C(0.06, 0.05, 0.05), "lips": C(0.07, 0.05, 0.05), "mouth": C(0.42, 0.14, 0.13),
         "teeth": C(0.88, 0.84, 0.72), "pupil": C(0.02, 0.015, 0.01), "nail": C(0.12, 0.10, 0.09),
         "pad": C(0.10, 0.09, 0.09), "mud": C(0.30, 0.25, 0.19)}


def painter(spec, field: sdf.SampledField):
    if spec.family == "canid":
        return canid_paint(spec, field)
    raise KeyError(spec.family)


def canid_paint(spec, field: sdf.SampledField):
    skel, st = spec.skel, spec.style
    s = bb._s(skel)
    pal = {**COATS[st.kind], **FIXED}
    n1 = paint.Noise(st.seed, 64)
    n2 = paint.Noise(st.seed + 7, 64)
    n3 = paint.Noise(st.seed + 19, 64)
    J = skel.J
    eyes = bb.eye_centres(skel, st)
    sleek = st.sleek > 0
    barky = st.bark > 0

    def flow(P):
        f = np.tile(np.array([0.0, 1.0, -0.25]), (len(P), 1))
        f[P[:, 2] < J["Forearm.L"][2]] = np.array([0.0, 0.15, -1.0])
        f[P[:, 1] < J["Neck1"][1]] = np.array([0.0, 0.7, -0.6])
        return f

    def grain(P, nrm):
        f = paint.strand_directions(P, nrm, flow)
        Q = P - f * np.sum(P * f, axis=1, keepdims=True)
        return n2.fbm(Q, freq=150.0 / s, octaves=2), n3.at(Q, 520.0 / s)

    def common(P, nrm):
        R = bb.regions(skel, P, st)
        occ = paint.sdf_occlusion(field, P, nrm, radius=0.06 * s, samples=5, strength=1.1)
        return R, occ

    def albedo(P, nrm):
        R, occ = common(P, nrm)
        up = np.clip(nrm[:, 2], -1, 1)
        big = n1.fbm(P, freq=3.0 / s, octaves=3)
        clump, strand = grain(P, nrm)
        c = np.broadcast_to(pal["body"], (len(P), 3)).copy() * (0.9 + 0.2 * big)[:, None]
        # the saddle: dark over the back, grizzled (broken by the clumps) where it fades down the flanks
        saddle = np.clip(R["back"] * (0.55 + 0.6 * paint.smoothstep(0.35, 0.75, clump + 0.3 * big)), 0, 1)
        saddle = np.clip(saddle + 0.6 * R["tail"] * paint.smoothstep(0.0, 0.6, up), 0, 1)
        c = paint.mix(c, pal["saddle"], saddle * (0.5 if sleek else 0.85))
        # pale under: the belly, the throat, the inside of the legs, the cheeks' lower edge
        under = np.clip(R["belly"] + 0.9 * R["throat"] + 0.7 * (1.0 - paint.smoothstep(-0.7, -0.1, up)) * (1.0 - R["back"]), 0, 1)
        c = paint.mix(c, pal["pale"], under * (0.85 if not barky else 0.5))
        c = paint.mix(c, pal["legs"], 0.75 * R["legs"] * (1.0 - R["paw"]))
        # the face: a darker mask over the brow, the muzzle lighter, pale cheeks and lips edged black
        c = paint.mix(c, pal["mask"], 0.55 * R["face"] * paint.smoothstep(0.2, 0.8, up) * (1.0 - R["muzzle"]))
        c = paint.mix(c, pal["muzzle"], 0.6 * R["muzzle"] * paint.smoothstep(-0.2, 0.5, up))
        c = paint.mix(c, pal["pale"], 0.6 * R["face"] * (1.0 - paint.smoothstep(-0.5, 0.1, up)) * (1.0 - R["lips"]))
        c = paint.mix(c, pal["ear"], R["ear"] * 0.9)
        c = paint.mix(c, pal["ear_in"], R["ear_in"] * 0.85)
        c = paint.mix(c, pal["tip"], np.clip(R["tail_tip"] * 1.2, 0, 1))
        if barky:
            # bark: plates split along their edges to the dark wood, lichen on what faces the sky
            F = bb._cells(P * np.array([1.0, 0.6, 1.0]), 24.0 / s, st.seed)
            crack = paint.smoothstep(0.55, 0.8, F) * np.clip(R["back"] + R["flank"] + R["tail"] + 0.6 * R["legs_upper"], 0, 1)
            ridge = 0.5 + 0.5 * np.sin(P[:, 2] * 220.0 / s + 4.0 * n1.at(P, 30.0 / s))
            c = c * (0.85 + 0.25 * ridge)[:, None]
            c = paint.mix(c, pal["crack"], 0.85 * crack)
            lich = paint.smoothstep(0.58, 0.72, n3.fbm(P, freq=16.0 / s, octaves=3)) * paint.smoothstep(0.2, 0.8, up)
            c = paint.mix(c, pal["lichen"], 0.75 * lich * (1.0 - R["face"]))
            th = R["thorn"]
            proud_tip = paint.smoothstep(0.4, 1.0, th)
            c = paint.mix(c, pal["thorn"], th)
            c = paint.mix(c, pal["thorn_tip"], 0.9 * proud_tip * paint.smoothstep(0.016 * s, 0.04 * s, bb._seg(P, J["Chest"], J["Spine1"])[0]))
        if sleek:
            # rings round the body, as a leech's, and pale spots along the flanks
            ring = 0.5 + 0.5 * np.sin(P[:, 1] * 140.0 / s + 2.0 * n1.at(P, 12.0 / s))
            c = paint.mix(c, pal["ring"], 0.35 * paint.smoothstep(0.7, 0.95, ring) * (1.0 - R["face"]))
            spot = paint.dots(P, 0.05 * s, 0.35, 0.008 * s, 0.016 * s, st.seed) if hasattr(paint, "dots") else 0.0
            c = paint.mix(c, pal["spot"], 0.6 * spot * R["flank"])
        elif not barky:
            # the guard hairs' black tips, grizzling the saddle and the ruff
            tips = paint.smoothstep(0.62, 0.85, strand) * np.clip(R["back"] + 0.6 * R["ruff"], 0, 1)
            c = paint.mix(c, pal["guard"], 0.45 * tips)
        # what every dog has: the pads and nails dark, the nose and lips black, the mouth red, the teeth
        c = paint.mix(c, FIXED["pad"], R["paw"] * paint.smoothstep(0.1, -0.6, up))
        c = paint.mix(c, FIXED["nail"], R["nail"])
        c = paint.mix(c, pal["mud"] if "mud" in pal else FIXED["mud"], 0.35 * R["paw"] * (1.0 - R["nail"]))
        c = paint.mix(c, FIXED["lips"], R["lips"] * 0.9)
        c = paint.mix(c, FIXED["mouth"], R["mouth"])
        c = paint.mix(c, FIXED["teeth"], np.clip(R["teeth"], 0, 1))
        c = paint.mix(c, FIXED["nose"], R["nose"])
        # the eye: the iris, the pupil, the dark rim
        de = np.minimum(np.linalg.norm(P - eyes[0], axis=1), np.linalg.norm(P - eyes[1], axis=1))
        iris = R["eye"]
        pupil = 1.0 - paint.smoothstep(0.004 * s, 0.006 * s, de - 0.006 * s)
        c = paint.mix(c, FIXED["lips"], 0.85 * R["eye_ring"])
        c = paint.mix(c, pal["iris"], iris)
        c = paint.mix(c, FIXED["pupil"], iris * paint.smoothstep(0.35, 0.8, pupil))
        # value from the shape: dark in the creases, light on what stands out
        v = 0.92 + (0.0 if sleek else 0.16) * (clump - 0.5) + (0.02 if sleek else 0.07) * (strand - 0.5)
        v = v * (0.52 + 0.48 * occ) + 0.10 * paint.exposure(occ, 4.0) * paint.smoothstep(-0.1, 0.6, up)
        v = np.maximum(v, R["eye"] * 0.95)
        return np.clip(c * v[:, None], 0, 1)

    def orm(P, nrm):
        R, occ = common(P, nrm)
        clump, _ = grain(P, nrm)
        rough = 0.82 + 0.08 * (clump - 0.5)
        if sleek:
            rough = 0.42 + 0.12 * n1.fbm(P, freq=20.0 / s, octaves=2)
        if barky:
            rough = 0.88 - 0.25 * R["thorn"]
        rough = rough - 0.45 * R["nose"] - 0.75 * R["eye"] - 0.3 * R["teeth"] - 0.35 * R["mouth"]
        return np.stack([0.5 + 0.5 * occ, np.clip(rough, 0.06, 0.97), np.zeros(len(P))], axis=1)

    def height(P, nrm):
        clump, strand = grain(P, nrm)
        R = bb.regions(skel, P, st, fine=False)
        if sleek:
            ring = 0.5 + 0.5 * np.sin(P[:, 1] * 140.0 / s + 2.0 * n1.at(P, 12.0 / s))
            return 0.25 * ring * (1.0 - R["face"]) + 0.1 * n2.fbm(P, freq=60.0 / s, octaves=2)
        if barky:
            F = bb._cells(P * np.array([1.0, 0.6, 1.0]), 24.0 / s, st.seed)
            ridge = 0.5 + 0.5 * np.sin(P[:, 2] * 220.0 / s + 4.0 * n1.at(P, 30.0 / s))
            return 0.6 * (1.0 - paint.smoothstep(0.4, 0.8, F)) + 0.3 * ridge
        return (0.3 + 0.5 * np.clip(R["ruff"] + R["back"] + R["tail"], 0, 1)) * (0.6 * clump + 0.4 * strand)

    return albedo, orm, height
