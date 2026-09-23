extends TestCase
## The fights and finds of the quests that follow the map (docs/ATLAS.md §15) stand in the open.
##
## A landmark's collision is a hollow shell, so a body put down inside a colossus, a tower's drum,
## a wreck's hull or a ribcage overlaps nothing. The one check QuestFoes had, a capsule that
## touches nothing, passed such a spot, and the Naming's wights stood inside the Choir's colossus
## where no blade could reach them. That the ids of a quest resolve says nothing about this.
##
## So this raises what the world raises at each place the map's quests fight at or leave something
## at: a point of interest's dressing, a place's landmark with the collision the streamer builds for
## it, a settlement's fabric. Then it asks for the spots the game itself would choose: where
## QuestFoes stands a stage's foes, and where QuestItems puts a find down. Each has to be open
## ground: a body fits there, and there is sky over it.
##
## The ground is flat and dry here on purpose. The question is whether the things built at the
## place leave room round them, not what the country under them does.

const MAP_QUESTS := "res://content/packs/core/quests/the_map.json"
const MAP_NOTES := "res://content/packs/core/encounters/the_map.json"
## The built world's pads, for the flat radius a place was given and the landmark it keeps. One the
## build has not reached yet gets the builder's default (tools/world/worldgen/roads.py,
## PAD_DEFAULT), or for a settlement WorldDoors' own.
const PADS := "res://world/generated/pois.json"
const PAD_DEFAULT_M := 25.0
const FABRIC_DEFAULT_M := 40.0
## How high the sky is looked for over a spot: higher than anything the builders raise.
const SKY_M := 80.0
## A standing body, the capsule QuestFoes measures ground with.
const BODY_R := 0.45
const BODY_H := 1.7
## A find lying on the ground, and room enough to stoop for it (QuestItems.OPEN_R, OPEN_H).
const FIND_R := 0.3
const FIND_H := 1.2

var _pads: Dictionary = {}
var _flat: TerrainProvider = null
## Stands for the cell a place is in: what the streamer hangs off the cell node hangs here.
var _host: Node3D = null
## Stands for WorldDoors, which raises every settlement's fabric beside the cells, not in them.
var _beside: Node3D = null


## Whether a body can be somewhere: it fits there, and there is sky over it.
class Ground:
	## Why a body `radius` wide and `height` tall cannot be at `p`, or "" when it can: a capsule its
	## size, its feet 0.2 m up as QuestFoes stands one, touches nothing, and a ball its width let
	## down from the sky reaches the top of its head. A hollow shell passes the first and not the
	## second.
	static func shut_in(space: PhysicsDirectSpaceState3D, p: Vector3, radius: float, height: float) -> String:
		var body := CapsuleShape3D.new()
		body.radius = radius
		body.height = maxf(height, radius * 2.0)
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = body
		q.collision_mask = 1
		q.transform = Transform3D(Basis.IDENTITY, p + Vector3(0.0, 0.2 + body.height * 0.5, 0.0))
		var inside := space.intersect_shape(q, 1)
		if not inside.is_empty():
			var node: Variant = (inside[0] as Dictionary).get("collider")
			return "in %s" % (str((node as Node).name) if node is Node else "something")
		return overhead(space, p, radius, body.height)

	## "under something n m up" when a ball the body's width, let down from the sky, stops above
	## its head; "" when it reaches the head.
	static func overhead(space: PhysicsDirectSpaceState3D, p: Vector3, radius: float, height: float) -> String:
		var ball := SphereShape3D.new()
		ball.radius = radius
		var fall := PhysicsShapeQueryParameters3D.new()
		fall.shape = ball
		fall.collision_mask = 1
		var head := p.y + 0.2 + height + radius
		fall.transform = Transform3D(Basis.IDENTITY, Vector3(p.x, p.y + SKY_M, p.z))
		fall.motion = Vector3(0.0, head - (p.y + SKY_M), 0.0)
		var way := space.cast_motion(fall)
		if way.size() == 2 and way[0] < 1.0:
			return "under something %.1f m up" % (SKY_M + fall.motion.y * way[1])
		return ""


