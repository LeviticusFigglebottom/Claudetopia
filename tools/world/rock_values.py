#!/usr/bin/env python3
"""The mean colour, in linear light, of every rock's albedo picture: game/world/rock_values.json.

The painted stone (game/world/rock_paint.gd) draws every rock between a floor and a ceiling of
value, so no stone reads as a hole in the frame (Cinderlea's fused stone was painted at 0.012) or
as white paper on a green slope (Hearthvale's chalk ledges and slabs at 0.33-0.41, which the
user's playtest 6 saw as "flat and out of place"). It needs each picture's mean to do that, and
reading it from the texture at run time would mean decompressing seventy pictures on the main
thread as the country streams in; so it is measured here, from the forge's PNGs, and read once.

    python3 tools/world/rock_values.py            # write the table
    python3 tools/world/rock_values.py --check    # exit 1 if it is out of date (the unit test does too)
"""
import json, os, sys
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ROCKS = os.path.join(ROOT, 'game', 'assets', 'models', 'rocks')
OUT = os.path.join(ROOT, 'game', 'world', 'rock_values.json')


def mean_linear(path):
    """Over the texels the stone's faces use: the atlas's unused padding is exact black (a third
    of a boulder's picture), and counting it made every stone read a third darker than it is."""
    a = np.asarray(Image.open(path).convert('RGB')).reshape(-1, 3)
    a = a[::7]
    a = a[a.sum(1) > 0].astype(np.float64) / 255.0
    lin = np.where(a <= 0.04045, a / 12.92, ((a + 0.055) / 1.055) ** 2.4)
    return [round(float(v), 4) for v in lin.mean(0)]


## Landmarks drawn in the painted stone (RockPaint.LANDMARKS), measured alike.
LANDMARKS = ['hearthvale_cracked_toll_a', 'cinderlea_choir_colossus_a', 'cinderlea_choir_colossus_b',
             'cinderlea_choir_colossus_c']


def table():
    out = {}
    for name in sorted(os.listdir(ROCKS)):
        png = os.path.join(ROCKS, name, name + '_albedo.png')
        if os.path.isfile(png):
            out[name] = mean_linear(png)
    for name in LANDMARKS:
        png = os.path.join(ROOT, 'game', 'assets', 'models', 'landmarks', name, name + '_albedo.png')
        if os.path.isfile(png):
            out[name] = mean_linear(png)
    return out


def main():
    t = table()
    text = json.dumps({"note": "Mean linear albedo (r, g, b) of each rock's picture, by tools/world/rock_values.py.",
                       "rocks": t}, indent=1) + "\n"
    if '--check' in sys.argv:
        old = open(OUT).read() if os.path.exists(OUT) else ''
        if old != text:
            print('rock_values.json is out of date: python3 tools/world/rock_values.py')
            return 1
        print('rock_values.json: %d rocks, current' % len(t))
        return 0
    open(OUT, 'w').write(text)
    print('wrote %s: %d rocks' % (os.path.relpath(OUT, ROOT), len(t)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
