extends TestCase
## The people the points of interest's sentences name, standing where the sentences put them.
##
## The lamplighter of the Lantern Causeway, the toll-keeper of the Chain Bridge, the knight in the
## Headless Watch's eye and the hermit of Willow Isle were named in the registry and absent, their
## props set out as if somebody had just stepped away; Ansel's shrine promised a pilgrim, the
## Charcoal Camp a merchant and a job board, and Ryn Larkbourne's schedule put him at a spot in
## Merrowby called "gosling_pit" that nothing there was named. The places' stories named more: the
## hedge-witch Tansy Cresswell at Foxglove Dell (a name in the names index and nobody in the
## world), the gate-warden who takes a toll at Windgate, and the Sayers' camp that digs at the
## Thirteenth and argues. They are ordinary people of the registry now, so they are in the `npcs`
## save section like anybody, and these check they are stood up once, where they work, and not
## twice after a load.

const GENERATED := "res://world/generated"
const POI_PEOPLE := {
	"core:npc/lissane_sa": "core:poi/lantern_causeway",
	"core:npc/khath_ko_rudd": "core:poi/chain_bridge",
	"core:npc/calen_ash": "core:poi/headless_watch",
	"core:npc/ivo_goslin": "core:poi/willow_isle",
	"core:npc/marigold_orchard": "core:poi/hedge_shrine_of_ansel",
	"core:npc/sorrel_rooke": "core:poi/charcoal_camp",
	"core:npc/barnaby_rooke": "core:poi/charcoal_camp",
	"core:npc/wardens_ryn": "core:poi/gosling_pit",
	"core:npc/tansy_cresswell": "core:poi/foxglove_dell",
	"core:npc/ruska_ko_dreugh": "core:poi/watch_of_the_gate",
	"core:npc/gisel_morneth": "core:poi/thirteenth_colossus",
	"core:npc/wennick_anthar": "core:poi/thirteenth_colossus",
	"core:npc/arn_sweeting": "core:poi/sweepers_lean_to",
	"core:npc/nell_hurdlegate": "core:poi/hurdlegate_farm",
	"core:npc/aud_brow_end": "core:poi/brow_end_farm",
	"core:npc/tam_hatchmoor": "core:poi/hatchmoor_farm",
	"core:npc/joss_coldharbour": "core:poi/coldharbour_farm",
	"core:npc/bessa_pennywort": "core:poi/pennywort_fields",
	"core:npc/rab_ashway": "core:poi/ashway_farm",
	"core:npc/maud_rookwell": "core:poi/grey_end_farm",
	"core:npc/hesta_southgate": "core:poi/southgate_farm",
	"core:npc/wil_ridgeway": "core:poi/ridgeway_farm",
	"core:npc/ebb_fallowgate": "core:poi/fallowgate_farm",
	"core:npc/corran_larkfield": "core:poi/larkfield_farm",
	"core:npc/wat_hazel": "core:poi/hazel_bottom_farm",
	"core:npc/ossie_cress": "core:poi/cress_mill",
	"core:npc/jenet_lark": "core:poi/lark_mill",
	"core:npc/gurd_ko_skarl": "core:poi/skarl_mill",
	"core:npc/brann_of_ruddow": "core:poi/rudd_mill",
}

var host: Node3D
var provider: TerrainProvider = null
var pois: Array = []
var registry: NpcRegistry
static var _warned := false


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	host = Node3D.new()
	host.name = "PoiPeopleTestHost"
	_tree().root.add_child(host)
	if provider == null and FileAccess.file_exists("%s/pois.json" % GENERATED):
		provider = TerrainProvider.new()
		provider.load_data()
		pois = JSON.parse_string(FileAccess.get_file_as_string("%s/pois.json" % GENERATED))
	elif provider == null and not _warned:
		_warned = true
		print("  (world data missing: run ./run.sh world; the standing cases skip)")
	registry = NpcRegistry.ensure()
	registry.despawn_all()
	registry.loaded_cells.clear()
	registry.states.clear()
	registry.rebuild()
	var streamer := _tree().get_first_node_in_group(NpcStreamer.GROUP)
	if streamer != null:
		streamer.set("enabled", false)
	WorldClock.set_time(12.0, 2)
	registry.simulate_all("clear")


