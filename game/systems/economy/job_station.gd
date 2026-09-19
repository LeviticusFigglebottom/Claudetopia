class_name JobStation
extends StaticBody3D
## A chopping block, forge bellows, mash tun, eel trap or peat bank. Interacting starts a
## timed shift: `started` fires with the clip the animation stream should play, and after
## `Jobs.station_seconds(kind)` the worker is paid marks and skill XP. One shift per station
## per cooldown, so the player cannot farm it; the station remembers when it was last worked.

signal started(kind: String, seconds: float, clip: String)
signal finished(kind: String, pay: int)

@export_enum("chop", "smith", "brew", "fish", "dig") var kind := "chop"
@export var display_name := ""
@export var owner_faction := ""
@export var owner_npc := ""
@export var gives_yield := true

var working := false
var last_worked_hours := -1000.0
var _rng := RandomNumberGenerator.new()
var _timer: SceneTreeTimer = null


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("job_station")
	_rng.randomize()
	if not owner_faction.is_empty() or not owner_npc.is_empty():
		Ownership.tag(self, owner_faction, owner_npc)
	if get_node_or_null("CollisionShape3D") == null:
		var col := CollisionShape3D.new()
		col.name = "CollisionShape3D"
		var box := BoxShape3D.new()
		box.size = Vector3(1.0, 1.0, 1.0)
		col.shape = box
		col.position.y = 0.5
		add_child(col)


func label() -> String:
	if not display_name.is_empty():
		return display_name
	return str(Jobs.STATIONS.get(kind, {}).get("label", "Work"))


func cooldown_hours() -> float:
	return float(Jobs.STATIONS.get(kind, {}).get("cooldown_hours", 4.0))


func hours_remaining() -> float:
	return maxf(0.0, last_worked_hours + cooldown_hours() - Merchant.now_hours())


func is_ready() -> bool:
	return not working and hours_remaining() <= 0.0


func prompt_text() -> String:
	if working:
		return "%s (working)" % label()
	var left := hours_remaining()
	if left > 0.0:
		return "%s (rest first)" % label()
	return label()


## Begins a shift. Returns false when the station is busy, resting, or owned by someone else.
func interact(actor: Node) -> bool:
	if working:
		return false
	if hours_remaining() > 0.0:
		EventBus.notify.emit("There is no more of that to do today.", "info")
		return false
	if Ownership.is_owned_by_other(self):
		EventBus.notify.emit("That is not your work to do.", "info")
		return false
	working = true
	var seconds := Jobs.station_seconds(kind)
	started.emit(kind, seconds, Jobs.station_clip(kind))
	if is_inside_tree() and seconds > 0.0:
		_timer = get_tree().create_timer(seconds)
		_timer.timeout.connect(_on_shift_done.bind(actor), CONNECT_ONE_SHOT)
	else:
		_on_shift_done(actor)
	return true


func _on_shift_done(actor: Node) -> void:
	finish(actor)


## Pays for the shift now (also called by the animation stream when the clip ends).
func finish(actor: Node = null) -> int:
	if not working:
		return 0
	working = false
	last_worked_hours = Merchant.now_hours()
	var skill := Jobs.station_skill(kind)
	var pay := Jobs.station_pay(kind, Peers.skill_level(skill), _rng)
	Purse.give(actor if actor != null else Peers.player(), pay)
	EventBus.skill_used.emit(skill, Jobs.station_xp(kind))
	if gives_yield:
		var item := str(Jobs.STATIONS.get(kind, {}).get("yield", ""))
		if not item.is_empty() and ContentDB.has(item):
			Peers.give_item(actor, item, 1)
	GameState.inc("jobs_done")
	GameState.inc("station_shifts_" + kind)
	EventBus.job_completed.emit("station:" + kind, pay)
	EventBus.notify.emit("%s: %d marks." % [label(), pay], "job")
	finished.emit(kind, pay)
	return pay


func cancel() -> void:
	working = false
