class_name Sparring
extends Node
## A bout in a ring with the teacher (docs/FIGHTING_STYLE_STARTS.md §3.1, "The ring"): the stage
## that says `spar` has the teacher step into the ring with a blunt blade and fight the player for
## real, slowly, so the block, the parry and the roll can be learned on somebody. Nobody dies of
## it. When the player is beaten down, the teacher knocks them off their feet, helps them up and
## says the one thing they did wrong (the first lesson of the stage not yet done); when the teacher
## has had enough, they step back and go again. When the stage's lessons are done, the bout ends
## and the teacher is themselves again.
##
## A stage's `spar`:
##   {enemy: the teacher as a foe (core:enemy/*), npc: the teacher, place, feature: the place's
##    ring (Settlement.feature_position), flag: set when the teacher has been asked to begin,
##    down_at: the player's health share that ends a bout (0.35), yield_at: the teacher's (0.5),
##    tips: [text per objective of the stage, in order], again: what is said going again}
## The teacher's own body is put out of sight while their foe's stands in the ring, and brought
## back where it was.

const GROUP := "sparring"
const POLL_S := 0.25
## How near the ring the player has to be for a bout to stand up, and how far off ends it.
const STEP_IN_M := 9.0
const WALK_OFF_M := 30.0
## Seconds between a bout ending and the next beginning.
const BREATHER_S := 3.5
const DOWN_S := 1.6

enum Phase { IDLE, FIGHT, BREATHER }

var phase := Phase.IDLE
var spec: Dictionary = {}
var quest_id := ""
var foe: Enemy = null
var bouts := 0
var _look := PollTimer.new(POLL_S)
var _breather_until := 0
var _hidden: Node3D = null
var _hidden_layer := 0
var _hidden_mask := 0


static func ensure() -> Sparring:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var found := tree.get_first_node_in_group(GROUP)
	if found is Sparring:
		return found as Sparring
	var made := Sparring.new()
	made.name = "Sparring"
	var host: Node = tree.current_scene if tree.current_scene != null else tree.root
	host.add_child(made)
	return made


func _ready() -> void:
	add_to_group(GROUP)


func _exit_tree() -> void:
	_end()


func _process(delta: float) -> void:
	if not _look.due(delta):
		return
	refresh()


## The stage that wants a bout now, if any: {quest_id, spar}.
func wanted() -> Dictionary:
	var log_node := get_tree().get_first_node_in_group("quest_log") if is_inside_tree() else null
	if log_node == null:
		return {}
	for q in (log_node.get("quests") as Dictionary).keys():
		if not bool(log_node.call("is_active", q)):
			continue
		var stage: Dictionary = log_node.call("stage_def", q, int(log_node.call("stage_of", q)))
		var s: Variant = stage.get("spar", null)
		if s is Dictionary:
			return {"quest_id": str(q), "spar": s}
	return {}


## Where the bout is fought: the ring of the place the spar names.
func ring() -> Vector3:
	var place := str(spec.get("place", ""))
	var feature := str(spec.get("feature", "ring"))
	for s in get_tree().get_nodes_in_group("settlement"):
		if str(s.get("place_id")) == place and s.has_method("feature_position"):
			var at: Vector3 = s.call("feature_position", feature)
			if at != Vector3.INF:
				return at
	return Vector3.INF


func refresh() -> void:
	var want := wanted()
	var player := get_tree().get_first_node_in_group("player") as Actor
	if want.is_empty() or player == null:
		if phase != Phase.IDLE:
			_end()
		return
	spec = want["spar"]
	quest_id = str(want["quest_id"])
	var at := ring()
	if at == Vector3.INF:
		return
	var off := Vector2(player.global_position.x - at.x, player.global_position.z - at.z).length()
	match phase:
		Phase.IDLE:
			if GameState.has_flag(str(spec.get("flag", ""))) and off <= STEP_IN_M:
				_begin(at, player)
		Phase.FIGHT:
			if off > WALK_OFF_M:
				_end()
				return
			if foe == null or not is_instance_valid(foe) or foe.dead:
				_end()
				return
			if player.health <= player.max_health * float(spec.get("down_at", 0.35)):
				_player_beaten(player)
			elif foe.health <= foe.max_health * float(spec.get("yield_at", 0.5)):
				_teacher_yields(player)
		Phase.BREATHER:
			if Time.get_ticks_msec() >= _breather_until:
				phase = Phase.IDLE


