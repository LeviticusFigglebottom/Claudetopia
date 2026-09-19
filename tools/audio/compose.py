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
        colour="warm and lyrical: a flute over a harp, the small bells the Vale hangs in trees",
    ),
    "brightwater": dict(
        region_id="core:region/brightwater",
        title="The Long Stride",
        tonic=67, music_mode="ionian_bright", bpm=92.0, bars=40, swing=0.0,
        progression=[0, 4, 5, 3, 0, 3, 4, 0],
        lead="whistle", pad_voice="pad", texture="pluck", bass="cello",
        reverb="chamber", reverb_mix=0.20, centre=59, lead_octave=12,
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
        colour="misty and modal: a breathy flute a long way off over still water",
    ),
    "briarwold": dict(
        region_id="core:region/briarwold",
        title="Under the Grandfather",
        tonic=52, music_mode="aeolian_deep", bpm=54.0, bars=24, swing=0.0,
        progression=[0, 5, 2, 6, 0, 3, 4, 0],
        lead="cello", pad_voice="choir", texture="pluck", bass="cello",
        reverb="cave", reverb_mix=0.30, centre=50, lead_octave=12,
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
        for comb in PLAY_COMBINATIONS:
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
                    before = sum(len(clashes(score, c)) for c in PLAY_COMBINATIONS)
                    fixed = False
                    for shift in (12, -12, 24, -24):
                        if not (20 <= n.midi + shift <= 104):
                            continue
                        notes[idx] = Note(n.beat, n.beats, n.midi + shift, n.vel, n.voice, n.tension)
                        after = sum(len(clashes(score, c)) for c in PLAY_COMBINATIONS)
                        if after < before:
                            moved += 1
                            progress = fixed = True
                            break
                        notes[idx] = n
                    if not fixed and voice in DROPPABLE_VOICES:
                        notes.pop(idx)
                        if sum(len(clashes(score, c)) for c in PLAY_COMBINATIONS) < before:
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
    score.meta["clashes"] = {c: len(clashes(score, c)) for c in PLAY_COMBINATIONS}


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
        # an arpeggio whose density follows the region's tempo: fast places move more
        density = 2 if cfg["bpm"] < 62 else 4
        pattern = [0, 2, 1, 2][:density] if density == 4 else [0, 2]
        for i, idx in enumerate(pattern):
            b = beat + i * (bpb / density)
            midi = chord[idx % len(chord)] + (12 if i % 4 == 3 else 0)
            texture.append(Note(b, bpb / density * 0.9, midi, 0.34 - 0.03 * i, "arp"))
        # a bell marks the start of every phrase: the ringing the region is made of
        if bar % phrase_bars == 0:
            texture.append(Note(beat, bpb * 2.0, tonic + 12, 0.5 if bar else 0.62, "bell"))
        elif bar % 4 == 2 and r.random() < 0.35:
            texture.append(Note(beat + bpb * 0.5, bpb, chord[1] + 12, 0.28, "bell"))
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
            combat.append(Note(b, 0.45, midi, 0.5 if i % 2 == 0 else 0.34, "ostinato"))
        # drum: a heartbeat that doubles up as the bar goes on
        for i, (b, v) in enumerate([(0.0, 0.85), (1.5, 0.5), (2.0, 0.7), (3.5, 0.45)]):
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
    out["main_theme"] = main_theme()
    out["naming"] = naming_cue()
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
UNPITCHED_VOICES = {"drum"}

# Which stems the game actually sounds together (see music_director.gd). `deep` replaces the
# melody rather than joining it, and `combat` layers over the exploration bed. Checking the
# harmony across stems that never play at once would condemn chords that no one ever hears.
PLAY_COMBINATIONS = {
    "explore": ["pad", "melody", "texture"],
    "combat": ["pad", "texture", "combat"],
    "deep": ["pad", "deep"],
    "deep_combat": ["deep", "combat"],
}


def sounding_together(score: Score, combination: str):
    """The pitched notes of one playing combination, merged."""
    out = []
    for stem in PLAY_COMBINATIONS[combination]:
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

    Percussion is exempt (its MIDI number picks a drum). A score that changes mode part-way
    declares the destination in meta["modulates_to"], and a note is accepted if it belongs to
    either mode -- the Naming cue is the one piece that does this, and deliberately.
    """
    bad = []
    accepted = [(score.tonic, score.mode)]
    if score.meta.get("modulates_to"):
        accepted.append((score.tonic + 2, score.meta["modulates_to"]))
    for stem, notes in score.stems.items():
        for n in notes:
            if n.voice in UNPITCHED_VOICES:
                continue
            if not any(theory.in_mode(n.midi, t, m) for t, m in accepted):
                bad.append((stem, n.beat, n.midi))
    return bad
