class_name Player
extends Actor
## The Foundling. Movement (DESIGN §5.2), committed stamina combat (§5.3), cameras, lock-on,
## interaction, quick-slot hooks and save data. Input comes from the actions in
## core/default_bindings.json; edge detection is done here so scripted drivers that call
## Input.action_press() behave exactly like a keyboard.

enum State { FREE, ATTACK, DODGE, STUNNED, CAST, MANTLE, BOW, RIPOSTE, DEAD }

signal state_changed(from: int, to: int)
signal lock_on_changed(target: Node3D)
signal attack_started(kind: String, index: int)
signal dodge_started(direction: Vector3)
signal parried(attacker: Node)
signal equipment_changed(slot: String, item_id: String)
## The readied saying changed (empty when it was put away). The HUD and the sayings screen listen.
signal spell_readied(spell_id: String)
signal quick_slot_used(index: int, item_id: String)
signal camera_mode_changed(first_person: bool)

const WALK_SPEED := 4.2
const RUN_SPEED := 6.5
const SNEAK_MULT := 0.5
const BLOCK_MOVE_MULT := 0.6
const JUMP_HEIGHT := 1.1
const GROUND_ACCEL := 18.0
const AIR_ACCEL := 5.0
const TURN_SPEED := 14.0
const ATTACK_STEP_SPEED := 1.6
const MANTLE_MIN := 0.4
const MANTLE_MAX := 1.3
const MANTLE_TIME := 0.5
const BOW_MIN_DRAW := 0.3
const RIPOSTE_RANGE := 2.4
const LOAD_CAPACITY_BASE := 40.0
const LOAD_CAPACITY_PER_ENDURANCE := 3.0
const SAVE_SECTION := "player"
const SKILL_IDS: Array[String] = ["one_handed", "two_handed", "archery", "block", "armour", "sneak", "speech", "alchemy", "smithing", "enchanting", "athletics", "kindling", "hush", "binding", "mending", "calling"]
const ACTIONS: Array[String] = ["attack_light", "attack_heavy", "dodge", "jump", "cast", "interact", "block", "sprint", "sneak", "lock_on", "cycle_target", "toggle_camera", "toggle_lantern", "quick_1", "quick_2", "quick_3", "quick_4"]
const BUFFERABLE: Array[String] = ["attack_light", "attack_heavy", "dodge", "jump", "cast", "interact"]
const ARROW_SCENE := "res://systems/combat/arrow.tscn"

var state: int = State.FREE
var level: int = 1
var skills: Dictionary = {}
var equipped: Dictionary = {"main_hand": "", "off_hand": "", "body": ""}
var weapon: WeaponInstance = null
var offhand: Dictionary = {}
var quick_slots: Array = ["", "", "", ""]
## Inventory-stream hook: Callable(index: int, item_id: String) -> bool, called on quick slot use.
var quick_slot_handler: Callable = Callable()
## Inventory-stream hook: Callable(ammo_tag: String) -> bool, consumes one arrow when true.
var ammo_provider: Callable = Callable()
var equipped_spell: String = ""
## A carried light is off until the player strikes it, and it is the one thing they can do
## about the dark that also makes them easier to see (Stealth reads it as any other lamp).
var lantern_lit: bool = false
var arrows: int = 20
var is_sneaking: bool = false
var is_sprinting: bool = false
var load_ratio: float = 0.0
## Stealth-stream input (0 = invisible, 1 = plain sight); perception multiplies by this.
var stealth_visibility: float = 1.0
var input_enabled: bool = true

var camera_rig: CameraRig = null
var lock: PlayerLockOn = null
var interactor: Interactor = null

var _held: Dictionary = {}
var _just: Dictionary = {}
var _prev: Dictionary = {}
var _buffer_action: String = ""
var _buffer_at: float = -1.0
var _move_input: Vector2 = Vector2.ZERO
var _look_stick: Vector2 = Vector2.ZERO
var _lantern_light: OmniLight3D = null
## A crossbow is loaded, not drawn: it looses at once and then costs you the time back.
var _reload_until: float = -1.0
var _attack_kind: String = "light"
var _attack_index: int = 0
var _attack_phase: String = ""
var _attack_clip: String = ""
var _chain_open: bool = false
var _charging: bool = false
var _charge_start: float = 0.0
var _charge_ratio: float = 0.0
var _dodge_params: Dictionary = {}
var _dodge_elapsed: float = 0.0
var _dodge_dir: Vector3 = Vector3.FORWARD
var _mantle_from: Vector3 = Vector3.ZERO
var _mantle_to: Vector3 = Vector3.ZERO
var _mantle_t: float = 0.0
var _bow_draw_start: float = -1.0
var _riposte_target: Actor = null
var _sprint_toggle: bool = false
var _noise_timer: float = 0.0
var _was_on_floor: bool = true


func _ready() -> void:
	faction = "player"
	if display_name == "Actor":
		display_name = "Foundling"
	body_kind = "humanoid"
	collision_layer = LAYER_PLAYER
	max_health = DamageModel.hp_max(vigour)
	poise_max = 40.0
	for s in SKILL_IDS:
		if not skills.has(s):
			skills[s] = 10
	super()
	camera_rig = get_node_or_null("CameraRig") as CameraRig
	if camera_rig == null:
		camera_rig = CameraRig.new()
		camera_rig.name = "CameraRig"
		camera_rig.position = Vector3(0.0, 1.6, 0.0)
		add_child(camera_rig)
	lock = get_node_or_null("LockOn") as PlayerLockOn
	if lock == null:
		lock = PlayerLockOn.new()
		lock.name = "LockOn"
		add_child(lock)
	lock.owner_actor = self
	lock.target_changed.connect(_on_lock_changed)
	interactor = get_node_or_null("Interactor") as Interactor
	if interactor == null:
		interactor = Interactor.new()
		interactor.name = "Interactor"
		interactor.position = Vector3(0.0, 1.3, 0.0)
		add_child(interactor)
	caster.target_lookup = func() -> Node: return lock.target
	# A saying has to have been taught before it can be Said, whatever put the id in the slot.
	caster.known_lookup = func(spell_id: String) -> bool: return knows_spell(spell_id)
	caster.cast_released.connect(_on_cast_released)
	caster.cast_failed.connect(_on_cast_failed)
	camera_rig.mode_changed.connect(_on_camera_mode_changed)
	if weapon == null:
		equip_weapon("")
	_refresh_lantern()          # equipment restored before the body entered the tree
	add_to_group("player")
	SaveSystem.register(SAVE_SECTION, self)
	_register_character_sections()
	_follow_equipment()
	if DisplayServer.get_name() != "headless" and input_enabled:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	call_deferred("_announce")


