# tools/world — the world builder

Deterministic, numpy-only generation of everything the overworld is made of, from an authored
atlas. Nothing here imports Godot; the engine side is `game/tools_gd/import_terrain.tscn` and
`game/world/`.

```
build_world.py            the pipeline (CLI below)
atlas/atlas.json          the geography as somebody drew it: provinces, coast, ranges, peaks,
                          valleys, rivers, lakes, forests, roads and the start
atlas/SCHEMA.md           what every field of the atlas means to the builder
atlas/atlas.schema.json   the same as JSON Schema; atlas/check_atlas.py checks an atlas
atlas/render_build.py     a built world's heights, roads and rivers with its atlas drawn over them
gen_terrain_textures.py   the 21 terrain textures of docs/CONTRACTS.md §5
scatter_rules.json        flora/rock keys -> asset names, densities and habitat rules, what each
                          kind of wood is made of, and the `cover` recipe's patch over them
                          (applied only with --recipe cover)
worldgen/
  grid.py       coordinate conventions: x east, z south, origin at the centre
  noise.py      spectral (FFT) fractal fields: periodic, band-limited, seeded
  atlas.py      loading and checking an atlas (its schema, and what a schema cannot say)
  geography.py  the atlas as fields: province weights, each province's hills in its character,
                ranges, peaks, valleys, the coast, the lakes and causeways, the woods
  regions.py    the content packs' regions; a RegionDef per province, and the membership field
  heights.py    the land composed from the atlas, drainage, and the full-resolution detail band
  landforms.py  each province's landforms at a walking scale (raised beaches, dune ridges, levees,
                oxbows, the granite stair, tors, scars, shakeholes, buried streets, lynchets,
                barrows), laid on after the roads and off them
  erosion.py    sink filling, D8 flow accumulation, valley carving
  hydro.py      the atlas's rivers in valleys they have cut, carved with falling surfaces; water
                mask, water level, flow, moisture; and keep_channels, which cuts every river back
                through the pads and roads laid on it
  roads.py      place pads and the atlas's roads: routed through their via points with priced
                grades and turns, graded within the carve's own tolerance of the ground
  paths.py      least-cost routes on a coarse lattice (scipy Dijkstra)
  surface.py    texture control maps and the region colour map
  cells.py      scatter placement into 256 m cells
  fields.py     the enclosed parcels: one pattern, or one per enclosed landform (`cover`)
  hedges.py     hedgerows and walls on the parcel boundaries, orchards; with `cover`, the fell
                wall, willow lines along the marsh water, wall stubs along Cinderlea's streets
  roadside.py   milestones, signposts, and frontage: post and rail, or by region (`cover`)
  output.py     the writers for docs/CONTRACTS.md §6
tests/test_atlas.py       the atlas checker, one mistake at a time, and the committed atlas
tests/test_atlas_world.py a small world built from the atlas is the land it draws; a drawn wood
                          is planted
tests/test_build.py       builds a 1024 world in a temp dir and checks the outputs
tests/test_roads.py       the road profile, router and channels, and every road and river of the
                          built world (road_profiles.json is written for it; nothing else reads it)
tests/test_sightlines.py  the 90 authored sightlines over the built world
tests/test_recipes.py     the cover recipe stays off by default and still builds when asked for
```

## Running it

```
tools/world/build_world.py                  # full build: 4096² at 2 m, about 3 minutes
tools/world/build_world.py --size 1024      # 8 m test build, about 25 seconds
tools/world/build_world.py --only textures  # re-do one stage (heights | textures | cells)
tools/world/build_world.py --seed 99 --out /tmp/w
tools/world/build_world.py --atlas other.json --out /tmp/w  # another atlas
tools/world/build_world.py --recipe cover   # the part that is off by default
python3 tools/world/atlas/check_atlas.py [atlas.json]
python3 tools/world/atlas/render_build.py --world /tmp/w --out /tmp/map.png
tools/world/gen_terrain_textures.py [slots...] [--size 1024]
python3 tools/world/tests/test_build.py
```

`./run.sh world` runs the builder and then the in-engine Terrain3D import, and passes its
arguments to the builder (`./run.sh world --recipe cover`).

