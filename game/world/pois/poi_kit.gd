class_name PoiKit
extends RefCounted
## The hands a point-of-interest builder works with.
##
## A builder describes what stands at a POI — a fire ring, a drum of drystone, a ribcage — and
## this does the part every builder needs the same way: find the forge's asset for a kind in
## this region, stand it on the ground with the collision the forge gave it, instance the same
## asset many times in one MultiMesh, paint anything built at runtime with the painted surface
## shader, put a light where a fire is, and ask the world about ground, water and roads.
##
## Everything is deterministic from the rng the dressing hands over, and nothing here knows
## which POI it is dressing: that is the builder's business.

const PROPS := "res://assets/models/props"
const ROCKS := "res://assets/models/rocks"
const TREES := "res://assets/models/trees"
const FLORA := "res://assets/models/flora"
const LANDMARKS := "res://assets/models/landmarks"
const SURFACE_SHADER := "res://assets/shaders/painted_surface.gdshader"
const STILL_WATER_SHADER := "res://assets/shaders/still_water.gdshader"
const FALLING_WATER_SHADER := "res://assets/shaders/falling_water.gdshader"
const HEARTHSTONE_SCENE := "res://systems/hearth/hearthstone.tscn"
const VARIANTS := ["a", "b", "c"]
## The metadata a collider carries to name the surface a foot lands on (Foley.SURFACE_META).
const SURFACE_META := "surface"
## Words in a forged asset's name that say what it is made of underfoot (surface_of_asset).
const WOOD_WORDS: Array[String] = ["boardwalk", "plank", "dock", "pier", "jetty", "rowboat", "cart", "crate",
	"barrel", "table", "bench", "chest", "stall", "fence", "gate", "coffin", "timber", "log", "grandfather",
	"stool", "chair", "signpost", "chopping_block", "stump", "wheelbarrow", "shelf", "cupboard"]
## Bone is not stone, but it is the hard, dry thing a foot on a giant's finger hears.
const STONE_WORDS: Array[String] = ["drystone", "wall", "stair", "step", "bridge", "masonry", "boulder",
	"cliff", "slab", "stone", "cairn", "ruin", "sarcophagus", "well", "colossus", "spire", "nave", "toll",
	"fallen_hand", "chalk_hound", "the_lamp", "bone_"]
## How far out a silhouette piece is still drawn: the far ring is 384-905 m away.
const FAR_RANGE := 950.0

## Region -> the surfaces of things built here at runtime, in the painted_surface patterns
## (0 plaster, 1 planks, 2 stone blocks, 3 timber, 5 beaten earth). Stone is the region's own
## rock: chalk in the Vale, lake stone at the Mere, wet dark stone in the marsh, mossed granite
## in the wood, limestone on the heights, fused black in the ash. "oroth" is the Builders'
## masonry wherever it stands, and it is the same everywhere because they built it.
const SURFACES := {
	"hearthvale": {"stone": {"base": "#d9d2bf", "accent": "#b9b09a", "grout": "#8b836e", "unit": 0.42},
				   "timber": {"base": "#6b5233", "accent": "#4a3721"},
				   "planks": {"base": "#8a6f4c", "accent": "#6b543a", "grout": "#40331f", "unit": 0.24},
				   "earth": {"base": "#6f6142", "accent": "#55492f", "grout": "#3b321f"}},
	"brightwater": {"stone": {"base": "#8d949c", "accent": "#6e747c", "grout": "#464a50", "unit": 0.48},
					"timber": {"base": "#4a4038", "accent": "#2e2721"},
					"planks": {"base": "#7d766a", "accent": "#5f594f", "grout": "#3a362f", "unit": 0.26},
					"earth": {"base": "#7a765f", "accent": "#5c5945", "grout": "#3e3c2e"}},
	"sedgemire": {"stone": {"base": "#4e5654", "accent": "#3a4240", "grout": "#232827", "unit": 0.46},
				  "timber": {"base": "#4c3b28", "accent": "#2c2116"},
				  "planks": {"base": "#6b5540", "accent": "#493826", "grout": "#2b2118", "unit": 0.24},
				  "earth": {"base": "#3f3a2c", "accent": "#2c2a1e", "grout": "#1c1b12"}},
	"briarwold": {"stone": {"base": "#6c7466", "accent": "#4f5a4a", "grout": "#2f382c", "unit": 0.5},
				  "timber": {"base": "#473625", "accent": "#2a2016"},
				  "planks": {"base": "#5c4a32", "accent": "#3f3221", "grout": "#241c12", "unit": 0.26},
				  "earth": {"base": "#4a4230", "accent": "#332d20", "grout": "#1f1b12"}},
	"skerrow": {"stone": {"base": "#a9a49a", "accent": "#8b857b", "grout": "#5c5850", "unit": 0.4},
				"timber": {"base": "#514436", "accent": "#332a20"},
				"planks": {"base": "#6f6658", "accent": "#554d42", "grout": "#3a352d", "unit": 0.24},
				"earth": {"base": "#5d5a4e", "accent": "#45433a", "grout": "#2c2b25"}},
	"cinderlea": {"stone": {"base": "#726f69", "accent": "#56534e", "grout": "#343230", "unit": 0.5},
				  "timber": {"base": "#4a453e", "accent": "#2c2925"},
				  "planks": {"base": "#6b6660", "accent": "#514d48", "grout": "#38352f", "unit": 0.26},
				  "earth": {"base": "#4b4946", "accent": "#353331", "grout": "#1e1d1c"}},
}
const OROTH := {"base": "#2c2b31", "accent": "#413f47", "grout": "#15141a", "unit": 1.1}
## Bronze for anything of the Toll's metal, and black glass for a riverbed the Ash Winter sang dry.
const BRONZE := Color(0.55, 0.42, 0.22)
const GLASS := Color(0.06, 0.06, 0.08)

