class_name Settlement
extends Node3D
## The built fabric of a town: its streets, and the houses nobody lives in.
##
## Twenty-four interiors are hand-built, and each one gets a real building raised around its
## door by `Building`. That is not a settlement. A settlement is fifty roofs, of which four open,
## and before this it was a flat green with white boxes round it: the houses turned their doors
## to a ring and not to the roads, stood on bare grass, and between them lay props dropped at
## random angles -- a wattle hurdle in the middle of nowhere, a hay bale on the green.
##
## So the town is laid out along its streets now (`StreetPlan`): the plots front the roads that
## cross the pad, shoulder to shoulder in a town and a garden apart in a hamlet, each house a
## few paces back from the carriageway with its door on the street and its garden running back
## to a fence. The middle, where the roads cross, is the market square in a town (paved, with
## its stalls, its well and its lamps) and the green in a village (a well, a tree, benches).
## What is made ground is laid as ground -- setts in front of a town's houses, a beaten path to
## a cottage door, the square -- so the foreground of a street is never bare grass. The houses
## are built by `HouseKit` in their region's walls and colours, with windows all round, porches,
## chimneys that smoke and signs over the shops; the gardens are fenced the way their region
## fences (wattle in the Vale, drystone on the hills, rails in the wood) and hold beds, sheds,
## woodpiles and washing; and the people whose schedules put them at the stalls, the well, the
## green or the forge stand there (`npc_spot` markers), not on a ring round the middle.
##
## However many houses, it is a handful of draws: one mesh per surface (walls, the second wall,
## roofs, stone, joinery, paving, earth), one MultiMesh per forge asset, and one for the smoke.

## How many roofs the fabric raises, and how tall. A city house is tall and narrow because land
## inside a wall is dear; a hamlet's is low because it is not. (`count` stays the first key of
## each row: tools/world/tests/test_roads.py reads this table.)
const FABRIC := {
	"city": {"count": 54, "storeys": [2, 3]},
	"town": {"count": 34, "storeys": [1, 2]},
	"village": {"count": 16, "storeys": [1, 2]},
	"hamlet": {"count": 8, "storeys": [1, 1]},
	"fort": {"count": 10, "storeys": [1, 2]},
	"lodge": {"count": 5, "storeys": [1, 1]},
	"camp": {"count": 0, "storeys": [1, 1]},
	"ruin_village": {"count": 9, "storeys": [1, 1]},
}

## Kinds whose middle is a paved market square rather than a green.
const SQUARE_KINDS := ["city", "town", "fort"]
## Kinds whose street fronts are paved: in a village the way to a door is a beaten path.
const PAVED_KINDS := ["city", "town", "fort"]

## What lies about the place, by culture, and where: `door` against the front wall beside a door,
## `yard` just behind a house, `garden` at the far end of a garden, `street` at the street's
## edge between two plots, `hub` in the square or on the green. Scaled by the size of the place;
## a prop the forge has not built is skipped rather than faked. A fence is not a prop any more:
## the gardens are fenced along their own edges (`FENCE_BY_CULTURE`).
##
## Briarwold has no props of its own in the forge yet, so the Woodfolk borrow the Vale's -- the
## nearest honest neighbour, and a barrel is a barrel.
const PROPS_BY_CULTURE := {
	"vale": [{"kind": "cart", "n": 2, "where": "street"},
			 {"kind": "hay_bale", "n": 5, "where": "garden"},
			 {"kind": "barrel", "n": 5, "where": "door"},
			 {"kind": "crate", "n": 3, "where": "yard"},
			 {"kind": "wheelbarrow", "n": 2, "where": "yard"},
			 {"kind": "bucket", "n": 3, "where": "door"},
			 {"kind": "bench", "n": 4, "where": "door"},
			 {"kind": "chopping_block", "n": 3, "where": "yard"}],
	"lakefolk": [{"kind": "barrel", "n": 6, "where": "door"},
				 {"kind": "crate", "n": 6, "where": "street"},
				 {"kind": "lantern_standing", "n": 3, "where": "street"},
				 {"kind": "banner", "n": 2, "where": "hub"}],
	"reedfolk": [{"kind": "dock_post", "n": 5, "where": "garden"},
				 {"kind": "rope_coil", "n": 3, "where": "door"},
				 {"kind": "rowboat", "n": 2, "where": "garden"},
				 {"kind": "lantern_hanging", "n": 2, "where": "hub"},
				 {"kind": "basket", "n": 2, "where": "door"}],
	"clans": [{"kind": "peat_stack", "n": 2, "where": "yard"}],
	"pilgrims": [{"kind": "brazier", "n": 4, "where": "hub"},
				 {"kind": "bedroll", "n": 2, "where": "yard"},
				 {"kind": "sarcophagus", "n": 1, "where": "hub"}],
	"woodfolk": [{"kind": "cart", "n": 1, "where": "street"},
				 {"kind": "barrel", "n": 3, "where": "door"},
				 {"kind": "chopping_block", "n": 3, "where": "yard"},
				 {"kind": "bench", "n": 2, "where": "door"},
				 {"kind": "hay_bale", "n": 2, "where": "garden"}],
}

## Which region's props a culture reaches for. Not always its own: see above.
const PROP_PREFIX := {
	"vale": "hearthvale", "lakefolk": "brightwater", "reedfolk": "sedgemire",
	"clans": "skerrow", "pilgrims": "cinderlea", "woodfolk": "hearthvale",
}

## Region to the surface keys `HouseInterior` and `Building` already speak.
const CULTURE_BY_REGION := {
	"core:region/hearthvale": "vale",
	"core:region/brightwater": "lakefolk",
	"core:region/sedgemire": "reedfolk",
	"core:region/briarwold": "woodfolk",
	"core:region/skerrow": "clans",
	"core:region/cinderlea": "pilgrims",
}

## A house's outside wall, where it is not the interior's own: the fen's tarred weatherboard and
## the wood's laid logs read as boards along the wall, not as one plank's grain the size of a
## house (which is what the interior's timber surface drew on a whole gable).
const OUTSIDE_WALL := {
	"reedfolk": {"pattern": 1, "base": "#62564a", "accent": "#4a4138", "grout": "#221e1a", "unit": 0.24},
	"woodfolk": {"pattern": 1, "base": "#6e5a40", "accent": "#4e3f2c", "grout": "#261e15", "unit": 0.3},
}

## The made ground: setts and flags where a town paves its street fronts and its square, and the
## beaten earth of a path, a yard or a lane.
const PAVING_BY_CULTURE := {
	"vale": {"pattern": 2, "base": "#968d7c", "accent": "#766e60", "grout": "#4f4a40", "unit": 0.15},
	"lakefolk": {"pattern": 2, "base": "#a19c90", "accent": "#817d74", "grout": "#57544d", "unit": 0.3},
	"reedfolk": {"pattern": 1, "base": "#6f5f4a", "accent": "#56493a", "grout": "#2c251d", "unit": 0.24},
	"woodfolk": {"pattern": 2, "base": "#8a8272", "accent": "#6b6456", "grout": "#48433a", "unit": 0.2},
	"clans": {"pattern": 2, "base": "#8f8a80", "accent": "#706c64", "grout": "#48453f", "unit": 0.36},
	"pilgrims": {"pattern": 2, "base": "#9a958d", "accent": "#7a766f", "grout": "#4f4c47", "unit": 0.45},
}
const EARTH := {"pattern": 5, "base": "#7c6c55", "accent": "#5f5242", "grout": "#40372c"}
## What grows along a cottage's front wall, by culture: the flowers of its own country.
const FLOWERS_BY_CULTURE := {
	"vale": ["hearthvale_poppy", "hearthvale_cow_parsley"], "lakefolk": ["brightwater_cow_parsley"],
	"reedfolk": ["sedgemire_marsh_marigold"], "woodfolk": ["briarwold_foxglove"],
	"clans": ["skerrow_heather"], "pilgrims": ["cinderlea_red_poppy_single"],
}

## How each culture closes a garden: hurdles of woven hazel in the Vale, a low wall or a paling on
## the lake, a drystone wall on the hills, split rails in the wood, reed hurdles in the fen. (The
## forge's hedge segment is a field's hedge, a line of tall blades, and round a cottage garden it
## read as a row of spikes; `_fence` still lays one if a culture asks.)
const FENCE_BY_CULTURE := {
	"vale": ["wattle", "wattle", "rail"],
	"lakefolk": ["wall", "paling", "rail"],
	"reedfolk": ["wattle"],
	"woodfolk": ["rail"],
	"clans": ["drystone"],
	"pilgrims": ["wall"],
}
const WATTLE_TINT := Color(0.55, 0.43, 0.27)
const RAIL_TINT := Color(0.45, 0.35, 0.24)
const PALING_TINT := Color(0.86, 0.84, 0.78)

## The tree on a village green, by culture: what the region grows and people plant.
const GREEN_TREE := {
	"vale": "hearthvale_oak", "lakefolk": "brightwater_lime", "reedfolk": "sedgemire_willow",
	"woodfolk": "briarwold_black_ash", "clans": "skerrow_rowan",
}
## The tree the Vale plants in a garden and in rows behind the houses.
const FRUIT_TREE := "hearthvale_apple"

## What a shop hangs over the street to say what it sells: the thing itself, bigger than life,
## on an iron bracket. A trade with no emblem the forge has built simply has none.
const EMBLEM := {
	"cobbler": "boots", "chandler": "lantern_hand", "cooper": "barrel", "weaver": "cloth",
	"potter": "jar", "baker": "loaf", "brewer": "jug", "innkeeper": "jug", "smith": "hammer",
	"apothecary": "phial", "alchemist": "phial", "bookbinder": "book_stack", "fishmonger": "basket",
	"fisher": "basket", "basketmaker": "basket", "ropemaker": "rope_coil", "turner": "bowl",
	"armourer": "shield", "draper": "cloth",
}
## The shops the fabric's houses keep, by culture, handed out nearest the middle first.
const SHOP_TRADES := {
	"vale": ["cobbler", "chandler", "cooper", "weaver", "potter", "baker", "armourer"],
	"lakefolk": ["chandler", "bookbinder", "apothecary", "fishmonger", "draper", "cooper", "potter"],
	"reedfolk": ["basketmaker", "ropemaker", "fishmonger"],
	"woodfolk": ["cooper", "turner", "chandler"],
	"clans": ["armourer", "brewer", "smith"],
	"pilgrims": ["chandler"],
}
const SHOPS_BY_KIND := {"city": 8, "town": 5, "village": 2, "fort": 1}
## How many stalls a market holds when nobody's schedule says more.
const STALLS_BY_KIND := {"city": 6, "town": 4, "village": 2, "fort": 0}

## Work you can stand up and do. `Jobs` knows five kinds of station and `JobBoard` lists the
## day's radiant work, and both were complete, tested and placed by nothing at all: no notice
## post stood in any village and no bellows, mash tun or eel trap existed outside a unit test.
## The interiors know every resident's trade, so a settlement's work follows from who lives in
## it rather than from a second list that can disagree.
const STATION_FOR_TRADE := {
	"smith": "smith", "brewer": "brew", "fisher": "fish", "farmer": "chop", "baker": "chop",
}
## Every settlement has work of its own even where nobody in it has an authored trade: the
## reed beds are cut, the Briarwold is coppiced, the Skerrow digs peat off the ledges.
const STATION_BY_CULTURE := {
	"vale": "chop", "lakefolk": "fish", "reedfolk": "dig",
	"woodfolk": "chop", "clans": "dig", "pilgrims": "dig",
}
## What the forge has that reads as the work from a few paces off. The chopping block and the
## peat stack were owed and are built now -- a nine-flat hewn billet with an axe bitten into it,
## and crossed courses of cut turves with the tusker standing beside them -- so nothing here is
## standing in for anything any more.
const STATION_PROP := {
	"smith": "anvil", "brew": "barrel", "fish": "dock_post",
	"chop": "chopping_block", "dig": "peat_stack",
}
## A hamlet of eight houses has no charter-board; a lodge in the woods has no notices.
const BOARD_KINDS := ["city", "town", "village", "fort"]
## The most stations one settlement gets, so Merrowby's ten authored interiors do not turn the
## square into a workshop floor.
const MAX_STATIONS := 4
## The top of a market stall's counter, where its goods are laid out (the forge's stall: 0.85 m
## at its chunky scale of 1.1).
const STALL_COUNTER_M := 0.94
## Made ground stands this far off the terrain, and is not drawn past this. A town's carriageway
## lies a little lower than the footways and the square it meets, so where they overlap the
## footway is always the one seen.
const GROUND_LIFT_M := 0.05
const CARRIAGEWAY_LIFT_M := 0.032
## Made ground is laid on the terrain at the corners of patches up to 3 m across and drawn flat
## between them, where the terrain draws its own surface on a vertex every 2 m (and every 4 m in
## its next ring out). On a level pad the two agree. Where the ground under a patch bends -- the
## lip of a pad built out over falling ground, a town's paving run out to its pad's edge -- the
## terrain stood up through it: 0.30 m at Grandfather Hollow, 0.38 m at Kharrow Hold, 0.29 m at
## the West Walk (tools_gd/paving_probe.gd; triage 15, "their roads/stone clip in several areas
## showing the terrain underneath"). A patch now halves where it is short of its lift over the
## ground by more than GROUND_FIT_M, down to GROUND_SPLIT_MIN_M, and one still short is raised by
## what it lacks. Ground within GROUND_LEVEL_M across a patch's corners and middle is level.
const GROUND_FIT_M := 0.01
const GROUND_SPLIT_MIN_M := 0.75
const GROUND_EDGE_STEP_M := 0.5
const GROUND_LEVEL_M := 0.002
const GROUND_RANGE_M := 240.0
## A drystone wall is drawn this far from the middle of its place, and the coping of stones along
## its top no further than a cart. The coping is most of a wall's triangles, and the walls had no
## range: every place's were drawn however far off it stood, and on the streets plan's Merrowby
## shot they were 0.32 M of the frame's 2.13 M triangles, where Merrowby's own (its sties) are
## three thousand. A wall is less than a pixel from the next hill.
const DRYSTONE_RANGE_M := 1000.0
const COPING_RANGE_M := FabricMesh.PROP_RANGE_M
## A prop smaller than this across (the crockery on a stall, a bucket, a loaf) is drawn only this
## near and casts no shadow; one smaller than the middling size (a barrel, a bench) half as far as
## a cart.
const SMALL_PROP_M := 0.7
const SMALL_PROP_RANGE_M := 70.0
const MIDDLING_PROP_M := 1.6
## The fabric key the gardens' small things are gathered under, drawn in the joinery's material as
## a mesh of their own, only this near (measured to the middle of the place) and with no shadow.
const GARDEN := "garden"
const GARDEN_RANGE_M := 110.0

## Where the people whose schedules name a spot at this place stand: the words in a spot's name
## that say what it is at. The first that matches wins.
const SPOT_WORDS := [
	["stall", "stall"], ["herb_table", "stall"], ["sutlers_cart", "stall"], ["market_cross", "cross"],
	["market", "square"], ["well", "well"], ["green", "green"], ["square", "square"],
	["forge", "forge"], ["inn_", "inn"], ["board", "board"], ["notice", "board"],
]


var place_id := ""
var kind := "village"
var culture := "vale"
var pad_radius := 40.0
## Footprints already spoken for: the real houses, and the mouths of deep places.
var taken: Array[Rect2] = []
var roads: Array = []
var ruined := false
## The streets and plots. `WorldDoors` hands in the plan it already put the real houses on.
var street: StreetPlan = null

var _rng := RandomNumberGenerator.new()
## Which houses are lit after dark, and which of their windows, has its own stream: drawing it
## from `_rng` would move every prop and station laid out after the houses.
var _lights := RandomNumberGenerator.new()
var _window_glows: Array = []      # lit panes, this node's space
var _door_lamps: Array = []        # a lamp over the door of every lit house, this node's space
var _chimneys: Array = []          # chimney tops that smoke, this node's space
var _built: Array = []             # {plot, frame (Transform3D, local), door (Vector3, local), trade}
var _emblems: Dictionary = {}      # prop kind -> Array[Transform3D]
var _placed: Dictionary = {}       # prop path -> Array[Transform3D]
var _features: Dictionary = {}     # "well", "cross", "board", "forge", "inn": Vector3 local; "stalls", "benches": Array
var _yard_bodies: Node3D = null
## The made ground's own stream, so how it is shaded never moves a house or a prop.
var _ground_rng := RandomNumberGenerator.new()
## The terrain's heights at its vertices, and the ground as it draws it (`_vertex_height`,
## `_drawn_ground`), as the made ground asks them while the town is laid out; emptied once it is.
var _vertex_heights: Dictionary = {}
var _drawn_heights: Dictionary = {}
var _vertex_m := 0.0
## How many runs of each kind of fence the gardens got: wattle, hedge, rail, paling, wall, drystone.
var fences_laid: Dictionary = {}


## A settlement's fabric around `centre`. Nothing is built until it enters the tree.
static func raise_at(id: String, place_kind: String, region: String, centre: Vector3,
		radius: float, road_lines: Array, reserved: Array[Rect2], plan: StreetPlan = null) -> Settlement:
	var s := Settlement.new()
	s.place_id = id
	s.kind = place_kind
	s.culture = str(CULTURE_BY_REGION.get(region, "vale"))
	s.pad_radius = radius
	s.roads = road_lines
	s.taken = reserved
	s.street = plan
	s.ruined = place_kind == "ruin_village"
	s.position = centre
	s.name = "Fabric_" + Ids.name_of(id)
	return s


func _ready() -> void:
	# a town raised stepwise joins the group once it stands: the people's ways (NpcNav) bake a mesh
	# over whatever settlement they find near, and half a town is not one
	if not stepwise:
		add_to_group("settlement")
	else:
		_slice = WorldPace.Slice.new()
	await _raise()
	if not is_inside_tree():
		return
	if _slice != null:
		# what was done since the last pause is this frame's too
		_slice.due("town_rest")
	add_to_group("settlement")
	is_raised = true
	_slice = null
	raised.emit()