func before_each() -> void:
	_flat = TerrainProvider.new()   # nothing loaded: flat at nought and dry everywhere
	if _pads.is_empty() and FileAccess.file_exists(PADS):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PADS))
		if typeof(parsed) == TYPE_ARRAY:
			for e in parsed:
				if typeof(e) == TYPE_DICTIONARY:
					_pads[str((e as Dictionary).get("place_id", ""))] = e
	_host = Node3D.new()
	_host.name = "MapQuestGround"
	_tree().root.add_child(_host)
	_beside = Node3D.new()
	_beside.name = "MapQuestFabric"
	_tree().root.add_child(_beside)


func after_each() -> void:
	for n in [_host, _beside]:
		if n != null and is_instance_valid(n):
			(n as Node).get_parent().remove_child(n)
			(n as Node).free()
	_host = null
	_beside = null


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _load(path: String) -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_ARRAY else []


## Heights come from a standing world when there is one, and then the flat ground here is not the
## ground the game measures on.
func _no_world() -> bool:
	if World.instance != null and is_instance_valid(World.instance):
		print("  (a world is standing, so the ground is not flat here: skipped)")
		return false
	return true


## What the world raises at a place, on flat ground at its position: a point of interest's dressing
## and a place's landmark in the cell (`_host`), a settlement's fabric beside it (`_beside`).
## {base, nodes, built}; nothing built when the world raises nothing there.
func _raise_place(where: String) -> Dictionary:
	var def := ContentDB.get_or_empty(where)
	var xz: Array = def.get("position", [])
	var out := {"base": Vector3.INF, "nodes": [], "built": []}
	if xz.size() < 2:
		return out
	var base := Vector3(float(xz[0]), 0.0, float(xz[1]))
	out["base"] = base
	var pad: Dictionary = _pads.get(where, {})
	if PoiDressing.dressable(where, def):
		var entry := pad.duplicate()
		entry["place_id"] = where
		entry["pos"] = [base.x, 0.0, base.z]
		entry["radius_flat_m"] = float(entry.get("radius_flat_m", PAD_DEFAULT_M))
		var d := PoiDressing.raise(entry, def, false, _flat, [])
		_host.add_child(d)
		(out["nodes"] as Array).append(d)
		(out["built"] as Array).append("dressing")
	var scene := str(pad.get("scene", ""))
	if scene != "":
		var landmark := _landmark(scene, base, float(pad.get("yaw", 0.0)))
		if landmark != null:
			(out["nodes"] as Array).append(landmark)
			(out["built"] as Array).append("landmark")
	# WorldDoors raises the fabric of every place of a settlement's kind, and a camp's is empty
	var kind := str(def.get("kind", ""))
	if Ids.type_of(where) == "place" and int((Settlement.FABRIC.get(kind, {}) as Dictionary).get("count", 0)) > 0:
		var radius := maxf(float(pad.get("radius_flat_m", FABRIC_DEFAULT_M)), 24.0)
		var s := Settlement.raise_at(where, kind, str(def.get("region", "")), base, radius, [], [])
		_beside.add_child(s)
		(out["nodes"] as Array).append(s)
		(out["built"] as Array).append("fabric")
	return out


## A place's landmark as the streamer stands it (`WorldStreamer._build_scene`): the forge's scene,
## and a static body of trimesh shapes from the low collision mesh the forge files beside it.
func _landmark(path: String, base: Vector3, yaw_deg: float) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var inst := (load(path) as PackedScene).instantiate() as Node3D
	if inst == null:
		return null
	inst.position = base
	inst.rotation.y = deg_to_rad(yaw_deg)
	_host.add_child(inst)
	var col := path.get_basename() + "_col.glb"
	if ResourceLoader.exists(col):
		var source := (load(col) as PackedScene).instantiate()
		var body := StaticBody3D.new()
		body.name = "Collision"
		for m in source.find_children("*", "MeshInstance3D", true, false):
			var mesh: Mesh = (m as MeshInstance3D).mesh
			if mesh == null:
				continue
			var shape := CollisionShape3D.new()
			shape.shape = mesh.create_trimesh_shape()
			shape.transform = WorldStreamer._transform_within(m as Node3D, source)
			body.add_child(shape)
		source.free()
		inst.add_child(body)
	return inst


