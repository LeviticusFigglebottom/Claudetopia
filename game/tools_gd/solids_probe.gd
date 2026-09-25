extends Node3D
## What the solid scatter costs (world/scatter_solids.gd), where there is most of it: the near ring
## streamed in round a point on the built world, its shapes stood tick by tick as the game stands
## them, then a body the player's size walked round a circle through it.
##
##   godot --headless --path game --audio-driver Dummy res://tools_gd/solids_probe.tscn -- \
##     [--at=label:x,z ...] [--out=<abs dir>] [--join-each] [--no-solids]
##
## Without --at it measures the densest wood of the built world (Hearthvale's, about 3200, 2688:
## 8 900 solids in its 3x3 cells), Merrowby's street (900, 2350) and the Stair Head. For each it reports the shapes and
## bodies stood, the ticks and the worst tick it took to stand them, and what one body's
## move_and_slide costs walking there with the scatter in its mask and without it. Writes
## <out>/solids.json and prints a table.

const DEFAULT_AT := {"densest_wood": Vector2(3200.0, 2688.0), "merrowby": Vector2(900.0, 2350.0), "stair_head": Vector2(-1922.0, 3708.0)}
const WALK_TICKS := 600
const WALK_RADIUS_M := 25.0
const WALK_SPEED := 4.5

var out_dir := ""
## `--no-solids`: the ring streamed with no solid scatter, for the physics tick it costs without it
var no_solids := false
var points: Dictionary = {}
var results: Array = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--no-solids":
			no_solids = true
		elif a == "--join-each":
			ScatterSolids.join_whole = false
		elif a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--at="):
			var v := a.substr(5)
			var label := "point_%d" % points.size()
			if v.contains(":"):
				label = v.get_slice(":", 0)
				v = v.get_slice(":", 1)
			points[label] = Vector2(float(v.get_slice(",", 0)), float(v.get_slice(",", 1)))
	if points.is_empty():
		points = DEFAULT_AT
	Settings.persist = false
	_run.call_deferred()


func _run() -> void:
	var provider := TerrainProvider.new()
	add_child(provider)
	if not provider.load_data():
		print("SOLIDS: no built world")
		get_tree().quit(2)
		return
	for label in points:
		results.append(await _measure(str(label), points[label], provider))
	_report()
	get_tree().quit(0)


func _measure(label: String, at: Vector2, provider: TerrainProvider) -> Dictionary:
	var target := Node3D.new()
	add_child(target)
	target.global_position = Vector3(at.x, provider.get_height(at.x, at.y), at.y)
	var streamer := WorldStreamer.new()
	streamer.name = "Streamer_" + label
	add_child(streamer)
	for key in ScatterSolids.stats:
		ScatterSolids.stats[key] = "" if key == "asset_worst" else ([] if key in ["tick_us", "tick_log"] else 0)
	var t0 := Time.get_ticks_msec()
	streamer.solid_scatter = not no_solids
	streamer.setup(provider, target)
	var ticks := 0
	# the engine's whole physics tick (the streamer, the shapes, and the step that files them), the
	# worst of the load and the mean
	var physics_worst := 0.0
	var physics_sum := 0.0
	while ticks < 6000 and (not streamer.is_ring_loaded(streamer.full_ring)
			or (not no_solids and (streamer.solids == null or streamer.solids.pending() > 0))):
		await get_tree().physics_frame
		ticks += 1
		var ms := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		physics_worst = maxf(physics_worst, ms)
		physics_sum += ms
	var r := {
		"label": label, "at": [at.x, at.y],
		"load_s": float(Time.get_ticks_msec() - t0) / 1000.0,
		"cells": int(ScatterSolids.stats["cells"]),
		"bodies": streamer.solids.body_count() if streamer.solids != null else 0,
		"assets": int(ScatterSolids.stats["assets"]),
		"asset_ms_total": float(ScatterSolids.stats["asset_us_total"]) / 1000.0,
		"asset_ms_worst": float(ScatterSolids.stats["asset_us_max"]) / 1000.0,
		"asset_worst": str(ScatterSolids.stats["asset_worst"]),
		"join_ms_worst": float(ScatterSolids.stats["join_us_max"]) / 1000.0,
		"tick_us": _spread(ScatterSolids.stats["tick_us"]),
		"work": _work(ScatterSolids.stats["tick_log"]),
		"physics_ms_worst": physics_worst,
		"physics_ms_mean": physics_sum / maxf(float(ticks), 1.0),
		"shapes": streamer.solids.shape_count() if streamer.solids != null else 0,
		"stand_ticks": int(ScatterSolids.stats["ticks"]),
		"stand_us_total": int(ScatterSolids.stats["stood_us_total"]),
		"stand_us_worst_tick": int(ScatterSolids.stats["stood_us_max"]),
	}
	# the most shapes in any one body (a block)
	var most := 0
	if streamer.solids != null:
		for body in streamer.solids.bodies():
			most = maxi(most, PhysicsServer3D.body_get_shape_count(body))
	r["shapes_most_in_a_body"] = most
	await get_tree().physics_frame
	r["walk_us_with"] = await _walk(target.global_position, provider, true)
	r["walk_us_without"] = await _walk(target.global_position, provider, false)
	r["stopped_with"] = _stops
	streamer.queue_free()
	target.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	return r


