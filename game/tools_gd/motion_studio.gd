extends Node3D
## The motion studio: the real player scene on a plain lit floor, driven by real key events on a
## timeline, and filmed at chosen moments from the side or through the player's own camera. It is
## for judging movement -- starts, stops, turns on the spot, rolls, swings, the camera's follow --
## with nothing else in the frame. It runs on either renderer in a minute or two, Forward+ under
## Mesa's software Vulkan included, where loading the country crashes the driver.
##
##   xvfb-run -a -s '-screen 0 1280x720x24' godot --path game --rendering-driver vulkan \
##       --rendering-method forward_plus --audio-driver Dummy --resolution 1280x720 --fixed-fps 60 \
##       res://tools_gd/motion_studio.tscn -- --plan=tools/capture/plans/motion.json --out=<dir>
##
## Run it with --fixed-fps 60: every frame is then one physics tick, and a time in the plan is
## simulated time.
##
## Plan: {"sequences": [{"label": "start_stop", "view": "side" | "feet" | "player" | "front" | "close"
##          | "close_front" | "close_back",
##          "equip": "core:item/iron_sword", "offhand": "core:item/...",
##          "length": s, "keys": [[t, "W", true], [t, "W", false], ...],
##          "look": [[t, dx], [t, dx, seconds], ...], "target": [x, y, z],
##          "foe": [enemy id, x, y, z, yaw?], "foe_attacks": [[t, attack name], ...],
##          "hud": false, "menu": "", "plant_feet": true, "items": [[id, count], ...],
##          "first_person": false, "drawn": false, "pitch": radians, "spell": id,
##          "shots": {"from": s, "every": s, "count": n}  or  [t, t, ...]}]}
## A key is a real key event through the input map, so through the bindings as the game sets them
## up. "look" turns the view as a mouse moving `dx` pixels would, all at once or spread evenly over
## `seconds`; "target" stands a post there that a lock can take; "foe" stands a real foe there that
## does nothing on its own, for a blow to land on, until "foe_attacks" has it begin one of its own
## attacks (by name) as its AI would, to film a wind-up; "hud" puts the HUD up and "menu"
## opens that screen (UI.open) before the first tick. "feet" is the side view brought down to the
## feet, close; "plant_feet": false films the body as it stopped before its feet were held
## (HumanoidModel.plant_feet), for a before and after in one run. "equip" and "offhand" put a
## weapon (or a shield, a lantern) in the hands first; "close" is the side view near enough that
## the body fills the frame, for judging a swing, and "close_front" and "close_back" are the same
## from three-quarters ahead and behind. Every sequence starts from a body
## standing still at the origin, facing north (-Z), with the view behind it. Each shot writes
## <out>/<label>_<nn>.png, and one line per shot goes to <out>/motion.txt: the time, the state,
## the speed, the clip and where the feet are.

const PLAYER_SCENE := "res://actors/player/player.tscn"
const SIDE_DISTANCE := 5.0
const SIDE_HEIGHT := 1.0
const FEET_DISTANCE := 2.4
const FEET_HEIGHT := 0.45
const CLOSE_DISTANCE := 3.1
const CLOSE_HEIGHT := 1.15

var plan_path := ""
var out_dir := "captures/motion"
var failures: Array[String] = []
var _cam: Camera3D
var _player: Player = null
var _lines: PackedStringArray = []
var _held: Dictionary = {}
var _seq_start := 0
var _foe: Enemy = null


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--plan="):
			plan_path = a.substr(7)
		elif a.begins_with("--out="):
			out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_build_stage()
	await get_tree().process_frame
	await _run()
	var f := FileAccess.open(out_dir.path_join("motion.txt"), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(_lines) + "\n")
	for msg in failures:
		push_error("MotionStudio: " + msg)
	print("MOTION: %d shots, %d failures -> %s" % [_lines.size(), failures.size(), out_dir])
	get_tree().quit(0 if failures.is_empty() else 1)


# --- the stage ----------------------------------------------------------------------------------

func _build_stage() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	shape.shape = box
	shape.position.y = -0.5
	body.add_child(shape)
	add_child(body)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(400.0, 400.0)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _checker()
	mat.uv1_scale = Vector3(200.0, 200.0, 1.0)        # one square a metre across
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.roughness = 0.95
	ground.material_override = mat
	add_child(ground)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, 35.0, 0.0)
	sun.shadow_enabled = true
	sun.light_energy = 1.1
	add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	_cam = Camera3D.new()
	_cam.fov = 50.0
	add_child(_cam)


