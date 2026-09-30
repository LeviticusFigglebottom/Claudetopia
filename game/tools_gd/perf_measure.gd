class_name PerfMeasure
extends RefCounted
## Frame timing for the capture runner's `--measure=<frames>` (tools_gd/capture_runner.gd).
##
## `frames` leaves the game running where a shot stands and times every frame: the wall clock
## between two frames, the main thread's own CPU over it (Linux schedstat; on this machine that
## includes handing the software renderer its work), the engine's process and physics steps (the
## scripts, the streaming, the world's own work -- what a faster GPU does not make quicker), what
## is drawn, memory and the node count. Each is given as mean, p95, p99 and max.
##
## `walk` moves the camera along a fixed path at a fixed speed, a fixed step of game time a frame,
## with the streamer at the rate it streams at in play (not the capture's hurry), and counts the
## frames that ran over 33, 50 and 100 ms on the wall clock with nothing drawn: the hitches a
## player feels while the country streams in around them, whatever their GPU.
##
## (The engine's TIME_PROCESS and TIME_PHYSICS_PROCESS monitors are the worst step of the last
## second, not the frame's, so they are recorded as that and not used for a frame's cost.)
##
## `attribute` stops every script's processing in turn for a few frames and records how far the
## process and physics steps fell: a profile by subtraction, for a build without a profiler.

const WALK_STEP_S := 1.0 / 30.0
const HITCH_MS := [33.3, 50.0, 100.0]
const ATTRIBUTE_FRAMES := 15
## Frames drawn before a measured shot's exposure (the renderer is off between them).
const DRAWN_BEFORE_EXPOSURE := 3


static func _stat_path() -> String:
	var pid := OS.get_process_id()
	var p := "/proc/%d/task/%d/schedstat" % [pid, pid]
	return p if FileAccess.file_exists(p) else ""


static func _cpu_ns(path: String) -> int:
	if path.is_empty():
		return 0
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	return int(f.get_line().split(" ")[0])


static func stats(values: PackedFloat32Array) -> Dictionary:
	if values.is_empty():
		return {"mean": 0.0, "p95": 0.0, "p99": 0.0, "max": 0.0}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for v in sorted:
		total += v
	var n := sorted.size()
	return {
		"mean": snappedf(total / n, 0.01),
		"p95": snappedf(sorted[mini(n - 1, int(ceil(n * 0.95)) - 1)], 0.01),
		"p99": snappedf(sorted[mini(n - 1, int(ceil(n * 0.99)) - 1)], 0.01),
		"max": snappedf(sorted[n - 1], 0.01),
	}


## Times `n` frames as the game runs where it stands. The capture runner calls it with the renderer
## off (the software renderer's seconds a frame are not a player's GPU), so the draw figures are
## the exposure's own (perf.json's `draw_calls`) and these are the main thread's.
static func frames(host: Node, n: int) -> Dictionary:
	var tree := host.get_tree()
	var stat := _stat_path()
	var wall := PackedFloat32Array()
	var cpu := PackedFloat32Array()
	var proc := PackedFloat32Array()
	var phys := PackedFloat32Array()
	await tree.process_frame
	var last := Time.get_ticks_usec()
	var last_cpu := _cpu_ns(stat)
	for i in n:
		await tree.process_frame
		var now := Time.get_ticks_usec()
		var now_cpu := _cpu_ns(stat)
		wall.append((now - last) / 1000.0)
		cpu.append((now_cpu - last_cpu) / 1e6 if not stat.is_empty() else (now - last) / 1000.0)
		last = now
		last_cpu = now_cpu
		proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		phys.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	return {
		"frames": n,
		"frame_ms": stats(wall),
		"main_cpu_ms": stats(cpu),
		# the engine's TIME_PROCESS and TIME_PHYSICS_PROCESS are the worst step of the last second
		"process_worst_per_s_ms": stats(proc),
		"physics_worst_per_s_ms": stats(phys),
		"static_mem_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		"video_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
		"texture_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, 0.1),
		"buffer_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0, 0.1),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"objects_alive": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
	}


static func line(t: Dictionary) -> String:
	return "frame %.2f ms (p95 %.2f, p99 %.2f, max %.2f), main thread CPU %.2f, %d nodes, %.0f MB static" % [
		t["frame_ms"]["mean"], t["frame_ms"]["p95"], t["frame_ms"]["p99"], t["frame_ms"]["max"],
		t["main_cpu_ms"]["mean"], int(t["nodes"]),
		float(t["static_mem_mb"])]


