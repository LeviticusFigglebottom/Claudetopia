extends TestCase
## Movement as a player's hands meet it (DESIGN §5.2).
##
## Reported after playing: "the movement is very slow, and the mouse/movement (WASD) relationship
## seems off, hence the compass and orientation issues." Measured before the fix: the camera rig
## was a plain child of the body, so the view looked along body yaw + rig yaw while W went along
## rig yaw alone; a second of D turned the view 90 degrees with the mouse still and swung the
## compass in steps of up to 21 degrees a frame; and a new character reached 4.20 m/s in 0.067 s.
## Every test here drives the real player scene through the real input actions.

const PLAYER := preload("res://actors/player/player.tscn")
const HUD_SCENE := preload("res://ui/hud/hud.tscn")
const KEYS: Array[String] = ["move_forward", "move_back", "move_left", "move_right", "sprint", "walk", "sneak", "block"]
## The compass test walks past Merrowby: 30 m south of its green, so its marker's bearing moves.
const MERROWBY := "core:place/merrowby"

var player: Player = null
var floor_body: StaticBody3D = null
var hud: Node = null


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	GameState.reset_for_new_game(7)
	SaveSystem.pending.clear()


func after_each() -> void:
	for a in KEYS:
		if InputMap.has_action(a):
			Input.action_release(a)
	for n in [hud, player, floor_body]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	hud = null
	player = null
	floor_body = null
	GameState.reset_for_new_game(7)


# --- scaffolding ---------------------------------------------------------------------------------

func _ticks(n: int) -> void:
	for i in n:
		await _tree().physics_frame


