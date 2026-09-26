class_name Wildlife
extends Node3D
## The wild things between the places: herons in the shallows, ducks and swans on still water,
## gulls over the Mere and the sea, crows over the Vale's fields, ravens over Skerrow's crags and
## Cinderlea's ash, and fish rising. The playtest found the country "empty between places"; the
## places have their people and their beasts, and this is what lives in the rest of it.
##
## They are there because the country is: every flock is put where the runtime maps say its kind
## lives (the water and its level, the shore's class, the region, the lie of the ground), the same
## flock in the same place on every visit. And they know you are there: a heron you walk up on
## lifts off and flaps away low to another stretch of shore, ducks go up all at once and circle
## before they come down on the water farther off, swans paddle away and keep their distance,
## crows go up off a field, wheel over it and settle again once you are past.
##
## The country is cut into cells `CELL_M` across; those round the eye within `LIVE_M` are surveyed
## (a few a frame, from the maps already in memory) and peopled, and those that fall out of it are
## emptied. Every kind is one MultiMesh for the whole country, a flock's pose drawn by the wildlife
## shader from its instance data, so a kind is one draw however many flocks are out: with every kind
## present, eight draws. How many flocks there are is the graphics setting `wildlife` (0 is none).
##
## A MultiMesh with no mesh AABB to go on (a headless run has none) is culled by the custom AABB
## this gives it: the ring round the eye, the height of the country.

signal put_up(kind: String, at: Vector3)

const CELL_M := 128.0
## A cell whose centre is within this of the eye is peopled.
const LIVE_M := 480.0
## How many cells are surveyed and peopled in a frame; the rest wait their turn.
const SURVEYS_PER_FRAME := 3
## Past this, a bird on the ground or the water is not drawn: at 600 px across a 55° view, a duck
## this far off is two pixels. A bird in the air is drawn to the edge of the ring.
const SITTING_SEEN_M := 300.0
## A spooked bird never lands nearer than this to what spooked it.
const CLEAR_M := 45.0

enum State { SIT, AIR }

## Each kind: how it lives (`habit`), how many to a flock, how near you may come before it goes,
## how fast it flies and how high, and the region it is found in and how often, per cell that has
## its ground. `still` asks for still water (a lake, the sea, a slow reach).
const KINDS := {
	"heron": {"habit": "wader", "flock": [1, 1], "flush_m": 34.0, "speed": 6.0, "cruise": [4.0, 9.0],
			"where": {"core:region/sedgemire": 0.15, "core:region/brightwater": 0.08, "core:region/hearthvale": 0.08,
					"core:region/briarwold": 0.06, "core:region/skerrow": 0.03}},
	"duck": {"habit": "swimmer", "flock": [3, 7], "flush_m": 22.0, "speed": 13.0, "cruise": [10.0, 22.0],
			"where": {"core:region/sedgemire": 0.3, "core:region/brightwater": 0.2, "core:region/hearthvale": 0.25,
					"core:region/briarwold": 0.15, "core:region/skerrow": 0.08}},
	"swan": {"habit": "shy", "flock": [2, 2], "flush_m": 26.0, "speed": 0.7, "cruise": [0.0, 0.0],
			"where": {"core:region/brightwater": 0.1, "core:region/hearthvale": 0.1, "core:region/sedgemire": 0.08}},
	"gull": {"habit": "wheeler", "flock": [4, 9], "flush_m": 20.0, "speed": 8.5, "cruise": [9.0, 26.0],
			"where": {"core:region/brightwater": 0.12, "core:region/sedgemire": 0.12, "core:region/skerrow": 0.18,
					"core:region/hearthvale": 0.05, "core:region/briarwold": 0.05, "core:region/cinderlea": 0.03}},
	"crow": {"habit": "gleaner", "flock": [6, 13], "flush_m": 26.0, "speed": 9.0, "cruise": [10.0, 20.0],
			"where": {"core:region/hearthvale": 0.1, "core:region/brightwater": 0.05, "core:region/briarwold": 0.04}},
	"raven": {"habit": "soarer", "flock": [1, 2], "flush_m": 0.0, "speed": 7.5, "cruise": [35.0, 70.0],
			"where": {"core:region/skerrow": 0.06, "core:region/cinderlea": 0.035}},
}
## How often a kind is found is per cell with its ground, measured round the Sedgemire and the Mere
## at the default setting: a heron to about every 250 m of reedy shore, a few flocks of gulls over
## open water, not the eighty gulls and nineteen herons in a kilometre the first numbers put out.
## Rises a cell of still water keeps going at once, per 1.0 of the setting.
const RISES_PER_CELL := 1
const RISE_SECONDS := 3.2
## Where fish rise: not the salt sea, nor the ash's water, nor a fast beck.
const RISE_REGIONS := ["core:region/hearthvale", "core:region/brightwater", "core:region/sedgemire",
		"core:region/briarwold", "core:region/skerrow"]

var provider: TerrainProvider = null
## The share of the flocks the country could hold that are put out (the `wildlife` setting).
var density := 1.0
## What counts as somebody coming near: the nodes in this group, or the eye if there are none.
var spooked_by := "player"
## A test turns the clock off: night then never falls on the flocks.
var use_clock := true

