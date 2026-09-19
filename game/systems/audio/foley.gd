extends Node
## Foley (autoload): every one-shot sound in the world, from one table and one pool of players.
##
## Other systems do not load streams or make players. They call:
##     Foley.play("sword_swing_light", position)      a sound in the world
##     Foley.play_ui("ui_page_turn")                  a sound in the player's head
##     Foley.footstep("vale_grass", position)         or let it work the surface out:
##     Foley.footstep(Foley.surface_at(position), position)
##
## The table is core:table/sfx, written by tools/audio/gen_sfx.py: each id maps to several
## variants, a level, a pitch variance and a bus. A random variant with a random pitch inside
## that variance is why a hundred footsteps never sound like one footstep played a hundred times.
##
## See README.md in this folder.

const TABLE_ID := "core:table/sfx"
const POOL_3D := 24
const POOL_2D := 8
const DEFAULT_SURFACE := "vale_grass"
const SURFACE_META := "surface"       ## StringName metadata a collider carries to name its surface
const MAX_HEAR_DISTANCE := 42.0
const SURFACE_RAY_DOWN := 2.2

signal played(id: String, position: Vector3)

var enabled := true
var rows: Dictionary = {}             ## id -> {files, volume_db, pitch_variance, bus}

var _pool3d: Array[AudioStreamPlayer3D] = []
var _pool2d: Array[AudioStreamPlayer] = []
var _rng := RandomNumberGenerator.new()
var _cache: Dictionary = {}           ## path -> AudioStream
var _missing: Dictionary = {}         ## ids already complained about, so a loop logs once
var _last_played: Dictionary = {}     ## id -> index, so the same variant is not picked twice running


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.seed = 5150
	if not ContentDB.is_loaded:
		await ContentDB.loaded
	_load_table()
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.name = "S3D_%d" % i
		p.bus = "SFX"
		p.max_distance = MAX_HEAR_DISTANCE
		p.unit_size = 4.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p)
		_pool3d.append(p)
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.name = "S2D_%d" % i
		p.bus = "UI"
		add_child(p)
		_pool2d.append(p)


func _load_table() -> void:
	var def := ContentDB.get_or_empty(TABLE_ID)
	rows = def.get("rows", {})
	if rows.is_empty():
		Log.warn("Foley", "%s is empty; run tools/audio/gen_sfx.py" % TABLE_ID)
	else:
		Log.info("Foley", "%d sfx ids" % rows.size())


func has(id: String) -> bool:
	return rows.has(id)


func ids() -> Array:
	var out: Array = rows.keys()
	out.sort()
	return out


# --- playing ---------------------------------------------------------------------------------

## Play `id` at a world position. Pass Vector3.INF (the default) for a non-positional sound.
## Returns the player used, or null if nothing was played.
func play(id: String, position: Vector3 = Vector3.INF, volume_db := 0.0) -> Node:
	if not enabled:
		return null
	var row := _row(id)
	if row.is_empty():
		return null
	var stream := _pick_stream(id, row)
	if stream == null:
		return null
	if position == Vector3.INF:
		return _play_2d(stream, row, volume_db, str(row.get("bus", "SFX")))
	var p := _free_3d()
	if p == null:
		return null
	p.stream = stream
	p.global_position = position
	p.volume_db = float(row.get("volume_db", 0.0)) + volume_db
	p.pitch_scale = _pitch(row)
	p.bus = _bus_for(str(row.get("bus", "SFX")))
	p.play()
	played.emit(id, position)
	return p


## Play `id` flat, on the UI bus: menus, notifications, anything in the player's head.
func play_ui(id: String, volume_db := 0.0) -> Node:
	if not enabled:
		return null
	var row := _row(id)
	if row.is_empty():
		return null
	var stream := _pick_stream(id, row)
	if stream == null:
		return null
	return _play_2d(stream, row, volume_db, "UI")


## A footstep on a named surface. Unknown surfaces fall back to vale_grass rather than silence,
## because a missing footstep reads as a bug and a wrong one does not.
func footstep(surface: String, position: Vector3 = Vector3.INF, volume_db := 0.0) -> Node:
	var id := "footstep_%s" % surface
	if not rows.has(id):
		id = "footstep_%s" % DEFAULT_SURFACE
	return play(id, position, volume_db)


func _play_2d(stream: AudioStream, row: Dictionary, volume_db: float, bus: String) -> Node:
	var p := _free_2d()
	if p == null:
		return null
	p.stream = stream
	p.volume_db = float(row.get("volume_db", 0.0)) + volume_db
	p.pitch_scale = _pitch(row)
	p.bus = bus
	p.play()
	played.emit(str(row.get("_id", "")), Vector3.INF)
	return p


