"""Effects: delays, a feedback-delay-network reverb, a convolution reverb with synthesised
impulse responses, chorus, saturation, tremolo, stereo tools and simple dynamics."""
from __future__ import annotations

import numpy as np
from scipy import ndimage, signal

from . import filters, osc
from .core import SR, TWO_PI, db_to_lin, is_stereo, samples, to_stereo


# --- delays ------------------------------------------------------------------------------------

def delay_fb(x: np.ndarray, time_s: float, feedback: float = 0.35, damping_hz: float = 4000.0,
             mix: float = 0.3, spread: float = 0.0) -> np.ndarray:
    """Feedback delay with a damped loop. `spread` offsets the right channel time (stereo ping)."""
    n = len(x)
    D = max(samples(time_s), 8)
    damp = float(np.exp(-TWO_PI * damping_hz / SR))
    if is_stereo(x):
        left = filters.comb_fb(x[:, 0], D, feedback, damp)
        right = filters.comb_fb(x[:, 1], max(int(D * (1.0 + spread)), 8), feedback, damp)
        wet = np.stack([left, right], axis=1)
    else:
        wet = filters.comb_fb(x, D, feedback, damp)
    wet = np.concatenate([np.zeros_like(wet[:D]), wet[:n - D]]) if D < n else np.zeros_like(x)
    return x * (1.0 - mix) + wet * mix


def multitap(x: np.ndarray, taps) -> np.ndarray:
    """Sum of delayed copies. taps: [(time_s, gain, pan)] -> stereo."""
    n = len(x)
    out = np.zeros((n, 2))
    mono = x if not is_stereo(x) else x.mean(axis=1)
    for t, g, p in taps:
        d = samples(t)
        if d >= n:
            continue
        a = (p + 1.0) * 0.25 * np.pi
        out[d:, 0] += mono[:n - d] * g * np.cos(a)
        out[d:, 1] += mono[:n - d] * g * np.sin(a)
    return out


# --- reverb: synthesised impulse responses + convolution -----------------------------------------

REVERB_PRESETS = {
    # name: dict(seconds, rt60 per band [low, mid, high], predelay, early, width, tone_hp, tone_lp)
    "room":      dict(seconds=1.2, rt60=(0.7, 0.55, 0.3), predelay=0.008, early=0.5, width=0.7, hp=120, lp=9000),
    "chamber":   dict(seconds=2.2, rt60=(1.6, 1.3, 0.7), predelay=0.015, early=0.45, width=0.9, hp=90, lp=8000),
    "hall":      dict(seconds=4.0, rt60=(3.2, 2.6, 1.3), predelay=0.025, early=0.35, width=1.0, hp=70, lp=7000),
    "cathedral": dict(seconds=7.0, rt60=(6.0, 4.8, 2.0), predelay=0.04, early=0.3, width=1.0, hp=60, lp=5500),
    "cave":      dict(seconds=5.0, rt60=(4.5, 3.0, 1.0), predelay=0.03, early=0.6, width=0.9, hp=50, lp=3500),
    "plate":     dict(seconds=2.5, rt60=(1.8, 2.0, 1.4), predelay=0.0, early=0.2, width=1.0, hp=150, lp=12000),
    "valley":    dict(seconds=3.0, rt60=(2.2, 1.8, 0.8), predelay=0.06, early=0.7, width=1.0, hp=100, lp=5000),
    "marsh":     dict(seconds=2.8, rt60=(2.0, 1.5, 0.5), predelay=0.03, early=0.5, width=1.0, hp=80, lp=3800),
    "cinder":    dict(seconds=9.0, rt60=(8.0, 6.0, 1.8), predelay=0.05, early=0.2, width=1.0, hp=45, lp=4200),
}


