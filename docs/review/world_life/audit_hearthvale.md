# World life audit: Hearthvale

Made by `python3 tools/world/region_audit.py hearthvale` from the installed world (2026-09-30T09:38:35Z) and the content pack; the POI measurements are `docs/review/world_life/probe_hearthvale.json` (tools_gd/poi_probe.gd, headless). docs/WORLD_LIFE.md says how to read and use it.

![map](audit_hearthvale.png)

## Summary

| | |
|---|---|
| land a body walks (dry, no steeper than 32 deg, 250 m in from the map's edge) | 10.9 km2 |
| points of interest | 106 (9.7 per km2; 2 not yet in the built world) |
| land more than 200 m from any place, POI or roadside mark | 0.57 km2 (5%); more than 400 m: 0% |
| share of land further than 100 / 150 / 200 / 300 / 400 m from anything | 53% / 24% / 5% / 0% / 0% |
| largest empty stretch | 0.05 km2 |
| weak POIs (score <= 3) | 8, and 25 wayside finds (small by design) |
| strong POIs (score >= 8) | 10 |
| placement problems | 29, at 25 POIs |

## (a) Empty land, largest first

A stretch is land of the region more than 200 m from the edge of every place's, POI's and roadside mark's pad. `furthest` is how far its middle is from anything. Sites are gentle ground (<= 14 deg) in it, as far from everything as it allows, nearer a road where one is near.

| # | middle (x, z) | km2 | extent m | furthest m | slope mean/p75 | height | province (biome) | road | sites (x, z, slope, road m) |
|---|---|---|---|---|---|---|---|---|---|
| 1 | (2964, 1868) | 0.05 | 576 x 264 | 283 | 11 / 15 | 81 | The East Downs (downs) | nearest 152 m | (2956, 1860) 2 deg 215 m; (2588, 1948) 2 deg 216 m |
| 2 | (2972, 2428) | 0.05 | 344 x 560 | 276 | 8 / 10 | 121 | Hound Down and the Brow (downs), Rook Wood | nearest 149 m | (3012, 2460) 1 deg 201 m; (2892, 2716) 2 deg 204 m |
| 3 | (-948, 2140) | 0.05 | 384 x 256 | 288 | 6 / 8 | 57 | The West Downs (downs) | nearest 200 m | (-948, 2140) 1 deg 308 m |
| 4 | (580, 2548) | 0.05 | 488 x 200 | 270 | 8 / 11 | 121 | Hound Down and the Brow (downs) | nearest 144 m | (684, 2572) 1 deg 233 m |

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
| 1 | The Cider Shrine `cider_shrine` | shrine | 6 / 14 | 33 | 33 | 19 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The Garrison Shrine `garrison_shrine` | shrine | 6 / 14 | 33 | 33 | 19 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The Hound's Bowl `hounds_bowl` | shrine | 6 / 14 | 33 | 33 | 19 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The Gossip Stones `gossip_stones` | standing_stones | 7 / 14 | 12 | 12 | 48 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The Brow Lichen Ring `brow_lichen_ring` | standing_stones | 7 / 14 | 15 | 15 | 50 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 2 | The Rubbing Stones `rubbing_stones` | standing_stones | 7 / 14 | 12 | 12 | 48 | 0 | 2 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 2 | Bell Meadow Stones `bell_meadow_stones` | standing_stones | 9 / 25 | 19 | 19 | 52 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small |
| 2 | The Hayward's Perch `haywards_perch` | tower | 9 / 25 | 15 | 15 | 20 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small |
| 2 | Toll View `toll_view` | vista | 11 / 14 | 10 | 10 | 74 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK wayside |
| 2 | Ribbon Meg's Fire `ribbon_megs_fire` | camp | 13 / 14 | 56 | 56 | 52 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK wayside |
| 3 | The Roll Stone `roll_stone` | standing_stones | 4 / 25 | 10 | 10 | 24 | 1 | 0 | 0 | 0 | yes |  |  |  |  | WEAK small |
| 3 | Lamb's Bottom `lambs_bottom` | ruins | 7 / 25 | 15 | 15 | 29 | 0 | 4 | 2 | 0 |  | yes |  |  |  | WEAK small |
| 3 | The Naming Stone `the_naming_stone` | shrine | 7 / 25 | 48 | 49 | 30 | 2 | 0 | 0 | 0 |  |  |  | yes |  | WEAK small |
| 3 | The Weighing Stone `the_weighing_stone` | standing_stones | 9 / 25 | 8 | 8 | 10 | 1 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small |
| 3 | The Malting Floor `malting_floor` | ruins | 10 / 14 | 22 | 22 | 123 | 0 | 2 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 3 | The Dole-House `dole_house` | ruins | 10 / 14 | 12 | 12 | 112 | 0 | 1 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 3 | The Lone Barrow `lone_barrow` | ruins | 10 / 14 | 12 | 12 | 116 | 0 | 1 | 2 | 0 |  | yes |  |  |  | WEAK wayside |
| 3 | The Long Table Bench `long_table_bench` | vista | 11 / 14 | 10 | 10 | 73 | 0 | 1 | 2 | 0 |  | yes |  |  |  | WEAK wayside |
| 3 | The Hare Stone `hare_stone` | standing_stones | 12 / 14 | 15 | 17 | 35 | 1 | 0 | 2 | 0 |  | yes |  |  |  | WEAK |
| 3 | The Drove Gate Toll `drove_gate_toll` | camp | 13 / 14 | 68 | 68 | 62 | 0 | 3 | 2 | 0 |  | yes |  |  |  | WEAK wayside |
| 3 | The Wardens' Halt `wardens_halt` | camp | 13 / 14 | 74 | 74 | 64 | 0 | 2 | 2 | 0 |  | yes |  |  |  | WEAK wayside |
| 3 | Gorse Hut `gorse_hut` | shieling | 13 / 14 | 11 | 11 | 31 | 0 | 3 | 2 | 0 |  | yes |  |  |  | WEAK wayside |
| 3 | The Boys' Lookout `boys_lookout` | camp | 14 / 14 | 68 | 68 | 62 | 0 | 2 | 2 | 0 |  | yes |  |  |  | WEAK wayside |
| 3 | Pennywort Bridge `pennywort_bridge` | bridge | 19 / 25 | 8 | 8 | 6 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK |
| 4 | Ash Watch `ash_watch` | tower | 6 / 25 | 15 | 15 | 69 | 0 | 0 | 2 | 1 | yes | yes |  |  |  | small |
| 4 | The Wellspring `the_wellspring` | shrine | 6 / 25 | 43 | 43 | 34 | 1 | 0 | 0 | 0 | yes |  |  | yes |  | small |
| 4 | Hound Watch `hound_watch` | tower | 6 / 25 | 15 | 15 | 69 | 0 | 0 | 2 | 1 | yes | yes |  |  |  | small |
| 4 | Candle Cross `candle_cross` | shrine | 6 / 16 | 54 | 54 | 21 | 1 | 0 | 0 | 0 | yes |  |  | yes |  | small |
| 4 | The Cliff Hearth `cliff_hearth` | shrine | 6 / 25 | 40 | 40 | 19 | 1 | 0 | 2 | 1 |  | yes |  | yes |  | small |
| 4 | The Brow Beacon `brow_beacon` | tower | 7 / 25 | 15 | 15 | 69 | 0 | 0 | 2 | 1 | yes | yes |  |  |  | small |
| 4 | Hushwatch `hushwatch_stones` | standing_stones | 7 / 25 | 12 | 12 | 48 | 1 | 0 | 4 | 0 | yes | yes |  |  |  | small |
| 4 | The Rookdown Bee-Garth `rookdown_bee_garth` | fold | 8 / 16 | 10 | 10 | 59 | 2 | 0 | 3 | 1 |  | yes |  |  |  | small |
| 4 | The Grey End `the_grey_end` | ruins | 8 / 25 | 5 | 7 | 94 | 0 | 3 | 2 | 1 |  | yes |  |  |  | small |
| 4 | The Struck Gibbet `struck_gibbet` | gibbet | 9 / 16 | 14 | 14 | 2 | 1 | 2 | 2 | 0 |  | yes |  |  |  | small |
| 4 | Whitecut Falls `whitecut_falls` | waterfall | 10 / 25 | 14 | 14 | 200 | 0 | 4 | 2 | 0 |  | yes |  |  |  | small |
| 4 | The Last Look `last_look` | vista | 11 / 25 | 10 | 10 | 74 | 0 | 0 | 2 | 0 | yes | yes |  |  |  |  |
| 4 | The Old Sheepwash `old_sheepwash` | ruins | 11 / 25 | 9 | 9 | 11 | 0 | 0 | 2 | 0 | yes | yes |  |  |  |  |
| 4 | The Singing Yew `singing_yew` | strange_tree | 12 / 25 | 22 | 23 | 28 | 0 | 2 | 0 | 0 | yes | yes |  |  |  |  |
| 4 | Rook Mill `rook_mill` | mill | 13 / 25 | 31 | 31 | 42 | 0 | 1 | 0 | 0 | yes | yes |  |  |  |  |
| 4 | Hurdle Fold `hurdle_fold` | camp | 14 / 22 | 74 | 74 | 65 | 0 | 3 | 0 | 1 |  | yes |  |  |  |  |
| 4 | Foxglove Dell `foxglove_dell` | hidden_valley | 15 / 25 | 31 | 33 | 416 | 0 | 2 | 0 | 1 |  | yes |  |  |  |  |
| 4 | Cress Mill `cress_mill` | mill | 15 / 25 | 34 | 34 | 54 | 0 | 0 | 2 | 1 |  | yes |  |  |  |  |
| 4 | The Dewpond Fold `dewpond_fold` | camp | 15 / 22 | 59 | 59 | 53 | 0 | 0 | 2 | 1 |  | yes |  |  |  |  |
| 4 | The Warrener's Camp `warreners_camp` | camp | 15 / 22 | 74 | 74 | 64 | 0 | 0 | 0 | 0 | yes |  |  |  |  |  |
| 4 | Lark Mill `lark_mill` | mill | 16 / 25 | 34 | 34 | 54 | 0 | 0 | 2 | 1 |  | yes |  |  |  |  |
| 4 | The Lambing Fold `lambing_fold` | camp | 16 / 22 | 74 | 74 | 65 | 0 | 0 | 0 | 0 | yes |  |  |  |  |  |
| 4 | Larkbourne Ford `larkbourne_ford` | bridge | 16 / 25 | 12 | 12 | 9 | 0 | 2 | 2 | 0 |  | yes |  |  |  |  |
| 4 | The Chalk Cell `chalk_cell` | ruins | 17 / 25 | 13 | 13 | 4 | 1 | 0 | 2 | 0 |  | yes |  |  |  |  |
| 4 | Southgate Farm `southgate_farm` | farmstead | 17 / 25 | 40 | 40 | 36 | 0 | 0 | 2 | 1 |  | yes |  |  |  |  |
| 4 | Larkfield `larkfield_farm` | farmstead | 19 / 25 | 37 | 37 | 37 | 0 | 0 | 2 | 1 |  | yes |  |  |  |  |
| 4 | Hazel Bottom `hazel_bottom_farm` | farmstead | 19 / 25 | 39 | 39 | 38 | 0 | 0 | 2 | 1 |  | yes |  |  |  |  |
| 4 | The Last Farm `grey_end_farm` | farmstead | 20 / 25 | 37 | 37 | 36 | 0 | 0 | 2 | 1 |  | yes |  |  |  |  |
| 4 | Ridgeway Farm `ridgeway_farm` | farmstead | 20 / 25 | 37 | 37 | 36 | 0 | 0 | 2 | 1 |  | yes |  |  |  |  |
| 4 | Hatchmoor `hatchmoor_farm` | farmstead | 21 / 25 | 40 | 40 | 38 | 0 | 0 | 2 | 1 |  | yes |  |  |  |  |
| 4 | The Southgate Stone `southgate_stone` | shrine | 21 / 25 | 43 | 43 | 23 | 1 | 0 | 0 | 0 |  |  |  | yes |  |  |
| 4 | Brow End `brow_end_farm` | farmstead | 22 / 25 | 39 | 39 | 38 | 0 | 0 | 2 | 1 |  | yes |  |  |  |  |
| 4 | The Turned Hut `turned_hut` | ruins | 23 / 25 | 13 | 13 | 10 | 0 | 0 | 2 | 0 |  | yes |  |  |  |  |
| 4 | The Chalk Pit `chalk_pit` | quarry | 28 / 25 | 17 | 17 | 34 | 0 | 0 | 2 | 0 |  | yes |  |  |  |  |
| 5 | Wolf Holt `wolf_holt` | ruins | 10 / 25 | 9 | 9 | 50 | 0 | 3 | 2 | 0 | yes | yes |  |  |  |  |
| 5 | The Bram Down Wheelhouse `bram_wheelhouse` | hut | 13 / 16 | 15 | 15 | 7 | 1 | 2 | 3 | 1 |  | yes |  |  |  |  |
| 5 | Gosling Pit `gosling_pit` | camp | 13 / 18 | 95 | 95 | 85 | 0 | 5 | 0 | 0 | yes | yes |  |  |  |  |
| 5 | The Turned-Back Fire `turned_back_fire` | camp | 15 / 14 | 84 | 84 | 59 | 1 | 2 | 4 | 0 |  | yes |  |  |  | wayside |
| 5 | The Rod Stacks `rod_stacks` | camp | 16 / 22 | 62 | 62 | 54 | 1 | 0 | 0 | 0 | yes |  |  |  |  |  |
| 5 | The Deneholes `hound_down_deneholes` | quarry | 16 / 24 | 14 | 14 | 3 | 1 | 2 | 3 | 0 |  | yes |  |  |  |  |
| 5 | The Roadmen's Lodge `roadmens_lodge` | ruins | 19 / 22 | 32 | 32 | 131 | 0 | 3 | 2 | 1 |  | yes |  |  |  |  |
| 5 | The Hush Steps `hush_steps` | ruins | 20 / 25 | 12 | 12 | 63 | 0 | 0 | 2 | 0 | yes | yes |  |  |  |  |
| 5 | Pennywort Fields `pennywort_fields` | farmstead | 22 / 25 | 45 | 45 | 50 | 0 | 0 | 2 | 1 |  | yes |  |  |  |  |
| 5 | Coldharbour `coldharbour_farm` | farmstead | 22 / 25 | 37 | 37 | 36 | 0 | 0 | 2 | 1 |  | yes |  |  |  |  |
| 5 | The Cress Bridge `cress_bridge` | bridge | 23 / 25 | 8 | 8 | 6 | 0 | 0 | 0 | 0 | yes |  |  |  |  |  |
| 5 | Fallowgate `fallowgate_farm` | farmstead | 23 / 25 | 39 | 39 | 38 | 0 | 0 | 2 | 1 |  | yes |  |  |  |  |
| 5 | The Flint Pits `the_flint_pits` | quarry | 28 / 32 | 17 | 17 | 34 | 0 | 0 | 0 | 0 | yes |  |  |  |  |  |
| 6 | Ansel's Hedge Shrine `hedge_shrine_of_ansel` | shrine | 10 / 25 | 48 | 49 | 25 | 1 | 0 | 0 | 1 | yes |  |  | yes |  | small |
| 6 | The Pinfold `the_pinfold` | ruins | 10 / 25 | 13 | 13 | 20 | 2 | 0 | 2 | 0 | yes | yes |  |  |  | small |
| 6 | The Wynstead Ditch Camp `wynstead_ditch_camp` | camp | 14 / 14 | 86 | 86 | 74 | 0 | 2 | 2 | 0 | yes | yes |  |  |  | wayside |
| 6 | The Cliff Graves `cliff_graves` | ruins | 16 / 25 | 61 | 61 | 15 | 1 | 0 | 2 | 0 | yes | yes |  |  |  |  |
| 6 | Hanging Coombe `hanging_coombe` | camp | 16 / 22 | 68 | 68 | 62 | 0 | 4 | 0 | 0 | yes | yes |  |  |  |  |
| 6 | Tallow Barrow `tallow_barrow` | ruins | 17 / 25 | 11 | 11 | 15 | 1 | 3 | 0 | 0 | yes | yes |  |  |  |  |
| 6 | Hurdlegate Farm `hurdlegate_farm` | farmstead | 19 / 25 | 37 | 37 | 36 | 0 | 0 | 2 | 1 | yes | yes |  |  |  |  |
| 6 | Orm's Long Barrow `orms_long_barrow` | ruins | 19 / 25 | 13 | 14 | 22 | 1 | 2 | 0 | 0 | yes | yes |  |  |  |  |
| 6 | The Tumbled Watch `tumbled_watchtower` | tower | 22 / 25 | 15 | 15 | 95 | 0 | 6 | 0 | 0 | yes | yes |  |  |  |  |
| 6 | The Drovers' Pound `drovers_pound` | stockade | 23 / 26 | 175 | 175 | 107 | 0 | 5 | 2 | 0 |  | yes |  |  |  |  |
| 6 | The Southcote Lynchets `southcote_lynchets` | ruins | 23 / 30 | 23 | 24 | 14 | 0 | 4 | 2 | 0 |  | yes |  |  |  |  |
| 6 | The Mother Pippin `mother_pippin` | strange_tree | 27 / 28 | 62 | 76 | 129 | 0 | 2 | 2 | 1 |  | yes |  |  |  |  |
| 7 | The Wheel Graves `wheel_graves` | grave | 8 / 18 | 20 | 20 | 4 | 1 | 2 | 3 | 1 | yes | yes |  |  |  | small |
| 7 | Ashway Farm `ashway_farm` | farmstead | 22 / 25 | 39 | 39 | 38 | 0 | 0 | 2 | 1 | yes | yes |  |  |  |  |
| 7 | The Warden Barrow `warden_barrow` | ruins | 24 / 25 | 37 | 38 | 54 | 1 | 0 | 2 | 0 | yes | yes |  |  |  |  |
| 7 | The Last Field `the_last_field` | ruins | 28 / 25 | 23 | 27 | 30 | 1 | 2 | 0 | 0 | yes | yes |  |  |  |  |
| 8 | The Listener's Shieling `listeners_shieling` | shieling | 14 / 22 | 33 | 33 | 43 | 2 | 2 | 3 | 1 | yes | yes |  |  |  |  |
| 8 | The Brow Long Table `brow_long_table` | market_field | 23 / 26 | 27 | 28 | 62 | 1 | 0 | 2 | 1 | yes | yes |  |  |  |  |
| 9 | The Lime Bay Kilns `lime_bay_kilns` | quarry | 20 / 30 | 17 | 17 | 16 | 1 | 2 | 3 | 2 | yes | yes |  |  |  |  |
| 9 | Briarfoot Watch `briarfoot_watch` | watchtower | 32 / 24 | 140 | 140 | 102 | 2 | 1 | 3 | 2 |  | yes |  |  |  |  |
| 10 | Scathe Fort `scathe_fort` | fort | 33 / 38 | 140 | 140 | 107 | 2 | 0 | 0 | 0 | yes |  | yes |  |  |  |
| 10 | The Wardens' Kennels `wardens_kennels` | walled_camp | 34 / 22 | 130 | 130 | 100 | 0 | 2 | 2 | 2 | yes | yes |  |  |  |  |
| 11 | The Scourers' Lodge `scourers_lodge` | farmstead | 24 / 28 | 57 | 57 | 55 | 3 | 0 | 3 | 2 | yes | yes |  |  |  |  |
| 12 | The Hound's Swallet `hounds_swallet` | delve | 32 / 34 | 71 | 75 | 98 | 2 | 4 | 2 | 0 | yes | yes | yes |  |  |  |
| 13 | Knappers' Deep `knappers_deep` | delve | 40 / 40 | 58 | 60 | 295 | 3 | 0 | 1 | 1 | yes |  | yes |  |  | unbuilt |
| 14 | The Hum Stone `hum_stone` | delve | 36 / 36 | 49 | 49 | 35 | 4 | 3 | 1 | 1 | yes | yes | yes |  |  | unbuilt |

Weak POIs by kind (not wayside): standing_stones 4, ruins 1, shrine 1, bridge 1, tower 1.


## (c) Placement problems

`seat:*` are the seat audit's findings over the POI's own pieces (tools_gd/seat_audit.gd: floating over the ground, buried, sunk, standing in a road's carriageway, overlapping another piece, a lamp or light hung from nothing; headless, so multimesh rows are not looked at). `past_pad`: pieces stand beyond the flattened pad, on the skirt or raw ground. `steep_skirt`: the pad's skirt (from its level core to its reach) falls at more than 33 deg along some line: a cut or an embankment. `steep_site`: a POI not yet built stands on ground sloping more than 18 deg on average under its pad. `overlap_pad`: two pads overlap. `road_through`: a road crosses the level core of a place that is not road furniture. `in_water`: its middle is in water.

Counts: road_through 17, steep_skirt 4, past_pad 4, seat:on_road 2, seat:overlap 2.

| POI | problem | n | detail |
|---|---|---|---|
| `briarfoot_watch` | past_pad | 1 | pieces reach 32 m from its middle; its pad is 24 m |
| `chalk_pit` | past_pad | 1 | pieces reach 28 m from its middle; its pad is 25 m |
| `the_last_field` | past_pad | 1 | pieces reach 28 m from its middle; its pad is 25 m |
| `wardens_kennels` | past_pad | 1 | pieces reach 34 m from its middle; its pad is 22 m |
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
| `brow_beacon` | seat:on_road | 1 | drum Drum at (2420, 3540): stands in the carriageway of rookdown_brow_beacon |
| `singing_yew` | seat:on_road | 1 | yew hearthvale_yew_a.glb at (1520, 1720): stands in the carriageway of tamwick_hollin_barrow |
| `bell_meadow_stones` | seat:overlap | 1 | standing_stone hearthvale_standing_stone_a.glb at (422, 1086): 94% of it shares its box with bell_small (poi:standing_stones) |
| `hounds_swallet` | seat:overlap | 1 | boulder hearthvale_boulder_a.glb at (1061, 3646): 91% of it shares its box with hawthorn_veteran (poi:delve) |
| `briarfoot_watch` | steep_skirt | 1 | its pad's skirt falls at 38 deg: a cut or an embankment |
| `candle_cross` | steep_skirt | 1 | its pad's skirt falls at 49 deg: a cut or an embankment |
| `gosling_pit` | steep_skirt | 1 | its pad's skirt falls at 44 deg: a cut or an embankment |
| `hare_stone` | steep_skirt | 1 | its pad's skirt falls at 59 deg: a cut or an embankment |
