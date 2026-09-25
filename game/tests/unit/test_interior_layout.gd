extends TestCase
## Every interior's furniture, measured against the colliders the game builds, as a body meets them.
##
## Reported from the sixth playtest: "many interiors need a full asset placement redesign
## (clipping, blocking doorways, no collision, etc)". Measured before the redesign: furniture had
## no collision at all (only the house shell did, decimated to half its faces), and nothing checked
## a way through a house past its furniture. Here each house and deep place is built as the game
## builds it, and:
##   * every piece of furniture that is not clutter collides, as a box about its own mesh;
##   * no two pieces of furniture overlap, and none reaches into a wall;
##   * nothing stands in a door's clear zone (the opening and a hand either side, a metre deep on
##     both faces of the wall);
##   * a navigation mesh baked from the real colliders, for a body of the player's radius, holds a
##     path from the front door to every other door, and to every bed, container and fire;
##   * in a deep place, nothing it stands up closes a way from the way out that the rock leaves open;
##   * the player, walked with the real movement keys, gets from the front door to the far room.

const PLAYER := preload("res://actors/player/player.tscn")
const BODY_RADIUS := 0.35
const BODY_HEIGHT := 1.75
## How far past a box's face the body may stand and still be at it (the reach is 2.6 m; this is
## standing beside it).
const REACH := 0.9
## A door's clear zone, as the forge keeps it (house_forge.py DOOR_MARGIN, CLEAR).
const DOOR_W := 0.95
const DOOR_MARGIN := 0.15
const CLEAR := 1.0
## Overlap allowed between two boxes, or a box and the shell, before it is a clash.
const TOLERANCE := 0.02
const HEARTHS := ["hearth", "cook_hearth", "forge", "bread_oven"]

func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _ticks(n: int) -> void:
	for i in n:
		await _tree().physics_frame


static func _houses() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for def in ContentDB.all("interior"):
		var p := str(def.get("meta", ""))
		if p.contains("/models/interior/") and FileAccess.file_exists(p):
			out.append(def)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	return out


static func _caves() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for def in ContentDB.all("interior"):
		var p := str(def.get("meta", ""))
		if p.contains("/models/dungeon/") and FileAccess.file_exists(p):
			out.append(def)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	return out


func _build_house(def: Dictionary) -> HouseInterior:
	var h := HouseInterior.new()
	h.build_on_ready = false
	_tree().root.add_child(h)
	h.build(str(def["meta"]))
	await _ticks(3)
	return h


func _build_cave(def: Dictionary) -> CaveInterior:
	var c := CaveInterior.new()
	c.build_on_ready = false
	_tree().root.add_child(c)
	c.build(str(def["meta"]))
	await _ticks(3)
	return c


static func _free(n: Node) -> void:
	if n != null and is_instance_valid(n):
		n.get_parent().remove_child(n)
		n.free()


## Each prop the house stood up: {node, kind, clutter, boxes (world AABBs of its colliders),
## mesh (world AABB of what it draws, or an empty AABB)}.
static func _props_of(root: Node3D) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for holder_name in ["Props", "Features"]:
		var holder := root.get_node_or_null(holder_name)
		if holder == null:
			continue
		for child in holder.get_children():
			if not (child is Node3D) or child is Door or child is Light3D or child is Marker3D:
				continue
			var node := child as Node3D
			if node.is_in_group("hearthstone") or node.get_class() == "Hearthstone" or str(node.name).begins_with("Hearthstone"):
				continue
			var boxes: Array[AABB] = []
			for cs_v in node.find_children("*", "CollisionShape3D", true, false):
				var cs := cs_v as CollisionShape3D
				var body := cs.get_parent() as CollisionObject3D
				if body == null or (body.collision_layer & 1) == 0 or not (cs.shape is BoxShape3D):
					continue
				var size := (cs.shape as BoxShape3D).size
				boxes.append(cs.global_transform * AABB(-size * 0.5, size))
			var mesh := AABB()
			var first := true
			for mi_v in node.find_children("*", "MeshInstance3D", true, false):
				var mi := mi_v as MeshInstance3D
				if mi.mesh == null:
					continue
				var b := mi.global_transform * mi.get_aabb()
				mesh = b if first else mesh.merge(b)
				first = false
			if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
				mesh = node.global_transform * (node as MeshInstance3D).get_aabb()
			out.append({"node": node, "kind": str(node.get_meta("kind", node.name)), "clutter": bool(node.get_meta("clutter", false)),
					"boxes": boxes, "mesh": mesh})
	return out