## Everything a settlement stands up, in order. Stepwise (a world standing up while something is
## drawn: WorldDoors), it is paced by the frame's budget (WorldPace) between houses, gardens, runs
## of fence and pieces of worked ground, and the town is raised over several frames; otherwise it
## is all done at once, inside `add_child`, as it always was.
func _raise() -> void:
	var plan: Dictionary = FABRIC.get(kind, {})
	if plan.is_empty() or int(plan.get("count", 0)) <= 0:
		return
	_rng.seed = abs(place_id.hash())
	_lights.seed = abs(("lights:" + place_id).hash())
	_ground_rng.seed = abs(("ground:" + place_id).hash())
	if street == null:
		street = StreetPlan.make(place_id, kind, Vector2(global_position.x, global_position.z),
				pad_radius, roads)
	for r in taken:
		street.reserve_rect(r)
	var added := street.fill(int(plan.get("count", 0)))
	Log.info("Settlement", "%s: %d streets, %d houses along them (%d with an inside), a middle of %.0f m" \
			% [Ids.name_of(place_id), street.arms.size(), street.houses.size(), street.houses.size() - added, street.hub])
	if _fabric_plots().is_empty():
		return
	await _pace("street")
	_yard_bodies = Node3D.new()
	_yard_bodies.name = "Yards"
	add_child(_yard_bodies)
	var fabric := FabricMesh.new()
	fabric.split(GARDEN, Vector3.ZERO)
	for key in ["paving", "earth"]:
		fabric.carry_lift(key)
	# the walls, fences and posts standing by a pad's lip: lifted as the terrain comes to its far rings
	# (`_foot_lift`), as the made ground is
	for key in GROUND_FOLLOWERS:
		fabric.carry_ground_lift(key)
	await _build(fabric, plan)
	await _yards(fabric)
	await _ground(fabric)
	await _pace("ground")
	_middle(fabric)
	await _pace("middle")
	if kind == "fort" and not ruined:
		_fort(fabric)
		await _pace("fort")
	await _stock(fabric)
	_vertex_heights.clear()
	_drawn_heights.clear()
	await _commit(fabric)
	await _strew(plan)
	_hang_emblems()
	_smoke()
	_light_up()
	await _pace("lights")
	_put_to_work()
	_offer_the_empty_houses()
	_mark_spots()


## Raised stepwise, a frame at a time within the frame's budget (WorldPace); set before it enters the
## tree. Off, it is all raised inside `add_child`.
var stepwise := false
## Whether everything is standing: at once when not stepwise, and when `raised` is emitted if it is.
var is_raised := false
signal raised
var _slice: WorldPace.Slice = null


## Between two pieces of a stepwise raise: the frame's budget spent, the next frame. `what` names
## the piece just done, for the accounts (WorldPace.pieces).
func _pace(what := "") -> void:
	if _slice != null:
		await _slice.pace("town_" + what)


## The plots the fabric builds on: everything the plan holds that is not a real house.
func _fabric_plots() -> Array:
	var out: Array = []
	for h in street.houses:
		if str((h as Dictionary).get("real", "")) == "":
			out.append(h)
	return out


# --- the houses --------------------------------------------------------------------------------

func _build(fabric: FabricMesh, plan: Dictionary) -> void:
	var storeys: Array = plan.get("storeys", [1, 1])
	var plots := _fabric_plots()
	# nearest the middle first: that is where the shops and the tall houses are
	plots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["door"] as Vector2).distance_to(street.centre) < (b["door"] as Vector2).distance_to(street.centre))
	var shops: Array = (SHOP_TRADES.get(culture, []) as Array).duplicate()
	var shop_count := mini(int(SHOPS_BY_KIND.get(kind, 0)), shops.size())
	for plot in plots:
		await _pace("house")
		var b: Dictionary = plot["box"]
		var w := float(b["hw"]) * 2.0
		var d := float(b["hd"]) * 2.0
		var near := (plot["door"] as Vector2).distance_to(street.centre) < street.hub + 20.0
		var n := _rng.randi_range(int(storeys[0]), int(storeys[1]))
		if near and kind in SQUARE_KINDS:
			n = int(storeys[1])
		var style := HouseKit.pick_style(culture, _rng)
		var trade := ""
		if shop_count > 0 and not ruined:
			trade = str(shops[_rng.randi_range(0, shops.size() - 1)])
			shops.erase(trade)
			shop_count -= 1
		# A ruin is a house with its roof gone and a wall down; it is still a plan on the ground.
		var standing := not ruined or _rng.randf() > 0.45
		var home := not ruined and _lights.randf() < 0.72
		var spec := {"w": w, "d": d, "storeys": n, "culture": culture, "style": style,
				"tint": HouseKit.pick_tint(style, _rng), "stone": _stone_tint(), "roof": _roof_spec(),
				"standing": standing, "home": home, "trade": trade,
				"jetty": culture in ["lakefolk", "vale"] and kind in ["city", "town"] and n >= 2 and _rng.randf() < 0.5}
		var at := _frame_of(b)
		# a house by the pad's lip rides up whole where the terrain's far rings come up round it
		var bc: Vector2 = b["c"]
		var bu: Vector2 = b["u"]
		fabric.lift = _foot_lift(bc - bu * float(b["hw"]), bc + bu * float(b["hw"]), float(b["hd"]))
		var made := HouseKit.build(fabric, at, spec, _rng, _lights)
		fabric.lift = Vector3.ZERO
		var body: Array = made["body"]
		if body.size() == 2:
			_body(body[0], at.basis, body[1])
			get_child(get_child_count() - 1).set_meta("house", true)
		_window_glows.append_array(made["glows"])
		if made["lamp"] != Vector3.INF:
			_door_lamps.append(made["lamp"])
		# about two chimneys in three are drawing by day: somebody is cooking
		for top in made["chimneys"]:
			if standing and not ruined and _lights.randf() < 0.66:
				_chimneys.append(top)
		if made["sign"] != null and EMBLEM.has(trade):
			_emblem(str(EMBLEM[trade]), made["sign"])
		_built.append({"plot": plot, "frame": at, "door": made["door"], "trade": trade})


## A house's frame in this node's space: origin on the ground at the middle of its plot, x along
## the street, -z out of its front door.
func _frame_of(b: Dictionary) -> Transform3D:
	var c: Vector2 = b["c"]
	var u: Vector2 = b["u"]
	var v: Vector2 = b["v"]
	# the ground under a house on a slope: the low side's, so no corner floats
	var low := INF
	for p in StreetPlan.corners(b):
		low = minf(low, _ground_at(p))
	var mid := _ground_at(c)
	var y := minf(mid, low + 0.25) - global_position.y
	var orient := Basis(Vector3(u.x, 0.0, u.y), Vector3.UP, Vector3(v.x, 0.0, v.y))
	return Transform3D(orient, Vector3(c.x - global_position.x, y, c.y - global_position.z))


## `_foot_lift`: how far past its ends a piece's footprint is taken (the pieces overlap the next), and
## how closely it is sampled inside (m).
const FOOT_OVER_M := 0.12
const FOOT_STEP_M := 0.5
## The fabric's keys whose pieces stand on the ground and carry how far they stand up on the terrain's
## far rings (FabricMesh.carry_ground_lift, set by `_foot_lift` round each wall length and post).
const GROUND_FOLLOWERS := ["drystone", "coping", "joinery", "wall", "wall_alt", "roof", "stone"]


func _commit(fabric: FabricMesh) -> void:
	if _slice != null:
		# raised stepwise, the meshes' arrays are gathered on a worker thread while frames go on
		_slice.due("town_commit")
		await fabric.gather_off_thread()
		_slice.t0 = Time.get_ticks_usec()
	for pair in [["wall", "Walls"], ["wall_alt", "WallsAlt"], ["roof", "Roofs"], ["stone", "Stone"]]:
		var mat := fabric_material(culture, str(pair[0]))
		(mat as ShaderMaterial).set_shader_parameter("ground_follow", true)
		fabric.commit(self, str(pair[0]), mat, str(pair[1]))
		await _pace("commit")
	var laid := fabric_material(culture, "drystone")
	(laid as ShaderMaterial).set_shader_parameter("ground_follow", true)
	var drystone := fabric.commit(self, "drystone", laid, "Drystone")
	if drystone != null:
		FabricMesh.near_only(drystone, DRYSTONE_RANGE_M, true)
	await _pace("commit")
	var coping := fabric.commit(self, "coping", laid, "Coping")
	if coping != null:
		FabricMesh.near_only(coping, COPING_RANGE_M, true)
	var timber := FabricMesh.joinery_material()
	timber.set_shader_parameter("ground_follow", true)
	var joinery := fabric.commit(self, "joinery", timber, "Joinery")
	if joinery != null:
		FabricMesh.near_only(joinery, FabricMesh.JOINERY_RANGE_M, false)
	await _pace("commit")
	# the gardens' crops, woodpiles and washing: small, many, and nothing from the next field; in
	# quarters, so a camera in the street draws the gardens it faces
	for garden in fabric.commit_all(self, GARDEN, FabricMesh.joinery_material(), "Garden"):
		FabricMesh.near_only(garden, GARDEN_RANGE_M, false)
	for key in ["paving", "earth"]:
		var ground := fabric.commit(self, key, fabric_material(culture, key), "Paving" if key == "paving" else "Earth")
		if ground != null:
			FabricMesh.near_only(ground, GROUND_RANGE_M, false)
			# up by what each patch carries (`_far_lift`) as the terrain under it comes to its far rings
			(ground.material_override as ShaderMaterial).set_shader_parameter("terrain_follow", true)


func _stone_tint() -> Color:
	var k := _rng.randf_range(-1.0, 1.0)
	return Color(0.93 + 0.07 * k, 0.935 + 0.065 * k, 0.94 + 0.06 * k)


## A box you cannot walk through. A house's hangs off the settlement itself (one body a house);
## a shed's, a wall's or a cross's off `Yards`.
func _body(at: Vector3, orient: Basis, size: Vector3, parent: Node = null) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1 << 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.transform = Transform3D(orient, at)
	(parent if parent != null else self).add_child(body)


# --- the gardens ----------------------------------------------------------------------------------

## Every garden behind a house, the real houses' too: fenced along its sides and its far end in
## the region's own way, with what a garden holds in it.
func _yards(fabric: FabricMesh) -> void:
	var fences: Array = FENCE_BY_CULTURE.get(culture, ["wattle"])
	var runs: Array = []
	for h in street.houses:
		var g: Dictionary = (h as Dictionary).get("garden", {})
		if g.is_empty():
			continue
		var kind_of_fence := str(fences[_rng.randi_range(0, fences.size() - 1)])
		var c := StreetPlan.corners(g)
		# corners run (-u,-v) (+u,-v) (+u,+v) (-u,+v): -v is the house's back wall, which closes
		# the garden already; the far end and the two sides are fenced
		for edge in [[c[1], c[2]], [c[2], c[3]], [c[3], c[0]]]:
			runs.append({"a": edge[0], "b": edge[1], "kind": kind_of_fence})
		_garden(fabric, h, g)
		await _pace("garden")
	for run in _without_doubles(runs):
		_fence(fabric, run["a"], run["b"], str(run["kind"]))
		await _pace("fence")


## Two gardens side by side share a boundary: one fence on it, not two a hand's width apart.
static func _without_doubles(runs: Array) -> Array:
	var kept: Array = []
	for run in runs:
		var a: Vector2 = run["a"]
		var b: Vector2 = run["b"]
		var dir := (b - a).normalized()
		var double := false
		for other in kept:
			var oa: Vector2 = other["a"]
			var ob: Vector2 = other["b"]
			var odir := (ob - oa).normalized()
			if absf(dir.dot(odir)) < 0.985:
				continue
			# parallel: does it lie along the same line, and overlap it?
			var off := absf((a - oa).cross(odir))
			if off > 0.9:
				continue
			var t0 := (a - oa).dot(odir)
			var t1 := (b - oa).dot(odir)
			var lo := minf(t0, t1)
			var hi := maxf(t0, t1)
			var overlap := minf(hi, oa.distance_to(ob)) - maxf(lo, 0.0)
			if overlap > (b - a).length() * 0.5:
				double = true
				break
		if not double:
			kept.append(run)
	return kept


## One run of fence from `a` to `b` (world xz), on the ground.
func _fence(fabric: FabricMesh, a: Vector2, b: Vector2, fence_kind: String) -> void:
	var length := a.distance_to(b)
	if length < 0.5:
		return
	var dir := (b - a) / length
	if fence_kind != "hedge" or not _prop_paths(str(PROP_PREFIX.get(culture, "hearthvale")), "hedge_segment").is_empty() \
			or not _prop_paths("hearthvale", "hedge_segment").is_empty():
		fences_laid[fence_kind] = int(fences_laid.get(fence_kind, 0)) + 1
	match fence_kind:
		"hedge":
			var paths := _prop_paths(str(PROP_PREFIX.get(culture, "hearthvale")), "hedge_segment")
			if paths.is_empty():
				paths = _prop_paths("hearthvale", "hedge_segment")
			if paths.is_empty():
				_fence(fabric, a, b, "wattle")
				return
			var n := maxi(1, int(round(length / 2.4)))
			for i in range(n):
				var p := a + dir * (length * (float(i) + 0.5) / float(n))
				var yaw := atan2(-dir.y, dir.x) + _rng.randf_range(-0.05, 0.05)
				_put(paths[_rng.randi_range(0, paths.size() - 1)], _on_ground(p),
						yaw, Vector3(length / float(n) / 2.5, _rng.randf_range(0.8, 1.0), 1.0))
		"drystone", "wall":
			_wall(fabric, a, b, 1.05 if fence_kind == "drystone" else 0.8)
		_:
			_hurdles(fabric, a, b, fence_kind)
	# a wall or fence stops you; one long thin body for the run
	var mid := (a + b) * 0.5
	var body := StaticBody3D.new()
	body.collision_layer = 1 << 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(length, 1.2, 0.3)
	shape.shape = box
	body.add_child(shape)
	body.transform = Transform3D(Basis(Vector3.UP, atan2(-dir.y, dir.x)), _on_ground(mid) + Vector3(0.0, 0.6, 0.0))
	_yard_bodies.add_child(body)


## Posts and whatever runs between them: woven hurdles, split rails, or a paling.
func _hurdles(fabric: FabricMesh, a: Vector2, b: Vector2, fence_kind: String) -> void:
	var length := a.distance_to(b)
	var dir := (b - a) / length
	var spacing := 1.8 if fence_kind == "wattle" else 2.2
	var n := maxi(1, int(ceil(length / spacing)))
	var yaw := atan2(-dir.y, dir.x)
	var orient := Basis(Vector3.UP, yaw)
	var tint := WATTLE_TINT if fence_kind == "wattle" else (PALING_TINT if fence_kind == "paling" else RAIL_TINT)
	# the wear on the timber is drawn from its own rng, so the settlement's draws after it are as
	# they were
	var jit := RandomNumberGenerator.new()
	jit.seed = hash(Vector2i(int(round(a.x * 10.0)), int(round(a.y * 10.0))))
	# how far each span between two posts stands up on the terrain's far rings, and each post as much
	# as the higher span beside it
	var spans: Array[Vector3] = []
	for i in range(n):
		spans.append(_foot_lift(a + dir * (length * float(i) / float(n)), a + dir * (length * float(i + 1) / float(n)), 0.1))
	for i in range(n + 1):
		fabric.lift = spans[mini(i, n - 1)].max(spans[maxi(i - 1, 0)])
		var p := _on_ground(a + dir * (length * float(i) / float(n)))
		# each post a little off true, and its own shade of old wood
		var lean := orient * Basis(Vector3.BACK, jit.randf_range(-0.04, 0.04)) * Basis(Vector3.RIGHT, jit.randf_range(-0.03, 0.03))
		fabric.box("joinery", Transform3D(lean, p + Vector3(0.0, 0.6, 0.0)), Vector3(0.1, 1.25, 0.1),
				FabricMesh.shade(RAIL_TINT.darkened(0.28), jit.randf_range(0.85, 1.1)))
	for i in range(n):
		fabric.lift = spans[i]
		var p0 := _on_ground(a + dir * (length * float(i) / float(n)))
		var p1 := _on_ground(a + dir * (length * float(i + 1) / float(n)))
		var mid := (p0 + p1) * 0.5
		var seg := p0.distance_to(p1)
		var tilt := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, atan2(p1.y - p0.y, Vector2(p1.x - p0.x, p1.z - p0.z).length()))
		match fence_kind:
			"wattle":
				# a hurdle: the shadow in the weave behind, the sails standing up through it, and the
				# withies woven in and out of them, each its own shade and none of them quite level.
				# It was one flat board with four bands on it, which the user's playtest read as a
				# pale plank with nothing painted on it.
				var k := _rng.randf_range(0.85, 1.05)
				fabric.box("joinery", Transform3D(tilt, mid + Vector3(0.0, 0.52, 0.0)), Vector3(seg - 0.08, 0.92, 0.03),
						FabricMesh.shade(tint, k * 0.55))
				var sails := maxi(2, int(seg / 0.34))
				for j in range(sails):
					var t := (float(j) + 0.5) / float(sails)
					var q := p0.lerp(p1, t)
					fabric.box("joinery", Transform3D(orient * Basis(Vector3.BACK, jit.randf_range(-0.05, 0.05)), q + Vector3(0.0, 0.54, 0.0)),
							Vector3(0.035, 1.06, 0.035), FabricMesh.shade(tint, k * jit.randf_range(0.7, 0.85)))
				for band in range(7):
					var side := 0.022 if band % 2 == 0 else -0.022
					var wobble := tilt * Basis(Vector3.BACK, jit.randf_range(-0.015, 0.015))
					fabric.box("joinery", Transform3D(wobble, mid + Vector3(0.0, 0.12 + band * 0.13, 0.0) + tilt * Vector3(0.0, 0.0, side)),
							Vector3(seg - 0.06, 0.09, 0.03), FabricMesh.shade(tint, k * jit.randf_range(0.88, 1.12)))
			"paling":
				for y_v in [0.3, 0.85]:
					fabric.box("joinery", Transform3D(tilt, mid + Vector3(0.0, float(y_v), 0.0)), Vector3(seg, 0.07, 0.05),
							FabricMesh.shade(tint, jit.randf_range(0.8, 0.9)))
				var pales := int(seg / 0.16)
				for j in range(pales):
					var q := p0.lerp(p1, (float(j) + 0.5) / float(pales))
					var tall := jit.randf_range(0.94, 1.06)
					fabric.box("joinery", Transform3D(orient * Basis(Vector3.BACK, jit.randf_range(-0.03, 0.03)), q + Vector3(0.0, 0.5 * tall, 0.04)),
							Vector3(0.07, tall, 0.025), FabricMesh.shade(tint, jit.randf_range(0.86, 1.04)))
			_:
				# split rails, each its own shade, none quite level
				for y_v in [0.45, 0.95]:
					var sag := tilt * Basis(Vector3.BACK, jit.randf_range(-0.02, 0.02))
					fabric.box("joinery", Transform3D(sag, mid + Vector3(0.0, float(y_v) + jit.randf_range(-0.04, 0.04), 0.0)),
							Vector3(seg + 0.1, jit.randf_range(0.09, 0.12), 0.08), FabricMesh.shade(tint, jit.randf_range(0.85, 1.1)))
	fabric.lift = Vector3.ZERO


