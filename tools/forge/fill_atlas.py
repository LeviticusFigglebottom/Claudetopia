"""Fill the uncovered texels of assets already baked (lib/atlas_fill.py).

    python3 tools/forge/fill_atlas.py game/assets/models/props/hearthvale_well_a [...]

The forge's bake does this itself now; this is for the atlases baked before it did, the ones of
hundreds of small islands whose far mips went dark: the well, Skerrow's drystone walls and wall
ends, the peat stacks. Each directory's <name>_albedo.png and <name>_orm.png are rewritten in
place (the normal map was always filled flat). Running it twice changes nothing.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib.atlas_fill import covered_of, fill_uncovered, shrink_mask  # noqa: E402


def fill_dir(d: Path) -> str:
    name = d.name
    albedo_p = d / ("%s_albedo.png" % name)
    orm_p = d / ("%s_orm.png" % name)
    if not albedo_p.exists():
        return "%s: no albedo" % name
    albedo = np.asarray(Image.open(albedo_p).convert("RGBA" if Image.open(albedo_p).mode == "RGBA" else "RGB"))
    covered = covered_of(albedo)
    share = float(covered.mean())
    filled = albedo.astype(np.float64)
    filled[..., :3] = fill_uncovered(filled[..., :3], covered)
    out = np.clip(np.round(filled), 0, 255).astype(np.uint8)
    Image.fromarray(out).save(albedo_p, optimize=True)
    if orm_p.exists():
        orm = np.asarray(Image.open(orm_p).convert("RGB"))
        small = shrink_mask(covered, orm.shape[:2])
        orm_f = fill_uncovered(orm.astype(np.float64), small)
        Image.fromarray(np.clip(np.round(orm_f), 0, 255).astype(np.uint8)).save(orm_p, optimize=True)
    return "%s: %.0f%% of the atlas was islands; the rest is filled" % (name, share * 100.0)


def main(argv: list[str]) -> int:
    if not argv:
        print(__doc__)
        return 2
    for a in argv:
        print(fill_dir(Path(a)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
