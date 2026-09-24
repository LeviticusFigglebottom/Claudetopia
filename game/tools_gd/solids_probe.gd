extends Node3D
## What the solid scatter costs (world/scatter_solids.gd), where there is most of it: the near ring
## streamed in round a point on the built world, its shapes stood tick by tick as the game stands
## them, then a body the player's size walked round a circle through it.
##
##   godot --headless --path game --audio-driver Dummy res://tools_gd/solids_probe.tscn -- \
##     [--at=label:x,z ...] [--out=<abs dir>]
##
## Without --at it measures the densest wood of the built world (Hearthvale's, about 3200, 2688:
## 8 900 solids in its 3x3 cells) and Merrowby (250, 1330). For each it reports the shapes and
## bodies stood, the ticks and the worst tick it took to stand them, and what one body's
## move_and_slide costs walking there with the scatter in its mask and without it. Writes
## <out>/solids.json and prints a table.

const DEFAULT_AT := {"densest_wood": Vector2(3200.0, 2688.0), "merrowby": Vector2(250.0, 1330.0)}
const WALK_TICKS := 600
const WALK_RADIUS_M := 25.0
const WALK_SPEED := 4.5

var out_dir := ""
var points: Dictionary = {}
var results: Array = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
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
		ScatterSolids.stats[key] = 0
	var t0 := Time.get_ticks_msec()
	streamer.setup(provider, target)
	var ticks := 0
	while ticks < 6000 and (not streamer.is_ring_loaded(streamer.full_ring)
			or streamer.solids == null or streamer.solids.pending() > 0):
		await get_tree().physics_frame
		ticks += 1
	var r := {
		"label": label, "at": [at.x, at.y],
		"load_s": float(Time.get_ticks_msec() - t0) / 1000.0,
		"cells": streamer.solids.body_count() if streamer.solids != null else 0,
		"shapes": streamer.solids.shape_count() if streamer.solids != null else 0,
		"stand_ticks": int(ScatterSolids.stats["ticks"]),
		"stand_us_total": int(ScatterSolids.stats["stood_us_total"]),
		"stand_us_worst_tick": int(ScatterSolids.stats["stood_us_max"]),
	}
	# the shapes of the cell the point is in, and the most of any one cell
	var most := 0
	var here := 0
	if streamer.solids != null:
		for body in streamer.solids.bodies():
			var n := PhysicsServer3D.body_get_shape_count(body)
			most = maxi(most, n)
			var p: Transform3D = PhysicsServer3D.body_get_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM)
			if absf(p.origin.x - target.global_position.x) <= 128.0 and absf(p.origin.z - target.global_position.z) <= 128.0:
				here = n
	r["shapes_in_its_cell"] = here
	r["shapes_most_in_a_cell"] = most
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


func _report() -> void:
	print("SOLIDS: %-14s %6s %6s %9s %10s %10s %11s %10s %10s %8s" % ["where", "cells", "shapes",
			"in cell", "most/cell", "ticks", "worst tick", "stand ms", "walk us", "without"])
	for r in results:
		print("SOLIDS: %-14s %6d %6d %9d %10d %10d %8d us %10.1f %10.1f %8.1f" % [r["label"], r["cells"], r["shapes"],
				r["shapes_in_its_cell"], r["shapes_most_in_a_cell"], r["stand_ticks"], r["stand_us_worst_tick"],
				float(r["stand_us_total"]) / 1000.0, r["walk_us_with"], r["walk_us_without"]])
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
		var f := FileAccess.open(out_dir.path_join("solids.json"), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(results, "  "))
