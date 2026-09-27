extends Node
## Does a town's made ground lie over the terrain, or does the ground show through it?
##
##   $GODOT --headless --path game res://tools_gd/paving_probe.tscn -- [--places=merrowby,tollmere]
##
## Triage 15 ("the ground textures of several towns, i.e. their roads/stone, clip in several areas
## showing the terrain underneath"). This loads the built terrain (Terrain3D, the game's own), raises
## each settlement's fabric the way WorldDoors does, and walks every triangle of its made ground
## (the Paving and Earth meshes) at PROBE_M: at each point it asks how far the terrain stands over
## the triangle there. The terrain is taken as Terrain3D draws it near the eye (its heights at its
## 2 m vertices, on its own triangles), and as its coarser clipmap rings draw it further off, where
## a vertex is every 4, 8 and 16 m. One line a place: points, and how many and how far the ground
## is over the made ground, near and in each ring.

const PROBE_M := 0.35
const RINGS := [2.0, 4.0, 8.0, 16.0]
## what counts as the ground showing through: over the made ground by more than this
const SHOW_M := 0.005

var _provider: TerrainProvider = null
var _cache := {}


func _ready() -> void:
	var only: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--places="):
			only = a.trim_prefix("--places=").split(",")
	var terrain: Node3D = ClassDB.instantiate("Terrain3D")
	terrain.name = "Terrain3D"
	add_child(terrain)
	terrain.set("data_directory", World.TERRAIN_DATA)
	terrain.set("vertex_spacing", 2.0)
	await get_tree().process_frame
	await get_tree().process_frame
	_provider = TerrainProvider.new()
	add_child(_provider)
	_provider.bind_terrain(terrain)
	var world := World.new()
	world.provider = _provider
	World.instance = world
	var pois: Array = JSON.parse_string(FileAccess.get_file_as_string("res://world/generated/pois.json"))
	var roads: Array = []
	for entry in JSON.parse_string(FileAccess.get_file_as_string("res://world/generated/roads.json")):
		roads.append((entry as Dictionary).get("points", []))
	for place in ContentDB.all("place"):
		var kind := str(place.get("kind", ""))
		var id := str(place.get("id", ""))
		if not Settlement.FABRIC.has(kind) or (not only.is_empty() and not only.has(Ids.name_of(id).to_lower().replace(" ", "_")) and not only.has(id.get_slice("/", 1))):
			continue
		var poi := {}
		for e in pois:
			if str((e as Dictionary).get("place_id", "")) == id:
				poi = e
		if poi.is_empty():
			continue
		var p: Array = poi["pos"]
		var centre := Vector3(float(p[0]), float(p[1]), float(p[2]))
		var radius := WorldDoors.pad_radius_of(poi)
		var near: Array = []
		for line in roads:
			if WorldDoors._touches(line, centre, radius):
				near.append(line)
		var s := Settlement.raise_at(id, kind, str(place.get("region", "")), centre, radius, near, [])
		var t0 := Time.get_ticks_usec()
		add_child(s)
		var built_ms := float(Time.get_ticks_usec() - t0) / 1000.0
		print("%s | raised in %.0f ms" % [_measure(s, id), built_ms])
		s.queue_free()
		await get_tree().process_frame
	get_tree().quit()


## The terrain's height at (x, z) drawn with a vertex every `step` metres: its heights at the four
## vertices round the point, on the two triangles Terrain3D splits a quad into.
func _drawn(x: float, z: float, step: float) -> float:
	var fx := x / step
	var fz := z / step
	var x0 := floorf(fx)
	var z0 := floorf(fz)
	var tx := fx - x0
	var tz := fz - z0
	var h00 := _at(x0 * step, z0 * step)
	var h10 := _at((x0 + 1.0) * step, z0 * step)
	var h01 := _at(x0 * step, (z0 + 1.0) * step)
	var h11 := _at((x0 + 1.0) * step, (z0 + 1.0) * step)
	return TerrainProvider.triangle_height(h00, h10, h01, h11, tx, tz)


func _at(x: float, z: float) -> float:
	var key := Vector2(x, z)
	if not _cache.has(key):
		_cache[key] = _provider.get_height(x, z)
	return _cache[key]


func _measure(s: Settlement, id: String) -> String:
	var at := s.global_position
	var points := 0
	var over := []
	var worst := []
	var worst_r := []
	for k in RINGS.size():
		over.append(0)
		worst.append(0.0)
		worst_r.append(0.0)
	for child in s.get_children():
		var mi := child as MeshInstance3D
		if mi == null or not (mi.name.begins_with("Paving") or mi.name.begins_with("Earth")):
			continue
		var faces: PackedVector3Array = mi.mesh.get_faces()
		for f in range(0, faces.size(), 3):
			var a := faces[f] + at
			var b := faces[f + 1] + at
			var c := faces[f + 2] + at
			# the made ground's own upper faces: not the sides and undersides of a garden's beds
			# (boxes set into the ground in the same mesh); front faces wind clockwise from above
			if (c - a).cross(b - a).normalized().y < 0.7:
				continue
			var n := maxi(1, int(ceil(maxf(a.distance_to(b), maxf(b.distance_to(c), c.distance_to(a))) / PROBE_M)))
			for i in range(n + 1):
				for j in range(n + 1 - i):
					var u := float(i) / float(n)
					var v := float(j) / float(n)
					var q := a + (b - a) * u + (c - a) * v
					points += 1
					for k in RINGS.size():
						var d := _drawn(q.x, q.z, RINGS[k]) - q.y
						if d > SHOW_M:
							over[k] += 1
						if d > worst[k]:
							worst[k] = d
							worst_r[k] = Vector2(q.x - at.x, q.z - at.z).length()
	# and how level the pad itself is, at the terrain's own vertices
	var lo := INF
	var hi := -INF
	var r := s.pad_radius - 2.0
	for gx in range(int(-r / 2.0), int(r / 2.0) + 1):
		for gz in range(int(-r / 2.0), int(r / 2.0) + 1):
			var x := roundf(at.x / 2.0) * 2.0 + float(gx) * 2.0
			var z := roundf(at.z / 2.0) * 2.0 + float(gz) * 2.0
			if Vector2(x - at.x, z - at.z).length() > r:
				continue
			var h := _at(x, z)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	var parts: Array = ["pad %.2f..%.2f (terrain3d %s)" % [lo, hi, str(_provider.has_terrain())]]
	for k in RINGS.size():
		parts.append("%dm: %d over (%.1f%%), worst %.2f m at %.0f m out" % [int(RINGS[k]), over[k],
				100.0 * float(over[k]) / float(maxi(points, 1)), worst[k], worst_r[k]])
	return "%s (%s, pad %.0f m): %d points | %s" % [Ids.name_of(id), s.kind, s.pad_radius, points, " | ".join(parts)]
