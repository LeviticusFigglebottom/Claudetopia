class_name SitePlan
extends RefCounted
## The layout of a large site's inside, worked out from its def before anything is built: rooms with
## where they stand and how high, the passages joining them (a loop, a secret, a shortcut back out),
## the rock carved and filled to make them (`ops`, which SiteField meshes), and every set-piece,
## light, container, foe and feature the dressing stands up (SiteDress). Pure data, deterministic from
## the def's `site.seed`: the same def is the same place on every machine and every visit, and a test
## can walk it without building a mesh.
##
## Coordinates are the interior's own: the entrance room's floor centre is the origin, +y up.
##
## The walk is laid as a descending spiral (every turn the same way, each room a little lower), so
## the rooms come back round near the way in, which is what makes a loop and a short way back out
## possible without either crossing another room. See docs/WORLD_LIFE_INTERIORS.md for the data.

const ROLES := ["entrance", "chamber", "passage", "camp", "treasure", "shrine", "hall", "boss", "secret", "bypass"]
## A corridor's floor may climb this much per metre it runs (about 27 degrees).
const MAX_SLOPE := 0.5
## Rooms stacked over one another are apart when this much rock lies between roof and floor.
const STACK_GAP := 3.0
## How far past its wall a doorway's mouth stands inside a room.
const MOUTH_IN := 1.0
const ATTEMPTS := 28

var id := ""
var name := ""
var kind := ""
var spec: Dictionary = {}
var site_seed := 1
var region := "hearthvale"
var danger := 2
var rooms: Array = []            # Array of room Dictionaries (see _room)
var links: Array = []            # Array of link Dictionaries (see _link)
var ops: Array = []              # carve/fill primitives, in order (SiteField)
var encounters: Array = []       # {room, enemy, count, role, spots, patrol}
var containers: Array = []       # {room, at, yaw, tier, table, id, prop}
var features: Array = []         # authored features placed: {kind, room, at, yaw, ...}
var problems: Array[String] = []
var bounds := AABB()
var entrance := Vector3.ZERO
var entrance_yaw := 0.0
var exit_at := Vector3.ZERO
var exit_yaw := 0.0
## Where the day shows at the end of a rock site's way out (INF for a built one's door).
var exit_glow := Vector3.INF

var _rng := RandomNumberGenerator.new()
var _by_id: Dictionary = {}
var _site: Dictionary = {}


## The plan for an interior def (its `site` block). Never fails: what cannot be laid is noted in
## `problems` and left out.
static func make(def: Dictionary) -> SitePlan:
	var p := SitePlan.new()
	p._make(def)
	return p


func room(room_id: String) -> Dictionary:
	return _by_id.get(room_id, {})


func _make(def: Dictionary) -> void:
	id = str(def.get("id", "core:interior/site"))
	name = str(def.get("name", Ids.name_of(id).capitalize()))
	_site = def.get("site", {})
	kind = str(_site.get("kind", "cave"))
	spec = SiteKinds.of(kind, _site.get("theme", {}))
	site_seed = int(_site.get("seed", abs(id.hash()) % 100000))
	_rng.seed = site_seed
	danger = int(def.get("danger", _site.get("danger", 2)))
	var reg := str(_site.get("region", ""))
	if reg == "":
		var place := str(def.get("place", ""))
		if place != "" and ContentDB.has(place):
			reg = str(ContentDB.get_def(place).get("region", ""))
	region = Ids.name_of(reg) if reg.contains("/") else (reg if reg != "" else "hearthvale")
	var wanted := _room_list()
	_lay_main(wanted)
	_lay_loop()
	if bool(_site.get("drops", true)):
		_lay_drop()
	_lay_secret()
	_lay_shortcut()
	for r in rooms:
		_room_ops(r)
	for l in links:
		_link_ops(l)
	for r in rooms:
		_set_piece(r)
	_mark_entrance()
	_spots()
	_people()
	_loot()
	_features()
	_bounds()


# --- the rooms wanted -------------------------------------------------------------------------------

## The rooms in the order they are walked: the def's own `rooms`, or ones made from the kind (an
## entrance, chambers with the kind's set-pieces spread among them, a hall, the boss).
func _room_list() -> Array:
	var authored: Array = _site.get("rooms", [])
	if not authored.is_empty():
		var copied: Array = []
		for r in authored:
			copied.append((r as Dictionary).duplicate(true))
		return copied
	var count := int(_site.get("rooms_count", SiteKinds.ROOM_COUNTS.get(str(_site.get("size", "medium")), 7)))
	var pool: Array = (spec.get("set_pieces", []) as Array).duplicate()
	var wanted_pieces: Array = _site.get("set_pieces", [])
	var pieces: Array = wanted_pieces.duplicate() if not wanted_pieces.is_empty() else []
	if pieces.is_empty():
		for i in maxi(1, floori(count / 3.0)):
			if pool.is_empty():
				break
			pieces.append(pool.pop_at(_rng.randi() % pool.size()))
	var out: Array = [{"id": "mouth", "role": "entrance", "size": "medium"}]
	var sizes := ["small", "medium", "medium", "large", "small", "large"]
	for i in range(1, count - 1):
		var role := "chamber"
		if bool(spec.get("camp", false)) and i % 3 == 1:
			role = "camp"
		elif i == count - 2:
			role = "hall"
		elif i % 4 == 2:
			role = "passage"
		var r := {"id": "room%d" % i, "role": role, "size": sizes[_rng.randi() % sizes.size()]}
		if role == "passage":
			r["size"] = "small"
		out.append(r)
	# the set-pieces go to the chambers spread along the walk, never the first or the boss's
	var free: Array = []
	for i in range(2, out.size()):
		if str(out[i]["role"]) != "passage":
			free.append(i)
	for p in pieces:
		if free.is_empty():
			break
		var at: int = free.pop_at((_rng.randi() % free.size()))
		out[at]["set_piece"] = p
		out[at]["size"] = SiteKinds.bigger(str(out[at]["size"]), str(SiteKinds.SET_PIECES.get(p, "medium")))
	# a ledge for the archers in one big room without a set-piece
	for i in range(2, out.size()):
		if not out[i].has("set_piece") and str(out[i]["size"]) == "large":
			out[i]["set_piece"] = "ledge"
			break
	out.append({"id": "boss", "role": "boss", "size": "huge", "set_piece": "boss_arena"})
	return out


# --- the walk: a descending spiral ------------------------------------------------------------------