func after_each() -> void:
	registry.despawn_all()
	registry.loaded_cells.clear()
	registry.states.clear()
	registry.rebuild()
	_tree().root.remove_child(host)
	host.free()
	WorldClock.set_time(9.0, 2)


func _dress(place_id: String) -> PoiDressing:
	var wp := WorldPois.new()
	wp.encounters = false
	host.add_child(wp)
	wp.index(pois, provider, WorldPois.roads_from_disk())
	var entry: Dictionary = {}
	for e in pois:
		if str((e as Dictionary).get("place_id", "")) == place_id:
			entry = e
	if entry.is_empty():
		return null
	var at := Vector3(float(entry["pos"][0]), float(entry["pos"][1]), float(entry["pos"][2]))
	var parent := Node3D.new()
	var cell := wp.cell_of(at)
	parent.name = "Cell_%d_%d" % [cell.x, cell.y]
	host.add_child(parent)
	for d in wp.raise_in_cell(parent, cell, false):
		if d.poi_id == place_id:
			return d
	return null


## The bodies standing for this person, not counting any on their way out of the tree.
func _bodies_of(npc_id: String) -> Array[Node]:
	var out: Array[Node] = []
	for n in _tree().get_nodes_in_group("npc"):
		if str(n.get("npc_id")) == npc_id and not n.is_queued_for_deletion():
			out.append(n)
	return out


# --- who, and where --------------------------------------------------------------------------------------

func test_every_person_a_sentence_names_lives_at_that_point_of_interest() -> void:
	for id in POI_PEOPLE:
		var def := ContentDB.get_or_empty(str(id))
		assert_false(def.is_empty(), "%s is nobody" % id)
		assert_true(ContentDB.has(str(def.get("dialogue", ""))), "%s has nothing to say" % id)
		var here := false
		for e in def.get("schedule", []):
			here = here or str((e as Dictionary).get("place", "")) == str(POI_PEOPLE[id])
		assert_true(here, "%s is never at %s" % [id, POI_PEOPLE[id]])
	for seller in ["core:npc/sorrel_rooke", "core:npc/tansy_cresswell"]:
		var merchant: Variant = ContentDB.get_or_empty(seller).get("merchant")
		assert_true(typeof(merchant) == TYPE_DICTIONARY and ContentDB.has(str((merchant as Dictionary).get("stock", ""))),
				"%s sells what the place makes" % seller)


## A body stands exactly on its marker, so two people working one marker at one hour stand inside
## each other: the Sayers' second chair was first put on his colleague's spot at the dig. A town's
## market square on market day is not one of these: the farmers come in to it from all round, and
## a settlement's square is a gathering marker that stands everybody sent to it round it.
func test_no_two_people_work_one_marker_at_once() -> void:
	for day in 7:
		for half in 48:
			var hour := float(half) * 0.5 + 0.25
			var taken: Dictionary = {}
			for id in POI_PEOPLE:
				var entry := Schedules.entry_for_def(ContentDB.get_or_empty(str(id)), day, hour)
				if bool(entry.get("indoors", false)) or str(entry.get("spot", "")) == "":
					continue
				if Ids.type_of(str(entry.get("place", ""))) != "poi":
					continue
				var key := "%s|%s" % [entry.get("place", ""), entry.get("spot", "")]
				assert_false(taken.has(key), "%s and %s both stand at '%s' at %.2f on day %d" % [taken.get(key, ""), id,
						entry.get("spot", ""), hour, day])
				taken[key] = id


## The dig is the Sayers' by day and the choristers' after dark, and the dell's boars root at dawn
## while the hedge-witch is asleep: the people these places' stories put there are under a roof in
## every hour their place's sentence stands something hostile in the open.
func test_nobody_is_out_while_their_place_stands_its_foes_up() -> void:
	for id in ["core:npc/tansy_cresswell", "core:npc/gisel_morneth", "core:npc/wennick_anthar"]:
		var def := ContentDB.get_or_empty(id)
		var place := str(def.get("home_place", ""))
		var groups := PoiEncounters.of(place)
		assert_false(groups.is_empty(), "%s: %s stands nothing up to keep out of the way of" % [id, place])
		var out_hours := 0
		for day in 7:
			for half in 48:
				var hour := float(half) * 0.5 + 0.25
				var entry := Schedules.entry_for_def(def, day, hour)
				if bool(entry.get("indoors", false)) or str(entry.get("place", "")) != place:
					continue
				out_hours += 1
				for g in groups:
					var group: Dictionary = g
					assert_false(PoiEncounters.is_open(str(group.get("when", "always")), hour),
							"%s is out at '%s' at %.2f on day %d while %s stand at %s" % [id, entry.get("spot", ""), hour,
							day, group.get("enemy", ""), place])
		assert_gt(out_hours, 0, "%s is never out at %s at all" % [id, place])


