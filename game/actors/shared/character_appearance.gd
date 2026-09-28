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
	# the wider palette (triage 39), after the first twelve so a record's old index keeps its colour
	"mahogany", "copper", "strawberry", "honey", "platinum", "salt_pepper", "iron_grey", "silver",
]
## The colours a head of hair is born with (the greys come with the years, `grey`).
const NATURAL_HAIR: Array[String] = ["black", "soot", "dark_brown", "brown", "chestnut", "auburn", "ginger",
	"sand", "flax", "ash_blond", "mahogany", "copper", "strawberry", "honey", "platinum"]
## The greys, and white.
const GREY_HAIR: Array[String] = ["grey", "white", "salt_pepper", "iron_grey", "silver"]
const EYE_COLOURS: Array[String] = [
	"brown", "dark_brown", "hazel", "amber", "green", "grey_green", "blue", "pale_blue", "grey",
]
## Every style is offered to everyone; the last five are the long cuts most women wear (the forge's
## hair system, triage 22), and a woman's rolls draw mostly from them (WOMEN_HAIR).
const HAIR_STYLES: Array[String] = ["short", "cropped", "long", "braid", "bun", "hood_friendly", "tousled",
	"long_loose", "shoulder", "twin_braids", "crown_braid", "chignon",
	# triage 39: curls, cropped curls, shaved at the sides, a shaven head, a hairline gone back, a tail
	"curly", "cropped_curls", "shaved_sides", "shaven", "receding", "ponytail"]
## The cuts added in triage 39, which the dice give now and then in place of the old ones (`_roll_newer_cuts`).
const NEWER_HAIR: Array[String] = ["curly", "cropped_curls", "shaved_sides", "shaven", "receding", "ponytail"]
## Close to the head: worn as they are under a hood or a helm (the rest go to `hood_friendly`).
const CLOSE_HAIR: Array[String] = ["cropped", "hood_friendly", "shaven", "receding", "cropped_curls"]
## Drawn as a shadow on the scalp, as stubble is on the jaw.
const SHADOW_HAIR: Array[String] = ["shaven"]
const BEARD_STYLES: Array[String] = ["stubble", "short_beard", "long_beard", "moustache",
	"full_beard", "goatee", "mutton_chops", "walrus"]
## The four beards the dice have always rolled from, so no villager's beard moved when more came.
const FIRST_BEARDS: Array[String] = ["stubble", "short_beard", "long_beard", "moustache"]

## The face's sliders (triage 39): each a morph target on every head (the forge's
## lib/face_morphs.py, `face_<name>`), -1..1, 0 the head as built. The Naming groups them: FACE_GROUPS.
const FACE_SLIDERS: Array[String] = [
	"jaw_width", "chin_length", "chin_projection", "cheekbones", "cheek_fullness",
	"nose_length", "nose_width", "nose_bridge", "eye_size", "eye_spacing", "eye_tilt", "eye_lids",
	"brow_height", "brow_ridge", "lip_fullness", "mouth_width", "face_length", "ear_size",
]
const FACE_GROUPS := [
	["Jaw and chin", ["jaw_width", "chin_length", "chin_projection", "face_length"]],
	["Cheeks", ["cheekbones", "cheek_fullness"]],
	["Nose", ["nose_length", "nose_width", "nose_bridge"]],
	["Eyes and brow", ["eye_size", "eye_spacing", "eye_tilt", "eye_lids", "brow_height", "brow_ridge"]],
	["Mouth and ears", ["lip_fullness", "mouth_width", "ear_size"]],
]
## The brows drawn over the painted ones (assets/shaders/face_marks.gdshader `brow_style`): "" is
## the head's own.
const BROW_STYLES: Array[String] = ["", "full", "straight", "arched", "bushy", "joined"]
const SCARS: Array[String] = ["", "cheek", "brow", "lip", "nose", "jaw"]
## Face paint, one to a people that wears it (the Vale does not).
const PAINTS: Array[String] = ["", "woad", "reed_dots", "ash_mark", "leaf_lines", "lake_tears"]
const PAINT_OF_CULTURE := {"clans": "woad", "reedfolk": "reed_dots", "ash_pilgrims": "ash_mark",
	"woodfolk": "leaf_lines", "lakefolk": "lake_tears"}
## How often each people's grown folk wear their paint, rolled.
const PAINT_CHANCE := {"clans": 0.14, "reedfolk": 0.16, "ash_pilgrims": 0.28, "woodfolk": 0.12, "lakefolk": 0.07}
## Leanings of a people's faces, added to the dice (a hint, never a type: every face is in every people).
const FACE_LEANINGS := {
	"clans": {"jaw_width": 0.15, "brow_ridge": 0.12, "cheekbones": 0.10},
	"lakefolk": {"face_length": 0.15, "nose_bridge": 0.10, "nose_width": -0.08},
	"reedfolk": {"nose_width": 0.14, "lip_fullness": 0.15, "cheekbones": 0.08},
	"woodfolk": {"cheekbones": 0.15, "eye_tilt": 0.12, "jaw_width": -0.05},
	"ash_pilgrims": {"cheek_fullness": -0.20, "face_length": 0.08},
	"vale": {"cheek_fullness": 0.08},
}
## Tattoos (triage 48): a design, where it is, its ink and how old it is ({design, on, ink, fade}).
## The designs are drawn by assets/shaders/tattoo_designs.gdshaderinc, in this order ("" is none).
const TATTOO_DESIGNS: Array[String] = ["", "knotwork", "triple_knot", "water_lines", "reeds", "leaf", "antlers",
	"ash_rings", "hearth_mark", "tally", "dots", "bands"]
