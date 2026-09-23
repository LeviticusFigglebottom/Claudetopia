"""Tests for the three generators: coverage of the game's data, and the shape of what they make.

These render only short excerpts -- the full set takes a quarter of an hour and is checked by
report.py instead. What is checked here is that nothing the game asks for is missing, that
stems line up, that loops fold correctly, and that one-shots start and end cleanly.
"""
from __future__ import annotations

import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.dirname(os.path.abspath(__file__)))))

import compose  # noqa: E402
import gen_ambience  # noqa: E402
import gen_music  # noqa: E402
import gen_sfx  # noqa: E402
from synth import core, render  # noqa: E402

SR = core.SR


def _regions():
    with open(os.path.join(ROOT, "game", "content", "packs", "core", "regions",
                           "regions.json")) as f:
        return json.load(f)


# --- coverage of the game's own data --------------------------------------------------------

def test_every_ambience_key_in_the_pack_has_a_generator():
    keys = set()
    for r in _regions():
        keys.update(r["identity"].get("ambience", []))
    missing = sorted(keys - set(gen_ambience.CATALOGUE))
    assert not missing, "no ambience generator for %s" % missing


def test_the_ambience_catalogue_covers_weather_and_time():
    for key in ("rain_light", "rain_heavy", "wind_gust_light", "wind_gust_strong", "snow_hush",
                "thunder_near", "thunder_far", "night_insects", "dawn_chorus", "room_tone"):
        assert key in gen_ambience.CATALOGUE, key


def test_every_weather_state_the_pack_declares_can_be_heard():
    """Every weather def's precipitation and wind must map onto a layer that exists."""
    with open(os.path.join(ROOT, "game", "content", "packs", "core", "weather",
                           "weather.json")) as f:
        weather = json.load(f)
    for w in weather:
        precip = w.get("precipitation", "none")
        if precip == "rain":
            assert "rain_light" in gen_ambience.CATALOGUE and "rain_heavy" in gen_ambience.CATALOGUE
        elif precip == "snow":
            assert "snow_hush" in gen_ambience.CATALOGUE
        elif precip == "ash":
            assert "ash_hiss" in gen_ambience.CATALOGUE
        if w.get("thunder"):
            assert "thunder_near" in gen_ambience.CATALOGUE
        if float(w.get("wind", 0)) > 0.5:
            assert "wind_gust_strong" in gen_ambience.CATALOGUE


def test_sfx_catalogue_covers_the_brief():
    needed = [
        "armour_light", "armour_heavy", "sword_swing_light", "sword_swing_heavy", "axe_swing",
        "mace_swing", "impact_flesh", "impact_wood", "impact_metal", "impact_stone",
        "block_clang", "parry_clang", "stagger_thud", "bow_draw", "bow_release",
        "arrow_whoosh", "arrow_hit", "potion_drink", "eat", "pick_up", "coins_few", "coins_many",
        "door_wood_open", "door_wood_close", "door_iron_open", "door_iron_close", "chest_open",
        "lockpick_click", "lockpick_break", "ui_paper_slide", "ui_brass_click", "ui_hover_tick",
        "ui_error_thunk", "ui_page_turn", "ui_book_open", "ui_book_close", "ui_map_unroll",
        "hearthstone_rest", "echo_recovered", "player_death", "bell_hand", "bell_tavern",
        "bell_tower", "bell_toll", "thunder_near", "thunder_far", "wind_gust", "water_splash",
        "wood_creak", "cart_wheels",
    ]
    missing = [n for n in needed if n not in gen_sfx.CATALOGUE]
    assert not missing, missing


def test_every_surface_has_four_footstep_variants():
    surfaces = ["vale_grass", "dirt", "stone", "wood", "water", "snow", "ash", "gravel", "mud",
                "sand"]
    for s in surfaces:
        key = "footstep_%s" % s
        assert key in gen_sfx.CATALOGUE, key
        assert gen_sfx.CATALOGUE[key]["count"] == 4, key


