extends TestCase
## Walking into a boss chamber, the way a player does.
##
## DESIGN §5.4 promises a boss "a fog gate, a name card, a bespoke arena scene, a unique drop",
## and `actors/enemy/boss_arena.tscn` -- the scene with the fog gate in it -- was instantiated
## by nothing anywhere in the project. Every fight improvised a bound through
## `BossArena.for_boss`, which is unbounded by design and closes nothing, so the one thing that
## tells a player a boss fight has begun, and the one thing that stops them wandering back up
## the tunnel in the middle of it, existed in a scene nobody opened.
##
## These build a real deep place from the forge's meta, put a real player in the tunnel and
## walk them through the threshold, and then ask the arena and the boss -- not the screen.

const BARROW := "res://assets/models/dungeon/hollin_barrow/hollin_barrow.meta.json"
const REEVE := "core:boss/barrow_reeve"
const PLAYER_SCENE := "res://actors/player/player.tscn"

var cave: CaveInterior
var player: Node3D
var boss: Enemy


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func after_each() -> void:
	for n: Node in [player, boss, cave]:
		if n != null and is_instance_valid(n):
			n.queue_free()
	player = null
	boss = null
	cave = null


func _build() -> CaveInterior:
	if not FileAccess.file_exists(BARROW):
		return null
	cave = CaveInterior.new()
	cave.build_on_ready = false
	cave.spawn_encounters = true
	_tree().root.add_child(cave)
	if not cave.build(BARROW):
		return null
	return cave


func _arena() -> BossArena:
	for n in cave.find_children("*", "BossArena", true, false):
		if (n as BossArena).boss_id == REEVE:
			return n
	return null


func test_the_barrows_reeve_hall_has_an_authored_arena_with_a_fog_gate() -> void:
	if _build() == null:
		return
	var arena := _arena()
	assert_true(arena != null, "the boss chamber has no arena in it: every fight improvises one")
	if arena == null:
		return
	assert_true(arena.gate != null, "the arena stands but has no fog gate")
	assert_true(arena.is_bounded(), "the arena has no floor, so the fight has no edge")
	var reeve_hall: Dictionary = cave.chambers["reeve_hall"]
	var radii := CaveInterior._vec(reeve_hall["radii"])
	assert_near(arena.radius, maxf(radii.x, radii.z), 0.01,
			"the bound is not the chamber the forge built")
	assert_eq(arena.centre, CaveInterior._vec(reeve_hall["centre"]),
			"the bound is not measured from the chamber")


## The gate belongs on the way in, not on the way out. The Reeve's hall is reached from the
## squeeze and leaves by the back stair; only one of those is a threshold.
func test_the_gate_stands_in_the_tunnel_you_come_in_by() -> void:
	if _build() == null:
		return
	var arena := _arena()
	if arena == null:
		return
	var centre := CaveInterior._vec((cave.chambers["reeve_hall"] as Dictionary)["centre"])
	var squeeze := CaveInterior._vec((cave.chambers["squeeze"] as Dictionary)["centre"])
	var back := CaveInterior._vec((cave.chambers["back_stair"] as Dictionary)["centre"])
	var gate_dir := (arena.global_position - centre)
	gate_dir.y = 0.0
	var to_squeeze := Vector3(squeeze.x - centre.x, 0.0, squeeze.z - centre.z).normalized()
	var to_back := Vector3(back.x - centre.x, 0.0, back.z - centre.z).normalized()
	var d := gate_dir.normalized()
	assert_gt(d.dot(to_squeeze), d.dot(to_back),
			"the fog gate is on the way out rather than the way in")


## The button, pressed: a body with legs walks through the threshold.
func test_walking_in_closes_the_gate_behind_you_and_starts_the_fight() -> void:
	if _build() == null:
		return
	var arena := _arena()
	if arena == null:
		return
	boss = Enemy.new()
	boss.configure(REEVE)
	_tree().root.add_child(boss)
	boss.global_position = arena.centre
	assert_true(boss.is_boss, "the Barrow Reeve is not marked a boss, so nothing would start")
	assert_false(boss.boss_started)
	assert_false(arena.gate.visible, "the gate is shut before anybody has arrived")

	player = await _walk_in(arena)
	if player == null:
		return

	assert_true(arena.active, "walking through the threshold did not start the arena")
	assert_true(boss.boss_started, "the boss did not wake, so no name card and no music")
	assert_true(arena.gate.visible, "the gate did not close behind the player")
	assert_true(_gate_is_solid(arena), "the gate closed and you can still walk out through it")


func test_when_the_boss_dies_the_gate_opens_and_the_arena_goes() -> void:
	if _build() == null:
		return
	var arena := _arena()
	if arena == null:
		return
	boss = Enemy.new()
	boss.configure(REEVE)
	_tree().root.add_child(boss)
	boss.global_position = arena.centre
	player = await _walk_in(arena)
	if player == null:
		return
	assert_true(arena.gate.visible, "nothing to open: the gate never closed")

	boss.die(null)
	assert_false(arena.gate.visible, "the gate stayed shut over a dead boss")
	assert_false(arena.is_bounded(), "the floor is still taken from a fight that is over")
	await _tree().process_frame
	await _tree().process_frame
	assert_false(is_instance_valid(arena), "the arena outlived the fight it was for")


# --- walking -----------------------------------------------------------------------------------

## Puts a real player body in the tunnel and moves it through the threshold, then lets the
## physics step flush the overlap. Returns null when the player scene will not build headless,
## and the caller stops rather than asserting on nothing.
func _walk_in(arena: BossArena) -> Node3D:
	if not ResourceLoader.exists(PLAYER_SCENE):
		return null
	var packed: PackedScene = load(PLAYER_SCENE)
	var body := packed.instantiate() as Node3D
	if body == null:
		return null
	_tree().root.add_child(body)
	if body.has_method("set_input_enabled"):
		body.call("set_input_enabled", false)
	# Outside first, then through: an Area3D reports a body entering, not a body already in it.
	var inward := (arena.centre - arena.global_position)
	inward.y = 0.0
	inward = inward.normalized()
	body.global_position = arena.global_position - inward * 3.0 + Vector3.UP * 0.6
	await _tree().physics_frame
	await _tree().physics_frame
	body.global_position = arena.global_position + Vector3.UP * 0.6
	await _tree().physics_frame
	await _tree().physics_frame
	# The gate turns its collision on with set_deferred, which lands at the end of an idle frame.
	await _tree().process_frame
	return body


func _gate_is_solid(arena: BossArena) -> bool:
	for c in arena.gate.get_children():
		if c is CollisionShape3D and not (c as CollisionShape3D).disabled:
			return true
	return false