var flocks: Array[Dictionary] = []
var _rises: Array[Dictionary] = []
var _cells: Dictionary = {}          # Vector2i -> the survey of that cell ({} while unsurveyed)
var _live: Dictionary = {}           # Vector2i -> true, cells peopled
var _queue: Array[Vector2i] = []
var _mm: Dictionary = {}             # kind -> MultiMesh
var _inst: Dictionary = {}           # kind -> MultiMeshInstance3D
## Where each kind's birds were last put in its MultiMesh (a headless renderer keeps no instance
## data to read back, so this is what a test reads).
var drawn: Dictionary = {}
var _rings: MultiMesh = null
var _rings_inst: MultiMeshInstance3D = null
var _shore: PackedByteArray = PackedByteArray()
var _still_levels: Array[float] = []
## The places, as [x, z, radius]: nothing wild is put down in a street or a yard (a town's gulls
## excepted), where 114 crows stood about Merrowby.
var _places: Array = []
var _eye := Vector3.ZERO
var _streamed_at := Vector3.ZERO
var _started_stream := false
var _time := 0.0
var _started := false


func _ready() -> void:
	add_to_group("wildlife")
	density = float(Settings.get_value("graphics", "wildlife", 1.0))
	if not Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.connect(_on_setting_changed)
	_build_draws()


func _exit_tree() -> void:
	if Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.disconnect(_on_setting_changed)


func _on_setting_changed(section: String, key: String, value: Variant) -> void:
	if section == "graphics" and key == "wildlife":
		set_density(float(value))


## A new share of the flocks: every cell is peopled again from its survey.
func set_density(d: float) -> void:
	density = maxf(d, 0.0)
	for cell in _live.keys():
		_empty(cell)
	_live.clear()
	_queue.clear()
	_started_stream = false


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null or provider == null:
		return
	update(cam.global_position, delta)


## Moves the country's wild things on by `delta` seconds, the eye at `eye`.
func update(eye: Vector3, delta: float) -> void:
	_eye = eye
	_time += delta
	if not _started:
		_start()
	_stream(eye)
	var near := _spookers(eye)
	for f in flocks:
		_step_flock(f, delta, near)
	_step_rises(delta)
	_draw_all()


# --- the maps -------------------------------------------------------------------------------

func _start() -> void:
	_started = true
	if provider == null:
		return
	var rt: Dictionary = provider.manifest.get("runtime", {})
	var path := "%s/%s" % [TerrainProvider.GENERATED, rt.get("shore", "")]
	if FileAccess.file_exists(path):
		_shore = FileAccess.get_file_as_bytes(path)
	var pois_path := "%s/pois.json" % TerrainProvider.GENERATED
	if FileAccess.file_exists(pois_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(pois_path))
		if parsed is Array:
			for e in parsed:
				if e is Dictionary and (e as Dictionary).has("pos"):
					var at: Array = e["pos"]
					_places.append([float(at[0]), float(at[2]), float(e.get("radius_flat_m", 25.0)) + 40.0])
	_still_levels = [provider.sea_level]
	for lake in provider.manifest.get("lakes", []):
		_still_levels.append(float((lake as Dictionary).get("level_m", 0.0)))


func _wet(x: float, z: float) -> bool:
	return provider.is_water(x, z)


## What a cell has for each kind: the shore a heron would stand on, water near the shore for ducks,
## open water, open ground for crows, crags. Points in world space, read straight off the runtime
## maps (a cell is 16 by 16 of their texels at 8 m), so a survey costs a fraction of a millisecond.
func survey(cell: Vector2i) -> Dictionary:
	if _cells.has(cell):
		return _cells[cell]
	var out := {"shore": [], "reeds": [], "near_water": [], "open_water": [], "field": [], "crag": [],
			"sea": false, "region": "", "wet": 0}
	var g := provider.runtime_grid()
	var s := provider.runtime_spacing()
	var water := provider.runtime_water()
	var heights := provider.runtime_heights()
	var levels := provider.runtime_levels()
	var regions_map := provider.runtime_regions()
	if water.size() < g * g or heights.size() < g * g or levels.size() < g * g:
		_cells[cell] = out
		return out
	var ix0 := int(round((float(cell.x) * CELL_M - provider.origin.x) / s))
	var iz0 := int(round((float(cell.y) * CELL_M - provider.origin.y) / s))
	var n := int(CELL_M / s)
	var regions := {}
	for iz in range(maxi(iz0, 3), mini(iz0 + n, g - 3)):
		for ix in range(maxi(ix0, 3), mini(ix0 + n, g - 3)):
			var i := iz * g + ix
			var x := provider.origin.x + float(ix) * s
			var z := provider.origin.y + float(iz) * s
			var rv := int(regions_map[i]) if regions_map.size() > i else 255
			if rv < provider.region_ids.size():
				regions[rv] = int(regions.get(rv, 0)) + 1
			var water_near := int(water[i - 1] != 0) + int(water[i + 1] != 0) + int(water[i - g] != 0) + int(water[i + g] != 0)
			if water[i] != 0:
				out["wet"] = int(out["wet"]) + 1
				var l := levels[i]
				var still := maxf(absf(levels[i + 1] - levels[i - 1]), absf(levels[i + g] - levels[i - g])) < 0.06
				for sl in _still_levels:
					if absf(l - sl) < 0.3:
						still = true
				if not still:
					continue
				if absf(l - provider.sea_level) < 0.3:
					out["sea"] = true
				if water_near < 4:
					continue
				var open := water[i - 3] != 0 and water[i + 3] != 0 and water[i - 3 * g] != 0 and water[i + 3 * g] != 0
				(out["open_water" if open else "near_water"] as Array).append(Vector3(x, l, z))
			else:
				var h := heights[i]
				var grad := maxf(absf(heights[i + 1] - heights[i - 1]), absf(heights[i + g] - heights[i - g])) / (2.0 * s)
				if water_near > 0 and grad < 0.35:
					var cls := int(_shore[i]) if _shore.size() > i else 0
					if cls == 4:
						continue
					# a heron stands at the edge, a step toward the water from the last dry texel
					var into := Vector3(float(water[i + 1] != 0) - float(water[i - 1] != 0), 0.0,
							float(water[i + g] != 0) - float(water[i - g] != 0))
					var at := Vector3(x, h, z) + (into.normalized() * s * 0.45 if into.length() > 0.1 else Vector3.ZERO)
					# its feet on the bed or a hand under the water, whichever is higher
					at.y = maxf(provider.sample_height(at.x, at.z), levels[i] - 0.12)
					(out["reeds" if cls == 6 or cls == 5 else "shore"] as Array).append(at)
				elif water_near == 0 and grad < 0.2:
					(out["field"] as Array).append(Vector3(x, h, z))
				elif grad > 0.6:
					(out["crag"] as Array).append(Vector3(x, h, z))
	var best := 0
	for rv in regions:
		if int(regions[rv]) > best:
			best = int(regions[rv])
			out["region"] = provider.region_ids[int(rv)]
	if str(out["region"]) == "":
		out["region"] = provider.nearest_region_id_at((float(cell.x) + 0.5) * CELL_M, (float(cell.y) + 0.5) * CELL_M)
	_cells[cell] = out
	return out