## What a pool of standing water looks like in each region, for the still-water shader.
const WATER_LOOK := {
	"hearthvale": [Color(0.30, 0.48, 0.44), Color(0.08, 0.18, 0.20)],
	"brightwater": [Color(0.30, 0.52, 0.62), Color(0.06, 0.20, 0.32)],
	"sedgemire": [Color(0.22, 0.38, 0.36), Color(0.06, 0.12, 0.13)],
	"briarwold": [Color(0.20, 0.36, 0.30), Color(0.04, 0.10, 0.10)],
	"skerrow": [Color(0.24, 0.34, 0.40), Color(0.03, 0.05, 0.07)],
	"cinderlea": [Color(0.30, 0.32, 0.34), Color(0.08, 0.08, 0.09)],
}

static var _scenes: Dictionary = {}       # path -> PackedScene
static var _meshes: Dictionary = {}       # path -> Mesh (LOD0)
static var _metas: Dictionary = {}        # path -> Dictionary
static var _variants: Dictionary = {}     # "<root>|<region>|<kind>" -> Array[String]
static var _shapes: Dictionary = {}       # "<path>@<scale>" -> Array of {shape, xform}
static var _library: PropLibrary = null

## The node everything is added to, and the world position it stands at.
var root: Node3D
var origin := Vector3.ZERO
var radius := 25.0
var region := "hearthvale"
var culture := "vale"
var far := false
var rng := RandomNumberGenerator.new()
## The ground, if a world is standing; a headless test has none and gets the pad height.
var provider: TerrainProvider = null
var roads: Array = []
var _bodies := 0
var _masonry: StaticBody3D = null


func _init(node: Node3D, at: Vector3, pad_radius: float, region_id: String, silhouette: bool,
		seed_text: String, terrain: TerrainProvider = null, road_lines: Array = []) -> void:
	root = node
	origin = at
	radius = pad_radius
	region = Ids.name_of(region_id) if region_id.contains("/") else region_id
	culture = str(Settlement.CULTURE_BY_REGION.get(region_id, "vale"))
	far = silhouette
	rng.seed = abs(seed_text.hash())
	provider = terrain if terrain != null else World.terrain()
	roads = road_lines


static func library() -> PropLibrary:
	if _library == null:
		_library = PropLibrary.new()
	return _library


# --- the ground and the water ------------------------------------------------------------

## World height under a world xz; the pad's own height when no ground exists (headless tests).
func ground(x: float, z: float) -> float:
	if provider != null:
		return provider.get_height(x, z)
	return origin.y


## A point in the dressing's local space standing on the ground at local (dx, dz).
func on_ground(dx: float, dz: float, lift := 0.0) -> Vector3:
	return Vector3(dx, ground(origin.x + dx, origin.z + dz) - origin.y + lift, dz)


func is_water(dx: float, dz: float) -> bool:
	if provider == null:
		return false
	return provider.is_water(origin.x + dx, origin.z + dz)


## Water surface height in local space at local (dx, dz), or NAN where there is none.
func water_y(dx: float, dz: float) -> float:
	if provider == null:
		return NAN
	var level := provider.water_level_at(origin.x + dx, origin.z + dz)
	if level <= TerrainProvider.NO_WATER + 1.0:
		return NAN
	return level - origin.y


## Unit direction (local xz) to the nearest water within `max_m`, or ZERO when there is none.
func water_direction(max_m := 120.0) -> Vector2:
	if provider == null:
		return Vector2.ZERO
	var best := INF
	var dir := Vector2.ZERO
	for a in range(0, 360, 10):
		var u := Vector2(sin(deg_to_rad(a)), cos(deg_to_rad(a)))
		var d := 3.0
		while d <= max_m:
			if is_water(u.x * d, u.y * d):
				if d < best:
					best = d
					dir = u
				break
			d += 3.0
	return dir


## Distance along `dir` at which water begins (or 0 when standing in it), then where it ends
## again on the far side, both capped at `max_m`. Used to span a channel from bank to bank.
func water_span(dir: Vector2, max_m := 80.0) -> Vector2:
	if provider == null or dir == Vector2.ZERO:
		return Vector2(-1.0, -1.0)
	var d := 0.0
	var start := -1.0
	while d <= max_m:
		var wet := is_water(dir.x * d, dir.y * d)
		if wet and start < 0.0:
			start = d
		elif not wet and start >= 0.0:
			return Vector2(start, d)
		d += 1.5
	if start >= 0.0:
		return Vector2(start, max_m)
	return Vector2(-1.0, -1.0)