**Recipes** (`build_world.RECIPES`) are parts of the world that are built and measured but not
yet accepted into the default build; the manifest's `recipes` says which a build made. `cover`
is the `cover` block of `scatter_rules.json`, the per-landform field patterns, the fell wall,
the waterside and ruin lines, frontage by region and the Briarwold's holloways. What it measured
is in PROGRESS.md under "The shape of the land" and "The shape of the land, looked at". The
landforms were a recipe; they are the atlas's now, listed province by province.

## How the land is made

Where everything is comes from the atlas (`atlas/atlas.json`, `atlas/SCHEMA.md`); the seed only
breaks up the detail between its lines. A build checks the atlas first and refuses one with
errors.

1. **Provinces.** Each province's polygon becomes a weight field, blended across its border over
   its `blend_m` and wandering by a few tens of metres of noise; the owner of a texel is the
   province it is deepest inside. A province belongs to a content region (what the game calls the
   place you are standing in; `region_mask.u8` holds the region) and has a biome (its textures,
   flora, rocks and colour: the six shapes the old regions had).
2. **Land.** Each province's low ground (`base_height_m`) with its hills rising `relief_m` over it
   in its character (flat, marsh, rolling, hills, ridged, plateau, mountains), blended by the
   weights; then the ranges at their crest heights, the peaks, and the valleys cut in.
3. **Coast and lakes.** Outside the coast the land falls to the seabed, with beaches, or cliffs
   along a `cliffs` path; each lake is carved to its bed at its own level, its shores raised a
   little over it and its islands stood up in it.
4. **Drainage.** Sinks are filled, D8 flow accumulation computed, and the network cut into the
   land by biome, down to the sea and the lakes; then the coast and the lakes are laid again, so
   the drawn water wins; then the causeways are raised across the lakes they cross. The water is
   routed over the land plus five metres of broad unevenness (`heights.ROUTE_JITTER_M`), so a
   slope drawn as one even plane gathers into gills a few hundred metres apart instead of being
   combed with rills down the fall line (`tests/test_erosion.py`).
5. **Pads** at every place and POI (radius by kind), raised above standing water so a
   stilt-town stands on peat rather than in a pool. A staged build (`--only textures|cells`)
   refuses to reuse a heightmap whose pads were laid for places that have since moved. Then the
   authored sightlines: where the land stands into one by no more than a saddle's depth
   (`geography.NOTCH_MAX_M`, 25 m) it is cut down under the line; a line with more than that in
   the way is left, and the build says how many (it is the atlas's or the content's to answer).
6. **Rivers** along the atlas's paths, each in a valley it has cut, carved with a surface that
   falls from its source to the water it runs into (a tributary to its river's level at the
   confluence), banks and widths from the atlas.
7. **Roads**: the atlas's list, each routed from its start through its via points to its end on
   a 16 m lattice and again on a 4 m one with grade priced the same both ways, quadratically past
   10%, and every change of heading priced, so a road goes round a hill or zigzags up it; a
   causeway's legs over a lake are laid straight on their bank. The profile follows the ground
   within `cut_fill_m(width)` (2.4–3.6 m), never lifted to make a grade (with `cover`, the
   Briarwold's lanes run sunk as holloways). Streets are laid through every settlement, the
   roads cut 3.5–6 m wide with shoulders, then the pads again, then the rivers are cut back
   through both (a road crossing is a ford). No road builds up inside 14 m of an authored
   sightline.
8. **Landforms**, each province's own, laid on last and held off the roads, the pads and the
   authored sightlines, and never dug below a lake's water beside it. Then each shelf's seaward
   edge is broken (`geography.break_shelf_edges`): the drawn line wanders up to 7 m in and out,
   blocks fallen from the face lie at its foot, and each of its `notches` is cut down into the
   sea; no pad is touched.
9. **Surface**: every terrain slot gets a weight from biome membership, slope, height,
   moisture, roads and noise; the two strongest become base and overlay with a blend value.
   The colour map is each region's palette as a chroma-only tint so the textures still set the
   value.
10. **Cells**: scatter by `scatter_rules.json` province by province, plus the atlas's woods,
    thinned by slope, moisture, height, clustering noise and the road/pad/water exclusions,
    bucketed into 32×32 cells of 256 m.

The seed in `game/content/packs/core/world/world.json` drives only noise: how a hillside is
broken, where a copse stands in a field. Two builds of one atlas are the same world.
