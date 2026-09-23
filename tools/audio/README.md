# tools/audio — everything Wickmere hears

No samples, no third-party sounds, no recordings. Every signal in the game starts here as an
oscillator, a noise source or a resonator, and is committed as OGG under `game/assets/audio/`.

```
synth/            the toolkit: oscillators, envelopes, filters, effects, instruments, theory,
                  rendering and loudness/loop measurement
compose.py        the score as note data: region themes, set pieces, the Toll leitmotif
gen_music.py      renders compose.py's scores to stems and pieces + core:music defs
gen_ambience.py   beds and one-shot pools for every ambience key, weather and time layer
gen_sfx.py        70 effects in 240 variants + the core:table/sfx content table
report.py         spectrograms and a loudness/balance table into captures/audio/
audit.py          what fails a release: clipping, true peak, DC, late or hot one-shot edges,
                  beds that drop to digital silence, loop-seam clicks and breaks, and files
                  far from their category's loudness (one-shots by their loudest 400 ms at
                  their table level); --strict exits 1 on any flag
tests/            122 tests; run with tests/run_tests.py (pytest is not installed here)
```

## Regenerating

```bash
python3 tools/audio/gen_music.py --force        # ~13 min
python3 tools/audio/gen_ambience.py --force     # ~4 min
python3 tools/audio/gen_sfx.py --force          # ~1 min
python3 tools/audio/report.py                   # spectrograms + captures/audio/loudness.md
python3 tools/audio/audit.py --strict           # every file against the release checks
python3 tools/audio/tests/run_tests.py          # the toolkit, the scores, the generators
godot --headless --path game --audio-driver Dummy -s tools_gd/make_bus_layout.gd
godot --headless --path game --import --audio-driver Dummy    # fills in the .import sidecars
```

Each generator takes `--only <names...>` and `--list`. Without `--force` they skip anything
already rendered, so re-running after a change to one region costs only that region.

Everything is deterministic: the same seed gives the same audio, byte for byte. Seeds derive
from content ids through `core.sub_seed`, so a region's music does not change because another
region's did.

## How the music is put together

`compose.py` writes notes; `gen_music.py` turns them into sound. They are separate so the
musical rules can be tested without rendering: every note in the region's mode, no simultaneous
minor seconds outside deliberate tension, the Toll present and developed in every region, stems
that line up.

The **Toll** is the leitmotif — five notes, a bell struck and answered. Each region states it
transformed by what that place has made of the ringing, then develops it across four phrases:
statement, inversion, augmentation, fragment.

| region | mode | bpm | lead | the colour |
|---|---|---|---|---|
| Hearthvale | lydian | 76 | flute over harp | warm and lyrical, with a lilt |
| Brightwater | ionian | 92 | whistle and pluck | bright and busy |
| Sedgemire | dorian | 60 | breathy flute, choir pad | misty, a long way off |
| Briarwold | aeolian | 54 | low strings | deep and hushed |
| Skerrow | mixolydian | 68 | pipes over a drone | cold and open |
| Cinderlea | phrygian | 44 | a held hum | hollow, sparse, one bell |

Five stems per region on one bar grid: `pad` (harmony and bass), `melody`, `texture`
(arpeggio, counter-line, bells), `combat` (an ostinato and a pulse in the same key) and `deep`
(the melody gone, a held low note, sparse bells). `systems/audio/README.md` has the mix table.

## How loops are verified

Two measures, for two different questions.

**Is the waveform continuous at the wrap?** `render.seam_click_db` compares the step between the
last and first sample against the 95th percentile of the steps this waveform takes elsewhere.
Below about 6 dB means the wrap looks like any other sample boundary. Dividing by the *median*
step instead, as the first version did, reports a click on anything that is mostly silence or a
slow sine, because their median step is near zero.

**Does the seam stand out?** `render.seam_report` puts the level difference across the wrap
beside `local_step_db`, the level difference this material takes between any two neighbouring
windows. A bed whose seam sits under its own movement is seamless; a composed loop that strikes
a bell on its downbeat honestly swings 30 dB every bar and its wrap doing the same is not a
defect. Holding music to an absolute "< 1 dB at the seam" would only mean composing away the
downbeat.

**The real proof**, for music: render the same bars three times in a row and compare the middle
repeat against the single folded loop. They match to within a couple of percent
(`test_a_folded_music_loop_matches_what_repeating_it_would_sound_like`). That is only possible
because per-note randomness is seeded from a note's musical position rather than its index in a
list, so the same bar always sounds the same.

Two things routinely break a loop and are worth knowing about: any causal filter (a high-pass,
a limiter, a compressor) starts from zero state, and that start-up transient lands exactly on
the wrap — `render.wrap_process` runs them circularly instead. And `loop_fold` assumes only
ring-out follows the loop point; events *started* after it are folded in whole and the loop
comes out denser than it was composed.

## Working without ears

This was all built without hearing any of it, so everything is checked by measurement:

* peak, true peak, RMS, crest, LUFS (BS.1770-style), DC offset, stereo correlation
* per-band energy, and spectrograms rendered with numpy and PIL (matplotlib is not installed)
* loop seams by the two measures above, plus the three-repeat comparison
* musical rules over the note data, before any audio exists
* structural checks per family: a one-shot starts and ends in silence, an impact leads with its
  attack and keeps a crest above 8 dB, footstep surfaces are spectrally distinct, a bed's level
  moves enough not to read as a static wall

Several defects were found this way and would have been hard to find otherwise: bells that
began at full amplitude on a random phase and clicked on every strike, strings whose loop gain
was applied per sample rather than per round trip so they died in milliseconds, a wind bed that
breathed only 8 dB across 42 seconds, and mud that measured brighter than stone.

`audit.py` found the next five, all fixed in the generators and pinned in the tests: one-shots
that decoded starting at -26 to -36 dBFS (Vorbis rings ahead of a transient on sample 0, so each
effect is now set in 4 ms of silence -- 50 files); beds of frogs, boardwalk ropes and chain
bridges that fell to digital silence for up to nine seconds between events (they now have a
floor); a far thunder that began up to 1.4 s after it was fired and coins that landed 100 ms
after the purchase (lead-ins below -60 dB of the peak are trimmed); variants of one effect up
to 4.9 LU apart (held to 3 LU now); and two rows the table played 10-11 LU under their family.
