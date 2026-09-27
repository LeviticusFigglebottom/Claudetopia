"""Composition: the scores Wickmere plays, as note data.

This module writes the music; gen_music.py renders it. Keeping them apart means the musical
rules (every note in the mode, no accidental minor seconds, the Toll present in every region,
stems the same length) are testable without rendering a second of audio.

The frame, from WORLD_BIBLE 1.1: the world is a bell struck once and still ringing. So the
Toll motif is the game's leitmotif and appears in every region theme, transformed by what that
region has made of the ringing -- plain and warm in Hearthvale where people still tend it,
inverted and misty in Sedgemire, augmented to a crawl in the Briarwold's deep green, cold and
open in Skerrow, and in Cinderlea reduced to its first three notes under a note that will not
stop.
"""
from __future__ import annotations

import json
import math
import os
from dataclasses import dataclass, field

from synth import theory
from synth.core import rng, sub_seed


@dataclass
class Note:
    """One played note. `beat` and `beats` are musical time; the renderer turns them into
    seconds. `voice` names the instrument role, `tension` marks a deliberate dissonance."""
    beat: float
    beats: float
    midi: int
    vel: float = 0.8
    voice: str = "lead"
    tension: bool = False

    def end(self) -> float:
        return self.beat + self.beats


@dataclass
class Score:
    """A piece: tempo, key and one list of notes per stem."""
    name: str
    tonic: int
    mode: str
    bpm: float
    bars: int
    beats_per_bar: int = 4
    stems: dict = field(default_factory=dict)      # stem name -> [Note]
    swing: float = 0.0                              # 0 = straight, 0.2 = a gentle lilt
    meta: dict = field(default_factory=dict)

    def total_beats(self) -> float:
        return self.bars * self.beats_per_bar

    def seconds(self) -> float:
        return self.total_beats() * 60.0 / self.bpm

    def add(self, stem: str, notes) -> None:
        self.stems.setdefault(stem, []).extend(notes)

    def notes(self, stem: str):
        return self.stems.get(stem, [])

    def all_notes(self):
        for ns in self.stems.values():
            for n in ns:
                yield n


# =================================================================================================
# Region identities: what each place has made of the ringing
# =================================================================================================

REGIONS = {
    "hearthvale": dict(
        region_id="core:region/hearthvale",
        title="Tended Light",
        tonic=62, music_mode="lydian_warm", bpm=76.0, bars=32, swing=0.16,
        # I II vi IV | I V II I -- the major II is the lydian glow, the warmth of the place
        progression=[0, 1, 5, 3, 0, 4, 1, 0],
        lead="flute", pad_voice="pad", texture="harp", bass="cello",
        reverb="valley", reverb_mix=0.24, centre=57, lead_octave=12,
        arp_density=4,
        colour="warm and lyrical: a flute over a harp, the small bells the Vale hangs in trees",
    ),
    "brightwater": dict(
        region_id="core:region/brightwater",
        title="The Long Stride",
        tonic=67, music_mode="ionian_bright", bpm=92.0, bars=40, swing=0.0,
        progression=[0, 4, 5, 3, 0, 3, 4, 0],
        lead="whistle", pad_voice="pad", texture="pluck", bass="cello",
        reverb="chamber", reverb_mix=0.20, centre=59, lead_octave=12,
        arp_density=4,
        colour="bright and busy: water light on white walls, a whistle and a quick pluck",
    ),
    "sedgemire": dict(
        region_id="core:region/sedgemire",
        title="What the Water Kept",
        tonic=57, music_mode="dorian_misty", bpm=60.0, bars=24, swing=0.0,
        # the major IV of dorian is the colour: hopeful in the fog, which is the reedfolk exactly
        progression=[0, 3, 6, 0, 5, 3, 4, 0],
        lead="flute", pad_voice="choir", texture="pluck", bass="cello",
        reverb="marsh", reverb_mix=0.34, centre=55, lead_octave=12,
        arp_density=3,
        colour="misty and modal: a breathy flute a long way off over still water",
    ),
    "briarwold": dict(
        region_id="core:region/briarwold",
        title="Under the Grandfather",
        tonic=52, music_mode="aeolian_deep", bpm=54.0, bars=24, swing=0.0,
        progression=[0, 5, 2, 6, 0, 3, 4, 0],
        lead="cello", pad_voice="choir", texture="pluck", bass="cello",
        reverb="cave", reverb_mix=0.30, centre=50, lead_octave=12,
        arp_density=3,
        colour="deep and hushed: low strings under a canopy, almost nothing above them",
    ),
    "skerrow": dict(
        region_id="core:region/skerrow",
        title="A Hand on the Rope",
        tonic=62, music_mode="mixolydian_cold", bpm=68.0, bars=28, swing=0.0,
        # the flat VII is the mixolydian colour: open, old, unsentimental
        progression=[0, 6, 3, 0, 6, 4, 3, 0],
        lead="pipes", pad_voice="glass", texture="pluck", bass="drone",
        reverb="hall", reverb_mix=0.26, centre=57, lead_octave=12,
        arp_density=4,
        colour="cold and open: pipes over a drone, wind on a high moor",
    ),
    "cinderlea": dict(
        region_id="core:region/cinderlea",
        title="The Held Note",
        tonic=52, music_mode="phrygian_hollow", bpm=44.0, bars=20, swing=0.0,
        # the flat II is phrygian's shadow; it is placed where the sustained note can bear it
        progression=[0, 1, 0, 6, 0, 1, 5, 0],
        lead="hum", pad_voice="glass", texture="bell", bass="drone",
        reverb="cinder", reverb_mix=0.42, centre=52, lead_octave=12,
        arp_density=2,
        colour="hollow and sparse: a held note, ash, and one bell every few minutes",
    ),
}


# =================================================================================================
# Helpers
# =================================================================================================

def humanise(notes, seed, timing: float = 0.02, velocity: float = 0.10, swing: float = 0.0,
             beats_per_bar: int = 4):
    """Nudge timing and velocity so the performance is not on a grid.

    Timing is in beats; swing delays every off-beat by `swing` of a half beat (the Vale lilt).
    The first note of a bar is left alone in time so the pulse stays clear.
    """
    r = rng(seed)
    out = []
    for n in notes:
        beat = n.beat
        if swing:
            frac = beat % 1.0
            if abs(frac - 0.5) < 1e-6:
                beat += swing * 0.5
        on_downbeat = abs(beat % beats_per_bar) < 1e-6
        if not on_downbeat:
            beat += float(r.normal(0.0, timing))
        vel = float(min(max(n.vel * (1.0 + r.normal(0.0, velocity)), 0.05), 1.0))
        out.append(Note(max(beat, 0.0), n.beats, n.midi, vel, n.voice, n.tension))
    return out


# Voices played by a single-line instrument: a flute or a cello plays one note at a time, so
# overlapping notes in these voices are a composing error, not a chord.
MONOPHONIC_VOICES = {"lead", "counter", "ostinato"}

# Voices an octave may be moved on to clear a clash. Displacing by an octave keeps the pitch
# class, so the harmony is exactly as written; the pad can therefore yield as freely as the
# bass. The lead is never moved: it carries the Toll, and the motif's shape is the point.
MOVABLE_VOICES = ("bass", "drone", "arp", "bell", "stab", "counter", "ostinato", "pad")


def make_monophonic(notes):
    """Truncate each note of a single-line voice at the start of the next note in that voice.

    Timing humanisation and overlapping phrases can otherwise leave a flute playing two notes
    at once, which both sounds wrong and invents harmonies nobody wrote.
    """
    by_voice: dict = {}
    for n in notes:
        by_voice.setdefault(n.voice, []).append(n)
    out = []
    for voice, ns in by_voice.items():
        if voice not in MONOPHONIC_VOICES:
            out.extend(ns)
            continue
        ns = sorted(ns, key=lambda n: (n.beat, n.midi))
        for i, n in enumerate(ns):
            beats = n.beats
            if i + 1 < len(ns):
                beats = min(beats, max(ns[i + 1].beat - n.beat, 0.05))
            out.append(Note(n.beat, beats, n.midi, n.vel, n.voice, n.tension))
    return sorted(out, key=lambda n: n.beat)


# Decorative voices that may simply be dropped when no octave clears them: one missing note of
# an arpeggio or one missing stab is inaudible, where a missing chord tone or bass note is not.
DROPPABLE_VOICES = ("arp", "stab")


