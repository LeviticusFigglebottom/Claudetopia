#!/usr/bin/env python3
"""Render Wickmere's ambience: the beds and one-shot pools the AmbienceMixer layers.

Every `identity.ambience` key in regions.json gets either a seamless bed (a continuous texture
that loops for 30-60 s) or a pool of one-shots (a bird, a bell, a creak) that the mixer
schedules at random gaps. Weather and time-of-day layers are separate files so the mixer can
follow Atmosphere.weather_params() and WorldClock without re-rendering anything.

    python3 tools/audio/gen_ambience.py
    python3 tools/audio/gen_ambience.py --only skylark rain_heavy --force
    python3 tools/audio/gen_ambience.py --list

Output: game/assets/audio/ambience/<key>/*.ogg plus manifest.json.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from synth import core, env, filters, fx, instruments as inst, osc, render  # noqa: E402
from synth.core import SR, midi_to_hz, samples  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT_ROOT = os.path.join(ROOT, "game", "assets", "audio", "ambience")

BED_SECONDS = 42.0         # long enough that the ear does not hear the repeat
BED_LUFS = -30.0           # a bed sits under everything; the mixer raises it if it needs to
ONESHOT_LUFS = -26.0
OGG_QUALITY_BED = 4.0
OGG_QUALITY_SHOT = 3.0     # mono one-shots, mostly noisy: quality 3 is plenty


# =================================================================================================
# Building blocks
# =================================================================================================

def wind(seconds: float, rng, strength: float = 0.5, height: float = 0.5, gustiness: float = 0.6,
         stereo: bool = True) -> np.ndarray:
    """Wind: filtered noise whose band and level breathe. `height` moves it from a low moan
    (a valley) to a thin whistle over stone (the Skerrow tops)."""
    n = samples(seconds)
    base = osc.brown(n, rng) * 0.6 + osc.pink(n, rng) * 0.4
    # Three gust envelopes at different rates, so gusts never arrive on a schedule, and a
    # power curve on the sum so the lulls between them are genuinely quiet. Wind that only
    # breathes a few dB reads as a static wall of noise however long the loop is.
    g1 = env.wander(n, rng, 0.035 + 0.04 * gustiness, 1.0)
    g2 = env.wander(n, rng, 0.13 + 0.18 * gustiness, 0.7)
    g3 = env.wander(n, rng, 0.45 + 0.5 * gustiness, 0.35)
    # The floor matters as much as the depth: wind that falls away to nothing sounds broken,
    # not calm. These give roughly a 13-17 dB swell, which reads as weather rather than as a
    # fader being moved.
    gust = np.clip(0.40 + 0.34 * g1 + 0.22 * g2 + 0.12 * g3, 0.10, 1.7) ** (1.0 + 0.25 * gustiness)
    gust = env.smooth(gust, 90.0)
    # wind is brighter when it blows harder, so the band opens with the gust rather than
    # sitting still; the two bands overlap so there is no notch between them
    centre = 260.0 + 820.0 * height + 900.0 * gust * (0.5 + height)
    y = filters.svf(base, np.clip(centre, 120.0, 9000.0), 0.7 + 0.5 * height, "lp", block=256)
    upper = filters.bandpass(base, 700.0 + 1500.0 * height, 0.8 + 0.5 * height)
    y = y + upper * (0.14 + 0.45 * height) * (0.4 + 0.9 * gust)
    y = y * gust * (0.5 + 1.1 * strength)
    y = filters.highpass(y, 40.0 + 60.0 * height, 0.7)
    if not stereo:
        return y
    # the two ears never hear the same gust: decorrelate, then let the gusts drift across
    st = fx.decorrelate(y, seed=int(rng.integers(1 << 30)), ms=32.0)
    sway = env.wander(n, rng, 0.04, 0.5)
    return np.stack([st[:, 0] * (1.0 - 0.3 * sway), st[:, 1] * (1.0 + 0.3 * sway)], axis=1)


def rain(seconds: float, rng, intensity: float = 0.6, surface: str = "leaves") -> np.ndarray:
    """Rain as two things at once: the hiss of many drops far off, and near drops hitting a
    surface. The surface is what tells the player where they are standing."""
    n = samples(seconds)
    hiss = osc.white(n, rng)
    hiss = filters.bandpass(hiss, 2600.0 + 2200.0 * intensity, 0.5) * 0.7 + \
        filters.highpass(hiss, 5000.0) * 0.5
    hiss *= 0.25 + 0.75 * intensity
    # slow variation: rain comes in waves
    hiss *= np.clip(0.75 + 0.35 * env.wander(n, rng, 0.08, 1.0), 0.2, 1.5)
    density = 60.0 + 900.0 * intensity ** 1.4
    drops = osc.crackle(n, rng, density, 4.0, 1.2)
    if surface == "leaves":
        drops = filters.bandpass(drops, 1700.0, 0.8) + filters.bandpass(drops, 3800.0, 1.2) * 0.5
    elif surface == "stone":
        drops = filters.bandpass(drops, 3200.0, 1.1) + filters.highpass(drops, 6000.0) * 0.7
    elif surface == "water":
        drops = filters.bandpass(drops, 900.0, 1.6) + filters.bandpass(drops, 2200.0, 2.0) * 0.6
    elif surface == "canvas":
        drops = filters.bandpass(drops, 420.0, 1.1) + filters.bandpass(drops, 1400.0, 1.0) * 0.5
    y = hiss * 0.55 + drops * (0.4 + 0.5 * intensity)
    y = filters.highpass(y, 120.0, 0.7)
    return fx.decorrelate(y, seed=int(rng.integers(1 << 30)), ms=18.0)


def water_lap(seconds: float, rng, size: float = 0.5, stereo: bool = True) -> np.ndarray:
    """Water moving against a shore: broad slow swells with a fizz of small breaks on top."""
    n = samples(seconds)
    swell_rate = 0.55 - 0.3 * size
    body = osc.brown(n, rng)
    body = filters.lowpass(body, 420.0 - 160.0 * size, 0.8)
    swell = np.clip(0.3 + 0.9 * np.abs(env.wander(n, rng, swell_rate, 1.0)), 0.0, 1.6)
    body = body * swell
    fizz = osc.white(n, rng)
    fizz = filters.bandpass(fizz, 2600.0, 0.6) * env.smooth(np.maximum(swell - 0.55, 0.0), 120.0)
    y = body * 0.8 + fizz * 0.5
    y = filters.highpass(y, 55.0, 0.7)
    return fx.decorrelate(y, seed=int(rng.integers(1 << 30)), ms=26.0) if stereo else y


def water_still(seconds: float, rng) -> np.ndarray:
    """Standing water: almost nothing, with occasional small movements and a hollow ring."""
    n = samples(seconds)
    bed = filters.lowpass(osc.brown(n, rng), 260.0, 0.7) * 0.5
    moves = osc.crackle(n, rng, 2.2, 22.0, 1.5)
    moves = filters.bandpass(moves, 700.0, 1.4) + filters.bandpass(moves, 1600.0, 2.2) * 0.5
    y = bed + moves * 0.35
    return fx.decorrelate(filters.highpass(y, 50.0), seed=int(rng.integers(1 << 30)), ms=30.0)


def drip(seconds: float, rng, rate_hz: float = 0.8, pitch: float = 1100.0) -> np.ndarray:
    """Water falling into water: a small pitched blip that rises as the cavity closes."""
    n = samples(seconds)
    out = np.zeros(n)
    t = 0.0
    while t < seconds:
        s = samples(t)
        dur = 0.13
        k = samples(dur)
        f0 = pitch * rng.uniform(0.6, 1.5)
        sweep = f0 * np.linspace(1.0, 2.1, k) ** 1.4
        blip = osc.sine(sweep, k) * env.perc(k, 0.0012, 0.05)
        body = filters.bandpass(osc.white(k, rng) * env.perc(k, 0.0005, 0.012), f0 * 2.2, 1.0)
        seg = (blip * 0.8 + body * 0.35) * rng.uniform(0.4, 1.0)
        if s + k <= n:
            out[s:s + k] += seg
        t += (1.0 / rate_hz) * rng.uniform(0.35, 2.4)
    return out


def soft_drop(rng) -> np.ndarray:
    """A single drop into still water: a short low plink whose pitch lifts a little, and the
    small splash under it."""
    k = samples(0.7)  # the loudness gate needs 400 ms to measure it
    f0 = float(rng.uniform(480.0, 820.0))
    m = samples(0.09)
    sweep = f0 * np.linspace(1.0, 1.35, m) ** 1.2
    blip = osc.sine(sweep, m) * env.perc(m, 0.003, 0.07)
    out = np.zeros(k)
    out[:m] += blip * 0.7
    splash = filters.bandpass(osc.pink(k, rng), f0 * 1.8, 0.9) * env.perc(k, 0.002, 0.05)
    out += splash * 0.25
    # the ring on the water after it
    out[m:] += filters.lowpass(osc.brown(k - m, rng), 500.0, 0.7) * env.perc(k - m, 0.02, 0.3) * 0.04
    return filters.lowpass(out, 3200.0, 0.7)


def insects(seconds: float, rng, kind: str = "crickets", density: float = 0.6) -> np.ndarray:
    """Night crickets across a field: each a soft pure chirp of three or four pulses, a couple
    of times a second, coming and going through the night, most of them some way off.

    Triage 2026-09-27 #53: the chirps were white noise through a Q-22 band-pass at 3.6-6.4 kHz,
    fifteen voices with every one of them on -- an insect whine in both ears all night, heard
    bare whenever the music rests. A cricket's note is nearly a sine."""
    n = samples(seconds)
    left, right = np.zeros(n), np.zeros(n)
    voices = int(4 + 6 * density)
    for _ in range(voices):
        f = rng.uniform(3300.0, 4700.0)
        far = float(rng.uniform(0.3, 1.0))
        pulses = int(rng.integers(3, 5))
        rate = rng.uniform(1.2, 2.6)          # chirps a second
        out = np.zeros(n)
        # one chirp: the pulses as a shallow ripple on a rounded swell, not as gated bursts
        chirp_k = samples(pulses * 0.026 + 0.03)
        tt = np.arange(chirp_k) / SR
        chirp = osc.sine(f, chirp_k) * np.hanning(chirp_k) * (0.7 + 0.3 * np.cos(2.0 * np.pi * tt / 0.026))
        t = float(rng.uniform(0.0, 1.0 / rate))
        while t < seconds:
            s = samples(t)
            if s + chirp_k < n:
                out[s:s + chirp_k] += chirp
            t += (1.0 / rate) * float(rng.uniform(0.85, 1.15))
        # each cricket stops and starts through the night
        presence = np.clip(env.wander(n, rng, 0.03, 1.0) + 0.3, 0.0, 1.0)
        out = filters.lowpass(out * presence, 6500.0 - 2500.0 * far, 0.7) * (1.0 - 0.6 * far)
        p = rng.uniform(-1.0, 1.0)
        a = (p + 1.0) * 0.25 * np.pi
        amp = rng.uniform(0.4, 1.0) / np.sqrt(voices)
        left += out * np.cos(a) * amp
        right += out * np.sin(a) * amp
    # the night air under them
    air = filters.lowpass(osc.brown(n, rng), 400.0, 0.7)
    air = air / (np.max(np.abs(air)) + 1e-12) * 0.02
    return np.stack([left + air, right + np.roll(air, samples(0.023))], axis=1)


