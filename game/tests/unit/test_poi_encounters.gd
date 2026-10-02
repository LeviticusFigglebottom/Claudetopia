extends TestCase
## What the points of interest's own sentences say stands at them, standing there.
##
## Every POI carries an `encounter` sentence and nothing stood up what any of them described: the
## world builder keeps the country's encounters off every pad, so the places a player is drawn to
## were the one kind of ground sure to be empty, and the Hart of Thorns was stood up nowhere. An
## `encounter` def says each sentence in terms `PoiEncounters` can raise with the dressing.
##
## These read the built world (`./run.sh world`); when it is missing they say so once and skip.

const GENERATED := "res://world/generated"

## Every POI and what its sentence comes to: enemy groups (by def), people (npcs/poi_people.json and
## Ryn at Gosling Pit), or why nothing stands there. Pinned so a sentence cannot quietly lose what
## it describes, and so the report reads off one table.
const WHAT_STANDS := {
	"core:poi/larkbourne_ford": "two bandits after dark",
	"core:poi/hedge_shrine_of_ansel": "person: core:npc/marigold_orchard",
	"core:poi/tumbled_watchtower": "five bandits in the stair-hall, a smuggler-Sayer on the parapet",
	"core:poi/gosling_pit": "four bandits and the Larkbourne Bruiser at the fire, and person: core:npc/wardens_ryn",
	"core:poi/singing_yew": "two hedge-wights at the gravestones after dark, turned away at the yew's ward (Wards)",
	"core:poi/whitecut_falls": "a down-wolf pack in the mouth behind the falls",
	"core:poi/bell_meadow_stones": "nobody: none",
	"core:poi/foxglove_dell": "two bristlebacks at dawn, and person: core:npc/tansy_cresswell",
	"core:poi/long_stride": "two cutpurses in the toll queue and a bravo keeping the toll, by day",
	"core:poi/shingle_shrine": "nobody: none",
	"core:poi/north_cliff_beacon": "a smuggler-Sayer and two cutpurses",
	"core:poi/gullhithe_wreck": "gutter drakes",
	"core:poi/eelweir": "leech-hounds at night",
	"core:poi/pilgrim_stair": "nobody: none above water",
	"core:poi/willow_isle": "person: core:npc/ivo_goslin",
	"core:poi/buoy_bell_field": "nobody: none",
	"core:poi/lantern_causeway": "bog-drowned at night unless the lamplighter is out, and person: core:npc/lissane_sa",
	"core:poi/drowned_bell_shrine": "wisps at midnight",
	"core:poi/sallow_king": "two sallowjaws in the pool, whose deaths cost the Reed Council's regard",
	"core:poi/reed_wreck": "leech-hounds",
	"core:poi/stair_of_isse": "bog-drowned",
	"core:poi/wisp_hollow": "wisps",
	"core:poi/tideflat_stones": "nobody: crabs on the old strand, which are not a fight",
	"core:poi/heron_watch": "person: core:npc/tuo_lissa",
	"core:poi/mossbridge": "a Warden at each end, sitting unless you carry the forest's goods past it",
	"core:poi/oiled_stone_shrine": "nobody: none",
	"core:poi/hunters_stand": "three poachers on the platform",
	"core:poi/foxfire_falls": "weavers at night on the lip above the fall",
	"core:poi/hart_bones": "a Hart-Knight",
	"core:poi/briar_breach": "ash-wights",
	"core:poi/charcoal_camp": "person: core:npc/sorrel_rooke, person: core:npc/barnaby_rooke, and a job board",
	"core:poi/fern_gully": "weavers",
	"core:poi/chain_bridge": "crag-wolves at night on the far approach, and person: core:npc/khath_ko_rudd",
	"core:poi/rib_cathedral": "a crag-wolf pack, and person: core:npc/ymma_ko_dreugh",
	"core:poi/three_sisters_falls": "scree-hags on the top ledge",
	"core:poi/clanless_camp": "a clanless hewer and two outriders",
	"core:poi/sinkhole_shrine": "nobody: none",
	"core:poi/watch_of_the_gate": "person: core:npc/ruska_ko_dreugh (the gate-warden of the story; the sentence says none)",
	"core:poi/lichen_stones": "nobody: none",
	"core:poi/hidden_tarn": "scree-hags",
	"core:poi/glass_bridge": "ash-wights",
	"core:poi/bell_of_the_pilgrims": "nobody: none",
	"core:poi/headless_watch": "a fallen Tolling knight on the stair while the watch has turned, and person: core:npc/calen_ash",
	"core:poi/the_one_poppy": "nobody: the poppy itself, to pick or water",
	"core:poi/thirteenth_colossus": "choristers after dark, and by day the Sayers' dig, person: core:npc/gisel_morneth, person: core:npc/wennick_anthar",
	"core:poi/cold_fire_camp": "six ash-wights, seated until the cup is touched",
	"core:poi/glass_falls": "a bell-bearer on the lip at the top",
	"core:poi/hushline_stair": "ash-wights",
	"core:poi/stair_head": "nobody: the Wardens' camp where a new game starts; the Warden stands there by her npc def's holds, not by a schedule",
	"core:poi/the_wellspring": "nobody: none",
	"core:poi/ash_watch": "person: core:npc/coll_ferrant",
	"core:poi/hound_watch": "person: core:npc/morwen_dagley",
	"core:poi/brow_beacon": "person: core:npc/edwy_marl",
	"core:poi/orms_long_barrow": "two hedge-wights at dusk",
	"core:poi/hurdle_fold": "three down-wolves at night, and person: core:npc/emmet_ewell",
	"core:poi/lambs_bottom": "four down-wolves",
	"core:poi/the_last_field": "two hedge-wights at night",
	"core:poi/the_grey_end": "three ash-wights at night, and person: core:npc/hale_brakewood",
	"core:poi/southgate_stone": "nobody: none",
	"core:poi/hanging_coombe": "four bandits",
	"core:poi/hushwatch_stones": "nobody: none",
	"core:poi/the_naming_stone": "nobody: none",
	"core:poi/the_flint_pits": "nobody: knappers, and a job board",
	"core:poi/the_weighing_stone": "nobody: none",
	"core:poi/wolf_holt": "three down-wolves",
	"core:poi/cress_bridge": "nobody: none",
	"core:poi/warden_barrow": "nobody: none",
	"core:poi/rod_stacks": "nobody: hazel-cutters, and a job board",
	"core:poi/sunk_plaza": "two choristers at night",
	"core:poi/bell_street": "three ash-wights",
	"core:poi/tower_of_vaelost": "a bell-bearer",
	"core:poi/anthem_hall": "two choristers at dusk",
	"core:poi/cistern_of_isse": "two ash-wights at night",
	"core:poi/kneeling_colossus": "nobody: none",
	"core:poi/bell_garden": "a bell-bearer",
	"core:poi/greywatch": "nobody: none",
	"core:poi/ashwinter_carts": "three ash-wights",
	"core:poi/bell_wood_stone": "nobody: none",
	"core:poi/ashcombe": "four ash-wights at night",
	"core:poi/hesk_pool": "nobody: none",
	"core:poi/last_milestone": "two ash-wights at dusk",
	"core:poi/builders_harbour": "nobody: none",
	"core:poi/grey_wreck": "three ash-wights",
	"core:poi/strand_beacon": "nobody: none",
	"core:poi/ninth_waystone": "nobody: none",
	"core:poi/hermits_gate": "person: core:npc/garrow_lune",
	"core:poi/the_limekilns": "nobody: lime-burners, and a job board",
	"core:poi/narrows_bridge": "nobody: none",
	"core:poi/gull_holm": "four gutter drakes",
	"core:poi/strandline_stones": "nobody: none",
	"core:poi/the_listening_post": "person: core:npc/emmet_quarle",
	"core:poi/tallymans_folly": "three cutpurses at night",
	"core:poi/rafters_camp": "nobody: rafters, and a job board",
	"core:poi/rudd_mouth_bridge": "nobody: none",
	"core:poi/fog_bell": "nobody: none",
	"core:poi/long_jetty": "two bog-drowned at midnight",
	"core:poi/peat_hags": "three leech-hounds at night, and person: core:npc/deo_oul, person: core:npc/lia_oul",
	"core:poi/drowned_arch": "nobody: none",
	"core:poi/sunken_tower": "two sallowjaws",
	"core:poi/traders_post": "nobody: none",
	"core:poi/eelboat_graveyard": "three bog-drowned at night",
	"core:poi/crookstilts": "two leech-hounds at night",
	"core:poi/indigo_beds": "nobody: dyers, and a job board",
	"core:poi/round_stones": "nobody: none",
	"core:poi/mor_oul": "three bog-drowned",
	"core:poi/oskel_ford": "nobody: none",
	"core:poi/northgate_stone": "nobody: none",
	"core:poi/old_gate_stone": "nobody: none",
	"core:poi/moot_gate_stone": "person: core:npc/wystan_tine",
	"core:poi/grey_man_tor": "a warden at dusk",
	"core:poi/hollin_tor": "a poacher at dusk",
	"core:poi/wold_force": "three thornhounds",
	"core:poi/blackgill_falls": "three weavers",
	"core:poi/barkbridge": "nobody: none",
	"core:poi/antler_chapel": "a Hart-Knight",
	"core:poi/antler_boilers": "three poachers",
	"core:poi/the_sawpit": "person: core:npc/ned_pitt, person: core:npc/aldo_pitt (sawyers, and a job board)",
	"core:poi/mossgrave": "a Warden",
	"core:poi/wardstone_line": "three thornhounds",
	"core:poi/harrow_tor": "two thornhounds at night",
	"core:poi/skarl_bridge": "person: core:npc/tosk_ko_skarl",
	"core:poi/the_sentinels": "two Wardens at dusk",
	"core:poi/old_quarry": "two weavers",
	"core:poi/countwatch": "two ash-wights at midnight",
	"core:poi/silked_camp": "three weavers",
	"core:poi/kharrow_gate": "nobody: none",
	"core:poi/ghasts_broken_bridge": "three crag-wolves",
	"core:poi/brindle_swallow": "nobody: none",
	"core:poi/the_smeltings": "nobody: smelters, and a job board",
	"core:poi/old_eld": "a stone-thrall at night",
	"core:poi/the_jawbone": "three crag-wolves",
	"core:poi/giants_spine": "two stone-thralls",
	"core:poi/kharrow_force": "nobody: none",
	"core:poi/rudd_pike_beacon": "nobody: none",
	"core:poi/snow_shelter": "nobody: none",
	"core:poi/kharrows_cairn": "nobody: none",
	"core:poi/blood_price_stones": "nobody: none",
	"core:poi/giants_stair": "a stone-thrall",
	"core:poi/the_bonefield": "two stone-thralls",
	"core:poi/ghorrow": "two stone-thralls",
	"core:poi/skarl_shieling": "person: core:npc/tamsk_ko_skarl",
	"core:poi/oskel_shieling": "nobody: none",
	"core:poi/skarl_spout": "two scree-hags, and person: core:npc/ossa_ko_skarl",
	"core:poi/ruddale_bridge": "nobody: none",
	"core:poi/red_moor": "person: core:npc/haska_ko_ghast",
	"core:poi/skerry_watch": "person: core:npc/grenna_ko_oskel",
	"core:poi/roll_stone": "nobody: none",
	"core:poi/old_sheepwash": "nobody: none",
	"core:poi/the_pinfold": "nobody: none",
	"core:poi/dewpond_fold": "person: core:npc/mab_dewhurst (shepherds, in summer)",
	"core:poi/hare_stone": "nobody: none",
	"core:poi/tallow_barrow": "three hedge-wights at night",
	"core:poi/warreners_camp": "nobody: a warrener's things, and nobody home",
	"core:poi/cliff_hearth": "person: core:npc/dilly_rookwell",
	"core:poi/hush_steps": "nobody: none",
	"core:poi/cliff_graves": "nobody: none",
	"core:poi/rook_mill": "a hedge-wight at midnight",
	"core:poi/candle_cross": "nobody: none",
	"core:poi/last_look": "nobody: none",
	"core:poi/pennywort_bridge": "nobody: none",
	"core:poi/wash_stones": "nobody: none",
	"core:poi/sedge_hearth": "nobody: none",
	"core:poi/dry_jetty": "three gutter drakes at night",
	"core:poi/eggers_camp": "person: core:npc/kester_wick (egg-collectors in spring, and their ropes the rest of the year)",
	"core:poi/charter_stone": "nobody: none",
	"core:poi/brindle_mill": "person: core:npc/ghedda_clanless (a clanless miller)",
	"core:poi/counting_tower": "person: core:npc/crispin_tolley",
	"core:poi/standing_arches": "person: core:npc/ottilie_gannet",
	"core:poi/beached_barge": "nobody: none",
	"core:poi/log_boom": "nobody: none",
	"core:poi/lime_bridge": "nobody: none",
	"core:poi/saoul": "three wisps at night",
	"core:poi/greyreed_decoy": "nobody: a decoyman and his dog",
	"core:poi/salt_pans": "nobody: salt-rakers",
	"core:poi/tide_hearth": "nobody: none",
	"core:poi/old_crannog": "two leech-hounds at night, and person: core:npc/aue_sa",
	"core:poi/knuckle_cairn": "nobody: none",
	"core:poi/drowned_road": "nobody: none",
	"core:poi/grey_gull": "two sallowjaws",
	"core:poi/boardwalk_gate": "nobody: none",
	"core:poi/reed_bridge": "two bog-drowned at night",
	"core:poi/eel_hurdles": "nobody: eel-trappers",
	"core:poi/wading_giant": "nobody: none",
	"core:poi/frost_moot": "nobody: none",
	"core:poi/oskel_rake": "two stone-thralls at night",
	"core:poi/breathing_stones": "nobody: none",
	"core:poi/rope_cairn": "nobody: none",
	"core:poi/kharrow_foot": "nobody: clan traders, and a job board",
	"core:poi/bone_ford": "person: core:npc/orsk_ko_rudd",
	"core:poi/tappers_camp": "person: core:npc/aggi_ko_rudd (resin-tappers)",
	"core:poi/rust_scar": "nobody: none",
	"core:poi/deadground": "nobody: none",
	"core:poi/ghastfoot": "nobody: none",
	"core:poi/drove_chain": "nobody: none",
	"core:poi/tinkers_camp": "person: core:npc/pell_kettleby (tinkers)",
	"core:poi/skerr_stone": "nobody: none",
	"core:poi/clan_stones": "nobody: none",
	"core:poi/briars_end": "nobody: none",
	"core:poi/the_watcher": "a scree-hag",
	"core:poi/black_keep": "nobody: none",
	"core:poi/winter_cairns": "nobody: none",
	"core:poi/verderers_tower": "person: core:npc/wat_hurle",
	"core:poi/briar_nursery": "nobody: a briar-gardener",
	"core:poi/poachers_lee": "three poachers",
	"core:poi/knights_mound": "a Hart-Knight at night",
	"core:poi/tally_hearth": "nobody: none",
	"core:poi/bark_camp": "nobody: bark-strippers",
	"core:poi/pellows_pale": "nobody: none",
	"core:poi/foxgill_arch": "nobody: none",
	"core:poi/hush_bell": "two ash-wights at night",
	"core:poi/tenth_waystone": "two ash-wights at night",
	"core:poi/row_of_mouths": "two choristers at night",
	"core:poi/hesk_morn": "nobody: none",
	"core:poi/silent_market": "three ash-wights at night",
	"core:poi/sulion": "a chorister at night",
	"core:poi/north_gate": "two ash-wights at night",
	"core:poi/greyline_stones": "nobody: none",
	"core:poi/driftwood_camp": "nobody: strand-scavengers",
	"core:poi/the_heronry": "nobody: none",
	"core:poi/fallen_firewatch": "nobody: none",
	"core:poi/net_field": "person: core:npc/netta_knotley, person: core:npc/cobb_knotley (net-menders)",
	"core:poi/smoke_coppice": "nobody: coppicers",
	"core:poi/grey_hedge": "nobody: none",
	"core:poi/lambing_fold": "nobody: shepherds at lambing",
	"core:poi/bell_pit": "two bell-bearers at night",
	"core:poi/chalk_cell": "nobody: none",
	"core:poi/cockle_beds": "nobody: cockle-rakers at low water",
	"core:poi/last_hearth": "nobody: none",
	"core:poi/turned_hut": "nobody: none",
	"core:poi/larkmouth_bridge": "nobody: none",
	"core:poi/weighhouse": "nobody: none",
	"core:poi/dale_watch": "nobody: none",
	"core:poi/drovers_bothy": "person: core:npc/ottar_ko_skarl (drovers, in autumn)",
	"core:poi/withy_beds": "two leech-hounds by day",
	"core:poi/south_stilts": "nobody: none",
	"core:poi/moot_beacon": "person: core:npc/varn_ko_skarl",
	"core:poi/chalk_pit": "nobody: chalk-diggers",
	"core:poi/eel_stews": "nobody: none",
	"core:poi/hanging_falls": "nobody: none",
	"core:poi/ness_market": "nobody: fishers selling the catch",
	"core:poi/turning_cairn": "nobody: none",
	"core:poi/sweepers_lean_to": "person: core:npc/arn_sweeting",
	"core:poi/haywards_perch": "nobody: none",
	"core:poi/novices_seats": "person: core:npc/ivet_carrow",
	"core:poi/hurdlegate_farm": "person: core:npc/nell_hurdlegate",
	"core:poi/brow_end_farm": "person: core:npc/aud_brow_end",
	"core:poi/hatchmoor_farm": "person: core:npc/tam_hatchmoor",
	"core:poi/coldharbour_farm": "person: core:npc/joss_coldharbour",
	"core:poi/pennywort_fields": "person: core:npc/bessa_pennywort",
	"core:poi/ashway_farm": "person: core:npc/rab_ashway",
	"core:poi/grey_end_farm": "person: core:npc/maud_rookwell",
	"core:poi/southgate_farm": "person: core:npc/hesta_southgate",
	"core:poi/ridgeway_farm": "person: core:npc/wil_ridgeway",
	"core:poi/fallowgate_farm": "person: core:npc/ebb_fallowgate",
	"core:poi/larkfield_farm": "person: core:npc/corran_larkfield",
	"core:poi/hazel_bottom_farm": "person: core:npc/wat_hazel",
	"core:poi/cress_mill": "person: core:npc/ossie_cress",
	"core:poi/lark_mill": "person: core:npc/jenet_lark",
	"core:poi/skarl_mill": "person: core:npc/gurd_ko_skarl",
	"core:poi/rudd_mill": "person: core:npc/brann_of_ruddow",
	"core:poi/kharrow_hole": "three crag wolves denned in the mouth among the blood-price strings",
	"core:poi/root_hollow": "two thornhounds out of the Hollow after dark",
	"core:poi/hushline_cave": "three ash-wights in on the night flood",
	"core:poi/carters_rest": "a bravo by day",
	"core:poi/charters_end": "two cutpurses at dusk",
	"core:poi/drovers_trough": "nobody: none",
	"core:poi/forgiving_stones": "a cutpurse by day",
	"core:poi/fair_day_stone": "two cutpurses at dusk",
	"core:poi/withy_camp": "nobody: none",
	"core:poi/three_rights": "two cutpurses after dark",
	"core:poi/lamp_niche": "nobody: none",
	"core:poi/hespers_boat": "nobody: none",
	"core:poi/listeners_tent": "nobody: none",
	"core:poi/salt_barn": "a smuggler-Sayer and a cutpurse after dark",
	"core:poi/serpent_watch": "nobody: none",
	"core:poi/unsayers": "nobody: none",
	"core:poi/pike_shrine": "two down-wolves after dark",
	"core:poi/reeves_chair": "nobody: none",
	"core:poi/burners_clamp": "two down-wolves after dark",
	"core:poi/market_brow": "nobody: none",
	"core:poi/bier_stone": "nobody: none",
	"core:poi/wrist_hole": "two crag-wolves after dark",
	"core:poi/patter_stone": "nobody: none",
	"core:poi/brakhs_eye": "a stone-thrall after midnight",
	"core:poi/oskel_drip": "nobody: none",
	"core:poi/singing_seat": "a scree-hag at dusk",
	"core:poi/two_clan_cairn": "two crag-wolves",
	"core:poi/horn_hole": "a scree-hag after dark",
	"core:poi/pitch_pot_shrine": "a scree-hag after dark",
	"core:poi/bone_carvers_camp": "nobody: none",
	"core:poi/swearers_rest": "two clanless outriders at dusk",
	"core:poi/beacon_shieling": "three crag-wolves after dark",
	"core:poi/oathbreakers_stone": "nobody: none",
	"core:poi/oath_takers_fire": "two crag-wolves after dark",
	"core:poi/unroofed_hold": "a clanless outrider",
	"core:poi/dreughs_lookout": "nobody: none",
	"core:poi/shaft_pebbles": "nobody: none",
	"core:poi/cart_wards_post": "nobody: none",
	"core:poi/brindles_luck": "two clanless outriders by day",
	"core:poi/gorge_porters": "a scree-hag by day",
	"core:poi/link_keepers_fire": "nobody: none",
	"core:poi/brothers_seat": "nobody: none",
	"core:poi/burned_ore_house": "two clanless outriders by day",
	"core:poi/last_cairn": "nobody: none",
	"core:poi/ice_cutters_camp": "a scree-hag by day",
	"core:poi/knotted_rope": "two crag-wolves at dusk",
	"core:poi/shift_stone": "a clanless hewer at dusk",
	"core:poi/ganns_shieling": "a stone-thrall after midnight",
	"core:poi/debtors_lean": "nobody: none",
	"core:poi/neither_stone": "nobody: none",
	"core:poi/skarl_skull": "two crag-wolves after dark",
	"core:poi/smelters_stone": "nobody: none",
	"core:poi/namers_fire": "nobody: none",
	"core:poi/newsmongers_stone": "three crag-wolves after dark",
	"core:poi/old_toll_house": "a clanless raider",
	"core:poi/slag_cairn": "a clanless hewer after dark",
	"core:poi/listening_stones": "a stone-thrall after midnight",
	"core:poi/laid_fire": "nobody: none",
	"core:poi/masons_lodge": "a weaver after dark",
	"core:poi/leave_stone": "nobody: none",
	"core:poi/torch_stone": "a weaver after dark",
	"core:poi/silk_gatherers_camp": "nobody: none",
	"core:poi/two_countries_bench": "a clanless outrider after dark",
	"core:poi/uncarried_stones": "nobody: none",
	"core:poi/planters_camp": "a warden at dusk, sitting",
	"core:poi/moss_bed": "a poacher at dusk",
	"core:poi/mourners_fire": "a Hart-Knight after dark",
	"core:poi/fourth_brother": "nobody: none",
	"core:poi/firewatchers_camp": "nobody: none",
	"core:poi/briar_root": "two thornhounds after dark",
	"core:poi/road_knot": "nobody: none",
	"core:poi/silence_stones": "two thornhounds by day",
	"core:poi/antler_smiths_house": "nobody: none",
	"core:poi/poachers_cache": "two poachers after dark",
	"core:poi/wennas_house": "a weaver",
	"core:poi/oil_carriers_stone": "nobody: none",
	"core:poi/hart_count": "nobody: none",
	"core:poi/drunk_stones": "nobody: none",
	"core:poi/bread_stone": "nobody: none",
	"core:poi/burnt_lodge": "a warden at dusk, sitting",
	"core:poi/foxfire_pickers_camp": "nobody: none",
	"core:poi/flood_stone": "nobody: none",
	"core:poi/coppice_round": "nobody: none",
	"core:poi/rafters_locker": "two thornhounds after dark",
	"core:poi/wall_watchers_fire": "two ash-wights after dark",
	"core:poi/cider_shrine": "nobody: none",
	"core:poi/sawyers_bench": "two poachers after dark",
	"core:poi/last_dry_mile": "nobody: none",
	"core:poi/lantern_wrights_camp": "two wisps after dark",
	"core:poi/lead_carriers_rest": "two leech-hounds at dusk",
	"core:poi/drowned_byre": "two bog-drowned after dark",
	"core:poi/long_table_bench": "a bristleback at dawn",
	"core:poi/ribbon_megs_fire": "nobody: none",
	"core:poi/hounds_bowl": "nobody: none",
	"core:poi/millers_stone": "nobody: none",
	"core:poi/gorse_hut": "three down-wolves after dark",
	"core:poi/boys_lookout": "two bandits after dark",
	"core:poi/dodgers_stone": "two cutpurses by day",
	"core:poi/laundry_punt": "a cutpurse by day",
	"core:poi/rafters_knots": "nobody: none",
	"core:poi/salvagers_fire": "a smuggler-Sayer at dusk",
	"core:poi/old_shore_bench": "two down-wolves after dark",
	"core:poi/weight_stone": "nobody: none",
	"core:poi/hum_cairn": "a bravo after dark",
	"core:poi/wardens_halt": "two down-wolves after dark",
	"core:poi/grey_wind_cairn": "nobody: none",
	"core:poi/garrison_shrine": "nobody: none",
	"core:poi/turned_back_fire": "two ash-wights after dark",
	"core:poi/gossip_stones": "nobody: none",
	"core:poi/lantern_hummock": "nobody: none",
	"core:poi/settled_house": "two bog-drowned after dark",
	"core:poi/pushers_stones": "nobody: none",
	"core:poi/malting_floor": "two bandits",
	"core:poi/toll_view": "nobody: none",
	"core:poi/dole_house": "a hedge-wight after dark",
	"core:poi/quiet_mile": "nobody: none",
	"core:poi/salt_road_cairn": "nobody: none",
	"core:poi/last_meal_stone": "nobody: none",
	"core:poi/bowing_stones": "nobody: none",
	"core:poi/scavengers_cold_camp": "two ash-wights after dark",
	"core:poi/robing_house": "nobody: none",
	"core:poi/harbour_milestone": "three ash-wights at dusk",
	"core:poi/first_verse": "nobody: none",
	"core:poi/toll_rope": "two cutpurses by day",
	"core:poi/false_light_house": "a smuggler-Sayer after dark",
	"core:poi/rubbing_stones": "two bristlebacks at dawn",
	"core:poi/drove_gate_toll": "two bandits and a bruiser by day",
	"core:poi/lone_barrow": "a hedge-wight after dark",
	"core:poi/hart_snares": "two thornhounds after dark",
	"core:poi/webbed_lodge": "two weavers after dark",
	"core:poi/unasked_camp": "two poachers by day, sitting",
	"core:poi/knights_challenge": "a Hart-Knight by day, sitting",
	"core:poi/raiders_perch": "two clanless outriders",
	"core:poi/wolf_stones": "three crag-wolves at dusk",
	"core:poi/hags_hut": "a scree-hag",
	"core:poi/broken_stilts": "a sallowjaw",
	"core:poi/scar_cairn": "nobody: none",
	"core:poi/last_look_cairn": "nobody: none",
	"core:poi/small_debts_post": "nobody: none",
	"core:poi/counting_fold": "nobody: none",
	"core:poi/ice_block_cairn": "nobody: none",
	"core:poi/news_owed_post": "nobody: none",
	"core:poi/unsaid_post": "nobody: none",
	"core:poi/two_knot_fold": "nobody: none",
	"core:poi/forgiveness_cairn": "nobody: none",
	"core:poi/neither_fold": "nobody: none",
	"core:poi/peat_road_cairn": "nobody: none",
	"core:poi/charter_debt_post": "nobody: none",
	"core:poi/eggers_cairn": "nobody: none",
	"core:poi/clanless_fold": "nobody: none",
	"core:poi/kept_oaths_cairn": "nobody: none",
	"core:poi/winter_herd_fold": "nobody: none",
	"core:poi/drowned_road_post": "nobody: none",
	"core:poi/peat_cutters_light": "nobody: none",
	"core:poi/old_shoreline_cairn": "nobody: none",
	"core:poi/burners_spring": "nobody: none",
	"core:poi/mill_down_fold": "nobody: none",
	"core:poi/eel_smokers_hut": "nobody: none",
	"core:poi/ansels_dew_well": "nobody: none",
	"core:poi/half_ash_cairn": "nobody: none",
	"core:poi/barrow_flock_fold": "nobody: none",
	"core:poi/ploughmans_grave": "nobody: none",
	"core:poi/naming_well": "nobody: none",
	"core:poi/first_step_cairn": "nobody: none",
	"core:poi/scavengers_grave": "nobody: none",
	"core:poi/salt_hulk": "nobody: none",
	"core:poi/tower_road_bell": "nobody: none",
	"core:poi/warden_under_ash": "nobody: none",
	"core:poi/glass_road_stone": "nobody: none",
	"core:poi/rudd_anchorite": "nobody: none",
	"core:poi/rudd_mouth_bench": "nobody: none",
	"core:poi/falls_road_finger": "nobody: none",
	"core:poi/clanless_fire_ring": "two clanless raiders",
	"core:poi/oskel_smithy": "nobody: none",
	"core:poi/dreugh_road_beacon": "two clanless hewers",
	"core:poi/skarl_brow_bench": "nobody: none",
	"core:poi/cathedral_spring": "nobody: none",
	"core:poi/oskelcrag_peat_bank": "nobody: none",
	"core:poi/ringing_oak": "nobody: none",
	"core:poi/verderers_moss_grave": "nobody: none",
	"core:poi/hazelwick_rumour_stone": "nobody: none",
	"core:poi/elderhold_charcoal_hut": "nobody: none",
	"core:poi/drowned_trader": "two bog-drowned after dark",
	"core:poi/brow_lichen_ring": "nobody: none",
	"core:poi/wynstead_ditch_camp": "two roadside bandits by day",
	# the regions' new places of 2026-09-29/30 (world life, sites): their people, and what their
	# encounters and the sites (site.garrison, site.boss, inside) stand up
	"core:poi/the_kilnway": "nobody: ash-wights along the tube, choristers on the ledges, and the Kiln-Warden in the old toll-hall at the bottom",
	"core:poi/scathe_fort": "nobody: bandits on the walls and in the yard, archers on the corner towers, their captain in the keep's undercroft",
	"core:poi/skarl_delving": "two weavers at night",
	"core:poi/horn_pale": "two thornhounds, two poachers at night",
	"core:poi/tallying_hide": "person: core:npc/corra_bracken",
	"core:poi/listening_horns": "two weavers at night, and person: core:npc/merel_quill, person: core:npc/ivo_lantry",
	"core:poi/layers_ring": "two thornhounds at night, and person: core:npc/kit_laywood, person: core:npc/ebb_laywood",
	"core:poi/greyed_ring": "three ash-wights at night",
	"core:poi/stave_hollow": "person: core:npc/aud_yewman, person: core:npc/hob_yewman",
	"core:poi/wold_beacon": "two thornhounds at dusk",
	"core:poi/colleys_hearth": "person: core:npc/orla_colley",
	"core:poi/hartswell": "two poachers at dawn",
	"core:poi/stray_thorn": "four thornhounds",
	"core:poi/tine_barrow": "a hart-knight at midnight, and person: core:npc/kenard_hartwell",
	"core:poi/pennyfold_keep": "nobody: the Fair Company's cutpurses and bravos on the walls and in the yard, crossbows on the corner towers, and their captain, Sabeline Marr, in the counting-vaults under the keep",
	"core:poi/bleaching_green": "person: core:npc/linnet_whitlow, person: core:npc/perrin_mull",
	"core:poi/the_hush_hole": "a smuggler-Sayer at night, three cutpurses at night",
	"core:poi/cadbrae_slate_cut": "three cutpurses at night, and person: core:npc/barnet_slade, person: core:npc/jessamy_slade",
	"core:poi/the_false_lantern": "a cutpurse at night",
	"core:poi/the_priced_gibbet": "two cutpurses at dusk",
	"core:poi/weedcutters_hut": "nobody: none; the cutters are out on the water by day",
	"core:poi/the_thousand_post": "nobody: none",
	"core:poi/turnback_keep": "person: core:npc/elsbet_ash",
	"core:poi/salt_landing": "person: core:npc/thalisse_tal, person: core:npc/ossul_tal",
	"core:poi/bell_counters_hut": "person: core:npc/eddery_wray",
	"core:poi/bellrope_walk": "person: core:npc/hewin_ash, person: core:npc/pim_harl",
	"core:poi/greyfleece_shieling": "person: core:npc/morwen_tarrant",
	"core:poi/ashcombe_mill": "two ash-wights",
	"core:poi/scavengers_ring": "person: core:npc/coll_brisket, person: core:npc/jory_flint",
	"core:poi/the_undertone": "ash-wights in the forecourt after dark; Hethra and the choir are inside (core:interior/the_undertone), and person: core:npc/merrin_aske",
	"core:poi/founders_delf": "ash-wights tending the pit; the Last Bellwright and the founders' dead are inside (core:interior/founders_delf), and person: core:npc/clemency_brazier",
	"core:poi/chalkwatch": "nobody: the dead garrison are the fort's (site.garrison) and Captain Haddow is in its undercroft, and person: core:npc/ysolde_penn",
	"core:poi/rooftop_shaft": "two choristers at night",
	"core:poi/unrung_graves": "a chorister at dusk",
	"core:poi/sayers_gauge": "person: core:npc/idrin_fenn",
	"core:poi/ploughed_ash": "four ash-wights",
	"core:poi/hounds_swallet": "two down wolves, two down wolves at night",
	"core:poi/drovers_pound": "three down wolves, two down wolves at night",
	"core:poi/lime_bay_kilns": "two bristlebacks at dusk, and person: core:npc/hedda_limeburner, person: core:npc/col_limeburner",
	"core:poi/brow_long_table": "person: core:npc/oswen_bellsey",
	"core:poi/bram_wheelhouse": "two down wolves at midnight, and person: core:npc/enid_drove",
	"core:poi/southcote_lynchets": "three hedge-wights at night, a hedge-wight by day",
	"core:poi/briarfoot_watch": "a hedge-wight at midnight, and person: core:npc/ferris_oakden, person: core:npc/jessamy_coppin",
	"core:poi/mother_pippin": "two bristlebacks at dusk, and person: core:npc/russet_graft",
	"core:poi/scourers_lodge": "person: core:npc/tamsin_hounder, person: core:npc/wat_hounder",
	"core:poi/listeners_shieling": "two hedge-wights at midnight, and person: core:npc/linnet_crale",
	"core:poi/wheel_graves": "two roadside bandits at night, and person: core:npc/bel_axtree",
	"core:poi/roadmens_lodge": "three roadside bandits at night, and person: core:npc/abel_larkbourne",
	"core:poi/wardens_kennels": "two down wolves at night, and person: core:npc/garrick_coupler, person: core:npc/pim_coupler",
	"core:poi/struck_gibbet": "two roadside bandits at night",
	"core:poi/hound_down_deneholes": "two bristlebacks",
	"core:poi/rookdown_bee_garth": "person: core:npc/tibby_wax",
	"core:poi/unsung_vault": "two bog-drowned at night",
	"core:poi/greylag_fold": "three leech-hounds at night, and person: core:npc/eune_mor, person: core:npc/pello_mor",
	"core:poi/oulnauve_stakes": "Aunsa Mor, the Caller, a flood-caller, two ebb-hands",
	"core:poi/eel_tally": "the Collector's Bravo by day, and person: core:npc/wystan_crail",
	"core:poi/hesters_stilts": "person: core:npc/hester_wrenn",
	"core:poi/isses_chair": "person: core:npc/maue_oul",
	"core:poi/leech_wifes_stilts": "four leech-hounds at night, and person: core:npc/illa_nauve",
	"core:poi/draining_mill": "four bog-drowned at night",
	"core:poi/drylanders_hummock": "two wisps at midnight",
	"core:poi/bog_iron_bloomery": "two sallowjaws",
	"core:poi/grey_line": "three ash-wights at night",
	"core:poi/old_ghastow": "nobody: the Unroped are the fort's garrison (site.garrison) and Gorrm is in its undercroft; a note lies at the gate",
	"core:poi/orrdun": "two scree-hags on the crag over the door; the Keener and the dead are inside (core:interior/orrdun_bone_hall)",
	"core:poi/brakhs_drink": "crag-wolves at night out of the dry galleries; the Kneeling Brakh is inside (core:interior/brakhs_drink_under)",
	"core:poi/pennants_weather_house": "crag-wolves at night down to the tarn, and person: core:npc/maudry_pennant",
	"core:poi/skerrfall_quarry": "a stone-thrall out of the new face, and person: core:npc/hodd_ko_brindle",
	"core:poi/the_leadhouse": "two clanless outriders and a raider out of the wind",
	"core:poi/frozen_drove": "crag-wolves circling the drove",
	"core:poi/sorting_ground": "four stone-thralls at their sorting",
	"core:poi/uldras_steading": "crag-wolves at the fold after dark, and person: core:npc/uldra_ko_skarl, person: core:npc/fenn_ko_skarl",
	"core:poi/wall_keepers_ring": "crag-wolves along the wall at night, and person: core:npc/durra_ko_skarl, person: core:npc/holt_fernby",
	"core:poi/reckoners_hut": "person: core:npc/graddo_ko_kharrow",
	"core:poi/broom_wifes_bield": "person: core:npc/bressa_unroped",
	"core:poi/faceless_graves": "stone-thralls out of the graves after dark",
	"core:poi/whelping_hole": "a crag-wolf pack with young in the hole (a shakehole: kind hidden_valley)",
	"core:poi/going_up_cairn": "nobody: none",
	"core:poi/old_kharrows_rest": "nobody: none",
	"core:poi/skarl_drove_well": "nobody: none",
	"core:poi/unroping_post": "nobody: none",
}