static func _shrunk(b: AABB, by: float) -> AABB:
	return AABB(b.position + Vector3.ONE * by, (b.size - Vector3.ONE * by * 2.0).max(Vector3.ZERO))


## A door's clear zone on the side of `room` (a flat box from the floor to head height).
static func _zone(door: Dictionary, room: Dictionary) -> AABB:
	var at := HouseInterior._vec(door["at"])
	var y := float(room["floor_y"])
	var half := DOOR_W * 0.5 + DOOR_MARGIN
	var x0 := float(room["x"])
	var z0 := float(room["z"])
	var x1 := x0 + float(room["w"])
	var z1 := z0 + float(room["d"])
	if str(door.get("axis", "z")) == "x":
		var face := x0 if absf(at.x - x0) < absf(at.x - x1) else x1
		var lo := face if face == x0 else face - CLEAR
		return AABB(Vector3(lo, y, at.z - half), Vector3(CLEAR, 2.0, half * 2.0))
	var facez := z0 if absf(at.z - z0) < absf(at.z - z1) else z1
	var loz := facez if facez == z0 else facez - CLEAR
	return AABB(Vector3(at.x - half, y, loz), Vector3(half * 2.0, 2.0, CLEAR))


## Where a body stands a pace inside `room` from `door`.
static func _door_point(door: Dictionary, room: Dictionary) -> Vector3:
	var z := _zone(door, room)
	var at := HouseInterior._vec(door["at"])
	var c := z.get_center()
	var inward := Vector3(c.x - at.x, 0.0, c.z - at.z).normalized()
	var p := Vector3(at.x, float(room["floor_y"]), at.z) + inward * (0.14 + 0.6)
	return p


# --- collision ----------------------------------------------------------------------------------

func test_every_piece_of_furniture_that_is_not_clutter_collides() -> void:
	var total := 0
	var solid := 0
	for def in _houses():
		var h: HouseInterior = await _build_house(def)
		for p in _props_of(h):
			total += 1
			var kind := str(p["kind"])
			var mesh: AABB = p["mesh"]
			var boxes: Array = p["boxes"]
			if not boxes.is_empty():
				solid += 1
				# The box stands where the mesh does: covering most of its footprint.
				if mesh.size != Vector3.ZERO:
					var b: AABB = boxes[0]
					for bb in boxes:
						b = b.merge(bb)
					var cover := b.intersection(mesh)
					var share := (cover.size.x * cover.size.z) / maxf(mesh.size.x * mesh.size.z, 0.0001)
					assert_true(share > 0.8, "%s: %s's collider covers %.0f%% of what it draws" % [def["id"], kind, share * 100.0])
				continue
			assert_true(bool(p["clutter"]), "%s: %s has no collider and is not clutter" % [def["id"], kind])
			if mesh.size != Vector3.ZERO:
				var small := mesh.size.y < HouseInterior.CLUTTER_H + 0.01 or maxf(mesh.size.x, mesh.size.z) < HouseInterior.CLUTTER_W + 0.01
				var up := mesh.position.y - h.global_position.y - _floor_under(h, mesh)
				assert_true(small or up > 0.2, "%s: %s is %.2f x %.2f x %.2f on the floor, and walked through" % [
						def["id"], kind, mesh.size.x, mesh.size.y, mesh.size.z])
		_free(h)
	print("    " + "COLLISION | %d of %d house props collide; the rest are clutter" % [solid, total])
	assert_gt(solid, 150, "the houses' furniture collides")


## The floor of the room a box stands in (for telling a mug on a table from a mug on the floor).
static func _floor_under(h: HouseInterior, b: AABB) -> float:
	var best := 0.0
	for id in h.rooms:
		var r: Dictionary = h.rooms[id]
		var y := float(r["floor_y"])
		if b.position.y + 0.05 >= y:
			best = maxf(best, y)
	return best