## Where a tattoo can be: on the face (face_marks.gdshader, in the head's face coordinates; the neck is
## the head's) or on the body (body_marks.gdshader, placed on the rig's bones: Adornment.tattoo_frame).
const FACE_TATTOO_PLACES: Array[String] = ["cheek_l", "cheek_r", "brow", "chin", "neck"]
const BODY_TATTOO_PLACES: Array[String] = ["forearm_l", "forearm_r", "upper_arm_l", "upper_arm_r", "hand_l", "hand_r",
	"collarbone_l", "collarbone_r", "back"]
## The most a face and a body carry (the shaders' slots).
const MOST_FACE_TATTOOS := 2
const MOST_BODY_TATTOOS := 4
const TATTOO_INKS := {"soot": "1c1d21", "blue_black": "1b2536", "woad": "2c4a82", "indigo": "2a3160",
	"ochre": "7a3120", "green": "22402c", "ash": "b9b4aa"}
const TATTOO_INK_ORDER: Array[String] = ["soot", "blue_black", "woad", "indigo", "ochre", "green", "ash"]
## Each people's own designs, where they wear them and in what (WORLD_BIBLE §3): the Clans' knotwork
## on arm, back and neck in woad; the Reedfolk's water lines and reeds in marsh indigo on hands and
## forearms; the Woodfolk's leaves and antlers; the Ash-Pilgrims' counted rings in ash and soot, on the
## brow and the hands; the Vale's small hearth-mark, rarely; the Lakefolk's ledger tallies, more rarely.
const TATTOO_WAYS := {
	"clans": {"chance": 0.42, "designs": ["knotwork", "knotwork", "triple_knot", "bands"],
		"places": ["forearm_l", "forearm_r", "upper_arm_l", "upper_arm_r", "back", "neck", "cheek_l"], "inks": ["woad", "woad", "blue_black"]},
	"reedfolk": {"chance": 0.38, "designs": ["water_lines", "water_lines", "reeds", "dots"],
		"places": ["forearm_l", "forearm_r", "hand_l", "hand_r", "collarbone_l", "chin"], "inks": ["indigo", "indigo", "blue_black"]},
	"woodfolk": {"chance": 0.34, "designs": ["leaf", "antlers", "leaf", "dots"],
		"places": ["forearm_l", "forearm_r", "upper_arm_l", "cheek_r", "brow", "hand_l"], "inks": ["green", "soot", "soot"]},
	"ash_pilgrims": {"chance": 0.30, "designs": ["ash_rings", "ash_rings", "dots"],
		"places": ["brow", "hand_l", "hand_r", "forearm_l", "collarbone_r"], "inks": ["ash", "soot", "ash"]},
	"vale": {"chance": 0.07, "designs": ["hearth_mark"], "places": ["hand_l", "hand_r", "forearm_l"], "inks": ["soot", "blue_black"]},
	"lakefolk": {"chance": 0.08, "designs": ["tally", "dots"], "places": ["hand_r", "forearm_r", "collarbone_l"], "inks": ["soot", "ochre"]},
}

## Jewellery (triage 48): a kind, where it is worn and what it is made of ({kind, on, metal}). Each kind
## is a forged piece (assets/models/characters/jewellery/) laid on the body or the head at a landmark
## (Adornment): an ear's lobe, a nostril, the lower lip, the neck, a finger, a wrist, the brow, the hair.
const JEWELLERY_KINDS: Array[String] = ["stud", "hoop", "drop", "nose_stud", "nose_ring", "lip_ring", "torc", "beads",
	"pendant", "brooch", "ring", "bracelet", "circlet", "hair_pin", "braid_rings"]
## Where each kind may go; the first is where it goes when the record does not say.
const JEWELLERY_PLACES := {
	"stud": ["ears", "ear_l", "ear_r"], "hoop": ["ears", "ear_l", "ear_r"], "drop": ["ears", "ear_l", "ear_r"],
	"nose_stud": ["nose"], "nose_ring": ["nose"], "lip_ring": ["lip"],
	"torc": ["neck"], "beads": ["neck"], "pendant": ["neck"], "brooch": ["breast"],
	"ring": ["hand_l", "hand_r", "hands"], "bracelet": ["wrist_l", "wrist_r", "wrists"],
	"circlet": ["brow"], "hair_pin": ["hair"], "braid_rings": ["hair"],
}
const JEWELLERY_METALS: Array[String] = ["iron", "bronze", "silver", "gold", "bone", "glass"]
## The places one piece of each at most is worn: two earrings in one ear, or a torc and beads on one
## neck, are one of them.
const JEWELLERY_SPOTS := {"stud": "ears", "hoop": "ears", "drop": "ears", "nose_stud": "nose", "nose_ring": "nose",
	"lip_ring": "lip", "torc": "neck", "beads": "neck", "pendant": "neck", "brooch": "breast", "ring": "ring",
	"bracelet": "bracelet", "circlet": "brow", "hair_pin": "hair", "braid_rings": "hair"}
