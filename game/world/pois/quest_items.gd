class_name QuestItems
extends Node
## The things a quest says are lying somewhere, lying there.
##
## Fourteen quests sent you for something nothing in the game gave, sold or put anywhere — the
## tine in the crown of the Toll, the hand-bell in the Tumbled Watch's fallen stair, a sliver
## chipped off the Lamp, the Ledger of Prices in a room behind a bell: eighteen `collect` and
## `read_book` objectives waited for an event that could only come from an item that did not
## exist, or (the forged chit) from a cutpurse's pocket if the dice fell that way.
## This puts them down, the way the Hearthstones and the dressing are put down: at stream time,
## deterministically, at the place the quest names, and in the cell node so they unload with it.
##
## **What is placed.** An item a `collect` or `use_item` objective asks for, or the item that
## reads the book a `read_book` objective asks for — unless the story already hands it over (a
## line of dialogue gives it, a stage or a reward gives it, a boss drops it), or somebody sells
## it, in which case that is the way to it. An objective's own `where` places its item whatever
## else provides it, because the quest has said where it lies.
##
## **Where.** The objective's `where` (a place, a point of interest, or an interior), else the
## item def's own `where`, else the place the same stage sends you to (`reach`). A `spot` names a
## marker in the dressing (the Tumbled Watch's `fallen_stair`), a chamber of a deep place, or a
## room of a house; without one the thing lies a few paces off the middle, the same few paces
## every time. `owner` makes taking it theft; in a house the resident owns it.
##
## **Decisions with nobody to decide them with.** A `choice` whose `with` names a place rather
## than a person — the note at the Cantor's Seat, whose holder is dead — gets a `ChoicePoint`
## there instead, which puts the open options when you walk up to it.
##
## **What the forge put in the caves.** A deep place's meta names `item` features (cold flour in
## the mill cellar); they were props with the item written on them as a note, and nothing could
## pick one up. They are pickups now, except a boss's own drop, which the boss still drops, and
## one whose item no def exists for (Hollin Barrow's roll fragment), which stays a prop.
##
## Picked-up state is the `quest_items` save section: the keys of everything taken, so a thing
## taken stays taken across streaming, reloads and saves.

const GROUP := "quest_items"
const SECTION := "quest_items"
const PADS_PATH := "res://world/generated/pois.json"

## How far off the middle of a place a thing without a spot lies.
const RING_MIN_M := 3.0
const RING_MAX_M := 9.0
## How a thing without a spot finds open ground when the first spot is shut in (`_open`): this
## many tries, a step further out every four, a crouching body's room, and how high the sky is
## looked for.
const OPEN_TRIES := 32
const OPEN_STEP_M := 3.0
const OPEN_R := 0.3
const OPEN_H := 1.2
const OPEN_SKY_M := 80.0

static var _placements: Array[Dictionary] = []
static var _unplaced: Array[Dictionary] = []
static var _built := false

var taken: Dictionary = {}          # key -> true
var _placed: Dictionary = {}        # key -> Node (while it stands)


static func ensure() -> QuestItems:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var found := tree.get_first_node_in_group(GROUP)
	if found is QuestItems:
		return found as QuestItems
	var made := QuestItems.new()
	made.name = "QuestItems"
	var host: Node = tree.current_scene if tree.current_scene != null else tree.root
	host.add_child(made)
	return made


func _enter_tree() -> void:
	add_to_group(GROUP)


func _ready() -> void:
	SaveSystem.register(SECTION, self)
	var pending := SaveSystem.take_pending(SECTION)
	if not pending.is_empty():
		from_save(pending)
	# The world services are installed when the body stands up, and cells near it were built
	# before that; what should lie in them is put down now.
	call_deferred("raise_in_loaded_cells")


func _exit_tree() -> void:
	if SaveSystem.participants.get(SECTION) == self:
		SaveSystem.unregister(SECTION)


