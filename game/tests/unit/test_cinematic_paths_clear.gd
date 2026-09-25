extends TestCase
## Every camera in every cinematic, sampled along the whole of its path against the built world:
## the full-resolution ground (not the quarter-resolution copy the runtime queries, which is up to
## a few metres out on a slope), the water, every piece of scatter the builder planted, and the
## edge of the world. A camera is resolved exactly as `CinematicPlayer` resolves it, so if the land
## is reshaped under a shot this is the test that says which shot and where.
##
## It does not look at the pictures. That is done by capturing every shot's key frames
## (`./run.sh shots tools/capture/plans/opening.json`) and looking at them.

const GENERATED := "res://world/generated"
const SAMPLES := 160
## Metres a camera keeps above the highest ground within `REACH` of it, or above the water.
const CLEARANCE := 3.0
const REACH := 3.0
## The hand-over's last stretch is the gameplay camera arriving at its own pose, 2.3 m above the
## player's feet by CameraRig's numbers; it answers to its spring arm, and here only to this.
const HANDOVER_CLEARANCE := 1.2
const SCATTER_MARGIN := 0.75
## How close the edge of the world may be along any line of sight in the frame.
const EDGE_M := 700.0

var _heights: FileAccess = null
var _water: PackedByteArray
var _levels: PackedFloat32Array
var _water_grid := 1024
var _grid := 4096
var _spacing := 2.0
var _origin := Vector2(-4096.0, -4096.0)
var _size := 8192.0
var _pois: Dictionary = {}
var _cells: Dictionary = {}
var _bounds: Dictionary = {}


func _world_is_built() -> bool:
	return FileAccess.file_exists("%s/heights.r32" % GENERATED) and FileAccess.file_exists("%s/pois.json" % GENERATED)


