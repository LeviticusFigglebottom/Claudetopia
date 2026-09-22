extends TestCase
## The people the points of interest's sentences name, standing where the sentences put them.
##
## The lamplighter of the Lantern Causeway, the toll-keeper of the Chain Bridge, the knight in the
## Headless Watch's eye and the hermit of Willow Isle were named in the registry and absent, their
## props set out as if somebody had just stepped away; Ansel's shrine promised a pilgrim, the
## Charcoal Camp a merchant and a job board, and Ryn Larkbourne's schedule put him at a spot in
## Merrowby called "gosling_pit" that nothing there was named. They are ordinary people of the
## registry now, so they are in the `npcs` save section like anybody, and these check they are
## stood up once, where they work, and not twice after a load.

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
	var merchant: Variant = ContentDB.get_or_empty("core:npc/sorrel_rooke").get("merchant")
	assert_true(typeof(merchant) == TYPE_DICTIONARY and ContentDB.has(str((merchant as Dictionary).get("stock", ""))),
			"the burners sell what the clamps make")


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
