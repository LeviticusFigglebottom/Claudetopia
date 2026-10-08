class_name PlaceDiscovery
extends Node
## Finding places by going to them, and filling the chart by looking out from high ground.
##
## DESIGN §5.16: "Compass shows cardinal points, discovered locations only… Map is a painted,
## partially revealed chart: you fill it by looking from high places (surveying at vistas) and
## by buying charts." The map screen has always drawn both — fog lifts a little around a
## discovered place and much further around a surveyed one — and the compass has always drawn
## discovered places only.
##
## Neither had a way to happen. `GameState.discover()` was called by a dialogue effect and by
## resting at a Hearthstone, and by nothing else: you could walk the length of the country and
## arrive at Tollmere with a blank chart, because the only way to learn a place existed was for
## somebody to tell you about it. `surveyed:<place>` was set by nothing at all outside the UI
## review's fake save, so the map's larger reveal had never once been drawn in play. And the 48
## POIs each carry a `visible_from` list — 96 authored sightlines, the composition rule from
## DESIGN §4 — which nothing read.
##
## So: walking into a place finds it, and standing on a vista and looking out finds everything
## the country shows you from there. A vista is a place some POI names as somewhere it can be
## seen from; that is what the authored data means, and it saves inventing a second list.
##
## The sightline is checked against the built terrain rather than taken on trust. A claim the
## land contradicts — a ridge in the way, the curve of a valley — reveals nothing, and
## `tools/sightlines.py` reports every such claim so the world builder can move the POI or the
## author can drop the line. The data says what should be visible; the ground decides.

const GROUP := "place_discovery"
const POIS_PATH := "res://world/generated/pois.json"
const INTERVAL := 0.55
## How far past a place's own footprint counts as having arrived. A village pad is its houses;
## you have found Merrowby when you are among the outermost of them, not when you touch the
## exact centre.
const ARRIVAL_MARGIN_M := 30.0
## Eye height above the ground at the vantage.
const EYE_M := 1.65
## How far a landmark stands above its own ground, by what kind of thing it is. This is the
## difference between a mechanic and a lookup: a beacon tower is legible across a lake and a
## charcoal camp is not, and a hidden valley is called hidden because you cannot see into it
## from anywhere — its sightline is the way in, not the thing itself. A flat six metres for
## all of them made the falls invisible and the campfires monumental.
##
## The numbers were guesses until the POIs were dressed. They are measured now: every one is
## what `game/world/pois/poi_builders.gd` actually raises above the pad, taken across the POIs
## of that kind, so the audit and the game are arguing about the same country.
##
## * `tower` — a watch drum is 10.4 m, its merlons to 11 and a beacon's cage to 12; the toll-house's
##   bell frame is 9.0, the reedfolk platform and its roof 9.5, the colossus head 10.6. The
##   Tumbled Watch is 5, because it is lying down. Eighteen was nobody's tower.
## * `waterfall` — a cliff face of 11 m, 13 for the Glass Falls, and the Three Sisters' three
##   tiers at 4.6 each. Twenty-four was two of them stacked.
## * `strange_tree` — the Sallow King's willow at 1.5 scale is 24 m, Willow Isle's pollard 13,
##   the Singing Yew's yew at 3.1 is 9.
## * `giant_bones` — the Hart Bones' antlers reach 15 above the pad, the Rib Cathedral's arch 11.
## * `ruins` — a gable still standing is 4.6, the Oroth colonnade's tallest column 7.2, a
##   wardstone 5.4, and the Thirteenth is face down.
## * `strange` — a bell buoy is a barrel, a post, a cage and a bell; the One Poppy is a poppy.
## * `standing_stones` — a menhir of 3.8 m set at 1.15 to 1.55.
## * The kinds the drawn map asked for next (`poi_builders_land.gd`): a cave's shoulder of rock
##   stands 6.6 to 10.6 m over the mouth's floor; a farmstead's house of one or two storeys and
##   its roof about 7; a mill's two storeys and roof 9, a windmill's tower 9.5 under its cap; a
##   waystone is a milestone at 1.55, 1.4 m; a market field's bell-post 3.4; a quarry's face three
##   benches of 3.2; a shieling's walls 1.5 under a turf roof to 2.6; a vista's cairn 2.
## * `bridge` — an arch and its parapet is 4, Mossbridge's crown 5.4, the Chain Bridge's pylons
##   7.8 over their deck.
## * `shrine` — the Pilgrims' Bell lying on its side is 7, a hawthorn through a stone chair 5,
##   a cairn of lake pebbles 2.
const LANDMARK_M := {
	"tower": 10.0, "waterfall": 13.0, "strange_tree": 14.0, "giant_bones": 13.0,
	"ruins": 6.0, "strange": 2.5, "wreck": 5.0, "standing_stones": 5.0,
	"bridge": 4.5, "shrine": 4.0, "camp": 2.5, "hidden_valley": 1.0,
	"cave": 6.0, "farmstead": 7.0, "mill": 9.0, "waystone": 1.4, "market_field": 3.4,
	"quarry": 10.0, "shieling": 2.6, "vista": 2.0,
	"cairn": 1.8, "tally_post": 3.6, "grave": 1.3, "gibbet": 4.3, "fold": 1.2, "well": 2.9, "lantern_post": 4.6,
	"hut": 3.2, "crossroads": 2.7, "peat_cut": 1.4, "beacon": 3.4,
	"dovecote": 10.0, "scarecrow_moot": 2.2, "chandlery": 11.0, "turf_maze": 9.0, "figure_cutting": 1.0,
	"rookery": 17.0,
}
const LANDMARK_DEFAULT_M := 6.0
## Steps along the ray. 64 over eight kilometres is a sample every 125 m, which is coarse for a
## hedge and right for a hill; the terrain grid is 2 m and sampling it all would cost more than
## the answer is worth.
const RAY_STEPS := 64
## How far the ground may stand above the line of sight before it is blocking rather than
## rolling country in the foreground.
const CLEARANCE_M := 2.0
## The ground you are standing on is not a thing in the way. A vantage is a place with extent
## — a city's quay, the brow of a hill — and somebody reading the country off it takes the few
## paces needed to see past the bank at their feet. Without this, the beacon across the lake
## from Tollmere is hidden by four metres of shoreline a hundred and eighty metres away, which
## is not what anybody standing there would see.
const FOREGROUND_M := 140.0
## Beyond this the haze in every region's fog would have swallowed it anyway.
const MAX_SIGHT_M := 4200.0