# --- streaming ------------------------------------------------------------------------------

func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL_M), floori(p.z / CELL_M))


func _stream(eye: Vector3) -> void:
	# the ring is worked out again when the eye has moved a little, or while cells wait their turn
	if _queue.is_empty() and Vector2(eye.x - _streamed_at.x, eye.z - _streamed_at.z).length() < 16.0 and _started_stream:
		return
	_started_stream = true
	_streamed_at = eye
	var here := cell_of(eye)
	var ring_at := Vector2(eye.x, eye.z)
	var reach := int(ceil(LIVE_M / CELL_M))
	var want := {}
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var c := here + Vector2i(dx, dz)
			var centre := Vector2((float(c.x) + 0.5) * CELL_M, (float(c.y) + 0.5) * CELL_M)
			if centre.distance_to(ring_at) <= LIVE_M and provider.in_bounds(centre.x, centre.y):
				want[c] = true
	for c in _live.keys():
		if not want.has(c):
			_empty(c)
			_live.erase(c)
	_queue.clear()
	for c in want:
		if not _live.has(c):
			_queue.append(c)
	# nearest first
	_queue.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Vector2(a - here).length_squared() < Vector2(b - here).length_squared())
	var done := mini(SURVEYS_PER_FRAME, _queue.size())
	for i in done:
		_people(_queue[i])
		_live[_queue[i]] = true
	_queue = _queue.slice(done)


## Everything a surveyed cell holds, put out: the same flocks on every visit.
func _people(cell: Vector2i) -> void:
	if density <= 0.0:
		return
	var sv := survey(cell)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(cell.x, cell.y, 7919))
	var region := str(sv["region"])
	var night := _night()
	# the places that reach into this cell: usually none, a town's worth at most
	var near_places: Array = []
	var c := Vector2((float(cell.x) + 0.5) * CELL_M, (float(cell.y) + 0.5) * CELL_M)
	for pl in _places:
		if Vector2(float(pl[0]), float(pl[1])).distance_to(c) < float(pl[2]) + CELL_M * 0.72:
			near_places.append(pl)
	for kind in KINDS:
		var k: Dictionary = KINDS[kind]
		var chance := float((k["where"] as Dictionary).get(region, 0.0)) * density
		var roll := rng.randf()
		var spots := _spots_for(kind, sv)
		if spots.is_empty() or roll >= chance:
			continue
		if str(k["habit"]) == "soarer" and night:
			continue
		if kind != "gull":
			spots = _away_from_places(spots, near_places)
			if spots.is_empty():
				continue
		_add_flock(kind, cell, spots, rng, night)
	# fish rising: on still water away from the salt, a few rises going at once
	if region in RISE_REGIONS and not bool(sv["sea"]):
		var water: Array = (sv["near_water"] as Array) + (sv["open_water"] as Array)
		if not water.is_empty():
			var going := int(round(float(RISES_PER_CELL) * density * minf(1.0, float(water.size()) / 40.0)))
			for i in going:
				_rises.append({"cell": cell, "spots": water, "t": rng.randf() * RISE_SECONDS * 3.0 - RISE_SECONDS * 2.0,
						"at": water[rng.randi() % water.size()], "size": rng.randf_range(0.7, 1.5),
						"rng": rng.randi()})


func _spots_for(kind: String, sv: Dictionary) -> Array:
	match kind:
		"heron":
			return (sv["reeds"] as Array) + (sv["shore"] as Array) if not (sv["reeds"] as Array).is_empty() else sv["shore"]
		"duck", "swan":
			return sv["near_water"] if (sv["near_water"] as Array).size() >= 4 else []
		"gull":
			return (sv["near_water"] as Array) + (sv["open_water"] as Array) + (sv["shore"] as Array) \
					if (int(sv["wet"]) >= 24) else []
		"crow":
			return sv["field"] if (sv["field"] as Array).size() >= 40 else []
		"raven":
			return (sv["crag"] as Array) + (sv["field"] as Array) if (sv["crag"] as Array).size() >= 8 \
					or str(sv["region"]) == "core:region/cinderlea" else []
	return []


func _away_from_places(spots: Array, places: Array) -> Array:
	if places.is_empty():
		return spots
	var out: Array = []
	for s in spots:
		var p: Vector3 = s
		var clear := true
		for pl in places:
			var dx := p.x - float(pl[0])
			var dz := p.z - float(pl[1])
			if dx * dx + dz * dz < float(pl[2]) * float(pl[2]):
				clear = false
				break
		if clear:
			out.append(p)
	return out