var host: Node3D
var provider: TerrainProvider = null
var pois: Array = []
static var _warned := false


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	host = Node3D.new()
	host.name = "PoiEncountersTestHost"
	_tree().root.add_child(host)
	if provider == null and FileAccess.file_exists("%s/pois.json" % GENERATED):
		provider = TerrainProvider.new()
		provider.load_data()
		pois = JSON.parse_string(FileAccess.get_file_as_string("%s/pois.json" % GENERATED))
	elif provider == null and not _warned:
		_warned = true
		print("  (world data missing: run ./run.sh world; the raising cases skip)")
	Social.quests.reset_for_new_game()
	WorldClock.set_time(12.0, 2)


func after_each() -> void:
	_tree().root.remove_child(host)
	host.free()
	GameState.clear_flag("boss_deed/core:boss/hart_of_thorns")
	Social.quests.reset_for_new_game()
	WorldClock.set_time(9.0, 2)


## Raises the cell a place stands in, as the streamer would, and returns the place's dressing.
func _dress(place_id: String) -> PoiDressing:
	var wp := WorldPois.new()
	host.add_child(wp)
	wp.index(pois, provider, WorldPois.roads_from_disk())
	var entry: Dictionary = {}
	for e in pois:
		if str((e as Dictionary).get("place_id", "")) == place_id:
			entry = e
	if entry.is_empty():
		return null
	var at := Vector3(float(entry["pos"][0]), float(entry["pos"][1]), float(entry["pos"][2]))
	var cell := wp.cell_of(at)
	var parent := Node3D.new()
	parent.name = "Cell_%d_%d" % [cell.x, cell.y]
	host.add_child(parent)
	var mine: PoiDressing = null
	for d in wp.raise_in_cell(parent, cell, false):
		if d.poi_id == place_id:
			mine = d
	return mine


