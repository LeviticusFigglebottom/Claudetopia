"""Tests for the synthesis toolkit: determinism, levels, filters, envelopes, loop seams.

Run: python3 -m pytest tools/audio/tests -q   (or  python3 tools/audio/tests/run_tests.py)
"""
from __future__ import annotations

import os
import subprocess
import sys
import tempfile

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from synth import core, env, filters, fx, instruments as inst, osc, render, theory  # noqa: E402

SR = core.SR


# --- determinism -----------------------------------------------------------------------------

def test_rng_is_deterministic_from_int_and_string():
    a = core.rng(1234).standard_normal(50)
    b = core.rng(1234).standard_normal(50)
    assert np.array_equal(a, b)
    c = core.rng("hearthvale").standard_normal(50)
    d = core.rng("hearthvale").standard_normal(50)
    assert np.array_equal(c, d)
    assert not np.array_equal(a, c)


def test_sub_seed_is_stable_and_distinct():
    assert core.sub_seed(7, "music", "pad") == core.sub_seed(7, "music", "pad")
    assert core.sub_seed(7, "music", "pad") != core.sub_seed(7, "music", "melody")
    assert core.sub_seed(7, "music") != core.sub_seed(8, "music")


def test_instruments_are_deterministic():
    for make in (
        lambda r: inst.bell(67, 2.0, rng=r),
        lambda r: inst.pluck(57, 1.0, rng=r),
        lambda r: inst.flute(72, 1.0, rng=r),
        lambda r: inst.choir([60, 64], 1.5, rng=r),
        lambda r: inst.membrane(90, 0.5, rng=r),
    ):
        a = make(core.rng(99))
        b = make(core.rng(99))
        assert np.array_equal(a, b)


# --- levels and sanity -------------------------------------------------------------------------

ALL_VOICES = {
    "bell": lambda r: inst.bell(67, 3.0, rng=r),
    "toll_bell": lambda r: inst.toll_bell(31, 4.0, rng=r),
    "hand_bell": lambda r: inst.hand_bell(84, 1.5, rng=r),
    "bell_fm": lambda r: inst.bell_fm(72, 1.5),
    "pluck": lambda r: inst.pluck(57, 2.0, rng=r),
    "harp": lambda r: inst.harp([57, 60, 64], 2.0, rng=r),
    "bowed": lambda r: inst.bowed(50, 1.5, rng=r),
    "cello_section": lambda r: inst.cello_section([43, 50], 1.5, rng=r),
    "flute": lambda r: inst.flute(74, 1.5, rng=r),
    "whistle": lambda r: inst.whistle(79, 1.0, rng=r),
    "pipes": lambda r: inst.pipes(62, 1.5, rng=r),
    "drone": lambda r: inst.drone(38, 2.0, rng=r),
    "choir": lambda r: inst.choir([55, 62, 67], 2.0, rng=r),
    "hum": lambda r: inst.hum(45, 3.0, rng=r),
    "pad": lambda r: inst.pad([48, 55, 60], 3.0, rng=r),
    "glass_pad": lambda r: inst.glass_pad([60, 67], 2.0, rng=r),
    "membrane": lambda r: inst.membrane(90, 0.6, rng=r),
    "frame_drum": lambda r: inst.frame_drum(rng=r),
    "war_drum": lambda r: inst.war_drum(rng=r),
    "wood_block": lambda r: inst.wood_block(rng=r),
    "shaker": lambda r: inst.shaker(rng=r),
    "tambour_roll": lambda r: inst.tambour_roll(1.0, rng=r),
    "cymbal_swell": lambda r: inst.cymbal_swell(1.0, rng=r),
}


