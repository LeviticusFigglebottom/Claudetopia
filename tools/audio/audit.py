#!/usr/bin/env python3
"""Audit every audio file the game ships, the way a mix engineer would before a release.

report.py draws the spectrograms and the loudness table; this reads the same files and asks the
questions that fail a release, per file and per category:

  * clipping     -- samples at full scale, and a true peak above -1 dBTP (no headroom left for
                    the OGG encoder or the mix bus);
  * DC offset    -- a mean far enough from zero to cost headroom and thump on start and stop;
  * silence      -- a file that is silent, a one-shot that starts late (latency on every play),
                    a one-shot that starts or ends hot (a click as the player starts or stops
                    it), and a continuous bed that drops to digital silence (the world goes dead);
  * loop seams   -- a click at the wrap (the sample step against this waveform's own steps,
                    render.seam_click_db) and a level break at the wrap that is larger, in its
                    direction, than anything the piece does elsewhere (a downbeat after a quiet
                    bar is music; a sustain cut off at the loop point is not);
  * loudness     -- per category: music stems against their own stem across regions, beds
                    against beds, pool one-shots against pool one-shots. A sound effect is
                    measured by its loudest 400 ms (integrated loudness means nothing for a 90 ms
                    click) plus the level core:table/sfx plays it at, and asked two things: are
                    its variants the same loudness (a random loud footstep is a fault), and does
                    the id sit within reach of its family (a hover tick is meant to be quieter
                    than a page turn, so the family bar is wide).

    python3 tools/audio/audit.py                    # everything; the flagged files and a summary
    python3 tools/audio/audit.py --only sfx/chest   # a subset
    python3 tools/audio/audit.py --json out.json --md out.md
    python3 tools/audio/audit.py --strict           # exit 1 if anything is flagged

The thresholds are constants below, each with the reason for its value.
"""
from __future__ import annotations

import argparse
import json
import os
import statistics
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import report  # noqa: E402
from synth import core, render  # noqa: E402
from synth.core import SR  # noqa: E402

ROOT = report.ROOT
AUDIO_ROOT = report.AUDIO_ROOT
SFX_TABLE = os.path.join(ROOT, "game", "content", "packs", "core", "tables", "sfx.json")

## A sample this close to full scale is clipped (or about to be, after the encoder's overshoot).
CLIP_CEILING = 0.999
## True peak above this leaves the OGG encoder and the bus no room (EBU R128 asks for -1 dBTP).
TRUE_PEAK_MAX_DB = -1.0
## A mean this far from zero is a DC offset worth removing (-54 dBFS).
DC_MAX = 0.002
## Silence, for these checks, is below this level.
SILENCE_DB = -60.0
## Digital silence -- no noise floor at all -- is below this.
DEAD_DB = -90.0
## A one-shot that has not started this long after it is triggered is late (a frame and a half).
LATE_START_S = 0.025
## A one-shot whose first or last sample is above this starts or stops with a click.
HOT_EDGE_DB = -40.0
## A continuous bed may not drop to digital silence for longer than this.
DEAD_BED_S = 0.25
## A click at a loop's wrap: the README's bar for the sample-step measure.
SEAM_CLICK_DB = 6.0
## A level break at the wrap may exceed the largest same-direction step the piece takes anywhere
## else by this much before it is a break rather than music. (Not a percentile: a drone struck
## again every four bars rises six times in a hundred seconds, fewer than one window in two
## hundred, and a high percentile misses exactly the events the wrap should be compared with.)
SEAM_BREAK_MARGIN_DB = 6.0
## How far from its category's median a file may sit (LU) before it is out of the category.
LOUDNESS_SPREAD_LU = 6.0
## How far one variant of a sound effect may sit from the id's median variant (LU).
VARIANT_SPREAD_LU = 4.0
## How far a sound effect's median variant may sit from its family's median id (LU): the families
## mix sounds meant to differ (a hover tick and a page turn), so only a mix mistake is this far out.
FAMILY_SPREAD_LU = 10.0


# --- measures ------------------------------------------------------------------------------------

def clipped_samples(x: np.ndarray, ceiling: float = CLIP_CEILING) -> int:
    return int(np.count_nonzero(np.abs(np.asarray(x, dtype=np.float64)) >= ceiling))


