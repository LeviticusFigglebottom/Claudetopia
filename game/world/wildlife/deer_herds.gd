class_name DeerHerds
extends Node3D
## The red deer: small herds at the woods' edges in the Briarwold, Hearthvale and Skerrow, grazing
## out on the open ground with the trees at their backs, as deer do at the ends of the day. It is
## the rut: most herds are hinds with a stag keeping them, and a few are stags alone together.
##
## A herd is put where the trees stop (TreeCover: open ground with wood within a couple of bins),
## on dry ground not too steep and clear of the places, the same herd in the same place on every
## visit (seeded by the streamer's cell). It grazes a slow step at a time about its patch. Somebody
## coming up puts their heads up and they stand and watch (Alert); nearer, or coming fast, and they
## go -- all together, bounding (the forge's Run), out and away to somewhere a couple of hundred
## metres off, where they drop to a trot, then a walk, and graze again.
##
## Near the eye the nearest MAX_LIVE are the forge's rigged deer (tools/forge/horse_forge.py `deer`,
## HorseModel): a stag shows the antler rack the hinds' model hides. The rest are the forge's far
## herd meshes (the hind's and the stag's, antlers and all) in two MultiMeshes posed by the herd
## shader (herd_far.gdshader), the way Livestock draws its far flocks: two draws for every deer in
## the country, and the live ones' own.

const MODEL := "res://assets/models/creatures/deer_red/deer_red.glb"
const FAR_HIND := "res://assets/models/creatures/deer_red/deer_red_lod2_bind.glb"
const FAR_STAG := "res://assets/models/creatures/deer_red/deer_red_stag_lod2_bind.glb"

## A streamer cell whose centre is within this of the eye has its herd; farther, it is let go.
const LIVE_M := 520.0
const KEEP_M := 640.0
## How likely a cell of each region with a wood's edge in it is to hold a herd (at wildlife 1.0).
const REGIONS := {"core:region/briarwold": 0.3, "core:region/hearthvale": 0.15, "core:region/skerrow": 0.2}
## Stags alone together, out of the herds a region holds: Skerrow's open hill has most of them.
const STAG_GROUPS := {"core:region/briarwold": 0.15, "core:region/hearthvale": 0.1, "core:region/skerrow": 0.3}
const HERD := [3, 7]
const MIN_EDGE_BINS := 5
## Grazing wanders this far from the herd's middle.
const GRAZE_R := 22.0
## Heads up at this; off at FLEE_M, or at FLEE_FAST_M from somebody coming at a run.
const ALERT_M := 75.0
const FLEE_M := 40.0
const FLEE_FAST_M := 60.0
const FAST_MPS := 4.0
## The flight: how fast, and how far before they drop to a trot and then a walk.
const RUN_MPS := 9.5
const TROT_MPS := 3.2
const WALK_MPS := 1.1
const STEP_MPS := 0.35
const RUN_TO := [170.0, 230.0]
## The rigged deer near the eye.
const NEAR_M := 65.0
const MAX_LIVE := 10
## The far herd shader's colours: the red summer coat, the rump patch on the scut.
const COLOURS := {"body": Color(0.50, 0.27, 0.14), "head": Color(0.44, 0.31, 0.22), "legs": Color(0.36, 0.25, 0.18),
		"tail": Color(0.84, 0.74, 0.55), "antler": Color(0.50, 0.41, 0.30)}
const STRIDE_HZ := 0.9

enum S { GRAZE, STEP, ALERT, RUN, SETTLE }

var provider: TerrainProvider = null
## The share of the herds put out (the `wildlife` graphics setting, handed down by Wildlife).
var density := 1.0
## What counts as somebody coming near: the nodes in this group, or the eye if there are none.
var spooked_by := "player"

