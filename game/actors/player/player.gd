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

## Gaits (DESIGN §5.2), ground speeds in m/s. A full stick or a key jogs; the walk key held, or a
## light stick, walks; sprint held runs flat out on stamina (DESIGN §5.3, 8/s). The first
## numbers were 4.2 and 6.5 with no walk at all, and the default was posed as a crouch.
const WALK_SPEED := 1.8
const JOG_SPEED := 5.0
const SPRINT_SPEED := 7.8
const SNEAK_SPEED := 1.5
## Locked on or blocking the body faces the target or the view, not the way it moves, and the
## legs have only walking strafes to show for it.
const STRAFE_SPEED := 2.6
const BLOCK_MOVE_MULT := 0.6
## Moving while a bow is drawn: what the first numbers gave it (half of 4.2), kept.
const AIM_MOVE_SPEED := 2.1
## Stick deflection at which a walk becomes a jog, and where the jog is reached.
const WALK_STICK := 0.55
const JOG_STICK := 0.9
## Speed changes, m/s². From rest to a jog in 0.31 s; a jog stops in 0.25 s over 0.63 m. Above a
## jog both are gentler: a sprint builds over 0.4 s more and takes 0.48 s and 2.1 m to stop.
const ACCEL := 16.0
const DECEL := 20.0
const SPRINT_ACCEL := 7.0
const SPRINT_DECEL := 12.0
const AIR_ACCEL := 8.0
## How fast the body turns toward where it is going (rad/s), by how fast it is going, and the
## rate at which the last few degrees ease in. A body turns on the spot faster than it can
## change course at a sprint.
const TURN_RATE_STILL := deg_to_rad(900.0)
const TURN_RATE_WALK := deg_to_rad(720.0)
const TURN_RATE_JOG := deg_to_rad(540.0)
const TURN_RATE_SPRINT := deg_to_rad(300.0)
const TURN_RATE_STRAFE := deg_to_rad(720.0)
const TURN_EASE := 16.0
## Full speed while the way you are going is within ALIGN_FULL of the way you face, none past
## ALIGN_NONE: a reversal plants and turns rather than moonwalking or swinging a wide arc.
const ALIGN_FULL := deg_to_rad(50.0)
const ALIGN_NONE := deg_to_rad(150.0)
## A sprint run to empty stops, and does not start again until this share of stamina is back.
const SPRINT_RESUME := 0.25
## A press of Sprint let go within this long is a tap, and a tap rolls (see _read_sprint_tap).
const SPRINT_TAP_S := 0.22
const JUMP_HEIGHT := 1.1
## Turn rate of the committed states (attacks, casting, the bow), which are not locomotion.
const TURN_SPEED := 14.0
const ATTACK_STEP_SPEED := 1.6
const MANTLE_MIN := 0.4
const MANTLE_MAX := 1.3
const MANTLE_TIME := 0.5
const BOW_MIN_DRAW := 0.3
const RIPOSTE_RANGE := 2.4
## How close you must be to a foe's back for the light to become a backstab.
const BACKSTAB_RANGE := 1.8
## Load is what is worn and wielded over 40 + 3·Endurance (the character's own Endurance). A bag
## carried past its capacity puts the roll in the overloaded band whatever is worn.
const LOAD_CAPACITY_BASE := 40.0
const LOAD_CAPACITY_PER_ENDURANCE := 3.0
const SAVE_SECTION := "player"
const SKILL_IDS: Array[String] = ["one_handed", "two_handed", "archery", "block", "armour", "sneak", "speech", "alchemy", "smithing", "enchanting", "athletics", "kindling", "hush", "binding", "mending", "calling"]
const ACTIONS: Array[String] = ["attack_light", "attack_heavy", "dodge", "jump", "cast", "interact", "block", "sprint", "walk", "sneak", "lock_on", "cycle_target", "toggle_camera", "toggle_lantern", "quick_1", "quick_2", "quick_3", "quick_4"]
const BUFFERABLE: Array[String] = ["attack_light", "attack_heavy", "dodge", "jump", "cast", "interact"]
const ARROW_SCENE := "res://systems/combat/arrow.tscn"

