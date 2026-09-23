extends Node
## Foley (autoload): every one-shot sound in the world, from one table and one pool of players.
##
## Other systems do not load streams or make players. They call:
##     Foley.play("sword_swing_light", position)      a sound in the world
##     Foley.play_ui("ui_page_turn")                  a sound in the player's head
##     Foley.footstep("vale_grass", position)         or let it work the surface out:
##     Foley.footstep(Foley.surface_at(position), position)
##
## Who calls what: every walking body steps through a Footfalls (actors/shared/footfalls.gd);
## Actor.take_hit sounds the victim's material, a block or a parry; weapons whoosh on hit_start;
## bows, arrows and sayings sound their draw, flight, cast and landing; UiKit buttons click. The
## rest -- chests, coins, pick-ups, doors, menus, meals, armour, the Hearthstone, the Echo -- is
## heard here, off EventBus, so the systems that cause them do not need to know about sound.
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
## Water deeper than this over the feet is walked in, not on (metres).
const WADE_DEPTH := 0.08
## Menus that open and close like a book, and the one that unrolls.
const BOOK_MENUS := ["journal", "book", "sayings", "skills"]
const PAPER_MENUS := ["inventory", "container", "trade", "crafting", "deed", "job_board"]
const BRASS_MENUS := ["pause", "settings", "save_load"]
const REFUSAL_NOTES := ["warning", "warn", "refusal"]
## A cue heard off EventBus plays at most once in this long (ms): taking everything from a chest,
## or a Calling's starting kit arriving, is one pick-up, not a pile of them struck together.
const CUE_GAP_MS := 150
## Interiors whose door has a bell over it: a tavern's, rung by whoever comes in.
const TAVERN_TRADES := ["innkeeper", "tavern", "alewife"]
## What the terrain's paint is underfoot, as a footstep surface: the world builder lays snow above
## the snow line, sand on the western tide-flats, cobbles in a market street and a dirt track on
## every road, and the feet should hear the paint they are standing on (tools/world/worldgen/
## surface.py names the twenty-one textures).
const TEXTURE_SURFACE := {
	"vale_grass": "vale_grass", "orchard_grass": "vale_grass", "barley": "vale_grass",
	"grey_grass": "vale_grass", "heather": "vale_grass", "moss": "vale_grass",
	"chalk": "stone", "granite": "stone", "limestone": "stone", "fused_stone": "stone", "cobbles": "stone",
	"dirt_path": "dirt", "forest_floor": "dirt",
	"mud": "mud", "peat": "mud", "lake_bed": "mud",
	"scree": "gravel", "shingle": "gravel",
	"snow": "snow", "sand_flats": "sand", "ash_soil": "ash",
}

signal played(id: String, position: Vector3)

var enabled := true
var rows: Dictionary = {}             ## id -> {files, volume_db, pitch_variance, bus}

var _pool3d: Array[AudioStreamPlayer3D] = []
var _pool2d: Array[AudioStreamPlayer] = []
var _rng := RandomNumberGenerator.new()
var _cache: Dictionary = {}           ## path -> AudioStream
var _missing: Dictionary = {}         ## ids already complained about, so a loop logs once
var _last_played: Dictionary = {}     ## id -> index, so the same variant is not picked twice running
var _cue_at: Dictionary = {}          ## cue id -> Time.get_ticks_msec() it last played


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
	EventBus.container_opened.connect(_on_container_opened)
	EventBus.item_acquired.connect(_on_item_acquired)
	EventBus.marks_changed.connect(_on_marks_changed)
	EventBus.hearthstone_rested.connect(_on_hearthstone_rested)
	EventBus.echo_recovered.connect(_on_echo_recovered)
	EventBus.item_used.connect(_on_item_used)
	EventBus.item_equipped.connect(_on_item_equipped)
	EventBus.menu_opened.connect(_on_menu_opened)
	EventBus.menu_closed.connect(_on_menu_closed)
	EventBus.interior_entered.connect(_on_interior_entered)
	EventBus.interior_exited.connect(_on_interior_exited)
	EventBus.notify.connect(_on_notify)


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
	# a stolen player is still playing; stopping it first releases the playback it holds
	p.stop()
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
	p.stop()
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
## A collider names its own surface with a `surface` metadata entry (an interior's floor, a
## prop); ground that says nothing (the terrain) is the water over it or its region's `ground`.
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
		# The overworld's ground has no collider (the terrain is a heightfield bodies are snapped
		# to), so nothing under the ray means the terrain, when there is one.
		return ground_surface(position) if World.terrain() != null else DEFAULT_SURFACE
	var declared := _declared_surface(_shape_node(hit))
	if declared.is_empty():
		declared = _declared_surface(hit.get("collider"))
	if declared.is_empty():
		return ground_surface(position)
	return _known_surface(declared)


