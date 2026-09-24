class_name Wayside
extends RefCounted
## What the streamer does with the furniture of the roads and the field boundaries before it
## draws a cell: the few things the world build lays down that are not scatter but are built.
##
## * A signpost is a `Fingerpost`: arms down the roads that leave, each with its place's name.
##   The forge's signpost with arms at random angles and nothing on them is not drawn at all.
## * A gate post has a gate. The build puts one post at the shoulder of a gap in a hedge; the gate
##   is hung from it across the gap, along the hedge's own line, with a post to shut against --
##   a five-barred field gate, most of them shut and some left open into the field.
## * Skerrow's drystone walls are walls. The build laid each boundary with the region's
##   "drystone_wall" assets, and its asset lookup matched the wall *end* by prefix too, so a
##   third of every run was a 0.9 m end piece standing in a 2.4 m slot: a wall of stubs with
##   daylight between them. It also scaled each piece at random in all three axes, so the run
##   stepped up and down every few metres. An end piece with wall on both sides of it is drawn as
##   wall; every piece is stretched along its line to meet the next (closing the gaps the texel
##   spacing leaves) and keeps a steady height.
##
## `prepare` takes a cell's instance table and returns the one to draw, having stood up whatever
## it builds under the cell node, so it all streams and unloads with the cell.

const SIGNPOST := "signpost"
const GATE_POST := "gate_post"
const WALL := "drystone_wall_"
const WALL_END := "drystone_wall_end"
const WALL_MODULE_M := 2.5
const GATE_LEN := 3.2
const GATE_H := 1.2
## How far a gate post looks for the hedge it stands in.
const LINE_REACH_M := 6.0
const GATE_RANGE_M := 220.0
const GATE_TIMBER := Color(0.55, 0.47, 0.36)


## The cell's instances to draw as scatter, after the wayside has built what it builds under
## `cell` (only in the near ring: `near`).
static func prepare(instances: Dictionary, cell: Node3D, near: bool) -> Dictionary:
	var out: Dictionary = {}
	var lines: Array = []          # rows of anything a gate post may stand in: hedges, rails
	var walls: Dictionary = {}     # path -> rows of drystone wall
	var ends: Dictionary = {}      # path -> rows of drystone wall end
	for path_v in instances:
		var path := str(path_v)
		var rows: Array = instances[path_v]
		if path.contains(SIGNPOST):
			if near:
				for row in rows:
					_fingerpost(cell, row)
			continue
		if path.contains("hedge_segment") or path.contains("fence_post_rail"):
			lines.append_array(rows)
		if path.contains(WALL_END):
			ends[path] = rows
			continue
		if path.contains(WALL):
			walls[path] = rows
			continue
		out[path] = rows
	if not walls.is_empty() or not ends.is_empty():
		_walls(walls, ends, out)
	if near:
		for path in instances:
			if str(path).contains(GATE_POST):
				_gates(cell, instances[path], lines)
	return out


# --- fingerposts ------------------------------------------------------------------------------------

static func _fingerpost(cell: Node3D, row: Array) -> void:
	var post := Fingerpost.new()
	post.name = "Fingerpost"
	post.position = Vector3(float(row[0]), float(row[1]), float(row[2])) - cell.position
	cell.add_child(post)


# --- gates ------------------------------------------------------------------------------------------

## Hangs a gate on every post that stands at the end of a line of hedge or rail: along the line,
## into the gap. All of a cell's gates are one mesh.
static func _gates(cell: Node3D, posts: Array, lines: Array) -> void:
	var fabric := FabricMesh.new()
	var hung := 0
	for row_v in posts:
		var row: Array = row_v
		var at := Vector2(float(row[0]), float(row[2]))
		var along := gate_line(at, lines)
		if along == Vector2.ZERO:
			continue
		var ground := float(row[1]) - cell.position.y
		var base := Vector3(at.x - cell.position.x, ground, at.y - cell.position.z)
		var h := hash(Vector2i(int(at.x * 10.0), int(at.y * 10.0)))
		var open := (h % 10) < 3
		hang_gate(fabric, base, along, open, float((h >> 4) % 40) / 40.0)
		hung += 1
	if hung == 0:
		return
	var mesh := fabric.commit(cell, "joinery", FabricMesh.joinery_material(), "Gates")
	if mesh != null:
		FabricMesh.near_only(mesh, GATE_RANGE_M, true)