func _encounters_of(d: PoiDressing) -> PoiEncounters:
	if d == null:
		return null
	for c in d.get_children():
		if c is PoiEncounters:
			return c as PoiEncounters
	return null


func _living(enc: PoiEncounters, enemy_id: String) -> Array[Enemy]:
	var out: Array[Enemy] = []
	if enc == null:
		return out
	for e in enc.everyone():
		if e.enemy_id == enemy_id:
			out.append(e)
	return out


# --- the data ------------------------------------------------------------------------------------------

func test_every_point_of_interest_is_accounted_for() -> void:
	for def in ContentDB.all("poi"):
		assert_true(WHAT_STANDS.has(str(def["id"])), "%s's sentence ('%s') is in no row of this table"
				% [def["id"], def.get("encounter", "")])
	var peopled: Dictionary = {}
	for def in ContentDB.all("npc"):
		for e in def.get("schedule", []):
			var place := str((e as Dictionary).get("place", ""))
			if Ids.type_of(place) == "poi":
				peopled[place] = true
				# and the other way: whoever a schedule puts at a point of interest is in its row
				assert_true(str(WHAT_STANDS.get(place, "")).contains("person: %s" % def["id"]),
						"%s's schedule puts them at %s and its row does not name them" % [def["id"], place])
	for poi_id in WHAT_STANDS:
		var said := str(WHAT_STANDS[poi_id])
		var has_def := not PoiEncounters.of(str(poi_id)).is_empty()
		var nobody := said.begins_with("nobody")
		var only_people := said.begins_with("person")
		if nobody or only_people:
			assert_false(has_def, "%s stands enemies up and the table says %s" % [poi_id, said])
		else:
			assert_true(has_def, "%s: '%s' and no encounter def stands it up" % [poi_id, said])
		if said.contains("person: "):
			assert_true(peopled.has(poi_id), "%s: '%s' and nobody's schedule puts them there" % [poi_id, said])