func _add_flock(kind: String, cell: Vector2i, spots: Array, rng: RandomNumberGenerator, night: bool) -> void:
	var k: Dictionary = KINDS[kind]
	var span: Array = k["flock"]
	var n := rng.randi_range(int(span[0]), int(span[1]))
	var home: Vector3 = spots[rng.randi() % spots.size()]
	var habit := str(k["habit"])
	var cruise: Array = k["cruise"]
	var f := {"kind": kind, "habit": habit, "cell": cell, "spots": spots, "home": home, "birds": [],
			"rng": rng.randi(), "height": rng.randf_range(float(cruise[0]), float(cruise[1])),
			"radius": rng.randf_range(18.0, 40.0) if habit != "soarer" else rng.randf_range(50.0, 110.0),
			"t": 0.0, "until": 0.0, "wander": 0.0}
	var r := RandomNumberGenerator.new()
	r.seed = int(f["rng"])
	f["r"] = r
	for i in n:
		var b := {"pos": home, "vel": Vector3.ZERO, "yaw": r.randf() * TAU, "bank": 0.0, "pitch": 0.0,
				"state": State.SIT, "phase": r.randf(), "beat": 0.0, "open": 0.0, "tuck": 0.0,
				"goal": Vector3.ZERO, "landing": false, "t": r.randf() * 4.0, "next": r.randf_range(2.0, 8.0),
				"target": home, "delay": 0.0, "angle": r.randf() * TAU, "glide": r.randf() * 6.0}
		match habit:
			"swimmer", "shy":
				b["pos"] = _water_near(home, 6.0, r)
			"gleaner":
				b["pos"] = _ground_near(home, 10.0, r)
			"wader":
				b["pos"] = home
			"wheeler":
				# most of a flock of gulls in the air by day, some sat on the water; all sat at night
				if not night and r.randf() < 0.65:
					_launch_to_wheel(f, b, false)
					b["pos"] = _on_wheel(f, b)
				else:
					b["pos"] = _water_near(home, 10.0, r) if _wet(home.x, home.z) else home
			"soarer":
				_launch_to_wheel(f, b, false)
				b["pos"] = _on_wheel(f, b)
		b["target"] = b["pos"]
		(f["birds"] as Array).append(b)
	flocks.append(f)


func _empty(cell: Vector2i) -> void:
	var kept: Array[Dictionary] = []
	for f in flocks:
		if f["cell"] != cell:
			kept.append(f)
	flocks = kept
	var kept_rises: Array[Dictionary] = []
	for r in _rises:
		if r["cell"] != cell:
			kept_rises.append(r)
	_rises = kept_rises


# --- behaviour ------------------------------------------------------------------------------

func _night() -> bool:
	return use_clock and WorldClock.is_night()


