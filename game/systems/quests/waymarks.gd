class_name Waymarks
extends RefCounted
## Where the tracked quest's objectives are, in the world, now (DESIGN §5.16).
##
## The user's words: "Intro quest also doesn't give a waymarker to Pilgrim's Ash, and an active
## quest should have a small hud element showing current step with distance". The compass used to
## draw every active quest's objective as a soft smudge at a place, and only where the objective
## named a place: a kill named an enemy and a `where`, which the markers never read, so the Naming's
## ash-wights had no mark at all; a talk named a person and marked the town they live in, not where
## they stood; a thing to pick up marked nothing. And the smudge was faint, the map drew one only at
## a place already found, and nothing said how far.
##
## So every current objective of the tracked quest is resolved to something that stands in the
## world, in two steps:
##
##   `anchor(quest, stage, objective)` reads the content alone: what the objective is about and
##       where that is kept. A place or point of interest; a person; foes of a kind at a place or
##       inside an interior; a thing lying somewhere; or `hidden`, only where the objective says
##       `"hidden": true` with its reason in `"hidden_why"`. The objective's own `marker`
##       ({place_id, radius}) overrides whatever its target would say. The audit
##       (tests/unit/test_waymarks.gd) asks it of every objective of every stage of every quest.
##   `locate(anchor, from, inside)` asks the live world where that is now: the person's body as
##       their day has moved it (the door of the house they are in, when they are indoors), the
##       nearest living foe of the kind where the story puts the fight, the thing where it was laid
##       down; and, when the target is in another space than the player, the door between.
##
## Nothing here is saved: the tracked quest is (QuestLog), and the rest follows from the world.

## An objective's own reach radius when it says none (QuestLog.REACH_RADIUS_M).
const PLACE_RADIUS_M := 45.0
## Within this of a person, a foe or a thing, you are there, and the distance is not shown.
const NPC_RADIUS_M := 5.0
const FOE_RADIUS_M := 6.0
const ITEM_RADIUS_M := 3.0
const DOOR_RADIUS_M := 3.0
## How far a place's foes may stand from it and still be the ones the story means, when the kill
## objective gives no radius of its own (KillPlaces.RADIUS_M).
const FOES_RADIUS_M := 140.0
## A point further out than this in x or z is an interior's pocket, not the map (PlaceRef).
const MAP_HALF_M := 4096.0

static var _homes: Dictionary = {}      # npc id -> interior id whose resident they are
static var _by_dialogue: Dictionary = {}  # dialogue id -> npc id
static var _by_stock: Dictionary = {}   # stock table id -> npc id
static var _built := false


static func reset() -> void:
	_homes.clear()
	_by_dialogue.clear()
	_by_stock.clear()
	_built = false


# --- what an objective is about ----------------------------------------------------------------