func before_each() -> void:
	if not _world_is_built() or _heights != null:
		return
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/world_manifest.json" % GENERATED))
	if manifest is Dictionary:
		_grid = int(manifest.get("grid", 4096))
		_spacing = float(manifest.get("spacing_m", 2.0))
		_size = float(manifest.get("size_m", 8192.0))
		var o: Array = manifest.get("origin", [-4096, -4096])
		_origin = Vector2(float(o[0]), float(o[1]))
		var rt: Dictionary = manifest.get("runtime", {})
		_water_grid = int(rt.get("grid", 1024))
		_water = FileAccess.get_file_as_bytes("%s/%s" % [GENERATED, rt.get("water", "runtime/water_1024.u8")])
		_levels = FileAccess.get_file_as_bytes("%s/%s" % [GENERATED, rt.get("water_level", "runtime/water_level_1024.r32")]).to_float32_array()
	_heights = FileAccess.open("%s/heights.r32" % GENERATED, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/pois.json" % GENERATED))
	for p in (parsed if parsed is Array else []):
		_pois[str(p.get("place_id", ""))] = p


func after_each() -> void:
	pass


# --- the world, read the way the builder wrote it ------------------------------------------------------

## Full-resolution ground at a point, bilinear over the 2 m grid.
func _ground(x: float, z: float) -> float:
	var fx := clampf((x - _origin.x) / _spacing, 0.0, float(_grid) - 1.001)
	var fz := clampf((z - _origin.y) / _spacing, 0.0, float(_grid) - 1.001)
	var x0 := int(fx)
	var z0 := int(fz)
	var tx := fx - float(x0)
	var tz := fz - float(z0)
	return lerpf(lerpf(_h(x0, z0), _h(x0 + 1, z0), tx), lerpf(_h(x0, z0 + 1), _h(x0 + 1, z0 + 1), tx), tz)


func _h(ix: int, iz: int) -> float:
	_heights.seek((clampi(iz, 0, _grid - 1) * _grid + clampi(ix, 0, _grid - 1)) * 4)
	return _heights.get_float()


## What a camera stands over: ground, or the water on it (read as `TerrainProvider` reads it).
func _surface(x: float, z: float) -> float:
	var ground := _ground(x, z)
	if _water.is_empty() or _levels.is_empty():
		return ground
	var step := _size / float(_water_grid)
	var ix := clampi(int(round((x - _origin.x) / step)), 0, _water_grid - 1)
	var iz := clampi(int(round((z - _origin.y) / step)), 0, _water_grid - 1)
	var i := iz * _water_grid + ix
	return maxf(ground, _levels[i]) if _water[i] != 0 else ground


func _highest(p: Vector3) -> float:
	var best := _surface(p.x, p.z)
	for i in 8:
		var a := TAU * float(i) / 8.0
		best = maxf(best, _surface(p.x + cos(a) * REACH, p.z + sin(a) * REACH))
	return best


## Where a place stands, as `World.place_position` answers it.
func _place(id: String) -> Vector3:
	if _pois.has(id):
		var pos: Array = _pois[id].get("pos", [0, 0, 0])
		return Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	var def := ContentDB.get_or_empty(id)
	if def.has("position"):
		var xz: Array = def["position"]
		return Vector3(float(xz[0]), _ground(float(xz[0]), float(xz[1])), float(xz[1]))
	return Vector3.INF


func _resolve(def: Dictionary, shot: Dictionary) -> CinematicPath:
	var opening := ContentDB.get_or_empty(GameServices.OPENING)
	var feet := _place(str(opening.get("place", "")))
	feet.y = _ground(feet.x, feet.z)
	var yaw := 0.0
	var facing: Variant = (def.get("handover", {}) as Dictionary).get("facing", {})
	if facing is Dictionary and (facing as Dictionary).has("place"):
		var at := _place(str(facing["place"]))
		yaw = atan2(-(at.x - feet.x), -(at.z - feet.z))
	elif facing is Dictionary and (facing as Dictionary).has("bearing"):
		yaw = -deg_to_rad(float(facing["bearing"]))
	return CinematicPath.resolve(shot, Callable(self, "_surface"), Callable(self, "_place"), feet,
			CinematicPlayer.resting_camera(feet, yaw), 75.0)


# --- scatter -------------------------------------------------------------------------------------------

func _cell(c: Vector2i) -> Dictionary:
	if _cells.has(c):
		return _cells[c]
	var path := "%s/cells/%d_%d.json" % [GENERATED, c.x, c.y]
	var data: Dictionary = {}
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			data = parsed
	_cells[c] = data
	return data


## [radius, height] of a scatter asset at scale 1, from the forge's own meta file.
func _bounds_of(asset: String) -> Array:
	if _bounds.has(asset):
		return _bounds[asset]
	var meta_path := asset.get_basename() + ".meta.json"
	var out := [1.5, 3.0]
	if FileAccess.file_exists(meta_path):
		var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
		if meta is Dictionary and (meta as Dictionary).has("bounds"):
			var b: Dictionary = meta["bounds"]
			var lo: Array = b.get("min", [-1, 0, -1])
			var hi: Array = b.get("max", [1, 3, 1])
			var r := 0.0
			for v in [lo[0], lo[2], hi[0], hi[2]]:
				r = maxf(r, absf(float(v)))
			out = [r, float(hi[1])]
	_bounds[asset] = out
	return out


## The first piece of scatter a point is inside, as "asset at (x, z)", or "".
func _inside_scatter(p: Vector3) -> String:
	var c := Vector2i(int(floor((p.x - _origin.x) / 256.0)), int(floor((p.z - _origin.y) / 256.0)))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var instances: Dictionary = _cell(Vector2i(c.x + dx, c.y + dz)).get("instances", {})
			for asset: String in instances:
				var b := _bounds_of(asset)
				for row_v in instances[asset]:
					var row: Array = row_v
					var scale := float(row[4]) if row.size() > 4 else 1.0
					var reach := float(b[0]) * scale + SCATTER_MARGIN
					var dxz := Vector2(p.x - float(row[0]), p.z - float(row[2]))
					if dxz.length_squared() > reach * reach:
						continue
					if p.y < float(row[1]) + float(b[1]) * scale + SCATTER_MARGIN:
						return "%s at (%.0f, %.0f)" % [asset.get_file().get_basename(), float(row[0]), float(row[2])]
	return ""


## Metres along a level line of sight before the world ends.
func _to_edge(from: Vector3, dir: Vector3) -> float:
	var d := Vector2(dir.x, dir.z)
	if d.length() < 0.001:
		return INF
	d = d.normalized()
	var best := INF
	var lo := _origin
	var hi := _origin + Vector2(_size, _size)
	for axis in 2:
		var v := d[axis]
		var p := from.x if axis == 0 else from.z
		if absf(v) < 0.00001:
			continue
		var edge := hi[axis] if v > 0.0 else lo[axis]
		best = minf(best, (edge - p) / v)
	return best


# --- the tests ------------------------------------------------------------------------------------------

func test_every_camera_stays_above_the_ground_and_out_of_the_trees() -> void:
	if not _world_is_built():
		skip("no full-resolution heights.r32 or pois.json in world/generated: build the world with ./run.sh world")
		return
	for def in ContentDB.all("cinematic"):
		var shots := CinematicDef.shots_of(def)
		for i in shots.size():
			var shot: Dictionary = shots[i]
			if bool(shot.get("black", false)):
				continue
			var path := _resolve(def, shot)
			assert_true(path.is_playable(), "%s/%s cannot be placed: %s" % [def["id"], shot.get("id"), path.unresolved])
			if not path.is_playable():
				continue
			var handover := bool(shot.get("handover", false))
			var worst := INF
			var worst_at := Vector3.ZERO
			var trees: Array[String] = []
			for s in SAMPLES:
				var u := float(s) / float(SAMPLES - 1)
				var p := path.position_at(u)
				var need := HANDOVER_CLEARANCE if handover and path.arriving(u) else CLEARANCE
				var clear := p.y - _highest(p)
				if clear - need < worst:
					worst = clear - need
					worst_at = p
				var hit := _inside_scatter(p)
				if not hit.is_empty() and trees.size() < 3:
					trees.append("%s at u %.2f" % [hit, u])
			assert_true(worst >= 0.0, "%s/%s: the camera comes %.1f m too near the ground at %s" % [
					def["id"], shot.get("id"), -worst, worst_at.round()])
			assert_true(trees.is_empty(), "%s/%s flies through scatter: %s" % [def["id"], shot.get("id"), ", ".join(trees)])


func test_no_camera_looks_at_the_edge_of_the_world() -> void:
	if not _world_is_built():
		skip("no full-resolution heights.r32 or pois.json in world/generated: build the world with ./run.sh world")
		return
	for def in ContentDB.all("cinematic"):
		for shot in CinematicDef.shots_of(def):
			var s: Dictionary = shot
			if bool(s.get("black", false)):
				continue
			var path := _resolve(def, s)
			if not path.is_playable():
				continue
			var nearest := INF
			var bad_u := 0.0
			for k in 21:
				var u := float(k) / 20.0
				var pose := path.pose(u)
				var fwd := -pose.basis.z
				# the middle and the two sides of a 16:9 frame at these fields of view
				for turn in [-0.66, 0.0, 0.66]:
					var d := _to_edge(pose.origin, fwd.rotated(Vector3.UP, turn))
					if d < nearest:
						nearest = d
						bad_u = u
			assert_true(nearest >= EDGE_M, "%s/%s sees the edge of the world %.0f m away at u %.2f" % [
					def["id"], s.get("id"), nearest, bad_u])


func test_every_camera_and_everything_it_looks_at_is_inside_the_world() -> void:
	if not _world_is_built():
		skip("no full-resolution heights.r32 or pois.json in world/generated: build the world with ./run.sh world")
		return
	for def in ContentDB.all("cinematic"):
		for shot in CinematicDef.shots_of(def):
			var s: Dictionary = shot
			if bool(s.get("black", false)):
				continue
			var path := _resolve(def, s)
			for i in path.points.size():
				for p in [path.points[i], path.looks[i]]:
					var q: Vector3 = p
					assert_true(q.x > _origin.x + 50.0 and q.z > _origin.y + 50.0 and q.x < _origin.x + _size - 50.0
							and q.z < _origin.y + _size - 50.0, "%s/%s key %d is off the map: %s" % [def["id"], s.get("id"), i, q.round()])
