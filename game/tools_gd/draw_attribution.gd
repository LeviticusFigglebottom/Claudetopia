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


## Hides each owner in turn and reads the frame counter back. Returns
## {"total": n, "shadow_passes": n, "by_owner": {name: draws}, "residue": n}, where the residue
## is what nothing here can hide: the sky, the terrain if it ignores `visible`, the UI.
static func measure(world: Node) -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	var result := {"total": 0, "shadow_passes": 0, "by_owner": {}, "owner_nodes": {}, "residue": 0}
	if tree == null or world == null:
		return result
	var total := await _settled_draws(tree)
	result["total"] = total
	var owners := _owners(world)
	var accounted := 0
	for name in owners:
		var nodes: Array = owners[name]
		if nodes.is_empty():
			continue
		var was: Array[bool] = []
		for n in nodes:
			was.append((n as Node3D).visible)
			(n as Node3D).visible = false
		var without := await _settled_draws(tree)
		for i in nodes.size():
			(nodes[i] as Node3D).visible = was[i]
		var cost := total - without
		result["by_owner"][name] = cost
		result["owner_nodes"][name] = nodes.size()
		accounted += cost
	# the sun's shadow passes, by turning them off
	var sun := _sun(world)
	if sun != null and sun.shadow_enabled:
		sun.shadow_enabled = false
		var lit := await _settled_draws(tree)
		sun.shadow_enabled = true
		result["shadow_passes"] = total - lit
	result["residue"] = total - accounted
	await _settled_draws(tree)
	return result


static func measure_table(m: Dictionary) -> String:
	var out: Array[String] = ["measured by hiding each owner (includes its shadow passes):"]
	var by: Dictionary = m.get("by_owner", {})
	var counts: Dictionary = m.get("owner_nodes", {})
	var names: Array = by.keys()
	names.sort_custom(func(a: String, b: String) -> bool: return int(by[a]) > int(by[b]))
	for name in names:
		out.append("  %-56s %6d   (%d nodes hidden)" % [name, int(by[name]), int(counts.get(name, 0))])
	out.append("  %-56s %6d" % ["residue (sky, terrain, water, UI, anything not listed)", int(m.get("residue", 0))])
	out.append("  %-56s %6d" % ["total draw calls", int(m.get("total", 0))])
	out.append("  %-56s %6d" % ["of which shadow passes (sun shadows off)", int(m.get("shadow_passes", 0))])
	return "\n".join(out)


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
	var scatter: Array = []
	var scenes: Array = []
	var streamer: Node = world.get("streamer") if world.get("streamer") != null else null
	if streamer != null:
		for cell in streamer.get_children():
			for child in cell.get_children():
				if child is MultiMeshInstance3D:
					scatter.append(child)
				elif child is Node3D:
					scenes.append(child)
	out["WorldStreamer scatter (MultiMesh)"] = scatter
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


static func _settled_draws(tree: SceneTree) -> int:
	# The counter reports the last frame drawn; two frames so the change is in it.
	await tree.process_frame
	await RenderingServer.frame_post_draw
	await tree.process_frame
	await RenderingServer.frame_post_draw
	return int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))


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