def quiet_floor(n: int, rng, lowpass_hz: float = 380.0, peak: float = 0.004) -> np.ndarray:
    """What a place sounds like between its events: a whisper of air or water far under them.

    A bed made only of events (frogs, creaking ropes, clinking chains) fell to digital silence
    between them -- up to nine seconds of it (tools/audio/audit.py) -- and a bed at -inf is the
    world switching off, which is exactly what silence_bed exists to avoid. Scaled to `peak`,
    some thirty dB under the events; drawn after them, so the events are the ones they were.
    """
    y = filters.lowpass(osc.brown(n, rng), lowpass_hz, 0.7)
    return y / (np.max(np.abs(y)) + 1e-12) * peak


def soft_frog_call(rng, f0: float, pulses: int, rate: float) -> np.ndarray:
    """One call of a frog across the water: a few rounded pulses, each a sine with two soft
    harmonics and a small fall in pitch, under a smooth window.

    Triage 2026-09-27 #53 ("a very weird ambient noise of buzzing and glitching" at Moreva): the
    croak this replaced was a pulse-width square wave through a formant bank, chopped at 9-20 Hz
    by a gate with 3 ms edges -- a buzz cut into a stutter, from thirteen voices, all night.
    """
    pulse = float(rng.uniform(0.07, 0.12))
    gap = 1.0 / rate
    k = samples(gap * (pulses - 1) + pulse + 0.02)
    out = np.zeros(k)
    for i in range(pulses):
        s = samples(i * gap * float(rng.uniform(0.94, 1.06)))
        m = samples(pulse)
        if s + m > k:
            break
        f = f0 * float(rng.uniform(0.98, 1.02)) * np.linspace(1.03, 0.95, m)
        tone = osc.sine(f, m) + 0.28 * osc.sine(f * 2.0, m) + 0.07 * osc.sine(f * 3.0, m)
        out[s:s + m] += tone * np.hanning(m) * (1.0 - 0.2 * i / max(pulses, 1))
    return out