## A wall of stones laid dry: battered, in a rubble of small stones (its own surface, not the
## plinths' dressed blocks, which made a garden wall read as a concrete planter), and a coping of
## stones set on edge along its top.
func _wall(fabric: FabricMesh, a: Vector2, b: Vector2, h: float) -> void:
	var length := a.distance_to(b)
	var dir := (b - a) / length
	var yaw := atan2(-dir.y, dir.x)
	var n := maxi(1, int(ceil(length / 3.0)))
	for i in range(n):
		fabric.lift = _foot_lift(a + dir * (length * float(i) / float(n)), a + dir * (length * float(i + 1) / float(n)), 0.31)
		var p0 := _on_ground(a + dir * (length * float(i) / float(n)))
		var p1 := _on_ground(a + dir * (length * float(i + 1) / float(n)))
		var mid := (p0 + p1) * 0.5
		var seg := p0.distance_to(p1) + 0.12
		var orient := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, atan2(p1.y - p0.y, Vector2(p1.x - p0.x, p1.z - p0.z).length()))
		var tint := _stone_tint().darkened(_rng.randf_range(0.0, 0.08))
		fabric.box("drystone", Transform3D(orient, mid + Vector3(0.0, h * 0.3 - 0.1, 0.0)), Vector3(seg, h * 0.6 + 0.2, 0.62), tint)
		fabric.box("drystone", Transform3D(orient, mid + Vector3(0.0, h * 0.74, 0.0)), Vector3(seg, h * 0.3, 0.48), tint)
		# the coping: stones on edge packed tight along the top, each its own thickness, height and
		# lean, so the crest is ragged. Spaced out at a hand's breadth with daylight between them
		# they read from the fold as the battlements of a toy fort.
		var stones := int(seg / 0.19)
		for k in range(stones):
			var q := p0.lerp(p1, (float(k) + 0.5) / float(stones)) \
					+ Basis(Vector3.UP, yaw) * Vector3(0.0, 0.0, _rng.randf_range(-0.04, 0.04))
			var lean := Basis(Vector3.UP, yaw + _rng.randf_range(-0.12, 0.12)) * Basis(Vector3.BACK, _rng.randf_range(-0.38, 0.38))
			var tall := h * 0.15 + _rng.randf_range(0.0, 0.1)
			fabric.box("coping", Transform3D(lean, q + Vector3(0.0, h * 0.9 + tall * 0.3, 0.0)),
					Vector3(_rng.randf_range(0.15, 0.22), tall, _rng.randf_range(0.34, 0.44)), tint.darkened(_rng.randf_range(0.04, 0.2)))
	fabric.lift = Vector3.ZERO


## What a garden holds: beds of greens, a shed at the far end, the woodpile, the washing out,
## a fruit tree -- a few of them, never all, and each garden its own.
func _garden(fabric: FabricMesh, h: Dictionary, g: Dictionary) -> void:
	var c: Vector2 = g["c"]
	var u: Vector2 = g["u"]
	var v: Vector2 = g["v"]
	var hw := float(g["hw"])
	var hd := float(g["hd"])
	if hd < 1.5 or hw < 1.5:
		return
	# beds of greens along the garden, a path of beaten earth down the middle
	if culture in ["vale", "woodfolk", "lakefolk"] and _rng.randf() < 0.75:
		var beds := clampi(int(hw * 2.0 / 1.6), 1, 4)
		var bed_len := hd * 1.2
		for i in range(beds):
			var x := -hw + 0.9 + (hw * 2.0 - 1.8) * (float(i) + 0.5) / float(beds)
			if absf(x) < 0.6:
				continue
			var mid := c + u * x - v * (hd * 0.1)
			var p := _on_ground(mid)
			# laid down the fall of the ground along it, as a bed is dug: level, a garden at a
			# pad's edge had one end of its bed in the bank (tools_gd/paving_probe.gd)
			var head := _ground_at(mid + v * (bed_len * 0.5))
			var foot := _ground_at(mid - v * (bed_len * 0.5))
			p.y = maxf(p.y, (head + foot) * 0.5 - global_position.y)
			var along := Basis(Vector3.UP, atan2(-v.y, v.x)) * Basis(Vector3.BACK, atan2(head - foot, bed_len))
			# a bed is a box, set in the ground: it carries the far rings' lift as the made ground does
			fabric.lift = _foot_lift(mid - v * (bed_len * 0.5), mid + v * (bed_len * 0.5), 0.45)
			fabric.box("earth", Transform3D(along, p + Vector3(0.0, 0.04, 0.0)), Vector3(bed_len, 0.16, 0.9), Color(0.72, 0.64, 0.56))
			fabric.lift = Vector3.ZERO
			_crop(fabric, CROPS[_rng.randi_range(0, CROPS.size() - 1)], mid, v, bed_len)
		_lay(fabric, "earth", StreetPlan.corners(StreetPlan.box_facing(c, u, v, 0.45, hd - 0.2)), Color(0.9, 0.86, 0.8))
	# a shed or a privy at the far end, in a corner
	if hd > 3.5 and _rng.randf() < 0.55:
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		var at := c + u * side * (hw - 1.3) + v * (hd - 1.2)
		_shed(fabric, at, u, v)
	# the woodpile against the back wall of the house
	if _rng.randf() < 0.5:
		var at2 := c + u * _rng.randf_range(-hw + 1.2, hw - 1.2) - v * (hd - 0.5)
		_woodpile(fabric, at2, u)
	# the washing out on a line across the garden
	if _rng.randf() < 0.3 and hw > 2.0:
		_washing(fabric, c + v * (hd * 0.35), u, hw)
	# an apple tree in a Vale garden
	if culture == "vale" and _rng.randf() < 0.25:
		var trees := tree_paths(FRUIT_TREE)
		if not trees.is_empty():
			_put(trees[_rng.randi_range(0, trees.size() - 1)], _on_ground(c + u * _rng.randf_range(-hw * 0.5, hw * 0.5) + v * (hd * 0.5)),
					_rng.randf() * TAU, Vector3.ONE * _rng.randf_range(0.7, 0.9))


## What a bed of a cottage garden grows, each drawn as the thing it is: a cube of green read as a
## crate of limes.
const CROPS := ["cabbages", "leeks", "beans", "potatoes"]


## One bed's crop, planted down its length (`v`, `bed_len` long, 0.9 m across) from `mid`. The
## leaves and blades are cards, in the garden's own mesh (`GARDEN`): a Vale town's crops as boxes
## were two hundred thousand triangles, most of the settlement's, drawn whole wherever you stood.
func _crop(fabric: FabricMesh, crop: String, mid: Vector2, v: Vector2, bed_len: float) -> void:
	var u := Vector2(v.y, -v.x)
	var top := 0.12
	match crop:
		"cabbages":
			var n := maxi(1, int(bed_len / 0.62))
			for j in range(n):
				for x in [-0.2, 0.2]:
					var q := _on_ground(mid + v * (-bed_len * 0.5 + (float(j) + 0.5) * bed_len / float(n)) + u * float(x))
					_cabbage(fabric, q + Vector3(0.0, top, 0.0), Color(0.4, 0.55, 0.42).lerp(Color(0.5, 0.6, 0.36), _rng.randf()))
		"leeks":
			var n := maxi(1, int(bed_len / 0.42))
			var green := Color(0.4, 0.54, 0.32)
			for j in range(n):
				for x in [-0.18, 0.18]:
					var q := _on_ground(mid + v * (-bed_len * 0.5 + (float(j) + 0.5) * bed_len / float(n)) + u * float(x))
					var turn := _rng.randf() * TAU
					for k in range(3):
						var yaw := turn + TAU * float(k) / 3.0
						# a blade stands up out of the soil and leans away from the others
						var lean := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, -0.22)
						fabric.card(GARDEN, Transform3D(lean, q + Vector3(0.0, top + 0.17, 0.0) + Basis(Vector3.UP, yaw) * Vector3(0.03, 0.0, 0.0)),
								Vector2(0.045, 0.34), FabricMesh.shade(green, _rng.randf_range(0.85, 1.12)))
		"beans":
			# a row of cane wigwams down the bed, a ridge cane along the top, the vines up them
			var n := maxi(2, int(bed_len / 0.6) + 1)
			var cane := Color(0.66, 0.58, 0.42)
			var leaf := Color(0.33, 0.5, 0.24)
			var ends: Array[Vector3] = []
			for j in range(n):
				var s := -bed_len * 0.5 + 0.15 + (bed_len - 0.3) * float(j) / float(n - 1)
				var apex := _on_ground(mid + v * s) + Vector3(0.0, 1.75, 0.0)
				ends.append(apex)
				for side in [-1.0, 1.0]:
					var foot := _on_ground(mid + v * s + u * (0.38 * float(side))) + Vector3(0.0, top, 0.0)
					_pole(fabric, foot, apex, 0.018, cane, GARDEN)
					for k in range(4):
						var t := 0.2 + 0.2 * float(k) + _rng.randf_range(-0.05, 0.05)
						fabric.card(GARDEN, Transform3D(Basis(Vector3.UP, _rng.randf() * TAU) * Basis(Vector3.RIGHT, _rng.randf_range(-0.5, 0.5)),
								foot.lerp(apex, t)), Vector2(0.2, 0.16), FabricMesh.shade(leaf, _rng.randf_range(0.82, 1.15)))
			_pole(fabric, ends[0], ends[-1], 0.016, cane, GARDEN)
		_:
			# potatoes, earthed up: a low ridge down the bed with the haulms bushing out of it
			# down the fall of its bed, as the bed is laid (`_garden`)
			var head := _ground_at(mid + v * (bed_len * 0.5))
			var foot := _ground_at(mid - v * (bed_len * 0.5))
			var at := _on_ground(mid)
			at.y = maxf(at.y, (head + foot) * 0.5 - global_position.y)
			var along := Basis(Vector3.UP, atan2(-v.y, v.x)) * Basis(Vector3.BACK, atan2(head - foot, bed_len))
			fabric.box("earth", Transform3D(along * Basis(Vector3.RIGHT, PI * 0.25), at + Vector3(0.0, top, 0.0)),
					Vector3(bed_len * 0.96, 0.3, 0.3), Color(0.62, 0.54, 0.46))
			var n := maxi(1, int(bed_len / 0.42))
			for j in range(n):
				var q := _on_ground(mid + v * (-bed_len * 0.5 + (float(j) + 0.5) * bed_len / float(n)))
				var turn := _rng.randf() * TAU
				for k in range(2):
					fabric.card(GARDEN, Transform3D(Basis(Vector3.UP, turn + float(k) * 1.57) * Basis(Vector3.RIGHT, -PI * 0.5 + _rng.randf_range(-0.35, 0.35)),
							q + Vector3(0.0, top + 0.24, 0.0)), Vector2(0.44, 0.22),
							FabricMesh.shade(Color(0.3, 0.45, 0.22), _rng.randf_range(0.85, 1.12)))


## A cabbage: a pale heart in a ring of leaves turned up at the edge.
func _cabbage(fabric: FabricMesh, at: Vector3, green: Color) -> void:
	var turn := _rng.randf() * TAU
	fabric.box(GARDEN, Transform3D(Basis(Vector3.UP, turn), at + Vector3(0.0, 0.1, 0.0)), Vector3(0.17, 0.15, 0.17),
			FabricMesh.shade(green, 1.18))
	for k in range(5):
		var yaw := turn + TAU * float(k) / 5.0 + _rng.randf_range(-0.2, 0.2)
		# a leaf lies out from the heart, its outer edge turned up: a card tipped back off the flat
		var leaf := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, _rng.randf_range(0.35, 0.6)) * Basis(Vector3.RIGHT, -PI * 0.5)
		fabric.card(GARDEN, Transform3D(leaf, at + Basis(Vector3.UP, yaw) * Vector3(0.13, 0.08, 0.0)), Vector2(0.24, 0.2),
				FabricMesh.shade(green, _rng.randf_range(0.8, 1.0)))


## A pole from `a` to `b`, `r` thick, in `key`.
func _pole(fabric: FabricMesh, a: Vector3, b: Vector3, r: float, tint: Color, key := "joinery") -> void:
	var d := b - a
	if d.length() < 0.01:
		return
	var x := d.normalized()
	var side := x.cross(Vector3.UP)
	if side.length() < 0.01:
		side = x.cross(Vector3.RIGHT)
	var z := side.normalized()
	var y := z.cross(x)
	fabric.box(key, Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(d.length(), r * 2.0, r * 2.0), tint)


## A lean-to shed of boards, its roof falling to the back.
func _shed(fabric: FabricMesh, at: Vector2, u: Vector2, v: Vector2) -> void:
	var orient := Basis(Vector3(u.x, 0.0, u.y), Vector3.UP, Vector3(v.x, 0.0, v.y))
	var p := _on_ground(at)
	var tint := FabricMesh.shade(RAIL_TINT, _rng.randf_range(0.85, 1.1))
	fabric.lift = _foot_lift(at - u * 0.95, at + u * 0.95, 0.8)
	fabric.box("joinery", Transform3D(orient, p + Vector3(0.0, 1.0, 0.0)), Vector3(1.8, 2.0, 1.5), tint)
	fabric.box("roof", Transform3D(orient * Basis(Vector3.RIGHT, 0.28), p + Vector3(0.0, 2.12, 0.0)),
			Vector3(2.2, 0.1, 1.9))
	fabric.box("joinery", Transform3D(orient, p + orient * Vector3(0.0, 0.85, -0.76)), Vector3(0.7, 1.7, 0.04), tint.darkened(0.35))
	# the joints of its boards, and the corner posts they are nailed to
	var joint := tint.darkened(0.3)
	for k in range(5):
		var x := -0.72 + 0.36 * float(k)
		if absf(x) > 0.4:
			fabric.box("joinery", Transform3D(orient, p + orient * Vector3(x, 1.0, -0.755)), Vector3(0.03, 2.0, 0.02), joint)
		fabric.box("joinery", Transform3D(orient, p + orient * Vector3(x, 1.0, 0.755)), Vector3(0.03, 2.0, 0.02), joint)
	for k in range(3):
		var z := -0.375 + 0.375 * float(k)
		for side in [-1.0, 1.0]:
			fabric.box("joinery", Transform3D(orient, p + orient * Vector3(0.905 * float(side), 1.0, z)), Vector3(0.02, 2.0, 0.03), joint)
	for cx in [-0.9, 0.9]:
		for cz in [-0.75, 0.75]:
			fabric.box("joinery", Transform3D(orient, p + orient * Vector3(float(cx), 1.0, float(cz))), Vector3(0.09, 2.02, 0.09), joint)
	fabric.lift = Vector3.ZERO
	_body(p + Vector3(0.0, 1.0, 0.0), orient, Vector3(1.8, 2.0, 1.5), _yard_bodies)


## Split logs stacked against a wall, their sawn ends out: rounds, not bricks.
func _woodpile(fabric: FabricMesh, at: Vector2, u: Vector2) -> void:
	var orient := Basis(Vector3.UP, atan2(-u.y, u.x))
	# a log lies along the prism's X: turned a right angle, it runs out from the wall
	var log_turn := orient * Basis(Vector3.UP, PI * 0.5)
	var p := _on_ground(at)
	var r := 0.1
	for row in range(4):
		var n := 6 if row % 2 == 0 else 5
		for i in range(n):
			var x := -r * float(n - 1) + float(i) * r * 2.0
			var y := r + float(row) * r * 1.74
			var bark := FabricMesh.shade(Color(0.36, 0.28, 0.2), _rng.randf_range(0.85, 1.15))
			var sawn := FabricMesh.shade(Color(0.8, 0.66, 0.46), _rng.randf_range(0.85, 1.08))
			fabric.prism(GARDEN, Transform3D(log_turn, p + orient * Vector3(x, y, _rng.randf_range(-0.04, 0.04))),
					r * _rng.randf_range(0.88, 1.0), 0.55, bark, sawn, 6)


## Two props and a line, and what is pegged out on it.
func _washing(fabric: FabricMesh, at: Vector2, u: Vector2, hw: float) -> void:
	var orient := Basis(Vector3.UP, atan2(-u.y, u.x))
	var reach := minf(hw - 0.6, 3.0)
	var a := _on_ground(at - u * reach)
	var b := _on_ground(at + u * reach)
	fabric.lift = _foot_lift(at - u * reach, at + u * reach, 0.1)
	for p in [a, b]:
		fabric.box("joinery", Transform3D(orient, (p as Vector3) + Vector3(0.0, 1.0, 0.0)), Vector3(0.07, 2.0, 0.07), RAIL_TINT)
	var mid := (a + b) * 0.5
	fabric.box("joinery", Transform3D(orient, mid + Vector3(0.0, 1.9, 0.0)), Vector3(reach * 2.0, 0.02, 0.02), Color(0.7, 0.66, 0.58))
	fabric.lift = Vector3.ZERO
	var colours := [Color(0.9, 0.88, 0.82), Color(0.62, 0.7, 0.8), Color(0.8, 0.62, 0.52), Color(0.86, 0.84, 0.7)]
	var n := int(reach * 2.0 / 0.9)
	for i in range(n):
		var q := a.lerp(b, (float(i) + 0.5) / float(n))
		var size := Vector3(_rng.randf_range(0.4, 0.7), _rng.randf_range(0.45, 0.8), 0.03)
		fabric.card(GARDEN, Transform3D(orient, q + Vector3(0.0, 1.9 - size.y * 0.5, 0.0)), Vector2(size.x, size.y),
				colours[_rng.randi_range(0, colours.size() - 1)])


