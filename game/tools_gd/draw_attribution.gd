class_name DrawAttribution
extends RefCounted
## What a frame is made of, and who put it there.
##
## `Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME` is one number. The worst frame in the game, a
## village street, was 2438 of them, and nothing could say which script they belonged to. This
## answers that two ways:
##
## * `census()` walks the tree for every geometry instance the camera can see and counts its
##   surfaces, grouped by the script that owns it (the nearest scripted ancestor) and the
##   node's name prefix, so the count reads as "Building/Walls 34, Settlement/Roofs 1,
##   HumanoidModel/torso 22 ..." rather than as a total. It is the colour pass only: it does
##   not guess how many shadow cascades a thing lands in.
## * `measure()` is the truth: it hides each owner in turn, lets a frame draw, and reads the
##   counter back. That includes every shadow pass, which is where the multiplier hides -- a
##   sunlit village is drawn once for the eye and up to four more times for the sun.
##
## Both are reached from the capture runner (`--attribute`) and the debug console (`draws`).

## How far a directional shadow reaches is set by the atmosphere; past it nothing casts.
const SHADOW_GROUPS := {
	"settlement": "Settlement (fabric, props, boards, stations)",
	"building": "Building (the houses you enter)",
	"door": "Door",
	"npc": "Npc (villagers)",
	"player": "Player",
}


## One row per (owner, prefix): instances, colour-pass draws, shadow-casting draws.
static func census(camera: Camera3D, root: Node) -> Dictionary:
	var rows: Dictionary = {}
	if camera == null or root == null:
		return rows
	var planes: Array[Plane] = camera.get_frustum()
	var eye := camera.global_position
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n is GeometryInstance3D):
			continue
		var gi := n as GeometryInstance3D
		if not gi.is_visible_in_tree():
			continue
		var surfaces := _surfaces_of(gi)
		if surfaces == 0:
			continue
		var box: AABB = gi.global_transform * gi.get_aabb()
		if not _in_frustum(box, planes):
			continue
		if gi.visibility_range_end > 0.0:
			var reach := gi.visibility_range_end + gi.visibility_range_end_margin
			if box.get_center().distance_to(eye) > reach and not box.has_point(eye):
				continue
		var key := "%s/%s" % [owner_of(gi), prefix_of(gi.name)]
		if not rows.has(key):
			rows[key] = {"owner": owner_of(gi), "prefix": prefix_of(gi.name),
					"instances": 0, "draws": 0, "shadow_draws": 0, "multimesh_instances": 0}
		var row: Dictionary = rows[key]
		row["instances"] += 1
		row["draws"] += surfaces
		if gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			row["shadow_draws"] += surfaces
		if gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh != null:
			row["multimesh_instances"] += (gi as MultiMeshInstance3D).multimesh.visible_instance_count \
					if (gi as MultiMeshInstance3D).multimesh.visible_instance_count >= 0 \
					else (gi as MultiMeshInstance3D).multimesh.instance_count
	return rows


## The census as a table, worst first, with the totals on the last line.
static func census_table(rows: Dictionary) -> String:
	var list: Array = rows.values()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["draws"]) > int(b["draws"]))
	var out: Array[String] = ["%-52s %6s %6s %7s" % ["owner/prefix", "nodes", "draws", "shadow"]]
	var draws := 0
	var shadow := 0
	var nodes := 0
	for r in list:
		var row: Dictionary = r
		var name := "%s/%s" % [row["owner"], row["prefix"]]
		if int(row["multimesh_instances"]) > 0:
			name += " (x%d)" % int(row["multimesh_instances"])
		out.append("%-52s %6d %6d %7d" % [name.left(52), int(row["instances"]), int(row["draws"]),
				int(row["shadow_draws"])])
		draws += int(row["draws"])
		shadow += int(row["shadow_draws"])
		nodes += int(row["instances"])
	out.append("%-52s %6d %6d %7d" % ["total (colour pass; shadow = casters, not passes)", nodes, draws, shadow])
	return "\n".join(out)