## What one objective points at, from the content alone:
##   {kind: "place", place, radius}
##   {kind: "npc", npc}
##   {kind: "escort", npc, place}                       the person, then where you take them
##   {kind: "foes", enemy, where, radius}               `where` a place/POI, or an interior
##   {kind: "item", item, key, where}                   `key` the QuestItems placement, if any
##   {kind: "interior", interior}                       somewhere inside (a shelf, a cave's hearth)
##   {kind: "hidden", why}                              the objective keeps its own counsel
##   {kind: "none", why}                                nothing stands anywhere for it (a fault)
## Every kind but hidden and none also carries `about`, the words for what it is.
static func anchor(quest: Dictionary, stage: Dictionary, o: Dictionary) -> Dictionary:
	_build()
	if bool(o.get("hidden", false)):
		return {"kind": "hidden", "why": str(o.get("hidden_why", ""))}
	var explicit: Variant = o.get("marker")
	if typeof(explicit) == TYPE_DICTIONARY and str((explicit as Dictionary).get("place_id", "")) != "":
		var m: Dictionary = explicit
		return _place(str(m["place_id"]), float(m.get("radius", PLACE_RADIUS_M)))
	var target := str(o.get("target", ""))
	var found: Dictionary = {}
	match str(o.get("type", "")):
		"reach":
			found = _place(target, float(o.get("radius", PLACE_RADIUS_M)))
		"rest_at":
			found = _rest(target)
		"talk", "deliver":
			found = _person(target)
		"escort":
			found = _person(target)
			if str(found.get("kind", "")) == "npc":
				found = {"kind": "escort", "npc": target, "place": str(o.get("place", "")), "about": _name(target)}
		"kill":
			found = _foes(o)
		"collect", "use_item":
			found = _item(target, str(quest.get("id", "")), stage, o)
		"read_book":
			found = _book(target, str(quest.get("id", "")), stage, o)
		"choice":
			found = _choice(quest, stage, o)
	if not _missing(found):
		return found
	# what the objective itself says about where, then where the same stage sends you
	for key in ["where", "place"]:
		var at := str(o.get(key, ""))
		if at != "":
			var near := _somewhere(at)
			if not _missing(near):
				return near
	var reach := QuestItems._reach_of(stage)
	if reach != "":
		return _place(reach, PLACE_RADIUS_M)
	# a lesson that says nowhere is taught where the teacher stands: the style starts' yard, butts,
	# braziers and traps had no mark on the compass at all (flow, 2026-09-27)
	if str(o.get("type", "")) == "act" and str(quest.get("giver", "")) != "":
		var teacher := _person(str(quest["giver"]))
		if not _missing(teacher):
			return teacher
	return found if not found.is_empty() else _none("nothing says where %s is" % (target if target != "" else "it"))


static func _missing(a: Dictionary) -> bool:
	return a.is_empty() or str(a.get("kind", "")) == "none"


static func _none(why: String) -> Dictionary:
	return {"kind": "none", "why": why}


## A place, a point of interest or an interior, whichever the id is.
static func _somewhere(id: String, radius := PLACE_RADIUS_M) -> Dictionary:
	match Ids.type_of(id):
		"place", "poi":
			return _place(id, radius)
		"interior":
			if ContentDB.has(id):
				return {"kind": "interior", "interior": id, "about": _name(id)}
		"npc":
			return _person(id)
	return _none("%s is nowhere on the map" % id)


static func _place(id: String, radius := PLACE_RADIUS_M) -> Dictionary:
	if PlaceRef.xz(id) == Vector2.INF:
		if Ids.type_of(id) == "interior":
			return _somewhere(id)
		return _none("%s has no position" % id)
	return {"kind": "place", "place": id, "radius": radius, "about": _name(id)}


static func _person(npc: String) -> Dictionary:
	if Ids.type_of(npc) != "npc" or not ContentDB.has(npc):
		return _none("%s is nobody in the pack" % npc)
	var def := ContentDB.get_or_empty(npc)
	var home := str(def.get("home_place", ""))
	var held := false
	for h in def.get("holds", []):
		if typeof(h) == TYPE_DICTIONARY and PlaceRef.xz(str((h as Dictionary).get("place", ""))) != Vector2.INF:
			held = true
	if PlaceRef.xz(home) == Vector2.INF and not held and not _homes.has(npc):
		return _none("%s lives nowhere on the map" % _name(npc))
	return {"kind": "npc", "npc": npc, "about": _name(npc)}


static func _rest(target: String) -> Dictionary:
	if PlaceRef.xz(target) != Vector2.INF:
		return _place(target, PLACE_RADIUS_M)
	var cave := QuestWalk.cave_hearth_interior(target)
	if cave != "":
		return {"kind": "interior", "interior": cave, "about": _name(cave)}
	return _none("no Hearthstone %s stands anywhere" % target)


