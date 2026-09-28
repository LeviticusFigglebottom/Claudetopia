class_name StreetPlan
extends RefCounted
## Where a settlement's streets run, and the plots that stand along them.
##
## A town is not a ring of houses looking in at a green. It is its streets: the road decides
## the grain, the plots front it shoulder to shoulder, each house stands a pace or two back from
## the carriageway with its door on the street, and its garden runs back from it to a fence.
## Where two roads cross there is an open place, a market square in a town and a green in a
## village, and that is the only open ground in the middle.
##
## The plan is geometry only, so it can be tested without a world: the arms of the street
## network inside the flattened pad (every road that crosses it, split at the middle and merged
## where two leave on the same line), and then the plots cut along every arm on both sides,
## the real houses first (the ones with an inside, each put on the frontage nearest where its
## door plan wanted it) and the fabric after them. A plot is an oriented box, and a box is kept
## only where it is clear of every road, every other box and the open middle.
##
## A place no road crosses still gets a street: one laid straight through it on a bearing of
## its own, because a village is a street before it is anything else.

## Two roads that leave the middle within this many degrees of each other are one street.
const MERGE_DEG := 16.0
## How far along a street the search steps when a plot does not fit.
const STEP_M := 1.0
## The road's own half-width, and the elbow room a house keeps from any road that is not its own.
const ROAD_HALF_M := 3.0
const ROAD_CLEAR_M := 0.6
## A house stays this far inside the flattened ground; its garden may run past the pad's edge.
const EDGE_M := 1.5
const GARDEN_PAST_EDGE_M := 7.0
## Every few plots a lane goes back from the street between two gardens, this wide and this long,
## in the kinds of place big enough to need a way through to the ground behind.
const LANE_W := 2.8
const LANE_LEN := 20.0
const LANE_KINDS := ["city", "town", "village"]

## How each kind of place is laid out. `hub` is the radius of the open middle; `front` is the
## frontage a plot takes along the street and `gap` the space left before the next (none in a
## town terrace, a garden's width in a hamlet); `setback` is from the road's edge to the front
## wall, `depth` how deep a house is, and `garden` how far its plot runs on behind it. How many
## houses a place of each kind has is the fabric's to say (`Settlement.FABRIC`).
const LAYOUT := {
	"city": {"hub": 19.0, "front": [6.0, 8.5], "gap": [0.0, 0.4], "setback": [1.2, 1.8],
			 "depth": [7.0, 9.5], "garden": [4.0, 8.0]},
	"town": {"hub": 14.0, "front": [6.5, 9.0], "gap": [0.0, 1.6], "setback": [1.6, 2.6],
			 "depth": [6.0, 8.0], "garden": [8.0, 14.0]},
	"village": {"hub": 11.0, "front": [7.0, 9.5], "gap": [1.8, 4.5], "setback": [2.4, 4.0],
				"depth": [5.2, 7.0], "garden": [10.0, 16.0]},
	"hamlet": {"hub": 8.0, "front": [7.0, 9.5], "gap": [4.0, 8.0], "setback": [3.0, 5.0],
			   "depth": [5.0, 6.8], "garden": [9.0, 14.0]},
	"fort": {"hub": 12.0, "front": [7.0, 10.0], "gap": [0.0, 1.0], "setback": [1.4, 2.2],
			 "depth": [6.0, 8.5], "garden": [3.0, 5.0]},
	"lodge": {"hub": 9.0, "front": [7.0, 9.0], "gap": [4.0, 8.0], "setback": [3.0, 4.5],
			  "depth": [5.0, 6.5], "garden": [6.0, 10.0]},
	"camp": {"hub": 9.0, "front": [6.0, 8.0], "gap": [3.0, 6.0], "setback": [3.0, 4.5],
			 "depth": [5.0, 6.0], "garden": [0.0, 0.0]},
	"ruin_village": {"hub": 10.0, "front": [7.0, 9.0], "gap": [2.0, 5.0], "setback": [2.5, 4.0],
					 "depth": [5.0, 6.8], "garden": [6.0, 10.0]},
}

