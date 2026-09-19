"""Filters: RBJ biquads, a block-modulated state-variable filter, resonators, formant banks,
combs and allpasses. All functions accept mono (n,) or stereo (n, 2) arrays."""
from __future__ import annotations

import numpy as np
from scipy import signal

from .core import SR, is_stereo


# --- biquads ---------------------------------------------------------------------------------

def biquad_coeffs(kind: str, f0: float, q: float = 0.7071, gain_db: float = 0.0, sr: int = SR):
    """RBJ audio-EQ-cookbook coefficients. kind: lp, hp, bp, notch, peak, lowshelf, highshelf, ap."""
    f0 = float(np.clip(f0, 5.0, sr * 0.49))
    q = max(float(q), 0.05)
    w0 = 2.0 * np.pi * f0 / sr
    cw, sw = np.cos(w0), np.sin(w0)
    alpha = sw / (2.0 * q)
    A = 10.0 ** (gain_db / 40.0)
    if kind == "lp":
        b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "hp":
        b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "bp":  # constant 0 dB peak gain
        b = [alpha, 0.0, -alpha]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "notch":
        b = [1.0, -2 * cw, 1.0]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "ap":
        b = [1 - alpha, -2 * cw, 1 + alpha]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "peak":
        b = [1 + alpha * A, -2 * cw, 1 - alpha * A]
        a = [1 + alpha / A, -2 * cw, 1 - alpha / A]
    elif kind == "lowshelf":
        sq = 2 * np.sqrt(A) * alpha
        b = [A * ((A + 1) - (A - 1) * cw + sq), 2 * A * ((A - 1) - (A + 1) * cw), A * ((A + 1) - (A - 1) * cw - sq)]
        a = [(A + 1) + (A - 1) * cw + sq, -2 * ((A - 1) + (A + 1) * cw), (A + 1) + (A - 1) * cw - sq]
    elif kind == "highshelf":
        sq = 2 * np.sqrt(A) * alpha
        b = [A * ((A + 1) + (A - 1) * cw + sq), -2 * A * ((A - 1) + (A + 1) * cw), A * ((A + 1) + (A - 1) * cw - sq)]
        a = [(A + 1) - (A - 1) * cw + sq, 2 * ((A - 1) - (A + 1) * cw), (A + 1) - (A - 1) * cw - sq]
    else:
        raise ValueError(kind)
    b = np.asarray(b, dtype=np.float64) / a[0]
    a = np.asarray(a, dtype=np.float64) / a[0]
    return b, a


def biquad(x: np.ndarray, b, a) -> np.ndarray:
    return signal.lfilter(b, a, x, axis=0)


def lowpass(x, f0, q=0.7071, order: int = 1):
    b, a = biquad_coeffs("lp", f0, q)
    for _ in range(order):
        x = biquad(x, b, a)
    return x


def highpass(x, f0, q=0.7071, order: int = 1):
    b, a = biquad_coeffs("hp", f0, q)
    for _ in range(order):
        x = biquad(x, b, a)
    return x


def bandpass(x, f0, q=1.0):
    b, a = biquad_coeffs("bp", f0, q)
    return biquad(x, b, a)


def notch(x, f0, q=4.0):
    b, a = biquad_coeffs("notch", f0, q)
    return biquad(x, b, a)


def peak(x, f0, q=1.0, gain_db=0.0):
    b, a = biquad_coeffs("peak", f0, q, gain_db)
    return biquad(x, b, a)


def lowshelf(x, f0, gain_db, q=0.7071):
    b, a = biquad_coeffs("lowshelf", f0, q, gain_db)
    return biquad(x, b, a)


def highshelf(x, f0, gain_db, q=0.7071):
    b, a = biquad_coeffs("highshelf", f0, q, gain_db)
    return biquad(x, b, a)


def allpass(x, f0, q=0.7071):
    b, a = biquad_coeffs("ap", f0, q)
    return biquad(x, b, a)


def onepole_lp(x: np.ndarray, f0: float) -> np.ndarray:
    k = np.exp(-2.0 * np.pi * float(np.clip(f0, 1.0, SR * 0.49)) / SR)
    return signal.lfilter([1.0 - k], [1.0, -k], x, axis=0)


def onepole_hp(x: np.ndarray, f0: float) -> np.ndarray:
    return x - onepole_lp(x, f0)


def dc_block(x: np.ndarray, f0: float = 20.0) -> np.ndarray:
    r = 1.0 - 2.0 * np.pi * f0 / SR
    return signal.lfilter([1.0, -1.0], [1.0, -r], x, axis=0)


# --- state-variable filter with control-rate modulation ---------------------------------------

def svf(x: np.ndarray, cutoff, q: float = 0.7071, mode: str = "lp", block: int = 64) -> np.ndarray:
    """State-variable style filter whose cutoff (scalar or per-sample array) is updated every
    `block` samples with the filter state carried across blocks. Modes: lp, hp, bp, notch."""
    n = len(x)
    c = np.asarray(cutoff, dtype=np.float64)
    if c.ndim == 0:
        b, a = biquad_coeffs(mode, float(c), q)
        return signal.lfilter(b, a, x, axis=0)
    if len(c) != n:
        c = np.interp(np.linspace(0, 1, n), np.linspace(0, 1, len(c)), c)
    out = np.empty_like(x)
    zi = None
    for s in range(0, n, block):
        e = min(s + block, n)
        b, a = biquad_coeffs(mode, float(np.mean(c[s:e])), q)
        if zi is None:
            zi = np.zeros((2,) + x.shape[1:])
        out[s:e], zi = signal.lfilter(b, a, x[s:e], axis=0, zi=zi)
    return out


