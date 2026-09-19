#!/usr/bin/env python3
"""Render Wickmere's sound effects.

Every effect is modelled rather than sampled: footsteps are a surface's grain under a body's
weight, impacts are the material's own modes struck hard, spells are the shape of the school
that casts them. Each entry gets several variants so repetition never reads as a loop, and
Foley picks one at random with a little pitch variance on top.

    python3 tools/audio/gen_sfx.py
    python3 tools/audio/gen_sfx.py --only footstep_stone sword_swing_light --force
    python3 tools/audio/gen_sfx.py --list

Output: game/assets/audio/sfx/<id>/<id>_NN.ogg, a manifest, and the core:table/sfx content
table that Foley reads (id -> paths, volume_db, pitch_variance, bus).
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from synth import core, env, filters, fx, instruments as inst, osc, render, theory  # noqa: E402
from synth.core import SR, midi_to_hz, samples  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_ROOT = os.path.join(ROOT, "game", "assets", "audio", "sfx")
PACK_DIR = os.path.join(ROOT, "game", "content", "packs", "core", "tables")

OGG_QUALITY = 3.0          # mono, short, mostly noisy: q3 is transparent for these

# One-shots are normalised by peak, not by loudness. Integrated loudness is measured over 400 ms
# blocks, so for a 90 ms click it means nothing, and matching it would force the transient down
# until the sound lost the attack that makes it readable. Peak normalisation keeps every effect's
# transient at the same height; the per-entry volume_db in the table sets the balance between
# them, which is where a mixer's judgement belongs.
PEAK_DB = -3.0


# =================================================================================================
# Shared shapes
# =================================================================================================

def _burst(n: int, rng, colour: str = "white") -> np.ndarray:
    return osc.noise(colour, n, rng)


def transient(rng, seconds: float, f_lo: float, f_hi: float, t60: float, colour: str = "white",
              attack: float = 0.0008) -> np.ndarray:
    """A band of noise with a fast attack and a short decay: the raw material of most impacts."""
    n = samples(seconds)
    y = _burst(n, rng, colour)
    centre = float(np.sqrt(f_lo * f_hi))
    q = max(centre / max(f_hi - f_lo, 1.0), 0.35)
    y = filters.bandpass(y, centre, q)
    return y * env.perc(n, attack, t60)


def body_thump(rng, seconds: float, freq: float, t60: float, bend: float = 0.5) -> np.ndarray:
    """The low half of an impact: a pitched thud that drops as it dies."""
    n = samples(seconds)
    t = np.arange(n) / SR
    f = freq * (1.0 + bend * np.exp(-t / (t60 * 0.25)))
    ph = 2.0 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * env.perc(n, 0.0012, t60)


def struck(rng, modes, seconds: float, hardness: float = 0.6, colour: str = "white") -> np.ndarray:
    """Strike a set of resonances. `modes` is [(hz, t60, gain)]."""
    n = samples(seconds)
    k = max(samples(0.0006 + 0.0035 * (1.0 - hardness)), 2)
    exc = np.zeros(n)
    exc[:k] = _burst(k, rng, colour) * np.hanning(k)
    y = filters.modal(exc, modes)
    y += filters.highpass(exc, 2500.0) * 0.35 * hardness
    return filters.dc_block(y)


def whoosh(rng, seconds: float, speed: float = 1.0, weight: float = 0.5,
           centre: float = 900.0) -> np.ndarray:
    """Something moving through air: a band of noise swept up and back down as it passes."""
    n = samples(seconds)
    y = osc.noise("pink", n, rng) * 0.8 + osc.noise("white", n, rng) * 0.4
    t = np.linspace(0.0, 1.0, n)
    # the classic pass-by curve: rises to the closest point, then falls
    curve = np.sin(np.pi * t ** (0.7 + 0.5 * weight))
    freq = centre * (0.45 + 1.7 * curve) * (0.7 + 0.6 * speed)
    y = filters.svf(y, np.clip(freq, 120.0, 14000.0), 1.2 + 1.4 * speed, "bp", block=64)
    y *= curve ** (1.2 + weight)
    return filters.highpass(y, 90.0)


def _limit_tail(y: np.ndarray, fade: float = 0.02) -> np.ndarray:
    return core.fade(y, 0.0004, fade)


def _trim_silence(y: np.ndarray, floor_db: float = -70.0, keep: float = 0.03) -> np.ndarray:
    """Cut the inaudible tail a long reverb leaves behind.

    Convolution reverbs are rendered with their full ring-out, which on a cathedral or the
    Toll's own decay is seconds of material below hearing. It costs file size and delays the
    moment the pooled player is free again.
    """
    mag = np.abs(y)
    thresh = core.db_to_lin(floor_db) * (mag.max() + 1e-12)
    idx = np.flatnonzero(mag > thresh)
    if not len(idx):
        return y
    end = min(len(y), int(idx[-1] + samples(keep)))
    return core.fade(y[:end], 0.0, min(keep, end / SR * 0.2))


# =================================================================================================
# Footsteps
# =================================================================================================

# Each surface: the grain that scatters under the foot, the body of the step, and how wet or
# resonant the ground under it is.
SURFACES = {
    "vale_grass": dict(colour="white", band=(1400, 5200), t60=0.075, body=88.0, body_gain=0.30,
                       body_t60=0.07, grains=170, wet=0.0, dur=0.34),
    "dirt":       dict(colour="pink", band=(700, 3200), t60=0.065, body=74.0, body_gain=0.42,
                       body_t60=0.075, grains=130, wet=0.0, dur=0.32),
    "stone":      dict(colour="white", band=(2200, 9000), t60=0.05, body=150.0, body_gain=0.26,
                       body_t60=0.05, grains=60, wet=0.0, dur=0.40, ring=True),
    "wood":       dict(colour="pink", band=(900, 4200), t60=0.06, body=190.0, body_gain=0.45,
                       body_t60=0.12, grains=50, wet=0.0, dur=0.38, hollow=True),
    "water":      dict(colour="white", band=(900, 6000), t60=0.14, body=120.0, body_gain=0.30,
                       body_t60=0.08, grains=240, wet=1.0, dur=0.55),
    "snow":       dict(colour="white", band=(2600, 9500), t60=0.09, body=70.0, body_gain=0.18,
                       body_t60=0.06, grains=420, wet=0.0, dur=0.38, squeak=True),
    "ash":        dict(colour="pink", band=(1600, 6500), t60=0.10, body=64.0, body_gain=0.16,
                       body_t60=0.07, grains=330, wet=0.0, dur=0.40),
    "gravel":     dict(colour="white", band=(1800, 8000), t60=0.11, body=96.0, body_gain=0.30,
                       body_t60=0.06, grains=260, wet=0.0, dur=0.42),
    "mud":        dict(colour="brown", band=(300, 1800), t60=0.10, body=62.0, body_gain=0.50,
                       body_t60=0.10, grains=90, wet=0.8, dur=0.48),
    "sand":       dict(colour="white", band=(1500, 7000), t60=0.09, body=70.0, body_gain=0.20,
                       body_t60=0.05, grains=380, wet=0.0, dur=0.36),
}


def footstep(rng, surface: str) -> np.ndarray:
    s = SURFACES[surface]
    dur = s["dur"]
    n = samples(dur)
    out = np.zeros(n)
    # the grain: many tiny particles displaced, densest right at the strike
    grains = osc.crackle(n, rng, s["grains"] / dur * float(rng.uniform(0.75, 1.3)), 1.6, 1.7)
    lo, hi = s["band"]
    grains = filters.bandpass(grains, float(np.sqrt(lo * hi)), max(np.sqrt(lo * hi) / (hi - lo), 0.4))
    grains *= env.perc(n, 0.001, s["t60"] * float(rng.uniform(0.8, 1.3)))
    out += grains * 0.9
    # the body: the weight going through the ground
    out += body_thump(rng, dur, s["body"] * float(rng.uniform(0.9, 1.12)),
                      s["body_t60"], bend=0.6) * s["body_gain"]
    # a second, softer contact: heel then toe
    roll = samples(float(rng.uniform(0.035, 0.075)))
    if roll < n:
        toe = osc.noise(s["colour"], n - roll, rng)
        toe = filters.bandpass(toe, np.sqrt(lo * hi) * 1.3, 1.0) * env.perc(n - roll, 0.001,
                                                                           s["t60"] * 0.6)
        out[roll:] += toe * 0.4
    if s.get("ring"):
        # a stone floor answers with the room, briefly
        out += struck(rng, [(rng.uniform(600, 1100), 0.11, 1.0), (rng.uniform(1600, 2600), 0.07, 0.5)],
                      dur, hardness=0.85) * 0.12
    if s.get("hollow"):
        # boards over a void
        out += struck(rng, [(rng.uniform(150, 230), 0.16, 1.0), (rng.uniform(420, 620), 0.10, 0.4),
                            (rng.uniform(900, 1300), 0.05, 0.15)], dur, hardness=0.5) * 0.30
    if s.get("squeak") and rng.random() < 0.65:
        # the squeak of compressed snow
        k = samples(float(rng.uniform(0.05, 0.11)))
        f = float(rng.uniform(1700.0, 3200.0))
        sq = osc.sine(f * np.linspace(1.0, rng.uniform(1.1, 1.5), k), k)
        sq *= env.smooth(osc.crackle(k, rng, 900.0, 1.0), 2.0)
        sq *= np.hanning(k) ** 0.7
        st = samples(float(rng.uniform(0.01, 0.05)))
        out[st:st + k] += sq * 0.22
    if s["wet"] > 0:
        # water displaced: a fizz and a small splash
        splash = osc.white(n, rng)
        splashenv = env.segments([(0, 0), (0.008, 1.0), (0.09, 0.35), (dur, 0.0)], n)
        splash = filters.bandpass(splash, 2600.0, 0.5) * splashenv
        drops = osc.crackle(n, rng, 55.0, 6.0, 1.2)
        drops = filters.bandpass(drops, 1500.0, 1.4)
        out += (splash * 0.55 + drops * 0.35) * s["wet"]
    return _limit_tail(filters.highpass(out, 45.0), 0.03)


# =================================================================================================
# Cloth, armour, weapons
# =================================================================================================

def armour_rustle(rng, heavy: bool = False) -> np.ndarray:
    dur = float(rng.uniform(0.32, 0.55))
    n = samples(dur)
    # cloth and leather: a broadband shuffle
    cloth = osc.crackle(n, rng, 900.0, 1.4, 1.9)
    cloth = filters.bandpass(cloth, 2600.0, 0.55) + filters.highpass(cloth, 5200.0) * 0.4
    shape = env.segments([(0, 0), (0.03, 1.0), (dur * 0.55, 0.5), (dur, 0.0)], n)
    out = cloth * shape * 0.7
    if heavy:
        # mail and plate: many small metal collisions over the cloth
        links = int(rng.integers(5, 12))
        for _ in range(links):
            s = samples(float(rng.uniform(0.0, dur * 0.7)))
            f = float(rng.uniform(2400.0, 6500.0))
            k = samples(0.16)
            if s + k >= n:
                continue
            hit = struck(rng, [(f, 0.09, 1.0), (f * 1.71, 0.06, 0.5), (f * 2.9, 0.04, 0.25)],
                         0.16, hardness=0.9)
            out[s:s + k] += hit[:k] * float(rng.uniform(0.1, 0.4))
        out += filters.lowpass(osc.brown(n, rng), 260.0) * shape * 0.25
    return _limit_tail(filters.highpass(out, 150.0), 0.04)


def sword_swing(rng, heavy: bool = False) -> np.ndarray:
    dur = 0.52 if heavy else 0.34
    y = whoosh(rng, dur, speed=0.7 if heavy else 1.25, weight=0.75 if heavy else 0.3,
               centre=620.0 if heavy else 1250.0)
    # the blade itself rings faintly as it cuts
    n = samples(dur)
    ring = osc.sine(float(rng.uniform(2600.0, 4200.0)), n) * env.perc(n, 0.02, 0.12) * 0.05
    return _limit_tail(y * (0.9 if heavy else 0.8) + ring, 0.05)


def axe_swing(rng) -> np.ndarray:
    y = whoosh(rng, 0.46, speed=0.85, weight=0.8, centre=520.0)
    n = len(y)
    y += filters.lowpass(osc.brown(n, rng), 260.0) * env.segments(
        [(0, 0), (0.25, 0.7), (0.46, 0.0)], n) * 0.3
    return _limit_tail(y, 0.05)


def mace_swing(rng) -> np.ndarray:
    y = whoosh(rng, 0.5, speed=0.6, weight=1.0, centre=380.0)
    return _limit_tail(y * 0.95, 0.06)


def bow_draw(rng) -> np.ndarray:
    dur = 0.78
    n = samples(dur)
    # the creak of the limbs plus the string sliding over the rest
    creaky = osc.saw(np.linspace(55.0, 92.0, n), n) * env.smooth(np.abs(osc.white(n, rng)), 3.0)
    creaky = filters.formant_bank(creaky, [(260, 110, 1.0), (760, 280, 0.35), (1700, 500, 0.12)])
    slide = filters.bandpass(osc.crackle(n, rng, 260.0, 2.0), 3200.0, 0.8) * 0.3
    shape = env.segments([(0, 0), (0.12, 0.8), (dur * 0.8, 1.0), (dur, 0.6)], n)
    return _limit_tail(filters.highpass((creaky * 0.5 + slide) * shape, 90.0), 0.06)


def bow_release(rng) -> np.ndarray:
    dur = 0.5
    n = samples(dur)
    # the string's snap: a short pitched thwack plus the limbs settling
    thwack = struck(rng, [(float(rng.uniform(150, 220)), 0.10, 1.0),
                          (float(rng.uniform(420, 620)), 0.07, 0.6),
                          (float(rng.uniform(1100, 1600)), 0.04, 0.3)], dur, hardness=0.85)
    air = whoosh(rng, dur, speed=1.5, weight=0.2, centre=1800.0) * 0.35
    return _limit_tail(thwack * 0.9 + air, 0.05)


def arrow_whoosh(rng) -> np.ndarray:
    return _limit_tail(whoosh(rng, 0.38, speed=1.7, weight=0.15, centre=2200.0) * 0.7, 0.04)


def impact(rng, material: str) -> np.ndarray:
    """A hit landing. Each material is its own resonances plus its own debris."""
    if material == "flesh":
        dur = 0.32
        n = samples(dur)
        out = body_thump(rng, dur, float(rng.uniform(58, 86)), 0.10, bend=0.9) * 0.9
        slap = transient(rng, dur, 400, 2400, 0.045, "pink")
        wet = filters.bandpass(osc.crackle(n, rng, 180.0, 5.0), 900.0, 1.0) * \
            env.perc(n, 0.002, 0.07)
        out += slap * 0.6 + wet * 0.35
    elif material == "wood":
        dur = 0.45
        f = float(rng.uniform(190.0, 330.0))
        out = struck(rng, [(f, 0.22, 1.0), (f * 2.4, 0.13, 0.5), (f * 4.6, 0.07, 0.22),
                           (f * 7.9, 0.04, 0.09)], dur, hardness=0.6, colour="pink")
        out += body_thump(rng, dur, f * 0.5, 0.09, bend=0.5) * 0.35
        out += transient(rng, dur, 900, 4200, 0.03) * 0.3
    elif material == "metal":
        dur = 1.1
        f = float(rng.uniform(900.0, 1900.0))
        out = struck(rng, [(f, 0.55, 1.0), (f * 1.74, 0.42, 0.65), (f * 2.61, 0.3, 0.4),
                           (f * 3.93, 0.2, 0.25), (f * 5.4, 0.13, 0.12)], dur, hardness=0.95)
        out += transient(rng, dur, 2500, 9000, 0.02) * 0.4
        out += body_thump(rng, dur, 140.0, 0.06, bend=0.4) * 0.2
    elif material == "stone":
        dur = 0.4
        f = float(rng.uniform(700.0, 1500.0))
        out = struck(rng, [(f, 0.085, 1.0), (f * 1.9, 0.06, 0.5), (f * 3.3, 0.04, 0.25)],
                     dur, hardness=0.9)
        out += transient(rng, dur, 1800, 7000, 0.035) * 0.55
        out += body_thump(rng, dur, 110.0, 0.05, bend=0.3) * 0.35
        n = samples(dur)
        grit = filters.bandpass(osc.crackle(n, rng, 260.0, 3.0), 4200.0, 0.9) * \
            env.perc(n, 0.004, 0.12)
        out += grit * 0.3
    else:
        raise ValueError(material)
    return _limit_tail(filters.highpass(out, 42.0), 0.03)


def block_clang(rng, parry: bool = False) -> np.ndarray:
    dur = 1.5 if parry else 0.9
    f = float(rng.uniform(1300.0, 2400.0)) * (1.15 if parry else 1.0)
    modes = [(f, 0.8 if parry else 0.4, 1.0), (f * 1.62, 0.6 if parry else 0.3, 0.7),
             (f * 2.47, 0.4, 0.45), (f * 3.71, 0.3, 0.25), (f * 5.1, 0.2, 0.12)]
    out = struck(rng, modes, dur, hardness=0.98)
    out += transient(rng, dur, 3000, 11000, 0.02) * (0.55 if parry else 0.4)
    out += body_thump(rng, dur, 160.0, 0.05, bend=0.3) * 0.25
    if parry:
        # a parry sings: the blade is turned, not stopped
        n = samples(dur)
        sing = osc.sine(f * 1.005, n) * env.perc(n, 0.006, 0.85) * 0.22
        out += sing
    return _limit_tail(filters.highpass(out, 120.0), 0.06)


def stagger_thud(rng) -> np.ndarray:
    dur = 0.6
    n = samples(dur)
    out = body_thump(rng, dur, float(rng.uniform(48, 68)), 0.20, bend=0.8)
    out += filters.lowpass(osc.brown(n, rng), 200.0) * env.perc(n, 0.004, 0.13) * 0.6
    # armour_rustle picks its own random length, which may be shorter than this thud
    core.mix_into(out, armour_rustle(rng, heavy=True), 0, 0.45)
    return _limit_tail(filters.highpass(out, 35.0), 0.05)


# =================================================================================================
# Spells: one gesture per school
# =================================================================================================

def spell_cast(rng, school: str) -> np.ndarray:
    """Kindling crackles and rushes, Hush shimmers and freezes, Binding hums and locks,
    Mending chimes, Calling swells like a choir taking breath."""
    if school == "kindling":
        dur = 1.0
        n = samples(dur)
        rush = whoosh(rng, dur, speed=1.3, weight=0.4, centre=1400.0) * 0.7
        fire = osc.crackle(n, rng, 420.0, 3.0, 1.4)
        fire = filters.bandpass(fire, 2200.0, 0.7) + filters.highpass(fire, 5000.0) * 0.5
        fire *= env.segments([(0, 0), (0.12, 1.0), (0.5, 0.6), (dur, 0.0)], n)
        low = body_thump(rng, dur, 70.0, 0.3, bend=0.6) * 0.35
        out = rush + fire * 0.7 + low
    elif school == "hush":
        dur = 1.4
        n = samples(dur)
        # frost: high inharmonic shimmer settling downward, and the air going quiet
        modes = [(float(rng.uniform(3200, 11000)), float(rng.uniform(0.3, 0.9)),
                  float(rng.uniform(0.2, 1.0))) for _ in range(28)]
        exc = np.zeros(n)
        k = samples(0.02)
        exc[:k] = osc.white(k, rng) * np.hanning(k)
        shimmer = filters.modal(exc, modes)
        sweep = osc.sine(np.geomspace(6000.0, 900.0, n), n) * env.perc(n, 0.02, 0.6) * 0.18
        breath = filters.bandpass(osc.white(n, rng), 4200.0, 0.4) * \
            env.segments([(0, 0), (0.1, 0.8), (dur, 0.0)], n) * 0.25
        out = shimmer * 0.9 + sweep + breath
    elif school == "binding":
        dur = 1.3
        n = samples(dur)
        # a hum that tightens, then a lock
        f = float(midi_to_hz(45))
        hum = osc.saw(f * np.linspace(0.92, 1.0, n), n) * 0.4 + osc.sine(f * 2, n) * 0.25
        hum = filters.formant_bank(hum, [(180, 90, 1.0), (620, 200, 0.5), (1400, 400, 0.2)])
        hum *= env.segments([(0, 0), (0.25, 0.7), (dur * 0.72, 1.0), (dur * 0.78, 0.25),
                             (dur, 0.0)], n)
        lock = np.zeros(n)
        core.mix_into(lock, struck(rng, [(320, 0.18, 1.0), (880, 0.1, 0.5), (1900, 0.06, 0.25)],
                                   0.3, hardness=0.8), samples(dur * 0.72), 0.8)
        out = hum * 0.8 + lock
    elif school == "mending":
        dur = 1.8
        notes = [theory.degree_to_midi(d, 72, "lydian") for d in (0, 2, 4, 6)]
        out = inst.chime_run(notes, dur, spacing=0.10, amp=0.55, rng=rng, t60=1.4)
        core.mix_into(out, inst.pad([60, 67], dur, amp=0.12, rng=rng, attack=0.25,
                                    release=0.8), 0, 0.6)
    elif school == "calling":
        dur = 2.0
        n = samples(dur)
        # a choir taking breath and arriving
        breath = filters.bandpass(osc.white(n, rng), 1800.0, 0.5) * \
            env.segments([(0, 0), (0.25, 0.7), (0.6, 0.15), (dur, 0.0)], n) * 0.3
        out = breath
        core.mix_into(out, inst.choir([52, 59, 64], dur * 0.9, amp=0.5, rng=rng, vowel="ah",
                                      attack=0.55, release=0.7), 0, 1.0)
        core.mix_into(out, inst.cymbal_swell(dur, amp=0.18, rng=rng, reverse=True), 0, 0.5)
    else:
        raise ValueError(school)
    out = filters.highpass(out, 60.0)
    wet = fx.reverb(out, {"kindling": "room", "hush": "cave", "binding": "chamber",
                          "mending": "hall", "calling": "cathedral"}[school],
                    mix=0.30, seed=int(rng.integers(1 << 30)), tail=True)
    return _limit_tail(core.to_mono(wet), 0.1)


def spell_impact(rng, school: str) -> np.ndarray:
    if school == "kindling":
        dur = 0.8
        n = samples(dur)
        out = body_thump(rng, dur, 62.0, 0.25, bend=1.0) * 0.9
        out += transient(rng, dur, 600, 6000, 0.09, "pink") * 0.8
        out += filters.bandpass(osc.crackle(n, rng, 500.0, 3.0), 2600.0, 0.7) * \
            env.perc(n, 0.004, 0.22) * 0.5
    elif school == "hush":
        dur = 0.9
        modes = [(float(rng.uniform(2600, 9000)), float(rng.uniform(0.15, 0.5)),
                  float(rng.uniform(0.3, 1.0))) for _ in range(20)]
        out = struck(rng, modes, dur, hardness=0.95) * 0.9
        out += body_thump(rng, dur, 110.0, 0.08, bend=0.3) * 0.35
    elif school == "binding":
        dur = 0.7
        out = struck(rng, [(220, 0.3, 1.0), (520, 0.2, 0.6), (1150, 0.12, 0.3)], dur, hardness=0.7)
        out += body_thump(rng, dur, 70.0, 0.16, bend=0.5) * 0.6
    elif school == "mending":
        dur = 1.2
        out = inst.hand_bell(84, dur, amp=0.5, rng=rng)
        core.mix_into(out, inst.hand_bell(91, dur * 0.8, amp=0.28, rng=rng), 0, 1.0)
    elif school == "calling":
        dur = 1.1
        n = samples(dur)
        out = body_thump(rng, dur, 55.0, 0.3, bend=0.7) * 0.5
        core.mix_into(out, inst.choir([45, 52], dur * 0.85, amp=0.45, rng=rng, vowel="oh",
                                      attack=0.05, release=0.4), 0, 1.0)
    else:
        raise ValueError(school)
    return _limit_tail(filters.highpass(out, 50.0), 0.06)


# =================================================================================================
# Objects, doors, UI
# =================================================================================================

def potion_drink(rng) -> np.ndarray:
    dur = 1.5
    n = samples(dur)
    out = np.zeros(n)
    # cork, then three swallows, then a breath
    cork = struck(rng, [(700, 0.05, 1.0), (1800, 0.03, 0.4)], 0.12, hardness=0.7)
    out[:len(cork)] += cork * 0.5
    t = 0.22
    for i in range(3):
        k = samples(0.18)
        s = samples(t)
        if s + k >= n:
            break
        f = float(rng.uniform(240.0, 420.0)) * (1.0 - 0.12 * i)
        glug = osc.sine(f * np.linspace(1.0, 1.7, k), k) * env.perc(k, 0.004, 0.06)
        glug += filters.bandpass(osc.white(k, rng), 1400.0, 1.2) * env.perc(k, 0.002, 0.03) * 0.4
        out[s:s + k] += glug * float(rng.uniform(0.6, 1.0))
        t += float(rng.uniform(0.2, 0.32))
    s = samples(t + 0.05)
    if s < n:
        breath = filters.bandpass(osc.white(n - s, rng), 1100.0, 0.5) * \
            env.segments([(0, 0), (0.06, 1.0), (0.35, 0.0)], n - s) * 0.18
        out[s:] += breath
    return _limit_tail(filters.highpass(out, 110.0), 0.06)


def eat(rng) -> np.ndarray:
    dur = 0.9
    n = samples(dur)
    out = np.zeros(n)
    bites = int(rng.integers(2, 4))
    t = 0.0
    for _ in range(bites):
        k = samples(float(rng.uniform(0.1, 0.2)))
        s = samples(t)
        if s + k >= n:
            break
        crunch = osc.crackle(k, rng, 700.0, 2.5, 1.3)
        crunch = filters.bandpass(crunch, 1900.0, 0.6) + filters.highpass(crunch, 4000.0) * 0.4
        crunch *= env.segments([(0, 0), (0.01, 1.0), (k / SR, 0.0)], k)
        out[s:s + k] += crunch * float(rng.uniform(0.5, 1.0))
        t += float(rng.uniform(0.22, 0.38))
    return _limit_tail(filters.highpass(out, 200.0), 0.05)


def pick_up(rng) -> np.ndarray:
    dur = 0.3
    out = transient(rng, dur, 900, 5200, 0.04, "pink") * 0.7
    out += struck(rng, [(float(rng.uniform(400, 900)), 0.09, 1.0),
                        (float(rng.uniform(1400, 2600)), 0.05, 0.4)], dur, hardness=0.6) * 0.5
    return _limit_tail(filters.highpass(out, 180.0), 0.03)


def coins(rng, many: bool = False) -> np.ndarray:
    dur = 1.3 if many else 0.6
    n = samples(dur)
    out = np.zeros(n)
    count = int(rng.integers(12, 30)) if many else int(rng.integers(2, 5))
    for i in range(count):
        s = samples(float(rng.uniform(0.0, dur * (0.55 if many else 0.35))))
        f = float(rng.uniform(2400.0, 6200.0))
        k = samples(0.4)
        if s + k >= n:
            continue
        # a coin rings and then rattles as it settles
        hit = struck(rng, [(f, 0.3, 1.0), (f * 1.58, 0.2, 0.6), (f * 2.43, 0.13, 0.3),
                           (f * 3.9, 0.08, 0.15)], 0.4, hardness=0.95)
        out[s:s + k] += hit[:k] * float(rng.uniform(0.25, 1.0))
    out += filters.bandpass(osc.crackle(n, rng, 40.0 if many else 12.0, 2.0), 3600.0, 0.8) * 0.2
    return _limit_tail(filters.highpass(out, 400.0), 0.06)


def door(rng, material: str = "wood", opening: bool = True) -> np.ndarray:
    dur = 1.5 if opening else 0.9
    n = samples(dur)
    out = np.zeros(n)
    if material == "wood":
        # hinges complain, then the door meets its frame
        k = samples(dur * 0.62)
        f = float(rng.uniform(180.0, 420.0))
        sweep = f * np.linspace(1.0, float(rng.uniform(1.3, 2.2)), k) ** 1.2
        rough = env.smooth(osc.white(k, rng), 2.2)
        creaky = osc.saw(sweep, k) * (0.4 + 0.6 * np.abs(rough))
        creaky = filters.formant_bank(creaky, [(f * 3.0, 90, 1.0), (1500, 450, 0.25)])
        creaky *= env.segments([(0, 0), (0.08, 0.9), (k / SR * 0.8, 0.7), (k / SR, 0.0)], k)
        out[:k] += creaky * 0.55
        thud_at = samples(dur * (0.72 if opening else 0.35))
        thud = struck(rng, [(110, 0.18, 1.0), (280, 0.11, 0.5), (620, 0.06, 0.2)], 0.5, hardness=0.5)
        out[thud_at:thud_at + min(len(thud), n - thud_at)] += thud[:n - thud_at] * (0.7 if not opening else 0.4)
        out += body_thump(rng, dur, 68.0, 0.12, bend=0.4) * 0.2
    else:  # iron
        k = samples(dur * 0.5)
        grind = filters.bandpass(osc.crackle(k, rng, 1600.0, 2.0), 2400.0, 0.5) * 0.5
        grind += filters.bandpass(osc.white(k, rng), 900.0, 0.7) * 0.3
        grind *= env.segments([(0, 0), (0.05, 1.0), (k / SR * 0.85, 0.7), (k / SR, 0.0)], k)
        out[:k] += grind
        clang_at = samples(dur * (0.62 if opening else 0.3))
        f = float(rng.uniform(600.0, 1200.0))
        cl = struck(rng, [(f, 0.6, 1.0), (f * 1.7, 0.4, 0.6), (f * 2.9, 0.25, 0.3)], 0.8,
                    hardness=0.9)
        out[clang_at:clang_at + min(len(cl), n - clang_at)] += cl[:n - clang_at] * 0.8
    return _limit_tail(filters.highpass(out, 55.0), 0.08)


def chest_open(rng) -> np.ndarray:
    dur = 1.6
    n = samples(dur)
    out = np.zeros(n)
    latch = struck(rng, [(1500, 0.08, 1.0), (3100, 0.05, 0.5)], 0.25, hardness=0.9)
    out[:len(latch)] += latch * 0.6
    core.mix_into(out, door(rng, "wood", opening=True), samples(0.2), 0.7)
    return _limit_tail(out, 0.08)


def lockpick(rng, kind: str = "click") -> np.ndarray:
    if kind == "break":
        dur = 0.35
        out = transient(rng, dur, 2200, 9000, 0.03) * 0.8
        out += struck(rng, [(3400, 0.08, 1.0), (5900, 0.05, 0.5)], dur, hardness=0.95) * 0.6
        out += body_thump(rng, dur, 180.0, 0.04, bend=0.3) * 0.2
    else:
        dur = 0.13
        f = float(rng.uniform(2600.0, 5200.0))
        out = struck(rng, [(f, 0.035, 1.0), (f * 1.9, 0.02, 0.4)], dur, hardness=0.95)
        out += transient(rng, dur, 3000, 10000, 0.008) * 0.5
    return _limit_tail(filters.highpass(out, 500.0), 0.02)


def ui_sound(rng, kind: str) -> np.ndarray:
    """The UI is paper, brass and oak (DESIGN.md 9), so it sounds like those and nothing else."""
    if kind == "paper_slide":
        dur = 0.34
        n = samples(dur)
        y = osc.crackle(n, rng, 2200.0, 1.2, 2.0)
        y = filters.bandpass(y, 3600.0, 0.5) + filters.highpass(y, 7000.0) * 0.5
        y *= env.segments([(0, 0), (0.02, 1.0), (dur * 0.6, 0.5), (dur, 0.0)], n)
        out = y * 0.7
    elif kind == "page_turn":
        dur = 0.55
        n = samples(dur)
        y = osc.crackle(n, rng, 1500.0, 1.5, 1.8)
        y = filters.bandpass(y, 2800.0, 0.45)
        # the sheet lifts, flips and settles
        y *= env.segments([(0, 0), (0.05, 0.8), (0.18, 0.35), (0.3, 1.0), (dur, 0.0)], n)
        out = y * 0.7
    elif kind == "book_open":
        dur = 0.7
        n = samples(dur)
        y = osc.crackle(n, rng, 900.0, 2.0, 1.6)
        y = filters.bandpass(y, 1800.0, 0.5)
        y *= env.segments([(0, 0), (0.06, 1.0), (0.4, 0.3), (dur, 0.0)], n)
        spine = struck(rng, [(220, 0.12, 1.0), (560, 0.07, 0.4)], dur, hardness=0.4) * 0.35
        out = y * 0.6 + spine
    elif kind == "book_close":
        dur = 0.5
        n = samples(dur)
        clap = body_thump(rng, dur, 150.0, 0.08, bend=0.5) * 0.7
        clap += transient(rng, dur, 700, 4000, 0.03, "pink") * 0.5
        out = clap
    elif kind == "map_unroll":
        dur = 1.1
        n = samples(dur)
        y = osc.crackle(n, rng, 1800.0, 1.4, 1.7)
        y = filters.bandpass(y, 2600.0, 0.45)
        y *= env.segments([(0, 0), (0.08, 0.9), (0.55, 1.0), (0.9, 0.4), (dur, 0.0)], n)
        out = y * 0.65
    elif kind == "brass_click":
        dur = 0.22
        f = float(rng.uniform(1900.0, 3100.0))
        out = struck(rng, [(f, 0.07, 1.0), (f * 2.76, 0.04, 0.45), (f * 5.4, 0.02, 0.18)],
                     dur, hardness=0.9) * 0.9
    elif kind == "hover_tick":
        dur = 0.09
        f = float(rng.uniform(3200.0, 4400.0))
        out = struck(rng, [(f, 0.022, 1.0), (f * 2.4, 0.014, 0.3)], dur, hardness=0.95) * 0.6
    elif kind == "error_thunk":
        dur = 0.4
        out = body_thump(rng, dur, 92.0, 0.11, bend=0.35) * 0.9
        out += struck(rng, [(230, 0.09, 1.0), (430, 0.05, 0.3)], dur, hardness=0.35) * 0.5
    else:
        raise ValueError(kind)
    return _limit_tail(filters.highpass(out, 120.0), 0.02)


# =================================================================================================
# Bells, weather, world
# =================================================================================================

def bell_sfx(rng, kind: str) -> np.ndarray:
    if kind == "hand":
        return _limit_tail(inst.hand_bell(81 + int(rng.integers(-2, 3)), 2.4, amp=0.6, rng=rng), 0.1)
    if kind == "tavern":
        y = inst.bell(69 + int(rng.integers(-1, 2)), 4.0, t60=3.4, amp=0.55, rng=rng, warmth=0.1)
        return _limit_tail(y, 0.15)
    if kind == "tower":
        y = inst.bell(50 + int(rng.integers(-1, 2)), 11.0, t60=10.0, amp=0.6, rng=rng, warmth=0.3)
        y = core.to_mono(fx.reverb(y, "valley", mix=0.3, seed=int(rng.integers(1 << 30)), tail=True))
        return _limit_tail(y, 0.4)
    if kind == "toll":
        # the Cracked Toll itself: forty metres of bronze, and the hum after
        y = inst.toll_bell(31, 22.0, amp=0.62, rng=rng)
        y = core.to_mono(fx.reverb(y, "cinder", mix=0.34, seed=int(rng.integers(1 << 30)), tail=True))
        return _limit_tail(y, 1.5)
    raise ValueError(kind)


def thunder_sfx(rng, near: bool = True):
    from gen_ambience import thunder as _thunder
    y = _thunder(5.0 if near else 7.5, rng, distance=0.15 if near else 0.8)
    return _limit_tail(core.to_mono(y), 0.3)


def wind_gust_sfx(rng) -> np.ndarray:
    from gen_ambience import wind as _wind
    dur = 3.4
    y = core.to_mono(_wind(dur, rng, strength=0.9, height=0.5, gustiness=1.0))
    n = len(y)
    y *= env.segments([(0, 0), (0.6, 1.0), (2.0, 0.7), (dur, 0.0)], n)
    return _limit_tail(y, 0.3)


def water_splash(rng) -> np.ndarray:
    dur = 1.1
    n = samples(dur)
    out = body_thump(rng, dur, 150.0, 0.12, bend=1.2) * 0.5
    burst = filters.bandpass(osc.white(n, rng), 2200.0, 0.4)
    burst *= env.segments([(0, 0), (0.012, 1.0), (0.18, 0.3), (dur, 0.0)], n)
    out += burst * 0.9
    drops = filters.bandpass(osc.crackle(n, rng, 120.0, 6.0), 1600.0, 1.2) * \
        env.segments([(0, 0), (0.08, 1.0), (dur, 0.0)], n)
    out += drops * 0.4
    return _limit_tail(filters.highpass(out, 80.0), 0.08)


def cart_wheels(rng) -> np.ndarray:
    dur = 3.0
    n = samples(dur)
    # rumble of iron tyres on a track, plus the axle and the bed of the cart
    rumble = filters.lowpass(osc.brown(n, rng), 220.0, 0.8) * 0.7
    rumble *= np.clip(0.6 + 0.5 * env.wander(n, rng, 2.2, 1.0), 0.2, 1.4)
    out = rumble
    # each wheel revolution knocks
    period = float(rng.uniform(0.42, 0.62))
    t = 0.0
    while t < dur:
        s = samples(t)
        k = samples(0.25)
        if s + k >= n:
            break
        knock = struck(rng, [(float(rng.uniform(120, 260)), 0.09, 1.0),
                             (float(rng.uniform(500, 900)), 0.05, 0.3)], 0.25, hardness=0.5)
        out[s:s + k] += knock[:k] * float(rng.uniform(0.3, 0.8))
        t += period * float(rng.uniform(0.92, 1.08))
    axle = filters.bandpass(osc.saw(np.linspace(150, 190, n), n), 900.0, 1.6) * 0.1
    axle *= np.clip(env.wander(n, rng, 1.5, 1.0) * 0.5 + 0.5, 0, 1)
    out += axle
    out *= env.segments([(0, 0), (0.25, 1.0), (dur - 0.4, 1.0), (dur, 0.0)], n)
    return _limit_tail(filters.highpass(out, 45.0), 0.2)


def wood_creak_sfx(rng) -> np.ndarray:
    from gen_ambience import creak as _creak
    return _limit_tail(_creak(rng, big=bool(rng.random() < 0.5)), 0.05)


def hearth_chime(rng) -> np.ndarray:
    """Resting at a Hearthstone: a name is kept. Warm, and it answers itself."""
    dur = 3.4
    notes = [theory.degree_to_midi(d, 74, "lydian") for d in (0, 2, 4)]
    y = inst.chime_run(notes, dur, spacing=0.22, amp=0.5, rng=rng, t60=2.6)
    core.mix_into(y, inst.pad([50, 57, 62], dur * 0.9, amp=0.13, rng=rng, attack=0.4,
                              release=1.0), 0, 1.0)
    y = core.to_mono(fx.reverb(y, "valley", mix=0.3, seed=int(rng.integers(1 << 30)), tail=True))
    return _limit_tail(y, 0.3)


def echo_tone(rng) -> np.ndarray:
    """Recovering an Echo: what you left comes back. The Toll's head, inverted, far away."""
    dur = 3.0
    n = samples(dur)
    out = np.zeros(n)
    tonic, mode = 57, "dorian"
    degs = theory.TOLL.inverse().fragment(3).degrees()
    for i, d in enumerate(degs):
        s = samples(i * 0.34)
        core.mix_into(out, inst.bell(theory.degree_to_midi(d, tonic, mode) + 12,
                                     dur - i * 0.34, t60=2.4, amp=0.4, rng=rng, warmth=0.3), s)
    out = core.to_mono(fx.reverb(out, "marsh", mix=0.4, seed=int(rng.integers(1 << 30)), tail=True))
    return _limit_tail(out, 0.3)


