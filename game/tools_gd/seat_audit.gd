extends RefCounted
## Is everything the world stands up standing on something?
##
## The user keeps finding them: a lamp in the air, a tree a hand above the grass, a fence run
## across a road or broken in the middle, a prop that looks dropped in to test something. This
## looks at every placed thing in the streamed country round a point -- the cells' scatter (the
## rows the builder wrote, trees and rocks included), the points of interest's pieces, the
## settlements' props and fabric, the wayside's posts and gates, the lamps and lights -- and says,
## for each, what is wrong with where it stands:
##
## * `floating`: its lowest point is more than FLOAT_M over the highest ground under its footprint
##   and nothing solid (a collider, or another thing's top) is under it within that;
## * `buried`: all of it is under the ground; `sunk`: a prop with more than SUNK_SHARE of its
##   height under the ground at its middle;
## * `lamp_unhung`: a hanging lamp or lantern with no post, bracket, wall or ground within
##   LAMP_REACH_M; `light_unhung`: a light with nothing at all within LIGHT_REACH_M;
## * `on_road`: something standing that is not road furniture, inside a road's carriageway;
## * `fence_gap`: a gap of FENCE_GAP_M to FENCE_GAP_MAX_M in the middle of a fence or rail run, in
##   line with the run on both sides, with no gate or road through it;
## * `fence_lone`: a placed length of fence or rail joined to nothing, stood alone in a field;
## * `overlap`: two solid props sharing more than OVERLAP_SHARE of the smaller's box (not a tent or
##   a stall and what is in it), or a tree
##   whose trunk stands inside a building.
##
## Each finding names its source: which builder or data put the thing there (`scatter` is the
## world build's cells, `poi:<kind>` the point-of-interest builders, `settlement:<kind>` the
## settlements, `wayside` the wayside's posts and gates, `landmark` a cell's scenes, `lights` the
## night lights) and its family (the asset's name without its region and variant). Things merged
## into one mesh for a whole cell or a whole town (a cell's gates, a town's fences) are looked at
## a vertex at a time where they meet the ground.
##
## Used by ground_probe.gd (`./run.sh seats`, the whole map) and tests/unit/test_objects_seated.gd
## (one region at a time, against a baseline).

const FLOAT_M := 0.15
const SUNK_SHARE := 0.6
const LAMP_REACH_M := 0.3
const LIGHT_REACH_M := 0.5
const FENCE_GAP_M := 1.0
const FENCE_GAP_MAX_M := 4.0
const OVERLAP_SHARE := 0.6
## Taller than this and a thing in a carriageway is in the way (grass and flowers are not).
const STANDING_M := 0.35
## A mesh whose box is wider than this is a merge of many things (a cell's gates, a town's fences)
## and is looked at a vertex at a time.
const MERGED_M := 12.0
## Merged meshes are looked at in columns this wide: every column that holds any of the mesh must
## touch the ground somewhere (a fence post, a wall's foot) or be held up by something.
const COLUMN_M := 6.0
const HASH_M := 4.0

const REGION_PREFIXES := ["hearthvale_", "briarwold_", "brightwater_", "sedgemire_", "skerrow_",
	"cinderlea_", "vale_", "common_", "shared_"]
const LAMP_RE := "lamp|lantern|sconce|torch|candle|brazier|beacon"
const STANDING_LAMP_RE := "post|standard|brazier|beacon|pole|stand|lamppost|street"
const FENCE_RE := "fence|rail|paling|wattle|hurdle|palisade|drystone|wall_run"
## Things with room inside them: a bedroll in a tent's mouth is where it belongs.
const SHELTER_RE := "tent|awning|stall|lean_to|canopy|shelter|booth|cart|wagon|bench|table|bed|trough"
const ROAD_FURNITURE_RE := "road|street|cobble|paving|path|kerb|bridge|ford|deck|causeway|sign|fingerpost|milestone|waystone|gate|toll|verge|made_ground|ground|puddle|rut|stepping"
const FLOATS_RE := "boat|buoy|raft|punt|float|lily|reed|net|coracle|jetty|pier|pontoon|barge|duck|swan"
## (not gates: a gate's leaf clears the ground by design, and its posts are looked at one by one)
const MERGED_STANDING_RE := "fence|rail|paling|wattle|hurdle|hedge|wall|drystone"

