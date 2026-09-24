# The horizon: what Wickmere shows past the streamed ring

**What this is for.** The streamer builds the world out to `far_ring` 2: 5×5 cells, so between
384 m and 640 m from the player depending on where they stand in their cell. A landmark's model
and every point of interest's dressing belong to their cell, so beyond that range nothing is on
screen but the ground. Nothing is missing from the country. The game's own sightline model
(`systems/exploration/place_discovery.gd`) says the Stair Head sees Merrowby at 2.4 km. From
above Pilgrim's Ash it sees the Grandfather and the Tower of Vaelost at 3.2 km. None of them are
drawn.

This file lists what belongs on the horizon: every landmark place, and every point of interest of
a tall kind. It gives heights, how each one reads as a silhouette, and what it does at night. The
horizon layer, its LODs and its draw distance belong to the graphics owner. This list is the
cartographer's.

## Rules

* **Range.** From where the streamed ring ends (about 0.6 km) out to `MAX_SIGHT_M` (4.2 km), the
  same limit the sightline model uses. Beyond 4.2 km nothing is claimed as seen.
* **Seen or not.** Whether a thing is visible is the sightline model's call, the same test
  `tools/sightlines.py` runs: eye height `EYE_M` over the ground, a top of `LANDMARK_M[kind]`
  over the thing's pad, and `CLEARANCE_M` under the line. The layer should not draw what that
  test says is hidden, or the map and the screen will disagree about what the player has seen.
* **Driven by kind, not by name.** A new place of a listed kind joins the horizon with no edit
  here. The tables below are the current members, measured on the rebuilt atlas world
  (`w_main_atlas`, atlas e11343a1).
* **Where each thing stands.** Positions are the built pads, `pos` in
  `world/generated/pois.json`. The ground height there is the base.
* **Reuse what exists.**
  * Tier A has LODs in the forge. The third entry of `tris` in each model's `.meta.json` is its
    lowest LOD, 240 to 1,663 triangles.
  * Tier B dressings already have a silhouette-only build. `WorldPois.raise_in_cell(..., far =
    true)` gives it for the far ring, and `WorldPois.raise_one(id, parent, true)` raises one.
    That is the natural source for their horizon mesh.
* **At night, a light carries further than a shape.** Every entry marked *lit* below has a fire,
  lamp or glow in the fiction. A lit thing should show as an emissive point at full range after
  dusk, even where its shape is under a pixel. This is the Fable skyline at night, and it costs
  one sprite each.

At 1080 lines and a 70-degree vertical field of view, a pixel is about 0.065 degrees. So a 7.6 m
tower is 2.7 px tall at 2.5 km. A 52 m colossus is 11 px at 4 km.

## Tier A: the landmark models (to 4.2 km)

Heights are measured off each model's mesh bounds (`assets/models/landmarks/*/*.glb`).

| Place | Pad (x, z), ground | Model | Height × across | Silhouette | Night |
|---|---|---|---|---|---|
| The Grandfather `core:place/grandfather` | 2750, 450; 181 m | `briarwold_grandfather_a` | 94 × 62–67 m | A dead giant: a bare, split crown over a trunk as wide as a street, standing out of a wooded hollow. The tallest thing in Briarwold. | *lit*: lights in its knots (the town inside) |
| The Drowned Nave `core:place/drowned_nave` | -3300, -1420; 4 m | `sedgemire_drowned_nave_a` | 120 × 63–68 m | An Oroth nave standing out of the marsh, the tallest thing in the world, over flat water. | |
| The Sayers' Spire `core:place/sayers_spire` | 120, -390; 16 m | `brightwater_sayers_spire_a` | 70 × 14 m | A black stalk with a brass crown over Tollmere, read against the Mere. | |
| The Sunken Choir `core:place/sunken_choir` | 12 colossi, centre about (-156, 3386), 36 to 160 m out from it; 124–130 m | `cinderlea_choir_colossus_a` ×7, `_b` ×5 | 52 × 27 m each | Twelve headless figures on the plateau's edge. A row of shoulders, not one shape. Seen from the whole south of the Vale. | |
| The Cracked Toll `core:place/cracked_toll` | 190, 1130; 55 m | `hearthvale_cracked_toll_a` | 44 × 114 × 102 m | A bronze bell's crown and cracked lip out of a hillside. A dome, wider than it is tall. | |
| The Lamp `core:place/the_lamp` | -1060, -1115; 18 m | `brightwater_the_lamp_a` | 36 × 12–18 m | A lighthouse on the lake shore. | *lit*: the sul-stone light, all night, to full range |
| The Fallen Hand `core:place/fallen_hand` | 900, -3230; 472 m | `skerrow_fallen_hand_a` | 14 × 40–48 m | A stone hand on a high shoulder. Low; it counts because it is at 472 m. | |
| The Chalk Hound `core:place/chalk_hound` | 500, 2150; 112 m | `hearthvale_chalk_hound_a` | 0.8 × 57 × 16 m | A white hill figure laid on the slope. It has no height, so give it to the horizon as terrain colour (a decal on the far terrain), not as a mesh. | |
| Eelfathom Pool `core:place/eelfathom` | -2330, -980; 4 m | `sedgemire_eelfathom_a` | 6.6 m | Leave it off. A pool is not a skyline. | |