static func _foes(o: Dictionary) -> Dictionary:
	var enemy := str(o.get("target", ""))
	var where := str(o.get("where", ""))
	var about := _plural_name(enemy)
	if where == "" or where == KillPlaces.ANYWHERE:
		return {"kind": "foes", "enemy": enemy, "where": "", "radius": 0.0, "about": about}
	match Ids.type_of(where):
		"interior":
			if ContentDB.has(where):
				return {"kind": "foes", "enemy": enemy, "where": where, "radius": 0.0, "about": about}
		"place", "poi":
			if PlaceRef.xz(where) != Vector2.INF:
				var found := {"kind": "foes", "enemy": enemy, "where": where, "radius": float(o.get("radius", FOES_RADIUS_M)),
						"about": about}
				# where the stage stands its foes, when that is not the place's middle (KillPlaces)
				if PlaceRef.is_spec(o.get("stand_at", null)):
					found["stand_at"] = o["stand_at"]
				return found
	return _none("the fight's place %s is nowhere" % where)


## A thing to pick up or use: where a quest lays it, else who hands it over or sells it, else a
## house or deep place it lies in.
static func _item(item: String, quest_id: String, stage: Dictionary, o: Dictionary) -> Dictionary:
	if item == "" or not ContentDB.has(item):
		return _none("%s is no item in the pack" % item)
	var best: Dictionary = {}
	for row in QuestItems.placements():
		if str(row.get("item", "")) != item:
			continue
		if best.is_empty() or str(row.get("quest_id", "")) == quest_id:
			best = row
	if not best.is_empty():
		var where := str(best["where"])
		if Ids.type_of(where) == "interior":
			return {"kind": "interior", "interior": where, "item": item, "key": str(best["key"]), "about": _name(item)}
		if PlaceRef.xz(where) != Vector2.INF:
			return {"kind": "item", "item": item, "key": str(best["key"]), "where": where, "about": _name(item)}
	for interior in QuestWalk.lying_inside(item):
		return {"kind": "interior", "interior": str(interior), "item": item, "about": _name(item)}
	for how in ItemSources.how_given(item):
		var parts := str(how).split(" ", false, 1)
		if parts.size() < 2:
			continue
		match parts[0]:
			"dialogue":
				var who := str(_by_dialogue.get(parts[1], ""))
				if who != "":
					return _person(who)
			"drop":
				if Ids.type_of(parts[1]) == "boss":
					var arena := str(ContentDB.get_or_empty(parts[1]).get("arena", ""))
					if arena != "":
						return _foes({"target": parts[1], "where": arena})
	for table in ItemSources.sold_by(item):
		var seller := str(_by_stock.get(str(table), ""))
		if seller != "":
			return _person(seller)
	# handed over by the story (a stage, a reward): whoever the stage has you speak to
	var host := QuestRoutes.host_of(ContentDB.get_or_empty(quest_id), stage, o)
	if host != "" and Ids.type_of(host) == "npc":
		return _person(host)
	return _none("nothing lays down, hands over or sells %s" % _name(item))


static func _book(book: String, quest_id: String, stage: Dictionary, o: Dictionary) -> Dictionary:
	for row in QuestItems.placements():
		if str(row.get("kind", "")) == "book" and str(row.get("book", "")) == book:
			var where := str(row["where"])
			if Ids.type_of(where) == "interior":
				return {"kind": "interior", "interior": where, "about": _name(book)}
			return {"kind": "item", "item": "", "key": str(row["key"]), "where": where, "about": _name(book)}
	for interior in QuestWalk.shelved_in(book):
		return {"kind": "interior", "interior": str(interior), "about": _name(book)}
	var reader := ItemSources.reader_of(book)
	if reader != "":
		return _item(reader, quest_id, stage, o)
	return _none("no item reads %s and no shelf keeps it" % _name(book))


static func _choice(quest: Dictionary, stage: Dictionary, o: Dictionary) -> Dictionary:
	var quest_id := str(quest.get("id", ""))
	for row in QuestItems.placements():
		if str(row.get("kind", "")) == "choice" and str(row.get("quest_id", "")) == quest_id \
				and str(row.get("stage_id", "")) == str(stage.get("id", "")):
			return _somewhere(str(row["where"]))
	var host := QuestRoutes.host_of(quest, stage, o)
	if host == "":
		return _none("nobody to decide it with")
	return _somewhere(host)