def _db(v: float) -> float:
    return float(20.0 * np.log10(abs(v) + 1e-12))


def envelope_db(x: np.ndarray, window_s: float = 0.01) -> np.ndarray:
    """RMS level per window (dB), mono."""
    m = core.to_mono(np.asarray(x, dtype=np.float64))
    w = max(1, int(window_s * SR))
    n = len(m) // w
    if n == 0:
        return np.array([_db(float(np.sqrt(np.mean(np.square(m))))) if len(m) else -240.0])
    blocks = m[:n * w].reshape(n, w)
    return 20.0 * np.log10(np.sqrt(np.mean(np.square(blocks), axis=1)) + 1e-12)


def leading_silence_s(x: np.ndarray, floor_db: float = SILENCE_DB) -> float:
    """How long before the file first rises above `floor_db` relative to its own peak."""
    m = np.abs(core.to_mono(np.asarray(x, dtype=np.float64)))
    peak = float(m.max()) if len(m) else 0.0
    if peak <= 0.0:
        return len(m) / SR
    idx = np.flatnonzero(m > peak * core.db_to_lin(floor_db))
    return float(idx[0]) / SR if len(idx) else len(m) / SR


def edge_levels_db(x: np.ndarray) -> tuple:
    """The first and the last sample's level, dBFS (a one-shot should begin and end at zero)."""
    m = core.to_mono(np.asarray(x, dtype=np.float64))
    if not len(m):
        return (-240.0, -240.0)
    return (_db(float(m[0])), _db(float(m[-1])))


def dead_runs_s(x: np.ndarray, floor_db: float = DEAD_DB, window_s: float = 0.01) -> list:
    """Stretches of digital silence, as (start s, length s), including a stretch that runs off
    the end into the start (a bed loops)."""
    env = envelope_db(x, window_s)
    dead = env < floor_db
    runs = []
    i = 0
    n = len(dead)
    while i < n:
        if dead[i]:
            j = i
            while j < n and dead[j]:
                j += 1
            runs.append([i * window_s, (j - i) * window_s])
            i = j
        else:
            i += 1
    # a run touching the end continues into one touching the start
    if len(runs) >= 2 and dead[0] and dead[-1]:
        runs[0][1] += runs[-1][1]
        runs[0][0] = runs[-1][0]
        runs.pop()
    return [tuple(r) for r in runs]


def seam_break(x: np.ndarray, window_s: float = 0.05) -> dict:
    """The level change across a loop's wrap, signed (+ is a rise into the start), beside the
    largest change the piece makes in the same direction anywhere else."""
    env = envelope_db(x, window_s)
    env = np.maximum(env, -120.0)
    if len(env) < 4:
        return {"wrap_db": 0.0, "own_db": 0.0, "excess_db": 0.0}
    wrap = float(env[0] - env[-1])
    steps = np.diff(env)
    same = steps[steps > 0] if wrap >= 0 else -steps[steps < 0]
    own = float(same.max()) if len(same) else 0.0
    return {"wrap_db": wrap, "own_db": own, "excess_db": abs(wrap) - own}


def momentary_max_lufs(x: np.ndarray) -> float:
    """The loudest 400 ms of a file, in LUFS (render.momentary_max_lufs)."""
    return render.momentary_max_lufs(x)


# --- what each file is ---------------------------------------------------------------------------

SFX_FAMILIES = [
    ("footsteps", ("footstep_",)),
    ("blows", ("impact_", "block_clang", "parry_clang", "stagger_thud", "arrow_hit")),
    ("swings", ("sword_swing", "axe_swing", "mace_swing", "arrow_whoosh", "bow_")),
    ("sayings", ("spell_",)),
    ("handling", ("door_", "chest_open", "coins_", "pick_up", "eat", "potion_drink", "lockpick_", "armour_")),
    ("interface", ("ui_",)),
    ("cues", ("hearthstone_rest", "echo_recovered", "player_death")),
    ("the world", ("bell_", "thunder_", "wind_gust", "wood_creak", "cart_wheels", "water_splash")),
]


def sfx_id_of(rel: str) -> str:
    # sfx/<id>/<id>_NN.ogg
    parts = rel.split("/")
    return parts[1] if len(parts) >= 3 else os.path.splitext(parts[-1])[0]