def test_every_voice_is_finite_audible_and_unclipped():
    for name, make in ALL_VOICES.items():
        y = make(core.rng(name))
        assert len(y) > 0, name
        assert np.all(np.isfinite(y)), "%s produced NaN/inf" % name
        assert core.peak(y) <= 1.0, "%s clips at %.3f" % (name, core.peak(y))
        assert core.peak(y) > 0.01, "%s is inaudible (peak %.5f)" % (name, core.peak(y))
        assert abs(np.mean(y)) < 0.02, "%s has DC offset %.4f" % (name, np.mean(y))


def _start_step_ratio(y: np.ndarray) -> float:
    """How far the first sample jumps away from silence, against the biggest step the waveform
    takes just afterwards. A waveform that simply starts moving scores about 1; one that is
    switched on at full amplitude scores many times that."""
    ref = float(np.max(np.abs(np.diff(y[:400])))) + 1e-12
    return float(abs(y[0]) / ref)


def test_no_voice_starts_with_a_step():
    """A voice whose first sample jumps away from zero clicks every time it is triggered.
    (The bell did exactly this: its partials started at random phase under a full envelope.)"""
    for name, make in ALL_VOICES.items():
        r = _start_step_ratio(make(core.rng(name)))
        assert r < 1.5, "%s starts with a step %.1fx its own slew" % (name, r)