func test_no_two_pieces_of_furniture_overlap_and_none_reaches_into_a_wall() -> void:
	var clashes := 0
	var pairs := 0
	for def in _houses() + _caves():
		var is_house := str(def["meta"]).contains("/models/interior/")
		var root: Node3D = (await _build_house(def)) if is_house else (await _build_cave(def))
		var props := _props_of(root)
		var boxes: Array[Dictionary] = []
		for p in props:
			for b in p["boxes"]:
				boxes.append({"kind": p["kind"], "box": b, "node": p["node"]})
		for i in boxes.size():
			for j in range(i + 1, boxes.size()):
				if boxes[i]["node"] == boxes[j]["node"]:
					continue
				pairs += 1
				var a := _shrunk(boxes[i]["box"], TOLERANCE)
				if a.intersects(_shrunk(boxes[j]["box"], TOLERANCE)):
					clashes += 1
					fail("%s: %s and %s overlap" % [def["id"], boxes[i]["kind"], boxes[j]["kind"]])
		# Against the shell: each box, a hand smaller, meets nothing of the house's own collision.
		var shell := root.get_node_or_null("Collision") as StaticBody3D
		if shell != null:
			var space := root.get_world_3d().direct_space_state
			for bx in boxes:
				var b: AABB = _shrunk(bx["box"], TOLERANCE)
				var q := PhysicsShapeQueryParameters3D.new()
				var form := BoxShape3D.new()
				form.size = b.size
				q.shape = form
				q.transform = Transform3D(Basis.IDENTITY, b.get_center())
				q.collision_mask = 1
				var own: Array[RID] = []
				for other in boxes:
					for body in (other["node"] as Node).find_children("*", "StaticBody3D", true, false):
						own.append((body as StaticBody3D).get_rid())
				q.exclude = own
				var hits := space.intersect_shape(q, 4)
				for hit in hits:
					if hit["collider"] == shell:
						clashes += 1
						fail("%s: %s reaches into the walls, floor or ceiling" % [def["id"], bx["kind"]])
						break
		_free(root)
	print("    " + "OVERLAP | %d pairs of colliders checked, %d clashes" % [pairs, clashes])


func test_nothing_stands_in_a_doors_clear_zone() -> void:
	var zones_n := 0
	for def in _houses():
		var h: HouseInterior = await _build_house(def)
		for door in h.meta.get("doors", []):
			for rid in door.get("between", []):
				if not h.rooms.has(str(rid)):
					continue
				var zone := _zone(door, h.rooms[str(rid)])
				zones_n += 1
				for p in _props_of(h):
					var shapes: Array = (p["boxes"] as Array).duplicate()
					if (p["mesh"] as AABB).size != Vector3.ZERO:
						shapes.append(p["mesh"])
					for b in shapes:
						if _shrunk(b, TOLERANCE).intersects(zone):
							fail("%s: %s stands in the clear zone of the door %s" % [def["id"], p["kind"], str(door["between"])])
							break
		_free(h)
	# A deep place's way out: nothing within a metre and a half of it.
	for def in _caves():
		var c: CaveInterior = await _build_cave(def)
		var exits: Array[Door] = []
		for n in c.find_children("*", "Door", true, false):
			exits.append(n as Door)
		for d in exits:
			zones_n += 1
			for p in _props_of(c):
				if (p["boxes"] as Array).is_empty():
					continue
				for b in p["boxes"]:
					var near := Vector2(maxf(maxf((b as AABB).position.x - d.global_position.x, d.global_position.x - (b as AABB).end.x), 0.0),
							maxf(maxf((b as AABB).position.z - d.global_position.z, d.global_position.z - (b as AABB).end.z), 0.0)).length()
					assert_true(near > 1.5, "%s: %s stands %.2f m from the way out" % [def["id"], p["kind"], near])
		_free(c)
	print("    " + "DOORWAYS | %d clear zones checked" % zones_n)


# --- the way through ----------------------------------------------------------------------------

