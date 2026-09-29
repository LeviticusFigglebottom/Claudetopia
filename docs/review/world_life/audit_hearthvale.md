# World life audit: Hearthvale

Made by `python3 tools/world/region_audit.py hearthvale` from the installed world (2026-09-28T18:00:36Z) and the content pack; the POI measurements are `docs/review/world_life/probe_hearthvale.json` (tools_gd/poi_probe.gd, headless). docs/WORLD_LIFE.md says how to read and use it.

![map](audit_hearthvale.png)

## Summary

| | |
|---|---|
| land a body walks (dry, no steeper than 32 deg, 250 m in from the map's edge) | 10.9 km2 |
| points of interest | 87 (8.0 per km2; 0 not yet in the built world) |
| land more than 200 m from any place, POI or roadside mark | 1.76 km2 (16%); more than 400 m: 0% |
| share of land further than 100 / 150 / 200 / 300 / 400 m from anything | 60% / 35% / 16% / 1% / 0% |
| largest empty stretch | 0.47 km2 |
| weak POIs (score <= 3) | 29, and 25 wayside finds (small by design) |
| strong POIs (score >= 8) | 0 |
| placement problems | 28, at 25 POIs |

## (a) Empty land, largest first

A stretch is land of the region more than 200 m from the edge of every place's, POI's and roadside mark's pad. `furthest` is how far its middle is from anything. Sites are gentle ground (<= 14 deg) in it, as far from everything as it allows, nearer a road where one is near.

| # | middle (x, z) | km2 | extent m | furthest m | slope mean/p75 | height | province (biome) | road | sites (x, z, slope, road m) |
|---|---|---|---|---|---|---|---|---|---|
| 1 | (2460, 2228) | 0.47 | 1480 x 1240 | 375 | 8 / 10 | 125 | Hound Down and the Brow (downs) | nearest 89 m | (2452, 2196) 1 deg 398 m; (2612, 2868) 1 deg 264 m; (2332, 2884) 1 deg 197 m |
| 2 | (1604, 3340) | 0.14 | 560 x 832 | 336 | 10 / 13 | 134 | Hound Down and the Brow (downs) | nearest 192 m | (1604, 3332) 1 deg 360 m; (1380, 3156) 4 deg 215 m; (1772, 3564) 2 deg 522 m |
| 3 | (1388, 900) | 0.12 | 696 x 552 | 351 | 8 / 11 | 73 | The East Downs (downs) | nearest 64 m | (1444, 1060) 0 deg 256 m; (1204, 908) 2 deg 211 m; (1452, 772) 2 deg 266 m |
| 4 | (1084, 3756) | 0.12 | 512 x 656 | 397 | 8 / 10 | 129 | Hound Down and the Brow (downs) | nearest 233 m | (1028, 3252) 4 deg 297 m; (1068, 3740) 1 deg 777 m; (908, 3508) 1 deg 570 m |
| 5 | (2604, 3844) | 0.11 | 824 x 472 | 333 | 12 / 16 | 141 | Hound Down and the Brow (downs) | nearest 96 m | (2692, 3564) 2 deg 181 m; (2588, 3828) 4 deg 329 m; (2284, 3796) 2 deg 290 m |
| 6 | (1204, 2660) | 0.10 | 928 x 312 | 296 | 7 / 8 | 112 | Hound Down and the Brow (downs) | nearest 126 m | (1172, 2620) 3 deg 215 m; (684, 2572) 1 deg 233 m |
| 7 | (3844, 2132) | 0.08 | 568 x 392 | 386 | 8 / 12 | 112 | Hound Down and the Brow (downs) | nearest 149 m | (3844, 2204) 0 deg 296 m; (3620, 2028) 0 deg 364 m; (3316, 1988) 6 deg 359 m |
| 8 | (-1356, 1636) | 0.08 | 752 x 216 | 276 | 4 / 5 | 94 | The West Downs (downs) | nearest 75 m | (-1668, 1684) 1 deg 150 m; (-1356, 1628) 2 deg 180 m; (-1060, 1644) 1 deg 188 m |
| 9 | (1308, 2020) | 0.08 | 360 x 544 | 319 | 6 / 7 | 110 | The East Downs (downs) | nearest 140 m | (1316, 1996) 1 deg 261 m; (1252, 1660) 1 deg 193 m |
| 10 | (3348, 2972) | 0.07 | 768 x 512 | 279 | 7 / 9 | 116 | Hound Down and the Brow (downs), Rook Wood | nearest 173 m | (3332, 2964) 2 deg 265 m; (3820, 2836) 1 deg 272 m; (3156, 3220) 2 deg 220 m |
| 11 | (740, 1908) | 0.07 | 448 x 424 | 314 | 7 / 9 | 102 | The East Downs (downs) | nearest 119 m | (756, 1940) 2 deg 301 m; (596, 1708) 0 deg 154 m |
| 12 | (-36, 2340) | 0.06 | 288 x 416 | 321 | 9 / 13 | 54 | The Vale of the Larkbourne (downs) | nearest 182 m | (-52, 2380) 3 deg 290 m |
| 13 | (-948, 2140) | 0.05 | 384 x 256 | 288 | 6 / 8 | 57 | The West Downs (downs) | nearest 197 m | (-948, 2140) 1 deg 304 m |
| 14 | (3844, 3380) | 0.04 | 312 x 224 | 293 | 10 / 12 | 120 | Hound Down and the Brow (downs) | nearest 168 m | (3652, 3396) 2 deg 241 m |

## (b) Points of interest, weakest first

Impact score, points for each: **size** footprint reach (m from the middle to its furthest piece): <8 = 0, <14 = 1, <22 = 2, <32 = 3, else 4; **things** interactables in the dressing (Hearthstone, touch, container, readable ...): 1 each, up to 3; **foes** an encounter that stands foes up: 1, and 1 more for 4 or more; **loot** something to take (an encounter's `lies`, a quest's item, a find): 1; **people** an NPC who lives or stands there: 1, 2 for two or more; **quest** a quest sends you there: 2; **interior** a door into an interior: 2; **landmark** a landmark model (a `scene` in pois.json): 2; **hearth** a Hearthstone: 1. **Weak** is 3 or under; **small** is a reach under 10 m. `reach` is metres from the middle to the furthest piece; `things` are interactables in the dressing (hearthstones, touches, containers); foes are the encounter's standing count; loot counts an encounter's `lies`, a find and a container.

| score | POI | kind | reach / pad m | pieces | draws | tris k | things | foes | loot | NPCs | quest | enc | interior | hearth | landmark | flags |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | The Grey-Wind Cairn `grey_wind_cairn` | vista | 0 / 14 | 3 | 3 | 71 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The Ploughman's Grave `ploughmans_grave` | grave | 2 / 14 | 7 | 7 | 3 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The Last Dry Mile `last_dry_mile` | waystone | 2 / 14 | 7 | 7 | 1 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The Quiet Mile `quiet_mile` | waystone | 2 / 14 | 7 | 7 | 2 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | Ansel's Dew-Well `ansels_dew_well` | well | 2 / 14 | 11 | 11 | 15 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The Naming Well `naming_well` | well | 2 / 14 | 11 | 11 | 15 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The Millers' Stone `millers_stone` | waystone | 2 / 14 | 10 | 10 | 2 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The Mill-Down Fold `mill_down_fold` | fold | 5 / 14 | 33 | 33 | 48 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The Barrow-Flock Fold `barrow_flock_fold` | fold | 6 / 14 | 36 | 36 | 51 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The Hare Stone `hare_stone` | standing_stones | 6 / 25 | 12 | 12 | 51 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small |
| 1 | The Garrison Shrine `garrison_shrine` | shrine | 6 / 14 | 33 | 33 | 19 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The Hound's Bowl `hounds_bowl` | shrine | 6 / 14 | 33 | 33 | 20 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The Cider Shrine `cider_shrine` | shrine | 6 / 14 | 33 | 33 | 20 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The Weighing Stone `the_weighing_stone` | standing_stones | 6 / 25 | 12 | 12 | 49 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small |
| 1 | The Gossip Stones `gossip_stones` | standing_stones | 7 / 14 | 12 | 12 | 51 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | Hushwatch `hushwatch_stones` | standing_stones | 7 / 25 | 12 | 12 | 51 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small |
| 1 | The Brow Lichen Ring `brow_lichen_ring` | standing_stones | 7 / 14 | 15 | 15 | 51 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | Wolf Holt `wolf_holt` | ruins | 8 / 25 | 21 | 21 | 123 | 0 | 3 | 0 | 0 |  | yes |  |  |  | WEAK small |
| 1 | The Chalk Cell `chalk_cell` | ruins | 8 / 25 | 21 | 21 | 126 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small |
| 2 | The Southgate Stone `southgate_stone` | shrine | 6 / 25 | 40 | 40 | 20 | 1 | 0 | 0 | 0 |  |  |  | yes |  | WEAK small |
| 2 | Ash Watch `ash_watch` | tower | 6 / 25 | 15 | 15 | 69 | 0 | 0 | 0 | 0 | yes |  |  |  |  | WEAK small |
| 2 | The Roll Stone `roll_stone` | standing_stones | 6 / 25 | 12 | 12 | 49 | 0 | 0 | 0 | 0 | yes |  |  |  |  | WEAK small |
| 2 | Hound Watch `hound_watch` | tower | 6 / 25 | 15 | 15 | 69 | 0 | 0 | 0 | 0 | yes |  |  |  |  | WEAK small |
| 2 | The Cliff Hearth `cliff_hearth` | shrine | 6 / 25 | 40 | 40 | 20 | 1 | 0 | 0 | 0 |  |  |  | yes |  | WEAK small |
| 2 | The Rubbing Stones `rubbing_stones` | standing_stones | 7 / 14 | 12 | 12 | 49 | 0 | 2 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 2 | The Brow Beacon `brow_beacon` | tower | 7 / 25 | 15 | 15 | 69 | 0 | 0 | 0 | 0 | yes |  |  |  |  | WEAK small |
| 2 | The Naming Stone `the_naming_stone` | shrine | 7 / 25 | 40 | 40 | 19 | 1 | 0 | 0 | 0 |  |  |  | yes |  | WEAK small |
| 2 | The Grey End `the_grey_end` | ruins | 8 / 25 | 5 | 7 | 94 | 0 | 3 | 0 | 0 |  | yes |  |  |  | WEAK small |
| 2 | The Warden Barrow `warden_barrow` | ruins | 9 / 25 | 12 | 12 | 112 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small |
| 2 | Bell Meadow Stones `bell_meadow_stones` | standing_stones | 9 / 25 | 19 | 19 | 53 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small |
| 2 | The Hayward's Perch `haywards_perch` | tower | 9 / 25 | 15 | 15 | 20 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small |
| 2 | The Turned Hut `turned_hut` | ruins | 10 / 25 | 21 | 21 | 126 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK |
| 2 | Toll View `toll_view` | vista | 11 / 14 | 10 | 10 | 74 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK wayside |
| 2 | Ribbon Meg's Fire `ribbon_megs_fire` | camp | 13 / 14 | 56 | 56 | 52 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK wayside |
| 3 | Lamb's Bottom `lambs_bottom` | ruins | 9 / 25 | 21 | 21 | 126 | 0 | 4 | 0 | 0 |  | yes |  |  |  | WEAK small |
| 3 | The Old Sheepwash `old_sheepwash` | ruins | 9 / 25 | 21 | 21 | 123 | 0 | 0 | 0 | 0 | yes |  |  |  |  | WEAK small |
| 3 | Whitecut Falls `whitecut_falls` | waterfall | 10 / 25 | 14 | 14 | 200 | 0 | 4 | 0 | 0 |  | yes |  |  |  | WEAK small |
| 3 | The Pinfold `the_pinfold` | ruins | 10 / 25 | 21 | 21 | 126 | 0 | 0 | 0 | 0 | yes |  |  |  |  | WEAK small |
| 3 | The Malting Floor `malting_floor` | ruins | 10 / 14 | 21 | 21 | 122 | 0 | 2 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 3 | The Dole-House `dole_house` | ruins | 10 / 14 | 12 | 12 | 112 | 0 | 1 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 3 | The Lone Barrow `lone_barrow` | ruins | 10 / 14 | 12 | 12 | 116 | 0 | 1 | 2 | 0 |  | yes |  |  |  | WEAK wayside |
| 3 | The Cliff Graves `cliff_graves` | ruins | 10 / 25 | 12 | 12 | 112 | 0 | 0 | 0 | 0 | yes |  |  |  |  | WEAK |
| 3 | The Last Look `last_look` | vista | 11 / 25 | 10 | 10 | 74 | 0 | 0 | 0 | 0 | yes |  |  |  |  | WEAK |
| 3 | The Long Table Bench `long_table_bench` | vista | 11 / 14 | 10 | 10 | 73 | 0 | 1 | 2 | 0 |  | yes |  |  |  | WEAK wayside |
| 3 | The Drove Gate Toll `drove_gate_toll` | camp | 13 / 14 | 68 | 68 | 62 | 0 | 3 | 2 | 0 |  | yes |  |  |  | WEAK wayside |
| 3 | The Wardens' Halt `wardens_halt` | camp | 13 / 14 | 74 | 74 | 64 | 0 | 2 | 2 | 0 |  | yes |  |  |  | WEAK wayside |
| 3 | Rook Mill `rook_mill` | mill | 13 / 25 | 31 | 31 | 42 | 0 | 0 | 0 | 0 | yes |  |  |  |  | WEAK |
| 3 | Gorse Hut `gorse_hut` | shieling | 13 / 14 | 11 | 11 | 31 | 0 | 3 | 2 | 0 |  | yes |  |  |  | WEAK wayside |
| 3 | The Boys' Lookout `boys_lookout` | camp | 14 / 14 | 68 | 68 | 62 | 0 | 2 | 2 | 0 |  | yes |  |  |  | WEAK wayside |
| 3 | Hurdle Fold `hurdle_fold` | camp | 14 / 22 | 74 | 74 | 65 | 0 | 3 | 0 | 0 |  | yes |  |  |  | WEAK |
| 3 | The Dewpond Fold `dewpond_fold` | camp | 15 / 22 | 59 | 59 | 53 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK |
| 3 | Larkbourne Ford `larkbourne_ford` | bridge | 16 / 25 | 12 | 12 | 9 | 0 | 2 | 0 | 0 |  | yes |  |  |  | WEAK |
| 3 | Pennywort Bridge `pennywort_bridge` | bridge | 19 / 25 | 8 | 8 | 6 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK |
| 3 | The Hush Steps `hush_steps` | ruins | 20 / 25 | 9 | 9 | 61 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK |
| 4 | The Wellspring `the_wellspring` | shrine | 6 / 25 | 43 | 43 | 35 | 1 | 0 | 0 | 0 | yes |  |  | yes |  | small |
| 4 | Candle Cross `candle_cross` | shrine | 6 / 25 | 40 | 40 | 20 | 1 | 0 | 0 | 0 | yes |  |  | yes |  | small |
| 4 | Orm's Long Barrow `orms_long_barrow` | ruins | 8 / 25 | 12 | 12 | 116 | 0 | 2 | 0 | 0 | yes | yes |  |  |  | small |
| 4 | Tallow Barrow `tallow_barrow` | ruins | 10 / 25 | 12 | 12 | 116 | 0 | 3 | 0 | 0 | yes | yes |  |  |  |  |
| 4 | The Singing Yew `singing_yew` | strange_tree | 12 / 25 | 22 | 23 | 28 | 0 | 2 | 0 | 0 | yes | yes |  |  |  |  |
| 4 | Foxglove Dell `foxglove_dell` | hidden_valley | 15 / 25 | 31 | 33 | 416 | 0 | 2 | 0 | 1 |  | yes |  |  |  |  |
| 4 | Cress Mill `cress_mill` | mill | 15 / 25 | 34 | 34 | 54 | 0 | 0 | 2 | 1 |  | yes |  |  |  |  |
| 4 | The Warrener's Camp `warreners_camp` | camp | 15 / 22 | 74 | 74 | 64 | 0 | 0 | 0 | 0 | yes |  |  |  |  |  |
| 4 | Lark Mill `lark_mill` | mill | 16 / 25 | 34 | 34 | 54 | 0 | 0 | 2 | 1 |  | yes |  |  |  |  |
| 4 | The Lambing Fold `lambing_fold` | camp | 16 / 22 | 74 | 74 | 65 | 0 | 0 | 0 | 0 | yes |  |  |  |  |  |
| 4 | Hanging Coombe `hanging_coombe` | camp | 16 / 22 | 68 | 68 | 62 | 0 | 4 | 0 | 0 |  | yes |  |  |  |  |
| 4 | Southgate Farm `southgate_farm` | farmstead | 17 / 25 | 40 | 40 | 36 | 0 | 0 | 2 | 1 |  | yes |  |  |  |  |
| 4 | Larkfield `larkfield_farm` | farmstead | 19 / 25 | 37 | 37 | 37 | 0 | 0 | 2 | 1 |  | yes |  |  |  |  |
| 4 | Hazel Bottom `hazel_bottom_farm` | farmstead | 19 / 25 | 39 | 39 | 38 | 0 | 0 | 2 | 1 |  | yes |  |  |  |  |
| 4 | Ridgeway Farm `ridgeway_farm` | farmstead | 19 / 25 | 37 | 37 | 36 | 0 | 0 | 2 | 1 |  | yes |  |  |  |  |
| 4 | The Last Farm `grey_end_farm` | farmstead | 20 / 25 | 37 | 37 | 36 | 0 | 0 | 2 | 1 |  | yes |  |  |  |  |
| 4 | Hatchmoor `hatchmoor_farm` | farmstead | 21 / 25 | 40 | 40 | 38 | 0 | 0 | 2 | 1 |  | yes |  |  |  |  |
| 4 | Brow End `brow_end_farm` | farmstead | 22 / 25 | 39 | 39 | 38 | 0 | 0 | 2 | 1 |  | yes |  |  |  |  |
| 4 | The Chalk Pit `chalk_pit` | quarry | 25 / 25 | 17 | 17 | 34 | 0 | 0 | 2 | 0 |  | yes |  |  |  |  |
| 5 | Gosling Pit `gosling_pit` | camp | 12 / 22 | 95 | 95 | 85 | 0 | 5 | 0 | 0 | yes | yes |  |  |  |  |
| 5 | The Turned-Back Fire `turned_back_fire` | camp | 15 / 14 | 84 | 84 | 59 | 1 | 2 | 4 | 0 |  | yes |  |  |  | wayside |
| 5 | The Last Field `the_last_field` | ruins | 15 / 25 | 21 | 21 | 126 | 0 | 2 | 0 | 0 | yes | yes |  |  |  |  |
| 5 | The Rod Stacks `rod_stacks` | camp | 16 / 22 | 62 | 62 | 54 | 1 | 0 | 0 | 0 | yes |  |  |  |  |  |
| 5 | Pennywort Fields `pennywort_fields` | farmstead | 22 / 25 | 45 | 45 | 50 | 0 | 0 | 2 | 1 |  | yes |  |  |  |  |
| 5 | Coldharbour `coldharbour_farm` | farmstead | 22 / 25 | 37 | 37 | 36 | 0 | 0 | 2 | 1 |  | yes |  |  |  |  |
| 5 | Ashway Farm `ashway_farm` | farmstead | 22 / 25 | 39 | 39 | 38 | 0 | 0 | 2 | 1 |  | yes |  |  |  |  |
| 5 | The Cress Bridge `cress_bridge` | bridge | 23 / 25 | 8 | 8 | 6 | 0 | 0 | 0 | 0 | yes |  |  |  |  |  |
| 5 | Fallowgate `fallowgate_farm` | farmstead | 23 / 25 | 39 | 39 | 38 | 0 | 0 | 2 | 1 |  | yes |  |  |  |  |
| 5 | The Flint Pits `the_flint_pits` | quarry | 28 / 25 | 17 | 17 | 34 | 0 | 0 | 0 | 0 | yes |  |  |  |  |  |
| 6 | Ansel's Hedge Shrine `hedge_shrine_of_ansel` | shrine | 10 / 25 | 48 | 49 | 25 | 1 | 0 | 0 | 1 | yes |  |  | yes |  | small |
| 6 | The Wynstead Ditch Camp `wynstead_ditch_camp` | camp | 14 / 14 | 86 | 86 | 74 | 0 | 2 | 2 | 0 | yes | yes |  |  |  | wayside |
| 6 | Hurdlegate Farm `hurdlegate_farm` | farmstead | 19 / 25 | 37 | 37 | 36 | 0 | 0 | 2 | 1 | yes | yes |  |  |  |  |
| 6 | The Tumbled Watch `tumbled_watchtower` | tower | 22 / 25 | 15 | 15 | 95 | 0 | 6 | 0 | 0 | yes | yes |  |  |  |  |

Weak POIs by kind (not wayside): ruins 10, standing_stones 5, tower 4, shrine 3, bridge 2, camp 2, waterfall 1, mill 1, vista 1.


## (c) Placement problems

`seat:*` are the seat audit's findings over the POI's own pieces (tools_gd/seat_audit.gd: floating over the ground, buried, sunk, standing in a road's carriageway, overlapping another piece, a lamp or light hung from nothing; headless, so multimesh rows are not looked at). `past_pad`: pieces stand beyond the flattened pad, on the skirt or raw ground. `steep_skirt`: the pad's skirt (from its level core to its reach) falls at more than 33 deg along some line: a cut or an embankment. `steep_site`: a POI not yet built stands on ground sloping more than 18 deg on average under its pad. `overlap_pad`: two pads overlap. `road_through`: a road crosses the level core of a place that is not road furniture. `in_water`: its middle is in water.

Counts: road_through 17, seat:overlap 3, steep_skirt 3, seat:on_road 3, past_pad 1, seat:floating 1.

| POI | problem | n | detail |
|---|---|---|---|
| `the_flint_pits` | past_pad | 1 | pieces reach 28 m from its middle; its pad is 25 m |
| `brow_beacon` | road_through | 1 | a road passes 0 m from its middle, inside its 18 m level core |
| `cress_mill` | road_through | 1 | a road passes 11 m from its middle, inside its 18 m level core |
| `hanging_coombe` | road_through | 1 | a road passes 1 m from its middle, inside its 15 m level core |
| `hound_watch` | road_through | 1 | a road passes 3 m from its middle, inside its 18 m level core |
| `larkfield_farm` | road_through | 1 | a road passes 6 m from its middle, inside its 18 m level core |
| `last_look` | road_through | 1 | a road passes 8 m from its middle, inside its 18 m level core |
| `rod_stacks` | road_through | 1 | a road passes 0 m from its middle, inside its 15 m level core |
| `roll_stone` | road_through | 1 | a road passes 8 m from its middle, inside its 18 m level core |
| `rook_mill` | road_through | 1 | a road passes 4 m from its middle, inside its 18 m level core |
| `singing_yew` | road_through | 1 | a road passes 0 m from its middle, inside its 18 m level core |
| `southgate_stone` | road_through | 1 | a road passes 0 m from its middle, inside its 18 m level core |
| `the_grey_end` | road_through | 1 | a road passes 0 m from its middle, inside its 18 m level core |
| `the_last_field` | road_through | 1 | a road passes 0 m from its middle, inside its 18 m level core |
| `the_naming_stone` | road_through | 1 | a road passes 4 m from its middle, inside its 18 m level core |
| `the_pinfold` | road_through | 1 | a road passes 13 m from its middle, inside its 18 m level core |
| `the_weighing_stone` | road_through | 1 | a road passes 12 m from its middle, inside its 18 m level core |
| `wolf_holt` | road_through | 1 | a road passes 11 m from its middle, inside its 18 m level core |
| `hush_steps` | seat:floating | 1 | rope_coil sedgemire_rope_coil_b.glb at (2013, 3755): 0.28 m over the ground |
| `brow_beacon` | seat:on_road | 1 | drum Drum at (2420, 3540): stands in the carriageway of rookdown_brow_beacon |
| `singing_yew` | seat:on_road | 1 | yew hearthvale_yew_a.glb at (1520, 1720): stands in the carriageway of tamwick_hollin_barrow |
| `southgate_stone` | seat:on_road | 1 | standing_stone hearthvale_standing_stone_a.glb at (3819, 2559): stands in the carriageway of rookdown_southgate_stone |
| `hedge_shrine_of_ansel` | seat:overlap | 1 | hawthorn hearthvale_hawthorn_a.glb at (778, 1561): 100% of it shares its box with gravestone (poi:shrine) |
| `pennywort_fields` | seat:overlap | 1 | chopping_block hearthvale_chopping_block_a.glb at (-249, 1238): 94% of it shares its box with barrel (poi:farmstead) |
| `southgate_farm` | seat:overlap | 1 | chopping_block hearthvale_chopping_block_b.glb at (3275, 2442): 62% of it shares its box with wheelbarrow (poi:farmstead) |
| `candle_cross` | steep_skirt | 1 | its pad's skirt falls at 52 deg: a cut or an embankment |
| `gosling_pit` | steep_skirt | 1 | its pad's skirt falls at 42 deg: a cut or an embankment |
| `hare_stone` | steep_skirt | 1 | its pad's skirt falls at 55 deg: a cut or an embankment |