var centre := Vector2.ZERO
var radius := 40.0
var kind := "village"
var hub := 11.0
## Every road that crosses the pad, as world-space polylines (PackedVector2Array).
var lines: Array = []
## The streets: {points: PackedVector2Array from the middle outward, length, bearing}.
var arms: Array = []
## Houses along the streets: {box, garden, arm, side, s, facing, door, real}.
var houses: Array = []
## Ground that is not a house but is not free either: a deep place's mouth, a door's apron.
var reserved: Array = []
## Which of `lines` the plan laid itself, where no road ran: they have no road on the ground.
var laid: Array[int] = []
## The lanes left between runs of plots, back from the street to the ground behind the gardens:
## oriented boxes, `v` away from the street.
var lanes: Array = []

var _rng := RandomNumberGenerator.new()


## A plan for a place of `place_kind` centred on `at` (world xz), over `pad_radius` of flattened
## ground, from the road polylines that touch it (each an array of [x, z] pairs).
static func make(place_id: String, place_kind: String, at: Vector2, pad_radius: float,
		road_lines: Array) -> StreetPlan:
	var plan := StreetPlan.new()
	plan.kind = place_kind
	plan.centre = at
	plan.radius = pad_radius
	var spec: Dictionary = LAYOUT.get(place_kind, LAYOUT["village"])
	plan.hub = minf(float(spec.get("hub", 11.0)), pad_radius * 0.4)
	plan._rng.seed = abs(("streets:" + place_id).hash())
	for line_v in road_lines:
		var pts := _points_of(line_v)
		if pts.size() >= 2 and _touches(pts, at, pad_radius + 6.0):
			# only the stretch near the place: a road is kilometres long and every test of a
			# plot against it would otherwise walk all of it
			plan.lines.append_array(_clip(pts, at, pad_radius + 30.0))
	if plan.lines.is_empty():
		plan.laid.append(plan.lines.size())
		plan.lines.append(plan._laid_street())
	plan.arms = _arms_of(plan.lines, at, pad_radius)
	# A road that ends at the place still has a street that goes on through it: a village at a
	# road's end is not half a village. And a town or a city on one road has a street across it.
	if plan.arms.size() == 1:
		plan._lay_street(float(plan.arms[0]["bearing"]) + 180.0, false)
	if place_kind in ["city", "town"] and plan.arms.size() <= 2:
		plan._lay_street(float(plan.arms[0]["bearing"]) + 90.0, true)
	return plan


## Lays a street of the plan's own on `bearing_deg`, out from the middle and, with `through`, out
## the other side as well; it is a street like the roads' (`laid` says which lines are the plan's,
## so the fabric knows to lay their ground itself).
func _lay_street(bearing_deg: float, through: bool) -> void:
	var a := deg_to_rad(bearing_deg)
	var dir := Vector2(sin(a), cos(a))
	var out := PackedVector2Array()
	var reach := radius + 10.0
	var steps := 8
	var from := -reach if through else 0.0
	for i in range(steps + 1):
		out.append(centre + dir * lerpf(from, reach, float(i) / float(steps)))
	laid.append(lines.size())
	lines.append(out)
	arms = _arms_of(lines, centre, radius)


func layout() -> Dictionary:
	return LAYOUT.get(kind, LAYOUT["village"])


# --- the streets ----------------------------------------------------------------------------------

## A street for a place no road crosses: straight through the middle, on a bearing of its own.
func _laid_street() -> PackedVector2Array:
	var bearing := _rng.randf_range(0.0, PI)
	var dir := Vector2(sin(bearing), cos(bearing))
	var out := PackedVector2Array()
	var reach := radius + 10.0
	var steps := 12
	for i in range(steps + 1):
		out.append(centre + dir * lerpf(-reach, reach, float(i) / float(steps)))
	return out


static func _points_of(line_v: Variant) -> PackedVector2Array:
	var out := PackedVector2Array()
	if line_v is PackedVector2Array:
		return line_v
	if typeof(line_v) != TYPE_ARRAY:
		return out
	for p_v in line_v:
		if p_v is Vector2:
			out.append(p_v)
		elif typeof(p_v) == TYPE_ARRAY and (p_v as Array).size() >= 2:
			out.append(Vector2(float(p_v[0]), float(p_v[1])))
	return out