var herds: Array[Dictionary] = []
var _cells: Dictionary = {}          # Vector2i streamer cell -> true once looked at (peopled or not)
var _places: Array = []
var _live: Dictionary = {}           # deer (Dictionary, by its id) -> HorseModel
var _far: Dictionary = {}            # "hind" | "stag" -> MultiMesh
var _far_inst: Dictionary = {}
var _far_lift := {"hind": 0.0, "stag": 0.0}
var _eye := Vector3.ZERO
var _time := 0.0
var _started := false
var _last: Dictionary = {}           # spooker id -> [position, time], to tell who is running
var _next_id := 0


func _ready() -> void:
	add_to_group("deer_herds")
	_build_far()


# --- the far herds' draws ---------------------------------------------------------------------

func _build_far() -> void:
	for kind in ["hind", "stag"]:
		var path: String = FAR_STAG if kind == "stag" else FAR_HIND
		if not ResourceLoader.exists(path):
			continue
		var mesh := Livestock.far_mesh(path)
		if mesh == null:
			continue
		var marks := Livestock.far_marks(mesh)
		var mat := ShaderMaterial.new()
		mat.shader = load("res://assets/shaders/herd_far.gdshader")
		mat.set_shader_parameter("leg_top", marks["legs"])
		mat.set_shader_parameter("neck_pivot", marks["neck"])
		mat.set_shader_parameter("tail_pivot", marks["tail"])
		mat.set_shader_parameter("stride_hz", STRIDE_HZ)
		mat.set_shader_parameter("body_colour", COLOURS["body"])
		mat.set_shader_parameter("head_colour", COLOURS["head"])
		mat.set_shader_parameter("leg_colour", COLOURS["legs"])
		mat.set_shader_parameter("tail_colour", COLOURS["tail"])
		mat.set_shader_parameter("antler_colour", COLOURS["antler"])
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		# instance colours on, white: with custom data and none, Compatibility drew the vertex colours
		# (the parts the shader reads) black
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = 0
		var inst := MultiMeshInstance3D.new()
		inst.name = "Deer_" + kind.capitalize()
		inst.multimesh = mm
		inst.material_override = mat
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		inst.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(inst)
		_far[kind] = mm
		_far_inst[kind] = inst
		_far_lift[kind] = maxf(0.0, -mesh.get_aabb().position.y)


# --- where the herds are ------------------------------------------------------------------------

func _start() -> void:
	_started = true
	var pois_path := "%s/pois.json" % TerrainProvider.GENERATED
	if FileAccess.file_exists(pois_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(pois_path))
		if parsed is Array:
			for e in parsed:
				if e is Dictionary and (e as Dictionary).has("pos"):
					var at: Array = e["pos"]
					_places.append([float(at[0]), float(at[2]), float(e.get("radius_flat_m", 25.0)) + 60.0])


func _near_place(x: float, z: float) -> bool:
	for pl in _places:
		var dx := x - float(pl[0])
		var dz := z - float(pl[1])
		if dx * dx + dz * dz < float(pl[2]) * float(pl[2]):
			return true
	return false


## The wood's-edge bins of a streamer cell a herd could graze: open, dry, not steep, clear of the
## places. World positions on the ground.
func edge_spots(cell: Vector2i) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for e in TreeCover.edges_in(cell):
		if provider.is_water(e.x, e.y) or provider.get_slope(e.x, e.y) > 0.45 or _near_place(e.x, e.y):
			continue
		out.append(Vector3(e.x, provider.get_height(e.x, e.y), e.y))
	return out