# --- made ground ----------------------------------------------------------------------------------

## The ground people have made: between each house and the road, setts in a town and a beaten
## path to the door in a village; the yard behind a town house; the lanes.
func _ground(fabric: FabricMesh) -> void:
	var paved := kind in PAVED_KINDS
	if paved:
		await _carriageway(fabric)
	elif not street.laid.is_empty():
		await _carriageway(fabric, "earth", true)
	# the lanes back between the gardens: a beaten track, flagged in a city
	for lane in street.lanes:
		_lay(fabric, "paving" if kind == "city" else "earth", StreetPlan.corners(lane), Color(0.95, 0.92, 0.88))
	await _pace("lanes")
	for h in street.houses:
		await _pace("front")
		var plot: Dictionary = h
		var b: Dictionary = plot["box"]
		var u: Vector2 = b["u"]
		var v: Vector2 = b["v"]
		var door: Vector2 = plot["door"]
		var setback := float(plot.get("setback", 2.0))
		# from inside the road's edge to the front wall: over the carriageway's own edge, which
		# lies lower, so there is never a line of grass between them
		var depth := setback + 0.6
		var front := door - v * (setback * 0.5 + 0.3)
		if paved:
			var hw := float(b["hw"]) + 0.6
			var along := (b["c"] as Vector2) - door
			var mid := front + u * along.dot(u)
			_lay(fabric, "paving", StreetPlan.corners(StreetPlan.box_facing(mid, u, v, hw, depth * 0.5)), Color.WHITE)
		else:
			# the path to the door, and a strip of beaten ground along the front of the house
			_lay(fabric, "earth", StreetPlan.corners(StreetPlan.box_facing(front, u, v, 0.7, depth * 0.5)), Color.WHITE)
			var mid2 := (b["c"] as Vector2) - v * (float(b["hd"]) + 0.45)
			_lay(fabric, "earth", StreetPlan.corners(StreetPlan.box_facing(mid2, u, v, float(b["hw"]) + 0.2, 0.45)),
					Color(1.0, 0.97, 0.93))
			_flowers(b, door)
		# the yard behind the house, where the garden begins
		var g: Dictionary = plot.get("garden", {})
		if not g.is_empty() and float(g["hd"]) > 2.0:
			var yard_c := (b["c"] as Vector2) + v * (float(b["hd"]) + 1.1)
			_lay(fabric, "earth", StreetPlan.corners(StreetPlan.box_facing(yard_c, u, v, float(b["hw"]), 0.9)),
					Color(0.94, 0.9, 0.86))


## A town paves its carriageway too, between the square and the edge of the flattened ground: the
## same setts as the footways, a shade darker with the traffic, and a hair lower, so the footway
## laid over its edge is the one seen. A village's road stays the country road it is, except the
## street the plan laid where no road ran, which is beaten into a track (`only_laid`).
func _carriageway(fabric: FabricMesh, key := "paving", only_laid := false) -> void:
	var half := StreetPlan.ROAD_HALF_M - 0.35
	for li in range(street.lines.size()):
		if only_laid and not street.laid.has(li):
			continue
		var pts: PackedVector2Array = street.lines[li]
		for j in range(pts.size() - 1):
			await _pace("carriageway")
			var a := pts[j]
			var b := pts[j + 1]
			var seg := a.distance_to(b)
			if seg < 0.05:
				continue
			var dir := (b - a) / seg
			var steps := maxi(1, int(ceil(seg / 3.0)))
			for k in range(steps):
				var p0 := a + dir * (seg * float(k) / float(steps))
				var p1 := a + dir * (seg * float(k + 1) / float(steps))
				var mid := (p0 + p1) * 0.5
				var r := mid.distance_to(street.centre)
				if r < street.hub + 1.4 or r > pad_radius - 1.5:
					continue
				var c := StreetPlan.corners(StreetPlan.box(mid, dir, p0.distance_to(p1) * 0.5 + 0.03, half))
				_ground_quad(fabric, key, c[0], c[1], c[2], c[3], Color(0.88, 0.86, 0.83), CARRIAGEWAY_LIFT_M)


## A border of the country's own flowers along a cottage's front wall, either side of its path.
func _flowers(b: Dictionary, door: Vector2) -> void:
	var names: Array = FLOWERS_BY_CULTURE.get(culture, [])
	if names.is_empty():
		return
	var u: Vector2 = b["u"]
	var v: Vector2 = b["v"]
	var hw := float(b["hw"])
	var front := (b["c"] as Vector2) - v * (float(b["hd"]) + 0.55)
	var along_door := (door - (b["c"] as Vector2)).dot(u)
	var n := int(hw * 2.0 / 0.55)
	for i in range(n):
		var x := -hw + 0.3 + (hw * 2.0 - 0.6) * (float(i) + 0.5) / float(n)
		if absf(x - along_door) < 0.9 or _ground_rng.randf() < 0.25:
			continue
		var flower := str(names[_ground_rng.randi_range(0, names.size() - 1)])
		var path := "res://assets/models/flora/%s_a/%s_a.glb" % [flower, flower]
		if ResourceLoader.exists(path):
			_put(path, _on_ground(front + u * x + v * _ground_rng.randf_range(-0.15, 0.15)),
					_ground_rng.randf() * TAU, Vector3.ONE * _ground_rng.randf_range(0.8, 1.15))


## A patch of made ground on the terrain: the quad `corners` (world xz), cut into cells of at most
## `cell` metres so it lies on the ground rather than bridging it.
func _lay(fabric: FabricMesh, key: String, corners: PackedVector2Array, tint: Color, cell := 3.0) -> void:
	var a := corners[0]
	var b := corners[1]
	var c := corners[2]
	var d := corners[3]
	var nu := maxi(1, int(ceil(a.distance_to(b) / cell)))
	var nv := maxi(1, int(ceil(a.distance_to(d) / cell)))
	for i in range(nu):
		for j in range(nv):
			var p00 := _bilerp(a, b, c, d, float(i) / nu, float(j) / nv)
			var p10 := _bilerp(a, b, c, d, float(i + 1) / nu, float(j) / nv)
			var p11 := _bilerp(a, b, c, d, float(i + 1) / nu, float(j + 1) / nv)
			var p01 := _bilerp(a, b, c, d, float(i) / nu, float(j + 1) / nv)
			_ground_quad(fabric, key, p00, p10, p11, p01, tint)


static func _bilerp(a: Vector2, b: Vector2, c: Vector2, d: Vector2, s: float, t: float) -> Vector2:
	return a.lerp(b, s).lerp(d.lerp(c, s), t)


func _ground_quad(fabric: FabricMesh, key: String, p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2,
		tint: Color, lift := GROUND_LIFT_M) -> void:
	# no two patches of made ground are quite the same shade: wear, damp, a newer repair
	tint = FabricMesh.shade(tint, 0.94 + 0.1 * _ground_rng.randf())
	_fit_quad(fabric, key, p0, p1, p2, p3, tint, lift)


## A patch of made ground drawn flat between its corners, split where the ground under it does not
## lie flat, and raised where it is still under the ground (`_ground_short`).
func _fit_quad(fabric: FabricMesh, key: String, p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2,
		tint: Color, lift: float) -> void:
	var q := [_on_ground(p0, lift), _on_ground(p1, lift), _on_ground(p2, lift), _on_ground(p3, lift)]
	var short := _ground_short(p0, p1, p2, p3, q, lift)
	if short > GROUND_FIT_M and p0.distance_to(p2) > GROUND_SPLIT_MIN_M * 1.5:
		var m01 := p0.lerp(p1, 0.5)
		var m12 := p1.lerp(p2, 0.5)
		var m23 := p2.lerp(p3, 0.5)
		var m30 := p3.lerp(p0, 0.5)
		var mid := _bilerp(p0, p1, p2, p3, 0.5, 0.5)
		_fit_quad(fabric, key, p0, m01, mid, m30, tint, lift)
		_fit_quad(fabric, key, m01, p1, m12, mid, tint, lift)
		_fit_quad(fabric, key, mid, m12, p2, m23, tint, lift)
		_fit_quad(fabric, key, m30, mid, m23, p3, tint, lift)
		return
	if short > 0.0:
		for i in 4:
			q[i] = (q[i] as Vector3) + Vector3(0.0, short, 0.0)
	# front faces wind clockwise seen from above; turn the quad over if it came the other way
	var up: Vector3 = ((q[2] as Vector3) - (q[0] as Vector3)).cross((q[1] as Vector3) - (q[0] as Vector3))
	if up.y < 0.0:
		q = [q[0], q[3], q[2], q[1]]
	fabric.carry_lift(key)
	fabric.quad_lifted(key, q[0], q[1], q[2], q[3], tint, _far_lift(q, lift))


## How far the patch `q` (laid, in this node's space) must stand up to be `lift` over the terrain
## as its clipmap's far rings draw it, a vertex every 4, 8 and 16 m (x, y, z), a few hundred metres
## off, where they cut the corner of a pad's lip: 0.8 m at Skarlow on the 8 m ring. The paving's
## shader lifts it by as much as the terrain under it has come to that ring, so close up it lies
## where `_fit_quad` put it. Zero where every vertex of the ring round the patch is below it.
func _far_lift(q: Array, lift: float) -> Vector3:
	var out := Vector3.ZERO
	var w: Array[Vector3] = []
	var lo := INF
	for c in q:
		w.append((c as Vector3) + global_position)
		lo = minf(lo, w[-1].y)
	var x0 := minf(minf(w[0].x, w[1].x), minf(w[2].x, w[3].x))
	var x1 := maxf(maxf(w[0].x, w[1].x), maxf(w[2].x, w[3].x))
	var z0 := minf(minf(w[0].z, w[1].z), minf(w[2].z, w[3].z))
	var z1 := maxf(maxf(w[0].z, w[1].z), maxf(w[2].z, w[3].z))
	for r in 3:
		var step := _ground_vertex_m() * float(2 << r)
		var hi := -INF
		# The ring's surface less the patch's is flat between the ring's grid lines and diagonals
		# (both ways) and the patch's edges and the diagonal its triangles meet on, so it is highest
		# where those cross: the patch's corners, where its edges cross the ring's lines, and the
		# ring's vertices and the middles of its quads inside it. (Every half metre along the edges
		# missed 0.3 m of a steep bank's triangle at Skarlow.)
		var at: Array[Vector2] = []
		for gx in range(int(floorf(x0 / step)), int(ceilf(x1 / step)) + 1):
			for gz in range(int(floorf(z0 / step)), int(ceilf(z1 / step)) + 1):
				var v := Vector2(float(gx) * step, float(gz) * step)
				hi = maxf(hi, _vertex_height(v.x, v.y))
				for m in [v, v + Vector2(step, step) * 0.5]:
					if m.x > x0 and m.x < x1 and m.y > z0 and m.y < z1:
						at.append(m)
		if hi + lift <= lo:
			continue
		for e in [[0, 1], [1, 2], [2, 3], [3, 0], [0, 2]]:
			var e0 := Vector2(w[e[0]].x, w[e[0]].z)
			var e1 := Vector2(w[e[1]].x, w[e[1]].z)
			at.append(e0)
			# x, z, x - z and x + z at every whole step: the ring's lines and diagonals
			for f in [Vector2(1.0, 0.0), Vector2(0.0, 1.0), Vector2(1.0, -1.0), Vector2(1.0, 1.0)]:
				var f0 := e0.dot(f) / step
				var f1 := e1.dot(f) / step
				if absf(f1 - f0) < 1e-6:
					continue
				for line in range(int(ceilf(minf(f0, f1))), int(floorf(maxf(f0, f1))) + 1):
					at.append(e0.lerp(e1, (float(line) - f0) / (f1 - f0)))
		var short := 0.0
		for s in at:
			var y := _plane_y(s, w[0], w[1], w[2])
			if is_nan(y):
				y = _plane_y(s, w[0], w[2], w[3])
			if not is_nan(y):
				short = maxf(short, _ring_surface(s, step) + lift - y)
		out[r] = short
	return out


## How far a thing standing on the ground from `a` to `b` (world xz, `half_w` either side of that
## line: a wall's length, a fence's span, a post) must stand up where the terrain draws a vertex every
## 4, 8 and 16 m (x, y, z): the most that ring's surface comes over the ground it stands on, along
## its line and its two sides every half metre. Zero at once where no vertex of a ring round it is
## above the ground there, which is nearly everywhere. (Triage 31: Skarlow's drystone against its
## crag 4.4 m into the 4 m ring, Kharrow's 1.4 m into the 8 m, Grandfather Hollow's posts 0.6 m.)
func _foot_lift(a: Vector2, b: Vector2, half_w: float) -> Vector3:
	var out := Vector3.ZERO
	var vm := _ground_vertex_m()
	var along := (b - a).normalized() if a.distance_squared_to(b) > 1e-8 else Vector2(1.0, 0.0)
	# a little past each end: the pieces overlap the next
	a -= along * FOOT_OVER_M
	b += along * FOOT_OVER_M
	var side := Vector2(-along.y, along.x)
	var across := side * half_w
	var corners: Array[Vector2] = [a + across, b + across, b - across, a - across]
	var lo := INF
	var x0 := INF
	var x1 := -INF
	var z0 := INF
	var z1 := -INF
	for c in corners:
		x0 = minf(x0, c.x)
		x1 = maxf(x1, c.x)
		z0 = minf(z0, c.y)
		z1 = maxf(z1, c.y)
	# the ground under it is nowhere lower than its lowest vertex round it
	for gx in range(int(floorf(x0 / vm)), int(ceilf(x1 / vm)) + 1):
		for gz in range(int(floorf(z0 / vm)), int(ceilf(z1 / vm)) + 1):
			lo = minf(lo, _vertex_height(float(gx) * vm, float(gz) * vm))
	var length := a.distance_to(b)
	var inside := func(p: Vector2) -> bool:
		var d := p - a
		return d.dot(along) >= 0.0 and d.dot(along) <= length and absf(d.dot(side)) <= half_w
	for r in 3:
		var step := vm * float(2 << r)
		var hi := -INF
		for gx in range(int(floorf(x0 / step)), int(ceilf(x1 / step)) + 1):
			for gz in range(int(floorf(z0 / step)), int(ceilf(z1 / step)) + 1):
				hi = maxf(hi, _vertex_height(float(gx) * step, float(gz) * step))
		if hi <= lo:
			continue
		# The ring's surface less the ground's is flat between the two meshes' lines, so it is highest
		# at the footprint's corners, where its edges cross either mesh's grid lines and diagonals, and
		# at the meshes' vertices (and the ring's quad middles) inside it; and every half metre over
		# it besides, for the crossings of the two inside.
		var at: Array[Vector2] = corners.duplicate()
		var nu := maxi(1, int(ceil(length / FOOT_STEP_M)))
		var nv := maxi(2, int(ceil(half_w * 2.0 / FOOT_STEP_M)))
		for i in range(nu + 1):
			for j in range(nv + 1):
				at.append(a + along * (length * float(i) / float(nu)) + across * (2.0 * float(j) / float(nv) - 1.0))
		for each in [step, vm]:
			var gs: float = each
			for gx in range(int(floorf(x0 / gs)), int(ceilf(x1 / gs)) + 1):
				for gz in range(int(floorf(z0 / gs)), int(ceilf(z1 / gs)) + 1):
					var v := Vector2(float(gx) * gs, float(gz) * gs)
					for m in [v, v + Vector2(gs, gs) * 0.5]:
						if inside.call(m):
							at.append(m)
			for k in 4:
				var e0 := corners[k]
				var e1 := corners[(k + 1) % 4]
				for f in [Vector2(1.0, 0.0), Vector2(0.0, 1.0), Vector2(1.0, -1.0), Vector2(1.0, 1.0)]:
					var f0: float = e0.dot(f) / gs
					var f1: float = e1.dot(f) / gs
					if absf(f1 - f0) < 1e-6:
						continue
					for line in range(int(ceilf(minf(f0, f1))), int(floorf(maxf(f0, f1))) + 1):
						at.append(e0.lerp(e1, (float(line) - f0) / (f1 - f0)))
		var short := 0.0
		for s in at:
			short = maxf(short, _ring_surface(s, step) - _vertex_surface(s, vm))
		out[r] = short
	return out


## The terrain at `s` drawn on a vertex every `step` metres, a quad of them split either way: its
## coarser rings split their quads one way and the next the other, so the higher of the two.
func _ring_surface(s: Vector2, step: float) -> float:
	var fx := s.x / step
	var fz := s.y / step
	var x0 := floorf(fx)
	var z0 := floorf(fz)
	var h00 := _vertex_height(x0 * step, z0 * step)
	var h10 := _vertex_height((x0 + 1.0) * step, z0 * step)
	var h01 := _vertex_height(x0 * step, (z0 + 1.0) * step)
	var h11 := _vertex_height((x0 + 1.0) * step, (z0 + 1.0) * step)
	return maxf(TerrainProvider.triangle_height(h00, h10, h01, h11, fx - x0, fz - z0),
			TerrainProvider.triangle_height(h10, h00, h11, h01, 1.0 - (fx - x0), fz - z0))