## The way the ground falls from the centre, as a unit local xz, or ZERO on level ground.
func downhill() -> Vector2:
	var best := 0.0
	var dir := Vector2.ZERO
	var h0 := ground(origin.x, origin.z)
	for a in range(0, 360, 15):
		var u := Vector2(sin(deg_to_rad(a)), cos(deg_to_rad(a)))
		var drop := h0 - ground(origin.x + u.x * 24.0, origin.z + u.y * 24.0)
		if drop > best:
			best = drop
			dir = u
	return dir if best > 0.6 else Vector2.ZERO


## The way into the high ground round the centre, out to 32 m, as a unit local xz, or ZERO when
## nothing in reach rises two metres. Each bearing counts by how far it rises, so a cliff along
## one side gives the bearing square into it. A level shelf at a cliff's foot (the Tide Mouth's,
## under the Hushline) has no fall for `downhill` to find, but it has this.
func uphill() -> Vector2:
	var h0 := ground(origin.x, origin.z)
	var sum := Vector2.ZERO
	var top := 0.0
	for a in range(0, 360, 15):
		var u := Vector2(sin(deg_to_rad(a)), cos(deg_to_rad(a)))
		var rise := 0.0
		for i in 3:
			var r := 16.0 + 8.0 * float(i)
			rise = maxf(rise, ground(origin.x + u.x * r, origin.z + u.y * r) - h0)
		top = maxf(top, rise)
		sum += u * rise
	return sum.normalized() if top > 2.0 and sum.length() > 0.001 else Vector2.ZERO


## The direction of the nearest road within `max_m` of the centre, or ZERO. A bridge lies
## along the road that crosses it and a causeway is the road, so both ask this first.
func road_direction(max_m := 40.0) -> Vector2:
	var best := INF
	var dir := Vector2.ZERO
	var here := Vector2(origin.x, origin.z)
	for line_v in roads:
		if typeof(line_v) != TYPE_ARRAY:
			continue
		var line: Array = line_v
		for i in range(line.size() - 1):
			var a: Array = line[i]
			var b: Array = line[i + 1]
			var pa := Vector2(float(a[0]), float(a[1]))
			var pb := Vector2(float(b[0]), float(b[1]))
			var seg := pb - pa
			if seg.length() < 0.5:
				continue
			var t := clampf((here - pa).dot(seg) / seg.length_squared(), 0.0, 1.0)
			var d := (pa + seg * t).distance_to(here)
			if d < best and d <= max_m:
				best = d
				dir = seg.normalized()
	return dir


## Some direction to face things along: the road, else the water, else downhill, else a
## deterministic bearing. Never ZERO.
func grain() -> Vector2:
	for u in [road_direction(), water_direction(60.0), downhill()]:
		if u != Vector2.ZERO:
			return u
	var a := rng.randf_range(0.0, TAU)
	return Vector2(sin(a), cos(a))


static func yaw_of(dir: Vector2) -> float:
	return atan2(dir.x, dir.y)


# --- what the forge built -----------------------------------------------------------------

## A prop of this kind in this region's timber, through the same library the interiors use.
func prop(kind: String, variant := -1) -> String:
	var v := variant if variant >= 0 else rng.randi_range(0, 7)
	return library().resolve(kind, region, v)


func rock(kind: String, variant := -1) -> String:
	return asset(ROCKS, kind, variant)


func tree(kind: String, variant := -1) -> String:
	return asset(TREES, kind, variant)


func flora(kind: String, variant := -1) -> String:
	return asset(FLORA, kind, variant)


## The region's own <region>_<kind>_<variant>.glb under `root_dir`, then any region's. A kind
## the forge has not built anywhere answers "" and the builder leaves that thing out.
func asset(root_dir: String, kind: String, variant := -1) -> String:
	var v := variant if variant >= 0 else rng.randi_range(0, 7)
	var order: Array[String] = [region]
	for r in PropLibrary.REGIONS:
		if r != region:
			order.append(r)
	for r in order:
		var found := variants_of(root_dir, r, kind)
		if not found.is_empty():
			return found[v % found.size()]
	return ""


static func variants_of(root_dir: String, region_short: String, kind: String) -> Array[String]:
	var key := "%s|%s|%s" % [root_dir, region_short, kind]
	if _variants.has(key):
		return _variants[key]
	var out: Array[String] = []
	for v in VARIANTS:
		var slug := "%s_%s_%s" % [region_short, kind, v]
		var path := "%s/%s/%s.glb" % [root_dir, slug, slug]
		if ResourceLoader.exists(path):
			out.append(path)
	_variants[key] = out
	return out


static func scene(path: String) -> PackedScene:
	if _scenes.has(path):
		return _scenes[path]
	var packed: PackedScene = null
	if path != "" and ResourceLoader.exists(path):
		packed = load(path) as PackedScene
	_scenes[path] = packed
	return packed


## The asset's LOD0 mesh, for instancing.
static func mesh(path: String) -> Mesh:
	if _meshes.has(path):
		return _meshes[path]
	var packed := scene(path)
	var m: Mesh = WorldStreamer._mesh_of(packed, 0) if packed != null else null
	_meshes[path] = m
	return m