## Where an anchor is on the map from the content alone, with no world standing: a place's position,
## a person's home (or where the story holds them), the place of a fight or of the house a thing is
## in. Vector2.INF for hidden, for nothing, and for a person who lives nowhere. What the audit asks.
static func map_xz_of(a: Dictionary) -> Vector2:
	_build()
	match str(a.get("kind", "")):
		"place":
			return PlaceRef.xz(str(a["place"]))
		"npc", "escort":
			var npc := str(a["npc"])
			var def := ContentDB.get_or_empty(npc)
			var home := PlaceRef.xz(str(def.get("home_place", "")))
			if home != Vector2.INF:
				return home
			for h in def.get("holds", []):
				if typeof(h) == TYPE_DICTIONARY:
					var held := PlaceRef.xz(str((h as Dictionary).get("place", "")))
					if held != Vector2.INF:
						return held
			if _homes.has(npc):
				return map_xz_of({"kind": "interior", "interior": str(_homes[npc])})
		"foes":
			var where := str(a.get("where", ""))
			if Ids.type_of(where) == "interior":
				return map_xz_of({"kind": "interior", "interior": where})
			return PlaceRef.xz(where)
		"item":
			return PlaceRef.xz(str(a.get("where", "")))
		"interior":
			return PlaceRef.xz(str(ContentDB.get_or_empty(str(a["interior"])).get("place", "")))
	return Vector2.INF


## Every objective of every authored quest and where it points: [{quest_id, stage_id, index, type,
## target, kind, xz, why}], `xz` Vector2.INF where it points nowhere. The audit's walk (and the
## console's report).
static func audit() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var quests := ContentDB.all("quest")
	quests.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return str(x["id"]) < str(y["id"]))
	for def in quests:
		if str(def.get("layer", "")) == "radiant":
			continue
		for stage_v in def.get("stages", []):
			var stage: Dictionary = stage_v
			var objs: Array = stage.get("objectives", [])
			for i in objs.size():
				var o: Dictionary = objs[i]
				var a := anchor(def, stage, o)
				out.append({"quest_id": str(def["id"]), "stage_id": str(stage.get("id", "")), "index": i,
						"type": str(o.get("type", "")), "target": str(o.get("target", "")), "kind": str(a.get("kind", "")),
						"xz": map_xz_of(a), "why": str(a.get("why", ""))})
	return out


# --- where that is now ---------------------------------------------------------------------------

## Where an anchor is in the live world, seen from `from` (the player's feet) in the space
## `inside` ("" the open country, else the interior the player is in):
##   {ok, at: Vector3 (in the player's own space), map_xz: Vector2 (on the chart), radius,
##    door: bool (at is a door between spaces), live: bool (a body or a thing, not a place)}
## ok is false for a hidden or unresolvable anchor, or a person the story has taken away.
static func locate(a: Dictionary, from: Vector3 = Vector3.INF, inside := "") -> Dictionary:
	var target := _target(a, from, inside)
	if not bool(target.get("ok", false)):
		return target
	var space := str(target.get("space", ""))
	var at: Vector3 = target["at"]
	if not at.is_finite():
		return {"ok": false, "why": "%s stands nowhere" % str(a.get("about", "it"))}
	var map_xz := Vector2(at.x, at.z) if space == "" else _outside_of(space)
	if space == inside:
		return {"ok": true, "at": at, "map_xz": map_xz, "radius": float(target["radius"]), "door": false,
				"live": bool(target.get("live", false))}
	# in another space from the player's: the way through
	var door := _exit_door(inside) if inside != "" else _door_of(space)
	if door == Vector3.INF:
		return {"ok": false, "why": "no way from %s to %s" % [inside, space]}
	return {"ok": true, "at": door, "map_xz": map_xz, "radius": DOOR_RADIUS_M, "door": true, "live": false}