def test_start_step_guard_catches_a_switched_on_tone():
    clicky = osc.sine(200.0, SR // 2, phase0=0.25)  # starts at full amplitude
    assert _start_step_ratio(clicky) > 5.0


def test_voices_decay_to_silence():
    """A struck voice must end near zero so one-shots do not click when they stop."""
    for name in ("bell", "hand_bell", "pluck", "membrane", "wood_block"):
        y = ALL_VOICES[name](core.rng(name))
        tail = core.rms(y[-int(0.02 * SR):])
        assert tail < core.rms(y) * 0.5, "%s does not decay (tail %.5f)" % (name, tail)


def test_pluck_decay_time_follows_request():
    """The Karplus-Strong loop gain is per round trip, so a longer request must ring longer."""
    def measured(y):
        w = 1102
        e = np.array([core.rms(y[i * w:(i + 1) * w]) for i in range(len(y) // w)])
        pk = e[:8].max()
        below = np.flatnonzero(e < pk / 1000.0)
        return (below[0] if len(below) else len(e)) * w / SR

    short = measured(inst.pluck(45, 8.0, decay=0.5))
    long = measured(inst.pluck(45, 8.0, decay=4.0))
    assert short < long, "decay parameter has no effect"
    assert 0.2 < short < 1.0, "short pluck rang for %.2f s" % short
    assert 2.0 < long < 5.0, "long pluck rang for %.2f s" % long


def test_bell_hum_outlasts_the_strike():
    """A bell's low hum partial must still be ringing when the bright partials have gone."""
    y = inst.bell(60, 8.0, t60=8.0, rng=core.rng(5))
    early, late = y[:SR // 2], y[int(6.0 * SR):int(6.5 * SR)]
    f_e, p_e = _spectrum(early)
    f_l, p_l = _spectrum(late)
    centroid_e = float(np.sum(f_e * p_e) / np.sum(p_e))
    centroid_l = float(np.sum(f_l * p_l) / np.sum(p_l))
    assert centroid_l < centroid_e * 0.8, "bell did not darken as it decayed (%.0f -> %.0f Hz)" % (
        centroid_e, centroid_l)
    assert core.rms(late) > 0.0, "bell fell silent too early"


def _spectrum(x):
    from scipy import signal as sg
    f, p = sg.welch(x, SR, nperseg=min(4096, len(x)))
    return f, p + 1e-18


# --- oscillators -------------------------------------------------------------------------------

def test_band_limited_oscillators_have_little_aliasing():
    """A naive saw at 3 kHz folds energy below the fundamental; PolyBLEP must not."""
    n = SR
    y = osc.saw(3000.0, n)
    f, p = _spectrum(y)
    below = p[(f > 100) & (f < 2500)].sum()
    at = p[(f > 2800) & (f < 3200)].sum()
    assert below / at < 0.05, "aliasing below the fundamental: %.3f" % (below / at)


def test_oscillator_ranges_and_frequency():
    for name, fn in (("sine", osc.sine), ("saw", osc.saw), ("square", lambda f, n: osc.square(f, n)),
                     ("triangle", osc.triangle)):
        y = fn(220.0, SR // 2)
        assert core.peak(y) <= 1.1, "%s peaks at %.3f" % (name, core.peak(y))
        assert core.rms(y) > 0.1, name
        assert abs(np.mean(y)) < 0.01, "%s has DC offset %.4f" % (name, np.mean(y))
    # zero crossings of a sine track its frequency
    y = osc.sine(200.0, SR)
    crossings = np.sum(np.diff(np.signbit(y)) != 0)
    assert abs(crossings - 400) <= 2, crossings


def test_frequency_can_vary_per_sample():
    n = SR
    sweep = np.linspace(100.0, 1000.0, n)
    y = osc.saw(sweep, n)
    assert np.all(np.isfinite(y))
    f_a, p_a = _spectrum(y[:n // 4])
    f_b, p_b = _spectrum(y[-n // 4:])
    assert float(f_b[np.argmax(p_b)]) > float(f_a[np.argmax(p_a)])


def test_noise_colours_have_the_right_tilt():
    n = SR
    r = core.rng(3)
    lows, highs = {}, {}
    for kind in ("brown", "pink", "white", "blue"):
        f, p = _spectrum(osc.noise(kind, n, r))
        lows[kind] = p[(f > 50) & (f < 200)].mean()
        highs[kind] = p[(f > 4000) & (f < 10000)].mean()
    tilt = {k: lows[k] / highs[k] for k in lows}
    assert tilt["brown"] > tilt["pink"] > tilt["white"] > tilt["blue"], tilt


# --- envelopes ---------------------------------------------------------------------------------

def test_adsr_shape_and_bounds():
    e = env.adsr(1.0, a=0.1, d=0.2, s=0.5, r=0.3)
    assert len(e) == core.samples(1.3)
    assert e[0] < 0.1 and e[-1] < 0.02
    assert abs(e[core.samples(0.1)] - 1.0) < 0.15, e[core.samples(0.1)]
    assert abs(e[core.samples(0.8)] - 0.5) < 0.05
    assert np.all(e >= -1e-9) and np.all(e <= 1.0 + 1e-9)


def test_adsr_total_length_is_respected():
    e = env.adsr(1.0, a=0.05, d=0.1, s=0.6, r=0.4, total=2.0)
    assert len(e) == core.samples(2.0)
    assert e[-1] < 0.02


def test_expdecay_hits_minus_60db():
    e = env.expdecay(core.samples(2.0), 1.0)
    assert abs(core.lin_to_db(e[core.samples(1.0)]) + 60.0) < 1.0


def test_wander_is_bounded_and_smooth():
    w = env.wander(SR, core.rng(1), 0.5, 1.0)
    assert np.max(np.abs(w)) <= 1.0001
    assert np.max(np.abs(np.diff(w))) < 0.02, "wander jumps"


# --- filters -----------------------------------------------------------------------------------

def test_lowpass_and_highpass_attenuate_the_right_side():
    r = core.rng(2)
    n = SR
    w = osc.white(n, r)
    lo = filters.lowpass(w, 500.0)
    hi = filters.highpass(w, 500.0)
    f, p_lo = _spectrum(lo)
    _, p_hi = _spectrum(hi)
    band_lo = (f > 100) & (f < 300)
    band_hi = (f > 3000) & (f < 8000)
    assert p_lo[band_lo].mean() > p_lo[band_hi].mean() * 50
    assert p_hi[band_hi].mean() > p_hi[band_lo].mean() * 20


def test_bandpass_peaks_at_its_centre():
    r = core.rng(4)
    y = filters.bandpass(osc.white(SR, r), 1000.0, 4.0)
    f, p = _spectrum(y)
    assert 700 < float(f[np.argmax(p)]) < 1400


def test_svf_tracks_a_moving_cutoff():
    n = SR
    r = core.rng(6)
    w = osc.white(n, r)
    sweep = np.linspace(200.0, 8000.0, n)
    y = filters.svf(w, sweep, 1.0, "lp")
    assert np.all(np.isfinite(y))
    f_a, p_a = _spectrum(y[:n // 4])
    f_b, p_b = _spectrum(y[-n // 4:])
    hb = (f_a > 4000) & (f_a < 9000)
    assert p_b[hb].mean() > p_a[hb].mean() * 10, "cutoff did not open"


def test_dc_block_removes_offset():
    x = np.ones(SR) * 0.5 + osc.sine(200.0, SR) * 0.2
    y = filters.dc_block(x)
    assert abs(np.mean(y[SR // 2:])) < 0.01


def test_resonator_rings_for_its_t60():
    imp = np.zeros(core.samples(2.0))
    imp[0] = 1.0
    y = filters.resonate(imp, 440.0, 1.0, norm="impulse")
    assert core.peak(y) > 0.5, "impulse-normalised resonator is too quiet"
    level = core.rms(y[core.samples(0.9):core.samples(1.0)]) / (core.rms(y[:core.samples(0.1)]) + 1e-12)
    assert 0.0002 < level < 0.02, level


def test_formant_bank_creates_vowel_peaks():
    r = core.rng(8)
    y = filters.vowel(osc.saw(110.0, SR), "ah")
    f, p = _spectrum(y)
    # energy should concentrate near F1 (700 Hz) and F2 (1150 Hz) rather than up high
    assert p[(f > 500) & (f < 1400)].mean() > p[(f > 4000) & (f < 8000)].mean() * 20


# --- effects -----------------------------------------------------------------------------------

def test_reverb_adds_a_tail_and_stays_finite():
    r = core.rng(9)
    x = np.zeros(core.samples(0.5))
    x[:100] = osc.white(100, r)
    y = fx.reverb(x, "hall", mix=0.5, seed=3)
    assert y.shape[1] == 2
    assert len(y) > len(x)
    assert np.all(np.isfinite(y))
    assert core.rms(y[core.samples(0.8):core.samples(1.2)]) > 1e-5, "no reverb tail"


def test_reverb_presets_differ_in_length():
    r = core.rng(10)
    imp = np.zeros(core.samples(1.0))
    imp[0] = 1.0
    room = fx.reverb(imp, "room", mix=1.0, seed=1)
    cath = fx.reverb(imp, "cathedral", mix=1.0, seed=1)
    def decay_len(y):
        e = np.abs(core.to_mono(y))
        thr = e.max() * 0.001
        idx = np.flatnonzero(e > thr)
        return idx[-1] / SR if len(idx) else 0.0
    assert decay_len(cath) > decay_len(room) * 1.5


def test_fdn_reverb_decays_and_is_stable():
    imp = np.zeros(core.samples(4.0))
    imp[0] = 1.0
    y = fx.fdn_reverb(imp, rt60=1.5, mix=1.0)
    assert np.all(np.isfinite(y))
    early = core.rms(y[core.samples(0.1):core.samples(0.3)])
    late = core.rms(y[core.samples(3.0):core.samples(3.5)])
    assert late < early, "FDN is not decaying (unstable feedback)"
    assert core.peak(y) < 10.0


def test_chorus_and_widen_produce_stereo_difference():
    y = fx.chorus(osc.saw(220.0, SR) * 0.3, mix=0.6)
    assert y.shape[1] == 2
    assert core.rms(y[:, 0] - y[:, 1]) > 1e-3, "chorus is mono"


def test_saturate_is_bounded_and_adds_harmonics():
    x = osc.sine(200.0, SR) * 0.9
    y = fx.saturate(x, 4.0)
    assert core.peak(y) <= 1.01
    f, p_x = _spectrum(x)
    _, p_y = _spectrum(y)
    third = (f > 550) & (f < 650)
    assert p_y[third].sum() > p_x[third].sum() * 10


def test_limiter_holds_the_ceiling():
    r = core.rng(12)
    x = core.to_stereo(osc.white(SR, r) * 3.0)
    y = fx.limiter(x, ceiling_db=-1.0)
    assert core.lin_to_db(core.peak(y)) <= -0.5


def test_compress_reduces_dynamic_range():
    r = core.rng(13)
    quiet = osc.white(SR // 2, r) * 0.05
    loud = osc.white(SR // 2, r) * 0.8
    x = np.concatenate([quiet, loud])
    y = fx.compress(x, threshold_db=-24.0, ratio=6.0)
    before = core.rms(loud) / core.rms(quiet)
    after = core.rms(y[SR // 2:]) / core.rms(y[:SR // 2])
    assert after < before


# --- render, loudness, looping --------------------------------------------------------------------

def test_wav_round_trip():
    x = core.to_stereo(osc.sine(440.0, SR) * 0.5)
    with tempfile.TemporaryDirectory() as d:
        p = render.write_wav(os.path.join(d, "t.wav"), x)
        y, sr = render.read_wav(p)
        assert sr == SR and y.shape == x.shape
        assert core.rms(y - x) < 0.001


def test_ogg_encode_round_trip():
    x = core.to_stereo(osc.sine(440.0, SR) * 0.4)
    with tempfile.TemporaryDirectory() as d:
        ogg = render.write_ogg(os.path.join(d, "t.ogg"), x, quality=5)
        assert os.path.getsize(ogg) > 1000
        back = os.path.join(d, "back.wav")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", ogg, back], check=True)
        y, sr = render.read_wav(back)
        assert sr == SR
        assert abs(len(y) - len(x)) < SR * 0.05
        assert abs(core.rms(y) - core.rms(x)) < 0.02


def test_loudness_scales_with_gain():
    r = core.rng(14)
    x = core.to_stereo(osc.pink(SR * 2, r) * 0.3)
    a = render.loudness_lufs(x)
    b = render.loudness_lufs(x * core.db_to_lin(-6.0))
    assert abs((a - b) - 6.0) < 0.3, (a, b)
    assert -40.0 < a < 0.0


def test_true_peak_catches_intersample_overs():
    x = np.tile([0.9, -0.9], SR // 2)
    assert render.true_peak_db(x) > core.lin_to_db(core.peak(x))


def test_mixdown_hits_the_peak_target():
    r = core.rng(15)
    x = core.to_stereo(osc.pink(SR, r) * 2.0)
    y = render.mixdown(x, peak_db=-1.0)
    assert -1.6 < core.lin_to_db(core.peak(y)) <= -0.9


def test_mixdown_matches_a_loudness_target():
    r = core.rng(16)
    x = core.to_stereo(osc.pink(SR * 2, r) * 0.05)
    y = render.mixdown(x, peak_db=-1.0, target_lufs=-18.0)
    assert abs(render.loudness_lufs(y) - (-18.0)) < 1.5


def test_loop_fold_reconstructs_the_steady_state():
    """Folding is for material that rings out past the loop point: strikes plus their decay.

    The test renders strikes over the loop and lets them ring on past it, folds the ring-out
    back, and checks the result matches the true steady state of the same pattern repeating
    for ever (which is what the game will actually hear once the loop has gone round twice).
    """
    period, loop_s, tail_s = 1.0, 4.0, 6.0

    def strikes(buffer_s, strike_until_s, first_k=0):
        """Bells struck every `period` up to `strike_until_s`, rendered into `buffer_s` of
        buffer so their tails keep ringing past the last strike."""
        n = core.samples(buffer_s)
        y = np.zeros(n)
        k = 0
        while k * period < strike_until_s:
            s = core.samples(k * period)
            d = inst.bell(60, 8.0, t60=3.0, rng=core.rng(1000 + (first_k + k) % 4))
            y[s:s + min(len(d), n - s)] += d[:max(n - s, 0)]
            k += 1
        return y

    # One loop's worth of strikes, rendered long enough for the tails, then folded back.
    folded = render.loop_fold(strikes(loop_s + tail_s, loop_s), loop_s)
    assert len(folded) == core.samples(loop_s)
    # The steady state: the same pattern has been repeating for several loops already, so the
    # window also carries the tails of every earlier repeat.
    pre = 12.0
    long = strikes(pre + loop_s + 8.0, pre + loop_s)[core.samples(pre):core.samples(pre + loop_s)]
    err = core.rms(folded - long) / (core.rms(long) + 1e-12)
    assert err < 0.05, "folded loop differs from the steady state by %.1f%%" % (err * 100)
    # No sample-level step at the wrap. The RMS-level measure is deliberately not asserted here:
    # this material strikes a bell on the downbeat, so the head is honestly louder than the
    # tail. That measure belongs to continuous beds (see the crossfade test).
    assert render.seam_click_db(folded) < 12.0


def test_crossfade_loop_is_seamless():
    r = core.rng(18)
    x = osc.pink(core.samples(8.0), r)
    looped = render.crossfade_loop(x, 5.0, 1.5)
    assert len(looped) == core.samples(5.0)
    assert render.seam_discontinuity_db(looped) < 1.0
    assert render.seam_click_db(looped) < 12.0


def test_seam_click_detects_a_real_discontinuity():
    """A loop cut mid-tone (start and end at different phases) must be reported as a click."""
    clean = osc.sine(440.0, core.samples(1.0))            # exactly 440 cycles: wraps perfectly
    cut = osc.sine(437.3, core.samples(1.0))              # non-integer cycles: steps at the wrap
    assert render.seam_click_db(clean) < 12.0
    assert render.seam_click_db(cut) > 20.0


def test_seam_discontinuity_detects_a_bad_loop():
    """The measure must actually fail a loop that fades out (so the game would hear a gap)."""
    r = core.rng(19)
    x = osc.pink(core.samples(4.0), r)
    faded = core.fade(x, 0.0, 1.0)
    assert render.seam_discontinuity_db(faded) > 6.0


def test_spectral_balance_bands_sum_sensibly():
    r = core.rng(20)
    b = render.spectral_balance(osc.pink(SR * 2, r))
    assert set(b) == {"20_120", "120_500", "500_2000", "2000_6000", "6000_20000"}
    assert all(-60.0 < v < 0.1 for v in b.values()), b


# --- theory -------------------------------------------------------------------------------------

def test_modes_are_seven_notes_within_an_octave():
    for name, steps in theory.MODES.items():
        assert len(steps) == 7, name
        assert steps[0] == 0 and max(steps) < 12, name
        assert steps == sorted(steps), name


def test_region_modes_all_resolve():
    for key in ("lydian_warm", "ionian_bright", "dorian_misty", "aeolian_deep",
                "mixolydian_cold", "phrygian_hollow"):
        assert theory.mode_of(key) in theory.MODES


def test_degree_to_midi_spans_octaves():
    assert theory.degree_to_midi(0, 60, "ionian") == 60
    assert theory.degree_to_midi(7, 60, "ionian") == 72
    assert theory.degree_to_midi(-1, 60, "ionian") == 59
    assert theory.degree_to_midi(4, 60, "ionian") == 67


def test_in_mode_and_snapping():
    assert theory.in_mode(64, 60, "ionian")
    assert not theory.in_mode(61, 60, "ionian")
    snapped = theory.nearest_in_mode(61, 60, "ionian")
    assert theory.in_mode(snapped, 60, "ionian")
    assert abs(snapped - 61) <= 1


def test_triads_are_diatonic():
    for d in range(7):
        for n in theory.triad(d, 62, "dorian"):
            assert theory.in_mode(n, 62, "dorian")


def test_voice_leading_moves_voices_a_little():
    prog = theory.progression([0, 5, 3, 4, 0], 60, "lydian")
    for a, b in zip(prog, prog[1:]):
        moves = [abs(x - y) for x, y in zip(sorted(a), sorted(b))]
        assert max(moves) <= 8, (a, b, moves)


def test_progression_notes_stay_in_mode():
    for mode in theory.MODES:
        for chord in theory.progression([0, 3, 4, 5], 57, mode):
            for n in chord:
                assert theory.in_mode(n, 57, mode), (mode, chord)


def test_minor_second_detection():
    assert theory.has_minor_second([60, 61])
    assert theory.has_minor_second([60, 73])
    assert not theory.has_minor_second([60, 64, 67])


def test_toll_motif_shape():
    t = theory.TOLL
    assert 4 <= len(t) <= 6, "the leitmotif must be 4-6 notes"
    assert t.degrees()[0] == 0 and t.degrees()[-1] == 0, "the Toll starts and returns to the tonic"
    assert t.duration() > 0


def test_motif_transformations_preserve_length():
    t = theory.TOLL
    assert len(t.inverse()) == len(t)
    assert len(t.retrograde()) == len(t)
    assert t.augment(2.0).duration() == t.duration() * 2
    assert abs(t.diminish(2.0).duration() - t.duration() / 2) < 1e-9
    assert t.retrograde().degrees() == list(reversed(t.degrees()))
    inv = t.inverse()
    axis = t.degrees()[0]
    assert inv.degrees() == [2 * axis - d for d in t.degrees()]


def test_motif_sequence_repeats_at_offsets():
    seq = theory.TOLL.sequence([0, 2])
    assert len(seq) == len(theory.TOLL) * 2
    assert seq.degrees()[len(theory.TOLL):] == [d + 2 for d in theory.TOLL.degrees()]


def test_motif_realisation_is_in_mode():
    for mode in ("lydian", "phrygian", "aeolian"):
        for (_, _, note, _) in theory.TOLL.to_notes(60, mode):
            assert theory.in_mode(note, 60, mode), mode


def test_motif_library_is_all_motifs():
    lib = theory.motif_library()
    assert "toll" in lib
    for name, m in lib.items():
        assert len(m) >= 3, name
        assert m.duration() > 0, name


def test_rewriting_an_import_sidecar_keeps_the_uid_godot_gave_the_file():
    """Regenerating a file used to throw away the uid, path and dest_files Godot had written, so
    every re-render gave every file a new resource uid on its next import."""
    with tempfile.TemporaryDirectory() as d:
        ogg = os.path.join(d, "x.ogg")
        render.write_ogg_import(ogg, "assets/audio/x.ogg", loop=False)
        with open(ogg + ".import") as f:
            text = f.read()
        text = text.replace('type="AudioStreamOggVorbis"\n', 'type="AudioStreamOggVorbis"\nuid="uid://abc123"\n'
                            'path="res://.godot/imported/x.ogg-0f.oggvorbisstr"\n')
        text = text.replace('source_file="res://assets/audio/x.ogg"\n', 'source_file="res://assets/audio/x.ogg"\n'
                            'dest_files=["res://.godot/imported/x.ogg-0f.oggvorbisstr"]\n')
        with open(ogg + ".import", "w") as f:
            f.write(text)
        render.write_ogg_import(ogg, "assets/audio/x.ogg", loop=True)
        with open(ogg + ".import") as f:
            again = f.read()
        assert 'uid="uid://abc123"' in again
        assert 'path="res://.godot/imported/x.ogg-0f.oggvorbisstr"' in again
        assert 'dest_files=["res://.godot/imported/x.ogg-0f.oggvorbisstr"]' in again
        assert "loop=true" in again, "the parameters are still the new ones"
