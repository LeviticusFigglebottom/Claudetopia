extends TestCase
## The scatter a body walks into (world/scatter_solids.gd): the playtest on batch 3 walked through
## trees, fences and rocks. A body with the player's own mask walks at a tree, a boulder, a
## drystone wall, a hedge and a roadside fence in a near-ring cell and is stopped short of each, and
## walks through the grass. The shapes are the forge's (its trunk radius, its bounds, its rocks'
## collision meshes), the body goes with the cell, and a villager or a foe pressed against a wall
## with nowhere to go walks through it after a second.

const TREE := "res://assets/models/trees/hearthvale_oak_a/hearthvale_oak_a.glb"
const BOULDER := "res://assets/models/rocks/hearthvale_boulder_a/hearthvale_boulder_a.glb"
const WALL := "res://assets/models/props/skerrow_drystone_wall_a/skerrow_drystone_wall_a.glb"
const HEDGE := "res://assets/models/props/hearthvale_hedge_segment_a/hearthvale_hedge_segment_a.glb"
const RAIL := "res://assets/models/props/hearthvale_fence_post_rail_a/hearthvale_fence_post_rail_a.glb"
const GRASS := "res://assets/models/flora/hearthvale_grass_clump_a/hearthvale_grass_clump_a.glb"
const SCREE := "res://assets/models/rocks/skerrow_scree_b/skerrow_scree_b.glb"
const SLAB := "res://assets/models/rocks/skerrow_cliff_slab_a/skerrow_cliff_slab_a.glb"
const STUMP := "res://assets/models/trees/cinderlea_char_stump_a/cinderlea_char_stump_a.glb"
## Where the test's cell stands: out of the way of anything else in the test world.
const AT := Vector3(5000.0, 0.0, 5000.0)

var _holder: Node3D


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func after_each() -> void:
	if _holder != null and is_instance_valid(_holder):
		_holder.free()
	_holder = null
	await _tree().physics_frame


static func _all_there(paths: Array) -> bool:
	for p in paths:
		if not ResourceLoader.exists(str(p)):
			return false
	return true


## The mask a scene's root body is saved with, read without standing the scene up.
static func _scene_mask(path: String) -> int:
	var packed := load(path) as PackedScene
	if packed == null:
		return -1
	var state := packed.get_state()
	for p in state.get_node_property_count(0):
		if state.get_node_property_name(0, p) == "collision_mask":
			return int(state.get_node_property_value(0, p))
	return 1


func test_the_player_the_foes_and_the_people_walk_into_the_scatter_and_the_camera_does_not() -> void:
	for scene in ["res://actors/player/player.tscn", "res://actors/enemy/enemy.tscn", "res://actors/npc/npc.tscn"]:
		var mask := _scene_mask(scene)
		assert_true(mask > 0 and (mask & ScatterSolids.LAYER) != 0, "%s's body walks into the scatter (mask %d)" % [scene, mask])
	assert_true((Actor.BODY_MASK & ScatterSolids.LAYER) != 0, "and so does any body made in code")
	assert_eq(Actor.LAYER_SCATTER, ScatterSolids.LAYER, "one layer, named the same in both")
	assert_eq(ProjectSettings.get_setting("layer_names/3d_physics/layer_13", ""), "scatter", "the layer has its name")
	var camera_mask := (1 << 0) | (1 << 9) | (1 << 10)
	assert_eq(camera_mask & ScatterSolids.LAYER, 0, "the camera's arm is not pulled in by a trunk")