var state: int = State.FREE
var level: int = 1
var skills: Dictionary = {}
var equipped: Dictionary = {"main_hand": "", "off_hand": "", "body": ""}
var weapon: WeaponInstance = null
var offhand: Dictionary = {}
var quick_slots: Array = ["", "", "", ""]
## The belt's answer to a quick key: Callable(index: int, item_id: String) -> bool, true when the
## item was used. The paper doll owns the belt and is bound here (`Equipment.use_quick_index`);
## a saying on a quick key is readied by this node, because a saying is not an item.
var quick_slot_handler: Callable = Callable()
## Where arrows come from: Callable(ammo_tag: String, preferred: String, take: bool) -> String,
## the id of the arrow that would be (take false) or was (take true) drawn, or "" when there is
## none. The bag is bound here (`Inventory.ammo_for`). A body with no bag -- a bench, the crossbow
## test -- looses from the `arrows` counter instead.
var ammo_provider: Callable = Callable()
var equipped_spell: String = ""
## What this character looks like, as the Naming wrote it (see `_take_the_naming`).
var appearance: CharacterAppearance = CharacterAppearance.new()
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
## The crit this swing carries ("" or "sneak"), kept so a charged heavy is rebuilt with it.
var _attack_crit: String = ""
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
## Run to empty: no sprint until SPRINT_RESUME of the stamina has come back.
var _sprint_spent: bool = false
## When the Sprint key went down (the combat clock), or -1 while it is up.
var _sprint_down_at: float = -1.0
## Speed along the way the body faces while moving freely (locomotion's own state, so a shove or
## a dodge's velocity is never taken for running speed).
var _ground_speed: float = 0.0
var _free_tick: int = -2
## The heightfield held the body up last tick (open country has no collider under it).
var _terrain_held: bool = false
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
	_take_the_naming()
	add_to_group("player")
	SaveSystem.register(SAVE_SECTION, self)
	_register_character_sections()
	_follow_equipment()
	_follow_the_character()
	if not EventBus.item_used.is_connected(_on_item_used):
		EventBus.item_used.connect(_on_item_used)
	if DisplayServer.get_name() != "headless" and input_enabled:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	call_deferred("_announce")


func _announce() -> void:
	EventBus.player_spawned.emit(self)


# --- the Naming ----------------------------------------------------------------------------------

## What the Naming wrote down, made flesh. Nothing read those flags before: the body that stood in
## the world was the bare rig with the default head whatever had been chosen, the Calling's skills
## never landed and its signature item never reached the bag. The flags travel in the save, so a
## new game and a loaded one get the same body from them. The Calling is applied once, while the
## game is new, because from then on its skills and its bag are state of their own.
func _take_the_naming() -> void:
	var name := str(GameState.get_flag("player_name", ""))
	if not name.is_empty():
		display_name = name
	apply_appearance(_look_from_the_naming())
	if not GameState.has_flag("new_game"):
		return
	var calling := str(GameState.get_flag("player_calling", ""))
	var prog := get_node_or_null("Progression")
	if calling.is_empty() or prog == null or not prog.has_method("apply_calling"):
		return
	if str(prog.get("calling_id")) == calling:
		return
	prog.call("apply_calling", calling, get_node_or_null("Inventory") as Inventory)


## The record the Naming wrote, or, when nothing wrote one (a `--new-game` run, an old save), a
## Foundling dressed by the Calling's people rather than the naked rig.
func _look_from_the_naming() -> CharacterAppearance:
	var raw: Variant = GameState.get_flag("player_appearance", null)
	var written: Dictionary = raw if raw is Dictionary else {}
	var look := CharacterAppearance.new(written)
	if not written.has("parts"):
		look.set_part("head", "default")
		look.set_part("hair", "short")
		var calling := str(GameState.get_flag("player_calling", ""))
		look.dress_for_culture(CharacterAppearance.culture_of_calling(calling), abs(display_name.hash()))
	return look


## Puts a look on the body. The model is the forge's humanoid under the Model pivot, driven by
## the animation driver; a placeholder capsule has nothing to apply it to and is left alone.
func apply_appearance(look: Variant) -> void:
	appearance = look if look is CharacterAppearance else CharacterAppearance.new(look as Dictionary)
	var body := body_model()
	if body != null:
		body.call("apply_appearance", appearance)


## The humanoid model standing in for this character, or null while it is a placeholder.
func body_model() -> Node:
	if anim != null and anim.model != null and anim.model.has_method("apply_appearance"):
		return anim.model
	return null


func _exit_tree() -> void:
	if EventBus.item_used.is_connected(_on_item_used):
		EventBus.item_used.disconnect(_on_item_used)
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
		var pressed := input_enabled and InputMap.has_action(a) and Input.is_action_pressed(a)
		_just[a] = pressed and not bool(_prev.get(a, false))
		_prev[a] = pressed
		_held[a] = pressed
	_move_input = Input.get_vector("move_left", "move_right", "move_forward", "move_back") if input_enabled else Vector2.ZERO
	_look_stick = Input.get_vector("look_left", "look_right", "look_up", "look_down") if input_enabled else Vector2.ZERO
	for a in BUFFERABLE:
		if _just[a]:
			_buffer_action = a
			_buffer_at = now()
	_read_sprint_tap()


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
		_terrain_held = snap_to_terrain()
		# Sneaking is felt through the boots as much as it is seen: a quieter step, and a
		# sprint's a louder one.
		step_sounds(delta, -8.0 if is_sneaking else (2.0 if is_sprinting else 0.0))
	# A raised guard halves regen, and so does a load (DESIGN §5.7): read every frame, because
	# a guard dropped by an attack or a roll must not leave regen halved behind it.
	stamina_comp.regen_multiplier = (0.5 if is_blocking else 1.0) * DamageModel.load_regen_mult(load_ratio)
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
				var bs := _backstab_candidate()
				if bs != null:
					_start_riposte(bs, "backstab")
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
	if is_blocking and not anim.is_busy() and not anim.is_playing("Block_Idle") and not anim.is_playing("Parry"):
		anim.play_intent("Block_Idle")
	elif not is_blocking and anim.is_playing("Block_Idle"):
		anim.stop()