## The CollisionShape3D a ray hit, so one body can carry a timber deck and a stone parapet and say
## which is which: a shape names its own surface before its body is asked.
static func _shape_node(hit: Dictionary) -> Node:
	var body := hit.get("collider") as CollisionObject3D
	var index := int(hit.get("shape", -1))
	if body == null or index < 0:
		return null
	var owner_id := body.shape_find_owner(index)
	if owner_id < 0:
		return null
	return body.shape_owner_get_owner(owner_id) as Node


## The surface a node declares, walking up to its parents so a whole prop can carry one.
func surface_of(node: Object) -> String:
	var declared := _declared_surface(node)
	return DEFAULT_SURFACE if declared.is_empty() else _known_surface(declared)


func _declared_surface(node: Object) -> String:
	var n := node as Node
	var steps := 0
	while n != null and steps < 4:
		if n.has_meta(SURFACE_META):
			return str(n.get_meta(SURFACE_META))
		n = n.get_parent()
		steps += 1
	return ""


func _known_surface(s: String) -> String:
	if rows.has("footstep_%s" % s):
		return s
	if not _missing.has("surface:" + s):
		_missing["surface:" + s] = true
		Log.warn("Foley", "collider declares unknown surface '%s'" % s)
	return DEFAULT_SURFACE


## Ground that names no surface of its own: water when the feet are in it, otherwise the region's
## `identity.ground` (chalk grass in the Vale, shingle round the lake, mud in the marsh ...).
func ground_surface(position: Vector3) -> String:
	var region := GameState.current_region_id
	var terrain := World.terrain()
	if terrain != null:
		if terrain.water_level_at(position.x, position.z) - position.y > WADE_DEPTH:
			return "water"
		var painted := str(TEXTURE_SURFACE.get(terrain.texture_at(position.x, position.z), ""))
		if not painted.is_empty() and rows.has("footstep_%s" % painted):
			return painted
		var here := terrain.region_id_at(position.x, position.z)
		if not here.is_empty():
			region = here
	var ident: Dictionary = ContentDB.get_or_empty(region).get("identity", {})
	var ground := str(ident.get("ground", ""))
	return ground if rows.has("footstep_%s" % ground) else DEFAULT_SURFACE


## Whether a sound at `position` is worth making: within `hear` metres of the player (or there
## is no player to be near, as in most tests).
func near_listener(position: Vector3, hear: float = MAX_HEAR_DISTANCE) -> bool:
	var tree := get_tree()
	var p := tree.get_first_node_in_group("player") as Node3D if tree != null else null
	return p == null or p.global_position.distance_to(position) <= hear


# --- what things are made of, and what they sound like -------------------------------------------

## What a body sounds like when it is struck, from its def: `material` when the def says, else
## what its tags make it (a construct is stone, a treant wood, a knight or anything in heavy mail
## metal), else flesh.
static func material_for(def: Dictionary, armour: float = 0.0) -> String:
	var m := str(def.get("material", ""))
	if m in ["flesh", "metal", "stone", "wood"]:
		return m
	var tags: Array = def.get("tags", [])
	if tags.has("construct") or tags.has("stone"):
		return "stone"
	if tags.has("treant") or tags.has("plant"):
		return "wood"
	if tags.has("knight") or armour >= 11.0:
		return "metal"
	return "flesh"