def resolve_clashes(score: Score, passes: int = 4) -> int:
    """Clear accidental minor seconds by moving accompaniment notes an octave.

    An octave displacement keeps the harmony exactly as written -- the pitch class, and so the
    chord, is unchanged -- while taking the two voices out of each other's way. Only the voices
    in MOVABLE_VOICES are touched, and a move is kept only if it actually reduces the number of
    clashes. A decorative note that no octave can free is dropped instead. Returns the number of
    notes changed.
    """
    moved = 0
    for _ in range(passes):
        problems = []
        for comb in combinations_of(score):
            problems.extend((comb, c) for c in clashes(score, comb))
        if not problems:
            break
        # index notes so a move can be applied in place
        targets: dict = {}
        for comb, (beat, va, ma, vb, mb) in problems:
            for voice, midi in ((va, ma), (vb, mb)):
                if voice in MOVABLE_VOICES:
                    targets.setdefault((voice, midi, beat), 0)
                    targets[(voice, midi, beat)] += 1
        if not targets:
            break
        progress = False
        for (voice, midi, beat) in sorted(targets, key=lambda k: -targets[k]):
            for stem, notes in score.stems.items():
                for idx, n in enumerate(notes):
                    if n.voice != voice or n.midi != midi or not (n.beat <= beat + 1e-6 < n.end()):
                        continue
                    before = sum(len(clashes(score, c)) for c in combinations_of(score))
                    fixed = False
                    for shift in (12, -12, 24, -24):
                        if not (20 <= n.midi + shift <= 104):
                            continue
                        notes[idx] = Note(n.beat, n.beats, n.midi + shift, n.vel, n.voice, n.tension)
                        after = sum(len(clashes(score, c)) for c in combinations_of(score))
                        if after < before:
                            moved += 1
                            progress = fixed = True
                            break
                        notes[idx] = n
                    if not fixed and voice in DROPPABLE_VOICES:
                        notes.pop(idx)
                        if sum(len(clashes(score, c)) for c in combinations_of(score)) < before:
                            moved += 1
                            progress = True
                        else:
                            notes.insert(idx, n)
                    break
        if not progress:
            break
    return moved



def _finish(score: Score) -> None:
    """Make single-line voices monophonic, keep every note inside the loop, clear accidental
    minor seconds, and record what is left. Every score goes through this before rendering."""
    end = score.total_beats()
    for stem in list(score.stems):
        notes = make_monophonic(score.stems[stem])
        # Humanised timing can nudge a note past the loop point, where its tail would be folded
        # back over the opening bar. Trim to the loop and drop anything that no longer sounds.
        trimmed = []
        for n in notes:
            if n.beat >= end - 1e-6:
                continue
            beats = min(n.beats, end - n.beat)
            if beats > 1e-6:
                trimmed.append(Note(n.beat, beats, n.midi, n.vel, n.voice, n.tension))
        score.stems[stem] = trimmed
    resolve_clashes(score)
    score.meta["clashes"] = {c: len(clashes(score, c)) for c in combinations_of(score)}


def chords_for(cfg: dict, size: int = 3):
    """The voice-led chord progression of a region."""
    mode = theory.mode_of(cfg["music_mode"])
    return theory.progression(cfg["progression"], cfg["tonic"], mode, centre=cfg["centre"], size=size)


def _phrase_plan(motifs: dict):
    """How the Toll is developed across the four phrases of a region theme.

    Plain, then turned over, then stretched out, then broken down to its head: the same bell
    heard by four different people.
    """
    return [
        ("statement", motifs["toll"]),
        ("inversion", motifs["toll_inv"]),
        ("augmented", motifs["toll_aug"]),
        ("fragment", motifs["toll_short"]),
    ]


# =================================================================================================
# Region themes
# =================================================================================================

