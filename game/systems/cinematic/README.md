# systems/cinematic

Purpose: cutscenes played in the streamed world, as data. The one that exists is the opening
(DESIGN §5.1a): the Warden's voice over the country, after the Naming, on New Game only.

| File | Class | Role |
|---|---|---|
| `cinematic_def.gd` | `CinematicDef` | the validator `Schemas` runs on every `core:cinematic/*`, and the readers everything else shares |
| `cinematic_path.gd` | `CinematicPath` | one shot's camera resolved against the ground: keys, an eased Hermite spline, poses |
| `cinematic_player.gd` | `CinematicPlayer` | plays a definition: borrows the camera, streamer, clock, sky, buses, HUD and input, and gives them back |
| `shot_sight.gd` | `ShotSight` | the cells a shot's camera will see along its path, near and far: streamed before and while it plays |
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
  included (`tools/capture/plans/opening.json`). The style films have `film_<style>.json`;
  `tools/capture/film_light.py <frames dir>` measures each frame's light (mean, 99th percentile,
  share blown to white) and fails a frame out of family.

## What it borrows, and the rule about giving it back

`_save_state` writes down the streamer's target, `also_around` and `report_regions`, the clock and
whether it runs, the atmosphere's saved weather and region, the Ambience and SFX bus levels, the
HUD and toast visibility, the current camera, the mouse mode, and the body's position, facing and
rig. `_restore` puts all of it back, and it is the same function whether the cinematic was
watched or skipped — a skip goes to black, jumps to the last frame of the hand-over shot and hands
over from there. `tests/unit/test_cinematic_player.gd` compares the two end states field by field
at four skip points. If you borrow something new, save it, restore it, and add it to that test's
`_state()`.

What a shot sees is streamed, not only where it stands: `ShotSight` walks its view over the ground
at nine moments to a kilometre, full detail within 320 m. A film asks for the whole of its country as
it begins (`_plan_film`): every cell every shot sees, the near and far rings round its camera's path,
and the rings and towns round every point a shot opens on or looks at, kept until the hand-over is
over. Its first picture waits under the black for all of the near part, and for everybody living
there to be stood up and dressed (then up to 3 s more for the far ring), because places, towns and
people are pieces of tens of milliseconds and none is built while the pictures are watched
(`watched()`: the streamer's places, WorldDoors' towns and NpcRegistry's people all ask it). From the
first picture on, nothing waits on the country: a cut holds its still a few frames without hurrying
the streamer, never goes to black and never shows the hold line, and a shot whose country is somehow
not in is shown after `MID_HOLD_CAP_SECONDS` with what there is. The shots' weather is the picture's,
not the game's: `Atmosphere.quiet` keeps `weather_changed` (and with it the whole roster's
`simulate_all`) from being told at every cut. `test_film_streaming.gd` plays each style's film as a
new game with the streaming paced and fails on any wait or caption after the first picture; the CPU
probe's `FILM|` lines measure it (tools_gd/cpu_probe.gd). The title's vista streams the same way.

The picture is drawn into the window's own pixels at the preset's render scale, never a smaller
viewport stretched up: `render_report()` says what each frame was drawn at, the log gives it once a
shot ("drawn at 1920x1080 in a 1920x1080 window"), and the capture runner writes it beside every
frame. The game's settings are tuned for a body five metres from what it looks at, and the films
look at the country from 100 to 700 m, so on High and Painted a film is drawn with `Graphics.FILM`
over the settings while it holds the screen: 4x MSAA, the meshes' and trees' detail twice as far
(2.5x on Painted), the sun's shadows to 700 m (1000 m). Low, Medium and a Custom drawn below the
window keep their own settings; the render scale is never touched. `_restore_globals` gives the
settings' own back. `--no-film-picture`, or a capture plan's `"film_ab": true`, shows the difference.

The tree is never paused: the villages the camera passes go on with their day. The streamer
follows the camera with `report_regions` off, because a region change seeds rumours, moves the
music and titles the HUD, and the camera is not a traveller.

## Tests

`test_cinematic_def.gd` (the validator), `test_cinematic_path.gd` (the arithmetic), `test_shot_sight.gd` (what a camera sees, as cells),
`test_cinematic_paths_clear.gd` (every path sampled against the full-resolution ground, the
water, the scatter and the world's edge, and no camera looking into a low sun: TRIAGE 54), `test_cinematic_player.gd` (New Game plays it, Continue
does not, skipping anywhere ends where watching does, a replay puts everything back).
