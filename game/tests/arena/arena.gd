extends Node3D
## Flat combat test arena (boot arg `--arena`). Ground, obstacles, a respawn marker (no
## Hearthstone content needed), the player, and the four Hearthvale enemies via EnemySpawner,
## plus an on-screen readout of HP/stamina/poise/state for player and enemies.
##
## Debug commands registered here (use `-- --cmd="..."` for scripted runs):
##   arena_report            one-line state of every actor
##   arena_spawn <enemy_id> [x] [z]
##   arena_hurt <hp>         damage the player
##   arena_kill_enemies
##   arena_give <item_id>    equip a weapon/shield on the player
##   arena_reset

const PLAYER_SCENE := "res://actors/player/player.tscn"
const GROUND_SIZE := 70.0
const PLAYER_START := Vector3(0.0, 0.6, 6.0)
const SPAWNS := [
	{"def": "core:enemy/roadside_bandit", "pos": Vector3(0.0, 0.5, -4.0), "yaw": 180.0},
	{"def": "core:enemy/down_wolf", "pos": Vector3(-12.0, 0.5, -8.0), "yaw": 150.0, "count": 3, "radius": 2.2, "group": "wolves"},
	{"def": "core:enemy/hedge_wight", "pos": Vector3(11.0, 0.5, -7.0), "yaw": 200.0},
	{"def": "core:enemy/bristleback", "pos": Vector3(2.0, 0.5, -20.0), "yaw": 180.0},
]

signal verification_finished(failures: int)

const VERIFY_TIMEOUT := 240.0
const SIGNPOST_SCRIPT := "res://tests/arena/signpost.gd"
const SIGNPOST_POSITION := Vector3(3.0, 0.0, 4.5)

var player: Player = null
var spawner: EnemySpawner = null
var signpost: StaticBody3D = null
var _verify_failures: int = -1
var readout: Label = null
var respawn_point: Marker3D = null
var _elapsed: float = 0.0


func _ready() -> void:
	add_to_group("arena")
	_build_environment()
	_build_ground()
	_build_obstacles()
	_build_signpost()
	respawn_point = Marker3D.new()
	respawn_point.name = "RespawnPoint"
	respawn_point.position = PLAYER_START
	add_child(respawn_point)
	_spawn_player()
	# No Hearthstone content in the arena: register the start marker as the rest point, which is
	# what a Hearthstone would do. Without this, Hearth's fallback respawns you where you fell.
	Hearth.rest_at("arena", PLAYER_START, 0.0, false)
	_spawn_enemies()
	_build_hud()
	_register_commands()
	Log.info("Arena", "ready: player at %s, %d enemies" % [str(PLAYER_START), spawner.all().size()])
	if _has_arg("--verify"):
		call_deferred("_run_verification_and_quit")


func _has_arg(flag: String) -> bool:
	return OS.get_cmdline_user_args().has(flag)


## `--arena --verify [--out=<dir>]`: run the scripted checks, then quit non-zero on any failure.
## A watchdog quits with 2 if the run stalls, so a broken build fails instead of hanging.
func _run_verification_and_quit() -> void:
	verification_finished.connect(func(failures: int) -> void:
		await get_tree().create_timer(0.3).timeout
		get_tree().quit(1 if failures > 0 else 0), CONNECT_ONE_SHOT)
	get_tree().create_timer(VERIFY_TIMEOUT).timeout.connect(func() -> void:
		if _verify_failures < 0:
			Log.error("Arena", "verification did not finish within %d s" % VERIFY_TIMEOUT)
			get_tree().quit(2))
	Debug.run("arena_verify")


# --- scene ----------------------------------------------------------------------------------

func _build_environment() -> void:
	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color(0.45, 0.58, 0.75)
	mat.sky_horizon_color = Color(0.88, 0.85, 0.74)
	mat.ground_bottom_color = Color(0.3, 0.3, 0.26)
	mat.ground_horizon_color = Color(0.7, 0.68, 0.58)
	sky.sky_material = mat
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 1.0
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-42.0, 38.0, 0.0)
	sun.light_color = Color(1.0, 0.9, 0.72)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)