## A navigation map baked from every static collider under `root` on the world layer, for the
## player's body. {map, region, mesh}.
func _bake(root: Node3D, cell: float, probe: Vector3, climb := 0.1) -> Dictionary:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nm.cell_size = cell
	nm.cell_height = 0.05
	nm.agent_radius = BODY_RADIUS
	nm.agent_height = BODY_HEIGHT
	# A body steps over a sill or a hearthstone, and not up a stair's side: the player has no step-up.
	nm.agent_max_climb = climb
	nm.agent_max_slope = 44.0
	nm.region_min_size = 1.0
	nm.edge_max_error = cell * 2.0
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, src, root)
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	var map := NavigationServer3D.map_create()
	NavigationServer3D.map_set_cell_size(map, cell)
	NavigationServer3D.map_set_cell_height(map, cell)
	NavigationServer3D.map_set_active(map, true)
	var region := NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(region, map)
	NavigationServer3D.region_set_navigation_mesh(region, nm)
	# The map joins its region on the server's own time: wait until a point known to be floor is
	# answered from it, or the first queries read an empty map and every way looks shut.
	for i in 240:
		await _tree().physics_frame
		if NavigationServer3D.map_get_closest_point(map, probe).distance_to(probe) < 0.6:
			break
	return {"map": map, "region": region, "mesh": nm}


static func _unbake(nav: Dictionary) -> void:
	NavigationServer3D.free_rid(nav["region"])
	NavigationServer3D.free_rid(nav["map"])


## Whether a body can walk from `a` to `b` on the map: the path's end is `b` itself.
static func _reaches(map: RID, a: Vector3, b: Vector3) -> bool:
	var from := NavigationServer3D.map_get_closest_point(map, a)
	var to := NavigationServer3D.map_get_closest_point(map, b)
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	return path.size() > 0 and path[path.size() - 1].distance_to(to) < 0.15 and path[0].distance_to(from) < 0.15


## The nearest place a body walking from `start` could stand at the thing in `box`: within REACH
## of its sides, on the floor it stands on, and reached by a way from `start`; or Vector3.INF. (The
## nearest place on the map at all may be the far side of a wall, in the next room.)
static func _standing_at(map: RID, box: AABB, start: Vector3) -> Vector3:
	var y := box.position.y + 0.05
	var best := Vector3.INF
	var best_d := INF
	# every point a pace out from the box, all the way round it, at two distances
	var qs: Array[Vector3] = []
	for out in [BODY_RADIUS + 0.1, REACH - 0.1]:
		var lo := Vector2(box.position.x - out, box.position.z - out)
		var hi := Vector2(box.end.x + out, box.end.z + out)
		for k in 12:
			var t := (float(k) + 0.5) / 12.0
			qs.append(Vector3(lerpf(lo.x, hi.x, t), y, lo.y))
			qs.append(Vector3(lerpf(lo.x, hi.x, t), y, hi.y))
			qs.append(Vector3(lo.x, y, lerpf(lo.y, hi.y, t)))
			qs.append(Vector3(hi.x, y, lerpf(lo.y, hi.y, t)))
	for q in qs:
		var p := NavigationServer3D.map_get_closest_point(map, q)
		if absf(p.y - box.position.y) > 0.3:
			continue
		var gap := Vector2(maxf(maxf(box.position.x - p.x, p.x - box.end.x), 0.0), maxf(maxf(box.position.z - p.z, p.z - box.end.z), 0.0)).length()
		if gap <= REACH and gap < best_d and _reaches(map, start, p):
			best_d = gap
			best = p
	return best


