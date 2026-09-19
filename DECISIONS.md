# DECISIONS.md — decision log

Each entry: date, decision, reasoning, alternatives considered, consequences.
Newest at the bottom. Reversible decisions say so.

---

## 2026-09-19 · Engine: Godot 4.7.2 (latest stable), GDScript first
**Decision.** Godot 4.7.2 stable, GDScript for all game code, GDExtension only
for terrain. Forward+ renderer as the shipped target; Compatibility (OpenGL) kept
working for low-end and for headless captures.
**Why.** Open source, scene/resource model fits data-driven content, headless
import/run works in this container, procedural sky/fog/post out of the box,
first-class controller support and input remapping. GDScript keeps every system
readable by a future session; C# would add a runtime and toolchain risk here.
**Alternatives.** Unity/Unreal (licensing, no headless run here), Bevy
(too much to build ourselves for a first pass).
**Consequences.** Performance-critical loops (scatter, streaming) must be
designed around MultiMesh, threads and pre-baked data.

## 2026-09-19 · Name and frame: *Wickmere*, the Dwindling, "being known holds"
**Decision.** The game is Wickmere. One cosmology (a fading world) told four
contradictory ways by four cultures; renown/memory literally anchors things.
**Why.** Gives Fable's renown, Elder Scrolls' unreliable books and Souls'
shrines/melancholy a single cause, so the three lineages are one game.
**Alternatives.** A literal "first flame" (too close to Souls), a loom/weave
(generic), no unifying myth (three games stapled).
**Consequences.** Every system touching reputation, shrines, death and deep
places must reference the frame in its data (names, descriptions, book text).

## 2026-09-19 · Terrain: Terrain3D 1.0.2 (GDExtension) at 2 m spacing
**Decision.** Use Terrain3D for the heightfield (LOD clipmap, up to 32 textures,
region files, holes, dynamic collision). World builder writes raw heights/control/
colour maps; a headless Godot tool imports them into Terrain3D regions.
**Why.** A hand-written clipmap terrain with splat shader, collision and
streaming would eat days and look worse. Terrain3D's regions are already a
chunked, streamable, data-driven world space. Verified: loads in 4.7.2
headless, imports a 1024² float heightmap, reports heights.
**Risk.** Prebuilt 1.0.2 binaries are compiled against Godot 4.4 API; a crash
appeared under lavapipe (software Vulkan) in this container. Being isolated (see
PROGRESS.md). If it proves to be a Terrain3D/4.7 incompatibility rather than a
software-renderer issue, the fallback is a custom chunked heightmap terrain
(`game/world/terrain_fallback/`), kept behind the same `TerrainProvider`
interface so the rest of the game does not care.
**Reversible.** Yes, behind `TerrainProvider`.

## 2026-09-19 · (SUPERSEDED, see below) Art: "Painted Low-Poly, Strong Light"
**Decision.** Flat-shaded low-poly assets (Kenney, KayKit, our own Blender/
Python generators) unified by one palette-shader family and one import
normaliser; painterly generated surface textures; realism carried by light,
fog and post. See DESIGN.md §7.0.
**Why.** Consistency is achievable without artists; procedural variation kills
the copy-paste feel; software rendering can preview it. The user asked for
coherent styles, and a shared palette system is the only way to guarantee it
across sources.
**Alternatives.** PBR photoscans (Poly Haven) as primary look: rejected; they
clash with any low-poly kit and cannot be varied procedurally.
**Consequences.** Every imported asset is re-materialled; textures are
generated; a style report gates the build.

## 2026-09-19 · (SUPERSEDED, see below) Characters: original bodies on the KayKit humanoid rig
**Decision.** Player, villagers and humanoid enemies are procedurally built
bodies (Blender script) skinned to the KayKit skeleton rig (41 bones), so the
CC0 KayKit animation library (95 clips: 1H/2H attacks, block, block-hit,
4-way dodge, hits, deaths, spellcasting, ranged, sit/lie/interact) drives
everything. KayKit skeletons themselves are used as one enemy family after
re-palettising.
**Why.** Animation is the hardest asset to make procedurally; combat readability
depends on it. Sharing one rig means every humanoid gets the full move set and
character-creation variety comes from the body generator, not from clips.
**Alternatives.** Hand-authored keyframes in Blender (weeks), Mixamo (licence
unsuitable for redistribution), runtime procedural animation (unreadable
attacks).
**Consequences.** Non-humanoid creatures need their own small rigs and clips
(generated in Blender by script, fewer clips each).

## 2026-09-19 · Content format: JSON packs with namespaced IDs `pack:type/name`
**Decision.** All content is JSON under `content/packs/<pack>/<type>/*.json`,
IDs are `core:item/iron_sword`, loaded by `ContentDB` through one path that
future packs also use. Scenes (.tscn) are referenced from data by path.
**Why.** Python tools and tests read it without Godot; diffs are readable; the
loader validates against schemas; nothing hard-codes the core pack.
**Alternatives.** Godot .tres resources (engine-bound, poor for tooling).

## 2026-09-19 · Generated terrain data is a build artifact, not committed
**Decision.** Heightmaps/control/colour maps and Terrain3D region files are
generated by `make world` from committed recipes (seeds + authored stamps) and
are gitignored. The single run command generates them if missing.
**Why.** Hundreds of MB of binary terrain in git would make the repo unusable;
the recipe is the source of truth and is deterministic.
**Consequences.** Python 3 + numpy are build-time dependencies (documented).

## 2026-09-19 · Art pivot: all assets self-made, "Storybook Painted", not low-poly
**Decision.** Per the user's direction, no third-party model/texture packs
(Kenney, KayKit, Quaternius, Poly Haven) and no low-poly style. Every mesh,
texture, animation, sound and UI element is produced by this project's own
tooling: Blender 4.0 scripted headlessly (`tools/forge/`), Python image and
audio synthesis, and Godot shaders. The look is painted storybook realism with
smooth mid-poly geometry and hand-painted-style baked PBR textures. The only
third-party files are SIL-OFL fonts and the Terrain3D plugin (MIT).
**Why.** The user does not want the low-poly kit look, and self-made assets
give total stylistic control and clean IP. Blender's built-in generators
(Sapling trees, displacement, Skin modifier bodies, Cycles baking) make this
feasible at scale; verified by prototype renders (see PROGRESS.md).
**Alternatives.** Keeping CC0 kits with a re-material pass: rejected by the
user. Photoreal scans: clash with a painted look and cannot be varied.
**Consequences.** Animation is authored in code from pose libraries and gait
generators on our own rig; this is the largest risk in the pass and gets a
dedicated review loop. Asset generation becomes a first-class build step
(`make assets`), cached and committed as GLB/PNG outputs so the game runs
without Blender.
**Supersedes.** The two entries marked SUPERSEDED above. The Kenney/KayKit
downloads were deleted; nothing from them is in the repository.