def test_every_spell_school_casts_and_lands():
    for school in ("kindling", "hush", "binding", "mending", "calling"):
        assert "spell_cast_%s" % school in gen_sfx.CATALOGUE
        assert "spell_impact_%s" % school in gen_sfx.CATALOGUE


def test_sfx_entries_declare_a_sane_row():
    for name, spec in gen_sfx.CATALOGUE.items():
        assert spec["count"] >= 2, name
        assert spec["bus"] in ("SFX", "UI"), name
        assert -20.0 <= spec["volume_db"] <= 6.0, name
        assert 0.0 <= spec["pitch_variance"] < 0.5, name


def test_ui_sfx_are_routed_to_the_ui_bus():
    for name, spec in gen_sfx.CATALOGUE.items():
        if name.startswith("ui_"):
            assert spec["bus"] == "UI", name


# --- what the generators actually produce ------------------------------------------------------

def _short_score(key: str, bars: int = 4) -> compose.Score:
    """One region's music cut down to a few bars, so a test can render it."""
    full = compose.region_score(key)
    s = compose.Score(full.name, full.tonic, full.mode, full.bpm, bars, full.beats_per_bar,
                      meta=dict(full.meta))
    end = bars * full.beats_per_bar
    for stem, notes in full.stems.items():
        s.stems[stem] = [compose.Note(n.beat, min(n.beats, end - n.beat), n.midi, n.vel, n.voice)
                         for n in notes if n.beat < end]
    return s


def _cfg(key: str) -> dict:
    cfg = dict(compose.REGIONS[key])
    cfg.setdefault("ostinato", "cello_short")
    cfg.setdefault("deep_voice", "drone")
    cfg.setdefault("vowel", "ah")
    cfg.setdefault("brightness", 0.5)
    cfg.setdefault("drum_hz", 72.0)
    return cfg


def test_stems_of_a_region_are_exactly_the_same_length():
    s = _short_score("hearthvale", 4)
    cfg = _cfg("hearthvale")
    lengths = set()
    for stem in ("pad", "melody", "texture", "combat", "deep"):
        y = gen_music.render_stem(s, stem, cfg, core.sub_seed("t", stem), tail=2.0)
        lengths.add(len(y))
        assert y.shape[1] == 2, "music must be stereo"
    assert len(lengths) == 1, "stems differ in length: %s" % lengths
    assert lengths.pop() == core.samples(s.seconds())


def test_an_empty_stem_is_still_the_right_length():
    s = _short_score("hearthvale", 4)
    s.stems["melody"] = []
    y = gen_music.render_stem(s, "melody", _cfg("hearthvale"), 1, tail=2.0)
    assert len(y) == core.samples(s.seconds())
    assert core.peak(y) == 0.0


def test_a_folded_music_loop_matches_what_repeating_it_would_sound_like():
    """The real test of a seamless loop: render the same bars three times in a row and compare
    the middle repeat against the single folded loop. They must be the same audio."""
    s = _short_score("sedgemire", 4)
    cfg = _cfg("sedgemire")
    stem = "pad"
    single = gen_music.render_stem(s, stem, cfg, core.sub_seed("h", stem), loop=True, tail=6.0)
    tri = compose.Score(s.name, s.tonic, s.mode, s.bpm, s.bars * 3, s.beats_per_bar)
    tri.stems[stem] = [compose.Note(n.beat + k * s.total_beats(), n.beats, n.midi, n.vel, n.voice)
                       for k in range(3) for n in s.notes(stem)]
    long = gen_music.render_stem(tri, stem, cfg, core.sub_seed("h", stem), loop=False, tail=6.0,
                                 seed_period_beats=s.total_beats())
    n = len(single)
    mid = long[n:2 * n]
    err = core.rms(single - mid) / (core.rms(mid) + 1e-12)
    assert err < 0.08, "folded loop differs from a true repeat by %.1f%%" % (err * 100)


def test_music_renders_are_deterministic():
    s = _short_score("skerrow", 2)
    cfg = _cfg("skerrow")
    a = gen_music.render_stem(s, "texture", cfg, 42, tail=1.0)
    b = gen_music.render_stem(s, "texture", cfg, 42, tail=1.0)
    assert np.array_equal(a, b)