func _spookers(eye: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if is_inside_tree():
		for n in get_tree().get_nodes_in_group(spooked_by):
			if n is Node3D:
				out.append((n as Node3D).global_position)
	if out.is_empty() and spooked_by == "player":
		out.append(eye)
	return out


static func _nearest(at: Vector3, bodies: Array[Vector3]) -> Vector3:
	var best := Vector3(INF, INF, INF)
	var bd := INF
	for p in bodies:
		var d := Vector2(p.x - at.x, p.z - at.z).length_squared()
		if d < bd:
			bd = d
			best = p
	return best


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _step_flock(f: Dictionary, dt: float, near: Array[Vector3]) -> void:
	var k: Dictionary = KINDS[f["kind"]]
	var r: RandomNumberGenerator = f["r"]
	var habit := str(f["habit"])
	var flush := float(k["flush_m"])
	f["t"] = float(f["t"]) + dt
	var night := _night()
	# a flock that is put up goes up together: the first to see you calls the rest
	var spooked := false
	for b in f["birds"]:
		if int(b["state"]) == State.SIT and flush > 0.0:
			var who := _nearest(b["pos"], near)
			if _flat(who, b["pos"]) < flush:
				spooked = true
	if spooked and habit != "shy":
		var who := _nearest(f["home"], near)
		_put_up(f, who)
	for b in f["birds"]:
		var bird: Dictionary = b
		bird["t"] = float(bird["t"]) + dt
		if float(bird["delay"]) > 0.0:
			bird["delay"] = float(bird["delay"]) - dt
			_sit_still(f, bird, dt)
			continue
		if int(bird["state"]) == State.SIT:
			match habit:
				"wader":
					_stand(f, bird, dt, r)
				"swimmer", "shy":
					_paddle(f, bird, dt, r, near, habit == "shy")
				"gleaner":
					_glean(f, bird, dt, r)
				"wheeler":
					_sit_still(f, bird, dt)
					# a gull sat on the water goes up again after a while, by day
					if not night and float(bird["t"]) > float(bird["next"]) + 25.0 and r.randf() < dt * 0.05:
						_launch_to_wheel(f, bird, true)
				_:
					_sit_still(f, bird, dt)
		else:
			_fly(f, bird, dt, r, near, night)


func _put_up(f: Dictionary, who: Vector3) -> void:
	var r: RandomNumberGenerator = f["r"]
	var habit := str(f["habit"])
	var away := Vector3(f["home"].x - who.x, 0.0, f["home"].z - who.z)
	if away.length() < 0.1:
		away = Vector3(1.0, 0.0, 0.0)
	away = away.normalized()
	var any := false
	for b in f["birds"]:
		if int(b["state"]) != State.SIT:
			continue
		any = true
		b["state"] = State.AIR
		b["landing"] = false
		b["t"] = 0.0
		b["delay"] = r.randf_range(0.0, 0.5) if habit in ["swimmer", "gleaner", "wheeler"] else 0.0
		var off := Vector3(b["pos"].x - who.x, 0.0, b["pos"].z - who.z).normalized()
		if off.length() < 0.1:
			off = away
		b["vel"] = (off * 0.6 + away * 0.4).normalized() * float(KINDS[f["kind"]]["speed"]) * 0.35 + Vector3(0.0, 2.5, 0.0)
		b["beat"] = 1.0
	if not any:
		return
	put_up.emit(str(f["kind"]), f["home"])
	match habit:
		"wader":
			# off low along the shore to another stretch of it, well away from you
			var to := _spot_away(f, who, CLEAR_M + 20.0)
			for b in f["birds"]:
				b["goal"] = to
				b["landing"] = true
			f["home"] = to
		"swimmer", "gleaner":
			# up, a turn or two over somewhere else, then down there
			var to := _spot_away(f, who, CLEAR_M + 20.0)
			f["home"] = to
			f["until"] = float(f["t"]) + r.randf_range(10.0, 20.0)
			for b in f["birds"]:
				_launch_to_wheel(f, b, true)
				b["delay"] = r.randf_range(0.0, 0.5)
		"wheeler":
			for b in f["birds"]:
				if int(b["state"]) == State.AIR and not bool(b["landing"]):
					_launch_to_wheel(f, b, true)


## One of the places its kind would be, in the flock's cell or those round it, at least `min_m`
## from `who` and as far as can be found in a couple of dozen tries; or where it is.
func _spot_away(f: Dictionary, who: Vector3, min_m: float) -> Vector3:
	var r: RandomNumberGenerator = f["r"]
	var spots := _spots_around(f)
	var best: Vector3 = f["home"]
	var bd := _flat(best, who)
	for i in mini(32, spots.size()):
		var p: Vector3 = spots[r.randi() % spots.size()]
		var d := _flat(p, who)
		if d > bd:
			bd = d
			best = p
		if d > min_m * 1.5:
			break
	return best


## Every spot the flock's kind has in its own cell and the eight round it (surveyed as needed).
func _spots_around(f: Dictionary) -> Array:
	if f.has("around"):
		return f["around"]
	var out: Array = []
	var cell: Vector2i = f["cell"]
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			out.append_array(_spots_for(str(f["kind"]), survey(cell + Vector2i(dx, dz))))
	if out.is_empty():
		out = f["spots"]
	f["around"] = out
	return out


func _launch_to_wheel(f: Dictionary, b: Dictionary, from_ground: bool) -> void:
	b["state"] = State.AIR
	b["landing"] = false
	b["t"] = 0.0
	var off: Vector3 = (b["pos"] as Vector3) - (f["home"] as Vector3)
	b["angle"] = atan2(off.z, off.x) if off.length() > 0.5 else (f["r"] as RandomNumberGenerator).randf() * TAU
	b["reach"] = (f["r"] as RandomNumberGenerator).randf_range(0.7, 1.2)
	b["lift"] = (f["r"] as RandomNumberGenerator).randf_range(0.8, 1.2)
	b["spin"] = (f["r"] as RandomNumberGenerator).randf_range(0.8, 1.2) * (1.0 if (f["r"] as RandomNumberGenerator).randf() < 0.75 else -1.0)
	b["next"] = (f["r"] as RandomNumberGenerator).randf_range(20.0, 60.0)
	if from_ground:
		b["vel"] = Vector3(0.0, 2.5, 0.0) + ((b["vel"] as Vector3) if (b["vel"] as Vector3).length() > 0.1 else Vector3.ZERO)
		b["beat"] = 1.0


func _on_wheel(f: Dictionary, b: Dictionary) -> Vector3:
	var a := float(b["angle"])
	var rad := float(f["radius"]) * float(b.get("reach", 1.0))
	var home: Vector3 = f["home"]
	var c := Vector3(home.x + cos(a) * rad, 0.0, home.z + sin(a) * rad)
	var floor_y := maxf(_floor_at(c), _floor_at(home))
	var bob := sin(_time * 0.5 + float(b["phase"]) * 6.0) * 1.5
	c.y = floor_y + float(f["height"]) * float(b.get("lift", 1.0)) + bob
	return c


func _fly(f: Dictionary, b: Dictionary, dt: float, r: RandomNumberGenerator, near: Array[Vector3], night: bool) -> void:
	var k: Dictionary = KINDS[f["kind"]]
	var habit := str(f["habit"])
	var speed := float(k["speed"])
	var pos: Vector3 = b["pos"]
	var vel: Vector3 = b["vel"]
	var target: Vector3
	var landing := bool(b["landing"])
	var wheel_speed := speed / maxf(float(f["radius"]) * float(b.get("reach", 1.0)), 1.0)
	if not landing:
		# round the wheel; a flock that was put up comes down again once its time is up, somewhere
		# nobody is standing
		b["angle"] = float(b["angle"]) + wheel_speed * float(b.get("spin", 1.0)) * dt
		target = _on_wheel(f, b)
		var done := false
		match habit:
			"swimmer", "gleaner":
				done = float(f["t"]) > float(f["until"])
			"wheeler":
				done = float(b["t"]) > float(b["next"]) and (night or r.randf() < dt * 0.02)
		if done:
			var who := _nearest(f["home"], near)
			var spot := _landing_near(f, r)
			if _flat(spot, who) > CLEAR_M:
				b["goal"] = spot
				b["landing"] = true
				landing = true
			else:
				f["until"] = float(f["t"]) + r.randf_range(6.0, 12.0)
				b["next"] = float(b["t"]) + 10.0
	if landing:
		target = b["goal"]
		var dist := _flat(pos, target)
		# hold height until the last stretch, then come down to it
		var cruise_y := maxf(_floor_at(pos), target.y) + float(f["height"]) * 0.5
		if habit == "wader":
			cruise_y = maxf(_floor_at(pos), target.y) + 5.0
		var down := clampf(dist / 30.0, 0.0, 1.0)
		target = Vector3(target.x, lerpf(target.y, cruise_y, down), target.z)
	# steer: toward the target at the kind's speed, turning as a bird turns, not on a point; and on
	# the last few metres of a landing straight in, braking, or it circles its spot for ever
	var to := target - pos
	var slow := 1.0
	if landing:
		slow = clampf(to.length() / 12.0, 0.25, 1.0)
	var want := to.normalized() * speed * slow if to.length() > 0.01 else Vector3.ZERO
	var turn := 1.6 if habit != "soarer" else 0.8
	var nv := vel.lerp(want, clampf(turn * dt, 0.0, 1.0))
	if landing and _flat(pos, b["goal"]) < 8.0:
		var goal: Vector3 = b["goal"]
		var left := goal - pos
		if left.length() < 0.5:
			_land(f, b)
			return
		nv = left.normalized() * minf(maxf(1.2, speed * slow), left.length() / maxf(dt, 0.001))
	if b["t"] < 1.0 and habit != "soarer":
		nv.y = maxf(nv.y, 2.0 * (1.0 - float(b["t"])))
	var old_yaw := float(b["yaw"])
	pos += nv * dt
	var floor_y := _floor_at(pos)
	if not landing or _flat(pos, b["goal"]) > 3.0:
		pos.y = maxf(pos.y, floor_y + 1.0)
	b["pos"] = pos
	b["vel"] = nv
	if Vector2(nv.x, nv.z).length() > 0.2:
		b["yaw"] = atan2(nv.x, nv.z)
	var yaw_rate := wrapf(float(b["yaw"]) - old_yaw, -PI, PI) / maxf(dt, 0.001)
	b["bank"] = lerpf(float(b["bank"]), clampf(-yaw_rate * 0.5, -0.7, 0.7), clampf(dt * 3.0, 0.0, 1.0))
	b["pitch"] = lerpf(float(b["pitch"]), clampf(-nv.y / maxf(nv.length(), 0.1), -0.5, 0.5) * 0.6, clampf(dt * 3.0, 0.0, 1.0))
	# the wings: beating to climb or to get going, gliding in the turn or coming down; a gull and a
	# raven hang on still wings most of the time
	var climbing := nv.y > 0.4 or float(b["t"]) < 2.0
	var beat := 1.0
	match habit:
		"wheeler", "soarer":
			b["glide"] = float(b["glide"]) + dt
			var cycle := 7.0 if habit == "wheeler" else 12.0
			beat = 1.0 if climbing or fmod(float(b["glide"]), cycle) < (1.6 if habit == "wheeler" else 1.2) else 0.0
		"wader":
			beat = 1.0 if climbing or fmod(float(b["t"]) + float(b["phase"]) * 5.0, 6.0) < 4.5 else 0.0
		_:
			beat = 1.0 if climbing or nv.y > -0.8 else 0.0
	if landing and _flat(pos, b["goal"]) < 8.0:
		beat = 0.6
	b["beat"] = lerpf(float(b["beat"]), beat, clampf(dt * 4.0, 0.0, 1.0))
	b["open"] = move_toward(float(b["open"]), 1.0, dt * 3.0)
	# a heron draws its neck in and trails its legs once it is going
	var tuck := 1.0 if habit == "wader" and float(b["t"]) > 0.8 and not (landing and _flat(pos, b["goal"]) < 5.0) else 0.0
	b["tuck"] = move_toward(float(b["tuck"]), tuck, dt * 1.5)
	b["phase"] = float(b["phase"]) + dt * float(WildlifeMeshes.RIGS[f["kind"]]["hz"]) * (0.35 + 0.65 * float(b["beat"]))


func _land(f: Dictionary, b: Dictionary) -> void:
	b["state"] = State.SIT
	b["landing"] = false
	b["pos"] = b["goal"]
	b["vel"] = Vector3.ZERO
	b["t"] = 0.0
	b["bank"] = 0.0
	b["pitch"] = 0.0
	b["target"] = b["goal"]
	b["next"] = (f["r"] as RandomNumberGenerator).randf_range(2.0, 6.0)


## Where one of a flock that is coming down puts down: on the water near the home for ducks and
## gulls, on the field for crows.
func _landing_near(f: Dictionary, r: RandomNumberGenerator) -> Vector3:
	var home: Vector3 = f["home"]
	match str(f["habit"]):
		"swimmer", "shy":
			return _water_near(home, 8.0, r)
		"gleaner":
			return _ground_near(home, 12.0, r)
		"wheeler":
			return _water_near(home, 12.0, r) if _wet(home.x, home.z) else _ground_near(home, 6.0, r)
	return home


func _water_near(home: Vector3, radius: float, r: RandomNumberGenerator) -> Vector3:
	for i in 8:
		var a := r.randf() * TAU
		var d := sqrt(r.randf()) * radius
		var p := home + Vector3(cos(a) * d, 0.0, sin(a) * d)
		if _wet(p.x, p.z):
			p.y = provider.nearest_water_level(p.x, p.z)
			return p
	return Vector3(home.x, provider.nearest_water_level(home.x, home.z) if _wet(home.x, home.z) else _floor_at(home), home.z)


func _ground_near(home: Vector3, radius: float, r: RandomNumberGenerator) -> Vector3:
	for i in 8:
		var a := r.randf() * TAU
		var d := sqrt(r.randf()) * radius
		var p := home + Vector3(cos(a) * d, 0.0, sin(a) * d)
		if not _wet(p.x, p.z):
			p.y = provider.get_height(p.x, p.z)
			return p
	return Vector3(home.x, provider.get_height(home.x, home.z), home.z)


## The ground, or the water over it.
func _floor_at(p: Vector3) -> float:
	var g := provider.get_height(p.x, p.z)
	if _wet(p.x, p.z):
		return maxf(g, provider.nearest_water_level(p.x, p.z))
	return g


func _sit_still(f: Dictionary, b: Dictionary, dt: float) -> void:
	b["beat"] = move_toward(float(b["beat"]), 0.0, dt * 4.0)
	b["open"] = move_toward(float(b["open"]), 0.0, dt * 2.0)
	b["tuck"] = move_toward(float(b["tuck"]), 0.0, dt * 2.0)
	b["bank"] = lerpf(float(b["bank"]), 0.0, clampf(dt * 4.0, 0.0, 1.0))
	b["pitch"] = lerpf(float(b["pitch"]), 0.0, clampf(dt * 4.0, 0.0, 1.0))


## A heron in the shallows: still for a long while, then a slow step, or a turn to watch another
## piece of water.
func _stand(f: Dictionary, b: Dictionary, dt: float, r: RandomNumberGenerator) -> void:
	_sit_still(f, b, dt)
	if float(b["t"]) > float(b["next"]):
		b["t"] = 0.0
		b["next"] = r.randf_range(4.0, 14.0)
		b["yaw"] = float(b["yaw"]) + r.randf_range(-0.9, 0.9)


## Ducks and swans on the water: a slow paddle about the home, and (a swan) away from anybody who
## comes near, keeping its distance rather than going up.
func _paddle(f: Dictionary, b: Dictionary, dt: float, r: RandomNumberGenerator, near: Array[Vector3], shy: bool) -> void:
	_sit_still(f, b, dt)
	var pos: Vector3 = b["pos"]
	var speed := 0.25 if not shy else 0.35
	if shy:
		var who := _nearest(pos, near)
		if _flat(who, pos) < float(KINDS[f["kind"]]["flush_m"]):
			var away := Vector3(pos.x - who.x, 0.0, pos.z - who.z).normalized()
			var t := pos + away * 6.0
			if _wet(t.x, t.z):
				b["target"] = t
				speed = float(KINDS[f["kind"]]["speed"])
	var target: Vector3 = b["target"]
	var way := Vector3(target.x - pos.x, 0.0, target.z - pos.z)
	if way.length() < 0.2 or float(b["t"]) > float(b["next"]):
		b["t"] = 0.0
		b["next"] = r.randf_range(4.0, 12.0)
		b["target"] = _water_near(f["home"], 10.0, r)
		return
	var step := way.normalized() * speed * dt
	var np := pos + step
	if _wet(np.x, np.z):
		np.y = provider.nearest_water_level(np.x, np.z)
		b["pos"] = np
		b["yaw"] = lerp_angle(float(b["yaw"]), atan2(step.x, step.z), clampf(dt * 2.0, 0.0, 1.0))
	else:
		b["target"] = f["home"]


## Crows on a field: a hop or a short walk, a peck, a look round.
func _glean(f: Dictionary, b: Dictionary, dt: float, r: RandomNumberGenerator) -> void:
	_sit_still(f, b, dt)
	var pos: Vector3 = b["pos"]
	var target: Vector3 = b["target"]
	var way := Vector3(target.x - pos.x, 0.0, target.z - pos.z)
	if way.length() > 0.05:
		var step := way.normalized() * minf(way.length(), 0.9 * dt)
		pos += step
		pos.y = provider.get_height(pos.x, pos.z)
		b["pos"] = pos
		b["yaw"] = atan2(step.x, step.z)
		b["tuck"] = 0.0
	else:
		# pecking between the steps
		b["tuck"] = 0.5 + 0.5 * sin(float(b["t"]) * 7.0 + float(b["phase"]) * 6.0) if fmod(float(b["t"]), 3.0) < 1.6 else 0.0
	if float(b["t"]) > float(b["next"]):
		b["t"] = 0.0
		b["next"] = r.randf_range(1.5, 6.0)
		var a := r.randf() * TAU
		var t := pos + Vector3(cos(a), 0.0, sin(a)) * r.randf_range(0.3, 1.8)
		if _flat(t, f["home"]) < 14.0 and not _wet(t.x, t.z):
			b["target"] = t


func _step_rises(dt: float) -> void:
	for rise in _rises:
		rise["t"] = float(rise["t"]) + dt
		if float(rise["t"]) >= RISE_SECONDS:
			# the next rise: somewhere else on the same water, after a pause
			var r := RandomNumberGenerator.new()
			r.seed = int(rise["rng"])
			rise["rng"] = r.randi()
			var spots: Array = rise["spots"]
			var at: Vector3 = spots[r.randi() % spots.size()]
			rise["at"] = at + Vector3(r.randf_range(-3.0, 3.0), 0.0, r.randf_range(-3.0, 3.0))
			rise["size"] = r.randf_range(0.7, 1.6)
			rise["t"] = -r.randf_range(2.0, 9.0)


# --- drawing --------------------------------------------------------------------------------

func _build_draws() -> void:
	var shader := load("res://assets/shaders/wildlife.gdshader") as Shader
	for kind in KINDS:
		var mesh := WildlifeMeshes.mesh(kind)
		if mesh == null:
			continue
		var rig: Dictionary = WildlifeMeshes.RIGS[kind]
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("wing_root", rig["root"])
		mat.set_shader_parameter("fold_sweep", float(rig["sweep"]))
		mat.set_shader_parameter("neck_shift", rig["neck"])
		mat.set_shader_parameter("hip", rig["hip"])
		mat.set_shader_parameter("trail", deg_to_rad(float(rig["trail_deg"])))
		mat.set_shader_parameter("beat_amp", deg_to_rad(float(rig["flap_deg"])))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		# instance colours on as well, all white: on the Compatibility renderer a MultiMesh with custom
		# data and no colours drew its vertex colours as black, and every swan on the Mere was a
		# black swan
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = 0
		var inst := MultiMeshInstance3D.new()
		inst.name = kind.capitalize()
		inst.multimesh = mm
		inst.material_override = mat
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		inst.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(inst)
		_mm[kind] = mm
		_inst[kind] = inst
	var rings_shader := load("res://assets/shaders/water_rings.gdshader") as Shader
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	quad.orientation = PlaneMesh.FACE_Y
	var rmat := ShaderMaterial.new()
	rmat.shader = rings_shader
	rmat.render_priority = 2
	_rings = MultiMesh.new()
	_rings.transform_format = MultiMesh.TRANSFORM_3D
	_rings.use_colors = true
	_rings.use_custom_data = true
	_rings.mesh = quad
	_rings_inst = MultiMeshInstance3D.new()
	_rings_inst.name = "Rises"
	_rings_inst.multimesh = _rings
	_rings_inst.material_override = rmat
	_rings_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rings_inst.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_rings_inst)