# --- resonators, modal synthesis, formants ----------------------------------------------------

def resonator_coeffs(f0: float, t60: float, sr: int = SR, norm: str = "bp"):
    """Two-pole resonator ringing for `t60` seconds.

    norm="bp":      band-pass numerator, ~unity gain for a steady sine at f0 (filtering).
    norm="impulse": numerator scaled so a unit impulse rings at amplitude ~1 (modal striking).
    The distinction matters: a band-pass-normalised resonator struck by an impulse rings at
    only (1 - r), which for a long t60 is inaudibly small.
    """
    r = np.exp(-np.log(1000.0) / max(t60 * sr, 1.0))
    w = 2.0 * np.pi * float(np.clip(f0, 5.0, sr * 0.49)) / sr
    a = [1.0, -2.0 * r * np.cos(w), r * r]
    if norm == "impulse":
        b = [np.sin(w), 0.0, 0.0]
    else:
        b = [1.0 - r, 0.0, -(1.0 - r)]
    return np.asarray(b), np.asarray(a)


def resonate(x: np.ndarray, f0: float, t60: float, norm: str = "bp") -> np.ndarray:
    b, a = resonator_coeffs(f0, t60, norm=norm)
    return signal.lfilter(b, a, x, axis=0)


def modal(excitation: np.ndarray, modes, norm: str = "impulse", scale: bool = True) -> np.ndarray:
    """Modal synthesis: strike a bank of resonators. modes: [(freq_hz, t60_s, gain)].

    norm="impulse" (default) suits a short strike: each mode rings at roughly its own gain.
    norm="bp" suits a continuous excitation (a bowed string's body resonances), where the
    resonators act as filters rather than as struck modes.
    `scale` divides by the summed gains so the bank's output stays near unity.
    """
    out = np.zeros_like(excitation)
    total = 0.0
    for f, t60, g in modes:
        if f >= SR * 0.49 or g == 0.0:
            continue
        out += g * resonate(excitation, f, t60, norm=norm)
        total += abs(g)
    if scale and total > 0.0:
        out /= total
    return out


def formant_bank(x: np.ndarray, formants, q_from_bw: bool = True) -> np.ndarray:
    """Parallel band-pass bank. formants: [(freq_hz, bandwidth_hz, gain_lin)]."""
    out = np.zeros_like(x)
    for f, bw, g in formants:
        q = max(f / max(bw, 1.0), 0.3) if q_from_bw else bw
        out += g * bandpass(x, f, q)
    return out


VOWELS = {
    # (F1, F2, F3, F4) centre frequencies and bandwidths of a fairly dark, choral voice
    "ah": [(700, 110, 1.0), (1150, 120, 0.5), (2600, 160, 0.16), (3300, 200, 0.06)],
    "oo": [(320, 90, 1.0), (800, 100, 0.25), (2500, 160, 0.05), (3300, 220, 0.03)],
    "oh": [(500, 100, 1.0), (900, 110, 0.4), (2500, 160, 0.08), (3300, 220, 0.04)],
    "eh": [(550, 100, 1.0), (1800, 130, 0.5), (2600, 160, 0.2), (3400, 220, 0.08)],
    "ee": [(300, 80, 1.0), (2200, 130, 0.35), (3000, 180, 0.2), (3600, 220, 0.08)],
    "mm": [(250, 80, 1.0), (1000, 200, 0.06), (2300, 250, 0.02), (3200, 300, 0.01)],
}


def vowel(x: np.ndarray, name: str) -> np.ndarray:
    return formant_bank(x, VOWELS[name])


# --- combs / allpasses (block-recursive, fast for long delays) --------------------------------

def _stereo_shape(x, n):
    return (n, 2) if is_stereo(x) else (n,)


def comb_fb(x: np.ndarray, delay_samples: int, g: float, damp: float = 0.0) -> np.ndarray:
    """Feedback comb y[n] = x[n] + g * lp(y[n-D]); processed in blocks of D samples."""
    D = max(int(delay_samples), 1)
    n = len(x)
    y = np.zeros(_stereo_shape(x, n + D))
    k = float(np.clip(damp, 0.0, 0.99))
    zi = np.zeros((1,) + x.shape[1:]) if k > 0 else None
    for s in range(0, n, D):
        e = min(s + D, n)
        fb = y[s:e]  # already computed: indices s..e are D behind s+D..e+D
        if k > 0:
            fb, zi = signal.lfilter([1.0 - k], [1.0, -k], fb, axis=0, zi=zi)
        y[s + D:e + D] = x[s:e] + g * fb
    return y[D:D + n]


def allpass_fb(x: np.ndarray, delay_samples: int, g: float) -> np.ndarray:
    """Schroeder allpass: y[n] = -g x[n] + x[n-D] + g y[n-D]."""
    D = max(int(delay_samples), 1)
    n = len(x)
    xp = np.concatenate([np.zeros(_stereo_shape(x, D)), x])
    y = np.zeros(_stereo_shape(x, n + D))
    for s in range(0, n, D):
        e = min(s + D, n)
        y[s + D:e + D] = -g * x[s:e] + xp[s:e] + g * y[s:e]
    return y[D:D + n]