## A pale checker, so a sliding foot or a creeping camera shows against the ground.
func _checker() -> ImageTexture:
	var img := Image.create(64, 64, true, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var light := ((x / 32) + (y / 32)) % 2 == 0
			img.set_pixel(x, y, Color(0.56, 0.6, 0.5) if light else Color(0.44, 0.48, 0.4))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


# --- the plan -----------------------------------------------------------------------------------

func _run() -> void:
	var path := plan_path
	if not FileAccess.file_exists(path) and FileAccess.file_exists("res://../" + path):
		path = "res://../" + path        # given relative to the repository root, as plans are
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		failures.append("cannot read the plan %s" % plan_path)
		return
	RenderingServer.render_loop_enabled = false
	for seq in (parsed as Dictionary).get("sequences", []):
		if typeof(seq) == TYPE_DICTIONARY:
			await _sequence(seq)
	RenderingServer.render_loop_enabled = true


func _sequence(seq: Dictionary) -> void:
	var label := str(seq.get("label", "motion"))
	UI.close_all()
	HumanoidModel.plant_feet = bool(seq.get("plant_feet", true))
	_fresh_player(bool(seq.get("hud", false)))
	if str(seq.get("equip", "")) != "":
		_player.equip_weapon(str(seq["equip"]))
	if str(seq.get("offhand", "")) != "":
		_player.equip_offhand(str(seq["offhand"]))
	# "items": [[id, count], ...] into the bag (arrows for a bow)
	if str(seq.get("spell", "")) != "":
		(_player.progression() as Progression).learn_spell(str(seq["spell"]))
		_player.equipped_spell = str(seq["spell"])
	var bag := _player.get_node_or_null("Inventory") as Inventory
	for it: Array in seq.get("items", []):
		if bag != null:
			bag.add(str(it[0]), int(it[1]) if it.size() > 1 else 1)
	# "first_person": seen through the eyes (triage 57); "drawn": the weapon in the hand from the
	# start; "pitch": the view's pitch, radians, up +
	if bool(seq.get("first_person", false)):
		_player.camera_rig.set_first_person(true)
	if bool(seq.get("drawn", false)):
		_player.weapon_drawn = true
		_player._last_fight_act = _player.now()
		_player._dress_hands()
	if seq.has("pitch"):
		_player.camera_rig.pitch = float(seq["pitch"])
	for i in 20:
		await get_tree().physics_frame
	# the UI raises its HUD when the player spawns, which can come after _fresh_player put it away
	if not bool(seq.get("hud", false)):
		UI.hide_hud()
	if str(seq.get("menu", "")) != "":
		UI.open(str(seq["menu"]))
	var target: Array = seq.get("target", [])
	if target.size() == 3:
		_stand_target(Vector3(float(target[0]), float(target[1]), float(target[2])))
	var foe: Array = seq.get("foe", [])
	if foe.size() >= 4:
		_stand_foe(str(foe[0]), Vector3(float(foe[1]), float(foe[2]), float(foe[3])), float(foe[4]) if foe.size() > 4 else PI)
		for i in 10:
			await get_tree().physics_frame
	var keys: Array = seq.get("keys", []).duplicate()
	var foe_attacks: Array = seq.get("foe_attacks", []).duplicate()
	var looks: Array = seq.get("look", []).duplicate()
	var turning: Array = []        # [until, dx a tick]
	var shots := _shot_times(seq.get("shots", []))
	var length := float(seq.get("length", (shots[shots.size() - 1] + 0.1) if not shots.is_empty() else 1.0))
	var view := str(seq.get("view", "side"))
	var shot := 0
	var dt := 1.0 / float(Engine.physics_ticks_per_second)
	# Time is read off the physics clock, not counted here: drawing a shot takes frames, and under
	# --fixed-fps every frame is a tick, so a count kept here would fall behind the body's.
	_seq_start = Engine.get_physics_frames()
	while true:
		var t := (Engine.get_physics_frames() - _seq_start) * dt
		if t > length + 0.0001:
			break
		while not keys.is_empty() and float(keys[0][0]) <= t + 0.0001:
			var k: Array = keys.pop_front()
			_send_key(str(k[1]), bool(k[2]))
		while not foe_attacks.is_empty() and float(foe_attacks[0][0]) <= t + 0.0001:
			_foe_attack(str((foe_attacks.pop_front() as Array)[1]))
		while not looks.is_empty() and float(looks[0][0]) <= t + 0.0001:
			var l: Array = looks.pop_front()
			if l.size() >= 3 and float(l[2]) > dt:
				turning = [float(l[0]) + float(l[2]), float(l[1]) * dt / float(l[2])]
			else:
				_player.camera_rig.add_mouse_look(Vector2(float(l[1]), 0.0))
		if not turning.is_empty():
			if t < float(turning[0]) - 0.0001:
				_player.camera_rig.add_mouse_look(Vector2(float(turning[1]), 0.0))
			else:
				turning = []
		if shot < shots.size() and shots[shot] <= t + 0.0001:
			await _shoot(label, shot, view)
			shot += 1
			continue
		await get_tree().physics_frame
	for key in _held.keys():
		_send_key(str(key), false)
	HumanoidModel.plant_feet = true
	for post in get_tree().get_nodes_in_group(LockOn.GROUP):
		if post.get_parent() == self:
			post.queue_free()
	for n in get_children():
		if n is Enemy:
			n.queue_free()
	_foe = null
	for n in get_tree().get_nodes_in_group(ImpactFx.GROUP):
		n.queue_free()


## A real foe of `enemy_id` standing at `at` facing `yaw`, that neither sees nor moves on its own:
## a blow lands on it as on any foe (its hurtbox, poise, reactions and Impact are the real ones).
func _stand_foe(enemy_id: String, at: Vector3, yaw: float) -> void:
	var e := Enemy.new()
	e.configure(enemy_id)
	e.position = at
	e.rotation.y = yaw
	add_child(e)
	e.spawn_position = at
	e.brain.post = at
	e.perception.enabled = false
	e.set_physics_process(false)
	_foe = e


## The standing foe begins its attack called `attack_name`, as its AI would: from here it ticks
## (its timers, its attack's phases, its hitbox), though it still sees no one and so turns to no one.
func _foe_attack(attack_name: String) -> void:
	if _foe == null or not is_instance_valid(_foe):
		failures.append("no foe stands to make the attack %s" % attack_name)
		return
	for a in _foe.current_attacks:
		if typeof(a) == TYPE_DICTIONARY and str((a as Dictionary).get("name", "")) == attack_name:
			_foe.set_physics_process(true)
			_foe._begin_attack(a)
			return
	failures.append("%s has no attack called %s" % [_foe.content_id(), attack_name])


## A post a lock can take (group LockOn.GROUP, alive), standing at `at`.
func _stand_target(at: Vector3) -> void:
	var script := GDScript.new()
	script.source_code = "extends Node3D\nfunc is_alive() -> bool:\n\treturn true\nfunc lock_point() -> Vector3:\n\treturn global_position + Vector3.UP * 1.2\n"
	script.reload()
	var post := Node3D.new()
	post.set_script(script)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 1.8, 0.3)
	mesh.mesh = box
	mesh.position = Vector3(0.0, 0.9, 0.0)
	post.add_child(mesh)
	add_child(post)
	post.global_position = at
	post.add_to_group(LockOn.GROUP)


