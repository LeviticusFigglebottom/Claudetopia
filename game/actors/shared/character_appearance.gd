class_name CharacterAppearance
extends RefCounted
## A character's whole look as plain data (DESIGN.md §5.1, CONTRACTS.md §7 `appearance`).
##
## `HumanoidModel` composes a body from this: which modular parts to show, what colours to
## tint them, which body variant to use for the proportions, and the morality visuals from
## DESIGN.md §5.11. It is a plain Dictionary on the wire so it saves and loads with
## everything else and NPC defs can carry one inline.

## Part slots. Each maps to one modular GLB under game/assets/models/characters/<slot>/.
const SLOTS: Array[String] = [
	"head", "hair", "beard", "torso", "legs", "feet", "hands", "belt", "back", "headgear", "attachment",
]
## Slots whose meshes replace the default body parts rather than layering over them.
const BODY_SLOTS: Array[String] = ["head"]

const CULTURES: Array[String] = ["vale", "lakefolk", "reedfolk", "clans", "woodfolk", "ash_pilgrims"]
const SKIN_TONES: Array[String] = [
	"porcelain", "fair", "wheat", "olive", "amber", "umber", "deep", "ebony",
]
const HAIR_COLOURS: Array[String] = [
	"black", "soot", "dark_brown", "brown", "chestnut", "auburn", "ginger", "sand",
	"flax", "ash_blond", "grey", "white",
]
const EYE_COLOURS: Array[String] = [
	"brown", "dark_brown", "hazel", "amber", "green", "grey_green", "blue", "pale_blue", "grey",
]
const HAIR_STYLES: Array[String] = ["short", "cropped", "long", "braid", "bun", "hood_friendly", "tousled"]
const BEARD_STYLES: Array[String] = ["stubble", "short_beard", "long_beard", "moustache"]
## The head presets the forge has built (game/assets/models/characters/heads/). "default" is
## the rig's own head; the rest replace it.
const HEADS: Array[String] = ["default", "round", "soft", "angular", "narrow", "broad", "hawk", "heavy_brow"]

## The colours behind the names, exactly as the forge paints them (tools/forge/lib/paint.py), so
## a swatch on the Naming and a tint on the model are the same colour. Every rig and head is
## baked at BAKED_SKIN with BAKED_EYE irises; an in-engine skin or eye is a tint relative to that.
## Below wheat (the bake, whose value stays as baked) the tones used to swing towards orange --
## amber was 57 % saturated at hue 28 -- and in the warm key light of the Naming a tanned hand
## read as a carrot. Skin darkens through redder, less saturated browns (hue 18-24, 42-55 %).
const SKIN_COLOURS := {
	"porcelain": "f0d2bd", "fair": "e9c3a4", "wheat": "dcae87", "olive": "c0936f",
	"amber": "a97855", "umber": "875a40", "deep": "5e3c2b", "ebony": "43291e",
}
const HAIR_COLOUR_VALUES := {
	"black": "1d1917", "soot": "2a2521", "dark_brown": "3b2a1e", "brown": "5a3b25",
	"chestnut": "6d3f22", "auburn": "8a3f22", "ginger": "a8501f", "sand": "a98a58",
	"flax": "c7ab74", "ash_blond": "cdbf9a", "grey": "9a958e", "white": "d9d5cd",
}
const EYE_COLOUR_VALUES := {
	"brown": "5a3a1e", "dark_brown": "3a2412", "hazel": "8a6a2a", "amber": "a5762a",
	"green": "4a7a4a", "grey_green": "6e8472", "blue": "3f6d94", "pale_blue": "7fa3bd",
	"grey": "78807f",
}
const BAKED_SKIN := "wheat"
const BAKED_EYE := "brown"
## Hair shells are baked at "brown", lightened by the forge's `hair_paint`; this is the mean of
## that bake, so a hair colour is a ratio against it rather than a darkening of it.
const BAKED_HAIR := "664730"

