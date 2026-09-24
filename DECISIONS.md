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

## 2026-09-19 · A landmark stands where the fiction says, with the collision it was built with
**Decision.** Landmarks are placed from the forge's own metadata, not from a table in the
builder. Each landmark model names its `place` in its meta file, so `build_world.py` indexes
`game/assets/models/landmarks/` by place id and emits the `.glb` as that POI's `scene`; an
imported `.glb` loads as a `PackedScene`, so the streamer instantiates it with no special
case. Collision is the `*_col.glb` the forge already builds beside it, named in the meta and
copied into the cell entry as a `collision` field; the streamer turns it into a `StaticBody3D`
of trimesh shapes under the instance. Yaw is a bearing the world gives the landmark, not a
default: the Lamp faces down the gradient of the water-distance field, the Sayers' Spire and
the Sunken Choir's colossi face a named place, and anything unlisted faces downhill, which for
a fallen thing is the way it fell. A `yaw` in `places.json` overrides all of it.
**Why.** The alternative for collision was a trimesh built from the visible mesh at load, which
would have put 10,807 triangles into the physics world for the Cracked Toll instead of 729 for
something you mostly walk around; and asking the forge for `-col` suffixed nodes inside the
main glb would have duplicated a file it already writes. The alternative for yaw was a hand
table, which is fine for six landmarks and wrong for sixty: a bearing taken from the water, the
slope or another place keeps working when a place moves, and a landmark facing due north
because that is the default is a tell.
**Consequences.** `pois.json` entries gain an optional `collision` path beside `scene`, and so
do the cell `scenes` entries — additive, and consumers that ignore it get what they had. A
landmark that is really a set (the Sunken Choir is twelve headless colossi) is described in
`LANDMARK_SETS` and comes out as an avenue running from the place toward what it faces, which
means one place can own more scene entries than it has POI entries. Standing stones are not
landmarks and are not scattered either: `worldgen/stones.py` sets them as a ring at the Moot,
as pairs flanking a road where it crosses the high ground, and as single stones on skylines,
because the whole point of a standing stone is that a person put it there.

## 2026-09-20 · A view range and the ring it applies to have to be read together
**Decision.** `WorldStreamer.VIEW_RANGE_FAR` is not a smaller version of `VIEW_RANGE`. It is
measured from the camera to a cell that is *already* between 384 m and 905 m away, so any
number below 384 hides the whole 5×5 ring. The far ring's cost is held down by `FAR_KEEP`, a
per-kind fraction of instances, and by drawing it at a lower LOD — never by a range that cuts
it off before it begins. And `_mesh_of` skips a LOD rung that has collapsed below
`MIN_LOD_TRIS`, taking the next one up instead.
**Why.** Both of these were systems that drew nothing while reporting success, which is the
hardest kind of fault to see in a screenshot: the far ring had view ranges of 300 m for trees
and 120 m for bushes, so it had been drawing essentially nothing since it was written, and a
wooded region could be photographed from a hilltop and show eight trees with no error
anywhere. The LOD guard is the same species: some of the forge's trees go to four triangles at
LOD2, so a renderer that faithfully drew the rung it was given drew empty air. Keep the guard
after the ladders are fixed — a generator that silently produces nothing will happen again.
**Consequences.** Measured on the Briarwold hilltop vista, the worst frame in the world:
6.52 M primitives as merged, 2.29 M with the ranges and per-ring LODs corrected, 1.59 M once
the wood came down to 34 stems a hectare — and turning the entire far ring off saved 0.06 M of
that, so all of the cost is the 3×3 at about six hundred trees of roughly five thousand
triangles each. The wood is held at 44 stems a hectare and that one frame carries about 2.0 M
against a 1.5 M budget, deliberately, because the alternative is hill grazing with trees on
it. Every other region is between 0.38 M and 0.6 M. When the forge ships a ladder of roughly
`[7000, 800, 8]` the density goes back up and the overage goes away.
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

## 2026-09-21 · A settlement's fabric is four draw calls, and so is a house
**Decision.** `Building` and `Settlement` both build through `FabricMesh`: every box and
triangle goes into one `SurfaceTool` per surface (walls, roof, stone, joinery) and each
surface is committed as a single `MeshInstance3D`, with a vertex colour per piece that the
painted shader multiplies in. So an entered house is four meshes plus a collision body per
room, whatever its room and window count, and a whole settlement's filler houses are the same
four meshes for all of them, each house in its own bucket of limewash. Props are one
`MultiMesh` per forge asset per settlement. Joinery and props carry a visibility range and the
joinery casts no shadow; walls and roofs are drawn to the horizon. Only collision bodies and
the interactables (`JobBoard`, `JobStation`, `PropertySign`) remain nodes of their own.
**Why.** Merrowby's street was the worst frame in the game at 2438 draw calls against DESIGN
§11's 2000, and until `DrawAttribution` (`--attribute` on a capture, `draws measure` in the
console) nobody could say what they were. Measured: 1093 were the eleven entered houses in
view — walls, plinths, slabs, gables, ridges, chimneys, door parts and window parts as 358
separate MeshInstance3Ds, each drawn once for the eye and about twice more for the sun's
cascades; 1535 of the 2441 draws were shadow passes. Merging per material rather than per
part is the only change that scales: a city of fifty-four houses costs what a hamlet does.
**Consequences.** The per-building tone shift is a vertex colour now rather than a material
per building, and the shader change (`ALBEDO *= COLOR`) is invisible to every mesh that
carries no colour. The filler houses gained their windows, chimneys, lintels, eaves and
varied plinths at the same time, at no draw cost, because inside a merged mesh geometry is
free and draws are not. Measured on gl_compatibility at 1600x900, the six street shots went
2438/479/660/764/609/515 -> 1328/283/498/547/433/405. What is left in Merrowby's 1328 is
villagers (590: about nine skinned meshes each, all shadow-casting, so twenty in view is
nearly six hundred draws), scatter MultiMeshes (332) and Terrain3D (160); the buildings are
120 and the fabric 110. `test_settlements.gd` ratchets a village of Merrowby's kind at 31
mesh nodes.

## 2026-09-19 · (SUPERSEDED, see above) The rest of a town is generated, and it is two draw calls a house
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

## 2026-09-20 · The land is built last, and the places land on it
**Decision.** The Hearthvale escarpment is generated from the region's own shape function with
no reference to where anything stands: a bearing, a wandering crest, a face, a dip slope and
a set of dry valleys. The places are not moved to suit it, and it is not moved to suit them.
The pads flatten wherever a place already was, and the land arrives underneath.
**Why.** The alternative — placing the scarp to miss the villages, or nudging a village off the
face — is the thing that makes a generated world feel arranged. A landscape is not negotiated
with its inhabitants; people settle where the ground lets them, and a generator that guarantees
a comfortable outcome guarantees a bland one. The risk was real: a seventy-metre face across
the middle of the start region could have put the first town on a cliff, and the answer to that
is the pad and the slope-cost roads, not a special case.
**Consequences.** The region sorted itself. Merrowby, Warden's Rest, Pennywort's Mill and the
Cracked Toll are in the vale at 18 to 30 m under the face; Tamwick, Hollin Barrow and the Chalk
Hound are up on the tops at 100 to 121. The roads climb the scarp through the coombes because
that is where the slope cost is lowest, which is why real roads go through them. None of that
is authored anywhere, and if the seed changes it will sort itself differently and still be
coherent. The height thresholds in the downs' texture rules had to move with the land — barley
stops below the crest now rather than above 95 m — and that is the maintenance cost of building
the land first: anything written against absolute heights is written against the landform, and
has to move when the landform does.

## 2026-09-22 · Two orderings the data broke, and the reading that hid them
**Decision.** `tools/balance.py` now reads three things the game acts on and the tool scored as
zero, and four enemy numbers changed to restore the two orderings a region's `danger` rating
promises. No formula moved: `hp_max`, `skill_mult`, `hit` and `level_threshold` are still
DESIGN §5.3 and §5.6 mirrored term for term, and the magnitudes stay the uncalibrated guesses
`ASSESSMENT.md` calls them. `tools/tests/test_balance.py` fails the build if either ordering
inverts again.

**Why the reading came first.** The tool said Brightwater was twice as safe as the starting
downs and the marsh paid a quarter of what the lake did. Most of both readings was the tool.

