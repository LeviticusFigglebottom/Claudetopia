"""Music theory helpers: modes, scale degrees, chords, voice leading and motif transformation.

The vocabulary is deliberately small and explicit so gen_music.py composes rather than
noodles: a mode is a list of semitone offsets, a chord is a list of MIDI notes, a motif is a
list of (scale_degree, beats, velocity) steps that transformations act on.
"""
from __future__ import annotations

from dataclasses import dataclass, replace

import numpy as np

# Modes as semitone offsets from the tonic. The region music_mode keys of regions.json map
# onto these plus a character (tempo, register, colour) chosen in gen_music.py.
MODES = {
    "ionian": [0, 2, 4, 5, 7, 9, 11],
    "dorian": [0, 2, 3, 5, 7, 9, 10],
    "phrygian": [0, 1, 3, 5, 7, 8, 10],
    "lydian": [0, 2, 4, 6, 7, 9, 11],
    "mixolydian": [0, 2, 4, 5, 7, 9, 10],
    "aeolian": [0, 2, 3, 5, 7, 8, 10],
    "locrian": [0, 1, 3, 5, 6, 8, 10],
}

# The region key ("lydian_warm") -> the mode name used above.
REGION_MODE = {
    "lydian_warm": "lydian",
    "ionian_bright": "ionian",
    "dorian_misty": "dorian",
    "aeolian_deep": "aeolian",
    "mixolydian_cold": "mixolydian",
    "phrygian_hollow": "phrygian",
}


def mode_of(music_mode: str) -> str:
    return REGION_MODE.get(music_mode, music_mode.split("_")[0])


def degree_to_midi(degree: int, tonic: int, mode: str) -> int:
    """Scale degree (0 = tonic, may be negative or > 6) to a MIDI note."""
    steps = MODES[mode]
    octave, idx = divmod(int(degree), len(steps))
    return int(tonic + 12 * octave + steps[idx])


def scale_notes(tonic: int, mode: str, low: int = 24, high: int = 108) -> list[int]:
    """Every MIDI note of the mode within a range, ascending."""
    steps = set(MODES[mode])
    return [n for n in range(low, high + 1) if (n - tonic) % 12 in steps]


def in_mode(note: int, tonic: int, mode: str) -> bool:
    return (int(note) - tonic) % 12 in MODES[mode]


def nearest_in_mode(note: float, tonic: int, mode: str) -> int:
    """Snap an arbitrary pitch to the closest note of the mode (ties go down, for gravity)."""
    cands = scale_notes(tonic, mode, int(note) - 12, int(note) + 12)
    return min(cands, key=lambda n: (abs(n - note), n))


# --- chords ---------------------------------------------------------------------------------

def triad(degree: int, tonic: int, mode: str, size: int = 3) -> list[int]:
    """Diatonic stack of thirds on a scale degree (size 3 = triad, 4 = seventh)."""
    return [degree_to_midi(degree + 2 * i, tonic, mode) for i in range(size)]


def chord_quality(notes: list[int]) -> str:
    """Rough label from the intervals above the root: maj, min, dim, aug, sus, other."""
    iv = sorted({(n - notes[0]) % 12 for n in notes[1:]})
    if 3 in iv and 6 in iv:
        return "dim"
    if 4 in iv and 8 in iv:
        return "aug"
    if 3 in iv:
        return "min"
    if 4 in iv:
        return "maj"
    if 5 in iv or 2 in iv:
        return "sus"
    return "other"


def invert(chord: list[int], times: int = 1) -> list[int]:
    c = sorted(chord)
    for _ in range(abs(times)):
        if times > 0:
            c = c[1:] + [c[0] + 12]
        else:
            c = [c[-1] - 12] + c[:-1]
    return sorted(c)


def voice_lead(prev: list[int], target: list[int], centre: int = 60, max_leap: int = 7) -> list[int]:
    """Re-voice `target` (pitch classes matter, octaves do not) so each voice moves as little as
    possible from `prev`. Greedy, one voice at a time, closest available chord tone wins."""
    if not prev:
        # first chord: pack the tones close around the centre
        out = []
        for pc in target:
            n = pc
            while n < centre - 6:
                n += 12
            while n > centre + 6:
                n -= 12
            out.append(n)
        return sorted(out)
    pcs = [t % 12 for t in target]
    out: list[int] = []
    used: list[int] = []
    for v in sorted(prev):
        best = None
        for i, pc in enumerate(pcs):
            if i in used:
                continue
            # candidate octaves near the previous voice
            for cand in (pc + 12 * k for k in range(0, 10)):
                if abs(cand - v) <= max_leap + 6:
                    if best is None or abs(cand - v) < abs(best[1] - v):
                        best = (i, cand)
        if best is None:
            best = (len(used) % len(pcs), prev[0])
        used.append(best[0])
        out.append(best[1])
    # any unused chord tone replaces the most redundant voice
    for i, pc in enumerate(pcs):
        if i not in used:
            n = pc
            while n < min(out) - 6:
                n += 12
            while n > max(out) + 6:
                n -= 12
            out[-1] = n
    return sorted(out)


def has_minor_second(notes: list[int]) -> bool:
    """True if any two simultaneous notes are a semitone (or a minor ninth) apart."""
    s = sorted(notes)
    for i in range(len(s)):
        for j in range(i + 1, len(s)):
            d = abs(s[j] - s[i])
            if d in (1, 13):
                return True
    return False