## Hides each owner in turn and reads the frame counters back. Returns
## {"total": n, "shadow_passes": n, "by_owner": {name: draws}, "residue": n} for draw calls and
## the same four for primitives ("total_primitives", "shadow_primitives",
## "by_owner_primitives", "residue_primitives"), where the residue is what nothing here can
## hide: the sky, the terrain if it ignores `visible`, the UI.
##
## Primitives are read as well as draw calls because it is the primitive budget the country
## misses, and a primitive total names nobody either.
static func measure(world: Node) -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	var result := {"total": 0, "shadow_passes": 0, "by_owner": {}, "owner_nodes": {}, "residue": 0,
			"total_primitives": 0, "shadow_primitives": 0, "by_owner_primitives": {},
			"residue_primitives": 0}
	if tree == null or world == null:
		return result
	var total := await _settled(tree)
	result["total"] = total.x
	result["total_primitives"] = total.y
	var owners := _owners(world)
	var accounted := Vector2i.ZERO
	for name in owners:
		var nodes: Array = owners[name]
		if nodes.is_empty():
			continue
		var was: Array[bool] = []
		for n in nodes:
			was.append((n as Node3D).visible)
			(n as Node3D).visible = false
		var without := await _settled(tree)
		for i in nodes.size():
			(nodes[i] as Node3D).visible = was[i]
		var cost := total - without
		result["by_owner"][name] = cost.x
		result["by_owner_primitives"][name] = cost.y
		result["owner_nodes"][name] = nodes.size()
		accounted += cost
	# each place in view, piece by piece and then its sun shadow as a whole: "the scenes" is one
	# owner, and a castle in it is masonry, timber, flora and its shadow, which is the question.
	# These overlap the scenes' own row, so they are not added to what is accounted for.
	var parts: Dictionary = {}
	var part_prims: Dictionary = {}
	# first each of the scenes standing in the cells that draws much (a place, a landmark, a camp)
	for scene_v in owners.get("WorldStreamer scenes (landmarks, encounters)", []):
		var scene := scene_v as Node3D
		if scene == null or not scene.is_visible_in_tree():
			continue
		var tris := 0
		for g in scene.find_children("*", "GeometryInstance3D", true, false):
			tris += _triangles_of(g as GeometryInstance3D)
		if tris < SCENE_MIN_TRIANGLES:
			continue
		scene.visible = false
		var without_scene := await _settled(tree)
		scene.visible = true
		var scost := total - without_scene
		parts["scene %s" % scene.name] = scost.x
		part_prims["scene %s" % scene.name] = scost.y
	for poi: Node3D in _places(world):
		var geo: Array[GeometryInstance3D] = []
		var by_prefix: Dictionary = {}
		var stack: Array[Node] = [poi]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			for c in n.get_children():
				stack.append(c)
			if n is GeometryInstance3D and (n as GeometryInstance3D).is_visible_in_tree():
				geo.append(n)
				var key := "%s: %s" % [poi.name, prefix_of(n.name)]
				if not by_prefix.has(key):
					by_prefix[key] = []
				(by_prefix[key] as Array).append(n)
		if geo.is_empty():
			continue
		var whole := Vector2i.ZERO
		for key in by_prefix:
			var nodes: Array = by_prefix[key]
			# weighed only where there is something to weigh: a frame a piece is slow under software
			# rendering, and a mug is a few hundred triangles
			var tris := 0
			for n in nodes:
				tris += _triangles_of(n as GeometryInstance3D)
			if tris < PART_MIN_TRIANGLES:
				continue
			for n in nodes:
				(n as Node3D).visible = false
			var without := await _settled(tree)
			for n in nodes:
				(n as Node3D).visible = true
			var cost := total - without
			if cost.y != 0 or cost.x != 0:
				parts[key] = cost.x
				part_prims[key] = cost.y
		var casts: Array[int] = []
		for g in geo:
			casts.append(g.cast_shadow)
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var unshadowed := await _settled(tree)
		for i in geo.size():
			geo[i].cast_shadow = casts[i] as GeometryInstance3D.ShadowCastingSetting
		whole = total - unshadowed
		parts["%s: (its sun shadow, every piece)" % poi.name] = whole.x
		part_prims["%s: (its sun shadow, every piece)" % poi.name] = whole.y
	result["place_parts"] = parts
	result["place_parts_primitives"] = part_prims
	# the sun's shadow passes, by turning them off
	var sun := _sun(world)
	if sun != null and sun.shadow_enabled:
		sun.shadow_enabled = false
		var lit := await _settled(tree)
		sun.shadow_enabled = true
		result["shadow_passes"] = total.x - lit.x
		result["shadow_primitives"] = total.y - lit.y
	result["residue"] = total.x - accounted.x
	result["residue_primitives"] = total.y - accounted.y
	await _settled(tree)
	return result