## The whoosh a swing makes, by the weapon's class; "" for the things that bite and claw.
static func swing_for(weapon_class: String, heavy: bool = false) -> String:
	match weapon_class:
		"bite", "claw", "tusk", "bow", "staff_cast":
			return ""
		"axe", "greataxe":
			return "axe_swing"
		"mace", "hammer", "club", "flail", "staff", "maul":
			return "mace_swing"
	return "sword_swing_heavy" if heavy else "sword_swing_light"


# --- heard off the EventBus ------------------------------------------------------------------------

func _player_position() -> Vector3:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	return p.global_position + Vector3.UP if p != null else Vector3.INF


func _on_container_opened(container: Node, _actor: Node) -> void:
	play("chest_open", (container as Node3D).global_position if container is Node3D else Vector3.INF)


## Whether a cue may play now (and, if it may, that it has): see CUE_GAP_MS.
func _cue_ready(id: String) -> bool:
	var now := Time.get_ticks_msec()
	if now - int(_cue_at.get(id, -100000)) < CUE_GAP_MS:
		return false
	_cue_at[id] = now
	return true


func _on_item_acquired(_item_id: String, _count: int) -> void:
	if _cue_ready("pick_up"):
		play("pick_up", _player_position())


func _on_marks_changed(_total: int, delta: int) -> void:
	if delta != 0 and _cue_ready("coins"):
		play("coins_many" if delta >= 50 else "coins_few")


func _on_hearthstone_rested(_hearthstone_id: String) -> void:
	play_ui("hearthstone_rest")


func _on_echo_recovered(_marks: int) -> void:
	play_ui("echo_recovered")


func _on_item_used(item_id: String, _effects: Array) -> void:
	var def := ContentDB.get_or_empty(item_id)
	var tags: Array = def.get("tags", [])
	if str(def.get("category", "")) == "potion" or tags.has("potion"):
		play("potion_drink", _player_position())
	elif tags.has("food") or str(def.get("category", "")) == "food":
		play("eat", _player_position())


func _on_item_equipped(slot: String, item_id: String) -> void:
	if not (slot in ["head", "body", "hands", "feet"]) or item_id.is_empty():
		return
	var armour: Dictionary = ContentDB.get_or_empty(item_id).get("armour", {})
	if armour.is_empty():
		return
	play("armour_light" if str(armour.get("weight_class", "light")) == "light" else "armour_heavy", _player_position())


func _on_menu_opened(menu_id: String) -> void:
	if menu_id in BOOK_MENUS:
		play_ui("ui_book_open")
	elif menu_id == "map":
		play_ui("ui_map_unroll")
	elif menu_id in PAPER_MENUS:
		play_ui("ui_paper_slide")
	elif menu_id in BRASS_MENUS:
		play_ui("ui_brass_click")


func _on_menu_closed(menu_id: String) -> void:
	if menu_id in BOOK_MENUS:
		play_ui("ui_book_close")


func _on_notify(_text: String, kind: String) -> void:
	if kind in REFUSAL_NOTES:
		play_ui("ui_error_thunk")
	elif kind == "quest":
		play_ui("ui_page_turn")


## A house door is wood; the way into a deep place (a def that says what formed it) is iron.
static func door_for(interior_id: String, opening: bool) -> String:
	var deep := ContentDB.get_or_empty(interior_id).has("formed_by")
	return "door_%s_%s" % ["iron" if deep else "wood", "open" if opening else "close"]


func _on_interior_entered(interior_id: String) -> void:
	play(door_for(interior_id, true))
	# A tavern door has a bell over it, and it rings for whoever comes in.
	if str(ContentDB.get_or_empty(interior_id).get("trade", "")) in TAVERN_TRADES:
		play("bell_tavern")


func _on_interior_exited(interior_id: String) -> void:
	play(door_for(interior_id, false))


## Cached streams and playing players both hold decoders open, so both go on the way out.
func release() -> void:
	# Nothing may start again after this: a frame running between the release and the
	# engine shutting down would put streams back and they would be reported as leaks.
	enabled = false
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
