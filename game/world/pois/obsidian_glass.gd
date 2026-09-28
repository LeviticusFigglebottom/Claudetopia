extends RefCounted
## Black volcanic glass for the places the Ash Winter sang dry: the Glass Falls, a fall that set as
## it poured, and the Glassbed under the Glass Bridge, a river that set as it flowed. They are dry
## black glass on purpose (DESIGN, the WORLD_BIBLE's Cinderlea): neither water nor plain dark rock.
##
## A flat sheet of black at a low roughness photographed as spilled oil, and five-metre plates in a
## row as grey squares; so the glass is shaped like the liquid it was: a pour that rolls over its lip
## in ropes and stops in lobed toes on the ground, a channel with levées at its margins and heaved,
## broken plates and shards along its edges. Its surface, the ropes, the arcs, the conchoidal shells
## and the ash in its cracks, is `assets/shaders/obsidian.gdshader`, which takes UV in metres (u
## across the flow, v along it).

const SHADER := "res://assets/shaders/obsidian.gdshader"


## The glass, shaped for what it is: "pour" (a fall's face: long ropes, little ash), "bed" (a
## channel's floor: arcs across it, cracks, ash in them), "shard" (broken edges: conchoidal shells,
## no flow of their own, drawn off the world along `flow`).
static func material(kind := "bed", flow := Vector2(0.0, 1.0)) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER)
	match kind:
		"pour":
			mat.set_shader_parameter("ropes", 1.2)
			mat.set_shader_parameter("ripples", 0.25)
			mat.set_shader_parameter("conchoidal", 0.25)
			mat.set_shader_parameter("cracks", 0.25)
			mat.set_shader_parameter("crack_cell", 3.4)
			mat.set_shader_parameter("ash", 0.12)
		"pool":
			mat.set_shader_parameter("ropes", 0.35)
			mat.set_shader_parameter("ripples", 0.9)
			mat.set_shader_parameter("conchoidal", 0.35)
			mat.set_shader_parameter("cracks", 0.5)
			mat.set_shader_parameter("ash", 0.3)
		"shard":
			mat.set_shader_parameter("ropes", 0.3)
			mat.set_shader_parameter("ripples", 0.1)
			mat.set_shader_parameter("conchoidal", 0.35)
			mat.set_shader_parameter("cracks", 0.0)
			mat.set_shader_parameter("ash", 0.12)
			mat.set_shader_parameter("world_uv", 1.0)
			mat.set_shader_parameter("world_flow", flow)
		_:
			# the ropes and shells drawn small on a flat bed read as wood grain and knots; a bed is
			# its arcs, a few long cracks, and ash in them
			# and its lines drawn straight and even read, from above, as planks: they wander, gather
			# and part, break off, and broad swells of the set flow carry the gloss between them
			mat.set_shader_parameter("ropes", 0.22)
			mat.set_shader_parameter("meander", 2.4)
			mat.set_shader_parameter("swells", 1.0)
			mat.set_shader_parameter("ripples", 0.4)
			mat.set_shader_parameter("conchoidal", 0.0)
			mat.set_shader_parameter("cracks", 0.5)
			mat.set_shader_parameter("crack_cell", 5.5)
			mat.set_shader_parameter("crack_ash", 0.0)
			mat.set_shader_parameter("ash", 0.16)
			mat.set_shader_parameter("bump", 1.6)
	return mat


static func begin(smooth := true) -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0 if smooth else -1)
	return st


## Finishes a batch as the masonry's commit does (the far ring keeps a silhouette), with tangents,
## which the glass's surface is drawn along.
static func commit(k: PoiKit, st: SurfaceTool, mat: Material, node_name: String, silhouette := true) -> MeshInstance3D:
	if k.far and not silhouette:
		return null
	if k.deferred:
		# a place raised while the world is drawn: made on a worker thread with its masonry
		# (PoiDressing.meshes_ready), with its tangents
		var later := MeshInstance3D.new()
		later.material_override = mat
		later.name = node_name
		k.root.add_child(later)
		k.pending.append([later, st, true])
		if k.far:
			k._far_range(later)
		return later
	st.generate_normals()
	st.generate_tangents()
	var mesh := st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return null
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.material_override = mat
	inst.name = node_name
	k.root.add_child(inst)
	if k.far:
		k._far_range(inst)
	return inst