## The runs of a polyline that come within `reach` of `at`, each with one point either side so
## the run still reaches the edge of the circle rather than stopping short of it.
static func _clip(pts: PackedVector2Array, at: Vector2, reach: float) -> Array:
	var runs: Array = []
	var run := PackedVector2Array()
	for i in range(pts.size()):
		var near := pts[i].distance_to(at) <= reach
		var next_near := i + 1 < pts.size() and pts[i + 1].distance_to(at) <= reach
		var prev_near := i > 0 and pts[i - 1].distance_to(at) <= reach
		if near or next_near or prev_near:
			run.append(pts[i])
		elif run.size() > 0:
			if run.size() >= 2:
				runs.append(run)
			run = PackedVector2Array()
	if run.size() >= 2:
		runs.append(run)
	return runs


static func _touches(pts: PackedVector2Array, at: Vector2, reach: float) -> bool:
	for i in range(pts.size() - 1):
		if _segment_distance(at, pts[i], pts[i + 1]) < reach:
			return true
	return false


## The streets inside the pad, each running from the middle out. A road through the middle is
## two arms; one that ends there is one; one that only passes the place by is a single arm
## along it. Arms leaving within MERGE_DEG of each other are the same street: the longer stays.
static func _arms_of(road_lines: Array, at: Vector2, pad_radius: float) -> Array:
	var found: Array = []
	var source: Array[int] = []
	for li in range(road_lines.size()):
		var pts: PackedVector2Array = road_lines[li]
		var k := 0
		var best := INF
		for i in range(pts.size()):
			var d := pts[i].distance_to(at)
			if d < best:
				best = d
				k = i
		if best < pad_radius * 0.4:
			for dir in [1, -1]:
				var arm := _walk(pts, k, int(dir), at, pad_radius)
				if arm.size() >= 2:
					found.append(arm)
					source.append(li)
		else:
			var inside := PackedVector2Array()
			for p in pts:
				if p.distance_to(at) < pad_radius + 8.0:
					inside.append(p)
			if inside.size() >= 2:
				found.append(inside)
				source.append(li)
	var kept: Array = []
	for fi in range(found.size()):
		var pts: PackedVector2Array = found[fi]
		var length := _length(pts)
		if length < 6.0:
			continue
		var probe := _point_at(pts, minf(22.0, length))
		var bearing := fposmod(rad_to_deg(atan2(probe.x - at.x, probe.y - at.y)), 360.0)
		var merged := false
		for i in range(kept.size()):
			var other: Dictionary = kept[i]
			var diff := absf(fposmod(bearing - float(other["bearing"]) + 180.0, 360.0) - 180.0)
			if diff < MERGE_DEG:
				merged = true
				var group: Array = other["lines"]
				if not group.has(source[fi]):
					group.append(source[fi])
				if length > float(other["length"]):
					kept[i] = {"points": pts, "length": length, "bearing": bearing, "lines": group}
				break
		if not merged:
			kept.append({"points": pts, "length": length, "bearing": bearing, "lines": [source[fi]]})
	kept.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["bearing"]) < float(b["bearing"]))
	return kept


