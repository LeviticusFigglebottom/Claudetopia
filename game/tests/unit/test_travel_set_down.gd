extends TestCase
## Everywhere the road goes, the body lands on its feet (triage 43: fast travel to any place found).
##
## A sweep over every entry of the built world's pois.json, which is every place and point of
## interest the road can go to: where TravelPlaces.set_down puts somebody is dry, on the ground
## or on what a dressing laid to be stood on (never a roof), not on a slope nobody stands on, and
## near the place, facing into it. Where a town stands, its fabric is raised and the engine's own
## physics is asked whether a body's capsule there overlaps anything the town put up; for a POI's
## own dressing test_pois.gd asks the same of every arrival
## (test_every_poi_sets_somebody_down_on_open_dry_ground).
##
## These read the built world (`./run.sh world`); when it is missing they say so and skip.

const GENERATED := "res://world/generated"
## A dressing may set you on something it laid to be stood on (a brow, a bank, a bridge's deck),
## never higher than this over the ground: a roof is higher.
const ON_THE_GROUND_M := 1.6

var provider: TerrainProvider = null
var roads: Array = []
var _scratch: Node3D = null


func before_each() -> void:
	if provider != null:
		return
	if not FileAccess.file_exists("%s/pois.json" % GENERATED):
		skip("world data missing: run ./run.sh world")
		return
	provider = TerrainProvider.new()
	provider.load_data()
	roads = WorldPois.roads_from_disk()


func _host() -> Node3D:
	if _scratch == null or not is_instance_valid(_scratch):
		_scratch = Node3D.new()
		_scratch.name = "TravelTestScratch"
		(Engine.get_main_loop() as SceneTree).root.add_child(_scratch)
	return _scratch


func test_every_place_and_poi_sets_you_down_dry_and_on_your_feet() -> void:
	if provider == null:
		return
	var bad: Array[String] = []
	var ways := {}
	for id_v in TravelPlaces.entries():
		var id := str(id_v)
		var down := TravelPlaces.set_down(id, provider, roads)
		if down.is_empty():
			bad.append("%s: nowhere" % id)
			continue
		var at: Vector3 = down["at"]
		var how := str(down.get("how", ""))
		ways[how] = int(ways.get(how, 0)) + 1
		var ground := provider.get_height(at.x, at.z)
		var name := Ids.name_of(id)
		if how == "centre":
			bad.append("%s: nowhere open, set down at its middle" % name)
		if TravelPlaces.is_wet(at, provider):
			bad.append("%s: in water at %s" % [name, str(at.round())])
		if at.y > ground + ON_THE_GROUND_M:
			bad.append("%s: %.1f m over the ground (a roof?)" % [name, at.y - ground])
		if at.y < ground - 0.3:
			bad.append("%s: %.1f m under the ground" % [name, ground - at.y])
		if absf(at.y - ground) < 0.5 and TravelPlaces.is_steep(at, provider):
			bad.append("%s: on a slope" % name)
		if not TravelPlaces.open_ground(at, id, provider):
			bad.append("%s: in a landmark's footprint or a deep place's mouth" % name)
		var c := TravelPlaces.centre_of(id)
		var r := float(TravelPlaces.entries()[id].get("radius_flat_m", 25.0))
		var off := Vector2(at.x - c.x, at.z - c.z).length()
		if off > r + TravelPlaces.SHORE_OUT_M + 1.0:
			bad.append("%s: %.0f m from its middle" % [name, off])
	Log.info("TravelTest", "set-downs: %s" % str(ways))
	assert_gt(TravelPlaces.entries().size(), 400, "every place and POI was asked (%d)" % TravelPlaces.entries().size())
	assert_true(bad.is_empty(), "%d bad set-downs: %s" % [bad.size(), "; ".join(bad.slice(0, 20))])


## A town's fabric is raised where the world raises it (WorldDoors: its roads, its pad) and a body's
## capsule where the road sets you down overlaps none of it: not a house, a wall, a fence, a stall.
func test_no_town_sets_you_down_inside_what_it_built() -> void:
	if provider == null:
		return
	var shut: Array[String] = []
	var checked := 0
	var capsule := CapsuleShape3D.new()
	capsule.radius = PoiDressing.ARRIVAL_RADIUS_M
	capsule.height = PoiDressing.ARRIVAL_HEIGHT_M
	for place in ContentDB.all("place"):
		var id := str(place.get("id", ""))
		var kind := str(place.get("kind", ""))
		if not Settlement.FABRIC.has(kind) or not TravelPlaces.has(id):
			continue
		var entry: Dictionary = TravelPlaces.entries()[id]
		var centre := TravelPlaces.centre_of(id)
		var radius := WorldDoors.pad_radius_of(entry)
		var near: Array = []
		for line in roads:
			if WorldDoors._touches(line, centre, radius):
				near.append(line)
		var s := Settlement.raise_at(id, kind, str(place.get("region", "")), centre, radius, near, [])
		_host().add_child(s)
		await (Engine.get_main_loop() as SceneTree).physics_frame
		await (Engine.get_main_loop() as SceneTree).physics_frame
		var at: Vector3 = TravelPlaces.set_down(id, provider, roads)["at"]
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = capsule
		q.transform = Transform3D(Basis(), at + Vector3(0.0, 0.08 + PoiDressing.ARRIVAL_HEIGHT_M * 0.5, 0.0))
		var hits := s.get_world_3d().direct_space_state.intersect_shape(q, 4)
		if not hits.is_empty():
			shut.append("%s (%s)" % [Ids.name_of(id), str((hits[0]["collider"] as Node).name)])
		checked += 1
		_host().remove_child(s)
		s.free()
	assert_gt(checked, 30, "every town, village, hamlet, fort and lodge was raised (%d)" % checked)
	assert_true(shut.is_empty(), "set down inside what a town built: %s" % ", ".join(shut))