## The forge's meta file beside the glb: collision kind, bounds, capsule parameters.
static func meta(path: String) -> Dictionary:
	if _metas.has(path):
		return _metas[path]
	var out: Dictionary = {}
	var meta_path := path.get_basename() + ".meta.json"
	if FileAccess.file_exists(meta_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
		if typeof(parsed) == TYPE_DICTIONARY:
			out = parsed
	_metas[path] = out
	return out


static func height_of(path: String) -> float:
	var b: Dictionary = meta(path).get("bounds", {})
	return float(b.get("height", 1.0))


## The forge's `radius` is a bounding sphere about the asset's centre, so it is the number to
## keep clear of, not the asset's half-width.
static func radius_of(path: String) -> float:
	var b: Dictionary = meta(path).get("bounds", {})
	return float(b.get("radius", 0.5))


## Half the asset's footprint across its wider axis: what lifts a thing laid on its side.
static func half_width_of(path: String) -> float:
	var b: Dictionary = meta(path).get("bounds", {})
	var lo: Array = b.get("min", [-0.5, 0.0, -0.5])
	var hi: Array = b.get("max", [0.5, 1.0, 0.5])
	return maxf(float(hi[0]) - float(lo[0]), float(hi[2]) - float(lo[2])) * 0.5


# --- standing things up --------------------------------------------------------------------

## The forged props that never stand in water: a dressing sets its things at offsets from its
## centre, and where a river runs through the pad (a ford, a bridge, a mill, a fall) some of those
## offsets are in it. The batch 3 shots had a cart in a Briarwold river (Barkbridge's, 6 m back from
## the abutment and 3 m aside); on that world the same was true of the carts and signposts at the
## Larkbourne Ford, the Oskel Ford, the Narrows and the log boom, Skarl Mill's cart, sacks and
## millstone, and the bench at the Whitecut. A prop of these kinds set down on water, its foot under
## the surface, is moved to the nearest dry ground within DRY_SEARCH_M, or left out. The buoys'
## barrels and bells, the weir's baskets and the causeway's lamps are not among them: those are the
## water's own.
const DRY_KINDS := ["cart", "signpost", "bench", "sack", "millstone", "chest", "stool", "brazier",
		"crate", "drystone_wall", "drystone_wall_end", "table_round", "table_trestle", "chair", "tent",
		"bedroll", "hay_bale", "wheelbarrow", "anvil", "chopping_block", "campfire", "forge_hearth",
		"market_stall", "well", "gravestone", "coffin", "sarcophagus", "peat_stack", "cooking_pot",
		"milestone", "gate_post", "fence_post_rail", "hen", "pig", "sheep", "goose", "bed", "cupboard",
		"shelf", "name_table", "banner"]
const DRY_SEARCH_M := 9.0
const DRY_UNDER_M := 0.25
## Nothing a dressing sets down stands on a road's way: its foot is kept this far from the road's
## line and half its own width more, or it is moved to the verge, or left out. The debug agent's road
## walk on w4096c found Sulion's barrel on the road at knee height, holding a walker for six seconds,
## and the ruined hall at Bell Street across the Greyfold road. The kinds that belong at a road's edge
## (a signpost, a milestone, a standing lamp) are kept off it the same way; a bridge's are its own.
const ROAD_CLEAR_M := 2.2
const ROAD_WAY_KINDS := ["bridge"]


static func prop_kind(path: String) -> String:
	if not path.contains("/props/"):
		return ""
	var parts := path.get_file().get_basename().split("_")
	if parts.size() <= 2:
		return ""
	return "_".join(parts.slice(1, parts.size() - 1))


## Whether a thing's foot at local `at` is in the water: on a water texel, under its surface.
func in_water(at: Vector3) -> bool:
	if provider == null or not is_water(at.x, at.z):
		return false
	var wy := water_y(at.x, at.z)
	return not is_nan(wy) and at.y < wy - DRY_UNDER_M


## Where a prop set down at local `at` stands: there when it is clear, else the nearest clear ground
## within DRY_SEARCH_M (on the ground), else NAN in x for nowhere. Clear is dry for a DRY_KINDS kind,
## and for every prop, off the road's way (ROAD_CLEAR_M).
func dry_spot(path: String, at: Vector3) -> Vector3:
	var kind := prop_kind(path)
	if kind == "":
		return at
	var wet := DRY_KINDS.has(kind)
	var clear := _road_clear_of(path)
	if _clear(at, wet, clear):
		return at
	var r := 1.5
	while r <= DRY_SEARCH_M:
		for i in 16:
			var a := TAU * float(i) / 16.0
			var g := on_ground(at.x + sin(a) * r, at.z + cos(a) * r)
			if _clear(g, wet, clear):
				return g
		r += 1.5
	return Vector3(NAN, NAN, NAN)


func _clear(at: Vector3, wet: bool, road_clear: float) -> bool:
	if wet and in_water(at):
		return false
	return road_clear <= 0.0 or road_distance(Vector2(at.x, at.z)) >= road_clear


## How far a prop's foot keeps from a road's line: 0 where it need not (a bridge's own things).
func _road_clear_of(path: String) -> float:
	if roads.is_empty() or ROAD_WAY_KINDS.has(str(root.get("kind")) if root != null else ""):
		return 0.0
	return ROAD_CLEAR_M + half_width_of(path) * 0.8


var _near_roads: Array = []   # [PackedVector2Array] of local segments' ends, near the pad
var _near_roads_read := false


## The distance from local xz `at` to the nearest road's line (INF where none runs near the pad).
func road_distance(at: Vector2) -> float:
	if not _near_roads_read:
		_near_roads_read = true
		var here := Vector2(origin.x, origin.z)
		var reach := radius + DRY_SEARCH_M + 10.0
		for line_v in roads:
			if typeof(line_v) != TYPE_ARRAY:
				continue
			var line: Array = line_v
			for i in range(line.size() - 1):
				var a := Vector2(float(line[i][0]), float(line[i][1])) - here
				var b := Vector2(float(line[i + 1][0]), float(line[i + 1][1])) - here
				if Geometry2D.get_closest_point_to_segment(Vector2.ZERO, a, b).length() < reach:
					_near_roads.append(PackedVector2Array([a, b]))
	var best := INF
	for seg_v in _near_roads:
		var seg: PackedVector2Array = seg_v
		best = minf(best, Geometry2D.get_closest_point_to_segment(at, seg[0], seg[1]).distance_to(at))
	return best

## One instance of a forge asset at a local position, on its feet (the forge exports every
## grounded asset with its base at y = 0). Adds the collision the forge named for it unless
## told not to, or the far ring is being dressed. Returns null if the asset does not exist.
func place(path: String, at: Vector3, yaw := 0.0, scale := 1.0, collide := true,
		tilt := Vector3.ZERO, silhouette := false) -> Node3D:
	if far and not silhouette:
		return null
	at = dry_spot(path, at)
	if is_nan(at.x):
		return null
	var packed := scene(path)
	if packed == null:
		return null
	var node := packed.instantiate()
	if not (node is Node3D):
		node.queue_free()
		return null
	var inst: Node3D = node
	inst.position = at
	inst.rotation = Vector3(tilt.x, yaw, tilt.z)
	inst.scale = Vector3.ONE * scale
	inst.name = path.get_file().get_basename()
	root.add_child(inst)
	if far:
		_far_range(inst)
	elif collide:
		_collide(inst, path, scale)
	return inst


## Many of one asset in one MultiMesh, each `Transform3D` in local space. Per-instance
## collision shares one shape between all of them, so a cairn of sixty pebbles costs one
## shape and one body. `collide` left out, a rock collides and anything else does not: a builder's
## boulders were walked through wherever it had not said so, and a rock too low to walk into
## (under ScatterSolids.MIN_HEIGHT_M as it stands) or loose (scree) is still stepped over.
func scatter(path: String, transforms: Array, collide: Variant = null, silhouette := false,
		shadows := true) -> MultiMeshInstance3D:
	var low_passes := collide == null
	if collide == null:
		collide = path.contains("/rocks/") and str(ScatterSolids.spec_for(path)["kind"]) != "none"
	if transforms.is_empty() or (far and not silhouette):
		return null
	if prop_kind(path) != "" and (provider != null or not roads.is_empty()):
		var dry: Array = []
		for xf_v in transforms:
			var xf: Transform3D = xf_v
			var at := dry_spot(path, xf.origin)
			if not is_nan(at.x):
				dry.append(Transform3D(xf.basis, at))
		transforms = dry
		if transforms.is_empty():
			return null
	var m := mesh(path)
	if m == null:
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = m
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.name = path.get_file().get_basename() + "_x%d" % transforms.size()
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mmi)
	if far:
		_far_range(mmi)
	elif collide:
		var body := StaticBody3D.new()
		body.name = mmi.name + "_body"
		body.collision_layer = 1 << 0
		var underfoot := surface_of_asset(path)
		if not underfoot.is_empty():
			body.set_meta(SURFACE_META, underfoot)
		var added := 0
		var tall := height_of(path)
		for xf in transforms:
			var t: Transform3D = xf
			var s := t.basis.get_scale().x
			if low_passes and tall * s < ScatterSolids.MIN_HEIGHT_M:
				continue
			for part in shapes_for(path, s):
				var cs := CollisionShape3D.new()
				cs.shape = part["shape"]
				cs.transform = Transform3D(t.basis.orthonormalized(), t.origin) * part["xform"]
				body.add_child(cs)
				added += 1
		if added > 0:
			root.add_child(body)
			_bodies += 1
		else:
			body.queue_free()
	return mmi