## How far the patch of made ground with corners `p0`..`p3` (world xz; `q` the same corners laid,
## in this node's space) falls short of standing `lift` over the ground anywhere under it, the
## ground taken as the terrain draws it (`_drawn_ground`): at its corners, its middle and every
## terrain vertex under it, and, unless those say the ground is level there (a pad's middle, which
## is nearly all of a town), along its edges and its diagonal (the line its two triangles meet on)
## every GROUND_EDGE_STEP_M.
func _ground_short(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, q: Array, lift: float) -> float:
	var gy := global_position.y
	var lo := INF
	var hi := -INF
	for c in q:
		lo = minf(lo, (c as Vector3).y + gy - lift)
		hi = maxf(hi, (c as Vector3).y + gy - lift)
	# the terrain's vertices under the patch, and its corners and middle as the terrain draws them
	var at: Array[Vector2] = [p0, p1, p2, p3, _bilerp(p0, p1, p2, p3, 0.5, 0.5)]
	var step := _ground_vertex_m()
	var x0 := minf(minf(p0.x, p1.x), minf(p2.x, p3.x))
	var x1 := maxf(maxf(p0.x, p1.x), maxf(p2.x, p3.x))
	var z0 := minf(minf(p0.y, p1.y), minf(p2.y, p3.y))
	var z1 := maxf(maxf(p0.y, p1.y), maxf(p2.y, p3.y))
	for gx in range(int(ceilf(x0 / step)), int(floorf(x1 / step)) + 1):
		for gz in range(int(ceilf(z0 / step)), int(floorf(z1 / step)) + 1):
			at.append(Vector2(float(gx) * step, float(gz) * step))
	var drawn: Array[float] = []
	for s in at:
		var h := _drawn_ground(s)
		drawn.append(h)
		hi = maxf(hi, h)
	if hi - lo < GROUND_LEVEL_M:
		return 0.0
	for e in [[p0, p1], [p1, p2], [p2, p3], [p3, p0], [p0, p2]]:
		var e0: Vector2 = e[0]
		var e1: Vector2 = e[1]
		var n := maxi(1, int(ceilf(e0.distance_to(e1) / GROUND_EDGE_STEP_M)))
		for k in range(1, n):
			var s := e0.lerp(e1, float(k) / float(n))
			at.append(s)
			drawn.append(_drawn_ground(s))
	var a := (q[0] as Vector3) + global_position
	var b := (q[1] as Vector3) + global_position
	var c3 := (q[2] as Vector3) + global_position
	var d := (q[3] as Vector3) + global_position
	var short := 0.0
	for i in at.size():
		# on the patch's triangles (a, b, c) and (a, c, d), as FabricMesh.quad draws it
		var y := _plane_y(at[i], a, b, c3)
		if is_nan(y):
			y = _plane_y(at[i], a, c3, d)
		if not is_nan(y):
			short = maxf(short, drawn[i] + lift - y)
	return short


## The height at `s` (xz) of the triangle (a, b, c) seen from above, or NAN off it.
static func _plane_y(s: Vector2, a: Vector3, b: Vector3, c: Vector3) -> float:
	var v0 := Vector2(b.x - a.x, b.z - a.z)
	var v1 := Vector2(c.x - a.x, c.z - a.z)
	var v2 := Vector2(s.x - a.x, s.y - a.z)
	var den := v0.x * v1.y - v1.x * v0.y
	if absf(den) < 1e-9:
		return NAN
	var u := (v2.x * v1.y - v1.x * v2.y) / den
	var v := (v0.x * v2.y - v2.x * v0.y) / den
	if u < -1e-4 or v < -1e-4 or u + v > 1.0 + 1e-4:
		return NAN
	return a.y + (b.y - a.y) * u + (c.y - a.y) * v


## The ground at `s` as the terrain draws it here: the highest of its height there, of its surface
## on its own vertices (every `_ground_vertex_m`, on the two triangles a quad of them is split
## into), and of that surface on every other vertex, which is how its next clipmap ring out draws it
## (the edge of a big town's pad is in that ring from its square).
func _drawn_ground(s: Vector2) -> float:
	# a corner is every patch's round it: asked once
	var key := Vector2i(roundi(s.x * 100.0), roundi(s.y * 100.0))
	if not _drawn_heights.has(key):
		var step := _ground_vertex_m()
		_drawn_heights[key] = maxf(_ground_at(s), maxf(_vertex_surface(s, step), _vertex_surface(s, step * 2.0)))
	return float(_drawn_heights[key])


func _vertex_surface(s: Vector2, step: float) -> float:
	var fx := s.x / step
	var fz := s.y / step
	var x0 := floorf(fx)
	var z0 := floorf(fz)
	return TerrainProvider.triangle_height(_vertex_height(x0 * step, z0 * step),
			_vertex_height((x0 + 1.0) * step, z0 * step), _vertex_height(x0 * step, (z0 + 1.0) * step),
			_vertex_height((x0 + 1.0) * step, (z0 + 1.0) * step), fx - x0, fz - z0)


func _vertex_height(x: float, z: float) -> float:
	var key := Vector2i(roundi(x * 4.0), roundi(z * 4.0))
	if not _vertex_heights.has(key):
		_vertex_heights[key] = _ground_at(Vector2(x, z))
	return float(_vertex_heights[key])


## The terrain's own vertex spacing: the build's texel (TerrainProvider's manifest), 2 m.
func _ground_vertex_m() -> float:
	if _vertex_m <= 0.0:
		_vertex_m = 2.0
		var provider: Object = World.terrain()
		if provider != null and "manifest" in provider:
			_vertex_m = maxf(float((provider.get("manifest") as Dictionary).get("spacing_m", 2.0)), 0.5)
	return _vertex_m


## A disc of made ground: the square, or the round of beaten earth under the well.
func _lay_disc(fabric: FabricMesh, key: String, at: Vector2, r: float, tint: Color) -> void:
	var rings := maxi(1, int(ceil(r / 3.0)))
	var segs := clampi(int(r * 2.0), 12, 40)
	for ring in range(rings):
		var r0 := r * float(ring) / float(rings)
		var r1 := r * float(ring + 1) / float(rings)
		for s in range(segs):
			var a0 := TAU * float(s) / float(segs)
			var a1 := TAU * float(s + 1) / float(segs)
			var p00 := at + Vector2(sin(a0), cos(a0)) * r0
			var p01 := at + Vector2(sin(a1), cos(a1)) * r0
			var p10 := at + Vector2(sin(a0), cos(a0)) * r1
			var p11 := at + Vector2(sin(a1), cos(a1)) * r1
			_ground_quad(fabric, key, p00, p10, p11, p01, tint)


# --- the middle -------------------------------------------------------------------------------------

## Where the roads cross: in a town the market square, paved, with its stalls round the edge,
## its well or cross and its lamps; in a village the green, with the well, a tree and benches.
func _middle(fabric: FabricMesh) -> void:
	var at := street.centre
	var hub := street.hub
	var wedges := street.wedges()
	var square := kind in SQUARE_KINDS
	if square:
		_lay_disc(fabric, "paving", at, hub + 1.2, Color.WHITE)
	# the well in the widest gap between the streets, clear of the roads
	var first: Dictionary = wedges[0]
	var well_at := _clear_point(float(first["bearing"]), hub * 0.55, 4.5)
	if well_at != Vector2.INF:
		if culture == "reedfolk":
			_put_kind("lantern_standing", _on_ground(well_at), 0.0, "brightwater")
		elif culture == "lakefolk":
			_cross(fabric, well_at)
			_features["cross"] = _on_ground(well_at)
		elif culture == "clans":
			var stone := "res://assets/models/rocks/skerrow_standing_stone/skerrow_standing_stone.glb"
			if ResourceLoader.exists(stone):
				_put(stone, _on_ground(well_at), _rng.randf() * TAU, Vector3.ONE * 0.8)
			_features["cross"] = _on_ground(well_at)
		else:
			_put_kind("well", _on_ground(well_at), _rng.randf() * TAU)
			if not square:
				_lay_disc(fabric, "earth", well_at, 2.6, Color.WHITE)
		_features["well"] = _on_ground(well_at)
	# a tree on a green, in the second gap
	if not square and wedges.size() >= 1 and GREEN_TREE.has(culture):
		var tw: Dictionary = wedges[1] if wedges.size() > 1 else wedges[0]
		var tree_at := _clear_point(float(tw["bearing"]) + (0.0 if wedges.size() > 1 else 60.0), hub * 0.62, 5.0)
		var trees := tree_paths(str(GREEN_TREE[culture]))
		if tree_at != Vector2.INF and not trees.is_empty():
			_put(trees[0], _on_ground(tree_at), _rng.randf() * TAU, Vector3.ONE * _rng.randf_range(0.8, 0.95))
	# benches round the well, facing it
	var benches: Array = []
	if well_at != Vector2.INF:
		for k in range(2):
			var a := _rng.randf() * TAU
			var p := well_at + Vector2(sin(a), cos(a)) * 3.4
			if street.road_distance(p) > StreetPlan.ROAD_HALF_M + 1.2:
				_put_kind("bench", _on_ground(p), atan2(well_at.x - p.x, well_at.y - p.y) + PI)
				benches.append(_on_ground(p))
	_features["benches"] = benches
	_market(wedges)
	# the lamps at the mouths of the streets, a town's and a city's
	if kind in ["city", "town", "fort"]:
		for i in range(street.arms.size()):
			var side := 1.0 if i % 2 == 0 else -1.0
			var fr := street.frontage(i, hub + 1.5, side)
			var p2: Vector2 = fr["p"] + (fr["n"] as Vector2) * (StreetPlan.ROAD_HALF_M + 0.6)
			_put_kind("lantern_standing", _on_ground(p2), 0.0, "brightwater")


## The market's stalls round the edge of the square, facing into it, in the gaps between the
## streets; as many as there are people whose day has them keep one, and at least the kind's.
func _market(wedges: Array) -> void:
	var want := maxi(int(STALLS_BY_KIND.get(kind, 0)), _spot_names_like("stall").size())
	if want <= 0 or ruined:
		return
	var stalls: Array = []
	var r := street.hub - 2.2
	for wedge in wedges:
		if stalls.size() >= want:
			break
		var width := float(wedge["width"])
		var arc := deg_to_rad(width) * r
		var fit := int((arc - 8.0) / 3.4)
		var n := mini(fit, want - stalls.size())
		for i in range(n):
			var bearing := float(wedge["bearing"]) + (float(i) - float(n - 1) * 0.5) * rad_to_deg(3.4 / r)
			var p := street.hub_point(bearing, r)
			if street.road_distance(p) < StreetPlan.ROAD_HALF_M + 2.0 or street.is_reserved(p):
				continue
			var face := atan2(street.centre.x - p.x, street.centre.y - p.y)
			var g := _on_ground(p)
			# its front, the side the awning's valance hangs from, to the square
			_put_kind("market_stall", g, face, "brightwater")
			# the stallholder stands behind the counter, the square in front of them
			stalls.append(g - Vector3(sin(face), 0.0, cos(face)) * 1.2)
			# what is laid out on the counter, and what is stacked beside it
			var ahead := Vector3(sin(face), 0.0, cos(face))
			var along := Vector3(cos(face), 0.0, -sin(face))
			for k in range(3):
				var on := ["jug", "bowl", "loaf", "mug", "candlestick", "plate"]
				_put_kind(str(on[_rng.randi_range(0, on.size() - 1)]),
						g + along * (-0.7 + 0.7 * float(k)) + ahead * 0.1 + Vector3(0.0, STALL_COUNTER_M, 0.0),
						_rng.randf() * TAU, "hearthvale")
			var beside := ["sack", "crate", "sack", "barrel"]
			_put_kind(str(beside[_rng.randi_range(0, beside.size() - 1)]),
					g + along * (1.7 if _rng.randf() < 0.5 else -1.7) + ahead * 0.4, _rng.randf() * TAU, "hearthvale")
	_features["stalls"] = stalls


## A point on `bearing` about `r` out from the middle that keeps `clear` metres off every road.
func _clear_point(bearing: float, r: float, clear: float) -> Vector2:
	for k in range(12):
		var b := bearing + (float(k >> 1) * 9.0 * (1.0 if k % 2 == 0 else -1.0))
		for rr in [r, r * 0.8, r * 1.2]:
			var p := street.hub_point(b, float(rr))
			# off the roads, and never on reserved ground: Grandfather Hollow's middle is the
			# Grandfather's trunk, and a well in it is as wrong as a house there
			if street.road_distance(p) > clear and not street.is_reserved(p):
				return p
	return Vector2.INF


## A market cross: steps, a shaft and a lantern head, in the square's own stone.
func _cross(fabric: FabricMesh, at: Vector2) -> void:
	var p := _on_ground(at)
	var tint := _stone_tint()
	fabric.lift = _foot_lift(at - Vector2(1.5, 0.0), at + Vector2(1.5, 0.0), 1.5)
	for i in range(3):
		var s := 2.8 - float(i) * 0.7
		fabric.box("stone", Transform3D(Basis(Vector3.UP, 0.4), p + Vector3(0.0, 0.12 + i * 0.24, 0.0)), Vector3(s, 0.24, s), tint)
	fabric.box("stone", Transform3D(Basis(Vector3.UP, 0.4), p + Vector3(0.0, 2.3, 0.0)), Vector3(0.36, 3.2, 0.36), tint)
	fabric.box("stone", Transform3D(Basis(Vector3.UP, 0.4), p + Vector3(0.0, 4.05, 0.0)), Vector3(0.62, 0.5, 0.62), tint.darkened(0.1))
	fabric.lift = Vector3.ZERO
	_body(p + Vector3(0.0, 0.5, 0.0), Basis(Vector3.UP, 0.4), Vector3(2.8, 1.0, 2.8), _yard_bodies)


# --- the beasts ---------------------------------------------------------------------------------------

## Where a settlement keeps its beasts (Livestock): hens in about two yards in five, a pig in its
## sty in a Vale or a wood garden now and then, geese on a village green, and ewes in the
## paddocks behind the houses (`_backlands`). A ruin and a camp keep nothing.
func _stock(fabric: FabricMesh) -> void:
	if ruined or kind == "camp":
		return
	var stock := Livestock.new()
	stock.name = "Livestock"
	stock.seed_with(abs(("stock:" + place_id).hash()))
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(("beasts:" + place_id).hash())
	var hens := Livestock.paths_of("hen")
	var pigs := Livestock.paths_of("pig")
	for h in street.houses:
		await _pace("stock")
		var g: Dictionary = (h as Dictionary).get("garden", {})
		if g.is_empty() or float(g["hd"]) < 2.5 or float(g["hw"]) < 2.0:
			continue
		var roll := rng.randf()
		if roll < 0.4 and not hens.is_empty():
			var home := (g["c"] as Vector2) - (g["v"] as Vector2) * (float(g["hd"]) * 0.45)
			stock.keep("hen", hens, _on_ground(home), minf(float(g["hw"]) - 0.7, 2.2), rng.randi_range(3, 5))
		elif roll < 0.55 and culture in ["vale", "woodfolk"] and not pigs.is_empty() and float(g["hd"]) > 3.5:
			# the sty in the far corner: a low pen, and its pig
			var u: Vector2 = g["u"]
			var v: Vector2 = g["v"]
			var side := 1.0 if rng.randf() < 0.5 else -1.0
			var at := (g["c"] as Vector2) + u * side * (float(g["hw"]) - 1.6) + v * (float(g["hd"]) - 1.4)
			var pen := StreetPlan.corners(StreetPlan.box_facing(at, u, v, 1.3, 1.1))
			for k in range(4):
				_wall(fabric, pen[k], pen[(k + 1) % 4], 0.7)
				# a sty's low wall stops you as a garden's does (it was drawn and walked through)
				var p0: Vector2 = pen[k]
				var p1: Vector2 = pen[(k + 1) % 4]
				var run := p1 - p0
				_body(_on_ground((p0 + p1) * 0.5, 0.35), Basis(Vector3.UP, atan2(-run.y, run.x)),
						Vector3(run.length(), 0.7, 0.3), _yard_bodies)
			stock.keep("pig", pigs, _on_ground(at), 0.6, 1)
	var geese := Livestock.paths_of("goose")
	if kind in ["village", "hamlet"] and not geese.is_empty():
		var w: Dictionary = street.wedges()[0]
		var home2 := _clear_point(float(w["bearing"]) + 30.0, street.hub * 0.55, 4.0)
		if home2 != Vector2.INF:
			stock.keep("goose", geese, _on_ground(home2), minf(street.hub * 0.35, 4.0), rng.randi_range(3, 6))
	await _backlands(fabric, stock, rng)
	if stock.beasts.is_empty():
		stock.free()
		return
	await _pace("backland")
	add_child(stock)
	await _pace("livestock")


## What lies behind the gardens, in the gaps between the streets out to the edge of the place:
## the ground a settlement works that is not a street or a garden. A paddock of ewes with a gate
## in it, an orchard in rows and a rickyard in the Vale, a drystone fold and the peat stacked to
## dry on the hills, allotments on the lake, a woodyard in the wood. Each gap takes as many as it
## has room for, from the edge of the place in, up to its size's share (`BACKLAND_CAP`): the
## ground between two streets was a lawn a town's width across. The fen and the ash keep none.
const BACKLANDS := {
	"vale": ["paddock", "orchard", "allotment", "rickyard"], "woodfolk": ["paddock", "woodyard", "allotment"],
	"clans": ["paddock", "peat"], "lakefolk": ["allotment", "paddock", "orchard"], "reedfolk": [], "pilgrims": [],
}
const BACKLAND_CAP := {"city": 8, "town": 7, "village": 4, "hamlet": 2}
## The sizes of a piece of it (half width, half depth): a field's corner, a croft's, and a plot
## squeezed in where a croft will not go. The biggest first, so the small ones fill what is left.
const BACKLAND_SIZES := [Vector2(8.0, 5.5), Vector2(5.5, 4.0), Vector2(4.0, 3.2)]


func _backlands(fabric: FabricMesh, stock: Livestock, rng: RandomNumberGenerator) -> void:
	var uses: Array = BACKLANDS.get(culture, [])
	if uses.is_empty() or not BACKLAND_CAP.has(kind):
		return
	var n := 0
	for w in street.wedges():
		var placed := 0
		for size_v in BACKLAND_SIZES:
			while placed < int(BACKLAND_CAP[kind]):
				await _pace("backland")
				var plot: Dictionary = await _backland_plot(w, rng, size_v)
				if plot.is_empty():
					break
				await _backland(fabric, stock, rng, plot, str(uses[n % uses.size()]))
				n += 1
				placed += 1


## Room for a piece of worked ground `size` (half width, half depth) in the gap `w` between two
## streets, as far out as the place allows: clear of every house, garden, road and piece already
## laid. Its -v side faces the middle.
func _backland_plot(w: Dictionary, rng: RandomNumberGenerator, size := Vector2(8.0, 5.5)) -> Dictionary:
	var width := float(w["width"])
	for t in range(12):
		await _pace("backland_look")
		# across the gap, short of the streets at its sides (their houses and gardens refuse the rest)
		var bearing := float(w["bearing"]) + rng.randf_range(-0.42, 0.42) * minf(width, 150.0)
		var r := pad_radius + 2.0
		while r > street.hub + 6.0 + size.y:
			var c := street.hub_point(bearing, r)
			var out := (c - street.centre).normalized()
			var plot := StreetPlan.box_facing(c, Vector2(out.y, -out.x), out, size.x, size.y)
			if street.is_clear(plot, false):
				street.reserved.append(plot)
				return plot
			r -= 2.5
	return {}