static func ensure() -> PlaceDiscovery:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var found := tree.get_first_node_in_group(GROUP)
	if found is PlaceDiscovery:
		return found as PlaceDiscovery
	var made := PlaceDiscovery.new()
	made.name = "PlaceDiscovery"
	var host: Node = tree.current_scene if tree.current_scene != null else tree.root
	host.add_child(made)
	return made


@export var enabled := true

var _accum := 0.0
var _positions: Dictionary = {}       # place_id -> Vector3
var _radii: Dictionary = {}           # place_id -> float
var _seen_from: Dictionary = {}       # vantage place_id -> Array[String] of poi ids
var _loaded := false


func _ready() -> void:
	add_to_group(GROUP)


func _process(delta: float) -> void:
	if not enabled:
		return
	_accum += delta
	if _accum < INTERVAL:
		return
	_accum = 0.0
	var player := Peers.player()
	if player == null or not is_instance_valid(player):
		return
	if player is Node3D:
		look_around((player as Node3D).global_position)


# --- the two ways a place is found -----------------------------------------------------------

## Everything within reach of this position: the place you are standing in, and — if it is
## somewhere the country can be read from — everything that can be seen from it.
func look_around(here: Vector3) -> void:
	_load()
	for place_id in _positions:
		var id := str(place_id)
		if GameState.is_discovered(id):
			continue
		var pos: Vector3 = _positions[id]
		if Vector2(here.x - pos.x, here.z - pos.z).length() <= _arrival_radius(id):
			arrive(id)
	# Surveying is a separate question: you can arrive somewhere you have already been.
	for place_id in _seen_from:
		var id := str(place_id)
		if GameState.has_flag("surveyed:" + id) or not GameState.is_discovered(id):
			continue
		var pos: Vector3 = _positions.get(id, Vector3.ZERO)
		if pos == Vector3.ZERO:
			continue
		if Vector2(here.x - pos.x, here.z - pos.z).length() <= _arrival_radius(id):
			survey(id)


## You are here. Names it, and lets the compass and the chart show it.
func arrive(place_id: String) -> void:
	if place_id.is_empty() or GameState.is_discovered(place_id):
		return
	GameState.discover(place_id)
	var name_of := _display_name(place_id)
	if name_of != "":
		EventBus.notify.emit(name_of, "place")