func _stream(eye: Vector3) -> void:
	var here := TreeCover.cell_of(eye.x, eye.z)
	var cm := TreeCover._cell_m
	var reach := int(ceil(LIVE_M / cm))
	var budget := 1          # a cell looked at a frame: a survey is 256 bins
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var c := here + Vector2i(dx, dz)
			if _cells.has(c) or not _read_round(c):
				continue
			var centre := TreeCover._origin + (Vector2(c) + Vector2(0.5, 0.5)) * cm
			if centre.distance_to(Vector2(eye.x, eye.z)) > LIVE_M:
				continue
			if budget <= 0:
				return
			budget -= 1
			_cells[c] = true
			_people(c)
	# herds whose cell has fallen out of reach are let go, and the cell may be peopled again
	var kept: Array[Dictionary] = []
	for h in herds:
		var c: Vector2i = h["cell"]
		var centre := TreeCover._origin + (Vector2(c) + Vector2(0.5, 0.5)) * cm
		if centre.distance_to(Vector2(eye.x, eye.z)) > KEEP_M:
			_cells.erase(c)
			for d in h["deer"]:
				_let_go(d)
		else:
			kept.append(h)
	herds = kept
	for c in _cells.keys():
		var centre := TreeCover._origin + (Vector2(c) + Vector2(0.5, 0.5)) * cm
		if centre.distance_to(Vector2(eye.x, eye.z)) > KEEP_M:
			_cells.erase(c)


## Whether the streamer has read the cell and the eight round it (a wood's edge runs over a cell's
## border).
static func _read_round(c: Vector2i) -> bool:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if not TreeCover.has_cell(c + Vector2i(dx, dz)):
				return false
	return true


func _people(cell: Vector2i) -> void:
	if density <= 0.0 or provider == null:
		return
	var cm := TreeCover._cell_m
	var cx := TreeCover._origin.x + (float(cell.x) + 0.5) * cm
	var cz := TreeCover._origin.y + (float(cell.y) + 0.5) * cm
	var region := provider.region_id_at(cx, cz)
	if not REGIONS.has(region):
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(cell.x, cell.y, 4831))
	if rng.randf() >= float(REGIONS[region]) * density:
		return
	var spots := edge_spots(cell)
	if spots.size() < MIN_EDGE_BINS:
		return
	var home: Vector3 = spots[rng.randi() % spots.size()]
	var stags_only := rng.randf() < float(STAG_GROUPS.get(region, 0.0))
	add_herd(home, rng.randi_range(int(HERD[0]), int(HERD[1])) if not stags_only else rng.randi_range(2, 3),
			stags_only, rng.randi(), cell, spots)


## Puts a herd of `count` down round `home`: hinds (and a stag keeping them, most often), or stags
## alone together. Returns it.
func add_herd(home: Vector3, count: int, stags_only := false, seed_n := 0, cell := Vector2i(-99999, -99999),
		spots: Array[Vector3] = []) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = seed_n
	if cell == Vector2i(-99999, -99999):
		cell = TreeCover.cell_of(home.x, home.z)
	var h := {"cell": cell, "home": home, "spots": spots, "deer": [], "r": r, "alarm": 0.0, "to": home,
			"state": S.GRAZE}
	var stag_kept := not stags_only and r.randf() < 0.75
	for i in count:
		var stag := stags_only or (stag_kept and i == 0)
		# a yearling or two among the hinds, smaller
		var size := 1.08 if stag else (0.82 if (i >= 3 and r.randf() < 0.4) else r.randf_range(0.94, 1.0))
		var at := home
		for k in 8:
			var a := r.randf() * TAU
			var d := sqrt(r.randf()) * GRAZE_R * 0.7
			var p := home + Vector3(cos(a) * d, 0.0, sin(a) * d)
			if _dry(p):
				at = p
				break
		at.y = _ground(at)
		h["deer"].append({"id": _next_id, "pos": at, "yaw": r.randf() * TAU, "stag": stag, "size": size,
				"state": S.GRAZE, "target": at, "wait": r.randf_range(0.0, 8.0), "speed": 0.0, "turn": 0.0,
				"phase": r.randf(), "delay": 0.0, "pace": r.randf_range(0.94, 1.06)})
		_next_id += 1
	herds.append(h)
	return h


func _dry(p: Vector3) -> bool:
	return provider == null or not provider.is_water(p.x, p.z)


func _ground(p: Vector3) -> float:
	return provider.get_height(p.x, p.z) if provider != null else p.y


# --- behaviour ------------------------------------------------------------------------------

