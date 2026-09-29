extends TestCase
## Every camera in every cinematic, sampled along the whole of its path against the built world:
## the full-resolution ground (not the quarter-resolution copy the runtime queries, which is up to
## a few metres out on a slope), the water, every piece of scatter the builder planted, and the
## edge of the world. The tracked world carries only the runtime copy (heights.r32 stays on the
## machine that built it), and these tests skipped on it without a word; there they now read that
## copy, as `CinematicPlayer` does, and judge the clearance against the highest of the four texels
## round a point, so a crest the 8 m grid smooths away still counts. A camera is resolved exactly as `CinematicPlayer` resolves it, so if the land
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
## Where a grown tree's crown begins, as a fraction of its height (tools/forge/lib/grow.py FORMS,
## `crown`'s third number), and how its age moves that (grow.py's ages, `base`). Below its crown a
## tree is only its trunk: a camera in Fernhold's clearing is under the giant oaks' leaves, not in
## them, and a big oak's full spread (37 m from the trunk) would otherwise rule out the clearing.
const CROWN_BASE := {"oak": 0.26, "giant_oak": 0.22, "apple": 0.25, "hawthorn": 0.18, "yew": 0.06,
		"black_ash": 0.42, "hardy_pine": 0.5, "rowan": 0.30, "juniper": 0.04, "willow": 0.2,
		"alder": 0.25, "willow_pollard": 0.45, "lime": 0.26, "birch": 0.35, "hazel": 0.12,
		"dead_ash_tree": 0.35}
const AGE_BASE := {"sapling": 0.45, "mature": 1.0, "veteran": 0.8}
## Metres a camera keeps under a crown's base when it passes beneath it.
const UNDER_CROWN := 1.0
## How close the edge of the world may be along any line of sight in the frame.
const EDGE_M := 700.0

var _heights: FileAccess = null
## The runtime copy, when the full-resolution ground is not on this machine.
var _coarse := PackedFloat32Array()
var _height_origin := Vector2(-4096.0, -4096.0)
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
	return FileAccess.file_exists("%s/pois.json" % GENERATED) and FileAccess.file_exists("%s/world_manifest.json" % GENERATED)


func before_each() -> void:
	if not _world_is_built() or _heights != null or not _coarse.is_empty():
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
	_height_origin = _origin
	if FileAccess.file_exists("%s/heights.r32" % GENERATED):
		_heights = FileAccess.open("%s/heights.r32" % GENERATED, FileAccess.READ)
	elif manifest is Dictionary:
		var rt: Dictionary = (manifest as Dictionary).get("runtime", {})
		_coarse = FileAccess.get_file_as_bytes("%s/%s" % [GENERATED, rt.get("heights", "runtime/heights_1024.r32")]).to_float32_array()
		_grid = int(rt.get("grid", 1024))
		_spacing = _size / float(_grid)
		_height_origin = _origin + Vector2.ONE * TerrainProvider.runtime_height_offset(manifest)
		print("  (no full-resolution ground here: the cinematic's paths are read against the %d m runtime copy)" % int(_spacing))
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("%s/pois.json" % GENERATED))
	for p in (parsed if parsed is Array else []):
		_pois[str(p.get("place_id", ""))] = p


func after_each() -> void:
	pass


# --- the world, read the way the builder wrote it ------------------------------------------------------

## The ground at a point, bilinear over the grid (full resolution where it is here).
func _ground(x: float, z: float) -> float:
	var fx := clampf((x - _height_origin.x) / _spacing, 0.0, float(_grid) - 1.001)
	var fz := clampf((z - _height_origin.y) / _spacing, 0.0, float(_grid) - 1.001)
	var x0 := int(fx)
	var z0 := int(fz)
	var tx := fx - float(x0)
	var tz := fz - float(z0)
	return lerpf(lerpf(_h(x0, z0), _h(x0 + 1, z0), tx), lerpf(_h(x0, z0 + 1), _h(x0 + 1, z0 + 1), tx), tz)


func _h(ix: int, iz: int) -> float:
	if not _coarse.is_empty():
		return _coarse[clampi(iz, 0, _grid - 1) * _grid + clampi(ix, 0, _grid - 1)]
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
	if not _coarse.is_empty():
		# on the runtime copy, the highest texel of the cell a point is in, not the blend of them
		var x0 := int(floor((p.x - _height_origin.x) / _spacing))
		var z0 := int(floor((p.z - _height_origin.y) / _spacing))
		for dz in 2:
			for dx in 2:
				best = maxf(best, _h(x0 + dx, z0 + dz))
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


## The opening that plays a film, so its hand-over lands behind the body where that opening stands it
## (a style's start in its own town); the fallback opening for a film no opening names.
func _opening_of(def: Dictionary) -> Dictionary:
	for o in ContentDB.all("opening"):
		if str(o.get("cinematic", "")) == str(def.get("id", "")):
			return o
	return ContentDB.get_or_empty(GameServices.OPENING)


func _resolve(def: Dictionary, shot: Dictionary) -> CinematicPath:
	var opening := _opening_of(def)
	var feet := _place(str(opening.get("place", "")))
	var yaw := 0.0
	var own: Variant = opening.get("start", null)
	if PlaceRef.is_spec(own):
		# as PlayerSpawn.pose_for stands it
		var xz := PlaceRef.point_xz(own as Dictionary)
		if xz != Vector2.INF:
			feet = Vector3(xz.x, feet.y, xz.y)
		yaw = -deg_to_rad(float((own as Dictionary).get("facing_deg", 0.0)))
	feet.y = _ground(feet.x, feet.z)
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


