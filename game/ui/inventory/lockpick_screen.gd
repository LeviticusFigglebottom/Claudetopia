extends Control
## Picking a lock (DESIGN §5.13): a pin, a needle that sweeps across it, and a narrow band where it
## sets. Press {interact} (or a blow, or accept) as the needle crosses the band. The band is
## Stealth.lockpick_window wide, so Sneak widens it and a harder lock narrows it; a bad miss snaps
## the pick (Lockpicking). A set pin opens the thing: a chest is opened in the same breath, a door
## is left for you to walk through. Cancel leaves it locked.
##
## The lock is anything with `attempt(actor, timing_accuracy) -> {success, broke, ...}`, `locked`
## and `lock_level`: a DoorLock or a locked WorldContainer (EventBus.lockpick_requested, UI).

const SWEEP_HZ := 0.55
const BAR_W := 420.0
const BAR_H := 26.0

var lock: Object = null
var actor: Node = null
var _t := 0.0
var _needle := 0.5
var _window := 0.3
var _bar: Control = null
var _status: Label = null
var _done := false


func setup(args: Dictionary) -> void:
	lock = args.get("lock", null)
	actor = args.get("actor", null)
	if lock != null and is_instance_valid(lock):
		_window = Stealth.lockpick_window(Peers.skill_level("sneak"), int(lock.get("lock_level")))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# the UI adds a screen before it hands it its arguments (setup), so it is drawn after
	_build.call_deferred()


func _build() -> void:
	add_child(UiKit.dim(0.5))
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)
	var panel := UiKit.panel("FramedPanel")
	panel.custom_minimum_size = Vector2(BAR_W + 60.0, 0)
	centre.add_child(panel)
	var col := UiKit.column(12)
	panel.add_child(col)
	col.add_child(UiKit.label("Pick the Lock", "Title", HORIZONTAL_ALIGNMENT_CENTER))
	var level := int(lock.get("lock_level")) if lock != null and is_instance_valid(lock) else 0
	col.add_child(UiKit.label(Stealth.lock_level_name(level), "Small", HORIZONTAL_ALIGNMENT_CENTER))
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(BAR_W, BAR_H)
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bar.draw.connect(_draw_bar)
	col.add_child(_bar)
	_status = UiKit.wrapped(SocialContext.keys_in("Set the pin as the needle crosses the band {key:interact}. {key:pause} leaves it."), "Journal")
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_status)


func _process(delta: float) -> void:
	if _done:
		return
	if lock == null or not is_instance_valid(lock) or not bool(lock.get("locked")):
		_close()
		return
	_t += delta
	# a sweep that slows at the ends, as a hand does
	_needle = 0.5 + 0.5 * sin(_t * TAU * SWEEP_HZ)
	if _bar != null:
		_bar.queue_redraw()


func _draw_bar() -> void:
	var w := _bar.size.x
	var h := _bar.size.y
	_bar.draw_rect(Rect2(0, 0, w, h), Color(0.12, 0.1, 0.08, 0.9))
	var band := _window * 0.5 * w
	_bar.draw_rect(Rect2(w * 0.5 - band, 2, band * 2.0, h - 4), Color(0.78, 0.66, 0.36, 0.85))
	var x := _needle * w
	_bar.draw_rect(Rect2(x - 1.5, -4, 3, h + 8), Color(0.95, 0.93, 0.88))


## How far off the band's middle the needle stands: 0 in the middle, 1 at either end.
func miss() -> float:
	return absf(_needle - 0.5) * 2.0


func try_pin() -> Dictionary:
	if lock == null or not is_instance_valid(lock) or not lock.has_method("attempt"):
		return {}
	var r: Dictionary = lock.call("attempt", actor, miss())
	if bool(r.get("success", false)):
		_done = true
		_say("It gives.")
		var opened := lock
		var who := actor
		await get_tree().create_timer(0.35, true, false, true).timeout
		var shown := UI.is_menu_open("lockpick")
		_close()
		# a chest opens in the same breath; a door waits for you to walk through it
		if shown and opened is WorldContainer and is_instance_valid(opened):
			(opened as WorldContainer).interact(who)
	elif bool(r.get("broke", false)):
		_say("The pick snaps.")
		if not Lockpicking.has_pick(actor):
			_done = true
			await get_tree().create_timer(0.6, true, false, true).timeout
			_close()
	else:
		_say("It slips. Again.")
	return r


func _unhandled_input(event: InputEvent) -> void:
	if _done:
		return
	if event.is_action_pressed("interact") or event.is_action_pressed("attack_light") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		try_pin()


func _close() -> void:
	if UI.is_menu_open("lockpick"):
		UI.close("lockpick")


func _say(text: String) -> void:
	if _status != null:
		_status.text = text