func test_a_body_walks_from_the_front_door_to_every_door_bed_chest_and_fire() -> void:
	var targets_n := 0
	for def in _houses():
		var h: HouseInterior = await _build_house(def)
		var front: Dictionary = {}
		for d in h.meta.get("doors", []):
			if str(d.get("kind", "")) == "front":
				front = d
		var start := _door_point(front, h.rooms[str(front["between"][1])])
		var nav: Dictionary = await _bake(h, 0.05, start)
		var map: RID = nav["map"]
		var reached := 0
		var wanted := 0
		for d in h.meta.get("doors", []):
			for rid in d.get("between", []):
				if not h.rooms.has(str(rid)):
					continue
				wanted += 1
				var p := _door_point(d, h.rooms[str(rid)])
				if _reaches(map, start, p):
					reached += 1
				else:
					fail("%s: no way for a body from the front door to the door %s, on the %s side" % [def["id"], str(d["between"]), rid])
		for p in _props_of(h):
			var kind := str(p["kind"])
			var node: Node3D = p["node"]
			var wants := kind == "bed" or HEARTHS.has(kind) or node.get_node_or_null("Container") != null
			if not wants or (p["boxes"] as Array).is_empty():
				continue
			wanted += 1
			var box: AABB = (p["boxes"] as Array)[0]
			var at := _standing_at(map, box, start)
			if at != Vector3.INF:
				reached += 1
			else:
				fail("%s: no way for a body from the front door to the %s in the %s" % [def["id"], kind, str(node.get_meta("room", "?"))])
		targets_n += wanted
		print("    " + "WAY | %s | %d of %d doors, beds, containers and fires reached from the front door" % [def["id"], reached, wanted])
		_unbake(nav)
		_free(h)
	assert_gt(targets_n, 100, "the houses were walked")


## Which chambers (and whether the Hearthstone) a body reaches from the way out on `map`.
func _deep_reach(c: CaveInterior, map: RID, start: Vector3) -> Dictionary:
	var reached: Array[String] = []
	for id in c.chambers:
		var pts: Array = (c.chambers[id] as Dictionary).get("floor_points", [])
		for k in mini(pts.size(), 6):
			if _reaches(map, start, CaveInterior._vec(pts[k])):
				reached.append(str(id))
				break
	var hs := false
	var features := c.get_node_or_null("Features")
	if features != null:
		for n in features.get_children():
			if n is Node3D and str(n.name).to_lower().contains("hearthstone"):
				hs = _reaches(map, start, (n as Node3D).global_position)
	return {"chambers": reached, "hearthstone": hs}


## In a deep place nothing it stands up (a sarcophagus, a tool rack, a mine cart) closes a way: a
## body's reach from the way out over the rock with the props' colliders in is the same as with
## them switched off. What the rock alone lets a body reach is measured and printed beside it.
func test_nothing_a_deep_place_stands_up_closes_a_way_through_it() -> void:
	for def in _caves():
		var c: CaveInterior = await _build_cave(def)
		var entrance := c.get_node_or_null("Entrance") as Node3D
		assert_true(entrance != null, "%s has an entrance" % def["id"])
		if entrance == null:
			_free(c)
			continue
		var start := entrance.global_position
		# Rock is rough underfoot: the rounded foot of the body rides over a hand's height of it.
		var nav: Dictionary = await _bake(c, 0.175, start, 0.3)
		var with_props := _deep_reach(c, nav["map"], start)
		_unbake(nav)
		var solids: Array[CollisionObject3D] = []
		for p in _props_of(c):
			for body in (p["node"] as Node).find_children("*", "StaticBody3D", true, false):
				solids.append(body as CollisionObject3D)
				(body as CollisionObject3D).collision_layer = 0
		await _ticks(2)
		var bare: Dictionary = await _bake(c, 0.175, start, 0.3)
		var rock_only := _deep_reach(c, bare["map"], start)
		_unbake(bare)
		var lost: Array[String] = []
		for id in rock_only["chambers"]:
			if not (with_props["chambers"] as Array).has(id):
				lost.append(str(id))
		print("    " + "DEEP | %s | %d props collide; from the way out %d of %d chambers over the rock alone, %d with the props in%s%s" % [
				def["id"], solids.size(), (rock_only["chambers"] as Array).size(), c.chambers.size(), (with_props["chambers"] as Array).size(),
				"" if lost.is_empty() else " (closed by props: %s)" % ", ".join(lost),
				"" if bool(with_props["hearthstone"]) == bool(rock_only["hearthstone"]) else "; a prop closes the way to the Hearthstone"])
		assert_true(lost.is_empty(), "%s: a prop closes the way to %s" % [def["id"], ", ".join(lost)])
		assert_eq(bool(with_props["hearthstone"]), bool(rock_only["hearthstone"]), "%s: a prop closes the way to the Hearthstone" % def["id"])
		_free(c)


# --- the player, walked --------------------------------------------------------------------------

