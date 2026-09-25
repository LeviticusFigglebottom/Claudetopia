class_name PlayerSpawn
extends Node
## Puts a body in the world, which nothing did until now: the Naming made a character, the
## world made ground, and the two never met.
##
## Where the character lands, in order:
##   1. a saved position, when a save is being loaded into this world;
##   2. the place named by `core:opening/new_game`, for a character who has just been named: where
##      the atlas's own start (the manifest's `start`, written by the world builder) stands on it,
##      and facing its way, else the place itself;
##   3. the world's own `spawn_place`.
## Whichever it is, the body is set down on the terrain rather than at the place's nominal
## height, so nobody starts inside a hill or falling from one.
##
## It also installs the world services (law, market, property, loot) through `GameServices`,
## because a player standing in a world with no law is the state we shipped once already.

signal player_spawned(player: Node3D)

const PLAYER_SCENE := "res://actors/player/player.tscn"
const OPENING := "core:opening/new_game"
## How far above the ground the body is placed, so the first frame settles down rather than up.
const DROP_IN := 0.6
## Where a new game may begin: see dry_ground_near.
const DRY_PROBE := 8.0
const DRY_MARGIN := 2.0
const WALKABLE_RELIEF := 6.0
const DRY_SEARCH_M := 800.0
## How far the manifest's start may stand from the opening's place and still be its start. The
## atlas writes both, so they agree; a start further off is another map's, or the story opens
## somewhere the atlas did not draw its start, and the place wins.
const START_ON_PLACE_M := 60.0

@export var spawn_place: String = ""
@export var install_services: bool = true
## A capture or a tool that wants the country without anybody in it turns this off.
@export var enabled: bool = true
## ...but a village with nobody in it cannot be judged, so a capture can ask for the world's
## services — and therefore its people — without a player body standing in the shot.
@export var services_without_a_body: bool = false

var player: Node3D = null
## The slot this world was loaded from, or "" for a new game: a loaded game is never a new one,
## whatever its flags say (GameServices.begin_new_game).
var loaded_slot := ""
## The compass bearing a new game's body faces from the first frame (the manifest's `facing_deg`),
## or NAN when nothing said: a loaded body keeps its own.
var start_facing_deg := NAN


func _ready() -> void:
	add_to_group("player_spawn")
	if not enabled:
		if services_without_a_body and install_services:
			var host := _world()
			if host != null and not host.is_world_ready:
				await host.world_ready
			_install_services()
		return
	# A child is ready before its parent, so World.instance is not set yet and the terrain
	# certainly is not: a body placed now lands at zero metres in the middle of the map.
	var world := _world()
	if world != null and not world.is_world_ready:
		await world.world_ready
	spawn()


## The world this belongs to, found by looking up rather than through World.instance, which the
## parent has not set yet while its children are readying.
func _world() -> World:
	var n := get_parent()
	while n != null:
		if n is World:
			return n as World
		n = n.get_parent()
	return World.instance


## Puts the body down and hands back whatever is now standing in the world (an existing player
## is left alone, so a scene that ships its own is not given a second one).
func spawn() -> Node3D:
	loaded_slot = load_pending_slot()
	var existing := get_tree().get_first_node_in_group("player")
	if existing is Node3D:
		player = existing
	else:
		var packed := load(PLAYER_SCENE) as PackedScene
		if packed == null:
			Log.error("PlayerSpawn", "no player scene at %s" % PLAYER_SCENE)
			return null
		player = packed.instantiate() as Node3D
		# The body belongs to the world it is standing in, not to whatever scene happens to be
		# current: parented anywhere else it outlives the world and haunts the next one.
		var host: Node = _world()
		if host == null:
			host = get_tree().current_scene if get_tree().current_scene != null else get_parent()
		host.add_child(player)
	player.global_position = _landing()
	if not is_nan(start_facing_deg):
		_face(player, start_facing_deg)
	if install_services:
		_install_services()
	var world := _world()
	if world != null:
		world.follow(player)
	Log.info("PlayerSpawn", "%s stands at %s" % [player.name, str(player.global_position.round())])
	player_spawned.emit(player)
	return player


## The slot the title menu's Continue and Load, and `--load=<slot>`, asked for. They wrote the
## flag and nothing read it, so every one of them stood a new Foundling up at the Hushline
## Stair with the save untouched on disk. Read here, before the body: the save's sections then
## reach the autoloads at once and wait in `SaveSystem.pending` for the player and its systems,
## which is what `_saved_position` and `Player._ready` expect. Returns the slot that was loaded.
static func load_pending_slot() -> String:
	var slot := str(GameState.get_flag("_pending_load_slot", ""))
	if slot.is_empty():
		return ""
	GameState.clear_flag("_pending_load_slot")
	var err := SaveSystem.load_from_slot(slot)
	if err != OK:
		Log.error("PlayerSpawn", "could not load slot '%s': %s" % [slot, error_string(err)])
		EventBus.emit_notify("That save could not be read (%s)." % error_string(err), "warning")
		return ""
	return slot


## Where the character starts, and on the ground.
func _landing() -> Vector3:
	var saved := _saved_position()
	if saved != Vector3.INF:
		return _on_ground(saved)
	var start := _opening_position()
	var provider := _terrain()
	if provider != null:
		var ashore := dry_ground_near(provider, start)
		if Vector2(ashore.x - start.x, ashore.z - start.z).length() > 0.5:
			Log.info("PlayerSpawn", "the opening place stands in the water at %s; the body comes ashore %d m away at %s"
					% [str(start.round()), int(Vector2(ashore.x - start.x, ashore.z - start.z).length()), str(ashore.round())])
		start = ashore
	return _on_ground(start)