## A silhouette piece in the far ring: drawn out to the far range, no shadow. A forge asset
## carries LOD0/1/2 siblings whose import bands would blank it past 260 m, which is where a
## far piece lives; the middle rung is kept alone and drawn all the way out.
func _far_range(node: Node3D) -> void:
	var meshes: Array = []
	if node is GeometryInstance3D:
		meshes.append(node)
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		if mi != node:
			meshes.append(mi)
	var by_level: Dictionary = {}
	for gi_v in meshes:
		var gi: GeometryInstance3D = gi_v
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var level := 0
		var n := str(gi.name)
		for suffix in ["_LOD1", "_LOD2", "_LOD3"]:
			if n.ends_with(suffix):
				level = int(suffix.substr(4))
		by_level.get_or_add(level, []).append(gi)
	var keep := 1 if by_level.has(1) else 0
	for level in by_level:
		for gi_v in by_level[level]:
			var gi: GeometryInstance3D = gi_v
			if int(level) != keep:
				gi.visible = false
				continue
			gi.visible = true
			gi.visibility_range_begin = 0.0
			gi.visibility_range_begin_margin = 0.0
			gi.visibility_range_end = FAR_RANGE
			gi.visibility_range_end_margin = 60.0
			gi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF


func _collide(inst: Node3D, path: String, scale: float) -> void:
	var parts := shapes_for(path, scale)
	if parts.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1 << 0
	var underfoot := surface_of_asset(path)
	if not underfoot.is_empty():
		body.set_meta(SURFACE_META, underfoot)
	for part in parts:
		var cs := CollisionShape3D.new()
		cs.shape = part["shape"]
		cs.transform = part["xform"]
		body.add_child(cs)
	# the body is the instance's child, so it has to undo the instance's scale: shapes were
	# built already scaled
	body.scale = Vector3.ONE / maxf(scale, 0.001)
	inst.add_child(body)
	_bodies += 1