func can_parry_with_equipment() -> bool:
	if bool(_offhand_guard().get("parry", false)):
		return true
	return weapon != null and weapon.can_parry


func block_stability_value() -> float:
	var guard := _offhand_guard()
	if not guard.is_empty() and not weapon.is_two_handed():
		return clampf(float(guard.get("stability", 0.0)), 0.0, 1.0)
	return weapon.stability if weapon != null else 0.0


## What the off hand guards with: a shield worn as armour says it in its `armour` block, and a
## shield carried as a weapon (the clan shield, the oak round shield) in its `weapon` block. Only
## the first was read, so a clan shield raised let every point of a blow through, cost the full
## 0.6 of it in stamina, and could never parry.
func _offhand_guard() -> Dictionary:
	if offhand.is_empty():
		return {}
	var worn: Dictionary = offhand.get("armour", {})
	if not worn.is_empty():
		return worn
	var carried: Dictionary = offhand.get("weapon", {})
	if str(carried.get("class", "")) == "shield":
		return carried
	return {}


## Where the stick or the keys point, on the ground, in the world. `camera_rig.yaw` is the view's
## world yaw (CameraRig), so W is the view's forward, S away from it, A and D its left and right.
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
	if not bool(_held["sprint"]):
		return false
	# a press that may yet be a tap is not a sprint: a roll must not start with a lurch forward
	return _sprint_down_at < 0.0 or now() - _sprint_down_at >= SPRINT_TAP_S


## A tap of Sprint rolls; a hold sprints. The genre's players reach for the run key to roll (the
## Souls games taught most of them), and it leaves Space to jump. The roll goes through the same
## buffer as the Dodge key, so it cancels an attack's recovery and waits out a busy moment the same
## way. Keyboard only: on a pad, B rolls and the stick click is a sprint and nothing else. Off
## with its setting, and while Sprint is a toggle, where a tap is the toggle.
func _read_sprint_tap() -> void:
	if not (input_enabled and sprint_taps_roll_setting()):
		_sprint_down_at = -1.0
		return
	if _just["sprint"]:
		_sprint_down_at = now() if _sprint_key_down() else -1.0
	elif not bool(_held["sprint"]) and _sprint_down_at >= 0.0:
		if now() - _sprint_down_at < SPRINT_TAP_S:
			_buffer_action = "dodge"
			_buffer_at = now()
		_sprint_down_at = -1.0


## Whether a tap of Sprint rolls, as the settings stand.
static func sprint_taps_roll_setting() -> bool:
	return bool(Settings.get_value("controls", "sprint_tap_rolls", true)) \
			and not bool(Settings.get_value("controls", "toggle_sprint", false))


## Whether Sprint is held on the keyboard (rather than on a pad).
func _sprint_key_down() -> bool:
	for ev in InputMap.action_get_events("sprint"):
		var key := ev as InputEventKey
		if key == null:
			continue
		if key.physical_keycode != KEY_NONE and Input.is_physical_key_pressed(key.physical_keycode):
			return true
		if key.keycode != KEY_NONE and Input.is_key_pressed(key.keycode):
			return true
	return false


# --- locomotion (DESIGN §5.2) -------------------------------------------------------------------

func _move(delta: float) -> void:
	var wish := _wish_direction()
	var moving := wish.length() > 0.1
	_update_sprint(moving, delta)
	var speed := _target_speed() if moving else 0.0
	if not _on_ground():
		_air_move(wish, speed, delta)
	elif _strafe_mode():
		_strafe_move(wish, speed, delta)
	else:
		_free_move(wish, speed, delta)


## Standing on something: a collider, or the heightfield that `snap_to_terrain` held us to.
func _on_ground() -> bool:
	return is_on_floor() or _terrain_held


## The ground speed a stick deflection (0..1) asks for, before sprint, sneak, stance and status:
## a light stick walks, a full one jogs, the walk key caps it at a walk.
static func gait_speed(stick: float, walk_held: bool) -> float:
	var m := clampf(stick, 0.0, 1.0)
	if m < 0.1:
		return 0.0
	var walk := WALK_SPEED * minf(m / WALK_STICK, 1.0)
	if walk_held or m <= WALK_STICK:
		return walk
	return lerpf(WALK_SPEED, JOG_SPEED, clampf((m - WALK_STICK) / (JOG_STICK - WALK_STICK), 0.0, 1.0))


