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

## 3. Animation clip contract (humanoid)

Exported as glTF animations on the model; loop flag and events in a sidecar
`<model>.clips.json`:
```json
{"Walk": {"loop": true, "length": 1.0, "events": [{"t": 0.05, "name": "footstep_l"}, {"t": 0.55, "name": "footstep_r"}]},
 "Attack_1H_Light_1": {"loop": false, "length": 0.8, "events": [{"t": 0.32, "name": "hit_start"}, {"t": 0.48, "name": "hit_end"}, {"t": 0.55, "name": "cancel_ok"}]}}
```
Required clip names (v1):
* Locomotion: `Idle`, `Idle_Combat`, `Walk`, `Walk_Back`, `Run`, `Strafe_L`,
  `Strafe_R`, `Sneak_Idle`, `Sneak_Walk`, `Jump_Start`, `Jump_Loop`, `Jump_Land`,
  `Fall_Loop`
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

Creatures use their own rigs; their clips must include `Idle`, `Walk`, `Run`,
`Attack_1`, `Attack_2`, `Hit`, `Death`, plus archetype extras listed in the
enemy def under `clips`.

## 4. Forge output layout

```
game/assets/models/<category>/<name>/<name>.glb        LOD0 (+ LOD1/2 as separate meshes named <mesh>_LOD1...)
game/assets/models/<category>/<name>/<name>_*.png      baked textures (albedo, normal, orm)
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

## 6. World builder outputs (`game/world/generated/`)

* `world_manifest.json`: `{"seed", "size_m": 8192, "spacing_m": 2, "origin": [-4096, -4096], "grid": 4096, "sea_level": 0, "lake_level": 8, "regions": [ids in mask order], "cell_size_m": 256, "cells": [32, 32]}`
* `heights.r32` float32 little-endian, `grid × grid`, row-major, row = z.
* `region_mask.u8` region index per texel (255 = open water).
* `texture_base.u8`, `texture_overlay.u8`, `texture_blend.u8` (0–255) per texel.
* `color.rgba8` colour-map tint per texel.
* `water_mask.u8` (1 = water surface at lake/sea/river level), `flow.rg8` (river direction).
* `rivers.json`, `roads.json`: `[{"id", "points": [[x, z], ...], "width_m"}]`.
* `pois.json`: `[{"place_id", "pos": [x, y, z], "yaw", "scene": "res://...", "radius_flat_m"}]`.
* `cells/<cx>_<cz>.json`: `{"cell": [cx, cz], "region": id, "instances": {"<asset_path>": [[x, y, z, yaw_deg, scale, tint_hex], ...]}, "scenes": [{"scene": "res://...", "pos", "yaw", "props": {...}}], "spawns": [{"kind": "enemy|npc|animal", "def": id, "pos", "yaw", "group"}], "lights": [...]}`
Cell indices: `cx = floor((x + 4096) / 256)`, `cz = floor((z + 4096) / 256)`.

## 7. Content definitions that other streams depend on

* `item`: `{id, name, category (weapon|armour|consumable|ingredient|material|book|key|misc|tool), weight, value, description, model?, icon?, stack?, tags[], tier?, material? (what tempering consumes), weapon?{class, damage, poise_damage, stamina_light, stamina_heavy, speed, reach, clips_set (1H|2H|dagger|bow|staff|unarmed), parry: bool, stability}, ranged?{draw_time, reload_time, ammo}, armour?{slot, armour, weight_class, stability}, light?{range, energy, color}, ember?{charge}, effects?[], alchemy?{effects:[4 ids]}, origin? (ingredient's region)}`.
  Per-instance state lives on the stack, not the definition: `data{temper, enchant, effects, name, quality}`.
* `enemy`: `{id, name, archetype, model, rig (humanoid|custom), stats{hp, stamina, poise, armour, speed}, attacks[{name, clip, damage, poise_damage, range, telegraph, recovery}], perception{sight_range, sight_fov, hearing}, behaviour{...}, loot: loot id, marks:[min,max], lore}`
* `npc`: `{id, name, home_place, personality{traits[]}, schedule[{days, hour, place, activity, spot}], dialogue: id, faction?, appearance: seed/params, merchant?{stock table id, marks, buys[]}}`
* `quest`: `{id, name, layer (main|faction|side|radiant), stages[{id, journal, objectives[{type, target, count}], on_enter[], on_complete[]}], rewards}`
* `dialogue`: `{id, nodes{node_id: {speaker, text, conditions[], effects[], choices[{text, next, conditions[]}], next}}, start}`
Conditions and effects are arrays of small objects: `{"flag": "met_wren"}`,
`{"quest_at": ["core:quest/toll_hums", 2]}`, `{"rep_min": ["core:faction/wardens", 20]}`,
`{"renown_min": 50}`, `{"morality_min": 10}`, `{"skill_min": ["speech", 25]}`,
`{"has_item": ["core:item/x", 1]}`, `{"time_between": [20, 6]}`; effects:
`{"set_flag": ...}`, `{"give_item": [...]}`, `{"quest_stage": [...]}`,
`{"rep": [faction, delta]}`, `{"morality": delta}`, `{"renown": delta}`,
`{"marks": delta}`, `{"start_quest": id}`, `{"teach_recipe": id}`.

## 8. System discovery contract (pinned by tests)

Systems find each other by group, never by node path. These names and methods are pinned
by `game/tests/unit/test_inventory_contract.gd` and equivalents; changing one breaks
other streams.

| Group | Node | Methods other systems call |
|---|---|---|
| `player` | the player actor | `full_restore()`, `respawn(pos, yaw)`, `set_input_enabled(bool)`, `is_dead()`, `teleport(pos, yaw)`, `save_summary()` |
| `inventory` | the **player's** bag only | `marks`, `add_marks(n)`, `remove_marks(n)->int`, `add/remove/count/has`, `items()`, `weight()`, `capacity()`, `use(item)`, `drop(item, count)` |
| `equipment` | the player's paper doll | `slots()`, `equip(item, slot)`, `unequip(slot)`, `armour_total()`, `stability()`, `weight_class()`, `main_weapon()` |
| `progression` | skills/levels/perks | `skills()`, `level`, `attribute_points`, `perk_points`, `perks_for(skill)`, `take_perk(id)`, `spend_attribute(name)`, `mods` |
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

### Loot table shape

`{id, entries:[{item|table, weight, count:[min,max], conditions:{region, min_level, luck, flag, quest_at}}], guaranteed:[...], rolls:[min,max]}`.
Rolls are deterministic for a given `RandomNumberGenerator`.
