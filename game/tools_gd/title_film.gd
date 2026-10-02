extends Node
## Films the title screen as a player meets it (ui/menus/title_vista.gd): the menu scene stood up as
## the game stands it, then a frame of each shot of the country behind it, a few frames either side
## of a cut, and what each cost to draw. Drawn, so it runs under a display:
##
##   xvfb-run -a -s '-screen 0 1600x900x24' godot --path game --rendering-driver opengl3 \
##     --audio-driver Dummy --resolution 1600x900 res://tools_gd/title_film.tscn -- \
##     --out=<abs dir> [--preset=medium] [--shots=N] [--cut]
##
## Writes <out>/NN_<shot>.png at the middle of each shot, <out>/cut_NN.png around the first cut with
## --cut, and <out>/title_film.json: when the menu took input, when the country came up, and for
## each shot whether its cells were in when it was shown, its draw calls and primitives, and the
## slowest frame while it played. Nothing is written to the player's settings.
##
## `--video=<fps>` films every shot whole instead, a frame each 1/fps of its time, as JPEGs
## (<out>/v_NNNNN.jpg) with the menu hidden, for the title's filmed country (TitleReel,
## tools/title_reel.sh, which encodes them). Run it with the engine's `--fixed-fps <fps>`, so the
## water, the clouds and the trees move by 1/fps a frame however long this machine takes to draw one.

const MENU_SCENE := "res://ui/menus/main_menu.tscn"
const CAP_S := 600.0

var out_dir := ""
var preset := "medium"
var shots_wanted := -1
var film_cut := false
## Frames a second of a shot's time, for the reel (0: stills only).
var video_fps := 0
var report := {"shots": []}
var _menu: Node = null
var _t0 := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--preset="):
			preset = a.substr(9)
		elif a.begins_with("--shots="):
			shots_wanted = int(a.substr(8))
		elif a == "--cut":
			film_cut = true
		elif a.begins_with("--video="):
			video_fps = int(a.substr(8))
		elif a == "--no-sight":
			TitleVista.sight_streaming = false
	if out_dir.is_empty():
		print("TITLE_FILM: --out=<dir> is needed")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	Settings.persist = false
	Settings.apply_graphics_preset(preset)
	# the live country is what is filmed, whatever the preset shows a player (Low and Medium the film)
	Settings.set_value("graphics", "title_vista", true)
	Settings.set_value("graphics", "title_live", true)
	report["preset"] = preset
	report["sight"] = TitleVista.sight_streaming
	_run.call_deferred()