# --- what the pack asks for -------------------------------------------------------------------------

## Every placement: [{key, kind: "item"|"choice", item, count, where, spot, owner, quest_id,
## stage_id, index, text}]. Built once from the content pack.
static func placements() -> Array[Dictionary]:
	_build()
	return _placements


## Objectives whose thing has no source and no place to lie: [{quest_id, stage_id, item, why}].
static func unplaced() -> Array[Dictionary]:
	_build()
	return _unplaced


static func reset() -> void:
	_placements.clear()
	_unplaced.clear()
	_built = false


static func _build() -> void:
	if _built:
		return
	_built = true
	var seen: Dictionary = {}
	var quests := ContentDB.all("quest")
	quests.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	for def in quests:
		if str(def.get("layer", "")) == "radiant":
			continue
		var stages: Array = def.get("stages", [])
		for si in stages.size():
			var stage: Dictionary = stages[si]
			var objectives: Array = stage.get("objectives", [])
			for oi in objectives.size():
				var o: Dictionary = objectives[oi]
				var row := _placement_for(def, stage, o, oi)
				if row.is_empty():
					continue
				if seen.has(row["key"]):
					continue
				seen[row["key"]] = true
				if str(row.get("where", "")) == "":
					_unplaced.append({"quest_id": str(def["id"]), "stage_id": str(stage.get("id", "")),
							"item": str(row.get("item", "")), "why": "the quest does not say where it lies"})
					continue
				_placements.append(row)
	# What a place's own sentence says lies there, from its encounter def's `lies`: the chart of
	# the Salt Isles in the Reed Wreck, which you can take, and the hermit's exercise book on
	# Willow Isle, which is read where it lies.
	var encounters := ContentDB.all("encounter")
	encounters.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	for def in encounters:
		var place := str(def.get("place", ""))
		for l in def.get("lies", []):
			if typeof(l) != TYPE_DICTIONARY or place == "":
				continue
			var lying: Dictionary = l
			var item := str(lying.get("item", ""))
			var book := str(lying.get("book", ""))
			var what := item if item != "" else book
			if what == "" or not ContentDB.has(what):
				continue
			var key := "lies:%s|%s" % [place, what]
			if seen.has(key):
				continue
			seen[key] = true
			_placements.append({"key": key, "kind": "item" if item != "" else "book", "item": item, "book": book,
					"count": maxi(1, int(lying.get("count", 1))), "where": place, "spot": str(lying.get("at", "")),
					"owner": str(lying.get("owner", "")), "quest_id": "", "stage_id": "", "index": -1, "text": ""})


static func _placement_for(def: Dictionary, stage: Dictionary, o: Dictionary, index: int) -> Dictionary:
	var type := str(o.get("type", ""))
	var explicit := str(o.get("where", ""))
	var item := ""
	match type:
		"collect", "use_item":
			item = str(o.get("target", ""))
		"read_book":
			if bool(o.get("in_place", false)):
				return _book_in_place(def, stage, o, index)
			item = ItemSources.reader_of(str(o.get("target", "")))
			if item == "" or ItemSources.on_a_shelf(str(o.get("target", ""))):
				return {}
		"choice":
			var host := str(o.get("with", ""))
			if host == "" or Ids.type_of(host) == "npc" or QuestRoutes.dialogue_offers(str(def["id"]), o):
				return {}
			return {"key": "choice:%s|%s" % [str(def["id"]), str(stage.get("id", ""))], "kind": "choice",
					"where": host, "spot": str(o.get("spot", "")), "quest_id": str(def["id"]),
					"stage_id": str(stage.get("id", "")), "index": index, "text": str(o.get("text", "")),
					"item": "", "count": 1, "owner": ""}
		_:
			return {}
	if item == "" or not ContentDB.has(item):
		return {}
	if explicit == "" and (ItemSources.story_gives(item) or ItemSources.sold(item)):
		return {}
	var where := explicit
	if where == "":
		where = str(ContentDB.get_or_empty(item).get("where", ""))
	if where == "":
		where = _reach_of(stage)
	var count := maxi(1, int(o.get("count", 1))) if type == "collect" else 1
	return {"key": "item:%s" % item, "kind": "item", "item": item, "count": count, "where": where,
			"spot": str(o.get("spot", "")), "owner": str(o.get("owner", "")), "quest_id": str(def["id"]),
			"stage_id": str(stage.get("id", "")), "index": index, "text": ""}


