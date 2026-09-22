"""How far across a settlement's platform a point lies.

`apply_pads` flattens a disc of ground at every named place and hands back a boolean mask,
which answers "is a village here" and nothing else. Everything that reads it treated the
whole disc alike, and for the scatter that meant no plant of any kind anywhere on it -- so
each village sat in the middle of a mown lawn up to eighty metres across, and the street
shot of Merrowby, taken 46 m from the centre of a 63.7 m pad, contained no growing thing.

A verge is not the green. This returns a normalised radius instead of a flag: 0 at the
place's own position, 1 at the edge of its pad, and large out in the country. The scatter
rules use it to keep houses and the green clear while letting rough grass back in at the
foot of the walls, and anything else that wants to treat the middle of a settlement
differently from its edge can read the same field.
"""
from __future__ import annotations

import numpy as np

from .grid import Grid
from .roads import pad_radius

FAR = 9.0


def pad_distance(grid: Grid, places: list) -> np.ndarray:
    """float32 [n, n]: distance to the nearest place, as a fraction of that place's pad radius.

    Computed in a window per place, the way `apply_pads` flattens them, so the cost is the
    area of the pads rather than the area of the world.
    """
    n = grid.n
    X, Z = grid.mesh()
    out = np.full((n, n), FAR, dtype=np.float32)
    for p in places:
        px, pz = float(p["position"][0]), float(p["position"][1])
        r = max(pad_radius(p), 1e-3)
        j, i = grid.to_tex(px, pz)
        j, i = grid.clamp_index(j, i)
        # far enough out that the field is valid well beyond the pad itself, which is what
        # a rule asking for "the outer quarter of the pad" needs to see
        rad_t = max(int((r * 2.5) / grid.spacing) + 4, 3)
        i0, i1 = max(0, int(i) - rad_t), min(n, int(i) + rad_t + 1)
        j0, j1 = max(0, int(j) - rad_t), min(n, int(j) + rad_t + 1)
        if i0 >= i1 or j0 >= j1:
            continue
        dx = X[:, j0:j1] - px
        dz = Z[i0:i1, :] - pz
        d = np.sqrt(dx * dx + dz * dz) / r
        np.minimum(out[i0:i1, j0:j1], d.astype(np.float32), out=out[i0:i1, j0:j1])
    return out
