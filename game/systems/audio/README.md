# systems/audio

Three autoloads. Nothing else in the game loads an audio stream or makes a player.

| Autoload | File | Role |
|---|---|---|
| `Music` | `music_director.gd` | region stems, combat and deep layers, boss tracks, the menu theme, stingers |
| `Ambience` | `ambience_mixer.gd` | region/time/weather ambience beds and one-shot pools, interior muffling |
| `Foley` | `foley.gd` | every world and UI one-shot, from `core:table/sfx`, through pooled players |

All the audio itself is generated outside the engine by `tools/audio/` and committed as OGG.
Nothing is synthesised at runtime; these scripts only choose files and move levels.

## Buses

`default_bus_layout.tres` (built by `tools_gd/make_bus_layout.gd`, set in project.godot under
`audio/buses/default_bus_layout`):

```
Master
├ Music      region stems, overlays, stingers
├ SFX        world one-shots
├ Ambience   beds and pools          (low-pass effect 0: interior muffling)
├ UI         menus, notifications, the rest/echo cues
├ Voice      reserved
└ Interior   reverb (dry .72 / wet .38); world sounds are routed here while indoors
```

`Settings` already applies the player's volumes to Master/Music/SFX/Ambience/UI/Voice.
`Interior` is a bus a player is *routed to*, not a true auxiliary send: a Godot bus has one
output, so it carries the dry signal as well as the reverb.

## Music

Reads: `core:music/*` (id, name, region, mode, bpm, `stems{name: res://...}`, and
`core:music/stingers`). Consumes `EventBus.region_entered`, `damage_dealt`, `boss_started`,
`boss_defeated`, `player_died`, `level_up`, `quest_stage_changed`, `hearthstone_rested`,
`echo_recovered`, `menu_opened`, `menu_closed`, `interior_entered/exited`. Emits
`region_music_changed`, `mode_changed`. No save section.

Five stems play together in sync for the current region; the director only changes their
levels. The mode is picked from two facts:

* **combat** — `combat_intensity` rises by 0.5 whenever `damage_dealt` involves a node in group
  `player` (either side of it) or a boss starts, and decays to zero over 8 seconds. The combat
  stem's level follows the intensity, so a single hit swells rather than switches.
* **deep** — true inside any interior, or when the region def's `danger` is 4 or more. The
  melody is muted and the deep stem takes over: *deep places drop the melody*.

| mode | pad | melody | texture | combat | deep |
|---|---|---|---|---|---|
| explore | 0 | 0 | −1 | − | − |
| combat | −2 | −9 | −4 | 0 (× intensity) | − |
| deep | −4 | − | −10 | − | 0 |
| deep_combat | −5 | − | −9 | −2 | −4 |

Region changes crossfade over 4 s. Boss music replaces the bed entirely and switches to its
second intensity on a phase change (`set_boss_intensity(2)`, also triggered by a boss quest
reaching stage 2). A full-screen menu either brings up the menu theme (main menu, character
creation) or ducks the bed by 10 dB. Stingers (`victory`, `death`, `level_up`, `quest_update`,
`rest`, `echo`, `menu_select`) play over whatever is going on.

API: `play_region(region_id, instant)`, `raise_combat(amount)`, `clear_combat()`,
`set_boss_intensity(1|2)`, `play_stinger(kind)`, `is_deep()`, `stem_volume_db(stem)`,
`playing_stems()`, `overlay_kind()`, `stop_all()`.

## Ambience

Reads: region `identity.ambience` keys, `assets/audio/ambience/manifest.json`,
`Atmosphere.weather_params()` (group `atmosphere`), `WorldClock.time_hours`. Consumes
`region_entered`, `hour_changed`, `weather_changed`, `interior_entered/exited`. Emits
`layers_changed`. No save section.

Each manifest entry is either a **bed** (a seamless loop held at a level) or a **pool** (one-shot
variants fired at a random gap, with a random pitch). On top of the region's own keys:

* **time of day** — layers declare an hour window, so owls and night insects come in after dark,
  the dawn chorus around 5, skylarks and the market by day.
* **weather** — rain follows `precip_intensity`, and which surface it lands on depends on the
  region (stone in Tollmere, water in Sedgemire, canvas in Cinderlea). Wind gust density follows
  `wind`. Snow and ashfall have their own beds. When `thunder` is true, rolls fire 20–90 s apart,
  near ones only in heavy rain.
* **interiors** — every outdoor layer drops 9 dB, a room tone comes in, and the low-pass on the
  Ambience bus closes to 900 Hz.

API: `set_region(id)`, `desired_layers() -> {key: dB}`, `active_layers()`, `bed_volume_db(key)`,
`target_db(key)`, `cutoff_hz()`, `weather_params()`, `set_weather_override(params)` (tests),
`stop_all()`.

## Foley

Reads: `core:table/sfx` — `rows[id] = {files[], volume_db, pitch_variance, bus}`, written by
`tools/audio/gen_sfx.py`. No signals consumed; emits `played(id, position)`. No save section.

```gdscript
Foley.play("sword_swing_light", global_position)      # in the world
Foley.play("ui_error_thunk")                          # no position: flat
Foley.play_ui("ui_page_turn")                         # on the UI bus
Foley.footstep("stone", global_position)              # a named surface
Foley.footstep(Foley.surface_at(global_position), global_position)
```

`surface_at(position)` casts down and reads a `surface` metadata entry off the collider (or up
to four parents), falling back to `vale_grass`; an unknown surface name is logged once and
falls back rather than going silent. Surfaces: `vale_grass`, `dirt`, `stone`, `wood`, `water`,
`snow`, `ash`, `gravel`, `mud`, `sand`.

24 pooled `AudioStreamPlayer3D` and 8 `AudioStreamPlayer`. A variant is never picked twice in a
row, and each play gets a pitch inside the row's `pitch_variance`. When every 3D player is busy
the quietest is stolen, so a sound is never simply dropped. World sounds route to the `Interior`
bus while the player is inside.

## Regenerating

```
python3 tools/audio/gen_music.py --force        # ~14 min: stems, theme, boss, stingers
python3 tools/audio/gen_ambience.py --force     # beds and one-shot pools
python3 tools/audio/gen_sfx.py --force          # 70 ids, 240 variants
python3 tools/audio/report.py                   # spectrograms + loudness table -> captures/audio
godot --headless --path game --audio-driver Dummy -s tools_gd/make_bus_layout.gd
```

`tools/audio/tests/run_tests.py` covers the toolkit and the scores; `tests/unit/test_music_director.gd`
and `test_foley.gd` cover these scripts.
