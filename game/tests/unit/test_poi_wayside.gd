extends TestCase
## The wayside finds the cartographer puts along a road where it runs a minute and more past
## nothing (the gap map): a cairn, a tally post, a grave, a gibbet, a fold, a well, a lantern post,
## and a cart gone over in the verge. The world gives each a 14 m pad on a dale side of 25 to 45
## degrees, so each is raised here on a 35 degree slope with a road along it, and must stand inside
## the pad with nothing of it in the air. Each is built in its region's way, and the tests ask for
## what tells one region's from another's at thirty metres.

const KINDS := ["cairn", "tally_post", "grave", "gibbet", "fold", "well", "lantern_post", "hut", "crossroads", "peat_cut", "beacon"]
## Where each kind is meant to stand (the coordinator's list for the cartographer).
const HOMES := {
	"cairn": ["skerrow", "cinderlea", "hearthvale"],
	"tally_post": ["skerrow"],
	"grave": ["hearthvale", "skerrow", "sedgemire", "cinderlea", "brightwater", "briarwold"],
	"gibbet": ["hearthvale", "brightwater"],
	"fold": ["skerrow", "hearthvale"],
	"well": ["hearthvale", "brightwater"],
	"lantern_post": ["sedgemire"],
	"hut": ["briarwold", "skerrow", "sedgemire"],
	"crossroads": ["hearthvale", "skerrow", "cinderlea", "sedgemire"],
	"peat_cut": ["skerrow"],
	"beacon": ["hearthvale", "skerrow"],
}
## Half the 14 m pad.
const PAD_HALF_M := 7.0
## What rests on something else rather than on the ground: a stone on a cairn, a lintel on its
## uprights, a lantern on its arm, a roof on its walls, a spout on its wall, and the rest.
const RESTS_ON := ["Capstone", "Wand", "bone_vertebra", "bone_finger", "lantern_hanging", "bell_small", "Charter",
		"Plate", "Cup", "Chain", "Spout", "Trickle", "TroughWater", "LeanTo", "Wreath", "FabricCoping", "Notches",
		"Lintel", "HeadSlab", "jar", "Hearth", "Stack", "brazier", "Coins", "TurfRoof"]
const MAP := preload("res://ui/map/map_screen.gd")

var host: Node3D


## A dale side falling to the south (-z) at 35 degrees, the centre at 50 m.
class DaleSide extends TerrainProvider:
	func get_height(_x: float, z: float) -> float:
		return 50.0 + z * 0.7


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	host = Node3D.new()
	host.name = "WaysideHost"
	_tree().root.add_child(host)


func after_each() -> void:
	_tree().root.remove_child(host)
	host.free()


## A dressing of `kind` in `region`, on level ground or on the dale side, with a road running along
## the slope four metres uphill of it.
func _dress(kind: String, region: String, brief := "", ground: TerrainProvider = null) -> PoiDressing:
	var id := "core:poi/test_%s_%s" % [kind, region]
	var entry := {"place_id": id, "pos": [0.0, 50.0, 0.0], "radius_flat_m": 7.0}
	var def := {"id": id, "name": kind.capitalize(), "kind": kind, "region": "core:region/" + region,
			"unique_feature": brief, "encounter": ""}
	var road := [[[-60.0, 4.0], [60.0, 4.0]]]
	var d := PoiDressing.raise(entry, def, false, ground, road)
	host.add_child(d)
	return d


## Whether `n` is something that hangs or flies rather than stands: a cage or a cord in the wind,
## a crow, a sheep, smoke.
func _loose(n: Node, d: Node) -> bool:
	var p := n
	while p != null and p != d:
		if p is Turning or p is Crows or p is Livestock or p is GPUParticles3D:
			return true
		p = p.get_parent()
	return false


## Every standing box of the dressing in its own space, as [aabb, name]: one for each mesh, and
## for a MultiMesh one for each instance, or one round them all when `whole`.
func _boxes(d: PoiDressing, whole := false) -> Array:
	var out: Array = []
	var inv := d.global_transform.affine_inverse()
	for n in d.find_children("*", "GeometryInstance3D", true, false):
		if _loose(n, d):
			continue
		var g := n as GeometryInstance3D
		var label := _named(g, d)
		if g is MeshInstance3D and (g as MeshInstance3D).mesh != null:
			out.append([inv * g.global_transform * (g as MeshInstance3D).mesh.get_aabb(), label])
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh != null:
			var mm := (g as MultiMeshInstance3D).multimesh
			if mm.mesh == null or mm.instance_count == 0:
				continue
			var all := AABB()
			for i in mm.instance_count:
				var box: AABB = inv * g.global_transform * mm.get_instance_transform(i) * mm.mesh.get_aabb()
				if whole:
					all = box if i == 0 else all.merge(box)
				else:
					out.append([box, "%s[%d]" % [label, i]])
			if whole:
				out.append([all, label])
	return out


