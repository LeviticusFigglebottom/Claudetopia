# world/ — terrain, water, streaming

Purpose: the overworld. Holds the built terrain, answers every question about the ground,
keeps the water surfaces, and streams 256 m cells around whoever is moving.

```
world.tscn / world.gd     World (Node3D, `World.instance`): builds and owns everything below
world_status.gd           WorldStatus: is there a world on disk, and what can draw its ground
terrain_provider.gd       TerrainProvider: heights, normals, regions, water (see below)
fallback_terrain.gd       FallbackTerrain: the ground from the runtime map when Terrain3D cannot
fallback_terrain.gdshader   draw it (see below)
world_streamer.gd         WorldStreamer: cell rings, MultiMesh scatter, POI scenes
water_surface.gd          WaterSurface: the Mere, the Grey Sea, marsh pools, river ribbons
fly_camera.gd             FlyCamera: stand-in for the player; the capture and smoke runners' eye
pois/                     WorldPois: what stands at the points of interest (see below)
generated/                world builder output; the part the game reads is tracked (.gitignore)
terrain_assets.tres       Terrain3DAssets: the 21 terrain slots of docs/CONTRACTS.md §5
```

## When there is no world, or nothing to draw its ground

`WorldStatus.current()` reads what is on disk and what the engine loaded and says one of three
things, and the title screen, boot's `--new-game`/`--load`, the Naming, the capture runner and the
world itself all ask it before going in:

* **missing** — no manifest, no runtime maps or no cells. Nothing enters the world: the title
  screen shuts New Game, Continue and Load and says what is missing, with `./run.sh world` and
  what that needs; a world scene entered anyway (the editor's Play Scene) stands down with the
  same notice and a way back to the title.
* **fallback** — the country is there but Terrain3D cannot draw it: no library for this machine
  (see LICENSES.md), Mesa's software Vulkan driver under Forward+ or Mobile (Terrain3D 1.0.2
  crashes it on its first frame, inside the driver's rasterizer threads), no regions in
  `game/terrain_data` (the command named is `./run.sh terrain` when the full-resolution maps are
  here, `./run.sh world` when they are not), regions that load as nothing, or
  `-- --terrain=fallback`. `FallbackTerrain` draws the ground. Unless the player asked for it, it
  is said where it cannot be missed (`GroundNotice`): across the title sheet with the way to the
  full terrain, on a card across the top of the view once the region's name has gone, and on a
  "Coarse ground" plate in the top left corner for as long as the HUD is up. A toast used to say
  it once, and a player on Windows took the coarse ground for the game's look.
  `-- --terrain=terrain3d` tries Terrain3D even on the driver it crashes.
* **ready** — Terrain3D and its regions.

`FallbackTerrain` is 256 chunks of 512 m sharing one flat 64 x 64 grid with a skirt, lifted in the
vertex shader from the 8 m runtime height map, with four index LODs Godot's mesh LOD picks from.
The surface is the region's own terrain textures (albedo and normal arrays at 512 px), tinted by
its palette the way the builder's colour map is, with slope, height bands, water, snow and the
roads (stamped at 2 m from `roads.json`). Collision is a HeightMapShape3D per chunk on the world
and terrain layers. The mesh, the collision and `TerrainProvider.get_height` split every quad the
same way, so a body stands on what is drawn; scatter placed on the 2 m ground is set down on the
8 m one as each cell arrives. It is coarser than Terrain3D and honest about it: softer hills,
terraces and cliffs rounded off, no field patchwork.

## Where the data comes from

1. `tools/world/build_world.py` writes `game/world/generated/` (docs/CONTRACTS.md §6) —
   heights, region mask, texture control maps, colour, water, flow, rivers, roads, POIs,
   one JSON per cell, plus small `runtime/` copies of heights/regions/water for queries.
2. `game/tools_gd/import_terrain.tscn` (headless) turns those maps into Terrain3D region
   files under `game/terrain_data/` (16 regions of 1024 texels at 2 m = 2048 m each) and
   writes `terrain_assets.tres`.
3. `world.tscn` loads both at runtime. `./run.sh world` does steps 1 and 2 (it finds Godot
   before it builds, since step 2 needs it), `./run.sh terrain` does step 2 alone, and `./run.sh`
   does them for you when the manifest or the regions are missing, with a banner when step 2
   cannot run. What the game reads of step 1 and all of step 2 are tracked, so a clone does not
   need to (README.md, "Run it").

The runtime height map is a block mean of 4 x 4 full texels, so its texel (i, j) is centred at
`origin + 8 (i, j) + 3 m`, not on the origin; the region, water and level maps are point samples
and sit on it. `TerrainProvider` reads the offset from the manifest's two grids (or from
`runtime.height_offset_m` if the builder ever writes it).

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