def test_a_note_seeded_by_position_sounds_the_same_in_a_later_bar():
    """Per-note randomness must depend on where a note sits musically, not on its index, or the
    same bar renders differently depending on what came before it.

    Rendered dry: with reverb on, the earlier note's tail reaches into the compared window and
    the two renders differ for a reason that has nothing to do with seeding."""
    cfg = dict(_cfg("hearthvale"), reverb_mix=0.0)
    one = compose.Score("a", 62, "lydian", 80.0, 1)
    one.stems["melody"] = [compose.Note(0.0, 1.0, 74, 0.8, "lead")]
    two = compose.Score("b", 62, "lydian", 80.0, 2)
    two.stems["melody"] = [compose.Note(0.0, 1.0, 69, 0.8, "lead"),
                           compose.Note(4.0, 1.0, 74, 0.8, "lead")]
    a = gen_music.render_stem(one, "melody", cfg, 7, loop=False, tail=1.0)
    b = gen_music.render_stem(two, "melody", cfg, 7, loop=False, tail=1.0,
                              seed_period_beats=4.0)
    # the note at beat 4 of `two` is beat 0 of the next period, so it must match `one`'s note
    offset = core.samples(4.0 * 60.0 / 80.0)
    k = min(len(a), len(b) - offset)
    assert core.rms(a[:k] - b[offset:offset + k]) < 1e-9


def test_ambience_beds_loop_seamlessly():
    """A continuous bed must not step at the wrap, and its seam must not stand out from the
    movement the material makes anyway."""
    for name in ("wind_soft", "water_still", "silence_bed"):
        y = gen_ambience.render_bed(name, gen_ambience.CATALOGUE[name], seconds=6.0)
        assert y.shape[1] == 2, "%s must be stereo" % name
        r = render.seam_report(y)
        assert r["seam_click_db"] < 6.0, "%s steps at the wrap (%.1f dB)" % (name, r["seam_click_db"])
        assert r["excess_db"] < 2.0, "%s seam stands out by %.1f dB" % (name, r["excess_db"])


def test_ambience_beds_are_quiet_enough_to_sit_under_everything():
    y = gen_ambience.render_bed("wind_soft", gen_ambience.CATALOGUE["wind_soft"], seconds=6.0)
    assert render.loudness_lufs(y) < -24.0
    assert core.lin_to_db(core.peak(y)) < -2.0


def test_ambience_one_shots_start_and_end_in_silence():
    for name in ("skylark", "owl", "buoy_bell", "creak"):
        spec = gen_ambience.CATALOGUE[name]
        assert spec["kind"] == "pool", name
        variants = gen_ambience.render_pool(name, dict(spec, count=2))
        for i, y in enumerate(variants):
            assert y.ndim == 1, "%s must be mono" % name
            assert core.peak(y) > 0.02, "%s variant %d is inaudible" % (name, i)
            assert abs(y[0]) < 0.01 and abs(y[-1]) < 0.01, "%s variant %d clicks" % (name, i)
            assert np.all(np.isfinite(y)), name


def test_ambience_variants_differ_from_each_other():
    variants = gen_ambience.render_pool("skylark", dict(gen_ambience.CATALOGUE["skylark"], count=3))
    for i in range(len(variants)):
        for j in range(i + 1, len(variants)):
            a, b = variants[i], variants[j]
            k = min(len(a), len(b))
            assert core.rms(a[:k] - b[:k]) > 1e-4, "variants %d and %d are the same" % (i, j)


def test_sfx_are_mono_short_and_clean():
    for name in ("footstep_stone", "sword_swing_light", "impact_metal", "ui_brass_click",
                 "spell_cast_kindling"):
        spec = gen_sfx.CATALOGUE[name]
        rng = core.rng(core.sub_seed("sfx", name, 0))
        y = gen_sfx.finish_variant(spec["fn"](rng, **spec.get("kw", {})))
        assert y.ndim == 1, name
        assert np.all(np.isfinite(y)), name
        assert 0.02 < len(y) / SR < 25.0, "%s is %.2f s" % (name, len(y) / SR)
        assert abs(y[0]) < 0.02 and abs(y[-1]) < 0.02, "%s clicks at an edge" % name
        assert -4.0 < core.lin_to_db(core.peak(y)) < -2.0, "%s is not peak-normalised" % name


