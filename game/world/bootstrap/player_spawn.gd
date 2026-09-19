class_name PlayerSpawn
extends Node
## Puts a body in the world, which nothing did until now: the Naming made a character, the
## world made ground, and the two never met.
##
## Where the character lands, in order:
##   1. a saved position, when a save is being loaded into this world;
##   2. the place named by `core:opening/new_game`, for a character who has just been named;
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

@export var spawn_place: String = ""
@export var install_services: bool = true
## A capture or a tool that wants the country without anybody in it turns this off.
@export var enabled: bool = true
## ...but a village with nobody in it cannot be judged, so a capture can ask for the world's
## services — and therefore its people — without a player body standing in the shot.
@export var services_without_a_body: bool = false

var player: Node3D = null


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
	if install_services:
		_install_services()
	var world := _world()
	if world != null and world.streamer != null:
		world.target = player
		world.streamer.target = player
		world.streamer.refresh()
	Log.info("PlayerSpawn", "%s stands at %s" % [player.name, str(player.global_position.round())])
	player_spawned.emit(player)
	return player


## Where the character starts, and on the ground.
func _landing() -> Vector3:
	var saved := _saved_position()
	var point := saved if saved != Vector3.INF else _opening_position()
	return _on_ground(point)


## A save being loaded into this world already knows where the body was standing.
func _saved_position() -> Vector3:
	var pending: Variant = SaveSystem.pending.get("player", {})
	if typeof(pending) != TYPE_DICTIONARY:
		return Vector3.INF
	var p: Variant = (pending as Dictionary).get("position", null)
	if p is Array and (p as Array).size() == 3:
		return Vector3(float(p[0]), float(p[1]), float(p[2]))
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
			return at
	if world != null:
		return world.place_position(world.spawn_place)
	return Vector3.ZERO


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