def frogs_bed(seconds: float, rng, density: float = 0.6) -> np.ndarray:
    """Marsh frogs: a few voices calling now and then across the water, most of them far off.

    Each call is soft_frog_call, darkened by its distance (a far frog keeps only its
    fundamental), and the marsh's slow water runs under all of them (quiet_floor)."""
    n = samples(seconds)
    left, right = np.zeros(n), np.zeros(n)
    voices = int(3 + 5 * density)
    for _ in range(voices):
        far = float(rng.uniform(0.35, 1.0))
        f0 = float(rng.uniform(170.0, 400.0))
        out = np.zeros(n)
        t = float(rng.uniform(0.0, 8.0))
        while t < seconds:
            call = soft_frog_call(rng, f0, int(rng.integers(2, 6)), float(rng.uniform(3.5, 7.0)))
            s = samples(t)
            if s + len(call) >= n:
                break
            out[s:s + len(call)] += call * float(rng.uniform(0.5, 1.0))
            t += float(rng.uniform(3.0, 12.0))
        out = filters.lowpass(out, 2400.0 - 1500.0 * far, 0.7, order=2) * (1.0 - 0.55 * far)
        p = float(rng.uniform(-0.9, 0.9))
        a = (p + 1.0) * 0.25 * np.pi
        amp = 0.5 / np.sqrt(voices)
        left += out * np.cos(a) * amp
        right += out * np.sin(a) * amp
    # Between calls a marsh is still a marsh: slow water under everything (quiet_floor).
    floor = quiet_floor(n, rng, 380.0, 0.012)
    left += floor
    right += np.roll(floor, samples(0.021))
    return np.stack([left, right], axis=1)


def marsh_night(seconds: float, rng) -> np.ndarray:
    """The Delta before dawn (Sedgemire's night layer): water lapping at the stilts, the reeds
    moving, and a frog or two a long way off. No insects: the whine of a marsh's insects, as
    the narrow-band chirp trains of `insects(..., "marsh")` at 9-16 Hz, was the buzz the
    Rogue's start was heard with (triage 2026-09-27 #53)."""
    n = samples(seconds)
    # small water against the piles: a slow dark swell, no fizz on top
    water = filters.lowpass(water_lap(seconds, rng, size=0.25, stereo=False), 1800.0, 0.7, order=2)
    # a lap against a post now and then: a soft hollow knock, low and rounded
    laps = np.zeros(n)
    t = float(rng.uniform(0.3, 2.0))
    while t < seconds:
        k = samples(0.35)
        s = samples(t)
        if s + k >= n:
            break
        hit = filters.bandpass(osc.pink(k, rng), float(rng.uniform(260.0, 520.0)), 1.6)
        laps[s:s + k] += hit * env.segments([(0, 0), (0.012, 1.0), (0.35, 0.0)], k) ** 2 * float(rng.uniform(0.3, 1.0))
        t += float(rng.uniform(1.4, 4.5))
    # the reeds: a high soft hiss that comes and goes with the air
    reeds = filters.lowpass(filters.bandpass(osc.pink(n, rng), 2600.0, 0.5), 5500.0, 0.7)
    reeds = reeds * np.clip(0.25 + 0.75 * np.abs(env.wander(n, rng, 0.07, 1.0)), 0.1, 1.0)
    # a far frog or two, darker still than the frogs bed's
    frogs = np.zeros(n)
    t = float(rng.uniform(2.0, 9.0))
    while t < seconds:
        call = soft_frog_call(rng, float(rng.uniform(160.0, 300.0)), int(rng.integers(2, 5)),
                              float(rng.uniform(3.0, 5.5)))
        s = samples(t)
        if s + len(call) >= n:
            break
        frogs[s:s + len(call)] += call * float(rng.uniform(0.4, 1.0))
        t += float(rng.uniform(6.0, 16.0))
    frogs = filters.lowpass(frogs, 800.0, 0.7, order=2)

    def unit(y):
        return y / (np.sqrt(np.mean(y * y)) + 1e-12)
    y = unit(water) * 1.0 + unit(laps) * 0.30 + unit(reeds) * 0.22 + unit(frogs) * 0.22
    return fx.decorrelate(filters.highpass(y, 45.0), seed=int(rng.integers(1 << 30)), ms=30.0)


def leaves(seconds: float, rng, broad: bool = True, strength: float = 0.5) -> np.ndarray:
    """Leaves in wind: many tiny transients gated by the gusts. Broad leaves rustle lower and
    wetter than a high conifer canopy."""
    n = samples(seconds)
    gust = np.clip(0.3 + 0.75 * env.wander(n, rng, 0.11, 1.0) + 0.3 * env.wander(n, rng, 0.5, 0.6),
                   0.0, 1.8)
    grain = osc.crackle(n, rng, 2600.0 * (0.4 + strength), 1.6, 1.8)
    band = (1500.0, 1.0) if broad else (3400.0, 0.8)
    y = filters.bandpass(grain, band[0], band[1]) + filters.bandpass(grain, band[0] * 2.4, 1.4) * 0.5
    y = y * gust * (0.4 + 0.8 * strength)
    y += filters.bandpass(osc.white(n, rng), band[0] * 1.6, 0.6) * gust * 0.12
    return fx.decorrelate(filters.highpass(y, 260.0), seed=int(rng.integers(1 << 30)), ms=22.0)


def bees(seconds: float, rng, density: float = 0.5) -> np.ndarray:
    """Bees at the flowers, a few steps off: a soft hum that swells as one comes near and is
    gone most of the time.

    Triage 2026-09-27 #53: this was a sawtooth and a square wave per bee, all of them always
    sounding -- a bright buzz and a drone under the whole Hearthvale day, heard bare whenever
    the music rests. A bee's wing note is a sine with a few soft partials; it wavers, and it
    carries only when it is close."""
    n = samples(seconds)
    left, right = np.zeros(n), np.zeros(n)
    voices = int(2 + 4 * density)
    for _ in range(voices):
        f = rng.uniform(170.0, 240.0)
        fr = f * (1.0 + env.wander(n, rng, 5.0, 0.03) + env.wander(n, rng, 0.4, 0.05))
        body = osc.sine(fr, n) + 0.3 * osc.sine(fr * 2.0, n) + 0.1 * osc.sine(fr * 3.0, n) \
            + 0.03 * osc.sine(fr * 4.0, n)
        # the bee comes and goes: mostly away, now and then close enough to hear
        near = np.clip(env.wander(n, rng, 0.08, 1.0) * 0.7 + 0.1, 0.0, 1.0) ** 2.5
        body = filters.svf(body, 500.0 + 1300.0 * near, 0.7, "lp", block=512) * near
        pan = env.wander(n, rng, 0.07, 0.9)
        a = (pan + 1.0) * 0.25 * np.pi
        amp = 0.35 / np.sqrt(voices)
        left += body * np.cos(a) * amp
        right += body * np.sin(a) * amp
    # the meadow's air between them, so the bed is never a hum on nothing
    air = filters.lowpass(osc.pink(n, rng), 700.0, 0.7, order=2)
    air = air / (np.sqrt(np.mean(air * air)) + 1e-12) * 0.004
    return np.stack([left + air, right + np.roll(air, samples(0.019))], axis=1)