## A grid of rows (each an Array of Vector3) as triangles, with UV in metres: u across, v along.
static func _grid(st: SurfaceTool, rows: Array, uvs: Array) -> void:
	for i in rows.size() - 1:
		var r0: Array = rows[i]
		var r1: Array = rows[i + 1]
		var u0: Array = uvs[i]
		var u1: Array = uvs[i + 1]
		for j in r0.size() - 1:
			st.set_uv(u0[j]); st.add_vertex(r0[j])
			st.set_uv(u1[j + 1]); st.add_vertex(r1[j + 1])
			st.set_uv(u0[j + 1]); st.add_vertex(r0[j + 1])
			st.set_uv(u0[j]); st.add_vertex(r0[j])
			st.set_uv(u1[j]); st.add_vertex(r1[j])
			st.set_uv(u1[j + 1]); st.add_vertex(r1[j + 1])


# --- the fall that set as it poured -----------------------------------------------------------------

## The ropes of a pour across `width`: [centre, half width, how far it stands out, where down the
## face (0 lip .. 1 foot, more runs on into the toe) it ends].
static func _ropes(rng: RandomNumberGenerator, width: float) -> Array:
	var out: Array = []
	var x := -width * 0.5 - 0.2
	while x < width * 0.5 + 0.2:
		var hw := rng.randf_range(0.28, 0.75)
		var reach := rng.randf_range(0.45, 1.0) if rng.randf() < 0.35 else rng.randf_range(1.05, 1.9)
		out.append([x + hw, hw, rng.randf_range(0.10, 0.34), reach])
		x += hw * rng.randf_range(1.2, 1.9)
	return out


static func _rope_out(ropes: Array, x: float, s: float) -> float:
	var best := 0.0
	var sum := 0.0
	for r in ropes:
		var d := (x - float(r[0])) / float(r[1])
		if absf(d) >= 1.0:
			continue
		var reach := float(r[3])
		# a rope swells into a drip where it stops, then is gone
		var end := 1.0 - smoothstep(reach - 0.06, reach + 0.03, s)
		var swell := 1.0 + 0.8 * smoothstep(reach - 0.22, reach - 0.04, s) * end
		var bump := (1.0 - d * d) * (1.0 - d * d) * float(r[2]) * end * swell
		best = maxf(best, bump)
		sum += bump
	return best * 0.7 + sum * 0.3


