class_name PropLibrary
extends RefCounted
## Finds the right generated prop for a wanted kind, in the right region's materials.
##
## The forge names its output `<region>_<kind>_<variant>` (hearthvale_barrel_a). Interiors
## ask for a plain kind (`barrel`) because a recipe should not care which region's timber
## the table is made of. This indexes what the forge actually built and answers with the
## best match: the asked-for kind in the asked-for region, then that kind anywhere, then a
## documented stand-in, then nothing (and the caller draws a labelled placeholder).
##
## A prop that does not exist yet is not an error. The forge is still filling in, and a
## room with three real barrels and one placeholder is more useful than a room of boxes.

const ROOT := "res://assets/models/props"
const REGIONS := ["hearthvale", "brightwater", "sedgemire", "briarwold", "skerrow", "cinderlea"]

## An interior knows its culture; the forge names its output by region. Callers were handing
## `resolve()` a culture ("reedfolk") where it wanted a region, which is not an error the
## function can see: it falls through to "any region at all" and answers with a plausible
## barrel from somewhere else entirely. Translating here means neither caller has to know.
## `test_prop_library.gd` asserts this is the exact inverse of `Settlement.CULTURE_BY_REGION`.
const REGION_BY_CULTURE := {
	"vale": "hearthvale", "lakefolk": "brightwater", "reedfolk": "sedgemire",
	"woodfolk": "briarwold", "clans": "skerrow", "pilgrims": "cinderlea",
}

## Things the forge does not build under that exact name, and what to use instead. The
## substitute has to make sense in the room, not merely fill the hole: a tally stick is a
## scroll, but a kneading table is a table, not a workbench from another trade.
const STAND_IN := {
	"table": "table_trestle", "long_table": "table_trestle", "kneading_table": "table_trestle",
	"prep_table": "table_trestle", "mortar_bench": "table_trestle", "tap_bench": "table_trestle",
	"writing_desk": "table_trestle", "roll_desk": "table_trestle", "ledger_desk": "table_trestle",
	# A Name-table is a heavy bench a Toll-Knight writes into iron at; the forge has no mesh
	# for one yet, and a trestle is nearer than anything else it has built.
	"name_table": "table_trestle",
	"counter": "table_trestle", "bar": "table_trestle", "sideboard": "cupboard",
	"deed_chest": "chest", "strongbox": "chest", "grain_bin": "chest",
	"bread_shelf": "shelf", "bottle_shelf": "shelf", "ingredient_shelf": "shelf",
	"tool_rack": "shelf", "weapon_rack": "shelf", "net_rack": "shelf", "peel_rack": "shelf",
	"drying_rack": "shelf", "pot_rack": "shelf", "barrel_rack": "shelf", "board": "shelf",
	"map_board": "shelf", "cooling_trays": "shelf",
	"hearth": "forge_hearth", "cook_hearth": "forge_hearth", "forge": "forge_hearth",
	"bread_oven": "forge_hearth", "copper": "cooking_pot", "mash_tun": "barrel",
	"quench_trough": "barrel", "hop_sacks": "sack", "flour_sacks": "sack",
	"seed_sacks": "sack", "iron_stock": "crate", "root_crate": "crate", "coal_heap": "sack",
	"hay_pile": "hay_bale", "stall": "fence_post_rail", "settle": "bench",
	"washstand": "table_trestle", "loom": "table_trestle", "spinning_wheel": "stool",
	"cradle": "basket", "mending_basket": "basket", "kindling_basket": "basket",
	"crumb_bowl": "plate", "dog_bowl": "plate", "bowl": "plate", "plate_stack": "plate",
	# Bread has its own mesh now. A wrapped loaf, the heel of one and a ball of proved
	# dough are all loaf-shaped and were all standing in as a 34 mm plate -- a quarter of
	# the height each of them is written down as. An empty loaf tin is not bread and keeps
	# the plate.
	"loaf_tin": "plate", "wrapped_loaf": "loaf", "bread_heel": "loaf", "cheese_end": "plate",
	"onion": "plate", "dough_ball": "loaf", "pan": "cooking_pot", "pot": "cooking_pot",
	"book_single": "book", "ledger": "book", "roll_book": "book", "paper_stack": "scroll",
	"tally_stick": "scroll", "tally_sticks": "scroll", "quill": "scroll", "seal": "scroll",
	"candle_stub": "candle", "lantern": "lantern_standing", "banked_embers": "campfire",
	"hand_bell": "bell_small", "small_bell": "bell_small", "medium_bell": "bell_medium",
	"mine_cart": "cart", "wheelbarrow": "cart", "bow_stand": "shelf",
	"blanket_heap": "bedroll", "bedroll": "bedroll", "boots": "sack", "small_boots": "sack",
	"scales": "plate", "mortar": "cooking_pot", "pestle": "candle", "phial": "jug",
	"inkpot": "jug", "ewer": "jug", "basin": "plate", "funnel": "jug", "tar_pot": "cooking_pot",
	"oar_rack": "shelf", "drying_line": "rope_coil", "yoke": "rope_coil", "string_ball": "rope_coil",
	"herb_bundle": "rope_coil", "oil_rag": "cloth", "rag": "cloth",
	# The smith's bench. `hammer` and `whetstone` are the forge's own meshes now and need no
	# stand-in at all; a mallet is a hammer and not a pair of tongs. A chisel, a punch and a
	# file are all drawn-down bars of about a tongs' length and read well enough as one; a
	# kitchen knife does not, and a carved wooden-handled spoon on a prep table is nearer to
	# it than half a metre of smith's tongs ever was.
	"chisel": "tongs", "punch": "tongs", "file": "tongs", "knife": "spoon",
	"bung_mallet": "hammer", "ladle": "spoon", "flour_scoop": "spoon",
	"scythe": "pitchfork", "bellows": "sack", "dice_cup": "mug", "cold_tea": "mug",
	"coin_few": "plate", "wooden_toy": "book", "chewed_stick": "rope_coil",
	"half_made_thing": "crate", "work_in_progress": "crate", "jar": "jug",
}