## From point `k` of a polyline along `dir` until it has left the pad.
static func _walk(pts: PackedVector2Array, k: int, dir: int, at: Vector2, pad_radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var i := k
	while i >= 0 and i < pts.size():
		out.append(pts[i])
		if pts[i].distance_to(at) > pad_radius + 8.0:
			break
		i += dir
	return out


static func _length(pts: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(pts.size() - 1):
		total += pts[i].distance_to(pts[i + 1])
	return total


static func _point_at(pts: PackedVector2Array, s: float) -> Vector2:
	return frame_on(pts, s)["p"]


## Where a street is `s` metres out from the middle, and which way it runs there.
static func frame_on(pts: PackedVector2Array, s: float) -> Dictionary:
	var walked := 0.0
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var seg := a.distance_to(b)
		if seg < 0.001:
			continue
		if walked + seg >= s or i == pts.size() - 2:
			var t := (b - a) / seg
			var f := clampf((s - walked) / seg, 0.0, 1.0)
			return {"p": a.lerp(b, f), "t": t}
		walked += seg
	return {"p": pts[0], "t": Vector2.RIGHT}


# --- boxes ------------------------------------------------------------------------------------------

## An oriented box on the ground: centre `c`, `u` along the street, `v` away from it, and the
## half-sizes along each.
static func box(c: Vector2, u: Vector2, hw: float, hd: float) -> Dictionary:
	var uu := u.normalized()
	return {"c": c, "u": uu, "v": Vector2(-uu.y, uu.x), "hw": hw, "hd": hd}


## The same box with `v` pointing the other way round `u` (the box itself is unchanged, but
## `v` is what a house means by "away from the street").
static func box_facing(c: Vector2, u: Vector2, v: Vector2, hw: float, hd: float) -> Dictionary:
	return {"c": c, "u": u.normalized(), "v": v.normalized(), "hw": hw, "hd": hd}


static func corners(b: Dictionary) -> PackedVector2Array:
	var c: Vector2 = b["c"]
	var u: Vector2 = b["u"] * float(b["hw"])
	var v: Vector2 = b["v"] * float(b["hd"])
	return PackedVector2Array([c - u - v, c + u - v, c + u + v, c - u + v])


static func contains(b: Dictionary, p: Vector2, margin := 0.0) -> bool:
	var d: Vector2 = p - b["c"]
	return absf(d.dot(b["u"])) <= float(b["hw"]) + margin and absf(d.dot(b["v"])) <= float(b["hd"]) + margin


## Separating axes: two boxes overlap unless one of their four axes parts them.
static func overlaps(a: Dictionary, b: Dictionary, margin := 0.0) -> bool:
	var ca := corners(a)
	var cb := corners(b)
	for axis in [a["u"], a["v"], b["u"], b["v"]]:
		var ax: Vector2 = axis
		var amin := INF
		var amax := -INF
		for p in ca:
			var d := p.dot(ax)
			amin = minf(amin, d)
			amax = maxf(amax, d)
		var bmin := INF
		var bmax := -INF
		for p in cb:
			var d := p.dot(ax)
			bmin = minf(bmin, d)
			bmax = maxf(bmax, d)
		if amax + margin <= bmin or bmax + margin <= amin:
			return false
	return true


## Does the segment p0-p1 come within `margin` of the box? Clipped in the box's own frame.
static func segment_hits(b: Dictionary, p0: Vector2, p1: Vector2, margin: float) -> bool:
	var c: Vector2 = b["c"]
	var u: Vector2 = b["u"]
	var v: Vector2 = b["v"]
	var a := Vector2((p0 - c).dot(u), (p0 - c).dot(v))
	var e := Vector2((p1 - c).dot(u), (p1 - c).dot(v))
	var hx := float(b["hw"]) + margin
	var hy := float(b["hd"]) + margin
	var t0 := 0.0
	var t1 := 1.0
	var d := e - a
	for axis in 2:
		var lo := -hx if axis == 0 else -hy
		var hi := hx if axis == 0 else hy
		var start := a.x if axis == 0 else a.y
		var delta := d.x if axis == 0 else d.y
		if absf(delta) < 1e-9:
			if start < lo or start > hi:
				return false
			continue
		var ta := (lo - start) / delta
		var tb := (hi - start) / delta
		if ta > tb:
			var tmp := ta
			ta = tb
			tb = tmp
		t0 = maxf(t0, ta)
		t1 = minf(t1, tb)
		if t0 > t1:
			return false
	return true


static func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 1e-9:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


# --- what is clear ----------------------------------------------------------------------------------

## Is this box free of every road, the open middle, every house and garden already planned and
## everything reserved? `house` asks for the stricter test: a house stays on the flattened ground.
func is_clear(b: Dictionary, house: bool, skip_line := -1) -> bool:
	var reach := radius - EDGE_M if house else radius + GARDEN_PAST_EDGE_M
	for p in corners(b):
		if p.distance_to(centre) > reach:
			return false
	if _nearest_distance(b, centre) < hub:
		return false
	# a segment whose bounds are nowhere near the box's (grown by the margin, within the circle round
	# it) cannot touch it: most of a road's segments are passed over without the box test
	var c: Vector2 = b["c"]
	var gx := float(b["hw"]) + ROAD_HALF_M + ROAD_CLEAR_M
	var gy := float(b["hd"]) + ROAD_HALF_M + ROAD_CLEAR_M
	var round_m := sqrt(gx * gx + gy * gy)
	for i in range(lines.size()):
		if i == skip_line:
			continue
		var pts: PackedVector2Array = lines[i]
		for j in range(pts.size() - 1):
			var p0 := pts[j]
			var p1 := pts[j + 1]
			if minf(p0.x, p1.x) > c.x + round_m or maxf(p0.x, p1.x) < c.x - round_m \
					or minf(p0.y, p1.y) > c.y + round_m or maxf(p0.y, p1.y) < c.y - round_m:
				continue
			if segment_hits(b, p0, p1, ROAD_HALF_M + ROAD_CLEAR_M):
				return false
	for other in reserved:
		if overlaps(b, other):
			return false
	for h in houses:
		if overlaps(b, h["box"], 0.05):
			return false
		var g: Dictionary = h["garden"]
		if not g.is_empty() and overlaps(b, g, 0.05):
			return false
	return true


## How close the box comes to a point: zero if the point is inside it.
static func _nearest_distance(b: Dictionary, p: Vector2) -> float:
	var d: Vector2 = p - b["c"]
	var x := maxf(absf(d.dot(b["u"])) - float(b["hw"]), 0.0)
	var y := maxf(absf(d.dot(b["v"])) - float(b["hd"]), 0.0)
	return Vector2(x, y).length()


## Whether a point is on reserved ground: a landmark's footprint, a deep place's mouth.
func is_reserved(p: Vector2) -> bool:
	for other in reserved:
		if _nearest_distance(other, p) <= 0.0:
			return true
	return false


## Keep an existing footprint out of the plan: a deep place's mouth, a door plan's apron.
func reserve_rect(r: Rect2) -> void:
	reserved.append(box(r.get_center(), Vector2.RIGHT, r.size.x * 0.5, r.size.y * 0.5))


# --- the frontage -------------------------------------------------------------------------------------

## The frame of a frontage: where on `arm`'s street, `s` metres out, on `side` (+1 to the left of
## the way out, -1 to the right), and which way is "away from the street" there.
##
## Where two roads leave on one line (the street through the town and the road to the next place,
## a few degrees apart) they are one street, and the frontage stands beyond the outer of the two:
## the street widens where they part, as a street does where a road forks off it, rather than
## a road running through somebody's front room.
func frontage(arm: int, s: float, side: float) -> Dictionary:
	var pts: PackedVector2Array = arms[arm]["points"]
	var f := frame_on(pts, s)
	var t: Vector2 = f["t"]
	var n := Vector2(-t.y, t.x) * side
	var p: Vector2 = f["p"]
	var out := 0.0
	for li in arms[arm].get("lines", []):
		var q := _closest_on(lines[int(li)], p)
		if q.distance_to(p) < 24.0:
			out = maxf(out, (q - p).dot(n))
	return {"p": p + n * out, "t": t, "n": n}


static func _closest_on(pts: PackedVector2Array, p: Vector2) -> Vector2:
	var best := pts[0]
	var best_d := INF
	for j in range(pts.size() - 1):
		var a := pts[j]
		var ab := pts[j + 1] - a
		var len2 := ab.length_squared()
		var t := 0.0 if len2 < 1e-9 else clampf((p - a).dot(ab) / len2, 0.0, 1.0)
		var q := a + ab * t
		var d := q.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = q
	return best


## A house of width `w` (along the street) and depth `d`, its front wall `setback` metres back
## from the road's edge, its middle `along` metres from the door along the front.
##
## The box's `v` points away from the street, so the house faces `-v`, and `u` is taken so that
## (u, up, v) is a right-handed frame: a house's own x axis, which is what `Building` and the
## fabric build in. On the far side of a street that runs the other way round, so a house on
## either side is a house and not its mirror image.
func house_box(fr: Dictionary, setback: float, w: float, d: float, along := 0.0) -> Dictionary:
	var n: Vector2 = fr["n"]
	var u := Vector2(n.y, -n.x)
	var front: Vector2 = fr["p"] + n * (ROAD_HALF_M + setback)
	return box_facing(front + u * along + n * (d * 0.5), u, n, w * 0.5, d * 0.5)


## The garden behind a house: the plot's own width, `depth` metres back from the back wall.
static func garden_box(house: Dictionary, width: float, depth: float) -> Dictionary:
	var v: Vector2 = house["v"]
	var c: Vector2 = house["c"] + v * (float(house["hd"]) + depth * 0.5 + 0.2)
	return box_facing(c, house["u"], v, width * 0.5, depth * 0.5)


## Puts a house that has an inside on the street. `footprint` is its ground floor in its door's
## own frame (x along the front, y back from the door), `wanted` where its door plan put the
## door. Returns the plot, or {} when no frontage in the place can take it. The street nearest
## the wanted spot wins, so the plan still decides which end of town a house is at.
func place_real(id: String, footprint: Rect2, wanted: Vector2) -> Dictionary:
	var spec := layout()
	var setback := float((spec["setback"] as Array)[0])
	var w := footprint.size.x
	var d := footprint.size.y + footprint.position.y
	var along := footprint.position.x + footprint.size.x * 0.5
	# every frontage spot, nearest the wanted door first; the first clear one is the house's
	var spots: Array = []
	for a in range(arms.size()):
		var length := minf(float(arms[a]["length"]), radius)
		var s := hub
		while s < length:
			for side_v in [1.0, -1.0]:
				var fr := frontage(a, s, float(side_v))
				var door: Vector2 = fr["p"] + (fr["n"] as Vector2) * (ROAD_HALF_M + setback)
				spots.append({"cost": door.distance_to(wanted), "arm": a, "s": s,
						"side": float(side_v), "fr": fr, "door": door})
			s += STEP_M
	spots.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["cost"]) < float(y["cost"]))
	for spot in spots:
		var fr: Dictionary = spot["fr"]
		var b := house_box(fr, setback, w, d, along)
		if not is_clear(b, true):
			continue
		var plot := {"box": b, "garden": {}, "arm": int(spot["arm"]), "side": float(spot["side"]),
				"s": float(spot["s"]), "facing": -(fr["n"] as Vector2), "door": spot["door"],
				"real": id, "setback": setback}
		plot["garden"] = _fit_garden(b, w + 1.0)
		houses.append(plot)
		return plot
	return {}


