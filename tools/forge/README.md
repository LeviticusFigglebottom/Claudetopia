# tools/forge — the asset forge

Every mesh and texture in Wickmere is made here (DESIGN.md §7, ARCHITECTURE.md §7).
Blender 4.0 runs headless driven by Python; leaf, grass and flower textures are drawn
directly with PIL. Nothing third-party is used or downloaded.

## Build

```
./run.sh assets                       # everything missing or stale
./run.sh assets --only trees          # one category, generator, palette or name
./run.sh assets --jobs 2 --force      # rebuild everything, two Blender processes
./run.sh assets --list                # what would be built, and what is current
python3 tools/forge/make_manifest.py  # regenerate manifest.json from the tables
python3 tools/forge/tests/run.py      # the test suite (--fast skips the Blender run)
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
filters, and `--only=bowl,table_trestle` takes several, which is how you get the known
reference the section below insists on into the same frame as the thing you are judging.
Exposure is fixed in the scene (`tonemap_white ≈ 6`, sun ≈ 1.0): on the Compatibility
renderer anything brighter clips mid-greys to white.

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
| `lib/impostor.py` | renders an object to an RGBA billboard and builds crossed cards (the old tree LOD2, before `gen_impostors`). |
| `gen_impostors.py` | a tree's far picture: eight Cycles views into a 3×3 albedo atlas and a normal-and-sky-visibility atlas, LOD2 rewritten as one upright quad for `tree_impostor.gdshader`. One `<tree>_impostor` manifest entry per tree, built after the trees. |
| `lib/lod_repair.py`, `repair_lod1.py` | drops the LOD1 bark triangles the collapse decimator stretched between branches (standing off the full tree's bark). `gen_impostors` runs it on every tree it draws; `repair_lod1.py` runs it on trees already current. Pure Python. |
| `lib/bake.py` | UV unwrap, Cycles CPU bake to albedo / normal / ORM. |
| `lib/export.py` | LODs, collision, glTF export, `meta.json`, Godot `.import` sidecars. |
| `lib/runner.py` | the shared `main()` most generators use. |
| `gen_*.py` | the generators. `--list` prints their kinds. |
| `make_manifest.py` | writes `manifest.json` from readable tables. |
| `fit_parts.py` | fits the garments already built to another body (the woman's) as a morph target, in the GLB, without Blender; `--check` lists the ones without it. `character_forge parts` fits new garments itself (`ALWAYS_FITTED`). |
| `bow_draw_morph.py` | the bows drawn (triage 55): writes the morph targets `drawn` (the limbs bent back and in) and `unstrung` (the forged string drawn onto its line, while the game draws the string round the fingers, BowHands) into the built bow GLBs, without Blender. Run it again after `gen_weapons` rebuilds a bow; `--check` lists the ones without them. |
| `hair_cards.py`, `lib/hair_cards.py` | hair and beards as strand cards (triage 47): the strand atlas and the cap's grain (`--atlas`), and `<name>_cards` written into each hair and beard GLB beside its shell, without Blender. `character_forge parts` runs it after each shell. `preview/cardpreview.py` draws them in numpy. |
| `creature_forge.py` | the common foes (`lib/foe_specs.py`): SDF bodies, painted maps, LODs, skins and clips, one GLB each in `game/assets/models/creatures/<foe>/`, read by `CreatureModel`. `blender -b --python tools/forge/creature_forge.py -- <foe> ...`; `--list` names them. The dogs, the boar and the reptiles are on WM_Quadruped_v1 drawn joint by joint (`lib/beast_body.py`, `lib/boar.py`, `lib/reptile.py`, clips `lib/foe_clips.py`); the weaver, the thralls, the warden and the wisp on `lib/creature_rig.py` (`lib/weaver.py`, `lib/biped.py`, `lib/thrall.py`, `lib/warden.py`, `lib/wisp.py`). `preview/beastmesh.py <foe> out.png [--paint] [--clips Name@t,...]` looks without Blender; `game/tools_gd/creature_review.tscn` looks in Godot. |
| `horse_forge.py hart` | the grey hart, the Ranger's lead (`world/tutorial/leads.gd`, drawn by `HorseModel`): the red deer's body (`lib/deer_body.py`) as an old stag (`HART`, heavier, a fourteen-point rack, his own iron-grey coat), the deer's gaits and `Look_Back`/`Look_Back_R` (`lib/quad_clips.py`), in `game/assets/models/creatures/grey_hart/`. `preview/horsemesh.py out.png --hart --paint` looks without Blender; `creature_review.tscn -- --foes=lead:grey_hart` in Godot. |
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

## Tests

```
python3 tools/forge/tests/run.py          # everything
python3 tools/forge/tests/run.py --fast   # pure Python only, no Blender
```

* `test_palette` — colour maths, role derivation, and that the six regions stay separable
  and in character (Hearthvale's warm is warm, Cinderlea is the least saturated).
* `test_paths` — naming, seeds, output layout against CONTRACTS §4, asset hashing, the
  manifest, and the GLB reader/writer.
* `test_output` — runs over whatever is in `game/assets/models`: triangle budgets, LOD
  ordering, grounding, texture sizes, external texture references, foliage material
  naming, variant distinctness, and the repository weight ceiling. Skips when nothing has
  been generated.
* `test_generation` — builds a mug, a boulder pair and a grass clump for real under
  `blender -b` and checks the files, the meta, the LOD meshes, determinism and the alpha
  cut-out. Skips when Blender is not on PATH.

## Contracts this keeps

* Output layout, categories, collision kinds and texture names: `docs/CONTRACTS.md` §4.
* Metres, models facing -Y in Blender, ~1.1× chunky props: `docs/CONTRACTS.md` §1.
* Triangle budgets and the style contract: `DESIGN.md` §7.0.
* Materials are Principled BSDF only, so Godot imports them as `StandardMaterial3D`;
  foliage materials are named `*_foliage` and `tools_gd/glb_post_import.gd` swaps in
  `assets/shaders/foliage_wind.gdshader`.

## Which Blender, and the three things 4.1 took away

The forge was written against **Blender 4.0** and this container now has **4.2.3**. Under
4.2 it could not build anything at all, and the three faults are worth knowing because
each of them fails in a different place:

| What | Then (4.0) | Now (4.1+) |
|---|---|---|
| smoothing angle | `mesh.use_auto_smooth` + `auto_smooth_angle` | `bpy.ops.object.shade_smooth_by_angle(angle, keep_sharp_edges)`, which writes a `sharp_edge` attribute the glTF exporter reads |
| vertex colours off | `export_scene.gltf(export_colors=False)` | `export_vertex_color="NONE"`; the old keyword makes the operator refuse the call |
| Pillow | bundled with Blender's Python | not bundled; `lib/__init__` puts the project's own `pillow>=10` on the path (same CPython minor version, so the wheel loads) |

The first one dies in the builder, on the first prop that asks for a smoothing angle. The
second dies at export, after the bake. The third died *after* the bake as
`'NoneType' object has no attribute 'fromarray'`, which names neither Pillow nor the
interpreter; `save_png` says it plainly now. All three are version-guarded, so the same
tree builds under either Blender.

**An asset rebuilt under 4.2 is not byte-identical to its 4.0 twin.** A mug rebuilt from
the same seed came out 0.108 m against the committed 0.110 and its LOD2 two triangles
different: `jitter_verts` displaces along the vertex normals, and the normals are what
changed hands above. The committed library was baked under 4.0, so **do not rebuild an
asset you are not deliberately changing** — `build_assets.py` is incremental on the hash
and will leave them alone unless something moves `FORGE_VERSION` or a manifest line.

A silent version guard is worse than a crash, and there is one in the tree: the character
forge's `lib/body.py` catches the `AttributeError` from `use_auto_smooth` and passes, so
under 4.2 every character it builds is fully smoothed with no threshold and nothing says
so. That is the character stream's to fix.

## The scale constant: the forge's one recurring bug

Three times now the same fault has shipped, and every time it was invisible in the code and
obvious in the first render: **a number that is a length in metres, written as a constant,
used at a size it was never chosen for.** A bark feature size fixed at one metre. A rock's
noise scale divided by its radius. And, when the forge first made things small enough to
hold:

* `wood_planks` bumps its normal over an absolute 15 mm. On a table top that is grain; on a
  16 mm hammer haft it is a screw thread. `relief` scales it.
* `wood_planks` lays its grain down as a wave banding every `scale`/22.5 metres. `scale` is
  the feature size, so shrinking it makes the rings *finer*, never fewer: a 0.55 m scale on
  a 1.4 m spear shaft is fifty-odd rings around a stick. `grain` divides that frequency,
  and it is the one that survived the first fix, because the rings are in the albedo and
  `relief` only touches the normal.
* `lake_stone` bumps its bedding over an absolute 40 mm. On a boulder that is a soft swell;
  on a 40 mm whetstone it is a flight of steps, and the hone came out as stacked slate.
* `paint_blocks` works the other way. It lays three tones down over `scale` × 1.43 metres,
  so a scale near the object's own size drops the whole object on one arbitrary stop of the
  ramp and it bakes out flat.

Every one of these is a parameter now, defaulting to the value that keeps existing assets
byte-identical, so there is no excuse for the fourth. The rule when adding a material
parameter that is a length: **either it scales with `scale`, or it takes a multiplier and
the docstring says what size it was chosen for.**

And the way you find it is to look. A contact sheet you did not open is worth nothing.

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

Roughly 10-40 s per asset, and the bake dominates. Every generated file is committed, so
the size each map is *written* at is a design decision, not an afterthought:

| Map | Size | Why |
|---|---|---|
| albedo | the asset's resolution (256 / 512 / 1024, 1536 for a landmark) | it carries the whole read; nothing else is worth spending bytes on |
| normal | a quarter of the albedo above 1024, a half below | painterly relief is broad and soft, so the downscale supersamples it rather than losing it |
| ORM | the same | occlusion, roughness and metallic all vary slowly, and baking occlusion at a quarter is a quarter of the rays as well as a quarter of the bytes |

Those three rules took a boulder from 1.6 MB to 0.42 MB with no visible change, which is
the difference between a 190 MB library and a 130 MB one.

The other lever is the mesh. A tree is the heaviest ordinary asset at roughly 1.4 MB and
most of that is vertices: smooth shading splits a branching trunk at nearly every vertex,
so a triangle costs about 2.5 vertices in the GLB. That is why the trunk budget is 5 000
triangles rather than the 40 000 a hero piece is allowed, and why the export strips the
pre-bake UV set — a second TEXCOORD nothing samples is eight bytes a vertex.