func _backland(fabric: FabricMesh, stock: Livestock, rng: RandomNumberGenerator, plot: Dictionary, use: String) -> void:
	var c := StreetPlan.corners(plot)
	var fences: Array = FENCE_BY_CULTURE.get(culture, ["rail"])
	var fence_kind := str(fences[0])
	if fence_kind == "hedge" or (use == "paddock" and fence_kind == "paling"):
		fence_kind = "rail"
	# three sides whole, and the side toward the middle with its gate
	for k in [1, 2, 3]:
		_fence(fabric, c[k], c[(k + 1) % 4], fence_kind)
		await _pace("backland_fence")
	var near_a: Vector2 = c[0]
	var near_b: Vector2 = c[1]
	var dir := (near_b - near_a).normalized()
	var gap_at := near_a.lerp(near_b, rng.randf_range(0.3, 0.7))
	_fence(fabric, near_a, gap_at - dir * 1.7, fence_kind)
	await _pace("backland_fence")
	_fence(fabric, gap_at + dir * 1.7, near_b, fence_kind)
	await _pace("backland_fence")
	fabric.lift = _foot_lift(gap_at - dir * 1.8, gap_at + dir * 1.8, 0.2)
	Wayside.hang_gate(fabric, _on_ground(gap_at - dir * 1.7), dir, rng.randf() < 0.35, rng.randf())
	fabric.lift = Vector3.ZERO
	var centre: Vector2 = plot["c"]
	var u: Vector2 = plot["u"]
	var v: Vector2 = plot["v"]
	match use:
		"paddock":
			var sheep := Livestock.paths_of("sheep")
			if not sheep.is_empty():
				stock.keep("sheep", sheep, _on_ground(centre), minf(float(plot["hw"]), float(plot["hd"])) - 1.2,
						rng.randi_range(4, 7))
			var hay := _prop_paths("hearthvale", "hay_bale")
			if not hay.is_empty():
				_put(hay[0], _on_ground(centre + u * (float(plot["hw"]) - 1.5) + v * (float(plot["hd"]) - 1.5)),
						rng.randf() * TAU, Vector3.ONE)
		"orchard":
			var trees := tree_paths(FRUIT_TREE)
			if not trees.is_empty():
				for i in range(3):
					for j in range(2):
						var p := centre + u * (-5.0 + 5.0 * float(i)) + v * (-2.2 + 4.4 * float(j)) \
								+ Vector2(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4))
						_put(trees[(i + j) % trees.size()], _on_ground(p), rng.randf() * TAU, Vector3.ONE * rng.randf_range(0.75, 0.95))
		"allotment":
			_garden(fabric, {}, StreetPlan.box_facing(centre, u, v, float(plot["hw"]) - 0.5, float(plot["hd"]) - 0.5))
		"woodyard":
			var piles := 3 if float(plot["hw"]) > 6.0 else 2
			for i in range(piles):
				var x := (float(i) - float(piles - 1) * 0.5) * 4.0
				_woodpile(fabric, centre + u * x + v * rng.randf_range(-1.5, 1.5), u)
			var block := _prop_paths("hearthvale", "chopping_block")
			if not block.is_empty():
				_put(block[0], _on_ground(centre + v * 2.5), rng.randf() * TAU, Vector3.ONE)
		"rickyard":
			# the hay in, in bales stacked two high, and the cart it came on
			var bales := _prop_paths("hearthvale", "hay_bale")
			if not bales.is_empty():
				# three on the ground and two on those (the forge's bale is 1.2 m every way)
				for layer in range(2):
					for i in range(3 - layer):
						var x := (float(i) - float(2 - layer) * 0.5) * 1.25
						_put(bales[0], _on_ground(centre + u * x - v * 1.0) + Vector3(0.0, 1.2 * float(layer), 0.0),
								atan2(-u.y, u.x) + rng.randf_range(-0.06, 0.06), Vector3.ONE)
			var cart := _prop_paths("hearthvale", "cart")
			if not cart.is_empty():
				_put(cart[0], _on_ground(centre + u * 2.5 + v * 2.5), rng.randf() * TAU, Vector3.ONE)
		"peat":
			# the peat cut in spring, stacked in the fold to dry
			var stacks := _prop_paths("skerrow", "peat_stack")
			if not stacks.is_empty():
				for i in range(4):
					var p := centre + u * rng.randf_range(-float(plot["hw"]) + 1.5, float(plot["hw"]) - 1.5) \
							+ v * rng.randf_range(-float(plot["hd"]) + 1.5, float(plot["hd"]) - 1.5)
					_put(stacks[i % stacks.size()], _on_ground(p), rng.randf() * TAU, Vector3.ONE)


# --- what is lying about -----------------------------------------------------------------------

## Buckets, carts, hay, benches, barrels: each where it belongs -- against a wall by a door, in a
## yard, at the end of a garden, at the street's edge -- and turned the way the house is turned.
## Scaled to the size of the place; every prop of one forge asset is one `MultiMesh`.
func _strew(plan: Dictionary) -> void:
	var share := clampf(float(int(plan.get("count", 10))) / 20.0, 0.4, 2.0)
	if _built.is_empty():
		return
	if _slice != null:
		# what is strewn so far, read on the loader's threads while the rest is laid out
		WorldStreamer.prefetch_paths(_placed.keys())
	for entry in PROPS_BY_CULTURE.get(culture, []):
		var row: Dictionary = entry
		var n := int(round(float(int(row.get("n", 1))) * share))
		for i in range(n):
			var spot := _prop_spot(str(row.get("where", "yard")))
			if spot.is_empty():
				continue
			_put_kind(str(row.get("kind", "")), spot["at"], float(spot["yaw"]))
		await _pace("strew_lay")
	for path in _placed:
		_strew_one_kind(str(path), _placed[path])
		await _pace("strew_kind")


## Where a prop of this sort belongs, in this node's space, and which way it is turned.
func _prop_spot(where: String) -> Dictionary:
	var built: Dictionary = _built[_rng.randi_range(0, _built.size() - 1)]
	var plot: Dictionary = built["plot"]
	var b: Dictionary = plot["box"]
	var u: Vector2 = b["u"]
	var v: Vector2 = b["v"]
	var house_yaw := atan2(-u.y, u.x)
	match where:
		"door":
			# against the front wall, a pace to one side of the door
			var door: Vector2 = plot["door"]
			var side := 1.0 if _rng.randf() < 0.5 else -1.0
			var p := door + u * side * _rng.randf_range(1.3, 2.2) - v * 0.55
			return {"at": _on_ground(p), "yaw": house_yaw + _rng.randf_range(-0.15, 0.15)}
		"yard":
			var p2 := (b["c"] as Vector2) + v * (float(b["hd"]) + _rng.randf_range(0.8, 1.8)) + u * _rng.randf_range(-float(b["hw"]) + 0.8, float(b["hw"]) - 0.8)
			return {"at": _on_ground(p2), "yaw": house_yaw + _rng.randf_range(-0.4, 0.4)}
		"garden":
			var g: Dictionary = plot.get("garden", {})
			if g.is_empty():
				return {}
			var p3 := (g["c"] as Vector2) + (g["v"] as Vector2) * (float(g["hd"]) - 1.2) \
					+ (g["u"] as Vector2) * _rng.randf_range(-float(g["hw"]) + 1.0, float(g["hw"]) - 1.0)
			return {"at": _on_ground(p3), "yaw": house_yaw + _rng.randf_range(-0.3, 0.3)}
		"street":
			# at the street's edge, beside the plot, turned along the street
			var p4 := (plot["door"] as Vector2) - v * (float(plot.get("setback", 2.0)) - 0.9) + u * (float(b["hw"]) + 0.6)
			return {"at": _on_ground(p4), "yaw": house_yaw + (PI * 0.5 if _rng.randf() < 0.5 else 0.0)}
		"hub":
			var wedges := street.wedges()
			var w: Dictionary = wedges[_rng.randi_range(0, wedges.size() - 1)]
			var p5 := _clear_point(float(w["bearing"]) + _rng.randf_range(-15.0, 15.0), street.hub * _rng.randf_range(0.4, 0.8), 4.2)
			if p5 == Vector2.INF:
				return {}
			return {"at": _on_ground(p5), "yaw": _rng.randf() * TAU}
	return {}


## One of a culture's props, by kind, at a spot in this node's space. `prefix` overrides the culture.
func _put_kind(prop_kind: String, at: Vector3, yaw: float, prefix := "") -> void:
	var paths := _prop_paths(prefix if prefix != "" else str(PROP_PREFIX.get(culture, "hearthvale")), prop_kind)
	if paths.is_empty() and prefix == "":
		paths = _prop_paths("hearthvale", prop_kind)
	if paths.is_empty():
		return
	_put(paths[_rng.randi_range(0, paths.size() - 1)], at, yaw, Vector3.ONE)


## Queues an instance of the asset at `path` (at `at` in this node's space, turned `yaw`, and
## scaled in its own axes, so a hedge segment stretched along a run stays a hedge).
func _put(path: String, at: Vector3, yaw: float, stretch: Vector3) -> void:
	if not _placed.has(path):
		_placed[path] = []
	(_placed[path] as Array).append(Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(stretch), at))


## One MultiMesh for every instance of one asset. A MultiMesh takes its level of detail as a
## whole, from the nearest of its instances, so props spread along a street were all drawn at full
## detail however far off most of them stood; the forge's first reduction is drawn instead, which
## is a barrel at 1 080 triangles rather than 2 700 and not a barrel anybody can tell apart.
## A tree on its own (the one on a green) keeps its full mesh, read against the sky; the trees of
## the gardens and the orchards, a few dozen to a village, are the forge's second level of them,
## its trunk and its leaf cards: 1 400 triangles a tree rather than 5 700, and four times that
## again in the sun's cascades.
func _strew_one_kind(path: String, transforms: Array) -> void:
	# (read once, and kept for the next world: WorldStreamer.load_asset)
	var packed := WorldStreamer.load_asset(path) as PackedScene
	if packed == null:
		return
	# The sun is drawn the cheapest rung of a thing, not the one the eye sees: its shadow is a
	# shape on the ground, and each kind was drawn again whole for every cascade of it -- an apple
	# tree's 1 400 triangles four times over where its crossed-card impostor's eight say the same.
	var low := _lod_parts(packed, 2)
	var shadow: Mesh = low[0] if not low.is_empty() else null
	if path.contains(FRUIT_TREE):
		var parts := _lod_parts(packed, 1)
		if not parts.is_empty():
			var near: Array[MultiMeshInstance3D] = []
			for i in parts.size():
				near.append(_strew_mesh(path, parts[i], transforms, "lod1_%d" % i, shadow if i == 0 else null, i > 0 and shadow != null))
			# and from further off, the impostor alone: the orchards of the next village are two
			# crossed cards a tree, not a trunk and forty leaf cards
			if shadow != null and not near.is_empty():
				_far_band(near, shadow, transforms)
			return
	var tree := path.contains("/trees/")
	var mesh := WorldStreamer._mesh_of(packed, 0 if tree else 1)
	if mesh == null:
		return
	# the one tree on a green is the whole tree, and throws its own shadow
	_strew_mesh(path, mesh, transforms, "", null if tree else shadow)


## Every mesh a forge scene keeps at LOD `level` (a tree's is its trunk and its cards, two meshes).
static func _lod_parts(packed: PackedScene, level: int) -> Array:
	var out: Array = []
	var state := packed.get_state()
	var tail := "_LOD%d" % level
	for i in state.get_node_count():
		if state.get_node_type(i) != "MeshInstance3D" or not str(state.get_node_name(i)).ends_with(tail):
			continue
		for k in state.get_node_property_count(i):
			if state.get_node_property_name(i, k) == "mesh":
				var v: Variant = state.get_node_property_value(i, k)
				if v is Mesh:
					out.append(v)
	return out


## Every variant of a tree the forge grew (`<slug>_a`, `_b`, `_c`).
static func tree_paths(slug: String) -> Array[String]:
	var out: Array[String] = []
	for variant in ["a", "b", "c"]:
		var path := "res://assets/models/trees/%s_%s/%s_%s.glb" % [slug, variant, slug, variant]
		if ResourceLoader.exists(path):
			out.append(path)
	return out