## Cuts the fabric's plots along every street, both sides, nearest the middle first so the
## houses gather round the crossing and thin out along the roads, until the place has `want`.
func fill(want: int) -> int:
	var spec := layout()
	var fr_r: Array = spec["front"]
	var gap_r: Array = spec["gap"]
	var sb_r: Array = spec["setback"]
	var dp_r: Array = spec["depth"]
	var cursors: Array = []
	for a in range(arms.size()):
		for side_v in [1.0, -1.0]:
			cursors.append({"arm": a, "side": float(side_v), "s": hub + 0.5,
					"end": minf(float(arms[a]["length"]), radius), "run": _rng.randi_range(3, 5)})
	var added := 0
	var guard := 0
	while added < want and guard < 4000:
		guard += 1
		var pick := -1
		var low := INF
		for i in range(cursors.size()):
			var cand: Dictionary = cursors[i]
			if float(cand["s"]) < float(cand["end"]) and float(cand["s"]) < low:
				low = float(cand["s"])
				pick = i
		if pick < 0:
			break
		var cur: Dictionary = cursors[pick]
		var w := _rng.randf_range(float(fr_r[0]), float(fr_r[1]))
		var d := _rng.randf_range(float(dp_r[0]), float(dp_r[1]))
		var setback := _rng.randf_range(float(sb_r[0]), float(sb_r[1]))
		var s := float(cur["s"]) + w * 0.5
		if s > float(cur["end"]):
			cur["s"] = float(cur["end"])
			continue
		var fr := frontage(int(cur["arm"]), s, float(cur["side"]))
		var b := house_box(fr, setback, w - 0.3, d)
		if is_clear(b, true):
			var door: Vector2 = fr["p"] + (fr["n"] as Vector2) * (ROAD_HALF_M + setback)
			houses.append({"box": b, "garden": _fit_garden(b, w), "arm": int(cur["arm"]),
					"side": float(cur["side"]), "s": s, "facing": -(fr["n"] as Vector2),
					"door": door, "real": "", "setback": setback})
			added += 1
			cur["s"] = float(cur["s"]) + w + _rng.randf_range(float(gap_r[0]), float(gap_r[1]))
			cur["run"] = int(cur["run"]) - 1
			if int(cur["run"]) <= 0 and kind in LANE_KINDS:
				_leave_lane(cur)
		else:
			cur["s"] = float(cur["s"]) + STEP_M
	return added