## The player, on the real movement keys, walked from the front door to the far room of every
## house: at each step the view is turned toward the next corner of the way (as a player turns the
## mouse) and W is held. The far room is the one whose door is the longest way from the front door.
func test_the_player_walks_from_the_front_door_to_the_far_room_of_every_house() -> void:
	GameState.reset_for_new_game(7)
	for def in _houses():
		var h: HouseInterior = await _build_house(def)
		var entrance := h.get_node_or_null("Entrance") as Node3D
		var nav: Dictionary = await _bake(h, 0.05, entrance.global_position)
		var map: RID = nav["map"]
		var far_point := Vector3.INF
		var far_room := ""
		var far_len := -1.0
		for d in h.meta.get("doors", []):
			for rid in d.get("between", []):
				if not h.rooms.has(str(rid)) or str(d.get("kind", "")) == "front":
					continue
				var room: Dictionary = h.rooms[str(rid)]
				var p := Vector3(float(room["item_spot"][0]), float(room["floor_y"]), float(room["item_spot"][2])) if room.has("item_spot") \
						else _door_point(d, room)
				var path := NavigationServer3D.map_get_path(map, entrance.global_position, p, true)
				var length := 0.0
				for i in range(1, path.size()):
					length += path[i].distance_to(path[i - 1])
				if path.size() > 0 and path[path.size() - 1].distance_to(NavigationServer3D.map_get_closest_point(map, p)) < 0.15 and length > far_len:
					far_len = length
					far_point = p
					far_room = str(rid)
		assert_true(far_point != Vector3.INF, "%s: somewhere to walk to" % def["id"])
		if far_point == Vector3.INF:
			_unbake(nav)
			_free(h)
			continue
		var player := PLAYER.instantiate() as Player
		_tree().root.add_child(player)
		player.teleport(entrance.global_position + Vector3.UP * 0.05, entrance.global_rotation.y)
		await _ticks(6)
		var way := NavigationServer3D.map_get_path(map, player.global_position, far_point, true)
		var next := 1
		var ticks := 0
		var limit := int((far_len / Player.WALK_SPEED + 12.0) * Engine.physics_ticks_per_second)
		var stuck := 0
		var last := player.global_position
		Input.action_press("move_forward")
		while next < way.size() and ticks < limit:
			var to := way[next] - player.global_position
			to.y = 0.0
			if to.length() < 0.3 or (next < way.size() - 1 and to.length() < 0.5):
				next += 1
				continue
			player.camera_rig.yaw = -deg_to_rad(Compass.bearing_deg(Vector2.ZERO, Vector2(to.x, to.z)))
			await _tree().physics_frame
			ticks += 1
			if ticks % 30 == 0:
				stuck = stuck + 1 if player.global_position.distance_to(last) < 0.1 else 0
				last = player.global_position
				if stuck >= 4:
					break
		Input.action_release("move_forward")
		var end := player.global_position
		var under := ""
		var ray := PhysicsRayQueryParameters3D.create(end + Vector3.UP * 0.3, end + Vector3.DOWN * 2.0, 1)
		ray.exclude = [player.get_rid()]
		var hit := player.get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty():
			var col: Node = hit["collider"]
			under = "%s/%s" % [col.get_parent().name, col.name]
		var next_at := way[mini(next, way.size() - 1)] if way.size() > 0 else Vector3.INF
		var in_room := h.rooms[far_room] as Dictionary
		var inside := end.x >= float(in_room["x"]) and end.x <= float(in_room["x"]) + float(in_room["w"]) \
				and end.z >= float(in_room["z"]) and end.z <= float(in_room["z"]) + float(in_room["d"]) \
				and absf(end.y - float(in_room["floor_y"])) < 0.4
		print("    " + "WALK | %s | to the %s, %.1f m of way in %.1f s: %s" % [def["id"], far_room, far_len,
				float(ticks) / Engine.physics_ticks_per_second, "arrived" if inside else "stopped at %s on %s, heading for %s (%d of %d)" % [str(end), under, str(next_at), next, way.size()]])
		assert_true(inside, "%s: the player, walked from the front door, did not reach the %s (stopped at %s)" % [def["id"], far_room, str(end)])
		player.queue_free()
		await _ticks(1)
		_unbake(nav)
		_free(h)
