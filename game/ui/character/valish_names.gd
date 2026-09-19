class_name ValishNames
extends RefCounted
## Valish names, by the rules in WORLD_BIBLE §5.1, kept in step with tools/namegen.py:
## two syllables, softened endings, and a surname from a trade or a place. Used to offer
## the Foundling something to be called before they choose for themselves.

const FIRST := ["Wren", "Osric", "Maud", "Tobin", "Hesk", "Ansel", "Bram", "Elsie", "Corin",
	"Ada", "Tam", "Nell", "Pell", "Ivo", "Rosalind", "Gil", "Hob", "Marigold", "Edric",
	"Tansy", "Jory", "Bea", "Aldous", "Lettie", "Wat", "Cille", "Fenwick", "Dorrie",
	"Barnaby", "Sorrel"]
const STEMS := ["Ros", "Hal", "Wil", "Mer", "Tor", "Bel", "Cal", "Lin", "Ged", "Mar", "Hesp", "Ann"]
const FEM := ["a", "ie", "el", "ow"]
const MASC := ["am", "ick", "ard", "en"]
const SURNAMES := ["Miller", "Tallow", "Brambling", "Ashdown", "Pennywort", "Cresswell",
	"Thatcher", "Cooper", "Fletcher", "Ropewalk", "Hollins", "Larkin", "Merriweather",
	"Goslin", "Fennick", "Mullard", "Bellhanger", "Orchard", "Cidery", "Rooke"]
const ROOTS := ["merrow", "hollin", "tam", "wyn", "cad", "brae", "thorn", "ash", "penny",
	"gos", "lark", "fenn", "hare", "mull", "cress", "bram", "elder", "fallow", "rook",
	"bell", "wick", "hazel", "orm", "sedge"]
const PLACE_SUFFIX := ["by", "wick", "combe", "mere", "stead", "ford", "well", "bourne",
	"down", "hithe", "fold", "hollow", "cross", "barrow"]


static func given(rng: RandomNumberGenerator) -> String:
	if rng.randf() < 0.3:
		var endings: Array = FEM + MASC
		return STEMS[rng.randi() % STEMS.size()] + str(endings[rng.randi() % endings.size()])
	return FIRST[rng.randi() % FIRST.size()]


static func surname(rng: RandomNumberGenerator) -> String:
	if rng.randf() < 0.35:
		return "of " + place(rng)
	return SURNAMES[rng.randi() % SURNAMES.size()]


static func place(rng: RandomNumberGenerator) -> String:
	var root: String = ROOTS[rng.randi() % ROOTS.size()]
	var suffix: String = PLACE_SUFFIX[rng.randi() % PLACE_SUFFIX.size()]
	if root.ends_with(suffix.substr(0, 1)):
		suffix = suffix.substr(1)
	return (root + suffix).capitalize()


static func full(rng: RandomNumberGenerator) -> String:
	return "%s %s" % [given(rng), surname(rng)]


## A handful of suggestions with no repeats, for the Naming's "or be called" row.
static func suggestions(count: int, seed_value: int = 0) -> PackedStringArray:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value if seed_value != 0 else randi()
	var out := PackedStringArray()
	var guard := 0
	while out.size() < count and guard < count * 20:
		guard += 1
		var name := full(rng)
		if not out.has(name):
			out.append(name)
	return out