## A lane back from the street at the cursor, if the ground behind is free to take it.
func _leave_lane(cur: Dictionary) -> void:
	cur["run"] = _rng.randi_range(3, 6)
	var s := float(cur["s"]) + LANE_W * 0.5 + 0.2
	if s > float(cur["end"]) - 4.0:
		return
	var fr := frontage(int(cur["arm"]), s, float(cur["side"]))
	var n: Vector2 = fr["n"]
	var start: Vector2 = fr["p"] + n * (ROAD_HALF_M - 0.3)
	var lane := box_facing(start + n * (LANE_LEN * 0.5), Vector2(n.y, -n.x), n, LANE_W * 0.5, LANE_LEN * 0.5)
	# a lane may run out past the flattened ground, into the fields
	for h in houses:
		if overlaps(lane, h["box"]) or (not (h["garden"] as Dictionary).is_empty() and overlaps(lane, h["garden"])):
			return
	lanes.append(lane)
	reserved.append(lane)
	cur["s"] = float(cur["s"]) + LANE_W + 0.4


## As much of the garden as fits behind a house: all of it, two thirds, a third, or none.
func _fit_garden(house: Dictionary, width: float) -> Dictionary:
	var spec := layout()
	var g_r: Array = spec["garden"]
	var want := _rng.randf_range(float(g_r[0]), float(g_r[1]))
	if want < 1.5:
		return {}
	for k in [1.0, 0.66, 0.4]:
		var g := garden_box(house, width, want * float(k))
		if is_clear(g, false):
			return g
	return {}