## Dry, walkable ground at `point` or the nearest to it: the spot and eight around it DRY_PROBE
## away all out of the water and at least DRY_MARGIN above the nearest water surface, with no
## more than WALKABLE_RELIEF of rise across them. The opening place, the Hushline Stair, is one
## 8 m pad at sea level with 20 m of sea round it on every side and the cliffs 130 m off; a new
## game stood the body on the water there, below the land Terrain3D drew, among floating trees.
## A saved position is never moved: only where a story opens is searched.
static func dry_ground_near(provider: Object, point: Vector3, max_radius := DRY_SEARCH_M) -> Vector3:
	if _dry_at(provider, point.x, point.z):
		return Vector3(point.x, float(provider.call("get_height", point.x, point.z)), point.z)
	var r := DRY_PROBE
	while r <= max_radius:
		var steps := maxi(12, int(TAU * r / DRY_PROBE))
		for k in steps:
			var a := TAU * float(k) / float(steps)
			var x := point.x + cos(a) * r
			var z := point.z + sin(a) * r
			if _dry_at(provider, x, z):
				return Vector3(x, float(provider.call("get_height", x, z)), z)
		r += DRY_PROBE
	return point


static func _dry_at(provider: Object, x: float, z: float) -> bool:
	var lo := INF
	var hi := -INF
	for dz in [-DRY_PROBE, 0.0, DRY_PROBE]:
		for dx in [-DRY_PROBE, 0.0, DRY_PROBE]:
			var px: float = x + dx
			var pz: float = z + dz
			if bool(provider.call("is_water", px, pz)):
				return false
			var ground := float(provider.call("get_height", px, pz))
			if ground < float(provider.call("nearest_water_level", px, pz)) + DRY_MARGIN:
				return false
			lo = minf(lo, ground)
			hi = maxf(hi, ground)
	return hi - lo <= WALKABLE_RELIEF


## A save being loaded into this world already knows where the body was standing: beside the
## place it pinned, which is where it was unless the map has been redrawn since (PlaceRef).
func _saved_position() -> Vector3:
	var pending: Variant = SaveSystem.pending.get("player", {})
	if typeof(pending) != TYPE_DICTIONARY:
		return Vector3.INF
	var p: Variant = (pending as Dictionary).get("position", null)
	if p is Array and (p as Array).size() == 3:
		var at := Vector3(float(p[0]), float(p[1]), float(p[2]))
		return PlaceRef.follow(at, (pending as Dictionary).get("near", null))
	return Vector3.INF


## The place the story opens at, then the world's own idea of where to start.
func _opening_position() -> Vector3:
	var world := _world()
	var wanted := spawn_place
	if wanted == "":
		wanted = str(ContentDB.get_or_empty(OPENING).get("place", ""))
	if world != null and wanted != "":
		var at := world.place_position(wanted)
		if at != Vector3.ZERO:
			var provider := _terrain()
			var start := manifest_start(provider.manifest if provider != null else {}, wanted, at)
			if not start.is_empty():
				start_facing_deg = float(start["facing_deg"])
				return start["pos"]
			return at
	if world != null:
		return world.place_position(world.spawn_place)
	return Vector3.ZERO


## The atlas's start as the world builder wrote it (`"start": {"pos", "facing_deg", "place"}`), when
## it names `place_id` and stands on it (`place_at`, where this world stands that place): {"pos":
## Vector3, "facing_deg": float}. Empty for a manifest with no start, a start of another place, or
## one that has drifted off its place, which is logged, and the place itself is used.
static func manifest_start(manifest: Dictionary, place_id: String, place_at: Vector3) -> Dictionary:
	var start: Variant = manifest.get("start", null)
	if typeof(start) != TYPE_DICTIONARY:
		return {}
	var st: Dictionary = start
	var raw: Variant = st.get("pos", null)
	if str(st.get("place", "")) != place_id or typeof(raw) != TYPE_ARRAY or (raw as Array).size() < 3:
		return {}
	var pos := Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	var off := Vector2(pos.x - place_at.x, pos.z - place_at.z).length()
	if off > START_ON_PLACE_M:
		Log.warn("PlayerSpawn", "the manifest's start stands %d m from %s; the place is used" % [int(off), place_id])
		return {}
	return {"pos": pos, "facing_deg": float(st.get("facing_deg", 0.0))}


## Turns a body, and the camera behind it, to a compass bearing (0 north = -z, 90 east = +x).
static func _face(body: Node3D, bearing_deg: float) -> void:
	var yaw := -deg_to_rad(bearing_deg)
	body.rotation.y = yaw
	var rig: Variant = body.get("camera_rig")
	if rig is Node3D:
		(rig as Node3D).set("yaw", yaw)


func _on_ground(point: Vector3) -> Vector3:
	var provider := _terrain()
	if provider == null:
		return point
	var ground := provider.get_height(point.x, point.z)
	return Vector3(point.x, ground + DROP_IN, point.z)


func _install_services() -> void:
	if get_tree().get_first_node_in_group("game_services") != null:
		return
	var services := GameServices.new()
	services.name = "GameServices"
	services.add_to_group("game_services")
	var host: Node = _world()
	(host if host != null else get_parent()).add_child(services)


## The ground, through this world rather than the singleton.
func _terrain() -> TerrainProvider:
	var world := _world()
	return world.provider if world != null else null
