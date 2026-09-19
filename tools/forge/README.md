# tools/forge — the asset forge

Every mesh and texture in Wickmere is made here (DESIGN.md §7, ARCHITECTURE.md §7).
Blender 4.0 runs headless driven by Python; leaf, grass and flower textures are drawn
directly with PIL. Nothing third-party is used or downloaded.

## Build

```
./run.sh assets                       # everything missing or stale
./run.sh assets -- --only trees       # one category, generator, palette or name
./run.sh assets -- --jobs 2 --force   # rebuild everything, two Blender processes
./run.sh assets -- --list             # what would be built, and what is current
python3 tools/forge/make_manifest.py  # regenerate manifest.json from the tables
python3 -m unittest discover -s tools/forge/tests -t tools/forge
```

A single asset, for iterating:

```
blender -b --python tools/forge/gen_trees.py -- \
    --kind oak --palette hearthvale --seed 101 --variant a --out game/assets/models
blender -b --python tools/forge/gen_props.py -- --list      # every kind a generator knows
FORGE_TRACE=1 blender -b ...                                 # per-stage and per-bake timings
```

`--quick` halves texture size, skips ambient occlusion, LODs and impostors. It is for
checking that a generator runs, never for committed output.

## Review

```
godot --headless --path game --import
xvfb-run -a -s "-screen 0 1600x900x24" godot --path game --rendering-driver opengl3 \
  --audio-driver Dummy --resolution 1600x900 res://tools_gd/asset_review.tscn -- \
  --category=trees --out=$PWD/captures/assets/trees --per-shot=3
python3 tools/forge/contact_sheet.py captures/assets/trees --cols 3
```

`--lod=1` or `--lod=2` reviews a LOD level; `--turntable=8` adds a turn; `--only=oak`
filters. Exposure is fixed in the scene (`tonemap_white ≈ 6`, sun ≈ 1.0): on the
Compatibility renderer anything brighter clips mid-greys to white.

## Layout

| File | What it is |
|---|---|
| `lib/palette.py` | region palettes from the content pack, and the role model (light, dark, accent, warm, cool, green, earth, mid) every generator tints with. Pure Python. |
| `lib/cli.py` | argument parsing, output paths, seeds, asset hashing, `FORGE_VERSION`. Pure Python. |
| `lib/glb.py` | minimal GLB reader/writer; points materials at the external PNGs and drops the embedded copies. Pure Python. |
| `lib/scene.py` | Blender scene setup, primitives, lathes, tubes, modifiers, jitter. |
| `lib/build.py` | joinery shared by props, architecture and landmarks: boards, turned legs, iron straps, wattle, drystone courses, cloth. |
| `lib/materials.py` | the painterly PBR node-material library. |
| `lib/textures.py` | drawn alpha atlases: leaf clusters, blades, fronds, flowers, moss, fungus, lily pads. |
| `lib/tree.py` | Sapling wrapper: growth, resolution caps, leaf cards, buttresses, hanging cards. |
| `lib/impostor.py` | renders an object to an RGBA billboard and builds crossed cards (tree LOD2). |
| `lib/bake.py` | UV unwrap, Cycles CPU bake to albedo / normal / ORM. |
| `lib/export.py` | LODs, collision, glTF export, `meta.json`, Godot `.import` sidecars. |
| `lib/runner.py` | the shared `main()` most generators use. |
| `gen_*.py` | the generators. `--list` prints their kinds. |
| `make_manifest.py` | writes `manifest.json` from readable tables. |
| `build_assets.py` | the incremental, parallel build. |
| `contact_sheet.py` | tiles review renders into one sheet per category. |

## How a material is painterly

Not a mood — a recipe, in `materials.py`. Every surface is four layers:

1. **paint blocks**: large soft colour patches through a three- or four-stop ramp, so the
   surface is blocked in like a painting rather than filled with noise;
2. **a pattern**: planks, courses, fissures, weave, tile rows — medium scale, soft edges;
3. **edge wear**: convex edges lightened via `Pointiness`, broken up by noise so the wear
   is not a uniform outline;
4. **cavity dirt**: concave areas darkened with the Ambient Occlusion node (or the free
   curvature term where AO rays are not worth their cost).

Plus directional brush `strokes` and, where it applies, ground grime rising from the base.
The finest layer is a low-contrast grain; there is no photographic micro-noise anywhere.

Every builder takes a `Palette` and mixes a role colour into its base tones by a small
`tint`, so the same generator gives a Hearthvale oak fence or a Briarwold black-ash one:
the region changes the palette, not the language.

## Contracts this keeps

* Output layout, categories, collision kinds and texture names: `docs/CONTRACTS.md` §4.
* Metres, models facing -Y in Blender, ~1.1× chunky props: `docs/CONTRACTS.md` §1.
* Triangle budgets and the style contract: `DESIGN.md` §7.0.
* Materials are Principled BSDF only, so Godot imports them as `StandardMaterial3D`;
  foliage materials are named `*_foliage` and `tools_gd/glb_post_import.gd` swaps in
  `assets/shaders/foliage_wind.gdshader`.

## Unwrapping: one strategy does not fit every shape

`bake.unwrap` takes a mode, and generators choose it, because the default is wrong for
most of what the forge makes:

| Shape | Mode | Why |
|---|---|---|
| crates, tables, walls, panelled props | `smart` | flat faces give a few large islands |
| boulders, scree, bones, lathed stones | `sphere` | smart project degenerates to ~900 face-sized islands at 43% coverage on a displaced blob; a sphere gives 3 islands at 81% |
| tree trunks | `cylinder` | bark is a repeating surface, and a branching trunk makes ~4600 islands whose seams bloat the export |

Two traps worth knowing, both of which produced black models before they were found:

* joining a Blender primitive (which carries a UV layer) with bmesh-built geometry (which
  does not) yields an object that *has* a UV layer while half its faces sit at (0, 0), so
  a "unwrap only if missing" check silently skips the unwrap. `bake_atlas` always
  unwraps unless the caller says the UVs are authored;
* the AO bake traces against the whole scene, so a tree's leaf cards or a billboard
  standing next to the model both falsify the occlusion and make the bake an order of
  magnitude slower. `bake_atlas` hides everything but its subject.

## Costs and weight (this container, 4 contended cores)

Roughly 10-40 s per asset. The bake dominates: albedo at the asset's resolution, the
normal at half, occlusion/roughness/metallic at half (occlusion is low-frequency, and the
ORM map is written at half size anyway, which turns the most expensive pass into a quarter
of the rays). Only hero pieces bake at 2048; bark is capped at 512.

Generated output is committed, so weight matters. A tree is the heaviest ordinary asset at
roughly 1.5 MB, and most of that is mesh: smooth shading splits a branching trunk at
nearly every vertex, so triangles cost about 2.5 vertices each in the GLB. That is why the
trunk budget is 5 000 triangles rather than the 40 000 a hero piece is allowed.