## Moves the herds on by `delta` seconds with the eye at `eye` (Wildlife.update calls it).
func update(eye: Vector3, delta: float) -> void:
	_eye = eye
	_time += delta
	if not _started:
		_start()
	if provider != null:
		_stream(eye)
	var near := _spookers(eye, delta)
	for h in herds:
		_step_herd(h, delta, near)
	_draw()


## Who is about, and how fast each is going: [[position, speed]].
func _spookers(eye: Vector3, delta: float) -> Array:
	var out: Array = []
	var seen := {}
	if is_inside_tree():
		for n in get_tree().get_nodes_in_group(spooked_by):
			if n is Node3D:
				var p := (n as Node3D).global_position
				var id := n.get_instance_id()
				var v := 0.0
				if _last.has(id) and delta > 0.0:
					v = Vector2(p.x - (_last[id][0] as Vector3).x, p.z - (_last[id][0] as Vector3).z).length() / delta
					v = lerpf(float(_last[id][1]), v, clampf(delta * 4.0, 0.0, 1.0))
				_last[id] = [p, v]
				seen[id] = true
				out.append([p, v])
	for id in _last.keys():
		if not seen.has(id):
			_last.erase(id)
	if out.is_empty() and spooked_by == "player":
		out.append([eye, 0.0])
	return out


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _step_herd(h: Dictionary, dt: float, near: Array) -> void:
	var r: RandomNumberGenerator = h["r"]
	# the nearest somebody to any of the herd, and how fast they come
	var who := Vector3(INF, 0.0, INF)
	var dist := INF
	var fast := false
	for d in h["deer"]:
		for s in near:
			var e := _flat(s[0], d["pos"])
			if e < dist:
				dist = e
				who = s[0]
				fast = float(s[1]) > FAST_MPS
	var state: int = h["state"]
	if state != S.RUN and (dist < FLEE_M or (fast and dist < FLEE_FAST_M)):
		_flee(h, who)
	elif state == S.GRAZE and dist < ALERT_M:
		h["state"] = S.ALERT
		h["alarm"] = r.randf_range(0.0, 0.6)
	elif state == S.ALERT and dist > ALERT_M + 15.0:
		h["state"] = S.GRAZE
	for d in h["deer"]:
		_step_deer(h, d, dt, who)
	if int(h["state"]) in [S.RUN, S.SETTLE]:
		var all_still := true
		for d in h["deer"]:
			if int(d["state"]) in [S.RUN, S.SETTLE]:
				all_still = false
		if all_still:
			h["state"] = S.GRAZE
			h["home"] = h["to"]


## Off, all together: the way away from `who`, a couple of hundred metres, over dry ground.
func _flee(h: Dictionary, who: Vector3) -> void:
	var r: RandomNumberGenerator = h["r"]
	var home: Vector3 = h["home"]
	var away := Vector2(home.x - who.x, home.z - who.z)
	if away.length() < 0.1:
		away = Vector2(1.0, 0.0)
	away = away.normalized()
	var best := home
	var best_score := -INF
	for i in 9:
		var ang := (float(i) - 4.0) * 0.18 + r.randf_range(-0.05, 0.05)
		var dir := away.rotated(ang)
		var run := r.randf_range(float(RUN_TO[0]), float(RUN_TO[1]))
		var to := Vector3(home.x + dir.x * run, 0.0, home.z + dir.y * run)
		var ok := true
		for k in range(1, 5):
			var p := home.lerp(to, float(k) / 4.0)
			if provider != null and (provider.is_water(p.x, p.z) or provider.get_slope(p.x, p.z) > 0.8):
				ok = false
				break
		if not ok:
			continue
		# straight away is best; a wood's edge to stop at is better still
		var score := -absf(ang) + (0.6 if TreeCover.is_edge(to.x, to.z) else 0.0)
		if score > best_score:
			best_score = score
			best = to
	if best_score == -INF:
		best = home + Vector3(away.x, 0.0, away.y) * float(RUN_TO[0])
	best.y = _ground(best)
	h["to"] = best
	h["state"] = S.RUN
	var lead := home.direction_to(best)
	for d in h["deer"]:
		d["state"] = S.RUN
		# the one that saw you goes first, the rest a heartbeat after
		d["delay"] = r.randf_range(0.0, 0.45)
		var side := Vector3(-lead.z, 0.0, lead.x)
		var t := best + side * r.randf_range(-9.0, 9.0) + lead * r.randf_range(-8.0, 8.0)
		d["target"] = t if _dry(t) else best


