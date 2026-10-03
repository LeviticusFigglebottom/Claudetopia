class_name TitleReel
extends VideoStreamPlayer
## The country behind the title as a film: the title's own shots (`core:cinematic/title`), filmed
## from the live vista (TitleVista) by `tools_gd/title_film.gd --video` and played round and round
## behind the menu. It is what a machine that cannot afford to stand the world up behind a menu is
## shown instead: the same shots, the same hours and weather, the same dips to dark between them,
## for the cost of decoding a small video. No world is stood up, nothing is streamed, no shader of
## the world's is compiled behind the menu.
##
## Shown when the setting "The live country behind the title" is off (Low and Medium, the presets an
## integrated GPU is given on its first launch) or when the live vista misses its frame budget
## (`TitleVista.gave_up` "budget"), and only when the file is there: without it the drawn chart
## stays, as before. It fades in over the chart once its first frame is decoded.

const PATH := "res://assets/video/title_reel.ogv"
const REVEAL_S := 1.6

## What the menu gives it: the chart it fades out once the film is up.
var chart: CanvasItem = null
var _revealed := false


## Whether the film is in the build.
static func available() -> bool:
	return ResourceLoader.exists(PATH)


func _ready() -> void:
	name = "TitleReel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# covered rather than letterboxed: the reel is 16:9 and the window may not be
	expand = true
	modulate.a = 0.0
	stream = load(PATH) as VideoStream
	if stream == null:
		queue_free()
		return
	# the audio is the title's music, not the film's (it has none)
	volume_db = -80.0
	if "loop" in self:
		set("loop", true)
	else:
		finished.connect(play)
	if get_parent() is Control:
		(get_parent() as Control).resized.connect(_cover)
	_cover()
	play()
	StartupTrace.step("title: the filmed country plays behind the menu")


func _process(_delta: float) -> void:
	if _revealed or not is_playing():
		return
	if get_video_texture() == null or stream_position <= 0.0:
		return
	_revealed = true
	_cover()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, REVEAL_S).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if chart != null and is_instance_valid(chart):
		tw.parallel().tween_property(chart, "modulate:a", 0.0, REVEAL_S)
	set_process(false)


## Fills the window keeping the film's aspect: wider than 16:9 it is cropped top and bottom, taller
## at the sides, as the live vista's camera would show it.
func _cover() -> void:
	var tex := get_video_texture()
	var film := Vector2(16.0, 9.0) if tex == null or tex.get_width() == 0 else Vector2(tex.get_size())
	var parent_size := (get_parent() as Control).size if get_parent() is Control else get_viewport_rect().size
	var s := maxf(parent_size.x / film.x, parent_size.y / film.y)
	var want := film * s
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	size = want
	position = (parent_size - want) * 0.5