def death_sound(rng) -> np.ndarray:
    dur = 3.5
    n = samples(dur)
    # the note goes out of the world: a low bell and everything draining away
    bell = inst.bell(38, dur, t60=3.2, amp=0.5, rng=rng, warmth=0.5)
    drain = osc.sine(np.geomspace(320.0, 42.0, n), n) * env.segments(
        [(0, 0), (0.08, 0.5), (1.2, 0.3), (dur, 0.0)], n) * 0.3
    out = drain.copy()
    core.mix_into(out, bell, 0, 1.0)
    out = core.to_mono(fx.reverb(out, "cinder", mix=0.38, seed=int(rng.integers(1 << 30)), tail=True))
    return _limit_tail(out, 0.5)


# =================================================================================================
# The catalogue
# =================================================================================================

def _e(fn, count=4, volume_db=0.0, pitch=0.06, bus="SFX", **kw):
    return dict(fn=fn, count=count, volume_db=volume_db, pitch_variance=pitch, bus=bus, kw=kw)


def _catalogue() -> dict:
    c: dict = {}
    for surface in SURFACES:
        c["footstep_%s" % surface] = _e(lambda rng, s=surface: footstep(rng, s), count=4,
                                        volume_db=-6.0, pitch=0.08)
    c.update({
        "armour_light": _e(lambda rng: armour_rustle(rng, False), 4, -10.0, 0.08),
        "armour_heavy": _e(lambda rng: armour_rustle(rng, True), 4, -8.0, 0.07),
        "sword_swing_light": _e(lambda rng: sword_swing(rng, False), 4, -4.0, 0.07),
        "sword_swing_heavy": _e(lambda rng: sword_swing(rng, True), 4, -3.0, 0.06),
        "axe_swing": _e(lambda rng: axe_swing(rng), 4, -3.0, 0.06),
        "mace_swing": _e(lambda rng: mace_swing(rng), 4, -3.0, 0.06),
        "impact_flesh": _e(lambda rng: impact(rng, "flesh"), 5, -3.0, 0.08),
        "impact_wood": _e(lambda rng: impact(rng, "wood"), 4, -4.0, 0.07),
        "impact_metal": _e(lambda rng: impact(rng, "metal"), 4, -5.0, 0.06),
        "impact_stone": _e(lambda rng: impact(rng, "stone"), 4, -4.0, 0.07),
        "block_clang": _e(lambda rng: block_clang(rng, False), 4, -4.0, 0.06),
        "parry_clang": _e(lambda rng: block_clang(rng, True), 4, -2.0, 0.05),
        "stagger_thud": _e(lambda rng: stagger_thud(rng), 3, -4.0, 0.07),
        "bow_draw": _e(lambda rng: bow_draw(rng), 3, -8.0, 0.05),
        "bow_release": _e(lambda rng: bow_release(rng), 4, -4.0, 0.06),
        "arrow_whoosh": _e(lambda rng: arrow_whoosh(rng), 4, -8.0, 0.09),
        "arrow_hit": _e(lambda rng: impact(rng, "wood"), 4, -6.0, 0.08),
        "potion_drink": _e(lambda rng: potion_drink(rng), 3, -6.0, 0.04),
        "eat": _e(lambda rng: eat(rng), 3, -8.0, 0.06),
        "pick_up": _e(lambda rng: pick_up(rng), 4, -8.0, 0.08),
        "coins_few": _e(lambda rng: coins(rng, False), 4, -8.0, 0.07),
        "coins_many": _e(lambda rng: coins(rng, True), 3, -7.0, 0.05),
        "door_wood_open": _e(lambda rng: door(rng, "wood", True), 3, -6.0, 0.05),
        "door_wood_close": _e(lambda rng: door(rng, "wood", False), 3, -5.0, 0.05),
        "door_iron_open": _e(lambda rng: door(rng, "iron", True), 3, -6.0, 0.04),
        "door_iron_close": _e(lambda rng: door(rng, "iron", False), 3, -5.0, 0.04),
        "chest_open": _e(lambda rng: chest_open(rng), 3, -6.0, 0.04),
        "lockpick_click": _e(lambda rng: lockpick(rng, "click"), 5, -10.0, 0.10),
        "lockpick_break": _e(lambda rng: lockpick(rng, "break"), 3, -6.0, 0.06),
        "water_splash": _e(lambda rng: water_splash(rng), 4, -5.0, 0.08),
        "wood_creak": _e(lambda rng: wood_creak_sfx(rng), 4, -10.0, 0.09),
        "cart_wheels": _e(lambda rng: cart_wheels(rng), 2, -9.0, 0.04),
        "wind_gust": _e(lambda rng: wind_gust_sfx(rng), 3, -10.0, 0.05),
        "thunder_near": _e(lambda rng: thunder_sfx(rng, True), 3, -2.0, 0.05),
        "thunder_far": _e(lambda rng: thunder_sfx(rng, False), 3, -6.0, 0.05),
        "bell_hand": _e(lambda rng: bell_sfx(rng, "hand"), 3, -6.0, 0.04),
        "bell_tavern": _e(lambda rng: bell_sfx(rng, "tavern"), 3, -5.0, 0.03),
        "bell_tower": _e(lambda rng: bell_sfx(rng, "tower"), 2, -3.0, 0.02),
        "bell_toll": _e(lambda rng: bell_sfx(rng, "toll"), 2, -1.0, 0.01),
        "hearthstone_rest": _e(lambda rng: hearth_chime(rng), 2, -4.0, 0.02, bus="UI"),
        "echo_recovered": _e(lambda rng: echo_tone(rng), 2, -4.0, 0.02, bus="UI"),
        "player_death": _e(lambda rng: death_sound(rng), 2, -2.0, 0.01, bus="UI"),
    })
    for school in ("kindling", "hush", "binding", "mending", "calling"):
        c["spell_cast_%s" % school] = _e(lambda rng, s=school: spell_cast(rng, s), 3, -5.0, 0.05)
        c["spell_impact_%s" % school] = _e(lambda rng, s=school: spell_impact(rng, s), 3, -4.0, 0.06)
    for kind in ("paper_slide", "page_turn", "book_open", "book_close", "map_unroll",
                 "brass_click", "hover_tick", "error_thunk"):
        c["ui_%s" % kind] = _e(lambda rng, k=kind: ui_sound(rng, k),
                               5 if kind in ("hover_tick", "brass_click") else 3,
                               -12.0 if kind == "hover_tick" else -9.0, 0.05, bus="UI")
    return c