## Which way a gate hung from the post at `at` runs: along the line the post stands at the end of,
## toward the side with no line (the gap). ZERO when the post stands in no line at all.
static func gate_line(at: Vector2, lines: Array) -> Vector2:
	var nearest: Array = []
	for row_v in lines:
		var row: Array = row_v
		var p := Vector2(float(row[0]), float(row[2]))
		var d := p.distance_to(at)
		if d < LINE_REACH_M:
			nearest.append({"p": p, "d": d, "yaw": float(row[3])})
	if nearest.is_empty():
		return Vector2.ZERO
	nearest.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["d"]) < float(y["d"]))
	# a line piece's own +X lies along the line: a turn of `a` about +Y sends +X to (cos a, -sin a)
	var a := deg_to_rad(float(nearest[0]["yaw"]))
	var t := Vector2(cos(a), -sin(a))
	# the line lies on one side of the post; the gap, and the gate, on the other
	var lean := 0.0
	for n in nearest:
		lean += ((n["p"] as Vector2) - at).dot(t)
	return -t if lean > 0.0 else t


## A five-barred gate in `fabric`, hung at `base` (the hanging post's foot, in the fabric's space),
## running `along` (world xz) to its shutting post; `open` swings it back into the field by up to
## a right angle (`swing` 0..1 of the way).
static func hang_gate(fabric: FabricMesh, base: Vector3, along: Vector2, open: bool, swing: float) -> void:
	var yaw := atan2(-along.y, along.x)
	# the shutting post, where the gate closes, stands in the ground whether the gate is open or not
	var far := base + Vector3(along.x, 0.0, along.y) * (GATE_LEN + 0.2)
	fabric.box("joinery", Transform3D(Basis(Vector3.UP, yaw), far + Vector3(0.0, 0.7, 0.0)), Vector3(0.2, 1.5, 0.2), GATE_TIMBER.darkened(0.3))
	var turn := yaw + (deg_to_rad(70.0 + 25.0 * swing) if open else 0.0)
	var frame := Transform3D(Basis(Vector3.UP, turn), base + Vector3(0.0, 0.0, 0.0))
	var tint := FabricMesh.shade(GATE_TIMBER, 0.9 + 0.2 * swing)
	# the stiles: the hanging one at the post, the head one at the far end
	fabric.box("joinery", frame * Transform3D(Basis(), Vector3(0.18, GATE_H * 0.5 + 0.12, 0.0)), Vector3(0.12, GATE_H, 0.1), tint)
	fabric.box("joinery", frame * Transform3D(Basis(), Vector3(GATE_LEN, GATE_H * 0.5 + 0.12, 0.0)), Vector3(0.1, GATE_H, 0.08), tint)
	# five bars, closer together at the foot where the stock would push through
	for y in [0.22, 0.42, 0.64, 0.9, 1.22]:
		fabric.box("joinery", frame * Transform3D(Basis(), Vector3(GATE_LEN * 0.5 + 0.1, float(y), 0.0)),
				Vector3(GATE_LEN - 0.1, 0.075, 0.06), tint)
	# and the brace, from the foot of the hanging stile up to the top bar near the head
	var foot := Vector3(0.25, 0.26, 0.0)
	var head := Vector3(GATE_LEN - 0.35, 1.18, 0.0)
	var mid := (foot + head) * 0.5
	var run := head - foot
	fabric.box("joinery", frame * Transform3D(Basis(Vector3.BACK, atan2(run.y, run.x)), mid + Vector3(0.0, 0.0, 0.035)),
			Vector3(run.length(), 0.07, 0.05), tint)


# --- drystone walls ---------------------------------------------------------------------------------