def market_murmur(seconds: float, rng) -> np.ndarray:
    """A crowd heard as texture, not words: many formant-filtered voices moving slowly, with
    the odd call rising out of it. No speech is synthesised; nothing is intelligible.

    Each voice is breath and a soft triangle through a vowel, not a sawtooth: fourteen saws a
    few hertz apart read as a buzz, not as people (triage 2026-09-27 #53)."""
    n = samples(seconds)
    left, right = np.zeros(n), np.zeros(n)
    for _ in range(14):
        f0 = rng.uniform(95.0, 210.0)
        tone = osc.triangle(f0 * (1.0 + env.wander(n, rng, 2.2, 0.03)), n)
        breath = osc.pink(n, rng)
        breath = breath / (np.sqrt(np.mean(breath * breath)) + 1e-12) * 0.35
        src = tone * 0.6 + breath
        vowels = ["ah", "oh", "eh", "oo"]
        v = filters.vowel(src, vowels[int(rng.integers(0, len(vowels)))])
        # syllable-rate gating, smoothed so it is a murmur rather than a stutter
        gate = env.smooth(env.gate_bursts(n, rng, rng.uniform(2.6, 4.6), 0.45, 0.5), 45.0)
        presence = np.clip(env.wander(n, rng, 0.06, 1.0) + 0.3, 0.0, 1.0)
        voice = v * gate * presence
        p = rng.uniform(-1.0, 1.0)
        a = (p + 1.0) * 0.25 * np.pi
        amp = rng.uniform(0.3, 1.0) * 0.16 / np.sqrt(14)
        left += voice * np.cos(a) * amp
        right += voice * np.sin(a) * amp
    body = np.stack([left, right], axis=1)
    body = filters.bandpass(body, 700.0, 0.5) * 1.4 + body * 0.35
    body = filters.lowpass(body, 2600.0, 0.7)
    # room: a market is outdoors but between walls
    return fx.reverb(body, "chamber", mix=0.22, seed=int(rng.integers(1 << 30)), tail=False)


def fire_hiss(seconds: float, rng, intensity: float = 0.5) -> np.ndarray:
    """Ash settling and the last of a burn: a dry hiss with sparse ticks."""
    n = samples(seconds)
    hiss = filters.bandpass(osc.white(n, rng), 3200.0, 0.45) * 0.6
    hiss += filters.highpass(osc.white(n, rng), 7000.0) * 0.25
    hiss *= np.clip(0.55 + 0.5 * env.wander(n, rng, 0.14, 1.0), 0.1, 1.4) * (0.3 + intensity)
    ticks = osc.crackle(n, rng, 14.0 * intensity, 2.5, 2.0)
    ticks = filters.bandpass(ticks, 2400.0, 1.0) + filters.highpass(ticks, 5000.0) * 0.5
    y = hiss + ticks * 0.3
    return fx.decorrelate(filters.highpass(y, 400.0), seed=int(rng.integers(1 << 30)), ms=14.0)


def waterfall(seconds: float, rng, distance: float = 0.0) -> np.ndarray:
    """Falling water: broadband, steady, with slow movement. `distance` dulls and quietens it."""
    n = samples(seconds)
    y = osc.white(n, rng) * 0.6 + osc.pink(n, rng) * 0.5
    y = filters.bandpass(y, 1400.0 - 900.0 * distance, 0.4) * 0.8 + \
        filters.lowpass(y, 500.0 - 250.0 * distance, 0.7) * 0.6
    y *= np.clip(0.82 + 0.25 * env.wander(n, rng, 0.2, 1.0), 0.3, 1.4)
    if distance > 0:
        y = filters.lowpass(y, 2600.0 - 2000.0 * distance, 0.7) * (1.0 - 0.6 * distance)
    return fx.decorrelate(filters.highpass(y, 70.0), seed=int(rng.integers(1 << 30)), ms=34.0)


def rope_creak_bed(seconds: float, rng) -> np.ndarray:
    """Boardwalk ropes and stilts: now and then a slow, soft groan of wood, over water moving
    under the boards.

    The groan was a sawtooth with its level shaken by white noise smoothed over 2 ms: a rasp,
    close and bright, every 2-11 s (triage 2026-09-27 #53). It is a triangle now, its grain
    slower and shallower, darkened, further apart, and the water under it carries the bed."""
    n = samples(seconds)
    out = np.zeros(n)
    t = rng.uniform(0, 5)
    while t < seconds:
        dur = rng.uniform(0.6, 1.8)
        k = samples(dur)
        if samples(t) + k >= n:
            break
        f = rng.uniform(70.0, 190.0)
        # stick-slip, gently: a slow rising pitch with a little unevenness in the level
        sweep = f * np.linspace(1.0, rng.uniform(1.05, 1.35), k)
        grain = env.smooth(osc.white(k, rng), 14.0)
        grain = grain / (np.max(np.abs(grain)) + 1e-12)
        body = osc.triangle(sweep, k) * (0.8 + 0.2 * grain)
        body = filters.formant_bank(body, [(f * 2.5, 160, 1.0), (700, 400, 0.25)]) + body * 0.15
        body = filters.lowpass(body, 1300.0, 0.7, order=2)
        shape = env.segments([(0, 0), (dur * 0.35, 1.0), (dur * 0.7, 0.6), (dur, 0)], k) ** 1.5
        out[samples(t):samples(t) + k] += body * shape * rng.uniform(0.3, 0.8)
        t += rng.uniform(4.0, 14.0)
    out = out / (np.max(np.abs(out)) + 1e-12)
    # water moving under the boardwalk: a soft lapping that is the bed between the groans
    water = filters.lowpass(water_lap(seconds, rng, size=0.2, stereo=False), 1500.0, 0.7, order=2)
    water = water / (np.sqrt(np.mean(water * water)) + 1e-12) * 0.06
    y = out * 0.5 + water
    return fx.decorrelate(filters.highpass(y, 60.0), seed=int(rng.integers(1 << 30)), ms=28.0)


def chain_bed(seconds: float, rng) -> np.ndarray:
    """Chain bridges in wind: small metallic collisions, sometimes a whole run of them."""
    n = samples(seconds)
    out = np.zeros(n)
    t = rng.uniform(0, 3)
    while t < seconds:
        links = int(rng.integers(1, 7))
        for i in range(links):
            s = samples(t + i * rng.uniform(0.04, 0.16))
            if s >= n:
                break
            f = rng.uniform(1700.0, 4200.0)
            k = samples(0.4)
            exc = np.zeros(k)
            exc[:12] = osc.white(12, rng) * np.hanning(12)
            modes = [(f, 0.22, 1.0), (f * 1.73, 0.16, 0.6), (f * 2.41, 0.1, 0.35),
                     (f * 3.9, 0.07, 0.15)]
            hit = filters.modal(exc, modes) * rng.uniform(0.2, 0.9)
            m = min(len(hit), n - s)
            out[s:s + m] += hit[:m]
        t += rng.uniform(1.8, 9.0)
    # the wind the chains hang in, between the clinks (quiet_floor, kept bright: the
    # bed is high-passed at 700 Hz, and a floor of rumble would be filtered out of existence)
    out += quiet_floor(n, rng, 2400.0, 0.02)
    return fx.decorrelate(filters.highpass(out, 700.0), seed=int(rng.integers(1 << 30)), ms=20.0)


