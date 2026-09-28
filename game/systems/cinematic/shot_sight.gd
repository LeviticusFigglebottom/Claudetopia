class_name ShotSight
extends RefCounted
## What a shot's camera will see along its path, as the streamer's cells: the country a shot has to
## have standing before it is shown, and streaming while it plays.
##
## A cinematic used to ask for the full-detail ring round where its camera starts and what it looks
## at. A camera flies faster and sees further than a walker: the Mere from 150 m looks a kilometre
## over land its five-by-five ring never reached, and a pan sweeps across cells nobody asked for, so
## the far ground came up bare and filled in while it was watched (TRIAGE item 24).
##
## For each of SAMPLES moments of the shot, the view is walked outward along COLUMNS bearings
## across the frame, over the ground, to REACH_M: a point of ground is seen when it is inside the
## frame and nothing nearer along its bearing stands above the line to it (with TOP_M for the trees
## on it, whose tops can show over a crest). Each cell seen is wanted: at full detail (ring 1,
## grass and all) when some moment sees it within NEAR_M, at the far ring's otherwise. With it is
## kept the first moment (0..1) it is seen, so a shot can be shown once its opening is in and the
## rest can come while it plays.
##
## The ground is a callable, `ground(x, z) -> float`, as in CinematicPath, so the tests answer it
## from the runtime maps without a world.

const SAMPLES := 9
const COLUMNS := 13
## How far out a shot's cells are wanted: past the far ring's trees (WorldStreamer.VIEW_RANGE_FAR,
## 920 m), which is all a streamed cell holds that can be told apart from a kilometre away.
const REACH_M := 1000.0
## Within this a cell is wanted with its grass (the near ring's herbs reach 110 m, its bushes 190 m,
## and a moment sees a cell's near edge before its middle).
const NEAR_M := 320.0
const STEP_M := 16.0
## How tall the things on the ground may stand over a crest: a tree's crown shows over a ridge its
## foot is behind.
const TOP_M := 22.0
## The frame is taken this much wider than it is, so a cell half in the picture's edge is wanted.
const MARGIN := 1.1
## However wide a view, no more cells than this are wanted for one shot, the nearest kept.
const MAX_CELLS := 72


## The cells `path` sees from `from_u` to `to_u` of its playing: Vector2i -> [ring, first_u, nearest_m].
static func seen(path: CinematicPath, streamer: WorldStreamer, ground: Callable, from_u := 0.0,
		to_u := 1.0, aspect := 16.0 / 9.0, reach := REACH_M) -> Dictionary:
	var out: Dictionary = {}
	if path == null or streamer == null or not path.is_playable():
		return out
	for i in SAMPLES:
		var u := lerpf(from_u, to_u, float(i) / float(maxi(SAMPLES - 1, 1)))
		_look(path.pose(u), path.fov_at(u), aspect, u, streamer, ground, reach, out)
	if out.size() > MAX_CELLS:
		var keys := out.keys()
		keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return float(out[a][2]) < float(out[b][2]))
		for k in keys.slice(MAX_CELLS):
			out.erase(k)
	return out


## One moment's view added to `out`.
static func _look(tf: Transform3D, fov_deg: float, aspect: float, u: float, streamer: WorldStreamer,
		ground: Callable, reach: float, out: Dictionary) -> void:
	var eye := tf.origin
	var fwd := -tf.basis.z.normalized()
	var right := tf.basis.x.normalized()
	var up := tf.basis.y.normalized()
	var tan_v := tan(deg_to_rad(clampf(fov_deg, 5.0, 150.0)) * 0.5)
	var tan_h := tan_v * aspect
	# the ground under the eye and round it is always seen, whatever the camera looks at
	_want(out, streamer.cell_of(eye), 1, u, 0.0)
	for c in COLUMNS:
		var x := lerpf(-1.0, 1.0, float(c) / float(COLUMNS - 1)) * MARGIN
		var dir := fwd + right * x * tan_h
		var flat := Vector2(dir.x, dir.z)
		if flat.length() < 0.05:
			# looking straight down: the frame's own bearing does not exist, use its top edge's
			flat = Vector2(up.x, up.z)
		flat = flat.normalized()
		var highest := -INF
		var d := STEP_M
		while d <= reach:
			var q := Vector2(eye.x, eye.z) + flat * d
			var h := float(ground.call(q.x, q.y))
			var to := Vector3(q.x, h + TOP_M * 0.5, q.y) - eye
			var depth := to.dot(fwd)
			var slope := (h - eye.y) / d
			var crown := (h + TOP_M - eye.y) / d
			if crown >= highest and depth > 0.0:
				var sy := to.dot(up) / (depth * tan_v)
				var sx := to.dot(right) / (depth * tan_h)
				if absf(sy) <= MARGIN + 0.1 and absf(sx) <= MARGIN + 0.1:
					_want(out, streamer.cell_of(Vector3(q.x, h, q.y)), 1 if d < NEAR_M else 2, u, d)
			highest = maxf(highest, slope)
			# finer near the eye, where a cell is a wide slice of the picture
			d += maxf(STEP_M, d * 0.06)


static func _want(out: Dictionary, cell: Vector2i, ring: int, u: float, d: float) -> void:
	var had: Variant = out.get(cell, null)
	if had == null:
		out[cell] = [ring, u, d]
		return
	var h: Array = had
	h[0] = mini(int(h[0]), ring)
	h[1] = minf(float(h[1]), u)
	h[2] = minf(float(h[2]), d)


## The streamer's wish list from `seen`: Vector2i -> ring. `until_u` < 1 keeps the cells first seen
## by then.
static func rings(seen_cells: Dictionary, until_u := 1.0) -> Dictionary:
	var out: Dictionary = {}
	for c in seen_cells:
		var s: Array = seen_cells[c]
		if float(s[1]) <= until_u + 0.0001:
			out[c] = int(s[0])
	return out


## Of a wish list, the cells wanted at full detail (the near ring): what a shot waits for before it
## is shown. The far ring's cells are asked for with them and come while it plays (TRIAGE item 36:
## waiting for a kilometre of country before the first picture was most of the wait).
static func near_only(wished: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for c in wished:
		if int(wished[c]) <= 1:
			out[c] = 1
	return out


## How far round where a shot's camera starts the towns must stand before it is shown.
const TOWNS_M := 600.0


## Two wish lists as one, each cell at the nearer ring either wants it at.
static func merged(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := a.duplicate()
	for c in b:
		out[c] = mini(int(b[c]), int(out.get(c, 99)))
	return out