var world: World = null
var streamer: WorldStreamer = null
var terrain: TerrainProvider = null
var space: PhysicsDirectSpaceState3D = null
var findings: Array[Dictionary] = []
## source -> check -> count
var counts: Dictionary = {}
var looked_at := 0
var merged_skipped: Array[String] = []
## Headless, the dummy renderer keeps no MultiMesh's instances: they read back as the cell's own
## origin, so every blade of grass would be "buried". The cells' plain scatter is only looked at
## drawn (`./run.sh seats`); headless it is left out, and said so in `headless`.
var headless := DisplayServer.get_name() == "headless"

var _segments: Array = []          # [a: Vector2, b: Vector2, half: float, id: String]
var _seg_hash: Dictionary = {}     # Vector2i -> Array[int]
var _lamp_re := RegEx.new()
var _standing_lamp_re := RegEx.new()
var _fence_re := RegEx.new()
var _furniture_re := RegEx.new()
var _floats_re := RegEx.new()
var _shelter_re := RegEx.new()
var _merged_standing_re := RegEx.new()
var _poi_kind_cache: Dictionary = {}


func _init(w: World) -> void:
	world = w
	streamer = w.streamer if w != null else null
	terrain = World.terrain()
	space = w.get_world_3d().direct_space_state if w != null and w.is_inside_tree() else null
	_lamp_re.compile(LAMP_RE)
	_standing_lamp_re.compile(STANDING_LAMP_RE)
	_fence_re.compile(FENCE_RE)
	_furniture_re.compile(ROAD_FURNITURE_RE)
	_floats_re.compile(FLOATS_RE)
	_shelter_re.compile(SHELTER_RE)
	_merged_standing_re.compile(MERGED_STANDING_RE)
	_load_roads()


# --- what is looked at -------------------------------------------------------------------------

## Audits everything standing in the streamed cells in `cells` (built at full detail), and the
## settlements' fabric over them. Returns the findings added.
func audit_cells(cells: Array) -> Array[Dictionary]:
	var start := findings.size()
	var rects: Array[Rect2] = []
	var objects: Array[Dictionary] = []
	for c: Vector2i in cells:
		var node := streamer.get_node_or_null("Cell_%d_%d" % [c.x, c.y]) as Node3D
		if node == null:
			continue
		if int(node.get_meta("ring", 0)) > streamer.full_ring:
			continue
		var centre := streamer.cell_centre(c)
		var half := streamer.cell_size * 0.5
		var rect := Rect2(centre.x - half, centre.y - half, half * 2.0, half * 2.0)
		rects.append(rect)
		_walk(node, objects, "cell", rect)
		_scatter_groups(node, objects, rect)
	# what is not in a cell: the settlements (all raised at the start), the night lights
	for extra: Node in _outside_cells():
		for rect in rects:
			_walk(extra, objects, _anchor_of(extra, "world"), rect)
	looked_at += objects.size()
	_check(objects)
	return findings.slice(start)


func _outside_cells() -> Array[Node]:
	var out: Array[Node] = []
	if world == null:
		return out
	for n: Node in world.get_children():
		if n == streamer or n == world.terrain_node or n == world.water or n == world.atmosphere \
				or n == world.fly_camera or n is Camera3D or n is CanvasLayer:
			continue
		var nm := str(n.name)
		if nm in ["Horizon", "HorizonLayer", "PlayerSpawn", "TerrainProvider", "Fallback"] or nm.begins_with("Horizon"):
			continue
		out.append(n)
	return out


## Every placed thing under `node` whose middle is in `rect`, as an object record.
func _walk(node: Node, out: Array[Dictionary], anchor: String, rect: Rect2) -> void:
	for c: Node in node.get_children():
		_visit(c, out, anchor, rect)


func _visit(n: Node, out: Array[Dictionary], anchor: String, rect: Rect2) -> void:
	if _skipped(n):
		return
	var a := _anchor_of(n, anchor)
	if n is MultiMeshInstance3D:
		if not n.has_meta("lod_group") and not headless:
			_add_multimesh(n as MultiMeshInstance3D, out, a, rect)
		return
	if n is Node3D and n.scene_file_path != "":
		_add_whole(n as Node3D, out, a, rect, "prop")
		return
	if str(n.name).begins_with("Building_"):
		_add_whole(n as Node3D, out, a, rect, "building")
		return
	if n is Light3D:
		var p := (n as Node3D).global_position
		if rect.has_point(Vector2(p.x, p.z)):
			out.append({"kind": "light", "src": a, "family": "light", "asset": str(n.name), "at": p,
				"aabb": AABB(p, Vector3.ZERO), "node": n})
	elif n is GeometryInstance3D and (n as GeometryInstance3D).is_visible_in_tree() and _drawable(n):
		_add_mesh(n as GeometryInstance3D, out, a, rect)
	_walk(n, out, a, rect)