## Tier B: the tall kinds (to 2.5 km; lit ones to 4.2 km at night)

Kinds and their sightline tops (`LANDMARK_M`): tower 10 m, strange_tree 14 m, giant_bones 13 m,
waterfall 13 m. The dressings are procedural (`world/pois/poi_builders.gd`), and their real heights
differ:

* A plain watch or beacon is a 7.6 m stone drum with a broken crown. It is smaller than the 10 m
  the sightline model credits it with. If the horizon should carry them past 1.5 km, the drum
  wants to be 10–12 m.
* Stilt towers are 7–9 m, a hide in a living trunk is the tree's height, and a toll-house under
  snow is 6.2 m.

Waterfalls: draw a pale vertical band (the water) against the dark cliff. That is what reads at
range, not the rock.

| Point of interest | Pad (x, z), ground | Kind, form | Silhouette | Night |
|---|---|---|---|---|
| The Hush Bell `hush_bell` | 660, 3700; 86 m | tower | A bell on a stone arm over the cliff edge, above the Hush. The first skyline thing the opening sees. | |
| Hound Watch `hound_watch` | 900, 2760; 105 m | tower | A drum with a bell in its crown on the south end of Hound Down. | |
| Ash Watch `ash_watch` | -380, 2310; 93 m | tower, beacon | A drum with a fire-bowl kept laid. | *lit* when anything walks up the Glassbed |
| The Brow Beacon `brow_beacon` | 2420, 3540; 178 m | tower, beacon | On the highest chalk above the Hush; the east end of the Wardens' line. | *lit* when the Wardens' line is lit, with Ash Watch |
| The Headless Watch `headless_watch` | -750, 2990; 119 m | tower, head | A colossus's fallen head, its eye a window. Kin to the Choir. | |
| The Glass Falls `glass_falls` | -80, 3030; 97 m | waterfall, glass | A black glass fall. Dry, so a dark, glossy band, not a pale one. | |
| The Tower of Vaelost `tower_of_vaelost` | -2550, 3350; 70 m | tower | An Oroth tower over the Builders' city, the tallest thing in the west of Cinderlea. | |
| Sulion `sulion` | -3120, 3080; 70 m | tower | The dead city's harbour light, its socket empty. | |
| The Strand Beacon `strand_beacon` | -3420, 1950; 15 m | tower, beacon | Grey stone on the strand. | *lit* every night |
| The Tumbled Watch `tumbled_watchtower` | -1000, 1420; 81 m | tower, lying | Low: a drum on its side. | |
| The Singing Yew `singing_yew` | 1520, 1720; 103 m | strange_tree | A hollow yew, dark and broad. | |
| Whitecut Falls `whitecut_falls` | -40, 990; 33 m | waterfall | A single white sheet off the chalk scarp. | |
| North Cliff Beacon `north_cliff_beacon` | -560, -1470; 58 m | tower, beacon | Ruined, its fire-bowl an upturned bell. | |
| The Counting Tower `counting_tower` | 180, -1600; 59 m | tower | Every window bricked. | |
| The Listening Post `the_listening_post` | 1430, 120; 12 m | tower | A brass horn turned toward Merrowby. | |
| Willow Isle `willow_isle` | -590, 240; 11 m | strange_tree | A barn-sized pollard on the Mere. | |
| The Heronry `the_heronry` | -1500, 800; 13 m | tower | A dead Oroth tower crowned with herons' nests. | |
| Heron Watch `heron_watch` | -2442, -660; 3 m | tower, stilts | A stilt lookout. | |
| The Fog Bell `fog_bell` | -3300, -700; 3 m | tower, stilts | A stilt tower; its bell is heard, not seen. | |
| The Sunken Tower `sunken_tower` | -3550, -980; 2 m | tower | Three courses out of the water. | |
| Crookstilts `crookstilts` | -2350, -1600; 4 m | tower, stilts | | |
| The South Stilts `south_stilts` | -2450, 1480; 12 m | tower, stilts | | |
| The Sallow King `sallow_king` | -3230, 180; 3 m | strange_tree | A ring of rooted willow, broad. | |
| The Hunters' Stand `hunters_stand` | 3120, 1000; 220 m | tower, hide | A hide in a living trunk: reads as a tall tree. | |
| Foxfire Falls `foxfire_falls` | 2460, 245; 111 m | waterfall | Into a ravine. | *lit*: the walls glow |
| The Hart Bones `hart_bones` | 3560, 780; 269 m | giant_bones | An antlered skull the size of a house. | |
| Wold Force `wold_force` | 3320, 660; 215 m | waterfall | A single rope of white. | |
| Countwatch `countwatch` | 3700, 300; 278 m | tower | A squat granite drum on a tor. | |
| Blackgill Falls `blackgill_falls` | 2600, -1700; 193 m | waterfall | Under oak; dark. Short range only. | |
| The Verderer's Tower `verderers_tower` | 3650, -1400; 252 m | tower, hide | Over the High Wold's canopy. | |
| The Fallen Firewatch `fallen_firewatch` | 3050, -1400; 246 m | tower, lying | Low. | |
| Kharrow Gate `kharrow_gate` | -100, -2120; 15 m | tower | | |
| The Three Sisters `three_sisters_falls` | -1100, -2220; 68 m | waterfall, terraced | Three white steps. | |
| The Dale Watch `dale_watch` | -2100, -2380; 86 m | tower | | |
| The Moot Beacon `moot_beacon` | 1750, -2200; 165 m | tower, beacon | | *lit* while the clans sit |
| The Black Keep `black_keep` | 2300, -2250; 244 m | tower | Burned black. | |
| The Rib Cathedral `rib_cathedral` | 1380, -2720; 223 m | giant_bones | Ribs taller than a hall, in a row. | |
| The Giant's Spine `giants_spine` | 1500, -3080; 314 m | giant_bones | A long low line of vertebrae, each with a cairn. | |
| Kharrow Force `kharrow_force` | 300, -3150; 505 m | waterfall | | |
| Rudd Pike Beacon `rudd_pike_beacon` | 860, -3420; 525 m | tower, beacon | | *lit* when the avalanche comes |
| The Rust Scar `rust_scar` | 790, -2890; 285 m | waterfall | A rust-red stain, not white. | |
| Skarl Spout `skarl_spout` | 2480, -2980; 305 m | waterfall | Out of a hole halfway up a scar. | |
| The Bonefield `the_bonefield` | 3250, -2950; 374 m | giant_bones | Bones like fallen timber on scree: texture, not shape. Short range. | |
| The Watcher `the_watcher` | 3750, -3550; 545 m | giant_bones | A barn-sized skull under the Wall. | |
| The Watch of the Gate `watch_of_the_gate` | -220, -3820; 458 m | tower, toll-house | Half buried in snow. | |
| The Jawbone `the_jawbone` | -2350, -3350; 357 m | giant_bones | A jaw on end, like a gate. | |
| The Skerry Watch `skerry_watch` | -3430, -3120; 355 m | tower | Drystone, on the sea cliff. | |
| The Wading Giant `wading_giant` | -3560, -2520; 155 m | giant_bones | Ribs and hips out of the sea cliff. | |
| The Bone Ford `bone_ford` | 1255, -1800; 44 m | giant_bones | Lies across a beck. Leave it off. | |
| The Hanging Falls `hanging_falls` | -1700, -3800; 512 m | waterfall, frozen | A white ice column on the Wall's face. | |