## A mesh's name, or the name of the forge asset it is a part of.
func _named(g: Node, d: Node) -> String:
	var p := g
	while p != null and p.get_parent() != d:
		p = p.get_parent()
	return str(p.name) if p != null else str(g.name)


func _rests(label: String) -> bool:
	for word in RESTS_ON:
		if label.contains(str(word)):
			return true
	return false


func test_every_wayside_kind_has_a_builder_in_every_region_it_stands_in() -> void:
	for kind in KINDS:
		assert_true(PoiDressing.KINDS.has(kind), "%s is a kind a POI can be" % kind)
		assert_true(PoiDressing.KINDS_BUILT.has(kind), "and one the kit builds: %s" % kind)
		assert_true(MAP.REVEAL_M.has(kind), "%s lights the map" % kind)
		assert_true(PlaceDiscovery.LANDMARK_M.has(kind), "%s has a height to be seen by" % kind)
		for region in HOMES[kind]:
			var warned := Log.warning_count
			var erred := Log.error_count
			var d := _dress(kind, region)
			assert_true(d.built, "%s in %s was dressed" % [kind, region])
			assert_eq(Log.warning_count, warned, "%s in %s was dressed without a warning" % [kind, region])
			assert_eq(Log.error_count, erred, "and without an error")
			assert_gt(d.find_children("*", "GeometryInstance3D", true, false).size(), 3, "%s in %s is more than a pad" % [kind, region])
			assert_gt(d.body_count(), 0, "%s in %s has something to bump into" % [kind, region])
			host.remove_child(d)
			d.free()


func test_every_wayside_kind_fits_its_pad_on_a_dale_side_with_nothing_in_the_air() -> void:
	var ground := DaleSide.new()
	var raised := 0
	for kind in KINDS:
		for region in HOMES[kind]:
			var d := _dress(kind, region, "", ground)
			var outside: Array[String] = []
			var floating: Array[String] = []
			for box_v in _boxes(d):
				var box: AABB = box_v[0]
				var reach := maxf(maxf(absf(box.position.x), absf(box.end.x)), maxf(absf(box.position.z), absf(box.end.z)))
				if reach > PAD_HALF_M:
					outside.append("%s %.1f m" % [box_v[1], reach])
			for box_v in _boxes(d, true):
				var box: AABB = box_v[0]
				if _rests(str(box_v[1])):
					continue
				# the highest ground under its foot: its bottom must reach it (a leaning thing's box
				# reaches further down than its foot, never less)
				var under := -INF
				for x in [box.position.x, box.end.x]:
					for z in [box.position.z, box.end.z]:
						under = maxf(under, ground.get_height(float(x), float(z)) - 50.0)
				if box.position.y > under + 0.05:
					floating.append("%s %.2f m up" % [box_v[1], box.position.y - under])
			assert_true(outside.is_empty(), "%s in %s stands inside 7 m of its centre: %s" % [kind, region, ", ".join(outside)])
			assert_true(floating.is_empty(), "%s in %s has nothing standing on air: %s" % [kind, region, ", ".join(floating)])
			raised += 1
			host.remove_child(d)
			d.free()
	var cart := _dress("wreck", "hearthvale", "a carter's cart gone over in the verge", ground)
	for box_v in _boxes(cart):
		var box: AABB = box_v[0]
		assert_true(maxf(absf(box.position.x), absf(box.end.x)) <= PAD_HALF_M and maxf(absf(box.position.z), absf(box.end.z)) <= PAD_HALF_M,
				"the cart and its load inside the pad (%s)" % box_v[1])
	assert_gt(raised, 15, "every kind in every region it stands in was raised on the slope")
	ground.free()