def synth_ir(rng: np.random.Generator, seconds: float = 3.0, rt60=(2.5, 2.0, 1.0), predelay: float = 0.02,
             early: float = 0.4, width: float = 1.0, hp: float = 80.0, lp: float = 7000.0,
             stereo: bool = True) -> np.ndarray:
    """A plausible room impulse response: sparse early reflections then a noise tail whose decay
    rate differs per frequency band (low/mid/high), decorrelated between channels."""
    n = samples(seconds)
    t = np.arange(n) / SR
    chans = []
    for ch in range(2 if stereo else 1):
        tail = np.zeros(n)
        bands = [(0.0, 300.0, rt60[0]), (300.0, 2500.0, rt60[1]), (2500.0, SR * 0.49, rt60[2])]
        for lo, hi, t60 in bands:
            noise = rng.standard_normal(n)
            if lo > 0:
                noise = filters.highpass(noise, lo, 0.7)
            if hi < SR * 0.49:
                noise = filters.lowpass(noise, hi, 0.7)
            tail += noise * np.exp(-np.log(1000.0) * t / max(t60, 0.05))
        # gentle density ramp (diffusion builds up over the first 60 ms)
        tail *= np.clip(t / 0.06, 0.15, 1.0)
        # early reflections: 12 sparse taps within 80 ms after predelay
        er = np.zeros(n)
        count = 14
        times = predelay + np.sort(rng.uniform(0.003, 0.08, count))
        gains = np.linspace(1.0, 0.35, count) * rng.uniform(0.6, 1.0, count)
        for tt, g in zip(times, gains):
            i = samples(tt)
            if i < n:
                er[i] += g * rng.choice([-1.0, 1.0])
        er = filters.lowpass(er, lp * 1.2, 0.7)
        ir = early * er + tail * (1.0 - 0.5 * early)
        pd = samples(predelay)
        ir = np.concatenate([np.zeros(pd), ir])[:n]
        ir = filters.highpass(ir, hp, 0.7)
        ir = filters.lowpass(ir, lp, 0.7)
        chans.append(ir)
    if stereo:
        left, right = chans
        mid, side = (left + right) * 0.5, (left - right) * 0.5 * width
        ir = np.stack([mid + side, mid - side], axis=1)
    else:
        ir = chans[0]
    # normalise energy so mix levels are comparable between presets
    ir /= np.sqrt(np.sum(np.square(ir))) + 1e-9
    return ir


_IR_CACHE: dict = {}


def reverb(x: np.ndarray, preset: str = "hall", mix: float = 0.25, seed: int = 7, tail: bool = True,
           pre_lp: float | None = None) -> np.ndarray:
    """Convolution reverb with a cached synthetic IR. Output is stereo and, when tail=True,
    len(x) + len(ir) - 1 samples long so ring-outs are kept (loop folding uses the tail)."""
    key = (preset, seed)
    if key not in _IR_CACHE:
        p = REVERB_PRESETS[preset]
        _IR_CACHE[key] = synth_ir(np.random.default_rng(seed), **p)
    ir = _IR_CACHE[key]
    xs = to_stereo(x)
    if pre_lp:
        xs = filters.lowpass(xs, pre_lp)
    # Overlap-add, not a single transform: a two-minute music stem against a seven-second
    # impulse response would otherwise need one FFT over the whole thing.
    wet = np.stack([signal.oaconvolve(xs[:, 0], ir[:, 0]), signal.oaconvolve(xs[:, 1], ir[:, 1])], axis=1)
    out_len = len(wet) if tail else len(xs)
    dry = np.zeros((out_len, 2))
    dry[:len(xs)] = to_stereo(x)
    return dry * (1.0 - mix) + wet[:out_len] * mix * 2.2


def fdn_reverb(x: np.ndarray, rt60: float = 2.5, damping_hz: float = 5000.0, mix: float = 0.3,
               size: float = 1.0, tail: bool = True) -> np.ndarray:
    """8-line feedback delay network (Hadamard mixing, one-pole damping per line), processed in
    blocks the size of the shortest delay so it stays vectorised. Output stereo."""
    base = np.array([1553, 1613, 1789, 1907, 2053, 2269, 2447, 2633], dtype=np.int64)
    delays = np.maximum((base * size).astype(np.int64), 64)
    L = len(delays)
    xin = x.mean(axis=1) if is_stereo(x) else x
    n_tail = samples(rt60 * 1.2) if tail else 0
    n = len(xin) + n_tail
    xin = np.concatenate([xin, np.zeros(n_tail)])
    # per-line gain for the requested rt60
    g = 10.0 ** (-3.0 * delays / (rt60 * SR))
    H = np.array([[1, 1, 1, 1, 1, 1, 1, 1], [1, -1, 1, -1, 1, -1, 1, -1], [1, 1, -1, -1, 1, 1, -1, -1],
                  [1, -1, -1, 1, 1, -1, -1, 1], [1, 1, 1, 1, -1, -1, -1, -1], [1, -1, 1, -1, -1, 1, -1, 1],
                  [1, 1, -1, -1, -1, -1, 1, 1], [1, -1, -1, 1, -1, 1, 1, -1]], dtype=np.float64) / np.sqrt(8.0)
    B = int(delays.min())
    maxd = int(delays.max())
    lines = np.zeros((L, n + maxd))  # line outputs (delayed)
    k = float(np.exp(-TWO_PI * damping_hz / SR))
    zi = np.zeros((L, 1))
    in_gain = np.array([1.0, 0.8, 0.9, 0.7, 1.0, 0.85, 0.75, 0.95])
    for s in range(0, n, B):
        e = min(s + B, n)
        m = e - s
        # read each line's output for this block: what entered it `delay` samples ago
        reads = np.stack([lines[i, s + maxd - delays[i]:e + maxd - delays[i]] for i in range(L)])
        # damping + decay per line
        for i in range(L):
            reads[i], zi[i] = signal.lfilter([1.0 - k], [1.0, -k], reads[i], zi=zi[i])
        reads *= g[:, None]
        mixed = H @ reads  # (L, m)
        lines[:, s + maxd:e + maxd] = mixed + in_gain[:, None] * xin[s:e][None, :]
    outl = lines[0::2, maxd:maxd + n].sum(axis=0)
    outr = lines[1::2, maxd:maxd + n].sum(axis=0)
    wet = np.stack([outl, outr], axis=1) * 0.35
    dry = np.zeros((n, 2))
    dry[:len(x)] = to_stereo(x)
    return dry * (1.0 - mix) + wet * mix