* A spell attack carries no `damage` of its own — `enemy.gd` sends it through the caster and
  the spell's own effects are what land (CONTRACTS §7). Read flat, the Smuggler Sayer and the
  Wisp did nothing three casts in five, and the two regions that field a caster read far safer
  than they are. Brightwater 13.1 → 10.3 hits to kill you, Sedgemire 9.2 → 6.4, on no data
  change at all.
* A bleed, a burn or a poison goes on taking health after the blow, and takes it raw, past
  armour. A Bravo's one real thrust is 25 in the moment and 12 more over six seconds.
* `guaranteed` loot entries were skipped, so a sallowjaw read as worth three marks when the
  hide it always leaves is worth thirty-four — the whole reason Isseva hunts one.

Tuning data against a reading we knew to be wrong would have been the wrong work. The
hardest-single-hit column deliberately keeps the aftermath *out*: whether a blow kills you
outright is decided by the blow, so `attack_impact` is the impact and `attack_damage` is both.
That column is unchanged at 30/25/34/35/48/58, and so are the bosses at 7–34 heavy hits.

**Why these four numbers.** Each is explainable in the creature's own terms, and each was odd
on its own before any curve was consulted.

* The **Bravo** is the only elite in a region rated as dangerous as the starting downs, and his
  measured thrust landed for 15 where a Hearthvale roadside bandit's slash lands for 11. A
  Tollmere rapier in a bought duellist's hand: 18. His one real blow stays at 25, so
  Brightwater's hardest single hit is still 25% of your health.
* The **Smuggler Sayer**'s staff rap is a two-handed staff with knockback and did less than a
  cutpurse's dagger: 17.
* The **Cutpurse** opens you to get at your belt, with the iron dagger his own takings drop,
  and was gentler than a boy with a hedge-knife: 9 and 15.
* The **Gutter Drake** stays cat-sized and stays weak in the jaw — its bite is still 6. What
  was missing is what its lore already said: "they eat what the city sends them". A mouthful of
  the Undercroft goes septic, so the ankle snap carries `poisoned` for eight seconds. The
  drake's danger is in the wound, not in muscle, and nothing about a vermin swarm had to be
  inflated to a wolf's bite to make the region keep its promise.
* The **Bog-Drowned** is the brute of a region one step past the start and carried 4–14 marks,
  less than a Hearthvale bandit. The Reedfolk go into the water with their things: 14–38. And
  their burial rite puts a lantern in with them — "sometimes the lantern goes out first" — so
  the lantern is `guaranteed` at the half-chance the lore names rather than one weighted pick
  in twenty-one.

Brightwater now reads 6.8 hits to kill you against Hearthvale's 6.6, inside the half-hit slack
the tool allows two regions written for the same point in the curve; the marsh pays 34 against
the downs' 31.

**What was deliberately left alone.**

* **Flat armour is still a design question and stays open.** The best weapon in Wickmere lands
  27 as a light and 107 as a charged heavy against the Stone-Thrall King's 30 armour, a
  four-fold spread, and the tool still says so on every run. Subtracting armour before
  everything else is DESIGN §5.3 and normative; whether a late boss should make the charged
  heavy the only real answer is a question for a playthrough, not for a tuning pass.
* **Brightwater pays 2.5 times what Hearthvale does at the same danger rating**, and the tool
  still reports the marsh after it as paying less. That is not the marsh being poor: three of
  Brightwater's four kinds are city criminals who carry purses, and three of Hearthvale's are
  animals who do not. Closing it means either taking the fee off a paid duellist or giving
  Sedgemire a human outlaw to kill — the marsh has none, only three beasts and a corpse, which
  is why its takings are hides and glands rather than marks. Inventing an enemy is content
  authoring and not a calibration, so the pair is exempted by name in the test and the reason
  is written there.
* **Encounter group sizes.** `tools/world/worldgen/encounters.py` already authors them: a swarm
  stands 4–7 together, a brute alone. So "hits to kill you" per body is not what the country
  sends at you, and a region of swarms reads safer than it plays. Counting the group would
  change what the column means rather than correct a misreading, so it is not counted, and
  this is the honest reason a per-kind mean flatters Brightwater.

## 2026-09-22 · A signal listener is a method reference, never a closure
**Decision.** Nothing in `game/` connects a lambda to a signal on an object that outlives the
node making the connection, and `run.sh test` fails the run on "Lambda capture at index N was
freed" the same way it fails on SCRIPT ERROR.
**Why.** A full test run printed that message 139 times and the suite was green throughout, so
the count was not being read by anything. All of them came from one closure: the toast fade in
`ui.gd` was started on UI, which is an autoload and never goes, and its last step was a closure
holding the toast panel -- which a sixth toast throws away five and a half seconds early. The
`is_instance_valid` guard inside the closure was never reached, because the engine checks the
captures before running the body.
**Consequences.** Godot *does* drop a connection whose callable was made from an object that is
then freed, including a lambda that captured `self`, so the eleven sites this was first blamed
on were not leaking. The one it does not catch is a lambda that captured some *other* object, or
a tween or scene-tree timer belonging to a node that outlives what it animates. A tween that
frees a node belongs to that node. `tests/unit/test_signal_hygiene.gd` takes a census of every
autoload signal around building and freeing a HUD, a streamer, a stat bar and a Hearthstone, and
asks the SceneTree how many toast fades are still running over panels that are gone.

## 2026-09-22 · A region's `sun_elevation_scale` is its latitude, not a mood dial
**Decision.** Every region states a `sun_elevation_scale` that pulls the day's arc down to
the elevation its identity sheet describes, and the default falls from 1.0 to 0.55.
Hearthvale 0.53 (noon 44°), Brightwater 0.53 (52°), Briarwold 0.54 (49°), Skerrow 0.38 (37°);
Sedgemire and Cinderlea already sat low and are untouched. The elevation is also clamped
below vertical.
**Why.** `WorldClock.sun_elevation_deg()` is a bare `-cos(hour)` curve that reaches 90° at
noon — the sun directly overhead, a latitude Wickmere is not at. Only three regions set the
scale, so the rest inherited it, and at each region's own review hour four of the six ran a
sun between 60° and 94°. A sun that high casts a shadow between 0.18 and 0.59 of its caster's
height, straight down and hidden underneath it. Three separate frames were reported as having
"no shadows anywhere" — a village street, a chain bridge in a steep valley, the opening view
of Cinderlea — and in every one the shadows were there and were the size of a doormat.
Brightwater's +4° bias on top of a 90° noon also pushed the elevation past vertical, which
flips `cos(e)` negative and swings the sun's bearing to the far side of the sky between one
hour and the next.
**Alternatives.** Changing the curve in `WorldClock` itself was the obvious fix and is worse:
the clock is a core autoload that stealth, schedules and the light level all read, and the
shape of the day is not the same question as how high the sun gets at this latitude. The
per-region scale already existed for exactly this and three regions were already using it.
**Consequences.** A cottage on the green throws ten metres of shadow instead of three, and
houses visibly shadow each other in the morning. Two hours of this investigation went into a
wrong hypothesis first — that Terrain3D's ground does not receive shadows on the Compatibility
renderer — on the strength of a 16:30 street frame showing a shadowed house standing on lit
grass. It was wrong: with the sun brought down, a hawthorn lays a dappled leaf shadow across
the terrain with the individual leaf clusters legible in it. `tools_gd/shadow_probe.tscn` is
the instrument that settled it and is committed, because "the frame has no shadows" has three
unrelated causes — the light, the receiving surface, or the sun being too high to see them —
and a screenshot of the world cannot tell them apart.

## 2026-09-22 · Variation that is computed and then discarded is worse than none
**Decision.** `foliage_wind.gdshader` multiplies by `COLOR`, and imported standard materials
set `vertex_color_use_as_albedo`.
**Why.** The world builder has always given each scattered plant its own tint from the
region's palette, and writes it into the cell data: 88 distinct greens among 91 grass clumps
in a single cell of Merrowby. The streamer has always loaded them into the MultiMesh with
`use_colors`. The foliage shader never read `COLOR`, so every one of those greens drew as the
same green, and the same was true of every rock and stump for want of one flag on the
material. DESIGN §7.0.6 promises per-instance colour jitter; the pipeline computed it end to
end and threw it away at the last step, which is the most expensive kind of bug — it costs
the build time and the file size and delivers nothing.
**Consequences.** A field of grass now has the colour spread it was always carrying. It also
exposed a second fault immediately: the forge already builds each asset from its region's
palette, so multiplying that palette over it again paints the colour on twice, and a downland
vista came back littered with orange slabs where the gold barley and red poppies had been
multiplied by gold and red. Rules now carry a `tint_strength` (how far from white the
multiplier may travel, default 0.45) and the species whose asset already carries that colour
take none at all.