## What each people wears, by cloth role (tools/forge/characters.json `culture_palettes`).
const CULTURE_PALETTES := {
	"vale": {"primary": "a8763f", "secondary": "7d8a4a", "leather": "6b4a2c", "metal": "8a8f94", "trim": "c9a24a", "accent": "b23a2e"},
	"lakefolk": {"primary": "efe9dc", "secondary": "5d6470", "leather": "4a4239", "metal": "b08a3e", "trim": "3f7fb5", "accent": "b08a3e"},
	"reedfolk": {"primary": "3b3a6e", "secondary": "2f7f78", "leather": "54452f", "metal": "7d7a70", "trim": "c9b26a", "accent": "e8a93f"},
	"clans": {"primary": "c8bda6", "secondary": "6e5a44", "leather": "59432c", "metal": "6f7378", "trim": "e8e4d8", "accent": "8a4a2e"},
	"woodfolk": {"primary": "4a4030", "secondary": "5c6b3c", "leather": "3f3325", "metal": "5f6259", "trim": "2b211c", "accent": "8ab34a"},
	"ash_pilgrims": {"primary": "8b8a86", "secondary": "5a5652", "leather": "4a4744", "metal": "77736d", "trim": "a08a4a", "accent": "d8cfbf"},
}

var seed: int = 0
var culture: String = "vale"

# -- proportions (CONTRACTS §2: the forge scales bone lengths from these) ----------------
var height: float = 1.78
var bulk: float = 1.0
var shoulder_width: float = 1.0
var hip_width: float = 1.0
var limb_length: float = 1.0
var neck_length: float = 1.0
var head_size: float = 1.0
var build: float = 0.5          ## 0 slight .. 1 heavy
var age: float = 0.3            ## 0 young .. 1 old
var feminine: float = 0.0

# -- colouring ---------------------------------------------------------------------------
var skin: String = "wheat"
var hair_colour: String = "dark_brown"
var eye_colour: String = "brown"
var palette: Dictionary = {}    ## overrides for cloth colours: {"primary": Color, ...}

# -- parts ---------------------------------------------------------------------------------
## slot -> part name, e.g. {"hair": "braid", "torso": "tunic"}. An empty or missing slot
## shows nothing (except "head", which falls back to the rig's default head).
var parts: Dictionary = {}

# -- morality visuals (DESIGN.md §5.11) -----------------------------------------------------
var hearth: float = 0.0         ## 0..1 warm skin, golden eye glint, halo
var hollow: float = 0.0         ## 0..1 pallor, dark veins, red eyes, horns
var veins: float = 0.0
var freckles: float = 0.15
var stubble: float = 0.0


func _init(from: Dictionary = {}) -> void:
	if not from.is_empty():
		from_dict(from)


func from_dict(d: Dictionary) -> void:
	seed = int(d.get("seed", seed))
	culture = culture_id(str(d.get("culture", culture)))
	for key in ["height", "bulk", "shoulder_width", "hip_width", "limb_length", "neck_length",
			"head_size", "build", "age", "feminine", "hearth", "hollow", "veins", "freckles", "stubble"]:
		if d.has(key):
			set(key, float(d[key]))
	# Colours are names, and a record may not know that: the Naming once wrote indices into its
	# own swatch rows, and a save from then (or the journey's shorthand) carries `"skin": 3`,
	# which taken as a string made the skin "3.0" — no tone, and a tint computed from nothing.
	# An index means what it used to mean; anything else unrecognised leaves the default.
	set("skin", _tone(d.get("skin", null), SKIN_TONES, skin))
	set("hair_colour", _tone(d.get("hair_colour", d.get("hair", null)), HAIR_COLOURS, hair_colour))
	set("eye_colour", _tone(d.get("eye_colour", d.get("eyes", null)), EYE_COLOURS, eye_colour))
	if d.has("parts") and typeof(d["parts"]) == TYPE_DICTIONARY:
		parts = (d["parts"] as Dictionary).duplicate(true)
	if d.has("palette") and typeof(d["palette"]) == TYPE_DICTIONARY:
		palette = {}
		for k in (d["palette"] as Dictionary):
			palette[str(k)] = _to_color(d["palette"][k])