func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = 1
	add_child(body)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.5, 0.3)
	mat.roughness = 0.95
	mesh.material_override = mat
	body.add_child(mesh)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(GROUND_SIZE, 1.0, GROUND_SIZE)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	body.add_child(shape)


func _build_obstacles() -> void:
	var specs := [
		{"pos": Vector3(-6.0, 0.6, -2.0), "size": Vector3(2.4, 1.2, 2.4), "color": Color(0.55, 0.53, 0.48)},
		{"pos": Vector3(7.0, 0.45, 1.0), "size": Vector3(3.0, 0.9, 1.4), "color": Color(0.5, 0.48, 0.44)},
		{"pos": Vector3(0.0, 1.5, -14.0), "size": Vector3(6.0, 3.0, 1.0), "color": Color(0.46, 0.44, 0.42)},
		{"pos": Vector3(-14.0, 1.0, 2.0), "size": Vector3(1.2, 2.0, 6.0), "color": Color(0.48, 0.46, 0.43)},
		{"pos": Vector3(5.0, 0.35, 8.0), "size": Vector3(2.0, 0.7, 2.0), "color": Color(0.58, 0.55, 0.5)}
	]
	var i := 0
	for s in specs:
		var body := StaticBody3D.new()
		body.name = "Obstacle%d" % i
		body.collision_layer = 1
		body.position = s["pos"]
		add_child(body)
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = s["size"]
		mesh.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = s["color"]
		mat.roughness = 0.9
		mesh.material_override = mat
		body.add_child(mesh)
		var shape := CollisionShape3D.new()
		var col := BoxShape3D.new()
		col.size = s["size"]
		shape.shape = col
		body.add_child(shape)
		i += 1


## One interactable, so the Interactor's prompt path is exercised in the arena.
func _build_signpost() -> void:
	signpost = StaticBody3D.new()
	signpost.name = "Signpost"
	signpost.set_script(load(SIGNPOST_SCRIPT))
	signpost.position = SIGNPOST_POSITION
	add_child(signpost)


func _spawn_player() -> void:
	var packed := load(PLAYER_SCENE) as PackedScene
	player = packed.instantiate() as Player
	add_child(player)
	player.global_position = PLAYER_START
	player.equip_weapon("core:item/iron_sword")
	player.equip_offhand("core:item/round_shield")
	player.equip_armour("core:item/wool_tunic")
	# The arena's Foundling is a Sayer for the purposes of the checks: a saying has to be
	# taught before it can be readied, so teach the four this bench uses.
	var prog := player.progression()
	if prog != null and prog.has_method("learn_spell"):
		for saying in ["core:spell/kindle_bolt", "core:spell/hush_frost", "core:spell/mend", "core:spell/ward"]:
			prog.call("learn_spell", saying)
	player.equip_spell("core:spell/kindle_bolt")
	player.set_quick_slot(0, "core:spell/kindle_bolt")
	player.set_quick_slot(1, "core:spell/hush_frost")
	player.set_quick_slot(2, "core:spell/mend")
	player.set_quick_slot(3, "core:spell/ward")


func _spawn_enemies() -> void:
	spawner = EnemySpawner.new()
	spawner.name = "EnemySpawner"
	spawner.spawns = SPAWNS.duplicate(true)
	spawner.spawn_on_ready = false
	add_child(spawner)
	spawner.spawn_all()


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "DebugHUD"
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(12.0, 12.0)
	panel.modulate = Color(1, 1, 1, 0.9)
	layer.add_child(panel)
	readout = Label.new()
	readout.name = "Readout"
	readout.add_theme_font_size_override("font_size", 14)
	panel.add_child(readout)


# --- runtime --------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_elapsed += delta
	if readout != null:
		readout.text = report()


