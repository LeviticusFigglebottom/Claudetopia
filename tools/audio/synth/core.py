"""Constants, deterministic seeding, unit conversions and buffer helpers."""
from __future__ import annotations

import hashlib

import numpy as np

SR = 44100
TWO_PI = 2.0 * np.pi


def rng(seed) -> np.random.Generator:
    """Deterministic generator from an int or any string (hashed)."""
    if isinstance(seed, str):
        seed = int.from_bytes(hashlib.sha256(seed.encode("utf-8")).digest()[:8], "little")
    return np.random.default_rng(int(seed) & 0xFFFFFFFFFFFFFFFF)


def sub_seed(seed, *names) -> int:
    """Derive a child seed from a parent seed and a path of names (stable across runs)."""
    h = hashlib.sha256(("%s|%s" % (seed, "/".join(str(n) for n in names))).encode("utf-8")).digest()
    return int.from_bytes(h[:8], "little")


def samples(seconds: float) -> int:
    return int(round(seconds * SR))


def t_axis(n: int) -> np.ndarray:
    return np.arange(n, dtype=np.float64) / SR


def midi_to_hz(m):
    return 440.0 * 2.0 ** ((np.asarray(m, dtype=np.float64) - 69.0) / 12.0)


def hz_to_midi(f):
    return 69.0 + 12.0 * np.log2(np.asarray(f, dtype=np.float64) / 440.0)


def cents(c):
    """Frequency ratio for a detune in cents."""
    return 2.0 ** (np.asarray(c, dtype=np.float64) / 1200.0)


def db_to_lin(db):
    return 10.0 ** (np.asarray(db, dtype=np.float64) / 20.0)


def lin_to_db(x):
    return 20.0 * np.log10(np.maximum(np.asarray(x, dtype=np.float64), 1e-12))


def is_stereo(x: np.ndarray) -> bool:
    return x.ndim == 2 and x.shape[1] == 2


def to_stereo(x: np.ndarray) -> np.ndarray:
    if is_stereo(x):
        return x
    return np.stack([x, x], axis=1)


def to_mono(x: np.ndarray) -> np.ndarray:
    if is_stereo(x):
        return x.mean(axis=1)
    return x


def pan(x: np.ndarray, p: float) -> np.ndarray:
    """Equal-power pan; p in [-1, 1]. A stereo input is balanced rather than collapsed."""
    p = float(np.clip(p, -1.0, 1.0))
    a = (p + 1.0) * 0.25 * np.pi
    left, right = np.cos(a), np.sin(a)
    if is_stereo(x):
        return np.stack([x[:, 0] * left * 1.4142, x[:, 1] * right * 1.4142], axis=1)
    return np.stack([x * left, x * right], axis=1)


def zeros(seconds: float, stereo: bool = False) -> np.ndarray:
    n = samples(seconds)
    return np.zeros((n, 2) if stereo else n, dtype=np.float64)


def mix_into(buf: np.ndarray, sig: np.ndarray, start: int, gain: float = 1.0) -> None:
    """Add `sig` into `buf` starting at sample `start`, clipping to the buffer bounds.
    A mono signal into a stereo buffer is centred; a stereo signal into a mono buffer is summed."""
    if start >= len(buf):
        return
    if start < 0:
        sig = sig[-start:]
        start = 0
    n = min(len(sig), len(buf) - start)
    if n <= 0:
        return
    seg = sig[:n]
    if is_stereo(buf) and not is_stereo(seg):
        seg = np.stack([seg, seg], axis=1) * 0.7071
    elif not is_stereo(buf) and is_stereo(seg):
        seg = seg.mean(axis=1)
    buf[start:start + n] += seg * gain


def fade(x: np.ndarray, fade_in: float = 0.0, fade_out: float = 0.0, shape: str = "cos") -> np.ndarray:
    """Apply raised-cosine (or linear) fades, in seconds."""
    y = x.copy()
    n = len(y)
    fi, fo = min(samples(fade_in), n), min(samples(fade_out), n)
    if fi > 0:
        r = np.linspace(0.0, 1.0, fi)
        w = 0.5 - 0.5 * np.cos(np.pi * r) if shape == "cos" else r
        y[:fi] = (y[:fi].T * w).T
    if fo > 0:
        r = np.linspace(1.0, 0.0, fo)
        w = 0.5 - 0.5 * np.cos(np.pi * r) if shape == "cos" else r
        y[n - fo:] = (y[n - fo:].T * w).T
    return y


def fit_length(x: np.ndarray, n: int) -> np.ndarray:
    """Pad with zeros or truncate to exactly n samples."""
    if len(x) == n:
        return x
    if len(x) > n:
        return x[:n]
    pad = ((0, n - len(x)), (0, 0)) if is_stereo(x) else (0, n - len(x))
    return np.pad(x, pad)


def peak(x: np.ndarray) -> float:
    return float(np.max(np.abs(x))) if len(x) else 0.0


def rms(x: np.ndarray) -> float:
    return float(np.sqrt(np.mean(np.square(x)))) if len(x) else 0.0