func test_what_stands_as_what() -> void:
	if not _all_there([TREE, BOULDER, WALL, HEDGE, GRASS, SCREE, SLAB, STUMP]):
		return
	assert_eq(ScatterSolids.spec_for(TREE)["kind"], "trunk", "a tree is its trunk")
	assert_eq(ScatterSolids.spec_for(STUMP)["kind"], "trunk", "and a stump too")
	assert_eq(ScatterSolids.spec_for(BOULDER)["kind"], "hull", "a boulder is its hull")
	assert_eq(ScatterSolids.spec_for(WALL)["kind"], "box", "a wall is the box of its bounds")
	assert_eq(ScatterSolids.spec_for(HEDGE)["kind"], "box", "and a hedge, though the forge says none: it is a field's wall")
	assert_eq(ScatterSolids.spec_for(SLAB)["kind"], "hull", "a cliff slab is the hull of the forge's collision mesh")
	var slab: Array = ScatterSolids.solid_of(SLAB, [AT.x, 0.0, AT.z, 0.0, 2.0, "#ffffff"], AT)
	assert_false(slab.is_empty(), "and stands, at twice its size too")
	assert_eq(ScatterSolids.spec_for(GRASS)["kind"], "none", "grass is walked through")
	assert_eq(ScatterSolids.spec_for(SCREE)["kind"], "none", "and loose scree")
	var trunk: Array = ScatterSolids.solid_of(TREE, [AT.x, 0.0, AT.z, 30.0, 1.0, "#ffffff"], AT)
	var r := float(ScatterSolids.meta(TREE)["collision_params"]["radius"])
	assert_near((trunk[0] as CylinderShape3D).radius, r, 0.02, "the trunk has the forge's own radius")
	var big: Array = ScatterSolids.solid_of(TREE, [AT.x, 0.0, AT.z, 30.0, 1.5, "#ffffff"], AT)
	assert_near((big[0] as CylinderShape3D).radius, r * 1.5, 0.02, "and grows with the tree")
	assert_true((big[0] as CylinderShape3D).height <= ScatterSolids.TRUNK_TOP_M + ScatterSolids.SINK_M + 0.01,
			"only as high as a body meets: the crown is walked under")
	var small: Array = ScatterSolids.solid_of(BOULDER, [AT.x, 0.0, AT.z, 0.0, 0.1, "#ffffff"], AT)
	assert_true(small.is_empty(), "a boulder scaled to a pebble is stepped over")


func test_a_row_stands_where_it_is_drawn() -> void:
	var origin := Vector3(120.0, 0.0, -340.0)
	for row in [[130.0, 4.0, -330.0, 71.0, 1.3, "#ffffff"],
			[118.5, 2.0, -351.0, 200.0, 0.9, "#ffffff", 7.0, 45.0],
			[125.0, 1.0, -335.0, 12.0, 1.0, "#ffffff", 0.0, 0.0, [1.4, 0.95, 1.0]]]:
		var drawn := WorldStreamer.instance_transform(row, origin)
		var stood := ScatterSolids.row_transform(row, origin)
		assert_true(drawn.is_equal_approx(stood), "the solid stands where the scatter draws it (%s)" % str(row))


## A cell of its own, with the scatter given, its wayside built, and its shapes stood.
func _cell(instances: Dictionary) -> ScatterSolids:
	_holder = Node3D.new()
	_holder.name = "SolidsTest"
	_tree().root.add_child(_holder)
	var solids := ScatterSolids.new()
	_holder.add_child(solids)
	var cell := Node3D.new()
	cell.name = "Cell_test"
	cell.position = AT
	_holder.add_child(cell)
	var built: Array = []
	var drawn := Wayside.prepare(instances, cell, true, built)
	solids.add_cell(cell, drawn, built)
	solids.flush()
	return solids


## A body the player's size with the player's mask, walked from `from` toward `to` a step at a time
## until something stops it. Where it ended up.
func _walk(from: Vector3, to: Vector3) -> Vector3:
	var body := CharacterBody3D.new()
	body.collision_layer = 1 << 1
	body.collision_mask = _scene_mask("res://actors/player/player.tscn")
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0.0, 0.9, 0.0)
	body.add_child(cs)
	_holder.add_child(body)
	body.global_position = from
	var step := (to - from) / 40.0
	for i in 40:
		if body.move_and_collide(step) != null:
			break
	var at := body.global_position
	body.free()
	return at