func _skipped(n: Node) -> bool:
	if n is CharacterBody3D or n is Camera3D or n is CollisionShape3D or n is CanvasLayer:
		return true
	if n is GPUParticles3D or n is CPUParticles3D or n is Decal or n is Label3D or n is Sprite3D:
		return true
	if n.is_in_group("actors") or n.is_in_group("player") or n.is_in_group("enemy"):
		return true
	var nm := str(n.name)
	if nm == "Encounters" or nm == "Livestock" or nm.begins_with("Npc") or nm == "PlayerSpawn":
		return true
	# a body stood up by anything (an NPC at its post, the player) is an actor, not a prop
	return n.scene_file_path.ends_with("humanoid_model.tscn") or n.scene_file_path.contains("/actors/")


func _drawable(n: Node) -> bool:
	if n is MeshInstance3D:
		return (n as MeshInstance3D).mesh != null
	return true


## Who put a thing there, from the nearest named owner above it.
func _anchor_of(n: Node, current: String) -> String:
	var nm := str(n.name)
	if nm.begins_with("Poi_"):
		var id := nm.substr(4)
		return "poi:%s" % _poi_kind(id)
	if nm.begins_with("Fabric_"):
		return "settlement:%s" % nm.substr(7)
	if nm == "Fingerpost" or nm == "Gates" or nm.begins_with("Wayside"):
		return "wayside"
	if n is NightLights or nm == "NightLights":
		return "lights"
	if nm.begins_with("QuestItem") or nm == "QuestItems":
		return "quest_items"
	return current


func _poi_kind(name: String) -> String:
	if _poi_kind_cache.has(name):
		return _poi_kind_cache[name]
	var def := ContentDB.get_or_empty("core:poi/%s" % name)
	if def.is_empty():
		def = ContentDB.get_or_empty("core:place/%s" % name)
	var k := "%s/%s" % [str(def.get("kind", "?")), name] if name == "stair_head" else str(def.get("kind", "?"))
	_poi_kind_cache[name] = k
	return k


func _add_multimesh(mmi: MultiMeshInstance3D, out: Array[Dictionary], anchor: String, rect: Rect2) -> void:
	var mm := mmi.multimesh
	if mm == null or mm.mesh == null or not mmi.is_visible_in_tree():
		return
	var local := mm.mesh.get_aabb()
	var asset := str(mmi.get_meta("asset_path", mmi.name))
	var src := anchor if anchor != "cell" else "scatter"
	var fam := family(asset)
	var solid := _has_body(mmi.get_parent())
	# a MultiMesh sized for more than it draws (the density setting thins grass and herbs by
	# drawing fewer) leaves the rest as zero transforms at the cell's corner: only what is drawn
	var drawn := mm.instance_count if mm.visible_instance_count < 0 else mini(mm.visible_instance_count, mm.instance_count)
	for i in drawn:
		var it := mm.get_instance_transform(i)
		if it.basis.determinant() == 0.0:
			continue
		var xf := mmi.global_transform * it
		var box := xf * local
		var c := box.get_center()
		if not rect.has_point(Vector2(c.x, c.z)):
			continue
		out.append({"kind": "instance", "src": src, "family": fam, "asset": asset, "aabb": box,
			"at": xf.origin, "solid": solid, "axis": _axis_of(xf, local), "flora": asset.contains("/flora/")})


