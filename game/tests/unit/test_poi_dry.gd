extends TestCase
## Nothing a point of interest is dressed with stands in the water. The batch 3 shots had a cart
## standing in a Briarwold river. A dressing sets its props at offsets from its centre, and a pad
## a river runs through (a bridge, a ford, a mill, a fall) puts some of those offsets in the water.
## This raises every dressable POI on the built world and checks every forged prop the dressing
## stood, one by one or in a MultiMesh: none may stand on water with its foot under the water's
## surface. The kinds that never do are PoiKit.DRY_KINDS; a buoy's barrel, a weir's basket and a
## causeway's lamp are the water's own.
##
## These read the built world (`./run.sh world`); when it is missing they say so once and skip.

const GENERATED := "res://world/generated"
const PROPS_DIR := "res://assets/models/props"
## how far under the surface a prop's foot may be (the forge's props stand from y = 0) and still
## count as standing on the bank's edge
const UNDER_M := 0.25

var provider: TerrainProvider = null
var pois: Array = []
var roads: Array = []
var _scratch: Node3D = null
var _props: Dictionary = {}


func before_each() -> void:
	if provider != null:
		return
	if not FileAccess.file_exists("%s/pois.json" % GENERATED):
		skip("world data missing: run ./run.sh world")
		return
	provider = TerrainProvider.new()
	provider.load_data()
	pois = JSON.parse_string(FileAccess.get_file_as_string("%s/pois.json" % GENERATED))
	roads = WorldPois.roads_from_disk()
	for name in DirAccess.get_directories_at(PROPS_DIR):
		_props[name] = true


func _host() -> Node3D:
	if _scratch == null or not is_instance_valid(_scratch):
		_scratch = Node3D.new()
		_scratch.name = "PoiDryScratch"
		(Engine.get_main_loop() as SceneTree).root.add_child(_scratch)
	return _scratch


## The forged prop a node is, by its name ("briarwold_cart_a", "…_x12" for a MultiMesh), or "".
func _prop_of(node: Node) -> String:
	var n := str(node.name)
	if node is MultiMeshInstance3D:
		var cut := n.rfind("_x")
		if cut > 0:
			n = n.substr(0, cut)
	if node is Node3D and not str((node as Node3D).scene_file_path).is_empty():
		n = str((node as Node3D).scene_file_path).get_file().get_basename()
	return n if _props.has(n) else ""


static func _kind(prop: String) -> String:
	var parts := prop.split("_")
	if parts.size() <= 2:
		return prop
	return "_".join(parts.slice(1, parts.size() - 1))


func _wet(p: Vector3) -> bool:
	if not provider.is_water(p.x, p.z):
		return false
	var level := provider.water_level_at(p.x, p.z)
	return level > TerrainProvider.NO_WATER + 1.0 and p.y < level - UNDER_M


func _walk(node: Node, out: Array, id: String) -> void:
	for child in node.get_children():
		var prop := _prop_of(child)
		# (a MultiMesh's instances cannot be read back headless: the dummy renderer keeps none,
		# so the ones PoiKit.scatter stands are held by its own test, below)
		if prop != "" and child is Node3D and not child is MultiMeshInstance3D \
				and PoiKit.DRY_KINDS.has(_kind(prop)):
			var p := (child as Node3D).global_position
			if _wet(p):
				out.append("%s: %s at (%.0f, %.1f, %.0f)" % [id, prop, p.x, p.y, p.z])
			continue
		_walk(child, out, id)


func test_no_poi_stands_a_prop_in_the_water() -> void:
	if provider == null:
		return
	var wet: Array = []
	var checked := 0
	for item_v in WorldPois.candidates(pois):
		var item: Dictionary = item_v
		var entry: Dictionary = item["entry"]
		if not PoiDressing.KINDS_BUILT.has(PoiDressing.kind_of(str(entry["place_id"]), item["def"])):
			continue
		var d := PoiDressing.raise(entry, item["def"], false, provider, roads)
		_host().add_child(d)
		checked += 1
		_walk(d, wet, str(entry["place_id"]))
		d.get_parent().remove_child(d)
		d.free()
	assert_gt(checked, 50, "POIs dressed")
	for line in wet:
		print("  wet: %s" % line)
	assert_true(wet.is_empty(), "%d props stand in the water: %s" % [wet.size(), ", ".join(wet.slice(0, 12))])


## PoiKit.place and PoiKit.scatter move a land prop set down in the water to dry ground, or leave it
## out, on a made-up ground that is a river across the middle.
func test_a_cart_set_down_in_a_river_stands_on_its_bank() -> void:
	if provider == null:
		return
	# the Barkbridge's own spot, where the batch 3 cart stood in the river, if it is still wet here
	var e: Dictionary = {}
	for item in pois:
		if str((item as Dictionary).get("place_id", "")) == "core:poi/barkbridge":
			e = item
	if e.is_empty():
		return
	var pos: Array = e["pos"]
	var holder := Node3D.new()
	_host().add_child(holder)
	var kit := PoiKit.new(holder, Vector3(float(pos[0]), float(pos[1]), float(pos[2])), 25.0,
			"core:region/briarwold", false, "dry test", provider, roads)
	var cart := "res://assets/models/props/hearthvale_cart_b/hearthvale_cart_b.glb"
	var wet_at := Vector3.INF
	for i in 400:
		var a := TAU * float(i) / 40.0
		var r := 2.0 + float(i / 40) * 2.0
		var g := kit.on_ground(sin(a) * r, cos(a) * r)
		if kit.in_water(g):
			wet_at = g
			break
	assert_true(wet_at != Vector3.INF, "the river by the Barkbridge is in the water map")
	if wet_at == Vector3.INF:
		holder.free()
		return
	var put := kit.place(cart, wet_at, 0.0, 1.0, false)
	if put != null:
		assert_false(kit.in_water(put.position), "the cart moved out of the river")
		assert_true(put.position.distance_to(wet_at) <= PoiKit.DRY_SEARCH_M + 0.5, "to the nearest dry ground")
		put.free()
	var many := kit.scatter(cart, [Transform3D(Basis(), wet_at), Transform3D(Basis(), wet_at)])
	if many != null:
		assert_true(many.multimesh.instance_count <= 2)
		many.free()
	# and a thing of the water's own stays where it was put
	var basket := "res://assets/models/props/hearthvale_basket_a/hearthvale_basket_a.glb"
	var b := kit.place(basket, wet_at, 0.0, 1.0, false)
	if b != null:
		assert_true(b.position.is_equal_approx(wet_at), "a basket in the weir stays in it")
		b.free()
	holder.free()