## The flocks' birds into their kinds' MultiMeshes, and the rises into theirs; each culled by the
## ring round the eye.
func _draw_all() -> void:
	var box := AABB(Vector3(_eye.x - LIVE_M - 60.0, -100.0, _eye.z - LIVE_M - 60.0),
			Vector3((LIVE_M + 60.0) * 2.0, 1200.0, (LIVE_M + 60.0) * 2.0))
	var by_kind := {}
	for kind in _mm:
		by_kind[kind] = []
	for f in flocks:
		for b in f["birds"]:
			if int(b["state"]) == State.SIT and _flat(b["pos"], _eye) > SITTING_SEEN_M:
				continue
			(by_kind[f["kind"]] as Array).append(b)
	for kind in _mm:
		var mm: MultiMesh = _mm[kind]
		var list: Array = by_kind[kind]
		var draft := float(WildlifeMeshes.RIGS[kind]["draft"])
		if mm.instance_count < list.size():
			mm.instance_count = maxi(list.size(), mm.instance_count * 2)
		mm.visible_instance_count = list.size()
		(_inst[kind] as MultiMeshInstance3D).custom_aabb = box
		(_inst[kind] as MultiMeshInstance3D).visible = not list.is_empty()
		var at := PackedVector3Array()
		for i in list.size():
			var b: Dictionary = list[i]
			var xb := Basis.from_euler(Vector3(float(b["pitch"]), float(b["yaw"]), float(b["bank"])), EULER_ORDER_YXZ)
			var pos: Vector3 = b["pos"]
			if int(b["state"]) == State.SIT and draft > 0.0 and _wet(pos.x, pos.z):
				# a bird on the water sits in it, and rides it
				pos.y += sin(_time * 1.3 + float(b["phase"]) * 9.0) * 0.012 - draft
			mm.set_instance_transform(i, Transform3D(xb, pos))
			mm.set_instance_color(i, Color.WHITE)
			at.append(pos)
			mm.set_instance_custom_data(i, Color(fmod(float(b["phase"]), 1.0), float(b["beat"]), float(b["open"]), float(b["tuck"])))
		drawn[kind] = at
	var live: Array = []
	for rise in _rises:
		if float(rise["t"]) >= 0.0 and _flat(rise["at"], _eye) < SITTING_SEEN_M * 0.6:
			live.append(rise)
	if _rings.instance_count < live.size():
		_rings.instance_count = maxi(live.size(), _rings.instance_count * 2)
	_rings.visible_instance_count = live.size()
	_rings_inst.custom_aabb = box
	_rings_inst.visible = not live.is_empty()
	for i in live.size():
		var rise: Dictionary = live[i]
		var at: Vector3 = rise["at"]
		var s := 3.2 * float(rise["size"])
		_rings.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, 1.0, s)), at + Vector3(0.0, 0.03, 0.0)))
		_rings.set_instance_color(i, Color.WHITE)
		_rings.set_instance_custom_data(i, Color(float(rise["t"]) / RISE_SECONDS, float(rise["size"]), 0.0, 0.0))


# --- for tests and the console ------------------------------------------------------------------

func count(kind := "") -> int:
	var n := 0
	for f in flocks:
		if kind == "" or f["kind"] == kind:
			n += (f["birds"] as Array).size()
	return n


func flocks_of(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f in flocks:
		if f["kind"] == kind:
			out.append(f)
	return out


## Every cell in the ring has been surveyed and peopled.
func settled() -> bool:
	return _started_stream and _queue.is_empty()


func rises() -> int:
	return _rises.size()


func multimesh_of(kind: String) -> MultiMesh:
	return _mm.get(kind, null)


func instance_of(kind: String) -> MultiMeshInstance3D:
	return _inst.get(kind, null)
