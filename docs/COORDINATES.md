# Where things are: every world coordinate the game holds

The map is drawn by hand (`tools/world/atlas/atlas.json`) and will be drawn again. When a place
moves, whatever was said *relative to it* moves with it; whatever wrote down *coordinates*
stays behind in the old country. This is the inventory of both, taken for the move to the
atlas world (2026-09-23), and the rule for anything new.

**The rule.** The map is written down in one place: each place's and POI's `position` (which the
atlas writes). Everything else names a place and says where from it:

| Say it as | Means | Read by |
|---|---|---|
| `{"place", "bearing", "distance", "height"}` | compass bearing (0 north = -z, 90 east) and metres from the place, `height` above the ground there | `PlaceRef.point`, `CinematicPath.point_of` |
| `{"place", "offset": [dx, dz]}` | metres east and south of the place | `PlaceRef.point_xz` |
| a way's `shape: [[along, across], ...]` | the frame from one place (0, 0) to another (1, 0); `across` to the right of the walker | `PlaceRef.along`, `PoiDressing.way_points` |
| a save's `near` pin `{"place", "at", "rise"}` | the place nearest a remembered position, where it stood, height above ground | `PlaceRef.pin` / `PlaceRef.follow` |

`test_place_ref.gd` fails if a definition holds coordinates where a place belongs. To turn
coordinates into places: `tools/place_paths.py` (a POI's way) and
`tools/capture/relative_plan.py` (a capture plan).

## Derived from a place (follows it already)

| Holder | How |
|---|---|
| Opening cinematic (`cinematics/opening.json`) | every camera key and look is `{place, bearing, distance, height}` or the player; the hand-over faces a place |
| The start (`opening.json`, `PlayerSpawn`, `World.spawn_place`) | a place id (`core:poi/stair_head`), set down on dry ground near it. The atlas manifest's `start` is not read by the game |
| NPC homes, schedules, holds | `home_place`, `schedule[].place` + a named `spot` (a marker the built place carries, else a fixed ring round the place) |
| Quest markers, `where`, kills, escorts | place ids with a radius (`QuestLog`, `KillPlaces`, `Escorts`) |
| Encounters (`encounters/pois.json`), deep places, houses, deeds | a place id and marker names |
| Door plans (`interiors/door_plan.json`) | a ring radius and bearing round the place's centre |
| Settlement fabric, the Stair Head camp's layout | the place's position, roads, and the direction of its way's end |
| Sightlines (`visible_from`, `tools/sightlines.py`) | place ids; rays between their positions |
| Journey, flow and perf probes; fights arena | `place_position`, the player, or interior/arena-local |
| Generated capture plans (`default`, `pois`, `look`, `horizon`) | written by `make_default_plan.py` / `make_pois_plan.py` from the built world: **run them again after a map change** |
| Region map centres in the smoke sweep and `test_kill_places` | the region definition's own `map` block |

## Literals that should follow a place (converted in this change)

| Was | Now |
|---|---|
| `door_plan.json` `position` ×15, a copy of each place's position | gone; `WorldDoors` falls back to the place's own position |
| The Stair Head's `path.via`, 18 map points | `path.shape` between the Stair Head and the Sunken Choir; the same points to 2 mm on this map. Where the built world has a road between the two (the atlas's track), the waystones stand along the road instead |
| Hand-written capture plans (`streets`, `start`, `opening_scout`, `gait`, `roll`): 48 points | place specs (`at`, `look`, gait `at`); within 7 mm of the old points against the runtime heights |
| Saves: the player, the Hearth's landing and Echo, an interior's way out, an escort on the road | each saved with a `near` pin; a load beside a moved place moves with it, unmoved loads exactly as saved |
| Map screen's default centre `(900, 2350)` | the place tagged `start_hub` |
| UI review's fake player `(980, 42, 2280)` | Merrowby + (80, -70) |
| World chart region names at `regions.json` `map.center` | the deepest point of each region in the built region mask (`gen_map.py`) |
| Unit tests: Merrowby and Grandfather Hollow as numbers (9 files) | `TestCase.at_place(id, y)` |
| `test_world_data`: the Mere, the northern wall, the Hushline, Merrowby, region centres | the deepest water at the lake level; the ground round Windgate; the Hushline's and Merrowby's places; each region's mean over its own mask |
| `test_npc_streamer` "far away" `(-3600, -3600)`; footsteps' sand search `(-3450, -450)` | the grid point farthest from every place; the Tideflat Stones |

## Legitimately absolute

| Holder | Why |
|---|---|
| `places.json` / `pois.json` `position`, `atlas.json`, `game/world/generated`, `game/terrain_data` | this *is* the map |
| The map frame: origin `(-4096, -4096)`, 256 m cells, `CONTRACTS.md` §6 | the coordinate system itself |
| Interior metas and pockets (`POCKET_ORIGIN` 50 km out) | interior-local; no place moves them |
| `regions.json` `map` (`center`, `radius`, `base_height`) | the no-world fallback (`WorldProbe.nearest_region_id`, the synthetic chart, the old seeded builder). It should still be kept inside each region as the atlas draws it |
| Crime records' `position` | in flight for a few game hours; the region travels with it |
| Test fixtures off the map (`5000, 10, 5000`), in arenas, on synthetic ground, or pure maths (compass, cinematic path) | no world under them |
| `gen_map.py` synthetic rivers and roads | the chart drawn when there is no world at all |