## [radius, height, crown base, trunk radius] of a scatter asset at scale 1, from the forge's own
## meta file; a crown base of 0 is a thing that is all crown (a bush, a rock, a prop).
func _bounds_of(asset: String) -> Array:
	if _bounds.has(asset):
		return _bounds[asset]
	var meta_path := asset.get_basename() + ".meta.json"
	var out := [1.5, 3.0, 0.0, 0.0]
	if FileAccess.file_exists(meta_path):
		var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
		if meta is Dictionary and (meta as Dictionary).has("bounds"):
			var m: Dictionary = meta
			var b: Dictionary = m["bounds"]
			var lo: Array = b.get("min", [-1, 0, -1])
			var hi: Array = b.get("max", [1, 3, 1])
			var r := 0.0
			for v in [lo[0], lo[2], hi[0], hi[2]]:
				r = maxf(r, absf(float(v)))
			var base := 0.0
			var trunk := 0.0
			var cp: Variant = m.get("collision_params", null)
			var kind := str(m.get("kind", ""))
			if str(m.get("category", "")) == "trees" and CROWN_BASE.has(kind) and cp is Dictionary:
				base = float(CROWN_BASE[kind]) * float(AGE_BASE.get(str(m.get("age", "mature")), 1.0)) * float(hi[1])
				trunk = float((cp as Dictionary).get("radius", 0.0))
			out = [r, float(hi[1]), base, trunk]
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
					if p.y < float(row[1]) + float(b[2]) * scale - UNDER_CROWN:
						# under a tree's crown: only its trunk is in the way
						reach = float(b[3]) * scale + SCATTER_MARGIN
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


# --- the sun -------------------------------------------------------------------------------------------

## Degrees a low sun is kept outside a film's frame (TRIAGE 54). A sun in or just off the frame is a
## disc the sky shader draws at about ten times white with a halo round it; on Forward+ the glow
## spreads it over the picture, and the "painted" preset's volumetric fog (the Briarwold's god rays)
## scatters it forward into the lens. The Ranger's lodge shot looked into a seven o'clock sun
## across the clearing (its 15-degree sun 3 degrees over the frame's top) and was "blindingly
## bright" on the user's GPU; on Compatibility the same frame is the clearing black against the
## light (mean luminance 0.035). The Warrior's opening over the downs keeps its sun 6 degrees off
## the frame's side and reads well (mean 0.40, nothing blown), so the line is drawn between them.
const SUN_CLEAR_DEG := 5.0
## A sun higher than this is out of any frame these cameras compose (they look level or down).
const SUN_LOW_DEG := 35.0
## Weather that veils the sun this much (its `sun_mult` under this) leaves no disc to stare into.
const SUN_VEILED := 0.6


func _region_of(p: Vector3, shot: Dictionary) -> Dictionary:
	if shot.has("region"):
		return ContentDB.get_or_empty(str(shot["region"]))
	var best: Dictionary = {}
	var best_d := INF
	for r in ContentDB.all("region"):
		var m: Dictionary = (r as Dictionary).get("map", {})
		var c: Array = m.get("center", [0, 0])
		var d := Vector2(p.x - float(c[0]), p.z - float(c[1])).length() / maxf(float(m.get("radius", 1000.0)), 1.0)
		if d < best_d:
			best_d = d
			best = r
	return best


func test_no_film_stares_into_a_low_sun() -> void:
	if not _world_is_built():
		skip("no full-resolution heights.r32 or pois.json in world/generated: build the world with ./run.sh world")
		return
	for def in ContentDB.all("cinematic"):
		var bars := float(def.get("letterbox", CinematicDef.DEFAULT_LETTERBOX))
		for shot in CinematicDef.shots_of(def):
			var s: Dictionary = shot
			if bool(s.get("black", false)) or not s.has("time"):
				continue
			var weather := ContentDB.get_or_empty(str(s.get("weather", "core:weather/clear")))
			if float(weather.get("sun_mult", 1.0)) < SUN_VEILED:
				continue
			var path := _resolve(def, s)
			if not path.is_playable():
				continue
			var look := Atmosphere.look_of_region(_region_of(path.position_at(0.0), s))
			var worst := INF
			var worst_u := 0.0
			var worst_elev := 0.0
			for k in 21:
				var u := float(k) / 20.0
				var hour := lerpf(float(s["time"]), float(s.get("time_to", s["time"])), u)
				var elev := Atmosphere.sun_elevation_for(hour, look)
				if elev < -1.0 or elev > SUN_LOW_DEG:
					continue
				var pose := path.pose(u)
				var local := pose.basis.inverse() * Atmosphere.sun_direction_for(hour, elev)
				if local.z >= 0.0:
					continue   # behind the camera
				# the frame is 16:9 at `fov` high, cut to the letterbox's aspect
				var tan_half := tan(deg_to_rad(path.fov_at(u)) * 0.5)
				var half_v := atan(tan_half * (16.0 / 9.0) / maxf(bars, 16.0 / 9.0))
				var half_h := atan(tan_half * 16.0 / 9.0)
				var out_h := rad_to_deg(absf(atan2(local.x, -local.z)) - half_h)
				var out_v := rad_to_deg(absf(atan2(local.y, -local.z)) - half_v)
				var off := maxf(out_h, out_v)   # degrees outside the frame's nearer edge; negative is inside
				if off < worst:
					worst = off
					worst_u = u
					worst_elev = elev
			var where := ("%.0f degrees inside the frame" % -worst) if worst < 0.0 else ("%.0f degrees off its edge" % worst)
			assert_true(worst >= SUN_CLEAR_DEG, "%s/%s has a %.0f-degree sun %s at u %.2f: re-time or re-frame it" % [
					def["id"], s.get("id"), worst_elev, where, worst_u])
