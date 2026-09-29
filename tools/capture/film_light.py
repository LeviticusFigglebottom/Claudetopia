#!/usr/bin/env python3
"""How bright each frame of a film is, and whether any is blown (TRIAGE item 54).

    tools/capture/film_light.py <frames dir> [<frames dir> ...] [--json out.json] [--no-check]
    tools/capture/film_light.py --shoot [--films ranger,warrior,mage,rogue,title] [--out captures/film_light]

Reads every <dir>/*.png: the frames `./run.sh shots tools/capture/plans/film_<style>.json` writes
for a style's film, or `tools_gd/title_film.gd` for the title's vista. For each it measures the
picture between the letterbox bars (rows that are black from edge to edge, top and bottom):

  * mean  -- the mean luminance (Rec. 709 weights on the sRGB values, 0-1);
  * p99   -- the 99th-percentile luminance;
  * blown -- the share of pixels at BLOWN or over: white or nearly (an orange sky at full red
             is not blown; a sun disc, a white-hot sky round it or a sunlit wall clipped to white is).

and fails (exit 1) if any frame's mean or blown share is over the caps below; p99 is reported.
The caps are for the Compatibility renderer, which is all a machine with no GPU can draw, with a
margin under what Forward+ adds: Forward+ glows in full HDR (the sun disc, the sky round a low sun,
water's glints) and on the "painted" preset scatters the sun in volumetric fog. Measured on
2026-09-29 (960x540, mid-shot; PROGRESS "The Ranger's film out of the sun"): the Warrior's film
mean 0.26-0.40 with nothing blown, the Mage's 0.36-0.50 with up to 2.5% blown (a white lighthouse
against white crags), the Rogue's night 0.05-0.08. A cap is where a frame is plainly out of family,
not where a bright subject is; a low sun in the frame is the unit test's to catch
(test_cinematic_paths_clear.test_no_film_stares_into_a_low_sun), because Compatibility draws that
frame dark (the Ranger's lodge looking into the sun: mean 0.035), not blown.

--shoot runs the captures first (each through ~/bin/heavy when it is there, one after another),
into <out>/<film>/, then checks them. A film takes up to an hour on a loaded 4-core machine.
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import shutil
import subprocess
import sys

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

BLOWN = 0.95
MAX_MEAN = 0.58
MAX_BLOWN = 0.04

FILMS = {
    "ranger": "tools/capture/plans/film_ranger.json",
    "warrior": "tools/capture/plans/film_warrior.json",
    "mage": "tools/capture/plans/film_mage.json",
    "rogue": "tools/capture/plans/film_rogue.json",
    "title": None,  # tools_gd/title_film.tscn
}


def picture(img: np.ndarray) -> np.ndarray:
    """The rows between the letterbox bars: black edge to edge at the top and the bottom."""
    dark = img.max(axis=(1, 2)) <= 6
    top = 0
    while top < len(dark) and dark[top]:
        top += 1
    bottom = len(dark)
    while bottom > top and dark[bottom - 1]:
        bottom -= 1
    # the lower bar carries the words, so it is not black edge to edge: find it by its height,
    # the top bar's, which the letterbox makes the same
    if top > 0 and bottom == len(dark):
        bottom = len(dark) - top
    return img[top:bottom] if bottom - top > 16 else img


def light_of(path: str) -> dict:
    img = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0
    pic = picture(img)
    lum = pic[..., 0] * 0.2126 + pic[..., 1] * 0.7152 + pic[..., 2] * 0.0722
    return {"mean": round(float(lum.mean()), 3), "p99": round(float(np.percentile(lum, 99)), 3),
            "blown": round(float((lum >= BLOWN).mean()), 4), "rows": int(pic.shape[0])}


def check(dirs: list[str]) -> tuple[list[dict], list[str]]:
    rows: list[dict] = []
    faults: list[str] = []
    for d in dirs:
        frames = sorted(p for p in glob.glob(os.path.join(d, "*.png")) if not os.path.basename(p).startswith("cut_"))
        if not frames:
            faults.append(f"{d}: no frames")
        for p in frames:
            r = {"film": os.path.basename(os.path.normpath(d)), "frame": os.path.basename(p), **light_of(p)}
            over = []
            if r["mean"] > MAX_MEAN:
                over.append(f"mean {r['mean']:.3f} > {MAX_MEAN}")
            if r["blown"] > MAX_BLOWN:
                over.append(f"blown {100 * r['blown']:.2f}% > {100 * MAX_BLOWN:.1f}%")
            r["over"] = over
            rows.append(r)
            if over:
                faults.append(f"{r['film']}/{r['frame']}: " + ", ".join(over))
    return rows, faults


def shoot(films: list[str], out: str) -> list[str]:
    godot = os.environ.get("GODOT", os.path.expanduser("~/godot/Godot_v4.7.2-stable_linux.x86_64"))
    heavy = os.path.expanduser("~/bin/heavy")
    wrap = [heavy] if os.path.exists(heavy) else []
    env = dict(os.environ, GODOT=godot)
    dirs = []
    for film in films:
        d = os.path.join(out, film)
        shutil.rmtree(d, ignore_errors=True)
        os.makedirs(d)
        if FILMS[film] is None:
            cmd = wrap + ["xvfb-run", "-a", "-s", "-screen 0 1600x900x24", godot, "--path", "game",
                          "--rendering-driver", "opengl3", "--audio-driver", "Dummy", "--resolution", "1600x900",
                          "res://tools_gd/title_film.tscn", "--", f"--out={d}", "--preset=high"]
        else:
            cmd = wrap + ["./run.sh", "shots", FILMS[film], f"--out={d}"]
        print("film_light: shooting", film, flush=True)
        subprocess.run(cmd, cwd=ROOT, env=env, check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        dirs.append(d)
    return dirs


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("dirs", nargs="*")
    ap.add_argument("--shoot", action="store_true")
    ap.add_argument("--films", default=",".join(FILMS))
    ap.add_argument("--out", default=os.path.join(ROOT, "captures", "film_light"))
    ap.add_argument("--json")
    ap.add_argument("--no-check", action="store_true", help="print the numbers, fail on nothing")
    a = ap.parse_args()
    dirs = list(a.dirs)
    if a.shoot:
        dirs += shoot([f for f in a.films.split(",") if f], a.out)
    if not dirs:
        ap.error("no frames: name directories or --shoot")
    rows, faults = check(dirs)
    for r in rows:
        print(f"{r['film']:>10} {r['frame']:<34} mean {r['mean']:.3f}  p99 {r['p99']:.3f}  blown {100 * r['blown']:5.2f}%"
              + ("   OVER" if r["over"] else ""))
    if a.json:
        with open(a.json, "w") as f:
            json.dump(rows, f, indent=1)
    if faults and not a.no_check:
        print(f"film_light: FAIL, {len(faults)} frame(s) over the caps (mean {MAX_MEAN}, blown {MAX_BLOWN})")
        for x in faults:
            print("  " + x)
        return 1
    print(f"film_light: {'PASS' if not faults else 'measured'}, {len(rows)} frames")
    return 0


if __name__ == "__main__":
    sys.exit(main())
