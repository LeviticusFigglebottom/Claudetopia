extends TestCase
## No tree's leaves in a house or a prop in the four fighting-style start towns (the owner, 2026-10-02:
## the Ranger's opening at Fernhold had leaves through the houses).
##
## The world build keeps every tree's crown off a town's pad and the gardens past it
## (tools/world/worldgen/trees.py, `clear_off_towns`: the pad's radius and TOWN_CROWN_CLEAR_M). That is
## only enough while the town stands inside that ring, so this stands the world up and asks the
## towns themselves: every house inside its pad, every prop the town set down inside the ring, no
## tree of the town's own with its crown in a house, and no tree of the built world's scatter with its
## crown over a house or a prop, the crown being the forge's box of the whole tree (`bounds` in its
## meta), turned, scaled and leant as the streamer draws it (WorldStreamer.instance_transform).

const WORLD_SCENE := "res://world/world.tscn"
const STARTS := ["core:place/fernhold", "core:place/wardens_rest", "core:place/gullhithe", "core:place/moreva"]
## The ring the world build keeps crowns out of, past the pad (worldgen.trees.TOWN_CROWN_CLEAR_M,
## which is StreetPlan.GARDEN_PAST_EDGE_M).
const CLEAR_PAST_PAD_M := 7.0

var _bounds: Dictionary = {}


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _settlements(n: Node, out: Array) -> void:
	if n is Settlement:
		out.append(n)
	for c in n.get_children():
		_settlements(c, out)


## The forge's box of a tree at scale one, its own axes: [min, max], or [] when it has none.
func _box(path: String) -> Array:
	if _bounds.has(path):
		return _bounds[path]
	var meta := path.get_basename() + ".meta.json"
	var out: Array = []
	if FileAccess.file_exists(meta):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta))
		if parsed is Dictionary and (parsed as Dictionary).get("bounds", null) is Dictionary:
			var b: Dictionary = parsed["bounds"]
			if b.has("min") and b.has("max"):
				out = [Vector3(b["min"][0], b["min"][1], b["min"][2]), Vector3(b["max"][0], b["max"][1], b["max"][2])]
	_bounds[path] = out
	return out


## Whether the ground point `p` (x, z) stands under a tree drawn with transform `t` from `path`.
func _under(path: String, t: Transform3D, p: Vector2) -> bool:
	var box := _box(path)
	if box.is_empty():
		return false
	var lo: Vector3 = box[0]
	var hi: Vector3 = box[1]
	# the crown's footprint: the point at the tree's own foot height, taken into its axes
	var local := t.affine_inverse() * Vector3(p.x, t.origin.y, p.y)
	return local.x >= lo.x and local.x <= hi.x and local.z >= lo.z and local.z <= hi.z


## A house's four corners and its middle.
func _house_points(h: Dictionary) -> Array[Vector2]:
	var b: Dictionary = h["box"]
	var out: Array[Vector2] = []
	for c in StreetPlan.corners(b):
		out.append(c)
	out.append(b["c"])
	return out


func test_no_crown_in_a_house_or_a_prop_in_the_start_towns() -> void:
	if not FileAccess.file_exists("res://world/generated/world_manifest.json"):
		skip("no built world")
		return
	var w := (load(WORLD_SCENE) as PackedScene).instantiate() as World
	_tree().root.add_child(w)
	if not w.is_world_ready:
		await w.world_ready
	for i in 5:
		await _tree().process_frame
	var doors := _tree().get_first_node_in_group("world_doors") as WorldDoors
	var towns: Array = []
	_settlements(_tree().root, towns)
	var manifest: Dictionary = w.provider.manifest
	var cell_m := float(manifest.get("cell_size_m", 256.0))
	var origin: Array = manifest.get("origin", [-4096.0, -4096.0])
	var found: Array[String] = []
	for place: String in STARTS:
		var street: StreetPlan = doors.streets.get(place) if doors != null else null
		var town: Settlement = null
		for s: Settlement in towns:
			if s.place_id == place:
				town = s
		if street == null or town == null:
			fail("%s stands no town" % place)
			continue
		var centre := street.centre
		var pad := town.pad_radius
		var short := place.get_file()
		# what stands in the town, and the ring the build keeps crowns out of covering it
		var solids: Array = []          # [label, Vector2]
		for h in street.houses:
			for p in _house_points(h):
				solids.append(["the house %s" % str((h as Dictionary).get("real", "")) if str((h as Dictionary).get("real", "")) != "" else "a house", p])
				if p.distance_to(centre) > pad + 0.01:
					found.append("%s: a house's corner stands %.1f m out, past the pad's %.1f m" % [short, p.distance_to(centre), pad])
		var own_trees: Array = []        # [path, Transform3D]
		for path: String in town._placed:
			for t: Transform3D in town._placed[path]:
				var g := town.global_transform * t
				var at := Vector2(g.origin.x, g.origin.z)
				if path.contains("/trees/"):
					own_trees.append([path, g])
					continue
				solids.append([path.get_file().get_basename(), at])
				if at.distance_to(centre) > pad + CLEAR_PAST_PAD_M:
					found.append("%s: %s stands %.1f m out, past the %.1f m the build keeps crowns out of" % [short,
							path.get_file(), at.distance_to(centre), pad + CLEAR_PAST_PAD_M])
		# the town's own trees: their crowns clear of its houses
		for ot in own_trees:
			for h in street.houses:
				for p in _house_points(h):
					if _under(str(ot[0]), ot[1], p):
						found.append("%s: its own %s at (%.0f, %.0f) has its crown in a house" % [short,
								str(ot[0]).get_file(), (ot[1] as Transform3D).origin.x, (ot[1] as Transform3D).origin.z])
						break
		# the built world's trees: no crown over anything the town stands up
		var c0 := Vector2i(floori((centre.x - float(origin[0])) / cell_m), floori((centre.y - float(origin[1])) / cell_m))
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var file := "res://world/generated/cells/%d_%d.json" % [c0.x + dx, c0.y + dz]
				if not FileAccess.file_exists(file):
					continue
				var cell: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
				if not (cell is Dictionary):
					continue
				var inst: Dictionary = (cell as Dictionary).get("instances", {})
				for path: String in inst:
					if not path.contains("/trees/"):
						continue
					for row: Array in inst[path]:
						var at := Vector2(float(row[0]), float(row[2]))
						if at.distance_to(centre) > pad + CLEAR_PAST_PAD_M + 120.0:
							continue
						var t := WorldStreamer.instance_transform(row, Vector3.ZERO)
						for s in solids:
							if _under(path, t, s[1]):
								found.append("%s: %s at (%.0f, %.0f), %.0f m out, has its crown over %s" % [short,
										path.get_file(), at.x, at.y, at.distance_to(centre), str(s[0])])
								break
	_tree().root.remove_child(w)
	w.queue_free()
	await _tree().process_frame
	assert_empty(found, "in the start towns (a world built before the crowns were kept off the towns fails here until it is built again):\n  %s"
			% "\n  ".join(found.slice(0, 30)))
