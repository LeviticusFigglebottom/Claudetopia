# systems/exploration — finding places, and reading the country off high ground

The two ways the chart fills. DESIGN.md §5.16 ("Compass shows cardinal points,
discovered locations only… Map is a painted, partially revealed chart: you fill
it by looking from high places (surveying at vistas) and by buying charts") and
the composition rule of §4, where every POI names somewhere it can be seen from.

The map screen and the compass had always drawn both states — fog lifts a little
around a discovered place and much further around a surveyed one — and neither
had a way to happen. `GameState.discover()` was called by a dialogue effect and
by resting at a Hearthstone and by nothing else, so you could walk the length of
the country and reach Tollmere with a blank chart. `surveyed:<place>` was set by
nothing at all outside the UI review's fake save. This is the half that walks.

## Files

| File | Kind | What it is |
|---|---|---|
| `place_discovery.gd` | Node, group `place_discovery` | Arriving somewhere, surveying from a vista, and the line-of-sight march that decides what a vista actually shows |

Installed once by `GameServices` (`world/bootstrap/game_services.gd`), like the
other non-autoload world services, so the world, the arena, the smoke run and
the scripted journey all get it. `PlaceDiscovery.ensure()` finds or creates it.

## The two ways a place is found

**Arriving.** Every 0.55 s the node reads the player's position and compares it
against every place's pad: within its own footprint plus `ARRIVAL_MARGIN_M`
(30 m) you have arrived. A village pad is its houses, so you have found Merrowby
when you are among the outermost of them and not when you touch the exact centre.

**Surveying.** A **vista** is any place that some POI names in its own
`visible_from`; that is what the authored data already means, and it saves
inventing a second list. Standing on one sets `surveyed:<place>` — the chart's
wider reveal — and discovers everything that place's sightlines promise *and the
land allows*. You can survey somewhere you have already arrived at; the two
questions are asked separately.

**The sightline is checked against the built terrain, not taken on trust.**
`can_see()` marches `RAY_STEPS` (64) samples from the eye at `EYE_M` (1.65 m)
above the vantage to the landmark's own top, and fails if the ground stands more
than `CLEARANCE_M` (2 m) above that line. The first `FOREGROUND_M` (140 m) is
skipped, because a vantage has extent and somebody standing on a quay takes the
few paces needed to see past the bank at their feet. Past `MAX_SIGHT_M` (4200 m)
the region's own haze would have swallowed it anyway. A claim the land
contradicts reveals nothing and says so in the log; `tools/sightlines.py` marches
the same ray over the same heightmap and reports every refused claim, so it is a
question for whoever placed the POI rather than a silent failure.

## Data it reads

* **`poi` defs' `visible_from[]`** — the authored composition. 48 POIs, 90
  sightlines. Every entry is a full place or POI id (CONTRACTS §8).
* **`LANDMARK_M`, by the place's `kind`** — how far the thing stands above its
  own ground, which is the difference between a mechanic and a lookup: `tower`
  10 m, `waterfall` 13, `strange_tree` 14, `giant_bones` 13, `ruins` 6,
  `strange` 2.5, `wreck` 5, `standing_stones` 5, `bridge` 4.5, `shrine` 4,
  `camp` 2.5, `hidden_valley` 1, and `LANDMARK_DEFAULT_M` 6 for anything else.
  A flat six metres for all of them made the falls invisible and the charcoal
  camps monumental, and a hidden valley is called hidden because you cannot see
  into it from anywhere — its sightline is the way in, not the thing itself.
  Every number is measured off `game/world/pois/poi_builders.gd`, which is what
  actually stands on the pad: a watch drum is 7.6 m and carries its fire-bowl to
  about 10, a cliff face is 11 to 13, a standing gable 4.6, a bell buoy is a
  barrel with a post on it. They were guesses before the POIs were dressed.
* **`world/generated/pois.json`** — the pads as the world builder actually
  placed them, read straight off disk rather than through `World`, so this
  answers the same in a unit test with no world in the tree, in the scripted
  journey and in the game. A place's own `[x, z]` from the content pack is the
  fallback.
* **`place` and `poi` defs' positions**, through `WorldProbe`.

## Public API

```gdscript
PlaceDiscovery.ensure() -> PlaceDiscovery       # group "place_discovery"
disco.look_around(here: Vector3)                # arrive at / survey anything in reach
disco.arrive(place_id)                          # you are here
disco.survey(vantage_id) -> Array[String]       # what the country shows from here
disco.can_see(from: Vector3, to: Vector3, target_id := "") -> bool
disco.vistas() -> Array[String]                 # every place some POI can be seen from
disco.sightlines() -> Array[Array]              # [[vantage, target], ...]
disco.position_of(place_id) -> Vector3
PlaceDiscovery.landmark_height(place_id) -> float   # static
```

`enabled = false` stops the polling without removing the node.

## Signals

Emitted: `EventBus.place_discovered(place_id)` — raised by `GameState.discover()`
rather than by this node, so being told about a place in dialogue and walking
into it announce themselves identically. `EventBus.notify(...)` for the name of
the place you have just reached, and for what a vista did or did not add.

Consumed: none. It polls the player's position off `Peers.player()` instead of
listening, because nothing emits a signal for "has moved thirty metres".

Who listens to `place_discovered`: the HUD's compass markers, the map screen's
fog, `Social` (the `place_discovered` deed and its renown), and `QuestLog` for
`reach` objectives.

## Save section

**None, deliberately.** Everything this system learns is kept by `GameState` and
rides in its section: the discovered set in `discovered_places[]`, and each
survey as a `surveyed:<place_id>` flag. What the node itself holds is either a
timer (`_accum`) or a cache rebuilt from the content pack and `pois.json` on
first use (`_positions`, `_radii`, `_seen_from`), so there is nothing here that a
save could lose. Adding a section would mean two records of the same fact.

## Notes for other streams

* `surveyed:<place_id>` is the flag name, and `map_screen.gd` reads it directly.
  A dialogue effect or a bought chart can set it without going through this node.
* Arrival radius is a place's own `radius_flat_m` from `pois.json` (floored at
  18 m) plus 30 m. A place with no pad in the built world still works; it just
  uses the floor.
* `can_see()` needs terrain to be meaningful. With no world loaded
  `WorldProbe.get_height` returns the sentinel and nothing blocks, so a test
  without a world sees every sightline as clear.