func test_every_encounter_names_a_real_place_real_foes_and_a_real_hour() -> void:
	var defs := ContentDB.all("encounter")
	assert_gt(defs.size(), 30, "the sentences want saying")
	for def in defs:
		var place := str(def.get("place", ""))
		assert_true(ContentDB.has(place), "%s stands at %s, which is nowhere" % [def["id"], place])
		assert_true(PoiDressing.dressable(place, ContentDB.get_or_empty(place)), "%s: nothing dresses %s, so nothing stands anyone up there" % [def["id"], place])
		for s in def.get("spawns", []):
			var e: Dictionary = s
			assert_true(ContentDB.has(str(e.get("enemy", ""))), "%s: no such foe %s" % [def["id"], e.get("enemy", "")])
			assert_true(PoiEncounters.WHEN.has(str(e.get("when", "always"))), "%s: '%s' is no hour" % [def["id"], e.get("when", "")])
			var keeper := str(e.get("unless_present", ""))
			if keeper != "":
				var lives := false
				for sch in ContentDB.get_or_empty(keeper).get("schedule", []):
					lives = lives or str((sch as Dictionary).get("place", "")) == place
				assert_true(lives, "%s waits on %s, who is never at %s" % [def["id"], keeper, place])


func test_every_marker_an_encounter_names_is_put_down_by_its_dressing() -> void:
	if provider == null:
		return
	var unbuilt: Array[String] = []
	for def in ContentDB.all("encounter"):
		var place := str(def.get("place", ""))
		var names: Array[String] = []
		for s in def.get("spawns", []):
			for key in ["at", "rises_when"]:
				if str((s as Dictionary).get(key, "")) != "":
					names.append(str(s[key]))
		for l in def.get("lies", []):
			if str((l as Dictionary).get("at", "")) != "":
				names.append(str(l["at"]))
		if names.is_empty():
			continue
		if not _built_pad(place):
			# a place newer than the built world (it stands on a pad PoiPreview lays at run time):
			# its dressing is asked once the world is built again, and a place the build knows and
			# does not dress still fails below
			unbuilt.append(place)
			continue
		var d := _dress(place)
		assert_true(d != null, "%s has a pad in the built world and nothing dresses it" % place)
		if d == null:
			continue
		for n in names:
			assert_true(d.find_child(n, true, false) != null, "%s's dressing puts down no '%s'" % [place, n])
	if not unbuilt.is_empty():
		Log.info("test_poi_encounters", "%d place(s) with named markers wait for the world build to be asked: %s"
				% [unbuilt.size(), ", ".join(unbuilt)])


