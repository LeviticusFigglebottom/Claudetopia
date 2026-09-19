"""Wickmere audio synthesis toolkit.

Everything the game hears is rendered by this package and the generators next to it
(gen_music.py, gen_ambience.py, gen_sfx.py). No samples, no third-party sounds: every
signal starts as an oscillator, a noise source or a resonator here.

Conventions: mono signals are 1-D float64 numpy arrays, stereo signals are (n, 2).
Sample rate is core.SR (44100). All randomness goes through core.rng(seed) so every
render is deterministic for a given seed.
"""
from . import core, osc, env, filters, fx, instruments, render, theory  # noqa: F401
from .core import SR, rng, midi_to_hz, hz_to_midi, db_to_lin, lin_to_db  # noqa: F401
