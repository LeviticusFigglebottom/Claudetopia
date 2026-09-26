class_name StairDescent
extends Node3D
## The descent (DESIGN §5.1a): while the Naming waits at `down_the_stair`, every step down the
## Hushline Stair takes a little of the colour and the sound out of the world, to none by the
## fortieth, and the fortieth step plays the wake (`GameServices.begin_wake`). A player who turns
## back and climbs to the top again has the colour back, and the Warden says "Good."
##
## The Stair Head's dressing stands one of these on the stair it lays (PoiBuilders), with the stair's
## line and the distance along it of every step it laid: the fortieth is the fortieth tread the
## player can see, whichever way the world drew the stair.

const QUEST := "core:quest/the_naming"
const STAGE := "down_the_stair"
const STEPS := 40
## How far off the stair's line a body may be and still be on it (the stair and its landings).
const ON_STAIR_M := 7.0
## Back at the top: within this much of the stair's head, having been this far down.
const TOP_M := 1.5
const TURNED_BACK_AFTER := 0.12
## How much quieter the world is at the fortieth step, in dB, on each bus that carries it.
const QUIET_DB := 36.0
const DRAINED_BUSES := ["Music", "SFX", "Ambience"]
const POLL_S := 0.1
const GROUP := "stair_descent"

## The stair's line, head first, in world space on the ground.
var path: PackedVector3Array = PackedVector3Array()
## How far along `path` each step is, in order down the stair.
var step_at: PackedFloat32Array = PackedFloat32Array()
## How far down the descent is: 0 at the head, 1 at the fortieth step.
var progress := 0.0
var deepest := 0.0
var triggered := false

var _look := PollTimer.new(POLL_S)
static var _bus_base: Dictionary = {}     # bus name -> its volume before the drain


func _ready() -> void:
	add_to_group(GROUP)
	# the colour and the sound are the world's own: put back whatever a descent took with it
	tree_exiting.connect(func() -> void:
			if progress > 0.0 and not triggered:
				restore())


## The distance along the stair at which its fortieth step lies.
func trigger_m() -> float:
	if step_at.is_empty():
		return 0.0
	return step_at[mini(STEPS, step_at.size()) - 1]


## How many steps down a point is, fractional: 0 at the head, `STEPS` at the fortieth step; -1 when it
## is not on the stair at all.
func steps_down(at: Vector3) -> float:
	var along := along_of(at)
	if along < 0.0:
		return -1.0
	if step_at.is_empty():
		return 0.0
	# the steps passed, and the share of the next one
	var n := 0
	while n < step_at.size() and step_at[n] <= along:
		n += 1
	if n >= step_at.size():
		return float(n)
	var from := step_at[n - 1] if n > 0 else 0.0
	var share := clampf((along - from) / maxf(step_at[n] - from, 0.01), 0.0, 1.0)
	return float(n) + share


## How far along the stair's line the nearest point to `at` is, or -1 when `at` is off it.
func along_of(at: Vector3) -> float:
	if path.size() < 2:
		return -1.0
	var best := INF
	var best_along := -1.0
	var run := 0.0
	for i in range(path.size() - 1):
		var a := path[i]
		var b := path[i + 1]
		var seg := b - a
		var length := seg.length()
		if length < 0.01:
			continue
		var t := clampf((at - a).dot(seg) / (length * length), 0.0, 1.0)
		var q := a + seg * t
		var d := q.distance_to(at)
		if d < best:
			best = d
			best_along = run + length * t
		run += length
	return best_along if best <= ON_STAIR_M else -1.0


func _process(delta: float) -> void:
	if triggered or not _look.due(delta):
		return
	if not waiting():
		if progress > 0.0:
			_set_progress(0.0)
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var steps := steps_down(player.global_position)
	var t := clampf(steps / float(STEPS), 0.0, 1.0) if steps >= 0.0 else 0.0
	if steps < 0.0 and progress > 0.5:
		# off the line far down (a landing, a stumble to the side): the grey stays where it was
		t = progress
	_set_progress(t)
	deepest = maxf(deepest, t)
	if t >= 1.0:
		_trigger()
		return
	if deepest >= TURNED_BACK_AFTER and steps >= 0.0 and along_of(player.global_position) <= TOP_M:
		_turned_back()


## Whether the Naming is waiting at the top of the stair for the character to go down.
func waiting() -> bool:
	var log_node := get_tree().get_first_node_in_group("quest_log") if is_inside_tree() else null
	if log_node == null or not log_node.has_method("stage_id_of"):
		return false
	return bool(log_node.call("is_active", QUEST)) and str(log_node.call("stage_id_of", QUEST)) == STAGE


func _set_progress(t: float) -> void:
	if is_equal_approx(t, progress):
		return
	progress = t
	drain(t)


## The world with `t` of its colour and sound gone (0 none, 1 all), eased so the last steps take
## the most.
static func drain(t: float) -> void:
	var k := smoothstep(0.0, 1.0, clampf(t, 0.0, 1.0))
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		for atm in tree.get_nodes_in_group("atmosphere"):
			if "drain" in atm:
				atm.set("drain", k)
	for bus_name in DRAINED_BUSES:
		var bus := AudioServer.get_bus_index(bus_name)
		if bus < 0:
			continue
		if not _bus_base.has(bus_name):
			if k <= 0.0:
				continue
			_bus_base[bus_name] = AudioServer.get_bus_volume_db(bus)
		AudioServer.set_bus_volume_db(bus, float(_bus_base[bus_name]) - QUIET_DB * k)
		if k <= 0.0:
			_bus_base.erase(bus_name)


## Everything the descent took, given back: the wake does this under its black, before the film.
static func restore() -> void:
	drain(0.0)
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		for d in tree.get_nodes_in_group(GROUP):
			(d as StairDescent).progress = 0.0
			(d as StairDescent).deepest = 0.0


func _trigger() -> void:
	triggered = true
	var player := get_tree().get_first_node_in_group("player")
	EventBus.act_done.emit("descend", player, null, "")
	var services := get_tree().get_first_node_in_group("game_services")
	if services != null and services.has_method("begin_wake"):
		services.call("begin_wake")
	else:
		restore()


## Back up at the top with the colour coming back: the thing is gone, and the Warden says so.
func _turned_back() -> void:
	deepest = 0.0
	_set_progress(0.0)
	GameState.set_flag("turned_back", true)
	var hud := UI.hud()
	if hud != null and hud.has_method("show_subtitle"):
		var wren := ContentDB.get_or_empty("core:npc/wren_tallow")
		hud.call("show_subtitle", "%s: Good." % Npc.shown_name(wren, Social.ctx if Social != null else null, "The Warden"), 3.0)