## 2026-09-22 · The opening is the Warden's voice over the real country, played in the world
**Decision.** The opening (DESIGN §5.1a) is data — a `core:cinematic/opening` definition of
shots whose cameras are placed relative to named places and to the ground beneath them, with
durations, time of day, weather, subtitle lines and a music cue — played by a small player
inside the streamed world after the Naming, on New Game only. The voice is Wren Tallow's,
in subtitles, saying back the name the player has just chosen. It ends on the gameplay
camera's own pose and hands over there, and the first quest starts at the hand-over.
**Why.** The game's first minute was a fade from black into control, with nothing said about
where you are, why, or what is wrong with the world. The Naming already *is* the Warden
asking your name at the top of the Stair, so the natural next beat is her answering, and her
lines already exist in her dialogue graph: the opening quotes the fiction rather than
inventing a narrator. Playing it in the world rather than as a film keeps it true to the land
as it is rebuilt — a stored height or a rendered video would be wrong the next time the world
builder runs, and the land is being reshaped while this is written — and it costs no new
tooling: the fly camera, the streamer, the atmosphere and the capture runner already exist.
**Alternatives.** A pre-rendered video (nothing here can encode one, and it would freeze the
country at whatever build it was shot from); painted still cards with text (cheap, but the
brief is a painted *world*, and it is the one thing the game can show that a card cannot);
a narrator outside the fiction (Wickmere's cosmology is told four contradictory ways on
purpose, and an omniscient voice would have to pick one); no opening (what shipped).
**Consequences.** The streamer must load the next shot while the current one plays, and must
be able to follow a camera without telling the game the player entered those regions — a
region change seeds rumours and moves music, and a camera is not a traveller. Every piece of
state the opening borrows (streamer target, clock, weather, buses, HUD, input, the current
camera) must be put back by the same code whether it is watched or skipped, and a test has to
hold the two end states against each other. The hook into the new-game flow is one call in
`GameServices.begin_new_game()`, the one place a new game already begins, and a setting stops
it for later new games. Reversible.

## 2026-09-22 · A stage number counts from one
**Decision.** Content names a quest stage by its id or by its number counted from one, in
`quest_at`, `quest_min_stage` and `quest_stage` alike. The code translates in one place,
`QuestLog.stage_index()`; `stage_of()` stays the index from nought and is never what content
writes.
**Why.** Every quest in the pack that writes stage numbers says in its own `notes` that they are
1-based, and the forty-eight numbered references all read correctly that way and wrongly the
other. The code compared them with the 0-based index, so each landed a stage late or on no stage
at all — among them the main thread's first conversation and every branch of six side quests.
**Alternatives.** Rewriting the forty-eight numbers as stage ids, which is what the later half of
the pack already does and is the sturdier habit. It would have made the test that pins them
tautological, and the numbers were written consistently; the fault was the reader, not the
writing. New content should still prefer ids.
**Consequences.** `test_quest_stage_references.gd` holds, for every number the pack uses, the
stage id its prose describes, and fails on a number nobody has explained. The fake quest provider
in `tests/fixtures/fakes.gd` counts the same way as the real log, so a test cannot pass against a
convention the game does not use.

## 2026-09-22 · The character's attributes start at 10, and the pools are the character's
**Decision.** Vigour, Endurance and Will start at 10, not 5, and there is one set of pool
formulas (`DamageModel`): stamina `100 + 8·Endurance`, mana `60 + 6·Will`, health from Vigour.
The Player reads the character's attributes (with modifiers) and refreshes its pools when a
level, a point or a modifier changes. Saves move to schema 4: `Migrations._v3_to_v4` adds the
5 to every saved attribute.
**Why.** DESIGN §5.3 gives the formulas and §5.6 says a level's point in Endurance raises
stamina. Measured before: the pools were a flat 180 / 120 / 100 whatever the attributes were,
while the character sheet held 5s, so the design's own formula gave 140 / 90 / 80 and a level
point changed nothing. Leveling kept a second copy of the formulas with different constants.
Starting at 10 makes the formula give the numbers the game was already balanced around.
**Alternatives.** Keeping 5 and changing the constants would have kept old saves untouched but
made every derived number (load capacity, noise, requirements) disagree with the sheet.
**Consequences.** Measured after: 180 / 120 / 100 at 10, 188 stamina and 126 mana after a
point. A v3 save loads with its attributes 5 higher, which is what it would have had.