func _room(src: Dictionary, centre: Vector3, yaw: float) -> Dictionary:
	var size := str(src.get("size", "medium"))
	var half := SiteKinds.size_of(size)
	var ratio := _rng.randf_range(0.75, 1.3)
	if str(src.get("role", "")) in ["boss"]:
		ratio = _rng.randf_range(0.9, 1.15)
	half = Vector3(half.x * ratio, half.y * float(src.get("height", 1.0)), half.z / ratio)
	if src.has("half"):
		var h: Array = src["half"]
		half = Vector3(float(h[0]), float(h[1]), float(h[2]))
	var r := {
		"id": str(src.get("id", "room%d" % rooms.size())), "role": str(src.get("role", "chamber")),
		"size": size, "set_piece": str(src.get("set_piece", "")), "note": str(src.get("note", "")),
		"centre": centre, "half": half, "yaw": yaw, "links": [], "spots": [], "wall_spots": [],
		"keep_clear": [], "zones": [], "index": rooms.size(),
	}
	return r


func _add_room(r: Dictionary) -> void:
	r["index"] = rooms.size()
	rooms.append(r)
	_by_id[str(r["id"])] = r


func _built() -> bool:
	return str(spec.get("style", "rock")) == "built"


## How far a room's wall is from its middle along the world direction `dir` (horizontal).
func edge_along(r: Dictionary, dir: Vector3) -> float:
	var half: Vector3 = r["half"]
	var local := dir.rotated(Vector3.UP, -float(r["yaw"]))
	local.y = 0.0
	local = local.normalized()
	if _built():
		var tx := INF if absf(local.x) < 0.0001 else half.x / absf(local.x)
		var tz := INF if absf(local.z) < 0.0001 else half.z / absf(local.z)
		return minf(tx, tz)
	var k := pow(local.x / half.x, 2.0) + pow(local.z / half.z, 2.0)
	return 1.0 / sqrt(k) if k > 0.0 else half.x


func radius_of(r: Dictionary) -> float:
	var half: Vector3 = r["half"]
	if _built():
		return Vector2(half.x, half.z).length()
	return maxf(half.x, half.z)


## Whether a room at `c` of `half` (and its passage from `from`) stands clear of every room laid.
func _clear_for(c: Vector3, half: Vector3, from: Vector3, skip: Array) -> bool:
	var rad := Vector2(half.x, half.z).length() if _built() else maxf(half.x, half.z)
	for o in rooms:
		if skip.has(o["id"]):
			continue
		var oc: Vector3 = o["centre"]
		var oh: Vector3 = o["half"]
		var stacked := c.y > oc.y + oh.y + STACK_GAP or oc.y > c.y + half.y + STACK_GAP
		if stacked:
			continue
		var d := Vector2(c.x - oc.x, c.z - oc.z).length()
		if d < rad + radius_of(o) + 2.5:
			return false
	return _segment_clear(from, c, skip, 1.2)