## The Glass Falls' pour, from a little behind `lip` (local, the channel's top centre) over the edge
## and down `drop` metres to the ground, facing `yaw`, `width` across: it rolls over the lip as a
## glassy bulge, falls in ropes that stand out of the face (some stop short in drips), and spreads
## at the foot into lobed toes on the ground where it stopped. The node is "Glass" (the capture
## plans and the dressing's wet names look for it). `drop` is from the lip to the pad's ground; the
## face runs to the ground at its own foot. Returns {mesh, toe (how far out the toes reach), top and
## bottom (local y of the face's run), belly}, for `face_at`.
static func pour(k: PoiKit, lip: Vector3, yaw: float, width: float, drop: float, belly := 0.8) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = k.rng.seed ^ 0x6a55
	var basis := Basis(Vector3.UP, yaw)
	var ropes := _ropes(rng, width)
	var cols := maxi(int(width / 0.16), 24)
	# the profile down the centre, in the face's own (out, up) plane, from behind the lip to the toe:
	# [out, y, s (0 at the lip, 1 at the foot)]
	var prof: Array = []
	for i in 5:
		var t := float(i) / 4.0
		var out := lerpf(-1.6, 0.05, t)
		prof.append([out, 0.10 + 0.16 * t * t, -0.2 * (1.0 - t)])
	# the roll over the edge: a quarter turn of a thick bead
	for i in 6:
		var a := float(i + 1) / 6.0 * PI * 0.5
		prof.append([0.05 + sin(a) * 0.5, 0.26 - (1.0 - cos(a)) * 0.62, 0.02 + float(i + 1) / 6.0 * 0.06])
	# the face, bellying out as it falls
	var face_top := 0.26 - 0.62
	# where the face meets the ground: the ground at its foot, not the pad's middle
	var foot := Vector3(lip.x, 0.0, lip.z) + basis * Vector3(0.0, 0.0, 0.55 + belly + 0.9)
	var face_bottom := minf(k.on_ground(foot.x, foot.z).y - lip.y, -drop) + 1.1
	var face_rows := maxi(int((face_top - face_bottom) / 0.35), 18)
	for i in face_rows:
		var v := float(i + 1) / float(face_rows)
		prof.append([pour_out(v, belly), lerpf(face_top, face_bottom, v), lerpf(0.08, 0.93, v)])
	# the fillet into the ground, and the toe running out on it
	for i in 5:
		var a := float(i + 1) / 5.0 * PI * 0.5
		prof.append([0.55 + belly + sin(a) * 0.9, face_bottom - sin(a) * 0.72, 0.93 + float(i + 1) / 5.0 * 0.07])
	var toe_rows := 12
	for i in toe_rows:
		var t := float(i + 1) / float(toe_rows)
		prof.append([0.55 + belly + 0.9 + t * 1.0, NAN, 1.0 + t])
	var rows: Array = []
	var uvs: Array = []
	var arc := 0.0
	var last := Vector2(float(prof[0][0]), float(prof[0][1]))
	var toe_reach := 0.0
	for i in prof.size():
		var p: Array = prof[i]
		var out := float(p[0])
		var s := float(p[2])
		var row: Array = []
		var uv_row: Array = []
		var y0 := float(p[1]) if not is_nan(float(p[1])) else face_bottom - 0.9
		arc += Vector2(out, y0).distance_to(last)
		last = Vector2(out, y0)
		var spread := 1.0 + 0.3 * clampf(s, 0.0, 1.0) + 0.35 * clampf(s - 1.0, 0.0, 1.0)
		# its sides are ragged where the outer ropes ran and stopped, not a curtain's hem
		var hem_l := 1.0 + 0.07 * sin(s * 11.0 + 1.3) + 0.05 * sin(s * 27.0 + 0.4)
		var hem_r := 1.0 + 0.07 * sin(s * 13.0 + 4.1) + 0.05 * sin(s * 23.0 + 2.2)
		# over the lip it is a bead, domed across, higher in the middle where most of it came
		var over := 1.0 - smoothstep(0.0, 0.12, s)
		for j in cols + 1:
			var u := float(j) / float(cols)
			var x := (u - 0.5) * width * spread * (hem_l if u < 0.5 else hem_r)
			var edge := absf(u - 0.5) * 2.0
			var tuck := smoothstep(0.82, 1.0, edge)
			var rope := _rope_out(ropes, x / spread, s)
			var o := out + rope - tuck * 0.45
			var y := y0 + over * 0.22 * (1.0 - edge * edge)
			if is_nan(float(p[1])):
				# on the ground: each rope runs its own way out, and the toe is a lobe where it stopped
				var reach := 0.25 + rope * 7.0 + 0.4 * sin(x * 1.3 + 0.7)
				var tt := clampf(s - 1.0, 0.0, 1.0)
				o = 0.55 + belly + 0.9 + tt * clampf(reach, 0.5, 3.4) - tuck * 0.45
				var q := Vector3(lip.x, 0.0, lip.z) + basis * Vector3(x, 0.0, o)
				var g := k.on_ground(q.x, q.z).y
				# thick at the fall, thinning out, the lobe's front rolling down into the ground
				y = g + (0.35 + rope * 0.8) * (1.0 - tt * tt) - 0.08 * tt - tuck * 0.2
				toe_reach = maxf(toe_reach, o)
			var pt := Vector3(lip.x, lip.y + y, lip.z) + basis * Vector3(x, 0.0, o)
			if is_nan(float(p[1])):
				pt.y = y
			else:
				pt.y = maxf(pt.y, k.on_ground(pt.x, pt.z).y - 0.3)
			row.append(pt)
			uv_row.append(Vector2(x, arc))
		rows.append(row)
		uvs.append(uv_row)
	var st := begin()
	_grid(st, rows, uvs)
	var mesh := commit(k, st, material("pour"), "Glass", true)
	if mesh != null:
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# the fall's own shader knew it was glass; the river's falls still ask
		mesh.set_meta("glass", true)
	# the strands that stopped in the air: ropes standing out from the face at its sides, each
	# ending in a drip
	var drips := begin()
	var hang := 0
	for r in ropes:
		if hang >= 5 or float(r[3]) > 1.0 or rng.randf() < 0.25:
			continue
		hang += 1
		var x := float(r[0])
		var strand := (face_top - face_bottom) * float(r[3]) * rng.randf_range(0.8, 1.0)
		var top := Vector3(lip.x, lip.y - 0.3, lip.z) + basis * Vector3(x, 0.0, 0.62 + float(r[2]))
		_drip(drips, top, basis, strand, float(r[1]) * 0.5, rng)
	commit(k, drips, material("pour"), "GlassDrips", false)
	return {"mesh": mesh, "toe": toe_reach, "top": lip.y + face_top, "bottom": lip.y + face_bottom, "belly": belly}


