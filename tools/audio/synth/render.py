"""Render and mixdown: WAV writing, OGG encoding, loudness measurement, seamless looping and
Godot .import sidecars."""
from __future__ import annotations

import json
import os
import struct
import subprocess
import wave

import numpy as np
from scipy import signal

from . import fx
from .core import SR, db_to_lin, is_stereo, lin_to_db, samples, to_mono, to_stereo


# --- files ------------------------------------------------------------------------------------

def write_wav(path: str, x: np.ndarray, sr: int = SR, bits: int = 16) -> str:
    """Write a 16- (or 24-) bit PCM WAV with TPDF dither at 16 bits."""
    os.makedirs(os.path.dirname(os.path.abspath(path)) or ".", exist_ok=True)
    y = np.asarray(x, dtype=np.float64)
    y = to_stereo(y) if is_stereo(y) else y
    if bits == 16:
        rng = np.random.default_rng(1234)
        lsb = 1.0 / 32768.0
        y = y + (rng.random(y.shape) - rng.random(y.shape)) * lsb * 0.5
        y = np.clip(y, -1.0, 1.0 - lsb)
        data = (y * 32767.0).astype("<i2").tobytes()
        sampwidth = 2
    elif bits == 24:
        y = np.clip(y, -1.0, 1.0 - 1.0 / 8388608.0)
        ints = (y * 8388607.0).astype("<i4")
        b = ints.astype("<u4").tobytes()
        data = bytearray()
        for i in range(0, len(b), 4):
            data += b[i:i + 3]
        data = bytes(data)
        sampwidth = 3
    else:
        raise ValueError(bits)
    with wave.open(path, "wb") as w:
        w.setnchannels(2 if y.ndim == 2 else 1)
        w.setsampwidth(sampwidth)
        w.setframerate(sr)
        w.writeframes(data)
    return path


def read_wav(path: str):
    with wave.open(path, "rb") as w:
        n, ch, sw, sr = w.getnframes(), w.getnchannels(), w.getsampwidth(), w.getframerate()
        raw = w.readframes(n)
    if sw != 2:
        raise ValueError("only 16-bit WAVs are read back")
    a = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
    if ch == 2:
        a = a.reshape(-1, 2)
    return a, sr


def encode_ogg(wav_path: str, ogg_path: str, quality: float = 5.0, delete_wav: bool = False) -> str:
    """Encode WAV -> OGG Vorbis with ffmpeg."""
    os.makedirs(os.path.dirname(os.path.abspath(ogg_path)) or ".", exist_ok=True)
    cmd = ["ffmpeg", "-v", "error", "-y", "-i", wav_path, "-c:a", "libvorbis", "-q:a", str(quality), ogg_path]
    subprocess.run(cmd, check=True)
    if delete_wav:
        os.remove(wav_path)
    return ogg_path


def write_ogg(path: str, x: np.ndarray, quality: float = 5.0, sr: int = SR, tmp_dir: str | None = None) -> str:
    """Render a signal straight to OGG through a temporary WAV."""
    tmp = (tmp_dir or os.path.dirname(os.path.abspath(path)) or ".")
    os.makedirs(tmp, exist_ok=True)
    wav = os.path.join(tmp, "." + os.path.basename(path) + ".tmp.wav")
    write_wav(wav, x, sr)
    try:
        encode_ogg(wav, path, quality)
    finally:
        if os.path.exists(wav):
            os.remove(wav)
    return path


IMPORT_OGG_TEMPLATE = """[remap]

importer="oggvorbisstr"
type="AudioStreamOggVorbis"

[deps]

source_file="res://{res}"

[params]

loop={loop}
loop_offset=0.0
bpm={bpm}
beat_count={beats}
bar_beats=4
"""


def write_ogg_import(ogg_path: str, res_path: str, loop: bool, bpm: float = 0.0, beat_count: int = 0) -> str:
    """Write the Godot .import sidecar so a fresh checkout imports with the right loop flag.
    Godot fills in uid/path on its next import pass and keeps these [params]."""
    p = ogg_path + ".import"
    with open(p, "w") as f:
        f.write(IMPORT_OGG_TEMPLATE.format(res=res_path, loop="true" if loop else "false",
                                           bpm=("%.1f" % bpm) if bpm else "0.0", beats=int(beat_count)))
    return p


# --- loudness ----------------------------------------------------------------------------------

_K_B, _K_A = None, None