# --- motifs ----------------------------------------------------------------------------------

@dataclass(frozen=True)
class Step:
    """One motif note: a scale degree relative to the motif's root, a length in beats, a velocity."""
    degree: int
    beats: float
    vel: float = 0.8

    def t(self, **kw) -> "Step":
        return replace(self, **kw)


@dataclass(frozen=True)
class Motif:
    name: str
    steps: tuple

    def __len__(self) -> int:
        return len(self.steps)

    def duration(self) -> float:
        return sum(s.beats for s in self.steps)

    def degrees(self) -> list[int]:
        return [s.degree for s in self.steps]

    # --- transformations ---------------------------------------------------------------

    def transpose(self, by: int) -> "Motif":
        return Motif(self.name, tuple(s.t(degree=s.degree + by) for s in self.steps))

    def inverse(self, axis: int | None = None) -> "Motif":
        """Melodic inversion about the first degree (or an explicit axis)."""
        a = self.steps[0].degree if axis is None else axis
        return Motif(self.name + "_inv", tuple(s.t(degree=2 * a - s.degree) for s in self.steps))

    def retrograde(self) -> "Motif":
        return Motif(self.name + "_retro", tuple(reversed(self.steps)))

    def augment(self, factor: float = 2.0) -> "Motif":
        return Motif(self.name + "_aug", tuple(s.t(beats=s.beats * factor) for s in self.steps))

    def diminish(self, factor: float = 2.0) -> "Motif":
        return Motif(self.name + "_dim", tuple(s.t(beats=s.beats / factor) for s in self.steps))

    def sequence(self, offsets, gap_beats: float = 0.0) -> "Motif":
        """Restate the motif at each offset in turn (a melodic sequence)."""
        steps: list[Step] = []
        for k, off in enumerate(offsets):
            for i, s in enumerate(self.steps):
                b = s.beats
                if gap_beats and i == len(self.steps) - 1 and k != len(offsets) - 1:
                    b += gap_beats
                steps.append(s.t(degree=s.degree + off, beats=b))
        return Motif(self.name + "_seq", tuple(steps))

    def fragment(self, count: int) -> "Motif":
        return Motif(self.name + "_frag", tuple(self.steps[:count]))

    def stretch_last(self, beats: float) -> "Motif":
        steps = list(self.steps)
        steps[-1] = steps[-1].t(beats=beats)
        return Motif(self.name, tuple(steps))

    def with_velocity(self, scale: float) -> "Motif":
        return Motif(self.name, tuple(s.t(vel=float(np.clip(s.vel * scale, 0.05, 1.0))) for s in self.steps))

    def to_notes(self, tonic: int, mode: str, root_degree: int = 0, start_beat: float = 0.0):
        """Realise as [(start_beat, beats, midi_note, velocity)] in a mode."""
        out = []
        b = start_beat
        for s in self.steps:
            out.append((b, s.beats, degree_to_midi(s.degree + root_degree, tonic, mode), s.vel))
            b += s.beats
        return out


# The Toll: the game's leitmotif. Five notes, a bell struck and answered: rise a fourth, fall
# back through the third, and settle a step below the tonic before returning. Every region theme
# states it transformed (WORLD_BIBLE §1.1: "the world is the ringing of a bell struck once").
TOLL = Motif("toll", (
    Step(0, 2.0, 0.95),
    Step(3, 1.0, 0.75),
    Step(2, 1.0, 0.70),
    Step(-1, 2.0, 0.65),
    Step(0, 2.0, 0.80),
))

# A shorter answering figure used for stingers and bell punctuation (the Toll's first three notes).
TOLL_SHORT = TOLL.fragment(3)


def motif_library() -> dict:
    """Named motifs available to the composer, all derived from or answering the Toll."""
    return {
        "toll": TOLL,
        "toll_short": TOLL_SHORT,
        "toll_inv": TOLL.inverse(),
        "toll_aug": TOLL.augment(2.0),
        "toll_dim": TOLL.diminish(2.0),
        "toll_retro": TOLL.retrograde(),
        # "the answer": a warm cadential tag the villages sing back at the bell
        "answer": Motif("answer", (Step(4, 1.0, 0.7), Step(2, 1.0, 0.7), Step(1, 1.0, 0.65), Step(0, 3.0, 0.8))),
        # "the hush": three falling steps that die away (deep places, Cinderlea)
        "hush": Motif("hush", (Step(2, 3.0, 0.5), Step(1, 3.0, 0.42), Step(-3, 6.0, 0.35))),
    }


# --- progressions ---------------------------------------------------------------------------------

def progression(degrees, tonic: int, mode: str, centre: int = 55, size: int = 3) -> list[list[int]]:
    """Voice-led chord progression from a list of scale degrees (0 = i/I)."""
    out: list[list[int]] = []
    prev: list[int] = []
    for d in degrees:
        ch = triad(d, tonic, mode, size)
        prev = voice_lead(prev, ch, centre)
        out.append(prev)
    return out


def bass_line(chords, low: int = 36, high: int = 50) -> list[int]:
    """Root of each chord placed in the bass register."""
    out = []
    for ch in chords:
        n = min(ch) % 12 + 12 * (low // 12)
        while n < low:
            n += 12
        while n > high:
            n -= 12
        out.append(n)
    return out