## Rebuilds the drystone rows of a cell as walls: an end piece standing in a run becomes wall, and
## each piece is stretched along its line to meet the next and held to a steady height.
static func _walls(walls: Dictionary, ends: Dictionary, out: Dictionary) -> void:
	var wall_paths: Array = walls.keys()
	var target := str(wall_paths[0]) if not wall_paths.is_empty() else ""
	if target == "":
		# no wall in the cell to turn an end into: draw the ends as they are
		for p in ends:
			out[p] = ends[p]
		return
	# every piece on the grid, walls and ends alike, so a piece finds its neighbours in O(1)
	var grid: Dictionary = {}
	var all: Array = []
	for p in walls:
		for row in walls[p]:
			all.append({"row": row, "path": str(p), "end": false})
	for p in ends:
		for row in ends[p]:
			all.append({"row": row, "path": str(p), "end": true})
	for i in range(all.size()):
		var row: Array = all[i]["row"]
		var key := Vector2i(int(floor(float(row[0]) / 4.0)), int(floor(float(row[2]) / 4.0)))
		if not grid.has(key):
			grid[key] = []
		(grid[key] as Array).append(i)
	for i in range(all.size()):
		var piece: Dictionary = all[i]
		var row: Array = (piece["row"] as Array).duplicate()
		var at := Vector2(float(row[0]), float(row[2]))
		var a := deg_to_rad(float(row[3]))
		var t := Vector2(cos(a), -sin(a))
		var ahead := INF
		var behind := INF
		# A boundary running on the diagonal came out of the build two texels thick, and laid a
		# wall along each: two walls a few metres apart where a field has one. Of such a pair the
		# one on the far side of the line (its canonical left) gives way.
		var canon := t if (t.x > 0.001 or (absf(t.x) <= 0.001 and t.y > 0.0)) else -t
		var left := Vector2(-canon.y, canon.x)
		var twin := false
		var key := Vector2i(int(floor(at.x / 4.0)), int(floor(at.y / 4.0)))
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				for j in grid.get(key + Vector2i(dx, dz), []):
					if j == i:
						continue
					var other: Array = all[j]["row"]
					var q := Vector2(float(other[0]), float(other[2]))
					var d := q - at
					var along := d.dot(t)
					var oa := deg_to_rad(float(other[3]))
					var across := d.dot(left)
					if absf(Vector2(cos(oa), -sin(oa)).dot(t)) > 0.9 and across < -1.6 and across > -5.0 \
							and absf(d.dot(canon)) < 2.2:
						twin = true
					if absf(d.dot(Vector2(-t.y, t.x))) > 1.2 or d.length() > 5.0:
						continue
					if along > 0.3:
						ahead = minf(ahead, along)
					elif along < -0.3:
						behind = minf(behind, -along)
		if twin:
			continue
		var in_run := ahead < 5.0 and behind < 5.0
		var path := str(piece["path"])
		if bool(piece["end"]) and in_run:
			path = target
		if not bool(piece["end"]) or in_run:
			# each piece reaches half way to the further of its neighbours, so two pieces either
			# side of a gap meet in it; never shorter than the module. A steady height, with a
			# little of the old variation left in it.
			var s := float(row[4]) if row.size() > 4 else 1.0
			var gap := maxf(ahead if ahead < 5.0 else 0.0, behind if behind < 5.0 else 0.0)
			var reach := clampf(gap / WALL_MODULE_M + 0.06, 1.0, 1.9)
			# the scale in the piece's own axes is the row's ninth field (CONTRACTS §6), after the
			# uniform scale, the tint and the lean pair, which a wall stands without
			while row.size() < 8:
				if row.size() == 4:
					row.append(1.0)
				elif row.size() == 5:
					row.append("#ffffff")
				else:
					row.append(0.0)
			row.resize(8)
			row.append([reach, 1.0 + (s - 1.0) * 0.25, 1.0])
		if not out.has(path):
			out[path] = []
		(out[path] as Array).append(row)