## A brand-new character the way the Naming leaves one (a Calling, its bag, its skills), standing
## on a flat floor at `at`.
func _stand(at: Vector3 = Vector3.ZERO) -> void:
	GameState.set_flag("player_name", "Wren")
	GameState.set_flag("player_calling", "core:calling/wayfarer")
	GameState.set_flag("new_game", true)
	floor_body = StaticBody3D.new()
	floor_body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(600.0, 1.0, 600.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	floor_body.add_child(shape)
	_tree().root.add_child(floor_body)
	floor_body.global_position = at
	player = PLAYER.instantiate() as Player
	_tree().root.add_child(player)
	player.teleport(at + Vector3(0.0, 0.02, 0.0), 0.0)
	await _ticks(8)


func _reset(at: Vector3, body_heading: float, view_heading: float) -> void:
	for a in KEYS:
		if InputMap.has_action(a):
			Input.action_release(a)
	player.teleport(at + Vector3(0.0, 0.02, 0.0), -deg_to_rad(body_heading))
	player.camera_rig.yaw = -deg_to_rad(view_heading)
	player.stamina_comp.refill()
	await _ticks(3)


func _flat_speed() -> float:
	return Vector2(player.velocity.x, player.velocity.z).length()


func _xz(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


## Compass bearing (0 north, 90 east) of a ground displacement.
func _bearing(d: Vector2) -> float:
	return Compass.bearing_deg(Vector2.ZERO, d)


func _view_heading() -> float:
	return Compass.heading_from_basis(player.camera_rig.camera.global_transform.basis)


# --- W/A/S/D follow the view ---------------------------------------------------------------------

## At every camera yaw, each key moves the body where the view says: W along the view's forward
## on the ground, S away from it, A and D to its left and right. The body starts facing north
## whatever the view, which is the case the old rig got wrong.
func test_wasd_follows_the_view_at_every_camera_yaw() -> void:
	await _stand()
	var keys := {"move_forward": 0.0, "move_right": 90.0, "move_back": 180.0, "move_left": 270.0}
	var worst := 0.0
	var worst_case := ""
	for view in [0.0, 90.0, 180.0, 270.0, 37.0]:
		for key in keys:
			await _reset(Vector3.ZERO, 0.0, view)
			Input.action_press(key)
			await _ticks(40)
			var a := _xz(player.global_position)
			await _ticks(12)
			var b := _xz(player.global_position)
			Input.action_release(key)
			var expected := fposmod(view + float(keys[key]), 360.0)
			var got := _bearing(b - a)
			var off := absf(Compass.wrap_delta(got - expected))
			if off > worst:
				worst = off
				worst_case = "view %.0f, %s: moved toward %.1f, expected %.1f" % [view, key, got, expected]
			assert_true((b - a).length() > 0.5, "view %.0f, %s: the body barely moved (%.2f m in 0.2 s)" % [view, key, (b - a).length()])
			assert_true(off < 3.0, "view %.0f, %s: moved toward %.1f degrees, expected %.1f" % [view, key, got, expected])
			assert_true(absf(Compass.wrap_delta(_view_heading() - view)) < 0.5, "view %.0f, %s: the view turned by itself to %.1f" % [view, key, _view_heading()])
	print("    worst W/A/S/D heading error over 20 cases: %.2f deg (%s)" % [worst, worst_case])


## The body turns toward where it is going and the view does not turn with it. This is the bug:
## a second of D used to swing the view (and the compass) through 90 degrees.
func test_the_view_does_not_turn_with_the_body() -> void:
	await _stand()
	await _reset(Vector3.ZERO, 0.0, 0.0)
	Input.action_press("move_right")
	var widest := 0.0
	for i in 60:
		await _tree().physics_frame
		widest = maxf(widest, absf(Compass.wrap_delta(_view_heading())))
	Input.action_release("move_right")
	assert_near(fposmod(rad_to_deg(-player.rotation.y), 360.0), 90.0, 1.0, "the body should face east after a second of D")
	assert_true(widest < 0.5, "the view turned %.1f degrees while only the body turned" % widest)


## Moving the mouse right turns the view right (the compass heading rises), toward you tilts it
## down, and only the invert setting reverses the vertical.
func test_mouse_right_turns_the_view_right() -> void:
	await _stand()
	await _reset(Vector3.ZERO, 0.0, 0.0)
	var rig := player.camera_rig
	var before := _view_heading()
	rig.add_mouse_look(Vector2(120.0, 0.0))
	await _tree().process_frame
	await _tree().process_frame
	var turned := Compass.wrap_delta(_view_heading() - before)
	var per_px := float(Settings.get_value("controls", "mouse_sensitivity", 0.25)) * CameraRig.MOUSE_RAD_PER_PX
	assert_gt(turned, 0.0, "mouse right must turn the view right (clockwise from above)")
	assert_near(turned, rad_to_deg(120.0 * per_px), 0.5, "120 px of mouse is %.1f degrees at the default sensitivity" % rad_to_deg(120.0 * per_px))
	var look_y := -rig.camera.global_transform.basis.z.y
	rig.add_mouse_look(Vector2(0.0, 60.0))
	await _tree().process_frame
	await _tree().process_frame
	assert_true(-rig.camera.global_transform.basis.z.y < look_y - 0.01, "mouse toward you must tilt the view down")
	var was: Variant = Settings.get_value("controls", "invert_y", false)
	Settings.set_value("controls", "invert_y", true, false)
	look_y = -rig.camera.global_transform.basis.z.y
	rig.add_mouse_look(Vector2(0.0, 60.0))
	await _tree().process_frame
	await _tree().process_frame
	Settings.set_value("controls", "invert_y", was, false)
	assert_true(-rig.camera.global_transform.basis.z.y > look_y + 0.01, "with invert on, mouse toward you tilts the view up")


# --- speed, per gait, for a brand-new character ----------------------------------------------------

## A new character's real ground speed per gait: distance over a second of level ground once up to
## speed, after every multiplier the game applies (status, stance, acceleration). No skill or load
## touches ground speed; a status (chilled, webbed) is the only thing that slows a free body.
func test_a_new_character_moves_at_the_designed_speed_per_gait() -> void:
	await _stand()
	var gaits := [["walk", ["move_forward", "walk"], Player.WALK_SPEED],
			["jog", ["move_forward"], Player.JOG_SPEED],
			["sprint", ["move_forward", "sprint"], Player.SPRINT_SPEED]]
	var report: Array[String] = []
	for g in gaits:
		await _reset(Vector3.ZERO, 0.0, 0.0)
		for a in g[1]:
			Input.action_press(str(a))
		await _ticks(60)
		var a0 := _xz(player.global_position)
		await _ticks(60)
		var measured := _xz(player.global_position).distance_to(a0)
		for a in g[1]:
			Input.action_release(str(a))
		report.append("%s %.2f m/s (constant %.2f)" % [g[0], measured, float(g[2])])
		assert_near(measured, float(g[2]), float(g[2]) * 0.03, "%s: %.2f m in a second, designed %.2f m/s" % [g[0], measured, float(g[2])])
	print("    measured ground speed: %s" % ", ".join(report))


## Weight that still answers: from rest to a jog in about 0.31 s, a jog stopped in about 0.25 s over
## 0.63 m, a sprint in about 0.48 s over 2.1 m (DESIGN §5.2). Measured, not assumed.
func test_acceleration_and_stopping_are_as_designed() -> void:
	await _stand()
	await _reset(Vector3.ZERO, 0.0, 0.0)
	Input.action_press("move_forward")
	var t0 := Engine.get_physics_frames()
	var reached := -1
	for i in 60:
		await _tree().physics_frame
		if reached < 0 and _flat_speed() >= Player.JOG_SPEED * 0.99:
			reached = Engine.get_physics_frames() - t0
	var up_s := float(reached) / Engine.physics_ticks_per_second
	var stop := await _stop_from(["move_forward"])
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _ticks(90)
	var stop_sprint := await _stop_from(["move_forward", "sprint"])
	print("    rest to jog %.3f s; jog stops in %.3f s over %.2f m; sprint stops in %.3f s over %.2f m" % [
		up_s, stop[0], stop[1], stop_sprint[0], stop_sprint[1]])
	assert_true(up_s > 0.2 and up_s < 0.45, "rest to a jog took %.3f s" % up_s)
	assert_true(stop[0] > 0.15 and stop[0] < 0.4, "a jog took %.3f s to stop" % stop[0])
	assert_true(stop[1] > 0.4 and stop[1] < 0.9, "a jog took %.2f m to stop" % stop[1])
	assert_true(stop_sprint[0] > 0.35 and stop_sprint[0] < 0.7, "a sprint took %.3f s to stop" % stop_sprint[0])
	assert_true(stop_sprint[1] > 1.5 and stop_sprint[1] < 3.0, "a sprint took %.2f m to stop: it should run on, not snap" % stop_sprint[1])


## Releases the keys and measures [seconds, metres] until the body stands still.
func _stop_from(keys: Array) -> Array:
	var p0 := _xz(player.global_position)
	for k in keys:
		Input.action_release(str(k))
	var t0 := Engine.get_physics_frames()
	var frames := 0
	for i in 120:
		await _tree().physics_frame
		if _flat_speed() < 0.01:
			frames = Engine.get_physics_frames() - t0
			break
	return [float(frames) / Engine.physics_ticks_per_second, _xz(player.global_position).distance_to(p0)]


# --- sprint and stamina --------------------------------------------------------------------------

## Sprint drains 8 stamina a second (DESIGN §5.3); run to empty it stops and stays stopped until a
## quarter of the pool is back, rather than stuttering on every tick of regeneration.
func test_sprint_drains_stamina_and_stops_when_it_is_spent() -> void:
	await _stand()
	await _reset(Vector3.ZERO, 0.0, 0.0)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await _ticks(30)
	var s0 := player.stamina_comp.current
	await _ticks(60)
	var drained := s0 - player.stamina_comp.current
	assert_near(drained, DamageModel.STAMINA_SPRINT_PER_S, 0.4, "a second of sprint drained %.2f" % drained)
	assert_true(player.is_sprinting, "sprinting while stamina lasts")
	player.stamina_comp.current = 2.0
	await _ticks(45)
	assert_false(player.is_sprinting, "spent: the sprint stops")
	assert_true(_flat_speed() <= Player.JOG_SPEED + 0.05, "spent, the body is back to a jog (%.2f m/s)" % _flat_speed())
	var resume := player.stamina_comp.maximum * Player.SPRINT_RESUME
	var resumed_at := -1.0
	for i in 360:
		await _tree().physics_frame
		if player.is_sprinting:
			resumed_at = player.stamina_comp.current
			break
	Input.action_release("sprint")
	Input.action_release("move_forward")
	# the first tick of the resumed sprint has already spent its 8/60, hence the small allowance
	assert_true(resumed_at >= resume - 1.0, "the held sprint resumed at %.1f stamina, the rule is %.1f" % [resumed_at, resume])


## A long sprint keeps the stamina bar in view. Holding keys sends no input events, and the HUD
## used to rest itself at 35% after seven idle seconds while the stamina drained under it.
func test_the_stamina_bar_stays_in_view_while_it_drains() -> void:
	await _stand()
	hud = HUD_SCENE.instantiate()
	_tree().root.add_child(hud)
	await _tree().process_frame
	hud.call("_connect_world")
	player.stamina_comp.current = player.stamina_comp.maximum * 0.5
	player.stats_changed.emit()
	hud.set("_idle", 60.0)
	for i in 30:
		hud.call("_update_idle_fade", 0.1)
	assert_gt(float(hud.get("modulate").a), 0.9, "half a stamina bar faded out with the rest of the HUD")
	player.stamina_comp.refill()
	player.stats_changed.emit()
	hud.set("_idle", 60.0)
	for i in 30:
		hud.call("_update_idle_fade", 0.1)
	assert_true(float(hud.get("modulate").a) < 0.5, "at full stamina and idle the HUD rests as it did")


# --- turning --------------------------------------------------------------------------------------

## The body turns toward where it is going at a limited rate that falls with speed, and eases into
## the end of the turn. The first code turned by 14/s of the remaining angle: 2500 deg/s at the
## start of a reversal, which is a snap.
func test_turning_is_rate_limited_and_faster_at_a_walk() -> void:
	assert_gt(Player.turn_rate_for(Player.WALK_SPEED), Player.turn_rate_for(Player.JOG_SPEED), "a walk turns faster than a jog")
	assert_gt(Player.turn_rate_for(Player.JOG_SPEED), Player.turn_rate_for(Player.SPRINT_SPEED), "a jog turns faster than a sprint")
	await _stand()
	await _reset(Vector3.ZERO, 0.0, 0.0)
	Input.action_press("move_forward")
	await _ticks(45)
	Input.action_release("move_forward")
	Input.action_press("move_back")
	var dt := 1.0 / Engine.physics_ticks_per_second
	var prev := player.rotation.y
	var took := -1
	for i in 90:
		await _tree().physics_frame
		var step := absf(wrapf(player.rotation.y - prev, -PI, PI))
		assert_true(step <= Player.TURN_RATE_STILL * dt + 0.0001, "tick %d turned %.1f degrees" % [i, rad_to_deg(step)])
		prev = player.rotation.y
		if took < 0 and absf(wrapf(player.rotation.y - PI, -PI, PI)) < deg_to_rad(2.0):
			took = i + 1
	Input.action_release("move_back")
	var took_s := float(took) / Engine.physics_ticks_per_second
	print("    a reversal from a jog took %.2f s to face the other way" % took_s)
	assert_true(took > 0, "the body never turned round")
	assert_true(took_s > 0.2 and took_s < 0.8, "a reversal from a jog took %.2f s" % took_s)


# --- the compass reads the view ------------------------------------------------------------------

## Walks a path past Merrowby with the mouse still, then with the view turning steadily. The strip
## must show the view's heading throughout (within the ~30 ms easing); with the mouse still it must
## not move at all however the body turns; with the mouse moving no single step may be larger than
## the view's own step plus the easing catching up; and no marker may jump. Before the fix the strip
## swung 21 degrees in a single frame here with the mouse still.
func test_compass_reads_the_view_while_the_body_turns() -> void:
	var place := ContentDB.get_or_empty(MERROWBY)
	var pos: Array = place.get("position", [0.0, 0.0])
	var green := Vector3(float(pos[0]), 0.0, float(pos[1]))
	var start := green + Vector3(-20.0, 0.0, 30.0)
	GameState.discover(MERROWBY)
	await _stand(start)
	hud = HUD_SCENE.instantiate()
	_tree().root.add_child(hud)
	await _tree().process_frame
	hud.call("_connect_world")
	hud.call("_rebuild_markers")
	await _reset(start, 0.0, 0.0)
	var compass: Compass = hud.get("_compass")
	var px_per_deg := compass.size.x / Compass.SPAN_DEG
	var path := [["move_right", 50], ["move_forward", 40], ["move_left", 30], ["move_back", 40], ["move_right", 30]]
	var report: Array[String] = []
	for turning in [false, true]:
		var gap := 0.0
		var strip_step := 0.0
		var excess := 0.0              # strip step beyond the view's own step
		# ...and beyond the view's step plus the lag the strip was carrying into the frame. An eased
		# strip catches up its lag faster in a long frame than a short one, so under a loaded
		# machine the first number grows with the frame times; the second is the jump that would
		# be a fault whatever the frame times were.
		var jump := 0.0
		var carried := 0.0
		var marker_step := 0.0
		var bearing_step := 0.0
		var body_turn := 0.0
		var last_shown := -1.0
		var last_view := -1.0
		var last_yaw := player.rotation.y
		var last_marker := {}
		var last_bearing := {}
		for leg in path:
			Input.action_press(str(leg[0]))
			for i in int(leg[1]):
				if turning:
					player.camera_rig.add_mouse_look(Vector2(6.0, 0.0))
				await _tree().physics_frame
				await _tree().process_frame
				var shown := compass.heading_deg
				var view := player.camera_rig.heading_degrees()
				gap = maxf(gap, absf(Compass.wrap_delta(shown - view)))
				body_turn += absf(wrapf(player.rotation.y - last_yaw, -PI, PI))
				last_yaw = player.rotation.y
				if last_shown >= 0.0:
					var s_step := absf(Compass.wrap_delta(shown - last_shown))
					var v_step := absf(Compass.wrap_delta(view - last_view))
					strip_step = maxf(strip_step, s_step)
					excess = maxf(excess, s_step - v_step)
					jump = maxf(jump, s_step - v_step - carried)
				carried = absf(Compass.wrap_delta(shown - view))
				last_shown = shown
				last_view = view
				for m in compass.markers:
					var label := str(m["label"])
					var bearing := float(m["bearing"])
					if not Compass.on_strip(bearing, shown):
						last_marker.erase(label)
						continue
					var x := Compass.strip_offset(bearing, shown, compass.size.x)
					if last_marker.has(label):
						marker_step = maxf(marker_step, absf(x - float(last_marker[label])))
						bearing_step = maxf(bearing_step, absf(Compass.wrap_delta(bearing - float(last_bearing[label]))))
					last_marker[label] = x
					last_bearing[label] = bearing
			Input.action_release(str(leg[0]))
		var name := "view turning" if turning else "mouse still"
		report.append("%s: body turned %.0f deg in all, strip within %.2f deg of the view, largest strip step %.2f deg (%.2f beyond the view's own, %.2f beyond it and the lag carried), largest marker step %.1f px" % [
				name, rad_to_deg(body_turn), gap, strip_step, excess, jump, marker_step])
		assert_true(gap < 1.5, "%s: the strip lagged the view by %.2f degrees" % [name, gap])
		assert_true(jump < 0.05, "%s: the strip stepped %.2f degrees further than the view and its own lag in one frame" % [name, jump])
		assert_true(marker_step < (strip_step + bearing_step + 0.2) * px_per_deg + 0.5, "%s: a marker jumped %.1f px" % [name, marker_step])
		if not turning:
			assert_gt(rad_to_deg(body_turn), 250.0, "the path should have turned the body round (it turned %.0f deg)" % rad_to_deg(body_turn))
			assert_true(strip_step < 0.05, "mouse still: the strip moved %.2f degrees while only the body turned" % strip_step)
	for r in report:
		print("    " + r)
	assert_true(compass.markers.size() > 0, "Merrowby should be on the compass: it was discovered")


## Turning on the spot steps round. Blocking, the body faces the view; turned hard with the mouse
## while standing, it used to pivot on planted feet at 720 degrees a second. Now the legs are told
## a side-step toward the turn while it lasts, and nothing once it stops or once the body moves.
func test_turning_on_the_spot_steps_round() -> void:
	await _stand(Vector3.ZERO)
	await _reset(Vector3.ZERO, 0.0, 0.0)
	Input.action_press("block")
	await _ticks(20)
	var still := absf(player.anim.locomotion.x)
	var widest := 0.0
	var left_way := 0.0
	var yaw0 := player.rotation.y
	for i in 30:
		player.camera_rig.add_mouse_look(Vector2(-50.0, 0.0))     # the hand to the left: turn left
		await _tree().physics_frame
		widest = maxf(widest, absf(player.anim.locomotion.x))
		left_way = minf(left_way, player.anim.locomotion.x)
	var turned := rad_to_deg(absf(player.rotation.y - yaw0))
	await _ticks(40)
	var after := absf(player.anim.locomotion.x)
	Input.action_release("block")
	print("    turning on the spot (%.0f deg in half a second): side-step %.2f m/s at the most (to the %s), %.2f standing before, %.2f after" % [
		turned, widest, "left" if left_way < 0.0 else "right", still, after])
	assert_true(still < 0.01, "standing still, the legs were told to step (%.2f)" % still)
	assert_true(widest > 0.5, "turning on the spot, the legs were told only %.2f m/s of step" % widest)
	assert_true(left_way < -0.5, "a turn to the left stepped to the right")
	assert_true(after < 0.05, "the stepping went on after the turn (%.2f)" % after)