## The scatter drawn by level of detail (trees, rocks, walls and the big props): each group keeps
## its instances' transforms as it composed them from the cell's rows after the wayside fitted them
## (ScatterLod.Group.rows, the MultiMesh buffer's own layout), which a headless run can read where
## it cannot read a MultiMesh back.
func _scatter_groups(cell_node: Node3D, out: Array[Dictionary], rect: Rect2) -> void:
	for g: Variant in streamer.get("_lod_groups"):
		var group := g as ScatterLod.Group
		if group == null or group.cell != cell_node or group.ladder == null:
			continue
		var asset := group.ladder.asset_path
		var mesh: Mesh = null
		for level: Dictionary in group.ladder.levels:
			mesh = level.get("solid", null) if level.get("solid", null) != null else level.get("leaves", null)
			if mesh != null:
				break
		if mesh == null:
			continue
		var local := mesh.get_aabb()
		var fam := family(asset)
		var n := group.count()
		var st := ScatterLod.STRIDE
		for i in n:
			var o := i * st
			var r := group.rows
			var xf := Transform3D(Basis(Vector3(r[o], r[o + 4], r[o + 8]), Vector3(r[o + 1], r[o + 5], r[o + 9]),
					Vector3(r[o + 2], r[o + 6], r[o + 10])), Vector3(r[o + 3], r[o + 7], r[o + 11]))
			xf = cell_node.global_transform * xf
			var box := xf * local
			var ctr := box.get_center()
			if not rect.has_point(Vector2(ctr.x, ctr.z)):
				continue
			out.append({"kind": "instance", "src": "scatter", "family": fam, "asset": asset, "aabb": box,
				"at": xf.origin, "solid": true, "axis": _axis_of(xf, local), "flora": asset.contains("/flora/")})


## A placed scene or a built building: one object, the box of everything drawn in it.
func _add_whole(n: Node3D, out: Array[Dictionary], anchor: String, rect: Rect2, kind: String) -> void:
	if not n.is_visible_in_tree():
		return
	var box := _drawn_box(n)
	if box.size == Vector3.ZERO:
		return
	var c := box.get_center()
	if not rect.has_point(Vector2(c.x, c.z)):
		return
	var asset := n.scene_file_path if n.scene_file_path != "" else str(n.name)
	out.append({"kind": kind, "src": anchor, "family": family(str(n.name) if kind == "building" else asset),
		"asset": asset, "aabb": box, "at": n.global_position, "node": n, "solid": _has_body(n),
		"axis": _axis_of(n.global_transform, _local_box(n)), "flora": asset.contains("/flora/")})


func _add_mesh(g: GeometryInstance3D, out: Array[Dictionary], anchor: String, rect: Rect2) -> void:
	var box := g.global_transform * g.get_aabb()
	var c := box.get_center()
	if not rect.has_point(Vector2(c.x, c.z)):
		return
	var nm := str(g.name)
	if maxf(box.size.x, box.size.z) > MERGED_M:
		if _merged_standing_re.search(nm.to_lower()) != null and g is MeshInstance3D:
			out.append({"kind": "merged", "src": anchor, "family": family(nm), "asset": nm, "aabb": box,
				"node": g, "at": box.get_center()})
		return
	out.append({"kind": "mesh", "src": anchor, "family": family(nm), "asset": nm, "aabb": box,
		"at": box.get_center(), "node": g, "solid": _has_body(g)})


## The horizontal direction a thing runs along: its own longer horizontal axis, turned as it is.
static func _axis_of(xf: Transform3D, local: AABB) -> Vector2:
	var v := xf.basis.x if local.size.x >= local.size.z else xf.basis.z
	var d := Vector2(v.x, v.z)
	return d.normalized() if d.length() > 0.0001 else Vector2.ZERO


## A placed scene's box in its own axes (its first drawn mesh's).
static func _local_box(n: Node3D) -> AABB:
	for m in n.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh != null:
			return mi.transform * mi.get_aabb()
	return AABB()