## The open middle's wedges: between each street and the next round the compass, the bearing
## halfway between them and how wide the gap is, widest first. The well, the stalls and the
## benches stand in these, never on a road.
func wedges() -> Array:
	var out: Array = []
	var n := arms.size()
	if n == 0:
		return [{"bearing": 0.0, "width": 360.0}]
	if n == 1:
		var b := float(arms[0]["bearing"])
		return [{"bearing": fposmod(b + 180.0, 360.0), "width": 360.0}]
	for i in range(n):
		var a := float(arms[i]["bearing"])
		var b := float(arms[(i + 1) % n]["bearing"])
		var width := fposmod(b - a, 360.0)
		if width < 0.01:
			width = 360.0
		out.append({"bearing": fposmod(a + width * 0.5, 360.0), "width": width})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["width"]) > float(y["width"]))
	return out


## A point in the open middle `r` metres out on `bearing_deg`.
func hub_point(bearing_deg: float, r: float) -> Vector2:
	var a := deg_to_rad(bearing_deg)
	return centre + Vector2(sin(a), cos(a)) * r


## How far a point is from the nearest road's centre line.
func road_distance(p: Vector2) -> float:
	var best := INF
	for line_v in lines:
		var pts: PackedVector2Array = line_v
		for j in range(pts.size() - 1):
			best = minf(best, _segment_distance(p, pts[j], pts[j + 1]))
	return best