func test_a_cairn_is_a_man_high_and_topped_in_its_regions_way() -> void:
	for region in ["skerrow", "cinderlea", "hearthvale"]:
		var d := _dress("cairn", region)
		var top := -INF
		var tallest := ""
		for box_v in _boxes(d):
			if str(box_v[1]).begins_with("Cairn") and (box_v[0] as AABB).end.y > top:
				top = (box_v[0] as AABB).end.y
				tallest = "%s %s" % [box_v[1], str(box_v[0])]
		assert_true(top > 1.6 and top < 2.4, "the %s cairn stands about a man high (%.2f m: %s)" % [region, top, tallest])
		match region:
			"skerrow":
				assert_true(d.find_child("Capstone", true, false) != null, "a slab on end in the top of the fell's cairn")
				assert_false(d.find_children("*bone_vertebra*", "Node3D", true, false).is_empty(), "and a giant's knucklebone at its foot")
			"cinderlea":
				assert_true(d.find_child("Wand", true, false) != null, "a wand of white ash in the pilgrims' cairn")
				assert_true(d.find_child("Strip", true, false) is Turning, "with a strip of gold on it the wind takes")
			"hearthvale":
				assert_true(d.find_child("Capstone", true, false) != null, "a white stone on top of the Vale's")
				assert_null_or_absent(d, "Wand")
		host.remove_child(d)
		d.free()
	var grave := _dress("cairn", "skerrow", "a cairn over a drover who lies here")
	assert_true(grave.find_child("HeadSlab", true, false) != null, "a cairn over a grave has a slab at its head")


func assert_null_or_absent(d: Node, child: String) -> void:
	assert_true(d.find_child(child, true, false) == null, "no %s" % child)


func test_a_tally_posts_cords_stir_in_the_wind() -> void:
	var d := _dress("tally_post", "skerrow", "a blood-price of the Oskel clan")
	var post := d.find_child("TallyPost", true, false) as MeshInstance3D
	assert_true(post != null, "a post")
	if post != null:
		assert_gt(post.mesh.get_aabb().size.y, 3.2, "a tall one, well over a man")
	assert_true(d.find_child("Notches", true, false) != null, "the tally cut down its face")
	var hands := _turning(d, "Cords*")
	assert_eq(hands.size(), 4, "cords hung either side of it, from both yokes")
	var knots := 0
	for turn in hands:
		assert_gt(turn.swing, 0.0, "cords that swing, not go round")
		var before := turn.basis
		turn.turn(0.6)
		assert_false(turn.basis.is_equal_approx(before), "the wind moves them")
		for i in 40:
			turn.turn(0.25)
			var tilt := turn.basis.y.angle_to(Vector3.UP)
			assert_true(tilt < 0.3, "and they swing back, never round (%.2f rad)" % tilt)
		knots += turn.find_children("Tokens", "MeshInstance3D", true, false).size()
	assert_eq(knots, 4, "with bone tokens tied on")


func test_a_grave_is_told_by_its_region() -> void:
	# what each region's grave has that no other's does
	var marks := {"hearthvale": "*gravestone*", "skerrow": "Uprights", "sedgemire": "LanternPole", "cinderlea": "Stake",
			"brightwater": "Plate", "briarwold": "Staff"}
	for region in marks:
		var d := _dress("grave", region)
		assert_true(d.find_child("GraveMound", true, false) != null, "a mound in %s" % region)
		assert_true(_marker(d, "the_grave") != null, "and somewhere to stand by it")
		for other in marks:
			var has := not d.find_children(str(marks[other]), "Node3D", true, false).is_empty()
			assert_eq(has, other == region, "a %s grave %s the %s mark (%s)" % [region, "has" if other == region else "has not", other, marks[other]])
		if region == "sedgemire":
			var lit := 0
			for s in NightLights.sources_of(d):
				lit += 1 if str(s[1]) == "poi" else 0
			assert_eq(lit, 1, "the Reedfolk's lantern is lit")
		if region == "skerrow":
			assert_false(d.find_children("*bone_finger*", "Node3D", true, false).is_empty(), "a giant's bone for the lintel")
		host.remove_child(d)
		d.free()
	var board := _dress("grave", "hearthvale", "a wooden board with a name burned in it")
	assert_true(board.find_child("Board", true, false) != null, "a board where the sentence says one")


func test_a_gibbet_hangs_its_cage_off_the_arm_for_the_crows() -> void:
	var d := _dress("gibbet", "hearthvale")
	var cage := d.find_child("Cage", true, false) as Turning
	assert_true(cage != null, "a cage hung on its chain")
	var arm := d.find_child("Gibbet", true, false) as MeshInstance3D
	assert_true(arm != null and arm.mesh.get_aabb().size.y > 4.0, "from a post over four metres")
	if cage != null:
		var iron := cage.find_child("CageIron", true, false) as MeshInstance3D
		assert_true(iron != null, "of iron")
		if iron != null:
			var box := iron.mesh.get_aabb()
			var foot := cage.position.y + box.position.y
			assert_gt(foot, d.kit.on_ground(cage.position.x, cage.position.z).y + 0.3, "clear of the ground")
			assert_gt(box.size.y, 2.0, "a man's length of cage under its chain")
		assert_true(cage.find_child("CageBones", true, false) != null, "and what is left of him in it")
	assert_true(d.find_child("Crows", true, false) is Crows, "with the crows")
	assert_true(d.find_child("Charter", true, false) == null, "the Vale's gibbet has no charter")
	var lake := _dress("gibbet", "brightwater")
	assert_true(lake.find_child("Charter", true, false) != null, "the Tollmere watch nails its charter's plate to theirs")
	assert_true(lake.find_child("Step", true, false) != null, "on a lime-washed step")