func _target_speed() -> float:
	var speed := SPRINT_SPEED if is_sprinting else gait_speed(_move_input.length(), bool(_held.get("walk", false)))
	if is_sneaking:
		speed = minf(speed, SNEAK_SPEED)
	if _strafe_mode() and not camera_rig.first_person:
		speed = minf(speed, STRAFE_SPEED)
	if is_blocking:
		speed *= BLOCK_MOVE_MULT
	return speed * speed_multiplier()


## Locked on (and not sprinting), blocking, or looking out of the body's own eyes: the body faces
## the target or the view and steps whichever way it is pushed. Sprinting breaks a lock's strafe.
func _strafe_mode() -> bool:
	return camera_rig.first_person or is_blocking or (lock.is_locked() and not is_sprinting)


## Sprint runs on stamina (DESIGN §5.3). Run to empty, it stops, and it does not start again
## until SPRINT_RESUME of the pool is back: otherwise it stutters on and off with every regen tick.
func _update_sprint(moving: bool, delta: float) -> void:
	var wanted := _sprint_wanted()
	if _sprint_spent and stamina_comp.current >= stamina_comp.maximum * SPRINT_RESUME:
		_sprint_spent = false
	is_sprinting = wanted and moving and not is_blocking and _on_ground() and not _sprint_spent \
			and stamina_comp.current > 0.0
	if not is_sprinting:
		return
	is_sneaking = false
	if not stamina_comp.drain(DamageModel.STAMINA_SPRINT_PER_S, delta):
		_sprint_spent = true
		is_sprinting = false
		return
	if _noise_timer <= 0.0:
		_emit_noise(0.6)
		_noise_timer = 0.4


## Moving freely: the body turns toward where the stick points, at a rate that falls as it goes
## faster, and it goes the way it faces. With much of a turn still to make it gives up speed to
## make it, so a reversal is a plant and a turn rather than a moonwalk or a wide arc.
func _free_move(wish: Vector3, target_speed: float, delta: float) -> void:
	var tick := Engine.get_physics_frames()
	if _free_tick != tick - 1:
		# back from a roll, a swing, the air or a strafe: carry the speed actually being made
		_ground_speed = maxf(Vector3(velocity.x, 0.0, velocity.z).dot(forward()), 0.0)
	else:
		# into a wall you stop running, rather than keep the speed you were asking for
		var real := get_real_velocity()
		var made := Vector2(real.x, real.z).length()
		if _ground_speed > made + 0.75:
			_ground_speed = made
	_free_tick = tick
	var want := 0.0
	if wish.length() > 0.1:
		var want_yaw := atan2(-wish.x, -wish.z)
		rotation.y = turn_toward(rotation.y, want_yaw, turn_rate_for(_ground_speed), delta)
		want = target_speed * alignment(absf(wrapf(want_yaw - rotation.y, -PI, PI)))
	_ground_speed = approach_speed(_ground_speed, want, delta)
	velocity.x = -sin(rotation.y) * _ground_speed
	velocity.z = -cos(rotation.y) * _ground_speed


