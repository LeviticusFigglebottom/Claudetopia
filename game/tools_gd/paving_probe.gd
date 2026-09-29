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
## a vertex is every 4, 8 and 16 m (its quads split either way there, so the higher). One line a
## place: points, and how many and how far the ground is over the made ground, near and in each
## ring, with the made ground lifted there as its shader lifts it (Settlement._far_lift).
##
## Triage 27 (the far rings): "seen" is the worst on each ring where the made ground is still drawn
## when the terrain under it has come to that ring, at the Near/Far/Epic view distances, and in
## brackets the same without the far rings' lift. Then how much deeper those rings bury the rest of
## the place (walls, plinths, joinery) than the terrain drawn near does, where each is seen on them.
##
## Triage 31: what stands on the ground carries the far rings' lift too (the walls, fences and posts:
## CUSTOM0, Settlement._foot_lift), and is measured lifted, with the unlifted worst in brackets.

const PROBE_M := 0.35
const RINGS := [2.0, 4.0, 8.0, 16.0]
## what counts as the ground showing through: over the made ground by more than this
const SHOW_M := 0.005
## The clipmap's vertices a side at each view distance (Graphics.TERRAIN_MESH_SIZE): the rings come
## nearer the fewer there are. A ring is "seen" only where the made ground is drawn that far off.
const VIEW := {"near": 32, "far": 48, "epic": 56}

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
	var h := TerrainProvider.triangle_height(h00, h10, h01, h11, tx, tz)
	if step <= RINGS[0]:
		return h
	# past its first ring Terrain3D splits its quads both ways, in alternation: either, so the
	# higher of the two
	return maxf(h, TerrainProvider.triangle_height(h10, h00, h11, h01, 1.0 - tx, tz))


func _at(x: float, z: float) -> float:
	var key := Vector2(x, z)
	if not _cache.has(key):
		_cache[key] = _provider.get_height(x, z)
	return _cache[key]




## How far off the eye can be while `mi` is still drawn, from its middle: its range and the margin
## it fades out over, or no end.
static func _reach(mi: GeometryInstance3D) -> float:
	if mi.visibility_range_end <= 0.0:
		return INF
	return mi.visibility_range_end + mi.visibility_range_end_margin


## Whether a point at most `far` metres from the eye is ever drawn on the terrain's ring of a
## vertex every RINGS[k] metres, the clipmap `mesh` vertices a side: from where the ring before it
## starts to fold its every other vertex away (Terrain3D's geomorph, in its vertex shader).
static func _seen_at(far: float, k: int, mesh: int) -> bool:
	return k == 0 or far >= (float(mesh) + 4.0 + 0.55 * float(mesh - 2)) * float(RINGS[k - 1])


func _measure(s: Settlement, id: String) -> String:
	var at := s.global_position
	var points := 0
	var over := []
	var worst := []
	var worst_r := []
	var seen := {}
	for k in RINGS.size():
		over.append(0)
		worst.append(0.0)
		worst_r.append(0.0)
	# and as it was before the far rings' lift, for the comparison
	var unlifted := {}
	for view in VIEW:
		seen[view] = [0.0, 0.0, 0.0, 0.0]
		unlifted[view] = [0.0, 0.0, 0.0, 0.0]
	for child in s.get_children():
		var mi := child as MeshInstance3D
		if mi == null or not (mi.name.begins_with("Paving") or mi.name.begins_with("Earth")):
			continue
		var middle := mi.global_transform * mi.get_aabb().get_center()
		var reach := _reach(mi)
		var arrays := mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		# what each patch is lifted by on the far rings (Settlement._fit_quad), as the paving's
		# shader lifts it: 4 and 8 m in UV, 16 m in UV2
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] != null else PackedVector2Array()
		var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
		var mat := mi.material_override as ShaderMaterial
		var follows: bool = mat != null and mat.get_shader_parameter("terrain_follow") == true and not uv.is_empty()
		for f in range(0, verts.size(), 3):
			var a := verts[f] + at
			var b := verts[f + 1] + at
			var c := verts[f + 2] + at
			# the made ground's own upper faces: not the sides and undersides of a garden's beds
			# (boxes set into the ground in the same mesh); front faces wind clockwise from above
			if (c - a).cross(b - a).normalized().y < 0.7:
				continue
			var lifts := [0.0, 0.0, 0.0, 0.0]
			if follows:
				lifts = [0.0, uv[f].x, uv[f].y, uv2[f].x if not uv2.is_empty() else 0.0]
			var n := maxi(1, int(ceil(maxf(a.distance_to(b), maxf(b.distance_to(c), c.distance_to(a))) / PROBE_M)))
			for i in range(n + 1):
				for j in range(n + 1 - i):
					var u := float(i) / float(n)
					var v := float(j) / float(n)
					var q := a + (b - a) * u + (c - a) * v
					var far := Vector2(q.x - middle.x, q.z - middle.z).length() + reach
					points += 1
					for k in RINGS.size():
						var bare: float = _drawn(q.x, q.z, RINGS[k]) - q.y
						var d: float = bare - float(lifts[k])
						if d > SHOW_M:
							over[k] += 1
						if d > worst[k]:
							worst[k] = d
							worst_r[k] = Vector2(q.x - at.x, q.z - at.z).length()
						for view in VIEW:
							if _seen_at(far, k, VIEW[view]):
								seen[view][k] = maxf(seen[view][k], d)
								unlifted[view][k] = maxf(unlifted[view][k], bare)
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
	var parts: Array = ["pad %.2f..%.2f" % [lo, hi]]
	for k in RINGS.size():
		var by_view: Array = []
		for view in VIEW:
			by_view.append("%.2f (%.2f)" % [seen[view][k], unlifted[view][k]])
		parts.append("%dm: %d over, worst %.2f m at %.0f m out, seen %s" % [int(RINGS[k]), over[k],
				worst[k], worst_r[k], "/".join(by_view)])
	return "%s (%s, pad %.0f m): %d points | %s | fabric buried past near: %s" % [
			Ids.name_of(id), s.kind, s.pad_radius, points, " | ".join(parts), _buried(s)]


