"""Tests for tools/audio/audit.py: each check catches the fault it names, on a signal built to
have it, and leaves a signal without it alone.

Run: python3 tools/audio/tests/run_tests.py --filter audit
"""
from __future__ import annotations

import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import audit  # noqa: E402
from synth import core, osc  # noqa: E402

SR = core.SR


def _sine(seconds: float, hz: float = 440.0, amp: float = 0.5) -> np.ndarray:
    t = np.arange(int(seconds * SR)) / SR
    return amp * np.sin(2.0 * np.pi * hz * t)


def _one_shot(seconds: float = 0.4, amp: float = 0.5) -> np.ndarray:
    """A decaying tone that starts and ends at zero, as a one-shot should."""
    y = _sine(seconds, 660.0, amp) * np.exp(-np.arange(int(seconds * SR)) / (0.08 * SR))
    return core.fade(y, 0.002, 0.02)


def _row(x: np.ndarray, rel: str, loop: bool, category: str = "test") -> dict:
    from synth import render
    info = render.analyse(x)
    info.update({"file": rel, "category": category, "loop": loop,
                 "clipped": audit.clipped_samples(x),
                 "leading_silence_s": audit.leading_silence_s(x),
                 "dead_runs": audit.dead_runs_s(x)})
    info["first_db"], info["last_db"] = audit.edge_levels_db(x)
    if loop:
        info["seam_click_db"] = render.seam_click_db(x)
        info.update({"seam_" + k: v for k, v in audit.seam_break(x).items()})
    return info


def test_a_clipped_sine_is_flagged_and_a_clean_one_is_not():
    hot = np.clip(_sine(0.5, amp=1.4), -1.0, 1.0)
    clean = _sine(0.5, amp=0.5)
    assert audit.clipped_samples(hot) > 100
    assert audit.clipped_samples(clean) == 0
    rows = [_row(core.fade(hot, 0.002, 0.02), "a.ogg", False), _row(core.fade(clean, 0.002, 0.02), "b.ogg", False)]
    audit.flag(rows)
    assert any(f.startswith("clipped") for f in rows[0]["flags"])
    assert not any(f.startswith("clipped") for f in rows[1]["flags"])


def test_a_dc_offset_is_flagged():
    y = _one_shot() + 0.01
    r = _row(y, "a.ogg", False)
    audit.flag([r])
    assert any("DC offset" in f for f in r["flags"])


def test_a_one_shot_that_starts_late_or_hot_is_flagged():
    late = np.concatenate([np.zeros(int(0.1 * SR)), _one_shot()])
    hot = _sine(0.3, amp=0.5)            # starts at a zero crossing but ends mid-cycle
    hot = hot[int(0.0003 * SR):]         # and now starts mid-cycle too
    good = _one_shot()
    rows = [_row(late, "late.ogg", False), _row(hot, "hot.ogg", False), _row(good, "good.ogg", False)]
    audit.flag(rows)
    assert any("late" in f for f in rows[0]["flags"]), rows[0]["flags"]
    assert any("starts hot" in f for f in rows[1]["flags"]), rows[1]["flags"]
    assert any("ends hot" in f for f in rows[1]["flags"]), rows[1]["flags"]
    assert rows[2]["flags"] == [], rows[2]["flags"]


def test_a_bed_that_drops_to_digital_silence_is_flagged():
    rng = core.rng("audit")
    bed = osc.noise("pink", int(4.0 * SR), rng) * 0.05
    gappy = bed.copy()
    gappy[int(1.0 * SR):int(1.6 * SR)] = 0.0
    rows = [_row(gappy, "gappy.ogg", True, "ambience: bed"), _row(bed, "bed.ogg", True, "ambience: bed"),
            _row(gappy, "melody.ogg", True, "music: melody stem")]
    audit.flag(rows)
    assert any("digital silence" in f for f in rows[0]["flags"]), rows[0]["flags"]
    assert not any("digital silence" in f for f in rows[1]["flags"]), rows[1]["flags"]
    # a stem rests while the others play: the same gap in a melody stem is not a fault
    assert not any("digital silence" in f for f in rows[2]["flags"]), rows[2]["flags"]


def test_silence_running_off_the_end_joins_the_silence_at_the_start():
    rng = core.rng("wrap")
    bed = osc.noise("pink", int(3.0 * SR), rng) * 0.05
    bed[:int(0.15 * SR)] = 0.0
    bed[-int(0.15 * SR):] = 0.0
    runs = audit.dead_runs_s(bed)
    assert len(runs) == 1 and abs(runs[0][1] - 0.30) < 0.02, runs