def category_of(rel: str, loops: set) -> str:
    parts = rel.split("/")
    if parts[0] == "music":
        name = os.path.splitext(parts[-1])[0]
        if "stinger" in rel:
            return "music: stinger"
        if name in ("pad", "melody", "texture", "combat", "deep"):
            return "music: %s stem" % name
        return "music: piece"
    if parts[0] == "ambience":
        return "ambience: bed" if rel in loops else "ambience: one-shot"
    if parts[0] == "sfx":
        sid = sfx_id_of(rel)
        for family, heads in SFX_FAMILIES:
            if any(sid.startswith(h) for h in heads):
                return "sfx: " + family
        return "sfx: other"
    return parts[0]


def sfx_levels() -> dict:
    """id -> the volume_db core:table/sfx plays it at."""
    try:
        with open(SFX_TABLE) as f:
            rows = json.load(f).get("rows", {})
    except (OSError, ValueError):
        return {}
    return {k: float(v.get("volume_db", 0.0)) for k, v in rows.items()}


# --- the audit -----------------------------------------------------------------------------------

def measure(path: str, rel: str, loops: set, levels: dict) -> dict:
    audio, _sr = report.load_audio(path)
    info = render.analyse(audio)
    info["file"] = rel
    info["category"] = category_of(rel, loops)
    info["loop"] = rel in loops
    info["clipped"] = clipped_samples(audio)
    info["leading_silence_s"] = leading_silence_s(audio)
    first, last = edge_levels_db(audio)
    info["first_db"] = first
    info["last_db"] = last
    info["dead_runs"] = dead_runs_s(audio)
    if info["loop"]:
        info["seam_click_db"] = render.seam_click_db(audio)
        info.update({"seam_" + k: v for k, v in seam_break(audio).items()})
    if rel.startswith("sfx/"):
        sid = sfx_id_of(rel)
        info["sfx_id"] = sid
        info["momentary_lufs"] = momentary_max_lufs(audio)
        info["effective_lufs"] = info["momentary_lufs"] + levels.get(sid, 0.0)
    return info


def loudness_of(row: dict) -> float:
    """The loudness a file is compared on: a one-shot's loudest 400 ms at its table level;
    anything longer, its integrated loudness."""
    return float(row.get("effective_lufs", row["lufs"]))


