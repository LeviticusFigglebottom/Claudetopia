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
##   "props": [{"kind": "butt" | "brazier" | "pell", "name", <a PlaceRef spec>, "facing"?}]
## and each is a Pell of that kind stood on the ground there: the butts at Fernhold, the braziers on
## Gullhithe's harbour wall, things a start's lessons are struck, shot or lit on.

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
			var pell := Pell.new()
			pell.name = prop_name
			pell.kind = str(p.get("kind", "pell"))
			add_child(pell)
			pell.global_position = at
			# its face (the body's forward) turned to the compass bearing it faces
			pell.rotation.y = -deg_to_rad(float(p.get("facing", 0.0)))
			props[prop_name] = pell


## Where a spot this service laid stands, or Vector3.INF.
func position_of(spot_name: String) -> Vector3:
	var m: Variant = laid.get(spot_name, null)
	return (m as Node3D).global_position if m is Node3D and is_instance_valid(m) else Vector3.INF
