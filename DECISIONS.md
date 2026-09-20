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

## 2026-09-19 · Interiors live in a far pocket, not in separate scenes
**Decision.** Interior cells are instanced at x≈50 km, y=3 km (one 1 km slot per
interior) inside the running world scene; doors teleport the player. The
overworld keeps running; the streamer finds nothing around the pocket and idles.
**Why.** No scene switching means autoloads, NPC simulation, weather and the
clock keep state trivially; interiors can be tested headlessly with a fake
player; sun and moon still light window shafts. A separate SubViewport world
or a scene swap would need bespoke save/restore plumbing.
**Consequences.** Interiors must be enclosed meshes (directional light is
global) and the Atmosphere switches to an interior mode (fog ×0.12, ambient
×0.45). Far-pocket coordinates are large but well within float precision for
1 km slots (sub-centimetre).

## 2026-09-19 · Death drops all marks into a single Echo
**Decision.** Death leaves one Echo at the death point holding every mark; a
second death before recovery lets the old Echo go quiet. Skills and levels are
never lost. Respawn counts as resting: the deep places reset.
**Why.** One clear, visible consequence (DESIGN pillar 2) that fits the fiction
(you are anchored where you were last known) without punishing use-based
progression, which is per-skill and would be awkward to drop.

## 2026-09-19 · Interiors are generated from authored intent, not from seeds
**Decision.** Deep places come from a recipe of **beats** (entrance, passage, chamber,
camp, flooded, shrine, treasure, boss) with a size word, a drop, links and a shortcut;
houses come from a resident's **trade, wealth, household and habits**. The generator
turns that intent into geometry and dressing. It is never the final result: the recipe
also carries hand-placed features, encounters, and the story of who was here.
**Why.** DESIGN requires interiors that answer "who was here?" and "what happened?", and
no two that read the same. Pure procedural generation cannot answer either question;
hand-building 24 interiors would eat the whole pass. Authored intent plus a generator
gives both, and makes a new interior a short JSON file rather than a week of modelling.
**Consequences.** The recipe is the source of truth; the meshes are build artifacts
(`./run.sh interiors` rebuilds them). A designer changes a place by changing a sentence.
The generated shell is chunked per chamber so the renderer can cull it.

## 2026-09-19 · The scripted journey is the real acceptance test
**Decision.** `./run.sh journey` drives one run through every promise in DESIGN's done
list, against the real systems, and fails if any step does not hold.
**Why.** Every stream's unit tests passed while the player spawned with no bag, no host
scene installed the law or the market, two streams named the same shop tables
differently, and four bosses had no stats. Unit tests cannot see a gap that lives
between two systems; the journey found six in its first run.
**Consequences.** Any new system that the done list depends on adds a step. A stream is
not integrated when its tests pass, but when the journey still passes with it merged.

## 2026-09-19 · Compatibility's light cap is a design constraint, not a bug to tune around
**Decision.** Interiors are lit for Forward+ (the shipped renderer) and reviewed on it.
The Compatibility per-object omni cap is raised to 12 and treated as a budget: a room
gets a small number of strong lamps plus one vault light and one fill, not a scatter.
**Why.** Compatibility silently drops lights past the cap, so a large chamber stayed
black no matter how much light was added. Discovering that cost an hour; the rendering
notes now say so plainly.

## 2026-09-19 · Known sayings live on Progression, not on the player actor
**Decision.** The list of sayings a character has been taught (`known_spells`) lives on the
`Progression` node beside skills, levels and perks, with `learn_spell` / `knows_spell` /
`spells()` mirroring Crafting's `known_recipes` / `learn_recipe` / `knows_recipe`. Which
saying is *readied* stays on the player actor as `equipped_spell`, because that is a thing
about the body and not about the character.
**Why.** A saying is something the character learned, like a skill or a recipe — not
something they are carrying. Progression already saves under its own section, is discovered
by group, and already owns the five magic schools the sayings belong to, so the screen, the
dialogue vocabulary, the tomes and the quest rewards all reach one owner. Putting it on the
player actor would have tied it to the body, which dies, respawns and is reconfigured.
**Consequences.** `SpellCaster` gained a `known_lookup` callable and `SpellRuntime.can_cast`
a `known` argument returning the reason `"not_known"`, so a saying nobody taught is refused
however its id reached the slot — a console, an old save, a quick slot. Enemy casters leave
`known_lookup` unset, which means yes: their spells are part of their def and nothing has to
teach them. The save schema went to v3; `Migrations._v2_to_v3` seeds `known_spells` from
whatever saying an old character had readied.

