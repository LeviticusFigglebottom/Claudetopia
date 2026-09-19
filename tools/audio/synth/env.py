"""Envelopes and control signals."""
from __future__ import annotations

import numpy as np
from scipy import signal

from .core import SR, TWO_PI, samples


def adsr(dur: float, a: float = 0.01, d: float = 0.1, s: float = 0.7, r: float = 0.3,
         curve: float = 2.0, total: float | None = None) -> np.ndarray:
    """ADSR for a note held `dur` seconds; the release runs after. Returns length dur+r (or total).
    curve>1 makes attack/decay/release exponential-ish (natural), 1 is linear."""
    na, nd, nr = samples(a), samples(d), samples(r)
    nhold = max(samples(dur), 1)
    n_total = samples(total) if total is not None else nhold + nr
    n_total = max(n_total, 1)
    env = np.zeros(n_total)
    pos = 0
    if na > 0:
        x = np.linspace(0.0, 1.0, na, endpoint=False)
        seg = 1.0 - (1.0 - x) ** curve
        end = min(na, n_total)
        env[:end] = seg[:end]
        pos = end
    if nd > 0 and pos < n_total:
        x = np.linspace(0.0, 1.0, nd, endpoint=False)
        seg = s + (1.0 - s) * (1.0 - x) ** curve
        end = min(pos + nd, n_total)
        env[pos:end] = seg[:end - pos]
        pos = end
    if nhold > pos:
        env[pos:min(nhold, n_total)] = s
    if nhold < n_total:
        level = env[nhold - 1] if nhold > 0 else s
        nr_eff = min(nr, n_total - nhold) if nr > 0 else 0
        if nr_eff > 0:
            x = np.linspace(0.0, 1.0, nr_eff, endpoint=False)
            env[nhold:nhold + nr_eff] = level * (1.0 - x) ** curve
    return env


def expdecay(n: int, t60: float, start: float = 1.0) -> np.ndarray:
    """Exponential decay reaching -60 dB after t60 seconds."""
    k = np.log(1000.0) / max(t60 * SR, 1.0)
    return start * np.exp(-k * np.arange(n))


def perc(n: int, attack: float = 0.002, t60: float = 0.5) -> np.ndarray:
    """Percussive envelope: quick attack then exponential decay."""
    e = expdecay(n, t60)
    na = max(samples(attack), 1)
    if na < n:
        e[:na] *= np.linspace(0.0, 1.0, na)
    return e


def segments(points, n: int | None = None) -> np.ndarray:
    """Piecewise-linear envelope from [(time_s, value), ...]."""
    ts = np.array([p[0] for p in points], dtype=np.float64)
    vs = np.array([p[1] for p in points], dtype=np.float64)
    n = n or samples(ts[-1])
    t = np.arange(n) / SR
    return np.interp(t, ts, vs)


def lfo(n: int, rate_hz: float, shape: str = "sine", phase0: float = 0.0, depth: float = 1.0,
        offset: float = 0.0) -> np.ndarray:
    t = np.arange(n) / SR
    ph = np.mod(t * rate_hz + phase0, 1.0)
    if shape == "sine":
        y = np.sin(TWO_PI * ph)
    elif shape == "tri":
        y = 1.0 - 4.0 * np.abs(ph - 0.5)
    elif shape == "saw":
        y = 2.0 * ph - 1.0
    elif shape == "square":
        y = np.where(ph < 0.5, 1.0, -1.0)
    else:
        raise ValueError(shape)
    return offset + depth * y


def smooth(x: np.ndarray, ms: float = 20.0) -> np.ndarray:
    """One-pole smoothing for control signals (removes zipper noise)."""
    if len(x) == 0:
        return x
    k = np.exp(-1.0 / max(ms * 0.001 * SR, 1.0))
    return signal.lfilter([1.0 - k], [1.0, -k], x, zi=[x[0] * k])[0]


def wander(n: int, rng: np.random.Generator, rate_hz: float = 0.3, depth: float = 1.0) -> np.ndarray:
    """Slow random drift in [-depth, depth]: interpolated low-rate noise (humanised pitch/level)."""
    steps = max(int(n * rate_hz / SR) + 3, 3)
    pts = rng.standard_normal(steps)
    y = np.interp(np.linspace(0, steps - 1, n), np.arange(steps), pts)
    y = smooth(y, ms=min(1000.0 / max(rate_hz, 0.01) * 0.25, 2000.0))
    m = np.max(np.abs(y)) + 1e-9
    return y / m * depth


def gate_bursts(n: int, rng: np.random.Generator, rate_hz: float, duty: float = 0.5,
                jitter: float = 0.3) -> np.ndarray:
    """Irregular on/off gate (pulse trains for frogs, crickets, woodpeckers)."""
    out = np.zeros(n)
    t = 0.0
    period = 1.0 / max(rate_hz, 1e-3)
    while t < n / SR:
        p = period * (1.0 + jitter * rng.uniform(-1, 1))
        on = int(p * duty * SR)
        s = int(t * SR)
        out[s:min(s + on, n)] = 1.0
        t += p
    return out