def _k_weighting():
    """ITU-R BS.1770 K-weighting: a high shelf plus a high-pass, as cascaded biquads at 44.1 kHz."""
    global _K_B, _K_A
    if _K_B is None:
        # stage 1: high shelf (+4 dB @ ~1681 Hz)
        f0, G, Q = 1681.974450955533, 3.999843853973347, 0.7071752369554196
        K = np.tan(np.pi * f0 / SR)
        Vh = 10.0 ** (G / 20.0)
        Vb = Vh ** 0.4996667741545416
        a0 = 1.0 + K / Q + K * K
        b = np.array([(Vh + Vb * K / Q + K * K) / a0, 2.0 * (K * K - Vh) / a0, (Vh - Vb * K / Q + K * K) / a0])
        a = np.array([1.0, 2.0 * (K * K - 1.0) / a0, (1.0 - K / Q + K * K) / a0])
        # stage 2: high pass (~38 Hz)
        f0b, Qb = 38.13547087602444, 0.5003270373238773
        Kb = np.tan(np.pi * f0b / SR)
        a0b = 1.0 + Kb / Qb + Kb * Kb
        b2 = np.array([1.0, -2.0, 1.0])
        a2 = np.array([1.0, 2.0 * (Kb * Kb - 1.0) / a0b, (1.0 - Kb / Qb + Kb * Kb) / a0b])
        _K_B, _K_A = (b, b2), (a, a2)
    return _K_B, _K_A


def loudness_lufs(x: np.ndarray) -> float:
    """Integrated loudness (BS.1770-style, gated at -10 LU relative). Good enough to compare
    our own renders and hit a target; not a certified meter."""
    (b1, b2), (a1, a2) = _k_weighting()
    y = to_stereo(np.asarray(x, dtype=np.float64))
    y = signal.lfilter(b1, a1, y, axis=0)
    y = signal.lfilter(b2, a2, y, axis=0)
    block = samples(0.4)
    hop = block // 4
    if len(y) < block:
        ms = np.mean(np.square(y), axis=0).sum()
        return -0.691 + 10.0 * np.log10(ms + 1e-12)
    n_blocks = 1 + (len(y) - block) // hop
    idx = np.arange(block)[None, :] + hop * np.arange(n_blocks)[:, None]
    loud = []
    for ch in range(y.shape[1]):
        blocks = y[:, ch][idx]
        loud.append(np.mean(np.square(blocks), axis=1))
    z = np.sum(np.stack(loud, axis=0), axis=0)
    lj = -0.691 + 10.0 * np.log10(z + 1e-12)
    keep = lj > -70.0
    if not np.any(keep):
        return -70.0
    gate = -0.691 + 10.0 * np.log10(np.mean(z[keep]) + 1e-12) - 10.0
    keep2 = keep & (lj > gate)
    if not np.any(keep2):
        keep2 = keep
    return float(-0.691 + 10.0 * np.log10(np.mean(z[keep2]) + 1e-12))


def true_peak_db(x: np.ndarray) -> float:
    """Peak of a 4x-oversampled signal, in dBFS (catches inter-sample overs)."""
    y = np.asarray(x, dtype=np.float64)
    up = signal.resample_poly(y, 4, 1, axis=0)
    return float(lin_to_db(np.max(np.abs(up)) + 1e-12))


def analyse(x: np.ndarray) -> dict:
    y = np.asarray(x, dtype=np.float64)
    mono = to_mono(y)
    n = len(mono)
    out = {
        "seconds": n / SR,
        "channels": 2 if is_stereo(y) else 1,
        "peak_db": float(lin_to_db(np.max(np.abs(y)) + 1e-12)),
        "true_peak_db": true_peak_db(y),
        "rms_db": float(lin_to_db(np.sqrt(np.mean(np.square(mono))) + 1e-12)),
        "lufs": loudness_lufs(y),
        "dc_offset": float(np.mean(mono)),
    }
    out["crest_db"] = out["peak_db"] - out["rms_db"]
    if is_stereo(y):
        m = (y[:, 0] + y[:, 1]) * 0.5
        s = (y[:, 0] - y[:, 1]) * 0.5
        out["side_rms_db"] = float(lin_to_db(np.sqrt(np.mean(np.square(s))) + 1e-12))
        out["mid_rms_db"] = float(lin_to_db(np.sqrt(np.mean(np.square(m))) + 1e-12))
        denom = np.sqrt(np.mean(np.square(y[:, 0])) * np.mean(np.square(y[:, 1]))) + 1e-12
        out["correlation"] = float(np.mean(y[:, 0] * y[:, 1]) / denom)
    return out


def spectral_balance(x: np.ndarray, bands=((20, 120), (120, 500), (500, 2000), (2000, 6000), (6000, 20000))) -> dict:
    """Energy per band in dB relative to the total (a cheap tonal-balance check)."""
    mono = to_mono(np.asarray(x, dtype=np.float64))
    n = min(len(mono), SR * 30)
    f, p = signal.welch(mono[:n], SR, nperseg=8192)
    total = np.trapezoid(p, f) + 1e-18
    out = {}
    for lo, hi in bands:
        m = (f >= lo) & (f < hi)
        out["%d_%d" % (lo, hi)] = float(10.0 * np.log10(np.trapezoid(p[m], f[m]) / total + 1e-12))
    return out