## The collision the forge authored for an asset, as shapes with local transforms, at a given
## uniform scale (baked into the shape, because a scaled CollisionShape3D is not reliable).
## `convex` and `trimesh` come off the LOD0 mesh; a `*_col.glb` is the forge's own simplified
## mesh; `capsule` is the trunk of a tree or the shaft of a post, never the crown the meta
## measured, because a player should bump into a trunk and walk under branches.
static func shapes_for(path: String, scale := 1.0) -> Array:
	var key := "%s@%.2f" % [path, scale]
	if _shapes.has(key):
		return _shapes[key]
	var out: Array = []
	var info := meta(path)
	var kind := str(info.get("collision", "none"))
	var m := mesh(path)
	if kind == "convex" and m != null:
		var shape := m.create_convex_shape(true, false)
		out.append({"shape": _scaled(shape, scale), "xform": Transform3D.IDENTITY})
	elif kind == "trimesh" and m != null:
		out.append({"shape": _scaled(m.create_trimesh_shape(), scale), "xform": Transform3D.IDENTITY})
	elif kind == "capsule":
		var b: Dictionary = info.get("bounds", {})
		var h := float(b.get("height", 2.0)) * scale
		var p: Dictionary = info.get("collision_params", {})
		var r := float(p.get("radius", 0.2)) * scale
		if path.contains("/trees/"):
			r = clampf(h * 0.028, 0.18, 0.9)
			h = h * 0.7
		var cap := CapsuleShape3D.new()
		cap.radius = r
		cap.height = maxf(h, r * 2.0 + 0.05)
		out.append({"shape": cap, "xform": Transform3D(Basis.IDENTITY, Vector3(0.0, cap.height * 0.5, 0.0))})
	elif kind.ends_with(".glb"):
		var col_path := path.get_base_dir() + "/" + kind
		var packed := scene(col_path)
		if packed != null:
			var source: Node = packed.instantiate()
			for mi in source.find_children("*", "MeshInstance3D", true, false):
				var cm: Mesh = (mi as MeshInstance3D).mesh
				if cm == null:
					continue
				var xf := WorldStreamer._transform_within(mi as Node3D, source)
				xf.origin *= scale
				out.append({"shape": _scaled(cm.create_trimesh_shape(), scale), "xform": xf})
			source.queue_free()
	_shapes[key] = out
	return out


static func _scaled(shape: Shape3D, scale: float) -> Shape3D:
	if is_equal_approx(scale, 1.0):
		return shape
	if shape is ConvexPolygonShape3D:
		var pts := (shape as ConvexPolygonShape3D).points.duplicate()
		for i in pts.size():
			pts[i] *= scale
		var c := ConvexPolygonShape3D.new()
		c.points = pts
		return c
	if shape is ConcavePolygonShape3D:
		var faces := (shape as ConcavePolygonShape3D).get_faces().duplicate()
		for i in faces.size():
			faces[i] *= scale
		var t := ConcavePolygonShape3D.new()
		t.set_faces(faces)
		return t
	return shape


## A box you can bump into, for things built at runtime. All of a dressing's built collision
## hangs off one body, so each shape names what it is made of (`surface`: stone, wood, dirt ...)
## and a foot on a timber deck beside a stone parapet hears the timber (Foley.surface_at).
func collider(size: Vector3, xform: Transform3D, underfoot := "") -> void:
	if far:
		return
	if _masonry == null:
		_masonry = StaticBody3D.new()
		_masonry.name = "Masonry"
		_masonry.collision_layer = 1 << 0
		root.add_child(_masonry)
		_bodies += 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# a block whose height came out negative (a pier whose foot is above its deck) is still
	# a thing you bump into, not an error
	box.size = size.abs().max(Vector3.ONE * 0.05)
	cs.shape = box
	cs.transform = xform
	if not underfoot.is_empty():
		cs.set_meta(SURFACE_META, underfoot)
	_masonry.add_child(cs)


func collider_shape(shape: Shape3D, xform: Transform3D, underfoot := "") -> void:
	if far or shape == null:
		return
	if _masonry == null:
		_masonry = StaticBody3D.new()
		_masonry.name = "Masonry"
		_masonry.collision_layer = 1 << 0
		root.add_child(_masonry)
		_bodies += 1
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = xform
	if not underfoot.is_empty():
		cs.set_meta(SURFACE_META, underfoot)
	_masonry.add_child(cs)


func bodies() -> int:
	return _bodies


## What a forged asset is made of underfoot, from its name: a pier, a jetty, a boardwalk, a cart or
## anything of plank and log is wood; a wall, a stair, a bridge of stone, a cairn or a ruin is
## stone. "" leaves it to the ground beneath (a bush, a banner).
static func surface_of_asset(path: String) -> String:
	var n := path.get_file().get_basename().to_lower()
	if n.contains("scree"):
		return "gravel"
	for word in WOOD_WORDS:
		if n.contains(word):
			return "wood"
	for word in STONE_WORDS:
		if n.contains(word):
			return "stone"
	return ""


