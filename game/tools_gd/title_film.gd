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

const MENU_SCENE := "res://ui/menus/main_menu.tscn"
const CAP_S := 600.0

var out_dir := ""
var preset := "medium"
var shots_wanted := -1
var film_cut := false
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
	if out_dir.is_empty():
		print("TITLE_FILM: --out=<dir> is needed")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	Settings.persist = false
	Settings.apply_graphics_preset(preset)
	report["preset"] = preset
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
	# the slowest frame while the world stands up behind the menu: what a player's hand would feel
	var slowest := 0.0
	var last := Time.get_ticks_usec()
	while not vista.is_showing() and vista.phase != TitleVista.Phase.GONE:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		slowest = maxf(slowest, float(now - last) / 1000.0)
		last = now
		if Time.get_ticks_msec() - _t0 > int(CAP_S * 1000.0):
			break
	report["vista_up_ms"] = Time.get_ticks_msec() - _t0
	report["slowest_frame_before_up_ms"] = slowest
	if not vista.is_showing():
		print("TITLE_FILM: the country never came up")
		_finish(1)
		return
	var count: int = vista._shots.size() if shots_wanted < 0 else mini(shots_wanted, vista._shots.size())
	var cut_done := false
	for n in count:
		var index := vista.index
		var id := vista.current_shot_id()
		var duration := float((vista._shots[index] as Dictionary).get("duration", 10.0))
		var entry := {"index": index, "id": id, "cells_ready": bool(vista.shown[-1]["cells_ready"]) if not vista.shown.is_empty() else false}
		# the middle of the shot
		var worst := 0.0
		last = Time.get_ticks_usec()
		while vista._t < duration * 0.5 and vista.index == index:
			await get_tree().process_frame
			var now2 := Time.get_ticks_usec()
			worst = maxf(worst, float(now2 - last) / 1000.0)
			last = now2
		await RenderingServer.frame_post_draw
		entry["draw_calls"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		entry["primitives"] = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		entry["camera"] = vista.camera.global_position if vista.camera != null else Vector3.ZERO
		await _save("%02d_%s" % [n, id])
		# the cut: a frame as the dip closes, at its darkest, and as the next shot opens
		if film_cut and not cut_done:
			cut_done = true
			var k := 0
			var cut_until := Time.get_ticks_msec() + 12000
			while Time.get_ticks_msec() < cut_until and k < 8:
				await get_tree().create_timer(0.45).timeout
				await _save("cut_%02d_%s" % [k, TitleVista.Phase.keys()[vista.phase]])
				k += 1
		# on to the next shot, timing the frames through its dip
		while vista.index == index and vista.phase != TitleVista.Phase.GONE:
			await get_tree().process_frame
			var now3 := Time.get_ticks_usec()
			worst = maxf(worst, float(now3 - last) / 1000.0)
			last = now3
			if Time.get_ticks_msec() - _t0 > int(CAP_S * 1000.0):
				break
		while vista.phase == TitleVista.Phase.DIP_IN:
			await get_tree().process_frame
		entry["slowest_frame_ms"] = worst
		(report["shots"] as Array).append(entry)
		print("TITLE_FILM: %-24s cells %s, %d draws, %.2f M prims, slowest frame %.0f ms" % [id,
				"in" if entry["cells_ready"] else "NOT in", entry["draw_calls"], float(entry["primitives"]) / 1e6, worst])
	report["shown"] = vista.shown
	_finish(0)


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