## {ok, at, space, radius, live}: the anchor itself, in whichever space it is.
static func _target(a: Dictionary, from: Vector3, inside: String) -> Dictionary:
	match str(a.get("kind", "")):
		"place":
			var p := WorldProbe.place_position(str(a["place"]))
			return {"ok": true, "at": p, "space": "", "radius": float(a.get("radius", PLACE_RADIUS_M))}
		"npc":
			return _person_now(str(a["npc"]))
		"escort":
			var reg := NpcRegistry.instance
			if reg != null and is_instance_valid(reg) and reg.is_escorted(str(a["npc"])) and str(a.get("place", "")) != "":
				return _target({"kind": "place", "place": str(a["place"]), "radius": PLACE_RADIUS_M}, from, inside)
			return _person_now(str(a["npc"]))
		"foes":
			return _foes_now(a, from, inside)
		"item":
			var node := _item_node(str(a.get("key", "")))
			if node != null:
				return {"ok": true, "at": node.global_position, "space": _space_of(node), "radius": ITEM_RADIUS_M, "live": true}
			return _target({"kind": "place", "place": str(a["where"]), "radius": PLACE_RADIUS_M}, from, inside)
		"interior":
			var interior := str(a["interior"])
			if inside == interior:
				var thing := _item_node(str(a.get("key", "")))
				if thing != null:
					return {"ok": true, "at": thing.global_position, "space": interior, "radius": ITEM_RADIUS_M, "live": true}
				var root := _interior_root(interior)
				if root != null:
					return {"ok": true, "at": root.global_position, "space": interior, "radius": 12.0}
			return {"ok": true, "at": _door_of(interior), "space": interior, "radius": DOOR_RADIUS_M}
	return {"ok": false, "why": str(a.get("why", "hidden"))}


## A person where their day has put them: their body if it is stood up (in the open, or in the
## interior the player is in), the door of their house when they are indoors, the road when they
## are on it, else the place their day has them at.
static func _person_now(npc: String) -> Dictionary:
	var reg := NpcRegistry.instance
	if reg == null or not is_instance_valid(reg):
		var home := str(ContentDB.get_or_empty(npc).get("home_place", ""))
		return {"ok": PlaceRef.xz(home) != Vector2.INF, "at": WorldProbe.place_position(home), "space": "",
				"radius": NPC_RADIUS_M, "why": "%s lives nowhere" % npc}
	if reg.is_gone(npc) or not reg.is_alive(npc):
		return {"ok": false, "why": "%s is not in the world" % npc}
	var body := reg.actor(npc) as Node3D
	if body != null and body.is_inside_tree():
		return {"ok": true, "at": body.global_position, "space": _space_of(body), "radius": NPC_RADIUS_M, "live": true}
	if reg.is_indoors(npc) and _homes.has(npc):
		return {"ok": true, "at": _door_of(str(_homes[npc])), "space": str(_homes[npc]), "radius": NPC_RADIUS_M}
	for p: Vector3 in [reg.escort_position(npc), reg.road_position(npc)]:
		if p != Vector3.INF:
			return {"ok": true, "at": p, "space": "", "radius": NPC_RADIUS_M}
	var place := reg.place_of(npc)
	var marker := reg.spot_marker(npc)
	if marker != null:
		return {"ok": true, "at": marker.global_position, "space": "", "radius": NPC_RADIUS_M}
	if PlaceRef.xz(place) == Vector2.INF:
		return {"ok": false, "why": "%s is at no place" % npc}
	return {"ok": true, "at": WorldProbe.place_position(place), "space": "", "radius": PLACE_RADIUS_M}


