extends Node
## The road's life on a ride (docs/WORLD_LIFE_ROADS.md): the ground probe's road walk
## (`./run.sh roads --roadlife=on|off`) with RoadLife running, or held off to compare, and building
## paced by WorldPace as it is when drawn (headless paces nothing unless told). It counts what the
## director started, skipped and took down per kilometre, and times every frame on the wall clock:
## the worst, the 99th percentile, and the frames over 50 ms, with and without the road's life, and
## the longest piece of the road's own building (WorldPace.pieces "road_life"). roadlife.json.

var on := true
var _frames: PackedInt32Array = PackedInt32Array()
var _last_us := 0
var _samples := 0
var _max_active := 0
var _start_pos := Vector3.INF
var _walked_m := 0.0
var _last_pos := Vector3.INF


func begin(road_life_on: bool) -> void:
	on = road_life_on
	RoadLife.forced = 1 if on else 0
	WorldPace.paced_override = 1
	process_priority = 1000
	_last_us = Time.get_ticks_usec()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	_frames.append(now - _last_us)
	_last_us = now


## Once a second of the game's time on the road.
func sample() -> void:
	_samples += 1
	var p := Peers.player() as Node3D
	if p != null:
		if _last_pos != Vector3.INF:
			var d := Vector2(p.global_position.x - _last_pos.x, p.global_position.z - _last_pos.z).length()
			if d < 60.0:
				_walked_m += d
		_last_pos = p.global_position
	var life := RoadLife.instance
	if life != null:
		_max_active = maxi(_max_active, life._active() + life.live_caravans.size())


func finish(out_dir: String) -> Dictionary:
	var sorted := _frames.duplicate()
	sorted.sort()
	var n := sorted.size()
	var over := 0
	for f in sorted:
		if f > 50000:
			over += 1
	var life := RoadLife.instance
	var st: Dictionary = life.stats.duplicate(true) if life != null else {}
	var piece := {}
	for k in WorldPace.pieces:
		if str(k).begins_with("road_life"):
			piece[k] = WorldPace.pieces[k]
	var started := 0
	for k in (st.get("started", {}) as Dictionary):
		started += int(st["started"][k])
	var km := maxf(_walked_m / 1000.0, 0.001)
	var out := {"road_life": on, "walked_m": _walked_m, "frames": n,
		"worst_ms": (sorted[n - 1] / 1000.0) if n > 0 else 0.0,
		"p99_ms": (sorted[int(n * 0.99)] / 1000.0) if n > 0 else 0.0,
		"over_50ms": over, "started": started, "per_km": started / km, "max_active": _max_active,
		"stats": st, "road_life_piece": piece}
	var f := FileAccess.open("%s/roadlife_%s.json" % [out_dir, "on" if on else "off"], FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(out, "  "))
	print("ROADLIFE %s: %.0f m walked, %d started (%.2f a km), most at once %d, frames %d, worst %.1f ms, p99 %.1f ms, over 50 ms %d, road_life piece %s, started %s, skipped %s, outcomes %s" % [
		"on" if on else "off", _walked_m, started, started / km, _max_active, n, out["worst_ms"], out["p99_ms"], over,
		str(piece), str(st.get("started", {})), str(st.get("skipped", {})), str(st.get("outcomes", {}))])
	return out