def silence_bed(seconds: float, rng) -> np.ndarray:
    """Cinderlea's near-silence: not digital silence, which sounds broken, but a very low room
    tone with the faintest movement, so the player hears that the world is still there."""
    n = samples(seconds)
    y = filters.lowpass(osc.brown(n, rng), 140.0, 0.7) * 0.5
    y += filters.bandpass(osc.pink(n, rng), 420.0, 0.5) * 0.06
    y *= np.clip(0.6 + 0.5 * env.wander(n, rng, 0.05, 1.0), 0.15, 1.3)
    return fx.decorrelate(filters.highpass(y, 32.0), seed=int(rng.integers(1 << 30)), ms=40.0)


def sustained_note_bed(seconds: float, rng) -> np.ndarray:
    """The Cantor's held note: an E under everything near the Seat, never quite steady.
    WORLD_BIBLE 1.1 -- a note that keeps its holder from ending."""
    n = samples(seconds)
    base = float(midi_to_hz(40))          # E2
    y = np.zeros(n)
    for mult, amp in ((1.0, 1.0), (2.0, 0.45), (3.0, 0.2), (4.03, 0.1), (5.98, 0.05)):
        drift = env.wander(n, rng, 0.03, 0.0012)
        beat = 1.0 + 0.04 * np.sin(2 * np.pi * rng.uniform(0.05, 0.16) * np.arange(n) / SR)
        y += osc.sine(base * mult * (1.0 + drift), n) * amp * beat
    y += inst.hum(52, seconds * 0.98, amp=0.28, rng=rng, attack=6.0, release=6.0)[:n] * 0.5
    y *= np.clip(0.75 + 0.3 * env.wander(n, rng, 0.02, 1.0), 0.3, 1.2)
    return fx.decorrelate(filters.lowpass(y, 2600.0), seed=int(rng.integers(1 << 30)), ms=45.0)


def thunder(seconds: float, rng, distance: float = 0.5) -> np.ndarray:
    """A thunder roll. Near: a crack then a long tumble. Far: only the tumble, dark and slow."""
    n = samples(seconds)
    body = osc.brown(n, rng) * 1.2
    # the roll is a sequence of overlapping rumbles
    envl = np.zeros(n)
    peaks = int(4 + 9 * (1.0 - distance))
    for i in range(peaks):
        at = rng.uniform(0.0, seconds * 0.7)
        w = rng.uniform(0.35, 1.9)
        k = samples(w)
        s = samples(at)
        if s + k > n:
            k = n - s
        if k <= 2:
            continue
        envl[s:s + k] += np.hanning(k) * rng.uniform(0.3, 1.0)
    envl = env.smooth(envl, 45.0)
    envl /= envl.max() + 1e-9
    y = filters.lowpass(body, 160.0 + 260.0 * (1.0 - distance), 0.8) * envl
    y += filters.bandpass(body, 420.0, 0.5) * envl * (0.3 * (1.0 - distance))
    if distance < 0.4:
        # the crack: a sharp broadband hit at the front
        k = samples(0.25)
        crack = osc.white(k, rng) * env.perc(k, 0.0008, 0.12)
        crack = filters.bandpass(crack, 900.0, 0.5) + filters.lowpass(crack, 300.0) * 1.2
        y[:k] += crack * (1.0 - distance) * 1.6
    y *= env.segments([(0, 1), (seconds * 0.6, 0.8), (seconds, 0.0)], n)
    return fx.decorrelate(filters.highpass(y, 25.0), seed=int(rng.integers(1 << 30)), ms=38.0)


# =================================================================================================
# One-shots: creatures and objects the mixer schedules at random gaps
# =================================================================================================