func _built_pad(place_id: String) -> bool:
	for e in pois:
		if str((e as Dictionary).get("place_id", "")) == place_id:
			return true
	return false


# --- standing there ----------------------------------------------------------------------------------------

func test_the_hart_keeps_the_moot_until_it_is_put_down() -> void:
	if provider == null:
		return
	var d := _dress("core:place/standing_moot")
	assert_true(d != null, "the Standing Moot is dressed")
	var enc := _encounters_of(d)
	assert_true(enc != null, "and something stands in it")
	if enc == null:
		return
	enc.refresh()
	var harts := _living(enc, "core:boss/hart_of_thorns")
	assert_eq(harts.size(), 1, "the Hart of Thorns keeps the circle")
	if not harts.is_empty():
		var circle := d.find_child("the_circle", true, false) as Node3D
		var off := Vector2(harts[0].global_position.x - circle.global_position.x, harts[0].global_position.z - circle.global_position.z)
		assert_true(off.length() < 0.5, "in the middle, where the question is asked")
		assert_true(harts[0].is_boss, "as a boss")
	# once he is down he stays down, however often the Moot is streamed in again
	GameState.set_flag("boss_deed/core:boss/hart_of_thorns")
	var again := _encounters_of(_dress("core:place/standing_moot"))
	again.refresh()
	assert_empty(_living(again, "core:boss/hart_of_thorns"), "a keeper put down is not stood up again")