def region_score(key: str) -> Score:
    """Compose one region's theme: pad, melody, texture, combat and deep stems over the same
    bars, in the same key and tempo, so the game can crossfade and layer them freely."""
    cfg = REGIONS[key]
    mode = theory.mode_of(cfg["music_mode"])
    tonic = cfg["tonic"]
    bpb = 4
    score = Score(name=key, tonic=tonic, mode=mode, bpm=cfg["bpm"], bars=cfg["bars"],
                  beats_per_bar=bpb, swing=cfg.get("swing", 0.0),
                  meta={"title": cfg["title"], "colour": cfg["colour"], "region_id": cfg["region_id"],
                        "music_mode": cfg["music_mode"], "reverb": cfg["reverb"],
                        "reverb_mix": cfg["reverb_mix"]})
    prog = cfg["progression"]
    chords = chords_for(cfg)
    bass = theory.bass_line(chords, low=tonic - 26, high=tonic - 14)
    motifs = theory.motif_library()
    plan = _phrase_plan(motifs)
    seed = sub_seed(cfg["region_id"], "theme")
    r = rng(seed)

    bars_per_chord = 1
    total_bars = cfg["bars"]

    # --- pad: the harmony bed, one chord per bar, held, plus the bass -------------------------
    pad_notes, bass_notes = [], []
    for bar in range(total_bars):
        ci = bar % len(prog)
        chord = chords[ci]
        beat = bar * bpb
        # hold each chord a little past the bar so the voices overlap rather than breathe together
        for i, n in enumerate(chord):
            pad_notes.append(Note(beat, bpb * bars_per_chord - 0.02, n, 0.55 - 0.04 * i, "pad"))
        bass_notes.append(Note(beat, bpb * bars_per_chord * 0.98, bass[ci], 0.6, "bass"))
        # a passing bass note into the next bar, on the last beat of every other bar
        if bar % 2 == 1 and bar + 1 < total_bars:
            nxt = bass[(bar + 1) % len(prog)]
            step = 1 if nxt > bass[ci] else -1
            passing = theory.nearest_in_mode(bass[ci] + step * 2, tonic, mode)
            if passing != nxt:
                bass_notes.append(Note(beat + bpb - 1, 1.0, passing, 0.4, "bass"))
    score.add("pad", humanise(pad_notes + bass_notes, sub_seed(seed, "pad"), 0.03, 0.08,
                              beats_per_bar=bpb))

    # --- melody: the Toll, developed ------------------------------------------------------------
    melody: list[Note] = []
    phrase_bars = max(total_bars // 4, 4)
    for p, (kind, motif) in enumerate(plan):
        start_bar = p * phrase_bars
        if start_bar >= total_bars:
            break
        beat0 = start_bar * bpb
        ci = start_bar % len(prog)
        # root the motif on a chord tone so the statement is consonant with the harmony under it
        root_degree = prog[ci]
        m = motif
        if kind == "fragment":
            # the head of the motif, then the answer, cadencing home
            m = motif.stretch_last(3.0)
        notes = m.to_notes(tonic, mode, root_degree=root_degree, start_beat=beat0)
        oct_shift = cfg["lead_octave"]
        for (b, dur, midi, vel) in notes:
            if b >= (start_bar + phrase_bars) * bpb:
                break
            melody.append(Note(b, dur, midi + oct_shift, vel, "lead"))
        used = notes[-1][0] + notes[-1][1] - beat0 if notes else 0.0
        remaining = phrase_bars * bpb - used
        # what follows the statement: a sequence of it, or the answering figure
        if remaining >= 4.0:
            if kind in ("statement", "inversion"):
                seq = m.sequence([2, 0] if kind == "statement" else [-2, 0], gap_beats=0.5)
                seq_notes = seq.to_notes(tonic, mode, root_degree=root_degree, start_beat=beat0 + used)
                for (b, dur, midi, vel) in seq_notes:
                    if b + dur > (start_bar + phrase_bars) * bpb:
                        break
                    melody.append(Note(b, dur, midi + oct_shift, vel * 0.8, "lead"))
            else:
                ans = motifs["answer"]
                for (b, dur, midi, vel) in ans.to_notes(tonic, mode, root_degree=prog[
                        (start_bar + phrase_bars - 2) % len(prog)], start_beat=beat0 + used):
                    if b + dur > (start_bar + phrase_bars) * bpb:
                        break
                    melody.append(Note(b, dur, midi + oct_shift, vel * 0.85, "lead"))
    # The last phrase must carry the melody close to the loop point and settle on the tonic, or
    # the theme trails off into several silent bars and the loop sounds like it stopped.
    end_beat = total_bars * bpb
    last_end = max((n.end() for n in melody), default=0.0)
    if end_beat - last_end > 5.0:
        tail_start = max(last_end + 1.0, end_beat - 9.0)
        for (b, dur, midi, vel) in motifs["answer"].to_notes(tonic, mode, 0, tail_start):
            if b + dur <= end_beat - 1.0:
                melody.append(Note(b, dur, midi + cfg["lead_octave"], vel * 0.7, "lead"))
        held = max((n.end() for n in melody), default=tail_start)
        if end_beat - held > 1.5:
            melody.append(Note(held, end_beat - held - 0.5, tonic + cfg["lead_octave"], 0.45, "lead"))
    # keep the lead inside a singable octave and a half
    lo, hi = tonic + 2, tonic + 26
    melody = [Note(n.beat, n.beats, int(min(max(n.midi, lo), hi)), n.vel, n.voice) for n in melody]
    score.add("melody", make_monophonic(humanise(melody, sub_seed(seed, "melody"), 0.025, 0.12,
                                              swing=cfg.get("swing", 0.0), beats_per_bar=bpb)))

    # --- texture: arpeggios, a counter-line and the bell on the phrase joins --------------------
    texture: list[Note] = []
    for bar in range(total_bars):
        ci = bar % len(prog)
        chord = chords[ci]
        beat = bar * bpb
        # How busy the arpeggio is belongs to the region, not to its tempo: deriving it from
        # bpm left the slow places with one note every two seconds, which at the pitches a
        # plucked string actually sustains is a hole rather than a texture.
        density = int(cfg.get("arp_density", 4))
        pattern = [0, 2, 1, 2, 0, 1][:density]
        for i, idx in enumerate(pattern):
            b = beat + i * (bpb / float(density))
            midi = chord[idx % len(chord)] + (12 if i % 4 == 3 else 0)
            texture.append(Note(b, bpb / float(density) * 0.9, midi, 0.46 - 0.035 * i, "arp"))
        # a bell marks the start of every phrase: the ringing the region is made of
        if bar % phrase_bars == 0:
            texture.append(Note(beat, bpb * 2.0, tonic + 12, 0.36 if bar else 0.44, "bell"))
        elif bar % 4 == 2 and r.random() < 0.35:
            texture.append(Note(beat + bpb * 0.5, bpb, chord[1] + 12, 0.22, "bell"))
    # a slow counter-melody under the lead: the augmented motif, very quiet
    counter = motifs["toll_aug"].to_notes(tonic, mode, root_degree=0, start_beat=phrase_bars * bpb)
    for (b, dur, midi, vel) in counter:
        if b + dur <= total_bars * bpb:
            texture.append(Note(b, dur, midi, vel * 0.3, "counter"))
    score.add("texture", make_monophonic(humanise(texture, sub_seed(seed, "texture"), 0.02, 0.14,
                                               swing=cfg.get("swing", 0.0), beats_per_bar=bpb)))

    # --- combat: the same harmony with a pulse under it ------------------------------------------
    combat: list[Note] = []
    for bar in range(total_bars):
        ci = bar % len(prog)
        chord = chords[ci]
        beat = bar * bpb
        root = bass[ci]
        # a driving low ostinato on the root and fifth
        for i in range(bpb * 2):
            b = beat + i * 0.5
            midi = root if i % 4 != 3 else theory.degree_to_midi(prog[ci] + 4, tonic, mode) - 12
            combat.append(Note(b, 0.45, midi, 0.56 if i % 2 == 0 else 0.4, "ostinato"))
        # drum: a heartbeat that doubles up as the bar goes on
        for i, (b, v) in enumerate([(0.0, 0.68), (1.5, 0.42), (2.0, 0.56), (3.5, 0.38)]):
            combat.append(Note(beat + b, 0.5, 36, v, "drum"))
        # accented bell every other bar, high and hard
        if bar % 2 == 0:
            combat.append(Note(beat, 2.0, chord[-1] + 12, 0.5, "bell"))
        # an upper stab on the off-beat of the second half
        if bar % 4 in (1, 3):
            combat.append(Note(beat + 2.5, 0.75, chord[-1] + 12, 0.42, "stab"))
    score.add("combat", make_monophonic(humanise(combat, sub_seed(seed, "combat"), 0.015, 0.1,
                                              beats_per_bar=bpb)))

    # --- deep: what is left when the melody goes -------------------------------------------------
    # A layer the director adds while it mutes the melody, so it carries only what the pad does
    # not: one held note far below the harmony, and a bell now and then. Deep places in Wickmere
    # are where the ringing failed, and this is the sound of it still just barely going.
    deep: list[Note] = []
    low = tonic - 24
    for bar in range(0, total_bars, 4):
        length = min(4, total_bars - bar) * bpb
        deep.append(Note(bar * bpb, length - 0.02, low, 0.5, "drone"))
    for bar in range(total_bars):
        beat = bar * bpb
        if bar % 8 == 0:
            deep.append(Note(beat, bpb * 3.0, tonic, 0.5, "bell"))
        elif bar % 8 == 5 and r.random() < 0.5:
            deep.append(Note(beat + 2.0, bpb * 2.0, tonic + 7, 0.3, "bell"))
    score.add("deep", humanise(deep, sub_seed(seed, "deep"), 0.04, 0.08, beats_per_bar=bpb))
    _finish(score)
    return score


# =================================================================================================
# Region variations: more of the same place
# =================================================================================================

# A region's theme on its own loop wore thin after a while (triage 2026-09-27 #19), so each
# region also has pieces the director rotates through: two more by day, two by night and a
# fight. They keep the region's tonic, instruments and the Toll; what changes is the phrase, the
# tempo feel and the arrangement, and at night the mode or the register. Each is rendered to
# one mixed file rather than stems: nothing is layered over them, they are only crossfaded.
VARIATIONS = ("day_2", "day_3", "night_1", "night_2", "fight")
VARIATION_ROLE = {"day_2": "day", "day_3": "day", "night_1": "night", "night_2": "night",
                  "fight": "combat"}
VARIATION_TITLE = {"day_2": "Walking", "day_3": "An Air", "night_1": "After Dark",
                   "night_2": "The Small Hours", "fight": "Drawn"}
# Roughly how long each loop runs; the bars are rounded to whole turns of the progression.
VARIATION_SECONDS = {"day_2": 64.0, "day_3": 72.0, "night_1": 76.0, "night_2": 68.0, "fight": 56.0}

# Night is one shade darker: one degree of the scale lowered a semitone. Phrygian is as dark as
# the country goes, so Cinderlea's night changes register rather than mode.
NIGHT_MODE = {"lydian": "ionian", "ionian": "mixolydian", "mixolydian": "dorian",
              "dorian": "aeolian", "aeolian": "phrygian", "phrygian": "phrygian"}

# A score whose every stem plays at once (a variation is one mixed piece) checks its harmony
# across all of them, not across the director's stem combinations.
WHOLE = "whole"


def _bars_for(seconds: float, bpm: float, unit: int, bpb: int = 4) -> int:
    """Whole turns of a `unit`-bar progression closest to `seconds`, never fewer than one."""
    bars = seconds * bpm / 60.0 / bpb
    return max(unit, int(round(bars / unit)) * unit)


def _in_range(midi: int, lo: int, hi: int) -> int:
    """Move a note by octaves into [lo, hi]: the pitch class, and so the mode, is kept."""
    while midi < lo:
        midi += 12
    while midi > hi:
        midi -= 12
    return midi


def _night_degrees(mode: str, reverse: bool = False) -> list:
    """A four-chord night progression, home - away - further - home, with no diminished chord in
    it whatever the mode: the first of (vi, vii, ii) and of (iv, v, iii) that is not diminished."""
    def ok(d):
        return theory.chord_quality(theory.triad(d, 60, mode)) != "dim"
    away = next(d for d in (5, 6, 1) if ok(d))
    further = next(d for d in (3, 4, 2, 6) if ok(d) and d != away)
    return [0, further, away, 0] if reverse else [0, away, further, 0]


def _place(motif, tonic: int, mode: str, root: int, at: float, until: float, octave: int,
           vel: float, voice: str, lo: int, hi: int) -> tuple:
    """Lay a motif from `at`, cut at `until`; returns (notes, where it ended)."""
    out = []
    end = at
    for (b, dur, midi, v) in motif.to_notes(tonic, mode, root_degree=root, start_beat=at):
        if b >= until - 0.25:
            break
        dur = min(dur, until - b)
        out.append(Note(b, dur, _in_range(midi + octave, lo, hi), v * vel, voice))
        end = b + dur
    return out, end


def _new_variation(key: str, kind: str, mode: str, bpm: float, bars: int) -> Score:
    cfg = REGIONS[key]
    return Score(name="%s_%s" % (key, kind), tonic=cfg["tonic"], mode=mode, bpm=round(bpm, 2),
                 bars=bars, beats_per_bar=4, swing=cfg.get("swing", 0.0) if kind == "day_2" else 0.0,
                 meta={"title": "%s: %s" % (cfg["title"], VARIATION_TITLE[kind]),
                       "colour": cfg["colour"], "region_id": cfg["region_id"],
                       "music_mode": cfg["music_mode"], "role": VARIATION_ROLE[kind],
                       "variation": kind, "whole": True})


def _day_walk(key: str) -> Score:
    """Day 2, walking: a little quicker, the progression taken in another order, the Toll shrunk to
    half its length and passed between the lead and an answering voice, eighth-note arpeggios."""
    cfg = REGIONS[key]
    mode = theory.mode_of(cfg["music_mode"])
    tonic, bpb = cfg["tonic"], 4
    bpm = cfg["bpm"] * 1.15
    p = cfg["progression"]
    prog = [p[i] for i in (0, 2, 4, 6, 1, 3, 5, 7)]
    bars = _bars_for(VARIATION_SECONDS["day_2"], bpm, len(prog))
    s = _new_variation(key, "day_2", mode, bpm, bars)
    chords = theory.progression(prog, tonic, mode, centre=cfg["centre"])
    bass = theory.bass_line(chords, low=tonic - 26, high=tonic - 14)
    motifs = theory.motif_library()
    seed = sub_seed(cfg["region_id"], "day_2")
    pad = []
    for bar in range(bars):
        ci = bar % len(prog)
        beat = bar * bpb
        for i, n in enumerate(chords[ci]):
            pad.append(Note(beat, bpb - 0.02, n, 0.46 - 0.04 * i, "pad"))
        # a walking bass: the root, then the chord's top note brought down into the bass
        pad.append(Note(beat, 2.0, bass[ci], 0.58, "bass"))
        upper = _in_range(chords[ci][-1], bass[ci] + 1, bass[ci] + 12)
        pad.append(Note(beat + 2.0, 2.0, upper, 0.44, "bass"))
    s.add("pad", humanise(pad, sub_seed(seed, "pad"), 0.025, 0.08, beats_per_bar=bpb))

    lo, hi = tonic + 2, tonic + 26
    oct_shift = cfg["lead_octave"]
    plan = [motifs["toll_dim"].sequence([0, 2], gap_beats=0.5), motifs["toll_retro"],
            motifs["toll_dim"].sequence([0, -2], gap_beats=0.5), motifs["answer"]]
    melody = []
    phrase_bars = 4
    for k, start_bar in enumerate(range(0, bars, phrase_bars)):
        if k % 4 == 3 and start_bar + phrase_bars < bars:
            continue            # a phrase of rest every sixteen bars: it walks, it does not run
        beat0 = start_bar * bpb + (0.5 if k % 2 else 0.0)
        voice = "lead" if k % 2 == 0 else "counter"
        notes, _ = _place(plan[k % len(plan)], tonic, mode, prog[start_bar % len(prog)], beat0,
                          (start_bar + phrase_bars) * bpb, oct_shift, 0.9 if voice == "lead" else 0.7,
                          voice, lo, hi)
        melody += notes
    s.add("melody", humanise(melody, sub_seed(seed, "melody"), 0.02, 0.12, swing=s.swing,
                             beats_per_bar=bpb))

    texture = []
    density = min(8, int(cfg.get("arp_density", 4)) * 2)
    pattern = [0, 1, 2, 1, 0, 2, 1, 2][:density]
    for bar in range(bars):
        ci = bar % len(prog)
        beat = bar * bpb
        for i, idx in enumerate(pattern):
            midi = chords[ci][idx % len(chords[ci])] + (12 if i in (3, 6) else 0)
            texture.append(Note(beat + i * bpb / density, bpb / density * 0.9, midi,
                                0.38 - 0.02 * (i % 4), "arp"))
        if bar % 8 == 0:
            texture.append(Note(beat, bpb * 2.0, tonic + 12, 0.36, "bell"))
    s.add("texture", humanise(texture, sub_seed(seed, "texture"), 0.015, 0.12, swing=s.swing,
                              beats_per_bar=bpb))
    _finish(s)
    return s


def _day_air(key: str) -> Score:
    """Day 3, an air: slower, a chord every two bars in the progression's mirror order, the Toll
    stretched out and sung lower, a harp rolled across each change and a counter-line above."""
    cfg = REGIONS[key]
    mode = theory.mode_of(cfg["music_mode"])
    tonic, bpb = cfg["tonic"], 4
    bpm = cfg["bpm"] * 0.85
    p = cfg["progression"]
    prog = [p[0], p[6], p[5], p[4], p[3], p[2], p[1], p[7]]
    per = 2                                         # bars per chord
    bars = _bars_for(VARIATION_SECONDS["day_3"], bpm, len(prog) * per // 2)
    s = _new_variation(key, "day_3", mode, bpm, bars)
    chords = theory.progression(prog, tonic, mode, centre=cfg["centre"])
    bass = theory.bass_line(chords, low=tonic - 26, high=tonic - 14)
    motifs = theory.motif_library()
    seed = sub_seed(cfg["region_id"], "day_3")

    def chord_at(bar):
        return (bar // per) % len(prog)

    pad = []
    for bar in range(0, bars, per):
        ci = chord_at(bar)
        beat = bar * bpb
        span = min(per, bars - bar) * bpb
        for i, n in enumerate(chords[ci]):
            pad.append(Note(beat, span - 0.02, n, 0.42 - 0.04 * i, "pad"))
        pad.append(Note(beat, span * 0.98, bass[ci], 0.5, "bass"))
    s.add("pad", humanise(pad, sub_seed(seed, "pad"), 0.03, 0.08, beats_per_bar=bpb))

    # lower than the theme sings it, where the instrument can still carry it
    octave = 0 if tonic >= 60 else 12
    lo, hi = tonic - 3 + octave, tonic + 19 + octave
    plan = [(motifs["toll_aug"], motifs["hush"]),
            (motifs["toll_inv"].augment(1.5), motifs["answer"].augment(2.0))]
    melody = []
    phrase_bars = 8
    for k, start_bar in enumerate(range(0, bars, phrase_bars)):
        first, second = plan[k % len(plan)]
        until = min(start_bar + phrase_bars, bars) * bpb
        a, end = _place(first, tonic, mode, prog[chord_at(start_bar)], start_bar * bpb + 1.0,
                        until, octave, 0.85, "lead", lo, hi)
        b, _ = _place(second, tonic, mode, prog[chord_at(int(end // bpb))], end + 1.0, until - 0.5,
                      octave, 0.7, "lead", lo, hi)
        melody += a + b
    s.add("melody", humanise(melody, sub_seed(seed, "melody"), 0.03, 0.1, beats_per_bar=bpb))

    texture = []
    for bar in range(0, bars, per):
        ci = chord_at(bar)
        beat = bar * bpb
        roll = sorted(chords[ci]) + [sorted(chords[ci])[0] + 12]
        for i, n in enumerate(roll):
            texture.append(Note(beat + 0.25 * i, bpb * 1.5, n + 12, 0.34 - 0.03 * i, "arp"))
        texture.append(Note(beat + bpb + 2.0, 1.5, roll[1] + 12, 0.22, "arp"))
    # the Toll run backwards far above, very quiet: someone else humming it across a field
    for start_bar in range(phrase_bars // 2, bars, phrase_bars * 2):
        notes, _ = _place(motifs["toll_retro"], tonic, mode, 0, start_bar * bpb,
                          min(start_bar + phrase_bars, bars) * bpb, 24, 0.3, "counter",
                          tonic + 14, tonic + 38)
        texture += notes
    texture.append(Note(0.0, bpb * 2.0, tonic + 12, 0.34, "bell"))
    s.add("texture", humanise(texture, sub_seed(seed, "texture"), 0.02, 0.12, beats_per_bar=bpb))
    _finish(s)
    return s


def _night_low(key: str) -> Score:
    """Night 1, after dark: slower, one shade darker in mode, the Toll sung low and only now and
    then, a chord every two bars under it, and a bell with small high ones like stars."""
    cfg = REGIONS[key]
    mode = NIGHT_MODE[theory.mode_of(cfg["music_mode"])]
    tonic, bpb = cfg["tonic"], 4
    bpm = cfg["bpm"] * 0.75
    prog = _night_degrees(mode)
    per = 2
    bars = _bars_for(VARIATION_SECONDS["night_1"], bpm, len(prog) * per)
    s = _new_variation(key, "night_1", mode, bpm, bars)
    chords = theory.progression(prog, tonic, mode, centre=cfg["centre"] - 4)
    bass = theory.bass_line(chords, low=tonic - 28, high=tonic - 16)
    motifs = theory.motif_library()
    seed = sub_seed(cfg["region_id"], "night_1")

    def chord_at(bar):
        return (bar // per) % len(prog)

    pad = []
    for bar in range(0, bars, per):
        ci = chord_at(bar)
        span = min(per, bars - bar) * bpb
        for i, n in enumerate(chords[ci]):
            pad.append(Note(bar * bpb, span - 0.02, n, 0.40 - 0.04 * i, "pad"))
        pad.append(Note(bar * bpb, span * 0.98, bass[ci], 0.42, "bass"))
    s.add("pad", humanise(pad, sub_seed(seed, "pad"), 0.03, 0.06, beats_per_bar=bpb))

    octave = 0 if tonic >= 57 else 12
    lo, hi = tonic - 5 + octave, tonic + 14 + octave
    melody = []
    for k, start_bar in enumerate(range(0, bars, 8)):
        until = min(start_bar + 8, bars) * bpb
        motif = motifs["toll_aug"] if k % 2 == 0 else motifs["toll_short"].augment(2.0)
        notes, _ = _place(motif, tonic, mode, prog[chord_at(start_bar)], start_bar * bpb + 4.0,
                          until - 1.0, octave, 0.6, "lead", lo, hi)
        melody += notes
    s.add("melody", humanise(melody, sub_seed(seed, "melody"), 0.03, 0.08, beats_per_bar=bpb))

    texture = []
    r = rng(sub_seed(seed, "stars"))
    for bar in range(bars):
        beat = bar * bpb
        if bar % 8 == 0:
            texture.append(Note(beat, bpb * 3.0, tonic, 0.42, "bell"))
        elif bar % 2 == 1 and r.random() < 0.6:
            ch = chords[chord_at(bar)]
            star = _in_range(ch[int(r.integers(0, len(ch)))] + 24, 76, 91)
            texture.append(Note(beat + float(r.choice([0.5, 1.5, 2.5])), 2.0, star, 0.18, "bell"))
    s.add("texture", humanise(texture, sub_seed(seed, "texture"), 0.03, 0.1, beats_per_bar=bpb))
    _finish(s)
    return s


def _night_high(key: str) -> Score:
    """Night 2, the small hours: the region's own mode, but high and far off -- a glassy chord up
    where the day's melody was, fragments of the Toll above it, one low note held under all of
    it and a slow pluck coming and going."""
    cfg = REGIONS[key]
    mode = theory.mode_of(cfg["music_mode"])
    tonic, bpb = cfg["tonic"], 4
    bpm = cfg["bpm"] * 0.8
    prog = _night_degrees(mode, reverse=True)
    per = 2
    bars = _bars_for(VARIATION_SECONDS["night_2"], bpm, len(prog) * per)
    s = _new_variation(key, "night_2", mode, bpm, bars)
    chords = theory.progression(prog, tonic, mode, centre=cfg["centre"] + 10)
    motifs = theory.motif_library()
    seed = sub_seed(cfg["region_id"], "night_2")

    def chord_at(bar):
        return (bar // per) % len(prog)

    pad = []
    for bar in range(0, bars, per):
        ci = chord_at(bar)
        span = min(per, bars - bar) * bpb
        for i, n in enumerate(chords[ci]):
            pad.append(Note(bar * bpb, span - 0.02, n, 0.36 - 0.04 * i, "pad"))
    s.add("pad", humanise(pad, sub_seed(seed, "pad"), 0.03, 0.06, beats_per_bar=bpb))

    lo, hi = tonic + 12, tonic + 31
    plan = [motifs["toll_short"], motifs["hush"], motifs["toll_retro"].fragment(3), motifs["hush"]]
    melody = []
    for k, start_bar in enumerate(range(0, bars, 4)):
        if k % 3 == 2:
            continue                    # the small hours are mostly quiet
        until = min(start_bar + 4, bars) * bpb
        notes, _ = _place(plan[k % len(plan)], tonic, mode, prog[chord_at(start_bar)],
                          start_bar * bpb + 2.0, until - 0.5, 24, 0.55, "lead", lo, hi)
        melody += notes
    s.add("melody", humanise(melody, sub_seed(seed, "melody"), 0.03, 0.08, beats_per_bar=bpb))

    texture = []
    low = tonic - 24
    for bar in range(0, bars, 4):
        texture.append(Note(bar * bpb, min(4, bars - bar) * bpb - 0.02, low, 0.45, "drone"))
    for bar in range(bars):
        if bar % 4 in (0, 1):
            ch = chords[chord_at(bar)]
            for i, idx in enumerate((0, 2, 1, 2)):
                texture.append(Note(bar * bpb + i, 1.6, ch[idx % len(ch)] - 12, 0.24 - 0.02 * i, "arp"))
    s.add("texture", humanise(texture, sub_seed(seed, "texture"), 0.025, 0.1, beats_per_bar=bpb))
    _finish(s)
    return s


def _fight(key: str) -> Score:
    """The fight: the region's own progression half as fast again, a driving ostinato and drums
    under it, and the Toll stated hard -- halved, whole, turned over -- by the region's lead."""
    cfg = REGIONS[key]
    mode = theory.mode_of(cfg["music_mode"])
    tonic, bpb = cfg["tonic"], 4
    bpm = min(max(cfg["bpm"] * 1.5, 84.0), 128.0)
    prog = list(cfg["progression"])
    bars = _bars_for(VARIATION_SECONDS["fight"], bpm, len(prog))
    s = _new_variation(key, "fight", mode, bpm, bars)
    chords = theory.progression(prog, tonic, mode, centre=cfg["centre"])
    bass = theory.bass_line(chords, low=tonic - 26, high=tonic - 14)
    motifs = theory.motif_library()
    seed = sub_seed(cfg["region_id"], "fight")

    pad, combat, texture = [], [], []
    for bar in range(bars):
        ci = bar % len(prog)
        chord = chords[ci]
        beat = bar * bpb
        for half in (0.0, 2.0):
            for i, n in enumerate(chord):
                pad.append(Note(beat + half, 1.9, n, (0.44 if half == 0 else 0.34) - 0.03 * i, "pad"))
        pad.append(Note(beat, bpb * 0.98, bass[ci], 0.5, "bass"))
        root = bass[ci]
        fifth = _in_range(theory.degree_to_midi(prog[ci] + 4, tonic, mode), root + 1, root + 12)
        if bar % 2 == 0:
            figure = [root, root, fifth, root, root + 12, root, fifth, root]
        else:
            figure = [root, fifth, root, root + 12, root, fifth, root + 12, fifth]
        for i, midi in enumerate(figure):
            combat.append(Note(beat + i * 0.5, 0.45, midi, 0.6 if i % 2 == 0 else 0.42, "ostinato"))
        for (b, v) in ((0.0, 0.8), (1.0, 0.45), (1.5, 0.35), (2.0, 0.7), (2.75, 0.4), (3.0, 0.5),
                       (3.5, 0.45)):
            combat.append(Note(beat + b, 0.5, 36, v, "drum"))
        if bar % 2 == 0:
            combat.append(Note(beat, 1.0, 36, 0.62, "war"))
        if bar % 8 == 7:
            combat.append(Note(beat + 3.0, 1.0, 36, 0.55, "war"))
        if bar % 2 == 0:
            texture.append(Note(beat, 2.0, chord[-1] + 12, 0.46, "bell"))
        if bar % 4 in (1, 3):
            texture.append(Note(beat + 2.5, 0.75, chord[-1] + 12, 0.4, "stab"))
    s.add("pad", humanise(pad, sub_seed(seed, "pad"), 0.012, 0.06, beats_per_bar=bpb))
    s.add("combat", humanise(combat, sub_seed(seed, "combat"), 0.01, 0.08, beats_per_bar=bpb))
    s.add("texture", humanise(texture, sub_seed(seed, "texture"), 0.012, 0.08, beats_per_bar=bpb))

    lo, hi = tonic + 2, tonic + 26
    oct_shift = cfg["lead_octave"]
    # eight-bar blocks: the drums alone and then the Toll halved; the Toll whole; turned over by
    # the answering voice; its head, climbing
    plan = [(4, motifs["toll_dim"].sequence([0, 2], gap_beats=0.5), "lead"),
            (0, motifs["toll"].sequence([0, 2]), "lead"),
            (0, motifs["toll_inv"].diminish(2.0).sequence([0, -2, 0], gap_beats=0.5), "counter"),
            (0, motifs["toll_short"].sequence([0, 2, 4], gap_beats=1.0), "lead")]
    melody = []
    for k, start_bar in enumerate(range(0, bars, 8)):
        skip, motif, voice = plan[k % len(plan)]
        notes, _ = _place(motif, tonic, mode, prog[(start_bar + skip) % len(prog)],
                          (start_bar + skip) * bpb, min(start_bar + 8, bars) * bpb - 0.5, oct_shift,
                          1.0 if voice == "lead" else 0.8, voice, lo, hi)
        melody += notes
    s.add("melody", humanise(melody, sub_seed(seed, "melody"), 0.012, 0.08, beats_per_bar=bpb))
    _finish(s)
    return s


_VARIATION_COMPOSERS = {"day_2": _day_walk, "day_3": _day_air, "night_1": _night_low,
                        "night_2": _night_high, "fight": _fight}


def variation_score(key: str, kind: str) -> Score:
    """One of a region's rotation pieces (VARIATIONS), as note data."""
    return _VARIATION_COMPOSERS[kind](key)


# =================================================================================================
# Set pieces
# =================================================================================================

def main_theme() -> Score:
    """The menu theme: the Toll stated whole, answered, then stated again with the world under it.
    D lydian, the key Hearthvale opens in, because the game begins in the warmth."""
    tonic, mode, bpm, bars, bpb = 62, "lydian", 70.0, 32, 4
    s = Score("main_theme", tonic, mode, bpm, bars, bpb,
              meta={"title": "Wickmere", "colour": "the theme: a bell, and people answering it"})
    prog = [0, 3, 5, 1, 0, 4, 3, 0]
    chords = theory.progression(prog, tonic, mode, centre=57)
    bass = theory.bass_line(chords, low=36, high=48)
    motifs = theory.motif_library()
    pad, melody, texture = [], [], []
    for bar in range(bars):
        ci = bar % len(prog)
        beat = bar * bpb
        for i, n in enumerate(chords[ci]):
            pad.append(Note(beat, bpb - 0.02, n, 0.5 - 0.03 * i, "pad"))
        bass_v = 0.55 if bar >= 8 else 0.3
        pad.append(Note(beat, bpb * 0.98, bass[ci], bass_v, "bass"))
        if bar % 8 == 0:
            texture.append(Note(beat, bpb * 2, tonic + 12, 0.7 if bar == 0 else 0.5, "bell"))
        if bar >= 8:
            for i, idx in enumerate([0, 2, 1, 2]):
                texture.append(Note(beat + i, 0.9, chords[ci][idx % 3] + 12, 0.3, "arp"))
    # bars 1-8: the Toll alone. 9-16: answered. 17-24: augmented, high. 25-32: whole, full.
    for (start_bar, motif, octv, vel) in [(0, motifs["toll"], 12, 0.95), (8, motifs["answer"], 12, 0.8),
                                          (16, motifs["toll_aug"], 24, 0.7), (24, motifs["toll"], 12, 1.0)]:
        beat0 = start_bar * bpb
        for (b, dur, midi, v) in motif.to_notes(tonic, mode, 0, beat0):
            if b + dur <= (start_bar + 8) * bpb:
                melody.append(Note(b, dur, midi + octv, v * vel, "lead"))
    s.add("pad", humanise(pad, sub_seed("main", "pad"), 0.03, 0.08, beats_per_bar=bpb))
    s.add("melody", humanise(melody, sub_seed("main", "mel"), 0.025, 0.1, beats_per_bar=bpb))
    s.add("texture", humanise(texture, sub_seed("main", "tex"), 0.02, 0.12, beats_per_bar=bpb))
    _finish(s)
    return s


def naming_cue() -> Score:
    """The Naming (tutorial): the player is given a name at the Hushline's edge. It starts in
    Cinderlea's hollow phrygian and turns, on the last phrase, into Hearthvale's lydian: the
    one moment in the game where the mode itself changes, because the Foundling walks out."""
    tonic, bpm, bars, bpb = 52, 50.0, 16, 4
    s = Score("naming", tonic, "phrygian", bpm, bars, bpb,
              meta={"title": "The Naming", "colour": "hollow, then warm: a name is given",
                    "modulates_to": "lydian"})
    motifs = theory.motif_library()
    pad, melody = [], []
    for bar in range(bars):
        beat = bar * bpb
        if bar < 10:
            chord = theory.triad([0, 0, 6, 1][bar % 4], tonic, "phrygian")
            mode_here = "phrygian"
        else:
            # the turn: the same tonic heard as lydian, which is the warmth arriving
            chord = theory.triad([0, 3, 4, 0][(bar - 10) % 4], tonic + 2, "lydian")
            mode_here = "lydian"
        for i, n in enumerate(chord):
            pad.append(Note(beat, bpb - 0.02, n, 0.45 - 0.03 * i, "pad"))
        if bar == 0:
            melody.append(Note(beat, bpb * 2, tonic - 12, 0.6, "drone"))
        if bar in (4, 12):
            m = motifs["toll_short"] if bar == 4 else motifs["toll"]
            t = tonic if bar == 4 else tonic + 2
            for (b, dur, midi, v) in m.to_notes(t, mode_here, 0, beat):
                if b + dur <= bars * bpb:
                    melody.append(Note(b, dur, midi + 12, v * (0.6 if bar == 4 else 0.9), "lead"))
    s.add("pad", humanise(pad, sub_seed("naming", "pad"), 0.03, 0.08, beats_per_bar=bpb))
    s.add("melody", humanise(melody, sub_seed("naming", "mel"), 0.03, 0.1, beats_per_bar=bpb))
    _finish(s)
    return s


# Where the opening's shots begin, in seconds, and where its music turns. Read from the cinematic
# definition itself so the cue stays cut to the pictures when a shot is lengthened; these are the
# values it was written against, used when the definition cannot be read.
OPENING_JSON = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
                            "game", "content", "packs", "core", "cinematics", "opening.json")
OPENING_MARKS = {"the_name": 0.0, "the_mere": 6.0, "the_spire": 18.0, "the_nave": 27.0, "the_hand": 34.0,
                 "merrowby": 41.0, "the_roll": 49.0, "the_toll": 59.5, "the_choir": 68.5,
                 "the_stair": 78.5, "title": 7.0, "turn": 87.7, "handover": 94.5}


def opening_marks() -> dict:
    """Shot starts, the title card and the turn ("Then, this morning, you did.") in seconds."""
    try:
        with open(OPENING_JSON) as f:
            defs = json.load(f)
    except (OSError, ValueError):
        return dict(OPENING_MARKS)
    d = defs[0] if isinstance(defs, list) else defs
    marks, at = {}, 0.0
    for shot in d.get("shots", []):
        marks[shot["id"]] = at
        at += float(shot.get("duration", 0.0))
    marks["handover"] = at
    card = d.get("title_card", {})
    marks["title"] = marks.get(card.get("shot", ""), 0.0) + float(card.get("at", 0.0))
    stair = d.get("shots", [])[-1] if d.get("shots") else {}
    lines = stair.get("lines", [])
    marks["turn"] = marks.get(stair.get("id", ""), 0.0) + (float(lines[2]["at"]) if len(lines) > 2 else 9.0)
    for key, value in OPENING_MARKS.items():
        marks.setdefault(key, value)
    return marks


def opening_cue() -> Score:
    """The opening (DESIGN 5.1a): the music under the Warden's voice, cut to the shots.

    One bell in the dark. The Toll stated warm over the Mere as the title comes up (D lydian, the
    key the main theme opens in), and the Sayers' bells after it; the marsh in dorian and the
    clans' moor in mixolydian, each heard in its own mode; the Vale at its warmest; then it thins
    -- the quiet villages in B aeolian, the Toll's hum with a tine a half-step under it, Cinderlea's
    hollow E phrygian -- until "Then, this morning, you did.", where the Hush's phrygian turns
    lydian on the same E, as the Naming cue turns, and the Toll is stated once more and held as
    control comes back.

    At 60 bpm a beat is a second, so every section begins on a shot of core:cinematic/opening.
    It does not loop: it is played once and faded as the region's own music comes back.
    """
    m = opening_marks()
    bpm, bpb = 60.0, 4
    end = float(int(m["handover"]) + 6)
    bars = int(math.ceil(end / bpb))
    s = Score("opening", 52, "phrygian", bpm, bars, bpb,
              meta={"title": "The Opening", "loop": False,
                    "colour": "one bell, the country in its own modes, the hollow, and the turn",
                    "sections": []})
    motifs = theory.motif_library()
    pad, melody, texture = [], [], []

    def section(start: float, tonic: int, mode: str) -> None:
        s.meta["sections"].append((start, tonic, mode))

    def hold(notes, at: float, until: float, vel: float, voice: str, dest=None) -> None:
        for i, n in enumerate(notes):
            (dest if dest is not None else pad).append(Note(at, until - at - 0.02, n, vel - 0.03 * i, voice))

    def tune(motif, tonic: int, mode: str, at: float, until: float, octave: int, vel: float,
             voice: str = "lead") -> None:
        for (b, dur, midi, v) in motif.to_notes(tonic, mode, 0, at):
            if b >= until - 0.05:
                break
            melody.append(Note(b, min(dur, until - b - 0.02), midi + octave, v * vel, voice))

    def arpeggio(chord, at: float, until: float, per_beat: int, vel: float) -> None:
        b, i = at, 0
        step = 1.0 / per_beat
        while b < until - 0.05:
            n = chord[[0, 2, 1, 2][i % 4] % len(chord)] + (12 if i % 8 == 7 else 0)
            texture.append(Note(b, min(step * 0.9, until - b - 0.02), n, vel - 0.02 * (i % 4), "arp"))
            b += step
            i += 1

    # the name: one bell, and the Hush's hollow under it
    t0, t1 = m["the_name"], m["the_mere"]
    section(t0, 52, "phrygian")
    texture.append(Note(t0, t1 - t0 - 0.02, 52, 0.9, "bell"))
    pad.append(Note(t0 + 0.5, t1 - t0 - 0.52, 40, 0.45, "drone"))
    hold([55, 59], t0 + 2.0, t1, 0.34, "pad")

    # the Mere and the title: the Toll, warm, as the main theme states it
    a, b = m["the_mere"], m["the_spire"]
    section(a, 62, "lydian")
    texture.append(Note(a, 4.0, 86, 0.35, "bell"))
    mid = a + (b - a) / 3.0
    chords = theory.progression([0, 1, 0], 62, "lydian", centre=57)
    for (lo, hi), ch, bass in zip(((a, mid), (mid, mid + (b - a) / 3.0), (mid + (b - a) / 3.0, b)), chords, (38, 40, 38)):
        hold(ch, lo, hi, 0.46, "pad")
        hold(ch, lo, hi, 0.28, "choir")
        pad.append(Note(lo, hi - lo - 0.02, bass, 0.5, "bass"))
    tune(motifs["toll"], 62, "lydian", m["title"], b, 12, 0.95)
    arpeggio(chords[1], mid, b, 2, 0.30)

    # the Spire: the Sayers' bell, struck once and still ringing
    a, b = m["the_spire"], m["the_nave"]
    section(a, 62, "lydian")
    half = a + (b - a) * 0.5
    for (lo, hi), deg, bass in (((a, half), 5, 35), ((half, b), 4, 33)):
        ch = theory.triad(deg, 62, "lydian")
        hold(ch, lo, hi, 0.42, "pad")
        pad.append(Note(lo, hi - lo - 0.02, bass, 0.46, "bass"))
    for k, n in enumerate((81, 78, 74)):
        texture.append(Note(a + 2.0 * k, 4.0, n, 0.42 - 0.06 * k, "bell"))
    tune(motifs["answer"], 62, "lydian", a + 1.0, b, 12, 0.8)

    # the Drowned Nave: the tide, heard in the marsh's own mode, the Toll turned over and low
    a, b = m["the_nave"], m["the_hand"]
    section(a, 62, "dorian")
    half = a + (b - a) * 0.55
    # i then the major IV, dorian's own colour and the chord the turned-over Toll passes through
    for (lo, hi), deg, bass in (((a, half), 0, 38), ((half, b), 3, 43)):
        ch = theory.triad(deg, 62, "dorian")
        hold(ch, lo, hi, 0.36, "choir")
        pad.append(Note(lo, hi - lo - 0.02, bass, 0.40, "bass"))
    tune(motifs["toll_inv"], 62, "dorian", a + 1.0, b, 0, 0.55)

    # the Fallen Hand: the clans' breath, open fifths on the moor
    a, b = m["the_hand"], m["merrowby"]
    section(a, 62, "mixolydian")
    pad.append(Note(a, b - a - 0.02, 38, 0.45, "drone"))
    pad.append(Note(a, b - a - 0.02, 45, 0.36, "drone"))
    half = a + (b - a) * 0.5
    for (lo, hi), deg in (((a, half), 0), ((half, b), 6)):
        hold(theory.triad(deg, 62, "mixolydian"), lo, hi, 0.34, "pad")
    tune(motifs["toll_short"], 62, "mixolydian", a + 0.5, b, 12, 0.7)

    # Merrowby: the Vale at its warmest -- harp, choir, the answer the villages sing back
    a, b = m["merrowby"], m["the_roll"]
    section(a, 62, "lydian")
    texture.append(Note(a, 3.0, 81, 0.4, "bell"))
    half = a + (b - a) * 0.5
    chords = theory.progression([0, 1], 62, "lydian", centre=57)
    for (lo, hi), ch, bass in zip(((a, half), (half, b)), chords, (38, 40)):
        hold(ch, lo, hi, 0.44, "pad")
        hold(ch, lo, hi, 0.34, "choir")
        pad.append(Note(lo, hi - lo - 0.02, bass, 0.55, "bass"))
        arpeggio(ch, lo, hi, 2, 0.34)
    tune(motifs["answer"], 62, "lydian", a + 1.0, b, 12, 0.9)

    # the Roll: it thins; the names of the places that went quiet
    a, b = m["the_roll"], m["the_toll"]
    section(a, 59, "aeolian")
    half = a + (b - a) * 0.48
    for (lo, hi), deg, bass in (((a, half), 0, 35), ((half, b), 5, 31)):
        hold(theory.triad(deg, 59, "aeolian"), lo, hi, 0.34, "pad")
        pad.append(Note(lo, hi - lo - 0.02, bass, 0.38, "bass"))
    texture.append(Note(half, 3.0, 71, 0.26, "bell"))
    tune(motifs["hush"], 59, "aeolian", a + 0.5, b, 12, 0.7)

    # the Toll: the hum, and the tine a half-step under it, beating
    a, b = m["the_toll"], m["the_choir"]
    section(a, 52, "phrygian")
    pad.append(Note(a, b - a - 0.02, 40, 0.5, "drone"))
    pad.append(Note(a + 1.5, b - a - 1.52, 39, 0.32, "drone", tension=True))
    half = a + (b - a) * 0.5
    for (lo, hi), deg in (((a, half), 0), ((half, b), 1)):
        hold(theory.triad(deg, 52, "phrygian"), lo, hi, 0.30, "pad")
    tune(motifs["toll_aug"], 52, "phrygian", a + 0.5, b, 0, 0.5, voice="drone")

    # the Choir: Cinderlea's hollow, one bell
    a, b = m["the_choir"], m["the_stair"]
    section(a, 52, "phrygian")
    texture.append(Note(a, 6.0, 64, 0.5, "bell"))
    pad.append(Note(a, b - a - 0.02, 40, 0.44, "drone"))
    half = a + (b - a) * 0.5
    for (lo, hi), deg in (((a, half), 0), ((half, b), 6)):
        hold(theory.triad(deg, 52, "phrygian"), lo, hi, 0.30, "pad")
    tune(motifs["toll_short"], 52, "phrygian", a + 2.0, b, 12, 0.45)

    # the Stair: hollow still, until you are the one who walked up it
    a, turn = m["the_stair"], m["turn"]
    section(a, 52, "phrygian")
    texture.append(Note(a, 5.0, 52, 0.6, "bell"))
    pad.append(Note(a, turn - a - 0.02, 40, 0.42, "drone"))
    half = a + (turn - a) * 0.5
    for (lo, hi), deg in (((a, half), 0), ((half, turn), 3)):
        hold(theory.triad(deg, 52, "phrygian"), lo, hi, 0.30, "pad")
    tune(motifs["hush"], 52, "phrygian", a + 1.0, turn, 12, 0.45)

    # the turn: the same E, heard lydian -- the colour coming back into your hands
    section(turn, 52, "lydian")
    warm = theory.triad(0, 52, "lydian")
    texture.append(Note(turn, 6.0, 88, 0.42, "bell"))
    texture.append(Note(turn + 3.5, 5.0, 83, 0.34, "bell"))
    hold(warm, turn, end, 0.46, "pad")
    hold([n + 12 for n in warm], turn + 0.5, end, 0.32, "choir")
    pad.append(Note(turn, end - turn - 0.02, 40, 0.55, "bass"))
    arpeggio([n + 12 for n in warm], turn + 0.5, m["handover"] + 1.0, 2, 0.30)
    tune(motifs["toll"], 64, "lydian", turn + 0.3, end, 12, 0.9)

    s.add("pad", humanise(pad, sub_seed("opening", "pad"), 0.02, 0.06, beats_per_bar=bpb))
    s.add("melody", humanise(melody, sub_seed("opening", "mel"), 0.02, 0.08, beats_per_bar=bpb))
    s.add("texture", humanise(texture, sub_seed("opening", "tex"), 0.015, 0.1, beats_per_bar=bpb))
    _finish(s)
    return s


def boss_score(intensity: int = 1) -> Score:
    """Boss music in two intensities. Intensity 1 is a circling threat; intensity 2 adds the
    choir, doubles the pulse and puts the Toll in the bass, for a phase change."""
    tonic, mode, bpm, bars, bpb = 50, "phrygian", 100.0 if intensity == 1 else 116.0, 24, 4
    s = Score("boss_%d" % intensity, tonic, mode, bpm, bars, bpb,
              meta={"title": "Boss %d" % intensity, "intensity": intensity,
                    "colour": "the last holder of a note, and it is not yours"})
    prog = [0, 0, 1, 0, 6, 6, 1, 0]
    chords = theory.progression(prog, tonic, mode, centre=50)
    bass = theory.bass_line(chords, low=28, high=40)
    motifs = theory.motif_library()
    combat, pad = [], []
    div = 2 if intensity == 1 else 4          # ostinato notes per beat
    for bar in range(bars):
        ci = bar % len(prog)
        beat = bar * bpb
        chord = chords[ci]
        for i, n in enumerate(chord):
            pad.append(Note(beat, bpb - 0.02, n, 0.4 - 0.03 * i, "pad"))
        for i in range(bpb * div):
            b = beat + i / div
            midi = bass[ci] if i % div else bass[ci] - 0 if i else bass[ci]
            combat.append(Note(b, 1.0 / div * 0.9, midi, 0.55 if i % div == 0 else 0.35, "ostinato"))
        hits = [(0.0, 0.9), (1.0, 0.45), (2.0, 0.75), (3.0, 0.5)]
        if intensity == 2:
            hits += [(0.5, 0.4), (2.5, 0.5), (3.5, 0.55)]
        for (b, v) in hits:
            combat.append(Note(beat + b, 0.4, 36, v, "drum"))
        if bar % 4 == 0:
            combat.append(Note(beat, 2.0, tonic + 12, 0.55, "bell"))
    if intensity == 2:
        # the Toll itself, slow and in the bass: the note the boss is holding
        for (b, dur, midi, v) in motifs["toll_aug"].to_notes(tonic, mode, 0, 0.0):
            if b + dur <= bars * bpb:
                combat.append(Note(b, dur, midi - 12, v * 0.6, "drone"))
        for bar in range(bars):
            if bar % 2 == 0:
                combat.append(Note(bar * bpb + 2.0, 2.0, chords[bar % len(prog)][-1] + 12, 0.4, "choir"))
    s.add("pad", humanise(pad, sub_seed("boss", intensity, "pad"), 0.02, 0.08, beats_per_bar=bpb))
    s.add("combat", humanise(combat, sub_seed("boss", intensity, "combat"), 0.012, 0.1,
                             beats_per_bar=bpb))
    _finish(s)
    return s


def stinger(kind: str) -> Score:
    """Short non-looping cues. Each is the Toll in some state: struck, broken off, or answered."""
    motifs = theory.motif_library()
    specs = {
        # name: (tonic, mode, bpm, bars, description)
        "victory": (62, "lydian", 84.0, 4, "the motif answered, up and open"),
        "death": (52, "phrygian", 46.0, 4, "the motif broken off; the bell keeps ringing"),
        "level_up": (67, "ionian", 96.0, 2, "three chimes and a fifth: you are more real"),
        "quest_update": (67, "ionian", 104.0, 2, "two chimes, a question answered"),
        "rest": (62, "lydian", 58.0, 4, "the hearthstone: warmth, a held chord, a small bell"),
        "echo": (57, "dorian", 52.0, 3, "what you left behind comes back"),
        "menu_select": (67, "ionian", 120.0, 1, "brass click with a pitch"),
    }
    tonic, mode, bpm, bars, colour = specs[kind]
    bpb = 4
    s = Score("stinger_%s" % kind, tonic, mode, bpm, bars, bpb,
              meta={"title": kind, "colour": colour, "loop": False})
    mel, pad = [], []
    if kind == "victory":
        chord = theory.triad(0, tonic, mode)
        for i, n in enumerate(chord + [tonic + 12]):
            pad.append(Note(0.0, bars * bpb, n, 0.5 - 0.04 * i, "pad"))
        for (b, dur, midi, v) in motifs["toll_short"].to_notes(tonic, mode, 0, 0.0):
            mel.append(Note(b * 0.75, dur * 0.75, midi + 12, v, "lead"))
        mel.append(Note(3.0, 5.0, tonic + 19, 0.9, "bell"))
    elif kind == "death":
        for i, n in enumerate(theory.triad(0, tonic, mode)):
            pad.append(Note(0.0, bars * bpb, n - 12, 0.45 - 0.05 * i, "pad"))
        # the motif starts and stops: two notes, then the bell alone
        notes = motifs["toll"].to_notes(tonic, mode, 0, 0.0)[:2]
        for (b, dur, midi, v) in notes:
            mel.append(Note(b, dur, midi, v * 0.8, "lead"))
        mel.append(Note(2.0, bars * bpb, tonic - 12, 0.85, "bell"))
    elif kind == "level_up":
        for i, d in enumerate([0, 2, 4]):
            mel.append(Note(i * 0.5, 2.0, theory.degree_to_midi(d, tonic, mode) + 12, 0.7, "bell"))
        mel.append(Note(1.5, 4.0, tonic + 24, 0.8, "bell"))
    elif kind == "quest_update":
        mel.append(Note(0.0, 1.5, tonic + 12, 0.6, "bell"))
        mel.append(Note(0.5, 2.5, theory.degree_to_midi(4, tonic, mode) + 12, 0.65, "bell"))
    elif kind == "rest":
        warm = theory.triad(0, tonic, mode) + [theory.degree_to_midi(8, tonic, mode)]
        for i, n in enumerate(warm):
            pad.append(Note(0.0, bars * bpb, n, 0.5 - 0.04 * i, "pad"))
        for (b, dur, midi, v) in motifs["answer"].to_notes(tonic, mode, 0, 1.0):
            mel.append(Note(b, dur, midi + 12, v * 0.55, "lead"))
        mel.append(Note(0.0, 6.0, tonic + 12, 0.45, "bell"))
    elif kind == "echo":
        for i, n in enumerate(theory.triad(0, tonic, mode)):
            pad.append(Note(0.0, bars * bpb, n, 0.4 - 0.04 * i, "pad"))
        # the motif's head, but inverted: it is you, the wrong way round
        for (b, dur, midi, v) in motifs["toll_inv"].fragment(3).to_notes(tonic, mode, 0, 0.0):
            mel.append(Note(b, dur, midi + 12, v * 0.6, "lead"))
    elif kind == "menu_select":
        mel.append(Note(0.0, 1.0, tonic + 24, 0.5, "bell"))
    s.add("pad", pad)
    s.add("melody", mel)
    _finish(s)
    return s


STINGERS = ["victory", "death", "level_up", "quest_update", "rest", "echo", "menu_select"]


def all_scores() -> dict:
    """Everything the music generator renders, by output name."""
    out = {}
    for key in REGIONS:
        out["region:" + key] = region_score(key)
        for kind in VARIATIONS:
            out["variation:%s/%s" % (key, kind)] = variation_score(key, kind)
    out["main_theme"] = main_theme()
    out["naming"] = naming_cue()
    out["opening"] = opening_cue()
    out["boss_1"] = boss_score(1)
    out["boss_2"] = boss_score(2)
    for k in STINGERS:
        out["stinger:" + k] = stinger(k)
    return out


# =================================================================================================
# Analysis used by the tests and the report
# =================================================================================================

def simultaneities(notes, tolerance: float = 1e-6):
    """Every set of notes sounding together, as (beat, [midi...]). Used to check for clashes."""
    events = sorted({round(n.beat, 6) for n in notes})
    out = []
    for b in events:
        sounding = [n for n in notes if n.beat <= b + tolerance and n.end() > b + tolerance]
        if len(sounding) > 1:
            out.append((b, sorted(n.midi for n in sounding), any(n.tension for n in sounding)))
    return out


# Voices with no pitch of their own: their MIDI number selects a drum, not a note, so the
# mode rules do not apply to them.
UNPITCHED_VOICES = {"drum", "war"}

# Which stems the game actually sounds together (see music_director.gd). `deep` replaces the
# melody rather than joining it, and `combat` layers over the exploration bed. Checking the
# harmony across stems that never play at once would condemn chords that no one ever hears.
PLAY_COMBINATIONS = {
    "explore": ["pad", "melody", "texture"],
    "combat": ["pad", "texture", "combat"],
    "deep": ["pad", "deep"],
    "deep_combat": ["deep", "combat"],
}


def combinations_of(score: Score) -> list:
    """The stem combinations a score is heard in: the director's, or all of it at once."""
    return [WHOLE] if score.meta.get("whole") else list(PLAY_COMBINATIONS)


def sounding_together(score: Score, combination: str):
    """The pitched notes of one playing combination, merged."""
    out = []
    for stem in (list(score.stems) if combination == WHOLE else PLAY_COMBINATIONS[combination]):
        out.extend(n for n in score.notes(stem) if n.voice not in UNPITCHED_VOICES)
    return out


def clashes(score: Score, combination: str, min_beats: float = 0.0):
    """Simultaneous minor seconds (or minor ninths) in a playing combination that are not
    marked as deliberate tension. `min_beats` ignores pairs where either note is shorter than
    that, which is how passing tones are excluded when a caller wants only sustained clashes."""
    notes = sounding_together(score, combination)
    beats = sorted({round(n.beat, 6) for n in notes})
    found = []
    for b in beats:
        snd = [n for n in notes if n.beat <= b + 1e-6 and n.end() > b + 1e-6]
        for i in range(len(snd)):
            for j in range(i + 1, len(snd)):
                if abs(snd[i].midi - snd[j].midi) not in (1, 13):
                    continue
                if snd[i].tension or snd[j].tension:
                    continue
                if min(snd[i].beats, snd[j].beats) < min_beats:
                    continue
                # The beat is reported unrounded: resolve_clashes looks notes up by it, and
                # rounding it moved the key past the note's own start time so the lookup failed.
                found.append((b, snd[i].voice, snd[i].midi, snd[j].voice, snd[j].midi))
    return found


def out_of_mode(score: Score) -> list:
    """Notes that are not in the score's mode.

    Percussion is exempt (its MIDI number picks a drum), and so is a note marked as deliberate
    tension, which is chromatic on purpose. A score that changes mode part-way declares the
    destination in meta["modulates_to"], and a note is accepted if it belongs to either mode --
    the Naming cue does this. A through-composed piece declares meta["sections"], a list of
    (start_beat, tonic, mode), and each note answers to the section it starts in, or to the next
    one when humanising has nudged it a hair before the boundary it was written on.
    """
    bad = []
    accepted = [(score.tonic, score.mode)]
    if score.meta.get("modulates_to"):
        accepted.append((score.tonic + 2, score.meta["modulates_to"]))
    sections = sorted(score.meta.get("sections") or [])

    def section_at(beat: float):
        found = None
        for start, tonic, mode in sections:
            if start <= beat + 1e-6:
                found = (tonic, mode)
        return found

    for stem, notes in score.stems.items():
        for n in notes:
            if n.voice in UNPITCHED_VOICES or n.tension:
                continue
            modes = accepted
            if sections:
                modes = [m for m in (section_at(n.beat), section_at(n.beat + 0.1)) if m is not None]
            if not any(theory.in_mode(n.midi, t, m) for t, m in modes):
                bad.append((stem, n.beat, n.midi))
    return bad
