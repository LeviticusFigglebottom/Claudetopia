#!/usr/bin/env python3
"""Render Wickmere's music.

compose.py writes the notes; this renders them with the synth toolkit, folds each region loop
so it repeats seamlessly, and writes OGG stems, Godot .import sidecars and the core:music
content definitions.

    python3 tools/audio/gen_music.py                  # everything that is missing or stale
    python3 tools/audio/gen_music.py --only hearthvale --force
    python3 tools/audio/gen_music.py --list

Output: game/assets/audio/music/<region>/<stem>.ogg, .../theme/*.ogg, .../stingers/*.ogg and
game/content/packs/core/music/music.json.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import compose  # noqa: E402
from synth import core, env, filters, fx, instruments as inst, render  # noqa: E402
from synth.core import SR, midi_to_hz, samples  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
AUDIO_DIR = os.path.join(ROOT, "game", "assets", "audio", "music")
PACK_DIR = os.path.join(ROOT, "game", "content", "packs", "core", "music")

OGG_QUALITY = 4.0          # ~128 kbps VBR stereo: transparent enough for these textures
TAIL_SECONDS = 12.0        # rendered past the loop so reverb and bells can ring back round

# Loudness per stem, so the director's default volumes sum to a sane mix. A stem is quieter
# than a finished piece because three or four of them play at once.
STEM_LUFS = {
    "pad": -21.0, "melody": -20.0, "texture": -23.0, "combat": -19.0, "deep": -24.0,
}
PIECE_LUFS = {"main_theme": -17.0, "naming": -19.0, "boss_1": -17.0, "boss_2": -16.0}
STINGER_LUFS = -16.0


# =================================================================================================
# Voices: how a composed part is actually played
# =================================================================================================

def _beats_to_seconds(beats: float, bpm: float) -> float:
    return beats * 60.0 / bpm


def render_voice(voice: str, midi: int, seconds: float, vel: float, cfg: dict,
                 rng: np.random.Generator) -> np.ndarray:
    """One note, played by whichever instrument the region gives that role."""
    amp = float(np.clip(vel, 0.05, 1.0))
    inst_name = {
        "pad": cfg.get("pad_voice", "pad"),
        "bass": cfg.get("bass", "cello"),
        "lead": cfg.get("lead", "flute"),
        "counter": cfg.get("lead", "flute"),
        "arp": cfg.get("texture", "pluck"),
        "ostinato": cfg.get("ostinato", "cello_short"),
        "bell": "bell",
        "stab": "bell",
        "drone": cfg.get("deep_voice", "drone"),
        "drum": "drum",
        "choir": "choir",
    }.get(voice, "pluck")

    if inst_name == "pad":
        return inst.pad([midi], seconds, amp=0.30 * amp, rng=rng, brightness=cfg.get("brightness", 0.45),
                        attack=min(0.9, seconds * 0.35), release=min(2.4, seconds * 1.1), voices=2)
    if inst_name == "choir":
        return inst.choir([midi], seconds, amp=0.34 * amp, rng=rng, vowel=cfg.get("vowel", "oo"),
                          attack=min(0.8, seconds * 0.4), release=min(2.0, seconds * 1.0), voices=2)
    if inst_name == "glass":
        return inst.glass_pad([midi], seconds, amp=0.30 * amp, rng=rng,
                              attack=min(1.4, seconds * 0.45), release=min(3.0, seconds * 1.2))
    if inst_name == "cello":
        return inst.cello_section([midi], seconds, amp=0.34 * amp, rng=rng,
                                  attack=min(0.22, seconds * 0.3), release=min(0.6, seconds * 0.8),
                                  brightness=0.4)
    if inst_name == "cello_short":
        return inst.bowed(midi, seconds, amp=0.34 * amp, rng=rng, attack=min(0.05, seconds * 0.3),
                          release=min(0.25, seconds * 0.6), brightness=0.5, vibrato=0.15)
    if inst_name == "flute":
        return inst.flute(midi, seconds, amp=0.34 * amp, rng=rng, attack=min(0.09, seconds * 0.3),
                          release=min(0.35, seconds * 0.7))
    if inst_name == "whistle":
        return inst.whistle(midi, seconds, amp=0.30 * amp, rng=rng, attack=min(0.05, seconds * 0.25),
                            release=min(0.25, seconds * 0.6))
    if inst_name == "pipes":
        return inst.pipes(midi, seconds, amp=0.34 * amp, rng=rng, reed=0.6,
                          attack=min(0.05, seconds * 0.25), release=min(0.25, seconds * 0.6))
    if inst_name == "hum":
        return inst.hum(midi, seconds, amp=0.40 * amp, rng=rng, attack=min(1.1, seconds * 0.4),
                        release=min(2.0, seconds * 0.9))
    if inst_name == "drone":
        return inst.drone(midi, seconds, amp=0.24 * amp, rng=rng, voices=2, fifth=False)
    # A Karplus-Strong string loses its energy through the loop filter as well as the loop
    # gain, so a high note rings far shorter than the decay asked for -- correctly, but it
    # means the request has to be generous or an arpeggio leaves gaps between its notes.
    if inst_name == "harp":
        return inst.pluck(midi, seconds + 2.0, amp=0.42 * amp, rng=rng, damping=0.25,
                          brightness=0.55, decay=min(5.5, seconds + 3.0))
    if inst_name == "pluck":
        return inst.pluck(midi, seconds + 1.6, amp=0.40 * amp, rng=rng, damping=0.35,
                          brightness=0.45, decay=min(4.5, seconds + 2.5))
    if inst_name == "bell":
        ring = float(np.clip(seconds * 1.8, 1.5, 9.0))
        if midi >= 72:
            return inst.hand_bell(midi, ring, amp=0.34 * amp, rng=rng)
        return inst.bell(midi, ring, t60=ring, amp=0.30 * amp, rng=rng, warmth=0.25)
    if inst_name == "drum":
        return inst.frame_drum(seconds=max(seconds, 0.7), amp=0.55 * amp, rng=rng,
                               freq=cfg.get("drum_hz", 78.0))
    if inst_name == "war_drum":
        return inst.war_drum(seconds=max(seconds, 1.0), amp=0.6 * amp, rng=rng)
    return inst.pluck(midi, seconds + 0.5, amp=0.35 * amp, rng=rng)


# How each voice sits in the stereo picture and how far back in the reverb it is.
VOICE_PLACEMENT = {
    "pad": (0.0, 1.0, 0.55),        # (pan, gain, reverb send)
    "bass": (0.0, 1.0, 0.30),
    "lead": (-0.08, 1.0, 0.45),
    "counter": (0.35, 0.8, 0.7),
    "arp": (0.28, 0.9, 0.5),
    "ostinato": (-0.1, 1.0, 0.3),
    "bell": (-0.3, 1.0, 0.9),
    "stab": (0.4, 0.85, 0.7),
    "drone": (0.0, 1.0, 0.6),
    "drum": (0.0, 1.0, 0.25),
    "choir": (0.0, 0.9, 0.85),
}


# A held note that lands on the loop point needs no special handling: it is rendered with its
# release, the release runs on into the tail, and loop_fold brings it back over the head where
# the same note is attacking again. Extending such notes past the loop instead was tried and
# made the seam worse, because a note still at full sustain folded onto its own restart doubles
# the level rather than cross-fading with it.


def render_stem(score: compose.Score, stem: str, cfg: dict, seed, loop: bool = True,
                tail: float = TAIL_SECONDS, seed_period_beats: float | None = None) -> np.ndarray:
    """Render one stem to stereo, reverberate it, and fold the ring-out back if it loops.

    Each note's random detail (bow noise, breath, bell detuning) is seeded from where the note
    sits musically rather than from its position in the list, so the same bar always sounds the
    same. `seed_period_beats` folds that position into one loop's length, which is what lets a
    render of several consecutive loops be compared against a single folded one.
    """
    notes = score.notes(stem)
    if not notes:
        return np.zeros((samples(score.seconds()), 2))
    loop_s = score.seconds()
    total = loop_s + tail
    n = samples(total)
    dry = np.zeros((n, 2))
    send = np.zeros((n, 2))
    rng = core.rng(core.sub_seed(seed, stem))
    period = seed_period_beats or score.total_beats()
    seen: dict = {}
    for note in notes:
        start = samples(_beats_to_seconds(note.beat, score.bpm))
        dur = _beats_to_seconds(note.beats, score.bpm)
        key = (round(note.beat % period, 4), note.midi, note.voice)
        # Two notes really can share a position, pitch and voice (a doubled unison), so they are
        # counted apart -- but only within their own repeat, or the same bar of the next time
        # round the loop would be given a different seed and sound different.
        ckey = (int(note.beat // period),) + key
        seen[ckey] = seen.get(ckey, -1) + 1
        nr = core.rng(core.sub_seed(seed, stem, key[0], key[1], key[2], seen[ckey]))
        y = render_voice(note.voice, note.midi, dur, note.vel, cfg, nr)
        if not len(y):
            continue
        pan, gain, rev = VOICE_PLACEMENT.get(note.voice, (0.0, 1.0, 0.5))
        # a little per-note stereo movement so repeated figures do not sit in one spot; taken
        # from the note's own generator so it too depends on musical position, not list order
        pan = float(np.clip(pan + nr.normal(0.0, 0.06), -0.95, 0.95))
        st = core.pan(y, pan) * gain
        core.mix_into(dry, st, start, 1.0 - rev * 0.35)
        core.mix_into(send, st, start, rev)
    wet = fx.reverb(send, cfg.get("reverb", "hall"), mix=1.0,
                    seed=core.sub_seed(seed, "ir") % (2 ** 31), tail=True)
    out = dry.copy()
    core.mix_into(out, wet[:n], 0, cfg.get("reverb_mix", 0.25) * 2.0)
    # The rumble filter waits for mixdown, which runs it circularly for a loop. Run here, its
    # start-up transient would land on sample 0 of the head and step against the folded tail.
    if loop:
        out = render.loop_fold(out, loop_s)
    else:
        out = out[:samples(loop_s + tail)]
    return out


# =================================================================================================
# Pieces
# =================================================================================================

def region_stems(key: str, seed=None) -> dict:
    """Render the five stems of one region, all the same length."""
    cfg = dict(compose.REGIONS[key])
    score = compose.region_score(key)
    seed = seed if seed is not None else cfg["region_id"]
    cfg.setdefault("ostinato", "cello_short")
    cfg.setdefault("deep_voice", "hum" if key == "cinderlea" else "drone")
    cfg.setdefault("vowel", {"sedgemire": "oo", "briarwold": "oh"}.get(key, "ah"))
    cfg.setdefault("brightness", {"hearthvale": 0.55, "brightwater": 0.62, "sedgemire": 0.38,
                                  "briarwold": 0.3, "skerrow": 0.45, "cinderlea": 0.25}[key])
    cfg.setdefault("drum_hz", 72.0)
    out = {}
    for stem in ("pad", "melody", "texture", "combat", "deep"):
        t0 = time.time()
        y = render_stem(score, stem, cfg, core.sub_seed(seed, stem))
        y = render.mixdown(y, peak_db=-1.5, target_lufs=STEM_LUFS[stem], hp=28.0, loop=True)
        out[stem] = y
        print("      %-8s %6.1f s  peak %5.1f dB  %5.1f LUFS  (%.0f s)" % (
            stem, len(y) / SR, core.lin_to_db(core.peak(y)), render.loudness_lufs(y),
            time.time() - t0))
    return out, score


def piece(name: str):
    """Render a set piece (menu theme, Naming cue, boss music) as one mixed file."""
    scores = {"main_theme": compose.main_theme, "naming": compose.naming_cue,
              "boss_1": lambda: compose.boss_score(1), "boss_2": lambda: compose.boss_score(2)}
    score = scores[name]()
    cfg = {
        "main_theme": dict(pad_voice="pad", lead="flute", texture="harp", bass="cello",
                           reverb="hall", reverb_mix=0.28, brightness=0.55, vowel="ah",
                           ostinato="cello_short", deep_voice="drone", drum_hz=74.0),
        "naming": dict(pad_voice="glass", lead="hum", texture="bell", bass="drone",
                       reverb="cinder", reverb_mix=0.40, brightness=0.3, vowel="oo",
                       ostinato="cello_short", deep_voice="hum", drum_hz=70.0),
        "boss_1": dict(pad_voice="choir", lead="cello", texture="pluck", bass="cello",
                       reverb="cathedral", reverb_mix=0.26, brightness=0.4, vowel="ah",
                       ostinato="cello_short", deep_voice="drone", drum_hz=58.0),
        "boss_2": dict(pad_voice="choir", lead="cello", texture="pluck", bass="cello",
                       reverb="cathedral", reverb_mix=0.24, brightness=0.5, vowel="ah",
                       ostinato="cello_short", deep_voice="drone", drum_hz=54.0),
    }[name]
    loop = True
    n = samples(score.seconds())
    mix = np.zeros((n, 2))
    for stem in score.stems:
        y = render_stem(score, stem, cfg, core.sub_seed(name, stem), loop=loop)
        mix[:len(y)] += y[:n]
    if name.startswith("boss"):
        # the drums of a boss track carry the pulse; glue them with a little compression
        mix = render.wrap_process(mix, lambda z: fx.compress(
            z, threshold_db=-20.0, ratio=2.5, attack_ms=12.0, release_ms=140.0))
    mix = render.mixdown(mix, peak_db=-1.2, target_lufs=PIECE_LUFS[name], hp=28.0, loop=loop)
    return mix, score


def stinger_audio(kind: str):
    """A short cue that does not loop: it is allowed to ring out and stop."""
    score = compose.stinger(kind)
    cfg = dict(pad_voice={"death": "glass", "echo": "glass"}.get(kind, "pad"),
               lead={"death": "cello", "echo": "flute", "rest": "flute"}.get(kind, "flute"),
               texture="bell", bass="cello", brightness=0.5, vowel="ah",
               ostinato="cello_short", deep_voice="drone", drum_hz=70.0,
               reverb={"death": "cinder", "echo": "marsh", "rest": "valley",
                       "victory": "hall"}.get(kind, "chamber"),
               reverb_mix={"death": 0.42, "echo": 0.36, "menu_select": 0.12}.get(kind, 0.26))
    tail = {"death": 6.0, "victory": 4.0, "rest": 5.0, "echo": 5.0,
            "menu_select": 1.2}.get(kind, 2.5)
    n = samples(score.seconds() + tail)
    mix = np.zeros((n, 2))
    for stem in score.stems:
        y = render_stem(score, stem, cfg, core.sub_seed("stinger", kind, stem), loop=False, tail=tail)
        mix[:min(len(y), n)] += y[:n]
    # a stinger must end in silence, not be cut off
    mix = core.fade(mix, 0.005, min(0.6, tail * 0.4))
    return render.mixdown(mix, peak_db=-1.2, target_lufs=STINGER_LUFS, hp=32.0), score


# =================================================================================================
# Writing
# =================================================================================================

def res_path(abs_path: str) -> str:
    rel = os.path.relpath(abs_path, os.path.join(ROOT, "game"))
    return rel.replace(os.sep, "/")


def write_piece(audio: np.ndarray, abs_path: str, loop: bool, bpm: float = 0.0,
                beats: int = 0) -> dict:
    render.write_ogg(abs_path, audio, quality=OGG_QUALITY)
    render.write_ogg_import(abs_path, res_path(abs_path), loop=loop, bpm=bpm, beat_count=beats)
    info = render.analyse(audio)
    info["path"] = "res://" + res_path(abs_path)
    info["bytes"] = os.path.getsize(abs_path)
    if loop:
        info.update(render.seam_report(audio))
    return info


def build(only=None, force: bool = False) -> dict:
    os.makedirs(AUDIO_DIR, exist_ok=True)
    manifest = {"regions": {}, "pieces": {}, "stingers": {}}

    for key in compose.REGIONS:
        if only and key not in only:
            continue
        print("[music] region %s" % key)
        out_dir = os.path.join(AUDIO_DIR, key)
        if not force and os.path.isdir(out_dir) and len(
                [f for f in os.listdir(out_dir) if f.endswith(".ogg")]) == 5:
            print("      up to date")
            manifest["regions"][key] = _reuse(out_dir, compose.region_score(key))
            continue
        stems, score = region_stems(key)
        entry = {"bpm": score.bpm, "mode": score.mode, "tonic": score.tonic, "bars": score.bars,
                 "seconds": score.seconds(), "title": score.meta.get("title", key),
                 "region_id": compose.REGIONS[key]["region_id"], "stems": {}}
        for stem, audio in stems.items():
            p = os.path.join(out_dir, "%s.ogg" % stem)
            entry["stems"][stem] = write_piece(audio, p, loop=True, bpm=score.bpm,
                                               beats=int(score.total_beats()))
        manifest["regions"][key] = entry

    for name in ("main_theme", "naming", "boss_1", "boss_2"):
        if only and name not in only:
            continue
        print("[music] piece %s" % name)
        p = os.path.join(AUDIO_DIR, "theme", "%s.ogg" % name)
        if not force and os.path.exists(p):
            print("      up to date")
            continue
        audio, score = piece(name)
        manifest["pieces"][name] = write_piece(audio, p, loop=True, bpm=score.bpm,
                                               beats=int(score.total_beats()))
        manifest["pieces"][name].update({"bpm": score.bpm, "mode": score.mode,
                                         "title": score.meta.get("title", name)})
        print("      %.1f s  %.1f LUFS" % (len(audio) / SR, render.loudness_lufs(audio)))

    for kind in compose.STINGERS:
        if only and kind not in only:
            continue
        p = os.path.join(AUDIO_DIR, "stingers", "%s.ogg" % kind)
        if not force and os.path.exists(p):
            continue
        print("[music] stinger %s" % kind)
        audio, score = stinger_audio(kind)
        manifest["stingers"][kind] = write_piece(audio, p, loop=False)
        print("      %.1f s  %.1f LUFS" % (len(audio) / SR, render.loudness_lufs(audio)))

    _write_content(manifest)
    render.save_manifest(os.path.join(AUDIO_DIR, "manifest.json"), manifest)
    return manifest


def _reuse(out_dir: str, score: compose.Score) -> dict:
    entry = {"bpm": score.bpm, "mode": score.mode, "tonic": score.tonic, "bars": score.bars,
             "seconds": score.seconds(), "title": score.meta.get("title", ""), "stems": {}}
    for f in sorted(os.listdir(out_dir)):
        if f.endswith(".ogg"):
            p = os.path.join(out_dir, f)
            entry["stems"][f[:-4]] = {"path": "res://" + res_path(p), "bytes": os.path.getsize(p)}
    return entry


def _write_content(manifest: dict) -> None:
    """The core:music definitions the MusicDirector reads."""
    defs = []
    for key, entry in sorted(manifest["regions"].items()):
        cfg = compose.REGIONS[key]
        defs.append({
            "id": "core:music/%s" % key,
            "name": entry.get("title") or cfg["title"],
            "region": cfg["region_id"],
            "mode": cfg["music_mode"],
            "bpm": round(float(entry.get("bpm", 0.0)), 3),
            "bars": int(entry.get("bars", 0)),
            "loop_seconds": round(float(entry.get("seconds", 0.0)), 3),
            "colour": cfg["colour"],
            "stems": {s: v["path"] for s, v in sorted(entry["stems"].items())},
        })
    pieces = manifest.get("pieces", {})
    for name, title, mode_key in (("main_theme", "Wickmere", "lydian_warm"),
                                  ("naming", "The Naming", "phrygian_hollow"),
                                  ("boss_1", "The Holder of a Note", "phrygian_hollow"),
                                  ("boss_2", "The Note Itself", "phrygian_hollow")):
        info = pieces.get(name, {})
        path = info.get("path") or "res://assets/audio/music/theme/%s.ogg" % name
        defs.append({
            "id": "core:music/%s" % name,
            "name": title,
            "mode": mode_key,
            "bpm": round(float(info.get("bpm", 0.0)), 3),
            "loop_seconds": round(float(info.get("seconds", 0.0)), 3),
            "stems": {"main": path},
        })
    stingers = {}
    for kind in compose.STINGERS:
        info = manifest.get("stingers", {}).get(kind, {})
        stingers[kind] = info.get("path") or "res://assets/audio/music/stingers/%s.ogg" % kind
    defs.append({
        "id": "core:music/stingers",
        "name": "Stingers",
        "mode": "ionian_bright",
        "bpm": 0.0,
        "stems": {},
        "stingers": stingers,
    })
    os.makedirs(PACK_DIR, exist_ok=True)
    with open(os.path.join(PACK_DIR, "music.json"), "w") as f:
        json.dump(defs, f, indent=2, sort_keys=True)
        f.write("\n")
    print("[music] wrote %d music definitions" % len(defs))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", nargs="*", help="regions/pieces/stingers to render")
    ap.add_argument("--force", action="store_true", help="re-render even if the files exist")
    ap.add_argument("--list", action="store_true", help="list what would be rendered")
    args = ap.parse_args()
    if args.list:
        for k in compose.REGIONS:
            s = compose.region_score(k)
            print("region  %-12s %6.1f s  %s %s  %.0f bpm" % (k, s.seconds(), s.mode,
                                                              "tonic=%d" % s.tonic, s.bpm))
        for k in ("main_theme", "naming", "boss_1", "boss_2"):
            print("piece   %s" % k)
        for k in compose.STINGERS:
            print("stinger %s" % k)
        return 0
    t0 = time.time()
    build(only=args.only, force=args.force)
    print("[music] done in %.0f s" % (time.time() - t0))
    return 0


if __name__ == "__main__":
    sys.exit(main())