func test_the_fords_bandits_come_out_after_dark_and_go_by_morning() -> void:
	if provider == null:
		return
	var enc := _encounters_of(_dress("core:poi/larkbourne_ford"))
	assert_true(enc != null)
	if enc == null:
		return
	WorldClock.set_time(12.0, 2)
	enc.refresh()
	assert_empty(_living(enc, "core:enemy/roadside_bandit"), "none by day")
	WorldClock.set_time(22.0, 2)
	enc.refresh()
	assert_eq(_living(enc, "core:enemy/roadside_bandit").size(), 2, "two bandits after dark")
	WorldClock.set_time(9.0, 3)
	enc.refresh()
	await _tree().process_frame
	assert_empty(_living(enc, "core:enemy/roadside_bandit"), "and gone by morning")


func test_a_group_put_down_is_not_raised_again_on_the_hour() -> void:
	if provider == null:
		return
	var enc := _encounters_of(_dress("core:poi/hart_bones"))
	enc.refresh()
	var knights := _living(enc, "core:enemy/hart_knight")
	assert_eq(knights.size(), 1, "a Hart-Knight keeps vigil at the skull")
	if knights.is_empty():
		return
	knights[0].die(null)
	enc.refresh()
	WorldClock.set_time(13.0, 2)
	enc.refresh()
	assert_empty(_living(enc, "core:enemy/hart_knight"), "the knight stays dead until a rest brings him back")


func test_the_drowned_climb_the_poles_only_when_the_lamplighter_is_not_on_them() -> void:
	if provider == null:
		return
	var registry := NpcRegistry.ensure()
	registry.despawn_all()
	registry.states.clear()
	registry.rebuild()
	var enc := _encounters_of(_dress("core:poi/lantern_causeway"))
	assert_true(enc != null)
	if enc == null:
		return
	# a workday at ten at night: Lissane is on her round, and every pole is lit
	WorldClock.set_time(22.0, 2)
	registry.simulate_all("clear")
	assert_true(PoiEncounters.is_present("core:npc/lissane_sa", "core:poi/lantern_causeway"), "she walks the boardwalk at ten")
	enc.refresh()
	assert_empty(_living(enc, "core:enemy/bog_drowned"), "the drowned stay under the boards while she is on them")
	# gone home at eleven, and the lanterns burn down
	WorldClock.set_time(23.5, 2)
	registry.simulate_all("clear")
	enc.refresh()
	assert_eq(_living(enc, "core:enemy/bog_drowned").size(), 2, "and after she has gone home they climb")
	registry.states.clear()
	registry.rebuild()


func test_the_larkbourne_boys_keep_their_knives_away_while_ryn_is_waiting_to_be_heard() -> void:
	if provider == null:
		return
	var enc := _encounters_of(_dress("core:poi/gosling_pit"))
	assert_true(enc != null)
	if enc == null:
		return
	enc.refresh()
	assert_eq(_living(enc, "core:enemy/roadside_bandit").size(), 4, "a pack of bandits at the fire")
	assert_true(Social.quests.start("core:quest/wardens_roll_of_names"))
	Social.quests.set_stage("core:quest/wardens_roll_of_names", "find_the_name")
	enc.refresh()
	await _tree().process_frame
	assert_empty(_living(enc, "core:enemy/roadside_bandit"), "they stand aside while the Roll sends you to hear Ryn out")
	Social.quests.set_stage("core:quest/wardens_roll_of_names", "the_pen")
	enc.refresh()
	assert_eq(_living(enc, "core:enemy/roadside_bandit").size(), 4, "and they are back when that is done")


