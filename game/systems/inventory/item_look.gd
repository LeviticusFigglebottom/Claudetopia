extends RefCounted
## What an item lying in the world looks like.
##
## Nearly no item def names a model of its own (4 of 504, and none of those files exists), so every
## pickup in the country -- loot, a quest's letter, a key on a cist -- was WorldItem's stand-in: a
## flat-coloured box or bar, named "Placeholder", which read as something dropped in to test and
## was found by the seat audit on a ruin's grass. An item is now drawn as the forge's own thing
## that fits it: a weapon or a shield as the model the hand holds (HeldItems), anything else as the
## forge prop its id, tags and category say it is (a letter a scroll, a potion a phial, a key or a
## coin a bit of copper, a pelt a folded cloth, a parcel a sack), through RULES below, and in the
## region's own make where the forge made one.
##
## model_for() is "" only for an item no rule and no fallback answers, and the forge has always
## made a sack, so in practice it is never "". WorldItem logs any it gets as a content error and
## draws the sack; test_item_looks fails on any item def without a look.

const HELD := preload("res://actors/shared/held_items.gd")
const WEAPONS_ROOT := "res://assets/models/"
## The largest a pickup is drawn, in metres: a prop made to stand in a room (a chest, a barrel)
## stood in for a small thing is scaled down to this.
const MOST_M := 0.7
const FALLBACK := "sack"

## [pattern over "<id leaf> <tags> <category>", prop kind], first match wins.
const RULES := [
	["arrow|bolt|quarrel", "spear"],
	["letter|page|note|writ|charter|verse|roll|ledger|scroll|map", "scroll"],
	["deed|contract|paper", "paper_stack"],
	["\\bbook\\b|tome|press", "book"],
	["potion|phial|tonic|draught|elixir|poison", "phial"],
	["flask|cider|ale|wine|mead|milk|drink|honey", "jug"],
	["cup|mug|tankard", "mug"],
	["loaf|bread|oatcake|cake|pie|flour", "loaf"],
	["cheese|egg|mutton|meat|food", "plate"],
	["lantern|lamp", "lantern_hand"],
	["torch|candle", "candle"],
	["bell|clapper|tine", "bell_small"],
	["rope|net|wire|snare", "rope_coil"],
	["hook|pin|screw|link|chain|lockpick|key|coin|silver|token|ring|amulet|signet|thimble|mark|ingot|ore|scrap|metal|bronze|iron", "copper"],
	["hammer", "hammer"],
	["tongs", "tongs"],
	["whetstone|stone|flint|chalk|sliver|glass|glim|mote|ember", "whetstone"],
	["boots|shoes|sabatons|greaves", "boots"],
	["shield", "shield"],
	["pelt|hide|leather|scale|wool|linen|silk|cloth|cloak|hood|tunic|jerkin|gambeson|mittens|gloves|gauntlets|cap|collar|rug|hangings", "cloth"],
	["helm|crown|plate|brigandine", "cloth"],
	["plank|wood|knot|rods|bow", "boardwalk_plank"],
	["bone|antler|tusk", "whetstone"],
	["berry|apple|fruit|seed|herb|flower|petal|moss|lichen|fungus|mould|root|cress|grass|thorn|dye", "basket"],
	["liver|gland|animal|sundew", "jar"],
	["chest|furnishing", "chest"],
	["shelf|storage|jar", "jar"],
	["chair|seat", "stool"],
	["parcel|sack|meal|bundle", "sack"],
]

static var _res: Array = []
static var _library: PropLibrary = null


## The scene an item def is drawn with, "" when nothing answers.
static func model_for(d: Dictionary, region_id := "") -> String:
	var own := str(d.get("model", ""))
	if own != "":
		var p := own if own.begins_with("res://") else "%s%s/%s.glb" % [WEAPONS_ROOT, own, own.get_file()]
		if ResourceLoader.exists(p):
			return p
	var held := HELD.model_for(d) if str(d.get("category", "")) in ["weapon", "armour"] else ""
	if held != "" and not d.has("model"):
		var p := "%s%s/%s.glb" % [WEAPONS_ROOT, held, held.get_file()]
		if ResourceLoader.exists(p):
			return p
	var kind := kind_for(d)
	return _prop(kind, region_id) if kind != "" else ""


## The forge prop kind an item is drawn as, by RULES, or FALLBACK.
static func kind_for(d: Dictionary) -> String:
	if _res.is_empty():
		for r: Array in RULES:
			var re := RegEx.new()
			re.compile(str(r[0]))
			_res.append([re, str(r[1])])
	var id := str(d.get("id", ""))
	if str(d.get("category", "")) == "book":
		# a book is a book, unless it is a sheet: a letter, a page, a verse, a map
		var tags := str(d.get("tags", [])) + " " + id
		for w in ["letter", "page", "sheet", "verse", "scroll", "map", "note"]:
			if tags.contains(w):
				return "scroll"
		return "book"
	var text := "%s %s %s" % [id.get_slice("/", id.get_slice_count("/") - 1).replace("_", " "),
		" ".join(PackedStringArray((d.get("tags", []) as Array).map(func(t: Variant) -> String: return str(t)))),
		str(d.get("category", ""))]
	for r: Array in _res:
		if (r[0] as RegEx).search(text) != null:
			return str(r[1])
	return FALLBACK


## The purse a pile of marks lies in.
static func purse_model(region_id := "") -> String:
	return _prop("sack", region_id)


static func _prop(kind: String, region_id: String) -> String:
	if _library == null:
		_library = PropLibrary.new()
	var p := _library.resolve(kind, region_id, 0)
	if p == "" and kind != FALLBACK:
		p = _library.resolve(FALLBACK, region_id, 0)
	return p


## Stands a model up as a pickup: scaled down to MOST_M at most, its foot on the item's origin.
static func instance(path: String, most := MOST_M) -> Node3D:
	var res: Resource = load(path)
	if not res is PackedScene:
		return null
	var node := (res as PackedScene).instantiate() as Node3D
	if node == null:
		return null
	var box := _box(node, Transform3D.IDENTITY)
	var big := maxf(box.size.x, maxf(box.size.y, box.size.z))
	var s := most / big if big > most else 1.0
	node.scale = Vector3.ONE * s
	node.position.y = -box.position.y * s
	return node


static func _box(n: Node, xf: Transform3D) -> AABB:
	var box := AABB()
	var first := true
	var here := xf * (n as Node3D).transform if n is Node3D else xf
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		box = here * (n as MeshInstance3D).mesh.get_aabb()
		first = false
	for c in n.get_children():
		var b := _box(c, here)
		if b.size == Vector3.ZERO:
			continue
		box = b if first else box.merge(b)
		first = false
	return box