## The teacher steps into the ring as a foe, and their own body goes out of sight.
func _begin(at: Vector3, player: Actor) -> void:
	var npc := str(spec.get("npc", ""))
	var body: Node3D = null
	if NpcRegistry.instance != null and not npc.is_empty():
		body = NpcRegistry.instance.actor(npc) as Node3D
	var from := at
	if body != null and is_instance_valid(body):
		from = body.global_position
		_hide(body)
	var spawner := EnemySpawner.new()
	spawner.name = "SparringFoe"
	spawner.spawn_on_ready = false
	spawner.respawn_on_rest = false
	add_child(spawner)
	var face := player.global_position - from
	foe = spawner.spawn_one(str(spec.get("enemy", "")), from, atan2(-face.x, -face.z))
	if foe == null:
		_end()
		return
	foe.add_to_group("sparring_foe")
	phase = Phase.FIGHT
	bouts += 1
	Log.info("Sparring", "bout %d: %s in the ring" % [bouts, foe.display_name])


## Beaten down: off your feet, helped up, and told the one thing.
func _player_beaten(player: Actor) -> void:
	var dir := player.global_position - foe.global_position
	dir.y = 0.0
	player.knock_down(dir.normalized() if dir.length() > 0.1 else -player.forward())
	_stand_down()
	_say(tip())
	var tree := get_tree()
	await tree.create_timer(DOWN_S, true, false, true).timeout
	if is_instance_valid(player):
		player.full_restore()


## The teacher has had enough of this bout: they step back, and it goes again.
func _teacher_yields(player: Actor) -> void:
	_stand_down()
	player.stamina_comp.refill()
	_say(str(spec.get("again", "")))


## The first lesson of the stage not yet learned, said the teacher's way.
func tip() -> String:
	var tips: Array = spec.get("tips", [])
	var log_node := get_tree().get_first_node_in_group("quest_log")
	for i in tips.size():
		if str(tips[i]).is_empty():
			continue
		if log_node == null or not bool(log_node.call("objective_done", quest_id, i)):
			return str(tips[i])
	return str(spec.get("again", ""))


func _say(text: String) -> void:
	if not text.is_empty():
		Barks.say(str(spec.get("npc", "")), text, 0.4)


## The foe leaves the ring, for a breather before the next bout.
func _stand_down() -> void:
	_drop_foe()
	_show()
	phase = Phase.BREATHER
	_breather_until = Time.get_ticks_msec() + int(BREATHER_S * 1000.0)


func _end() -> void:
	_drop_foe()
	_show()
	phase = Phase.IDLE


func _drop_foe() -> void:
	if foe != null and is_instance_valid(foe):
		var spawner := foe.get_parent()
		if spawner is EnemySpawner:
			spawner.queue_free()
		else:
			foe.queue_free()
	foe = null


func _hide(body: Node3D) -> void:
	_hidden = body
	body.visible = false
	if body is CollisionObject3D:
		_hidden_layer = (body as CollisionObject3D).collision_layer
		_hidden_mask = (body as CollisionObject3D).collision_mask
		(body as CollisionObject3D).collision_layer = 0
	body.set_meta("sparring", true)


func _show() -> void:
	if _hidden != null and is_instance_valid(_hidden):
		_hidden.visible = true
		if _hidden is CollisionObject3D:
			(_hidden as CollisionObject3D).collision_layer = _hidden_layer
		_hidden.remove_meta("sparring")
	_hidden = null