func _step_deer(h: Dictionary, d: Dictionary, dt: float, who: Vector3) -> void:
	var r: RandomNumberGenerator = h["r"]
	var herd_state: int = h["state"]
	var pos: Vector3 = d["pos"]
	var want_speed := 0.0
	var face := NAN
	match int(d["state"]):
		S.GRAZE, S.STEP, S.ALERT:
			if herd_state == S.ALERT:
				d["state"] = S.ALERT
				# heads up, turned to look at you, after a moment
				if float(h["alarm"]) > 0.0:
					h["alarm"] = float(h["alarm"]) - dt
				else:
					face = atan2(who.x - pos.x, who.z - pos.z)
			else:
				if int(d["state"]) == S.ALERT:
					d["state"] = S.GRAZE
					d["wait"] = r.randf_range(1.0, 4.0)
				d["wait"] = float(d["wait"]) - dt
				if int(d["state"]) == S.GRAZE and float(d["wait"]) <= 0.0:
					# a slow step on through the grass, head down
					var home: Vector3 = h["home"]
					var a := r.randf() * TAU
					var t := pos + Vector3(cos(a), 0.0, sin(a)) * r.randf_range(0.8, 3.0)
					if _flat(t, home) > GRAZE_R or not _dry(t):
						t = pos.lerp(home, 0.3)
					d["target"] = t
					d["state"] = S.STEP
				if int(d["state"]) == S.STEP:
					want_speed = STEP_MPS
					if _flat(pos, d["target"]) < 0.15:
						d["state"] = S.GRAZE
						d["wait"] = r.randf_range(3.0, 12.0)
						want_speed = 0.0
		S.RUN:
			if float(d["delay"]) > 0.0:
				d["delay"] = float(d["delay"]) - dt
				face = atan2(who.x - pos.x, who.z - pos.z)
			else:
				want_speed = RUN_MPS * float(d["pace"])
				if _flat(pos, d["target"]) < 30.0:
					d["state"] = S.SETTLE
		S.SETTLE:
			var left := _flat(pos, d["target"])
			want_speed = TROT_MPS if left > 10.0 else WALK_MPS
			if left < 0.5:
				d["state"] = S.GRAZE
				d["wait"] = r.randf_range(2.0, 6.0)
				want_speed = 0.0
	# speed eases, as a body's does: quick to go, slower to pull up
	var sp := float(d["speed"])
	var rate := 14.0 if want_speed > sp else 6.0
	sp = move_toward(sp, want_speed, rate * dt)
	d["speed"] = sp
	var yaw := float(d["yaw"])
	var old := yaw
	if sp > 0.01:
		var to: Vector3 = d["target"]
		var want := atan2(to.x - pos.x, to.z - pos.z)
		var turn := 4.0 if sp > 2.0 else 1.6
		yaw = yaw + clampf(wrapf(want - yaw, -PI, PI), -turn * dt, turn * dt)
		var step := Vector3(sin(yaw), 0.0, cos(yaw)) * minf(sp * dt, _flat(pos, to) + 0.01)
		pos += step
		pos.y = _ground(pos)
		d["pos"] = pos
	elif not is_nan(face):
		yaw = yaw + clampf(wrapf(face - yaw, -PI, PI), -1.5 * dt, 1.5 * dt)
	d["yaw"] = yaw
	d["turn"] = wrapf(yaw - old, -PI, PI) / maxf(dt, 0.001)


# --- drawing --------------------------------------------------------------------------------

