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
## The builders are reached by path at runtime, not by their class name.
##
## Every builder takes a `PoiDressing`, so naming `PoiBuilders` here makes the two scripts
## name each other, and GDScript cannot always resolve that: it parses whichever it reaches
## first, fails on the half-built other, and reports "Could not resolve class PoiBuilders,
## because of a parser error" — against `test_pois.gd`, which merely mentions both. It only
## bites once an import has rebuilt the global class cache, so the tests pass when run
## directly and the whole suite fails after `./run.sh test` imports. Loading by path leaves
## the dependency one-way and the cycle gone.
const BUILDERS_PATH := "res://world/pois/poi_builders.gd"

## Every kind a POI can be, and whether the thing built is something you can bump into. A kind
## missing here is a POI that stays a flattened pad, and `test_pois.gd` fails on it.
const KINDS := {
	"camp": true, "shrine": true, "tower": true, "bridge": true, "waterfall": true,
	"ruins": true, "strange_tree": true, "wreck": true, "strange": false, "giant_bones": true,
	"standing_stones": true, "hidden_valley": true,
	## the Hearthstone a settlement or landmark keeps, for a place tagged `shrine`
	"hearth": true,
	## the kinds the drawn map asked for next (docs/ATLAS.md, section 10): a mouth in a slope, the
	## worked land out between the villages, and the marks along a road
	"cave": true, "farmstead": true, "mill": true, "waystone": true, "market_field": true,
	"quarry": true, "shieling": true, "vista": true,
	## the wayside finds the gap map asks for, where a road runs a minute and more past nothing:
	## a cairn, a tally post, a grave, a gibbet, a fold, a well, a lantern post
	"cairn": true, "tally_post": true, "grave": true, "gibbet": true, "fold": true, "well": true,
	"lantern_post": true, "hut": true, "crossroads": true, "peat_cut": true, "beacon": true,
}

## The kinds a builder exists for. `KINDS` above is the whole list the design names; the
## difference is what is still to be dressed, and `test_pois.gd` prints it rather than hiding
## it. It lives here rather than on the builders because that script has no global name (see
## `poi_builders.gd`), and this is the type everything else already speaks to.
const KINDS_BUILT := ["camp", "shrine", "hearth", "tower", "bridge", "waterfall", "ruins",
		"giant_bones", "strange_tree", "wreck", "hidden_valley", "standing_stones", "strange",
		"cave", "farmstead", "mill", "waystone", "market_field", "quarry", "shieling", "vista",
		"cairn", "tally_post", "grave", "gibbet", "fold", "well", "lantern_post", "hut", "crossroads", "peat_cut",
		"beacon"]

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
## Ground some foes will not cross, from the def's `ward` ({radius_m, keeps_off}): Wards.
var ward: Dictionary = {}
## A way marked on the ground from here to somewhere else: `{to: place id, via: [[x, z], ...]}`
## in world coordinates, the walk the POI's builder lays markers along (the Stair Head's cairns
## to the Choir). Empty for nearly everything.
var path: Dictionary = {}
## Where the land is stepped for a waterfall, from its `pois.json` entry (docs/CONTRACTS.md
## section 6): {facing_deg, foot_m, top_m, form, river, faces: [{behind_m, drop_m}]}. Empty where
## the world has no step there, and a fall then makes its own facing and its own hill.
var fall: Dictionary = {}
## How far out the pad is level (`radius_level_m`): a stepped fall's face runs as wide as that.
var level_radius := 17.5
## Where a stepped fall's river falls are read from (rivers.json's `falls`); a test points it at
## its own file.
static var rivers_path := "res://world/generated/rivers.json"

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
	d.level_radius = float(entry.get("radius_level_m", d.pad_radius * 0.7))
	var step: Variant = entry.get("fall", {})
	d.fall = (step as Dictionary).duplicate(true) if typeof(step) == TYPE_DICTIONARY else {}
	var pos: Array = entry.get("pos", [0.0, 0.0, 0.0])
	d.world_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	d.position = d.world_position
	d.far = silhouette
	d.wants_hearthstone = bool(def.get("hearthstone", false)) or d.kind == "hearth"
	d.ward = def.get("ward", {})
	var way: Variant = def.get("path", {})
	d.path = (way as Dictionary).duplicate(true) if typeof(way) == TYPE_DICTIONARY else {}
	if d.path.has("to"):
		var via: Array = []
		for p in way_points(d.poi_id, def):
			via.append([p.x, p.y])
		if not via.is_empty():
			d.path["via"] = via
	d.name = "Poi_" + Ids.name_of(d.poi_id)
	d._provider = terrain
	d._roads = roads
	return d