## How far out from the lip the pour's face stands, `v` of the way down it (0 top, 1 foot).
static func pour_out(v: float, belly: float) -> float:
	return 0.55 + belly * v * v


## Where on the pour's face (local xz off the lip along `facing`, and how far out) a thing set into
## it at local height `y` stands: the face's own line there, before its ropes.
static func face_at(info: Dictionary, y: float) -> float:
	var span := float(info["top"]) - float(info["bottom"])
	var v := clampf((float(info["top"]) - y) / maxf(span, 0.1), 0.0, 1.0)
	return pour_out(v, float(info["belly"]))


## A strand of glass hanging from `top`, `length` long, `radius` thick, tapering to a drip's point
## after a swelling: a ring of sides down it, a little out of true.
static func _drip(st: SurfaceTool, top: Vector3, basis: Basis, length: float, radius: float,
		rng: RandomNumberGenerator) -> void:
	var sides := 7
	var rings := 10
	var lean := basis * Vector3(0.0, 0.0, rng.randf_range(0.02, 0.1))
	var grid: Array = []
	var uvs: Array = []
	for i in rings + 1:
		var t := float(i) / float(rings)
		var r := radius * (1.0 - 0.35 * t) * (1.0 + 0.7 * smoothstep(0.6, 0.85, t)) * (1.0 - smoothstep(0.86, 1.0, t))
		r = maxf(r, 0.004)
		var c := top + Vector3(0.0, -length * t, 0.0) + lean * t * length
		var row: Array = []
		var uv_row: Array = []
		for j in sides + 1:
			var a := TAU * float(j) / float(sides)
			row.append(c + basis * Vector3(cos(a) * r, 0.0, sin(a) * r * 0.8))
			uv_row.append(Vector2(a * radius, length * t))
		grid.append(row)
		uvs.append(uv_row)
	_grid(st, grid, uvs)


## The basin the fall stopped in: a pool of glass set hard, a low lens over the ground with frozen
## rings round where the fall struck it and a rolled, broken edge, and the ground's lie under it.
static func set_pool(k: PoiKit, centre: Vector2, r: float, struck: Vector2, node_name := "Basin") -> MeshInstance3D:
	if k.far:
		return null
	var rng := RandomNumberGenerator.new()
	rng.seed = k.rng.seed ^ 0x2b0c
	var segs := 40
	var rings := 14
	var lobes: Array = []
	for j in segs:
		lobes.append(rng.randf_range(0.72, 1.18))
	var rows: Array = []
	var uvs: Array = []
	for i in rings + 1:
		var t := float(i) / float(rings)
		var row: Array = []
		var uv_row: Array = []
		for j in segs + 1:
			var a := TAU * float(j % segs) / float(segs)
			var wob := (float(lobes[(j + segs - 1) % segs]) + float(lobes[j % segs]) * 2.0 + float(lobes[(j + 1) % segs])) * 0.25
			var rr := r * t * wob
			var p := centre + Vector2(sin(a), cos(a)) * rr
			var g := k.on_ground(p.x, p.y).y
			# the frozen rings round the strike, fading out, and the lens's rolled edge
			var ds := p.distance_to(struck)
			var ring := sin(ds * 3.6) * 0.035 * exp(-ds * 0.25)
			var lens := 0.2 * (1.0 - smoothstep(0.55, 1.0, t)) + 0.05 * (1.0 - t)
			var y := g + lens + ring * (1.0 - t) - smoothstep(0.8, 1.0, t) * 0.12
			row.append(Vector3(p.x, y, p.y))
			uv_row.append(Vector2(sin(a) * rr, cos(a) * rr))
		rows.append(row)
		uvs.append(uv_row)
	var st := begin()
	_grid(st, rows, uvs)
	var inst := commit(k, st, material("pool"), node_name, false)
	if inst != null:
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return inst


# --- the river that set as it flowed ----------------------------------------------------------------