def test_every_sfx_starts_and_ends_at_zero():
    """A one-shot that starts or stops mid-waveform clicks every time it is played. The audit's
    bar (-40 dBFS) applied to every id in the catalogue, not a sample of five; the chest's latch,
    struck on sample 0, started at -26 dBFS until finish_variant opened every sound from zero."""
    bar = core.db_to_lin(-40.0)
    for name, spec in gen_sfx.CATALOGUE.items():
        rng = core.rng(core.sub_seed("sfx", name, 0))
        y = gen_sfx.finish_variant(spec["fn"](rng, **spec.get("kw", {})))
        assert abs(y[0]) < bar and abs(y[-1]) < bar, \
            "%s starts at %.0f and ends at %.0f dBFS" % (name, core.lin_to_db(abs(y[0]) + 1e-12),
                                                         core.lin_to_db(abs(y[-1]) + 1e-12))


def test_an_encoded_sfx_still_starts_at_zero():
    """The file is what the game plays, and the Vorbis round trip rings ahead of a transient:
    rendered from zero, these decoded at -26 to -36 dBFS on their first sample until every
    one-shot was set in 4 ms of silence."""
    import tempfile
    import report
    bar = core.db_to_lin(-40.0)
    with tempfile.TemporaryDirectory() as d:
        for name in ("chest_open", "lockpick_click", "impact_metal", "footstep_stone", "ui_brass_click"):
            spec = gen_sfx.CATALOGUE[name]
            rng = core.rng(core.sub_seed("sfx", name, 0))
            y = gen_sfx.finish_variant(spec["fn"](rng, **spec.get("kw", {})))
            p = os.path.join(d, name + ".ogg")
            render.write_ogg(p, y, quality=gen_sfx.OGG_QUALITY)
            back, _ = report.load_audio(p)
            back = core.to_mono(back)
            assert abs(back[0]) < bar and abs(back[-1]) < bar, "%s decodes starting at %.0f dBFS" % (
                name, core.lin_to_db(abs(back[0]) + 1e-12))


def test_the_variants_of_an_effect_are_the_same_loudness():
    """Four of the ids had a variant more than 4 LU from its siblings (a water step 4.2 LU over,
    a spell cast 4.9 under); match_variants holds them to 3 LU where the peak allows."""
    import audit
    for name in ("footstep_water", "footstep_ash", "door_wood_open", "spell_cast_binding"):
        spec = gen_sfx.CATALOGUE[name]
        ys = [gen_sfx.finish_variant(spec["fn"](core.rng(core.sub_seed("sfx", name, i)), **spec.get("kw", {})))
              for i in range(spec["count"])]
        levels = [render.momentary_max_lufs(y) for y in gen_sfx.match_variants(ys)]
        med = float(np.median(levels))
        assert max(abs(v - med) for v in levels) <= audit.VARIANT_SPREAD_LU, "%s: %s" % (name, levels)
        assert all(core.lin_to_db(core.peak(y)) < -1.0 for y in gen_sfx.match_variants(ys)), name


def test_effects_and_pool_shots_start_when_they_are_played():
    """Coins that land 100 ms after the purchase, a thunder that begins a second after it was
    fired: the lead-in below -60 dB of the peak is trimmed off both kinds of one-shot."""
    import audit
    for name in ("coins_few", "thunder_far"):
        spec = gen_sfx.CATALOGUE[name]
        for i in range(spec["count"]):
            y = gen_sfx.finish_variant(spec["fn"](core.rng(core.sub_seed("sfx", name, i)), **spec.get("kw", {})))
            assert audit.leading_silence_s(y) <= audit.LATE_START_S, "%s %d starts %.0f ms in" % (
                name, i, audit.leading_silence_s(y) * 1000.0)
    for i, y in enumerate(gen_ambience.render_pool("thunder_far", gen_ambience.CATALOGUE["thunder_far"])):
        assert audit.leading_silence_s(y) <= audit.LATE_START_S, "pool thunder %d starts %.0f ms in" % (
            i, audit.leading_silence_s(y) * 1000.0)


