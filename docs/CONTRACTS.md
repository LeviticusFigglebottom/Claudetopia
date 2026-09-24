# CONTRACTS.md — interfaces between parallel work streams

These are binding. Change them only with a DECISIONS.md entry and a grep for users.

## 1. Units, axes, scale

* Metres. Character eye height 1.65 m; default character 1.78 m; door 2.1 m;
  one storey 3.0 m; table 0.75 m; a "chunky" stylisation of ~1.1× on props.
* Blender models face **-Y** (Blender front view). After glTF export they face
  **+Z** in Godot; actor scenes place the model under a `Model` Node3D rotated
  180° about Y so gameplay forward is **-Z**. Static props keep their own facing
  and placements store a yaw.
* Terrain: world origin at the centre; x east, z south (Godot); bounds
  ±4096 m. Height 0 = sea level; the Mere sits at +8 m.

## 2. Humanoid rig `WM_Humanoid_v1` (all humanoids: player, NPCs, human enemies)

Deform bones (exact names, `.L`/`.R` suffixes):
```
Root                      (ground, origin; carries no deformation)
└ Hips
  ├ Spine ─ Chest ─ Neck ─ Head
  │          ├ Shoulder.L ─ UpperArm.L ─ LowerArm.L ─ Hand.L
  │          └ Shoulder.R ─ UpperArm.R ─ LowerArm.R ─ Hand.R
  ├ UpperLeg.L ─ LowerLeg.L ─ Foot.L ─ Toe.L
  └ UpperLeg.R ─ LowerLeg.R ─ Foot.R ─ Toe.R
```
Socket bones (non-deforming, for `BoneAttachment3D`): `Socket.WeaponR`
(child of Hand.R, grip origin, +Y along blade), `Socket.WeaponL` (Hand.L),
`Socket.ShieldL` (LowerArm.L, forearm strap), `Socket.Back` (Chest, for
sheathed 2H/bows), `Socket.HipL` (Hips, scabbard), `Socket.Head` (Head, for
helms/hats/horns/halo), `Socket.Lantern` (Hand.L).
Rest pose: A-pose, arms 35° below horizontal, palms in. Feet flat at y=0.
Body proportions vary per character (the forge scales bone lengths); clips are
authored on the default proportions and retarget by bone-local rotation, so
they must not bake bone translations except `Hips` (vertical bob) and `Root`
(none; all locomotion is in-place, movement is driven by code).
No mesh object may be named after a bone. Godot's glTF importer renames the
*bone* when a mesh shares its name (a mesh called `Head` renamed the `Head`
bone to `Head_2`), which silently breaks every animation track that targets it.
The forge suffixes such meshes.

## 3. Animation clip contract (humanoid)

Exported as glTF animations on the model; loop flag and events in a sidecar
`<model>.clips.json`:
```json
{"Walk": {"loop": true, "length": 1.0, "events": [{"t": 0.05, "name": "footstep_l"}, {"t": 0.55, "name": "footstep_r"}]},
 "Attack_1H_Light_1": {"loop": false, "length": 0.8, "events": [{"t": 0.32, "name": "hit_start"}, {"t": 0.48, "name": "hit_end"}, {"t": 0.55, "name": "cancel_ok"}]}}
```
Required clip names (v1):
* Locomotion: `Idle`, `Idle_Combat`, `Walk`, `Walk_Back`, `Trot`, `Run`, `Sprint`, `Strafe_L`,
  `Strafe_R`, `Sneak_Idle`, `Sneak_Walk`, `Turn_L90`, `Turn_R90`, `Turn_L180`, `Turn_R180`,
  `Jump_Start`, `Jump_Loop`, `Jump_Land`, `Fall_Loop`
* Dodge: `Dodge_F`, `Dodge_B`, `Dodge_L`, `Dodge_R` (roll; i-frames from data)
* Melee: `Attack_1H_Light_1`, `_2`, `_3`, `Attack_1H_Heavy`, `Attack_2H_Light_1`,
  `_2`, `Attack_2H_Heavy`, `Attack_Dagger_1`, `_2`, `Attack_Unarmed_1`, `_2`,
  `Riposte`, `Backstab`