## A book an objective asks you to read where it lies (`in_place`): a board hung inside a tower
## door, the names cut in a cairn, a ledger chained in the counting room. The book itself is laid
## down, fixed, at the objective's `where` (and `spot`), else where the same stage sends you, and
## reading it there is what closes the objective (`Readable` says `book_opened`). It is never
## taken, so it is never in the save.
static func _book_in_place(def: Dictionary, stage: Dictionary, o: Dictionary, index: int) -> Dictionary:
	var book := str(o.get("target", ""))
	if not ContentDB.has(book):
		return {}
	var where := str(o.get("where", ""))
	if where == "":
		where = _reach_of(stage)
	return {"key": "book:%s|%s" % [book, where], "kind": "book", "item": "", "book": book, "count": 1,
			"where": where, "spot": str(o.get("spot", "")), "owner": "", "quest_id": str(def["id"]),
			"stage_id": str(stage.get("id", "")), "index": index, "text": ""}


## The place or point of interest the same stage sends you to, which is where its thing lies.
static func _reach_of(stage: Dictionary) -> String:
	for o in stage.get("objectives", []):
		var other: Dictionary = o
		var t := str(other.get("target", ""))
		if str(other.get("type", "")) == "reach" and (Ids.type_of(t) == "place" or Ids.type_of(t) == "poi"):
			return t
	return ""


## The placements lying in the open (a place or a point of interest), not inside anything.
static func _outdoors() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in placements():
		var t := Ids.type_of(str(row["where"]))
		if t == "place" or t == "poi":
			out.append(row)
	return out


# --- the open country ------------------------------------------------------------------------------

## Puts down what lies in one cell, parented to the cell node so it unloads with it. Called by
## `WorldPois` as the streamer builds a near cell.
func raise_in_cell(parent: Node3D, cell: Vector2i) -> Array[Node]:
	var out: Array[Node] = []
	for row in _outdoors():
		var key := str(row["key"])
		if taken.has(key) or _standing(key):
			continue
		var base := _position_of(str(row["where"]))
		if base == Vector3.INF or WorldProbe.cell_of(base) != cell:
			continue
		var at := _spot_in_the_open(parent, row, base)
		var node := _make(row)
		if node == null:
			continue
		parent.add_child(node)
		(node as Node3D).global_position = at
		_placed[key] = node
		out.append(node)
	return out


## The near cells already standing when this node arrived.
func raise_in_loaded_cells() -> void:
	var world := World.instance
	if world == null or world.streamer == null:
		return
	for child in world.streamer.get_children():
		var n := str(child.name)
		if not n.begins_with("Cell_") or child.is_queued_for_deletion() or not (child is Node3D):
			continue
		if int(child.get_meta("ring", 99)) > world.streamer.full_ring:
			continue
		var parts := n.split("_")
		if parts.size() == 3:
			raise_in_cell(child as Node3D, Vector2i(int(parts[1]), int(parts[2])))


## Where a place's pad is: the built `pois.json`, read straight off disk the way `WorldPois` and
## `PlaceDiscovery` read it, so this answers the same with or without a world in the tree; the
## content's own [x, z] when the place has no pad.
func _position_of(where: String) -> Vector3:
	var pad := _pad_of(where)
	if pad != Vector3.INF:
		return pad
	var def := ContentDB.get_or_empty(where)
	if not def.has("position"):
		return Vector3.INF
	return WorldProbe.place_position(where)