static func measure_table(m: Dictionary) -> String:
	var out: Array[String] = ["measured by hiding each owner (includes its shadow passes):",
			"  %-56s %6s %11s" % ["", "draws", "primitives"]]
	var by: Dictionary = m.get("by_owner", {})
	var prims: Dictionary = m.get("by_owner_primitives", {})
	var counts: Dictionary = m.get("owner_nodes", {})
	var names: Array = by.keys()
	names.sort_custom(func(a: String, b: String) -> bool:
			return int(prims.get(a, 0)) > int(prims.get(b, 0)))
	for name in names:
		out.append("  %-56s %6d %11d   (%d nodes hidden)" % [name, int(by[name]),
				int(prims.get(name, 0)), int(counts.get(name, 0))])
	out.append("  %-56s %6d %11d" % ["residue (sky, terrain, water, UI, anything not listed)",
			int(m.get("residue", 0)), int(m.get("residue_primitives", 0))])
	out.append("  %-56s %6d %11d" % ["total", int(m.get("total", 0)), int(m.get("total_primitives", 0))])
	out.append("  %-56s %6d %11d" % ["of which shadow passes (sun shadows off)",
			int(m.get("shadow_passes", 0)), int(m.get("shadow_primitives", 0))])
	var parts: Dictionary = m.get("place_parts", {})
	if not parts.is_empty():
		var pp: Dictionary = m.get("place_parts_primitives", {})
		out.append("the places in the scenes, a piece at a time (with its shadow) and their shadow whole:")
		var keys: Array = parts.keys()
		keys.sort_custom(func(a: String, b: String) -> bool: return int(pp.get(a, 0)) > int(pp.get(b, 0)))
		for key in keys:
			out.append("  %-56s %6d %11d" % [str(key).left(56), int(parts[key]), int(pp.get(key, 0))])
	return "\n".join(out)


## The points of interest standing in the streamed cells (PoiDressing names each `Poi_<id>`).
static func _places(world: Node) -> Array[Node3D]:
	var out: Array[Node3D] = []
	var streamer: Node = world.get("streamer") if world.get("streamer") != null else null
	if streamer == null:
		return out
	var cam := (Engine.get_main_loop() as SceneTree).root.get_viewport().get_camera_3d()
	for n in streamer.find_children("Poi_*", "Node3D", true, false):
		# the ones near enough to be the shot's subject: each costs a frame a piece to weigh
		if cam == null or (n as Node3D).global_position.distance_to(cam.global_position) < PLACE_REACH_M:
			out.append(n as Node3D)
	return out


## How near the camera a place is weighed piece by piece (`measure`), and how many triangles a
## piece needs to be weighed on its own.
const PLACE_REACH_M := 200.0
const PART_MIN_TRIANGLES := 3000
const SCENE_MIN_TRIANGLES := 20000


## The triangles a geometry instance draws once (a MultiMesh's for every instance).
static func _triangles_of(gi: GeometryInstance3D) -> int:
	var mesh: Mesh = null
	var count := 1
	if gi is MeshInstance3D:
		mesh = (gi as MeshInstance3D).mesh
	elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh != null:
		var mm := (gi as MultiMeshInstance3D).multimesh
		mesh = mm.mesh
		count = mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
	if mesh == null:
		return 0
	var tris := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var idx: Variant = arrays[Mesh.ARRAY_INDEX]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		tris += int(((idx as PackedInt32Array).size() if idx != null else verts.size()) / 3.0)
	return tris * count


# --- what belongs to whom -------------------------------------------------------------------------

