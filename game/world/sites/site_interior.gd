class_name SiteInterior
extends Node3D
## A large site's inside (a cave system, a mine, a crypt, a keep's undercroft ...), raised from its
## interior def's `site` block: the layout (SitePlan) at once, the rock (SiteField) on a worker
## thread, and everything in it (SiteDress) a step at a time within the frame's budget (WorldPace),
## so walking in never makes a long frame. The way in and the way out stand from the first frame, on
## a slab of floor, and the body is held on it until the rock under the rest is there.
##
## The scene contract is the interiors' own (systems/interiors/README.md): a Marker3D "Entrance",
## an exit Door. A game saved inside comes back here and is held at the way in until built.
##
## Headless (the tests, the tools) nothing is paced and nothing is threaded: the whole place is
## built before `_ready` returns, the same as a stepwise build, piece for piece.

signal built

const SCENE := "res://world/sites/site_interior.tscn"
const CACHE_DIR := "user://site_cache"
## The rock's look per kind of formation, shared with the deep places.
const ROCK_SHADER := preload("res://assets/shaders/cave_rock.gdshader")

## Set by a test or a tool to build a def that is not in the content (or to build it again).
var def_override: Dictionary = {}
var interior_id := ""
var def: Dictionary = {}
var plan: SitePlan = null
var is_built := false
## The shell's chunks as they came off the field (for tests: the faces are the collision).
var chunks: Array = []
var rock_body: StaticBody3D = null
var nav_region: NavigationRegion3D = null
var dress: SiteDress = null
## How long the build took on the main thread, and its longest single piece (microseconds).
var main_us := 0
var longest_piece_us := 0
var longest_piece_at := ""
## Force pacing on or off (-1: WorldPace decides), for the frame-budget test.
var paced_override := -1

var _t0 := 0
var _hold_at := Vector3.INF
var _temp_floor: StaticBody3D = null
var _rock_mat: ShaderMaterial = null

## Shells worked out before anyone walked in (prefetch), and the jobs still working them out.
static var _ready_shells: Dictionary = {}     # cache key -> Array of chunks
static var _jobs: Dictionary = {}             # cache key -> {"task": id, "out": Array}


func _ready() -> void:
	add_to_group("site_interior")
	interior_id = str(get_meta("interior_id", GameState.current_interior_id))
	def = def_override if not def_override.is_empty() else ContentDB.get_or_empty(interior_id)
	if def.is_empty() or not def.has("site"):
		Log.error("SiteInterior", "%s has no site to build" % interior_id)
		return
	if interior_id == "":
		interior_id = str(def.get("id", ""))
	_t0 = Time.get_ticks_usec()
	plan = SitePlan.make(def)
	for p in plan.problems:
		Log.warn("SiteInterior", p)
	_way_in()
	_note_piece()
	_build()


func paced() -> bool:
	if paced_override >= 0:
		return paced_override == 1
	return WorldPace.paced()


## Between two pieces of the build: paced, the time since the last is spent from the frame's
## budget, and once that is gone the build waits for the next frame.
func step() -> void:
	_note_piece()
	if not paced():
		return
	if WorldPace.left_usec() <= 0:
		await get_tree().process_frame
		_t0 = Time.get_ticks_usec()


## The time since the last piece went to standing a foe up (an Enemy's own body and parts, one
## piece whatever builds it): counted apart from the build's own pieces.
var longest_foe_us := 0


func note_foe() -> void:
	var now := Time.get_ticks_usec()
	var used := now - _t0
	main_us += used
	longest_foe_us = maxi(longest_foe_us, used)
	if paced():
		WorldPace.spend(used)
	_t0 = now


func _note_piece() -> void:
	var now := Time.get_ticks_usec()
	var used := now - _t0
	main_us += used
	if used > longest_piece_us:
		longest_piece_us = used
		longest_piece_at = "?"
		for f in get_stack():
			if str(f["function"]) not in ["_note_piece", "step"]:
				longest_piece_at = "%s:%d %s" % [str(f["source"]).get_file(), int(f["line"]), f["function"]]
				break
	if paced():
		WorldPace.spend(used)
		WorldPace.count("site", used)
	_t0 = now


# --- the way in, at once ----------------------------------------------------------------------------

func _way_in() -> void:
	var marker := Marker3D.new()
	marker.name = "Entrance"
	marker.position = plan.entrance + Vector3.UP * 0.05
	marker.rotation.y = plan.entrance_yaw
	add_child(marker)
	# a slab of floor under the way in, until the rock is there (at the rock's own floor height)
	_temp_floor = StaticBody3D.new()
	_temp_floor.name = "TempFloor"
	_temp_floor.set_meta("surface", "stone")
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 0.5, 8.0)
	cs.shape = box
	cs.position = plan.entrance + Vector3.DOWN * 0.25
	_temp_floor.add_child(cs)
	add_child(_temp_floor)