## The points a POI's `path` passes on today's map. Where the built world has a road between the
## POI and the place its way leads to, the way is that road: the builder routes a road round a
## hill rather than over it, and a way drawn straight between the same points on the atlas world
## crossed ground of 37 to 61 degrees. Otherwise it is the way's `shape` between its two ends, so
## it follows them when the map is redrawn (`PlaceRef.along`, tools/place_paths.py); a `via` of
## bare coordinates is still read, and stays where it is. `follow_roads` false asks for the
## drawn way whatever is built.
static func way_points(poi_id: String, def: Dictionary, follow_roads := true) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var way: Variant = def.get("path", {})
	if typeof(way) != TYPE_DICTIONARY:
		return out
	var to := str((way as Dictionary).get("to", ""))
	if follow_roads and to != "":
		var road := WorldPois.road_between(poi_id, to, str((way as Dictionary).get("built_road", "")))
		if road.size() >= 2:
			return road
	var shape: Variant = (way as Dictionary).get("shape", null)
	if typeof(shape) == TYPE_ARRAY:
		return PlaceRef.along(poi_id, to, shape)
	for p in (way as Dictionary).get("via", []):
		if typeof(p) == TYPE_ARRAY and (p as Array).size() >= 2:
			out.append(Vector2(float(p[0]), float(p[1])))
	return out


## A POI's kind is its own; a place is dressed only for the Hearthstone its `shrine` tag
## promises (the main quest rests at three of them and nothing stood at any), or when its data
## names a `dressing` kind: the Standing Moot is a place, not a registry POI, and the main quest
## fights the Hart of Thorns among stones that nothing had stood there.
static func kind_of(id: String, def: Dictionary) -> String:
	if id.begins_with("core:poi/") or Ids.type_of(id) == "poi":
		return str(def.get("kind", ""))
	if str(def.get("dressing", "")) != "":
		return str(def["dressing"])
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
	var builders: GDScript = load(BUILDERS_PATH)
	if builders == null:
		Log.error("PoiDressing", "%s: the builders did not load from %s" % [poi_id, BUILDERS_PATH])
		return
	builders.build(self)
	if kind == "waterfall" and not far:
		# a fall no river draws: its water drawn as the rivers' falls are, over the dressing's rock
		RiverFalls.dress_place(self)
	if not far and not ward.is_empty():
		Wards.add(self, world_position, float(ward.get("radius_m", 8.0)), ward.get("keeps_off", []))
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


## Real lights standing in this dressing. None, now: its fires and lamps are sources for
## NightLights, which lights the nearest of them from one pool (`light_sources()` lists them).
func lights() -> Array:
	return find_children("*", "OmniLight3D", true, false)


## The fires and lamps this dressing registered with NightLights: [position, kind, colour,
## energy, range] each.
func light_sources() -> Array:
	return NightLights.sources_of(self)


## A flat description of everything standing here, for comparing two raisings of one POI.
## A node Godot had to name itself (`@Node3D@1034`) carries a counter that is never the same
## twice, so those are described by class alone; what is compared is what stands where.
func signature() -> Array:
	var out: Array = []
	for node in find_children("*", "", true, false):
		if node is Node3D:
			var n3 := node as Node3D
			var label := n3.get_class() if n3.name.begins_with("@") else str(n3.name)
			out.append("%s@%s" % [label, str(n3.position.snapped(Vector3.ONE * 0.001))])
	# its fires and lamps stand here too, though they are sources for NightLights and no longer
	# nodes of their own
	for s in light_sources():
		out.append("light@%s" % str(to_local(s[0]).snapped(Vector3.ONE * 0.001)))
	return out