## The rest of the place (its walls, plinths, stones, joinery): how much deeper the terrain's far
## rings bury what stands on the ground than the terrain drawn near does, where it is ever drawn
## on them. Each ring's worst at each view distance, and what it was.
func _buried(s: Settlement) -> String:
	var worst := {}
	var what := {}
	var bare := {}
	for view in VIEW:
		worst[view] = [0.0, 0.0, 0.0, 0.0]
		what[view] = ["", "", "", ""]
		bare[view] = [0.0, 0.0, 0.0, 0.0]
	var stack: Array[Node] = [s]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null or mi.name.begins_with("Paving") or mi.name.begins_with("Earth"):
			continue
		var xf := mi.global_transform
		var middle := xf * mi.get_aabb().get_center()
		var reach := _reach(mi)
		var done := {}
		# the lift it carries on the far rings (CUSTOM0, three floats a vertex), where its shader takes it
		var mat := mi.material_override as ShaderMaterial
		var follows: bool = mat != null and mat.get_shader_parameter("ground_follow") == true
		var arrays := mi.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var custom: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0] if follows and arrays[Mesh.ARRAY_CUSTOM0] is PackedFloat32Array else PackedFloat32Array()
		for vi in verts.size():
			var p := xf * verts[vi]
			var lifts := [0.0, 0.0, 0.0, 0.0]
			if custom.size() >= verts.size() * 3:
				lifts = [0.0, custom[vi * 3], custom[vi * 3 + 1], custom[vi * 3 + 2]]
			var key := Vector3i(roundi(p.x * 4.0), roundi(p.y * 4.0), roundi(p.z * 4.0))
			if done.has(key) and float(done[key]) >= float(lifts[1]) + float(lifts[2]) + float(lifts[3]):
				continue
			done[key] = float(lifts[1]) + float(lifts[2]) + float(lifts[3])
			var ground := _drawn(p.x, p.z, RINGS[0])
			# on the ground: a foot, a plinth's foot, a wall's bottom course
			if p.y > ground + 0.25 or p.y < ground - 1.0:
				continue
			var far := Vector2(p.x - middle.x, p.z - middle.z).length() + reach
			for k in range(1, RINGS.size()):
				var un := _drawn(p.x, p.z, RINGS[k]) - maxf(ground, p.y)
				var d := un - float(lifts[k])
				for view in VIEW:
					if un > bare[view][k] and _seen_at(far, k, VIEW[view]):
						bare[view][k] = un
					if d > worst[view][k] and _seen_at(far, k, VIEW[view]):
						worst[view][k] = d
						what[view][k] = "%s %.0f m out" % [str(mi.name), Vector2(p.x - s.global_position.x, p.z - s.global_position.z).length()]
	var parts: Array = []
	for k in range(1, RINGS.size()):
		var by_view: Array = []
		for view in VIEW:
			by_view.append("%.2f (%.2f)%s" % [worst[view][k], bare[view][k], (" " + str(what[view][k])) if worst[view][k] > 0.1 else ""])
		parts.append("%dm %s" % [int(RINGS[k]), "/".join(by_view)])
	return ", ".join(parts)