func _run() -> void:
	_t0 = Time.get_ticks_msec()
	_menu = (load(MENU_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child(_menu)
	await get_tree().process_frame
	var focused := get_viewport().gui_get_focus_owner()
	report["menu_focus_ms"] = Time.get_ticks_msec() - _t0
	report["menu_focus"] = str(focused.get("text")) if focused != null else ""
	var vista: TitleVista = _menu.get("vista")
	if vista == null:
		print("TITLE_FILM: no vista (setting off, no world, or headless)")
		_finish(1)
		return
	# the software renderers here draw a frame in seconds: the caps a player's machine gets before
	# the first shot (TitleVista.LONG_FRAME_S, FIRST_SHOW_CAP_S) would end the film before it began
	vista.long_frame_s = 600.0
	vista.first_show_cap_s = 3600.0
	# the slowest frame while the world stands up behind the menu: what a player's hand would feel
	# and every frame longer than a quarter second, with what the vista was doing: where a gap is
	var slowest := 0.0
	var frames := 0
	var long_frames: Array = []
	var last := Time.get_ticks_usec()
	while not vista.is_showing() and vista.phase != TitleVista.Phase.GONE:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var gap := float(now - last) / 1000.0
		slowest = maxf(slowest, gap)
		frames += 1
		if gap > 250.0:
			long_frames.append({"at_ms": Time.get_ticks_msec() - _t0, "gap_ms": int(gap),
					"phase": TitleVista.Phase.keys()[vista.phase],
					"world": (vista.world.stand_up_ms.duplicate() if vista.world != null else {}),
					# where it went: scripts' _process, physics ticks (and how many), or neither (the renderer)
					"process_ms": int(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0),
					"physics_ms": int(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0),
					"navigation_ms": int(Performance.get_monitor(Performance.TIME_NAVIGATION_PROCESS) * 1000.0),
					"cells": vista.world.streamer.loaded_count() if vista.world != null and vista.world.streamer != null else 0,
					"worst_build": str(vista.world.streamer.worst_frame_build) if vista.world != null and vista.world.streamer != null else ""})
		last = now
		if Time.get_ticks_msec() - _t0 > int(CAP_S * 1000.0):
			break
	report["vista_up_ms"] = Time.get_ticks_msec() - _t0
	report["slowest_frame_before_up_ms"] = slowest
	report["frames_before_up"] = frames
	report["long_frames_before_up"] = long_frames
	report["stand_up_ms"] = vista.world.stand_up_ms if vista.world != null else {}
	print("TITLE_FILM: %d frames before the country came up, the slowest %.0f ms; the world stood up in %s"
			% [frames, slowest, str(report["stand_up_ms"])])
	if not vista.is_showing():
		print("TITLE_FILM: the country never came up")
		_finish(1)
		return
	# From here the shots are posed rather than played: this machine draws a frame in seconds, and a
	# shot played in real time would be a handful of frames. Each is posed half way through, its
	# country waited for, and drawn; the dip between the first two is drawn at five points.
	var count: int = vista._shots.size() if shots_wanted < 0 else mini(shots_wanted, vista._shots.size())
	if video_fps > 0:
		await _film(vista, count)
		report["shown"] = vista.shown
		_finish(0)
		return
	for n in count:
		var entry := await _still(vista, n, 0.5, "%02d_%s" % [n, str((vista._shots[n] as Dictionary).get("id", ""))])
		(report["shots"] as Array).append(entry)
		print("TITLE_FILM: %-24s cells %s, %d of %d seen standing, %d loaded, %d draws, %.2f M prims" % [entry["id"],
				"in" if entry["cells_ready"] else "NOT in", entry["seen_standing"][0], entry["seen_standing"][1],
				entry["loaded"], entry["draw_calls"], float(entry["primitives"]) / 1e6])
	if film_cut and count >= 2:
		await _still(vista, 0, 0.97, "cut_0_end_of_first")
		for pair in [[0.5, "cut_1_dipping"], [1.0, "cut_2_dark"]]:
			vista.dip.modulate.a = float(pair[0])
			await _save(str(pair[1]))
		await _still(vista, 1, 0.0, "cut_3_next_opens", 0.5)
		await _still(vista, 1, 0.08, "cut_4_next")
	report["shown"] = vista.shown
	_finish(0)


## Every frame of the first `count` shots, the menu hidden: <out>/v_NNNNN.jpg, and in the report each
## shot's first frame and frame count, the frame rate, the dips' lengths and the dark they dip to.
func _film(vista: TitleVista, count: int) -> void:
	for c in _menu.get_children():
		if c is CanvasItem:
			(c as CanvasItem).visible = false
	var reel := {"fps": video_fps, "dark": "#" + (_menu.get("_back") as ColorRect).color.to_html(false),
			"dip_in_s": TitleVista.DIP_IN_S, "dip_out_s": TitleVista.DIP_OUT_S, "shots": []}
	var frame := 0
	var t_start := Time.get_ticks_msec()
	for i in count:
		var duration := float((vista._shots[i] as Dictionary).get("duration", 10.0))
		var n := roundi(duration * video_fps)
		var first := frame
		var slowest := 0
		for k in n:
			var t := float(k) / float(video_fps)
			var t0 := Time.get_ticks_msec()
			if k == 0:
				vista.scrub(i, 0.0)
				var until := Time.get_ticks_msec() + 300000
				while not vista.cells_in() and Time.get_ticks_msec() < until:
					await get_tree().process_frame
				for w in 4:
					await get_tree().process_frame
			else:
				vista._t = t
				vista._pose(i, t)
				# a camera that has moved into cells not yet in waits for them, a few frames at most
				var waits := 0
				while not vista.cells_in() and waits < 30:
					await get_tree().process_frame
					waits += 1
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.save_jpg("%s/v_%05d.jpg" % [out_dir, frame], 0.95)
			frame += 1
			slowest = maxi(slowest, Time.get_ticks_msec() - t0)
		(reel["shots"] as Array).append({"id": str((vista._shots[i] as Dictionary).get("id", "")), "first": first,
				"frames": n, "slowest_frame_ms": slowest})
		print("TITLE_FILM: filmed %s, %d frames (%d to %d), slowest %d ms, %.0f s in" % [
				str((vista._shots[i] as Dictionary).get("id", "")), n, first, frame - 1, slowest,
				(Time.get_ticks_msec() - t_start) / 1000.0])
	report["reel"] = reel


## Shot `i` posed `u` of the way through, its country waited for, drawn with the dip at `dark`, and
## saved; what it cost to draw.
func _still(vista: TitleVista, i: int, u: float, name: String, dark := 0.0) -> Dictionary:
	vista.scrub(i, u)
	var until := Time.get_ticks_msec() + 300000
	while not vista.cells_in() and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	var came := vista.cells_in()
	if not came:
		print("TITLE_FILM: %s is waiting for: %s" % [vista.current_shot_id(), vista.waiting_for()])
	for k in 4:
		await get_tree().process_frame
	vista.dip.modulate.a = dark
	await RenderingServer.frame_post_draw
	# the bare-ground measure: of the cells this very moment sees (ShotSight), how many are standing
	var streamer := vista.world.streamer
	var now_seen := streamer.standing_of(ShotSight.rings(ShotSight.seen(vista.path_of(i), streamer,
			Callable(vista, "_surface"), u, u, vista._aspect(), vista._reach(streamer))))
	var entry := {"index": i, "id": vista.current_shot_id(), "u": u, "cells_ready": came,
			"seen_standing": [now_seen.x, now_seen.y], "loaded": streamer.loaded_count(),
			"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
			"camera": vista.camera.global_position}
	await _save(name)
	return entry


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, name])


func _finish(code: int) -> void:
	print("TITLE_FILM: menu took focus at %s ms, the country came up at %s ms" % [str(report.get("menu_focus_ms", "?")), str(report.get("vista_up_ms", "?"))])
	var f := FileAccess.open(out_dir.path_join("title_film.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  ", false))
		f.close()
	if _menu != null and is_instance_valid(_menu):
		_menu.queue_free()
	await get_tree().process_frame
	get_tree().quit(code)
