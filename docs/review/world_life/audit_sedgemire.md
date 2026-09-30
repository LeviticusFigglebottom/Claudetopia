# World life audit: Sedgemire

Made by `python3 tools/world/region_audit.py sedgemire` from the installed world (2026-09-28T18:00:36Z) and the content pack; the POI measurements are `docs/review/world_life/probe_sedgemire.json` (tools_gd/poi_probe.gd, headless). docs/WORLD_LIFE.md says how to read and use it.

![map](audit_sedgemire.png)

## Summary

| | |
|---|---|
| land a body walks (dry, no steeper than 32 deg, 250 m in from the map's edge) | 6.0 km2 |
| points of interest | 57 (9.6 per km2; 11 not yet in the built world) |
| land more than 200 m from any place, POI or roadside mark | 0.41 km2 (7%); more than 400 m: 0% |
| share of land further than 100 / 150 / 200 / 300 / 400 m from anything | 58% / 28% / 7% / 0% / 0% |
| largest empty stretch | 0.07 km2 |
| weak POIs (score <= 3) | 8, and 9 wayside finds (small by design) |
| strong POIs (score >= 8) | 8 |
| placement problems | 23, at 17 POIs |

## (a) Empty land, largest first

A stretch is land of the region more than 200 m from the edge of every place's, POI's and roadside mark's pad. `furthest` is how far its middle is from anything. Sites are gentle ground (<= 14 deg) in it, as far from everything as it allows, nearer a road where one is near.

| # | middle (x, z) | km2 | extent m | furthest m | slope mean/p75 | height | province (biome) | road | sites (x, z, slope, road m) |
|---|---|---|---|---|---|---|---|---|---|
| 1 | (-1772, -1380) | 0.07 | 440 x 632 | 287 | 5 / 6 | 31 | The North Shore (lake_basin) | nearest 380 m | (-2028, -956) 0 deg 476 m; (-1876, -1292) 0 deg 484 m |

## (b) Points of interest, weakest first

Impact score, points for each: **size** footprint reach (m from the middle to its furthest piece): <8 = 0, <14 = 1, <22 = 2, <32 = 3, else 4; **things** interactables in the dressing (Hearthstone, touch, container, readable ...): 1 each, up to 3; **foes** an encounter that stands foes up: 1, and 1 more for 4 or more; **loot** something to take (an encounter's `lies`, a quest's item, a find): 1; **people** an NPC who lives or stands there: 1, 2 for two or more; **quest** a quest sends you there: 2; **interior** a door into an interior: 2; **landmark** a landmark model (a `scene` in pois.json): 2; **hearth** a Hearthstone: 1. **Weak** is 3 or under; **small** is a reach under 10 m. `reach` is metres from the middle to the furthest piece; `things` are interactables in the dressing (hearthstones, touches, containers); foes are the encounter's standing count; loot counts an encounter's `lies`, a find and a container.

| score | POI | kind | reach / pad m | pieces | draws | tris k | things | foes | loot | NPCs | quest | enc | interior | hearth | landmark | flags |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | The Drowned Road Post `drowned_road_post` | lantern_post | 1 / 14 | 9 | 9 | 11 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The Sunken Tower `sunken_tower` | tower | 6 / 25 | 12 | 12 | 50 | 0 | 2 | 0 | 0 |  | yes |  |  |  | WEAK small |
| 1 | The Eel-Smoker's Hut `eel_smokers_hut` | hut | 6 / 14 | 15 | 15 | 35 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The Peat-Cutters' Light `peat_cutters_light` | lantern_post | 6 / 14 | 17 | 17 | 13 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The Round Stones `round_stones` | standing_stones | 6 / 25 | 12 | 12 | 51 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small |
| 1 | The Knuckle Cairn `knuckle_cairn` | standing_stones | 6 / 25 | 12 | 12 | 50 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small |
| 1 | The Pushers' Stones `pushers_stones` | standing_stones | 6 / 14 | 12 | 12 | 51 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 1 | The Drowned Road `drowned_road` | ruins | 8 / 25 | 21 | 21 | 126 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK small |
| 2 | The Fog Bell `fog_bell` | tower | 6 / 25 | 15 | 15 | 71 | 0 | 0 | 0 | 0 | yes |  |  |  |  | WEAK small |
| 2 | The Broken Stilts `broken_stilts` | ruins | 8 / 14 | 21 | 21 | 126 | 0 | 1 | 2 | 0 |  | yes |  |  |  | WEAK small wayside |
| 2 | Crookstilts `crookstilts` | tower | 8 / 25 | 15 | 15 | 20 | 0 | 2 | 0 | 0 |  | yes |  |  |  | WEAK small |
| 2 | The Tideflat Stones `tideflat_stones` | standing_stones | 12 / 25 | 19 | 19 | 205 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK |
| 2 | Oskel Ford `oskel_ford` | bridge | 13 / 25 | 2 | 2 | 1 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK |
| 3 | The Drowned Byre `drowned_byre` | ruins | 10 / 14 | 21 | 21 | 138 | 0 | 2 | 2 | 0 |  | yes |  |  |  | WEAK wayside |
| 3 | The Settled House `settled_house` | ruins | 10 / 14 | 21 | 21 | 138 | 0 | 2 | 4 | 0 |  | yes |  |  |  | WEAK wayside |
| 3 | The Lantern-Wright's Camp `lantern_wrights_camp` | camp | 13 / 14 | 56 | 56 | 54 | 0 | 2 | 2 | 0 |  | yes |  |  |  | WEAK wayside |
| 3 | The Lantern Hummock `lantern_hummock` | shrine | 15 / 14 | 36 | 36 | 15 | 0 | 0 | 2 | 0 |  | yes |  |  |  | WEAK wayside |
| 4 | The Tide Hearth `tide_hearth` | shrine | 3 / 25 | 31 | 31 | 16 | 1 | 0 | 0 | 0 | yes |  |  | yes |  | small |
| 4 | The Old Crannog `old_crannog` | ruins | 8 / 25 | 21 | 21 | 138 | 0 | 2 | 0 | 1 | yes | yes |  |  |  | small |
| 4 | The South Stilts `south_stilts` | tower | 8 / 25 | 15 | 15 | 20 | 0 | 0 | 2 | 0 | yes | yes |  |  |  | small |
| 4 | The Eel-Boat Graveyard `eelboat_graveyard` | wreck | 9 / 25 | 28 | 28 | 63 | 0 | 3 | 0 | 0 | yes | yes |  |  |  | small |
| 4 | The Eel Stews `eel_stews` | ruins | 10 / 25 | 21 | 21 | 128 | 0 | 0 | 2 | 0 | yes | yes |  |  |  | small |
| 4 | Saoul `saoul` | ruins | 10 / 25 | 21 | 21 | 128 | 0 | 3 | 0 | 0 | yes | yes |  |  |  | small |
| 4 | Mor'oul `mor_oul` | ruins | 10 / 25 | 21 | 21 | 128 | 0 | 3 | 0 | 0 | yes | yes |  |  |  |  |
| 4 | The Eel Hurdles `eel_hurdles` | camp | 13 / 22 | 74 | 74 | 67 | 0 | 0 | 2 | 0 | yes | yes |  |  |  |  |
| 4 | The Draining Mill `draining_mill` | mill | 13 / 26 | 31 | 31 | 42 | 0 | 4 | 2 | 0 |  | yes |  |  |  | unbuilt |
| 4 | The Bog-Iron Bloomery `bog_iron_bloomery` | camp | 14 / 24 | 74 | 74 | 77 | 0 | 2 | 2 | 0 |  | yes |  |  |  | unbuilt |
| 4 | The Traders' Post `traders_post` | camp | 14 / 22 | 68 | 68 | 64 | 0 | 0 | 0 | 0 | yes |  |  |  |  |  |
| 4 | The Cockle Beds `cockle_beds` | camp | 14 / 22 | 68 | 68 | 64 | 0 | 0 | 0 | 0 | yes |  |  |  |  |  |
| 4 | The Greyreed Decoy `greyreed_decoy` | camp | 14 / 22 | 59 | 59 | 55 | 0 | 0 | 0 | 0 | yes |  |  |  |  |  |
| 4 | The Salt Pans `salt_pans` | camp | 14 / 22 | 59 | 59 | 56 | 0 | 0 | 0 | 0 | yes |  |  |  |  |  |
| 4 | The Grey Line `grey_line` | strange | 15 / 24 | 9 | 9 | 44 | 0 | 3 | 2 | 0 |  | yes |  |  |  | unbuilt |
| 4 | The Indigo Beds `indigo_beds` | camp | 16 / 22 | 65 | 65 | 58 | 1 | 0 | 2 | 0 |  | yes |  |  |  |  |
| 4 | The Lead-Carriers' Rest `lead_carriers_rest` | camp | 16 / 14 | 62 | 62 | 55 | 0 | 2 | 2 | 0 |  | yes |  |  |  | wayside |
| 4 | The Stair of Isse `stair_of_isse` | ruins | 17 / 25 | 9 | 9 | 61 | 0 | 3 | 2 | 0 |  | yes |  |  |  |  |
| 4 | Isse's Chair `isses_chair` | shrine | 17 / 24 | 14 | 14 | 15 | 0 | 0 | 2 | 1 |  | yes |  |  |  | unbuilt |
| 4 | The Reed Wreck `reed_wreck` | wreck | 18 / 25 | 33 | 33 | 39 | 0 | 3 | 2 | 0 |  | yes |  |  |  |  |
| 4 | The Grey Gull `grey_gull` | wreck | 18 / 25 | 33 | 33 | 39 | 0 | 2 | 2 | 0 |  | yes |  |  |  |  |
| 4 | The Drowned Trader `drowned_trader` | wreck | 18 / 14 | 33 | 33 | 39 | 0 | 2 | 2 | 0 |  | yes |  |  |  | wayside |
| 4 | The Lantern Causeway `lantern_causeway` | bridge | 19 / 25 | 10 | 10 | 7 | 0 | 2 | 0 | 1 |  | yes |  |  |  |  |
| 4 | The Boardwalk Gate `boardwalk_gate` | bridge | 19 / 25 | 10 | 10 | 7 | 0 | 0 | 0 | 0 | yes |  |  |  |  |  |
| 4 | The Reed Bridge `reed_bridge` | bridge | 19 / 25 | 7 | 7 | 5 | 0 | 2 | 2 | 0 |  | yes |  |  |  |  |
| 4 | The Sallow King `sallow_king` | strange_tree | 22 / 25 | 51 | 75 | 92 | 0 | 2 | 2 | 0 |  | yes |  |  |  |  |
| 5 | Heron Watch `heron_watch` | tower | 9 / 25 | 15 | 15 | 20 | 0 | 0 | 2 | 1 | yes | yes |  |  |  | small |
| 5 | The Withy Beds `withy_beds` | camp | 14 / 22 | 68 | 68 | 63 | 0 | 2 | 2 | 0 | yes | yes |  |  |  |  |
| 5 | The Long Jetty `long_jetty` | bridge | 18 / 25 | 11 | 11 | 7 | 0 | 2 | 0 | 0 | yes | yes |  |  |  |  |
| 5 | The Drowned Arch `drowned_arch` | bridge | 60 / 25 | 5 | 5 | 2 | 0 | 0 | 2 | 0 |  | yes |  |  |  |  |
| 6 | The Drylanders' Hummock `drylanders_hummock` | grave | 18 / 22 | 25 | 25 | 7 | 0 | 2 | 2 | 0 | yes | yes |  |  |  | unbuilt |
| 6 | Hester's House `hesters_stilts` | farmstead | 21 / 28 | 39 | 39 | 37 | 0 | 0 | 2 | 1 | yes | yes |  |  |  | unbuilt |
| 8 | The Peat Hags `peat_hags` | camp | 14 / 22 | 74 | 74 | 67 | 0 | 4 | 2 | 2 | yes | yes |  |  |  |  |
| 8 | Drowned Bell Shrine `drowned_bell_shrine` | shrine | 15 / 25 | 43 | 43 | 17 | 1 | 2 | 4 | 0 | yes | yes |  | yes |  |  |
| 8 | The Eel Tally `eel_tally` | tally_post | 18 / 22 | 37 | 37 | 59 | 1 | 1 | 2 | 1 | yes | yes |  |  |  | unbuilt |
| 8 | The Leech-Wife's Stilts `leech_wifes_stilts` | hut | 19 / 24 | 41 | 41 | 37 | 0 | 4 | 2 | 1 | yes | yes |  |  |  | unbuilt |
| 8 | Greylag Fold `greylag_fold` | fold | 20 / 24 | 53 | 53 | 67 | 0 | 3 | 2 | 2 | yes | yes |  |  |  | unbuilt |
| 8 | Wisp Hollow `wisp_hollow` | hidden_valley | 22 / 25 | 17 | 17 | 7 | 0 | 4 | 2 | 0 | yes | yes |  |  |  |  |
| 9 | The Stakes at Oulnauve `oulnauve_stakes` | stockade | 22 / 28 | 118 | 118 | 188 | 1 | 4 | 2 | 0 | yes | yes |  |  |  | unbuilt |
| 11 | The Unsung Vault `unsung_vault` | delve | 31 / 30 | 81 | 81 | 92 | 2 | 2 | 2 | 0 | yes | yes | yes |  |  | unbuilt |

Weak POIs by kind (not wayside): standing_stones 3, tower 3, bridge 1, ruins 1.


## (c) Placement problems

`seat:*` are the seat audit's findings over the POI's own pieces (tools_gd/seat_audit.gd: floating over the ground, buried, sunk, standing in a road's carriageway, overlapping another piece, a lamp or light hung from nothing; headless, so multimesh rows are not looked at). `past_pad`: pieces stand beyond the flattened pad, on the skirt or raw ground. `steep_skirt`: the pad's skirt (from its level core to its reach) falls at more than 33 deg along some line: a cut or an embankment. `steep_site`: a POI not yet built stands on ground sloping more than 18 deg on average under its pad. `overlap_pad`: two pads overlap. `road_through`: a road crosses the level core of a place that is not road furniture. `in_water`: its middle is in water.

Counts: seat:overlap 5, seat:floating 4, road_through 4, seat:lamp_unhung 3, steep_skirt 3, seat:sunk 2, past_pad 2.

| POI | problem | n | detail |
|---|---|---|---|
| `drowned_arch` | past_pad | 1 | pieces reach 60 m from its middle; its pad is 25 m |
| `drowned_trader` | past_pad | 1 | pieces reach 18 m from its middle; its pad is 14 m |
| `drowned_bell_shrine` | road_through | 1 | a road passes 2 m from its middle, inside its 18 m level core |
| `eel_hurdles` | road_through | 1 | a road passes 8 m from its middle, inside its 15 m level core |
| `stair_of_isse` | road_through | 1 | a road passes 1 m from its middle, inside its 18 m level core |
| `traders_post` | road_through | 1 | a road passes 0 m from its middle, inside its 15 m level core |
| `boardwalk_gate` | seat:floating | 6 | rope Rope at (-1855, 1244): 3.82 m over the ground |
| `lantern_causeway` | seat:floating | 6 | rope Rope at (-2366, -46): 3.82 m over the ground |
| `long_jetty` | seat:floating | 6 | rope Rope at (-2760, 835): 4.30 m over the ground (over 0.3 m of water) |
| `stair_of_isse` | seat:floating | 1 | rope_coil sedgemire_rope_coil_b.glb at (-3118, -1166): 0.20 m over the ground |
| `drowned_trader` | seat:lamp_unhung | 1 | lantern_hanging sedgemire_lantern_hanging_a.glb at (-3334, 576): nothing to hang from within 0.3 m (3.4 m over the ground) |
| `grey_gull` | seat:lamp_unhung | 1 | lantern_hanging sedgemire_lantern_hanging_b.glb at (-3661, -2202): nothing to hang from within 0.3 m (3.8 m over the ground) |
| `reed_wreck` | seat:lamp_unhung | 1 | lantern_hanging sedgemire_lantern_hanging_a.glb at (-2989, 697): nothing to hang from within 0.3 m (3.2 m over the ground) |
| `drowned_trader` | seat:overlap | 1 | barrel briarwold_barrel_a.glb at (-3333, 574): 80% of it shares its box with crate (poi:wreck) |
| `lead_carriers_rest` | seat:overlap | 1 | crate briarwold_crate_b.glb at (-2947, -2078): 66% of it shares its box with crate (poi:camp) |
| `sallow_king` | seat:overlap | 18 | willow sedgemire_willow_a.glb at (-3230, 180): 75% of it shares its box with willow (poi:strange_tree) |
| `traders_post` | seat:overlap | 1 | campfire hearthvale_campfire_b.glb at (-3759, 883): 99% of it shares its box with stool (poi:camp) |
| `unsung_vault` | seat:overlap | 12 | boulder sedgemire_boulder_a.glb at (-2901, -1569): 82% of it shares its box with boulder (poi:delve) |
| `drowned_bell_shrine` | seat:sunk | 1 | bell_medium cinderlea_bell_medium_a.glb at (-2878, -339): 86% of its 3.7 m under the ground at its middle |
| `lantern_hummock` | seat:sunk | 1 | bell_medium cinderlea_bell_medium_a.glb at (-2258, -497): 86% of its 3.7 m under the ground at its middle |
| `grey_gull` | steep_skirt | 1 | its pad's skirt falls at 63 deg: a cut or an embankment |
| `old_crannog` | steep_skirt | 1 | its pad's skirt falls at 40 deg: a cut or an embankment |
| `south_stilts` | steep_skirt | 1 | its pad's skirt falls at 49 deg: a cut or an embankment |