## Whether a passage from `a` to `b` (floor points) keeps out of every room but `skip`'s.
func _segment_clear(a: Vector3, b: Vector3, skip: Array, extra: float) -> bool:
	for o in rooms:
		if skip.has(o["id"]):
			continue
		var oc: Vector3 = o["centre"]
		var oh: Vector3 = o["half"]
		var a2 := Vector2(a.x, a.z)
		var b2 := Vector2(b.x, b.z)
		var ab := b2 - a2
		var t := 0.0 if ab.length_squared() < 0.001 else clampf((Vector2(oc.x, oc.z) - a2).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var y := lerpf(a.y, b.y, t)
		if y > oc.y + oh.y + STACK_GAP - 1.0 or y + 3.5 + STACK_GAP < oc.y:
			continue
		var near := a2 + ab * t
		if near.distance_to(Vector2(oc.x, oc.z)) < radius_of(o) + float(spec.get("tunnel_r", 1.8)) + extra:
			return false
	return true


func _lay_main(wanted: Array) -> void:
	var turn_sign := 1.0 if _rng.randf() < 0.5 else -1.0
	var heading := _rng.randf() * TAU
	if _built():
		heading = float(_rng.randi() % 4) * PI * 0.5
	var first := _room(wanted[0], Vector3.ZERO, heading if not _built() else 0.0)
	first["role"] = "entrance"
	_add_room(first)
	var turn_rng: Array = spec.get("turn", [30.0, 70.0])
	var len_rng: Array = spec.get("tunnel_len", [5.0, 10.0])
	var drop_rng: Array = spec.get("drop", [-3.0, 0.5])
	for i in range(1, wanted.size()):
		var src: Dictionary = wanted[i]
		var prev: Dictionary = rooms[-1]
		var placed := false
		var size_steps := 0
		var candidate: Dictionary = {}
		while not placed and size_steps < 3:
			for attempt in ATTEMPTS:
				var turn := deg_to_rad(_rng.randf_range(float(turn_rng[0]), float(turn_rng[1])))
				if _built():
					var choice := _rng.randi() % 3
					turn = [0.0, PI * 0.5, PI * 0.5][choice]
				var sgn := turn_sign if _rng.randf() < 0.8 or attempt > ATTEMPTS >> 1 else -turn_sign
				var h := heading + turn * sgn
				if attempt > (ATTEMPTS * 3) >> 2:
					h = heading + (float(attempt) * 0.9)
					if _built():
						h = heading + PI * 0.5 * float(attempt % 4)
				var dir := Vector3(sin(h), 0.0, cos(h))
				var r := _room(src, Vector3.ZERO, h if not _built() else 0.0)
				if size_steps > 0:
					r["half"] = (r["half"] as Vector3) * Vector3(1.0 - 0.18 * size_steps, 1.0, 1.0 - 0.18 * size_steps)
				var corridor := _rng.randf_range(float(len_rng[0]), float(len_rng[1])) + floorf(float(attempt) / 8.0) * 3.0
				var drop := float(src.get("drop", _rng.randf_range(float(drop_rng[0]), float(drop_rng[1]))))
				drop = clampf(drop, -corridor * MAX_SLOPE, corridor * MAX_SLOPE)
				var from_edge := edge_along(prev, dir)
				var c: Vector3 = (prev["centre"] as Vector3) + dir * from_edge
				r["centre"] = c
				var to_edge := edge_along(r, dir)
				c += dir * (corridor + to_edge)
				c.y = (prev["centre"] as Vector3).y + drop
				r["centre"] = c
				var mouth: Vector3 = (prev["centre"] as Vector3) + dir * (from_edge - MOUTH_IN)
				if _clear_for(c, r["half"], mouth, [prev["id"]]):
					candidate = r
					heading = h
					placed = true
					break
			size_steps += 1
		if not placed:
			problems.append("%s: no room for %s beside %s" % [id, src.get("id", "?"), prev["id"]])
			continue
		_add_room(candidate)
		_join(prev, candidate, "passage")


## A passage between two rooms, mouth to mouth along the line between their middles (or `via`).
func _join(a: Dictionary, b: Dictionary, link_kind: String, via: Array = []) -> Dictionary:
	var ca: Vector3 = a["centre"]
	var cb: Vector3 = b["centre"]
	var first := cb if via.is_empty() else (via[0] as Vector3)
	var last := ca if via.is_empty() else (via[-1] as Vector3)
	var da := Vector3(first.x - ca.x, 0.0, first.z - ca.z).normalized()
	var db := Vector3(last.x - cb.x, 0.0, last.z - cb.z).normalized()
	var pa := ca + da * (edge_along(a, da) - MOUTH_IN)
	var pb := cb + db * (edge_along(b, db) - MOUTH_IN)
	pa.y = ca.y
	pb.y = cb.y
	var pts: Array = [pa]
	for v in via:
		pts.append(v)
	pts.append(pb)
	var l := {"a": a["id"], "b": b["id"], "kind": link_kind, "points": pts,
			"width": float(spec.get("tunnel_r", 1.8)) * 2.0, "index": links.size()}
	links.append(l)
	(a["links"] as Array).append(l["index"])
	(b["links"] as Array).append(l["index"])
	return l


func _linked(a: String, b: String) -> bool:
	for l in links:
		if (l["a"] == a and l["b"] == b) or (l["a"] == b and l["b"] == a):
			return true
	return false


func _path_len(pts: Array) -> float:
	var total := 0.0
	for i in range(1, pts.size()):
		var d: Vector3 = (pts[i] as Vector3) - (pts[i - 1] as Vector3)
		total += Vector2(d.x, d.z).length()
	return total


# --- a loop, a secret, the way back out -------------------------------------------------------------

## A second way between two rooms of the walk that are not neighbours on it, so the place is a
## loop and not a line: the nearest such pair whose passage keeps clear of the rest and climbs no
## steeper than a passage may. Where the walk comes round to no such pair, a room is laid beside
## the walk bridging two rooms one apart. A loop whose far room lies 2.5-4.5 m lower may end on a
## ledge over it instead: a drop, one way down.
func _lay_loop() -> void:
	var best: Array = []
	var best_d := 30.0
	for i in rooms.size():
		for j in range(i + 2, rooms.size()):
			var a: Dictionary = rooms[i]
			var b: Dictionary = rooms[j]
			if a["role"] == "boss" or b["role"] == "boss" or _linked(a["id"], b["id"]):
				continue
			var ca: Vector3 = a["centre"]
			var cb: Vector3 = b["centre"]
			var flat := Vector2(cb.x - ca.x, cb.z - ca.z).length()
			var gap := flat - edge_along(a, (cb - ca).normalized()) - edge_along(b, (ca - cb).normalized())
			if gap < 3.0 or gap > best_d:
				continue
			var dy := absf(cb.y - ca.y)
			if dy > gap * MAX_SLOPE and not (dy >= 2.5 and dy <= 4.5):
				continue
			if not _segment_clear(ca, cb, [a["id"], b["id"]], 1.0):
				continue
			best = [a, b]
			best_d = gap
	if not best.is_empty():
		var a: Dictionary = best[0]
		var b: Dictionary = best[1]
		var l := _join(a, b, "loop")
		var pts: Array = l["points"]
		var dy := absf((pts[0] as Vector3).y - (pts[-1] as Vector3).y)
		if dy > _path_len(pts) * MAX_SLOPE:
			_make_drop(l)
		return
	# a room beside the walk, joined to two rooms one apart on it
	for k in range(1, rooms.size() - 2):
		var a: Dictionary = rooms[k]
		var c: Dictionary = rooms[k + 2]
		if c["role"] == "boss":
			continue
		var ca: Vector3 = a["centre"]
		var cc: Vector3 = c["centre"]
		var mid := (ca + cc) * 0.5
		var mid_room: Vector3 = (rooms[k + 1] as Dictionary)["centre"]
		var away := Vector3(mid.x - mid_room.x, 0.0, mid.z - mid_room.z)
		if away.length() < 0.5:
			away = Vector3(cc.z - ca.z, 0.0, ca.x - cc.x)
		away = away.normalized()
		for push in [10.0, 14.0, 18.0, 23.0]:
			var r := _room({"id": "bypass", "role": "bypass", "size": "small"}, mid + away * float(push), 0.0)
			var c2: Vector3 = r["centre"]
			c2.y = mid.y
			r["centre"] = c2
			if not _clear_for(c2, r["half"], ca, [a["id"]]):
				continue
			if not _segment_clear(c2, cc, [c["id"], "bypass"], 1.0):
				continue
			if absf(c2.y - ca.y) > Vector2(c2.x - ca.x, c2.z - ca.z).length() * 0.4:
				continue
			_add_room(r)
			_join(a, r, "loop")
			_join(r, c, "loop")
			return
	problems.append("%s: no loop could be laid" % id)


## A loop passage that ends on a ledge over its lower room: it runs level from the upper room and
## stops over the lower's floor, the fall between.
func _make_drop(l: Dictionary) -> void:
	var pts: Array = l["points"]
	var hi := 0 if (pts[0] as Vector3).y > (pts[-1] as Vector3).y else pts.size() - 1
	var lo := pts.size() - 1 - hi
	var top: float = (pts[hi] as Vector3).y
	var low: Vector3 = pts[lo]
	var fall := top - low.y
	var lower := room(str(l["b"] if lo == pts.size() - 1 else l["a"]))
	# the lower room is raised tall enough for the passage to open into it over its floor
	var half: Vector3 = lower["half"]
	half = Vector3(half.x, maxf(half.y, fall + 4.0), half.z)
	lower["half"] = half
	# the ledge: the passage's level floor carried into the lower room as far as its roof is high
	# enough over the lip for a body to stand there
	var lc: Vector3 = lower["centre"]
	var out := Vector3(low.x - lc.x, 0.0, low.z - lc.z).normalized()
	var e := 0.8
	if not _built():
		var s := (fall + 2.4 + 0.15 * half.y) / (1.15 * half.y)
		e = clampf(sqrt(maxf(0.0, 1.0 - s * s)), 0.3, 0.8)
	var lip := lc + out * edge_along(lower, out) * e
	lip.y = top
	for i in pts.size():
		var p: Vector3 = pts[i]
		pts[i] = Vector3(p.x, top, p.z)
	pts[lo] = lip
	l["kind"] = "drop"
	l["drop"] = fall
	l["one_way_to"] = lower["id"]


## A ledge over a lower room: a level passage from a room of the walk that ends high in the wall
## of a room further on and 2.5-5 m lower, the fall between, one way down. The spiral seldom brings
## a loop's two rooms to that difference by itself, so the drop is looked for on its own: the
## nearest pair (not neighbours, the upper one past the way in, neither the boss's) whose passage
## keeps clear of every other room and whose lower room can be raised to open under the lip
## without meeting a room or passage over it. A place with `"drops": false` has none.
const DROP_FALL := Vector2(2.5, 5.0)


func _lay_drop() -> void:
	for l in links:
		if l["kind"] == "drop":
			return
	var best: Array = []
	var best_gap := 16.0
	for i in range(1, rooms.size()):
		for j in range(i + 2, rooms.size()):
			var up: Dictionary = rooms[i]
			var lo: Dictionary = rooms[j]
			if lo["role"] in ["boss", "secret", "bypass"] or up["role"] in ["boss", "secret", "bypass"]:
				continue
			if _linked(up["id"], lo["id"]):
				continue
			var cu: Vector3 = up["centre"]
			var cl: Vector3 = lo["centre"]
			var fall := cu.y - cl.y
			if fall < DROP_FALL.x or fall > DROP_FALL.y:
				continue
			var flat := Vector3(cl.x - cu.x, 0.0, cl.z - cu.z)
			if flat.length() < 0.5:
				continue
			var gap := flat.length() - edge_along(up, flat.normalized()) - edge_along(lo, -flat.normalized())
			if gap < 2.5 or gap > best_gap:
				continue
			if _mouth_near(up, flat.normalized(), 2.5) or _mouth_near(lo, -flat.normalized(), 2.5):
				continue
			# the passage runs level at the upper room's floor
			if not _segment_clear(cu, Vector3(cl.x, cu.y, cl.z), [up["id"], lo["id"]], 1.0):
				continue
			if not _raise_clear(lo, fall + 4.0, [up["id"]]):
				continue
			best = [up, lo]
			best_gap = gap
	if best.is_empty():
		return
	var l := _join(best[0], best[1], "loop")
	_make_drop(l)


## Whether room `r` can be made `new_h` high (half-height) without its roof coming within STACK_GAP
## of a room over it, or cutting a passage that runs over it (those of `skip` and its own aside).
func _raise_clear(r: Dictionary, new_h: float, skip: Array) -> bool:
	var c: Vector3 = r["centre"]
	var top := c.y + new_h + STACK_GAP
	var rad := radius_of(r)
	for o in rooms:
		if o["id"] == r["id"] or skip.has(o["id"]):
			continue
		var oc: Vector3 = o["centre"]
		if oc.y <= c.y:
			continue
		if Vector2(oc.x - c.x, oc.z - c.z).length() < rad + radius_of(o) + 2.5 and oc.y < top:
			return false
	for l in links:
		if l["a"] == r["id"] or l["b"] == r["id"] or skip.has(l["a"]) or skip.has(l["b"]):
			continue
		var pts: Array = l["points"]
		for i in range(1, pts.size()):
			var a: Vector3 = pts[i - 1]
			var b: Vector3 = pts[i]
			for t in 9:
				var p := a.lerp(b, float(t) / 8.0)
				if p.y > c.y and p.y < top and Vector2(p.x - c.x, p.z - c.z).length() < rad + float(spec.get("tunnel_r", 1.8)) + 1.0:
					return false
	return true


## A small room off a chamber in the middle of the walk, behind a wall of loose stones: rich loot,
## found by whoever looks at the walls.
func _lay_secret() -> void:
	if not bool(_site.get("secret", true)):
		return
	var order: Array = []
	for i in range(2, rooms.size() - 1):
		if rooms[i]["role"] not in ["boss", "bypass"]:
			order.append(i)
	var middle := rooms.size() >> 1
	order.sort_custom(func(x: int, y: int) -> bool: return absi(x - middle) < absi(y - middle))
	for i in order:
		var host: Dictionary = rooms[i]
		for k in 12:
			var h := TAU * float(k) / 12.0 + float(i)
			if _built():
				h = PI * 0.5 * float(k % 4)
			var dir := Vector3(sin(h), 0.0, cos(h))
			if _mouth_near(host, dir, 4.0):
				continue
			var r := _room({"id": "secret", "role": "secret", "size": "small"}, Vector3.ZERO, 0.0)
			var c: Vector3 = (host["centre"] as Vector3) + dir * (edge_along(host, dir) + 4.0 + edge_along(r, dir))
			r["centre"] = c
			var mouth: Vector3 = (host["centre"] as Vector3) + dir * (edge_along(host, dir) - MOUTH_IN)
			if _clear_for(c, r["half"], mouth, [host["id"]]):
				_add_room(r)
				var l := _join(host, r, "secret")
				l["width"] = 2.2 if _built() else 2.8
				return
	problems.append("%s: no wall for a secret room" % id)


## Whether a doorway already opens in `r`'s wall within `within` metres of the one along `dir`.
func _mouth_near(r: Dictionary, dir: Vector3, within: float) -> bool:
	var at: Vector3 = (r["centre"] as Vector3) + dir * edge_along(r, dir)
	for li in r["links"]:
		var l: Dictionary = links[li]
		var pts: Array = l["points"]
		var m: Vector3 = pts[0] if l["a"] == r["id"] else pts[-1]
		if Vector2(m.x - at.x, m.z - at.z).length() < within + 1.5:
			return true
	return false


## A way from the boss's room back to the way in, barred from the entrance side until it is
## lifted from within: the walk out once the place is done. It climbs no steeper than a passage,
## winding out and back when the climb is long, and keeps clear of every room between.
func _lay_shortcut() -> void:
	if not bool(_site.get("shortcut", true)):
		return
	var boss: Dictionary = {}
	for r in rooms:
		if r["role"] == "boss":
			boss = r
	if boss.is_empty():
		return
	var targets: Array = [rooms[0]]
	if rooms.size() > 2:
		targets.append(rooms[1])
	for target in targets:
		var cb: Vector3 = boss["centre"]
		var ct: Vector3 = (target as Dictionary)["centre"]
		var flat := Vector2(ct.x - cb.x, ct.z - cb.z)
		var across := Vector3(-flat.y, 0.0, flat.x).normalized() if flat.length() > 0.1 else Vector3.RIGHT
		var tries: Array = [[]]
		for off in [10.0, -10.0, 16.0, -16.0, 24.0, -24.0, 32.0, -32.0]:
			tries.append([(cb + ct) * 0.5 + across * float(off)])
		for via in tries:
			# the mouths as the passage will have them, and the climb spread evenly along its length
			var first: Vector3 = ct if (via as Array).is_empty() else via[0]
			var last: Vector3 = cb if (via as Array).is_empty() else via[-1]
			var da := Vector3(first.x - cb.x, 0.0, first.z - cb.z).normalized()
			var db := Vector3(last.x - ct.x, 0.0, last.z - ct.z).normalized()
			var pa := cb + da * (edge_along(boss, da) - MOUTH_IN)
			var pb := ct + db * (edge_along(target, db) - MOUTH_IN)
			pa.y = cb.y
			pb.y = ct.y
			var chain: Array = [pa]
			for v in via:
				chain.append(v)
			chain.append(pb)
			var total := _path_len(chain)
			if absf(pb.y - pa.y) > total * MAX_SLOPE * 0.95:
				continue
			var along := 0.0
			var fixed: Array = []
			for i in range(1, chain.size() - 1):
				var p: Vector3 = chain[i]
				var q: Vector3 = chain[i - 1]
				along += Vector2(p.x - q.x, p.z - q.z).length()
				fixed.append(Vector3(p.x, pa.y + (pb.y - pa.y) * along / total, p.z))
			var ok := true
			var walk: Array = [pa] + fixed + [pb]
			for i in range(1, walk.size()):
				if not _segment_clear(walk[i - 1], walk[i], [boss["id"], target["id"]], 0.8):
					ok = false
					break
			if ok:
				var l := _join(boss, target, "shortcut", fixed)
				l["barred_from"] = target["id"]
				return
	problems.append("%s: no way back from the boss could be laid" % id)


# --- the rock -------------------------------------------------------------------------------------

func _noise_amp() -> float:
	return float(spec.get("noise", 0.8))


func _room_ops(r: Dictionary) -> void:
	var c: Vector3 = r["centre"]
	var half: Vector3 = r["half"]
	if _built():
		ops.append({"op": "carve", "type": "vault", "c": c, "half": half, "yaw": float(r["yaw"]),
				"noise": _noise_amp(), "k": 0.0})
	else:
		ops.append({"op": "carve", "type": "dome", "c": c, "half": half, "yaw": float(r["yaw"]),
				"noise": _noise_amp() * (1.2 if r["role"] == "boss" else 1.0), "k": 0.0})


func _link_ops(l: Dictionary) -> void:
	var pts: Array = l["points"]
	var width := float(l["width"])
	var square := _built() or bool(spec.get("square_tunnels", false))
	for i in range(1, pts.size()):
		var a: Vector3 = pts[i - 1]
		var b: Vector3 = pts[i]
		# extend each run a little past its ends so the joins between runs and rooms are closed
		var d := Vector3(b.x - a.x, 0.0, b.z - a.z).normalized()
		var a2 := a - d * (0.8 if i == 1 else 1.2)
		var b2 := b + d * (0.8 if i == pts.size() - 1 else 1.2)
		a2.y = a.y
		b2.y = b.y
		var height := width * (1.25 if square else 1.3)
		if str(l["kind"]) == "secret":
			height = 2.6
		if square:
			ops.append({"op": "carve", "type": "corridor", "a": a2, "b": b2, "w": width * 0.5,
					"h": height, "arched": _built(), "noise": _noise_amp() * 0.5, "k": 0.0})
		else:
			ops.append({"op": "carve", "type": "tube", "a": a2, "b": b2, "r": width * 0.5 * 1.1,
					"noise": _noise_amp() * 0.7, "k": 0.9})


# --- set-pieces -----------------------------------------------------------------------------------

## The two doorways a room is walked through by (the way in along the walk, and the way on), as
## floor points: a set-piece is laid across or beside the line between them.
func mouths_of(r: Dictionary) -> Array:
	var out: Array = []
	for li in r["links"]:
		var l: Dictionary = links[li]
		var pts: Array = l["points"]
		out.append({"at": pts[0] if l["a"] == r["id"] else pts[-1], "link": l})
	return out


func _through(r: Dictionary) -> Vector3:
	var ms := mouths_of(r)
	var main: Array = []
	for m in ms:
		if str((m["link"] as Dictionary)["kind"]) == "passage":
			main.append(m["at"])
	if main.size() >= 2:
		var d: Vector3 = (main[1] as Vector3) - (main[0] as Vector3)
		d.y = 0.0
		if d.length() > 0.5:
			return d.normalized()
	if ms.size() >= 1:
		var d2: Vector3 = (r["centre"] as Vector3) - (ms[0]["at"] as Vector3)
		d2.y = 0.0
		if d2.length() > 0.5:
			return d2.normalized()
	return Vector3.FORWARD


## Whether a zone (a circle on the floor) lies clear of every doorway into the room.
func _clear_of_mouths(r: Dictionary, at: Vector3, radius: float) -> bool:
	for m in mouths_of(r):
		var p: Vector3 = m["at"]
		if Vector2(p.x - at.x, p.z - at.z).length() < radius + 2.2:
			return false
	return true


func _set_piece(r: Dictionary) -> void:
	var piece := str(r["set_piece"])
	var c: Vector3 = r["centre"]
	var half: Vector3 = r["half"]
	var through := _through(r)
	var side := Vector3(through.z, 0.0, -through.x)
	var small := minf(half.x, half.z)
	match piece:
		"underground_lake":
			# a basin to one side of the way through, waded at its edge, deep at its heart
			for s in [1.0, -1.0]:
				var rad := small * 0.55
				var at := c + side * float(s) * small * 0.38
				if _clear_of_mouths(r, at, rad):
					ops.append({"op": "carve", "type": "bowl", "c": at, "r": rad, "depth": 1.6, "noise": 0.25, "k": 0.8})
					(r["zones"] as Array).append({"kind": "lake", "at": at, "r": rad, "level": c.y - 0.3})
					return
			r["set_piece"] = ""
		"daylight_shaft", "collapsed_shaft":
			var at := c + side * small * 0.2
			var rad := clampf(small * 0.22, 1.2, 2.4)
			ops.append({"op": "carve", "type": "shaft", "c": at + Vector3.UP * half.y * 0.6, "r": rad, "noise": 0.35})
			(r["zones"] as Array).append({"kind": "shaft", "at": at, "r": rad})
			if piece == "collapsed_shaft" or _built():
				# the fall of roof under it: a mound you can walk over
				ops.append({"op": "fill", "type": "mound", "c": at + side * 0.8, "r": Vector3(rad * 2.2, 1.1, rad * 1.8), "noise": 0.3, "k": 0.6})
				(r["zones"] as Array).append({"kind": "rubble", "at": at + side * 0.8, "r": rad * 2.0})
		"chasm_bridge", "lava_chasm":
			# a rift across the way through: the far side is reached by the bridge alone
			var width := 4.0 if piece == "chasm_bridge" else 5.0
			var across_m := Vector2(half.x, half.z).length() * 2.2
			var ok := true
			for m in mouths_of(r):
				var p: Vector3 = m["at"]
				if absf((p - c).dot(through)) < width * 0.5 + 2.4:
					ok = false
			if not ok:
				r["set_piece"] = "ledge"
				_set_piece(r)
				return
			var depth := 9.0 if piece == "chasm_bridge" else 4.0
			ops.append({"op": "carve", "type": "box", "c": c + Vector3.DOWN * depth * 0.5, "half": Vector3(across_m * 0.5, depth * 0.5 + 0.3, width * 0.5),
					"yaw": atan2(through.x, through.z), "noise": 0.4, "k": 0.4})
			var bridge := {"kind": "chasm", "at": c, "along": through, "width": width, "depth": depth,
					"reach": across_m, "lava": piece == "lava_chasm", "bridge": "stone" if (_built() or piece == "lava_chasm") else "timber"}
			(r["zones"] as Array).append(bridge)
			if bridge["bridge"] == "stone":
				# a span of the rock itself, left standing across the rift
				ops.append({"op": "fill", "type": "box", "c": c + Vector3.DOWN * 0.9, "half": Vector3(1.4, 0.9, width * 0.5 + 0.6),
						"yaw": atan2(through.x, through.z), "noise": 0.0, "k": 0.0})
		"ledge":
			# a shelf along the wall 3 m up, a ramp to it along the wall: archers stand here
			for s in [1.0, -1.0]:
				var wall := c + side * float(s) * (small - 1.6)
				if not _clear_of_mouths(r, wall, 2.4):
					continue
				var span := minf(maxf(half.x, half.z) * 1.1, 11.0)
				var yaw := atan2(through.x, through.z)
				var top := 3.0
				ops.append({"op": "fill", "type": "box", "c": wall + through * (span * 0.25) + Vector3.UP * (top * 0.5 - 0.5),
						"half": Vector3(1.9, top * 0.5 + 0.5, span * 0.35), "yaw": yaw, "noise": 0.1, "k": 0.0})
				var ramp_len := top / 0.45
				var ramp_mid := wall + through * (span * 0.25 - span * 0.35 - ramp_len * 0.5)
				ops.append({"op": "fill", "type": "ramp", "c": ramp_mid, "half": Vector3(1.2, top * 0.5, ramp_len * 0.5),
						"yaw": yaw, "rise": top, "noise": 0.0, "k": 0.0})
				(r["zones"] as Array).append({"kind": "ledge", "at": wall + through * (span * 0.25) + Vector3.UP * top,
						"r": 2.0, "len": span * 0.7, "along": through, "ramp": ramp_mid})
				(r["zones"] as Array).append({"kind": "keep", "at": ramp_mid, "r": ramp_len * 0.55})
				return
			r["set_piece"] = ""
		"boss_arena":
			# four pillars round the floor: cover from a charge, and the roof held up
			var n := 4
			for i in n:
				var a := float(i) / float(n) * TAU + PI / 4.0 + float(r["yaw"])
				var at := c + Vector3(sin(a), 0.0, cos(a)) * small * 0.55
				if not _clear_of_mouths(r, at, 1.6):
					continue
				ops.append({"op": "fill", "type": "pillar", "c": at, "r": 0.9 if _built() else 1.2, "top": half.y + 2.0,
						"noise": 0.15 if _built() else 0.5, "k": 0.5})
				(r["zones"] as Array).append({"kind": "pillar", "at": at, "r": 1.4})
		"ossuary":
			# rows of niches in the walls, bones in them
			var count := 0
			for k in 16:
				var a := TAU * float(k) / 16.0
				var dir := Vector3(sin(a), 0.0, cos(a))
				if _built():
					dir = [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT][k % 4]
					var slide := (floorf(float(k) / 4.0) - 1.5) * 1.6
					var edge := edge_along(r, dir)
					var at := c + dir * (edge + 0.25) + Vector3(dir.z, 0.0, -dir.x) * slide
					if not _clear_of_mouths(r, at, 1.2):
						continue
					for row in 2:
						var y := 0.7 + float(row) * 1.0
						ops.append({"op": "carve", "type": "box", "c": at + Vector3.UP * y, "half": Vector3(0.6, 0.35, 0.45),
								"yaw": atan2(dir.x, dir.z) + PI * 0.5, "noise": 0.0, "k": 0.0})
						(r["zones"] as Array).append({"kind": "niche", "at": at + Vector3.UP * (y - 0.35) - dir * 0.05, "facing": -dir})
					count += 1
			if count == 0:
				r["set_piece"] = ""
		_:
			pass


# --- where things stand ---------------------------------------------------------------------------

## Every room's clear floor, as points a pace apart: off the doorways, off the lanes between them,
## out of the lake, the rift, the pillars and the ramp. `wall_spots` are the ones by the wall, where
## a thing is left; `spots` the rest.
func _spots() -> void:
	for r in rooms:
		var c: Vector3 = r["centre"]
		var half: Vector3 = r["half"]
		var yaw := float(r["yaw"])
		var inset := 1.1 + (_noise_amp() if not _built() else 0.1)
		var step := 1.4
		var ms := mouths_of(r)
		var spots: Array = []
		var wall: Array = []
		var nx := int(half.x / step)
		var nz := int(half.z / step)
		for ix in range(-nx, nx + 1):
			for iz in range(-nz, nz + 1):
				var local := Vector3(float(ix) * step, 0.0, float(iz) * step)
				var e := 0.0
				if _built():
					e = maxf(absf(local.x) / maxf(half.x - inset, 0.5), absf(local.z) / maxf(half.z - inset, 0.5))
				else:
					e = sqrt(pow(local.x / maxf(half.x - inset, 0.5), 2.0) + pow(local.z / maxf(half.z - inset, 0.5), 2.0))
				if e > 1.0:
					continue
				var p := c + local.rotated(Vector3.UP, yaw)
				if not _spot_clear(r, p, ms):
					continue
				if e > 0.72:
					wall.append(p)
				else:
					spots.append(p)
		r["spots"] = spots
		r["wall_spots"] = wall


func _spot_clear(r: Dictionary, p: Vector3, ms: Array) -> bool:
	var c: Vector3 = r["centre"]
	for k in r.get("keep_clear", []):
		if Vector2((k as Vector3).x - p.x, (k as Vector3).z - p.z).length() < 2.8:
			return false
	for m in ms:
		var at: Vector3 = m["at"]
		if Vector2(at.x - p.x, at.z - p.z).length() < 2.6:
			return false
		# the lane from each doorway to the middle
		var a := Vector2(at.x, at.z)
		var b := Vector2(c.x, c.z)
		var ab := b - a
		var t := clampf((Vector2(p.x, p.z) - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		if (a + ab * t).distance_to(Vector2(p.x, p.z)) < 1.3:
			return false
	for z in r["zones"]:
		var kind_z := str(z["kind"])
		var zat: Vector3 = z["at"]
		if kind_z == "chasm":
			var along: Vector3 = z["along"]
			if absf((p - zat).dot(along)) < float(z["width"]) * 0.5 + 1.2:
				return false
			continue
		if kind_z in ["niche", "ledge"]:
			continue
		if Vector2(zat.x - p.x, zat.z - p.z).length() < float(z.get("r", 1.0)) + 0.9:
			return false
	return true


func take_spot(r: Dictionary, wall := false, near := Vector3.INF) -> Vector3:
	var list: Array = r["wall_spots"] if wall else r["spots"]
	if list.is_empty():
		list = r["spots"] if wall else r["wall_spots"]
	if list.is_empty():
		return Vector3.INF
	var i := _rng.randi() % list.size()
	if near != Vector3.INF:
		var best := INF
		for k in list.size():
			var d := (list[k] as Vector3).distance_squared_to(near)
			if d < best:
				best = d
				i = k
	var p: Vector3 = list[i]
	list.remove_at(i)
	# neighbours of a taken spot are left alone, so two things do not stand in one another
	for k in range(list.size() - 1, -1, -1):
		if Vector2((list[k] as Vector3).x - p.x, (list[k] as Vector3).z - p.z).length() < 1.5:
			list.remove_at(k)
	return p


## The way in: the exit door a step inside the entrance room's wall, opposite its passage on, and
## the arrival a pace in front of it.
func _mark_entrance() -> void:
	var r: Dictionary = rooms[0]
	var c: Vector3 = r["centre"]
	var away := Vector3.BACK
	var ms := mouths_of(r)
	if not ms.is_empty():
		var sum := Vector3.ZERO
		for m in ms:
			sum += ((m["at"] as Vector3) - c)
		sum.y = 0.0
		if sum.length() > 0.1:
			away = -sum.normalized()
	var edge := edge_along(r, away)
	exit_yaw = atan2(-away.x, -away.z)
	entrance_yaw = atan2(away.x, away.z)
	if _built():
		exit_at = c + away * (edge - 1.4)
		entrance = exit_at - away * 1.6
	else:
		# a short throat out through the rock, climbing toward the daylight at its end: the way out
		# is a tunnel with the day in it, and its door a pace inside the throat
		var a := c + away * (edge - 2.0)
		var b := c + away * (edge + 7.0) + Vector3.UP * 1.4
		ops.append({"op": "carve", "type": "tube", "a": a, "b": b, "r": 1.6, "noise": _noise_amp() * 0.4, "k": 0.8})
		exit_at = c + away * (edge + 0.6) + Vector3.UP * 0.15
		exit_glow = b + Vector3.UP * 1.3 - away * 0.4
		entrance = c + away * (edge - 2.2 - _noise_amp())
	r["keep_clear"] = [exit_at, entrance]


# --- who is here ----------------------------------------------------------------------------------

func _foes() -> Array:
	var pools: Dictionary = _site.get("foes", {})
	var dflt: Array = SiteKinds.REGION_FOES.get(region, SiteKinds.REGION_FOES["hearthvale"])
	return [pools.get("rank", dflt[0]), pools.get("archers", dflt[1]), pools.get("heavy", dflt[2])]


func _pick(list: Array) -> String:
	return str(list[_rng.randi() % list.size()]) if not list.is_empty() else ""


## The foes, set where they would be: a sentry in the first room's far side, a pair on guard in
## most chambers, sleepers round a camp's fire, archers on a ledge, one walking the round between
## two rooms, heavies before the boss, the boss in its arena. An `encounters` list in the def
## replaces all of it but the boss.
func _people() -> void:
	var foes := _foes()
	var authored: Array = _site.get("encounters", [])
	var boss_id := str(_site.get("boss", ""))
	if not authored.is_empty():
		for e in authored:
			var r := room(str(e.get("room", "")))
			if r.is_empty():
				problems.append("%s: an encounter names no room '%s'" % [id, e.get("room", "")])
				continue
			_group(r, str(e.get("enemy", "")), int(e.get("count", 1)), str(e.get("role", "guard")))
	else:
		var scale := clampi(danger, 1, 5)
		for r in rooms:
			match str(r["role"]):
				"entrance", "secret", "bypass", "shrine":
					pass
				"camp":
					_group(r, _pick(foes[0]), 2 + (scale >> 1), "sleeper")
					_group(r, _pick(foes[0]), 1, "guard")
				"passage":
					if _rng.randf() < 0.5:
						_group(r, _pick(foes[0]), 1, "ambush")
				"hall":
					_group(r, _pick(foes[2]), 1, "guard")
					_group(r, _pick(foes[0]), 1 + floori(scale / 3.0), "guard")
				"boss":
					pass
				_:
					_group(r, _pick(foes[0]), 1 + (scale >> 1), "guard")
			if str(r["set_piece"]) == "ledge":
				_group(r, _pick(foes[1]), 1 + floori(scale / 3.0), "archer")
		# one walks the round between the second room and the fourth
		if rooms.size() > 4:
			_patrol(rooms[1], rooms[3], _pick(foes[0]))
	if boss_id != "":
		for r in rooms:
			if r["role"] == "boss":
				var at: Vector3 = r["centre"]
				encounters.append({"room": r["id"], "enemy": boss_id, "role": "boss", "spots": [at], "yaw": 0.0})
				if int(_site.get("boss_adds", 2)) > 0:
					_group(r, _pick(foes[0]), int(_site.get("boss_adds", 2)), "sleeper")


func _group(r: Dictionary, enemy: String, count: int, role: String) -> void:
	if enemy == "":
		return
	var spots: Array = []
	if role == "archer":
		for z in r["zones"]:
			if z["kind"] == "ledge":
				var along: Vector3 = z["along"]
				for i in count:
					spots.append((z["at"] as Vector3) + along * (float(i) - float(count - 1) * 0.5) * 1.8)
	else:
		var near := Vector3.INF
		for i in count:
			var p := take_spot(r, role == "sleeper", near)
			if p == Vector3.INF:
				break
			spots.append(p)
			near = p
	if spots.is_empty():
		return
	var face := _through(r)
	encounters.append({"room": r["id"], "enemy": enemy, "role": role, "spots": spots,
			"yaw": atan2(-face.x, -face.z)})


func _patrol(a: Dictionary, b: Dictionary, enemy: String) -> void:
	var route: Array = [a["centre"]]
	for l in links:
		if (l["a"] == a["id"] and l["b"] == b["id"]) or (l["a"] == b["id"] and l["b"] == a["id"]):
			for p in l["points"]:
				route.append(p)
	if route.size() == 1:
		# through the room between them
		for l in links:
			if l["kind"] != "passage":
				continue
			if l["a"] == a["id"] or l["b"] == a["id"]:
				for p in l["points"]:
					route.append(p)
				break
	route.append(b["centre"] if route.size() > 1 and _linked(a["id"], b["id"]) else route[-1])
	encounters.append({"room": a["id"], "enemy": enemy, "role": "patrol", "spots": [a["centre"]], "patrol": route, "yaw": 0.0})


# --- what is left lying -------------------------------------------------------------------------

func _loot() -> void:
	var table := str(spec.get("loot", "core:loot/common_chest"))
	var rich := str(_site.get("rich_loot", "core:loot/rich_chest"))
	var n := 0
	for r in rooms:
		var tier := ""
		match str(r["role"]):
			"secret", "treasure":
				tier = "rich"
			"boss":
				tier = "boss"
			"camp", "hall":
				tier = "common"
			"chamber":
				tier = "common" if _rng.randf() < 0.35 else ""
		if tier == "":
			continue
		var at := take_spot(r, true)
		if at == Vector3.INF:
			continue
		var t := table
		if tier == "rich":
			t = rich
		elif tier == "boss":
			t = str(_site.get("boss_loot", rich))
		var face: Vector3 = (r["centre"] as Vector3) - at
		containers.append({"room": r["id"], "at": at, "yaw": atan2(face.x, face.z), "tier": tier, "table": t,
				"id": "%s/%s/%d" % [id, r["id"], n], "prop": str(spec.get("container", "chest"))})
		n += 1


## The def's own features (a Hearthstone, a quest item, a note, a prop), each set in its room: at a
## wall spot unless it says `open`.
func _features() -> void:
	for f in _site.get("features", []):
		var fd: Dictionary = (f as Dictionary).duplicate(true)
		var r := room(str(fd.get("room", "")))
		if r.is_empty():
			problems.append("%s: a feature names no room '%s'" % [id, fd.get("room", "")])
			continue
		var at := take_spot(r, not bool(fd.get("open", false)))
		if at == Vector3.INF:
			at = r["centre"]
		fd["at"] = at
		var face: Vector3 = (r["centre"] as Vector3) - at
		fd["yaw"] = rad_to_deg(atan2(face.x, face.z))
		features.append(fd)


func _bounds() -> void:
	var b := AABB(Vector3.ZERO, Vector3.ZERO)
	for r in rooms:
		var c: Vector3 = r["centre"]
		var rad := radius_of(r) + 2.0
		var half: Vector3 = r["half"]
		b = b.merge(AABB(c - Vector3(rad, 10.0, rad), Vector3(rad * 2.0, half.y + 14.0, rad * 2.0)))
	for l in links:
		for p in l["points"]:
			b = b.expand(p + Vector3(3, 6, 3)).expand(p - Vector3(3, 3, 3))
	# every carve's own box (the way out's throat, a basin, a rift), so none is cut off at the grid's
	# edge and left open; a shaft runs up to the top whatever it is
	for op in ops:
		if str(op["type"]) != "shaft":
			b = b.merge(SiteField.op_box(op, b.end.y))
	bounds = b


# --- checks -----------------------------------------------------------------------------------------

## Which rooms can be reached from the entrance walking the links (a drop only down), and which can
## reach the entrance back: {"from": [ids], "back": [ids]}.
func reach() -> Dictionary:
	return {"from": _walk(str(rooms[0]["id"]), false), "back": _walk(str(rooms[0]["id"]), true)}


func _walk(start: String, reverse: bool) -> Array:
	var seen := {start: true}
	var todo := [start]
	while not todo.is_empty():
		var at: String = todo.pop_back()
		for l in links:
			var nxt := ""
			var one_way := str(l.get("one_way_to", ""))
			if l["a"] == at:
				nxt = l["b"]
			elif l["b"] == at:
				nxt = l["a"]
			if nxt == "" or seen.has(nxt):
				continue
			if one_way != "":
				# walking forward, a drop is taken only toward its lower room; walking back, only from it
				if (not reverse and nxt != one_way) or (reverse and at != one_way):
					continue
			seen[nxt] = true
			todo.append(nxt)
	return seen.keys()


## Whether the rooms and passages (the drops left out) make at least one cycle.
func has_loop() -> bool:
	var edges := 0
	for l in links:
		if str(l["kind"]) not in ["secret"]:
			edges += 1
	var nodes := 0
	for r in rooms:
		if r["role"] != "secret":
			nodes += 1
	return edges >= nodes


## A text fingerprint of the whole plan, for the determinism test and the shell's cache.
func fingerprint() -> String:
	return str([rooms.map(func(r: Dictionary) -> Array: return [r["id"], r["centre"], r["half"], r["set_piece"]]),
			links.map(func(l: Dictionary) -> Array: return [l["a"], l["b"], l["kind"], l["points"]]),
			ops.size(), encounters.size(), containers.size()]).md5_text()