def bird_call(rng, kind: str = "skylark") -> np.ndarray:
    """A bird as a pitch contour: a swept whistle with a little noise and its own rhythm."""
    specs = {
        # (seconds, base Hz, syllables, sweep range, noisiness)
        "skylark": (2.4, 3600.0, 22, 0.5, 0.18),
        "woodpecker": (0.9, 1500.0, 12, 0.02, 0.85),   # a drum, not a song
        "owl": (1.9, 420.0, 2, 0.12, 0.10),
        "bittern": (2.6, 130.0, 3, 0.05, 0.22),
        "gull": (1.5, 1100.0, 3, 0.55, 0.35),
        "crow": (1.1, 700.0, 3, 0.25, 0.55),
        "small_bird": (1.2, 4200.0, 6, 0.6, 0.2),
    }
    dur, f0, syl, sweep, noisy = specs[kind]
    dur *= float(rng.uniform(0.85, 1.2))
    n = samples(dur)
    out = np.zeros(n)
    if kind == "woodpecker":
        # a drum roll on a dead branch
        hits = int(rng.integers(8, 18))
        gap = rng.uniform(0.028, 0.045)
        for i in range(hits):
            s = samples(i * gap)
            k = samples(0.035)
            if s + k >= n:
                break
            tick = inst.wood_block(0.035, amp=0.9, rng=rng, freq=rng.uniform(1300.0, 2100.0))
            out[s:s + min(k, len(tick))] += tick[:min(k, len(tick))] * (1.0 - i / hits * 0.4)
        return filters.highpass(out, 500.0)
    if kind == "owl":
        for i in range(2):
            s = samples(i * rng.uniform(0.55, 0.85))
            k = samples(0.42)
            if s + k >= n:
                break
            f = f0 * rng.uniform(0.94, 1.06) * (1.0 if i == 0 else 0.92)
            contour = f * (1.0 + sweep * np.concatenate([
                np.linspace(0.3, 0.0, k // 3), np.linspace(0.0, -0.12, k - k // 3)]))
            tone = osc.sine(contour, k) + 0.25 * osc.sine(contour * 2.0, k)
            breath = filters.bandpass(osc.white(k, rng), f * 3.0, 1.2) * noisy
            shape = env.segments([(0, 0), (0.06, 1.0), (0.3, 0.85), (0.42, 0.0)], k)
            out[s:s + k] += (tone * 0.6 + breath) * shape
        return filters.highpass(out, 150.0)
    if kind == "bittern":
        # the boom: three low pulses that carry miles over a marsh
        for i in range(syl):
            s = samples(i * rng.uniform(0.7, 0.95))
            k = samples(0.55)
            if s + k >= n:
                break
            f = f0 * rng.uniform(0.95, 1.05)
            # a hollow, blown boom: a sine and two soft partials (it was a square wave, a buzz)
            fr = f * (1.0 + 0.02 * env.wander(k, rng, 4.0, 1.0))
            boom = osc.sine(fr, k) + 0.35 * osc.sine(fr * 2.0, k) + 0.08 * osc.sine(fr * 3.0, k)
            shape = env.segments([(0, 0), (0.12, 1.0), (0.4, 0.8), (0.55, 0.0)], k)
            out[s:s + k] += boom * shape * (0.6 + 0.4 * i / max(syl - 1, 1))
        return filters.lowpass(filters.highpass(out, 60.0), 1200.0)
    # Whistled songs: a phrase of gliding syllables. Triage 2026-09-27 #53 heard the old ones as
    # glitching: every syllable jumped to an unrelated pitch (x0.75-1.3), bent up or down by as
    # much as 60 %, and was switched on and off under a window with near-vertical edges -- a
    # computer's bleeps, every few seconds, in every morning. Now each syllable follows the last
    # (a phrase walks, it does not leap), glides along a half-cosine, trills a little, and swells
    # in and out.
    pos = float(rng.uniform(0.0, 0.03))
    f = f0 * rng.uniform(0.85, 1.15)
    for i in range(syl):
        dur = rng.uniform(0.06, 0.16)
        k = samples(dur)
        s = samples(pos)
        if s + k >= n:
            break
        f = float(np.clip(f * rng.uniform(0.9, 1.12), f0 * 0.75, f0 * 1.3))
        glide = 0.5 - 0.5 * np.cos(np.linspace(0.0, np.pi, k))
        contour = f * (1.0 + rng.choice([-1.0, 1.0]) * sweep * 0.5 * glide)
        contour = contour * (1.0 + 0.012 * osc.sine(rng.uniform(18.0, 28.0), k))
        tone = osc.sine(contour, k) + 0.12 * osc.sine(contour * 2.0, k)
        noise = filters.bandpass(osc.white(k, rng), f, 4.0) * noisy * 0.6
        shape = np.hanning(k)
        out[s:s + k] += (tone * (1.0 - noisy * 0.4) + noise) * shape * rng.uniform(0.6, 1.0)
        pos += dur + rng.uniform(0.02, 0.12)
    out = filters.lowpass(out, 7000.0, 0.7)
    return filters.highpass(out, 400.0)


def buoy_bell(rng) -> np.ndarray:
    """A bell on a buoy: struck unevenly by the lake, never on a beat."""
    dur = 4.5
    y = inst.bell(70 + int(rng.integers(-2, 3)), dur, t60=3.2, amp=0.5, rng=rng, warmth=0.15)
    # it rocks: a second, softer strike sometimes follows
    if rng.random() < 0.45:
        s = samples(rng.uniform(0.25, 0.9))
        second = inst.bell(70, dur - s / SR, t60=2.6, amp=0.28, rng=rng, warmth=0.2)
        y[s:s + len(second)] += second
    return y


def bell_rare(rng) -> np.ndarray:
    """Cinderlea's bell: one every few minutes, enormous, a long way off."""
    y = inst.toll_bell(33 + int(rng.integers(-1, 2)), 14.0, amp=0.55, rng=rng)
    y = filters.lowpass(y, 2400.0, 0.7)
    return y


def hammer_distant(rng) -> np.ndarray:
    """A smith working somewhere below: a ring of strikes, dulled by distance and rock."""
    n = samples(3.2)
    out = np.zeros(n)
    hits = int(rng.integers(3, 7))
    t = 0.0
    for i in range(hits):
        s = samples(t)
        k = samples(0.8)
        if s + k >= n:
            break
        f = rng.uniform(520.0, 1000.0)
        exc = np.zeros(k)
        exc[:16] = osc.white(16, rng) * np.hanning(16)
        anvil = filters.modal(exc, [(f, 0.5, 1.0), (f * 2.76, 0.3, 0.5), (f * 5.4, 0.18, 0.2)])
        out[s:s + k] += anvil * (1.0 if i % 2 == 0 else 0.55) * rng.uniform(0.7, 1.0)
        t += rng.uniform(0.38, 0.62) * (1.0 if i % 2 == 0 else 0.6)
    out = filters.lowpass(out, 3000.0, 0.7) * 0.7
    return core.to_mono(fx.reverb(out, "cave", mix=0.5, seed=int(rng.integers(1 << 30)), tail=True))


def creak(rng, big: bool = True) -> np.ndarray:
    """Wood under load: a tree in the Briarwold, or a boardwalk plank. A slow groan with a
    little grain in it; it was a sawtooth shaken by white noise, a rasp (triage 2026-09-27 #53)."""
    dur = float(rng.uniform(0.8, 2.0))
    k = samples(dur)
    f = rng.uniform(70.0, 170.0) if big else rng.uniform(180.0, 380.0)
    sweep = f * np.linspace(1.0, rng.uniform(1.08, 1.45), k) ** rng.uniform(0.6, 1.5)
    grain = env.smooth(osc.white(k, rng), 14.0)
    grain = grain / (np.max(np.abs(grain)) + 1e-12)
    body = osc.triangle(sweep, k) * (0.8 + 0.2 * grain)
    body = filters.formant_bank(body, [(f * 2.5, 160, 1.0), (f * 5.0, 300, 0.2), (700, 400, 0.2)]) + body * 0.15
    body = filters.lowpass(body, 1400.0, 0.7, order=2)
    shape = env.segments([(0, 0), (dur * 0.3, 1.0), (dur * 0.75, 0.5), (dur, 0)], k) ** 1.5
    return filters.highpass(body * shape, 55.0)


def pipes_night(rng) -> np.ndarray:
    """Someone playing pipes on a crag at night: a short phrase, carried on the wind."""
    from synth import theory
    tonic, mode = 62, "mixolydian"
    degrees = [0, 2, 4, 2, 0, -3, 0]
    start = int(rng.integers(0, 3))
    dur_total = 6.0
    n = samples(dur_total)
    out = np.zeros(n)
    t = 0.0
    for i, d in enumerate(degrees[start:] + degrees[:start]):
        dur = float(rng.uniform(0.45, 1.1))
        s = samples(t)
        if s >= n:
            break
        note = inst.pipes(theory.degree_to_midi(d, tonic, mode), dur, amp=0.45, rng=rng,
                          reed=0.5, attack=0.06, release=0.3)
        m = min(len(note), n - s)
        out[s:s + m] += note[:m]
        t += dur * rng.uniform(0.85, 1.05)
    # the wind takes it away and brings it back
    out *= np.clip(0.35 + 0.8 * env.wander(n, rng, 0.35, 1.0), 0.05, 1.2)
    return core.to_mono(fx.reverb(out, "valley", mix=0.45, seed=int(rng.integers(1 << 30)), tail=True))


# =================================================================================================
# The catalogue: every ambience key in regions.json, plus weather and time layers
# =================================================================================================

def _bed(fn, **kw):
    return {"kind": "bed", "fn": fn, "kw": kw}


def _pool(fn, count=6, **kw):
    return {"kind": "pool", "fn": fn, "count": count, "kw": kw}


CATALOGUE = {
    # --- region ambience keys (regions.json identity.ambience) ---------------------------------
    "skylark": _pool(lambda rng, **k: bird_call(rng, "skylark"), count=8),
    "bees": _bed(lambda s, rng, **k: bees(s, rng, density=0.55)),
    "wind_soft": _bed(lambda s, rng, **k: wind(s, rng, strength=0.35, height=0.25, gustiness=0.45)),
    "leaves_broad": _bed(lambda s, rng, **k: leaves(s, rng, broad=True, strength=0.5)),
    "gulls": _pool(lambda rng, **k: bird_call(rng, "gull"), count=7),
    "water_lap": _bed(lambda s, rng, **k: water_lap(s, rng, size=0.4)),
    "market_murmur": _bed(lambda s, rng, **k: market_murmur(s, rng)),
    "buoy_bell": _pool(lambda rng, **k: buoy_bell(rng), count=5),
    "frogs": _bed(lambda s, rng, **k: frogs_bed(s, rng, density=0.6)),
    "bittern": _pool(lambda rng, **k: bird_call(rng, "bittern"), count=5),
    # A drip is a discrete event, not a texture: as a 42-second bed it was 94% digital
    # silence, which is both a waste of a file and worse than letting the mixer place
    # them with its own random gaps.
    # One drop per variant, low and short: a variant was four rising 0.6-1.6 kHz blips in 2.2 s,
    # fired every 1.5-7 s -- a bleeping, not water (triage 2026-09-27 #53).
    "drip": _pool(lambda rng, **k: soft_drop(rng), count=6),
    "rope_creak": _bed(lambda s, rng, **k: rope_creak_bed(s, rng)),
    "water_still": _bed(lambda s, rng, **k: water_still(s, rng)),
    "canopy_wind": _bed(lambda s, rng, **k: wind(s, rng, strength=0.5, height=0.7, gustiness=0.75)),
    "woodpecker": _pool(lambda rng, **k: bird_call(rng, "woodpecker"), count=6),
    "distant_falls": _bed(lambda s, rng, **k: waterfall(s, rng, distance=0.75)),
    "creak": _pool(lambda rng, **k: creak(rng, big=True), count=7),
    "owl": _pool(lambda rng, **k: bird_call(rng, "owl"), count=5),
    "wind_high": _bed(lambda s, rng, **k: wind(s, rng, strength=0.8, height=0.85, gustiness=0.8)),
    "chain_clink": _bed(lambda s, rng, **k: chain_bed(s, rng)),
    "waterfall": _bed(lambda s, rng, **k: waterfall(s, rng, distance=0.1)),
    "hammer_distant": _pool(lambda rng, **k: hammer_distant(rng), count=5),
    "pipes_night": _pool(lambda rng, **k: pipes_night(rng), count=4),
    "ash_hiss": _bed(lambda s, rng, **k: fire_hiss(s, rng, intensity=0.45)),
    "bell_rare": _pool(lambda rng, **k: bell_rare(rng), count=4),
    "silence_bed": _bed(lambda s, rng, **k: silence_bed(s, rng)),
    "sustained_note": _bed(lambda s, rng, **k: sustained_note_bed(s, rng)),

    # --- time of day --------------------------------------------------------------------------
    "night_insects": _bed(lambda s, rng, **k: insects(s, rng, "crickets", 0.6)),
    # Sedgemire's night: water, reeds and a far frog, not insects (triage 2026-09-27 #53)
    "marsh_night": _bed(lambda s, rng, **k: marsh_night(s, rng)),
    "dawn_chorus": _pool(lambda rng, **k: bird_call(rng, "small_bird"), count=8),
    "crows": _pool(lambda rng, **k: bird_call(rng, "crow"), count=6),

    # --- weather ------------------------------------------------------------------------------
    "rain_light": _bed(lambda s, rng, **k: rain(s, rng, 0.3, "leaves")),
    "rain_heavy": _bed(lambda s, rng, **k: rain(s, rng, 0.95, "leaves")),
    "rain_stone": _bed(lambda s, rng, **k: rain(s, rng, 0.7, "stone")),
    "rain_water": _bed(lambda s, rng, **k: rain(s, rng, 0.7, "water")),
    "rain_canvas": _bed(lambda s, rng, **k: rain(s, rng, 0.6, "canvas")),
    "wind_gust_light": _bed(lambda s, rng, **k: wind(s, rng, strength=0.45, height=0.4, gustiness=0.8)),
    "wind_gust_strong": _bed(lambda s, rng, **k: wind(s, rng, strength=1.0, height=0.6, gustiness=1.0)),
    "snow_hush": _bed(lambda s, rng, **k: _snow_hush(s, rng)),
    "thunder_near": _pool(lambda rng, **k: thunder(6.0, rng, distance=0.12), count=4),
    "thunder_far": _pool(lambda rng, **k: thunder(8.0, rng, distance=0.85), count=4),

    # --- interiors ----------------------------------------------------------------------------
    "room_tone": _bed(lambda s, rng, **k: _room_tone(s, rng)),
    "hearth_fire": _bed(lambda s, rng, **k: _hearth_fire(s, rng)),
}


def _snow_hush(seconds: float, rng) -> np.ndarray:
    """Snow does not make a sound; it takes them away. A very soft high bed with a dip in the
    mid where the world would otherwise be."""
    n = samples(seconds)
    y = filters.bandpass(osc.white(n, rng), 6200.0, 0.35) * 0.22
    y += filters.lowpass(osc.brown(n, rng), 180.0, 0.7) * 0.35
    y *= np.clip(0.7 + 0.35 * env.wander(n, rng, 0.07, 1.0), 0.2, 1.3)
    return fx.decorrelate(y, seed=int(rng.integers(1 << 30)), ms=36.0)


def _room_tone(seconds: float, rng) -> np.ndarray:
    """Inside: the low hum of a closed space, and the building settling."""
    n = samples(seconds)
    y = filters.lowpass(osc.brown(n, rng), 200.0, 0.7) * 0.5
    y += filters.bandpass(osc.pink(n, rng), 320.0, 0.6) * 0.1
    settle = osc.crackle(n, rng, 0.5, 30.0, 1.4)
    y += filters.bandpass(settle, 480.0, 1.2) * 0.25
    return fx.decorrelate(filters.highpass(y, 35.0), seed=int(rng.integers(1 << 30)), ms=26.0)


def _hearth_fire(seconds: float, rng) -> np.ndarray:
    """A fire in a grate: a body of noise, sparse pops, and the breath of the flame."""
    n = samples(seconds)
    body = filters.bandpass(osc.pink(n, rng), 700.0, 0.4) * 0.5
    body += filters.lowpass(osc.brown(n, rng), 300.0, 0.7) * 0.4
    body *= np.clip(0.6 + 0.55 * env.wander(n, rng, 0.35, 1.0), 0.15, 1.5)
    pops = osc.crackle(n, rng, 9.0, 3.0, 1.6)
    pops = filters.bandpass(pops, 1900.0, 0.9) + filters.highpass(pops, 4200.0) * 0.4
    y = body + pops * 0.45
    return fx.decorrelate(filters.highpass(y, 90.0), seed=int(rng.integers(1 << 30)), ms=18.0)


# =================================================================================================
# Rendering
# =================================================================================================

def render_bed(name: str, spec: dict, seconds: float = BED_SECONDS) -> np.ndarray:
    """A seamless bed. Rendered longer than the loop and crossfaded, so the texture running
    into its own start is genuinely continuous rather than merely quiet at both ends."""
    fade = 6.0
    rng = core.rng(core.sub_seed("ambience", name))
    y = spec["fn"](seconds + fade, rng, **spec.get("kw", {}))
    y = core.to_stereo(y)
    y = render.crossfade_loop(y, seconds, fade)
    y = render.mixdown(y, peak_db=-3.0, target_lufs=BED_LUFS, hp=22.0, loop=True)
    return y


def _trim_lead(y: np.ndarray, floor_db: float = -60.0, keep: float = 0.004) -> np.ndarray:
    """Drop what comes before the sound starts (below `floor_db` of its peak), keeping `keep`."""
    mag = np.abs(y)
    idx = np.flatnonzero(mag > core.db_to_lin(floor_db) * (mag.max() + 1e-12))
    if not len(idx):
        return y
    return y[max(0, int(idx[0]) - samples(keep)):]


def render_pool(name: str, spec: dict) -> list:
    """A pool of one-shot variants, each ending in silence so it can be triggered any time."""
    out = []
    for i in range(spec.get("count", 6)):
        rng = core.rng(core.sub_seed("ambience", name, i))
        y = spec["fn"](rng, **spec.get("kw", {}))
        y = core.to_mono(y)
        y = core.fade(y, 0.004, 0.06)
        y = render.mixdown(y, peak_db=-3.0, target_lufs=ONESHOT_LUFS, hp=30.0, limit=True)
        # A far thunder swelled up out of up to a second of nothing below -60 dB of its peak:
        # a second of latency on a sound that is already random, and a pool player held for it.
        # Trimmed after the mix, whose limiter moves the peak the threshold is measured from.
        y = core.fade(_trim_lead(y), 0.004, 0.0)
        out.append(y)
    return out


def res_path(abs_path: str) -> str:
    return os.path.relpath(abs_path, os.path.join(ROOT, "game")).replace(os.sep, "/")


def _load_manifest() -> dict:
    path = os.path.join(OUT_ROOT, "manifest.json")
    if not os.path.exists(path):
        return {}
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def build(only=None, force: bool = False) -> dict:
    # Start from what is already there: rendering one key with --only must not drop every
    # other entry from the manifest the game reads at startup.
    manifest = _load_manifest()
    for name, spec in CATALOGUE.items():
        if only and name not in only:
            continue
        out_dir = os.path.join(OUT_ROOT, name)
        t0 = time.time()
        if spec["kind"] == "bed":
            path = os.path.join(out_dir, "%s.ogg" % name)
            if os.path.exists(path) and not force:
                manifest[name] = _reuse_bed(name, path)
                continue
            y = render_bed(name, spec)
            render.write_ogg(path, y, quality=OGG_QUALITY_BED)
            render.write_ogg_import(path, res_path(path), loop=True)
            info = render.analyse(y)
            info.update(render.seam_report(y))
            manifest[name] = {"kind": "bed", "loop": True,
                              "files": ["res://" + res_path(path)],
                              "seconds": round(len(y) / SR, 3),
                              "bytes": os.path.getsize(path),
                              "lufs": round(info["lufs"], 2),
                              "peak_db": round(info["peak_db"], 2),
                              "seam_rms_db": round(info["seam_rms_db"], 3),
                              "seam_click_db": round(info["seam_click_db"], 2)}
            print("[amb] %-20s bed   %5.1f s  %5.1f LUFS  seam %4.2f dB  (%.0f s)" % (
                name, len(y) / SR, info["lufs"], info["seam_rms_db"], time.time() - t0))
        else:
            paths = []
            if os.path.isdir(out_dir) and not force:
                existing = sorted(f for f in os.listdir(out_dir) if f.endswith(".ogg"))
                if len(existing) == spec.get("count", 6):
                    manifest[name] = _reuse_pool(name, out_dir, existing)
                    continue
            variants = render_pool(name, spec)
            lufs = []
            for i, y in enumerate(variants):
                p = os.path.join(out_dir, "%s_%02d.ogg" % (name, i + 1))
                render.write_ogg(p, y, quality=OGG_QUALITY_SHOT)
                render.write_ogg_import(p, res_path(p), loop=False)
                paths.append("res://" + res_path(p))
                lufs.append(render.loudness_lufs(y))
            manifest[name] = {"kind": "pool", "loop": False, "files": paths,
                              "seconds": round(float(np.mean([len(v) / SR for v in variants])), 3),
                              "bytes": sum(os.path.getsize(os.path.join(out_dir, f))
                                           for f in os.listdir(out_dir) if f.endswith(".ogg")),
                              "lufs": round(float(np.mean(lufs)), 2)}
            print("[amb] %-20s pool  %d variants  %5.1f s avg  %5.1f LUFS  (%.0f s)" % (
                name, len(variants), manifest[name]["seconds"], manifest[name]["lufs"],
                time.time() - t0))
    render.save_manifest(os.path.join(OUT_ROOT, "manifest.json"), manifest)
    total = sum(v["bytes"] for v in manifest.values())
    print("[amb] %d entries, %.1f MB" % (len(manifest), total / 1e6))
    return manifest


def _reuse_bed(name: str, path: str) -> dict:
    return {"kind": "bed", "loop": True, "files": ["res://" + res_path(path)],
            "bytes": os.path.getsize(path)}


def _reuse_pool(name: str, out_dir: str, existing) -> dict:
    return {"kind": "pool", "loop": False,
            "files": ["res://" + res_path(os.path.join(out_dir, f)) for f in existing],
            "bytes": sum(os.path.getsize(os.path.join(out_dir, f)) for f in existing)}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", nargs="*")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()
    if args.list:
        for k, v in CATALOGUE.items():
            print("%-22s %s" % (k, v["kind"]))
        return 0
    t0 = time.time()
    build(only=args.only, force=args.force)
    print("[amb] done in %.0f s" % (time.time() - t0))
    return 0


if __name__ == "__main__":
    sys.exit(main())