## The line of a bed from `start` along `dir`, `each` metres a step, `steps` of them, down the lowest
## ground across it: at each step the ground is looked at across the bed and the line eases toward
## its lowest point, so the glass lies in the riverbed's own trough whichever way it winds.
## `hold_m` is how near `start` the line keeps to the straight (under a bridge's arch).
static func thalweg(k: PoiKit, start: Vector2, dir: Vector2, steps: int, each: float, hold_m := 6.0,
		look := 10.0) -> Array:
	var pts: Array = [start]
	var p := start
	var d := dir.normalized()
	for i in steps:
		var ahead := p + d * each
		var side := Vector2(-d.y, d.x)
		var best := 0.0
		var low := INF
		for n in range(-5, 6):
			var o := float(n) / 5.0 * look
			var q := ahead + side * o
			# a little bias to the straight, so a flat floor does not make it wander
			var h := k.on_ground(q.x, q.y).y + absf(o) * 0.03
			if h < low:
				low = h
				best = o
		var pull := 0.0 if ahead.distance_to(start) < hold_m else 0.12
		var next := ahead + side * best * pull
		d = (d * 0.8 + (next - p).normalized() * 0.2).normalized()
		p = next
		pts.append(p)
	return pts


## The Glassbed under a crossing: a ribbon of black glass down `line` (local xz points, in order down
## the bed), `half_w` either side give or take, lying on the ground with levées at its margins where
## the flow set first, the arcs across it a slowing flow wrinkles into, and a buried, ragged edge.
## Returns its margin points every 1.2 m, [left, right], each [the margin, the way down the bed,
## the bed's middle there], for the plates and shards along them.
static func ribbon(k: PoiKit, line_in: Array, half_w: float, node_name := "GlassBed") -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = k.rng.seed ^ 0x51ed
	# the line at a row every 0.6 m, so the arcs across it are drawn and not aliased away
	var line: Array = []
	for i in line_in.size() - 1:
		var p0: Vector2 = line_in[i]
		var p1: Vector2 = line_in[i + 1]
		var n := maxi(int(ceil(p0.distance_to(p1) / 0.6)), 1)
		for j in n:
			line.append(p0.lerp(p1, float(j) / float(n)))
	line.append(line_in[-1])
	var across := 26
	var rows: Array = []
	var uvs: Array = []
	var left: Array = []
	var right: Array = []
	var along := 0.0
	var wl := half_w
	var wr := half_w
	var want_l := half_w
	var want_r := half_w
	var phase := rng.randf_range(0.0, TAU)
	# the level the liquid stood at, down the bed: a little over the trough's floor, eased along it,
	# and sinking under the ground at both ends where the glass runs out
	var level: Array[float] = []
	for i in line.size():
		if i % 16 == 15:
			await k.step()
		var p: Vector2 = line[i]
		var low := INF
		for n in range(-4, 5):
			var prev_i: Vector2 = line[maxi(i - 1, 0)]
			var next_i: Vector2 = line[mini(i + 1, line.size() - 1)]
			var dd := (next_i - prev_i).normalized()
			var q := p + Vector2(-dd.y, dd.x) * float(n) * half_w * 0.2
			low = minf(low, k.on_ground(q.x, q.y).y)
		var t := float(i) / float(maxi(line.size() - 1, 1))
		var ends := smoothstep(0.0, 0.1, t) * smoothstep(1.0, 0.9, t)
		level.append(low + lerpf(-0.35, rng.randf_range(0.28, 0.4), ends))
	for _pass in 3:
		for i in range(1, line.size() - 1):
			level[i] = (level[i - 1] + level[i] * 2.0 + level[i + 1]) * 0.25
	for i in line.size():
		if i % 8 == 7:
			await k.step()
		var p: Vector2 = line[i]
		var prev: Vector2 = line[maxi(i - 1, 0)]
		var next: Vector2 = line[mini(i + 1, line.size() - 1)]
		var d := (next - prev).normalized()
		var side := Vector2(-d.y, d.x)
		if i > 0:
			along += p.distance_to(prev)
		# each margin wanders on its own, and is ragged where plates broke from it
		if i % 6 == 0:
			want_l = half_w * rng.randf_range(0.7, 1.25)
			want_r = half_w * rng.randf_range(0.7, 1.25)
		wl = lerpf(wl, want_l, 0.15)
		wr = lerpf(wr, want_r, 0.15)
		# ragged: a notch or a tooth every row or two, where a plate broke from the margin
		var rag_l := rng.randf_range(-0.55, 0.3) if i % 2 == 0 else rng.randf_range(-0.1, 0.1)
		var rag_r := rng.randf_range(-0.55, 0.3) if i % 2 == 1 else rng.randf_range(-0.1, 0.1)
		var row: Array = []
		var uv_row: Array = []
		for j in across + 1:
			var s := float(j) / float(across) * 2.0 - 1.0
			var w := (wl + rag_l) if s < 0.0 else (wr + rag_r)
			var q := p + side * s * w
			var g := k.on_ground(q.x, q.y).y
			var e := absf(s)
			# A low lobe of glass lying in the bed, crowned a little, a levée near each margin where
			# the flow set first, the arcs across it bowed downstream, and the margin tapering down
			# into the ground over its last metre (a step down at the edge read as a kerb). And no
			# higher than the liquid stood when it set: where the bank rises above that, the glass
			# goes under it, so its edge follows the ground's own contour.
			var levee := smoothstep(0.45, 0.72, e) * (1.0 - smoothstep(0.72, 0.95, e)) * 0.07
			var arcs := sin((along - s * s * 1.8) * (1.7 + 0.5 * sin(along * 0.21)) + phase) * 0.014 * (1.0 - e * e)
			var body := 0.1 + 0.04 * (1.0 - e * e) + levee + arcs
			var lift := body * (1.0 - smoothstep(0.66, 1.0, e)) - 0.1 * smoothstep(0.8, 1.0, e)
			lift = minf(lift, level[i] + 0.04 * (1.0 - e * e) + arcs - g)
			row.append(Vector3(q.x, g + lift, q.y))
			uv_row.append(Vector2(s * w, along))
		rows.append(row)
		uvs.append(uv_row)
		if i % 2 == 0:
			left.append([p - side * wl, d, p])
			right.append([p + side * wr, d, p])
	await k.step()
	var st := begin()
	_grid(st, rows, uvs)
	await k.step()
	var inst := commit(k, st, material("bed"), node_name, true)
	if inst != null:
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return [left, right]


