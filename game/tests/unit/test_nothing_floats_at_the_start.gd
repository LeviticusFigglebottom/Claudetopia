extends TestCase
## Nothing drawn about the start floats. The user's playtest of the starter area (2026-09-25, on
## Forward+) found "floating lamps, those white pillars having a gap, the massive stone pillars not
## being fully flush with the ground ... several seemingly random/floating assets as if it was a
## testing grounds". This stands the built world up round the new game's spawn and round the
## Choir's avenue at the end of the waystones, and asks of everything drawn within RADIUS_M: does
## its lowest point meet what is under it -- the ground, or something solid it stands on -- within
## GAP_M? A thing meant to hang (a lantern from a bracket, a flag from its pole) says so with the
## meta `hangs` on itself or a parent, and is left alone.
##
## Every object looked at is printed once (FLOATS | ... for each offender), with where it came from,
## so a failure says what to seat.

const WORLD_SCENE := "res://world/world.tscn"
const RADIUS_M := 120.0
const GAP_M := 0.15
## A level of detail first drawn this far out is not looked at here.
const FAR_LOD_BEGIN_M := 50.0
## Too small to be seen floating (a pebble, a tuft), and not what the user saw.
const MIN_SIZE_M := 0.3
const PLACES := {
	"the new game's spawn (the Stair Head)": {"place": "core:poi/stair_head"},
	"the Choir's avenue at the end of the waystones": {"place": "core:place/sunken_choir", "bearing": 155, "distance": 60},
}


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _frames(n: int) -> void:
	for i in n:
		await _tree().process_frame


## Whether a node is somebody (a body, a creature), not the place: people move and are not seated.
func _is_actor(n: Node) -> bool:
	var p := n
	while p != null:
		if p is CharacterBody3D or p is RigidBody3D:
			return true
		if p.is_in_group("player") or p.is_in_group("enemy") or p.is_in_group("npc"):
			return true
		# the animals: the crows fly and perch, and the sheep walk
		if p is Livestock or (p.get_script() != null and (p.get_script() as Script).resource_path.ends_with("crows.gd")):
			return true
		p = p.get_parent()
	return false


func _hangs(n: Node) -> bool:
	var p := n
	while p != null:
		if p.has_meta("hangs"):
			return true
		p = p.get_parent()
	return false


## Where a drawn thing came from, for the report: the nearest scene file or script above it.
func _source(n: Node) -> String:
	var p := n
	while p != null:
		if p.scene_file_path != "":
			return p.scene_file_path.get_file()
		var s: Script = p.get_script()
		if s != null and s.resource_path != "":
			return "%s (%s)" % [s.resource_path.get_file(), p.name]
		p = p.get_parent()
	return "?"


## The highest thing under a point: the ground, or anything solid below `top`.
func _support(space: PhysicsDirectSpaceState3D, x: float, z: float, top: float) -> float:
	var ground := World.get_height(x, z)
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, top, z), Vector3(x, ground - 1.0, z))
	# a foot inside something solid is set in it, not over it: a ray that starts inside a shape hits
	# it where it starts (the coals in a Hearthstone's bowl, its names cut in the stone's face, since
	# the stone is solid to its shape)
	q.hit_from_inside = true
	var hit := space.intersect_ray(q)
	return maxf(ground, (hit["position"] as Vector3).y) if not hit.is_empty() else ground


## The gap under one drawn box: its lowest point less the highest support under any of its bottom
## corners or its middle. Negative is sunk (fine); over GAP_M floats.
func _gap(space: PhysicsDirectSpaceState3D, box: AABB) -> float:
	var y := box.position.y
	var best := -INF
	var e := box.size
	for c in [Vector2(0.5, 0.5), Vector2(0.1, 0.1), Vector2(0.9, 0.1), Vector2(0.1, 0.9), Vector2(0.9, 0.9)]:
		var x: float = box.position.x + e.x * c.x
		var z: float = box.position.z + e.z * c.y
		best = maxf(best, _support(space, x, z, y + 0.05))
	return y - best