* Defence: `Block_Idle`, `Block_Hit`, `Parry`, `Hit_Light`, `Hit_Heavy`,
  `Stagger`, `Knockdown`, `Get_Up`, `Death_A`, `Death_B`
* Ranged/magic: `Bow_Draw`, `Bow_Aim`, `Bow_Release`, `Cast_Quick`, `Cast_Long`,
  `Cast_Loop`, `Throw`
* Life: `Interact`, `Pick_Up`, `Sit_Down`, `Sit_Idle`, `Stand_Up`, `Sleep_Idle`,
  `Work_Hammer`, `Work_Chop`, `Work_Stir`, `Work_Dig`, `Talk_1`, `Talk_2`,
  `Wave`, `Bow_Gesture`, `Laugh`, `Rude`, `Dance`, `Cheer`, `Cower`, `Point`,
  `Drink`, `Eat`, `Read`
Every attack clip has `hit_start`, `hit_end`, `cancel_ok` events. Locomotion
has footstep events. Death clips end in a held pose.

Every locomotion clip's sidecar carries `"speed"`: the ground speed in m/s at which its planted
foot stands still. It is load-bearing. The game plays a gait at (ground speed / `speed`), so a
clip authored at the wrong speed slides its feet by exactly the difference. `Walk`, `Run` and
`Sprint` are the three gaits of DESIGN §5.2 (1.8, 5.0 and 7.8 m/s), `Trot` a slow run between
the walk and the jog (3.6), `Sneak_Walk` is sneak (1.5), and `Walk_Back` and `Strafe_L`/`_R`
are the locked-on backpedal and side-steps (1.8 and 3.0). The gaits also share a phase: the
left foot goes down at phase 0 and the right at 0.5 in every one of them, because the game
blends them on one normalised timeline. A gait that breaks this blends out of step: halfway
through the blend one clip's foot is planted while the other's is swinging, and the leg comes
out as the average of the two, half lifted.

