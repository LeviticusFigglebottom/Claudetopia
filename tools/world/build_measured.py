#!/usr/bin/env python3
"""Run the world builder and say what it cost: its wall time and the peak resident memory of the
build process (the child's ru_maxrss), on one line at the end.

    python3 tools/world/build_measured.py --out /tmp/w                # the atlas world at 4096
    python3 tools/world/build_measured.py --out /tmp/w --size 1024    # a preview

Every argument goes to build_world.py as given. The builder's stage lines already end with the
peak so far; this is the number for the whole run, measured from outside it. Use
`build_when_free.sh` to wait for the memory first.
"""
import os
import resource
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))

t0 = time.time()
rc = subprocess.call([sys.executable, os.path.join(HERE, "build_world.py")] + sys.argv[1:], cwd=REPO)
wall = time.time() - t0
if rc < 0:
    rc = 128 - rc       # killed by a signal: say so as a shell would (the OOM killer's 9 is 137)
peak_kb = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
print("[measure] rc=%d wall=%.1fs peak_rss=%.2f GB" % (rc, wall, peak_kb / 1024.0 / 1024.0), flush=True)
sys.exit(rc)