## The hair a braid's rings go on, and the hair a pin holds (other hair takes neither).
const BRAIDED_HAIR: Array[String] = ["braid", "twin_braids", "ponytail"]
const PINNED_HAIR: Array[String] = ["bun", "chignon", "crown_braid", "ponytail", "braid", "twin_braids"]
## Each people's jewellery (WORLD_BIBLE §3), with the chance of each piece on a grown person of middling
## means: the Clans' torcs, arm-rings and giant-bone tokens and the rings on their braids; the Reedfolk's
## glass beads and bronze hoops, a ring through the nose; the Woodfolk's bone and antler; the pilgrims'
## iron and little else; the Vale's ring and pendant; the Lakefolk's silver and gold.
const JEWELLERY_WAYS := {
	"clans": {"torc": 0.30, "bracelet": 0.25, "beads": 0.12, "braid_rings": 0.35, "brooch": 0.10, "ring": 0.18, "stud": 0.06},
	"reedfolk": {"beads": 0.35, "hoop": 0.25, "nose_ring": 0.10, "nose_stud": 0.06, "bracelet": 0.20, "lip_ring": 0.04, "ring": 0.10},
	"woodfolk": {"beads": 0.22, "stud": 0.15, "hair_pin": 0.20, "bracelet": 0.12, "ring": 0.08, "pendant": 0.06},
	"ash_pilgrims": {"ring": 0.25, "beads": 0.12, "pendant": 0.06},
	"vale": {"ring": 0.26, "pendant": 0.14, "stud": 0.14, "hair_pin": 0.14, "beads": 0.08, "drop": 0.05},
	"lakefolk": {"ring": 0.40, "pendant": 0.22, "drop": 0.14, "stud": 0.16, "brooch": 0.14, "circlet": 0.03, "bracelet": 0.12},
}
## What each people makes its jewellery of, poorest first: the dice pick further along with wealth.
const JEWELLERY_STUFF := {
	"clans": ["bone", "iron", "bronze", "bronze", "silver", "gold"],
	"reedfolk": ["bone", "glass", "bronze", "bronze", "silver"],
	"woodfolk": ["bone", "bone", "iron", "bronze", "silver"],
	"ash_pilgrims": ["iron", "iron", "bone", "bronze"],
	"vale": ["iron", "bronze", "bronze", "silver", "gold"],
	"lakefolk": ["bronze", "silver", "silver", "gold", "gold"],
}

## The head presets the forge has built (game/assets/models/characters/heads/). "default" is
## the rig's own head; the rest replace it. Each is built again with a woman's face as
## `<name>` + FEMININE_HEAD, which a woman wears in its place (HumanoidModel).
const HEADS: Array[String] = ["default", "round", "soft", "angular", "narrow", "broad", "hawk", "heavy_brow"]
const FEMININE_HEAD := "_f"
## The body variant a woman wears (tools/forge/character_forge.py BODY_VARIANTS).
const WOMAN_BODY := "woman"
## What a woman's hair is rolled from: the women's cuts, most of the time (17 of 20), and now and
## then one of the men's. One roll, as a man's is, so the rest of a record's dice fall where they did.
const WOMEN_HAIR: Array[String] = [
	"long_loose", "long_loose", "long_loose", "shoulder", "shoulder", "twin_braids", "twin_braids",
	"crown_braid", "crown_braid", "chignon", "chignon", "chignon", "long", "long", "braid", "bun", "bun",
	"short", "cropped", "tousled",
]
## What a man's hair is rolled from: the men's cuts, as they always were (so no villager's dice
## move); the long ones are there to choose in the Naming.
const MEN_HAIR: Array[String] = ["short", "cropped", "long", "braid", "bun", "hood_friendly", "tousled"]
## The same kind of cut on the other body, for a record whose body is changed with its hair left
## as it was (the Naming's Body row): short and cropped go long, a braid two braids, a bun a low
## knot, and the women's cuts back again.
const HAIR_ACROSS := {
	"short": "long_loose", "tousled": "shoulder", "long": "long_loose", "braid": "twin_braids",
	"bun": "chignon", "cropped": "chignon", "hood_friendly": "crown_braid",
	"long_loose": "long", "shoulder": "tousled", "twin_braids": "braid", "crown_braid": "bun",
	"chignon": "bun",
}
## The women's cuts of clothing (triage 22), each built on the default body and fitted to hers. A
## woman is dressed in them where her people have one (`_culture_outfit`); a garment the forge has
## not built yet is worn as the man's cut it stands for.
const WOMENS_CUTS := {"kirtle": "tunic", "fitted_tunic": "tunic", "bodice": "shirt", "long_skirt": "trousers",
	"shawl": ""}
## A worn item's part, cut for a woman: the wool tunic in the pack is a man's tunic, and on a woman
## it is her long belted one.
const WOMANS_CUT_OF := {"tunic": "fitted_tunic"}

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
	"mahogany": "4a2219", "copper": "93441c", "strawberry": "b87a52", "honey": "a97a3c",
	"platinum": "ddd3b8", "salt_pepper": "6e6a66", "iron_grey": "7d7f80", "silver": "bdbcb9",
}
## What hair goes to with the years (`grey`): a warm grey, not the white of an old man's beard.
const GREYED_HAIR := "a8a49e"
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
	"vale": {"primary": "8f7a5a", "secondary": "6a6b52", "accent": "8c4a3e", "leather": "5e4632", "metal": "7c7e7e", "trim": "a8925c"},
	"lakefolk": {"primary": "c6bca8", "secondary": "5b6570", "accent": "8f7446", "leather": "4a4239", "metal": "8f7446", "trim": "5d7080"},
	"reedfolk": {"primary": "4f5a69", "secondary": "7a5a4c", "accent": "a8804a", "leather": "54452f", "metal": "7d7a70", "trim": "b0a070"},
	"clans": {"primary": "c2b8a0", "secondary": "5e4c3a", "accent": "7c4034", "leather": "59432c", "metal": "6f7274", "trim": "d6cfbd"},
	"woodfolk": {"primary": "665a45", "secondary": "5a5f47", "accent": "6e7650", "leather": "3f3325", "metal": "5f6259", "trim": "2b211c"},
	"ash_pilgrims": {"primary": "8b8a86", "secondary": "5a5652", "accent": "cfc7b6", "leather": "4a4744", "metal": "77736d", "trim": "8f7f58"},
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
## 0 a man's body, 1 a woman's: at 0.5 and over the model wears the woman's body and face
## (`is_woman`). The Naming's Body choice writes it; an NPC def may carry it.
var feminine: float = 0.0
## A woman's bust, 0.8..1.2 of the body as built (item 46): the woman's body and every garment
## fitted to her carry the 1.2 end as a morph target (`bust_weight`). A man's body ignores it.
var bust: float = 1.0

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

