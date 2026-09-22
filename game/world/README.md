# world/ — terrain, water, streaming

Purpose: the overworld. Holds the built terrain, answers every question about the ground,
keeps the water surfaces, and streams 256 m cells around whoever is moving.

```
world.tscn / world.gd     World (Node3D, `World.instance`): builds and owns everything below
terrain_provider.gd       TerrainProvider: heights, normals, regions, water (see below)
world_streamer.gd         WorldStreamer: cell rings, MultiMesh scatter, POI scenes
water_surface.gd          WaterSurface: the Mere, the Grey Sea, marsh pools, river ribbons
fly_camera.gd             FlyCamera: stand-in for the player; the capture and smoke runners' eye
pois/                     WorldPois: what stands at the points of interest (see below)
generated/                world builder output (gitignored; `./run.sh world` writes it)
terrain_assets.tres       Terrain3DAssets: the 21 terrain slots of docs/CONTRACTS.md §5
```

## Where the data comes from

1. `tools/world/build_world.py` writes `game/world/generated/` (docs/CONTRACTS.md §6) —
   heights, region mask, texture control maps, colour, water, flow, rivers, roads, POIs,
   one JSON per cell, plus small `runtime/` copies of heights/regions/water for queries.
2. `game/tools_gd/import_terrain.tscn` (headless) turns those maps into Terrain3D region
   files under `game/terrain_data/` (16 regions of 1024 texels at 2 m = 2048 m each) and
   writes `terrain_assets.tres`.
3. `world.tscn` loads both at runtime. `./run.sh world` does steps 1 and 2; `./run.sh`
   does them for you when the manifest is missing.

## TerrainProvider

The one place to ask about the ground. Heights and normals come from Terrain3D when it is
loaded and from the low-resolution runtime copy otherwise, so tools and tests work headless
and without terrain data.

```gdscript
var t := World.terrain()
t.get_height(x, z) -> float          # metres above sea level
t.get_normal(x, z) -> Vector3        # unit surface normal
t.get_slope(x, z) -> float           # radians
t.region_id_at(x, z) -> String       # "" over open water
t.nearest_region_id_at(x, z)         # never "": open water answers with the nearest land
t.is_water(x, z) -> bool
t.water_level_at(x, z) -> float      # TerrainProvider.NO_WATER (-1000) where there is none
t.water_depth_at(x, z) -> float
t.max_height_around(x, z, radius)    # for vantage points
```

## WorldStreamer

Ring 0 (3×3 cells) is full detail: POI scenes plus every scatter MultiMesh. Ring 1 (5×5)
keeps MultiMesh instances only, at `far_density` (45%) with shadows off and a shorter LOD
cut-off. Cell JSON is parsed on the worker pool; scene-tree work is capped at
`cells_per_frame` per frame. Scatter assets that the forge has not made yet are skipped with
exactly one warning each. Emits `EventBus.cell_loaded` / `cell_unloaded`, and calls
`GameState.enter_region` when the target crosses a boundary.

## WorldPois

`pois/world_pois.gd` is the `Pois` node in `world.tscn`, beside `Doors`. It indexes every
`pois.json` entry a builder can dress — the 48 POIs of the registry plus the places whose
`shrine` tag promises a Hearthstone — by the cell it stands in, and `WorldStreamer._build_cell`
asks it for that cell's dressings and parents them to the cell node. So a dressing streams and
culls with the ring system; in the far ring only its silhouette pieces are built, with no
lights, no collision and no Hearthstone.

`PoiDressing` raises one POI: deterministic from its id, positioned from the built data, with
its `unique_feature` as the brief. `PoiBuilders` holds one builder per kind, `PoiKit` finds the
forge's assets and stands them on the real ground with their own collision, and `PoiMasonry`
builds what the forge has no asset for (drums of courses, arches, plank decks, steps, mounds,
pools, falling-water sheets) as one mesh per material. `tests/unit/test_pois.gd` pins that
every POI raises a mesh, a body and the Hearthstone its data promises, that it is the same
twice, and that a quest's `rest_at` target always has a stone.

`pois/quest_items.gd` (`QuestItems`, a world service installed by `GameServices`) puts down what
the quests send you to pick up: in a near cell after its dressings, so a thing can lie on a
marker the dressing put down (`PoiKit.marker`: the Tumbled Watch's `fallen_stair`, the Clanless
Camp's `the_chimes`), and inside a house or a deep place as `HouseInterior`/`CaveInterior` build
it. A deep place's `item` features are pickups through it too, except a boss's own drop. What has
been taken is its save section, `quest_items`. See systems/quests/README.md.

## WaterSurface

One subdivided sheet spans the world; its vertices take their height from the builder's water
level map and its fragments discard where the water mask is empty, so the lake, the sea and
the marsh pools are one draw call at their own levels. Rivers are ribbon meshes built from
`rivers.json`, each following its own falling surface profile. `painted_water.gdshader` uses
no depth or screen texture, so it behaves the same on Compatibility as on Forward+.

Region colour comes from `WaterSurface.REGION_WATER` and follows `EventBus.region_entered`.

## Atmosphere

`world.gd` instances `systems/atmosphere/atmosphere.tscn` as the child named `Atmosphere`;
sky, sun, weather, fog and the save section `world` belong to that system, not to this one.