func test_every_spot_they_work_is_a_marker_their_place_puts_down() -> void:
	if provider == null:
		return
	for id in POI_PEOPLE:
		var place := str(POI_PEOPLE[id])
		var d := _dress(place)
		assert_true(d != null, "%s has no pad in the built world" % place)
		if d == null:
			continue
		for e in ContentDB.get_or_empty(str(id)).get("schedule", []):
			var entry: Dictionary = e
			if str(entry.get("place", "")) != place or Schedules.is_indoors(entry):
				continue
			var spot := str(entry.get("spot", ""))
			var marker := d.find_child(spot, true, false)
			assert_true(marker is Node3D, "%s works at '%s' and %s's dressing puts no such marker down" % [id, spot, place])
			if marker != null:
				assert_true(marker.is_in_group(NpcRegistry.SPOT_GROUP), "'%s' at %s is not somewhere a person stands" % [spot, place])
				assert_eq(str(marker.get_meta("place", "")), place, "and it says whose place it is in")


## A body stands exactly where its marker is, so nothing solid may be there. The Sayers' first camp
## at the Thirteenth stood inside the carving (the finds table in the colossus's shoulders, a tent in
## its arm), and a snow drift at Windgate runs over the brazier by the toll-house door.
func test_nobody_is_stood_inside_anything() -> void:
	if provider == null:
		return
	var person := CapsuleShape3D.new()
	person.radius = 0.3
	person.height = 1.6
	var places: Dictionary = {}
	for id in POI_PEOPLE:
		places[str(POI_PEOPLE[id])] = true
	var looked := 0
	for place in places:
		var d := _dress(str(place))
		if d == null:
			continue
		for i in 2:
			await _tree().physics_frame
		var space := d.get_world_3d().direct_space_state
		for n in d.find_children("*", "Marker3D", true, false):
			if not n.is_in_group(NpcRegistry.SPOT_GROUP):
				continue
			looked += 1
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = person
			q.collision_mask = 1 << 0
			q.transform = Transform3D(Basis.IDENTITY, (n as Node3D).global_position + Vector3(0.0, 0.95, 0.0))
			var what: Array[String] = []
			for hit in space.intersect_shape(q, 4):
				var thing: Variant = (hit as Dictionary).get("collider")
				what.append(str((thing as Node).get_path()) if thing is Node else "something")
			assert_true(what.is_empty(), "%s: whoever works at '%s' stands inside %s" % [place, n.name, ", ".join(what)])
		if str(place) == "core:poi/thirteenth_colossus":
			# and the check can see: a person stood at the colossus's hips is inside its back
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = person
			q.collision_mask = 1 << 0
			q.transform = Transform3D(Basis.IDENTITY, d.to_global(Vector3(0.0, 1.8, 0.0)))
			assert_false(space.intersect_shape(q, 1).is_empty(), "a person inside the carving is seen to be inside something")
	assert_gt(looked, 10, "the people's places put their markers down")