# -- the face (triage 39) -------------------------------------------------------------------
## slider -> -1..1 (FACE_SLIDERS); a missing slider is 0, the head as built.
var face: Dictionary = {}
var brows: String = ""           ## BROW_STYLES
var scar: String = ""            ## SCARS
var moles: float = 0.0           ## 0..1, how many of their places carry one
var paint: String = ""           ## PAINTS
## How grey the hair has gone, 0..1; below 0 the years decide (`hair_grey`).
var grey: float = -1.0

# -- adornment (triage 48) -------------------------------------------------------------------------
## [{design, on, ink, fade}], TATTOO_DESIGNS at FACE_TATTOO_PLACES or BODY_TATTOO_PLACES.
var tattoos: Array = []
## [{kind, on, metal}], JEWELLERY_KINDS at their JEWELLERY_PLACES, of JEWELLERY_METALS.
var jewellery: Array = []


func _init(from: Dictionary = {}) -> void:
	if not from.is_empty():
		from_dict(from)


func from_dict(d: Dictionary) -> void:
	seed = int(d.get("seed", seed))
	culture = culture_id(str(d.get("culture", culture)))
	for key in ["height", "bulk", "shoulder_width", "hip_width", "limb_length", "neck_length",
			"head_size", "build", "age", "feminine", "hearth", "hollow", "veins", "freckles", "stubble",
			"moles", "grey", "bust"]:
		if d.has(key) and typeof(d[key]) in [TYPE_INT, TYPE_FLOAT]:
			set(key, float(d[key]))
	if d.has("face") and typeof(d["face"]) == TYPE_DICTIONARY:
		face = {}
		for k in d["face"]:
			var v: Variant = d["face"][k]
			set_face(str(k), float(v) if typeof(v) in [TYPE_INT, TYPE_FLOAT] else 0.0)
	for pair in [["brows", BROW_STYLES], ["scar", SCARS], ["paint", PAINTS]]:
		var key: String = pair[0]
		if d.has(key) and str(d[key]) in (pair[1] as Array):
			set(key, str(d[key]))
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
	if d.has("tattoos"):
		set_tattoos(d["tattoos"])
	if d.has("jewellery"):
		set_jewellery(d["jewellery"])


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
		"face": face.duplicate(), "brows": brows, "scar": scar, "moles": moles, "paint": paint, "grey": grey,
		"bust": bust,
		"tattoos": tattoos.duplicate(true), "jewellery": jewellery.duplicate(true),
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


# -- the face ------------------------------------------------------------------------------------

## A face slider's value, -1..1 (0 when the record says nothing of it).
func face_value(slider: String) -> float:
	return clampf(float(face.get(slider, 0.0)), -1.0, 1.0)


func set_face(slider: String, value: float) -> void:
	if not FACE_SLIDERS.has(slider):
		return
	var v := clampf(value, -1.0, 1.0)
	if absf(v) < 0.0005:
		face.erase(slider)
	else:
		face[slider] = snappedf(v, 0.001)


## The years on the face (the `face_age` morph): nothing until the middle of life, all of it at the
## top of the record's age range.
const AGE_FACE_FROM := 0.35
const AGE_FACE_FULL := 0.95


func age_on_face() -> float:
	return clampf((age - AGE_FACE_FROM) / (AGE_FACE_FULL - AGE_FACE_FROM), 0.0, 1.0)


## The weight a head's morph target `face_<name>` is set to (HumanoidModel._apply_fits).
func face_weight(target: String) -> float:
	if target == "age":
		return age_on_face()
	if target == "eye_lids":
		# every lid rests a little down over the iris; the slider takes it from open to heavy
		return LID_REST + face_value(target) * (1.0 - LID_REST)
	return face_value(target)


## How far down the upper lid rests on a face whose slider is at 0 (triage 40's lid shadow asked it).
const LID_REST := 0.45


## How grey the hair is, 0..1: the record's own `grey`, or else the years' (each person's own onset,
## from their seed, between the late thirties and the fifties).
func hair_grey() -> float:
	if grey >= 0.0:
		return clampf(grey, 0.0, 1.0)
	return greying_for(age, seed)


static func greying_for(years: float, rng_seed: int) -> float:
	var onset := 0.40 + 0.20 * float(absi(hash("%d|grey" % rng_seed)) % 1000) / 999.0
	return clampf((years - onset) / 0.40, 0.0, 1.0)


## Every face slider rolled for a person of this people, body, build and age: a spread round the
## head as built, leaning the way the people's faces lean. On dice of its own (`rng`), so the rest of
## a record's rolls fall where they always did.
func roll_face(rng: RandomNumberGenerator) -> void:
	face = {}
	var lean: Dictionary = FACE_LEANINGS.get(culture, {})
	for slider in FACE_SLIDERS:
		set_face(slider, rng.randfn(0.0, 0.36) + float(lean.get(slider, 0.0)))
	# a heavier body, a fuller face; the years take the fullness out of it
	set_face("cheek_fullness", face_value("cheek_fullness") + (build - 0.45) * 0.9 - maxf(age - 0.5, 0.0) * 0.5)
	set_face("jaw_width", face_value("jaw_width") + (build - 0.45) * 0.35)