## One multi-line status block: the arena's debug readout and its scripted-run report.
func report() -> String:
	var lines: Array[String] = []
	if is_instance_valid(player):
		lines.append("PLAYER %s  hp %5.1f/%5.1f  st %5.1f/%5.1f  po %5.1f/%5.1f  mana %5.1f  state %s%s%s" % [
			player.display_name, player.health, player.max_health,
			player.stamina, player.max_stamina, player.poise, player.max_poise, player.mana,
			player.state_name(),
			"  IFRAMES" if player.is_in_iframes() else "",
			"  BLOCK" if player.is_blocking else ""])
		lines.append("       weapon %s  lock %s  sneak %s  load %.2f" % [
			player.weapon.display_name(),
			(player.lock.target.name if player.lock.is_locked() else "-"),
			str(player.is_sneaking), player.load_ratio])
	if spawner != null:
		for e in spawner.all():
			lines.append("%-16s hp %5.1f/%5.1f  po %5.1f/%5.1f  %-10s det %.2f  d %5.1f%s%s" % [
				Ids.name_of(e.enemy_id), e.health, e.max_health, e.poise, e.max_poise,
				("DEAD" if e.dead else e.state_name()), e.perception.detection,
				(e.global_position.distance_to(player.global_position) if is_instance_valid(player) else 0.0),
				"  STUN" if (not e.dead and e.is_stunned()) else "",
				"  HA" if e.poise_comp.has_hyper_armour() else ""])
	lines.append("t %.1f s" % _elapsed)
	return "\n".join(lines)


func reset() -> void:
	if is_instance_valid(player):
		player.respawn(PLAYER_START, 0.0)
	if spawner != null:
		for e in spawner.all():
			e.reset_to_spawn()


# --- debug commands ---------------------------------------------------------------------------

func _register_commands() -> void:
	Debug.register("arena_report", func(_a: Array) -> String:
		return report(), "arena: state of every actor")
	Debug.register("arena_spawn", func(a: Array) -> String:
		if a.is_empty():
			return "usage: arena_spawn <enemy_id> [x] [z]"
		var id: String = a[0] if a[0].contains(":") else "core:enemy/%s" % a[0]
		var pos := Vector3(float(a[1]) if a.size() > 1 else 0.0, 0.5, float(a[2]) if a.size() > 2 else -5.0)
		var e := spawner.spawn_one(id, pos, PI)
		return "spawned %s" % id if e else "unknown enemy", "arena: spawn an enemy")
	Debug.register("arena_hurt", func(a: Array) -> String:
		if not is_instance_valid(player):
			return "no player"
		player.apply_raw_damage(float(a[0]) if a.size() > 0 else 10.0, "blunt", null)
		return "hp %.1f" % player.health, "arena: damage the player")
	Debug.register("arena_kill_enemies", func(_a: Array) -> String:
		var n := 0
		for e in spawner.alive():
			e.die(player)
			n += 1
		return "killed %d" % n, "arena: kill every living enemy")
	Debug.register("arena_give", func(a: Array) -> String:
		if a.is_empty() or not is_instance_valid(player):
			return "usage: arena_give <item_id>"
		var id: String = a[0] if a[0].contains(":") else "core:item/%s" % a[0]
		if not ContentDB.has(id):
			return "unknown item"
		var def := ContentDB.get_or_empty(id)
		if def.has("weapon"):
			player.equip_weapon(id)
		elif def.has("armour") and str(def["armour"].get("slot", "")) == "off_hand":
			player.equip_offhand(id)
		else:
			player.equip_armour(id)
		return "equipped %s" % id, "arena: equip an item on the player")
	Debug.register("arena_reset", func(_a: Array) -> String:
		reset()
		return "reset", "arena: reset player and enemies")
	Debug.register("arena_verify", func(a: Array) -> String:
		var out: String = a[0] if a.size() > 0 else _out_dir()
		var v := ArenaVerify.new()
		v.name = "ArenaVerify"
		add_child(v)
		v.finished.connect(func(_p: int, failed: int) -> void:
			_verify_failures = failed
			verification_finished.emit(failed))
		v.run(self, out)
		return "verification started (out %s)" % out, "arena: run the scripted combat verification")


## `--out=<dir>` (absolute) is where screenshots go; defaults to user://captures/arena.
func _out_dir() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			return arg.substr(6)
	return "user://captures/arena"