# --- modulation -----------------------------------------------------------------------------------

def _frac_delay_read(x: np.ndarray, delay_samples: np.ndarray) -> np.ndarray:
    n = len(x)
    idx = np.arange(n) - delay_samples
    idx = np.clip(idx, 0, n - 1)
    return np.interp(idx, np.arange(n), x)


def chorus(x: np.ndarray, rate_hz: float = 0.35, depth_ms: float = 6.0, base_ms: float = 14.0,
           voices: int = 3, mix: float = 0.4, spread: float = 1.0, rng=None) -> np.ndarray:
    """Multi-voice chorus (modulated fractional delays), stereo out."""
    rng = rng or np.random.default_rng(3)
    mono = x.mean(axis=1) if is_stereo(x) else x
    n = len(mono)
    t = np.arange(n) / SR
    left = np.zeros(n)
    right = np.zeros(n)
    for v in range(voices):
        ph = rng.uniform(0, 1)
        r = rate_hz * (1.0 + 0.13 * v)
        d = (base_ms + depth_ms * np.sin(TWO_PI * (t * r + ph))) * 0.001 * SR
        voice = _frac_delay_read(mono, d)
        p = (v / max(voices - 1, 1) * 2.0 - 1.0) * spread if voices > 1 else 0.0
        a = (p + 1.0) * 0.25 * np.pi
        left += voice * np.cos(a)
        right += voice * np.sin(a)
    wet = np.stack([left, right], axis=1) / np.sqrt(voices)
    return to_stereo(x) * (1.0 - mix) + wet * mix


def vibrato_delay(x: np.ndarray, rate_hz: float = 5.0, depth_ms: float = 0.4) -> np.ndarray:
    n = len(x)
    t = np.arange(n) / SR
    d = (depth_ms + depth_ms * np.sin(TWO_PI * t * rate_hz)) * 0.001 * SR
    if is_stereo(x):
        return np.stack([_frac_delay_read(x[:, 0], d), _frac_delay_read(x[:, 1], d)], axis=1)
    return _frac_delay_read(x, d)


def tremolo(x: np.ndarray, rate_hz: float = 4.0, depth: float = 0.3) -> np.ndarray:
    n = len(x)
    m = 1.0 - depth * 0.5 * (1.0 + np.sin(TWO_PI * np.arange(n) / SR * rate_hz))
    return (x.T * m).T


# --- non-linear -----------------------------------------------------------------------------------

def saturate(x: np.ndarray, drive: float = 2.0, kind: str = "tanh", mix: float = 1.0) -> np.ndarray:
    d = max(drive, 1e-3)
    if kind == "tanh":
        y = np.tanh(x * d) / np.tanh(d)
    elif kind == "soft":  # cubic soft clip
        z = np.clip(x * d, -1.5, 1.5)
        y = (z - z ** 3 / 6.75) / (1.5 - 1.5 ** 3 / 6.75)
    elif kind == "fold":
        y = np.sin(x * d)
    else:
        raise ValueError(kind)
    return x * (1.0 - mix) + y * mix


def bitcrush(x: np.ndarray, bits: int = 8) -> np.ndarray:
    q = 2.0 ** (bits - 1)
    return np.round(x * q) / q


# --- stereo -----------------------------------------------------------------------------------------

def widen(x: np.ndarray, amount: float = 1.4) -> np.ndarray:
    s = to_stereo(x)
    mid = (s[:, 0] + s[:, 1]) * 0.5
    side = (s[:, 0] - s[:, 1]) * 0.5 * amount
    return np.stack([mid + side, mid - side], axis=1)


def haas(x: np.ndarray, ms: float = 12.0, gain: float = 0.8, side: int = 1) -> np.ndarray:
    """Mono -> stereo by a short delay on one side."""
    mono = x.mean(axis=1) if is_stereo(x) else x
    d = samples(ms * 0.001)
    delayed = np.concatenate([np.zeros(d), mono[:-d]]) if d < len(mono) else np.zeros_like(mono)
    if side > 0:
        return np.stack([mono, delayed * gain], axis=1)
    return np.stack([delayed * gain, mono], axis=1)