var _index: Dictionary = {}       # kind -> {region -> Array[String] of scene paths}
var _kinds: Dictionary = {}       # kind -> true
var _missing: Dictionary = {}     # kind -> true (asked for, nothing to give)
var _scanned := false


func scan() -> void:
	if _scanned:
		return
	_scanned = true
	if not DirAccess.dir_exists_absolute(ROOT):
		return
	for folder in DirAccess.get_directories_at(ROOT):
		var path := "%s/%s/%s.glb" % [ROOT, folder, folder]
		if not ResourceLoader.exists(path):
			continue
		var region := ""
		var kind := folder
		for r in REGIONS:
			if folder.begins_with(r + "_"):
				region = r
				kind = folder.substr(r.length() + 1)
				break
		# Trailing single-letter variant: hearthvale_barrel_a -> barrel
		var parts := kind.split("_")
		if parts.size() > 1 and parts[parts.size() - 1].length() == 1:
			kind = "_".join(parts.slice(0, parts.size() - 1))
		if not _index.has(kind):
			_index[kind] = {}
		if not _index[kind].has(region):
			_index[kind][region] = []
		(_index[kind][region] as Array).append(path)
		_kinds[kind] = true


## Best prop for this kind in this region, or "" if the forge has not built one.
## `variant` picks deterministically among the variants so a room is not all one barrel.
func resolve(kind: String, region_id := "", variant := 0) -> String:
	scan()
	var region := Ids.name_of(region_id) if region_id.contains("/") else region_id
	region = str(REGION_BY_CULTURE.get(region, region))
	for candidate in [kind, str(STAND_IN.get(kind, ""))]:
		if candidate.is_empty() or not _index.has(candidate):
			continue
		var by_region: Dictionary = _index[candidate]
		for key in [region, ""]:
			if by_region.has(key) and (by_region[key] as Array).size() > 0:
				var list: Array = by_region[key]
				return str(list[variant % list.size()])
		# Any region at all: better a Skerrow barrel than a pink box.
		for key in by_region:
			var any: Array = by_region[key]
			if any.size() > 0:
				return str(any[variant % any.size()])
	_missing[kind] = true
	return ""


func kinds_built() -> int:
	scan()
	return _kinds.size()


## Kinds that were asked for and could not be answered: the forge's to-do list.
func missing_kinds() -> Array:
	var out := _missing.keys()
	out.sort()
	return out