## The One Poppy's sentence is a deed: a Hollow one if picked, a Hearth one if watered. Kneeling by
## it puts the choice, and a poppy picked is not there when the heath is next built.
func test_the_one_poppy_is_watered_or_picked_and_once_picked_is_gone() -> void:
	if provider == null:
		return
	GameState.clear_flag("poppy_picked")
	GameState.clear_flag("poppy_watered")
	var d := _dress("core:poi/the_one_poppy")
	var touch := d.find_child("the_poppy", true, false) as PoiTouch
	assert_true(touch != null, "the poppy is something to kneel by")
	if touch == null:
		return
	assert_eq(touch.dialogue_id, "core:dialogue/the_one_poppy")
	assert_true(touch.find_child("Bloom", true, false) != null, "and it holds the flower")
	var bag := SocialFakes.FakeInventory.new()
	Social.bind("inventory", bag)
	var morality_before := int(Social.reaction_profile().get("morality", 0))
	touch.interact(null)
	var runner: Node = Social.dialogue
	assert_true(runner.is_running(), "kneeling puts the choice")
	var texts: Array = []
	for c in runner.current_choices:
		texts.append(str((c as Dictionary).get("text", "")))
	assert_eq(texts, ["Water it from the cup.", "Pick it.", "Leave it where it is."], "water, pick or leave: nobody here passes on the news")
	runner.choose(1)
	if runner.is_running():
		runner.stop()
	assert_true(GameState.has_flag("poppy_picked"), "picked")
	assert_eq(bag.count("core:item/ash_poppy_petal"), 4, "four petals in your hand")
	assert_true(int(Social.reaction_profile().get("morality", 0)) < morality_before, "and it was a Hollow deed")
	assert_false(touch.visible, "and it is gone from the heath at once")
	var again := _dress("core:poi/the_one_poppy")
	assert_true(again.find_child("the_poppy", true, false) == null, "and when the heath is next built, a ring round nothing")
	assert_true(again.find_child("Bloom", true, false) == null)
	GameState.clear_flag("poppy_picked")
	Social.bind("inventory", null)
	Social.refresh_providers()


func test_the_cold_fire_sits_until_somebody_takes_up_the_cup() -> void:
	if provider == null:
		return
	var d := _dress("core:poi/cold_fire_camp")
	var enc := _encounters_of(d)
	assert_true(enc != null)
	if enc == null:
		return
	enc.refresh()
	var seated := _living(enc, "core:enemy/ash_wight")
	assert_eq(seated.size(), 6, "Greyfold's six, round the fire")
	for w in seated:
		assert_false(w.perception.enabled, "seated, and not seeing you")
	var cup := d.find_child("the_cup", true, false)
	assert_true(cup is PoiTouch, "and the cup going round is there to be taken up")
	if not (cup is PoiTouch):
		return
	var actor := Node3D.new()
	actor.add_to_group("player")
	host.add_child(actor)
	(cup as PoiTouch).interact(actor)
	for w in seated:
		assert_true(w.perception.enabled, "they rise")
		assert_eq(w.perception.target, actor, "and they rise for whoever took it")
	assert_eq((cup as PoiTouch).collision_layer, 0, "the cup is not taken up twice")


# --- the sentences honoured at last -------------------------------------------------------------------------

## A body walked past a group, carrying a bag of its own; `as_player` puts it in the player group,
## so that what it does costs what the player's deeds cost.
func _walker(at: Vector3, as_player := false) -> Node3D:
	var who := Node3D.new()
	who.name = "Walker"
	if as_player:
		who.add_to_group("player")
	var bag := Inventory.new()
	bag.name = "Bag"
	who.add_child(bag)
	host.add_child(who)
	who.global_position = at
	return who


func _marker(d: PoiDressing, marker_name: String) -> Node3D:
	return d.find_child(marker_name, true, false) as Node3D if d != null else null


func test_the_clanless_camp_is_a_brute_and_two_skirmishers() -> void:
	if provider == null:
		return
	var enc := _encounters_of(_dress("core:poi/clanless_camp"))
	assert_true(enc != null)
	if enc == null:
		return
	enc.refresh()
	var hewers := _living(enc, "core:enemy/clanless_hewer")
	var outriders := _living(enc, "core:enemy/clanless_outrider")
	assert_eq(hewers.size(), 1, "a brute")
	assert_eq(outriders.size(), 2, "and two skirmishers")
	if hewers.size() == 1 and outriders.size() == 2:
		assert_eq(hewers[0].archetype, "brute")
		assert_eq(outriders[0].archetype, "skirmisher")
		assert_true(hewers[0].max_health > outriders[0].max_health, "the hewer is the one who goes in first")


func test_the_larkbourne_band_has_its_brute() -> void:
	if provider == null:
		return
	var enc := _encounters_of(_dress("core:poi/gosling_pit"))
	enc.refresh()
	var brutes := _living(enc, "core:enemy/larkbourne_bruiser")
	assert_eq(brutes.size(), 1, "the pack's brute leader stands at the fire with it")
	if not brutes.is_empty():
		assert_eq(brutes[0].archetype, "brute")


func test_the_watch_turns_only_while_its_condition_holds() -> void:
	if provider == null:
		return
	var d := _dress("core:poi/headless_watch")
	var enc := _encounters_of(d)
	assert_true(enc != null, "the Headless Watch has a group to raise")
	if enc == null:
		return
	enc.refresh()
	assert_empty(_living(enc, "core:enemy/tolling_knight"), "a friendly vigil while the watch has not turned")
	var entry: Dictionary = enc.entries[0]
	assert_eq(str(entry.get("at", "")), "the_stair")
	var said: Array = entry.get("if", [])
	assert_eq(said, [{"quest_at": ["core:quest/the_names_in_the_chapter_book", "the_walks"]}],
			"it turns while the Order's fallen stand the north walk")
	# the same group on a condition a test can hold: up while it holds, down when it does not
	var turned := entry.duplicate(true)
	turned["if"] = [{"flag": "test_the_watch_has_turned"}]
	enc.entries = [turned]
	GameState.set_flag("test_the_watch_has_turned")
	enc.refresh()
	var knights := _living(enc, "core:enemy/tolling_knight")
	assert_eq(knights.size(), 1, "a fallen knight once the watch has turned")
	var stair := _marker(d, "the_stair")
	if knights.size() == 1 and stair != null:
		assert_true(knights[0].global_position.distance_to(stair.global_position) < 0.6, "on the stair")
		# Up the stair from its own foot. A pad keeps the land's lie now (tilted up to 6%), and the
		# stair's foot 11 m out stands 0.9 m under the watch's middle on w4096e, so the middle is no
		# measure of how far up it the knight stands: the ground under the stair's lowest end is.
		var steps := d.get_node_or_null("Stair") as MeshInstance3D
		assert_true(steps != null, "the watch has its stair")
		if steps != null:
			var box := steps.global_transform * steps.mesh.get_aabb()
			var foot := INF
			for c in 8:
				var corner := box.get_endpoint(c)
				foot = minf(foot, provider.get_height(corner.x, corner.z))
			assert_true(knights[0].global_position.y > foot + 1.5,
					"up the stair, not at its foot (%.2f m over its foot at %.2f)" % [knights[0].global_position.y - foot, foot])
	GameState.clear_flag("test_the_watch_has_turned")
	enc.refresh()
	await _tree().process_frame
	assert_empty(_living(enc, "core:enemy/tolling_knight"), "and gone when it has not")


func test_the_sallow_kings_sallowjaws_rise_from_the_pool_and_cost_the_reedfolk() -> void:
	if provider == null:
		return
	var d := _dress("core:poi/sallow_king")
	var enc := _encounters_of(d)
	enc.refresh()
	var jaws := _living(enc, "core:enemy/sallowjaw")
	assert_eq(jaws.size(), 2)
	var pool := _marker(d, "the_pool")
	assert_true(pool != null, "the water inside the ring is where they lie")
	if jaws.size() != 2 or pool == null:
		return
	for j in jaws:
		assert_true(Vector2(j.global_position.x - pool.global_position.x, j.global_position.z - pool.global_position.z).length() < 2.5,
				"in the pool, not on the pad's rim")
	var council := "core:faction/reed_council"
	Social.factions.set_reputation(council, 20)
	# somebody else's kill costs the player nothing; the player's costs the council's regard
	jaws[0].die(null)
	assert_eq(Social.factions.reputation(council), 20, "a death that was not the player's is not held against them")
	var who := _walker(pool.global_position + Vector3(6.0, 0.0, 0.0), true)
	jaws[1].die(who)
	assert_eq(Social.factions.reputation(council), 12, "the Reed Council hears who killed one")
	Social.factions.set_reputation(council, 0)


