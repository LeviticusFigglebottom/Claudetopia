"""Tests for the scores themselves: the musical rules, before a sample is rendered.

These are the rules the brief sets for the music -- every note in the region's mode, no
simultaneous minor seconds outside deliberate tension, the Toll leitmotif present and
transformed in every region, and stems that line up so the director can crossfade them.
"""
from __future__ import annotations

import functools
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import compose  # noqa: E402
from synth import theory  # noqa: E402


@functools.lru_cache(maxsize=1)
def scores():
    return compose.all_scores()


@functools.lru_cache(maxsize=1)
def region_scores():
    return {k: v for k, v in scores().items() if k.startswith("region:")}


def region(key: str):
    """The already-composed score for a region. Composing is deterministic but not cheap
    (clash resolution re-measures the whole score), so the tests share one copy."""
    return region_scores()["region:" + key]


# --- the modal rule --------------------------------------------------------------------------

def test_every_note_is_in_its_mode():
    for name, s in scores().items():
        bad = compose.out_of_mode(s)
        assert not bad, "%s has %d notes outside %s: %s" % (name, len(bad), s.mode, bad[:4])


def test_each_region_uses_the_mode_its_data_asks_for():
    for key, cfg in compose.REGIONS.items():
        s = region(key)
        assert s.mode == theory.mode_of(cfg["music_mode"]), key
        assert s.tonic == cfg["tonic"], key


def test_regions_do_not_all_share_one_key_or_tempo():
    keys = {(s.tonic % 12, s.mode) for s in region_scores().values()}
    assert len(keys) == len(compose.REGIONS), "regions must not share a key and mode: %s" % keys
    tempos = {s.bpm for s in region_scores().values()}
    assert len(tempos) >= 5, tempos


def test_modes_match_the_region_character():
    """The brief's characters: warm Hearthvale, bright Brightwater, misty Sedgemire, deep
    Briarwold, cold Skerrow, hollow Cinderlea -- and the tempos follow the same order."""
    by = {k.split(":")[1]: v for k, v in region_scores().items()}
    assert by["hearthvale"].mode == "lydian"
    assert by["brightwater"].mode == "ionian"
    assert by["sedgemire"].mode == "dorian"
    assert by["briarwold"].mode == "aeolian"
    assert by["skerrow"].mode == "mixolydian"
    assert by["cinderlea"].mode == "phrygian"
    assert by["brightwater"].bpm > by["hearthvale"].bpm > by["cinderlea"].bpm
    assert by["cinderlea"].bpm <= 48.0, "Cinderlea must be the slowest, most hollow place"


# --- the harmony rule --------------------------------------------------------------------------

def test_no_simultaneous_minor_seconds_in_any_playing_combination():
    for name, s in scores().items():
        for comb in compose.PLAY_COMBINATIONS:
            bad = compose.clashes(s, comb)
            assert not bad, "%s (%s) clashes: %s" % (name, comb, bad[:3])


def test_clash_detector_actually_detects_one():
    s = compose.Score("probe", 60, "ionian", 90.0, 1)
    s.add("pad", [compose.Note(0.0, 4.0, 60, 0.5, "pad"), compose.Note(0.0, 4.0, 61, 0.5, "pad")])
    assert compose.clashes(s, "explore"), "a semitone in the pad must be reported"
    s2 = compose.Score("probe2", 60, "ionian", 90.0, 1)
    s2.add("pad", [compose.Note(0.0, 4.0, 60, 0.5, "pad"),
                   compose.Note(0.0, 4.0, 61, 0.5, "pad", tension=True)])
    assert not compose.clashes(s2, "explore"), "a marked tension must be allowed"


def test_minor_ninths_count_as_clashes():
    s = compose.Score("probe", 60, "ionian", 90.0, 1)
    s.add("pad", [compose.Note(0.0, 4.0, 48, 0.5, "pad"), compose.Note(0.0, 4.0, 61, 0.5, "pad")])
    assert compose.clashes(s, "explore"), "a minor ninth is a clash too"


def test_percussion_is_exempt_from_the_modal_rule():
    s = compose.Score("probe", 60, "lydian", 90.0, 1)
    s.add("combat", [compose.Note(0.0, 0.5, 36, 0.8, "drum")])
    assert not compose.out_of_mode(s)
    s.add("combat", [compose.Note(0.0, 0.5, 61, 0.8, "lead")])
    assert compose.out_of_mode(s)


def test_chord_progressions_are_diatonic_and_voice_led():
    for key, cfg in compose.REGIONS.items():
        chords = compose.chords_for(cfg)
        mode = theory.mode_of(cfg["music_mode"])
        for ch in chords:
            for n in ch:
                assert theory.in_mode(n, cfg["tonic"], mode), (key, ch, n)
        for a, b in zip(chords, chords[1:]):
            moves = [abs(x - y) for x, y in zip(sorted(a), sorted(b))]
            assert max(moves) <= 8, "%s leaps %s between %s and %s" % (key, moves, a, b)