func _shot_times(spec: Variant) -> Array[float]:
	var out: Array[float] = []
	if typeof(spec) == TYPE_ARRAY:
		for t in spec:
			out.append(float(t))
	elif typeof(spec) == TYPE_DICTIONARY:
		var d: Dictionary = spec
		for i in int(d.get("count", 8)):
			out.append(float(d.get("from", 0.0)) + i * float(d.get("every", 0.1)))
	out.sort()
	return out


func _fresh_player(hud: bool) -> void:
	for key in _held.keys():
		_send_key(str(key), false)
	if _player != null and is_instance_valid(_player):
		_player.queue_free()
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as Player
	add_child(_player)
	_player.teleport(Vector3(0.0, 0.02, 0.0), 0.0)
	# The UI raises its own HUD, themed, when a player spawns; a second one here drew every
	# label twice, once in the theme and once without it.
	if hud:
		UI.show_hud()
	else:
		UI.hide_hud()


func _shoot(label: String, n: int, view: String) -> void:
	RenderingServer.render_loop_enabled = true
	# The first frame drawn after the loop has been off shows what the last draw left (a sky with
	# no floor, or the camera before it moved); the second is the frame asked for. Each frame is a
	# tick under --fixed-fps, so the side camera is put beside the body before each.
	for i in 2:
		_place_camera(view)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	RenderingServer.render_loop_enabled = false
	var path := out_dir.path_join("%s_%02d.png" % [label, n])
	var img := get_viewport().get_texture().get_image()
	if img == null or img.save_png(path) != OK:
		failures.append("cannot write %s" % path)
	_lines.append(_describe(label, n))