func _physics_process(_delta: float) -> void:
	if is_built:
		set_physics_process(false)
		return
	# held on the slab at the way in until the floor everywhere is there
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null or not _inside(player.global_position):
		return
	if _hold_at == Vector3.INF:
		_hold_at = to_global(plan.entrance + Vector3.UP * 0.05)
	player.global_position = _hold_at
	if "velocity" in player:
		player.set("velocity", Vector3.ZERO)


func _inside(at: Vector3) -> bool:
	var local := to_local(at)
	return plan.bounds.grow(4.0).has_point(local)


# --- the rock ---------------------------------------------------------------------------------------

static func cache_key(p: SitePlan) -> String:
	return "%s_%s" % [Ids.name_of(p.id), str([p.ops, SiteField.VERSION, p.spec.get("voxel", 0.55)]).md5_text().substr(0, 12)]


static func _field_args(p: SitePlan) -> Array:
	return [p.ops, p.bounds, float(p.spec.get("voxel", 0.55)), p.site_seed, float(p.spec.get("noise_freq", 0.1)), p.spec.get("palette", [])]


## Works out a site's rock on a worker thread before anyone walks in (the entrance's dressing asks,
## as its cell is raised), so the way in finds it ready. Does nothing if it is ready or on disk.
static func prefetch(site_def: Dictionary) -> void:
	if not site_def.has("site"):
		return
	var p := SitePlan.make(site_def)
	var key := cache_key(p)
	if _ready_shells.has(key) or _jobs.has(key) or FileAccess.file_exists("%s/%s.bin" % [CACHE_DIR, key]):
		return
	_start_job(key, p)


static func _start_job(key: String, p: SitePlan) -> void:
	var out: Array = []
	var args := _field_args(p)
	var path := "%s/%s.bin" % [CACHE_DIR, key]
	# worked out and written to the cache off the main thread: a shell is megabytes, and writing it
	# on the main thread was the longest piece of a paced build (49 ms)
	var task := WorkerThreadPool.add_task(func() -> void:
			var made: Array = SiteField.build(args[0], args[1], args[2], args[3], args[4], args[5])
			_save(path, made)
			out.append(made), false, "site shell")
	_jobs[key] = {"task": task, "out": out}


## The shell's chunks for a plan: from memory, from disk, from a job already running, or worked
## out now (on a worker thread when paced, waiting frames; at once when not).
func _shell() -> Array:
	var key := cache_key(plan)
	if _ready_shells.has(key):
		return _ready_shells[key]
	var path := "%s/%s.bin" % [CACHE_DIR, key]
	if FileAccess.file_exists(path):
		var fa := FileAccess.open(path, FileAccess.READ)
		if fa != null:
			var got: Variant = fa.get_var()
			fa.close()
			if typeof(got) == TYPE_ARRAY and not (got as Array).is_empty():
				_remember(key, got)
				return got
	if not paced() and not _jobs.has(key):
		var args := _field_args(plan)
		var made: Array = SiteField.build(args[0], args[1], args[2], args[3], args[4], args[5])
		_t0 = Time.get_ticks_usec()
		_save(path, made)
		_remember(key, made)
		return made
	if not _jobs.has(key):
		_start_job(key, plan)
	var job: Dictionary = _jobs[key]
	while not WorkerThreadPool.is_task_completed(int(job["task"])):
		await get_tree().process_frame
		_t0 = Time.get_ticks_usec()
	WorkerThreadPool.wait_for_task_completion(int(job["task"]))
	_jobs.erase(key)
	var result: Array = (job["out"] as Array)[0] if not (job["out"] as Array).is_empty() else []
	_remember(key, result)
	return result


static func _remember(key: String, shell: Array) -> void:
	# two shells kept, as Interiors keeps two interiors
	if _ready_shells.size() >= 2 and not _ready_shells.has(key):
		_ready_shells.erase(_ready_shells.keys()[0])
	_ready_shells[key] = shell


static func _save(path: String, shell: Array) -> void:
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var fa := FileAccess.open(path, FileAccess.WRITE)
	if fa != null:
		fa.store_var(shell)
		fa.close()