static var _pads: Dictionary = {}

static func _pad_of(id: String) -> Vector3:
	if _pads.is_empty() and FileAccess.file_exists(PADS_PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PADS_PATH))
		if typeof(parsed) == TYPE_ARRAY:
			for e in parsed:
				if typeof(e) == TYPE_DICTIONARY and (e as Dictionary).has("pos"):
					var p: Array = e["pos"]
					_pads[str(e.get("place_id", ""))] = Vector3(float(p[0]), float(p[1]), float(p[2]))
	return _pads.get(id, Vector3.INF)


## A marker the dressing put down under the spot's name, if the place is dressed and has one: a
## thing with a marker lies exactly on it. Otherwise the same few paces off the middle every time,
## on open ground: the first spot tried is the one the key gives, and one that is shut in is passed
## over for the next, round and outward (`_open`). A dressing's collision is a hollow shell, so
## without the asking a note at Hound Watch lay inside a boulder and one at Hanging Falls under
## thirteen metres of rock. The same thing lands in the same place every load: the tries follow
## from the key and from what the dressing built, not from when it was asked.
##
## The asking is the physics space's, so it sees only colliders already standing: WorldPois puts
## the dressing up before it asks for the cell's finds. A find raised with no dressing in the tree
## takes the first spot, as everything did before.
func _spot_in_the_open(parent: Node3D, row: Dictionary, base: Vector3) -> Vector3:
	var spot := str(row.get("spot", ""))
	if spot != "":
		for dressing in parent.get_children():
			if dressing is PoiDressing and (dressing as PoiDressing).poi_id == str(row["where"]):
				var marker := (dressing as Node).find_child(spot, true, false)
				if marker is Node3D:
					return (marker as Node3D).global_position
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(str(row["key"]).hash())
	var angle := rng.randf() * TAU
	var reach := _landmark_reach(parent, base)
	var radius := reach + rng.randf_range(RING_MIN_M, RING_MAX_M) if reach > 0.0 else rng.randf_range(RING_MIN_M, RING_MAX_M)
	var first := _ground_at(base, angle, radius)
	var space := parent.get_world_3d().direct_space_state if parent.is_inside_tree() else null
	if space == null:
		return first
	for k in OPEN_TRIES:
		# the golden angle, so no two tries fall on one line, and a step outward every few
		var at := first if k == 0 else _ground_at(base, angle + float(k) * 2.39996, radius + OPEN_STEP_M * floorf(float(k) / 4.0))
		if _open(space, at):
			return at
	return first


static func _ground_at(base: Vector3, angle: float, radius: float) -> Vector3:
	var at := base + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
	at.y = WorldProbe.get_height(at.x, at.z, base.y) + 0.05
	return at


## Room to stoop for a thing, and sky over it: a capsule the size of a crouching body touches
## nothing solid, and a ball as wide, let down from high over the spot, comes down to it. A hollow
## shell passes the first and not the second.
static func _open(space: PhysicsDirectSpaceState3D, at: Vector3) -> bool:
	var body := CapsuleShape3D.new()
	body.radius = OPEN_R
	body.height = OPEN_H
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = body
	q.collision_mask = 1 << 0
	q.transform = Transform3D(Basis.IDENTITY, at + Vector3(0.0, 0.2 + OPEN_H * 0.5, 0.0))
	if not space.intersect_shape(q, 1).is_empty():
		return false
	var ball := SphereShape3D.new()
	ball.radius = OPEN_R
	var fall := PhysicsShapeQueryParameters3D.new()
	fall.shape = ball
	fall.collision_mask = 1 << 0
	fall.transform = Transform3D(Basis.IDENTITY, at + Vector3(0.0, OPEN_SKY_M, 0.0))
	fall.motion = Vector3(0.0, 0.2 + OPEN_H + OPEN_R - OPEN_SKY_M, 0.0)
	var way := space.cast_motion(fall)
	return way.size() < 2 or way[0] >= 1.0