## The nearest living foe of the kind where the story puts the fight; the place itself (or the
## interior's door) while none stands.
static func _foes_now(a: Dictionary, from: Vector3, inside: String) -> Dictionary:
	var enemy := str(a.get("enemy", ""))
	var where := str(a.get("where", ""))
	var in_interior := Ids.type_of(where) == "interior"
	var centre := Vector3.INF if in_interior or where == "" else WorldProbe.place_position(where)
	var radius := float(a.get("radius", FOES_RADIUS_M))
	var best: Node3D = null
	var best_d := INF
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		for node in tree.get_nodes_in_group("enemy"):
			var e := node as Node3D
			if e == null or not e.is_inside_tree() or e.is_queued_for_deletion() or e.get("dead") == true:
				continue
			var id := str(e.call("content_id")) if e.has_method("content_id") else ""
			if not _is_kind(enemy, id):
				continue
			var space := _space_of(e)
			if in_interior:
				if space != where:
					continue
			elif space != "":
				continue
			elif centre != Vector3.INF and _flat(e.global_position, centre) > radius:
				continue
			elif centre == Vector3.INF and from != Vector3.INF and _flat(e.global_position, from) > FOES_RADIUS_M * 2.0:
				continue
			var d := e.global_position.distance_to(from) if from != Vector3.INF and space == inside else 0.0
			if d < best_d:
				best_d = d
				best = e
	if best != null:
		return {"ok": true, "at": best.global_position, "space": _space_of(best), "radius": FOE_RADIUS_M, "live": true}
	if in_interior:
		return _target({"kind": "interior", "interior": where}, from, inside)
	if centre == Vector3.INF:
		return {"ok": false, "why": "no %s stands near" % enemy}
	# none standing yet: where the stage will stand them (the Choir's is its colossus, and they
	# stand ahead of it on the way in), else the place
	if a.has("stand_at"):
		var at := PlaceRef.point_xz(a["stand_at"])
		if at != Vector2.INF:
			return {"ok": true, "at": Vector3(at.x, WorldProbe.get_height(at.x, at.y, centre.y), at.y), "space": "",
					"radius": FOE_RADIUS_M * 3.0}
	return {"ok": true, "at": centre, "space": "", "radius": radius}


## "" for the open country, else the interior a node stands in: the pocket it is loaded into says
## (KillPlaces.interior_of), and a person the streamer stood up inside is in the pocket the player is.
static func _space_of(node: Node3D) -> String:
	var named := KillPlaces.interior_of(node)
	if named != "":
		return named
	var p := node.global_position
	if absf(p.x) > MAP_HALF_M or absf(p.z) > MAP_HALF_M:
		return str(GameState.current_interior_id)
	return ""


## Where an interior is on the chart: its door where it stands, else its place.
static func _outside_of(interior: String) -> Vector2:
	var door := _door_of(interior)
	return Vector2(door.x, door.z)


## The way into an interior from the open country: its door, where the world stood one; else the
## place it belongs to.
static func _door_of(interior: String) -> Vector3:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		for node in tree.get_nodes_in_group("door"):
			var d := node as Node3D
			if d == null or not d.is_inside_tree() or d.get("is_exit") == true or str(d.get("interior_id")) != interior:
				continue
			if absf(d.global_position.x) <= MAP_HALF_M and absf(d.global_position.z) <= MAP_HALF_M:
				return d.global_position
	var place := str(ContentDB.get_or_empty(interior).get("place", ""))
	return WorldProbe.place_position(place) if PlaceRef.xz(place) != Vector2.INF else Vector3.INF


## The way out of the interior the player is in.
static func _exit_door(interior: String) -> Vector3:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return Vector3.INF
	var root := _interior_root(interior)
	for node in tree.get_nodes_in_group("door"):
		var d := node as Node3D
		if d == null or not d.is_inside_tree() or d.get("is_exit") != true:
			continue
		if KillPlaces.interior_of(d) == interior or (root != null and root.is_ancestor_of(d)):
			return d.global_position
	return root.global_position if root != null else Vector3.INF