## The brows, a scar, moles and paint, rolled (`rng` is the face's own dice).
func roll_marks(rng: RandomNumberGenerator) -> void:
	var r := rng.randf()
	if is_woman():
		brows = "" if r < 0.55 else ("arched" if r < 0.72 else ("full" if r < 0.87 else "straight"))
	else:
		var bushy := 0.10 + 0.25 * maxf(age - 0.5, 0.0)
		if r < 0.45:
			brows = ""
		elif r < 0.63:
			brows = "full"
		elif r < 0.78:
			brows = "straight"
		elif r < 0.78 + bushy:
			brows = "bushy"
		else:
			brows = "joined"
	scar = SCARS[1 + rng.randi() % (SCARS.size() - 1)] if rng.randf() < (0.03 if is_woman() else 0.07) else ""
	moles = rng.randf_range(0.2, 0.9) if rng.randf() < 0.28 else 0.0
	paint = str(PAINT_OF_CULTURE.get(culture, "")) if rng.randf() < float(PAINT_CHANCE.get(culture, 0.0)) else ""


## What a named person's def pins over their dice: any face slider (`face`: {slider: -1..1}), the
## brows, a scar, moles, paint, how grey, the head, hair, beard and colours -- each only when it is a
## word or number the record knows. A def's `appearance` block is written for a reader too
## (`"hair": "red_grey_shaved_sides"`), and prose is left to the reader.
func pin(block: Dictionary) -> void:
	var f: Variant = block.get("face", null)
	if typeof(f) == TYPE_DICTIONARY:
		for k in f:
			if typeof(f[k]) in [TYPE_INT, TYPE_FLOAT]:
				set_face(str(k), float(f[k]))
	for pair in [["brows", BROW_STYLES], ["scar", SCARS], ["paint", PAINTS], ["skin", SKIN_TONES],
			["hair_colour", HAIR_COLOURS], ["eye_colour", EYE_COLOURS]]:
		var key: String = pair[0]
		if block.has(key) and typeof(block[key]) == TYPE_STRING and str(block[key]) in (pair[1] as Array):
			set(key, str(block[key]))
	for key in ["moles", "grey", "bust"]:
		if typeof(block.get(key, null)) in [TYPE_INT, TYPE_FLOAT]:
			set(key, float(block[key]))
	bust = clampf(bust, BUST_MIN, BUST_MAX)
	for pair in [["head", "head", HEADS], ["hair", "hair", HAIR_STYLES], ["beard", "beard", BEARD_STYLES]]:
		var v: Variant = block.get(pair[0], null)
		if typeof(v) == TYPE_STRING and (str(v) in (pair[2] as Array) or (pair[0] == "beard" and str(v) == "none")):
			set_part(str(pair[1]), "" if str(v) == "none" else str(v))
	# tattoos and jewellery (triage 48): a list replaces the dice's, "none" takes them off
	for key in ["tattoos", "jewellery"]:
		var v: Variant = block.get(key, null)
		if typeof(v) == TYPE_STRING and str(v) == "none":
			set(key, [])
		elif typeof(v) == TYPE_ARRAY:
			if key == "tattoos":
				set_tattoos(v)
			else:
				set_jewellery(v)


const BUST_MIN := 0.8
const BUST_MAX := 1.2


## The weight of the `bust` morph target on the woman's body and of `woman_bust` on what she
## wears: -1 at the smallest, 0 as built, 1 at the fullest (HumanoidModel._apply_fits).
func bust_weight() -> float:
	return clampf((bust - 1.0) / (BUST_MAX - 1.0), -1.0, 1.0)


## A woman's bust by the dice (item 46): its own dice, from the seed, so no old roll moved; a
## little fuller with weight, most near the body as built.
func roll_bust(rng_seed: int) -> void:
	if not is_woman():
		bust = 1.0
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d|bust46" % rng_seed)
	bust = clampf(rng.randfn(1.0, 0.075) + 0.10 * (build - 0.45), BUST_MIN, BUST_MAX)


