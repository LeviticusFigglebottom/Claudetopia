class_name PoiDressing
extends Node3D
## What stands at a point of interest.
##
## The world builder flattens a pad for every POI and writes its position to `pois.json`;
## nothing else is baked. What the player finds there — a camp's fire ring and tents, a
## shrine's stone and its Hearthstone, a tower, a bridge over the water, a ribcage to walk
## through — is raised here at runtime, the way `Settlement` raises a town: deterministically
## from the POI's id, from the forge's own assets, on the ground the world actually has, with
## the POI's `unique_feature` as the brief the builder answers.
##
## One builder per kind lives in `PoiBuilders`. The dressing is parented to its cell by
## `WorldPois` when the streamer loads that cell, so it streams and unloads with the ring
## system; in the far ring only the silhouette pieces are built.

const GROUP := "poi_dressing"

## Every kind a POI can be, and whether the thing built is something you can bump into. A kind
## missing here is a POI that stays a flattened pad, and `test_pois.gd` fails on it.
const KINDS := {
	"camp": true, "shrine": true, "tower": true, "bridge": true, "waterfall": true,
	"ruins": true, "strange_tree": true, "wreck": true, "strange": false, "giant_bones": true,
	"standing_stones": true, "hidden_valley": true,
	## the Hearthstone a settlement or landmark keeps, for a place tagged `shrine`
	"hearth": true,
}

var poi_id := ""
var kind := ""
var region := ""
var display_name := ""
var brief := ""
var encounter := ""
var pad_radius := 25.0
var far := false
## Where in the world this stands; `position` is relative to whatever cell node holds it.
var world_position := Vector3.ZERO
var wants_hearthstone := false

var kit: PoiKit = null
var masonry: PoiMasonry = null
var built := false

var _provider: TerrainProvider = null
var _roads: Array = []


## A dressing for one `pois.json` entry and the content def behind it. Nothing is built until
## it enters the tree. `far` builds the silhouette only. `terrain` and `roads` let a headless
## test hand over real ground and roads; the world's own are used otherwise.
static func raise(entry: Dictionary, def: Dictionary, silhouette := false,
		terrain: TerrainProvider = null, roads: Array = []) -> PoiDressing:
	var d := PoiDressing.new()
	d.poi_id = str(entry.get("place_id", def.get("id", "")))
	d.kind = kind_of(d.poi_id, def)
	d.region = str(def.get("region", ""))
	d.display_name = str(def.get("name", Ids.name_of(d.poi_id).capitalize()))
	d.brief = str(def.get("unique_feature", ""))
	d.encounter = str(def.get("encounter", ""))
	d.pad_radius = float(entry.get("radius_flat_m", 25.0))
	var pos: Array = entry.get("pos", [0.0, 0.0, 0.0])
	d.world_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	d.position = d.world_position
	d.far = silhouette
	d.wants_hearthstone = bool(def.get("hearthstone", false)) or d.kind == "hearth"
	d.name = "Poi_" + Ids.name_of(d.poi_id)
	d._provider = terrain
	d._roads = roads
	return d


## A POI's kind is its own; a place is dressed only for the Hearthstone its `shrine` tag
## promises (the main quest rests at three of them and nothing stood at any).
static func kind_of(id: String, def: Dictionary) -> String:
	if id.begins_with("core:poi/") or Ids.type_of(id) == "poi":
		return str(def.get("kind", ""))
	var tags: Variant = def.get("tags", [])
	if typeof(tags) == TYPE_ARRAY and (tags as Array).has("shrine"):
		return "hearth"
	return ""


## Whether anything would be raised for this entry at all.
static func dressable(id: String, def: Dictionary) -> bool:
	return KINDS.has(kind_of(id, def))


func _ready() -> void:
	add_to_group(GROUP)
	build()


func build() -> void:
	if built:
		return
	built = true
	kit = PoiKit.new(self, world_position, pad_radius, region, far, poi_id, _provider, _roads)
	masonry = PoiMasonry.new(kit)
	PoiBuilders.build(self)
	if wants_hearthstone and not far and hearthstones().is_empty():
		# a builder that did not find a better place for the stone gets the plain one: at the
		# pad's centre, off the exact middle so nothing spawning there stands inside it
		var g := kit.grain()
		kit.hearthstone(kit.on_ground(g.x * 3.0, g.y * 3.0), PoiKit.yaw_of(g) + PI, poi_id, display_name)


# --- what got built, for the tests and the tools ------------------------------------------------

func mesh_count() -> int:
	var n := 0
	for node in find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).mesh != null:
			n += 1
	for node in find_children("*", "MultiMeshInstance3D", true, false):
		var mm := (node as MultiMeshInstance3D).multimesh
		if mm != null and mm.instance_count > 0:
			n += 1
	return n


func body_count() -> int:
	var n := 0
	for node in find_children("*", "StaticBody3D", true, false):
		if node is Hearthstone:
			continue
		if not (node as Node).find_children("*", "CollisionShape3D", true, false).is_empty():
			n += 1
	return n


func hearthstones() -> Array:
	return find_children("*", "Hearthstone", true, false)


func lights() -> Array:
	return find_children("*", "OmniLight3D", true, false)


## A flat description of everything standing here, for comparing two raisings of one POI.
func signature() -> Array:
	var out: Array = []
	for node in find_children("*", "", true, false):
		if node is Node3D:
			var n3 := node as Node3D
			out.append("%s@%s" % [n3.name, str(n3.position.snapped(Vector3.ONE * 0.001))])
	return out