func _place_camera(view: String) -> void:
	var at := _player.get_global_transform_interpolated().origin
	# "foe_close", "foe_close_front" and the rest: the same view of the standing foe
	if view.begins_with("foe_") and _foe != null and is_instance_valid(_foe):
		at = _foe.get_global_transform_interpolated().origin
		view = view.substr(4)
	match view:
		"player":
			_player.camera_rig.camera.make_current()
		"front":
			_cam.make_current()
			_cam.look_at_from_position(at + Vector3(0.0, SIDE_HEIGHT, -SIDE_DISTANCE), at + Vector3.UP * 0.95)
		"feet":
			_cam.make_current()
			_cam.look_at_from_position(at + Vector3(FEET_DISTANCE, FEET_HEIGHT, 0.0), at + Vector3.UP * 0.35)
		"close":
			_cam.make_current()
			_cam.look_at_from_position(at + Vector3(CLOSE_DISTANCE, CLOSE_HEIGHT, 0.0), at + Vector3.UP * 1.0)
		"close_front":
			_cam.make_current()
			_cam.look_at_from_position(at + Vector3(CLOSE_DISTANCE, 0.0, -CLOSE_DISTANCE).normalized() * CLOSE_DISTANCE
					+ Vector3.UP * CLOSE_HEIGHT, at + Vector3.UP * 1.0)
		"close_back":
			_cam.make_current()
			_cam.look_at_from_position(at + Vector3(CLOSE_DISTANCE, 0.0, CLOSE_DISTANCE).normalized() * CLOSE_DISTANCE
					+ Vector3.UP * CLOSE_HEIGHT, at + Vector3.UP * 1.0)
		_:
			_cam.make_current()
			_cam.look_at_from_position(at + Vector3(SIDE_DISTANCE, SIDE_HEIGHT, 0.0), at + Vector3.UP * 0.95)


## The body as drawn in the shot just taken, at the physics clock's time since the sequence began.
func _describe(label: String, n: int) -> String:
	var t := (Engine.get_physics_frames() - _seq_start) / float(Engine.physics_ticks_per_second)
	var v := _player.velocity
	var feet := ""
	var models := _player.find_children("*", "HumanoidModel", true, false)
	if not models.is_empty():
		var m := models[0] as HumanoidModel
		var sk := m.skeleton
		for side in ["L", "R"]:
			var p := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("Foot." + side)).origin
			feet += " foot%s (%.2f, %.2f, %.2f)" % [side, p.x, p.y, p.z]
	var rig := _player.camera_rig
	var cam_gap := rig.camera.global_position.distance_to(_player.global_position + Vector3.UP * CameraRig.TP_HEIGHT)
	return "%s_%02d t=%.2f %s speed %.2f yaw %.0f clip %s%s camera %.2f m from the pivot, fov %.1f%s%s" % [
		label, n, t, _player.state_name(), Vector2(v.x, v.z).length(), rad_to_deg(_player.rotation.y),
		_player.anim.current_clip, " untouchable" if _player.is_in_iframes() else "", cam_gap, rig.camera.fov, feet,
		_describe_foe()]


## The standing foe, when there is one: what its timeline plays and what its picture shows.
func _describe_foe() -> String:
	if _foe == null or not is_instance_valid(_foe):
		return ""
	var shown := ""
	var models := _foe.find_children("*", "HumanoidModel", true, false)
	if not models.is_empty():
		var m := models[0] as HumanoidModel
		shown = " picture %s at %.2f, speed %.2f, owed %.3f" % [m.current_intent() if m.holding_pose().is_empty() else m.holding_pose() + " (held)",
				m._one_shot_time, m.speed_scale, m.hit_stop_owed()]
	return " | foe %s%s health %.0f, clip %s%s" % [_foe.content_id(), " dead" if _foe.dead else "", _foe.health,
			_foe.anim.current_clip, shown]


## A key as a keyboard sends it, through the input map: a modifier key reports itself held.
## "LMB", "RMB" and "MMB" are the mouse's buttons.
func _send_key(name: String, pressed: bool) -> void:
	if name in ["LMB", "RMB", "MMB"]:
		var mb := InputEventMouseButton.new()
		var buttons := {"LMB": [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MASK_LEFT], "RMB": [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MASK_RIGHT],
				"MMB": [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_MASK_MIDDLE]}
		mb.button_index = buttons[name][0]
		mb.pressed = pressed
		mb.button_mask = buttons[name][1] if pressed else 0
		Input.parse_input_event(mb)
		Input.flush_buffered_events()
		if pressed:
			_held[name] = true
		else:
			_held.erase(name)
		return
	var code := OS.find_keycode_from_string(name)
	if code == KEY_NONE:
		failures.append("no key called '%s'" % name)
		return
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.key_label = code
	ev.pressed = pressed
	ev.ctrl_pressed = pressed and code == KEY_CTRL
	ev.shift_pressed = pressed and code == KEY_SHIFT
	ev.alt_pressed = pressed and code == KEY_ALT
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	if pressed:
		_held[name] = true
	else:
		_held.erase(name)