func to_dict() -> Dictionary:
	var pal := {}
	for k in palette:
		pal[k] = (palette[k] as Color).to_html(false)
	return {
		"seed": seed, "culture": culture,
		"height": height, "bulk": bulk, "shoulder_width": shoulder_width, "hip_width": hip_width,
		"limb_length": limb_length, "neck_length": neck_length, "head_size": head_size,
		"build": build, "age": age, "feminine": feminine,
		"skin": skin, "hair_colour": hair_colour, "eye_colour": eye_colour,
		"parts": parts.duplicate(true), "palette": pal,
		"hearth": hearth, "hollow": hollow, "veins": veins, "freckles": freckles, "stubble": stubble,
	}


func duplicate_appearance() -> CharacterAppearance:
	return CharacterAppearance.new(to_dict())


## One colour name out of whatever a record carries: a name from `table`, an index into it, or
## `fallback` when it is neither.
static func _tone(v: Variant, table: Array[String], fallback: String) -> String:
	match typeof(v):
		TYPE_STRING, TYPE_STRING_NAME:
			var name := str(v)
			return name if name in table else fallback
		TYPE_INT, TYPE_FLOAT:
			return table[clampi(int(v), 0, table.size() - 1)]
	return fallback


static func _to_color(v: Variant) -> Color:
	if typeof(v) == TYPE_COLOR:
		return v
	if typeof(v) == TYPE_STRING:
		return Color(str(v))
	if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 3:
		var a: Array = v
		return Color(float(a[0]), float(a[1]), float(a[2]))
	return Color.WHITE


func part(slot: String) -> String:
	return str(parts.get(slot, ""))


# -- colours ---------------------------------------------------------------------------------

static func skin_colour(name: String) -> Color:
	return Color(str(SKIN_COLOURS.get(name, SKIN_COLOURS[BAKED_SKIN])))


static func hair_colour_value(name: String) -> Color:
	return Color(str(HAIR_COLOUR_VALUES.get(name, HAIR_COLOUR_VALUES["dark_brown"])))


static func eye_colour_value(name: String) -> Color:
	return Color(str(EYE_COLOUR_VALUES.get(name, EYE_COLOUR_VALUES[BAKED_EYE])))


## What multiplies `baked` into `want`: the rig's textures carry one skin, so another is a
## per-channel ratio against it. Lighter than the bake goes above 1, which the material allows.
static func _relative_tint(want: Color, baked: Color) -> Color:
	return Color(want.r / maxf(baked.r, 0.01), want.g / maxf(baked.g, 0.01), want.b / maxf(baked.b, 0.01), 1.0)


## The tint that turns the baked skin into this one (`palette.skin_tint` overrides it).
func skin_tint() -> Color:
	if palette.has("skin_tint"):
		return palette["skin_tint"]
	return _relative_tint(skin_colour(skin), skin_colour(BAKED_SKIN))


## The tint that turns the baked iris into this eye colour.
func iris_tint() -> Color:
	return _relative_tint(eye_colour_value(eye_colour), eye_colour_value(BAKED_EYE))


## The tint that turns the baked hair into this colour (`palette.hair` overrides it).
func hair_tint() -> Color:
	if palette.has("hair"):
		return palette["hair"]
	return _relative_tint(hair_colour_value(hair_colour), Color(BAKED_HAIR))


## Dresses this character the way its people dress (WORLD_BIBLE §3): culture, the outfit slots
## and the cloth colours, deterministically from `rng_seed`. Head, hair and beard are left
## alone: they are the person's own, not the people's. The Naming and the player both dress
## through here, so the body in the world is the one the preview showed.
##
## The player is dressed in the people's whole outfit -- the piece that makes the silhouette
## (the Clans' plaid, the Lakefolk's cape, the Woodfolk's torn cloak) always, where a villager
## only sometimes has it -- and never with the hood up: a hood swaps the hair the Naming just
## chose for the close style and covers it, so choosing Long for an Ashwalker changed nothing
## anybody could see.
func dress_for_culture(in_culture: String, rng_seed: int, for_player: bool = false) -> void:
	culture = culture_id(in_culture)
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var outfit := _culture_outfit(rng, culture, feminine > 0.5, for_player)
	if for_player:
		var down: String = str(HOOD_DOWN.get(str(outfit.get("back", "")), outfit.get("back", "")))
		# a part the forge has not built yet is worn as the plain cloak rather than as nothing
		if not down.is_empty() and not ResourceLoader.exists("res://assets/models/characters/clothing/%s/%s.glb" % [down, down]):
			down = "cloak"
		outfit["back"] = down
	for slot in ["torso", "legs", "feet", "belt", "back", "hands"]:
		set_part(slot, str(outfit.get(slot, "")))
	palette = culture_palette(culture)