func _strew_mesh(path: String, mesh: Mesh, transforms: Array, part: String, shadow: Mesh = null,
		no_shadow := false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	# The forge exports a standing prop with its feet at y = 0 (CONTRACTS §4). One that reaches
	# below is lifted by its own box, so a cart centred on its axle still sits on the ground.
	var lift := maxf(0.0, -mesh.get_aabb().position.y)
	# a lantern or a brazier is a light after dark: its flame sits just under the top of its box
	var lamp := "brazier" if path.contains("brazier") else ("lantern" if path.contains("lantern") else "")
	var flame := mesh.get_aabb().end.y * (0.8 if lamp == "brazier" else 0.88)
	var flames: Array = []
	for i in transforms.size():
		var xf: Transform3D = transforms[i]
		xf.origin.y += lift * xf.basis.get_scale().y
		mm.set_instance_transform(i, xf)
		if lamp != "" and is_inside_tree():
			flames.append(to_global(xf.origin + Vector3(0.0, flame, 0.0)))
	if not flames.is_empty():
		NightLights.add(self, flames, lamp)
	var inst := MultiMeshInstance3D.new()
	inst.name = path.get_file().get_basename() + ("_" + part if part != "" else "")
	inst.multimesh = mm
	# a mug on a stall is a pixel from the next street and a cart is not: the small things go early
	# and throw no shadow (a shadow pass for each kind of crockery was a tenth of a street's draws)
	# (a range is measured to the middle of all of a kind at once, so it reaches past half of them)
	var size := mesh.get_aabb().size
	var span := maxf(size.x, maxf(size.y, size.z))
	var spread := mm.get_aabb().size
	var half := Vector2(spread.x, spread.z).length() * 0.5
	var reach := FabricMesh.PROP_RANGE_M * (2.0 if path.contains("/trees/") else 1.0)
	if span < SMALL_PROP_M:
		reach = SMALL_PROP_RANGE_M + half
	elif span < MIDDLING_PROP_M:
		reach = minf(reach, FabricMesh.PROP_RANGE_M * 0.5 + half)
	var casts := span >= SMALL_PROP_M and not no_shadow
	FabricMesh.near_only(inst, reach, casts and shadow == null)
	add_child(inst)
	if casts and shadow != null:
		add_child(shadow_of(inst, shadow, reach))
	return inst


## Where a settlement's fruit trees give way to their impostors: this far from the middle of the
## trees of a kind, past which the eye's LOD1 and the near shadow stop and the impostor is drawn.
const TREE_NEAR_M := 130.0


## `near` (the eye's LOD1 of a kind of tree, and the proxy that casts its shadow) drawn only to
## TREE_NEAR_M past the trees' own spread, and the impostor `far` from there out.
func _far_band(near: Array[MultiMeshInstance3D], far: Mesh, transforms: Array) -> void:
	# the spread from where the trees were put: a MultiMesh's own box and its instances are the
	# renderer's to keep, and the headless one keeps neither
	var spread := Rect2()
	for i in transforms.size():
		var at: Vector3 = (transforms[i] as Transform3D).origin
		spread = Rect2(at.x, at.z, 0.0, 0.0) if i == 0 else spread.expand(Vector2(at.x, at.z))
	var edge := TREE_NEAR_M + spread.size.length() * 0.5
	var nodes: Array[Node] = []
	for n in near:
		nodes.append(n)
		var sh := get_node_or_null(NodePath(str(n.name) + "_shadow"))
		if sh != null:
			nodes.append(sh)
	for n in nodes:
		var gi := n as GeometryInstance3D
		gi.visibility_range_end = edge
		gi.visibility_range_end_margin = 12.0
	var impostor := shadow_of(near[0], far, FabricMesh.PROP_RANGE_M * 2.0)
	impostor.name = str(near[0].name).trim_suffix("_lod1_0") + "_far"
	impostor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	impostor.visibility_range_begin = edge
	impostor.visibility_range_begin_margin = 12.0
	add_child(impostor)


## What the sun draws of `eye` (a MultiMesh of the forge's LOD1): the same instances in `shadow`,
## the forge's lowest rung, casting and never seen.
static func shadow_of(eye: MultiMeshInstance3D, shadow: Mesh, reach: float) -> MultiMeshInstance3D:
	var src := eye.multimesh
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = shadow
	mm.instance_count = src.instance_count
	for i in src.instance_count:
		mm.set_instance_transform(i, src.get_instance_transform(i))
	var inst := MultiMeshInstance3D.new()
	inst.name = str(eye.name) + "_shadow"
	inst.multimesh = mm
	inst.extra_cull_margin = eye.extra_cull_margin
	FabricMesh.near_only(inst, reach, true)
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	return inst


## Both variants of a prop, if the forge built them. Naming is `<region>_<kind>_<a|b>` and a
## one-off has only an `_a`, so asking for both and keeping what exists covers either case.
static func _prop_paths(prefix: String, prop_kind: String) -> Array[String]:
	var out: Array[String] = []
	for variant in ["a", "b"]:
		var slug := "%s_%s_%s" % [prefix, prop_kind, variant]
		var path := "res://assets/models/props/%s/%s.glb" % [slug, slug]
		if ResourceLoader.exists(path):
			out.append(path)
	return out


# --- signs and smoke ---------------------------------------------------------------------------

## A shop's emblem, hung from the end of its bracket (`sign`: the bracket's frame on the wall,
## this node's space; see HouseKit.sign_bracket).
func _emblem(prop_kind: String, board: Transform3D) -> void:
	if not _emblems.has(prop_kind):
		_emblems[prop_kind] = []
	(_emblems[prop_kind] as Array).append(board)


# --- a fort --------------------------------------------------------------------------------------

## A fort's palisade stands this far out from the last house or garden, and never nearer the pad's
## edge than FORT_EDGE_M.
const FORT_CLEAR_M := 3.5
const FORT_EDGE_M := 3.0
const STAKE_TINT := Color(0.46, 0.37, 0.27)
## The Wardens' banners (banner_cloth.gdshader: weathered wool in their green with an ochre border).
const FORT_BANNER := preload("res://assets/shaders/banner_cloth.gdshader")
const REGION_OF_CULTURE := {"vale": "core:region/hearthvale", "lakefolk": "core:region/brightwater",
		"reedfolk": "core:region/sedgemire", "woodfolk": "core:region/briarwold", "clans": "core:region/skerrow",
		"pilgrims": "core:region/cinderlea"}


## A fort (Wardens' Rest, "a fortified waystation"): its houses, closed in a palisade of pointed
## stakes, with a gatehouse of two stone towers where each road comes in, a stone watch tower at
## the back flying the Wardens' colours, and the square their drill yard: pells to cut at, a rack
## of spears, the butts. It was dressed as a hamlet's cottages round a green, on the first road the
## player walks, where the opening frames it from the Roll at a hundred metres.
func _fort(fabric: FabricMesh) -> void:
	var c := street.centre
	var r := street.hub + 8.0
	for h in street.houses:
		for p in StreetPlan.corners(h["box"]):
			r = maxf(r, p.distance_to(c) + FORT_CLEAR_M)
		var g: Dictionary = h.get("garden", {})
		if not g.is_empty():
			for p in StreetPlan.corners(g):
				r = maxf(r, p.distance_to(c) + FORT_CLEAR_M * 0.6)
	r = minf(r, pad_radius - FORT_EDGE_M)
	var kit := PoiKit.new(self, global_position, pad_radius, str(REGION_OF_CULTURE.get(culture, "core:region/hearthvale")),
			false, "fort:" + place_id)
	var m := PoiMasonry.new(kit)
	var stone := m.begin()
	var timber := m.begin()
	# the ring, and where the roads come through it
	var n := maxi(24, int(TAU * r / 1.6))
	var gap: Array[bool] = []
	var ring: Array[Vector2] = []
	for i in range(n):
		var a := TAU * float(i) / float(n)
		var q := c + Vector2(sin(a), cos(a)) * r
		ring.append(q)
		gap.append(street.road_distance(q) < StreetPlan.ROAD_HALF_M + 2.2)
	var gates: Array = []
	for i in range(n):
		if gap[i] and not gap[(i - 1 + n) % n]:
			var j := i
			while gap[j % n] and j < i + n:
				j += 1
			gates.append([ring[(i - 1 + n) % n], ring[j % n]])
	# the stakes: pointed, leaning a little, each its own height and shade, on a bank of turf
	for i in range(n):
		if gap[i] or gap[(i + 1) % n]:
			continue
		var a: Vector2 = ring[i]
		var b: Vector2 = ring[(i + 1) % n]
		var seg := a.distance_to(b)
		var dir := (b - a) / seg
		var yaw := atan2(-dir.y, dir.x)
		var stakes := int(seg / 0.3)
		var skip := false
		for h in street.houses:
			if StreetPlan.contains(h["box"], (a + b) * 0.5, 0.6):
				skip = true
		if skip:
			continue
		for k in range(stakes):
			var q := a.lerp(b, (float(k) + 0.5) / float(stakes))
			var tall := _rng.randf_range(2.9, 3.5)
			var lean := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, _rng.randf_range(-0.05, 0.05)) * Basis(Vector3.RIGHT, _rng.randf_range(-0.04, 0.02))
			var foot := _on_ground(q, -0.3)
			var tint := FabricMesh.shade(STAKE_TINT, _rng.randf_range(0.78, 1.08))
			fabric.box("joinery", Transform3D(lean, foot + lean * Vector3(0.0, tall * 0.5, 0.0)), Vector3(0.26, tall, 0.26), tint)
			# the point
			fabric.box("joinery", Transform3D(lean * Basis(Vector3.BACK, PI * 0.25), foot + lean * Vector3(0.0, tall, 0.0)),
					Vector3(0.19, 0.19, 0.26), tint.darkened(0.1))
		# the rail the stakes are pinned to, inside
		var inward := (c - (a + b) * 0.5).normalized() * 0.2
		for y_v in [1.0, 2.3]:
			var p0 := _on_ground(a + inward, float(y_v) - 0.3)
			var p1 := _on_ground(b + inward, float(y_v) - 0.3)
			fabric.box("joinery", Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, atan2(p1.y - p0.y, seg)), (p0 + p1) * 0.5),
					Vector3(seg + 0.1, 0.12, 0.1), FabricMesh.shade(STAKE_TINT, 0.8))
		_body(_on_ground((a + b) * 0.5, 1.4), Basis(Vector3.UP, yaw), Vector3(seg, 3.2, 0.4), _yard_bodies)
	# the gatehouses: a stone tower either side of each road, a walk over the way between them, and
	# the colours hung from it
	var banners := 0
	for gate_v in gates:
		var ga: Vector2 = gate_v[0]
		var gb: Vector2 = gate_v[1]
		var mid := (ga + gb) * 0.5
		var out := (mid - c).normalized()
		var across := (gb - ga).normalized()
		var yaw := atan2(out.x, out.y)
		var tops: Array[Vector3] = []
		for side in [ga - across * 0.9, gb + across * 0.9]:
			var sp: Vector2 = side
			tops.append(_fort_tower(m, stone, sp, yaw, Vector3(3.4, 6.6, 3.4)))
		var walk_y := minf(tops[0].y, tops[1].y) - 1.3
		var w0 := Vector3(tops[0].x, walk_y, tops[0].z)
		var w1 := Vector3(tops[1].x, walk_y, tops[1].z)
		m.block(timber, Transform3D(Basis.looking_at((w1 - w0).normalized(), Vector3.UP), (w0 + w1) * 0.5), Vector3(2.2, 0.35, w0.distance_to(w1)))
		for s_v in [-1.0, 1.0]:
			var rail := (w0 + w1) * 0.5 + Vector3(out.x, 0.0, out.y) * (1.0 * float(s_v)) + Vector3(0.0, 0.6, 0.0)
			m.block(timber, Transform3D(Basis.looking_at((w1 - w0).normalized(), Vector3.UP), rail), Vector3(0.12, 0.12, w0.distance_to(w1)))
		var hang := (w0 + w1) * 0.5 + Vector3(out.x, 0.0, out.y) * 1.2 - Vector3(0.0, 0.2, 0.0)
		_fort_banner(m, hang, yaw, 1.3, 2.6, banners)
		banners += 1
		_features["gate_%d" % gates.find(gate_v)] = _on_ground(mid)
	# the watch tower: at the back, away from the road the fort is come to by, a platform at eleven
	# metres with the colours on a pole over it
	var front := Vector2.ZERO
	for gate_v in gates:
		front += ((gate_v[0] + gate_v[1]) * 0.5 - c).normalized()
	var back := -front.normalized() if front.length() > 0.1 else Vector2(0.0, -1.0)
	var tower_at := c + back * (r - 3.4)
	for h in street.houses:
		if StreetPlan.contains(h["box"], tower_at, 3.0):
			tower_at = c + back.rotated(0.5) * (r - 3.4)
	var top := _fort_tower(m, stone, tower_at, atan2(back.x, back.y), Vector3(5.0, 11.0, 5.0))
	var pole_top := top + Vector3(0.0, 4.2, 0.0)
	m.block(timber, Transform3D(Basis(), (top + pole_top) * 0.5), Vector3(0.14, 4.2, 0.14))
	m.block(timber, Transform3D(Basis(Vector3.UP, atan2(back.x, back.y) + PI * 0.5), pole_top - Vector3(0.0, 0.2, 0.0)), Vector3(1.8, 0.09, 0.09))
	_fort_banner(m, pole_top - Vector3(0.0, 0.25, 0.0), atan2(back.x, back.y), 1.6, 3.2, banners)
	_features["watch"] = top
	m.commit(stone, fabric_material(culture, "stone"), "FortStone", true)
	m.commit(timber, kit.surface("timber", 0.85), "FortTimber", true)
	_drill_yard(fabric, kit)


## A square stone tower `size` at world xz `at`, turned to `yaw`, its top crenellated, with a body.
## Returns its top's middle, in this node's space.
func _fort_tower(m: PoiMasonry, st: SurfaceTool, at: Vector2, yaw: float, size: Vector3) -> Vector3:
	var low := INF
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			low = minf(low, _ground_at(at + Vector2(size.x * 0.5 * float(sx), size.z * 0.5 * float(sz)).rotated(-yaw)))
	var foot := Vector3(at.x - global_position.x, low - global_position.y - 0.4, at.y - global_position.z)
	var b := Basis(Vector3.UP, yaw)
	# the body, battered a little: a wider plinth course at its foot
	m.block(st, Transform3D(b, foot + Vector3(0.0, 0.7, 0.0)), Vector3(size.x + 0.5, 1.4, size.z + 0.5))
	m.block(st, Transform3D(b, foot + Vector3(0.0, size.y * 0.5, 0.0)), size)
	# the parapet: a string course and a merlon at each corner and between
	var top := foot + Vector3(0.0, size.y, 0.0)
	m.block(st, Transform3D(b, top + Vector3(0.0, 0.1, 0.0)), Vector3(size.x + 0.4, 0.2, size.z + 0.4))
	for i in range(3):
		for s in [-1.0, 1.0]:
			var along := (float(i) - 1.0) * size.x * 0.4
			for face in [Vector3(along, 0.0, float(s) * size.z * 0.5), Vector3(float(s) * size.x * 0.5, 0.0, along)]:
				m.block(st, Transform3D(b, top + b * face + Vector3(0.0, 0.55, 0.0)), Vector3(0.8, 0.9, 0.45))
	_body(foot + Vector3(0.0, size.y * 0.5, 0.0), b, size, _yard_bodies)
	return top + Vector3(0.0, 0.2, 0.0)


## One of the Wardens' banners hung at `at` (this node's space), facing along `yaw`: weathered wool
## in their green, moving in the wind.
func _fort_banner(m: PoiMasonry, at: Vector3, yaw: float, width: float, height: float, index: int) -> void:
	if culture != "vale":
		# the colours are the Wardens'; a fort of another people's flies none of them
		return
	var cloth := ShaderMaterial.new()
	cloth.shader = FORT_BANNER
	cloth.set_shader_parameter("seed", 0.29 * float(index + 1))
	m.sheet(at, yaw, width, height, cloth, "Banner%d" % index, 0.12, true, 6, 14)


## The square as the Wardens use it: pells to cut at, a rack of spears, the butts with a target on
## each, and the well that is already there.
func _drill_yard(fabric: FabricMesh, kit: PoiKit) -> void:
	var wedges := street.wedges()
	var w: Dictionary = wedges[1] if wedges.size() > 1 else wedges[0]
	var bearing := deg_to_rad(float(w["bearing"]) + (0.0 if wedges.size() > 1 else 90.0))
	var dir := Vector2(sin(bearing), -cos(bearing))
	var across := Vector2(-dir.y, dir.x)
	var yard := street.centre + dir * street.hub * 0.55
	# The Wardens' yard is where their recruits are made, and it wants room: out past the paved
	# middle, in the widest ground between two streets, with the pells in a row facing the square.
	# In the middle itself, by the well, there was room for one pell of the three.
	var out_yard := _open_yard(wedges)
	var rack_off := dir * 3.2
	var butts_off := -dir * 3.4
	if out_yard != Vector2.INF:
		yard = out_yard
		dir = (street.centre - yard).normalized()
		across = Vector2(-dir.y, dir.x)
		# the pells face the square, and a recruit faces the pells: the rack and the butts stand
		# behind them, out of the way of whoever is cutting
		rack_off = -dir * 2.3 + across * 3.9
		butts_off = -dir * 3.9 - across * 1.4
	var pells: Array[Vector3] = []
	for i in range(3):
		var q := yard + across * (float(i) - 1.0) * 2.2
		if street.road_distance(q) < StreetPlan.ROAD_HALF_M + 0.8:
			continue
		var foot := _on_ground(q, -0.2)
		var turn := Basis(Vector3.UP, _rng.randf_range(0.0, TAU))
		fabric.box("joinery", Transform3D(turn, foot + Vector3(0.0, 0.95, 0.0)), Vector3(0.22, 1.9, 0.22),
				FabricMesh.shade(STAKE_TINT, _rng.randf_range(0.8, 1.0)))
		# a Vale fort's pells are Pells, bodies of their own to be struck; anyone else's are posts
		if culture != "vale":
			_body(foot + Vector3(0.0, 0.95, 0.0), turn, Vector3(0.24, 1.9, 0.24), _yard_bodies)
		# the arms it is struck on
		fabric.box("joinery", Transform3D(Basis(Vector3.UP, atan2(-across.y, across.x)), foot + Vector3(0.0, 1.45, 0.0)), Vector3(0.9, 0.1, 0.1),
				FabricMesh.shade(STAKE_TINT, 0.85))
		pells.append(foot)
	# the rack: two uprights and a bar, and the spears leaning on it
	var rack := yard + rack_off
	if street.road_distance(rack) > StreetPlan.ROAD_HALF_M + 1.0:
		var yaw := atan2(-across.y, across.x)
		for s in [-1.0, 1.0]:
			fabric.box("joinery", Transform3D(Basis(Vector3.UP, yaw), _on_ground(rack + across * (1.1 * float(s)), 0.7)), Vector3(0.1, 1.4, 0.1), FabricMesh.shade(STAKE_TINT, 0.8))
		fabric.box("joinery", Transform3D(Basis(Vector3.UP, yaw), _on_ground(rack, 1.3)), Vector3(2.4, 0.09, 0.09), FabricMesh.shade(STAKE_TINT, 0.8))
		_body(_on_ground(rack, 0.7), Basis(Vector3.UP, yaw), Vector3(2.4, 1.4, 0.3), _yard_bodies)
		var spear := kit.prop("spear")
		if spear != "":
			for i in range(5):
				var q := rack + across * (float(i) - 2.0) * 0.4 - dir * 0.25
				kit.place(spear, _on_ground(q), yaw + _rng.randf_range(-0.1, 0.1), 1.0, false, Vector3(0.28, 0.0, 0.0))
	# the butts: hay bales with a painted target, at the square's far side
	var butts := yard + butts_off
	var bale := kit.prop("hay_bale")
	if bale != "" and street.road_distance(butts) > StreetPlan.ROAD_HALF_M + 1.0:
		kit.place(bale, _on_ground(butts), atan2(dir.x, dir.y), 1.0, true)
	_features["drill_yard"] = _on_ground(yard)
	_features["pells"] = pells
	if culture == "vale":
		_training_ground(fabric, yard, dir, across, pells, [rack, butts])


## The yard's middle out past the paved square, in the widest wedge between streets, where three
## pells, the rack and the ring have room: Vector2.INF when no wedge has it.
func _open_yard(wedges: Array) -> Vector2:
	for w_v in wedges:
		var w: Dictionary = w_v
		if float(w.get("width", 0.0)) < 60.0:
			continue
		for extra in [7.0, 9.0, 5.5]:
			var c := street.hub_point(float(w["bearing"]), street.hub + float(extra))
			var inward := (street.centre - c).normalized()
			var side := Vector2(-inward.y, inward.x)
			var ok := true
			for q in [c, c + side * 2.6, c - side * 2.6, c - inward * 3.4]:
				if street.road_distance(q) < StreetPlan.ROAD_HALF_M + 1.4:
					ok = false
				for h in street.houses:
					if StreetPlan.contains(h["box"], q, 1.6):
						ok = false
			if ok:
				return c
	return Vector2.INF


## A sparring ring's radius, and how close to it anything else in the square may stand. It was
## 3.4 m, and the playtest of 09-27 found it cramped: a roll or two and you were at the rope, with
## the sergeant and his swing filling the rest. 4.8 m (twice the ground) gives a bout room to move
## and still finds its place beside the drill yard at Wardens' Rest (5.4 m pushed it 34 m off,
## across the square).
const RING_R := 4.8
const RING_CLEAR_M := 1.4
const ROPE_TINT := Color(0.62, 0.53, 0.36)


## Where a Warden is made (docs/FIGHTING_STYLE_STARTS.md §3.1): the pells are there to be struck
## (Pell: a blow on one lands, and is counted by a lesson), a straw man is lashed to the middle
## one, a ring of stakes and rope is pegged out on the square beside them for sparring, and the
## sergeant and the recruit have their places marked. The warrior's start is this yard.
func _training_ground(fabric: FabricMesh, yard: Vector2, dir: Vector2, across: Vector2, pells: Array[Vector3], taken_at: Array) -> void:
	var middle := int(pells.size() / 2.0)
	for i in pells.size():
		var pell := Pell.new()
		pell.name = "Pell%d" % i
		pell.straw_man = i == middle
		pell.position = pells[i]
		pell.rotation.y = atan2(-dir.x, -dir.y)
		add_child(pell)
	# the ring: on open ground in the square, clear of the roads, the houses, the well and the rest
	# of the yard, and as near the pells as that allows
	var avoid: Array[Vector2] = []
	for f in pells:
		avoid.append(Vector2(f.x + global_position.x, f.z + global_position.z))
	for t in taken_at:
		avoid.append(t as Vector2)
	for key in ["well", "cross", "board", "watch", "gate_0", "gate_1", "gate_2", "gate_3"]:
		if _features.has(key):
			var w: Vector3 = _features[key]
			avoid.append(Vector2(w.x + global_position.x, w.z + global_position.z))
	var ring := _ring_spot(yard, avoid)
	if ring != Vector2.INF:
		_sparring_ring(fabric, ring, yard)
		_features["ring"] = _on_ground(ring)
	var toward := (yard - ring).normalized() if ring != Vector2.INF else dir
	_spot("dole_yard", yard - across * 3.9 + dir * 1.0, yard)
	# where a recruit stands to begin: a pace back from the middle pell, facing it (the warrior's
	# start stands the body here, by core:opening/warrior's `start`)
	_spot("recruit_start", yard + dir * 3.0, yard)
	if not pells.is_empty():
		var last: Vector3 = pells[pells.size() - 1]
		var at := Vector2(last.x + global_position.x, last.z + global_position.z)
		_spot("tam_yard", at + dir * 1.1, at)
	if ring != Vector2.INF:
		_spot("dole_ring", ring - toward * 1.4, ring + toward * RING_R)