## Everyone stands on their own marker at every hour they work, not on the ring round the place's
## middle that a person without one is given: a marker the dressing names and the registry cannot
## find fails quietly, and on an island, a causeway or a dig that ring is water, lake bed or
## colossus.
func test_everyone_stands_on_their_marker_at_every_hour_they_work() -> void:
	if provider == null:
		return
	var dressed: Dictionary = {}
	var stood := 0
	for id in POI_PEOPLE:
		var place := str(POI_PEOPLE[id])
		if not dressed.has(place):
			dressed[place] = _dress(place)
		var d: PoiDressing = dressed[place]
		if d == null:
			continue
		for e in ContentDB.get_or_empty(str(id)).get("schedule", []):
			var entry: Dictionary = e
			if str(entry.get("place", "")) != place or Schedules.is_indoors(entry):
				continue
			var day := -1
			for candidate in 7:
				if day < 0 and Schedules.applies_on(entry.get("days", "all"), Schedules.weekday_of(candidate)):
					day = candidate
			assert_true(day >= 0, "%s works '%s' on no day at all" % [id, entry.get("spot", "")])
			if day < 0:
				continue
			WorldClock.set_time(float(entry.get("hour", 0)) + 0.25, day)
			registry.simulate_all("clear")
			registry.despawn(str(id))
			registry.loaded_cells[registry.cell_of(str(id))] = true
			var body := registry.spawn(str(id)) as Node3D
			var marker := d.find_child(str(entry.get("spot", "")), true, false) as Node3D
			assert_true(body != null and marker != null, "%s is stood up at '%s'" % [id, entry.get("spot", "")])
			if body == null or marker == null:
				continue
			var flat := Vector2(body.global_position.x - marker.global_position.x, body.global_position.z - marker.global_position.z)
			assert_true(flat.length() < 0.5, "%s at %.2f stands %.1f m from '%s'" % [id, float(entry.get("hour", 0)) + 0.25,
					flat.length(), entry.get("spot", "")])
			stood += 1
			registry.despawn(str(id))
	assert_gt(stood, 12, "every working hour of every one of them was stood")


func test_the_charcoal_camp_posts_its_work() -> void:
	if provider == null:
		return
	var d := _dress("core:poi/charcoal_camp")
	var boards := d.find_children("*", "JobBoard", true, false)
	assert_eq(boards.size(), 1, "a safe camp with a job board")
	if not boards.is_empty():
		assert_eq((boards[0] as JobBoard).place_id, "core:poi/charcoal_camp", "and its notices are the camp's own")
		assert_eq((boards[0] as JobBoard).collision_layer, JobBoard.INTERACT_LAYER, "and it can be walked up to")


func test_the_hermit_stands_at_his_stool_on_the_isle_not_on_the_lake_bed() -> void:
	if provider == null:
		return
	var d := _dress("core:poi/willow_isle")
	var stool := d.find_child("the_hermits_stool", true, false) as Node3D
	assert_true(stool != null)
	if stool == null:
		return
	registry.loaded_cells[registry.cell_of("core:npc/ivo_goslin")] = true
	var body := registry.spawn("core:npc/ivo_goslin") as Node3D
	assert_true(body != null, "Ivo is stood up at noon")
	if body == null:
		return
	var flat := Vector2(body.global_position.x - stool.global_position.x, body.global_position.z - stool.global_position.z)
	assert_true(flat.length() < 0.5, "at his stool (%.1f m off)" % flat.length())
	assert_true(absf(body.global_position.y - stool.global_position.y) < 0.6, "on the isle's crown, not under it")


# --- saved, and not doubled ------------------------------------------------------------------------------

func test_the_people_of_the_points_of_interest_are_saved_and_stand_once_after_a_load() -> void:
	var ivo := "core:npc/ivo_goslin"
	var lissane := "core:npc/lissane_sa"
	var cell := registry.cell_of(ivo)
	registry._on_cell_loaded(cell)
	assert_eq(_bodies_of(ivo).size(), 1, "the cell comes in and Ivo is stood up")
	# the cell comes round again without going: nobody is stood up a second time
	registry._on_cell_loaded(cell)
	assert_eq(_bodies_of(ivo).size(), 1, "and not twice")
	registry.kill(lissane)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(registry.to_save()))
	var states: Dictionary = saved.get("states", {})
	for id in POI_PEOPLE:
		assert_true(states.has(str(id)), "%s is in the npcs save section" % id)
	assert_eq(str((states[ivo] as Dictionary).get("place", "")), "core:poi/willow_isle", "where he is is saved")
	# a load: the section goes back in over a registry that already has him standing
	registry.from_save(saved)
	await _tree().process_frame
	assert_eq(_bodies_of(ivo).size(), 1, "a load stands him up once, not once more beside himself")
	assert_false(registry.is_alive(lissane), "and whoever died is still dead")
	registry._on_cell_loaded(registry.cell_of(lissane))
	assert_empty(_bodies_of(lissane), "and is not stood up when her cell comes in")
	# and a fresh registry reading the same section, as a game started from the menu does
	registry.despawn_all()
	registry.states.clear()
	registry.from_save(saved)
	await _tree().process_frame
	assert_eq(_bodies_of(ivo).size(), 1, "loaded from nothing, still one of him")
	assert_false(registry.is_alive(lissane))