func _drop_all(nodes: Array) -> void:
	for n in nodes:
		if n != null and is_instance_valid(n):
			(n as Node).get_parent().remove_child(n)
			(n as Node).free()


func _settle() -> void:
	await _tree().physics_frame
	await _tree().physics_frame


func _shut_in(p: Vector3, radius: float, height: float) -> String:
	return Ground.shut_in(_host.get_world_3d().direct_space_state, p, radius, height)


## Every fight the map's quests ask for at a place or point of interest in the open, as
## {key, quest, stage, objective, where}; `key` is the one QuestFoes seeds its ring with.
func _fights() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for def_v in _load(MAP_QUESTS):
		var def: Dictionary = def_v
		var stages: Array = def.get("stages", [])
		for si in stages.size():
			var objectives: Array = (stages[si] as Dictionary).get("objectives", [])
			for oi in objectives.size():
				var o: Dictionary = objectives[oi]
				var where := str(o.get("where", ""))
				if str(o.get("type", "")) != "kill" or not (Ids.type_of(where) in ["poi", "place"]):
					continue
				out.append({"key": "%s|%d|%d" % [def["id"], si, oi], "quest": str(def["id"]),
						"stage": str((stages[si] as Dictionary).get("id", si)), "objective": o, "where": where})
	return out


## Where `foes` stands each of the map's fights, and where the place's own groups of that kind
## stand, as [{fight, why: [String], own: [String], built}]: an entry of `why` or `own` is "" for a
## body in the open.
func _stand_fights(foes: QuestFoes) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f in _fights():
		var raised := _raise_place(str(f["where"]))
		if (raised["built"] as Array).is_empty():
			_drop_all(raised["nodes"])
			continue
		await _settle()
		var o: Dictionary = f["objective"]
		var why: Array[String] = []
		for p in foes.clear_ground(str(f["key"]), raised["base"], maxi(1, int(o.get("count", 1)))):
			why.append(_shut_in(p, BODY_R, BODY_H))
		var own: Array[String] = []
		for node in raised["nodes"]:
			if node is PoiDressing:
				for p in _own_group(node as PoiDressing, str(o.get("target", ""))):
					own.append(_shut_in(p, BODY_R, BODY_H))
		out.append({"fight": f, "why": why, "own": own, "built": raised["built"]})
		_drop_all(raised["nodes"])
	return out


## Where a place's own groups of one kind stand, as PoiEncounters stands them: on the marker an
## entry names, else on the pad's rim, and spread round that when there are several. QuestFoes
## counts these first and stands only the shortfall, so one of them shut inside a shell would
## hold a fight open as surely as a ring spot there would. Nobody is raised: the node asks where
## and is gone before its first refresh.
func _own_group(d: PoiDressing, enemy: String) -> Array[Vector3]:
	var out: Array[Vector3] = []
	var entries := PoiEncounters.of(d.poi_id)
	if entries.is_empty():
		return out
	var enc := PoiEncounters.new()
	enc.poi_id = d.poi_id
	enc.entries = entries
	enc.pad_radius = d.pad_radius
	enc.terrain = _flat
	d.add_child(enc)
	for i in entries.size():
		var e: Dictionary = entries[i]
		if str(e.get("enemy", "")) != enemy:
			continue
		var anchor: Dictionary = enc._anchor(i, e)
		var count := maxi(1, int(e.get("count", 1)))
		for k in count:
			var at: Vector3 = anchor["pos"]
			if count > 1:
				var a := TAU * float(k) / float(count) + float(i)
				at += Vector3(cos(a), 0.0, sin(a)) * float(e.get("spread", 2.5))
			if not bool(anchor["raised"]):
				at.y = d.world_position.y
			out.append(at)
	d.remove_child(enc)
	enc.free()
	return out