## The first clear spot for the ring, nearest the yard.
func _ring_spot(yard: Vector2, avoid: Array[Vector2]) -> Vector2:
	var best := Vector2.INF
	var best_d := INF
	for r_m in [street.hub * 0.45, street.hub * 0.8, street.hub + 4.0, street.hub + 8.0, street.hub + 12.0, street.hub + 16.0]:
		for k in 36:
			var c := street.hub_point(float(k) * 10.0, float(r_m))
			if not _ring_clear(c, avoid):
				continue
			var d := c.distance_to(yard)
			if d < best_d:
				best_d = d
				best = c
	return best


func _ring_clear(c: Vector2, avoid: Array[Vector2]) -> bool:
	if street.road_distance(c) < StreetPlan.ROAD_HALF_M + RING_R + RING_CLEAR_M:
		return false
	if c.distance_to(street.centre) > pad_radius - RING_R - FORT_CLEAR_M - FORT_EDGE_M - 4.0:
		return false
	for h in street.houses:
		if StreetPlan.contains(h["box"], c, RING_R + RING_CLEAR_M):
			return false
		var g: Dictionary = h.get("garden", {})
		if not g.is_empty() and StreetPlan.contains(g, c, RING_R + 0.6):
			return false
	for a in avoid:
		if a.distance_to(c) < RING_R + RING_CLEAR_M + 1.2:
			return false
	# level enough to fight on
	var lo := INF
	var hi := -INF
	for k in 8:
		var q := c + Vector2(cos(TAU * float(k) / 8.0), sin(TAU * float(k) / 8.0)) * RING_R
		var y := _ground_at(q)
		lo = minf(lo, y)
		hi = maxf(hi, y)
	return hi - lo < 0.9


## Fourteen stakes in a circle with a rope along their heads, open on the side the yard is. Each
## stake is a body you cannot walk through (it had none: you ran through the posts, playtest
## 09-27); the rope is not, and you duck under it.
func _sparring_ring(fabric: FabricMesh, c: Vector2, yard: Vector2) -> void:
	const N := 14
	var open_at := (yard - c).angle()
	var tops: Array[Vector3] = []
	var angles: Array[float] = []
	for i in N:
		var a := open_at + TAU * (float(i) + 0.5) / float(N)
		var q := c + Vector2(cos(a), sin(a)) * RING_R
		var foot := _on_ground(q, -0.25)
		var tall := _rng.randf_range(1.05, 1.2)
		var lean := Basis(Vector3.UP, -a) * Basis(Vector3.RIGHT, _rng.randf_range(-0.05, 0.05))
		var middle := foot + lean * Vector3(0.0, tall * 0.5, 0.0)
		fabric.box("joinery", Transform3D(lean, middle), Vector3(0.13, tall, 0.13),
				FabricMesh.shade(STAKE_TINT, _rng.randf_range(0.8, 1.0)))
		_body(middle, lean, Vector3(0.16, tall, 0.16), _yard_bodies)
		tops.append(foot + lean * Vector3(0.0, tall - 0.12, 0.0))
		angles.append(a)
	# the rope, stake to stake round the ring, but not across the way in (between the last and the first)
	for i in N - 1:
		var p0 := tops[i]
		var p1 := tops[i + 1]
		var mid := (p0 + p1) * 0.5 - Vector3(0.0, 0.06, 0.0)
		var along := p1 - p0
		var flat := Vector2(along.x, along.z)
		var rope := Basis(Vector3.UP, atan2(-flat.y, flat.x)) * Basis(Vector3.BACK, atan2(along.y, flat.length()))
		fabric.box("joinery", Transform3D(rope, mid), Vector3(along.length(), 0.05, 0.05), ROPE_TINT)


## A place a named person stands in the yard, facing `face`: NpcSpot, found by the registry.
func _spot(spot_name: String, at: Vector2, face: Vector2) -> void:
	var m := NpcSpot.new()
	m.name = spot_name
	m.place_id = place_id
	add_child(m)
	m.position = _on_ground(at)
	var f := face - at
	if f.length() > 0.1:
		m.rotation.y = atan2(-f.x, -f.y)


## A feature of this place where the world can find it (the fort's drill yard, its sparring ring):
## Vector3.INF when it has none.
func feature_position(feature_name: String) -> Vector3:
	var v: Variant = _features.get(feature_name, null)
	if v is Vector3:
		return to_global(v as Vector3)
	return Vector3.INF


func _hang_emblems() -> void:
	for prop_kind in _emblems:
		var paths := _prop_paths(str(PROP_PREFIX.get(culture, "hearthvale")), str(prop_kind))
		if paths.is_empty():
			paths = _prop_paths("hearthvale", str(prop_kind))
		if paths.is_empty():
			continue
		var packed := load(paths[0]) as PackedScene
		var mesh: Mesh = WorldStreamer._mesh_of(packed, 0) if packed != null else null
		if mesh == null:
			continue
		var box := mesh.get_aabb()
		# bigger than life, as a shop sign is: about half a metre whatever the thing is
		var k := 0.55 / maxf(maxf(box.size.x, box.size.y), maxf(box.size.z, 0.05))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		var signs: Array = _emblems[prop_kind]
		mm.instance_count = signs.size()
		for i in signs.size():
			# the emblem's top, in the middle, hangs from the foot of the bracket's chain
			var hang := HouseKit.emblem_frame(signs[i])
			var top := Vector3(box.get_center().x, box.end.y, box.get_center().z)
			mm.set_instance_transform(i, Transform3D(hang.basis * Basis.from_scale(Vector3.ONE * k), hang.origin)
					* Transform3D(Basis(), -top))
		var inst := MultiMeshInstance3D.new()
		inst.name = "Sign_" + str(prop_kind)
		inst.multimesh = mm
		FabricMesh.near_only(inst, FabricMesh.PROP_RANGE_M * 0.5, false)
		add_child(inst)


## Smoke from the chimneys that are drawing: one MultiMesh of puffs for the whole place.
func _smoke() -> void:
	if _chimneys.is_empty():
		return
	var smoke := ChimneySmoke.make(_chimneys, _rng.randi())
	if smoke != null:
		add_child(smoke)


## The settlement's lit windows and door lamps, and its lanterns and braziers, handed to
## NightLights in world space (the props are registered as they are strewn).
func _light_up() -> void:
	if not is_inside_tree():
		return
	var glows: Array = []
	for p in _window_glows:
		glows.append(to_global(p))
	NightLights.add(self, glows, "window")
	var doors: Array = []
	for p in _door_lamps:
		doors.append(to_global(p))
	NightLights.add(self, doors, "door")


# --- work -------------------------------------------------------------------------------------

## A notice post in the square and the settlement's own work at the houses of its trades.
func _put_to_work() -> void:
	if kind in BOARD_KINDS:
		var board := JobBoard.new()
		board.name = "JobBoard"
		board.place_id = place_id
		board.display_name = "the charter-board" if kind == "city" else "the notice post"
		var wedges := street.wedges()
		var w: Dictionary = wedges[mini(1, wedges.size() - 1)]
		var at := _clear_point(float(w["bearing"]), street.hub * 0.85, 4.0)
		var by_a_house: Dictionary = {}
		if at == Vector2.INF:
			# the middle is all reserved (Grandfather Hollow's is the Grandfather's trunk), or
			# all road: the post stands at a street's edge by a house instead
			by_a_house = _prop_spot("street") if not _built.is_empty() else {}
			if by_a_house.is_empty():
				at = street.hub_point(float(w["bearing"]), street.hub * 0.85)
		if by_a_house.is_empty():
			board.position = _on_ground(at)
			board.rotation.y = atan2(street.centre.x - at.x, street.centre.y - at.y)
		else:
			board.position = by_a_house["at"]
			board.rotation.y = float(by_a_house["yaw"])
		HouseKit.notice_board(board, abs(place_id.hash()))
		add_child(board)
		_features["board"] = board.position
	for station_kind in _work_here():
		var station := JobStation.new()
		station.kind = station_kind
		station.name = "JobStation_" + station_kind
		var spot := _station_spot(station_kind)
		station.position = spot["at"]
		station.rotation.y = float(spot["yaw"])
		_give_a_body(station, str(STATION_PROP.get(station_kind, "crate")))
		add_child(station)
		if station_kind == "smith":
			_features["forge"] = station.position


## Where a station stands: at the front of the house whose trade it is, if one of this place's
## real houses keeps that trade; otherwise in the yard of a fabric house.
func _station_spot(station_kind: String) -> Dictionary:
	for h in street.houses:
		var plot: Dictionary = h
		var real := str(plot.get("real", ""))
		if real == "":
			continue
		var trade := str(ContentDB.get_or_empty(real).get("trade", ""))
		if str(STATION_FOR_TRADE.get(trade, "")) != station_kind or plot.has("station"):
			continue
		plot["station"] = station_kind
		var b: Dictionary = plot["box"]
		var u: Vector2 = b["u"]
		var v: Vector2 = b["v"]
		var p := (plot["door"] as Vector2) + u * (float(b["hw"]) * 0.6) - v * 1.4
		return {"at": _on_ground(p), "yaw": atan2(-u.y, u.x)}
	var spot := _prop_spot("yard" if station_kind != "dig" else "garden")
	if spot.is_empty():
		spot = _prop_spot("yard")
	return {"at": spot["at"], "yaw": float(spot["yaw"])}


## A "for sale" board outside each house in this settlement that has a deed behind it.
## `PropertySign` was another complete, tested, self-placing node that nothing placed: six
## deeds are authored and the only way to buy one was to call `PropertyRegistry.buy()`, which
## a player cannot do. A steward still sells the same deed through dialogue; this is the board
## you walk past.
func _offer_the_empty_houses() -> void:
	for def in ContentDB.all("item"):
		var property: Dictionary = def.get("property", {})
		if property.is_empty() or str(property.get("place", "")) != place_id:
			continue
		var sign_node := PropertySign.new()
		sign_node.property_id = str(def.get("id", ""))
		sign_node.name = "ForSale_" + Ids.name_of(str(def.get("id", "")))
		var spot := _prop_spot("door")
		sign_node.position = spot["at"]
		sign_node.rotation.y = float(spot["yaw"])
		add_child(sign_node)


## The kinds of work this settlement offers: one per trade among the people who live here,
## and its region's own work when nobody in it has an authored trade at all.
func _work_here() -> Array[String]:
	var out: Array[String] = []
	for def in ContentDB.all("interior"):
		if str(def.get("place", "")) != place_id:
			continue
		var station := str(STATION_FOR_TRADE.get(str(def.get("trade", "")), ""))
		if station != "" and not out.has(station) and out.size() < MAX_STATIONS:
			out.append(station)
	if out.is_empty():
		var own := str(STATION_BY_CULTURE.get(culture, ""))
		if own != "":
			out.append(own)
	return out


## A `JobBoard` and a `JobStation` are a collision shape and a signal each, with nothing to
## look at: they were written to be dropped into a hand-built scene beside a mesh. Out here
## they have to carry their own, so each takes the forge prop that reads as the work.
func _give_a_body(node: Node3D, prop_kind: String) -> void:
	var paths := _prop_paths(str(PROP_PREFIX.get(culture, "hearthvale")), prop_kind)
	if paths.is_empty():
		paths = _prop_paths("hearthvale", prop_kind)
	if paths.is_empty():
		return
	var packed := load(paths[0]) as PackedScene
	if packed == null:
		return
	var body := packed.instantiate()
	if body is Node3D:
		node.add_child(body)
	else:
		body.queue_free()


# --- where people stand -------------------------------------------------------------------------

## The spots this place's people's days name, out of doors: every schedule entry here that is
## not in a building.
func _outdoor_spots() -> Array[String]:
	var out: Array[String] = []
	for def in ContentDB.all("npc"):
		for e in def.get("schedule", []):
			if typeof(e) != TYPE_DICTIONARY:
				continue
			var entry: Dictionary = e
			var at := str(entry.get("place", ""))
			if at == "home":
				at = str(def.get("home_place", ""))
			if at != place_id or Schedules.is_indoors(entry):
				continue
			var spot := str(entry.get("spot", ""))
			if spot != "" and not out.has(spot):
				out.append(spot)
	out.sort()
	return out


func _spot_names_like(what: String) -> Array[String]:
	var out: Array[String] = []
	for spot in _outdoor_spots():
		if spot_feature(spot) == what:
			out.append(spot)
	return out


## What a spot's name says it is at: "stall", "well", "green", "square", "forge", "inn",
## "board", "cross" -- or "" for a spot this fabric has nothing standing at.
static func spot_feature(spot: String) -> String:
	for pair in SPOT_WORDS:
		if spot.contains(str(pair[0])):
			return str(pair[1])
	return ""


## Stands a marker for every outdoor spot this place's people are sent to that the fabric has
## something at: each stallholder at a stall of their own, the gossips at the well and on the
## green, the smith at the anvil, the regulars at the inn door. `gather` tells NpcRegistry that
## several people may share it and should stand round it rather than in one another.
func _mark_spots() -> void:
	var stalls: Array = _features.get("stalls", [])
	var stall_i := 0
	for spot in _outdoor_spots():
		var feature := spot_feature(spot)
		var at := Vector3.INF
		var gather := true
		# what a shared spot's people stand round, from its marker, and how far out the first of
		# them stand (NpcRegistry.gather_slots): the well's ring is round the well, not its marker
		var round_from := Vector3.ZERO
		var round_r := -1.0
		match feature:
			"stall":
				if stall_i < stalls.size():
					at = stalls[stall_i]
					stall_i += 1
					gather = false
			"well", "cross":
				at = _features.get(feature, _features.get("well", _features.get("cross", Vector3.INF)))
				if at != Vector3.INF:
					at += Vector3(1.6, 0.0, 0.8)
					round_from = -Vector3(1.6, 0.0, 0.8)
					round_r = 1.9
			"green", "square":
				var benches: Array = _features.get("benches", [])
				if not benches.is_empty():
					at = benches[0]
				else:
					at = _on_ground(street.hub_point(float(street.wedges()[0]["bearing"]), street.hub * 0.35))
			"forge", "board":
				at = _features.get(feature, Vector3.INF)
				if at != Vector3.INF:
					at += Vector3(1.2, 0.0, 1.2)
			"inn":
				at = _inn_door()
		if at == Vector3.INF:
			continue
		var m := Marker3D.new()
		m.name = spot
		m.position = at
		m.set_meta("place", place_id)
		m.set_meta("gather", gather)
		if gather and round_r > 0.0:
			m.set_meta("gather_from", round_from)
			m.set_meta("gather_r", round_r)
		m.add_to_group(NpcRegistry.SPOT_GROUP)
		add_child(m)


## In front of the door of this place's inn, if it has one.
func _inn_door() -> Vector3:
	for h in street.houses:
		var plot: Dictionary = h
		var real := str(plot.get("real", ""))
		if real != "" and str(ContentDB.get_or_empty(real).get("trade", "")) == "innkeeper":
			var v: Vector2 = (plot["box"] as Dictionary)["v"]
			return _on_ground((plot["door"] as Vector2) - v * 1.6)
	return Vector3.INF


# --- surfaces -------------------------------------------------------------------------------

## The material a fabric key is drawn in for `for_culture`: what the settlements commit their
## surfaces with, so a farmstead or a mill standing on its own is built of what its region's
## villages are built of.
static func fabric_material(for_culture: String, key: String) -> Material:
	match key:
		"wall":
			return _surface(_wall_spec_of(for_culture), 0.45)
		"wall_alt":
			return _surface(HouseKit.STONE_WALL.get(for_culture, HouseKit.STONE_WALL["vale"]), 0.5)
		"roof":
			return _surface(_roof_spec_of(for_culture), 0.5)
		"stone":
			return _surface(_stone_spec_of(for_culture), 0.6)
		"drystone", "coping":
			# the walls laid dry: the plinths' stone broken small, with the dark of the gaps between
			var rubble := _stone_spec_of(for_culture).duplicate()
			rubble["unit"] = 0.16
			rubble["grout"] = "#2e2c28"
			return _surface(rubble, 0.7)
		"paving":
			return _surface(PAVING_BY_CULTURE.get(for_culture, PAVING_BY_CULTURE["vale"]), 0.55)
		"earth":
			return _surface(EARTH, 0.55)
	return FabricMesh.joinery_material()


static func _wall_spec_of(for_culture: String) -> Dictionary:
	if OUTSIDE_WALL.has(for_culture):
		return OUTSIDE_WALL[for_culture]
	var by_culture: Dictionary = HouseInterior.CULTURE_SURFACES.get(
			for_culture, HouseInterior.CULTURE_SURFACES["vale"])
	return by_culture.get("wall", {})


static func _roof_spec_of(for_culture: String) -> Dictionary:
	return Building.ROOF_BY_CULTURE.get(for_culture, Building.ROOF_BY_CULTURE["vale"])


static func _stone_spec_of(for_culture: String) -> Dictionary:
	return Building.PLINTH_BY_CULTURE.get(for_culture, Building.PLINTH_BY_CULTURE["vale"])


func _roof_spec() -> Dictionary:
	return _roof_spec_of(culture)


static func _surface(spec: Dictionary, wear: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(Building.WALL_SHADER)
	mat.set_shader_parameter("pattern", int(spec.get("pattern", 0)))
	mat.set_shader_parameter("base_color", Color.html(str(spec.get("base", "#cccccc"))))
	mat.set_shader_parameter("accent_color", Color.html(str(spec.get("accent", "#999999"))))
	mat.set_shader_parameter("grout_color", Color.html(str(spec.get("grout", "#555555"))))
	mat.set_shader_parameter("unit_size", float(spec.get("unit", 0.32)))
	mat.set_shader_parameter("wear", wear)
	mat.set_shader_parameter("variation", 0.62)
	return mat


func _ground_at(at: Vector2) -> float:
	var provider: Object = World.terrain()
	if provider == null or not provider.has_method("get_height"):
		return global_position.y
	return float(provider.call("get_height", at.x, at.y))


## A world xz point on the ground, `lift` metres up, in this node's space (the node is never
## turned or scaled, so that is the world less its own position). Everything the fabric builds,
## every prop and every marker is placed in this space.
func _on_ground(p: Vector2, lift := 0.0) -> Vector3:
	return Vector3(p.x - global_position.x, _ground_at(p) + lift - global_position.y, p.y - global_position.z)