func _announce() -> void:
	EventBus.player_spawned.emit(self)


func _exit_tree() -> void:
	if SaveSystem.participants.get(SAVE_SECTION) == self:
		SaveSystem.unregister(SAVE_SECTION)
	for pair in [["inventory", "Inventory"], ["equipment", "Equipment"],
			["progression", "Progression"], ["crafting", "Crafting"]]:
		var node := get_node_or_null(NodePath(pair[1]))
		if node != null and SaveSystem.participants.get(str(pair[0])) == node:
			SaveSystem.unregister(str(pair[0]))


# --- input --------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			lock.handle_wheel(-1, lock_point(), camera_rig.forward_flat())
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			lock.handle_wheel(1, lock_point(), camera_rig.forward_flat())
		elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event.is_action_pressed("pause") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _read_input() -> void:
	for a in ACTIONS:
		var pressed := input_enabled and Input.is_action_pressed(a)
		_just[a] = pressed and not bool(_prev.get(a, false))
		_prev[a] = pressed
		_held[a] = pressed
	_move_input = Input.get_vector("move_left", "move_right", "move_forward", "move_back") if input_enabled else Vector2.ZERO
	_look_stick = Input.get_vector("look_left", "look_right", "look_up", "look_down") if input_enabled else Vector2.ZERO
	for a in BUFFERABLE:
		if _just[a]:
			_buffer_action = a
			_buffer_at = now()


func _peek_buffer(actions: Array) -> String:
	if _buffer_action != "" and actions.has(_buffer_action) and DamageModel.buffer_valid(_buffer_at, now()):
		return _buffer_action
	return ""


func _consume_buffer(actions: Array) -> String:
	var a := _peek_buffer(actions)
	if a != "":
		_buffer_action = ""
		_buffer_at = -1.0
	return a


func set_input_enabled(enabled: bool) -> void:
	input_enabled = enabled
	camera_rig.look_enabled = enabled
	if not enabled:
		_move_input = Vector2.ZERO
		_look_stick = Vector2.ZERO
		for a in ACTIONS:
			_held[a] = false
			_just[a] = false
		is_sprinting = false
		_buffer_action = ""


# --- main loop ----------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_read_input()
	lock.validate(lock_point())
	camera_rig.stick = _look_stick
	camera_rig.set_lock_point(lock.target_point(), lock.is_locked())
	camera_rig.sneak_low = is_sneaking
	interactor.update_aim(camera_rig.aim_direction())
	if shield_hp > 0.0 and now() >= shield_until:
		shield_hp = 0.0
		shield_changed.emit(0.0)
	match state:
		State.FREE: _tick_free(delta)
		State.ATTACK: _tick_attack(delta)
		State.DODGE: _tick_dodge(delta)
		State.STUNNED: _tick_stunned(delta)
		State.CAST: _tick_cast(delta)
		State.MANTLE: _tick_mantle(delta)
		State.BOW: _tick_bow(delta)
		State.RIPOSTE: _tick_riposte(delta)
		State.DEAD: _damp_horizontal(delta, 10.0)
	if state != State.MANTLE:
		apply_gravity(delta)
		integrate_shove(delta)
		move_and_slide()
	_update_locomotion_anim(delta)
	_noise_timer -= delta


func _set_state(s: int) -> void:
	if s == state:
		return
	var prev := state
	state = s
	state_changed.emit(prev, s)


func state_name() -> String:
	return State.keys()[state]


func is_busy() -> bool:
	return state in [State.ATTACK, State.DODGE, State.CAST, State.BOW, State.RIPOSTE, State.MANTLE]


# --- FREE ---------------------------------------------------------------------------------------

func _tick_free(delta: float) -> void:
	if is_stunned():
		_enter_stunned()
		return
	_update_common_toggles()
	_update_block()
	var buffered := _consume_buffer(["dodge", "attack_light", "attack_heavy", "cast", "jump", "interact"])
	match buffered:
		"dodge":
			if _start_dodge():
				return
		"attack_light":
			if weapon.is_ranged():
				if _start_bow():
					return
			else:
				var rt := _riposte_candidate()
				if rt != null:
					_start_riposte(rt)
					return
				if _start_attack("light", 0, false):
					return
		"attack_heavy":
			if not weapon.is_ranged() and _start_attack("heavy", 0, true):
				return
		"cast":
			if _start_cast():
				return
		"jump":
			if is_on_floor() and not is_blocking:
				if not _try_mantle():
					velocity.y = sqrt(2.0 * gravity * JUMP_HEIGHT)
					anim.play_intent("Jump_Start")
					_emit_noise(0.4)
				return
		"interact":
			if interactor.try_interact(self):
				anim.play_intent("Interact")
	if not is_on_floor() and _move_input.y < -0.5 and velocity.y < 1.0 and _try_mantle():
		return
	_move(delta)
	if is_on_floor() and not _was_on_floor and not anim.is_busy():
		anim.play_intent("Jump_Land")
	_was_on_floor = is_on_floor()