func test_a_fold_is_a_ring_with_a_gate_to_the_road() -> void:
	var d := _dress("fold", "skerrow", "a fold of drystone, ewes in it, a lean-to for lambing")
	assert_true(d.find_child("FabricDrystone", true, false) != null, "drystone on the fells")
	assert_true(d.find_child("LeanTo", true, false) != null, "a lean-to where the sentence says one")
	assert_true(d.find_child("Flock", true, false) != null, "and the ewes in it")
	var gate := _marker(d, "the_fold")
	assert_true(gate != null, "somebody can stand at its gate")
	if gate != null:
		assert_gt(gate.position.z, 2.0, "on the road's side (%.1f)" % gate.position.z)
	var downs := _dress("fold", "hearthvale")
	assert_false(downs.find_children("*fence_wattle*", "Node3D", true, false).is_empty(), "the Vale's fold is wattle hurdles on the down")
	assert_true(downs.find_child("FabricDrystone", true, false) == null, "not drystone")


func test_a_well_on_the_level_and_a_spring_on_the_slope_each_keep_a_cup() -> void:
	var level := _dress("well", "hearthvale")
	assert_false(level.find_children("*_well_*", "Node3D", true, false).is_empty(), "a wellhead on the level")
	assert_true(level.find_child("Cup", true, false) != null, "with a cup")
	assert_true(level.find_child("Chain", true, false) != null, "on a chain")
	var ground := DaleSide.new()
	var slope := _dress("well", "hearthvale", "", ground)
	assert_true(slope.find_child("Spring", true, false) != null, "a spring let out of the bank on the slope")
	assert_true(slope.find_child("TroughWater", true, false) != null, "into a trough of water")
	assert_true(slope.find_child("Cup", true, false) != null, "with its cup")
	var spring := slope.find_child("Spring", true, false) as MeshInstance3D
	if spring != null:
		# its back is into the hill: uphill of the trough
		var water := slope.find_child("TroughWater", true, false) as MeshInstance3D
		assert_gt(spring.mesh.get_aabb().get_center().z, water.mesh.get_aabb().get_center().z, "the spring's wall is into the hill")
	var lake := _dress("well", "brightwater")
	var cup := lake.find_child("Cup", true, false) as MeshInstance3D
	assert_true(cup != null and (cup.material_override as StandardMaterial3D) != null and (cup.material_override as StandardMaterial3D).metallic > 0.5,
			"the Lakefolk's cup is brass")
	ground.free()


func test_a_lantern_post_is_lit_and_rags_the_way_on() -> void:
	var d := _dress("lantern_post", "sedgemire", "the safe way over the fen")
	var pole := d.find_child("LanternPole", true, false) as MeshInstance3D
	assert_true(pole != null and pole.mesh.get_aabb().size.y > 4.0, "a tall pole")
	assert_false(d.find_children("*lantern_hanging*", "Node3D", true, false).is_empty(), "a lantern on it")
	assert_true(d.find_child("Rags", true, false) is Turning, "indigo rags the wind takes")
	assert_eq(_turning(d, "StakeRag*").size(), 4, "and ragged stakes on along the way")
	var lit := 0
	for s in NightLights.sources_of(d):
		lit += 1 if str(s[1]) == "poi" else 0
	assert_eq(lit, 1, "lit")
	var drowned := _dress("lantern_post", "sedgemire", "the lantern of a boy who drowned here")
	assert_true(drowned.find_child("Wreath", true, false) != null, "a drowned man's lantern has its wreath")
	assert_true(_turning(drowned, "StakeRag*").is_empty(), "and marks no way")