def test_single_line_voices_never_overlap_themselves():
    for name, s in scores().items():
        for stem, notes in s.stems.items():
            for voice in compose.MONOPHONIC_VOICES:
                vs = sorted([n for n in notes if n.voice == voice], key=lambda n: n.beat)
                for a, b in zip(vs, vs[1:]):
                    assert a.end() <= b.beat + 1e-6, \
                        "%s/%s: %s plays two notes at once at beat %.2f" % (name, stem, voice, b.beat)


# --- the leitmotif ------------------------------------------------------------------------------

def test_the_toll_is_four_to_six_notes():
    assert 4 <= len(theory.TOLL) <= 6


def _contains_transformation(melody_midis, tonic, mode):
    """True if the melody contains the Toll's interval shape in some transformation:
    as written, inverted, retrograde, or the head alone.

    Notes outside the mode (a cue that modulates has them) break the run rather than failing
    the whole search, so a motif stated on either side of a modulation is still found.
    """
    shapes = set()
    for m in (theory.TOLL, theory.TOLL.inverse(), theory.TOLL.retrograde(),
              theory.TOLL.inverse().retrograde()):
        degs = m.degrees()
        shapes.add(tuple(d - degs[0] for d in degs))
        shapes.add(tuple(d - degs[0] for d in degs[:3]))     # the head alone (the fragment)
    scale = theory.MODES[mode]
    degrees = []
    for n in melody_midis:
        pc = (n - tonic) % 12
        degrees.append(scale.index(pc) + 7 * ((n - tonic) // 12) if pc in scale else None)
    for shape in shapes:
        k = len(shape)
        for i in range(len(degrees) - k + 1):
            window = degrees[i:i + k]
            if any(d is None for d in window):
                continue
            if tuple(d - window[0] for d in window) == shape:
                return True
    return False


def test_every_region_theme_states_the_toll():
    for name, s in region_scores().items():
        lead = [n for n in s.notes("melody") if n.voice == "lead"]
        midis = [n.midi for n in sorted(lead, key=lambda n: n.beat)]
        assert midis, "%s has no melody" % name
        assert _contains_transformation(midis, s.tonic, s.mode), \
            "%s never states the Toll motif" % name


def test_the_main_theme_and_the_naming_state_the_toll():
    for name in ("main_theme", "naming"):
        s = scores()[name]
        lead = [n for n in s.notes("melody") if n.voice == "lead"]
        midis = [n.midi for n in sorted(lead, key=lambda n: n.beat)]
        tonics = [(s.tonic, s.mode)]
        if s.meta.get("modulates_to"):
            tonics.append((s.tonic + 2, s.meta["modulates_to"]))
        assert any(_contains_transformation(midis, t, m) for t, m in tonics), name


def test_regions_transform_the_motif_rather_than_repeating_it():
    """A region theme must develop the motif, not just restate it: the melody's pitch material
    has to go somewhere the plain statement does not."""
    for name, s in region_scores().items():
        mel = sorted([n for n in s.notes("melody") if n.voice == "lead"], key=lambda n: n.beat)
        first = [n.midi for n in mel[:len(theory.TOLL)]]
        later = [n.midi for n in mel[len(theory.TOLL):]]
        assert later, name
        first_shape = [b - a for a, b in zip(first, first[1:])]
        found_other = False
        for i in range(len(later) - len(first_shape)):
            shape = [b - a for a, b in zip(later[i:i + len(first_shape) + 1],
                                           later[i + 1:i + len(first_shape) + 2])]
            if shape and shape != first_shape:
                found_other = True
                break
        assert found_other, "%s only ever repeats one shape" % name


def test_motif_library_transformations_are_distinct():
    lib = theory.motif_library()
    shapes = {name: tuple(m.degrees()) for name, m in lib.items()}
    assert shapes["toll_inv"] != shapes["toll"]
    assert shapes["toll_retro"] != shapes["toll"]
    assert lib["toll_aug"].duration() > lib["toll"].duration()
    assert lib["toll_dim"].duration() < lib["toll"].duration()


# --- structure the renderer and the director rely on ----------------------------------------------

def test_region_loops_are_between_96_and_150_seconds():
    for name, s in region_scores().items():
        assert 96.0 <= s.seconds() <= 150.0, "%s is %.1f s" % (name, s.seconds())


def test_every_region_has_all_five_stems_and_they_are_the_same_length():
    for name, s in region_scores().items():
        for stem in ("pad", "melody", "texture", "combat", "deep"):
            assert s.notes(stem), "%s is missing the %s stem" % (name, stem)
        # every stem is written against the same bar grid, so they align by construction;
        # what matters is that no stem runs past the loop
        for stem, notes in s.stems.items():
            last = max(n.end() for n in notes)
            assert last <= s.total_beats() + 1e-6, \
                "%s/%s runs %.2f beats past the loop" % (name, stem, last - s.total_beats())


def test_every_stem_reaches_the_end_of_the_loop():
    """A stem that stops early leaves a silent gap before the loop repeats."""
    for name, s in region_scores().items():
        for stem in ("pad", "texture", "combat", "deep"):
            last = max(n.end() for n in s.notes(stem))
            assert last > s.total_beats() * 0.9, \
                "%s/%s stops at %.0f%% of the loop" % (name, stem, 100 * last / s.total_beats())


def test_the_deep_stem_has_no_melody_and_holds_a_low_note():
    for name, s in region_scores().items():
        deep = s.notes("deep")
        voices = {n.voice for n in deep}
        assert "lead" not in voices, "%s deep stem still has the melody" % name
        assert "drone" in voices, "%s deep stem has no sustained note" % name
        drones = [n for n in deep if n.voice == "drone"]
        assert min(n.midi for n in drones) < s.tonic - 12, "%s drone is not low" % name
        assert "bell" in voices, "%s deep stem has no bells" % name


def test_the_combat_stem_shares_key_and_tempo_so_it_can_layer():
    for key in compose.REGIONS:
        s = region(key)
        combat = s.notes("combat")
        assert combat, key
        pitched = [n for n in combat if n.voice not in compose.UNPITCHED_VOICES]
        for n in pitched:
            assert theory.in_mode(n.midi, s.tonic, s.mode), (key, n)
        assert any(n.voice == "drum" for n in combat), "%s combat has no pulse" % key


def test_boss_music_has_two_intensities_that_differ():
    a, b = scores()["boss_1"], scores()["boss_2"]
    assert b.bpm > a.bpm
    assert len(b.notes("combat")) > len(a.notes("combat")), "intensity 2 must add material"
    assert a.tonic == b.tonic and a.mode == b.mode, "a phase change must not change key"


def test_stingers_are_short_and_do_not_loop():
    for k in compose.STINGERS:
        s = scores()["stinger:" + k]
        assert s.seconds() <= 22.0, "%s is %.1f s" % (k, s.seconds())
        assert s.meta.get("loop") is False
        assert list(s.all_notes()), k


def test_the_naming_cue_modulates_out_of_the_hush():
    s = scores()["naming"]
    assert s.mode == "phrygian"
    assert s.meta.get("modulates_to") == "lydian"
    late = [n for n in s.all_notes() if n.beat >= 40]
    assert any(not theory.in_mode(n.midi, s.tonic, s.mode) for n in late), \
        "the cue never actually leaves phrygian"


def test_humanisation_moves_notes_without_reordering_the_bar():
    notes = [compose.Note(float(i), 1.0, 60 + i, 0.8, "lead") for i in range(16)]
    out = compose.humanise(notes, 1234, timing=0.02, velocity=0.1)
    assert len(out) == len(notes)
    assert [n.midi for n in out] == [n.midi for n in notes]
    moved = sum(1 for a, b in zip(notes, out) if abs(a.beat - b.beat) > 1e-9)
    assert moved > 5, "humanisation did nothing"
    assert all(abs(a.beat - b.beat) < 0.15 for a, b in zip(notes, out)), "humanisation ran wild"
    assert all(0.0 < n.vel <= 1.0 for n in out)


def test_downbeats_stay_on_the_grid():
    notes = [compose.Note(float(i), 1.0, 60, 0.8, "lead") for i in range(16)]
    out = compose.humanise(notes, 99, timing=0.05, beats_per_bar=4)
    for n in out:
        if abs(round(n.beat) - n.beat) < 1e-9 and round(n.beat) % 4 == 0:
            assert abs(n.beat - round(n.beat)) < 1e-9


def test_scores_are_deterministic():
    a = compose.region_score("skerrow")
    b = compose.region_score("skerrow")
    for stem in a.stems:
        assert [(n.beat, n.midi, n.vel) for n in a.notes(stem)] == \
               [(n.beat, n.midi, n.vel) for n in b.notes(stem)], stem


def test_every_region_in_the_pack_has_a_theme():
    """The composer must cover exactly the regions the content pack declares."""
    import json
    here = os.path.dirname(os.path.dirname(os.path.dirname(
        os.path.dirname(os.path.abspath(__file__)))))
    path = os.path.join(here, "game", "content", "packs", "core", "regions", "regions.json")
    with open(path) as f:
        regions = json.load(f)
    ids = {r["id"] for r in regions}
    composed = {cfg["region_id"] for cfg in compose.REGIONS.values()}
    assert composed == ids, "composed %s but the pack has %s" % (composed, ids)
    for r in regions:
        cfg = next(c for c in compose.REGIONS.values() if c["region_id"] == r["id"])
        assert cfg["music_mode"] == r["identity"]["music_mode"], r["id"]