func test_the_mossbridge_wardens_let_the_empty_handed_cross() -> void:
	if provider == null:
		return
	var d := _dress("core:poi/mossbridge")
	var enc := _encounters_of(d)
	enc.refresh()
	var wardens := _living(enc, "core:enemy/warden")
	assert_eq(wardens.size(), 2)
	if wardens.is_empty():
		return
	for w in wardens:
		assert_true(w.inactive, "a Warden is a dead tree to whoever carries nothing")
	var who := _walker(wardens[0].global_position + Vector3(3.0, 0.0, 0.0))
	# it sees you cross, and seeing you is not a reason
	wardens[0].call("_on_detected", who)
	assert_true(wardens[0].inactive and wardens[0].minding, "a Warden that has seen you still lets you by")
	enc.mind(who)
	assert_true(wardens[0].inactive, "empty-handed, you cross")
	(who.get_node("Bag") as Inventory).add("core:item/wolf_pelt")
	enc.mind(who)
	assert_true(wardens[0].inactive, "a pelt Fernhold pays for is not the forest's to miss")
	(who.get_node("Bag") as Inventory).add("core:item/heartwood_knot")
	enc.mind(who)
	assert_false(wardens[0].inactive or wardens[0].minding, "a knot out of a Warden's own trunk wakes it")
	assert_eq(wardens[0].brain.state, Brain.COMBAT, "and it comes for you")
	wardens[0].reset_to_spawn()
	assert_true(wardens[0].inactive and wardens[0].minding, "and after a rest it is minding its end of the arch again")


func test_the_long_stride_bravo_keeps_the_toll_and_duels_who_walks_past_it() -> void:
	if provider == null:
		return
	WorldClock.set_time(12.0, 2)
	var d := _dress("core:poi/long_stride")
	var enc := _encounters_of(d)
	enc.refresh()
	var bravos := _living(enc, "core:enemy/bravo")
	assert_eq(bravos.size(), 1, "the toll is kept by day")
	var table := _marker(d, "the_toll_table")
	var line := _marker(d, "the_toll_line")
	assert_true(table != null and line != null and d.find_child("the_toll", true, false) is PoiTouch,
			"a table, a line past it and the toll to pay at it")
	if bravos.is_empty() or line == null:
		return
	assert_true(bravos[0].inactive, "he keeps his table and asks, he does not start it")
	bravos[0].call("_on_detected", null)
	assert_true(bravos[0].inactive, "and seeing you come is not starting it")
	GameState.clear_flag(enc.toll_flag())
	var who := _walker(line.global_position + Vector3(0.0, 0.0, 30.0))
	enc.mind(who)
	assert_true(bravos[0].inactive, "waiting in the queue is not refusing")
	# the toll is paid by touching the table, as a player does
	await _tree().process_frame
	var toll := d.find_child("the_toll", true, false) as PoiTouch
	assert_true(toll.prompt.contains("5 marks"), "the table says what the toll is: %s" % toll.prompt)
	Purse.give(who, 12)
	var before := Purse.balance(who)
	toll.interact(who)
	assert_eq(Purse.balance(who), before - 5, "five marks at the table")
	assert_true(enc.toll_paid())
	toll.interact(who)
	assert_eq(Purse.balance(who), before - 5, "and once a day")
	who.global_position = line.global_position
	enc.mind(who)
	assert_true(bravos[0].inactive, "paid, you walk on past him")
	GameState.clear_flag(enc.toll_flag())
	enc.mind(who)
	assert_false(bravos[0].inactive, "past the table without paying, and he has it out with you")
	GameState.clear_flag(enc.toll_flag())


func test_the_groups_the_sentences_put_up_high_stand_up_high() -> void:
	if provider == null:
		return
	WorldClock.set_time(23.0, 2)
	for row in [["core:poi/foxfire_falls", "core:enemy/weaver", "above_the_falls"],
			["core:poi/three_sisters_falls", "core:enemy/scree_hag", "the_cliffs"],
			["core:poi/glass_falls", "core:enemy/bell_bearer", "the_top"]]:
		var d := _dress(str(row[0]))
		var enc := _encounters_of(d)
		enc.refresh()
		var up := _marker(d, str(row[2]))
		var foes := _living(enc, str(row[1]))
		assert_false(foes.is_empty(), "%s stands %s up" % [row[0], row[1]])
		assert_true(up != null and bool(up.get_meta("raised", false)), "%s's %s is a place to stand, up off the ground" % [row[0], row[2]])
		if up == null or foes.is_empty():
			continue
		# up over the fall's foot, where whoever comes to it stands: where the world steps the land
		# for the fall, the ground under the top of the rock is the step's top, and a marker on it is
		# as high as the rock without being off the ground
		var foot := d.global_position.y
		assert_true(up.global_position.y > foot + 3.5, "%s: %s is up high (%.1f m over the fall's foot)" % [row[0], row[2], up.global_position.y - foot])
		var ground := provider.get_height(up.global_position.x, up.global_position.z)
		assert_true(up.global_position.y > ground - 0.3, "%s: %s is not under the ground (%.1f m)" % [row[0], row[2], up.global_position.y - ground])
		for f in foes:
			assert_true(absf(f.global_position.y - up.global_position.y) < 0.5, "%s: %s stands on it" % [row[0], row[1]])
	# and the down-wolves in the mouth behind the water, at the foot of the face
	var falls := _dress("core:poi/whitecut_falls")
	var mouth := _marker(falls, "behind_the_falls")
	var enc2 := _encounters_of(falls)
	enc2.refresh()
	var wolves := _living(enc2, "core:enemy/down_wolf")
	assert_eq(wolves.size(), 4)
	# the mouth is the channel's foot cut back under the ledge above it: its marker is behind the
	# water, which falls from the lip in front of it
	var lip := _marker(falls, "lip")
	assert_true(mouth != null and lip != null, "a mouth behind the fall, and the lip it falls from")
	if mouth != null:
		for w in wolves:
			assert_true(Vector2(w.global_position.x - mouth.global_position.x, w.global_position.z - mouth.global_position.z).length() < 2.5,
					"the pack is in it")
	WorldClock.set_time(9.0, 2)


func test_the_tideflat_has_its_crabs_and_nothing_to_fight() -> void:
	if provider == null:
		return
	var d := _dress("core:poi/tideflat_stones")
	assert_true(_encounters_of(d) == null, "none")
	var shore := d.find_child("Crabs", true, false) as Livestock
	assert_true(shore != null, "crabs")
	if shore == null:
		return
	assert_true(shore.beasts.size() >= 9, "a few on the strand at each stone (%d)" % shore.beasts.size())
	for b in shore.beasts:
		assert_eq(str((b as Dictionary)["kind"]), "crab")


func test_the_singing_yew_is_ground_the_dead_will_not_cross() -> void:
	if provider == null:
		return
	Wards.clear()
	var d := _dress("core:poi/singing_yew")
	assert_eq(Wards.count(), 1, "the yew puts its ward down with it")
	var yew := d.world_position
	assert_false(Wards.keeping(["humanoid", "revenant", "undead"], yew + Vector3(3.0, 0.0, 0.0)).is_empty(), "a hedge-wight will not pass it")
	# after dark two of the barrow's dead come up past the gravestones, and stop outside it
	WorldClock.set_time(23.0, 2)
	var enc := _encounters_of(d)
	assert_true(enc != null, "the yew has its dead to turn away")
	if enc != null:
		enc.refresh()
		var wights := _living(enc, "core:enemy/hedge_wight")
		assert_eq(wights.size(), 2, "two hedge-wights at the gravestones after dark")
		for w in wights:
			assert_true(Wards.keeping(w.def.get("tags", []), w.global_position).is_empty(), "standing outside the yew's ground")
			assert_true(Vector2(w.global_position.x - yew.x, w.global_position.z - yew.z).length() < 26.0,
					"and near enough, on their leash, to come for somebody standing under it")
	WorldClock.set_time(9.0, 2)
	assert_true(Wards.keeping(["bandit", "humanoid", "person"], yew + Vector3(3.0, 0.0, 0.0)).is_empty(), "a bandit does not care")
	assert_true(Wards.keeping(["undead"], yew + Vector3(20.0, 0.0, 0.0)).is_empty(), "and the ward ends where the yew's ground does")
	d.get_parent().free()
	assert_eq(Wards.count(), 0, "and it goes with the dressing")
