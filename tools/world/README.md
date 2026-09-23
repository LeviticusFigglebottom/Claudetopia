# tools/world — the world builder

Deterministic, numpy-only generation of everything the overworld is made of. Nothing here
imports Godot; the engine side is `game/tools_gd/import_terrain.tscn` and `game/world/`.

```
build_world.py            the pipeline (CLI below)
gen_terrain_textures.py   the 21 terrain textures of docs/CONTRACTS.md §5
scatter_rules.json        flora/rock keys -> asset names, densities and habitat rules, and the
                          `cover` recipe's patch over them (applied only with --recipe cover)
worldgen/
  grid.py       coordinate conventions: x east, z south, origin at the centre
  noise.py      spectral (FFT) fractal fields: periodic, band-limited, seeded
  regions.py    weighted, domain-warped Voronoi membership and blend weights
  heights.py    per-shape height synthesis, the Mere, the world edges, drainage
  landforms.py  each region's own landform at a walking scale (raised beaches, levees, the
                granite stair, scars and shakeholes, the Builders' streets, lynchets and barrows);
                the `landforms` recipe, off by default
  erosion.py    sink filling, D8 flow accumulation, valley carving
  hydro.py      river tracing and carving, water mask, water level, flow, moisture; and
                keep_channels, which cuts every river back through the pads and roads laid on it
  roads.py      place pads and the road network: routed with priced grades and turns, graded
                within the carve's own tolerance of the ground
  paths.py      least-cost routes on a coarse lattice (scipy Dijkstra)
  surface.py    texture control maps and the region colour map
  cells.py      scatter placement into 256 m cells
  fields.py     the enclosed parcels: one pattern, or one per enclosed landform (`cover`)
  hedges.py     hedgerows and walls on the parcel boundaries, orchards; with `cover`, the fell
                wall, willow lines along the marsh water, wall stubs along Cinderlea's streets
  roadside.py   milestones, signposts, and frontage: post and rail, or by region (`cover`)
  output.py     the writers for docs/CONTRACTS.md §6
tests/test_build.py       builds a 1024 world in a temp dir and checks the outputs
tests/test_roads.py       the road profile, router and channels, and every road and river of the
                          built world (road_profiles.json is written for it; nothing else reads it)
tests/test_sightlines.py  the 90 authored sightlines over the built world
tests/test_recipes.py     the recipes stay off by default and still build when asked for
```

## Running it

```
tools/world/build_world.py                  # full build: 4096² at 2 m, about 3 minutes
tools/world/build_world.py --size 1024      # 8 m test build, about 25 seconds
tools/world/build_world.py --only textures  # re-do one stage (heights | textures | cells)
tools/world/build_world.py --seed 99 --out /tmp/w
tools/world/build_world.py --recipe landforms --recipe cover   # the parts that are off by default
tools/world/gen_terrain_textures.py [slots...] [--size 1024]
python3 tools/world/tests/test_build.py
```

`./run.sh world` runs the builder and then the in-engine Terrain3D import, and passes its
arguments to the builder (`./run.sh world --recipe landforms --recipe cover`).

**Recipes** (`build_world.RECIPES`) are parts of the world that are built and measured but not
yet accepted into the default build; the manifest's `recipes` says which a build made.
`landforms` is `worldgen/landforms.py`; `cover` is the `cover` block of `scatter_rules.json`,
the per-landform field patterns, the fell wall, the waterside and ruin lines, frontage by
region and the Briarwold's holloways. What each measured, and what is still to check before it
becomes default, is in PROGRESS.md under "The shape of the land".

## How the land is made

1. **Regions.** Each region's `map` block (centre, radius) becomes a weighted Voronoi cell
   in a domain-warped plane, so borders wander; named places pull their own region toward
   them. Softmax over the scores gives blend weights (borders read over 300–500 m).
2. **Shapes.** One height field per `map.shape` — `downs`, `lake_basin`, `delta`,
   `forest_rise`, `mountains`, `ash_plateau` — blended by those weights. Fields are
   broadband (low-passed) rather than narrow-band, which is the difference between hills and
   sine ripples.
3. **The Mere.** Carved below the lake level with shingle shores, a cliff step on the north
   shore, the black island of Tollmere and the Long Stride causeway to the south shore.
4. **Edges** (DESIGN.md §4.2): the mountain wall north with the Windgate notch, the
   Thornmarch rampart east, cliffs down to the Hush south, tide-flats and the Grey Sea west.
5. **Drainage.** Sinks are filled, D8 flow accumulation is computed, and the resulting
   network is cut into the land per region (deep in the karst, barely at all in the marsh).
   This is what makes the valleys dendritic instead of mazy — and what the rivers then find.
   With the `landforms` recipe, then each region's **landform** (`landforms.py`), held off the
   ground under every place and never raised along an authored sightline.
6. **Pads** at every place (radius by kind), raised above standing water so a stilt-town
   stands on peat rather than in a pool. A staged build (`--only textures|cells`) refuses to
   reuse a heightmap whose pads were laid for places that have since moved.
7. **Rivers**: least-cost downhill routes (the Skerrow water into the Mere, the Mere's
   outflow west to the sea, the Larkbourne and the Briarwold fall-water), carved with a
   monotone surface profile, banks and widths of 4–14 m.
8. **Roads**: a minimum spanning tree over the settlements plus a few ring links, routed on a
   16 m lattice and again on a 4 m one with grade priced the same both ways, quadratically
   past 10%, and every change of heading priced, so a road goes round a hill or zigzags up
   it. The profile follows the ground within `cut_fill_m(width)` (2.4–3.6 m), never lifted
   to make a grade (with `cover`, Briarwold's lanes run sunk as holloways). Cut 4–6 m wide
   with shoulders, then the pads again, then the rivers are cut back through both (a road
   crossing is a ford). No road builds up inside 14 m of an authored sightline.
9. **Surface**: every terrain slot gets a weight from region membership, slope, height,
   moisture, roads and noise; the two strongest become base and overlay with a blend value.
   The colour map is the region palette as a chroma-only tint so the textures still set the
   value.
10. **Cells**: scatter by `scatter_rules.json`, thinned by slope, moisture, height, clustering
    noise and the road/pad/water exclusions, bucketed into 32×32 cells of 256 m.

Everything is a pure function of the seed in `game/content/packs/core/world/world.json`.