func _update_common_toggles() -> void:
	if _just["toggle_camera"]:
		camera_rig.toggle_mode()
	if _just["toggle_lantern"]:
		toggle_lantern()
	if _just["sneak"]:
		is_sneaking = not is_sneaking
		if is_sneaking:
			is_sprinting = false
	if _just["lock_on"]:
		lock.handle_toggle(lock_point(), camera_rig.forward_flat())
	if _just["cycle_target"]:
		lock.handle_cycle_action(lock_point(), camera_rig.forward_flat())
	lock.handle_stick(_look_stick, lock_point(), camera_rig.forward_flat())
	for i in 4:
		if _just["quick_%d" % (i + 1)]:
			use_quick_slot(i)


func _update_block() -> void:
	var parry_item := can_parry_with_equipment()
	if _just["block"] and parry_item and stamina_comp.current > 0.0 and not weapon.is_ranged():
		parry_pressed_at = now()
		if not anim.is_busy():
			anim.play_intent("Parry")
	var want := bool(_held["block"]) and not weapon.is_ranged() and stamina_comp.current > 0.0 and is_on_floor()
	is_blocking = want
	can_parry = parry_item
	block_stability = block_stability_value()
	stamina_comp.regen_multiplier = 0.5 if is_blocking else 1.0
	if is_blocking and not anim.is_busy() and not anim.is_playing("Block_Idle") and not anim.is_playing("Parry"):
		anim.play_intent("Block_Idle")
	elif not is_blocking and anim.is_playing("Block_Idle"):
		anim.stop()


func can_parry_with_equipment() -> bool:
	if not offhand.is_empty() and bool(offhand.get("armour", {}).get("parry", false)):
		return true
	return weapon != null and weapon.can_parry


func block_stability_value() -> float:
	if not offhand.is_empty() and not weapon.is_two_handed():
		return clampf(float(offhand.get("armour", {}).get("stability", 0.0)), 0.0, 1.0)
	return weapon.stability if weapon != null else 0.0


func _wish_direction() -> Vector3:
	var basis := Basis(Vector3.UP, camera_rig.yaw)
	var wish := basis * Vector3(_move_input.x, 0.0, _move_input.y)
	wish.y = 0.0
	if wish.length() > 1.0:
		wish = wish.normalized()
	return wish


func _sprint_wanted() -> bool:
	if bool(Settings.get_value("controls", "toggle_sprint", false)):
		if _just["sprint"]:
			_sprint_toggle = not _sprint_toggle
		if _move_input.length() < 0.1:
			_sprint_toggle = false
		return _sprint_toggle
	return bool(_held["sprint"])


func _move(delta: float) -> void:
	var wish := _wish_direction()
	var speed := WALK_SPEED
	is_sprinting = _sprint_wanted() and wish.length() > 0.1 and not is_blocking and stamina_comp.current > 0.0 and is_on_floor()
	if is_sprinting:
		is_sneaking = false
		speed = RUN_SPEED
		stamina_comp.drain(DamageModel.STAMINA_SPRINT_PER_S, delta)
		if _noise_timer <= 0.0:
			_emit_noise(0.6)
			_noise_timer = 0.4
	if is_sneaking:
		speed *= SNEAK_MULT
	if is_blocking:
		speed *= BLOCK_MOVE_MULT
	speed *= speed_multiplier()
	var target_v := wish * speed
	var accel := GROUND_ACCEL if is_on_floor() else AIR_ACCEL
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(target_v, accel * delta * maxf(speed, 1.0))
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	_face_for_movement(wish, delta)


func _face_for_movement(wish: Vector3, delta: float) -> void:
	if camera_rig.first_person or lock.is_locked() or is_blocking:
		var target_yaw := camera_rig.yaw if not lock.is_locked() else yaw_to(lock.target_point())
		rotation.y = lerp_angle(rotation.y, target_yaw, clampf(TURN_SPEED * delta, 0.0, 1.0))
	elif wish.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(-wish.x, -wish.z), clampf(TURN_SPEED * delta, 0.0, 1.0))


