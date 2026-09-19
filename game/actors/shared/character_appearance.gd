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
	culture = str(d.get("culture", culture))
	for key in ["height", "bulk", "shoulder_width", "hip_width", "limb_length", "neck_length",
			"head_size", "build", "age", "feminine", "hearth", "hollow", "veins", "freckles", "stubble"]:
		if d.has(key):
			set(key, float(d[key]))
	for key in ["skin", "hair_colour", "eye_colour"]:
		if d.has(key):
			set(key, str(d[key]))
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
	a.culture = in_culture if in_culture != "" else CULTURES[rng.randi() % CULTURES.size()]
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


static func _culture_outfit(rng: RandomNumberGenerator, culture: String, fem: bool) -> Dictionary:
	var d := {"head": "default", "feet": "shoes" if rng.randf() < 0.5 else "boots"}
	d["hair"] = HAIR_STYLES[rng.randi() % HAIR_STYLES.size()]
	if fem and rng.randf() < 0.55:
		d["torso"] = "dress"
	else:
		d["torso"] = "tunic" if rng.randf() < 0.7 else "shirt"
		d["legs"] = "trousers"
	if rng.randf() < 0.6:
		d["belt"] = "belt"
	match culture:
		"reedfolk":
			if rng.randf() < 0.35:
				d["back"] = "cloak"
		"ash_pilgrims":
			d["torso"] = "robe"
			d.erase("legs")
			d["back"] = "hooded_cloak"
		"woodfolk":
			if rng.randf() < 0.5:
				d["back"] = "hooded_cloak"
		"clans":
			if rng.randf() < 0.4:
				d["back"] = "cloak"
	return d