## A back piece with its hood up -> the same piece worn with it down.
const HOOD_DOWN := {"hooded_cloak": "cloak", "ragged_cloak": "torn_cloak"}


## The people a Calling was raised among: its home region's culture, in the record's spelling.
static func culture_of_calling(calling_id: String) -> String:
	var def := ContentDB.get_or_empty(calling_id)
	var region := ContentDB.get_or_empty(str(def.get("home_region", "")))
	return culture_id(str(region.get("culture", "vale")))


## The culture's cloth colours, for a character whose palette says nothing of its own.
static func culture_palette(in_culture: String) -> Dictionary:
	var raw: Dictionary = CULTURE_PALETTES.get(culture_id(in_culture), CULTURE_PALETTES["vale"])
	var out := {}
	for k in raw:
		out[k] = Color(str(raw[k]))
	return out


## The world names its peoples one way (`WorldProbe.culture_key`: "pilgrims") and this record
## another ("ash_pilgrims"); every Ash-Pilgrim rolled through the world's key fell through to
## the Vale outfit. One place turns any spelling into the record's.
static func culture_id(key: String) -> String:
	var k := key.strip_edges().to_lower()
	if k in CULTURES:
		return k
	if k.contains("pilgrim") or k.contains("ash"):
		return "ash_pilgrims"
	if k.contains("clan") or k.contains("skerrow"):
		return "clans"
	if k.contains("lake"):
		return "lakefolk"
	if k.contains("reed"):
		return "reedfolk"
	if k.contains("wood"):
		return "woodfolk"
	return "vale"


func set_part(slot: String, name: String) -> void:
	if name.is_empty():
		parts.erase(slot)
	else:
		parts[slot] = name


## The proportions the forge understands, as a Dictionary (mirrors rig.Proportions).
func proportions() -> Dictionary:
	return {
		"height": height, "bulk": bulk, "shoulder_width": shoulder_width, "hip_width": hip_width,
		"limb_length": limb_length, "neck_length": neck_length, "head_size": head_size,
		"build": build, "age": age, "feminine": feminine,
	}


## Which exported body-scale variant fits these proportions best. Runtime bone scaling would
## break clips that are authored on the default proportions (CONTRACTS §2), so the forge
## exports a handful of variants and we pick the nearest.
func body_variant() -> String:
	if height <= 1.45:
		return "child"
	if build >= 0.68:
		return "heavy"
	if build <= 0.30:
		return "slight"
	return "default"


## A deterministic random appearance for NPC variety.
static func random(rng_seed: int, in_culture: String = "") -> CharacterAppearance:
	var a := CharacterAppearance.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	a.seed = rng_seed
	a.culture = culture_id(in_culture) if in_culture != "" else CULTURES[rng.randi() % CULTURES.size()]
	a.feminine = 1.0 if rng.randf() < 0.5 else 0.0
	a.height = 1.62 + rng.randf() * 0.24 - a.feminine * 0.055
	a.bulk = 0.90 + rng.randf() * 0.24
	a.shoulder_width = 0.88 + rng.randf() * 0.26
	a.hip_width = 0.88 + rng.randf() * 0.26
	a.limb_length = 0.94 + rng.randf() * 0.13
	a.neck_length = 0.9 + rng.randf() * 0.24
	a.head_size = 0.94 + rng.randf() * 0.13
	a.build = clampf(rng.randfn(0.45, 0.20), 0.0, 1.0)
	a.age = clampf(rng.randfn(0.38, 0.22), 0.0, 1.0)
	a.freckles = 0.0 if rng.randf() < 0.6 else rng.randf() * 0.5
	a.skin = _weighted_skin(rng, a.culture)
	a.hair_colour = _weighted_hair(rng, a.culture, a.age)
	a.eye_colour = EYE_COLOURS[rng.randi() % EYE_COLOURS.size()]
	a.parts = _culture_outfit(rng, a.culture, a.feminine > 0.5)
	# the culture's cloth colours: without them every people's clothes were the bake's one hue
	a.palette = culture_palette(a.culture)
	if a.feminine < 0.5 and rng.randf() < 0.45:
		a.parts["beard"] = BEARD_STYLES[rng.randi() % BEARD_STYLES.size()]
	elif a.feminine < 0.5 and rng.randf() < 0.4:
		a.stubble = 0.3 + rng.randf() * 0.5
	return a