## A plate of the set glass broken from the margin and heaved up by what flowed under it: an
## irregular polygon a hand thick, tilted up along `lift_dir`, its broken edge standing sharp. Laid
## into `st` (flat facets), centred at `at` (local, on the ground). Returns its frame, for a collider.
static func plate(st: SurfaceTool, at: Vector3, size: Vector2, yaw: float, tilt: float,
		rng: RandomNumberGenerator, thick := 0.12) -> Transform3D:
	var n := rng.randi_range(5, 7)
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt) * Basis(Vector3.BACK, rng.randf_range(-0.15, 0.15))
	var top: Array = []
	var bot: Array = []
	for i in n:
		var a := TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / float(n)
		var r := rng.randf_range(0.6, 1.0)
		var v := Vector3(sin(a) * size.x * 0.5 * r, 0.0, cos(a) * size.y * 0.5 * r)
		top.append(at + basis * (v + Vector3(0.0, thick * 0.5 + rng.randf_range(-0.02, 0.03), 0.0)))
		bot.append(at + basis * (v * 0.93 - Vector3(0.0, thick * 0.5, 0.0)))
	var c_top := at + basis * Vector3(0.0, thick * 0.5 + 0.03, 0.0)
	for i in n:
		var i1 := (i + 1) % n
		_tri(st, c_top, top[i1], top[i])
		_tri(st, top[i], top[i1], bot[i1])
		_tri(st, top[i], bot[i1], bot[i])
	return Transform3D(basis, at)


## A shard of glass standing up from the ground at `at`: a three- or four-sided blade, leaning,
## thin across, sharp at the tip and along its edges.
static func shard(st: SurfaceTool, at: Vector3, height: float, width: float, lean: Vector3,
		rng: RandomNumberGenerator) -> void:
	var n := rng.randi_range(3, 4)
	var yaw := rng.randf_range(0.0, TAU)
	var flat := rng.randf_range(0.3, 0.6)
	var base: Array = []
	for i in n:
		var a := yaw + TAU * (float(i) + rng.randf_range(-0.2, 0.2)) / float(n)
		base.append(at + Vector3(sin(a) * width * 0.5, -0.15, cos(a) * width * 0.5 * flat).rotated(Vector3.UP, yaw))
	var tip := at + Vector3(0.0, height, 0.0) + lean * height
	var mid := at.lerp(tip, rng.randf_range(0.45, 0.7)) + Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)) * width * 0.15
	for i in n:
		var i1 := (i + 1) % n
		var shoulder: Vector3 = (base[i] as Vector3).lerp(base[i1], 0.5).lerp(mid, 0.7)
		_tri(st, base[i], base[i1], shoulder)
		_tri(st, base[i], shoulder, tip)
		_tri(st, shoulder, base[i1], tip)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	for v in [a, b, c]:
		var p: Vector3 = v
		st.set_uv(Vector2(p.x + p.y * 0.7, p.z - p.y * 0.4))
		st.add_vertex(p)
