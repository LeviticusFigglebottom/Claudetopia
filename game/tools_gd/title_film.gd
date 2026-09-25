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
	# From here the shots are posed rather than played: this machine draws a frame in seconds, and a
	# shot played in real time would be a handful of frames. Each is posed half way through, its
	# country waited for, and drawn; the dip between the first two is drawn at five points.
	var count: int = vista._shots.size() if shots_wanted < 0 else mini(shots_wanted, vista._shots.size())
	for n in count:
		var entry := await _still(vista, n, 0.5, "%02d_%s" % [n, str((vista._shots[n] as Dictionary).get("id", ""))])
		(report["shots"] as Array).append(entry)
		print("TITLE_FILM: %-24s cells %s, %d draws, %.2f M prims" % [entry["id"],
				"in" if entry["cells_ready"] else "NOT in", entry["draw_calls"], float(entry["primitives"]) / 1e6])
	if film_cut and count >= 2:
		await _still(vista, 0, 0.97, "cut_0_end_of_first")
		for pair in [[0.5, "cut_1_dipping"], [1.0, "cut_2_dark"]]:
			vista.dip.modulate.a = float(pair[0])
			await _save(str(pair[1]))
		await _still(vista, 1, 0.0, "cut_3_next_opens", 0.5)
		await _still(vista, 1, 0.08, "cut_4_next")
	report["shown"] = vista.shown
	_finish(0)


## Shot `i` posed `u` of the way through, its country waited for, drawn with the dip at `dark`, and
## saved; what it cost to draw.
func _still(vista: TitleVista, i: int, u: float, name: String, dark := 0.0) -> Dictionary:
	vista.scrub(i, u)
	var until := Time.get_ticks_msec() + 300000
	while not vista.cells_in() and Time.get_ticks_msec() < until:
		await get_tree().process_frame
	var came := vista.cells_in()
	for k in 4:
		await get_tree().process_frame
	vista.dip.modulate.a = dark
	await RenderingServer.frame_post_draw
	var entry := {"index": i, "id": vista.current_shot_id(), "u": u, "cells_ready": came,
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
