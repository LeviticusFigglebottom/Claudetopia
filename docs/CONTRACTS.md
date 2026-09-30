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
Cloth bones (deforming, keyed by no clip): `Skirt.F`, `Skirt.B`, `Skirt.L`, `Skirt.R` (children of
Hips, from the hip joints' height to the knee's, in front of, behind and beside the legs) and
`Skirt.F2`, `Skirt.B2`, `Skirt.L2`, `Skirt.R2` (each a child of the one above it, from the knee to
above the ankle). Only a skirt is weighted to them; the body and every other part are not, and a
part's skin leaves them out when nothing in it is weighted to them. `SkirtDrive` (a
SkeletonModifier3D after the clips) poses them each frame from the thighs; a channel on one is a
contract break (`test_rig_contract`).
Rest pose: A-pose, arms 35° below horizontal, palms in. Feet flat at y=0.
Body proportions vary per character (the forge scales bone lengths); clips are
authored on the default proportions and retarget by bone-local rotation, so
they must not bake bone translations except `Hips` (vertical bob) and `Root`
(none; all locomotion is in-place, movement is driven by code).
No mesh object may be named after a bone. Godot's glTF importer renames the
*bone* when a mesh shares its name (a mesh called `Head` renamed the `Head`
bone to `Head_2`), which silently breaks every animation track that targets it.
The forge suffixes such meshes.


## 2b. Quadruped rig `WM_Quadruped_v1` (every hoofed four-legged animal: horse, deer, ...)