CATALOGUE = _catalogue()


# =================================================================================================
# Rendering and the content table
# =================================================================================================

def res_path(abs_path: str) -> str:
    return os.path.relpath(abs_path, os.path.join(ROOT, "game")).replace(os.sep, "/")


def build(only=None, force: bool = False) -> dict:
    manifest = {}
    t_all = time.time()
    for name, spec in CATALOGUE.items():
        if only and name not in only:
            continue
        out_dir = os.path.join(OUT_ROOT, name)
        existing = sorted(f for f in os.listdir(out_dir) if f.endswith(".ogg")) \
            if os.path.isdir(out_dir) else []
        if existing and len(existing) == spec["count"] and not force:
            manifest[name] = _reuse(name, spec, out_dir, existing)
            continue
        t0 = time.time()
        paths, lens, lufs = [], [], []
        for i in range(spec["count"]):
            rng = core.rng(core.sub_seed("sfx", name, i))
            y = core.to_mono(spec["fn"](rng, **spec.get("kw", {})))
            y = render.mixdown(y, peak_db=PEAK_DB, target_lufs=None, limit=False, hp=35.0)
            y = _trim_silence(y)
            p = os.path.join(out_dir, "%s_%02d.ogg" % (name, i + 1))
            render.write_ogg(p, y, quality=OGG_QUALITY)
            render.write_ogg_import(p, res_path(p), loop=False)
            paths.append("res://" + res_path(p))
            lens.append(len(y) / SR)
            lufs.append(render.loudness_lufs(y))
        manifest[name] = {
            "files": paths, "count": spec["count"], "volume_db": spec["volume_db"],
            "pitch_variance": spec["pitch_variance"], "bus": spec["bus"],
            "seconds": round(float(np.mean(lens)), 3),
            "lufs": round(float(np.mean(lufs)), 2),
            "bytes": sum(os.path.getsize(os.path.join(out_dir, f))
                         for f in os.listdir(out_dir) if f.endswith(".ogg")),
        }
        print("[sfx] %-24s %d x %5.2f s  %5.1f LUFS  %5.0f kB  (%.1f s)" % (
            name, spec["count"], manifest[name]["seconds"], manifest[name]["lufs"],
            manifest[name]["bytes"] / 1000.0, time.time() - t0))
    render.save_manifest(os.path.join(OUT_ROOT, "manifest.json"), manifest)
    _write_table(manifest)
    total = sum(v["bytes"] for v in manifest.values())
    print("[sfx] %d entries, %d files, %.1f MB in %.0f s" % (
        len(manifest), sum(v["count"] for v in manifest.values()), total / 1e6,
        time.time() - t_all))
    return manifest