static func _weighted_skin(rng: RandomNumberGenerator, culture: String) -> String:
	## Wickmere has one human people (WORLD_BIBLE §3); regions shade the mix, they do not fix it.
	var bias := {
		"vale": 2, "lakefolk": 2, "reedfolk": 3, "clans": 1, "woodfolk": 3, "ash_pilgrims": 2,
	}
	var centre: int = int(bias.get(culture, 2))
	var i: int = clampi(centre + int(round(rng.randfn(1.2, 1.9))), 0, SKIN_TONES.size() - 1)
	return SKIN_TONES[i]


static func _weighted_hair(rng: RandomNumberGenerator, culture: String, age_v: float) -> String:
	if age_v > 0.72 and rng.randf() < 0.75:
		return "grey" if rng.randf() < 0.6 else "white"
	if age_v > 0.55 and rng.randf() < 0.4:
		return "grey"
	var pool: Array[String] = ["black", "soot", "dark_brown", "brown", "chestnut", "auburn"]
	match culture:
		"vale":
			pool.append_array(["sand", "flax", "ginger"])
		"clans":
			pool.append_array(["ginger", "auburn", "ash_blond"])
		"woodfolk":
			pool.append_array(["dark_brown", "soot"])
		"lakefolk":
			pool.append_array(["sand", "ash_blond"])
	return pool[rng.randi() % pool.size()]


## Each culture dresses in ONE shape you could name from across a field, because that is
## the distance the player actually sees a crowd from and a colour carries no further than
## a few metres (WORLD_BIBLE.md §3, DESIGN.md §7).  Six recolours of a tunic is one people.
static func _culture_outfit(rng: RandomNumberGenerator, culture: String, fem: bool, full: bool = false) -> Dictionary:
	var d := {"head": "default", "feet": "shoes" if rng.randf() < 0.5 else "boots"}
	d["hair"] = HAIR_STYLES[rng.randi() % HAIR_STYLES.size()]
	match culture:
		"lakefolk":
			# a straight column with square shoulders
			d["torso"] = "coat"
			d["legs"] = "trousers"
			d["feet"] = "shoes"
			# a satchel on a strap across the coat: the clerk's papers
			d["belt"] = "belt_satchel"
			if rng.randf() < 0.7 or full:
				d["back"] = "shoulder_cape"
		"reedfolk":
			# asymmetric, one bare shoulder, over a long wrap
			d["torso"] = "wrap_torso"
			d["legs"] = "wrap_skirt"
			d["feet"] = "shoes"
			d["belt"] = "sash"
		"clans":
			# a diagonal drape over bare knees
			d["torso"] = "shirt"
			d["legs"] = "kilt"
			d["feet"] = "boots"
			d["belt"] = "belt_knife"
			if rng.randf() < 0.75 or full:
				d["back"] = "plaid"
		"woodfolk":
			# hooded, banded legs, a torn hem
			d["torso"] = "shirt"
			d["legs"] = "leg_wraps"
			d["feet"] = "boots"
			d["belt"] = "belt_knife"
			d["back"] = "ragged_cloak" if rng.randf() < 0.7 or full else "hooded_cloak"
		"ash_pilgrims":
			# enveloped and cowled, with no waist at all
			d["torso"] = "robe"
			d["feet"] = "boots"
			d["belt"] = "cord_beads"
			d["back"] = "hooded_cloak"
		_:
			# the Vale: belted and knee-length, the baseline everyone else departs from
			if fem and rng.randf() < 0.55:
				d["torso"] = "dress"
			else:
				d["torso"] = "tunic" if rng.randf() < 0.72 else "shirt"
				d["legs"] = "trousers"
			d["belt"] = "belt"
			if rng.randf() < 0.25:
				d["back"] = "cloak"
	return d