def flag(rows: list) -> list:
    """Adds `flags` (a list of reasons) to every row and returns the rows that have any."""
    by_cat: dict = {}
    by_id: dict = {}
    for r in rows:
        if "sfx_id" in r:
            by_id.setdefault(r["sfx_id"], []).append(loudness_of(r))
        else:
            by_cat.setdefault(r["category"], []).append(loudness_of(r))
    medians = {c: statistics.median(v) for c, v in by_cat.items()}
    id_medians = {i: statistics.median(v) for i, v in by_id.items()}
    by_family: dict = {}
    for r in rows:
        if "sfx_id" in r:
            by_family.setdefault(r["category"], {})[r["sfx_id"]] = id_medians[r["sfx_id"]]
    family_medians = {c: statistics.median(list(v.values())) for c, v in by_family.items()}
    flagged = []
    for r in rows:
        f = []
        if r["clipped"] > 0:
            f.append("clipped: %d samples at full scale" % r["clipped"])
        if r["true_peak_db"] > TRUE_PEAK_MAX_DB:
            f.append("true peak %.1f dBTP (above %.0f)" % (r["true_peak_db"], TRUE_PEAK_MAX_DB))
        if abs(r["dc_offset"]) > DC_MAX:
            f.append("DC offset %.4f" % r["dc_offset"])
        if r["rms_db"] < -100.0:
            f.append("silent")
        if not r["loop"]:
            if r["leading_silence_s"] > LATE_START_S:
                f.append("starts %.0f ms late" % (r["leading_silence_s"] * 1000.0))
            if r["first_db"] > HOT_EDGE_DB:
                f.append("starts hot (%.0f dBFS first sample)" % r["first_db"])
            if r["last_db"] > HOT_EDGE_DB:
                f.append("ends hot (%.0f dBFS last sample)" % r["last_db"])
        else:
            # A music stem rests while the others play, so only a bed is held to never going dead.
            dead = [d for d in r["dead_runs"] if d[1] > DEAD_BED_S] if r["category"] == "ambience: bed" else []
            if dead:
                f.append("drops to digital silence: %s" % ", ".join("%.2f s at %.1f s" % (d[1], d[0]) for d in dead[:4]))
            if r.get("seam_click_db", -120.0) > SEAM_CLICK_DB:
                f.append("clicks at the wrap (%.1f dB over its own steps)" % r["seam_click_db"])
            if r.get("seam_excess_db", 0.0) > SEAM_BREAK_MARGIN_DB:
                f.append("level %s %.0f dB at the wrap, %.0f dB past anything else it does" % (
                    "rises" if r["seam_wrap_db"] >= 0 else "falls", abs(r["seam_wrap_db"]), r["seam_excess_db"]))
        if "sfx_id" in r:
            own = id_medians[r["sfx_id"]]
            off = loudness_of(r) - own
            r["variant_offset_lu"] = off
            if abs(off) > VARIANT_SPREAD_LU:
                f.append("%.1f LU %s the other variants of %s (median %.1f)" % (
                    abs(off), "above" if off > 0 else "below", r["sfx_id"], own))
            fam = own - family_medians[r["category"]]
            r["category_offset_lu"] = fam
            if abs(fam) > FAMILY_SPREAD_LU:
                f.append("%s sits %.1f LU %s its family (%s, median %.1f)" % (
                    r["sfx_id"], abs(fam), "above" if fam > 0 else "below", r["category"], family_medians[r["category"]]))
        else:
            off = loudness_of(r) - medians[r["category"]]
            r["category_offset_lu"] = off
            if abs(off) > LOUDNESS_SPREAD_LU:
                f.append("%.1f LU %s its category (%s, median %.1f)" % (abs(off), "above" if off > 0 else "below",
                         r["category"], medians[r["category"]]))
        r["flags"] = f
        if f:
            flagged.append(r)
    return flagged


def run(only=None) -> list:
    loops = report._looping_files()
    levels = sfx_levels()
    rows = []
    for path, rel in report.walk_audio(only):
        rows.append(measure(path, rel, loops, levels))
    flag(rows)
    return rows


def summary(rows: list) -> list:
    """Per category: files, loudness median and spread, the highest true peak, flagged files."""
    out = []
    cats: dict = {}
    for r in rows:
        cats.setdefault(r["category"], []).append(r)
    for c in sorted(cats):
        rs = cats[c]
        l = [loudness_of(r) for r in rs]
        out.append({"category": c, "files": len(rs), "median": statistics.median(l), "min": min(l),
                    "max": max(l), "true_peak": max(r["true_peak_db"] for r in rs),
                    "flagged": sum(1 for r in rs if r["flags"])})
    return out


def markdown(rows: list) -> str:
    lines = ["# Wickmere audio audit", "",
             "%d files. One-shot loudness is the loudest 400 ms at the level core:table/sfx plays "
             "it at; everything else is integrated loudness." % len(rows), "",
             "| category | files | median | min | max | max true peak | flagged |", "|---|---|---|---|---|---|---|"]
    for s in summary(rows):
        lines.append("| %s | %d | %.1f | %.1f | %.1f | %.1f | %d |" % (
            s["category"], s["files"], s["median"], s["min"], s["max"], s["true_peak"], s["flagged"]))
    bad = [r for r in rows if r["flags"]]
    lines += ["", "## Flagged (%d)" % len(bad), ""]
    for r in bad:
        lines.append("* `%s` — %s" % (r["file"], "; ".join(r["flags"])))
    return "\n".join(lines) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", nargs="*")
    ap.add_argument("--json")
    ap.add_argument("--md")
    ap.add_argument("--strict", action="store_true", help="exit 1 when anything is flagged")
    args = ap.parse_args()
    rows = run(args.only)
    text = markdown(rows)
    print(text)
    if args.md:
        with open(args.md, "w") as f:
            f.write(text)
    if args.json:
        with open(args.json, "w") as f:
            json.dump(rows, f, indent=1, sort_keys=True, default=float)
    flagged = sum(1 for r in rows if r["flags"])
    return 1 if (args.strict and flagged) else 0


if __name__ == "__main__":
    sys.exit(main())