func _row(id: String) -> Dictionary:
	if rows.has(id):
		var r: Dictionary = rows[id]
		r["_id"] = id
		return r
	if not _missing.has(id):
		_missing[id] = true
		Log.warn("Foley", "no sfx row for '%s'" % id)
	return {}


func _pitch(row: Dictionary) -> float:
	var v := float(row.get("pitch_variance", 0.0))
	return 1.0 if v <= 0.0 else clampf(1.0 + _rng.randf_range(-v, v), 0.25, 4.0)


## A random variant, never the same one twice running (a repeat is what makes a pool audible).
func _pick_stream(id: String, row: Dictionary) -> AudioStream:
	var files: Array = row.get("files", [])
	if files.is_empty():
		return null
	var idx := 0
	if files.size() > 1:
		idx = _rng.randi_range(0, files.size() - 1)
		if idx == int(_last_played.get(id, -1)):
			idx = (idx + 1) % files.size()
	_last_played[id] = idx
	return _stream(str(files[idx]))


func _stream(path: String) -> AudioStream:
	if _cache.has(path):
		return _cache[path]
	if not ResourceLoader.exists(path):
		Log.warn("Foley", "missing stream %s" % path)
		_cache[path] = null
		return null
	var s := load(path) as AudioStream
	_cache[path] = s
	return s


## Indoors, world sounds go through the Interior bus, which carries the room's reverb.
func _bus_for(bus: String) -> String:
	if bus == "SFX" and _indoors():
		return "Interior"
	return bus


func _indoors() -> bool:
	return not GameState.current_interior_id.is_empty()


func _free_3d() -> AudioStreamPlayer3D:
	for p in _pool3d:
		if is_instance_valid(p) and not p.playing:
			return p
	# everything is busy: steal the quietest, so a new sound is never simply dropped
	var quietest: AudioStreamPlayer3D = null
	for p in _pool3d:
		if is_instance_valid(p) and (quietest == null or p.volume_db < quietest.volume_db):
			quietest = p
	return quietest


func _free_2d() -> AudioStreamPlayer:
	for p in _pool2d:
		if is_instance_valid(p) and not p.playing:
			return p
	return _pool2d[0] if not _pool2d.is_empty() else null


# --- surfaces ---------------------------------------------------------------------------------

## What the ground is at a world position, for footsteps and for anything else that lands.
## A collider names its own surface with a `surface` metadata entry; otherwise the default.
func surface_at(position: Vector3) -> String:
	var tree := get_tree()
	if tree == null or position == Vector3.INF:
		return DEFAULT_SURFACE
	var world := tree.root.world_3d if tree.root else null
	if world == null:
		return DEFAULT_SURFACE
	var space := world.direct_space_state
	if space == null:
		return DEFAULT_SURFACE
	var from := position + Vector3.UP * 0.6
	var to := position + Vector3.DOWN * SURFACE_RAY_DOWN
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1 | (1 << 10)          # world and terrain
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return DEFAULT_SURFACE
	return surface_of(hit.get("collider"))


## The surface a node declares, walking up to its parents so a whole prop can carry one.
func surface_of(node: Object) -> String:
	var n := node as Node
	var steps := 0
	while n != null and steps < 4:
		if n.has_meta(SURFACE_META):
			var s := str(n.get_meta(SURFACE_META))
			if rows.has("footstep_%s" % s):
				return s
			if not _missing.has("surface:" + s):
				_missing["surface:" + s] = true
				Log.warn("Foley", "collider declares unknown surface '%s'" % s)
			return DEFAULT_SURFACE
		n = n.get_parent()
		steps += 1
	return DEFAULT_SURFACE


## Cached streams and playing players both hold decoders open, so both go on the way out.
func release() -> void:
	stop_all()
	_release_players()
	_cache.clear()

## Stop and detach every player under this node, whichever code path made it.
## A stream that is still playing keeps its decoder alive, and a node queue_freed during
## shutdown never reaches its deferred free, so both show up as leaks when the engine exits.
func _release_players() -> void:
	for child in get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer3D or child is AudioStreamPlayer2D:
			child.stop()
			child.stream = null


func _exit_tree() -> void:
	release()


func stop_all() -> void:
	for p in _pool3d:
		if is_instance_valid(p):
			p.stop()
	for p in _pool2d:
		if is_instance_valid(p):
			p.stop()


func active_count() -> int:
	var n := 0
	for p in _pool3d:
		if is_instance_valid(p) and p.playing:
			n += 1
	for p in _pool2d:
		if is_instance_valid(p) and p.playing:
			n += 1
	return n
