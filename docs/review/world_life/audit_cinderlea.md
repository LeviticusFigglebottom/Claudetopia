# World life audit: Cinderlea

Made by `python3 tools/world/region_audit.py cinderlea` from the installed world (2026-09-28T18:00:36Z) and the content pack; the POI measurements are `docs/review/world_life/probe_cinderlea.json` (tools_gd/poi_probe.gd, headless). docs/WORLD_LIFE.md says how to read and use it.

![map](audit_cinderlea.png)

## Summary

| | |
|---|---|
| land a body walks (dry, no steeper than 32 deg, 250 m in from the map's edge) | 7.1 km2 |
| points of interest | 57 (8.0 per km2; 0 not yet in the built world) |
| land more than 200 m from any place, POI or roadside mark | 0.95 km2 (13%); more than 400 m: 0% |
| share of land further than 100 / 150 / 200 / 300 / 400 m from anything | 60% / 33% / 13% / 0% / 0% |
| largest empty stretch | 0.38 km2 |
| weak POIs (score <= 3) | 26, and 12 wayside finds (small by design) |
| strong POIs (score >= 8) | 3 |
| placement problems | 56, at 34 POIs |

## (a) Empty land, largest first

A stretch is land of the region more than 200 m from the edge of every place's, POI's and roadside mark's pad. `furthest` is how far its middle is from anything. Sites are gentle ground (<= 14 deg) in it, as far from everything as it allows, nearer a road where one is near.

| # | middle (x, z) | km2 | extent m | furthest m | slope mean/p75 | height | province (biome) | road | sites (x, z, slope, road m) |
|---|---|---|---|---|---|---|---|---|---|
| 1 | (-3148, 2356) | 0.38 | 1432 x 1032 | 333 | 5 / 6 | 68 | The Ash Heath (ash_plateau) | nearest 86 m | (-2676, 2836) 1 deg 274 m; (-3260, 2756) 0 deg 311 m; (-2596, 2028) 1 deg 155 m |
| 2 | (-1412, 3052) | 0.12 | 1128 x 584 | 272 | 3 / 4 | 69 | The Ashgrid (ash_plateau) | through it, 16 m | (-1404, 3060) 1 deg 168 m; (-1348, 3380) 1 deg 152 m; (-1884, 3228) 0 deg 192 m |
| 3 | (-3044, 1500) | 0.09 | 1120 x 400 | 301 | 7 / 8 | 61 | The Ash Heath (ash_plateau) | nearest 72 m | (-2492, 1732) 0 deg 150 m; (-3140, 1516) 0 deg 243 m; (-2204, 1716) 1 deg 277 m |
| 4 | (492, 3420) | 0.07 | 328 x 512 | 301 | 7 / 8 | 70 | The Ash Heath (ash_plateau) | nearest 237 m | (492, 3372) 2 deg 408 m; (436, 3652) 4 deg 248 m |
| 5 | (-948, 2748) | 0.06 | 448 x 328 | 280 | 4 / 6 | 68 | The Ash Heath (ash_plateau) | nearest 159 m | (-916, 2740) 1 deg 288 m; (-1124, 2940) 2 deg 201 m |
| 6 | (-2908, 3692) | 0.04 | 256 x 464 | 283 | 7 / 10 | 69 | The Ashgrid (ash_plateau) | nearest 104 m | (-2972, 3252) 1 deg 121 m; (-2788, 3468) 2 deg 268 m |

## (b) Points of interest, weakest first

Impact score, points for each: **size** footprint reach (m from the middle to its furthest piece): <8 = 0, <14 = 1, <22 = 2, <32 = 3, else 4; **things** interactables in the dressing (Hearthstone, touch, container, readable ...): 1 each, up to 3; **foes** an encounter that stands foes up: 1, and 1 more for 4 or more; **loot** something to take (an encounter's `lies`, a quest's item, a find): 1; **people** an NPC who lives or stands there: 1, 2 for two or more; **quest** a quest sends you there: 2; **interior** a door into an interior: 2; **landmark** a landmark model (a `scene` in pois.json): 2; **hearth** a Hearthstone: 1. **Weak** is 3 or under; **small** is a reach under 10 m. `reach` is metres from the middle to the furthest piece; `things` are interactables in the dressing (hearthstones, touches, containers); foes are the encounter's standing count; loot counts an encounter's `lies`, a find and a container.

| score | POI | kind | reach / pad m | pieces | draws | tris k | things | foes | loot | NPCs | quest | enc | interior | hearth | landmark | flags |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | The Salt Road Cairn `salt_road_cairn` | vista | 0 / 14 | 3 | 3 | 65 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The Half-Ash Cairn `half_ash_cairn` | cairn | 0 / 14 | 7 | 7 | 136 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The First-Step Cairn `first_step_cairn` | cairn | 0 / 14 | 7 | 7 | 125 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The Scavenger's Grave `scavengers_grave` | grave | 2 / 14 | 8 | 8 | 51 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The Warden Under the Ash `warden_under_ash` | grave | 2 / 14 | 8 | 8 | 39 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The Glass-Road Stone `glass_road_stone` | waystone | 2 / 14 | 7 | 7 | 1 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The Tenth Waystone `tenth_waystone` | waystone | 2 / 25 | 7 | 7 | 1 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small |
| 1 | The Last Meal Stone `last_meal_stone` | shrine | 3 / 14 | 24 | 24 | 17 | 0 | 0 | 4 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The Last Milestone `last_milestone` | standing_stones | 6 / 25 | 12 | 12 | 47 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small |
| 1 | The Novices' Seats `novices_seats` | standing_stones | 6 / 25 | 12 | 12 | 47 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small |
| 1 | The Tower of Vaelost `tower_of_vaelost` | tower | 6 / 25 | 12 | 12 | 43 | 0 | 1 | 0 | 0 |  | yes |  |  |  | WEAK small |
| 1 | The Bowing Stones `bowing_stones` | standing_stones | 6 / 14 | 12 | 12 | 43 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The Hush Bell `hush_bell` | tower | 7 / 25 | 15 | 15 | 77 | 0 | 2 | 0 | 0 |  | yes |  |  |  | WEAK small |
| 1 | Sulion `sulion` | tower | 7 / 25 | 12 | 12 | 43 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small |
| 2 | The Harbour Milestone `harbour_milestone` | waystone | 2 / 14 | 10 | 10 | 2 | 0 | 3 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 2 | The Turning Cairn `turning_cairn` | shrine | 2 / 25 | 20 | 20 | 13 | 0 | 0 | 0 | 0 | yes |  |  |  |  | WEAK small |
| 2 | The One Poppy `the_one_poppy` | strange | 5 / 25 | 16 | 16 | 140 | 1 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small |
| 2 | The Ninth Waystone `ninth_waystone` | standing_stones | 6 / 25 | 12 | 12 | 55 | 0 | 0 | 0 | 0 | yes |  |  |  |  | WEAK small |
| 2 | The Strand Beacon `strand_beacon` | tower | 6 / 25 | 15 | 15 | 77 | 0 | 0 | 0 | 0 | yes |  |  |  |  | WEAK small |
| 2 | Greywatch `greywatch` | standing_stones | 6 / 25 | 12 | 12 | 51 | 0 | 0 | 0 | 0 | yes |  |  |  |  | WEAK small |
| 2 | The Greyline Stones `greyline_stones` | standing_stones | 6 / 25 | 12 | 12 | 54 | 0 | 0 | 0 | 0 | yes |  |  |  |  | WEAK small |
| 2 | The Hermit's Gate `hermits_gate` | ruins | 8 / 25 | 21 | 21 | 118 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small |
| 2 | The Robing-House `robing_house` | ruins | 8 / 14 | 21 | 21 | 112 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 2 | The Tower-Road Bell `tower_road_bell` | shrine | 8 / 14 | 29 | 29 | 15 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 2 | The Grey Hedge `grey_hedge` | ruins | 9 / 25 | 5 | 7 | 97 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small |
| 2 | Bell Street `bell_street` | ruins | 13 / 25 | 21 | 21 | 121 | 0 | 3 | 0 | 0 |  | yes |  |  |  | WEAK |
| 2 | Hesk-Morn `hesk_morn` | ruins | 14 / 25 | 21 | 21 | 115 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK |
| 3 | The Bell Wood Stone `bell_wood_stone` | shrine | 3 / 25 | 27 | 27 | 12 | 1 | 0 | 2 | 0 |  | yes |  | yes |  | WEAK small |
| 3 | The Last Hearth `last_hearth` | shrine | 4 / 25 | 31 | 31 | 16 | 1 | 0 | 2 | 0 |  | yes |  | yes |  | WEAK small |
| 3 | The Driftwood Camp `driftwood_camp` | camp | 13 / 22 | 56 | 56 | 58 | 0 | 0 | 0 | 0 | yes |  |  |  |  | WEAK |
| 3 | The Anthem Hall `anthem_hall` | ruins | 14 / 25 | 21 | 21 | 112 | 0 | 2 | 0 | 0 |  | yes |  |  |  | WEAK |
| 3 | The Bell Garden `bell_garden` | ruins | 16 / 25 | 21 | 21 | 118 | 0 | 1 | 0 | 0 |  | yes |  |  |  | WEAK |
| 3 | The Weighhouse `weighhouse` | ruins | 16 / 25 | 21 | 21 | 112 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK |
| 3 | The Row of Mouths `row_of_mouths` | ruins | 17 / 25 | 9 | 9 | 61 | 0 | 2 | 0 | 0 |  | yes |  |  |  | WEAK |
| 3 | The Salt Hulk `salt_hulk` | wreck | 17 / 14 | 33 | 33 | 39 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK wayside |
| 3 | The Grey Wreck `grey_wreck` | wreck | 18 / 25 | 33 | 33 | 39 | 0 | 3 | 0 | 0 |  | yes |  |  |  | WEAK |
| 3 | The Cistern of Isse `cistern_of_isse` | ruins | 18 / 25 | 9 | 9 | 61 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK |
| 3 | The Sunk Plaza `sunk_plaza` | ruins | 20 / 25 | 9 | 9 | 61 | 0 | 2 | 0 | 0 |  | yes |  |  |  | WEAK |
| 4 | The Silent Market `silent_market` | ruins | 8 / 25 | 21 | 21 | 118 | 0 | 3 | 0 | 0 | yes | yes |  |  |  | small |
| 4 | The Bell Pit `bell_pit` | ruins | 9 / 25 | 21 | 21 | 121 | 0 | 2 | 0 | 0 | yes | yes |  |  |  | small |
| 4 | The North Gate `north_gate` | ruins | 10 / 25 | 21 | 21 | 115 | 0 | 2 | 0 | 0 | yes | yes |  |  |  |  |
| 4 | The Pilgrims' Bell `bell_of_the_pilgrims` | shrine | 12 / 25 | 36 | 36 | 16 | 1 | 0 | 2 | 0 |  | yes |  | yes |  |  |
| 4 | The Ash-Winter Carts `ashwinter_carts` | ruins | 13 / 25 | 21 | 21 | 118 | 0 | 3 | 0 | 0 | yes | yes |  |  |  |  |
| 4 | Hesk Pool `hesk_pool` | ruins | 17 / 25 | 9 | 9 | 61 | 0 | 0 | 0 | 0 | yes |  |  |  |  |  |
| 4 | The Builders' Harbour `builders_harbour` | ruins | 20 / 25 | 9 | 9 | 61 | 0 | 0 | 0 | 0 | yes |  |  |  |  |  |
| 5 | Ashcombe `ashcombe` | ruins | 14 / 25 | 21 | 21 | 115 | 0 | 4 | 0 | 0 | yes | yes |  |  |  |  |
| 5 | The Headless Watch `headless_watch` | tower | 14 / 25 | 13 | 13 | 83 | 0 | 1 | 0 | 1 | yes | yes |  |  |  |  |
| 5 | The Sweeper's Lean-To `sweepers_lean_to` | camp | 15 / 22 | 62 | 62 | 59 | 0 | 0 | 0 | 1 | yes |  |  |  |  |  |
| 5 | The Scavengers' Cold Camp `scavengers_cold_camp` | camp | 15 / 14 | 84 | 84 | 64 | 1 | 2 | 4 | 0 |  | yes |  |  |  | wayside |
| 5 | The Glass Falls `glass_falls` | waterfall | 23 / 25 | 21 | 21 | 273 | 0 | 1 | 2 | 0 |  | yes |  |  |  |  |
| 5 | The Tide Mouth `hushline_cave` | cave | 26 / 18 | 49 | 49 | 154 | 0 | 3 | 2 | 0 |  | yes |  |  |  |  |
| 5 | The Kneeling Colossus `kneeling_colossus` | ruins | 38 / 25 | 35 | 35 | 102 | 0 | 0 | 2 | 0 |  | yes |  |  |  |  |
| 6 | The Cold Fire `cold_fire_camp` | camp | 13 / 22 | 96 | 96 | 68 | 1 | 6 | 0 | 0 | yes | yes |  |  |  |  |
| 7 | The Thirteenth `thirteenth_colossus` | ruins | 38 / 25 | 35 | 35 | 106 | 0 | 3 | 0 | 2 |  | yes |  |  |  |  |
| 8 | The Hushline Stair `hushline_stair` | hidden_valley | 64 / 26 | 27 | 27 | 13 | 1 | 4 | 0 | 0 |  | yes |  | yes |  |  |
| 8 | The Glass Bridge `glass_bridge` | bridge | 67 / 25 | 14 | 14 | 58 | 0 | 4 | 0 | 0 | yes | yes |  |  |  |  |
| 9 | The Stair Head `stair_head` | camp | 437 / 22 | 245 | 245 | 129 | 2 | 0 | 0 | 0 | yes |  |  | yes |  |  |

Weak POIs by kind (not wayside): ruins 10, standing_stones 5, tower 4, shrine 3, strange 1, wreck 1, waystone 1, camp 1.


## (c) Placement problems

`seat:*` are the seat audit's findings over the POI's own pieces (tools_gd/seat_audit.gd: floating over the ground, buried, sunk, standing in a road's carriageway, overlapping another piece, a lamp or light hung from nothing; headless, so multimesh rows are not looked at). `past_pad`: pieces stand beyond the flattened pad, on the skirt or raw ground. `steep_skirt`: the pad's skirt (from its level core to its reach) falls at more than 33 deg along some line: a cut or an embankment. `steep_site`: a POI not yet built stands on ground sloping more than 18 deg on average under its pad. `overlap_pad`: two pads overlap. `road_through`: a road crosses the level core of a place that is not road furniture. `in_water`: its middle is in water.

Counts: road_through 24, seat:floating 8, past_pad 7, steep_skirt 7, seat:on_road 5, seat:lamp_unhung 2, seat:buried 1, seat:overlap 1, seat:sunk 1.

| POI | problem | n | detail |
|---|---|---|---|
| `glass_bridge` | past_pad | 1 | pieces reach 67 m from its middle; its pad is 25 m |
| `hushline_cave` | past_pad | 1 | pieces reach 26 m from its middle; its pad is 18 m |
| `hushline_stair` | past_pad | 1 | pieces reach 64 m from its middle; its pad is 26 m |
| `kneeling_colossus` | past_pad | 1 | pieces reach 38 m from its middle; its pad is 25 m |
| `salt_hulk` | past_pad | 1 | pieces reach 17 m from its middle; its pad is 14 m |
| `stair_head` | past_pad | 1 | pieces reach 437 m from its middle; its pad is 22 m |
| `thirteenth_colossus` | past_pad | 1 | pieces reach 38 m from its middle; its pad is 25 m |
| `anthem_hall` | road_through | 1 | a road passes 3 m from its middle, inside its 18 m level core |
| `ashcombe` | road_through | 1 | a road passes 1 m from its middle, inside its 18 m level core |
| `ashwinter_carts` | road_through | 1 | a road passes 1 m from its middle, inside its 18 m level core |
| `bell_garden` | road_through | 1 | a road passes 1 m from its middle, inside its 18 m level core |
| `bell_of_the_pilgrims` | road_through | 1 | a road passes 0 m from its middle, inside its 18 m level core |
| `bell_street` | road_through | 1 | a road passes 0 m from its middle, inside its 18 m level core |
| `bell_wood_stone` | road_through | 1 | a road passes 3 m from its middle, inside its 18 m level core |
| `builders_harbour` | road_through | 1 | a road passes 0 m from its middle, inside its 18 m level core |
| `cistern_of_isse` | road_through | 1 | a road passes 2 m from its middle, inside its 18 m level core |
| `cold_fire_camp` | road_through | 1 | a road passes 5 m from its middle, inside its 15 m level core |
| `greywatch` | road_through | 1 | a road passes 1 m from its middle, inside its 18 m level core |
| `hesk_morn` | road_through | 1 | a road passes 0 m from its middle, inside its 18 m level core |
| `hushline_stair` | road_through | 1 | a road passes 0 m from its middle, inside its 18 m level core |
| `kneeling_colossus` | road_through | 1 | a road passes 0 m from its middle, inside its 18 m level core |
| `ninth_waystone` | road_through | 1 | a road passes 0 m from its middle, inside its 18 m level core |
| `row_of_mouths` | road_through | 1 | a road passes 2 m from its middle, inside its 18 m level core |
| `stair_head` | road_through | 1 | a road passes 0 m from its middle, inside its 15 m level core |
| `strand_beacon` | road_through | 1 | a road passes 0 m from its middle, inside its 18 m level core |
| `sulion` | road_through | 1 | a road passes 0 m from its middle, inside its 18 m level core |
| `sunk_plaza` | road_through | 1 | a road passes 0 m from its middle, inside its 18 m level core |
| `sweepers_lean_to` | road_through | 1 | a road passes 2 m from its middle, inside its 15 m level core |
| `the_one_poppy` | road_through | 1 | a road passes 2 m from its middle, inside its 18 m level core |
| `tower_of_vaelost` | road_through | 1 | a road passes 0 m from its middle, inside its 18 m level core |
| `weighhouse` | road_through | 1 | a road passes 1 m from its middle, inside its 18 m level core |
| `hushline_cave` | seat:buried | 5 | throat1 Throat1 at (-593, 3766): all of it under the ground (top 52.97 m below the lowest ground under it) |
| `builders_harbour` | seat:floating | 1 | rope_coil sedgemire_rope_coil_a.glb at (-3491, 2989): 0.27 m over the ground |
| `cistern_of_isse` | seat:floating | 1 | rope_coil sedgemire_rope_coil_b.glb at (-2736, 3150): 0.29 m over the ground |
| `glass_falls` | seat:floating | 1 | stream Stream at (-88, 3039): 0.21 m over the ground |
| `headless_watch` | seat:floating | 1 | eyes Eyes at (-753, 2986): 2.56 m over the ground |
| `hesk_pool` | seat:floating | 1 | rope_coil sedgemire_rope_coil_a.glb at (-1998, 2394): 0.27 m over the ground |
| `stair_head` | seat:floating | 5 | @meshinstance3d@7682 @MeshInstance3D@7682 at (-7, 3670): 1.77 m over the ground |
| `sunk_plaza` | seat:floating | 1 | rope_coil sedgemire_rope_coil_b.glb at (-1588, 3272): 0.30 m over the ground |
| `tower_road_bell` | seat:floating | 1 | bell_medium cinderlea_bell_medium_a.glb at (-2226, 3503): 0.16 m over the ground |
| `grey_wreck` | seat:lamp_unhung | 1 | lantern_hanging sedgemire_lantern_hanging_b.glb at (-3502, 2431): nothing to hang from within 0.3 m (3.5 m over the ground) |
| `salt_hulk` | seat:lamp_unhung | 1 | lantern_hanging sedgemire_lantern_hanging_b.glb at (-3545, 1633): nothing to hang from within 0.3 m (3.6 m over the ground) |
| `ninth_waystone` | seat:on_road | 1 | standing_stone briarwold_standing_stone_a.glb at (-616, 2562): stands in the carriageway of glass_bridge_greyfold |
| `strand_beacon` | seat:on_road | 1 | drum Drum at (-3420, 1950): stands in the carriageway of west_walk_strand_beacon |
| `sulion` | seat:on_road | 1 | drum Drum at (-3120, 3080): stands in the carriageway of greyfold_builders_harbour |
| `sweepers_lean_to` | seat:on_road | 4 | stool briarwold_stool_a.glb at (-61, 2965): stands in the carriageway of sunken_choir_pilgrims_ash |
| `tower_of_vaelost` | seat:on_road | 1 | drum Drum at (-2550, 3350): stands in the carriageway of sunk_plaza_tower_of_vaelost |
| `hushline_cave` | seat:overlap | 1 | boulder cinderlea_boulder_a.glb at (-590, 3771): 61% of it shares its box with boulder (poi:cave) |
| `hushline_cave` | seat:sunk | 6 | boulder cinderlea_boulder_a.glb at (-590, 3771): 382% of its 7.0 m under the ground at its middle |
| `builders_harbour` | steep_skirt | 1 | its pad's skirt falls at 33 deg: a cut or an embankment |
| `glass_falls` | steep_skirt | 1 | its pad's skirt falls at 46 deg: a cut or an embankment |
| `headless_watch` | steep_skirt | 1 | its pad's skirt falls at 52 deg: a cut or an embankment |
| `hushline_cave` | steep_skirt | 1 | its pad's skirt falls at 81 deg: a cut or an embankment |
| `strand_beacon` | steep_skirt | 1 | its pad's skirt falls at 43 deg: a cut or an embankment |
| `sweepers_lean_to` | steep_skirt | 1 | its pad's skirt falls at 37 deg: a cut or an embankment |
| `turning_cairn` | steep_skirt | 1 | its pad's skirt falls at 73 deg: a cut or an embankment |