# --- surfaces ------------------------------------------------------------------------------

func _spec(kind: String) -> Dictionary:
	var by_region: Dictionary = SURFACES.get(region, SURFACES["hearthvale"])
	return by_region.get(kind, by_region["stone"])


## A painted surface: `kind` is stone, timber, planks or earth in this region's colours, or
## "oroth" for the Builders' fused masonry.
func surface(kind: String, wear := 0.5) -> ShaderMaterial:
	var pattern := 2
	var spec: Dictionary
	match kind:
		"oroth":
			spec = OROTH
		"timber":
			spec = _spec("timber")
			pattern = 3
		"planks":
			spec = _spec("planks")
			pattern = 1
		"earth":
			spec = _spec("earth")
			pattern = 5
		_:
			spec = _spec("stone")
	return painted(pattern, spec, wear)


static func painted(pattern: int, spec: Dictionary, wear := 0.5, variation := 0.6) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(SURFACE_SHADER)
	mat.set_shader_parameter("pattern", pattern)
	mat.set_shader_parameter("base_color", Color.html(str(spec.get("base", "#cccccc"))))
	mat.set_shader_parameter("accent_color", Color.html(str(spec.get("accent", "#999999"))))
	mat.set_shader_parameter("grout_color", Color.html(str(spec.get("grout", "#555555"))))
	mat.set_shader_parameter("unit_size", float(spec.get("unit", 0.4)))
	mat.set_shader_parameter("wear", wear)
	mat.set_shader_parameter("variation", variation)
	return mat


## Plain materials for the few things that are not painted masonry: bronze, black glass, snow.
static func plain(albedo: Color, roughness := 0.7, metallic := 0.0, emission := Color.BLACK,
		emission_energy := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = roughness
	m.metallic = metallic
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	return m


## Standing water in this region's colours, its depth read against `floor_y` (local).
func still_water(floor_local_y: float, tint := Color.WHITE, transparency := 0.72) -> ShaderMaterial:
	var look: Array = WATER_LOOK.get(region, WATER_LOOK["hearthvale"])
	var mat := ShaderMaterial.new()
	mat.shader = load(STILL_WATER_SHADER)
	mat.set_shader_parameter("shallow_color", (look[0] as Color) * tint)
	mat.set_shader_parameter("deep_color", (look[1] as Color) * tint)
	mat.set_shader_parameter("floor_y", origin.y + floor_local_y)
	mat.set_shader_parameter("depth_fade", 2.0)
	mat.set_shader_parameter("transparency", transparency)
	return mat


## Water falling, or the black glass a fall left behind when it was sung dry.
static func falling_water(glass := false, speed := 2.6) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(FALLING_WATER_SHADER)
	mat.set_shader_parameter("glass", 1.0 if glass else 0.0)
	mat.set_shader_parameter("speed", speed)
	return mat


# --- light, smoke and the stone that keeps a name -----------------------------------------

## A fire's or a lantern's light, as a source for NightLights rather than a light of its own.
##
## Every one of these used to be an always-on OmniLight3D -- 27 calls across the builders, six
## along the Long Stride alone -- and nothing counted them against the pool of lamps NightLights
## hands out, so beside a causeway the two together passed the twelve lights Compatibility draws
## on one object and it dropped the rest without a word. Registered here, the fire is a glow that
## reads from across the valley at night, and it takes one of the pool's real lights, at the
## energy and reach given, whenever it is among the nearest to the camera -- by day as well,
## because a camp's fire burns at noon. The far ring registers too; it is never near enough to
## be given a light, and its glow is what a far camp is.
func light(at: Vector3, colour := Color(1.0, 0.72, 0.42), energy := 2.2, reach := 11.0) -> void:
	if root.is_inside_tree():
		NightLights.add(root, [root.to_global(at)], "poi", Color(colour.r, colour.g, colour.b, 1.0), energy, reach)


## Light thrown back into a place the sun leaves in shadow, a cave's mouth: one of NightLights'
## real lights when the camera is near, by day as well, and no glow, because nothing there burns.
func bounce_light(at: Vector3, colour := Color(0.9, 0.86, 0.78), energy := 1.0, reach := 10.0) -> void:
	if root.is_inside_tree():
		NightLights.add(root, [root.to_global(at)], "bounce", Color(colour.r, colour.g, colour.b, 1.0), energy, reach)


## Smoke, mist or spray: a soft billboard puff emitted in a column or a spread.
func puffs(at: Vector3, spread: Vector3, rise: float, amount: int, colour: Color,
		size := 1.6, life := 4.0) -> GPUParticles3D:
	if far:
		return null
	var p := GPUParticles3D.new()
	p.position = at
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.visibility_aabb = AABB(Vector3(-spread.x - size, -1.0, -spread.z - size),
			Vector3(spread.x * 2.0 + size * 2.0, spread.y + rise * life + size * 2.0, spread.z * 2.0 + size * 2.0))
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = spread
	mat.direction = Vector3.UP
	mat.spread = 12.0
	mat.initial_velocity_min = rise * 0.7
	mat.initial_velocity_max = rise * 1.3
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.7
	mat.scale_max = 1.3
	var ramp := Gradient.new()
	ramp.set_color(0, Color(colour.r, colour.g, colour.b, 0.0))
	ramp.set_color(1, Color(colour.r, colour.g, colour.b, 0.0))
	ramp.add_point(0.25, Color(colour.r, colour.g, colour.b, colour.a))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	mat.color_ramp = ramp_tex
	p.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var qm := StandardMaterial3D.new()
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.vertex_color_use_as_albedo = true
	qm.albedo_texture = _soft_disc()
	qm.no_depth_test = false
	quad.material = qm
	p.draw_pass_1 = quad
	p.name = "Puffs"
	root.add_child(p)
	return p


static var _disc: Texture2D = null


## A soft radial disc drawn by the engine, the one texture the puffs need.
static func _soft_disc() -> Texture2D:
	if _disc != null:
		return _disc
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.45, Color(1, 1, 1, 0.55))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 64
	t.height = 64
	_disc = t
	return t