func _drawn_box(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var m: Node = stack.pop_back()
		if m is GeometryInstance3D and not (m is GPUParticles3D or m is CPUParticles3D or m is Label3D or m is Sprite3D) \
				and (m as GeometryInstance3D).is_visible_in_tree():
			var b := (m as GeometryInstance3D).global_transform * (m as GeometryInstance3D).get_aabb()
			if m is MultiMeshInstance3D and (m as MultiMeshInstance3D).multimesh != null:
				b = (m as MultiMeshInstance3D).global_transform * (m as MultiMeshInstance3D).multimesh.get_aabb()
			if b.size != Vector3.ZERO:
				box = b if first else box.merge(b)
				first = false
		stack.append_array(m.get_children())
	return box


func _has_body(n: Node) -> bool:
	if n == null:
		return false
	for c in n.get_children():
		if c is CollisionObject3D:
			return true
	return false


## An asset's family: its file name without the region it was made for and its variant letter.
static func family(asset: String) -> String:
	var f := asset.get_file().get_basename().to_lower()
	for p: String in REGION_PREFIXES:
		if f.begins_with(p):
			f = f.substr(p.length())
			break
	var re := RegEx.new()
	re.compile("(_x\\d+)?(_body)?$")
	f = re.sub(f, "")
	re.compile("(_lod\\d|_[a-z]|_\\d+)+$")
	f = re.sub(f, "")
	return f if f != "" else asset.get_file().get_basename()


# --- the checks --------------------------------------------------------------------------------

func _check(objects: Array[Dictionary]) -> void:
	var tops := _hash(objects)
	var buildings: Array[Dictionary] = []
	for o in objects:
		if str(o["kind"]) == "building":
			buildings.append(o)
	for o in objects:
		match str(o["kind"]):
			"light":
				_check_light(o, tops)
			"merged":
				_check_merged(o)
			_:
				_check_seat(o, tops)
				_check_lamp(o, tops)
				_check_road(o)
	_check_fences(objects)
	_check_overlaps(objects, tops, buildings)


func _check_seat(o: Dictionary, tops: Dictionary) -> void:
	var box: AABB = o["aabb"]
	var low := box.position.y
	var h := box.size.y
	var c := box.get_center()
	var g := _ground_under(box)
	var gmax: float = g["max"]
	var gmin: float = g["min"]
	var gc: float = g["centre"]
	var water := terrain.water_level_at(c.x, c.z) if terrain != null else TerrainProvider.NO_WATER
	var wet := water > gc + 0.2 and water > TerrainProvider.NO_WATER * 0.5
	if box.end.y < gmin - 0.02 and h > 0.05:
		_add(o, "buried", "all of it under the ground (top %.2f m below the lowest ground under it)" % (gmin - box.end.y))
		return
	if low > gmax + FLOAT_M:
		if wet and _floats_re.search(str(o["family"])) != null:
			return
		if _supported(o, low, tops):
			return
		_add(o, "floating", "%.2f m over the ground%s" % [low - gmax,
			" (over %.1f m of water)" % (water - gc) if wet else ""], low - gmax)
		return
	if str(o["kind"]) in ["prop", "building"] and h > 0.4 and gc - low > SUNK_SHARE * h:
		_add(o, "sunk", "%.0f%% of its %.1f m under the ground at its middle" % [100.0 * (gc - low) / h, h], gc - low)


## The ground under a box: its highest, lowest and middle heights at the middle and four points
## in from the corners of its footprint.
func _ground_under(box: AABB) -> Dictionary:
	var c := box.get_center()
	var hx := box.size.x * 0.35
	var hz := box.size.z * 0.35
	var pts := [Vector2(c.x, c.z)]
	if hx > 0.15 or hz > 0.15:
		pts.append_array([Vector2(c.x - hx, c.z - hz), Vector2(c.x + hx, c.z - hz), Vector2(c.x - hx, c.z + hz), Vector2(c.x + hx, c.z + hz)])
	var gmax := -INF
	var gmin := INF
	var gc := 0.0
	for i in pts.size():
		var p: Vector2 = pts[i]
		var y := terrain.get_height(p.x, p.y) if terrain != null else 0.0
		gmax = maxf(gmax, y)
		gmin = minf(gmin, y)
		if i == 0:
			gc = y
	return {"max": gmax, "min": gmin, "centre": gc}


## Held up by something solid: a collider under its middle within FLOAT_M, or another thing's top.
func _supported(o: Dictionary, low: float, tops: Dictionary) -> bool:
	var box: AABB = o["aabb"]
	var c := box.get_center()
	if space != null:
		var q := PhysicsRayQueryParameters3D.create(Vector3(c.x, low + 0.05, c.z), Vector3(c.x, low - FLOAT_M - 0.05, c.z))
		if not space.intersect_ray(q).is_empty():
			return true
	for other: Dictionary in _near(tops, Vector2(c.x, c.z)):
		if other == o:
			continue
		var b: AABB = other["aabb"]
		if b.end.y < low - FLOAT_M - 0.05 or b.position.y > low:
			continue
		if c.x >= b.position.x - 0.05 and c.x <= b.end.x + 0.05 and c.z >= b.position.z - 0.05 and c.z <= b.end.z + 0.05:
			return true
	return false


func _check_lamp(o: Dictionary, tops: Dictionary) -> void:
	var fam := str(o["family"])
	if _lamp_re.search(fam) == null or _standing_lamp_re.search(fam) != null:
		return
	var box: AABB = o["aabb"]
	var g := _ground_under(box)
	if box.position.y <= float(g["max"]) + LAMP_REACH_M:
		return
	if _anything_near(o, box.grow(LAMP_REACH_M), tops):
		return
	_add(o, "lamp_unhung", "nothing to hang from within %.1f m (%.1f m over the ground)" % [LAMP_REACH_M, box.position.y - float(g["max"])])


func _check_light(o: Dictionary, tops: Dictionary) -> void:
	var p: Vector3 = o["at"]
	var ground := terrain.get_height(p.x, p.z) if terrain != null else 0.0
	if p.y - ground <= LIGHT_REACH_M:
		return
	if _anything_near(o, AABB(p, Vector3.ZERO).grow(LIGHT_REACH_M), tops):
		return
	_add(o, "light_unhung", "a light %.1f m over the ground with nothing within %.1f m" % [p.y - ground, LIGHT_REACH_M])


func _anything_near(o: Dictionary, box: AABB, tops: Dictionary) -> bool:
	var c := box.get_center()
	for other: Dictionary in _near(tops, Vector2(c.x, c.z)):
		if other == o or str(other["kind"]) == "light":
			continue
		if (other["aabb"] as AABB).intersects(box):
			return true
	if space != null:
		var shape := BoxShape3D.new()
		shape.size = box.size
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = shape
		q.transform = Transform3D(Basis.IDENTITY, c)
		q.collision_mask = 0xFFFFFFFF
		if not space.intersect_shape(q, 1).is_empty():
			return true
	return false


func _check_road(o: Dictionary) -> void:
	var box: AABB = o["aabb"]
	if box.size.y < STANDING_M or bool(o.get("flora", false)):
		return
	var fam := str(o["family"])
	var src := str(o["src"])
	if _furniture_re.search(fam) != null or _furniture_re.search(str(o["asset"]).to_lower()) != null:
		return
	if src.begins_with("poi:bridge") or src.begins_with("poi:ford") or str(o["kind"]) == "building":
		return
	# the trunk or foot, not the crown: where it meets the ground
	var foot: Vector3 = o.get("at", box.get_center())
	var p := Vector2(foot.x, foot.z) if str(o["kind"]) == "instance" else Vector2(box.get_center().x, box.get_center().z)
	var hit := _road_at(p, 0.25)
	if hit != "":
		_add(o, "on_road", "stands in the carriageway of %s" % hit)


## The road whose carriageway `p` is in (more than `inset` inside its edge), or "".
func _road_at(p: Vector2, inset: float) -> String:
	for i: int in _seg_hash.get(Vector2i(floori(p.x / 64.0), floori(p.y / 64.0)), []):
		var s: Array = _segments[i]
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		if p.distance_to(a + ab * t) < float(s[2]) - inset:
			return str(s[3]).get_slice("/", 1)
	return ""


## Fence and rail runs: a gap in the middle of a run, in line with it on both sides, with no gate
## and no road through it.
func _check_fences(objects: Array[Dictionary]) -> void:
	var pieces: Array[Dictionary] = []
	for o in objects:
		if str(o["kind"]) in ["instance", "prop", "mesh"] and _fence_re.search(str(o["family"])) != null:
			pieces.append(o)
	var h := _hash(pieces)
	# a lone length of fence stood in a field, joined to nothing: "fences randomly placed"
	for a in pieces:
		if str(a["kind"]) != "prop":
			continue
		var ab: AABB = a["aabb"]
		var c := Vector2(ab.get_center().x, ab.get_center().z)
		var joined := false
		for b: Dictionary in _near(h, c):
			if b != a and _box_gap(ab, b["aabb"]) < 1.0:
				joined = true
				break
		if not joined and maxf(ab.size.x, ab.size.z) < 6.0:
			_add(a, "fence_lone", "a %.1f m length of %s joined to no other" % [maxf(ab.size.x, ab.size.z), str(a["family"])])
	if pieces.size() < 3:
		return
	var reported := {}
	for i in pieces.size():
		var a := pieces[i]
		var ab: AABB = a["aabb"]
		var ac := Vector2(ab.get_center().x, ab.get_center().z)
		var a_axis: Vector2 = a.get("axis", _long_axis(ab))
		var neighbours := 0
		var gaps: Array[Dictionary] = []
		for b: Dictionary in _near(h, ac):
			if b == a or str(b["family"]) != str(a["family"]) or str(b["src"]) != str(a["src"]):
				continue
			var gap := _box_gap(ab, b["aabb"])
			if gap < 0.6:
				neighbours += 1
			elif gap >= FENCE_GAP_M and gap <= FENCE_GAP_MAX_M:
				var bc := Vector2((b["aabb"] as AABB).get_center().x, (b["aabb"] as AABB).get_center().z)
				var d := (bc - ac).normalized()
				var b_axis: Vector2 = b.get("axis", _long_axis(b["aabb"]))
				if a_axis != Vector2.ZERO and absf(d.dot(a_axis)) > 0.95 and absf(b_axis.dot(a_axis)) > 0.95:
					gaps.append({"other": b, "gap": gap, "mid": (ac + bc) * 0.5})
		if neighbours == 0:
			continue          # the end of a run, not its middle
		for g in gaps:
			var mid: Vector2 = g["mid"]
			var key := str(mid.snapped(Vector2(0.5, 0.5)))
			if reported.has(key):
				continue
			reported[key] = true
			if _road_at(mid, -0.5) != "" or _gate_near(objects, mid):
				continue
			_add(a, "fence_gap", "a %.1f m gap in the middle of the run" % float(g["gap"]), float(g["gap"]))


func _gate_near(objects: Array[Dictionary], p: Vector2) -> bool:
	for o in objects:
		var f := str(o["family"])
		if not (f.contains("gate") or f.contains("stile") or f.contains("gap")):
			continue
		var c := (o["aabb"] as AABB).get_center()
		if Vector2(c.x, c.z).distance_to(p) < 2.0:
			return true
	return false


static func _long_axis(box: AABB) -> Vector2:
	if box.size.x > box.size.z * 1.5:
		return Vector2(1, 0)
	if box.size.z > box.size.x * 1.5:
		return Vector2(0, 1)
	return Vector2.ZERO


static func _box_gap(a: AABB, b: AABB) -> float:
	var dx := maxf(0.0, maxf(a.position.x - b.end.x, b.position.x - a.end.x))
	var dz := maxf(0.0, maxf(a.position.z - b.end.z, b.position.z - a.end.z))
	return Vector2(dx, dz).length()


## Two solid props sharing much of the smaller's box, or a tree standing in a building.
func _check_overlaps(objects: Array[Dictionary], tops: Dictionary, buildings: Array[Dictionary]) -> void:
	var seen := {}
	var index := {}
	for i in objects.size():
		index[objects[i]] = i
	for o in objects:
		var k := str(o["kind"])
		var box: AABB = o["aabb"]
		if k == "instance" and str(o["src"]) == "scatter" and str(o["family"]).contains("tree"):
			var foot: Vector3 = o["at"]
			for b in buildings:
				if (b["aabb"] as AABB).grow(-0.5).has_point(Vector3(foot.x, (b["aabb"] as AABB).get_center().y, foot.z)):
					_add(o, "overlap", "a tree's trunk inside %s" % str(b["family"]))
					break
			continue
		if k != "prop" or box.size.y < STANDING_M or not bool(o.get("solid", false)) \
				or _shelter_re.search(str(o["family"])) != null:
			continue
		var c := box.get_center()
		for other: Dictionary in _near(tops, Vector2(c.x, c.z)):
			if other == o or str(other["kind"]) not in ["prop", "building"] or not bool(other.get("solid", false)) \
					or _shelter_re.search(str(other["family"])) != null:
				continue
			var ob: AABB = other["aabb"]
			if not box.intersects(ob):
				continue
			var inter := box.intersection(ob)
			var share := inter.get_volume() / maxf(minf(box.get_volume(), ob.get_volume()), 0.0001)
			if share <= OVERLAP_SHARE:
				continue
			var ia: int = index[o]
			var ib: int = index.get(other, -1)
			var pair := "%d-%d" % [mini(ia, ib), maxi(ia, ib)]
			if seen.has(pair):
				continue
			seen[pair] = true
			_add(o, "overlap", "%.0f%% of it shares its box with %s (%s)" % [100.0 * share, str(other["family"]), str(other["src"])], share)


## Merged meshes (a cell's gates, a town's fences and walls): in every COLUMN_M column the mesh
## has vertices in, the lowest must meet the ground or something solid.
func _check_merged(o: Dictionary) -> void:
	var mi := o["node"] as MeshInstance3D
	if mi == null or mi.mesh == null:
		return
	var xf := mi.global_transform
	var lowest := {}      # Vector2i -> Vector3 (the lowest vertex, world)
	for s in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(s)
		if arrays.is_empty():
			continue
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for v in verts:
			var w := xf * v
			var key := Vector2i(floori(w.x / COLUMN_M), floori(w.z / COLUMN_M))
			if not lowest.has(key) or w.y < (lowest[key] as Vector3).y:
				lowest[key] = w
	for key: Vector2i in lowest:
		var w: Vector3 = lowest[key]
		var g := terrain.get_height(w.x, w.z) if terrain != null else 0.0
		if w.y <= g + FLOAT_M:
			continue
		if space != null:
			var q := PhysicsRayQueryParameters3D.create(Vector3(w.x, w.y + 0.05, w.z), Vector3(w.x, w.y - FLOAT_M - 0.05, w.z))
			if not space.intersect_ray(q).is_empty():
				continue
		var one := o.duplicate()
		one["aabb"] = AABB(w, Vector3.ZERO)
		_add(one, "floating", "a %.0f m stretch of merged %s %.2f m over the ground at its lowest" % [COLUMN_M, str(o["asset"]), w.y - g], w.y - g)


# --- bookkeeping -------------------------------------------------------------------------------

func _add(o: Dictionary, check: String, detail: String, amount := 0.0) -> void:
	var box: AABB = o["aabb"]
	var at: Vector3 = o.get("at", box.get_center())
	var src := str(o["src"])
	var row := {"check": check, "src": src, "family": str(o["family"]), "asset": str(o["asset"]).get_file(),
		"x": snappedf(at.x, 0.1), "y": snappedf(box.position.y, 0.01), "z": snappedf(at.z, 0.1),
		"amount": snappedf(amount, 0.01), "detail": detail,
		"region": World.region_id_at(Vector3(at.x, 0.0, at.z)).get_slice("/", 1)}
	findings.append(row)
	var key := "%s | %s" % [src, str(o["family"])]
	if not counts.has(key):
		counts[key] = {}
	counts[key][check] = int(counts[key].get(check, 0)) + 1


func _hash(objects: Array) -> Dictionary:
	var h := {}
	for o: Dictionary in objects:
		var b: AABB = o["aabb"]
		var x0 := floori(b.position.x / HASH_M)
		var x1 := floori(b.end.x / HASH_M)
		var z0 := floori(b.position.z / HASH_M)
		var z1 := floori(b.end.z / HASH_M)
		if (x1 - x0) * (z1 - z0) > 400:
			continue          # something the size of a town is not what props stand on
		for x in range(x0, x1 + 1):
			for z in range(z0, z1 + 1):
				var k := Vector2i(x, z)
				if not h.has(k):
					h[k] = []
				(h[k] as Array).append(o)
	return h


func _near(h: Dictionary, p: Vector2) -> Array:
	var out: Array = []
	var cx := floori(p.x / HASH_M)
	var cz := floori(p.y / HASH_M)
	for x in range(cx - 1, cx + 2):
		for z in range(cz - 1, cz + 2):
			out.append_array(h.get(Vector2i(x, z), []))
	return out


func _load_roads() -> void:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://world/generated/roads.json"))
	for r: Dictionary in (raw if raw is Array else []):
		var pts: Array = r.get("points", [])
		var half := float(r.get("width_m", 3.5)) * 0.5
		for i in range(pts.size() - 1):
			var a := Vector2(float(pts[i][0]), float(pts[i][1]))
			var b := Vector2(float(pts[i + 1][0]), float(pts[i + 1][1]))
			_segments.append([a, b, half, str(r.get("id", ""))])
			var idx := _segments.size() - 1
			var lo := Vector2(minf(a.x, b.x) - half, minf(a.y, b.y) - half)
			var hi := Vector2(maxf(a.x, b.x) + half, maxf(a.y, b.y) + half)
			for x in range(floori(lo.x / 64.0), floori(hi.x / 64.0) + 1):
				for z in range(floori(lo.y / 64.0), floori(hi.y / 64.0) + 1):
					var k := Vector2i(x, z)
					if not _seg_hash.has(k):
						_seg_hash[k] = []
					(_seg_hash[k] as Array).append(idx)


## The counts as rows, most first: [{src, family, check, n}].
func ranked() -> Array:
	var out: Array = []
	for key: String in counts:
		for check: String in counts[key]:
			out.append({"src": key.get_slice(" | ", 0), "family": key.get_slice(" | ", 1), "check": check, "n": counts[key][check]})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["n"]) > int(b["n"]))
	return out
