"""Oscillators and noise sources.

Saw/square/triangle are band-limited with PolyBLEP corrections and accept a per-sample
frequency array (vibrato, glides). `oversampled()` renders any generator at 2x/4x and
decimates, for signals that are then distorted.
"""
from __future__ import annotations

import numpy as np
from scipy import signal

from .core import SR, TWO_PI


def _freq_array(freq, n: int) -> np.ndarray:
    f = np.asarray(freq, dtype=np.float64)
    if f.ndim == 0:
        return np.full(n, float(f))
    if len(f) != n:
        f = np.interp(np.linspace(0, 1, n), np.linspace(0, 1, len(f)), f)
    return f


def phase(freq, n: int, phase0: float = 0.0, sr: int = SR):
    """Phase in cycles [0, 1) for a scalar or per-sample frequency, plus the per-sample increment."""
    f = _freq_array(freq, n)
    inc = f / sr
    ph = phase0 + np.cumsum(inc) - inc
    return np.mod(ph, 1.0), inc


def sine(freq, n: int, phase0: float = 0.0, sr: int = SR) -> np.ndarray:
    ph, _ = phase(freq, n, phase0, sr)
    return np.sin(TWO_PI * ph)


def _polyblep(t: np.ndarray, dt: np.ndarray) -> np.ndarray:
    """Two-sample polynomial band-limited step residual for discontinuities at t=0."""
    out = np.zeros_like(t)
    m = t < dt
    tt = t[m] / dt[m]
    out[m] = tt + tt - tt * tt - 1.0
    m2 = t > 1.0 - dt
    tt = (t[m2] - 1.0) / dt[m2]
    out[m2] = tt * tt + tt + tt + 1.0
    return out


def saw(freq, n: int, phase0: float = 0.0, sr: int = SR) -> np.ndarray:
    """Band-limited sawtooth (PolyBLEP), rising, -1..1."""
    ph, inc = phase(freq, n, phase0, sr)
    naive = 2.0 * ph - 1.0
    return naive - _polyblep(ph, np.maximum(inc, 1e-9))


def square(freq, n: int, pw: float = 0.5, phase0: float = 0.0, sr: int = SR) -> np.ndarray:
    """Band-limited pulse wave (PolyBLEP) with pulse width pw."""
    ph, inc = phase(freq, n, phase0, sr)
    inc = np.maximum(inc, 1e-9)
    naive = np.where(ph < pw, 1.0, -1.0)
    return naive + _polyblep(ph, inc) - _polyblep(np.mod(ph + (1.0 - pw), 1.0), inc)


def triangle(freq, n: int, phase0: float = 0.0, sr: int = SR) -> np.ndarray:
    """Triangle from an integrated band-limited square.

    The integrator starts at -1 (the value a symmetric triangle has when its square is about to
    rise), otherwise the first half cycle is an octave-long ramp to +2, and a DC blocker removes
    the slow drift the integration accumulates. Output is +/-1.
    """
    if n <= 0:
        return np.zeros(0)
    f = _freq_array(freq, n)
    sq = square(freq, n, 0.5, phase0, sr)
    scale = 4.0 * f / sr
    y = signal.lfilter([1.0], [1.0, -1.0], sq * scale, zi=np.array([-1.0]))[0]
    # remove the integrator's DC drift without touching the audio band
    r = 1.0 - 2.0 * np.pi * 5.0 / sr
    return signal.lfilter([1.0, -1.0], [1.0, -r], y)


def additive(freq: float, n: int, amps, phase0: float = 0.0, max_hz: float = 18000.0) -> np.ndarray:
    """Sum of harmonics with given amplitudes (harmonic k has amplitude amps[k-1]); fixed pitch."""
    t = np.arange(n) / SR
    out = np.zeros(n)
    for k, a in enumerate(amps, start=1):
        if freq * k > max_hz or a == 0.0:
            continue
        out += a * np.sin(TWO_PI * (freq * k * t + phase0 * k))
    return out


def additive_saw(freq: float, n: int, phase0: float = 0.0) -> np.ndarray:
    kmax = max(1, int(18000.0 / max(freq, 1.0)))
    amps = [(-1.0) ** (k + 1) * 2.0 / (np.pi * k) for k in range(1, kmax + 1)]
    return additive(freq, n, amps, phase0)


# --- noise --------------------------------------------------------------------------------

def white(n: int, rng: np.random.Generator) -> np.ndarray:
    return rng.standard_normal(n) * 0.35


def pink(n: int, rng: np.random.Generator) -> np.ndarray:
    """Pink noise (-3 dB/oct) via the Paul Kellet 3-pole approximation, normalised."""
    w = rng.standard_normal(n)
    b = [0.049922035, -0.095993537, 0.050612699, -0.004408786]
    a = [1.0, -2.494956002, 2.017265875, -0.522189400]
    p = signal.lfilter(b, a, w)
    return p / (np.std(p) + 1e-9) * 0.35


def brown(n: int, rng: np.random.Generator) -> np.ndarray:
    """Brown/red noise (-6 dB/oct): leaky integration of white, DC removed."""
    w = rng.standard_normal(n)
    y = signal.lfilter([1.0], [1.0, -0.999], w)
    y = y - np.mean(y)
    return y / (np.std(y) + 1e-9) * 0.35


def blue(n: int, rng: np.random.Generator) -> np.ndarray:
    """Blue noise (+3 dB/oct): differentiated pink."""
    p = pink(n, rng)
    y = np.diff(p, prepend=p[0])
    return y / (np.std(y) + 1e-9) * 0.35


def violet(n: int, rng: np.random.Generator) -> np.ndarray:
    w = rng.standard_normal(n)
    y = np.diff(w, prepend=w[0])
    return y / (np.std(y) + 1e-9) * 0.35


def noise(kind: str, n: int, rng: np.random.Generator) -> np.ndarray:
    return {"white": white, "pink": pink, "brown": brown, "blue": blue, "violet": violet}[kind](n, rng)


def crackle(n: int, rng: np.random.Generator, density_hz: float = 40.0, decay_ms: float = 3.0,
            spread: float = 1.0) -> np.ndarray:
    """Sparse random impulses with short exponential tails (fire, gravel, ash, vinyl)."""
    out = np.zeros(n)
    count = int(rng.poisson(density_hz * n / SR))
    if count == 0:
        return out
    pos = rng.integers(0, n, size=count)
    amp = rng.random(count) ** spread * rng.choice([-1.0, 1.0], size=count)
    np.add.at(out, pos, amp)
    k = int(decay_ms * 0.001 * SR)
    if k > 1:
        tail = np.exp(-np.arange(k) / (k / 5.0))
        out = signal.fftconvolve(out, tail)[:n]
    return out


# --- oversampling ---------------------------------------------------------------------------

def oversampled(fn, n: int, factor: int = 2, **kw) -> np.ndarray:
    """Render fn(n_over, sr=SR*factor, **kw) at a higher rate and decimate with a polyphase FIR.
    fn must accept `sr` and return a mono signal of length n_over."""
    y = fn(n * factor, sr=SR * factor, **kw)
    y = signal.resample_poly(y, 1, factor, padtype="line")
    return y[:n]
