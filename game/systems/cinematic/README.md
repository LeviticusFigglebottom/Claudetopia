# systems/cinematic

Purpose: cutscenes played in the streamed world, as data. The one that exists is the opening
(DESIGN §5.1a): the Warden's voice over the country, after the Naming, on New Game only.

| File | Class | Role |
|---|---|---|
| `cinematic_def.gd` | `CinematicDef` | the validator `Schemas` runs on every `core:cinematic/*`, and the readers everything else shares |
| `cinematic_path.gd` | `CinematicPath` | one shot's camera resolved against the ground: keys, an eased Hermite spline, poses |
| `cinematic_player.gd` | `CinematicPlayer` | plays a definition: borrows the camera, streamer, clock, sky, buses, HUD and input, and gives them back |
| `cinematic_overlay.gd` | `CinematicOverlay` | what is drawn over the world: curtain, dissolve still, letterbox, title card, subtitles, skip prompt, caption |

Reads: `core:cinematic/*` (shape in `cinematic_def.gd`'s header), `core:opening/new_game`
(`cinematic`), `core:music/*` (the cue), places and POIs through `World.place_position`, the ground
and water through `TerrainProvider`, Settings `gameplay/play_opening`, `gameplay/subtitles`,
`accessibility/ui_scale`, `controls/camera_side`.
Emits: `shot_started(index, id)`, `finished(skipped)`. No save section: nothing it does outlives it.

## Where it plugs in

* **New Game**: `GameServices.begin_new_game()` awaits `CinematicPlayer.play_opening(opening)`
  before starting the opening quest. That is the only hook into the new-game flow. It returns at
  once when there is nothing to play, when `gameplay/play_opening` is off, with `-- --no-opening`,
  and in any headless run unless `CinematicPlayer.headless_allowed` is set (tests only).
* **Replay**: the pause menu's *How it began* calls `CinematicPlayer.replay()`; afterwards the
  body, the clock and the sky are exactly where they were.
* **Capture**: a capture plan with a `cinematic` block has the capture runner `scrub()` the
  player to each shot's key frames and write what a player would see, letterbox and subtitles
  included (`tools/capture/plans/opening.json`).

## What it borrows, and the rule about giving it back

`_save_state` writes down the streamer's target, `also_around` and `report_regions`, the clock and
whether it runs, the atmosphere's saved weather and region, the Ambience and SFX bus levels, the
HUD and toast visibility, the current camera, the mouse mode, and the body's position, facing and
rig. `_restore` puts all of it back, and it is the same function whether the cinematic was
watched or skipped — a skip goes to black, jumps to the last frame of the hand-over shot and hands
over from there. `tests/unit/test_cinematic_player.gd` compares the two end states field by field
at four skip points. If you borrow something new, save it, restore it, and add it to that test's
`_state()`.

The tree is never paused: the villages the camera passes go on with their day. The streamer
follows the camera with `report_regions` off, because a region change seeds rumours, moves the
music and titles the HUD, and the camera is not a traveller.

## Tests

`test_cinematic_def.gd` (the validator), `test_cinematic_path.gd` (the arithmetic),
`test_cinematic_paths_clear.gd` (every path sampled against the full-resolution ground, the
water, the scatter and the world's edge), `test_cinematic_player.gd` (New Game plays it, Continue
does not, skipping anywhere ends where watching does, a replay puts everything back).