def test_the_sparse_beds_never_fall_to_digital_silence():
    import audit
    for name in ("rope_creak", "chain_clink"):
        y = gen_ambience.render_bed(name, gen_ambience.CATALOGUE[name], seconds=16.0)
        dead = [r for r in audit.dead_runs_s(y) if r[1] > audit.DEAD_BED_S]
        assert not dead, "%s is silent for %s" % (name, dead)


def test_the_frogs_never_fall_to_digital_silence():
    """A bed is the world's floor; a bed at -inf between frogs is the world switching off."""
    import audit
    y = gen_ambience.render_bed("frogs", gen_ambience.CATALOGUE["frogs"], seconds=12.0)
    dead = [r for r in audit.dead_runs_s(y) if r[1] > audit.DEAD_BED_S]
    assert not dead, "silent for %s" % dead


def test_footsteps_of_different_surfaces_sound_different():
    """The whole point of ten surfaces is that a player can hear which one they are on."""
    from scipy import signal as sg

    def centroid(y):
        f, p = sg.welch(y, SR, nperseg=min(1024, len(y)))
        return float(np.sum(f * p) / (np.sum(p) + 1e-18))

    marks = {}
    for s in ("stone", "mud", "snow", "water", "wood"):
        rng = core.rng(core.sub_seed("sfx", "footstep_%s" % s, 0))
        marks[s] = centroid(gen_sfx.footstep(rng, s))
    assert marks["mud"] < marks["stone"], "mud must be duller than stone"
    assert marks["snow"] > marks["mud"], "snow must be brighter than mud"
    assert len(set(round(v / 100) for v in marks.values())) >= 4, \
        "surfaces are not distinct enough: %s" % marks


def test_sfx_variants_of_one_id_differ():
    spec = gen_sfx.CATALOGUE["footstep_gravel"]
    ys = []
    for i in range(3):
        rng = core.rng(core.sub_seed("sfx", "footstep_gravel", i))
        ys.append(core.to_mono(spec["fn"](rng)))
    for i in range(len(ys)):
        for j in range(i + 1, len(ys)):
            k = min(len(ys[i]), len(ys[j]))
            assert core.rms(ys[i][:k] - ys[j][:k]) > 1e-4, "variants %d and %d match" % (i, j)


def test_impacts_are_punchy():
    """An impact must be a transient, not a swell: most of its energy in the first fifty
    milliseconds, and a high crest factor."""
    for name in ("impact_flesh", "impact_stone", "impact_wood"):
        rng = core.rng(core.sub_seed("sfx", name, 0))
        y = core.to_mono(gen_sfx.CATALOGUE[name]["fn"](rng))
        head = core.rms(y[:core.samples(0.05)])
        rest = core.rms(y[core.samples(0.05):]) + 1e-12
        assert head > rest, "%s does not lead with its attack" % name
        crest = core.lin_to_db(core.peak(y)) - core.lin_to_db(core.rms(y))
        assert crest > 8.0, "%s crest is only %.1f dB" % (name, crest)


def test_the_trim_keeps_the_sound_and_drops_the_silence():
    y = np.concatenate([np.zeros(100), core.rng(1).standard_normal(4410) * 0.5,
                        np.zeros(SR * 3)])
    out = gen_sfx._trim_silence(y)
    assert len(out) < len(y) / 2, "the silent tail was not trimmed"
    assert core.peak(out) > 0.1, "the sound itself was trimmed away"


def test_generator_output_paths_stay_inside_the_project():
    for path in (gen_music.AUDIO_DIR, gen_ambience.OUT_ROOT, gen_sfx.OUT_ROOT,
                 gen_music.PACK_DIR, gen_sfx.PACK_DIR):
        assert os.path.abspath(path).startswith(os.path.join(ROOT, "game")), path