## How far a landmark standing on this spot reaches out from it: a thing that lies at the Cracked
## Toll lies by the bell, not inside it. Read off the landmark's own meshes in the cell; 0 when
## nothing stands there.
static func _landmark_reach(parent: Node3D, base: Vector3) -> float:
	var reach := 0.0
	for child in parent.get_children():
		if not (child is Node3D) or child is PoiDressing or child is WorldItem or child is ChoicePoint:
			continue
		var n3 := child as Node3D
		if Vector2(n3.global_position.x - base.x, n3.global_position.z - base.z).length() > 3.0:
			continue
		for mesh in n3.find_children("*", "MeshInstance3D", true, false):
			var mi := mesh as MeshInstance3D
			if mi.mesh == null:
				continue
			var box := mi.global_transform * mi.get_aabb()
			for corner in [box.position, box.end, Vector3(box.position.x, 0.0, box.end.z), Vector3(box.end.x, 0.0, box.position.z)]:
				var c: Vector3 = corner
				reach = maxf(reach, Vector2(c.x - base.x, c.z - base.z).length())
	return minf(reach, 60.0)


# --- inside -------------------------------------------------------------------------------------------

## Puts down what lies inside one interior: its quest items, its decision points, and the
## pickups the forge named in a deep place's meta. `root` is the interior's own node; positions
## are in its space. `features_at` gives a cave feature's position (the cave builder knows how).
func raise_in_interior(root: Node3D, interior_id: String, meta: Dictionary, features_at: Callable = Callable()) -> Array[Node]:
	var out: Array[Node] = []
	var resident := str(ContentDB.get_or_empty(interior_id).get("resident", ""))
	for row in placements():
		if str(row["where"]) != interior_id:
			continue
		var key := str(row["key"])
		if taken.has(key) or _standing(key):
			continue
		var node := _make(row)
		if node == null:
			continue
		if node is WorldItem and str(row.get("owner", "")) == "" and Ids.type_of(resident) == "npc":
			(node as WorldItem).owner_npc = resident
		root.add_child(node)
		(node as Node3D).position = spot_inside(meta, str(row.get("spot", "")), key)
		_placed[key] = node
		out.append(node)
	if features_at.is_valid():
		out.append_array(_raise_features(root, interior_id, meta, features_at))
	return out


## Where inside a thing lies: the named chamber's floor or room's middle; otherwise a deep
## place's treasure chamber, or a house's hearth room, which every house has.
static func spot_inside(meta: Dictionary, spot: String, key: String) -> Vector3:
	var chambers: Dictionary = meta.get("chambers", {})
	if not chambers.is_empty():
		var ch: Dictionary = chambers.get(spot, {})
		if ch.is_empty():
			for id in chambers:
				if str((chambers[id] as Dictionary).get("role", "")) == "treasure":
					ch = chambers[id]
		if ch.is_empty():
			ch = chambers[chambers.keys()[chambers.size() - 1]]
		var points: Array = ch.get("floor_points", [])
		if not points.is_empty():
			var p: Array = points[abs(key.hash()) % points.size()]
			return Vector3(float(p[0]), float(p[1]), float(p[2]))
		var c: Array = ch.get("centre", [0, 0, 0])
		return Vector3(float(c[0]), float(c[1]), float(c[2]))
	var rooms: Array = meta.get("rooms", [])
	var room: Dictionary = {}
	for r in rooms:
		if str((r as Dictionary).get("id", "")) == spot:
			room = r
	if room.is_empty():
		for r in rooms:
			if str((r as Dictionary).get("kind", "")) == "hearth_room":
				room = r
	if room.is_empty() and not rooms.is_empty():
		room = rooms[0]
	var centre: Array = room.get("centre", [0, 0, 0])
	return Vector3(float(centre[0]) + 0.4, float(room.get("floor_y", centre[1])) + 0.05, float(centre[2]) + 0.3)