func _draw() -> void:
	# the nearest deer in reach get the forge's rigged model; the rest are the far herd's
	var all: Array = []
	for h in herds:
		for d in h["deer"]:
			all.append(d)
	var near: Array = []
	for d in all:
		var e := (d["pos"] as Vector3).distance_to(_eye)
		if e <= NEAR_M:
			near.append([e, d])
	near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	var want := {}
	if ResourceLoader.exists(MODEL):
		for k in mini(near.size(), MAX_LIVE):
			want[int((near[k][1] as Dictionary)["id"])] = near[k][1]
	for id in _live.keys():
		if not want.has(id):
			(_live[id] as Node).queue_free()
			_live.erase(id)
	for id in want:
		var d: Dictionary = want[id]
		var m: HorseModel = _live.get(id, null)
		if m == null:
			m = HorseModel.new()
			m.model_path = MODEL
			m.antlers = bool(d["stag"])
			m.name = "Deer_%d" % int(id)
			add_child(m)
			_live[id] = m
		m.transform = Transform3D(Basis(Vector3.UP, float(d["yaw"])).scaled(Vector3.ONE * float(d["size"])),
				(d["pos"] as Vector3))
		var st: int = d["state"]
		var gait := "Walk"
		if st == S.STEP:
			gait = "Graze_Step"
		elif float(d["speed"]) > 6.0:
			gait = "Run"
		elif float(d["speed"]) > 2.0:
			gait = "Trot"
		# a smaller beast takes more strides to the metre
		m.set_motion(float(d["speed"]) / float(d["size"]), float(d["turn"]), gait)
		m.standing_clip = "Alert" if (st == S.ALERT or (st == S.RUN and float(d["speed"]) < 0.3)) else ""
		m.grazing = st == S.GRAZE
	var box := AABB(Vector3(_eye.x - KEEP_M, -200.0, _eye.z - KEEP_M), Vector3(KEEP_M * 2.0, 1400.0, KEEP_M * 2.0))
	for kind in _far:
		var mm: MultiMesh = _far[kind]
		var list: Array = []
		for d in all:
			if bool(d["stag"]) == (kind == "stag") and not want.has(int(d["id"])):
				list.append(d)
		if mm.instance_count < list.size():
			mm.instance_count = maxi(list.size(), mm.instance_count * 2)
		mm.visible_instance_count = list.size()
		(_far_inst[kind] as MultiMeshInstance3D).custom_aabb = box
		(_far_inst[kind] as MultiMeshInstance3D).visible = not list.is_empty()
		for i in list.size():
			var d: Dictionary = list[i]
			var s := float(d["size"])
			var at: Vector3 = d["pos"]
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, float(d["yaw"])).scaled(Vector3.ONE * s),
					at + Vector3(0.0, float(_far_lift[kind]) * s, 0.0)))
			mm.set_instance_color(i, Color.WHITE)
			var sp := float(d["speed"])
			var st: int = d["state"]
			# x its phase, y walking, z grazing, w how fast the legs go against the walk's
			mm.set_instance_custom_data(i, Color(float(d["phase"]), 1.0 if sp > 0.2 else 0.0,
					1.0 if st in [S.GRAZE, S.STEP] else 0.0, clampf(sp / WALK_MPS, 0.3, 2.6) if sp > 0.2 else 1.0))


func _let_go(d: Dictionary) -> void:
	var id := int(d["id"])
	if _live.has(id):
		(_live[id] as Node).queue_free()
		_live.erase(id)


# --- for tests and the console ------------------------------------------------------------------

func count(stags := false) -> int:
	var n := 0
	for h in herds:
		for d in h["deer"]:
			if not stags or bool(d["stag"]):
				n += 1
	return n


func live_count() -> int:
	return _live.size()


func live_models() -> Array:
	return _live.values()


func multimesh_of(kind: String) -> MultiMesh:
	return _far.get(kind, null)


func state_name(d: Dictionary) -> String:
	return S.keys()[int(d["state"])]