def autopan(x: np.ndarray, rate_hz: float = 0.1, depth: float = 0.8, phase0: float = 0.0) -> np.ndarray:
    mono = x.mean(axis=1) if is_stereo(x) else x
    n = len(mono)
    p = depth * np.sin(TWO_PI * (np.arange(n) / SR * rate_hz + phase0))
    a = (p + 1.0) * 0.25 * np.pi
    return np.stack([mono * np.cos(a), mono * np.sin(a)], axis=1)


def decorrelate(x: np.ndarray, seed: int = 11, ms: float = 25.0) -> np.ndarray:
    """Mono -> wide stereo through two short different allpass/noise convolutions."""
    rng = np.random.default_rng(seed)
    mono = x.mean(axis=1) if is_stereo(x) else x
    k = samples(ms * 0.001)
    outs = []
    for _ in range(2):
        h = rng.standard_normal(k) * np.exp(-np.arange(k) / (k / 4.0))
        h[0] = 3.0
        h /= np.sqrt(np.sum(h * h))
        outs.append(signal.fftconvolve(mono, h)[:len(mono)])
    return np.stack(outs, axis=1)


# --- dynamics ---------------------------------------------------------------------------------------

def envelope_follow(x: np.ndarray, attack_ms: float = 5.0, release_ms: float = 80.0) -> np.ndarray:
    mag = np.abs(x.mean(axis=1) if is_stereo(x) else x)
    na = max(samples(attack_ms * 0.001), 1)
    peakhold = ndimage.maximum_filter1d(mag, size=na, mode="nearest", origin=-(na // 2))
    k = np.exp(-1.0 / max(release_ms * 0.001 * SR, 1.0))
    return signal.lfilter([1.0 - k], [1.0, -k], peakhold)


def compress(x: np.ndarray, threshold_db: float = -18.0, ratio: float = 3.0, attack_ms: float = 8.0,
             release_ms: float = 120.0, makeup_db: float = 0.0, knee_db: float = 6.0) -> np.ndarray:
    env = envelope_follow(x, attack_ms, release_ms)
    lvl = 20.0 * np.log10(env + 1e-9)
    over = lvl - threshold_db
    # soft knee
    gain_db = np.where(over <= -knee_db / 2, 0.0,
                       np.where(over >= knee_db / 2, -(over) * (1.0 - 1.0 / ratio),
                                -((over + knee_db / 2) ** 2) / (2 * knee_db) * (1.0 - 1.0 / ratio)))
    g = db_to_lin(gain_db + makeup_db)
    return (x.T * g).T


def limiter(x: np.ndarray, ceiling_db: float = -1.0, lookahead_ms: float = 5.0, release_ms: float = 60.0) -> np.ndarray:
    ceil = db_to_lin(ceiling_db)
    mag = np.max(np.abs(x), axis=1) if is_stereo(x) else np.abs(x)
    la = max(samples(lookahead_ms * 0.001), 1)
    need = np.minimum(1.0, ceil / (ndimage.maximum_filter1d(mag, size=2 * la, mode="nearest") + 1e-9))
    # smooth the gain reduction so it never rises faster than the release
    k = np.exp(-1.0 / max(release_ms * 0.001 * SR, 1.0))
    g = np.empty_like(need)
    # attack instantly (min filter already gives lookahead), release with a one-pole toward 1
    g = signal.lfilter([1.0 - k], [1.0, -k], need)
    g = np.minimum(g, need)
    return (x.T * g).T


def normalize_peak(x: np.ndarray, peak_db: float = -1.0) -> np.ndarray:
    p = float(np.max(np.abs(x))) if len(x) else 0.0
    if p <= 1e-9:
        return x
    return x * (db_to_lin(peak_db) / p)


def pitch_shift_resample(x: np.ndarray, semitones: float) -> np.ndarray:
    """Varispeed pitch shift (changes length), good for one-shot variants."""
    ratio = 2.0 ** (semitones / 12.0)
    n_out = max(int(len(x) / ratio), 1)
    idx = np.linspace(0, len(x) - 1, n_out)
    if is_stereo(x):
        return np.stack([np.interp(idx, np.arange(len(x)), x[:, 0]), np.interp(idx, np.arange(len(x)), x[:, 1])], axis=1)
    return np.interp(idx, np.arange(len(x)), x)


def noise_burst(rng: np.random.Generator, seconds: float, kind: str = "white") -> np.ndarray:
    return osc.noise(kind, samples(seconds), rng)
