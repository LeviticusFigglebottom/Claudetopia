# World life: large sites (caves, mines, crypts, keeps, forts)

How a region agent adds a big site to the country: a multi-room inside (a cave system, a mine, a
barrow, a keep's undercroft, a bandit hideout, a sea cave, a lava tube) and/or a fortified outside
(a fort, a stockade, a watchtower, a ruined castle, a walled camp) with a way from one to the other.
Everything is data: a site is a POI entry and an interior def. No meshes are made offline; the
inside's rock is generated at runtime from the def, the same on every machine.

The two finished examples are the model to copy:

| site | files |
|---|---|
| **The Kilnway** (lava tube, Cinderlea, at -3152, 2360) | `pois/_interiors_showcase.json`, `interiors/sites_showcase.json`, `bosses/sites_showcase.json`, `items/`, `quests/`, `dialogues/`, `rumours/sites_showcase.json` |
| **Scathe Fort** (fort + keep undercroft, Hearthvale, at 2456, 2224) | the same files |

Code: `game/world/sites/` (`site_kinds.gd`, `site_plan.gd`, `site_field.gd`, `site_interior.gd`,
`site_dress.gd`, `site_exterior.gd`, `site_seal.gd`). Tests: `game/tests/unit/test_sites.gd`.
Review renders: `game/tools_gd/site_review.tscn`.

## 1. The two halves

**The outside** is a POI (`content/packs/core/pois/*.json`) whose `kind` is one of:

| kind | what is built |
|---|---|
| `delve` | a mouth in rock (the cave builder's own crag and throat) with the door to `site.interior` at the back of its throat |
| `fort` | square stone curtain, crenellated walkway, square corner towers, gatehouse, stairs up beside the gate, keep, yard |
| `castle_ruin` | pentagon, taller walls torn down in places, round towers, some tumbled |
| `stockade` | hexagon palisade of stakes with a plank fighting step behind it, timber watch platforms on posts |
| `walled_camp` | a low drystone ring with a gate gap, the yard dressed as a camp |
| `watchtower` | a tall square tower with flights of stairs round its outside and a beacon, in a low wall |

**The inside** is an interior def (`content/packs/core/interiors/*.json`) with
`"scene": "res://world/sites/site_interior.tscn"` and a `site` block. Its door stands in the
outside's dressing (`delve`'s throat, a fort's keep via `site.keep`), so no `door_plan` table is
needed. (A `door_plan` row still works, if you want a door on a ring round a place.)

## 2. The data

### The POI (outside)

```json
{
  "id": "core:poi/scathe_fort", "name": "Scathe Fort", "region": "core:region/hearthvale",
  "kind": "fort", "position": [2456, 2224], "radius_m": 30,
  "unique_feature": "...", "story": "...", "encounter": "...", "hook": "...",
  "site": {
    "style": "fort",                          // optional: the kind's own by default
    "radius": 19,                             // the walls' radius (kept inside radius_m - 3)
    "gate_bearing_deg": 200,                  // optional: faces the nearest road, else downhill
    "keep": "core:interior/scathe_undercroft",// the keep's door leads here (a fort/castle_ruin)
    "keep_building": true,                    // a keep without an inside (default: stone styles)
    "profile": {"wall_h": 6.0},               // optional overrides of site_exterior.gd STYLES
    "hook": "core:dialogue/scathe_notice",    // a notice post by the gate starts the quest
    "hook_prompt": "Read the notices on the gate",
    "garrison": {"rank": [ids], "archers": [ids], "heavy": [ids], "count": 10, "tower_archers": 3}
  }
}
```

For a `delve`: `"site": {"interior": "core:interior/<id>", "mouth": "lava", "hook": ..., "hook_prompt": ...}`.
A garrison block is optional; without one, nobody stands in the fort (use an `encounter` def as
for any POI if you want the POI system's day/night groups instead).

### The interior (inside)

```json
{
  "id": "core:interior/the_kilnway", "name": "The Kilnway",
  "scene": "res://world/sites/site_interior.tscn",
  "kind": "deep_place", "place": "core:poi/the_kilnway", "danger": 3,
  "resident": "...", "story": "...", "unique_object": "...",
  "site": {
    "kind": "lava_tube",           // see 3.
    "seed": 3117,                  // change it to get another layout; same seed = same place
    "region": "core:region/cinderlea",
    "size": "large",               // small 5 rooms, medium 7, large 9, huge 12 (+ boss, secret, bypass)
    "set_pieces": ["lava_chasm", "daylight_shaft", "obsidian_grotto"],   // else chosen from the kind
    "boss": "core:boss/kiln_warden", "boss_adds": 2, "boss_loot": "core:loot/rich_chest",
    "rich_loot": "core:loot/rich_chest",                   // the secret room's chest
    "foes": {"rank": [ids], "archers": [ids], "heavy": [ids]},   // else the region's (SiteKinds.REGION_FOES)
    "secret": true, "shortcut": true,                       // both on by default
    "theme": {"palette": ["#3d3835", "#26221f", "#5a4f47"], "lights": ["lava", "ember"]},  // any SiteKinds key
    "features": [
      {"kind": "prop", "room": "mouth", "prop": "bedroll"},
      {"kind": "note", "room": "secret", "book": "core:book/...", "name": "a letter"},
      {"kind": "hearthstone", "room": "room3", "id": "...", "name": "..."},
      {"kind": "item", "room": "boss", "item": "core:item/...", "asset": "res://..."}
    ]
  }
}
```

Room ids of a generated layout are `mouth`, `room1`...`roomN`, `boss`, `secret`, `bypass` (the loop's
side room, when one was needed). Write `rooms` yourself to name them and choose each one:

```json
"rooms": [
  {"id": "porch", "role": "entrance", "size": "medium"},
  {"id": "stair", "role": "passage", "size": "small", "drop": -4.0},
  {"id": "lake", "role": "chamber", "size": "large", "set_piece": "underground_lake", "note": "..."},
  {"id": "camp", "role": "camp", "size": "large"},
  {"id": "hall", "role": "hall", "size": "large", "set_piece": "ledge"},
  {"id": "throne", "role": "boss", "size": "huge", "set_piece": "boss_arena"}
]
```

Roles: `entrance` (first), `chamber`, `passage` (a small room, maybe an ambusher), `camp` (fire,
bedrolls, sleepers), `hall` (the heavy before the boss), `treasure` (rich chest), `shrine` (quiet),
`boss` (last). A room may give `drop` (metres up or down from the previous room, clamped to a
walkable slope), `height` (a multiplier) or `half` ([x, height, z] in metres). With `encounters`
written (`{"room", "enemy", "count", "role": "guard|sleeper|archer|ambush|patrol"}`) they replace the
generated groups (the boss stays).

## 3. Kinds

| kind | rock | rooms / passages | lit by | left in it | set-pieces it picks from |
|---|---|---|---|---|---|
| `cave` | water-worn | domes, round bores | glow fungus, torches | boulders, a few bones | underground_lake, daylight_shaft, chasm_bridge, fungus_grotto |
| `mine` | cut | domes, square adits with timbering and lanterns | lanterns, torches | frames, carts, barrows, rope | forge_hall, chasm_bridge, collapsed_shaft, ore_gallery |
| `crypt` (barrow) | dressed, fallen | vaulted boxes, square passages with stairs | braziers, candles | sarcophagi, coffins, bones | ossuary, collapsed_shaft, chasm_bridge |
| `keep` (undercroft) | ashlar | vaulted halls, stairs | torches, braziers | stores, barracks | forge_hall, barracks, cellar_store |
| `ruined_hall` | broken ashlar | vaults, rubble, roots | daylight, braziers | rubble, roots | collapsed_shaft, ossuary, chasm_bridge |
| `bandit_cave` | gouged | domes | campfires, torches, lanterns | a camp in every third room, stores | daylight_shaft, underground_lake, chasm_bridge |
| `sea_cave` | water-worn, wet | wide bores | daylight, fungus | rope, crabs, a boat | underground_lake, daylight_shaft, chasm_bridge |
| `lava_tube` | black, smooth | wide tubes | lava vents, ember cracks | basalt columns | lava_chasm, daylight_shaft, chasm_bridge, obsidian_grotto |

Set-pieces: `underground_lake` (a basin to one side of the way through, wadeable, with water and
glow), `daylight_shaft` / `collapsed_shaft` (a hole to the sky, the sun's shaft, dust, ferns; the
collapsed one with a mound of fallen roof under it), `chasm_bridge` (a 9 m rift across the room,
crossed by a rope-and-plank bridge or a span of the rock; a fall is caught and stood back at the
near end), `lava_chasm` (the same with lava 4 m down and its light), `ledge` (a shelf 3 m up along
a wall with a ramp and a rail: archers stand on it), `forge_hall`, `ossuary` (rows of niches with
bones), `barracks`, `cellar_store`, `fungus_grotto`, `obsidian_grotto`, `ore_gallery`,
`boss_arena` (always on the boss room: four pillars, braziers or lava vents, the fog gate).

## 4. What every inside gets

- **A loop**, not a line: the walk is laid as a descending spiral (every turn the same way), so the
  rooms come back round and two rooms not next to each other are joined; where none can be, a side
  room is laid bridging two rooms one apart. A loop whose rooms are 2.5-4.5 m apart in height may
  end on a ledge over the lower room: a drop, one way down (rare in practice: see Known limits).
- **Levels**: rooms step down (or up) along the walk, passages are ramps no steeper than 27 degrees
  (built kinds dress them as stairs), ledges and pillars stand in big rooms.
- **A secret**: a small room off a mid-walk chamber, behind loose stones (a `SiteSeal`: "Pull the
  loose stones away"), with the rich chest.
- **The way back out**: a passage from the boss room to the entrance (or the room after it),
  barred on the entrance side; the bar lifts only from the boss's side ("Lift the bar"), and stays
  lifted (the flag `site_open/<interior>/shortcut`).
- **The way out** at the entrance: a rock site's is a short throat climbing to daylight, a built
  one's a door in a stone frame; the arrival stands a few paces inside, facing in.
- **People** where they would be: a pair on guard in most chambers, sleepers by a camp's fire,
  archers on a ledge, an ambusher in a passage, one walking the round between the second and
  fourth rooms, the heavy and his men in the hall, the boss in its arena behind a fog gate (not
  stood up again once `boss_deed/<id>` is set). They walk a navigation mesh baked from the rock.
- **Loot**: the kind's container (chest, crate, sarcophagus) in camps and halls and a third of the
  chambers, the rich table in the secret room, `boss_loot` in the boss room; ids are stable
  (`<interior>/<room>/<n>`) so what was taken stays taken.
- **Quest things**: an `item` feature, and anything a quest places in this interior, go through
  `QuestItems.raise_in_interior` with the rooms as its chambers (a `treasure`/`secret` room is the
  default spot).

## 5. How it is built (and paced)

1. `SitePlan.make(def)` (pure data, a few ms): rooms, links, the rock's carve/fill ops, spots,
   foes, containers. Deterministic from `site.seed`.
2. `SiteField.build(...)`: the ops as a signed distance field on a 0.5-0.55 m grid, evaluated only
   inside each op's box, meshed by surface nets into 14 m chunks (each a mesh, and its faces its
   collision: what you see is what you stand on). On a **worker thread**; the result is cached in
   `user://site_cache/<id>_<hash>.bin` (keyed by the ops, so editing the def rebuilds it). An
   entrance's dressing calls `SiteInterior.prefetch` when its cell is raised, so the rock is
   usually ready before the door is opened.
3. `SiteInterior` stands the way in and a slab of floor at once, holds the body there until the
   rest is built, then adds chunks, dressing (`SiteDress`), the navigation mesh (baked off the main
   thread) and the foes, each piece within `WorldPace`'s budget. Headless (tests, tools) it all
   happens in one go.

Measured (test_sites, loaded 4-core box): the rock for a 9-room site 1-3 s on a worker; the paced
main-thread pieces at most 8-13 ms; a foe stood up 17-56 ms (the Enemy's own body, as anywhere).

## 6. Sizing and placing

- A `delve` needs a slope or flat ground about 25 m round; `radius_m` 20-24.
- A fort needs `radius_m` at least `site.radius + 8` (19 m walls on a 30 m pad). Pick ground under
  about 8 degrees; the walls follow the ground in 4 m bays with one walkway level, so a steep pad
  makes one side tall.
- Keep the inside's `size` to the site's importance: `medium` for a hideout, `large` for a region's
  landmark, `huge` only for a questline's end.
- Two sites' insides never meet (each interior has its own pocket), so size is free of the map.

## 7. The world build

A POI written after the world was built has no flattened pad: `WorldPois.unbuilt_entries` dresses
it on the ground as it stands (the runtime pad). The next world build flattens it, but
`tools/world/build_world.py` reads only `pois/pois.json`: once 0-A's per-region split lands,
make sure it reads every file in `pois/` (including `_interiors_showcase.json`), or move these
entries into the region files. Until then the showcases are dressed on unflattened ground, and
scatter (trees, rocks) the build put there may stand inside the fort's yard.

## 8. Testing a site

```
./run.sh test --filter=test_sites        # every kind's layouts; the showcases walked, entered, left, saved
```

- Add your interior to `SHOWCASE` in `test_sites.gd` (or copy its walk test) to have it built,
  stood on, walked on its navigation mesh from the way in to every room, and left.
- Render it (Compatibility) and look at every room before calling it done:
  ```
  xvfb-run -a -s "-screen 0 1280x720x24" $GODOT --path game --rendering-driver opengl3 \
    --audio-driver Dummy --resolution 1280x720 res://tools_gd/site_review.tscn -- \
    --site=core:interior/<id> --out=/abs/dir          # or --poi=core:poi/<id>[,...] for an outside
  python3 tools/capture/contact_sheet.py /abs/dir --out docs/review/sites/<id>.jpg --cols 4
  ```
  and the outside on the real ground: `./run.sh shots tools/capture/plans/sites_showcase.json`
  (copy its shots, change the place ids).
- Things to look for: a room with nothing lit, a white or untextured shape, a prop in a doorway, a
  foe inside rock, a set-piece that does not read. The contact sheets for the two showcases are in
  `docs/review/sites/`.

## 9. Known limits

- Drops (a loop ending on a ledge over the lower room) are supported but the spiral rarely
  produces the height difference; write `drop` on rooms to get one.
- The "rock" style's walls are smooth at 0.55 m: detail comes from the shader and props. Very
  small rooms with high noise can pinch shut; keep `tight` for passages.
- A fort's garrison stands up again when its cell is raised again (as any POI's encounter does);
  killed foes are not remembered across streaming.
- Lights: the pocket's own OmniLights, up to three or four a room plus glow. Compatibility draws at
  most 12 per mesh, so chunks are 14 m and `SiteDress._light_budget` draws in the widest lights
  until no chunk is reached by more than 11 (tested). In the Kilnway's review render the view from
  the way in straight into the mouth room still comes out unlit (the same room is lit seen from its
  other doorway, and physics has the arrival inside the room): not yet explained, worth a look on
  Forward+ and in the game with the player's own light.
- The lava tube reads red and dark; the keep's undercroft reads as cut chalk rather than ashlar.