## `{"label", "path": [[x, z], ...], "speed": m/s, "height": m above the ground, "time": hours,
##   "weather": id}`: the camera goes along the path at `speed`, WALK_STEP_S of game time a frame.
static func walk(host: Node, world: World, spec: Dictionary, cells_per_frame: int) -> Dictionary:
	var tree := host.get_tree()
	var pts: Array[Vector2] = []
	for p in spec.get("path", []):
		pts.append(Vector2(float(p[0]), float(p[-1])))
	if pts.size() < 2 or world == null or world.fly_camera == null:
		return {}
	if spec.has("time"):
		WorldClock.set_time(float(spec["time"]))
	if spec.has("weather"):
		host.call("_force_weather", str(spec["weather"]))
	var cam := world.fly_camera
	var height := float(spec.get("height", 1.7))
	var speed := float(spec.get("speed", 6.0))
	var at := func(d: float) -> Vector3:
		var left := d
		for i in pts.size() - 1:
			var seg := pts[i].distance_to(pts[i + 1])
			if left <= seg or i == pts.size() - 2:
				var q := pts[i].lerp(pts[i + 1], clampf(left / maxf(seg, 0.001), 0.0, 1.0))
				return Vector3(q.x, world.provider.get_height(q.x, q.y) + height, q.y)
			left -= seg
		return Vector3.ZERO
	var length := 0.0
	for i in pts.size() - 1:
		length += pts[i].distance_to(pts[i + 1])
	# stand at the start with everything built, as a player who has been standing there is
	var start: Vector3 = at.call(0.0)
	world.move_target(start, at.call(8.0))
	var waited := 0
	while waited < 600 and not (world.streamer.is_ring_loaded() and world.streamer.instance_count() > 0):
		await tree.process_frame
		waited += 1
	for _i in 30:
		await tree.process_frame
	var hurried := world.streamer.cells_per_frame
	world.streamer.cells_per_frame = cells_per_frame
	Log.info("Capture", "walk %s: begins, %.0f m at %.1f m/s" % [str(spec.get("label", "walk")), length, speed])
	var stat := _stat_path()
	var wall := PackedFloat32Array()
	var cpu := PackedFloat32Array()
	var build := PackedFloat32Array()
	var hitches := {}
	for h in HITCH_MS:
		hitches[str(h)] = 0
	var d := 0.0
	var last := Time.get_ticks_usec()
	var last_cpu := _cpu_ns(stat)
	var frames := 0
	var cells_built := 0
	var mem_peak := 0.0
	while d < length:
		d += speed * WALK_STEP_S
		var pos: Vector3 = at.call(minf(d, length))
		var ahead: Vector3 = at.call(minf(d + 12.0, length + 12.0))
		cam.move_to(pos, Vector3(ahead.x, pos.y - 1.0, ahead.z) if ahead.distance_to(pos) > 1.0 else null)
		await tree.process_frame
		frames += 1
		var now := Time.get_ticks_usec()
		var now_cpu := _cpu_ns(stat)
		wall.append((now - last) / 1000.0)
		cpu.append((now_cpu - last_cpu) / 1e6 if not stat.is_empty() else (now - last) / 1000.0)
		last = now
		last_cpu = now_cpu
		for h in HITCH_MS:
			if wall[-1] > h:
				hitches[str(h)] += 1
		build.append(float(world.streamer.done_frame_build.y))
		cells_built += world.streamer.done_frame_build.x
		mem_peak = maxf(mem_peak, Performance.get_monitor(Performance.MEMORY_STATIC))
	world.streamer.cells_per_frame = hurried
	var out := {
		"label": str(spec.get("label", "walk")),
		"length_m": snappedf(length, 0.1), "speed": speed, "frames": frames,
		"frame_ms": stats(wall), "main_cpu_ms": stats(cpu),
		"streamer_build_ms": stats(build),
		"cells_built": cells_built,
		"hitches_over_ms": hitches,
		"static_mem_peak_mb": snappedf(mem_peak / 1048576.0, 0.1),
		"nodes_end": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
	}
	Log.info("Capture", "walk %s: %d frames, frame mean %.2f p99 %.2f max %.2f ms, frames over %s" % [
		out["label"], frames, out["frame_ms"]["mean"], out["frame_ms"]["p99"],
		out["frame_ms"]["max"], JSON.stringify(hitches)])
	return out


## Stops each script's processing in turn (every node running it) for ATTRIBUTE_FRAMES frames and
## records how far the process and physics steps fell, against the frames either side with it on.
static func attribute(host: Node) -> Array:
	var tree := host.get_tree()
	var groups := {}
	var stack: Array[Node] = [tree.root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n == host:
			continue
		var s: Script = n.get_script()
		var key: String = s.resource_path if s != null and not s.resource_path.is_empty() else n.get_class()
		if not (n.is_processing() or n.is_physics_processing()):
			continue
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(n)
	var rows: Array = []
	for key: String in groups:
		var nodes: Array = groups[key]
		var on := await _work(tree, ATTRIBUTE_FRAMES)
		var was: Array = []
		for n: Variant in nodes:
			if is_instance_valid(n):
				var node := n as Node
				was.append([node, node.is_processing(), node.is_physics_processing()])
				node.set_process(false)
				node.set_physics_process(false)
		var off := await _work(tree, ATTRIBUTE_FRAMES)
		for w: Array in was:
			var alive: Variant = w[0]
			if is_instance_valid(alive):
				(w[0] as Node).set_process(w[1])
				(w[0] as Node).set_physics_process(w[2])
		var after := await _work(tree, ATTRIBUTE_FRAMES)
		var base := (on + after) * 0.5
		rows.append({"script": key, "nodes": nodes.size(),
			"process_ms": snappedf(base.x - off.x, 0.01), "physics_ms": snappedf(base.y - off.y, 0.01),
			"frame_ms": snappedf(base.z - off.z, 0.01)})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["frame_ms"]) > float(b["frame_ms"]))
	for r in rows.slice(0, 20):
		print("CPUATTR %-60s %4d nodes  frame %6.2f  process %6.2f  physics %6.2f" % [r["script"], r["nodes"], r["frame_ms"], r["process_ms"], r["physics_ms"]])
	return rows


## Median process, physics and wall-clock frame ms over `n` frames.
static func _work(tree: SceneTree, n: int) -> Vector3:
	await tree.process_frame
	var p := PackedFloat32Array()
	var f := PackedFloat32Array()
	var w := PackedFloat32Array()
	var last := Time.get_ticks_usec()
	for i in n:
		await tree.process_frame
		p.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		f.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		w.append((Time.get_ticks_usec() - last) / 1000.0)
		last = Time.get_ticks_usec()
	p.sort()
	f.sort()
	w.sort()
	return Vector3(p[n / 2], f[n / 2], w[n / 2])
