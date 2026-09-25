#!/usr/bin/env python3
"""Shoot a capture plan on Forward+ (the renderer players use) on a machine with no GPU.

    python3 tools/capture/forward_plus.py tools/capture/plans/start.json captures/fplus_start
        [--lods 7] [--attempts 4] [--res 1280x720] [--fps 20] [--min-gb 6] [--lock PATH]

Runs `godot --rendering-driver vulkan --rendering-method forward_plus` under xvfb, which on a
machine without a GPU is Mesa's software Vulkan (lavapipe), about four seconds a frame. Lavapipe
has three faults to plan round:

  * it segfaults drawing Terrain3D's full clipmap (9 rings), so this asks for fewer with
    `--terrain-lods` (7 works; a few far vistas never render at any count);
  * it crashes every few teleports (after a "caller thread can't call propagate_notification()"
    error), so each attempt shoots only the shots with no frame yet, and the next attempt
    starts a fresh process for the rest;
  * it crashes on a moving camera, so plans for this should be still shots.

Every frame lands in <out>/<label>.png. Before each attempt it waits until `--min-gb` GB of
memory is available and no world build holds `--lock` (a lock younger than 45 minutes), so it can
share a machine. It proves nothing about Terrain3D on a real GPU: see PROGRESS.md.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def available_gb() -> int:
    with open("/proc/meminfo") as f:
        for line in f:
            if line.startswith("MemAvailable:"):
                return int(line.split()[1]) // (1024 * 1024)
    return 0


def wait_turn(min_gb: int, lock: str) -> None:
    while True:
        if lock and os.path.exists(lock) and time.time() - os.path.getmtime(lock) < 2700:
            print("[fplus] a world build holds %s; waiting" % lock, flush=True)
        elif available_gb() < min_gb:
            print("[fplus] %d GB available, want %d; waiting" % (available_gb(), min_gb), flush=True)
        else:
            return
        time.sleep(60)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("plan")
    ap.add_argument("out")
    ap.add_argument("--lods", type=int, default=7)
    ap.add_argument("--attempts", type=int, default=4)
    ap.add_argument("--res", default="1280x720")
    ap.add_argument("--fps", type=int, default=20)
    ap.add_argument("--min-gb", type=int, default=6)
    ap.add_argument("--lock", default="")
    ap.add_argument("--timeout", type=int, default=7200)
    args = ap.parse_args()

    plan = json.load(open(args.plan))
    shots = plan["shots"]
    out = os.path.abspath(args.out)
    os.makedirs(out, exist_ok=True)
    log_path = out + ".log"
    env = dict(os.environ, LP_NUM_THREADS=os.environ.get("LP_NUM_THREADS", "2"))
    # this checkout's own user:// (tools/godot_env.sh), and no settings.cfg an earlier run left in it
    env["XDG_DATA_HOME"] = os.environ.get("WICKMERE_USER_HOME") or os.path.join(ROOT, ".godot_user")
    stale = os.path.join(env["XDG_DATA_HOME"], "godot", "app_userdata", "Wickmere", "settings.cfg")
    if os.path.exists(stale):
        os.unlink(stale)
    for n in range(args.attempts):
        left = [s for s in shots if not os.path.exists(os.path.join(out, s["label"] + ".png"))]
        if not left:
            break
        print("[fplus] attempt %d: %d shots left: %s" % (n, len(left), ", ".join(s["label"] for s in left)), flush=True)
        wait_turn(args.min_gb, args.lock)
        with tempfile.TemporaryDirectory() as tmp:
            sub_plan = os.path.join(tmp, "plan.json")
            json.dump(dict(plan, shots=left), open(sub_plan, "w"), indent=1)
            shot_dir = os.path.join(tmp, "frames")
            os.makedirs(shot_dir)
            cmd = ["timeout", str(args.timeout), "xvfb-run", "-a", "-s", "-screen 0 %sx24" % args.res,
                   "godot", "--path", os.path.join(ROOT, "game"), "--rendering-driver", "vulkan",
                   "--rendering-method", "forward_plus", "--audio-driver", "Dummy", "--resolution", args.res,
                   "--fixed-fps", str(args.fps), "--", "--capture=" + sub_plan, "--out=" + shot_dir,
                   "--terrain-lods=%d" % args.lods]
            with open(log_path, "a") as log:
                log.write("\n# attempt %d: %s\n" % (n, " ".join(cmd)))
                log.flush()
                code = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, env=env).returncode
                log.write("# EXIT %d\n" % code)
            for f in sorted(os.listdir(shot_dir)):
                if f.endswith(".png") and "_" in f:
                    shutil.copy2(os.path.join(shot_dir, f), os.path.join(out, f.split("_", 1)[1]))
                elif f == "perf.json":
                    shutil.copy2(os.path.join(shot_dir, f), os.path.join(out, "perf_attempt%d.json" % n))
    left = [s["label"] for s in shots if not os.path.exists(os.path.join(out, s["label"] + ".png"))]
    print("[fplus] %d of %d shots in %s%s (log %s)" % (len(shots) - len(left), len(shots), out,
                                                      "; missing " + ", ".join(left) if left else "", log_path))
    return 1 if left else 0


if __name__ == "__main__":
    sys.exit(main())