var _stops := 0


## A body the player's size walked round a circle for WALK_TICKS ticks: the mean microseconds of its
## move_and_slide, with the scatter in its mask or without.
func _walk(centre: Vector3, provider: TerrainProvider, with_scatter: bool) -> float:
	var body := CharacterBody3D.new()
	body.collision_layer = 1 << 1
	body.collision_mask = Actor.BODY_MASK if with_scatter else (Actor.BODY_MASK & ~ScatterSolids.LAYER)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0.0, 0.9, 0.0)
	body.add_child(cs)
	add_child(body)
	body.global_position = centre + Vector3(WALK_RADIUS_M, 0.0, 0.0)
	var total := 0
	_stops = 0
	for i in WALK_TICKS:
		var a := float(i) / float(WALK_TICKS) * TAU * 3.0
		var goal := centre + Vector3(cos(a), 0.0, sin(a)) * WALK_RADIUS_M
		var to := goal - body.global_position
		to.y = 0.0
		var v := to.normalized() * WALK_SPEED if to.length() > 0.05 else Vector3.ZERO
		body.velocity = v
		var t0 := Time.get_ticks_usec()
		body.move_and_slide()
		total += Time.get_ticks_usec() - t0
		if body.get_slide_collision_count() > 0:
			_stops += 1
		var p := body.global_position
		body.global_position = Vector3(p.x, provider.get_height(p.x, p.z), p.z)
		await get_tree().physics_frame
	body.queue_free()
	return float(total) / float(WALK_TICKS)


## What the ticks did: the most shapes stood, joined and assets made in any one tick, the worst
## five ticks with their work ([µs, stood, joined shapes, assets made, µs sorting]), the worst sort,
## and the median cost
## of a shape stood (µs) over the ticks that did nothing else, which a loaded machine's pre-emption
## does not move as it moves a worst tick.
static func _work(log: Array) -> Dictionary:
	if log.is_empty():
		return {}
	var most_stood := 0
	var most_joined := 0
	var most_assets := 0
	var worst_sort := 0
	var per_shape: Array = []
	for t: Array in log:
		most_stood = maxi(most_stood, int(t[1]))
		most_joined = maxi(most_joined, int(t[2]))
		most_assets = maxi(most_assets, int(t[3]))
		worst_sort = maxi(worst_sort, int(t[4]))
		if int(t[1]) >= 10 and int(t[2]) == 0 and int(t[3]) == 0 and int(t[4]) == 0:
			per_shape.append(float(t[0]) / float(t[1]))
	per_shape.sort()
	var worst := log.duplicate()
	worst.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]))
	return {"most_stood": most_stood, "most_joined_shapes": most_joined, "most_assets": most_assets, "worst_sort_us": worst_sort,
			"median_us_per_shape": per_shape[per_shape.size() / 2] if not per_shape.is_empty() else -1.0,
			"worst": worst.slice(0, 5)}


## The ticks' spread: median, 90th, 99th percentile and worst (µs), and how many were over 2 ms.
static func _spread(ticks: Array) -> Dictionary:
	var a := ticks.duplicate()
	a.sort()
	if a.is_empty():
		return {}
	var at := func(q: float) -> int: return int(a[mini(a.size() - 1, int(q * float(a.size())))])
	var over := 0
	for t in a:
		over += 1 if int(t) > 2000 else 0
	return {"p50": at.call(0.5), "p90": at.call(0.9), "p99": at.call(0.99), "max": int(a[-1]), "over_2ms": over, "n": a.size()}


func _report() -> void:
	print("SOLIDS: %-14s %5s %6s %6s %6s %9s %6s %11s %9s %11s %10s %8s %8s" % ["where", "cells", "bodies", "shapes",
			"assets", "most/body", "ticks", "worst tick", "stand ms", "physics ms", "worst", "walk us", "without"])
	for r in results:
		print("SOLIDS: %-14s %5d %6d %6d %6d %9d %6d %8d us %9.1f %8.2f avg %7.1f %8.1f %8.1f" % [r["label"], r["cells"], r["bodies"],
				r["shapes"], r["assets"], r["shapes_most_in_a_body"], r["stand_ticks"], r["stand_us_worst_tick"],
				float(r["stand_us_total"]) / 1000.0, r["physics_ms_mean"], r["physics_ms_worst"], r["walk_us_with"], r["walk_us_without"]])
	for r in results:
		print("SOLIDS: %-14s work %s" % [r["label"], str(r["work"])])
		print("SOLIDS: %-14s assets made in %.1f ms, the worst %s in %.1f ms; worst join %.2f ms; ticks (us) %s" % [r["label"],
				r["asset_ms_total"], r["asset_worst"], r["asset_ms_worst"], r["join_ms_worst"], str(r["tick_us"])])
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		var f := FileAccess.open(out_dir.path_join("solids.json"), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(results, "  "))