One rig, one set of bone names, for every hoofed beast; what differs is its proportions
(`QuadProportions` in `tools/forge/lib/quadruped.py`: `withers`, `body_length`, `leg_length`,
`neck_length`, `head_size`, `bulk`, `width`, `tail_length`, `cannon`). Hounds and wolves (paws, a
flexing spine) are not on it. Deform bones (exact names):
```
Root                        (ground, origin; carries no deformation)
└ Hips                      (the lumbosacral joint; the croup turns about it)
  ├ Spine1 ─ Spine2 ─ Chest ─ Neck1 ─ Neck2 ─ Head ─ Jaw
  │                    │                         ├ Ear.L
  │                    │                         └ Ear.R
  │                    ├ Scapula.L ─ Humerus.L ─ Forearm.L ─ FrontCannon.L ─ FrontPastern.L ─ FrontHoof.L
  │                    └ Scapula.R ─ ...                                                      FrontHoof.R
  ├ Thigh.L ─ Gaskin.L ─ HindCannon.L ─ HindPastern.L ─ HindHoof.L
  ├ Thigh.R ─ ...                                     HindHoof.R
  └ Tail1 ─ Tail2 ─ Tail3
```
The joints, head of each bone: the scapula's top, the point of the shoulder (Humerus), the elbow
(Forearm), the knee (FrontCannon), the fetlock (FrontPastern), the coronet (FrontHoof, whose tail is
the toe on the ground); the hip joint (Thigh), the stifle (Gaskin), the hock (HindCannon), the
fetlock and the coronet.
Socket bones (non-deforming): `Socket.Saddle` (Spine2: the lowest point of the seat, where a
rider's hips sit, +Y up), `Socket.Bit` (Head: the near bit ring, where the reins start),
`Socket.Pack` (Spine1: behind the saddle), `Socket.Head` (Head: on the poll, for antlers).
Rest pose: standing square, all four soles flat at y=0, the head carried with the face about 40°
off vertical. Axes and facing as §1. The same rules as §2 hold: clips retarget by bone-local
rotation, translate only `Hips`, and no mesh is named after a bone.

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
  `Stagger`, `Knockdown`, `Get_Up`, `Death_A`, `Death_B`; `Hit_Light` and `Stagger` are a
  blow from in front, and `Hit_Light_B`, `_L`, `_R` and `Stagger_B`, `_L`, `_R` the blow from
  behind, the left and the right (`Actor.reaction_clip` picks; a body without them plays the front's)
* Ranged/magic: `Bow_Draw`, `Bow_Aim`, `Bow_Release`, `Cast_Quick`, `Cast_Long`,
  `Cast_Loop`, `Throw`
* Life: `Interact`, `Pick_Up`, `Sit_Down`, `Sit_Idle`, `Stand_Up`, `Sleep_Idle`,
  `Work_Hammer`, `Work_Chop`, `Work_Stir`, `Work_Dig`, `Talk_1`, `Talk_2`,
  `Wave`, `Bow_Gesture`, `Laugh`, `Rude`, `Dance`, `Cheer`, `Cower`, `Point`,
  `Drink`, `Eat`, `Read`
Every attack clip has `hit_start`, `hit_end`, `cancel_ok` events. Locomotion
has footstep events. Death clips end in a held pose. Every clip with a blow (the attacks, the
casts, Throw, the work cycles) also has `cocked`: the moment its wind-up has drawn all the way
back. A foe's telegraph longer than the clip's own wind-up is held there, not played in slow
motion (AnimationDriver.hold_windup).

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


### 3b. Quadruped clips (`WM_Quadruped_v1`)

Sidecar and naming as §3. A mount's clips (v1): `Idle`, `Graze`, `Walk`, `Trot`, `Canter`,
`Gallop`, `Walk_Back`, `Turn_L90`, `Turn_R90`, `Stop`, `Rear`, `Mount`, `Dismount`. A wild
beast adds the creature set of §3 (`Run` is its canter or bound, `Hit`, `Death`).

The gaits are made by one generator (`tools/forge/lib/quad_clips.py`, `GaitSpec`) from:
`speed` (m/s, the ground speed at which the planted hooves stand still: written to the sidecar
as for the humanoid), `cycle` (s, one stride: two steps of each leg is never one cycle),
`duty` (the share of the cycle a hoof is on the ground), `footfalls` (the phase, 0..1, at which
each hoof `FL`, `FR`, `HL`, `HR` touches down), `lift` (the hoof's height in the swing, m),
`fold` (how far the knee and hock fold in the swing, 0..1), `bob` (the trunk's rise and fall, m),
`pitch` (the trunk's rocking, degrees), `nod` (the head's, degrees) and `flex` (the loin's bend,
degrees, for the canter and gallop). **The hind left hoof lands at phase 0 in every gait**, as the
humanoid's left foot does, so the game's gait blend keeps the legs in step. Every hoof's landing
is an event: `hoof_fl`, `hoof_fr`, `hoof_hl`, `hoof_hr`. The turns carry `"turn"` as §3's do.

The horse's gaits (`quad_clips.HORSE_GAITS`), for reference:

| Gait | speed | cycle | duty | FL | FR | HL | HR |
|---|---|---|---|---|---|---|---|
| Walk (four-beat, lateral) | 1.8 | 1.00 | 0.60 | 0.25 | 0.75 | 0.0 | 0.5 |
| Trot (two-beat, diagonal) | 3.8 | 0.70 | 0.38 | 0.5 | 0.0 | 0.0 | 0.5 |
| Canter (three-beat, left lead) | 7.0 | 0.533 | 0.28 | 0.22 | 0.02 | 0.0 | 0.80 |
| Gallop (four-beat, left lead) | 11.5 | 0.433 | 0.21 | 0.34 | 0.22 | 0.0 | 0.87 |

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
|  |  |  |  | 21 | crag |
|  |  |  |  | 22 | talus |

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
* `runtime/shore_1024.u8`: what kind of shore each texel near the water's edge is (`tools/world/worldgen/shores.py`), for the water's foam and the shore's sound. Same lattice as `runtime/water_1024.u8`. The manifest lists it as `runtime.shore`, with the class names in order as `runtime.shore_classes`: 0 `none`, 1 `sand`, 2 `shingle`, 3 `rock` (a ledge, the wave-cut platform at a cliff's foot, a stack or a skerry), 4 `cliff` (a face standing out of the water), 5 `mud` (a marsh's or a lake's soft edge, the tide-flats), 6 `reeds` (a reed bed in a lake's shallows). The land within 60 m of the water carries the kind of its own bank, and the water within 60 m of the land the kind of the bank it laps, so a reader at a wet texel knows what the water breaks on; a sandy bay's dunes carry `sand` further back (to about 210 m). Every other texel is 0. The sea, the lakes, the rivers and the marsh's pools are all classed.
* `water_mask.u8` (1 = water surface at lake/sea/river level), `flow.rg8` (river direction).
* The water masks, `water_mask.u8` and `runtime/water_1024.u8`, are one byte a texel: 0 is dry, and water is 1 (as the builder writes it) or 255, nothing else. A shader samples an 8-bit texture as byte/255, so a 1 reads as 0.004: `WaterSurface.mask_bytes` stretches a 0-and-1 mask to 0 and 255 as the game loads it, and the water shader discards under 0.5. Until it did, every lake and the sea were discarded and the lake bed showed through. `tests/unit/test_water_look.gd` loads the mask the manifest names the way the game does and fails if any texel the file marks wet would read as dry in the shader.
* `rivers.json`, `roads.json`: `[{"id", "points": [[x, z], ...], "width_m"}]`. A river also carries
  `width_from_m` and `width_to_m` (at its source and its mouth), `surface_from_m` and
  `surface_to_m` (its water there), and `surface_m`, the water surface at every one of its
  `points`, falling from source to mouth. A mountain river is not a straight ramp: it falls in its
  gorge and runs nearly level across its plain, so a reader drawing the water takes `surface_m`
  where it is given and the two ends only where it is not.
  A river also carries `falls`: `[{"top": [x, y, z], "foot": [x, y, z], "height_m", "width_m",
  "run_m", "facing_deg", "kind", "pool"?}]`, every stretch where its water falls faster than one in one
  (between points 5 m apart) by 2 m or more. `top` is the water at the lip and `foot` the water at
  the bottom, both on `surface_m`'s line; `height_m` is the drop, `width_m` the river's width at
  the lip, `run_m` how far the face runs across the ground, and `facing_deg` the bearing the face
  looks out along, downstream (from +z toward +x). `kind` is `fall` where the drop is at least twice
  the run (a sheet over a lip) and `cascade` where it is less (water down a stepped face). A fall of
  6 m or more has a plunge pool where there is room for one before the next drop,
  `{"centre": [x, y, z], "radius_m", "depth_m"}`: a round basin of still water at the foot's level,
  cut into the land (it is in the water mask and the level map), `depth_m` under its surface at
  its deepest. The ribbon still runs down the face: a reader drawing a proper fall draws it over
  that stretch instead. The list is empty for a river with no falls.
* `pois.json`: `[{"place_id", "pos": [x, y, z], "yaw", "scene": "res://...", "radius_flat_m", "radius_level_m"}]`. `scene` is omitted when no scene exists for that place yet, and consumers skip it.
  A waterfall POI's entry also carries `fall`: `{"facing_deg", "foot_m", "top_m", "form", "river", "faces": [{"behind_m", "drop_m"}]}`. The land is stepped there (tools/world/worldgen/falls.py): level at `foot_m` (the pad's level and `pos`'s y) in front of the first face, and `drop_m` higher behind each face, whose line is `behind_m` behind `pos` along the facing and square across it. `facing_deg` is the way the water goes over, as a yaw about +Y measured as `PoiKit.yaw_of` measures it (0 is +z, 90 is +x). The ground climbs from a face's foot to its top over the 3 m behind that line. `form` is the dressing's (`single`, `glass` or `terraced`), and `river` is the atlas river that falls there (rivers.json has the fall), or "" where none does. `line` is the faces' line in plan, `[[across_m, forward_m, drop_share], ...]` every 2 m from -48 to 48 m across (+ to the left of the facing, `(-fz, fx)`): at `across_m`, every face stands `forward_m` further forward (along the facing) than its `behind_m`, and has `drop_share` of its drop. It is 0 forward and all of the drop at the centre (the river's line). In the middle it bows forward as the dressing's own face does (poi_builders._rock_face, `4 * 0.18 * width * t^2`), easing off before it reaches the pad's centre line. Past the dressing's end or the pad's level radius, whichever is further out, the wings swing forward round the pool, wander by up to a metre or so, and fall to about half the drop toward their ends. Between samples, interpolate linearly. An entry with no `line` is square across with the whole drop.
  A cave POI's entry carries `cave`: `{"facing_deg", "mouth_m", "face_top_m", "mouth_behind_m", "face_half_width_m"}`. The land rises behind the cave's mouth for it to go into (tools/world/worldgen/falls.caves): level at `mouth_m` (the pad's level and `pos`'s y, the floor at the mouth) in front of the mouth's line, `mouth_behind_m` behind `pos` along the facing, and at `face_top_m` from 3 m behind that line, back across the pad. `facing_deg` is the way the mouth looks out (away from the hill; measured as `PoiKit.yaw_of`). `face_half_width_m` is how far either side of the facing's line a raised knoll stands at full height, falling to the pad over 10 m more; it is null where the pad is a shelf cut into ground that already rises the whole face, across the pad.
  `radius_flat_m` is the pad's radius, the size the game's dressing, arrival rings and door plans
  are tuned to; the ground is not level all the way out to it. `radius_level_m` is how far out
  the ground truly is level at the pad's height: all of `radius_flat_m` for a settlement, 0.7 of
  it for a point of interest, and a place's own where it has one (Grandfather Hollow's 72 m). Past it the pad's skirt blends into the land. Anything that must
  stand on level ground, a settlement's houses above all, stays inside `radius_level_m`.
  A point of interest's or a wayside find's pad (not a settlement's, an atlas `pads` one or a
  fall's or cave's step) is not dead level inside `radius_level_m`. It keeps the land's lie
  (roads.pad_relief): a tilt with the land round it of at most 6%, and a gentle roll of up to
  about 0.45 m over 30 to 60 m, both nothing at `pos`, which is the pad's level. Within 5 m of `pos`
  (a quarter of the radius on a small pad) it is level but for the tilt. A 4 m footprint anywhere
  on it lies within about a quarter metre of level, so a dressing sets each prop on the ground
  under it (`PoiKit.on_ground`), not at `pos`'s y.
  An entry may carry `"pad_shape"`: `"slope"` (a cave's, a quarry's, a cave-mouthed delve's, or a
  def that asks: the land as it lies, its banks and benches kept, only softened by a 5 m blur) or `"trench"`, with the def's
  `"trench"` ({bearing_deg, length_m, ramp_m, width_m, depth_m, behind_m, head_width_m, head_from_m,
  side_m}; roads.trench_depth) sunk into the pad. Absent, the pad is the level one above.
* `cells/<cx>_<cz>.json`: `{"cell": [cx, cz], "region": id, "instances": {"<asset_path>": [[x, y, z, yaw_deg, scale, tint_hex], ...]}, "scenes": [{"scene": "res://...", "pos", "yaw", "props": {...}}], "spawns": [{"kind": "enemy|npc|animal", "def": id, "pos", "yaw", "group"}], "lights": [...]}`
  An instance row may carry two more fields, `[.., lean_deg, lean_toward_deg]`: the instance is
  tipped `lean_deg` from upright, its top carried toward the ground direction
  `(cos, sin)(lean_toward_deg)` in x, z (the world builder writes them for trees the wind has
  bent, for seated rocks, and for a wall, hedge or rail piece pitched with the ground along its run,
  toward its low end, 24 degrees at most: tools/world/worldgen/lines.py). A six-field row stands upright, and a reader that takes only the first six fields sees
  the tree as it would have been, so old cells and old readers both still work.
  `WorldStreamer.instance_transform` applies it.
  A ninth field, `[.., lean_deg, lean_toward_deg, [sx, sy, sz]]`, is a scale in the asset's own
  axes that stands in for the uniform `scale`: `Wayside` writes it at runtime for a wall or hedge
  piece it has stretched along its line to meet the next (and `0, 0` for the lean it does not
  have). The builder writes it for the sea cliffs' ledges (tools/world/worldgen/crags.coast_walls), whose
  beds each have their own thickness, a vertical stretch of the module, and for a wall or hedge piece
  stepped down ground steeper than it may be pitched (lines.seat): split into two or three, each
  `[scale / n, scale, scale]`, a third or half of the module along its run. (Wayside's wall rebuild
  sets its own stretch on a drystone wall row and keeps the lean pair, so a stepped wall is drawn as
  overlapping full modules, a wall stepping down the bank.) Elsewhere it does not; a reader that takes eight fields sees the piece at its
  uniform scale.
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
* `enemy`: `{id, name, archetype, model, rig (humanoid|custom), stats{hp, stamina, poise, armour, speed}, attacks[{name, clip, damage, poise_damage, range, telegraph, recovery}], perception{sight_range, sight_fov, hearing}, behaviour{...}, loot: loot id, marks:[min,max], lore, holds?}`. `holds` is what a humanoid is seen holding when its attacks' `weapon_class` names nothing the forge makes: an item id, or `class:<weapon class>`. It changes only the look.
* `spell`: `{id, name, school (kindling|hush|binding|mending|calling), cast_type (projectile|self|aura|target|summon), cost, cast_time?, range?, speed?, radius?, duration?, clip?, description, effects[]}`.
  Effect shapes: `{"type": "damage", "kind", "amount", "poise"}`, `{"type": "status", "id", "duration", "magnitude"}`, `{"type": "heal", "amount"}`, `{"type": "shield", "amount", "duration"}`, `{"type": "cleanse", "ids": []}`, `{"type": "summon", "enemy": "core:enemy/x", "count", "duration", "radius"}`.
  A summon stands an ordinary `enemy` def up on the caster's side for `duration` seconds; it joins the `summon_ally` group, drops nothing, and lets go rather than dying. An enemy attack may carry the same block as `attack.summons{enemy, count, radius, cap}` to call help at the moment the blow lands.
  **A spell is not castable until the caster has been taught it.** Known sayings live on the `progression` node (`learn_spell` / `knows_spell` / `spells()`), ride in the `progression` save section as `known_spells[]`, and gate `SpellRuntime.can_cast(..., known)` — which answers `{"ok": false, "reason": "not_known"}`. An enemy caster's own spells need no teaching: `SpellCaster.known_lookup` defaults to yes.
* `book`: `{id, title, author, category: "book", body (markdown-lite), teaches_skill?, teaches_spell?, quest_hook?}`.
  `teaches_spell` is a full `core:spell/*` id: the first opening of that book teaches the saying, wherever it is opened (out of the bag, off a shelf, by a quest). An item reaches a book through its own `reads: <book id>`, or by being a `book`-category item whose short name matches a book id.
* `calling`: `{id, name, culture, home_region, skill_bonuses, signature_item, starting_items[], starting_reputation{}, starting_marks, starting_spells?[], description}`.
  `starting_spells` are `core:spell/*` ids the character comes up already knowing; only callings whose `skill_bonuses` include that saying's school should carry one.
* `npc`: `{id, name, home_place, personality{traits[]}, schedule[{days, hour, place, activity, spot}], dialogue: id, faction?, appearance: seed/params, merchant?{stock table id, marks, buys[]}, carries?{main_hand?, off_hand?} (item ids, or `class:<weapon class>` for a plain one: sheathed through the day, drawn when hostile), gone_when?: [conditions]}`
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