func _raise_features(root: Node3D, interior_id: String, meta: Dictionary, features_at: Callable) -> Array[Node]:
	var out: Array[Node] = []
	var place := str(ContentDB.get_or_empty(interior_id).get("place", ""))
	for f_v in meta.get("features", []):
		var f: Dictionary = f_v
		if str(f.get("kind", "")) != "item":
			continue
		var item := str(f.get("item", ""))
		if item == "" or not ContentDB.has(item) or ItemSources.boss_drops_at(item, place):
			continue
		var key := "feature:%s:%s" % [interior_id, item]
		if taken.has(key) or _standing(key):
			continue
		var pickup := WorldItem.new()
		pickup.setup(item, 1)
		pickup.visual_path = str(f.get("asset", ""))
		pickup.bob = false
		pickup.name = "Pickup_" + Ids.name_of(item)
		pickup.picked_up.connect(_on_taken.bind(key))
		root.add_child(pickup)
		pickup.position = features_at.call(f)
		_placed[key] = pickup
		out.append(pickup)
	return out


# --- making things ------------------------------------------------------------------------------------

func _make(row: Dictionary) -> Node:
	var key := str(row["key"])
	if str(row["kind"]) == "choice":
		var point := ChoicePoint.new()
		point.quest_id = str(row["quest_id"])
		point.stage_id = str(row["stage_id"])
		point.objective_index = int(row["index"])
		point.prompt = str(row.get("text", ""))
		point.speaker = str(ContentDB.get_or_empty(str(row["where"])).get("name", ""))
		point.name = "Choice_" + Ids.name_of(str(row["quest_id"]))
		return point
	if str(row["kind"]) == "book":
		# read where it lies: never taken, so never in the save
		var readable := Readable.new()
		readable.book_id = str(row["book"])
		readable.fixed = true
		readable.name = "Book_" + Ids.name_of(str(row["book"]))
		# on a marker the dressing shows what lies there; in the open it would be a prompt in thin air
		if str(row.get("spot", "")) == "":
			readable.add_child(WorldItem.placeholder_mesh({"category": "book"}))
		return readable
	var item := WorldItem.new()
	item.setup(str(row["item"]), int(row.get("count", 1)))
	item.owner_npc = str(row.get("owner", ""))
	item.name = "QuestItem_" + Ids.name_of(str(row["item"]))
	item.picked_up.connect(_on_taken.bind(key))
	return item


## The thing put down under this key while it stands, else null: where a tracked objective's
## thing is (Waymarks).
func standing_node(key: String) -> Node:
	return _placed[key] as Node if _standing(key) else null


## Whether the thing put down under this key still stands (its cell may have unloaded it).
func _standing(key: String) -> bool:
	var node: Variant = _placed.get(key)
	if not is_instance_valid(node):
		_placed.erase(key)
		return false
	return node is Node and not (node as Node).is_queued_for_deletion()


func _on_taken(_actor: Node, key: String) -> void:
	taken[key] = true
	_placed.erase(key)


func is_taken(key: String) -> bool:
	return taken.has(key)


## Forgets what was taken and what stands. A new game gets a new node with the world scene; this
## is for whoever shares one node across several runs (the test suite).
func clear() -> void:
	taken.clear()
	_placed.clear()


# --- save ---------------------------------------------------------------------------------------------

func to_save() -> Dictionary:
	var keys: Array = taken.keys()
	keys.sort()
	return {"taken": keys}


func from_save(d: Dictionary) -> void:
	taken.clear()
	for key in d.get("taken", []):
		taken[str(key)] = true
	# something standing that the save says was taken goes
	for key in _placed.keys():
		if taken.has(key) and _standing(key):
			(_placed[key] as Node).queue_free()
			_placed.erase(key)