## The dice for the face and the marks: their own, from the seed, so adding them moved nobody's
## height, colouring or clothes.
static func face_rng(rng_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d|face39" % rng_seed)
	return rng


# -- adornment: tattoos and jewellery (triage 48) -------------------------------------------------

## A tattoo as the record keeps it, or {} when it is not one: a known design at a known place, a known
## ink (soot when it says none), fade 0..1.
static func clean_tattoo(v: Variant) -> Dictionary:
	if typeof(v) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = v
	var design := str(d.get("design", ""))
	var on := str(d.get("on", ""))
	if design.is_empty() or not TATTOO_DESIGNS.has(design):
		return {}
	if not FACE_TATTOO_PLACES.has(on) and not BODY_TATTOO_PLACES.has(on):
		return {}
	var ink := str(d.get("ink", "soot"))
	if not TATTOO_INKS.has(ink):
		ink = "soot"
	var fade: Variant = d.get("fade", 0.0)
	return {"design": design, "on": on, "ink": ink,
		"fade": snappedf(clampf(float(fade) if typeof(fade) in [TYPE_INT, TYPE_FLOAT] else 0.0, 0.0, 1.0), 0.01)}


## A piece of jewellery as the record keeps it, or {}: a known kind, at one of its places (its first
## when the record says none), of a known stuff (bronze when it says none).
static func clean_jewel(v: Variant) -> Dictionary:
	if typeof(v) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = v
	var kind := str(d.get("kind", ""))
	if not JEWELLERY_KINDS.has(kind):
		return {}
	var places: Array = JEWELLERY_PLACES[kind]
	var on := str(d.get("on", places[0]))
	if not places.has(on):
		on = str(places[0])
	var metal := str(d.get("metal", "bronze"))
	if not JEWELLERY_METALS.has(metal):
		metal = "bronze"
	return {"kind": kind, "on": on, "metal": metal}


## The tattoos, cleaned: one to a place, and no more than the face's and the body's slots.
func set_tattoos(list: Variant) -> void:
	tattoos = []
	if typeof(list) != TYPE_ARRAY:
		return
	var faces := 0
	var bodies := 0
	var taken := {}
	for v in list:
		var t := clean_tattoo(v)
		if t.is_empty() or taken.has(t["on"]):
			continue
		var on_face := FACE_TATTOO_PLACES.has(t["on"])
		if (on_face and faces >= MOST_FACE_TATTOOS) or (not on_face and bodies >= MOST_BODY_TATTOOS):
			continue
		faces += int(on_face)
		bodies += int(not on_face)
		taken[t["on"]] = true
		tattoos.append(t)


## The jewellery, cleaned: one piece to a spot (JEWELLERY_SPOTS; rings and bracelets one to a hand).
func set_jewellery(list: Variant) -> void:
	jewellery = []
	if typeof(list) != TYPE_ARRAY:
		return
	var taken := {}
	for v in list:
		var j := clean_jewel(v)
		if j.is_empty():
			continue
		var spot := str(JEWELLERY_SPOTS.get(j["kind"], j["kind"]))
		var sides: Array = [spot]
		if spot in ["ring", "bracelet"]:
			sides = ["%s_l" % spot, "%s_r" % spot] if str(j["on"]).ends_with("s") else ["%s_%s" % [spot, str(j["on"]).right(1)]]
		var clash := false
		for s in sides:
			clash = clash or taken.has(s)
		if clash:
			continue
		for s in sides:
			taken[s] = true
		jewellery.append(j)


## The tattoo at a place, or {}.
func tattoo_at(place: String) -> Dictionary:
	for t in tattoos:
		if str(t.get("on", "")) == place:
			return t
	return {}


## The piece of jewellery of one of `kinds`, or {}.
func jewel_of(kinds: Array) -> Dictionary:
	for j in jewellery:
		if kinds.has(str(j.get("kind", ""))):
			return j
	return {}


func face_tattoos() -> Array:
	return tattoos.filter(func(t: Dictionary) -> bool: return FACE_TATTOO_PLACES.has(str(t["on"])))


func body_tattoos() -> Array:
	return tattoos.filter(func(t: Dictionary) -> bool: return BODY_TATTOO_PLACES.has(str(t["on"])))


static func ink_colour(ink: String) -> Color:
	return Color(str(TATTOO_INKS.get(ink, TATTOO_INKS["soot"])))


## The dice for tattoos and jewellery: their own, from the seed, so no roll made before them moved.
static func adorn_rng(rng_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d|adorn48" % rng_seed)
	return rng


## How well off a person is, 0..1, by what their def's tags say they do: a merchant, a steward or the
## law are better off than a farmer, a wayfarer or a child. -1 when the tags say nothing of it.
const WEALTH_OF_TAGS := {"merchant": 0.75, "steward": 0.8, "law": 0.6, "trade": 0.6, "guard": 0.5, "noble": 0.95,
	"elder": 0.6, "priest": 0.5, "miller": 0.55, "farmer": 0.3, "wayfarer": 0.25, "child": 0.2, "beggar": 0.05,
	"pilgrim": 0.15}


static func wealth_of(tags: Array) -> float:
	var best := -1.0
	for t in tags:
		best = maxf(best, float(WEALTH_OF_TAGS.get(str(t), -1.0)))
	return best


## Tattoos and jewellery by people, body, years and means (`wealth` 0..1, below 0 rolled), on `rng`
## (adorn_rng). A child is inked by no one and wears a bead at most; the old have faded ink.
func roll_adornment(rng: RandomNumberGenerator, wealth: float = -1.0) -> void:
	tattoos = []
	jewellery = []
	var w := wealth if wealth >= 0.0 else clampf(rng.randfn(0.4, 0.2), 0.0, 1.0)
	# every die is thrown whatever is kept, so a record's pieces do not move when one of them changes
	var ways: Dictionary = TATTOO_WAYS.get(culture, TATTOO_WAYS["vale"])
	var want: Array = []
	var inked := rng.randf() < float(ways["chance"]) * (1.15 if not is_woman() else 0.85)
	var how_many := 1 + int(rng.randf() < 0.45) + int(rng.randf() < 0.25)
	var ink := str((ways["inks"] as Array)[rng.randi() % (ways["inks"] as Array).size()])
	# ink goes in young and fades with the years; each piece has its own share of it
	var first_inked := rng.randf_range(0.12, 0.35)
	for i in 3:
		var design := str((ways["designs"] as Array)[rng.randi() % (ways["designs"] as Array).size()])
		var place := str((ways["places"] as Array)[rng.randi() % (ways["places"] as Array).size()])
		var own_fade := rng.randf_range(-0.1, 0.15)
		if inked and i < how_many and age >= 0.18 and body_variant() != "child":
			want.append({"design": design, "on": place, "ink": ink,
				"fade": clampf((age - first_inked) * 1.1 + own_fade, 0.0, 1.0)})
	set_tattoos(want)
	var pieces: Array = []
	var jways: Dictionary = JEWELLERY_WAYS.get(culture, JEWELLERY_WAYS["vale"])
	var stuff: Array = JEWELLERY_STUFF.get(culture, JEWELLERY_STUFF["vale"])
	for kind in JEWELLERY_KINDS:
		var chance := float(jways.get(kind, 0.0))
		# the better off wear more, and women more at the ears and the hair
		chance *= lerpf(0.4, 1.7, w)
		if is_woman() and kind in ["stud", "hoop", "drop", "hair_pin", "beads", "circlet"]:
			chance *= 1.8
		elif not is_woman() and kind in ["drop", "hair_pin", "circlet"]:
			chance *= 0.3
		var r := rng.randf()
		var pick := rng.randf()
		var side := rng.randf()
		if body_variant() == "child" and kind != "beads":
			continue
		if r >= chance:
			continue
		var k := clampi(int(floor(lerpf(0.0, float(stuff.size()), clampf(w + (pick - 0.5) * 0.5, 0.0, 0.999)))), 0, stuff.size() - 1)
		var metal := str(stuff[k])
		if kind == "beads" and metal in ["iron", "gold"]:
			metal = "glass"
		if kind in ["torc", "circlet", "pendant"] and metal in ["glass"]:
			metal = "bronze"
		var places: Array = JEWELLERY_PLACES[kind]
		var on := str(places[0])
		if kind in ["ring", "bracelet"]:
			on = str(places[2]) if side < 0.2 else (str(places[0]) if side < 0.6 else str(places[1]))
		elif kind in ["stud", "hoop", "drop"]:
			on = "ears" if side < 0.8 else str(places[1 + int(side < 0.9)])
		if kind == "braid_rings" and not BRAIDED_HAIR.has(part("hair")):
			continue
		if kind == "hair_pin" and not PINNED_HAIR.has(part("hair")):
			continue
		pieces.append({"kind": kind, "on": on, "metal": metal})
	set_jewellery(pieces)


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


## The tint that turns the baked hair into this colour (`palette.hair` overrides it), greyed as far
## as the years or the record's `grey` have taken it.
func hair_tint() -> Color:
	if palette.has("hair"):
		return palette["hair"]
	return _relative_tint(hair_worn_colour(), Color(BAKED_HAIR))


## The colour the hair is, greyed.
func hair_worn_colour() -> Color:
	var own := hair_colour_value(hair_colour)
	if hair_colour in GREY_HAIR:
		return own
	# grey comes in as white hairs among the colour: lighter and colder, not a dye
	return own.lerp(Color(GREYED_HAIR), hair_grey() * 0.85)


## The hair this record should wear on the body it now has, when `style` is the other body's kind
## of cut (HAIR_ACROSS: a man's cut on a woman, one of the women's cuts on a man).
func hair_for_body(style: String) -> String:
	var mans := MEN_HAIR.has(style)
	if style.is_empty() or mans != is_woman():
		return style
	return str(HAIR_ACROSS.get(style, style))


## The part a woman wears for `garment`: her cut of it when one is built (WOMANS_CUT_OF), else it.
func cut_for_body(garment: String) -> String:
	if not is_woman() or not WOMANS_CUT_OF.has(garment):
		return garment
	var hers := str(WOMANS_CUT_OF[garment])
	return hers if garment_built(hers) else garment


## True when the forge has built this garment (the women's cuts were added after the rest).
static func garment_built(garment: String) -> bool:
	return ResourceLoader.exists("res://assets/models/characters/clothing/%s/%s.glb" % [garment, garment])


## `garment` when built, else the man's cut it stands for (WOMENS_CUTS).
static func _womans(garment: String) -> String:
	return garment if garment_built(garment) else str(WOMENS_CUTS.get(garment, garment))


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
	var outfit := _culture_outfit(rng, culture, is_woman(), for_player)
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


## A woman's body and face (the forge's `woman` body and `<face>_f` heads), not a man's.
func is_woman() -> bool:
	return feminine >= 0.5


## Which exported body-scale variant fits these proportions best. Runtime bone scaling would
## break clips that are authored on the default proportions (CONTRACTS §2), so the forge
## exports a handful of variants and we pick the nearest.
##
## A woman's body is one variant across the whole build range, as a man's default is: the rig's
## girth does the widening (HumanoidModel.girth_for). A child's body is a child's either way;
## a girl is told by her hair and her dress, as a child is at that age.
func body_variant() -> String:
	if height <= 1.45:
		return "child"
	if is_woman():
		return WOMAN_BODY
	if build >= 0.68:
		return "heavy"
	if build <= 0.30:
		return "slight"
	return "default"


## A deterministic random appearance for NPC variety. `in_feminine` (0 or 1) is a def's own
## word on it; below 0 the dice decide. `in_wealth` (0 poor .. 1 rich) is how much jewellery and of
## what (`wealth_of`); below 0 the dice decide that too. It has to be known before the roll goes on: a woman is
## shorter, dressed as her people dress women and never bearded, and a def's `feminine` laid
## over the finished roll afterwards gave a named woman the beard and height of the man the dice
## had made.
static func random(rng_seed: int, in_culture: String = "", in_feminine: float = -1.0,
		in_wealth: float = -1.0) -> CharacterAppearance:
	var a := CharacterAppearance.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	a.seed = rng_seed
	a.culture = culture_id(in_culture) if in_culture != "" else CULTURES[rng.randi() % CULTURES.size()]
	var rolled := 1.0 if rng.randf() < 0.5 else 0.0
	a.feminine = rolled if in_feminine < 0.0 else clampf(in_feminine, 0.0, 1.0)
	# about a hand shorter: women 1.55-1.79 m, men 1.62-1.86 m
	a.height = 1.62 + rng.randf() * 0.24 - (0.07 if a.is_woman() else 0.0)
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
	a.parts = _culture_outfit(rng, a.culture, a.is_woman())
	# the culture's cloth colours: without them every people's clothes were the bake's one hue
	a.palette = culture_palette(a.culture)
	if not a.is_woman() and rng.randf() < 0.45:
		a.parts["beard"] = FIRST_BEARDS[rng.randi() % FIRST_BEARDS.size()]
	elif not a.is_woman() and rng.randf() < 0.4:
		a.stubble = 0.3 + rng.randf() * 0.5
	# the face, the marks and the newer cuts, on dice of their own (triage 39)
	var frng := face_rng(rng_seed)
	# one of the eight heads: every villager wore the "default" one, the rest only the Naming offered
	a.set_part("head", HEADS[frng.randi() % HEADS.size()])
	a.roll_face(frng)
	a.roll_marks(frng)
	a._roll_newer_cuts(frng)
	a.roll_bust(rng_seed)
	# tattoos and jewellery, on dice of their own again (triage 48): nothing above moved
	a.roll_adornment(adorn_rng(rng_seed), in_wealth)
	return a


## Now and then one of the cuts, beards and colours added in triage 39 in place of what the old
## dice gave, where the forge has built it: curls, a tail, a shaved head, a hairline gone back.
func _roll_newer_cuts(rng: RandomNumberGenerator) -> void:
	var hair := part("hair")
	var r := rng.randf()
	var newer := ""
	if is_woman():
		newer = "curly" if r < 0.10 else ("ponytail" if r < 0.20 else ("cropped_curls" if r < 0.23 else ""))
	elif age > 0.55 and r < 0.30:
		newer = "receding" if rng.randf() < 0.7 else "shaven"
	elif r < 0.06:
		newer = "curly"
	elif r < 0.13:
		newer = "cropped_curls"
	elif r < 0.18:
		newer = "shaved_sides"
	elif r < 0.22:
		newer = "shaven"
	if not newer.is_empty() and not hair.is_empty() and part_built("hair", newer):
		set_part("hair", newer)
	var beard := part("beard")
	if not beard.is_empty() and rng.randf() < 0.40:
		var others := {"short_beard": ["full_beard", "goatee"], "long_beard": ["full_beard"],
			"moustache": ["walrus", "goatee"], "stubble": ["goatee", "mutton_chops"]}
		var pool: Array = others.get(beard, [])
		if not pool.is_empty():
			var pick := str(pool[rng.randi() % pool.size()])
			if part_built("beards", pick):
				set_part("beard", pick)
	# a shade of the wider palette, some of the time, near the colour rolled
	var near := {"brown": ["mahogany"], "chestnut": ["mahogany", "copper"], "auburn": ["copper"],
		"ginger": ["copper", "strawberry"], "sand": ["honey"], "flax": ["honey", "platinum"],
		"ash_blond": ["platinum"], "grey": ["salt_pepper", "iron_grey", "silver"], "white": ["silver"]}
	if near.has(hair_colour) and rng.randf() < 0.3:
		var shades: Array = near[hair_colour]
		hair_colour = str(shades[rng.randi() % shades.size()])


## True when the forge has built this part (`dir` is the parts' directory: hair, beards, ...).
static func part_built(dir: String, name: String) -> bool:
	return ResourceLoader.exists("res://assets/models/characters/%s/%s/%s.glb" % [dir, name, name])


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
	var styles: Array[String] = WOMEN_HAIR if fem else MEN_HAIR
	d["hair"] = styles[rng.randi() % styles.size()]
	match culture:
		"lakefolk":
			# a straight column with square shoulders
			d["torso"] = "coat"
			# a woman's coat falls over a long skirt, not over trousers: the same column, to the ankle
			d["legs"] = _womans("long_skirt") if fem else "trousers"
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
			# and a woman's shawl over it, some days
			if fem and rng.randf() < 0.4:
				d["back"] = _womans("shawl")
		"clans":
			# a diagonal drape over bare knees; a woman's is the plaid over a laced bodice and a skirt
			# to the ankle (the arisaid), the same diagonal from across a field
			d["torso"] = _womans("bodice") if fem else "shirt"
			d["legs"] = _womans("long_skirt") if fem else "kilt"
			d["feet"] = "boots"
			d["belt"] = "belt_knife"
			if rng.randf() < 0.75 or full:
				d["back"] = "plaid"
		"woodfolk":
			# hooded, banded legs, a torn hem; a woman's long belted tunic over the bands
			d["torso"] = _womans("fitted_tunic") if fem else "shirt"
			d["legs"] = "leg_wraps"
			d["feet"] = "boots"
			d["belt"] = "belt_knife"
			d["back"] = "ragged_cloak" if rng.randf() < 0.7 or full else "hooded_cloak"
		"ash_pilgrims":
			# enveloped and cowled, with no waist at all: the robe is a woman's as well as a man's
			d["torso"] = "robe"
			d["feet"] = "boots"
			d["belt"] = "cord_beads"
			d["back"] = "hooded_cloak"
		_:
			# the Vale: belted and knee-length, the baseline everyone else departs from. A woman's
			# is the gown (the kirtle), the short-sleeved dress, or the long belted tunic over
			# trousers for work; a shawl over it as often as a cloak.
			if fem:
				var r := rng.randf()
				if r < 0.45:
					d["torso"] = _womans("kirtle")
				elif r < 0.72:
					d["torso"] = "dress"
				else:
					d["torso"] = _womans("fitted_tunic")
					d["legs"] = "trousers"
			else:
				d["torso"] = "tunic" if rng.randf() < 0.72 else "shirt"
				d["legs"] = "trousers"
			d["belt"] = "belt"
			if rng.randf() < 0.25:
				d["back"] = "cloak"
			elif fem and rng.randf() < 0.30:
				d["back"] = _womans("shawl")
	# a stand-in that is no garment at all (a shawl not yet built) is nothing in that slot
	for slot in d.keys():
		if str(d[slot]).is_empty():
			d.erase(slot)
	return d
