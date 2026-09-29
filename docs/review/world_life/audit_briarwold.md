# World life audit: Briarwold

Made by `python3 tools/world/region_audit.py briarwold` from the installed world (2026-09-28T18:00:36Z) and the content pack; the POI measurements are `docs/review/world_life/probe_briarwold.json` (tools_gd/poi_probe.gd, headless). docs/WORLD_LIFE.md says how to read and use it.

![map](audit_briarwold.png)

## Summary

| | |
|---|---|
| land a body walks (dry, no steeper than 32 deg, 250 m in from the map's edge) | 6.0 km2 |
| points of interest | 74 (12.2 per km2; 0 not yet in the built world) |
| land more than 200 m from any place, POI or roadside mark | 1.16 km2 (19%); more than 400 m: 0% |
| share of land further than 100 / 150 / 200 / 300 / 400 m from anything | 57% / 36% / 19% / 2% / 0% |
| largest empty stretch | 0.36 km2 |
| weak POIs (score <= 3) | 19, and 28 wayside finds (small by design) |
| strong POIs (score >= 8) | 0 |
| placement problems | 50, at 30 POIs |

## (a) Empty land, largest first

A stretch is land of the region more than 200 m from the edge of every place's, POI's and roadside mark's pad. `furthest` is how far its middle is from anything. Sites are gentle ground (<= 14 deg) in it, as far from everything as it allows, nearer a road where one is near.

| # | middle (x, z) | km2 | extent m | furthest m | slope mean/p75 | height | province (biome) | road | sites (x, z, slope, road m) |
|---|---|---|---|---|---|---|---|---|---|
| 1 | (3108, -1812) | 0.36 | 1112 x 960 | 393 | 13 / 18 | 214 | The Northwold (forest_rise), The Northwold | nearest 193 m | (3076, -1812) 2 deg 391 m; (3364, -1564) 1 deg 451 m; (2828, -1596) 0 deg 306 m |
| 2 | (2804, 4) | 0.23 | 832 x 944 | 366 | 8 / 10 | 150 | The Greatwood (forest_rise), The Greatwood | nearest 79 m | (2804, 4) 2 deg 354 m; (2908, -532) 1 deg 246 m; (2500, -20) 0 deg 170 m |
| 3 | (3284, -500) | 0.06 | 384 x 648 | 322 | 9 / 12 | 276 | The High Wold (forest_rise), The High Wold | nearest 91 m | (3300, -508) 2 deg 208 m; (3468, -84) 2 deg 331 m; (3564, -404) 3 deg 270 m |

## (b) Points of interest, weakest first

Impact score, points for each: **size** footprint reach (m from the middle to its furthest piece): <8 = 0, <14 = 1, <22 = 2, <32 = 3, else 4; **things** interactables in the dressing (Hearthstone, touch, container, readable ...): 1 each, up to 3; **foes** an encounter that stands foes up: 1, and 1 more for 4 or more; **loot** something to take (an encounter's `lies`, a quest's item, a find): 1; **people** an NPC who lives or stands there: 1, 2 for two or more; **quest** a quest sends you there: 2; **interior** a door into an interior: 2; **landmark** a landmark model (a `scene` in pois.json): 2; **hearth** a Hearthstone: 1. **Weak** is 3 or under; **small** is a reach under 10 m. `reach` is metres from the middle to the furthest piece; `things` are interactables in the dressing (hearthstones, touches, containers); foes are the encounter's standing count; loot counts an encounter's `lies`, a find and a container.

| score | POI | kind | reach / pad m | pieces | draws | tris k | things | foes | loot | NPCs | quest | enc | interior | hearth | landmark | flags |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Foxfire Falls `foxfire_falls` | waterfall | 0 / 25 | 13 | 13 | 217 | 0 | 2 | 0 | 0 |  | yes |  |  |  | WEAK small |
| 1 | The Fourth Brother `fourth_brother` | waystone | 2 / 14 | 7 | 7 | 1 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The Hart Count `hart_count` | waystone | 2 / 14 | 7 | 7 | 1 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The Flood Stone `flood_stone` | waystone | 2 / 14 | 7 | 7 | 1 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The Leave Stone `leave_stone` | waystone | 2 / 14 | 7 | 7 | 1 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The Verderer's Moss Grave `verderers_moss_grave` | grave | 2 / 14 | 8 | 8 | 7 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The Hazelwick Rumour Stone `hazelwick_rumour_stone` | waystone | 2 / 14 | 10 | 10 | 2 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The Road Knot `road_knot` | shrine | 3 / 14 | 24 | 24 | 15 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The Oil-Carriers' Stone `oil_carriers_stone` | shrine | 3 / 14 | 37 | 37 | 26 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The Bread Stone `bread_stone` | shrine | 3 / 14 | 24 | 24 | 15 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The Uncarried `uncarried_stones` | standing_stones | 6 / 14 | 12 | 12 | 53 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The Elderhold Charcoal Hut `elderhold_charcoal_hut` | hut | 6 / 14 | 5 | 5 | 3 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The Drunk Stones `drunk_stones` | standing_stones | 6 / 14 | 12 | 12 | 53 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The Sentinels `the_sentinels` | standing_stones | 7 / 25 | 12 | 12 | 52 | 0 | 2 | 0 | 0 |  | yes |  |  |  | WEAK small |
| 2 | The Moot Gate Stone `moot_gate_stone` | shrine | 3 / 25 | 31 | 31 | 16 | 1 | 0 | 0 | 0 |  |  |  | yes |  | WEAK small |
| 2 | The Torch Stone `torch_stone` | shrine | 3 / 14 | 24 | 24 | 15 | 0 | 1 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 2 | The Moss Bed `moss_bed` | shrine | 3 / 14 | 24 | 24 | 17 | 0 | 1 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 2 | Hollin Tor `hollin_tor` | standing_stones | 6 / 25 | 12 | 12 | 52 | 0 | 0 | 0 | 0 | yes |  |  |  |  | WEAK small |
| 2 | Harrow Tor `harrow_tor` | standing_stones | 6 / 25 | 12 | 12 | 55 | 0 | 0 | 0 | 0 | yes |  |  |  |  | WEAK small |
| 2 | The Grey Man `grey_man_tor` | standing_stones | 6 / 25 | 12 | 12 | 53 | 0 | 0 | 0 | 0 | yes |  |  |  |  | WEAK small |
| 2 | Countwatch `countwatch` | tower | 6 / 25 | 12 | 12 | 54 | 0 | 0 | 0 | 0 | yes |  |  |  |  | WEAK small |
| 2 | The Silence Stones `silence_stones` | standing_stones | 6 / 14 | 12 | 12 | 55 | 0 | 2 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 2 | The Knight's Challenge `knights_challenge` | standing_stones | 7 / 14 | 12 | 12 | 53 | 0 | 1 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 2 | The Wardstone Line `wardstone_line` | ruins | 8 / 25 | 5 | 7 | 97 | 0 | 3 | 0 | 0 |  | yes |  |  |  | WEAK small |
| 2 | Pellow's Pale `pellows_pale` | ruins | 8 / 25 | 21 | 21 | 138 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small |
| 2 | The Knight's Mound `knights_mound` | ruins | 9 / 25 | 12 | 12 | 120 | 0 | 1 | 0 | 0 |  | yes |  |  |  | WEAK small |
| 2 | The Antler-Smith's House `antler_smiths_house` | ruins | 10 / 14 | 21 | 21 | 140 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 2 | The Antler Boilers `antler_boilers` | camp | 13 / 22 | 56 | 56 | 58 | 0 | 3 | 0 | 0 |  | yes |  |  |  | WEAK |
| 2 | The Bark Camp `bark_camp` | camp | 13 / 22 | 68 | 68 | 68 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK |
| 2 | The Poachers' Lee `poachers_lee` | camp | 14 / 22 | 56 | 56 | 55 | 0 | 3 | 0 | 0 |  | yes |  |  |  | WEAK |
| 3 | The Burnt Lodge `burnt_lodge` | ruins | 8 / 14 | 21 | 21 | 140 | 0 | 1 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 3 | The Masons' Lodge `masons_lodge` | ruins | 10 / 14 | 21 | 21 | 138 | 0 | 1 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 3 | Wenna's House `wennas_house` | ruins | 10 / 14 | 12 | 12 | 128 | 0 | 1 | 2 | 0 |  | yes |  |  |  | WEAK wayside |
| 3 | The Webbed Lodge `webbed_lodge` | ruins | 10 / 14 | 21 | 21 | 138 | 0 | 2 | 2 | 0 |  | yes |  |  |  | WEAK wayside |
| 3 | The Two Countries Bench `two_countries_bench` | vista | 10 / 14 | 10 | 10 | 93 | 0 | 1 | 2 | 0 |  | yes |  |  |  | WEAK wayside |
| 3 | The Sawyers' Bench `sawyers_bench` | vista | 11 / 14 | 10 | 10 | 84 | 0 | 2 | 2 | 0 |  | yes |  |  |  | WEAK wayside |
| 3 | The Sawpit `the_sawpit` | camp | 13 / 22 | 74 | 74 | 70 | 1 | 0 | 2 | 0 |  | yes |  |  |  | WEAK |
| 3 | The Laid Fire `laid_fire` | camp | 14 / 14 | 62 | 62 | 57 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK wayside |
| 3 | The Silk-Gatherers' Camp `silk_gatherers_camp` | camp | 14 / 14 | 59 | 59 | 59 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK wayside |
| 3 | The Foxfire-Pickers' Camp `foxfire_pickers_camp` | camp | 15 / 14 | 59 | 59 | 56 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK wayside |
| 3 | The Coppice Round `coppice_round` | camp | 15 / 14 | 71 | 71 | 67 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK wayside |
| 3 | The Briar Nursery `briar_nursery` | camp | 16 / 22 | 68 | 68 | 66 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK |
| 3 | The Antler Chapel `antler_chapel` | ruins | 16 / 25 | 21 | 21 | 127 | 0 | 1 | 0 | 0 |  | yes |  |  |  | WEAK |
| 3 | Blackgill Falls `blackgill_falls` | waterfall | 19 / 25 | 26 | 26 | 179 | 0 | 3 | 0 | 0 |  | yes |  |  |  | WEAK |
| 3 | The Skarl Bridge `skarl_bridge` | bridge | 20 / 25 | 8 | 8 | 6 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK |
| 3 | The Ringing Oak `ringing_oak` | strange_tree | 20 / 14 | 51 | 75 | 85 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK wayside |
| 3 | The Hart Bones `hart_bones` | giant_bones | 22 / 25 | 22 | 22 | 60 | 0 | 1 | 0 | 0 |  | yes |  |  |  | WEAK |
| 4 | The Northgate Stone `northgate_stone` | shrine | 3 / 25 | 31 | 31 | 16 | 1 | 0 | 0 | 0 | yes |  |  | yes |  | small |
| 4 | The Old Gate Stone `old_gate_stone` | shrine | 3 / 25 | 31 | 31 | 14 | 1 | 0 | 0 | 0 | yes |  |  | yes |  | small |
| 4 | The Tally Hearth `tally_hearth` | shrine | 3 / 25 | 31 | 31 | 16 | 1 | 0 | 0 | 0 | yes |  |  | yes |  | small |
| 4 | The Oiled Stone `oiled_stone_shrine` | shrine | 5 / 25 | 44 | 44 | 29 | 1 | 0 | 0 | 0 | yes |  |  | yes |  | small |
| 4 | Mossgrave `mossgrave` | ruins | 10 / 25 | 12 | 12 | 128 | 0 | 1 | 0 | 0 | yes | yes |  |  |  |  |
| 4 | Wold Force `wold_force` | waterfall | 11 / 25 | 14 | 14 | 210 | 0 | 3 | 0 | 0 | yes | yes |  |  |  |  |
| 4 | The Wall-Watchers' Fire `wall_watchers_fire` | camp | 14 / 14 | 56 | 56 | 55 | 0 | 2 | 2 | 0 |  | yes |  |  |  | wayside |
| 4 | The Firewatchers' Camp `firewatchers_camp` | camp | 14 / 14 | 96 | 96 | 73 | 1 | 0 | 4 | 0 |  | yes |  |  |  | wayside |
| 4 | The Planters' Camp `planters_camp` | camp | 14 / 14 | 62 | 62 | 57 | 0 | 1 | 2 | 0 |  | yes |  |  |  | wayside |
| 4 | The Hart Snares `hart_snares` | camp | 14 / 14 | 59 | 59 | 56 | 0 | 2 | 2 | 0 |  | yes |  |  |  | wayside |
| 4 | The Rafters' Locker `rafters_locker` | cave | 15 / 14 | 52 | 52 | 108 | 0 | 2 | 2 | 0 |  | yes |  |  |  | wayside |
| 4 | The Unasked Camp `unasked_camp` | camp | 16 / 14 | 59 | 59 | 56 | 0 | 2 | 2 | 0 |  | yes |  |  |  | wayside |
| 4 | The Mourners' Fire `mourners_fire` | camp | 16 / 14 | 68 | 68 | 68 | 0 | 1 | 4 | 0 |  | yes |  |  |  | wayside |
| 4 | The Briar Root `briar_root` | cave | 16 / 14 | 51 | 51 | 110 | 0 | 2 | 2 | 0 |  | yes |  |  |  | wayside |
| 4 | The Root Hollow `root_hollow` | cave | 17 / 25 | 51 | 51 | 106 | 0 | 2 | 2 | 0 |  | yes |  |  |  |  |
| 4 | The Poachers' Cache `poachers_cache` | camp | 18 / 14 | 68 | 68 | 66 | 0 | 2 | 2 | 0 |  | yes |  |  |  | wayside |
| 4 | Barkbridge `barkbridge` | bridge | 18 / 25 | 8 | 8 | 6 | 0 | 0 | 0 | 0 | yes |  |  |  |  |  |
| 4 | The Fallen Firewatch `fallen_firewatch` | tower | 23 / 25 | 15 | 15 | 107 | 0 | 0 | 2 | 0 |  | yes |  |  |  |  |
| 5 | The Breach `briar_breach` | ruins | 8 / 25 | 5 | 7 | 111 | 0 | 5 | 0 | 0 | yes | yes |  |  |  | small |
| 5 | The Silked Camp `silked_camp` | camp | 15 / 22 | 59 | 59 | 59 | 0 | 3 | 0 | 0 | yes | yes |  |  |  |  |
| 5 | The Foxgill Arch `foxgill_arch` | bridge | 45 / 25 | 14 | 24 | 85 | 0 | 0 | 2 | 0 |  | yes |  |  |  |  |
| 5 | Mossbridge `mossbridge` | bridge | 46 / 25 | 14 | 24 | 89 | 0 | 2 | 0 | 0 |  | yes |  |  |  |  |
| 5 | Fern Gully `fern_gully` | hidden_valley | 50 / 25 | 25 | 30 | 57 | 0 | 3 | 0 | 0 |  | yes |  |  |  |  |
| 6 | The Old Quarry `old_quarry` | quarry | 28 / 25 | 17 | 17 | 35 | 0 | 2 | 0 | 0 | yes | yes |  |  |  |  |
| 6 | The Verderer's Tower `verderers_tower` | tower | 38 / 25 | 23 | 28 | 19 | 0 | 0 | 0 | 0 | yes |  |  |  |  |  |
| 7 | The Charcoal Camp `charcoal_camp` | camp | 15 / 22 | 86 | 86 | 70 | 1 | 0 | 0 | 2 | yes |  |  |  |  |  |
| 7 | The Hunters' Stand `hunters_stand` | tower | 43 / 25 | 23 | 28 | 19 | 0 | 3 | 0 | 0 | yes | yes |  |  |  |  |

Weak POIs by kind (not wayside): camp 5, standing_stones 4, ruins 4, waterfall 2, giant_bones 1, shrine 1, bridge 1, tower 1.


## (c) Placement problems

`seat:*` are the seat audit's findings over the POI's own pieces (tools_gd/seat_audit.gd: floating over the ground, buried, sunk, standing in a road's carriageway, overlapping another piece, a lamp or light hung from nothing; headless, so multimesh rows are not looked at). `past_pad`: pieces stand beyond the flattened pad, on the skirt or raw ground. `steep_skirt`: the pad's skirt (from its level core to its reach) falls at more than 33 deg along some line: a cut or an embankment. `steep_site`: a POI not yet built stands on ground sloping more than 18 deg on average under its pad. `overlap_pad`: two pads overlap. `road_through`: a road crosses the level core of a place that is not road furniture. `in_water`: its middle is in water.

Counts: steep_skirt 15, past_pad 9, road_through 8, seat:overlap 7, seat:on_road 5, seat:buried 3, seat:sunk 3.

| POI | problem | n | detail |
|---|---|---|---|
| `briar_root` | past_pad | 1 | pieces reach 16 m from its middle; its pad is 14 m |
| `fern_gully` | past_pad | 1 | pieces reach 50 m from its middle; its pad is 25 m |
| `foxgill_arch` | past_pad | 1 | pieces reach 45 m from its middle; its pad is 25 m |
| `hunters_stand` | past_pad | 1 | pieces reach 43 m from its middle; its pad is 25 m |
| `mossbridge` | past_pad | 1 | pieces reach 46 m from its middle; its pad is 25 m |
| `old_quarry` | past_pad | 1 | pieces reach 28 m from its middle; its pad is 25 m |
| `poachers_cache` | past_pad | 1 | pieces reach 18 m from its middle; its pad is 14 m |
| `ringing_oak` | past_pad | 1 | pieces reach 20 m from its middle; its pad is 14 m |
| `verderers_tower` | past_pad | 1 | pieces reach 38 m from its middle; its pad is 25 m |
| `antler_chapel` | road_through | 1 | a road passes 1 m from its middle, inside its 18 m level core |
| `bark_camp` | road_through | 1 | a road passes 0 m from its middle, inside its 15 m level core |
| `charcoal_camp` | road_through | 1 | a road passes 7 m from its middle, inside its 15 m level core |
| `countwatch` | road_through | 1 | a road passes 1 m from its middle, inside its 18 m level core |
| `oiled_stone_shrine` | road_through | 1 | a road passes 1 m from its middle, inside its 18 m level core |
| `old_quarry` | road_through | 1 | a road passes 7 m from its middle, inside its 18 m level core |
| `the_sawpit` | road_through | 1 | a road passes 3 m from its middle, inside its 15 m level core |
| `the_sentinels` | road_through | 1 | a road passes 6 m from its middle, inside its 18 m level core |
| `briar_root` | seat:buried | 4 | throat2 Throat2 at (3343, -834): all of it under the ground (top 1.40 m below the lowest ground under it) |
| `rafters_locker` | seat:buried | 5 | throat1 Throat1 at (1905, -177): all of it under the ground (top 1.19 m below the lowest ground under it) |
| `root_hollow` | seat:buried | 4 | throat2 Throat2 at (2456, 1374): all of it under the ground (top 1.65 m below the lowest ground under it) |
| `charcoal_camp` | seat:on_road | 1 | @meshinstance3d@6826 @MeshInstance3D@6826 at (2775, 671): stands in the carriageway of grandfather_hollow_standing_moot |
| `countwatch` | seat:on_road | 1 | drum Drum at (3700, 300): stands in the carriageway of fernhold_thornmarch |
| `oiled_stone_shrine` | seat:on_road | 2 | standing_stone briarwold_standing_stone_a.glb at (2421, 881): stands in the carriageway of tamwick_grandfather_hollow |
| `the_sentinels` | seat:on_road | 1 | standing_stone briarwold_standing_stone_a.glb at (2953, 1096): stands in the carriageway of grandfather_hollow_standing_moot |
| `two_countries_bench` | seat:on_road | 1 | fabricdrystone FabricDrystone at (2140, -1572): stands in the carriageway of elderhold_skarl_bridge |
| `briar_root` | seat:overlap | 5 | boulder briarwold_boulder_b.glb at (3337, -838): 91% of it shares its box with boulder (poi:cave) |
| `hart_bones` | seat:overlap | 3 | bone_skull_fragment skerrow_bone_skull_fragment_a.glb at (3560, 780): 71% of it shares its box with bone_skull_fragment (poi:giant_bones) |
| `hunters_stand` | seat:overlap | 2 | giant_oak briarwold_giant_oak_b.glb at (3120, 1000): 100% of it shares its box with campfire (poi:tower) |
| `rafters_locker` | seat:overlap | 3 | boulder briarwold_boulder_b.glb at (1907, -173): 84% of it shares its box with boulder (poi:cave) |
| `ringing_oak` | seat:overlap | 6 | willow sedgemire_willow_b.glb at (3023, 1365): 74% of it shares its box with willow (poi:strange_tree) |
| `root_hollow` | seat:overlap | 5 | boulder briarwold_boulder_a.glb at (2457, 1382): 100% of it shares its box with boulder (poi:cave) |
| `verderers_tower` | seat:overlap | 2 | campfire hearthvale_campfire_b.glb at (3651, -1395): 100% of it shares its box with giant_oak (poi:tower) |
| `briar_root` | seat:sunk | 3 | boulder briarwold_boulder_a.glb at (3336, -835): 76% of its 5.5 m under the ground at its middle |
| `rafters_locker` | seat:sunk | 4 | boulder briarwold_boulder_b.glb at (1908, -175): 79% of its 2.7 m under the ground at its middle |
| `root_hollow` | seat:sunk | 2 | boulder briarwold_boulder_a.glb at (2458, 1380): 67% of its 4.7 m under the ground at its middle |
| `briar_nursery` | steep_skirt | 1 | its pad's skirt falls at 34 deg: a cut or an embankment |
| `elderhold_charcoal_hut` | steep_skirt | 1 | its pad's skirt falls at 64 deg: a cut or an embankment |
| `fallen_firewatch` | steep_skirt | 1 | its pad's skirt falls at 42 deg: a cut or an embankment |
| `fern_gully` | steep_skirt | 1 | its pad's skirt falls at 42 deg: a cut or an embankment |
| `harrow_tor` | steep_skirt | 1 | its pad's skirt falls at 50 deg: a cut or an embankment |
| `hart_bones` | steep_skirt | 1 | its pad's skirt falls at 47 deg: a cut or an embankment |
| `moot_gate_stone` | steep_skirt | 1 | its pad's skirt falls at 43 deg: a cut or an embankment |
| `moss_bed` | steep_skirt | 1 | its pad's skirt falls at 34 deg: a cut or an embankment |
| `poachers_lee` | steep_skirt | 1 | its pad's skirt falls at 55 deg: a cut or an embankment |
| `rafters_locker` | steep_skirt | 1 | its pad's skirt falls at 50 deg: a cut or an embankment |
| `root_hollow` | steep_skirt | 1 | its pad's skirt falls at 37 deg: a cut or an embankment |
| `silked_camp` | steep_skirt | 1 | its pad's skirt falls at 38 deg: a cut or an embankment |
| `skarl_bridge` | steep_skirt | 1 | its pad's skirt falls at 33 deg: a cut or an embankment |
| `tally_hearth` | steep_skirt | 1 | its pad's skirt falls at 61 deg: a cut or an embankment |
| `verderers_tower` | steep_skirt | 1 | its pad's skirt falls at 50 deg: a cut or an embankment |