static func _interior_root(interior: String) -> Node3D:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	for node in tree.get_nodes_in_group("interior_root"):
		if node is Node3D and str((node as Node3D).get_meta("interior_id", "")) == interior:
			return node as Node3D
	return null


## The thing QuestItems laid down under a key, while it stands.
static func _item_node(key: String) -> Node3D:
	if key == "":
		return null
	var tree := Engine.get_main_loop() as SceneTree
	var items := tree.get_first_node_in_group(QuestItems.GROUP) as QuestItems if tree != null else null
	if items == null or not items.has_method("standing_node"):
		return null
	return items.standing_node(key) as Node3D


## Whether an enemy of this id is what an objective asks for: "" and "any" are anything, "tag:x"
## anything carrying the tag (QuestLog's own reading).
static func _is_kind(target: String, id: String) -> bool:
	if target == "" or target == "any":
		return true
	if target.begins_with("tag:"):
		return (ContentDB.get_or_empty(id).get("tags", []) as Array).has(target.substr(4))
	return target == id


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --- words ---------------------------------------------------------------------------------------

static func _name(id: String) -> String:
	var def := ContentDB.get_or_empty(id)
	return str(def.get("name", def.get("title", Ids.name_of(id).replace("_", " "))))


## What a kind is called, several of them, in running text: "ash-wights", "hearth loaves". A def's
## own `plural` wins.
static func _plural_name(id: String) -> String:
	if id == "" or id == "any":
		return "foes"
	if id.begins_with("tag:"):
		return plural(id.substr(4).replace("_", " "))
	var def := ContentDB.get_or_empty(id)
	if def.has("plural"):
		return str(def["plural"])
	return plural(_name(id).to_lower())


const _SAME := ["drowned", "sheep", "deer", "fish", "folk", "kin", "salmon", "trout", "grey", "dead"]
const _VES := {"wolf": "wolves", "loaf": "loaves", "knife": "knives", "leaf": "leaves", "thief": "thieves",
		"half": "halves", "shelf": "shelves", "elf": "elves", "calf": "calves", "wife": "wives", "life": "lives"}


## The plural of a name in lower case, by the last word: "ash-wight" -> "ash-wights", "down wolf"
## -> "down wolves", "bog-drowned" -> "bog-drowned", "hearth loaf" -> "hearth loaves".
static func plural(name: String) -> String:
	var s := name.strip_edges()
	if s == "":
		return s
	var cut := maxi(s.rfind(" "), s.rfind("-"))
	var head := s.substr(0, cut + 1)
	var word := s.substr(cut + 1)
	var lower := word.to_lower()
	if _SAME.has(lower):
		return s
	if _VES.has(lower):
		return head + str(_VES[lower])
	if lower.ends_with("man") and lower.length() > 3:
		return head + word.substr(0, word.length() - 3) + "men"
	if lower.ends_with("s") or lower.ends_with("x") or lower.ends_with("z") or lower.ends_with("ch") or lower.ends_with("sh"):
		return head + word + "es"
	if lower.ends_with("y") and lower.length() > 1 and not "aeiou".contains(lower[lower.length() - 2]):
		return head + word.substr(0, word.length() - 1) + "ies"
	return head + word + "s"


# --- the tables read once ----------------------------------------------------------------------

static func _build() -> void:
	if _built:
		return
	_built = true
	for def in ContentDB.all("interior"):
		var who := str(def.get("resident", def.get("resident_npc", "")))
		if who != "" and not _homes.has(who):
			_homes[who] = str(def.get("id", ""))
	for def in ContentDB.all("npc"):
		var id := str(def.get("id", ""))
		var dialogue := str(def.get("dialogue", ""))
		if dialogue != "" and not _by_dialogue.has(dialogue):
			_by_dialogue[dialogue] = id
		var merchant: Variant = def.get("merchant", {})
		if typeof(merchant) == TYPE_DICTIONARY:
			var stock := str((merchant as Dictionary).get("stock", ""))
			if stock != "" and not _by_stock.has(stock):
				_by_stock[stock] = id