## Standing on high ground and reading the country off it. Sets the survey flag the chart
## reads for its wider reveal, and finds everything the sightlines promise and the land allows.
## Returns the ids it found, which is what the tests and the audit tool want.
func survey(vantage_id: String) -> Array[String]:
	_load()
	var found: Array[String] = []
	if vantage_id.is_empty():
		return found
	GameState.set_flag("surveyed:" + vantage_id, true)
	var from: Vector3 = _positions.get(vantage_id, Vector3.ZERO)
	var blocked := 0
	for target in _seen_from.get(vantage_id, []) as Array:
		var id := str(target)
		if GameState.is_discovered(id):
			continue
		if not can_see(from, _positions.get(id, Vector3.ZERO), id):
			blocked += 1
			continue
		GameState.discover(id)
		found.append(id)
	var where := _display_name(vantage_id)
	if found.is_empty():
		EventBus.notify.emit("Nothing new from here." if where == ""
			else "Nothing new from %s." % where, "place")
	else:
		EventBus.notify.emit("From %s you can make out %d more of the country."
			% [where, found.size()], "place")
	if blocked > 0:
		Log.info("Discovery", "%s: %d of its sightlines are blocked by the land"
			% [vantage_id, blocked])
	return found


# --- can you actually see it -----------------------------------------------------------------

## Marches the line of sight over the built terrain. `from` and `to` are ground positions; the
## eye stands above one and the landmark above the other.
func can_see(from: Vector3, to: Vector3, target_id := "") -> bool:
	if from == Vector3.ZERO or to == Vector3.ZERO:
		return false
	var flat := Vector2(to.x - from.x, to.z - from.z).length()
	if flat <= 1.0:
		return true
	if flat > MAX_SIGHT_M:
		return false
	var eye := from.y + EYE_M
	var top := to.y + landmark_height(target_id)
	var skip := minf(FOREGROUND_M / flat, 0.4)
	for i in range(1, RAY_STEPS):
		var t := float(i) / float(RAY_STEPS)
		if t < skip:
			continue
		var x := lerpf(from.x, to.x, t)
		var z := lerpf(from.z, to.z, t)
		var line := lerpf(eye, top, t)
		if WorldProbe.get_height(x, z, -9999.0) > line + CLEARANCE_M:
			return false
	return true


## How far this thing rises above its own ground.
static func landmark_height(place_id: String) -> float:
	if place_id.is_empty():
		return LANDMARK_DEFAULT_M
	var kind := str(ContentDB.get_or_empty(place_id).get("kind", ""))
	return float(LANDMARK_M.get(kind, LANDMARK_DEFAULT_M))


# --- what there is to find ---------------------------------------------------------------------

func _load() -> void:
	if _loaded:
		return
	_loaded = true
	# Positions come from the built world where it exists, because that is where the pads
	# actually landed; the content's own [x, z] is the fallback for a test with no world.
	for entry in _world_pois():
		var id := str(entry.get("place_id", ""))
		if id.is_empty():
			continue
		var pos: Array = entry.get("pos", [0.0, 0.0, 0.0])
		_positions[id] = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
		_radii[id] = float(entry.get("radius_flat_m", 0.0))
	for type in ["place", "poi"]:
		for def in ContentDB.all(type):
			var id := str(def.get("id", ""))
			if id.is_empty() or _positions.has(id):
				continue
			var xz := WorldProbe.xz_of(def)
			if xz == Vector2.ZERO:
				continue
			_positions[id] = Vector3(xz.x, WorldProbe.get_height(xz.x, xz.y, 0.0), xz.y)
	for def in ContentDB.all("poi"):
		var id := str(def.get("id", ""))
		for vantage in def.get("visible_from", []) as Array:
			var v := str(vantage)
			if not _seen_from.has(v):
				_seen_from[v] = []
			(_seen_from[v] as Array).append(id)


## The pads as the world builder actually placed them, read from the same file the World node
## reads. Straight off disk rather than through `World`, so this answers the same in the
## scripted journey, in a unit test with no world in the tree, and in the game.
func _world_pois() -> Array:
	if not FileAccess.file_exists(POIS_PATH):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(POIS_PATH))
	return parsed as Array if typeof(parsed) == TYPE_ARRAY else []


func _arrival_radius(place_id: String) -> float:
	return maxf(float(_radii.get(place_id, 0.0)), 18.0) + ARRIVAL_MARGIN_M


func _display_name(place_id: String) -> String:
	var def := ContentDB.get_or_empty(place_id)
	return str(def.get("name", ""))


## Every authored sightline as a pair, for the audit tool and the tests.
func sightlines() -> Array[Array]:
	_load()
	var out: Array[Array] = []
	for vantage in _seen_from:
		for target in _seen_from[vantage] as Array:
			out.append([str(vantage), str(target)])
	return out


func position_of(place_id: String) -> Vector3:
	_load()
	return _positions.get(place_id, Vector3.ZERO)


## Places some POI says it can be seen from: the vistas, without a second authored list.
func vistas() -> Array[String]:
	_load()
	var out: Array[String] = []
	for v in _seen_from:
		out.append(str(v))
	out.sort()
	return out