func _material() -> ShaderMaterial:
	if _rock_mat != null:
		return _rock_mat
	var mat := ShaderMaterial.new()
	mat.shader = ROCK_SHADER
	var formation := str(plan.spec.get("formation", "water"))
	var tuned: Dictionary = CaveInterior.ROCK_BY_FORMATION.get(formation, CaveInterior.ROCK_BY_FORMATION["water"])
	for key in tuned:
		mat.set_shader_parameter(key, tuned[key])
	mat.set_shader_parameter("brightness", float(tuned.get("brightness", 1.1)) * float(plan.spec.get("brightness", 1.0)))
	var wet := -10000.0
	for r in plan.rooms:
		for z in r["zones"]:
			if z["kind"] == "lake":
				wet = maxf(wet, float(z["level"]))
	if bool(plan.spec.get("wet", false)):
		wet = maxf(wet, (plan.rooms[0]["centre"] as Vector3).y - 2.0)
	mat.set_shader_parameter("wet_level", wet + 0.3)
	mat.set_shader_parameter("wet_fade", 1.6)
	_rock_mat = mat
	return mat


func _build() -> void:
	chunks = await _shell()
	await step()
	rock_body = StaticBody3D.new()
	rock_body.name = "Rock"
	rock_body.set_meta("surface", "stone")
	rock_body.collision_layer = 1 | (1 << 9)   # the world, and what the camera stops at
	rock_body.collision_mask = 0
	add_child(rock_body)
	var shell := Node3D.new()
	shell.name = "Shell"
	add_child(shell)
	var mat := _material()
	for ch in chunks:
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = ch["verts"]
		arrays[Mesh.ARRAY_NORMAL] = ch["normals"]
		arrays[Mesh.ARRAY_COLOR] = ch["colors"]
		arrays[Mesh.ARRAY_INDEX] = ch["indices"]
		if (ch["indices"] as PackedInt32Array).is_empty():
			continue
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.name = "Rock_%d_%d" % [(ch["key"] as Vector2i).x, (ch["key"] as Vector2i).y]
		mi.mesh = am
		mi.material_override = mat
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		shell.add_child(mi)
		await step()
		var cs := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(ch["faces"])
		cs.shape = shape
		cs.name = mi.name
		rock_body.add_child(cs)
		await step()
	if is_instance_valid(_temp_floor):
		_temp_floor.queue_free()
		_temp_floor = null
	dress = SiteDress.new(self, plan)
	await dress.build()
	_navigate()
	await step()
	if paced():
		# the foes stand up once they have a navigation mesh to walk (its bake is off the main thread)
		for i in 240:
			if nav_region.navigation_mesh.get_polygon_count() > 0:
				break
			await get_tree().process_frame
		await get_tree().physics_frame
		_t0 = Time.get_ticks_usec()
		await _finish()
	else:
		# built in one go inside Interiors' add_child: the foes and the arena are stood up once the
		# interior has been moved to its pocket (the same frame), since they keep world positions
		_finish.call_deferred()


func _finish() -> void:
	_t0 = Time.get_ticks_usec()
	await dress.people()
	is_built = true
	built.emit()
	Log.info("SiteInterior", "%s built: %d rooms, %d links, %d chunks, main thread %.1f ms (longest piece %.1f ms)" %
			[plan.name, plan.rooms.size(), plan.links.size(), chunks.size(), main_us / 1000.0, longest_piece_us / 1000.0])


# --- the ways foes walk -----------------------------------------------------------------------------

## A navigation mesh from the rock's own faces, baked off the main thread, so the foes in here
## path round rooms and down passages rather than into the wall.
func _navigate() -> void:
	nav_region = NavigationRegion3D.new()
	nav_region.name = "Nav"
	var nm := navmesh_settings()
	nav_region.navigation_mesh = nm
	add_child(nav_region)
	var src := source_geometry()
	if paced():
		NavigationServer3D.bake_from_source_geometry_data_async(nm, src, func() -> void:
				if is_instance_valid(nav_region):
					nav_region.navigation_mesh = nm)
	else:
		NavigationServer3D.bake_from_source_geometry_data(nm, src)
		nav_region.navigation_mesh = nm


static func navmesh_settings() -> NavigationMesh:
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.45
	# whole cells of cell_height, what Recast made of 1.8 and 0.45 (eight cells and one) while it
	# warned at every bake that they lost precision
	nm.agent_height = 2.0
	nm.agent_max_climb = 0.25
	nm.agent_max_slope = 40.0
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.region_min_size = 4.0
	return nm


func source_geometry() -> NavigationMeshSourceGeometryData3D:
	var src := NavigationMeshSourceGeometryData3D.new()
	for ch in chunks:
		src.add_faces(ch["faces"], Transform3D.IDENTITY)
	if dress != null:
		for f in dress.walk_faces:
			src.add_faces(f, Transform3D.IDENTITY)
	return src


func _process(_delta: float) -> void:
	if dress != null:
		dress.flicker()