func _check_around(w: World, label: String, centre: Vector3) -> Array[String]:
	var space := w.get_world_3d().direct_space_state
	var floating: Array[String] = []
	var looked := 0
	for n in _tree().root.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if not g.is_visible_in_tree() or _is_actor(g) or _hangs(g):
			continue
		# a far level of detail (drawn from FAR_LOD_BEGIN_M out) is judged where it is seen: a forge
		# fence's LOD2 stands half a metre off its feet, which nobody sees at a hundred metres
		if g.visibility_range_begin >= FAR_LOD_BEGIN_M:
			continue
		if g is MeshInstance3D and (g as MeshInstance3D).mesh != null:
			var box := g.global_transform * (g as MeshInstance3D).mesh.get_aabb()
			if Vector2(box.get_center().x - centre.x, box.get_center().z - centre.z).length() > RADIUS_M:
				continue
			if box.size.length() < MIN_SIZE_M or box.size.y > 200.0:
				continue
			looked += 1
			var gap := _gap(space, box)
			if gap > GAP_M:
				floating.append("%s %s at %s, %.2f m up (%s)" % [g.name, str(box.size.snapped(Vector3.ONE * 0.1)),
						str(box.position.round()), gap, _source(g)])
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh != null:
			var mm := (g as MultiMeshInstance3D).multimesh
			if mm.mesh == null:
				continue
			var local := mm.mesh.get_aabb()
			for i in mm.instance_count:
				var box := g.global_transform * mm.get_instance_transform(i) * local
				if Vector2(box.get_center().x - centre.x, box.get_center().z - centre.z).length() > RADIUS_M:
					continue
				if box.size.length() < MIN_SIZE_M:
					continue
				looked += 1
				var gap := _gap(space, box)
				if gap > GAP_M:
					floating.append("%s[%d] %s at %s, %.2f m up (%s)" % [g.name, i, str(box.size.snapped(Vector3.ONE * 0.1)),
							str(box.position.round()), gap, _source(g)])
	# the Choir's colossi stand in the ash, their plinths set down into it, not on it
	for n in w.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or not str(mi.name).begins_with("cinderlea_choir_colossus") or str(mi.name).contains("_LOD"):
			continue
		var box := mi.global_transform * mi.mesh.get_aabb()
		if Vector2(box.get_center().x - centre.x, box.get_center().z - centre.z).length() > RADIUS_M:
			continue
		var c := box.get_center()
		var ground := World.get_height(c.x, c.z)
		if box.position.y > ground - 1.0:
			floating.append("%s's plinth stands on the ash, its foot %.2f m below the ground at its middle (wanted 1 m or more)"
					% [mi.name, ground - box.position.y])
	print("  (%s: %d drawn things looked at within %d m, %d floating)" % [label, looked, int(RADIUS_M), floating.size()])
	for f in floating:
		print("  FLOATS | %s | %s" % [label, f])
	return floating


func test_nothing_drawn_about_the_start_floats() -> void:
	if not FileAccess.file_exists("res://world/generated/world_manifest.json"):
		return
	var w := (load(WORLD_SCENE) as PackedScene).instantiate() as World
	_tree().root.add_child(w)
	await w.world_ready
	for label: String in PLACES:
		var spec: Dictionary = PLACES[label]
		var at := PlaceRef.point(spec)
		w.move_target(at)
		var until := Time.get_ticks_msec() + 120000
		while Time.get_ticks_msec() < until:
			await _tree().process_frame
			if w.streamer == null or (w.streamer.is_loaded_around(at) and w.streamer.is_ring_loaded()):
				break
		await _frames(30)
		var floating := _check_around(w, label, at)
		assert_true(floating.is_empty(), "%s: %d things float: %s" % [label, floating.size(), "; ".join(floating.slice(0, 12))])
	_tree().root.remove_child(w)
	w.free()
	await _tree().process_frame