## Facing the target or the view, stepping any way: the velocity itself eases toward the push.
func _strafe_move(wish: Vector3, target_speed: float, delta: float) -> void:
	var face := yaw_to(lock.target_point()) if lock.is_locked() and not camera_rig.first_person else camera_rig.yaw
	rotation.y = turn_toward(rotation.y, face, TURN_RATE_STRAFE, delta)
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var goal := wish * target_speed
	horizontal = horizontal.move_toward(goal, (ACCEL if goal.length() > horizontal.length() else DECEL) * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	_free_tick = -2


func _air_move(wish: Vector3, target_speed: float, delta: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	if wish.length() > 0.1:
		horizontal = horizontal.move_toward(wish * maxf(target_speed, horizontal.length()), AIR_ACCEL * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if _strafe_mode():
		var face := yaw_to(lock.target_point()) if lock.is_locked() and not camera_rig.first_person else camera_rig.yaw
		rotation.y = turn_toward(rotation.y, face, TURN_RATE_STRAFE, delta)
	elif horizontal.length() > 0.5:
		rotation.y = turn_toward(rotation.y, atan2(-horizontal.x, -horizontal.z), TURN_RATE_SPRINT, delta)
	_free_tick = -2


## One tick of turning `yaw` toward `want`: at most `rate` rad/s, and easing into the last few
## degrees instead of stopping dead on them.
static func turn_toward(yaw: float, want: float, rate: float, delta: float) -> float:
	var diff := wrapf(want - yaw, -PI, PI)
	var step := diff * (1.0 - exp(-TURN_EASE * delta))
	var cap := rate * delta
	return wrapf(yaw + clampf(step, -cap, cap), -PI, PI)


## How fast the body can turn at a ground speed: quickest standing, slowest at a sprint.
static func turn_rate_for(speed: float) -> float:
	if speed <= WALK_SPEED:
		return lerpf(TURN_RATE_STILL, TURN_RATE_WALK, speed / WALK_SPEED)
	if speed <= JOG_SPEED:
		return lerpf(TURN_RATE_WALK, TURN_RATE_JOG, (speed - WALK_SPEED) / (JOG_SPEED - WALK_SPEED))
	return lerpf(TURN_RATE_JOG, TURN_RATE_SPRINT, clampf((speed - JOG_SPEED) / (SPRINT_SPEED - JOG_SPEED), 0.0, 1.0))


## The share of the asked-for speed allowed with `off` radians of turn still to make.
static func alignment(off: float) -> float:
	return 1.0 - smoothstep(ALIGN_FULL, ALIGN_NONE, off)


## One tick of speed change: brisk up to a jog, gentler above it, both ways.
static func approach_speed(speed: float, want: float, delta: float) -> float:
	if want > speed:
		return minf(speed + (ACCEL if speed < JOG_SPEED else SPRINT_ACCEL) * delta, want)
	return maxf(speed - (DECEL if speed <= JOG_SPEED else SPRINT_DECEL) * delta, want)


func _damp_horizontal(delta: float, rate: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).move_toward(Vector3.ZERO, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


func _update_locomotion_anim(_delta: float) -> void:
	# the ground velocity the body really made, in its own frame, m/s: the model plays the gait
	# at the rate that keeps its feet planted under exactly that
	var v := get_real_velocity()
	var local := global_transform.basis.inverse() * Vector3(v.x, 0.0, v.z)
	anim.set_locomotion(Vector2(local.x, -local.z), is_sneaking)
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
	_attack_crit = _sneak_crit()
	var timing := weapon.timing_for(kind, index)
	weapon.begin_attack(weapon.build_hit(kind, index, 0.0, get_skill(weapon.skill_id), _attack_crit))
	# "Hyper-armour frames on heavies" (DESIGN §5.3): from the wind-up to the end of the swing, a
	# small hit does not take the swinger's footing. Only the brute's heavies ever had it.
	if kind == "heavy":
		poise_comp.set_hyper_armour(DamageModel.HEAVY_HYPER_ARMOUR)
	else:
		poise_comp.clear_hyper_armour()
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
	weapon.begin_attack(weapon.build_hit("heavy", 0, _charge_ratio, get_skill(weapon.skill_id), _attack_crit))


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
				poise_comp.clear_hyper_armour()
		"cancel_ok":
			_chain_open = true


func _on_clip_finished(clip: String) -> void:
	match state:
		State.ATTACK:
			if clip == _attack_clip:
				weapon.end_attack()
				poise_comp.clear_hyper_armour()
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


## A foe with its back to you, within arm's reach and in front of you: the light becomes a
## backstab. DESIGN §5.3 lists it beside the riposte as a crit, `DamageModel.is_behind` was written
## for it, and nothing ever made one. A boss is too aware of its own back to be taken this way.
func _backstab_candidate() -> Actor:
	var pool: Array = [lock.target] if lock.is_locked() else get_tree().get_nodes_in_group("enemy")
	var best: Actor = null
	var best_d := BACKSTAB_RANGE
	for n in pool:
		if not (n is Enemy) or not is_hostile_to(n):
			continue
		var e := n as Enemy
		if e.is_dead() or e.is_boss or e.is_stunned():
			continue
		var to := e.global_position - global_position
		var d := Vector3(to.x, 0.0, to.z).length()
		if d > best_d or not DamageModel.is_facing(forward(), to, 0.5):
			continue
		if not DamageModel.is_behind(e.forward(), -to):
			continue
		best = e
		best_d = d
	return best


## A blow from somebody the victim never noticed is a sneak attack (DESIGN §5.3): the victim is
## what the swing is about to meet -- the locked target, or the nearest foe in front within reach.
func _sneak_crit() -> String:
	if not is_sneaking:
		return ""
	var victim: Node = lock.target if lock.is_locked() else _foe_in_reach()
	if victim is Enemy and (victim as Enemy).is_unaware():
		return "sneak"
	return ""


func _foe_in_reach() -> Node:
	var best: Node = null
	var best_d := (weapon.reach if weapon != null else 1.0) + 0.6
	for n in get_tree().get_nodes_in_group("enemy"):
		if not (n is Actor) or (n as Actor).is_dead() or not is_hostile_to(n):
			continue
		var to := (n as Node3D).global_position - global_position
		var d := Vector3(to.x, 0.0, to.z).length()
		if d <= best_d and DamageModel.is_facing(forward(), to, 0.5):
			best = n
			best_d = d
	return best


## A riposte at a foe a parry opened, or (`kind` "backstab") a blow into one's back: both are the
## same committed move, a crit that cannot be blocked, parried or rolled out of.
func _start_riposte(target: Actor, kind := "riposte") -> void:
	_riposte_target = target
	snap_facing(target.global_position - global_position)
	target.stunned_until = maxf(target.stunned_until, now() + 1.4)
	_attack_kind = kind
	_attack_index = 0
	_attack_phase = "windup"
	_attack_crit = kind
	weapon.begin_attack(weapon.build_hit(kind, 0, 0.0, get_skill(weapon.skill_id), kind))
	anim.play_intent("Riposte" if kind == "riposte" else "Backstab", weapon.timing_for(kind))
	_set_state(State.RIPOSTE)
	attack_started.emit(kind, 0)


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
	poise_comp.clear_hyper_armour()
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
	Foley.play_ui("player_death")
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
	revive()
	collision_layer = LAYER_PLAYER
	_buffer_action = ""
	_set_state(State.FREE)
	set_input_enabled(true)
	teleport(position, yaw)


## CONTRACTS §8: puts the body somewhere at once (a door, a Hearthstone, a load, the console),
## facing `yaw`, with the view behind it looking the same way. Nothing is carried across the
## jump: not the speed, not the camera's follow, not an interpolation smear from where it was.
func teleport(position: Vector3, yaw: float) -> void:
	global_position = position
	rotation.y = yaw
	velocity = Vector3.ZERO
	_ground_speed = 0.0
	_free_tick = -2
	camera_rig.yaw = yaw
	reset_physics_interpolation()
	camera_rig.snap_to_target()


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
	if _draw_ammo(false).is_empty():
		EventBus.notify.emit("No arrows.", "warning")
		return false
	if now() < _reload_until:
		EventBus.notify.emit("Still winding.", "warning")
		return false
	_bow_draw_start = now()
	var draw_time := float(weapon.ranged.get("draw_time", 0.7))
	anim.play_intent("Bow_Draw", {"length": draw_time})
	Foley.play("bow_draw", attack_origin.global_position)
	camera_rig.set_aiming(true)
	_set_state(State.BOW)
	return true


func _tick_bow(delta: float) -> void:
	if is_stunned():
		_enter_stunned()
		return
	rotation.y = lerp_angle(rotation.y, camera_rig.yaw, clampf(TURN_SPEED * delta, 0.0, 1.0))
	var wish := _wish_direction() * AIM_MOVE_SPEED
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


## The arrow this bow would loose: the kind it names if the quiver has it, else any of its tag.
## `take` spends it. Returns the item id, or "" for an empty quiver.
func _draw_ammo(take: bool) -> String:
	var tag := str(weapon.ranged.get("ammo_tag", "bolt" if weapon.weapon_class == "crossbow" else "arrow"))
	var preferred := str(weapon.ranged.get("ammo_item", ""))
	if ammo_provider.is_valid():
		return str(ammo_provider.call(tag, preferred, take))
	if arrows <= 0:
		return ""
	if take:
		arrows -= 1
	return preferred if not preferred.is_empty() else "core:item/arrow"


func _fire_arrow(drawn: float) -> void:
	var shot := _draw_ammo(true)
	if shot.is_empty():
		EventBus.notify.emit("No arrows.", "warning")
		return
	stamina_comp.spend(weapon.stamina_cost("light"))
	# What flies is what came out of the quiver, so its head is the one that hits.
	var arrow_def := ContentDB.get_or_empty(shot)
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
	arrow.impact_sound = "arrow_hit"
	Foley.play("bow_release", attack_origin.global_position)
	Foley.play("arrow_whoosh", attack_origin.global_position)
	# A method reference, not a closure: an arrow outlives the bow that loosed it, and a
	# closure on it is not disconnected when the archer is freed.
	arrow.struck.connect(_on_arrow_struck)
	var reload := float(weapon.ranged.get("reload_time", 0.0))
	if reload > 0.0:
		_reload_until = now() + reload
	_emit_noise(0.3)


func _on_arrow_struck(_victim: Node, hit: HitData, outcome: String) -> void:
	if outcome == "hit" or outcome == "blocked":
		EventBus.skill_used.emit(hit.skill_id, 3.0)


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

## The character's skill, which is the one use raises and a Calling's bonus lands on: Progression's,
## with its fortify effects. This used to read a `skills` table of its own on this node, all tens,
## that nothing but a save ever wrote -- so a swing hit as hard on the first day as on the
## hundredth, and a Hearthkeeper's One-Handed +10 never reached a blade. The table is kept for a
## body with no Progression (a bench, an old save being read).
func get_skill(skill_id: String) -> float:
	var prog := get_node_or_null(NodePath("Progression"))
	if prog != null and prog.has_method("effective_skill"):
		return float(prog.call("effective_skill", skill_id))
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
	equipped["body"] = item_id
	_refresh_armour()
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


## Eating or drinking something: the bag says what was used and the body does it. Nothing
## applied these before, so every potion in the game was coloured water.
func _on_item_used(item_id: String, effects: Array = []) -> void:
	if effects.is_empty():
		return
	take_effects(effects)
	var name := str(ContentDB.get_or_empty(item_id).get("name", "It"))
	EventBus.notify.emit("%s takes hold." % name, "item")


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


## Load, which lengthens the roll and slows regen (DESIGN §5.3, §5.7): everything worn and wielded
## over 40 + 3·Endurance, and past 100% whenever the bag carries more than the character can. It
## used to count only the hands and the coat, so a helm, gauntlets and sabatons weighed nothing,
## and it never looked at the bag, whose `is_overloaded()` says in its own comment that it is "for
## the movement code to read" and was read by nothing.
func _recompute_load() -> void:
	var capacity := LOAD_CAPACITY_BASE + LOAD_CAPACITY_PER_ENDURANCE * float(endurance)
	load_ratio = _worn_weight() / capacity if capacity > 0.0 else 0.0
	var bag := get_node_or_null(NodePath("Inventory"))
	if bag != null and bag.has_method("is_overloaded") and bool(bag.call("is_overloaded")):
		load_ratio = maxf(load_ratio, float(bag.call("load_fraction")))


## Everything worn and wielded. The doll is the record when there is one; a hand or a coat put on
## straight through equip_* (the arena, a bench) is counted once as well.
func _worn_weight() -> float:
	var total := 0.0
	var doll := _doll()
	var on_doll := {}
	if doll != null and doll.has_method("equipped_weight"):
		total = float(doll.call("equipped_weight"))
		for slot in equipped:
			on_doll[slot] = str(doll.call("item_id", slot))
	for slot in equipped:
		var id: String = equipped[slot]
		if not id.is_empty() and id != str(on_doll.get(slot, "")):
			total += float(ContentDB.get_or_empty(id).get("weight", 0.0))
	return total


## Armour is everything worn (DESIGN §5.3's `armour_flat`), temper included. It used to be the coat
## alone: a helm, gloves and boots were worn, drawn, saved and weighed, and stopped nothing.
func _refresh_armour() -> void:
	var total := 0.0
	var doll_body := ""
	var doll := _doll()
	if doll != null and doll.has_method("armour_total"):
		total = float(doll.call("armour_total"))
		doll_body = str(doll.call("item_id", "body"))
	var body := str(equipped.get("body", ""))
	if not body.is_empty() and body != doll_body:
		total += float(ContentDB.get_or_empty(body).get("armour", {}).get("armour", 0.0))
	armour_flat = total
	# Struck in heavy mail you ring; in cloth and leather you are hit (Foley.material_for).
	var heavy := doll != null and doll.has_method("weight_class") and str(doll.call("weight_class")) == "heavy"
	body_material = "metal" if heavy or armour_flat >= 11.0 else "flesh"


## The belt lives on the equipment doll: `Equipment` binds it, persists it, and the HUD draws
## what it holds. This node kept a second `quick_slots` array of its own, and the keys read
## *that* one — which nothing ever filled — so four slots were drawn on screen, saved to disk
## and could not be loaded or fired from either end. The array stays for the arena and for a
## saying, which is not an item and has no place on the doll; the doll is asked first.
func _doll() -> Node:
	return get_node_or_null(NodePath("Equipment"))


## True when the slot now holds what was asked for. The inventory screen goes through here
## rather than reaching for the doll itself: writing the belt behind the player's back left
## `to_save` recording an empty belt beside an `Equipment` that had one, which is two answers
## to the same question and only one of them true.
func set_quick_slot(index: int, item_id: String) -> bool:
	if index < 0 or index >= quick_slots.size():
		return false
	var eq := _doll()
	var slot := "quick_%d" % (index + 1)
	if item_id.is_empty():
		quick_slots[index] = ""
		if eq != null:
			eq.call("clear_quick", slot)
		return true
	# A saying is not an item and has no place on the doll, so it lives on this array alone.
	if Ids.type_of(item_id) == "spell":
		quick_slots[index] = item_id
		return true
	if eq != null and not bool(eq.call("bind_quick", slot, item_id)):
		return false
	quick_slots[index] = item_id
	return true


func use_quick_slot(index: int) -> void:
	if index < 0 or index >= quick_slots.size():
		return
	var eq := _doll()
	var slot := "quick_%d" % (index + 1)
	var id: String = str(eq.call("quick_item", slot)) if eq != null else ""
	if id.is_empty():
		id = quick_slots[index]
	quick_slot_used.emit(index, id)
	if id.is_empty():
		return
	if Ids.type_of(id) == "spell":
		if equip_spell(id):
			EventBus.notify.emit("Readied %s." % ContentDB.get_or_empty(id).get("name", id), "info")
		return
	if not quick_slot_handler.is_valid() or not bool(quick_slot_handler.call(index, id)):
		EventBus.notify.emit("None left.", "info")


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
	if eq.has_method("use_quick_index"):
		quick_slot_handler = Callable(eq, "use_quick_index")
	for slot in ["main_hand", "off_hand", "body"]:
		_on_equipment_changed(slot)


## The body's pools and skills are the character's, and the character lives on Progression; its
## load lives on the doll and in the bag. This listens to all three, and fills the pools once, as
## a body that has just stood up.
func _follow_the_character() -> void:
	var prog := get_node_or_null(NodePath("Progression"))
	if prog != null:
		if prog.has_signal("points_changed") and not prog.points_changed.is_connected(_on_points_changed):
			prog.points_changed.connect(_on_points_changed)
		if prog.has_signal("modifiers_changed") and not prog.modifiers_changed.is_connected(_on_modifiers_changed):
			prog.modifiers_changed.connect(_on_modifiers_changed)
		if prog.has_signal("level_changed") and not prog.level_changed.is_connected(_on_level_changed):
			prog.level_changed.connect(_on_level_changed)
	var bag := get_node_or_null(NodePath("Inventory"))
	if bag != null and bag.has_signal("changed") and not bag.changed.is_connected(_recompute_load):
		bag.changed.connect(_recompute_load)
	if bag != null and bag.has_method("ammo_for"):
		ammo_provider = Callable(bag, "ammo_for")
	if not status.renown_tick.is_connected(_on_renown_tick):
		status.renown_tick.connect(_on_renown_tick)
	_refresh_pools(true)


func _on_points_changed(_attribute_points: int, _perk_points: int) -> void:
	_refresh_pools(false)


func _on_modifiers_changed() -> void:
	_refresh_pools(false)


func _on_level_changed(_new_level: int) -> void:
	_refresh_pools(false)


## Health, stamina and mana from the character's Vigour, Endurance and Will (DESIGN §5.3, §5.6),
## through Progression so a fortify effect counts. This node used to keep its own three
## attributes at 10 while Progression kept the character's, and a level's point spent on
## Endurance raised a number the stamina bar never read. `fill` is for a body standing up; a
## level-up grows the pool and leaves what is in it.
func _refresh_pools(fill := false) -> void:
	var prog := get_node_or_null(NodePath("Progression"))
	if prog != null and prog.has_method("attribute_with_mods") and prog.has_method("max_stamina"):
		vigour = int(prog.call("attribute_with_mods", "vigour"))
		endurance = int(prog.call("attribute_with_mods", "endurance"))
		will = int(prog.call("attribute_with_mods", "will"))
		level = int(prog.get("level"))
		max_health = float(prog.call("max_health"))
		stamina_comp.setup(float(prog.call("max_stamina")), fill)
		caster.mana_max = float(prog.call("max_mana"))
	else:
		max_health = DamageModel.hp_max(vigour)
		stamina_comp.setup(DamageModel.stamina_max(endurance), fill)
		caster.mana_max = DamageModel.mana_max(will)
	if fill:
		health = max_health
		caster.refill()
	else:
		health = minf(health, max_health)
		caster.restore_mana(0.0)
	_recompute_load()
	stats_changed.emit()


## Quieted drains renown (DESIGN §5.3). StatusEffects has always ticked it, and nothing listened,
## so a Cinderlea shade's quieting touch did nothing at all.
func _on_renown_tick(amount: float) -> void:
	if not is_inside_tree():
		return
	var standing := get_tree().get_first_node_in_group("standing")
	if standing != null and standing.has_method("add_renown"):
		standing.call("add_renown", -int(round(amount)), "quieted")


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
		_:
			# A helm, gloves, boots, a ring: no hand to put them in, but armour and weight.
			_refresh_armour()
			_recompute_load()


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
	# a load is a teleport: the body is somewhere else now, facing its saved way
	teleport(global_position, rotation.y)
	is_sneaking = bool(d.get("sneaking", false))
	if not dead:
		_set_state(State.FREE)
	# The look lives in GameState's flags, which come back in the same pass as this section
	# but not necessarily before it, so the body is dressed once the whole save is in.
	call_deferred("_dress_from_the_save")


func _dress_from_the_save() -> void:
	if is_inside_tree():
		apply_appearance(_look_from_the_naming())


func save_summary() -> Dictionary:
	return {"name": display_name, "level": level, "region": GameState.current_region_id, "health": health, "max_health": max_health, "weapon": equipped.get("main_hand", "")}