## The stone that keeps a name. Its id is the id of the place it stands at, because that is
## what a quest's `rest_at` names and what the Hearth remembers.
func hearthstone(at: Vector3, yaw: float, id: String, display_name: String) -> Hearthstone:
	if far:
		return null
	var packed := load(HEARTHSTONE_SCENE) as PackedScene
	var stone: Hearthstone = packed.instantiate() as Hearthstone if packed != null else Hearthstone.new()
	stone.hearthstone_id = id
	stone.display_name = display_name
	stone.place_id = id
	stone.name = "Hearthstone"
	stone.position = at
	stone.rotation.y = yaw
	root.add_child(stone)
	return stone


## A named point on the pad that something else looks for: a quest item's `spot` (the hand-bell
## in the Tumbled Watch's fallen stair), an encounter's `at`, or, with `worked`, where a
## resident's schedule has them stand (group `npc_spot`, found by name and by the place it
## belongs to, so two dressings' `the_fire` are never mistaken for each other). `raised` says the
## floor there is a deck or a mound rather than the terrain, and holds for `radius` metres, so a
## person standing on it is not snapped to the lake bed underneath. Nothing in the far ring.
func marker(marker_name: String, at: Vector3, worked := false, raised := false, reach := 3.0) -> Marker3D:
	if far:
		return null
	var m := Marker3D.new()
	m.name = marker_name
	m.position = at
	m.set_meta("place", str(root.get("poi_id")) if root.get("poi_id") != null else "")
	if worked:
		m.add_to_group(NpcRegistry.SPOT_GROUP)
	if raised:
		m.set_meta("raised", true)
		m.set_meta("radius", reach)
	root.add_child(m)
	return m


## Something that can be touched: the cup going round the Cold Fire Camp, which a
## `PoiEncounters` group waits on (`rises_when`), or the One Poppy, which puts a conversation
## (`dialogue_id`) and is gone once `gone_flag` is set. Nothing in the far ring.
func touchable(touch_name: String, at: Vector3, prompt_line: String, dialogue_id := "",
		gone_flag := "", once := true) -> PoiTouch:
	if far:
		return null
	var t := PoiTouch.new()
	t.name = touch_name
	t.prompt = prompt_line
	t.dialogue_id = dialogue_id
	t.gone_flag = gone_flag
	t.once = once
	t.position = at
	root.add_child(t)
	return t


## A notice post the radiant generator fills, for a place whose sentence says there is work to be
## had there (the charcoal camp's "merchant and jobs"): the same `JobBoard` a village green has,
## with the place's own id, so its notices are for the country round it. Nothing in the far ring.
func job_board(at: Vector3, yaw: float) -> JobBoard:
	if far:
		return null
	var board := JobBoard.new()
	board.name = "JobBoard"
	board.place_id = str(root.get("poi_id")) if root.get("poi_id") != null else ""
	board.display_name = "the notice post"
	board.position = at
	board.rotation.y = yaw
	root.add_child(board)
	# what you see is a signpost; what the interaction ray finds is the board's own box
	place(prop("signpost"), at, yaw, 1.0, false)
	return board


# --- small helpers ---------------------------------------------------------------------------

func jitter(amount: float) -> Vector2:
	return Vector2(rng.randf_range(-amount, amount), rng.randf_range(-amount, amount))


## A ring of `count` local xz points about `centre` at `ring_r`, each nudged a little.
func ring(count: int, ring_r: float, centre := Vector2.ZERO, wobble := 0.08, start := NAN) -> Array:
	var out: Array = []
	var a0 := start if not is_nan(start) else rng.randf_range(0.0, TAU)
	for i in count:
		var a := a0 + TAU * float(i) / float(count) + rng.randf_range(-wobble, wobble) * TAU / float(count)
		var r := ring_r * rng.randf_range(0.94, 1.06)
		out.append(centre + Vector2(sin(a), cos(a)) * r)
	return out


## Whether the POI's own words name a thing, so a builder can answer its brief.
static func brief_says(brief: String, words: Array) -> bool:
	var low := brief.to_lower()
	for w in words:
		if low.contains(str(w)):
			return true
	return false


static func transform_at(at: Vector3, yaw := 0.0, scale := 1.0, tilt := Vector3.ZERO) -> Transform3D:
	var basis := Basis.from_euler(Vector3(tilt.x, yaw, tilt.z)).scaled(Vector3.ONE * scale)
	return Transform3D(basis, at)