## Tier C: the settlements (to 3 km)

A settlement's fabric (`world/exteriors/settlement.gd`) is roofs. At range it should read as a
cluster of roof shapes the colour of its region's thatch, slate or timber, with smoke by day and
lit windows by night. The fabric already knows its house count and plots. A far version can be
one merged mesh of the roofs alone.

| Kind | Roofs (FABRIC.count) | Members |
|---|---|---|
| city | 54 | Tollmere (40, -300) |
| town | 34 | Merrowby (250, 1330), Isseva (-2600, 50) on stilts over water, Kharrow Hold (300, -2740) cut into a cliff with a chain bridge, Grandfather Hollow (2750, 450) round the Grandfather's foot |
| fort | 10 | Wardens' Rest (-700, 1640), the West Walk (-2250, 2150) |
| village | 16 | Gullhithe (-1300, -960), Brindlecrag (-880, -2660) with mine headframes |
| lodge | 5 | the Hare and Hurdle, Fernhold, Elderhold, Rookhold, Ormhold |

Hamlets (8 roofs) are too small to carry past the streamed ring; leave them off. Camps are fires,
and a camp's fire is worth a night light to 1.5 km.

## Features that are not objects

* **The Thornmarch** (`core:place/thornmarch`, the Briar wall). It follows the ridge from x 3925 to
  4030 along the east edge. The horizon should see a dark, ragged band on that ridge line, the
  height of a wood.
* **The Hushline** (`core:place/hushline`). A bank of grey mist along the south cliff foot, where
  colour and sound drain away. From the Stair Head and the Choir it should read as a pale,
  colourless haze over everything south, not as a line.
* **The Chalk Hound**, above. A hill figure is terrain colour.

## Leave off

Camps, shrines, ruins, standing stones, bridges, wrecks, hidden valleys and the strange kinds are
under 6 m. They are what the streamed ring is for. The exceptions: lit camp fires at night, the
Long Stride's lamps and the Lantern Causeway's lamps at dusk, all of them *lit* points only. Deep
places and interiors have nothing above ground.

## How the list was made

* The landmark models' heights and triangle counts come from their `.glb` bounds and
  `.meta.json`.
* Positions and grounds come from the rebuilt world's `pois.json`.
* Kinds and fiction come from `content/packs/core/pois` and `places`.
* The tower and tumbled-tower heights come from `world/pois/poi_builders.gd`.

A place added with one of these kinds joins by its kind. A new landmark model joins Tier A by its
`scene` in `pois.json`.