def test_a_click_at_the_wrap_is_flagged_and_a_continuous_loop_is_not():
    loop = _sine(2.0, 220.0, 0.4)        # a whole number of cycles: continuous at the wrap
    clicky = loop.copy()
    clicky[-1] = 0.9
    rows = [_row(clicky, "clicky.ogg", True), _row(loop, "loop.ogg", True)]
    audit.flag(rows)
    assert any("clicks at the wrap" in f for f in rows[0]["flags"]), rows[0]["flags"]
    assert not any("clicks" in f for f in rows[1]["flags"]), rows[1]["flags"]


def test_a_sustain_cut_at_the_loop_point_is_a_break_and_a_downbeat_is_not():
    # A drone that dies away over its last half second and starts again at full level.
    n = int(6.0 * SR)
    drone = _sine(6.0, 110.0, 0.3)
    drone[-int(0.5 * SR):] *= np.linspace(1.0, 0.001, int(0.5 * SR))
    b = audit.seam_break(drone)
    assert b["wrap_db"] > 20.0 and b["excess_db"] > audit.SEAM_BREAK_MARGIN_DB, b
    # A bar of four struck notes: every bar starts loud after a quiet tail, the wrap too.
    beat = int(0.5 * SR)
    bars = np.zeros(n)
    for k in range(0, n, beat):
        m = min(beat, n - k)
        bars[k:k + m] = _sine(m / SR, 330.0, 0.4) * np.exp(-np.arange(m) / (0.05 * SR))
    b2 = audit.seam_break(bars)
    assert b2["excess_db"] <= audit.SEAM_BREAK_MARGIN_DB, b2


def test_a_file_far_from_its_category_is_flagged():
    rows = []
    for i in range(5):
        r = _row(_one_shot(amp=0.5), "f%d.ogg" % i, False, "sfx: test")
        r["effective_lufs"] = -24.0 + i * 0.5
        rows.append(r)
    quiet = _row(_one_shot(amp=0.5), "quiet.ogg", False, "sfx: test")
    quiet["effective_lufs"] = -34.0
    rows.append(quiet)
    audit.flag(rows)
    assert any("below its category" in f for f in quiet["flags"]), quiet["flags"]
    assert all(r["flags"] == [] for r in rows[:5]), [r["flags"] for r in rows[:5]]


def test_a_loud_variant_is_flagged_against_its_siblings_and_a_quiet_id_only_when_far_out():
    rows = []
    for sid, levels in (("step", [-28.0, -27.5, -28.5, -21.0]), ("tick", [-36.0, -36.5]),
                        ("page", [-27.0, -26.5]), ("slide", [-28.0, -27.0]), ("clang", [-50.0, -49.5])):
        for i, v in enumerate(levels):
            r = _row(_one_shot(), "%s_%d.ogg" % (sid, i), False, "sfx: test")
            r["sfx_id"] = sid
            r["effective_lufs"] = v
            rows.append(r)
    audit.flag(rows)
    loud = [r for r in rows if r["file"] == "step_3.ogg"][0]
    assert any("other variants of step" in f for f in loud["flags"]), loud["flags"]
    assert all(not any("variants" in f for f in r["flags"]) for r in rows if r["file"] != "step_3.ogg")
    tick = [r for r in rows if r["file"] == "tick_0.ogg"][0]
    clang = [r for r in rows if r["file"] == "clang_0.ogg"][0]
    assert not any("family" in f for f in tick["flags"]), "a quiet tick is allowed: %s" % tick["flags"]
    assert any("family" in f for f in clang["flags"]), "22 LU under the family is a mistake: %s" % clang["flags"]


def test_momentary_loudness_reads_a_short_click_by_its_loudest_moment():
    click = _one_shot(0.09, 0.5)
    long_quiet = np.concatenate([click, np.zeros(int(2.0 * SR))])
    # integrated loudness drops as silence is added; the loudest 400 ms does not
    a = audit.momentary_max_lufs(click)
    b = audit.momentary_max_lufs(long_quiet)
    assert abs(a - b) < 0.5, (a, b)


def test_every_file_is_given_a_category_and_one_shots_a_family():
    loops = {"ambience/wind_soft/wind_soft.ogg"}
    assert audit.category_of("music/hearthvale/pad.ogg", loops) == "music: pad stem"
    assert audit.category_of("music/stingers/death.ogg", loops) == "music: stinger"
    assert audit.category_of("ambience/wind_soft/wind_soft.ogg", loops) == "ambience: bed"
    assert audit.category_of("ambience/owl/owl_01.ogg", loops) == "ambience: one-shot"
    assert audit.category_of("sfx/footstep_mud/footstep_mud_01.ogg", loops) == "sfx: footsteps"
    assert audit.category_of("sfx/chest_open/chest_open_01.ogg", loops) == "sfx: handling"
    assert audit.category_of("sfx/ui_page_turn/ui_page_turn_02.ogg", loops) == "sfx: interface"
