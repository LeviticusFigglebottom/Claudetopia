# tools/world — the world builder

Deterministic, numpy-only generation of everything the overworld is made of. Nothing here
imports Godot; the engine side is `game/tools_gd/import_terrain.tscn` and `game/world/`.

```
build_world.py            the pipeline (CLI below)
gen_terrain_textures.py   the 21 terrain textures of docs/CONTRACTS.md §5
scatter_rules.json        flora/rock keys -> asset names, densities and habitat rules
worldgen/
  grid.py       coordinate conventions: x east, z south, origin at the centre
  noise.py      spectral (FFT) fractal fields: periodic, band-limited, seeded
  regions.py    weighted, domain-warped Voronoi membership and blend weights
  heights.py    per-shape height synthesis, the Mere, the world edges, drainage
  erosion.py    sink filling, D8 flow accumulation, valley carving
  hydro.py      river tracing and carving, water mask, water level, flow, moisture
  roads.py      place pads and the graded road network
  paths.py      least-cost routes on a coarse lattice (scipy Dijkstra)
  surface.py    texture control maps and the region colour map
  cells.py      scatter placement into 256 m cells
  output.py     the writers for docs/CONTRACTS.md §6
tests/test_build.py       builds a 1024 world in a temp dir and checks the outputs
```

## Running it

```
tools/world/build_world.py                  # full build: 4096² at 2 m, about 3 minutes
tools/world/build_world.py --size 1024      # 8 m test build, about 25 seconds
tools/world/build_world.py --only textures  # re-do one stage (heights | textures | cells)
tools/world/build_world.py --seed 99 --out /tmp/w
tools/world/gen_terrain_textures.py [slots...] [--size 1024]
python3 tools/world/tests/test_build.py
```

`./run.sh world` runs the builder and then the in-engine Terrain3D import.

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
6. **Pads** at every place (radius by kind), raised above standing water so a stilt-town
   stands on peat rather than in a pool.
7. **Rivers**: least-cost downhill routes (the Skerrow water into the Mere, the Mere's
   outflow west to the sea, the Larkbourne and the Briarwold fall-water), carved with a
   monotone surface profile, banks and widths of 4–14 m.
8. **Roads**: a minimum spanning tree over the settlements plus a few ring links, routed by
   slope cost, graded to ≤ 11% and cut 4–6 m wide with shoulders.
9. **Surface**: every terrain slot gets a weight from region membership, slope, height,
   moisture, roads and noise; the two strongest become base and overlay with a blend value.
   The colour map is the region palette as a chroma-only tint so the textures still set the
   value.
10. **Cells**: scatter by `scatter_rules.json`, thinned by slope, moisture, height, clustering
    noise and the road/pad/water exclusions, bucketed into 32×32 cells of 256 m.

Everything is a pure function of the seed in `game/content/packs/core/world/world.json`.