def _reuse(name, spec, out_dir, existing) -> dict:
    return {"files": ["res://" + res_path(os.path.join(out_dir, f)) for f in existing],
            "count": spec["count"], "volume_db": spec["volume_db"],
            "pitch_variance": spec["pitch_variance"], "bus": spec["bus"],
            "bytes": sum(os.path.getsize(os.path.join(out_dir, f)) for f in existing)}


def _write_table(manifest: dict) -> None:
    """core:table/sfx -- what Foley looks an id up in."""
    rows = {}
    for name, v in sorted(manifest.items()):
        rows[name] = {"files": v["files"], "volume_db": v["volume_db"],
                      "pitch_variance": v["pitch_variance"], "bus": v["bus"]}
    table = {
        "id": "core:table/sfx",
        "name": "Sound effects",
        "description": "id -> variant files, level, pitch variance and bus. Foley.play(id) and "
                       "Foley.footstep(surface, position) read this.",
        "rows": rows,
    }
    os.makedirs(PACK_DIR, exist_ok=True)
    with open(os.path.join(PACK_DIR, "sfx.json"), "w") as f:
        json.dump(table, f, indent=2, sort_keys=True)
        f.write("\n")
    print("[sfx] wrote core:table/sfx with %d rows" % len(rows))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", nargs="*")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()
    if args.list:
        for k, v in CATALOGUE.items():
            print("%-26s %d variants  %+.0f dB  bus=%s" % (k, v["count"], v["volume_db"], v["bus"]))
        print("%d entries, %d files" % (len(CATALOGUE), sum(v["count"] for v in CATALOGUE.values())))
        return 0
    build(only=args.only, force=args.force)
    return 0


if __name__ == "__main__":
    sys.exit(main())