func _damp_horizontal(delta: float, rate: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _update_locomotion_anim(_delta: float) -> void:
	var local := global_transform.basis.inverse() * Vector3(velocity.x, 0.0, velocity.z)
	anim.set_locomotion(Vector2(local.x, -local.z) / RUN_SPEED, is_sneaking)
	if state == State.FREE and not anim.is_busy() and not is_blocking:
		if not is_on_floor() and velocity.y < -3.0 and not anim.is_playing("Fall_Loop"):
			anim.play_intent("Fall_Loop")
		elif is_on_floor() and anim.is_playing("Fall_Loop"):
			anim.stop()
	model.visible = not camera_rig.first_person


# --- ATTACK -------------------------------------------------------------------------------------

func _start_attack(kind: String, index: int, charging: bool) -> bool:
	if not can_act() or weapon == null:
		return false
	var cost := weapon.stamina_cost(kind)
	if not stamina_comp.can_afford(cost):
		return false
	stamina_comp.spend(cost)
	is_blocking = false
	_attack_kind = kind
	_attack_index = index
	_attack_phase = "windup"
	_chain_open = false
	_charging = charging
	_charge_start = now()
	_charge_ratio = 0.0
	var timing := weapon.timing_for(kind, index)
	weapon.begin_attack(weapon.build_hit(kind, index, 0.0, get_skill(weapon.skill_id)))
	_face_attack_target()
	_attack_clip = weapon.clip_for(kind, index)
	anim.play_intent(_attack_clip, timing)
	if charging:
		var hs := float(anim.event_times.get("hit_start", 0.4))
		anim.hold(maxf(hs - 0.05, 0.05))
	_set_state(State.ATTACK)
	attack_started.emit(kind, index)
	return true


func _face_attack_target() -> void:
	if lock.is_locked():
		snap_facing(lock.target_point() - global_position)
	elif camera_rig.first_person:
		rotation.y = camera_rig.yaw
	else:
		var wish := _wish_direction()
		if wish.length() > 0.2:
			snap_facing(wish)


func _tick_attack(delta: float) -> void:
	if is_stunned():
		_enter_stunned()
		return
	if _charging:
		_charge_ratio = clampf((now() - _charge_start) / DamageModel.HEAVY_CHARGE_TIME, 0.0, 1.0)
		if lock.is_locked():
			face_toward(lock.target_point(), TURN_SPEED, delta)
		elif camera_rig.first_person:
			rotation.y = camera_rig.yaw
		if not _held["attack_heavy"] or _charge_ratio >= 1.0:
			_release_charge()
	if _attack_phase == "active":
		var f := forward() * ATTACK_STEP_SPEED
		velocity.x = f.x
		velocity.z = f.z
	else:
		_damp_horizontal(delta, 20.0)
	if _attack_phase == "recovery" and _peek_buffer(["dodge"]) != "":
		_consume_buffer(["dodge"])
		weapon.end_attack()
		if _start_dodge():
			return
	if _chain_open and _attack_kind == "light" and _attack_index + 1 < weapon.chain_length() and _peek_buffer(["attack_light"]) != "":
		_consume_buffer(["attack_light"])
		weapon.end_attack()
		_start_attack("light", _attack_index + 1, false)


func _release_charge() -> void:
	_charging = false
	anim.release_hold()
	weapon.begin_attack(weapon.build_hit("heavy", 0, _charge_ratio, get_skill(weapon.skill_id)))


func _on_clip_event(event_name: String) -> void:
	match event_name:
		"hit_start":
			if state == State.ATTACK or state == State.RIPOSTE:
				_attack_phase = "active"
				weapon.on_clip_event(event_name)
				_emit_noise(0.5)
		"hit_end":
			if state == State.ATTACK or state == State.RIPOSTE:
				_attack_phase = "recovery"
				weapon.on_clip_event(event_name)
		"cancel_ok":
			_chain_open = true


func _on_clip_finished(clip: String) -> void:
	match state:
		State.ATTACK:
			if clip == _attack_clip:
				weapon.end_attack()
				if _attack_kind == "light" and _attack_index + 1 < weapon.chain_length() and _peek_buffer(["attack_light"]) != "":
					_consume_buffer(["attack_light"])
					_start_attack("light", _attack_index + 1, false)
				else:
					_set_state(State.FREE)
		State.RIPOSTE:
			if clip == "Riposte" or clip == "Backstab":
				weapon.end_attack()
				_riposte_target = null
				_set_state(State.FREE)
		_:
			pass


func _on_weapon_hit(_victim: Node, hit: HitData, outcome: String) -> void:
	if outcome == "hit" or outcome == "blocked":
		EventBus.skill_used.emit(hit.skill_id, 4.0 if hit.heavy else 2.0)
		_emit_noise(0.6)


# --- RIPOSTE ------------------------------------------------------------------------------------

func _riposte_candidate() -> Actor:
	var best: Actor = null
	var best_d := RIPOSTE_RANGE
	var pool: Array = [lock.target] if lock.is_locked() else get_tree().get_nodes_in_group("actors")
	for n in pool:
		if not (n is Actor) or n == self:
			continue
		var a := n as Actor
		if not a.is_riposte_open() or a.is_dead():
			continue
		var to := a.global_position - global_position
		var d := Vector3(to.x, 0.0, to.z).length()
		if d <= best_d and DamageModel.is_facing(forward(), to, 0.3):
			best = a
			best_d = d
	return best


func _start_riposte(target: Actor) -> void:
	_riposte_target = target
	snap_facing(target.global_position - global_position)
	target.stunned_until = maxf(target.stunned_until, now() + 1.4)
	_attack_kind = "riposte"
	_attack_index = 0
	_attack_phase = "windup"
	weapon.begin_attack(weapon.build_hit("riposte", 0, 0.0, get_skill(weapon.skill_id), "riposte"))
	anim.play_intent("Riposte", weapon.timing_for("riposte"))
	_set_state(State.RIPOSTE)
	attack_started.emit("riposte", 0)


func _tick_riposte(delta: float) -> void:
	if is_stunned():
		_enter_stunned()
		return
	if _attack_phase == "active" and is_instance_valid(_riposte_target):
		var to := _riposte_target.global_position - global_position
		to.y = 0.0
		if to.length() > 1.2:
			var step := to.normalized() * 2.5
			velocity.x = step.x
			velocity.z = step.z
			return
	_damp_horizontal(delta, 20.0)


# --- DODGE --------------------------------------------------------------------------------------

func _start_dodge() -> bool:
	if not can_act():
		return false
	if not stamina_comp.can_afford(DamageModel.STAMINA_DODGE):
		return false
	stamina_comp.spend(DamageModel.STAMINA_DODGE)
	_dodge_params = DamageModel.dodge_params(load_ratio)
	_dodge_elapsed = 0.0
	is_blocking = false
	var wish := _wish_direction()
	var clip := "Dodge_F"
	if wish.length() > 0.1:
		_dodge_dir = wish.normalized()
	elif lock.is_locked():
		_dodge_dir = -forward()
	else:
		_dodge_dir = forward()
	if lock.is_locked() or camera_rig.first_person:
		var local := global_transform.basis.inverse() * _dodge_dir
		if absf(local.x) > absf(local.z):
			clip = "Dodge_R" if local.x > 0.0 else "Dodge_L"
		else:
			clip = "Dodge_F" if local.z < 0.0 else "Dodge_B"
	else:
		snap_facing(_dodge_dir)
	var t := now()
	set_invulnerable_window(t + float(_dodge_params["iframe_start"]), t + float(_dodge_params["iframe_end"]))
	anim.play_intent(clip, {"length": float(_dodge_params["duration"])})
	_set_state(State.DODGE)
	dodge_started.emit(_dodge_dir)
	return true


func _tick_dodge(delta: float) -> void:
	if is_stunned():
		_enter_stunned()
		return
	_dodge_elapsed += delta
	var duration := float(_dodge_params["duration"])
	var p := clampf(_dodge_elapsed / duration, 0.0, 1.0)
	var v := _dodge_dir * (2.0 * float(_dodge_params["distance"]) / duration) * (1.0 - p)
	velocity.x = v.x
	velocity.z = v.z
	if p > 0.75 and _peek_buffer(["attack_light", "attack_heavy"]) != "":
		var a := _consume_buffer(["attack_light", "attack_heavy"])
		clear_invulnerability()
		if _start_attack("heavy" if a == "attack_heavy" else "light", 0, a == "attack_heavy"):
			return
	if _dodge_elapsed >= duration:
		clear_invulnerability()
		_set_state(State.FREE)


func is_in_iframes() -> bool:
	return state == State.DODGE and is_invulnerable()


# --- STUNNED / DEAD -----------------------------------------------------------------------------

func on_action_interrupted() -> void:
	if weapon != null:
		weapon.end_attack()
	_charging = false
	anim.release_hold()
	caster.interrupt()
	is_blocking = false
	camera_rig.set_aiming(false)
	clear_invulnerability()
	_riposte_target = null
	if state != State.DEAD:
		_set_state(State.STUNNED)


func _enter_stunned() -> void:
	on_action_interrupted()


func _tick_stunned(delta: float) -> void:
	_damp_horizontal(delta, 12.0)
	if not is_stunned():
		_set_state(State.FREE)


func die(killer: Node = null) -> void:
	if dead:
		return
	super.die(killer)
	_set_state(State.DEAD)
	lock.clear()
	EventBus.player_died.emit(global_position)


## Debug/scripted death (the Debug console's `die` command).
func kill() -> void:
	if not dead:
		health = 0.0
		die(null)


## Called by the Hearth autoload after the death delay; Hearth owns the respawn point and Echo.
func respawn(position: Vector3, yaw: float) -> void:
	global_position = position
	rotation.y = yaw
	velocity = Vector3.ZERO
	revive()
	collision_layer = LAYER_PLAYER
	_buffer_action = ""
	_set_state(State.FREE)
	camera_rig.yaw = yaw
	set_input_enabled(true)


# --- CAST ---------------------------------------------------------------------------------------

func _start_cast() -> bool:
	if not can_act():
		return false
	if equipped_spell.is_empty():
		EventBus.notify.emit("No saying readied.", "warning")
		return false
	if not caster.cast(equipped_spell, lock.target):
		return false
	var def := ContentDB.get_or_empty(equipped_spell)
	var ct := SpellRuntime.cast_time_of(def, get_skill(SpellRuntime.skill_for(def)))
	_face_attack_target()
	anim.play_intent(SpellRuntime.clip_for(def), {"length": ct})
	_set_state(State.CAST)
	return true


func _tick_cast(delta: float) -> void:
	if is_stunned():
		_enter_stunned()
		return
	if lock.is_locked():
		face_toward(lock.target_point(), TURN_SPEED, delta)
	elif camera_rig.first_person:
		rotation.y = camera_rig.yaw
	_damp_horizontal(delta, 16.0)


func _on_cast_released(_spell_id: String) -> void:
	if state == State.CAST:
		_set_state(State.FREE)


func _on_cast_failed(_spell_id: String, reason: String) -> void:
	match reason:
		"silenced": EventBus.notify.emit("You cannot Say anything: silenced.", "warning")
		"mana": EventBus.notify.emit("Not enough breath to Say it.", "warning")
		"no_target": EventBus.notify.emit("No target.", "warning")
		"not_known": EventBus.notify.emit("You have not been taught that saying.", "warning")
		"busy": EventBus.notify.emit("You are already saying something.", "warning")
	if state == State.CAST and reason != "interrupted":
		_set_state(State.FREE)


func aim_direction() -> Vector3:
	if camera_rig.first_person:
		return camera_rig.aim_direction()
	var far := camera_rig.camera_position() + camera_rig.aim_direction() * 40.0
	return (far - aim_origin()).normalized()


func aim_origin() -> Vector3:
	return global_position + Vector3.UP * 1.45 + forward() * 0.35


# --- BOW ----------------------------------------------------------------------------------------

func _start_bow() -> bool:
	if not can_act():
		return false
	if arrows <= 0 and not ammo_provider.is_valid():
		EventBus.notify.emit("No arrows.", "warning")
		return false
	if now() < _reload_until:
		EventBus.notify.emit("Still winding.", "warning")
		return false
	_bow_draw_start = now()
	var draw_time := float(weapon.ranged.get("draw_time", 0.7))
	anim.play_intent("Bow_Draw", {"length": draw_time})
	camera_rig.set_aiming(true)
	_set_state(State.BOW)
	return true


func _tick_bow(delta: float) -> void:
	if is_stunned():
		_enter_stunned()
		return
	rotation.y = lerp_angle(rotation.y, camera_rig.yaw, clampf(TURN_SPEED * delta, 0.0, 1.0))
	var wish := _wish_direction() * WALK_SPEED * 0.5
	velocity.x = wish.x
	velocity.z = wish.z
	var draw_time := maxf(float(weapon.ranged.get("draw_time", 0.7)), 0.1)
	var drawn := clampf((now() - _bow_draw_start) / draw_time, 0.0, 1.0)
	if drawn >= 1.0 and not anim.is_playing("Bow_Aim") and not anim.is_busy():
		anim.play_intent("Bow_Aim")
	if _peek_buffer(["dodge"]) != "":
		camera_rig.set_aiming(false)
		_consume_buffer(["dodge"])
		if _start_dodge():
			return
	if not _held["attack_light"]:
		camera_rig.set_aiming(false)
		if drawn >= BOW_MIN_DRAW:
			_fire_arrow(drawn)
			anim.play_intent("Bow_Release")
		else:
			anim.stop()
		_set_state(State.FREE)


func _fire_arrow(drawn: float) -> void:
	if ammo_provider.is_valid():
		if not bool(ammo_provider.call(str(weapon.ranged.get("ammo_tag", "arrow")))):
			EventBus.notify.emit("No arrows.", "warning")
			return
	elif arrows > 0:
		arrows -= 1
	else:
		return
	stamina_comp.spend(weapon.stamina_cost("light"))
	var arrow_def := ContentDB.get_or_empty(str(weapon.ranged.get("ammo_item", "")))
	var proj: Dictionary = arrow_def.get("projectile", {})
	var scene_path := str(proj.get("scene", ARROW_SCENE))
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return
	var arrow := packed.instantiate() as Projectile
	if arrow == null:
		return
	get_tree().current_scene.add_child(arrow)
	var hit := HitData.new()
	# The shaft's own contribution: `damage` for a self-contained projectile, `damage_mult` for
	# ammunition whose worth is in the head it carries. Both were in the pack; only one was read.
	var base := (weapon.damage + float(proj.get("damage", 0.0))) * float(proj.get("damage_mult", 1.0))
	hit.amount = DamageModel.raw_damage(base, get_skill(weapon.skill_id), lerpf(0.5, 1.0, drawn), 1.0)
	hit.kind = str(proj.get("kind", "pierce"))
	hit.poise_damage = weapon.poise_damage + float(proj.get("poise_damage", 0.0))
	hit.attacker = self
	hit.skill_id = weapon.skill_id
	hit.label = "arrow"
	hit.parryable = false
	var speed := float(weapon.ranged.get("speed", 42.0)) * lerpf(0.6, 1.0, drawn)
	arrow.launch(aim_origin(), aim_direction(), speed, hit, float(proj.get("gravity", gravity)))
	arrow.struck.connect(func(_v: Node, h: HitData, outcome: String) -> void:
		if outcome == "hit" or outcome == "blocked":
			EventBus.skill_used.emit(h.skill_id, 3.0))
	var reload := float(weapon.ranged.get("reload_time", 0.0))
	if reload > 0.0:
		_reload_until = now() + reload
	_emit_noise(0.3)


# --- MANTLE -------------------------------------------------------------------------------------

func _try_mantle() -> bool:
	var wish := _wish_direction()
	var dir := wish.normalized() if wish.length() > 0.2 else forward()
	var space := get_world_3d().direct_space_state
	var feet := global_position
	var mask := LAYER_WORLD | LAYER_TERRAIN
	var knee_q := PhysicsRayQueryParameters3D.create(feet + Vector3.UP * 0.45, feet + Vector3.UP * 0.45 + dir * 0.9, mask, [get_rid()])
	if space.intersect_ray(knee_q).is_empty():
		return false
	var head_q := PhysicsRayQueryParameters3D.create(feet + Vector3.UP * (MANTLE_MAX + 0.25), feet + Vector3.UP * (MANTLE_MAX + 0.25) + dir * 0.9, mask, [get_rid()])
	if not space.intersect_ray(head_q).is_empty():
		return false
	var probe := feet + Vector3.UP * (MANTLE_MAX + 0.25) + dir * 0.7
	var down_q := PhysicsRayQueryParameters3D.create(probe, probe + Vector3.DOWN * (MANTLE_MAX + 0.3), mask, [get_rid()])
	var hit := space.intersect_ray(down_q)
	if hit.is_empty() or Vector3(hit["normal"]).y < 0.7:
		return false
	var top: Vector3 = hit["position"]
	var h := top.y - feet.y
	if h < MANTLE_MIN or h > MANTLE_MAX:
		return false
	_mantle_from = feet
	_mantle_to = Vector3(top.x, top.y + 0.03, top.z) + dir * 0.12
	_mantle_t = 0.0
	velocity = Vector3.ZERO
	snap_facing(dir)
	anim.play_intent("Jump_Start")
	_set_state(State.MANTLE)
	return true


func _tick_mantle(delta: float) -> void:
	_mantle_t += delta / MANTLE_TIME
	var t := clampf(_mantle_t, 0.0, 1.0)
	var p := _mantle_from.lerp(_mantle_to, t)
	p.y = lerpf(_mantle_from.y, _mantle_to.y, minf(t * 1.6, 1.0))
	global_position = p
	velocity = Vector3.ZERO
	if t >= 1.0:
		anim.play_intent("Jump_Land")
		_set_state(State.FREE)


# --- equipment / skills / quick slots -----------------------------------------------------------

func get_skill(skill_id: String) -> float:
	return float(skills.get(skill_id, 10))


func set_skill(skill_id: String, level_value: int) -> void:
	skills[skill_id] = level_value


func equip_weapon(item_id: String, instance_data: Dictionary = {}) -> void:
	if weapon != null:
		weapon.end_attack()
		weapon.queue_free()
	weapon = WeaponInstance.unarmed(self) if item_id.is_empty() else WeaponInstance.from_item(item_id, self, instance_data)
	attack_origin.add_child(weapon)
	weapon.hit_landed.connect(_on_weapon_hit)
	equipped["main_hand"] = item_id
	_recompute_load()
	equipment_changed.emit("main_hand", item_id)
	EventBus.item_equipped.emit("main_hand", item_id)


func equip_offhand(item_id: String) -> void:
	offhand = ContentDB.get_or_empty(item_id) if not item_id.is_empty() else {}
	equipped["off_hand"] = item_id
	_refresh_lantern()
	_recompute_load()
	equipment_changed.emit("off_hand", item_id)
	EventBus.item_equipped.emit("off_hand", item_id)


func equip_armour(item_id: String) -> void:
	var def := ContentDB.get_or_empty(item_id) if not item_id.is_empty() else {}
	equipped["body"] = item_id
	armour_flat = float(def.get("armour", {}).get("armour", 0.0))
	_recompute_load()
	equipment_changed.emit("body", item_id)
	EventBus.item_equipped.emit("body", item_id)


## The `light` block on the off-hand item (CONTRACTS §7) becomes a real lamp on the lantern
## socket, with a StealthLight beside it so being lit costs you the dark. Nothing carried means
## nothing to strike.
func _refresh_lantern() -> void:
	if not is_inside_tree():
		return          # equipment can be restored before the body is in the world; _ready retries
	var light_def: Dictionary = offhand.get("light", {})
	if light_def.is_empty():
		if _lantern_light != null:
			# Taken out of the tree at once, not on the next frame: anything asking whether a
			# light is carried must get the answer the equipment change already gave.
			var parent := _lantern_light.get_parent()
			if parent != null:
				parent.remove_child(_lantern_light)
			_lantern_light.queue_free()
			_lantern_light = null
		lantern_lit = false
		return
	if _lantern_light == null:
		_lantern_light = OmniLight3D.new()
		_lantern_light.name = "CarriedLight"
		_lantern_light.shadow_enabled = true
		_lantern_light.light_bake_mode = Light3D.BAKE_DISABLED
		var stealth_light := StealthLight.new()
		stealth_light.name = "StealthLight"
		_lantern_light.add_child(stealth_light)
		get_socket("Socket.Lantern").add_child(_lantern_light)
	_lantern_light.omni_range = float(light_def.get("range", 8.0))
	_lantern_light.light_energy = float(light_def.get("energy", 1.0))
	_lantern_light.light_color = Color.html(str(light_def.get("color", "#ffb86a")))
	var stealth := _lantern_light.get_node_or_null("StealthLight") as StealthLight
	if stealth != null:
		stealth.range_m = _lantern_light.omni_range
		stealth.energy = _lantern_light.light_energy
		stealth.enabled = lantern_lit
	_lantern_light.visible = lantern_lit


## Strikes or shutters the carried light. Returns whether anything is lit afterwards.
func toggle_lantern() -> bool:
	if offhand.get("light", {}).is_empty():
		EventBus.notify.emit("You have nothing to light.", "warning")
		return false
	lantern_lit = not lantern_lit
	_refresh_lantern()
	var said := "The %s is lit." % str(offhand.get("name", "lantern")).to_lower() if lantern_lit else "You shutter the light."
	EventBus.notify.emit(said, "item")
	return lantern_lit


## Seconds before the weapon can be loosed again; 0 for a bow, which is drawn instead.
func reload_left() -> float:
	return maxf(_reload_until - now(), 0.0)


## How much the thing in your hand adds to a saying. A staff carries a `casting` block naming
## the school it was cut for; holding the right one for the saying is worth its power_mult.
func casting_power(school: String = "") -> float:
	if weapon == null:
		return 1.0
	var casting: Dictionary = weapon.item_def.get("casting", {})
	if casting.is_empty():
		return 1.0
	var cut_for := str(casting.get("school", ""))
	if cut_for != "" and school != "" and cut_for != school:
		return 1.0
	return float(casting.get("power_mult", 1.0))


## The Progression node that keeps what this character has learned, if there is one.
func progression() -> Node:
	var p := get_node_or_null(NodePath("Progression"))
	if p != null:
		return p
	return get_tree().get_first_node_in_group("progression") if is_inside_tree() else null


## Whether this character has been taught a saying. With no progression node (an arena test,
## a review harness) nothing has been taught, so nothing is castable — which is the honest
## answer rather than a silently permissive one.
func knows_spell(spell_id: String) -> bool:
	if spell_id.is_empty():
		return false
	var prog := progression()
	if prog != null and prog.has_method("knows_spell"):
		return bool(prog.call("knows_spell", spell_id))
	return false


## Puts away a readied saying the character turns out not to know (an old save, a pack that
## is no longer loaded, a console id). Runs a frame after a load, once progression is back.
func _validate_readied_saying() -> void:
	if equipped_spell.is_empty():
		return
	if knows_spell(equipped_spell):
		spell_readied.emit(equipped_spell)
		return
	Log.warn("Player", "readied saying '%s' is not known; slot cleared" % equipped_spell)
	equipped_spell = ""
	spell_readied.emit("")


## Readies a saying (the sayings screen and the quick slots call this). An empty id puts the
## saying away; an unknown one is refused and says so. Returns whether the slot now holds it.
func equip_spell(spell_id: String) -> bool:
	if spell_id.is_empty():
		equipped_spell = ""
		spell_readied.emit("")
		return true
	if not knows_spell(spell_id):
		EventBus.notify.emit("You have not been taught that saying.", "warning")
		return false
	equipped_spell = spell_id
	spell_readied.emit(spell_id)
	return true


## Placeholder load until the inventory stream owns weights: equipped weight over capacity.
func _recompute_load() -> void:
	var weight := 0.0
	for slot in equipped:
		var id: String = equipped[slot]
		if not id.is_empty():
			weight += float(ContentDB.get_or_empty(id).get("weight", 0.0))
	load_ratio = weight / (LOAD_CAPACITY_BASE + LOAD_CAPACITY_PER_ENDURANCE * float(endurance))


func set_quick_slot(index: int, item_id: String) -> void:
	if index >= 0 and index < quick_slots.size():
		quick_slots[index] = item_id


func use_quick_slot(index: int) -> void:
	if index < 0 or index >= quick_slots.size():
		return
	var id: String = quick_slots[index]
	quick_slot_used.emit(index, id)
	if quick_slot_handler.is_valid():
		quick_slot_handler.call(index, id)
	elif not id.is_empty() and Ids.type_of(id) == "spell":
		if equip_spell(id):
			EventBus.notify.emit("Readied %s." % ContentDB.get_or_empty(id).get("name", id), "info")


func _emit_noise(loudness: float) -> void:
	for n in get_tree().get_nodes_in_group("perceivers"):
		if n.has_method("noise_heard"):
			n.noise_heard(global_position, loudness)


func _on_lock_changed(target: Node3D) -> void:
	lock_on_changed.emit(target)


func _on_camera_mode_changed(fp: bool) -> void:
	model.visible = not fp
	camera_mode_changed.emit(fp)


# --- save ---------------------------------------------------------------------------------------

## The bag, the paper doll, the skills and the known recipes ride with the character, not
## with the world, so the player owns their save sections. Each is registered under its
## own name so a future pack can add one without touching this file.
## Binds the hands to the Equipment node when the player has one, so what the menu equips is
## what gets swung, with the stack's temper and enchantment on it. Without an Equipment node
## (the arena, the tests) equip_weapon stays the way in.
func _follow_equipment() -> void:
	var eq := get_node_or_null(NodePath("Equipment"))
	if eq == null or not eq.has_signal("changed"):
		return
	if not eq.changed.is_connected(_on_equipment_changed):
		eq.changed.connect(_on_equipment_changed)
	for slot in ["main_hand", "off_hand", "body"]:
		_on_equipment_changed(slot)


func _on_equipment_changed(slot: String) -> void:
	var eq := get_node_or_null(NodePath("Equipment"))
	if eq == null or not eq.has_method("get_slot"):
		return
	var stack: Variant = eq.call("get_slot", slot)
	var id := str(stack.id) if stack != null else ""
	var stack_data: Dictionary = stack.data.duplicate(true) if stack != null else {}
	match slot:
		"main_hand":
			if id != equipped.get("main_hand", "") or not stack_data.is_empty():
				equip_weapon(id, stack_data)
		"off_hand":
			equip_offhand(id)
		"body":
			equip_armour(id)


## The blade running down: the WeaponInstance spent charge, so the stack it came from loses it
## too, which is what makes it survive unequipping and a save.
func on_weapon_charge_spent(item_id: String, left: int) -> void:
	var eq := get_node_or_null(NodePath("Equipment"))
	if eq == null or not eq.has_method("get_slot"):
		return
	var stack: Variant = eq.call("get_slot", "main_hand")
	if stack == null or str(stack.id) != item_id:
		return
	var ench: Dictionary = stack.data.get("enchant", {})
	if ench.is_empty():
		return
	ench["charge"] = left
	stack.data["enchant"] = ench


func _register_character_sections() -> void:
	for pair in [["inventory", "Inventory"], ["equipment", "Equipment"],
			["progression", "Progression"], ["crafting", "Crafting"]]:
		var node := get_node_or_null(NodePath(pair[1]))
		if node and node.has_method("to_save"):
			SaveSystem.register(str(pair[0]), node)


func to_save() -> Dictionary:
	var d := super.to_save()
	d["name"] = display_name
	d["level"] = level
	d["attributes"] = {"vigour": vigour, "endurance": endurance, "will": will}
	d["stamina"] = stamina_comp.to_save()
	d["mana"] = caster.to_save()
	d["equipped"] = equipped.duplicate()
	d["equipped_spell"] = equipped_spell
	d["lantern_lit"] = lantern_lit
	d["quick_slots"] = quick_slots.duplicate()
	d["skills"] = skills.duplicate()
	d["arrows"] = arrows
	d["first_person"] = camera_rig.first_person
	d["sneaking"] = is_sneaking
	return d


func from_save(d: Dictionary) -> void:
	display_name = str(d.get("name", display_name))
	level = int(d.get("level", level))
	var attrs: Dictionary = d.get("attributes", {})
	vigour = int(attrs.get("vigour", vigour))
	endurance = int(attrs.get("endurance", endurance))
	will = int(attrs.get("will", will))
	max_health = DamageModel.hp_max(vigour)
	stamina_comp.setup(DamageModel.stamina_max(endurance), false)
	caster.mana_max = DamageModel.mana_max(will)
	for k in d.get("skills", {}):
		skills[k] = int(d["skills"][k])
	var eq: Dictionary = d.get("equipped", {})
	equip_weapon(str(eq.get("main_hand", "")))
	equip_offhand(str(eq.get("off_hand", "")))
	equip_armour(str(eq.get("body", "")))
	# The readied saying comes back as saved. It cannot be checked against what the character
	# knows yet — the "progression" section loads after this one — so the check is deferred to
	# the end of the frame. Until then the caster's own gate refuses it anyway.
	equipped_spell = str(d.get("equipped_spell", ""))
	lantern_lit = bool(d.get("lantern_lit", false))
	_refresh_lantern()
	call_deferred("_validate_readied_saying")
	var qs: Array = d.get("quick_slots", [])
	for i in mini(qs.size(), quick_slots.size()):
		quick_slots[i] = str(qs[i])
	arrows = int(d.get("arrows", arrows))
	super.from_save(d)
	stamina_comp.from_save(d.get("stamina", {}))
	caster.from_save(d.get("mana", {}))
	camera_rig.set_first_person(bool(d.get("first_person", false)))
	camera_rig.yaw = rotation.y
	is_sneaking = bool(d.get("sneaking", false))
	if not dead:
		_set_state(State.FREE)


func save_summary() -> Dictionary:
	return {"name": display_name, "level": level, "region": GameState.current_region_id, "health": health, "max_health": max_health, "weapon": equipped.get("main_hand", "")}
