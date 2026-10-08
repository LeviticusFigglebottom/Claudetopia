class_name ShadowTrim
extends RefCounted
## Small things at a place cast no sun shadow.
##
## A place's dressing -- stools, crates, cups, ferns, tools, the bits of an encounter's camp -- is
## hundreds of small meshes, each drawn again into every one of the sun's cascades it falls in. The
## places were 0.49-0.64 M primitives of a Greatwood frame with their shadows (attribution, w4096j),
## and a shadow under a cup is a few pixels no one sees. So a mesh raised inside a streamed cell
## whose longest side is under MAX_M does not cast; walls, buildings, landmarks and anything a body
## stands behind keep their shadows, and so does everything that is or carries a character.
##
## The world watches the nodes entering its tree (World._ready) and hands each geometry node here
## a frame later, when its mesh and transform are set: a place raised a step at a time, or whose
## masonry is made on a worker thread, is caught whenever its pieces arrive.
## `-- --no-shadow-trim` leaves every shadow on, for an A/B.

const MAX_M := 1.0

static var enabled := not OS.get_cmdline_user_args().has("--no-shadow-trim")
## How many it has switched off, for the measurement.
static var trimmed := 0


## The deferred form of consider: by instance id, since either may be freed before it runs.
static func consider_ids(node_id: int, streamer_id: int) -> void:
	var node := instance_from_id(node_id) as Node
	var streamer := instance_from_id(streamer_id) as Node
	if node == null or streamer == null:
		return
	consider(node, streamer)


## Weighs a geometry node that entered the tree under `streamer`.
static func consider(node: Node, streamer: Node) -> void:
	if not enabled or streamer == null or not is_instance_valid(node) or not node.is_inside_tree():
		return
	var gi := node as GeometryInstance3D
	if gi == null or gi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
		return
	# a scatter MultiMesh is the streamer's own (and has a shadow LOD of its own)
	if gi.has_meta("asset_path"):
		return
	var inside_cell := false
	var p := gi.get_parent()
	while p != null:
		if p is CharacterBody3D or p is HumanoidModel:
			return
		if p.get_parent() == streamer:
			inside_cell = true
			break
		p = p.get_parent()
	if not inside_cell:
		return
	if longest_side(gi) < MAX_M:
		gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		trimmed += 1


## The longest side of what `gi` draws, in metres in the world. A MultiMesh is taken whole, all its
## instances together: a wall laid as a MultiMesh of small stones is a wall, and keeps its shadow.
static func longest_side(gi: GeometryInstance3D) -> float:
	if gi is MeshInstance3D and (gi as MeshInstance3D).mesh == null:
		return INF
	if gi is MultiMeshInstance3D:
		var mm := (gi as MultiMeshInstance3D).multimesh
		if mm == null or mm.mesh == null or mm.instance_count == 0:
			return INF
	var size := gi.get_aabb().size * gi.global_transform.basis.get_scale().abs()
	return maxf(size.x, maxf(size.y, size.z))
