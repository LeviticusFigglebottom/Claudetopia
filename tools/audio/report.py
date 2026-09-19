#!/usr/bin/env python3
"""Look at the audio without listening to it.

Renders a spectrogram PNG per file and a loudness/balance table, into captures/audio/.
matplotlib is not installed in this container, so the plots are drawn straight into a numpy
array and saved with PIL: log-frequency axis, dB colour scale, gridlines and labels.

    python3 tools/audio/report.py                      # everything under game/assets/audio
    python3 tools/audio/report.py --only music/hearthvale
    python3 tools/audio/report.py --table              # the table only, no images
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image, ImageDraw
from scipy import signal as sg

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from synth import core, render  # noqa: E402
from synth.core import SR  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
AUDIO_ROOT = os.path.join(ROOT, "game", "assets", "audio")
OUT_DIR = os.path.join(ROOT, "captures", "audio")

# A perceptually ordered colour ramp (dark blue -> teal -> green -> amber -> white). Built by
# hand because matplotlib's colormaps are not available here.
RAMP = np.array([
    (8, 10, 22), (16, 28, 62), (18, 54, 96), (16, 86, 112), (22, 118, 108),
    (60, 148, 86), (124, 168, 62), (192, 178, 54), (232, 166, 62), (246, 196, 120),
    (252, 232, 200), (255, 255, 255),
], dtype=np.float64)


def colourise(norm: np.ndarray) -> np.ndarray:
    """Map 0..1 to RGB through the ramp with linear interpolation."""
    x = np.clip(norm, 0.0, 1.0) * (len(RAMP) - 1)
    i = np.floor(x).astype(int)
    f = (x - i)[..., None]
    i2 = np.minimum(i + 1, len(RAMP) - 1)
    return (RAMP[i] * (1 - f) + RAMP[i2] * f).astype(np.uint8)


def load_audio(path: str):
    """Read a WAV directly, or decode an OGG through ffmpeg."""
    if path.lower().endswith(".wav"):
        return render.read_wav(path)
    with tempfile.TemporaryDirectory() as d:
        tmp = os.path.join(d, "a.wav")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", path, "-ar", str(SR), tmp], check=True)
        return render.read_wav(tmp)


def spectrogram(x: np.ndarray, width: int = 1100, height: int = 420, fmin: float = 30.0,
                fmax: float = 18000.0, db_floor: float = -96.0):
    """A log-frequency spectrogram image (numpy RGB) plus the axis data for labelling."""
    mono = core.to_mono(x)
    nper = 2048
    hop = max(len(mono) // width, nper // 4)
    f, t, Z = sg.stft(mono, SR, nperseg=nper, noverlap=nper - hop, boundary=None)
    mag = 20.0 * np.log10(np.abs(Z) + 1e-12)
    # resample the frequency axis to log spacing
    lf = np.geomspace(fmin, min(fmax, SR / 2 - 1), height)
    rows = np.empty((height, mag.shape[1]))
    for i, target in enumerate(lf):
        lo = np.searchsorted(f, target / 1.03)
        hi = max(np.searchsorted(f, target * 1.03), lo + 1)
        rows[i] = mag[lo:hi].max(axis=0)
    # resample time to the requested width
    if rows.shape[1] != width:
        idx = np.linspace(0, rows.shape[1] - 1, width)
        rows = np.stack([np.interp(idx, np.arange(rows.shape[1]), r) for r in rows])
    peak = float(rows.max())
    norm = (rows - (peak + db_floor)) / (-db_floor)
    img = colourise(norm)[::-1]          # low frequencies at the bottom
    return img, lf, len(mono) / SR


def draw_plot(path_out: str, x: np.ndarray, title: str, subtitle: str = "") -> str:
    img, lf, seconds = spectrogram(x)
    h, w, _ = img.shape
    pad_l, pad_t, pad_b, pad_r = 66, 34, 34, 12
    canvas = Image.new("RGB", (w + pad_l + pad_r, h + pad_t + pad_b), (14, 15, 20))
    canvas.paste(Image.fromarray(img), (pad_l, pad_t))
    d = ImageDraw.Draw(canvas)
    d.text((8, 9), title, fill=(235, 232, 226))
    if subtitle:
        d.text((max(pad_l, w - 8 * len(subtitle)), 9), subtitle, fill=(150, 160, 175))
    # frequency gridlines
    for hz in (50, 100, 200, 500, 1000, 2000, 5000, 10000):
        if hz < lf[0] or hz > lf[-1]:
            continue
        row = int(np.argmin(np.abs(lf - hz)))
        y = pad_t + (h - 1 - row)
        d.line([(pad_l, y), (pad_l + w, y)], fill=(255, 255, 255, 40), width=1)
        d.text((6, y - 6), ("%gk" % (hz / 1000)) if hz >= 1000 else str(hz), fill=(150, 160, 175))
    # time gridlines
    step = 10 if seconds <= 60 else 20
    for s in range(0, int(seconds) + 1, step):
        px = pad_l + int(s / max(seconds, 1e-6) * (w - 1))
        d.line([(px, pad_t), (px, pad_t + h)], fill=(255, 255, 255, 30), width=1)
        d.text((px - 8, pad_t + h + 8), "%ds" % s, fill=(150, 160, 175))
    d.text((6, pad_t + h + 8), "Hz", fill=(150, 160, 175))
    os.makedirs(os.path.dirname(path_out), exist_ok=True)
    canvas.save(path_out)
    return path_out


def _looping_files() -> set:
    """Which files are actually loops, from the manifests, so a one-shot is not measured as
    one. An ambience pool variant starts and ends in silence by design; asking what its level
    does across a "wrap" it never has produces a large and meaningless number."""
    loops: set = set()
    amb = os.path.join(AUDIO_ROOT, "ambience", "manifest.json")
    if os.path.exists(amb):
        with open(amb) as f:
            for key, entry in json.load(f).items():
                if str(entry.get("kind", "")) == "bed":
                    for p in entry.get("files", []):
                        loops.add(str(p).replace("res://assets/audio/", ""))
    music = os.path.join(AUDIO_ROOT, "music", "manifest.json")
    if os.path.exists(music):
        with open(music) as f:
            m = json.load(f)
        for entry in m.get("regions", {}).values():
            for v in entry.get("stems", {}).values():
                loops.add(str(v.get("path", "")).replace("res://assets/audio/", ""))
        for v in m.get("pieces", {}).values():
            loops.add(str(v.get("path", "")).replace("res://assets/audio/", ""))
    return {p for p in loops if p}


def walk_audio(only=None):
    for dirpath, _dirs, files in os.walk(AUDIO_ROOT):
        for f in sorted(files):
            if not f.lower().endswith((".ogg", ".wav")):
                continue
            p = os.path.join(dirpath, f)
            rel = os.path.relpath(p, AUDIO_ROOT).replace(os.sep, "/")
            if only and not any(o in rel for o in only):
                continue
            yield p, rel


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", nargs="*")
    ap.add_argument("--table", action="store_true", help="skip the images")
    ap.add_argument("--limit", type=int, default=0, help="stop after N files (images)")
    args = ap.parse_args()

    os.makedirs(OUT_DIR, exist_ok=True)
    rows = []
    made = 0
    loops = _looping_files()
    for path, rel in walk_audio(args.only):
        audio, sr = load_audio(path)
        info = render.analyse(audio)
        info.update(render.spectral_balance(audio))
        if rel in loops:
            info.update(render.seam_report(audio))
        info["file"] = rel
        info["bytes"] = os.path.getsize(path)
        rows.append(info)
        if not args.table and (args.limit == 0 or made < args.limit):
            out = os.path.join(OUT_DIR, rel.rsplit(".", 1)[0] + ".png")
            sub = "%.1f s  %.1f LUFS  peak %.1f dB" % (info["seconds"], info["lufs"], info["peak_db"])
            draw_plot(out, audio, rel, sub)
            made += 1

    rows.sort(key=lambda r: r["file"])
    table_path = os.path.join(OUT_DIR, "loudness.md")
    with open(table_path, "w") as f:
        f.write("# Wickmere audio report\n\n")
        f.write("%d files, %.1f MB total.\n\n" % (len(rows), sum(r["bytes"] for r in rows) / 1e6))
        f.write("Bands are energy relative to the whole file, in dB. `seam` is the level step at "
                "a loop's wrap point and `local` the level step this material takes between any "
                "two neighbouring windows; a seam at or below `local` does not stand out.\n\n")
        head = ("| file | s | ch | LUFS | peak | true pk | crest | corr | 20-120 | 120-500 | "
                "500-2k | 2k-6k | 6k-20k | seam | local | click |")
        f.write(head + "\n")
        f.write("|" + "---|" * 16 + "\n")
        for r in rows:
            f.write("| `%s` | %.0f | %d | %.1f | %.1f | %.1f | %.1f | %s | %.0f | %.0f | %.0f | "
                    "%.0f | %.0f | %s | %s | %s |\n" % (
                        r["file"], r["seconds"], r["channels"], r["lufs"], r["peak_db"],
                        r["true_peak_db"], r["crest_db"],
                        ("%.2f" % r["correlation"]) if "correlation" in r else "-",
                        r["20_120"], r["120_500"], r["500_2000"], r["2000_6000"], r["6000_20000"],
                        ("%.1f" % r["seam_rms_db"]) if "seam_rms_db" in r else "-",
                        ("%.1f" % r["local_step_db"]) if "local_step_db" in r else "-",
                        ("%.1f" % r["seam_click_db"]) if "seam_click_db" in r else "-"))
    with open(os.path.join(OUT_DIR, "report.json"), "w") as f:
        json.dump(rows, f, indent=2, sort_keys=True)
    print("[report] %d files -> %s" % (len(rows), table_path))
    if not args.table:
        print("[report] %d spectrograms in %s" % (made, OUT_DIR))
    return 0


if __name__ == "__main__":
    sys.exit(main())
