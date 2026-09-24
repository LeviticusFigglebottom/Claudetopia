class_name Wards
extends RefCounted
## Ground a kind of foe will not cross.
##
## The Singing Yew's sentence is "safe ground; a place to lure barrow-wights and watch them turn
## away", and its story says why: a Tamwick child hung a bell in a sapling, the tree ate it in
## three hundred years, and the hedge-wights from the barrow will not pass it. A point of interest
## whose def carries a `ward` ({"radius_m": 8, "keeps_off": ["undead"]}) puts one down with its
## dressing, and it goes when the dressing does. A foe with any of the tags a ward keeps off does
## not follow its quarry onto that ground: while whoever it is chasing stands inside, it turns for
## home (`Brain`, "warded"), and it does not step across the edge of its own accord either.

static var _wards: Array = []   # {owner: WeakRef, centre: Vector3, radius: float, keeps_off: Array}


## A ward of `radius` metres round `centre` (world), keeping off foes with any of `keeps_off`
## among their tags, for as long as `owner` stands.
static func add(owner: Node, centre: Vector3, radius: float, keeps_off: Array) -> void:
	_prune()
	_wards.append({"owner": weakref(owner), "centre": centre, "radius": radius, "keeps_off": keeps_off.duplicate()})


static func clear() -> void:
	_wards.clear()


static func count() -> int:
	_prune()
	return _wards.size()


## The ward that keeps a foe with `tags` off `point`, or {} when none does.
static func keeping(tags: Array, point: Vector3) -> Dictionary:
	if _wards.is_empty() or tags.is_empty():
		return {}
	for w_v in _wards:
		var w: Dictionary = w_v
		var owner: Object = (w["owner"] as WeakRef).get_ref()
		if owner == null:
			continue
		if not _keeps(w, tags):
			continue
		var c: Vector3 = w["centre"]
		if Vector2(point.x - c.x, point.z - c.z).length() <= float(w["radius"]):
			return w
	return {}


## Whether a step from `from` to `to` would take a foe with `tags` onto ground a ward keeps it off:
## into a ward, or deeper into one it is already standing in.
static func bars(tags: Array, from: Vector3, to: Vector3) -> bool:
	var w := keeping(tags, to)
	if w.is_empty():
		return false
	var c: Vector3 = w["centre"]
	var before := Vector2(from.x - c.x, from.z - c.z).length()
	var after := Vector2(to.x - c.x, to.z - c.z).length()
	return after < before


static func _keeps(w: Dictionary, tags: Array) -> bool:
	for t in w["keeps_off"]:
		if tags.has(t):
			return true
	return false


static func _prune() -> void:
	var kept: Array = []
	for w in _wards:
		if ((w as Dictionary)["owner"] as WeakRef).get_ref() != null:
			kept.append(w)
	_wards = kept
