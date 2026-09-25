#!/usr/bin/env python3
"""The character presets are the same from one forge run to the next.

    python3 tools/forge/tests/test_presets.py

The presets were seeded with Python's hash() of a str, which is salted per process, so every run
of `character_forge.py presets` wrote them with new seeds. A seed now comes from the committed
table or a stable hash; this runs the seeding in two interpreters with different hash salts and
compares, and checks the committed presets still carry the seeds the table pins."""
from __future__ import annotations

import json
import os
import subprocess
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
FORGE = os.path.join(ROOT, "tools", "forge")

CODE = ("import sys; sys.path.insert(0, %r); sys.path.insert(0, %r); import character_forge as cf; "
        "print(cf._preset('vale', _n='bandit')['seed'], cf._preset('woodfolk', _n='not_yet_written')['seed'])"
        % (FORGE, os.path.dirname(FORGE)))


class TestPresetSeeds(unittest.TestCase):
    def test_a_preset_seed_is_the_same_in_every_process(self):
        outs = set()
        for salt in ("1", "2", "3"):
            env = dict(os.environ, PYTHONHASHSEED=salt)
            outs.add(subprocess.check_output([sys.executable, "-c", CODE], env=env, cwd=ROOT).strip())
        self.assertEqual(len(outs), 1, "the seeds changed with the hash salt: %s" % outs)

    def test_the_committed_presets_keep_their_seeds(self):
        sys.path.insert(0, FORGE)
        sys.path.insert(0, os.path.dirname(FORGE))
        import character_forge as cf
        presets = json.load(open(os.path.join(FORGE, "characters.json")))["presets"]
        for pid, p in presets.items():
            self.assertEqual(p["seed"], cf.PRESET_SEEDS.get(pid, p["seed"]), pid)


if __name__ == "__main__":
    unittest.main()