func test_a_body_stops_at_a_tree_a_boulder_a_wall_a_hedge_and_a_fence_and_walks_through_grass() -> void:
	if not _all_there([TREE, BOULDER, WALL, HEDGE, RAIL, GRASS]):
		return
	var rails: Array = []
	for i in 4:
		rails.append([AT.x - 30.0 + 2.35 * float(i), 0.0, AT.z + 30.0, 0.0, 1.0, "#ffffff"])
	var solids := _cell({
		TREE: [[AT.x, 0.0, AT.z, 0.0, 1.0, "#ffffff"]],
		BOULDER: [[AT.x + 30.0, 0.0, AT.z, 0.0, 1.2, "#ffffff"]],
		WALL: [[AT.x - 30.0, 0.0, AT.z, 0.0, 1.0, "#ffffff"]],
		HEDGE: [[AT.x, 0.0, AT.z - 30.0, 0.0, 1.0, "#ffffff"]],
		RAIL: rails,
		GRASS: [[AT.x + 30.0, 0.0, AT.z + 30.0, 0.0, 1.5, "#ffffff"]],
	})
	# the oak and the boulder share a block, the wall and the rails another, and the hedge has one
	assert_eq(solids.body_count(), 3, "a body for each block with something solid in it")
	assert_eq(solids.bodies_in_space(), 3, "each in the physics space once it is whole")
	assert_true(solids.shape_count() >= 5, "with a shape for each solid thing (%d)" % solids.shape_count())
	await _tree().physics_frame
	await _tree().physics_frame
	var r := float(ScatterSolids.meta(TREE)["collision_params"]["radius"])
	# at the trunk, from four metres, square on
	var at := _walk(AT + Vector3(-4.0, 0.0, 0.0), AT)
	assert_true(at.x < AT.x - r - 0.2, "a tree stops the body short of its trunk (%.2f m off its middle)" % (AT.x - at.x))
	at = _walk(AT + Vector3(26.0, 0.0, 0.0), AT + Vector3(30.0, 0.0, 0.0))
	assert_true(at.x < AT.x + 29.0, "a boulder stops it (%.2f m short of the middle)" % (AT.x + 30.0 - at.x))
	# the wall runs along x; walked at across it, the body stays on its own side
	at = _walk(AT + Vector3(-30.0, 0.0, -4.0), AT + Vector3(-30.0, 0.0, 4.0))
	assert_true(at.z < AT.z - 0.2, "a drystone wall stops it (%.2f m from its line)" % (AT.z - at.z))
	at = _walk(AT + Vector3(0.0, 0.0, -34.0), AT + Vector3(0.0, 0.0, -26.0))
	assert_true(at.z < AT.z - 30.0 - 0.3, "a hedge stops it (%.2f m from its line)" % (AT.z - 30.0 - at.z))
	at = _walk(AT + Vector3(-26.5, 0.0, 26.0), AT + Vector3(-26.5, 0.0, 34.0))
	assert_true(at.z < AT.z + 30.0 - 0.1, "a roadside fence stops it (%.2f m from its line)" % (AT.z + 30.0 - at.z))
	at = _walk(AT + Vector3(26.0, 0.0, 30.0), AT + Vector3(34.0, 0.0, 30.0))
	assert_near(at.x, AT.x + 34.0, 0.05, "and grass is walked through")


func test_the_body_goes_with_the_cell() -> void:
	if not _all_there([TREE]):
		return
	var solids := _cell({TREE: [[AT.x, 0.0, AT.z, 0.0, 1.0, "#ffffff"], [AT.x + 5.0, 0.0, AT.z, 0.0, 1.0, "#ffffff"]]})
	assert_eq(solids.body_count(), 1, "a body while the cell stands")
	var body: RID = solids.bodies()[0]
	assert_eq(PhysicsServer3D.body_get_shape_count(body), 2, "with a trunk for each tree")
	assert_eq(PhysicsServer3D.body_get_collision_layer(body), ScatterSolids.LAYER, "on the scatter's layer")
	assert_eq(PhysicsServer3D.body_get_space(body), _holder.get_world_3d().space, "and in the world's space")
	var cell := _holder.get_node("Cell_test")
	cell.free()
	assert_eq(solids.body_count(), 0, "and none once the cell is gone")
	assert_eq(solids.shape_count(), 0, "nor its shapes")