# --- looping ------------------------------------------------------------------------------------

def loop_fold(x: np.ndarray, loop_seconds: float, tail_seconds: float | None = None) -> np.ndarray:
    """Make a seamless loop from a render that is longer than the loop: the material after the
    loop point (reverb tails, ring-outs) is folded back onto the start, so the end of the loop
    runs into its own beginning exactly as it will in the game.

    The caller must stop *starting* events at the loop point and keep rendering only so the
    tails of events inside the loop can ring on. Anything newly struck after the loop point is
    folded in as a whole event and the loop ends up denser than it was composed to be.
    """
    n = samples(loop_seconds)
    y = np.asarray(x, dtype=np.float64)
    if len(y) < n:
        y = np.pad(y, ((0, n - len(y)), (0, 0)) if is_stereo(y) else (0, n - len(y)))
    out = y[:n].copy()
    tail = y[n:]
    if tail_seconds is not None:
        tail = tail[:samples(tail_seconds)]
    # Wrap the whole tail, not just its first loop-length: a ring-out longer than the loop has
    # to come round more than once, exactly as it would when the loop actually repeats.
    pos = 0
    while pos < len(tail):
        k = min(n, len(tail) - pos)
        out[:k] += tail[pos:pos + k]
        pos += k
    return out


def crossfade_loop(x: np.ndarray, loop_seconds: float, fade_seconds: float = 2.0) -> np.ndarray:
    """Classic crossfaded loop: the last `fade` of the (longer) render is mixed over the first
    `fade` with equal-power curves. Use where there is no meaningful tail to fold."""
    n = samples(loop_seconds)
    nf = samples(fade_seconds)
    y = np.asarray(x, dtype=np.float64)
    if len(y) < n + nf:
        y = np.pad(y, ((0, n + nf - len(y)), (0, 0)) if is_stereo(y) else (0, n + nf - len(y)))
    head = y[:n].copy()
    over = y[n:n + nf]
    r = np.linspace(0.0, 1.0, nf)
    fade_in = np.sin(r * np.pi / 2.0)
    fade_out = np.cos(r * np.pi / 2.0)
    head[:nf] = (head[:nf].T * fade_in).T + (over.T * fade_out).T
    return head


def seam_discontinuity_db(x: np.ndarray, window_ms: float = 50.0) -> float:
    """RMS difference (dB) between the window before the loop end and the window after the loop
    start: how audible the seam is. The bar for our loops is < 1 dB."""
    y = to_mono(np.asarray(x, dtype=np.float64))
    w = samples(window_ms * 0.001)
    if len(y) < 2 * w:
        return 0.0
    a = np.sqrt(np.mean(np.square(y[-w:]))) + 1e-9
    b = np.sqrt(np.mean(np.square(y[:w]))) + 1e-9
    return float(abs(20.0 * np.log10(a / b)))


def seam_click_db(x: np.ndarray) -> float:
    """How far the sample-level step at the wrap point stands out from the signal's own
    sample-to-sample motion, in dB.

    Comparing the step to the overall RMS would condemn every noise bed, because neighbouring
    samples of noise already differ by about the RMS. The reference here is the median absolute
    difference between successive samples, so 0 dB means "the wrap looks like any other sample
    boundary" and a real click shows up as +20 dB or more.
    """
    y = to_mono(np.asarray(x, dtype=np.float64))
    if len(y) < 4:
        return -120.0
    step = abs(y[0] - y[-1])
    typical = float(np.median(np.abs(np.diff(y))))
    if typical < 1e-12:
        return -120.0 if step < 1e-9 else 120.0
    return float(20.0 * np.log10(step / typical + 1e-12))


# --- mixdown ------------------------------------------------------------------------------------

def mixdown(x: np.ndarray, peak_db: float = -1.0, target_lufs: float | None = None,
            limit: bool = True, hp: float | None = 24.0) -> np.ndarray:
    """Finish a render: DC/rumble removal, optional loudness match, limiting, peak normalisation."""
    from . import filters as _f
    y = np.asarray(x, dtype=np.float64)
    if hp:
        y = _f.highpass(y, hp, 0.7)
    if target_lufs is not None:
        cur = loudness_lufs(y)
        if cur > -70.0:
            y = y * db_to_lin(target_lufs - cur)
    if limit:
        y = fx.limiter(y, ceiling_db=peak_db, lookahead_ms=4.0, release_ms=80.0)
    p = float(np.max(np.abs(y))) if len(y) else 0.0
    if p > 1e-9:
        y = y * min(db_to_lin(peak_db) / p, 1.0) if p > db_to_lin(peak_db) else y
    return y


def save_manifest(path: str, data: dict) -> str:
    os.makedirs(os.path.dirname(os.path.abspath(path)) or ".", exist_ok=True)
    with open(path, "w") as f:
        json.dump(data, f, indent=2, sort_keys=True)
        f.write("\n")
    return path
