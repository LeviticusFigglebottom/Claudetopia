"""The default body's distance field, cached on disk (it takes minutes in numpy).

Kept at $FORGE_PREVIEW_CACHE, or in the system temp directory. Delete the file when the body
changes (tools/forge/lib/body.py or cloth.body_field): it is not checked against them."""
import os
import sys
import tempfile
from pathlib import Path
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import numpy as np
from forge.lib import rig, cloth, sdf

CACHE = os.environ.get("FORGE_PREVIEW_CACHE", os.path.join(tempfile.gettempdir(), "forge_bodyfield_default.npz"))


def body(skel=None, cache=CACHE):
    skel = skel or rig.Skeleton(rig.Proportions())
    if cache and os.path.exists(cache):
        z = np.load(cache)
        return sdf.SampledField.from_grid(z["F"], z["origin"], float(z["spacing"]))
    f = cloth.body_field(skel)
    if cache:
        np.savez(cache, F=f.F.astype(np.float32), origin=f.origin, spacing=f.spacing)
    return f