func test_the_nearest_cell_is_stood_first_and_a_tick_is_bounded() -> void:
	if not _all_there([TREE]):
		return
	_holder = Node3D.new()
	_tree().root.add_child(_holder)
	var solids := ScatterSolids.new()
	_holder.add_child(solids)
	var cells: Array[Node3D] = []
	for i in 3:
		var cell := Node3D.new()
		cell.position = AT + Vector3(256.0 * float(i), 0.0, 0.0)
		_holder.add_child(cell)
		var rows: Array = []
		for k in 300:
			rows.append([cell.position.x + float(k % 20) * 3.0, 0.0, cell.position.z + float(k / 20) * 3.0, 0.0, 1.0, "#ffffff"])
		solids.add_cell(cell, {TREE: rows})
		cells.append(cell)
	# the eye at the third cell: that one is stood first
	var eye := cells[2].position
	var stood := solids.build(eye, 300)
	assert_true(stood > 0 and stood < 900, "a tick stands part of the ring (%d of 900)" % stood)
	var first := solids.shapes_under(cells[2])
	assert_true(first > 0 and solids.shapes_under(cells[0]) == 0 and solids.shapes_under(cells[1]) == 0,
			"and it is the cell the eye is in (%d there)" % first)
	assert_eq(solids.in_space_under(cells[0]), 0, "a block not yet begun is not in the physics space")
	assert_eq(solids.in_space_under(cells[2]), 0,
			"nor is one stood this tick: it joins whole, at the start of the next, so the engine files its shapes once")
	var ticks := 1
	while solids.in_space_under(cells[2]) == 0 and ticks < 200:
		solids.build(eye, 300)
		ticks += 1
	assert_true(solids.in_space_under(cells[2]) > 0, "a block joins the tick after it is whole (%d ticks)" % ticks)
	assert_eq(solids.shapes_under(cells[0]) + solids.shapes_under(cells[1]), 0, "and the far cells are not begun")
	solids.flush()
	assert_eq(solids.shape_count(), 900, "everything stands in the end")
	assert_eq(solids.pending(), 0, "and nothing waits")


func test_a_stuck_villager_walks_through_the_scatter_for_a_moment() -> void:
	var body := CharacterBody3D.new()
	body.collision_mask = 1 | ScatterSolids.LAYER
	_holder = Node3D.new()
	_tree().root.add_child(_holder)
	_holder.add_child(body)
	# walking at 1.4 m/s and getting nowhere
	for i in 6:
		ScatterSolids.unstick(body, Vector3(1.4, 0.0, 0.0), 0.1)
	assert_true((body.collision_mask & ScatterSolids.LAYER) != 0, "half a second against a wall is still walking into it")
	for i in 6:
		ScatterSolids.unstick(body, Vector3(1.4, 0.0, 0.0), 0.1)
	assert_eq(body.collision_mask & ScatterSolids.LAYER, 0, "a second getting nowhere and it walks through")
	assert_true((body.collision_mask & 1) != 0, "the world's own walls still stop it")
	for i in 16:
		ScatterSolids.unstick(body, Vector3(1.4, 0.0, 0.0), 0.1)
	assert_true((body.collision_mask & ScatterSolids.LAYER) != 0, "and after a moment it is solid to it again")
	# one that is getting somewhere is left alone
	for i in 15:
		body.global_position += Vector3(0.14, 0.0, 0.0)
		ScatterSolids.unstick(body, Vector3(1.4, 0.0, 0.0), 0.1)
	assert_true((body.collision_mask & ScatterSolids.LAYER) != 0, "a body that walks is never let through")