## Every fight the map's quests ask for at a place in the open: the spots QuestFoes stands the
## whole count on, which it does when nothing of the kind is there already (the place's own were
## put down before the stage opened). QuestFoes refuses a spot with anything solid over it, since
## the Naming's wights were found inside the Choir's colossus; this holds the map's places to it.
func test_the_maps_fights_stand_in_the_open() -> void:
	if not _no_world():
		return
	var foes := QuestFoes.new()
	foes.enabled = false
	_host.add_child(foes)
	var stood := await _stand_fights(foes)
	var built: Dictionary = {}
	var own := 0
	for s in stood:
		var f: Dictionary = s["fight"]
		var target := Ids.name_of(str((f["objective"] as Dictionary).get("target", "")))
		for b in s["built"]:
			built[b] = int(built.get(b, 0)) + 1
		for why in s["why"]:
			assert_true(why == "", "%s / %s: a %s stands %s at %s" % [f["quest"], f["stage"], target, why,
					Ids.name_of(str(f["where"]))])
		for why in s["own"]:
			own += 1
			assert_true(why == "", "%s / %s: the place's own %s, which the fight counts, stands %s at %s" % [
					f["quest"], f["stage"], target, why, Ids.name_of(str(f["where"]))])
	print("MEASURE | the map's fights at a place something is built at | %d | %s | the places' own foes they count: %d"
			% [stood.size(), str(built), own])
	assert_gt(stood.size(), 25, "the map's fights were asked")


## Every find the map's quests and notes leave at a place in the open: where QuestItems puts it
## down, asked in the same frame the place is raised in, as WorldPois asks.
func test_the_maps_finds_lie_in_the_open() -> void:
	if not _no_world():
		return
	var ours: Dictionary = {}
	for def_v in _load(MAP_QUESTS):
		ours[str((def_v as Dictionary)["id"])] = true
	var noted: Dictionary = {}
	for enc_v in _load(MAP_NOTES):
		noted[str((enc_v as Dictionary).get("place", ""))] = true
	var by_place: Dictionary = {}
	for row in QuestItems.placements():
		var where := str(row["where"])
		var mine := ours.has(str(row.get("quest_id", ""))) or (str(row["key"]).begins_with("lies:") and noted.has(where))
		if mine and Ids.type_of(where) in ["poi", "place"]:
			(by_place.get_or_add(where, []) as Array).append(row)
	# where a find goes is worked out without a QuestItems standing in the tree (and saving)
	var items := QuestItems.new()
	var asked := 0
	var bare: Array[String] = []
	for where in by_place:
		var raised := _raise_place(str(where))
		if (raised["built"] as Array).is_empty():
			bare.append(str(where))
			_drop_all(raised["nodes"])
			continue
		var spots: Array[Vector3] = []
		for row_v in by_place[where]:
			spots.append(items._spot_in_the_open(_host, row_v, raised["base"]))
		await _settle()
		var rows: Array = by_place[where]
		for i in rows.size():
			var row: Dictionary = rows[i]
			asked += 1
			var why := _shut_in(spots[i], FIND_R, FIND_H)
			var what := str(row.get("item", ""))
			if what == "":
				what = str(row.get("book", ""))
			var whose := str(row.get("quest_id", ""))
			assert_true(why == "", "%s: %s lies %s at %s" % [whose if whose != "" else "a note", Ids.name_of(what), why,
					Ids.name_of(str(where))])
		_drop_all(raised["nodes"])
	items.free()
	print("MEASURE | the map's finds at a place something is built at | %d asked at %d places | nothing built at: %s"
			% [asked, by_place.size() - bare.size(), ", ".join(bare)])
	assert_gt(asked, 90, "the map's finds were asked")
