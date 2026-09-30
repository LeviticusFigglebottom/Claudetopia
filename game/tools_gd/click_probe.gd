extends Node
## The click probe (`-- --click=<seconds>[:<button>]`): presses a title button a set time after the
## menu comes up, while the country behind it is still standing up, and says whether the game went
## on. A player's first click on a fresh PC froze the game for good (docs/FIRST_LAUNCH.md).
##
## From the click it measures how long the click itself held the main thread until the next scene
## was in (the title torn down and the next screen read: `click_ms`), the frame that first drew it
## (the next screen's own cost, the same with no country behind the title), the longest frame after
## that, and the errors the engine and the game report. It prints one line,
##
##   CLICK at=2.0 button=New Game went_on=yes click_ms=420 first_frame_ms=1750 longest_after_ms=90 ...
##
## writes it to `--click-out=<file>` when given, and quits: 0 when the game went on within LIMIT_S,
## the click and every frame after the first held the main thread no more than GAP_LIMIT_MS, and
## nothing new was reported as an error; 1 otherwise. tools/debug/click_probe.sh runs it over
## several moments.

## A frame longer than this after the click is a main thread that waited on something.
const GAP_LIMIT_MS := 1000
## The screen the button leads to must be up by then.
const LIMIT_S := 20.0
## Frames watched once it is up, for errors from what was torn down.
const AFTER_FRAMES := 90

var at_s := 1.0
## `--click=shown+<s>`: <s> seconds after the title's first shot is shown, with the title's caps before
## it lifted (a software renderer's first frames of the country would give it up otherwise).
var after_shown := false
var button := "New Game"
var out_path := ""

var _menu_ms := -1
var _clicked_ms := -1
var _arrived_ms := -1
var _frames_after := 0
var _last_us := 0
var _longest_ms := 0
var _longest_at := ""
var _scene_in_us := -1
var _click_us := 0
var _first_frame_ms := -1
var _errors_before := 0
var _log_errors_before := 0
var _done := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--click="):
			var v := a.trim_prefix("--click=").split(":", true, 1)
			after_shown = v[0].begins_with("shown+")
			at_s = float(v[0].trim_prefix("shown+"))
			if v.size() > 1:
				button = v[1]
		elif a.begins_with("--click-out="):
			out_path = a.trim_prefix("--click-out=")
	_last_us = Time.get_ticks_usec()


func _process(_delta: float) -> void:
	if _done:
		return
	var now_us := Time.get_ticks_usec()
	var gap_ms := roundi((now_us - _last_us) / 1000.0)
	_last_us = now_us
	var now := Time.get_ticks_msec()
	var scene := get_tree().current_scene
	if _clicked_ms < 0:
		if scene != null and scene.scene_file_path.ends_with("main_menu.tscn"):
			if after_shown:
				var vista := scene.get_node_or_null("TitleVista") as TitleVista
				if vista != null:
					vista.long_frame_s = 3600.0
					vista.first_show_cap_s = 3600.0
				if vista == null or vista.shown.is_empty():
					return
			if _menu_ms < 0:
				_menu_ms = now
			elif now - _menu_ms >= int(at_s * 1000.0):
				_click(scene)
		return
	if _first_frame_ms < 0:
		# the frame the click was in: the title torn down and the next screen read, then drawn
		_first_frame_ms = gap_ms
	elif gap_ms > _longest_ms:
		_longest_ms = gap_ms
		_longest_at = StartupTrace.last()
	if _arrived_ms < 0 and _arrived(scene):
		_arrived_ms = now
	if _arrived_ms >= 0:
		_frames_after += 1
		if _frames_after >= AFTER_FRAMES:
			_finish(true)
	elif now - _clicked_ms > int(LIMIT_S * 1000.0):
		_finish(false)


func _click(menu: Node) -> void:
	var b := _find_button(menu, button)
	if b == null:
		print("CLICK no button %s" % button)
		get_tree().quit(2)
		_done = true
		return
	var vista := menu.get_node_or_null("TitleVista") as TitleVista
	var vista_state := "no vista"
	if vista != null:
		vista_state = "%s, world %s" % [str(TitleVista.Phase.keys()[vista.phase]).to_lower(),
			("ready" if vista.world.is_world_ready else "standing up (%s)" % str(vista.world.stand_up_ms.keys()))
			if vista.world != null else "not yet"]
	print("CLICK pressing %s at %s%.1f s: %s" % [button, "shown+" if after_shown else "", at_s, vista_state])
	_errors_before = _errors()
	_log_errors_before = Log.error_count
	_clicked_ms = Time.get_ticks_msec()
	_last_us = Time.get_ticks_usec()
	_click_us = _last_us
	get_tree().node_added.connect(_on_node_added)
	b.pressed.emit()


func _on_node_added(node: Node) -> void:
	if _scene_in_us < 0 and node.get_parent() == get_tree().root and node != self:
		_scene_in_us = Time.get_ticks_usec()


func _arrived(scene: Node) -> bool:
	match button:
		"Settings":
			return UI.is_menu_open("settings")
	return scene != null and not scene.scene_file_path.ends_with("main_menu.tscn")


func _errors() -> int:
	return ErrorLog.count("error") + ErrorLog.count("script_error")


func _finish(went_on: bool) -> void:
	_done = true
	var errors := _errors() - _errors_before
	# a screen opened over the title (Settings) brings no scene: the click's frame is the measure
	var click_ms := roundi((_scene_in_us - _click_us) / 1000.0) if _scene_in_us >= 0 else _first_frame_ms
	var ok := went_on and click_ms <= GAP_LIMIT_MS and _longest_ms <= GAP_LIMIT_MS and errors == 0 \
			and Log.error_count == _log_errors_before
	var line := "CLICK at=%s%.1f button=%s went_on=%s click_ms=%d first_frame_ms=%d longest_after_ms=%d (at \"%s\") errors=%d verdict=%s" % [
		"shown+" if after_shown else "", at_s, button, "yes" if went_on else "NO", click_ms, _first_frame_ms,
		_longest_ms, _longest_at, errors, "PASS" if ok else "FAIL"]
	print(line)
	if errors > 0:
		print(ErrorLog.report(6))
	if not out_path.is_empty():
		var f := FileAccess.open(out_path, FileAccess.READ_WRITE if FileAccess.file_exists(out_path) else FileAccess.WRITE)
		if f != null:
			f.seek_end()
			f.store_line(line)
			f.close()
	get_tree().quit(0 if ok else 1)


static func _find_button(root: Node, text: String) -> Button:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Button and (n as Button).text == text:
			return n as Button
		stack.append_array(n.get_children())
	return null