func test_a_wreck_that_is_a_cart_is_a_cart_and_not_a_boat() -> void:
	var cart := _dress("wreck", "hearthvale", "a carter's cart gone over in the verge, its load spilled")
	assert_false(cart.find_children("*_cart_*", "Node3D", true, false).is_empty(), "a cart")
	assert_true(cart.find_child("Hull", true, false) == null, "and no hull")
	assert_true(cart.find_child("Wheel", true, false) != null, "with a wheel off")
	assert_false(cart.find_children("*sack*", "Node3D", true, false).is_empty(), "and its load spilled")
	var boat := _dress("wreck", "sedgemire", "a punt stove in on the mud")
	assert_true(boat.find_child("Hull", true, false) != null, "a wreck with no cart in its sentence is still a boat")


func _marker(d: Node, marker_name: String) -> Marker3D:
	return d.find_child(marker_name, true, false) as Marker3D


func _turning(d: Node, pattern: String) -> Array[Turning]:
	var out: Array[Turning] = []
	for n in d.find_children(pattern, "Node3D", true, false):
		if n is Turning:
			out.append(n as Turning)
	return out


func test_a_hut_is_its_regions_and_a_hermit_keeps_a_lean_to() -> void:
	var wood := _dress("hut", "briarwold", "a charcoal-burner's hut in the ride")
	assert_true(wood.find_child("HutSkin", true, false) != null, "a cone of poles under turf in the wood")
	assert_true(wood.find_child("Clamp", true, false) != null, "with the clamp smoking by it")
	assert_true(wood.find_child("Cordwood", true, false) != null, "and the cordwood stacked")
	var fell := _dress("hut", "skerrow", "a shepherd's bothy")
	assert_true(fell.find_child("FabricDrystone", true, false) != null, "a drystone bothy on the fells")
	assert_true(fell.find_child("TurfRoof", true, false) != null, "under turf")
	var hermit := _dress("hut", "briarwold", "a hermit's lean-to under the rock")
	assert_true(hermit.find_child("Boughs", true, false) != null, "a hermit's lean-to of boughs")
	assert_true(hermit.find_child("HutSkin", true, false) == null, "not a burner's cone")
	assert_true(_marker(hermit, "the_hut") != null, "somewhere to stand at its mouth")


func test_a_crossroads_has_a_fingerpost_and_its_regions_mark() -> void:
	var vale := _dress("crossroads", "hearthvale")
	assert_true(vale.find_child("Fingerpost", true, false) is Fingerpost, "a fingerpost")
	assert_true(vale.find_child("Stone", true, false) != null, "a stone at its foot")
	assert_false(vale.find_children("*milestone*", "Node3D", true, false).is_empty(), "and the Vale's milestone")
	var fell := _dress("crossroads", "skerrow")
	assert_true(fell.find_child("Cairn", true, false) != null, "a cairn at the fells' crossroads")
	var ash := _dress("crossroads", "cinderlea")
	assert_false(ash.find_children("*bell_small*", "Node3D", true, false).is_empty(), "a bell on a stake on the ash")


func test_a_peat_cut_is_a_bank_with_turves_drying() -> void:
	var ground := DaleSide.new()
	var d := _dress("peat_cut", "skerrow", "", ground)
	assert_true(d.find_child("Bank", true, false) != null, "a bank cut square")
	assert_true(d.find_child("Turves", true, false) != null, "the turves laid out and footed")
	assert_true(d.find_child("CutWater", true, false) != null, "black water in the floor of the cut")
	assert_false(d.find_children("*peat_stack*", "Node3D", true, false).is_empty(), "the dry ones stacked")
	var bank := d.find_child("Bank", true, false) as MeshInstance3D
	var turves := d.find_child("Turves", true, false) as MeshInstance3D
	if bank != null and turves != null:
		assert_gt(bank.mesh.get_aabb().get_center().z, turves.mesh.get_aabb().get_center().z, "the bank is cut into the hill, the turves laid below it")
	host.remove_child(d)
	d.free()
	ground.free()


func test_a_beacon_is_laid_and_burns_only_where_it_is_lit() -> void:
	var laid := _dress("beacon", "hearthvale", "the Wardens' beacon on the down")
	assert_true(laid.find_child("Stack", true, false) != null, "a cone of cordwood laid ready")
	assert_true(laid.find_child("Plinth", true, false) != null, "on a round of stone")
	assert_false(laid.find_children("*brazier*", "Node3D", true, false).is_empty(), "and a fire-basket on its pole")
	assert_eq(NightLights.sources_of(laid).size(), 0, "not lit")
	var lit := _dress("beacon", "hearthvale", "the beacon, lit and burning")
	assert_eq(NightLights.sources_of(lit).size(), 1, "lit where the sentence says it burns")