## The nodes to hide for each owner. Groups are used where the game already keeps them; the
## streamer's cells are split into scatter and the authored scenes standing in them.
static func _owners(world: Node) -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	var out: Dictionary = {}
	for group in SHADOW_GROUPS:
		var nodes: Array = []
		for n in tree.get_nodes_in_group(group):
			if n is Node3D and n.is_inside_tree():
				nodes.append(n)
		out[str(SHADOW_GROUPS[group])] = nodes
	# The scatter by kind and by ring, because "the scatter" is most of a country frame and the
	# question is always which of it: trees near or far, the ground cover, the hedges.
	var scenes: Array = []
	var streamer: Node = world.get("streamer") if world.get("streamer") != null else null
	if streamer != null:
		for cell in streamer.get_children():
			var ring := "far ring" if int(cell.get_meta("ring", 0)) > 1 else "near ring"
			for child in cell.get_children():
				if child is GeometryInstance3D and child.has_meta("asset_path"):
					var key := "WorldStreamer scatter: %s, %s" % [
							scatter_kind(str(child.get_meta("asset_path"))), ring]
					if not out.has(key):
						out[key] = []
					(out[key] as Array).append(child)
				elif child is Node3D:
					scenes.append(child)
	out["WorldStreamer scenes (landmarks, encounters)"] = scenes
	var terrain: Variant = world.get("terrain_node")
	out["Terrain3D"] = [terrain] if terrain is Node3D else []
	var water: Variant = world.get("water")
	out["Water"] = [water] if water is Node3D else []
	return out


static func _sun(world: Node) -> DirectionalLight3D:
	var atmos: Variant = world.get("atmosphere")
	if atmos is Node:
		var sun: Variant = (atmos as Node).get("sun")
		if sun is DirectionalLight3D:
			return sun
	return null


## Draw calls in x, primitives in y, for the last frame drawn.
static func _settled(tree: SceneTree) -> Vector2i:
	# The counter reports the last frame drawn; two frames so the change is in it.
	await tree.process_frame
	await RenderingServer.frame_post_draw
	await tree.process_frame
	await RenderingServer.frame_post_draw
	return Vector2i(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))


## What the streamer calls a scatter asset, with the hedges named on their own: they file
## under props for their view range, and they are a tenth of a million pieces in the Vale.
static func scatter_kind(asset_path: String) -> String:
	if asset_path.contains("hedge"):
		return "hedge"
	if asset_path.contains("/trees/"):
		return "tree"
	if asset_path.contains("/rocks/"):
		return "rock"
	if asset_path.contains("/props/"):
		return "prop"
	return "flora"


# --- naming ------------------------------------------------------------------------------------

## The nearest scripted ancestor's class, which is who raised the thing.
static func owner_of(node: Node) -> String:
	var n: Node = node
	while n != null:
		var s: Variant = n.get_script()
		if s is Script:
			var script := s as Script
			var global := script.get_global_name()
			if global != "":
				return global
			return script.resource_path.get_file().get_basename()
		n = n.get_parent()
	return "(no script)"


## "Walls_hearth" -> "Walls", "Slope-1" -> "Slope", "torso_Tunic" -> "torso",
## "hearthvale_oak_a" -> "hearthvale_oak": the name without the part that numbers it.
static func prefix_of(name: String) -> String:
	var s := name
	while s.length() > 1 and (s[s.length() - 1].is_valid_int() or s.ends_with("-")):
		s = s.left(s.length() - 1)
	var cut := s.rfind("_")
	if cut > 0:
		s = s.left(cut)
	return s


static func _surfaces_of(gi: GeometryInstance3D) -> int:
	if gi is MeshInstance3D:
		var mesh := (gi as MeshInstance3D).mesh
		return mesh.get_surface_count() if mesh != null else 0
	if gi is MultiMeshInstance3D:
		var mm := (gi as MultiMeshInstance3D).multimesh
		if mm == null or mm.mesh == null or mm.instance_count == 0:
			return 0
		return mm.mesh.get_surface_count()
	return 1


## `AABB.intersects_convex_shape` is not scripted, so this is the same test: a box is outside
## when its most-inward corner is on the far side of any plane.
static func _in_frustum(box: AABB, planes: Array[Plane]) -> bool:
	var half := box.size * 0.5
	var centre := box.position + half
	for p in planes:
		var corner := centre + Vector3(
				-half.x if p.normal.x > 0.0 else half.x,
				-half.y if p.normal.y > 0.0 else half.y,
				-half.z if p.normal.z > 0.0 else half.z)
		if p.is_point_over(corner):
			return false
	return true