The turns on the spot carry `"turn"` instead: the degrees one cycle turns the body (+ to the
left). They are authored in the turning body's own frame, a planted foot going round the other
way, and the game plays them at (the body's turn / `turn`) cycles, as it plays a gait at the
ground's speed.

Every looping clip is a whole number of frames at 30 fps, its last frame its first again (the
forge's `check_contract` refuses one that is not). The keys start at frame 0: baked from frame 1,
every clip began with its first frame twice, and every loop stood still for a frame once a cycle.

A change to the clips alone does not re-bake the rig, which rebuilds and repaints the body too
and takes twenty minutes. `blender -b --python tools/forge/bake_clips.py -- --out <dir>` bakes
every clip onto the bare armature in under a minute, with the same functions, and writes the
sidecar. `tools/forge/transplant_clips.py` then moves the clips onto the committed
`humanoid_rig.glb`, bone by bone by name, and checks that nothing but the animations changed.

Creatures use their own rigs; their clips must include `Idle`, `Walk`, `Run`,
`Attack_1`, `Attack_2`, `Hit`, `Death`, plus archetype extras listed in the
enemy def under `clips`.

Godot strips a `_Loop`, `-loop` or `_cycle` suffix from an imported animation
name and sets the clip looping instead, so `Jump_Loop` arrives as `Jump` and
would collide with another clip. The contract names stay as written here; every
loader restores them from the `.clips.json` sidecar (`HumanoidModel` does this
in `_restore_contract_clip_names()`). Any other animated asset with such a name
needs the same treatment.

## 4. Forge output layout

```
game/assets/models/<category>/<name>/<name>.glb        LOD0 (+ LOD1/2 as separate meshes named <mesh>_LOD1...)
game/assets/models/<category>/<name>/<name>_*.png      baked textures (albedo, normal?, orm)
game/assets/models/<category>/<name>/<name>.meta.json  {generator, version, seed, params, tris:[lod0,lod1,lod2], collision, bounds, region_palette}
game/assets/models/<category>/<name>/<name>.clips.json (animated only)
```
Categories: `trees`, `flora`, `rocks`, `props`, `architecture/<culture>`,
`dungeon/<kit>`, `landmarks`, `characters`, `creatures`, `weapons`, `armour`,
`vfx_meshes`. Collision: `convex`, `trimesh`, `capsule`, `none`, or a
`<name>_col.glb` simplified mesh. Names are `snake_case`, seeds are stable.
Textures: albedo sRGB PNG, normal (OpenGL +Y) PNG, ORM (occlusion, roughness,
metallic) PNG; 512–2048 px; alpha in albedo for foliage.
Materials use the Principled BSDF only, so Godot imports them as
`StandardMaterial3D`; foliage materials are named `*_foliage` and the import
step swaps in the wind shader.

Region palettes: generators accept `--palette <region_id>` and read the six
hex colours from the region def; outputs record `region_palette`.


### LOD0 is one mesh, and it is the first one

A forge asset's `.glb` holds its **LOD0 as a single MeshInstance3D with one surface per
material**, and that first MeshInstance3D is the whole asset. `WorldStreamer` takes the first
mesh it finds and hands it to a MultiMesh; anything in a second mesh is silently dropped.

This is load-bearing and invisible from the file layout, and its violation is what emptied the
country: a tree exported as a trunk mesh plus a leaf-card mesh scattered as a bare trunk, four
hundred thousand times, and read as "the trees look like winter scrub" for a week.

Two consequences for the exporter. Joining meshes whose UV layers are named differently gives
the result both layers, each half-blank, so the layer name is normalised before the join —
otherwise every leaf card samples the bark atlas. And a prop that stands on the ground is
exported with `bounds.min[1] == 0.0`, enforced by a forge test, so nothing placing a prop has
to measure it.

## 5. Terrain texture slots (Terrain3D asset ids)

| id | name | id | name | id | name |
|---|---|---|---|---|---|
| 0 | vale_grass | 7 | granite | 14 | fused_stone |
| 1 | chalk | 8 | limestone | 15 | shingle |
| 2 | dirt_path | 9 | scree | 16 | cobbles |
| 3 | mud | 10 | snow | 17 | barley |
| 4 | peat | 11 | heather | 18 | orchard_grass |
| 5 | forest_floor | 12 | ash_soil | 19 | lake_bed |
| 6 | moss | 13 | grey_grass | 20 | sand_flats |

Each: `game/assets/textures/terrain/<name>_albedo_height.png` (RGB albedo, A
height) and `<name>_normal_rough.png` (RGB normal, A roughness), 1024², seamless.

A slot draws at its albedo texture's mean in linear light times its `value`
(`game/tools_gd/import_terrain.gd` SLOTS, written to `game/world/terrain_assets.tres` as the
asset's `albedo_color`, which Terrain3D multiplies in linear light). No slot draws under 0.02:
`tests/unit/test_ground_albedo.gd` fails if one does, or if the importer's table and the resource
disagree. `tools/world/ground_albedo.py` prints every slot as drawn and, in a built world, what
the ground is made of at a point.

## 6. World builder outputs (`game/world/generated/`)

* `world_manifest.json`: `{"seed", "size_m": 8192, "spacing_m": 2, "origin": [-4096, -4096], "grid": 4096, "sea_level": 0, "lake_level": 8, "regions": [ids in mask order], "cell_size_m": 256, "cells": [32, 32]}`
  The world is built from the atlas (`tools/world/atlas/atlas.json`, `tools/world/atlas/SCHEMA.md`),
  and the manifest also carries `"start": {"pos": [x, y, z], "facing_deg", "place"?}` (where the
  atlas puts a new game: on the ground, `facing_deg` a compass bearing, 0 north = -z, 90 east),
  `"lakes": [{"id", "level_m"}]` (every lake's own level; `lake_level` is the biggest's, and each
  texel's water level is `runtime/water_level_*.r32`'s) and `"atlas": {"name", "provinces", "crc"}`.
  A region of `regions` may be made of several of the atlas's provinces; `region_mask.u8` holds
  the region's index either way.
* `heights.r32` float32 little-endian, `grid × grid`, row-major, row = z.
* `region_mask.u8` region index per texel (255 = open water).
* `texture_base.u8`, `texture_overlay.u8`, `texture_blend.u8` (0–255) per texel.
* `color.rgba8` colour-map tint per texel.
* `control.u32` the same three texture maps pre-packed into Terrain3D's uint32 control format (`base << 27 | overlay << 22 | blend << 14 | hole << 2 | nav << 1 | auto`), so the import tool hands the image straight to `Terrain3DData.import_images`.
* `runtime/heights_1024.r32`, `runtime/regions_1024.u8`, `runtime/water_1024.u8`, `runtime/water_level_1024.r32`: quarter-resolution copies the runtime queries without Terrain3D (`TerrainProvider`), so height, region, water and water-level lookups work headlessly and in tests. `world_manifest.json` lists them under `"runtime"`.
  The regions, water and water level are point samples of every fourth full texel, so runtime texel `(i, j)` sits at `origin + 8 (i, j)`. The heights are a 4 x 4 block mean, so their texel `(i, j)` is centred at `origin + 8 (i, j) + 3 m`; consumers take the offset from the two grids, or from `runtime.height_offset_m` when the manifest carries it. They are also what `FallbackTerrain` draws the ground from when Terrain3D cannot, so the set the game reads at run time is: the manifest, `pois.json`, `roads.json`, `rivers.json`, `runtime/`, `cells/` and `game/terrain_data/`. That set is tracked; the rest of this directory is not.
* `water_mask.u8` (1 = water surface at lake/sea/river level), `flow.rg8` (river direction).
* The water masks, `water_mask.u8` and `runtime/water_1024.u8`, are one byte a texel: 0 is dry, and water is 1 (as the builder writes it) or 255, nothing else. A shader samples an 8-bit texture as byte/255, so a 1 reads as 0.004: `WaterSurface.mask_bytes` stretches a 0-and-1 mask to 0 and 255 as the game loads it, and the water shader discards under 0.5. Until it did, every lake and the sea were discarded and the lake bed showed through. `tests/unit/test_water_look.gd` loads the mask the manifest names the way the game does and fails if any texel the file marks wet would read as dry in the shader.
* `rivers.json`, `roads.json`: `[{"id", "points": [[x, z], ...], "width_m"}]`. A river also carries
  `width_from_m` and `width_to_m` (at its source and its mouth), `surface_from_m` and
  `surface_to_m` (its water there), and `surface_m`, the water surface at every one of its
  `points`, falling from source to mouth. A mountain river is not a straight ramp: it falls in its
  gorge and runs nearly level across its plain, so a reader drawing the water takes `surface_m`
  where it is given and the two ends only where it is not.
* `pois.json`: `[{"place_id", "pos": [x, y, z], "yaw", "scene": "res://...", "radius_flat_m", "radius_level_m"}]`. `scene` is omitted when no scene exists for that place yet, and consumers skip it.
  `radius_flat_m` is the pad's radius, the size the game's dressing, arrival rings and door plans
  are tuned to; the ground is not level all the way out to it. `radius_level_m` is how far out
  the ground truly is level at the pad's height: all of `radius_flat_m` for a settlement, 0.7 of
  it for a point of interest, and a place's own where it has one (Grandfather Hollow's 72 m). Past it the pad's skirt blends into the land. Anything that must
  stand on level ground, a settlement's houses above all, stays inside `radius_level_m`.
* `cells/<cx>_<cz>.json`: `{"cell": [cx, cz], "region": id, "instances": {"<asset_path>": [[x, y, z, yaw_deg, scale, tint_hex], ...]}, "scenes": [{"scene": "res://...", "pos", "yaw", "props": {...}}], "spawns": [{"kind": "enemy|npc|animal", "def": id, "pos", "yaw", "group"}], "lights": [...]}`
  An instance row may carry two more fields, `[.., lean_deg, lean_toward_deg]`: the instance is
  tipped `lean_deg` from upright, its top carried toward the ground direction
  `(cos, sin)(lean_toward_deg)` in x, z (the world builder writes them for trees the wind has
  bent). A six-field row stands upright, and a reader that takes only the first six fields sees
  the tree as it would have been, so old cells and old readers both still work.
  `WorldStreamer.instance_transform` applies it.
Cell indices: `cx = floor((x + 4096) / 256)`, `cz = floor((z + 4096) / 256)`.

## 7. Content definitions that other streams depend on

* `item`: `{id, name, category (weapon|armour|consumable|ingredient|material|book|key|misc|tool), weight, value, description, model?, icon?, stack?, tags[], tier?, material? (what tempering consumes), weapon?{class, damage, poise_damage, stamina_light, stamina_heavy, speed, reach, clips_set (1H|2H|dagger|bow|staff|unarmed), parry: bool, stability}, ranged?{draw_time, reload_time, ammo}, armour?{slot, armour, weight_class, stability}, light?{range, energy, color}, ember?{charge}, effects?[], alchemy?{effects:[4 ids]}, origin? (ingredient's region), furnishing?{prop, room?, spot?, storage?}}`.
  A **furnishing** is a `misc` item tagged `furnishing`, bought for a house the player owns
  from the landlord's side of the deed screen and drawn by `HouseInterior` when that house is
  built. `prop` is a prop *kind* `PropLibrary` can resolve (`cloth`, `chair`, `shelf`,
  `cupboard`, `chest` — not an asset path, because the forge builds a kind per region and a
  house you buy has no recipe line for a rug). `room` names the room it belongs in by the id
  the house forge gives it (`hearth_room`, `bed`, `store`, `study`, `hall`); a house without
  that room puts it by the hearth, which every house has. `spot` is `floor` (default) or
  `wall`. `storage: true` gives it a `WorldContainer` of its own, claimed for the player, so a
  chest you bought is somewhere to put things down. The item's `value` is what it costs; a
  furnishing rides in the `property` save section under the deed that bought it, not in the
  bag.
  Per-instance state lives on the stack, not the definition: `data{temper, enchant, effects, name, quality}`.
* `enemy`: `{id, name, archetype, model, rig (humanoid|custom), stats{hp, stamina, poise, armour, speed}, attacks[{name, clip, damage, poise_damage, range, telegraph, recovery}], perception{sight_range, sight_fov, hearing}, behaviour{...}, loot: loot id, marks:[min,max], lore}`
* `spell`: `{id, name, school (kindling|hush|binding|mending|calling), cast_type (projectile|self|aura|target|summon), cost, cast_time?, range?, speed?, radius?, duration?, clip?, description, effects[]}`.
  Effect shapes: `{"type": "damage", "kind", "amount", "poise"}`, `{"type": "status", "id", "duration", "magnitude"}`, `{"type": "heal", "amount"}`, `{"type": "shield", "amount", "duration"}`, `{"type": "cleanse", "ids": []}`, `{"type": "summon", "enemy": "core:enemy/x", "count", "duration", "radius"}`.
  A summon stands an ordinary `enemy` def up on the caster's side for `duration` seconds; it joins the `summon_ally` group, drops nothing, and lets go rather than dying. An enemy attack may carry the same block as `attack.summons{enemy, count, radius, cap}` to call help at the moment the blow lands.
  **A spell is not castable until the caster has been taught it.** Known sayings live on the `progression` node (`learn_spell` / `knows_spell` / `spells()`), ride in the `progression` save section as `known_spells[]`, and gate `SpellRuntime.can_cast(..., known)` — which answers `{"ok": false, "reason": "not_known"}`. An enemy caster's own spells need no teaching: `SpellCaster.known_lookup` defaults to yes.
* `book`: `{id, title, author, category: "book", body (markdown-lite), teaches_skill?, teaches_spell?, quest_hook?}`.
  `teaches_spell` is a full `core:spell/*` id: the first opening of that book teaches the saying, wherever it is opened (out of the bag, off a shelf, by a quest). An item reaches a book through its own `reads: <book id>`, or by being a `book`-category item whose short name matches a book id.
* `calling`: `{id, name, culture, home_region, skill_bonuses, signature_item, starting_items[], starting_reputation{}, starting_marks, starting_spells?[], description}`.
  `starting_spells` are `core:spell/*` ids the character comes up already knowing; only callings whose `skill_bonuses` include that saying's school should carry one.
* `npc`: `{id, name, home_place, personality{traits[]}, schedule[{days, hour, place, activity, spot}], dialogue: id, faction?, appearance: seed/params, merchant?{stock table id, marks, buys[]}, gone_when?: [conditions]}`
* `quest`: `{id, name, layer (main|faction|side|radiant), stages[{id, journal, objectives[{type, target, count}], on_enter[], on_complete[]}], rewards}`
  An objective that sends you to pick something up may say where it lies: `where` (a place, POI or interior id), `spot` (a dressing marker, a deep place's chamber, or a house's room), `owner` (an npc id: taking it is theft). A `choice` may name its host in `with`: an npc, or a place/interior where nobody is left to ask. The quest-item placer (`QuestItems`) reads all four; systems/quests/README.md has the rules.
  A `kill` says where the fight is: `where` (an interior id, or a place/POI id with `radius`, 140 m unless given), or `region` for a hunt; only a kill there counts (`KillPlaces`). In the open the stage stands up the foes it asks for (`QuestFoes`): the shortfall, or with `stand: "own"` its own group; `when` is an hour window (`always`, `day`, `night`, `dawn`, `dusk`, `midnight`).
* `encounter`: `{id, place, spawns[{enemy, count, when?, at?, spread?, unless?[conds], unless_present?, rises_when?}], lies?[{item | book, at?, count?, owner?}]}` — what a place's `encounter` sentence says stands or lies there, raised with its dressing (`PoiEncounters`, `QuestItems`). A `place` def may name a `dressing` kind (the Standing Moot: `standing_stones`) so the POI builders dress it.
* `dialogue`: `{id, nodes{node_id: {speaker, text, conditions[], effects[], choices[{text, next, conditions[]}], next}}, start}`
Conditions and effects are arrays of small objects: `{"flag": "met_wren"}`,
`{"quest_at": ["core:quest/toll_hums", 2]}`, `{"rep_min": ["core:faction/wardens", 20]}`,
`{"renown_min": 50}`, `{"morality_min": 10}`, `{"skill_min": ["speech", 25]}`,
`{"has_item": ["core:item/x", 1]}`, `{"time_between": [20, 6]}`,
`{"knows_spell": "core:spell/x"}`, `{"knows_recipe": "core:recipe/x"}`; effects:
`{"set_flag": ...}`, `{"give_item": [...]}`, `{"quest_stage": [...]}`,
`{"rep": [faction, delta]}`, `{"morality": delta}`, `{"renown": delta}`,
`{"marks": delta}`, `{"start_quest": id}`, `{"teach_recipe": id}`,
`{"teach_spell": "core:spell/x"}`.
**A quest stage is named by its id or by its number counted from one** — in `quest_at`,
`quest_min_stage` and `quest_stage` alike: `["core:quest/the_naming", 1]` is the Naming's first
stage, `["core:quest/the_naming", "wake"]` the same stage by name. `QuestLog.stage_index()` is the
only translation to an index (DECISIONS 2026-09-22, "A stage number counts from one").
`teach_recipe` and `knows_recipe` go through the context's **`recipes`** provider, which
`Social` binds to the first node in the `crafting` group, and whose methods are
`learn_recipe` / `knows_recipe`. `teach_spell` and `knows_spell` go through the context's **`sayings`** provider, which `Social`
binds to the first node in the `progression` group. A quest grants a saying the same way, through
its `rewards.effects[]`.

* `place`: `{id, name, region, kind, position:[x, z], unique_feature, tags[]}`.
  `kind` is load-bearing for the exterior: `WorldDoors` raises a built fabric around every
  place whose kind appears in `Settlement.FABRIC` (`city`, `town`, `village`, `hamlet`,
  `fort`, `lodge`, `camp`, `ruin_village`), and the kind picks how many houses, how big and
  how many storeys. A new settlement kind with no entry raises nothing, and
  `test_settlements.gd` fails the build rather than letting a place quietly stay empty.
  `region` picks the culture through `Settlement.CULTURE_BY_REGION`, which must name a
  culture that `Building.ROOF_BY_CULTURE`, `HouseInterior.CULTURE_SURFACES` and
  `Settlement.PROP_PREFIX` all know — also pinned by that test.

## 8. System discovery contract (pinned by tests)

Systems find each other by group, never by node path. These names and methods are pinned
by `game/tests/unit/test_inventory_contract.gd` and equivalents; changing one breaks
other streams.

| Group | Node | Methods other systems call |
|---|---|---|
| `player` | the player actor | `full_restore()`, `respawn(pos, yaw)`, `set_input_enabled(bool)`, `is_dead()`, `teleport(pos, yaw)`, `save_summary()`, `equip_spell(id) -> bool`, `knows_spell(id)`, `equipped_spell`, signal `spell_readied(id)` |
| `inventory` | the **player's** bag only | `marks`, `add_marks(n)`, `remove_marks(n)->int`, `add/remove/count/has`, `items()`, `weight()`, `capacity()`, `use(item)`, `read(item)`, `drop(item, count)` |
| `equipment` | the player's paper doll | `slots()`, `equip(item, slot)`, `unequip(slot)`, `armour_total()`, `stability()`, `weight_class()`, `main_weapon()` |
| `progression` | skills/levels/perks/sayings | `skills()`, `level`, `attribute_points`, `perk_points`, `perks_for(skill)`, `take_perk(id)`, `spend_attribute(name)`, `mods`, `learn_spell(id)`, `knows_spell(id)`, `spells()`, `known_spells` |
| `crafting` | recipes/alchemy/enchanting | `recipes_for(station)`, `craft(id)`, `known_effects(item)`, `combine(ids)`, `enchant(...)`, `disenchant(item)`, `consume_charge(item)` |
| `quest_log` | quests | `active_quests()`, `completed_quests()`, `active_markers()` |
| `dialogue_runner` | dialogue | `choose(index)`, `advance()`; signals `line_shown`, `choice_needed`, `ended` |
| `factions` | reputation & law | `reputation(id)`, `rank(id)`, `is_member(id)`, `law_faction_for_region(id)` |
| `standing` | morality & renown | `reaction_profile()` -> `{renown, renown_tier, morality, morality_tier, title}` |
| `crime` | bounty | `bounty(faction)`, `report_crime(dict)`, `pay_bounty(faction)` |
| `stealth` | visibility | `player_visibility()`, `player_noise()` |
| `atmosphere` | sky/weather | `weather_params()`, `set_region(id, instant)`, `force_weather(id)`, `set_interior(bool)`, `light_level_at(pos)` |
| `world` | terrain/streaming | `get_height(x, z)`, `region_id_at(x, z)`, `is_water(x, z)` |

Containers, corpses and merchant bags use the same `Inventory` class but must NOT join the
`inventory` group: only the player's bag does, so a lookup can never grab a chest.

### Every reference is a full namespaced id

Anywhere one definition names another, it uses the whole id (`core:effect/resist_cold`),
never a bare name. The one exception is `teaches_skill` on a book and `clips_set` on a
weapon, which are plain strings by design. Bare names silently skip validation, so a test
that resolves them is the only thing that catches the mistake.

### Loot table shape

`{id, entries:[{item|table, weight, count:[min,max], conditions:{region, min_level, luck, flag, quest_at}}], guaranteed:[...], rolls:[min,max]}`.
Rolls are deterministic for a given `RandomNumberGenerator`.