## 2026-09-22 · Load is what is worn over what Endurance can carry, and the bag can overload it
**Decision.** Load = worn weight / (40 + 3·Endurance). Tiers: light below 0.3, medium below
0.7, heavy to 1.0, overloaded past it — and a bag carried past its capacity is overloaded
whatever is worn. Stamina regen is multiplied by 1.0 / 0.9 / 0.75 / 0.5 across the tiers
(`DamageModel.LOAD_REGEN_MULT`).
**Why.** DESIGN §5.3 has heavy load lengthen the roll and §5.7 says "Load affects dodge and
stamina regen", with no numbers. Measured before: a full plate kit and a sword read 24.3%
load (half the design's own reading), nothing could reach overloaded, and regen was 30/s at
every load. The capacity formula is new; the regen multipliers are chosen so a heavy kit costs
a quarter of the regen and an overloaded one half, which is felt in a fight without deciding it.
**Consequences.** A plate kit at Endurance 10 is 38.6% (medium); an overfull bag gives 129% and
the overloaded roll. Found and not fixed: gear alone cannot reach the heavy tier (the heaviest
kit in the pack is about 0.61 of capacity), so heavy and overloaded rolls are reachable only by
carrying too much.

## 2026-09-22 · A heavy's wind-up has hyper-armour 12; hit windows come from the clip
**Decision.** The player's heavy attack carries hyper-armour 12 (`DamageModel.HEAVY_HYPER_ARMOUR`)
from its start to its `hit_end`. A weapon's hit window is its clip's own `hit_start`/`hit_end`
(the rig's `.clips.json` sidecar) divided by the weapon's `speed`; the placeholder proportions
are the fallback. Light and heavy stamina costs are each weapon's own (18 / 32 are the iron
sword's; a dagger's light is 12).
**Why.** DESIGN §5.3: "hyper-armour frames on heavies ignore poise damage below a threshold",
and hit windows "per attack in the weapon data". Measured before: a player's heavy lost 8
poise to an 8-poise hit; 65 of 69 humanoid attacks threw their blow off the authored time
(56 early, 6 late, 3 never live) because the rig played the clip on its own schedule. The
AnimationDriver now keeps the time and the rig is stretched to it (worst of 100 attacks after:
0.017 s). Putting the window in the weapon data would duplicate what the clip already says,
and a clip that is re-forged would silently disagree with it.
**Consequences.** A held heavy measures 1.5×, a player's heavy loses 0 poise in its wind-up.

## 2026-09-22 · A backstab is from behind within 1.8 m; a sneak attack is on a foe that has not noticed
**Decision.** A light attack on a foe whose back is to the player within 1.8 m is a backstab
(×3, the Backstab clip); any blow on an enemy that is not in combat and whose detection is below
1 is a sneak attack (×6 with a dagger, per `DamageModel.crit_multiplier`). Both multiply
before armour, as §5.3 says crits do.
**Why.** §5.3 names both crits; measured before, neither ever happened.

## 2026-09-22 · A swing is a band from shin to crown, and knockback is metres
**Decision.** A swing's volume is a box `2·radius` wide along the reach, from 0.1 m to 1.9 m
above the ground for a person (`Hitbox.set_swing`, `WeaponInstance.SWING_BELOW/ABOVE` = 1.0 /
0.8 about the 1.1 m attack origin; an enemy's reaches from the ground to a little over its own
height). Knockback is a distance, as `HitData.knockback` always said: a shove starts at
`sqrt(2·14·metres)` m/s and runs down at 14 m/s² (`Actor.SHOVE_DECEL`), it moves the body by
`move_and_collide` and never enters `velocity`, two shoves add as distances, and a knockdown
carries at least 1.2 m (`KNOCKDOWN_SHOVE`) without adding to a blow that already throws further.
**Why.** DESIGN §5.3 says "capsules". The capsule sat at chest height (0.7–1.5 m) and missed
everything shorter: `./run.sh fights` measured 0 hits on four gutter drakes, and the reach test
fails on the old band. The shove was added to the velocity every frame; a body whose state only
damps velocity (stunned, knocked down) summed sixty of them a second, and the bristleback's
charge threw the player at 140 m/s off the edge of the arena.
**Consequences.** A 3.4 m knockback measures 3.4 ± 0.35 m. DESIGN §5.3's hitbox line is
amended to say band rather than capsule.

## 2026-09-22 · What an enemy does with patience, a leash, a pack and a circle
**Decision.** (1) Patience counts from the last sight of the target, not from the start of the
fight. (2) A fighter that leaves the fight mid-blow has the blow called off. (3) A leash that
breaks holds until the fighter is back within half its leash (`Brain.RETURN_HOME`), and on the
way home it turns only on somebody within 3 m (`Brain.REENGAGE_REACH`). (4) A pack member waits
on its ring and, with a blow ready, closes along its own bearing to its bite; slots are ordered
by where each member stands, not by instance id. (5) Circling is held to 1.4 rad/s about the
target (`Enemy.MAX_CIRCLE_RATE`).
**Why.** All five were found by the headless fights, each as a fight that could not end: (1) a
wolf past four seconds into any fight dropped to search the first frame a roll put the player
behind it; (2) the idle clip that replaced its attack stranded it lunging for ever; (3) a
kiting caster walked 50 m from a 32 m leash because seeing its quarry put it straight back in
the fight; (4) the ring (3.2 m) was wider than the bite (1.9 m), so a pack that met a player who
did not walk into it bit nobody in 120 s; (5) a wolf at 1.2 m went round the player once a
second, faster than any swing could be aimed. DESIGN §5.4's "do not chase past their
threshold" is (3).
**Consequences.** The arena's flank check still passes (smallest gap between three wolves 44°).
The fights are seeded and repeat exactly; the numbers after these changes are in PROGRESS.

## 2026-09-23 · The score follows the fight, the clock and the boss; the foley follows the ground
**Decision.** (1) An enemy entering or leaving combat says so (`EventBus.enemy_engaged`), and
while any is fighting the combat layer cannot fall below 0.6 of full. (2) Night (21:00–05:00)
is a music mode: melody −11 dB, a little of the deep stem (−14 dB). (3) A boss's phase change
reaches the score from the boss (`EventBus.boss_phase_changed`); the quest-stage stand-in is gone.
(4) Overlays (boss tracks, the menu theme) crossfade on two players. (5) Footsteps come from
distance covered (`Footfalls`, a stride of `0.35·speed + 0.6` m), on the collider's declared
surface, else water, else the region's new `identity.ground`. (6) A body sounds its def's
material when struck (construct → stone, treant → wood, knight or armour ≥ 11 → metal, else
flesh; a def's `material` overrides). (7) The Interior bus sends to SFX.
**Why.** Measured before: the combat layer came in only after a hit and fell back to exploring
eight seconds later in the middle of a fight nobody had landed a blow in; the score had no
night; the second boss track was reached only through a quest stage and was a cut (stop one
stream, start the next at −60 dB); nothing in the game called Foley at all -- no footstep,
no blow, no door, no button was ever heard -- and indoors every world sound went round the
Sounds slider, because the Interior bus sent straight to Master. DESIGN §8 asks for ambience per
time and "foley for surfaces"; the night mix is the score's answer to the same clock.
**Alternatives.** Footsteps off the forged rig's `footstep_l/r` clip events were rejected: the
AnimationDriver keeps the gameplay timeline and the rig is only stretched to it, a placeholder
body has no feet, and movement speeds are being changed by other work -- distance covered is the
same measure for every body at every speed. Applying the SFX volume to the Interior bus from
`Settings` was the other fix for the slider; routing is one line and cannot drift.
**Consequences.** `tests/unit/test_audio_wired.gd` drives every one of these from its real
trigger and measures levels a sixtieth of a second at a time (no player may move more than
3 dB in a step; outgoing and incoming tracks overlap). The headless fights check that every
fight is heard. Eleven sfx rows have nothing in the game that plays them (bells, thunder, wind
gust, wood creak, cart wheels, sand and snow footsteps); they are listed by the test on every run.
## 2026-09-23 · The built world is tracked, and the ground never depends on one plugin
**Decision.** The part of `game/world/generated/` the game reads at run time (the manifest,
`pois.json`, `roads.json`, `rivers.json`, `runtime/`, `cells/`) and `game/terrain_data/` are
tracked in git, named exactly by `.gitignore`; the full-resolution maps that only the terrain
import reads stay out. When Terrain3D cannot draw the ground — no library for the machine, no
regions on disk, regions that load as nothing — `FallbackTerrain` draws it from the 8 m runtime
height map, and `WorldStatus` refuses the world outright only when there is no world data at all.
**Why.** A player cloned the repository, pressed Play and stood on a grey void. The world was
never in the repository; building it needs Python, 8 GB and minutes, which the editor's Play
button does not do; and on a Mac the plugin had no binary at all. Every way in let them through,
because nothing asked whether there was ground, and `./run.sh flow` passed the void.
**Consequences.** About 310 MB of built data in the repository (a 207 MiB pack, most of it
Terrain3D's already-compressed regions), and a rebuild of the world is now a commit of that
data, which will diff. The runtime height map's 3 m block-mean offset became part of the
contract (CONTRACTS §6), because the fallback draws from it and it is visibly wrong without it.
## 2026-09-23 · The view belongs to the mouse, movement is relative to it, and there are three gaits
**Decision.** The camera rig is `top_level`: it follows the body's position every frame and never
its rotation, and `CameraRig.yaw` is a world yaw that only look input changes. W/A/S/D are
relative to that yaw. The body turns toward where it is going at a rate that falls with speed
(900°/s standing to 300°/s at a sprint) and moves the way it faces, giving up speed while a large
turn is still to make. Gaits are walk 1.8 m/s (a modifier or a light stick), jog 5.0 (the
default) and sprint 7.8 (held, stamina 8/s, locked out at empty until 25% is back), with 16 m/s²
up to a jog, 7 above it, 20 m/s² down from a jog and 12 above it.
**Why.** Measured, not argued. The rig was a plain child of the body, so the view looked along
body yaw + rig yaw while movement, respawn and saves all read the rig's yaw as the whole of it:
one second of D turned the body 90° and the view with it, with the mouse untouched, and swung the
compass in steps of up to 21° a frame. The player's report was "the mouse/movement relationship
seems off, hence the compass and orientation issues", which is that sentence exactly. The speeds
were 4.2 and 6.5 with no walk; the player said the movement was very slow and asked for a brisk
jog near 5 and a sprint of 7.5–8. Two things made 4.2 read slower than it was: the default gait
was posed as a crouch (the blend space fed velocity/6.5 = 0.65 sat beside Sneak_Walk at 0.5) and
the planted feet slid at 79% of ground speed, so the legs looked like a shuffle while the body
glided. Moving along the facing rather than straight along the stick is what stops a reversal
reading as a moonwalk; giving up speed for the turn is what stops it swinging a wide arc.
**Alternatives.** Keeping the rig under the body and subtracting its yaw everywhere it is read
(every reader has to remember, and the camera still moves at physics rate); velocity straight
along the stick with the body catching up (exact directions, but the body runs backward for a
third of a second after every reversal); DESIGN's first numbers (4.2 and 6.5).
**Consequences.** `Stealth` normalises noise by the sprint (a jog makes 0.51, where the old
default made 0.52), and its speeds are pinned to the player's by a test. On a pad, sprint moved
from the right-stick click, which it shared with lock-on and the camera toggle, to the left-stick
click, which the Sayings menu gave up (it is on B on the keyboard; the pad layout wants a pass of
its own). How the legs keep pace with these speeds is its own entry, below. Reversible: the
numbers are constants at the top of `player.gd`, and DESIGN §5.2 states them.

## 2026-09-23 · Physics is interpolated; what moves per frame opts out, and what jumps resets
**Decision.** `physics/common/physics_interpolation` is on and the jitter fix is off. Bodies move
in `_physics_process` as before and are drawn between ticks. A node moved every rendered frame
opts out with `PHYSICS_INTERPOLATION_MODE_OFF`: the camera rig, the fly camera, bone-attached
sockets, the atmosphere (sun, moon, the rain that follows the camera), a dropped item's bob, the
Echo's hover, the Naming's turning mannequin, and the UI roots. A node already in the world that
is put somewhere else calls `reset_physics_interpolation()`: the player's `teleport()` (which
respawn, loads, doors, jail and the console all go through), an enemy sent home, a villager put
indoors, a loaded actor.
**Why.** Measured in the engine, not assumed. A child moved every frame under an interpolated
parent is interpolated between ticks and trails: it read 3.61 where it had been put at 4, and
5.71 where it had been put at 6. The same child opted out sits exactly where it was put on top of
its parent's interpolated position, which is what a sword in a hand needs. A node moved on the
frame it enters the tree does not smear (the engine resets it on its first tick), so spawners
need nothing. An existing node moved without a reset does: moved from x = 4 to 500 it was drawn
at 254 for a frame, and at 500 with the reset.
**Alternatives.** Moving the camera in `_physics_process` (it would step at 60 Hz on a 144 Hz
display, which is the judder being fixed); interpolating by hand in the camera only (the body,
enemies and arrows would still step).
**Consequences.** Anything new that is moved per frame in `_process` must opt out, and anything
that teleports an existing node must reset it. Terrain3D 1.0.2 still calls the deprecated
`instance_reset_physics_interpolation`, which prints a warning at load and is harmless.

## 2026-09-23 · A new game starts at the Stair Head, with the Warden at her fire and a way marked north
**Decision.** A new game hands over at `core:poi/stair_head`, a Wardens' camp on the rim of the
Cinderlea cliff above the Hushline Stair, not at the Stair. The Warden is kept there by a
`holds` entry in her npc def (the dialogue's condition vocabulary, checked before her
timetable) from the moment a new game is named until the Foundling reaches the Choir. She speaks
first, in her own greeting for the moment, and the HUD writes each new objective under the
compass as it changes. The Naming's first stage asks only to speak to her, with its marker at the
camp. A new second stage, `the_choir`, sends the player 426 m north along waystones the camp's
dressing lays from its `path` to the Sunken Choir.
**Why.** The user's first minutes were a body alone on a grey pad in the Hush's water at the
foot of an 80 m cliff (the pad the world builder flattened for the Stair). An objective ("Go to
The Hushline Stair") was done the moment it appeared, the Warden it asked for was in Merrowby,
and nothing in view said where to go. From the rim the country opens north: the Choir's colossi
on the skyline, the heath, the Cantor's Seat. A camp there gives the first view something to
look at and a person to speak to, and the second stage a destination a minute and a half away.
**Alternatives.** Moving the Stair's own position to the rim (it is the land's to move, and the
builder's stair dressing goes downhill from its pad, so it needs a rebuild and a look before
anybody trusts it). Starting at Greyfold or Pilgrim's Ash (on the road, but a kilometre and
more from where the story says you come up). An escort with the Warden walking beside you (the
people stream is building escorts; this does not wait for them). Pinning the start in code
(the POI is data, and a content pack can move it).
**Consequences.** A POI written after the land was built is dressed where its def says, on the
ground as it stands, until the next build flattens it a pad (`WorldPois.unbuilt_entries`), the
same fallback `World.place_position` and `PlaceDiscovery` already made. A test holds the
waystones' way against the built ground (walkable, dry, clear of the spawned enemies) and says
which leg fails if the land moves under it. `quest_at` conditions on the Naming name its
stages by id, so a stage can be added without renumbering the Warden's dialogue. The `new_game`
flag now stays up through the opening, because it is what holds the Warden at the camp while the
pictures play.

## 2026-09-23 · The legs are played at the ground's speed, on one stride timeline, and stand up
**Decision.** `HumanoidModel.set_locomotion` takes the body's ground velocity in metres per second.
Every moving clip carries the ground speed it was made at (`speed` in the sidecar, CONTRACTS §3)
and lies on one shared one-second timeline, one stride cycle stretched to fit it. Every blend
keeps its silent inputs running, so all the gaits are always at the same phase. One time scale
sets the strides per second: the ground speed over the blended stride, held to 0.5–1.6 times the
clip's own rate. The forge re-authors the gaits at the game's speeds: Walk 1.8, Run (the jog)
5.0, a new Sprint at 7.8 and Sneak_Walk 1.5. They stand upright, with the stance sweep, the reach
and the hip bob timed as a person's are.
**Why.** Measured. At the old default of 4.2 m/s, the single 2D blend space fed velocity/6.5
posed the body three-quarters of the way into Sneak_Walk, with the hips 15.2 cm below standing.
The planted foot moved at 79% of the ground speed. The sprint played Walk and slid at 76%. The
forge's own Walk sank 11.4 cm peak to peak at every step, and its Run 23.9 cm. The legs folded
under the body with every contact, which is what a crouch-walk is. Stride-matched and
phase-locked, the planted foot moves at 0–2% of the ground at every gait and every blend.
Re-authored, the hips ride about 4 cm below standing with 5–6 cm of bob.
**Alternatives.** Root motion: the body would move at the clip's speed, and the design's speeds
would be whatever the clips said. Foot IK in the engine: it costs work per actor per frame, and
it hides a clip that is wrong. A playback speed per clip without a shared timeline: the feet
slide in every blend as the phases drift apart.
**Consequences.** A locomotion clip without a `speed` in its sidecar plays at rate 1 and slides. A
new gait clip must put its left foot down at phase 0 and its right at 0.5, which the forge's tests
pin. Walk_Back and the strafes are still made by the first stride model. The strafes' side-steps
are shortened (0.6 s, duty 0.5), so they no longer drop the hips 21 cm at every step. A diagonal
strafe slides, because blending two strides in rotation space does not add up to the diagonal: at a
fifth to a quarter of the ground speed with these clips (see the entry on the locked-on pace). The
rig bake rebuilds the body as well as the clips, and under Blender 4.2 the body the committed rig
was made with under 4.0 comes back with the same vertices but a different UV layout and repainted
textures. So the clips are baked into a scratch copy and moved onto the committed GLB by
`tools/forge/transplant_clips.py`, which changes nothing but the animations and checks that it did
not. When another branch changes the rig GLB, the merge takes that branch's GLB and transplants
these clips onto it, provided the two share a skeleton (the tool refuses otherwise). If they do
not, the merge re-runs the rig bake on the merged tree.

## 2026-09-23 · A tap of Sprint rolls; Ctrl and B still do, and Space stays jump
**Decision.** On the keyboard, a press of Sprint (Shift) let go within 0.22 s is a roll, and a
hold sprints. The sprint waits out those 0.22 s, so a tap is not a lurch forward and then a roll.
The Dodge action keeps Ctrl on the keyboard and B on a pad, and stays rebindable. The tap follows
whatever key Sprint is bound to. A setting (Controls, "A tap of Sprint rolls", on by default)
turns it off. It is off while Sprint is a toggle, because the tap is the toggle. It is off on a
pad, where the stick click is a sprint and nothing else and B rolls. Space stays jump.
**Why.** The playtest asked "no roll?". The roll did work. Measured from real key events through
the default bindings, Ctrl rolls a jogging body 3.31 m in the tick the key goes down, keeps it
untouchable for 0.30 s, and plays Dodge_F. But it was on Ctrl alone, a key the genre does not use
for a roll and a player does not find without reading. The games most players will have come
from put the roll on the run key (the Souls games: tap to roll, hold to run) or on Space. Space
is the jump here and stays so. A tap of Sprint makes the run key and the roll key the same key,
the one the hand is already on.
**Alternatives.** Roll on Space and move the jump: every player of every other genre presses
Space to jump, and a surprise roll off a ledge is worse than a surprise jump. Roll on Alt: that
is the walk key. Roll on the press of Sprint rather than its release: a roll cannot be told from
a sprint until the key is let go, which is why the Souls games roll on release too.
**Consequences.** A roll by tap starts when the key is let go, so up to 0.22 s after the press
where Ctrl's starts on it. A sprint starts 0.22 s after Shift goes down rather than at once; it
takes 0.4 s to reach sprint speed from a jog in any case. Letting Shift go and pressing it again
quickly in a sprint rolls. The hint strip and the controls page say "tap Shift" while the tap is
on, and name the Dodge key when it is not.

## 2026-09-23 · What the perks that named no system now mean
**Decision.** Each of the 28 perk stats nothing read is read where the thing it names happens,
and four of them needed a small system first. (1) **Fletcher's Thrift**: 40% of loosed arrows
and bolts survive where they land (`DamageModel.ARROW_RECOVERY`); one that stands in the world
is left there as a pickup, one that stays in a body comes out with the body's loot; the perk
makes it 65%. (2) **Mote-Catcher**: a foe whose last blow was a Kindling saying gives its killer
one Ember Mote (`Enchanting.MOTES_PER_WARMTH`), the perk two. (3) **Forager**: an ingredient
taken from the ground where nobody owns it and nobody dropped it is "picked", and the perk gives
one more. (4) **Second Skin**: worn armour counts at half its weight in the load the roll feels,
and the noise medium and heavy armour add over cloth (×1.3, ×1.7) is halved. Fair Dealing's
"buy for less" covers a house deed as well as a shop; Loud Name makes renown gained travel
further and leaves renown lost as it was.
**Why.** DESIGN §5.8 has motes "captured from slain foes with a Kindling spell", and nothing
captured them; DESIGN names no arrow recovery, no gathering and no armour-weight rule, and the
perk texts presuppose each. The figures are the smallest that make each sentence true: "a
quarter more of your arrows" needs a share that can take a quarter more, and 40% leaves the perk
a plain 65%; one mote a kill keeps motes an income for a Kindling-sayer rather than a flood (a
mote sells for about 18 marks).
**Alternatives.** Wild herbs to pick (the ground cover has a "herb" class) were not built: the
world is another agent's this round, and a harvest node on every herb is its own work. Forager
is therefore only as good as the ingredients lying in the world, which today are the ones
creatures drop.
**Consequences.** `tests/unit/test_perks_do_what_they_say.gd` takes all 34 perks on the player
scene and measures the number each text names; its last test fails when any of the 36 perk
stat keys has no reader anywhere in the game's scripts.

## 2026-09-23 · The Hearth Flask
**Decision.** Every character carries a Hearth Flask (`core:item/hearth_flask`): three swallows,
each restoring 40% of the drinker's greatest health; a swallow is a committed, rooted drink of
1.0 s with the warmth landing at 0.55 s, and a stagger before then spills it. Resting at a
Hearthstone and coming back from death fill it. It rides in the bag (the charges in the stack's
own data, so the save keeps them) and on the belt's first free slot, where the slot shows
swallows left against a full flask. Merchants will not buy it (tag `keepsake`), and "use" in the
bag does not drink it.
**Why.** DESIGN §5.5: "Resting at a Hearthstone: full restore, respawn point set, refills flask
charges." Nothing existed. DESIGN gives no numbers; these are the genre's: a filling that covers
most of one bad exchange, a drink long enough to be a decision rather than a reflex.
**Alternatives.** A dedicated key: every pad button is already bound, and the belt is how DESIGN
§5.16 has items used in a fight. The flask as a number kept on the player: the bag already saves
stack data, and an item has a name and a description to read.

## 2026-09-23 · Load is measured against 20 + 1.5·Endurance
**Decision.** The capacity that worn and wielded weight is measured against for the roll and for
stamina regeneration is `20 + 1.5·Endurance` (35 at the start), not `40 + 3·Endurance` (70). The
bands stay light below 30%, medium below 70%, heavy to 100%, overloaded past it.
**Why.** DESIGN §5.3: "Heavy load lengthens [the roll] and cuts i-frames", §5.7: "Load affects
dodge and stamina regen". Against 70 the heaviest kit in the pack reached 54%, so the heavy and
overloaded rolls were only ever a bag's. Against 35: leathers and a sword 25% (light), a
brigandine and a sword 51% (medium), clan plate and a greatsword 89% (heavy), clan plate and the
Bearer's clapper 109% (overloaded); twenty points of Endurance later the plate and greatsword
roll medium.
**Alternatives.** Lower bands (light below 20%, medium below 40%): the same reach, but the bands
are the ones every roll table in the genre uses and the capacity is the number nothing else
leans on.
**Consequences.** `test_every_load_band_can_be_reached_by_what_is_worn` equips the four kits at
base Endurance and checks each band. Every Calling still starts light (0 to 14% of capacity; the
Cragborn's axe and tunic are the heaviest).

## 2026-09-23 · The eleven sounds nothing played: five wired, six dropped
**Decision.** Wired: `bell_toll` to the Bell-bearer's toll and the Barrow Reeve's (and to the
Reeve ringing his hammer on the floor as his second phase opens), `bell_hand` to the bell-headed
weapons going live (the Tolling knight's mace, the Reeve's hammer, the Last Cantor's blade),
`bell_tavern` to coming through an inn's door, `footstep_snow` and `footstep_sand` to the snow
and the tide-flats the world builder paints. Footsteps on the terrain now read its paint: the
builder's twenty-one textures fall into eight surfaces (the grasses, heather and moss as the
Vale's grass; chalk, granite, limestone, fused stone and cobbles as stone; the dirt track and the
forest floor as dirt; mud, peat and the lake bed as mud; scree and shingle as gravel; snow, sand
and ash as themselves). Dropped: `bell_tower` (no bell in the world strikes the hours),
`thunder_near`, `thunder_far` and `wind_gust` (the ambience's storm and wind layers are the
thunder and the gusts, and nothing flashes or gusts as an event a one-shot could follow),
`wood_creak` (the ambience's creak pools are the creaking) and `cart_wheels` (no cart moves
anywhere in the game).
**Why.** The brief: wire each to its real event, or remove it if no event exists for it.
**Consequences.** `test_every_sound_the_game_asks_for_is_in_the_table_and_loads` now fails on
any row nothing in the game can play, and the audio toolkit's tests fail when the sfx manifest
or table holds an id the generator no longer makes.

## 2026-09-23 · A blade for the two Callings that started without one
**Decision.** The Wayfarer starts with a hunting knife beside the bow, and the Lantern-Clerk with
an iron dagger.
**Why.** With the scripted player blocking, rolling, drinking and saying what its Calling knows,
`./run.sh fights` found two Callings that cannot beat the first region's foes at level 1, which
DESIGN §5.1 and the Naming (WORLD_BIBLE §10: "Fight ash-wights") take for granted. Measured again
on the game as it stands after the movement rework (one run per Calling): without its dagger the
Lantern-Clerk, fists and a ward, died to the swarm with 85% of the drakes left and ran out of the
120 s on the pack (95% of the wolves left, 528 damage taken and survived only by drinking), the
hedge-wight (33% left) and the bravo (41%); without its knife the Wayfarer, a bow and thirty
arrows, died to the swarm with 60% of the drakes left. With the blades both win every danger-one
fight and the Naming (the Wayfarer in 3–58 s, the Lantern-Clerk in 13–32 s). The four other
Callings win the same fights in 2–69 s and are unchanged.
**Alternatives.** Wren handing every Foundling a blade in the Naming: it changes every Calling,
including the four that need nothing. Softer danger-one foes: four Callings beat them already,
which is the design working.
**Consequences.** Nobody beats the Barrow Reeve at level 1: four Callings die and two run out of
time with 47–73% of him left. He has 520 health and armour 6 against 3–11 a blow, and four to six
of his (22–36 each, a knockdown among them) kill a 100-health character, flask and all. He is the
third quest of the Wardens' line, behind 45 reputation and the quest before it, so this is not
tuned.
## 2026-09-23 · Software Vulkan gets the coarse ground, and the coarse ground says so out loud
**Decision.** `WorldStatus` does not start Terrain3D when the renderer draws through a
RenderingDevice (Forward+ or Mobile) and the adapter is Mesa's llvmpipe; the ground is the coarse
one and the title says why. `-- --terrain=terrain3d` tries Terrain3D anyway, and so does asking
for a number of clipmap rings (`-- --terrain-lods=N`, or `WICKMERE_TERRAIN_LODS`; nine when
nobody asks). `-- --terrain=fallback` asks for the coarse ground anywhere. Unless it was asked for,
the coarse ground is said across the title sheet, on a card when the player arrives and on a
"Coarse ground" plate in the top left corner that stays while the HUD is up.
**Why.** Measured. Terrain3D 1.0.2 alone in an empty project (a camera, a light, the node) crashes
lavapipe: under gdb all four `llvmpipe` rasterizer threads stop at one address in the driver's
compiled shader, on an indexed load out of range. When depends on the clipmap and the view, not on
the ring count alone: alone at 2 m spacing, 7, 8 and 9 rings of 32 drew 60 frames and 9 of 48
crashed, and at 1 m spacing 7 of 48 crashed on the first frame; in the game, 9 rings crash as the
world is built, and 7 drew the real terrain for 40 seconds of the New Game flow and then crashed
the same way. The line before each crash, "/root: The caller thread can't call the function
`propagate_notification()`", is Godot's crash handler sending NOTIFICATION_CRASH from that driver
thread; it is not there when gdb takes the fault first. None of the game's code touches the tree
from a thread: its one worker task (the streamer's `_parse_cell`) reads a file and parses JSON,
and nothing processes on a sub-thread group. And a player on Windows played for days on the
coarse ground, which one toast and one small line had announced, taking its plain grey hills for
the game's look.
**Alternatives.** Leaving Forward+ on llvmpipe to crash (nothing could shoot the world there).
Seven rings on llvmpipe by default (they crashed too, later). Upgrading Terrain3D: there is no
newer release (1.0.2 is the newest tag, its branch has one docs commit since, and `main` is
1.1.0-dev, without the deprecated call but without a release or binaries). Asking the driver to
bound its loads (Vulkan's robustness features): not a setting the project has.
**Consequences.** On software Vulkan the world is the coarse ground unless a tool asks, and then
it should take short captures; the Compatibility renderer's llvmpipe still draws Terrain3D. The
guard is a name match: when lavapipe or Terrain3D stops crashing, `--terrain=terrain3d` shows it
and the guard goes. Screenshots with the HUD up on the coarse ground show the plate; captures
have no HUD and do not.
## 2026-09-23 · The controls are taught on screen for the first minutes, and remembered by the game
**Decision.** A strip low in the HUD names move, sprint, roll, jump, use, strike and block with
the keys bound at that moment, or the pad's buttons while a pad is in use. Each item goes once
the thing has been done: moved for 1.2 s, sprinted 0.6 s, rolled, jumped, pressed use, swung,
held a guard 0.25 s. The strip goes when nothing is left, or after fifteen minutes of play.
What has been learned is a GameState flag, so it is saved with the game. The pause page reaches
a page of every control, read-only, with a button to the rebinding tab.
**Why.** The playtest asked "no roll?" of a roll that worked. Nothing on the screen named it,
and a player reads the foot of the screen long before a menu. Items go as they are done, not on
a timer, so the one control a player has not found keeps being shown. The first version kept
the learned list in the settings file. The test suite's own HUDs then taught that file every
control on this machine, and the next run's strip came up empty, which is exactly how a
shared settings file behaves for a second player on the same machine.
**Alternatives.** A tutorial sequence (the game has no place to put one before the Naming, and
players skip them). A timed strip that fades after a minute whatever was done (it teaches the
player who least needs it). Keeping the list in the settings (above).
**Consequences.** A new game is taught again, which a player who knows the controls will see
for the minute it takes to move, sprint, roll and jump. The Hints setting turns the strip off.

## 2026-09-23 · Locked on, the pace goes by the way you go: a jog at the foe, a side-step across
**Decision.** Locked on and not blocking, the body faces the foe and moves at 5.0 m/s straight
at it (the jog), 3.0 m/s across it and 1.8 m/s backing away, and on the ellipse through the
three in between (3.6 m/s on the forward diagonal). Blocking stays a guard walk at 1.56 m/s
(2.6 × 0.6) whatever the lock. Sprint while locked on breaks the strafe and keeps the lock: the
body turns to run where it is pushed at 7.8 m/s, the view stays on the foe, and letting go of
Sprint turns the body back to face the foe.
**Why.** The combat round's headless fights found that a locked-on player could not close on a
caster backing away at about 3 m/s. Every locked-on direction was capped at 2.6 m/s, so the gap
grew by 1.39 m over three seconds of pressing W. Locked on, W at a foe now closes the gap by
5.26 m in the same three seconds, and the lock holds. The action RPGs this game is read against
let a locked-on player advance at their run and keep strafes and backpedals slower. Advancing
is how a fight is joined; circling and retreating are how it is survived. The locked-on
sprint, lock kept, is the Souls convention: the lock is a choice about the view, and running
is a choice about the legs.
**Alternatives.** One locked-on speed for every direction at 3.2 m/s or more: it catches the
caster, but the backpedal outruns the clip (Walk_Back at 1.15 m/s cannot play faster than
1.84 without sliding) and a retreat becomes as good as an advance. Breaking the lock on sprint:
it throws away the target at the moment the player is chasing it.
**Consequences.** Each speed is within what its clip can play without sliding. Run is at 1.0x.
The side-steps are at 1.58x (0% slide measured at 3.0 m/s). Walk_Back is at 1.57x (0% at
1.8 m/s). The diagonals slide: at 3.64 m/s on the forward diagonal the planted foot moves at 28%
of the ground speed, and at 2.18 m/s backing off diagonally at 23%. It was 19% at the old 2.6
m/s. Diagonal clips or foot IK would take that out. `Player.locked_speed(way)` is the ellipse,
and test_lock_on_movement pins all of it.

## 2026-09-23 · A raised guard is a layer over the legs, and a turn on the spot steps
**Decision.** Block_Idle is held over the upper body in the Locomotion graph: a Blend2 filtered
to the bones above the hips (and the sockets hanging off them) mixes it over whatever the legs
are doing, easing in and out over 0.12 s. `HumanoidModel.play_intent("Block_Idle")` raises it
and keeps the body in Locomotion; `stop_intent()` or any other clip lowers it. The Block_Idle
state stays in the machine for anything that still wants the whole-body pose. A body turning on
the spot faster than 60°/s while standing is shown a side-step toward the turn at the pace its
feet travel round its middle (0.18 m out), up to 1.4 m/s, eased in and out.
**Why.** Filmed in the motion studio: played as a whole-body state, the guard froze the legs in
its stance, and a player walking behind it at 1.56 m/s glided across the ground with still feet.
Layered, the legs walk under it, with the planted foot at 2% of the ground speed, and the right
hand stays at chest height (0.01 m below the chest bone, where the walk swings it 0.29 m
below). A turn on the spot while guarding or locked on pivoted the whole body on planted feet at
up to 720°/s. The side-step makes it a step round, the cheapest thing that reads as a person
turning.
**Alternatives.** A guard-walk clip set (walk, strafes and backpedal each with the guard up):
that is four more clips to keep in step, and the layer gives the same picture from one pose.
Turn-in-place clips (90° and 180° steps): better, and the next thing to make if the side-step
reads as a shuffle in play.
**Consequences.** Enemies that raise a guard (`Enemy._guard`) get the same layer: they now walk
under their guard instead of gliding. Any new stance meant to be held over the legs is added
to `HumanoidModel.STANCE_CLIPS`.

## 2026-09-23 · A body comes in a step inside the door and goes out a pace and a half before it
**Decision.** Going in through any door stands the body just inside the interior's own door
(the one the way back is through), facing into the room. In a house that is at least 0.75 m in
from the inside of the wall, on the floor of the room the front door opens into, on the nearest
point of a 0.1 m lattice (2.0 m deep, 1.6 m either side) that keeps 0.45 m from every prop mesh on
that floor and from the walls, or 0.37 m where a room has no more room than that. In a deep place
it is 1.2 m in from its way out toward the middle of its chamber, on the rock. Going out stands
the body 1.5 m in front of the door it came in by, on what is under that spot, facing away from
the door. A game saved inside goes out by the door the save recorded.
**Why.** The brief, and what was measured: every house put the player in the corner of its first
room a metre up; every deep place put them in the middle of its mouth, 3-5 m from the way out;
leaving faced the door just left; and a loaded game left into the pocket at 50 km. The props were
measured, not taken from their kinds' stand-in sizes: Merrick's forge hearth and crate are larger
than the boxes they would be drawn as.
**Consequences.** `test_every_door_both_ways` walks all 24 doors both ways in the built world. A
forged house whose doorway has no clear spot says so in a warning, and the test fails on it.

## 2026-09-23 · The audio mixer is kept from memory the engine has freed
**Decision.** `AudioGuard` (systems/audio, stood up by Foley) takes the audio driver's lock at the
end of every frame's processing and lets it go at once, in every run: the game, the tests, the
fights. `-- --no-audio-guard` turns it off, for the reproduction. Music stems and ambience beds
write a volume only when it moves (`AudioGuard.ease_volume`).
**Why.** The crash that killed the fights, a headless unit run and a Forward+ world load had one
backtrace every time, in the audio mixing thread. StringName's copy constructor was called from
AudioServer::_mix_step as it copied a sound's bus details, which was called from _driver_process.
The stripped binary's frames were named by the strings each function refers to. Godot 4.7.2
swaps in new bus details whenever a playing sound's volume or panning changes. For an
AudioStreamPlayer3D that is every physics frame, because it compares a mix count it never
records. The engine frees the old details two AudioServer.update()s later, whatever the mixer is
doing, so a mixer descheduled between loading a sound's details and copying them reads freed
memory. The mixer holds the driver's lock for a whole mix. The barrier therefore waits out a mix
under way, and anything a later update() frees was swapped out before it. The measurements came
from holding only the mixing thread at that instruction under gdb (tools/debug/stall_mixer.py),
with frames paced at 60 a second:
* Without the guard, the reproduction crashed at the first 20 ms stall.
* Without the guard, it also crashed after 57 stalls of 10 ms.
* With the guard, it ran its 40 s through 1,434 stalls.
* The fights under 20 ms stalls crashed after 32 without the guard and survived 2,655 with it.
**Alternatives.** Holding the lock from the end of one frame to the start of the next. The first
version of the guard did that; it spans the frame's sleep in a paced game and starves the mixer.
One process per Calling in the fights: a crash still loses a Calling, and the game is still
exposed. Playing no audio in headless runs: the Foley, music and ambience tests test real
playback.
**Consequences.** When a mix is under way at the end of a frame, the frame waits for it: a
millisecond or two, or as long as the mixer is descheduled, which is a hitch where the engine
would have crashed. The fault is Godot's, and should be reported upstream with the reproduction:
AudioServer's graveyard frees by frame count and not by the mixer's progress, and
AudioStreamPlayer3D never records `last_mix_count`. `tools/debug/audio_race_check.sh` fails if the
reproduction stops crashing without the guard or crashes with it. The Jolt warning ("exceeded the
maximum number of jobs") that came before some crashes is starvation, not the cause: the
crashing thread was the mixer every time, and no project setting sets that limit.

## 2026-09-23 · The opening keeps the wall clock, cannot keep anyone, and is never saved into
**Decision.** The opening's pictures run on real seconds (`CinematicPlayer._real_delta`), not on
the engine's delta: a long frame after quick ones is a hitch and moves them on by a second at
most, a long frame after long ones is the machine and counts in full, and no frame moves a shot
past half its length, so every shot is drawn at least once past its middle. A shot waits for
its country four seconds at most and is then shown with what has come; its two settling frames
are skipped for the black and once that wait is spent. Six minutes after the first shot the
whole opening hands over the way a held key does, and after that nothing is waited for. A skip
is timed from the key going down, on the wall clock. The hand-over hands the world to the body
(`World.follow`) and stands the camp's people up at once. No slot is written while a cinematic
holds the game (`SaveSystem.hold_saves`, held from the first thing borrowed until `finished` has
been heard), and a world loaded from a slot never plays the opening, whatever its flags say: it
gets the story, not the pictures.
**Why.** Two flow runs on a tree carrying the opening sat in it for ten minutes, on its third
shot, at a load average of 20 to 25 on this machine's four cores. The last frame they drew was
the Spire playing, its first line on the screen: not a hold, and nothing waited for. Godot
slows the whole game rather than step physics more than eight times a frame, so a frame of five
or six seconds counts as an eighth of one. Measured on the same load with a log line per shot:
the name's six seconds took 37 s of the wall clock in six frames, and the engine counted 0.8 s
of them; timed on the engine, the Mere's twelve seconds would have taken ninety frames. The two
shots before the Spire used the probe's ten minutes up. Each hold also waited four frames to
settle, 25 to 30 s each on that machine. The Warden was not at her fire when control came back:
a point of interest's people wait for its dressing, which went with its cell when the camera
flew off, and the NPC streamer looks round every three quarters of a second of game time. The
probe then saved its slot in the middle of the opening, with the `new_game` flag still up, and
the `--load` run played the opening again from that slot.
**Alternatives.** Scaling the delta by the frame rate (the same thing, less plainly). Dropping
shots whose frames are slow (a player on a slow machine would lose the Warden's lines with
them). Saving the borrowed state's originals into the slot (every system that is borrowed
would have to know it; refusing the save is one line in one place).
**Consequences.** On a slow machine the pictures stay with the music and are drawn with fewer
frames; a line can fall between two frames there. A hold of two seconds says in the log which
of its cells are missing and where each has got to in the streamer, and every shot logs its
frames and wall time. The quicksave key says "Not saved while the opening plays." The flow
probe reads the opening just before each frame is drawn, so the picture it keeps is the moment
it read, and reports when the overall cap handed over.

## 2026-09-23 · Wickmere is drawn, not seeded
**Decision.** The world's geography is authored in `tools/world/atlas/atlas.json` (docs/ATLAS.md
says why each part is where it is). That covers the provinces and their ground, the ranges,
peaks, valleys, rivers, lakes, woods, coast and roads, and the start. The builder makes the land
from it, and noise decides only how a slope is broken. The places and points of interest were
moved to where the map puts them, and the country between them was filled until no walkable
ground is far from somewhere worth walking to. This supersedes "The land is built last, and the
places land on it" (2026-09-20).
**Why.** The playtest was dropped at the edge of a map of hilly nothingness with the odd tower
standing in it. It said the seed took the mystique away, and it was right. A generator that
does not know where anything stands cannot put a village where a valley opens, a road through a
coombe, or a bell-tower where the first view needs one. It also cannot say where the country is
empty. The earlier decision was sound for a generated world: a landscape negotiated with its
villages feels arranged. A drawn map is arranged on purpose, the way the maps of the games this
one stands beside are.
**Alternatives.** Constraining the generator by hand-placed stamps (the seed still owns most of
the ground, and the empty country with it). Shrinking the world until the old content filled it
(the brief was a sprawling world; with 297 locations and a density rule, 8192 m is full).
**Consequences.** Every place and POI has a position the atlas agrees with (check_atlas.py
refuses a place outside its region's provinces). tools/world/tests/test_atlas_map.py holds the
density: no walkable point more than about 400 m from a location, and no road more than about
250 m. A new location is placed on the map and not left to the builder. Tests that read the
tracked world (test_world_data, test_the_start, test_pois, the cinematic paths, the sightlines)
disagree with the moved content until the world is rebuilt from the atlas.

## 2026-09-23 · The map is written down once; everything else says what it is beside

**Decision.** A place's and a POI's `position` is the only place the map is written in
coordinates (the atlas writes it). Everything else that means "near that place" names the place
and says where from it: a compass bearing and a distance, an offset, a way's shape between two
places, or, for a position a save remembers, a pin (the nearest place, where it stood then, the
height above the ground). `PlaceRef` reads all four. A door plan no longer copies its place's
position, the Stair Head's way is a shape, the hand-written capture plans are place specs, and
the saves pin the player, the Hearth's landing and Echo, an interior's way out and an escort on
the road. `test_place_ref.gd` fails when a definition writes coordinates where a place belongs.
**Why.** The atlas moved 83 places and added 216. Every copy of a coordinate had to be found and
edited by hand to follow them. The land agent's branch did exactly that for the door plans, the
Stair Head's way and three tests, and the next redraw would need it again. Said as places, they
follow without anyone touching them, and on an unmoved map they resolve to the same points: a
way to 2 mm, a plan's camera to 7 mm, a save exactly.
**Alternatives.** A way drawn in coordinates with the two ends it was drawn against recorded
beside it, and re-fitted on load. That is easier to draw, but a way redrawn for the new map and
not re-recorded is moved twice. A table of where each place moved, applied to saves: it has to
be written for every redraw, and a save cannot say which table it predates.
**Consequences.** Anything new that stands near a place should say so as a spec;
tools/place_paths.py and tools/capture/relative_plan.py turn coordinates into one. The generated
capture plans (default, pois, look, horizon) are still coordinates: their generators read the
built world, and are run again after a redraw. A region's `map.center` is still the no-world
fallback for region lookups, and should be kept inside its region as the atlas draws it.

## 2026-09-23 · The Stair Head's waystones walk the road the builder routed

**Decision.** Where the built world has a road between a POI and the place its way leads to,
the waystones stand along that road: the one the path names (`built_road`), else the one named
for its two ends (`core:road/<from>_<to>`, either way round). The way's drawn shape is used only
where there is no road.
**Why.** On the atlas world the way drawn straight from the Stair Head to the Choir crossed
ground of 37 to 61 degrees; the builder's road goes round the knoll. DESIGN 5.1a asks for a way
marked on walkable ground.
**Alternatives.** Keeping the drawn shape and asking the cartographer to redraw it round the
knoll by hand: it would be walkable only on the build it was drawn against.
**Consequences.** The walk is the road's length: 980 m on the atlas world, against the 300-650 m
test_the_start holds it to. That is the atlas's distance, and it is left failing for the
coordinator to decide. On main's world there is no such road and nothing changes.
