class_name QuestSpots
extends Node
## Where a story stands somebody who has no dressing of their own to stand at: a recruit waiting at
## the verge above a bandits' ditch, or on the far end of a bridge. A quest def may say
##   "spots": [{"name", "place", "bearing"?, "distance"?, "offset"?, "facing"?: compass bearing}]
## and each is an NpcSpot on the ground there (a PlaceRef spec), for the quest's `holds` and its
## people's npc defs to name. They are laid when the world's services are installed, all at once:
## a marker is a point, and there are a handful.
##
## A quest may also say
##   "props": [{"kind": "butt" | "brazier" | "sack" | "pell" | "strongbox", "name", <a PlaceRef spec>, "facing"?}]
## and each is a Pell of that kind stood on the ground there: the butts at Fernhold, the braziers on
## Gullhithe's harbour wall, things a start's lessons are struck, shot or lit on; and a `strongbox`
## (a locked WorldContainer: `lock_level`, `owner_faction`, `loot`, `label`) for a lock picked; and
## `cover` (a QuestCover: `look` crates | traps | boat) to be low behind.

const GROUP := "quest_spots"

var laid: Dictionary = {}          # spot name -> NpcSpot
var props: Dictionary = {}         # prop name -> Pell


static func ensure() -> QuestSpots:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var found := tree.get_first_node_in_group(GROUP)
	if found is QuestSpots:
		return found as QuestSpots
	var made := QuestSpots.new()
	made.name = "QuestSpots"
	var host: Node = tree.current_scene if tree.current_scene != null else tree.root
	host.add_child(made)
	return made


func _ready() -> void:
	add_to_group(GROUP)
	lay()


## Every quest's spots, stood on the ground (once each).
func lay() -> void:
	for def in ContentDB.all("quest"):
		for s_v in def.get("spots", []):
			if typeof(s_v) != TYPE_DICTIONARY:
				continue
			var s: Dictionary = s_v
			var spot_name := str(s.get("name", ""))
			if spot_name.is_empty() or laid.has(spot_name) or not PlaceRef.is_spec(s):
				continue
			var at := PlaceRef.point(s)
			if at == Vector3.INF:
				continue
			var m := NpcSpot.new()
			m.name = spot_name
			m.place_id = str(s.get("at_place", s.get("place", "")))
			add_child(m)
			m.global_position = at
			if s.has("facing"):
				m.rotation.y = -deg_to_rad(float(s["facing"]))
			laid[spot_name] = m
		for p_v in def.get("props", []):
			if typeof(p_v) != TYPE_DICTIONARY:
				continue
			var p: Dictionary = p_v
			var prop_name := str(p.get("name", ""))
			if prop_name.is_empty() or props.has(prop_name) or not PlaceRef.is_spec(p):
				continue
			var at := PlaceRef.point(p)
			if at == Vector3.INF:
				continue
			if str(p.get("kind", "")) == "strongbox":
				var box := _strongbox(prop_name, p)
				add_child(box)
				box.global_position = at
				box.rotation.y = -deg_to_rad(float(p.get("facing", 0.0)))
				props[prop_name] = box
				continue
			if str(p.get("kind", "")) == "cover":
				var cover := QuestCover.new()
				cover.name = prop_name
				cover.look = str(p.get("look", "crates"))
				add_child(cover)
				cover.global_position = at
				cover.rotation.y = -deg_to_rad(float(p.get("facing", 0.0)))
				props[prop_name] = cover
				continue
			var pell := Pell.new()
			pell.name = prop_name
			pell.kind = str(p.get("kind", "pell"))
			add_child(pell)
			pell.global_position = at
			# its face (the body's forward) turned to the compass bearing it faces
			pell.rotation.y = -deg_to_rad(float(p.get("facing", 0.0)))
			props[prop_name] = pell


## A locked iron-bound box (a quest prop of kind `strongbox`): a WorldContainer with its lock
## (`lock_level`), its owner (`owner_faction`), its contents (`loot`, a table) and its id from
## the prop's name, so it is the same box after a load; a body on the world layer so it is not
## walked through, and the container's own on the interaction layer.
static func _strongbox(prop_name: String, p: Dictionary) -> WorldContainer:
	var box := WorldContainer.new()
	box.name = prop_name
	box.container_id = "quest_prop/" + prop_name
	box.prop_kind = "strongbox"
	box.display_name = str(p.get("label", "Strongbox"))
	box.locked = true
	box.lock_level = int(p.get("lock_level", 1))
	box.owner_faction = str(p.get("owner_faction", ""))
	box.loot_table = str(p.get("loot", ""))
	var size := Vector3(0.8, 0.5, 0.5)
	var shape := CollisionShape3D.new()
	var form := BoxShape3D.new()
	form.size = size
	shape.shape = form
	shape.position.y = size.y * 0.5
	box.add_child(shape)
	var solid := StaticBody3D.new()
	solid.name = "Solid"
	solid.collision_layer = 1
	solid.collision_mask = 0
	var solid_shape := CollisionShape3D.new()
	solid_shape.shape = form
	solid_shape.position.y = size.y * 0.5
	solid.add_child(solid_shape)
	box.add_child(solid)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.33, 0.22, 0.14)
	wood.roughness = 0.85
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color(0.2, 0.19, 0.18)
	iron.metallic = 0.6
	iron.roughness = 0.5
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	body.mesh = bm
	body.material_override = wood
	body.position.y = size.y * 0.5
	box.add_child(body)
	for x in [-0.28, 0.28]:
		var band := MeshInstance3D.new()
		var band_mesh := BoxMesh.new()
		band_mesh.size = Vector3(0.06, size.y + 0.02, size.z + 0.02)
		band.mesh = band_mesh
		band.material_override = iron
		band.position = Vector3(float(x), size.y * 0.5, 0.0)
		box.add_child(band)
	var hasp := MeshInstance3D.new()
	var hasp_mesh := BoxMesh.new()
	hasp_mesh.size = Vector3(0.12, 0.14, 0.04)
	hasp.mesh = hasp_mesh
	hasp.material_override = iron
	hasp.position = Vector3(0.0, size.y * 0.7, size.z * 0.5 + 0.02)
	box.add_child(hasp)
	return box


## Where a spot this service laid stands, or Vector3.INF.
func position_of(spot_name: String) -> Vector3:
	var m: Variant = laid.get(spot_name, null)
	return (m as Node3D).global_position if m is Node3D and is_instance_valid(m) else Vector3.INF
