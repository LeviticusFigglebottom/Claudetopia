"""Common main() for generators: parse args, pick palette/seed/name, build, finish."""
from __future__ import annotations

import random
import sys
import traceback

from . import cli, export, palette, scene


def run_generator(description: str, kinds: dict, category: str, generator: str, argv=None,
                  version: int = export.FORGE_VERSION) -> dict | None:
    """kinds: {kind_name: builder(pal, rng, params, variant) -> spec dict for finish_asset}."""
    args = cli.parse(description, argv)
    if args.list:
        for k in sorted(kinds):
            print(k)
        return None
    kind = args.kind or sorted(kinds)[0]
    if kind not in kinds:
        raise SystemExit("unknown kind %r; --list shows the options" % kind)
    pal = palette.get_palette(args.palette)
    seed = cli.derive_seed(args.seed, args.variant_index, kind)
    name = args.name or cli.default_name(args.palette_short, kind, args.variant)
    cli.validate_name(name)
    scene.reset()
    rng = random.Random(seed)
    try:
        spec = kinds[kind](pal, rng, dict(args.params), args.variant_index)
    except Exception:
        traceback.print_exc()
        print("FORGE_FAIL %s/%s (build)" % (category, name))
        sys.exit(3)
    spec = dict(spec)
    tier = spec.pop("tier", None)
    unwrap_mode = spec.pop("unwrap_mode", "smart")
    # An asset that hangs from a beam or floats on water has no ground contact to settle.
    extra = spec.get("extra_meta") or {}
    ground = spec.pop("ground", not (extra.get("hangs") or extra.get("floats")
                                     or extra.get("attaches_to")))
    try:
        meta = export.finish_asset(
            out_root=args.out, category=args.category or category, name=name, generator=generator, seed=args.seed,
            kind=kind, params=args.params, pal=pal, quick=args.quick, res=args.res,
            tier=tier, unwrap_mode=unwrap_mode, ground=ground,
            write_import=not args.no_import_files, rng=rng, version=version, **spec)
    except Exception:
        traceback.print_exc()
        print("FORGE_FAIL %s/%s (finish)" % (category, name))
        sys.exit(4)
    return meta