## 2026-09-19 · A spell tome is a book, not a potion
**Decision.** Each of the fifteen sayings has a `core:book/saying_*` def with the working
actually written out in it, and a `core:item/tome_*` that `reads` it. Reading teaches the
saying through `EventBus.book_opened`, the same path an ordinary book takes, and the book is
not consumed.
**Why.** The pack already had one way to read a thing. A tome that vanished when used would
be a second, parallel path with its own rules, and would have made the most interesting
objects in the magic system unreadable — the point of *Off the Roll* is the six owners' lines
inside it, not the item tooltip. Keeping the book means a tome can be sold on, given away or
left on a shelf, which is what the fiction says happens to them.
**Consequences.** Teaching hangs off `book_opened` in `Progression`, so a tome read off a
shelf and a tome read out of the bag teach exactly the same thing. Re-reading one says so
rather than silently doing nothing.

## 2026-09-19 · A house is built from the inside of the house it opens onto
**Decision.** `Building` raises a house's exterior by reading that interior's own meta: the
ground-floor rooms become wall masses, each mass takes a pitched roof at its culture's pitch
and depth, the hearth room takes a chimney, and the door and windows are placed where the
interior says they are. No exterior is modelled or authored separately.
**Why.** The alternative is a library of house meshes and a rule for choosing between them,
which guarantees that the cottage you walk up to is not the cottage you walk into. Reading
the interior means a one-room cottage is small outside and the steward's eight-room house is
not, for free, and a change to the house forge changes both sides at once.
**Consequences.** The outside is plain massing with painted surfaces rather than a modelled
asset — what a village needs first is silhouette, mass and a door in the right wall. Two
bugs came out of writing it and both were invisible except by looking: the painted_surface
uniforms are spelled `base_color`, so setting `base_colour` was silently a no-op and every
wall and roof in Merrowby came out the shader's default grey; and the roof slabs were tilted
the wrong way, which turns a cottage into a pair of open wings.

## 2026-09-19 · The rest of a town is generated, and it is two draw calls a house
**Decision.** Twenty-four hand-built interiors cannot furnish eleven settlements, so
`Settlement` raises the other roofs: plots along any road that crosses the place's pad, a
ring around a green where none does, counts and sizes by the place's `kind`. Every filler
house is merged into two meshes — one per material — rather than instanced as parts.
**Why.** A settlement is fifty roofs of which four open. Without them, Tollmere the capital
was a paved circle with three doors on it. Merging per material means fifty of them cost
what six full `Building`s would, which is the only reason a city is affordable at all.
**Consequences.** Filler houses cannot be entered and have no interior; that is honest, and
the ones that can be entered are exactly the ones the content pack authored. Props are
placed against the houses rather than against the pad, because the flattened ground is far
wider than the town standing on it, and each is dropped by its own AABB until it sits on the
ground — the forge centres a cart on its axle, so a cart placed at ground height hovers.

## 2026-09-19 · Ask what nothing outside a test ever calls
**Decision.** `tools/unwired.py` reports public functions in `game/` that only the tests
reach, with a `--verbs` mode for the ones that are actions rather than accessors. It is the
counterpart to `tools/dead_data.py`: that one asks what the data promises that the code never
reads, this one asks what the code can do that nothing ever asks for.
**Why.** A system can be complete, correct, covered by tests and completely inert, and a green
suite says nothing about it. Three things in this project were in exactly that state:
`NpcRegistry.spawn()` had one caller and it was a test, so every village was empty while its
schedules ran; `Bounty.commit()` was reached by picking a lock and picking a pocket but not
by emptying a chest or killing a villager; and `WorldContainer.take_all()` had no caller at
all, so every chest in the world was scenery.
**Consequences.** It is a text scan and not a compiler, so it has false positives — an
accessor nobody calls is dead weight, but a verb nobody calls is a feature that does not
happen, and that distinction is the whole value. Running it also exposed a related habit:
five places reached for `Bounty.instance` and gave up quietly when it was null, so crimes
were being committed and dropped. Everything goes through `Bounty.ensure()` now.

## 2026-09-20 · A landform score must be blind to where the camera stood
**Decision.** The drop test's landform axis dropped the absolute horizon height and the sky
fraction from its signature, and the landform bar only binds at six or more images per region.
**Why.** Moving the review camera from 48 m above a hilltop to eye height moved the score by a
factor of eight. A metric that swings when the photographer moves is measuring the photograph.
The terms that did it encode how high the camera stood and how far it tilted, and neither is
anything the place does. Separately, three images per region over six regions makes
leave-one-out turn on one or two frames, and the figure lands anywhere including below the
chance line — which means noise, not a bad country.
**Consequences.** The tool now says out loud when the sample cannot support the number and
refuses to fail the run on it, and the confusion pairs are the part worth reading meanwhile.
Six shots a region is cheap and is the next thing to do. The cost of this honesty is that half
the drop test is currently unmeasured, and PROGRESS.md says so.
