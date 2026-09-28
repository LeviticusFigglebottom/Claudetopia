class_name CinematicOverlay
extends CanvasLayer
## What a cinematic draws over the world: the curtain it fades from and holds on, the still of
## the last frame that a dissolve fades out over the next shot, the letterbox, the title card,
## the subtitles, the hold-to-skip prompt and, when the country has not arrived in time, the
## same kind of caption the menus put over the black.
##
## It is dressed from the UI theme (DESIGN §9): Cinzel for the title and the speaker, Spectral
## for the words, paper for the ink because the ground here is black, and the bell mark. It
## decides nothing; `CinematicPlayer` says what shows and when.
##
## Layer 45: over the HUD, the toasts and the screen fade (40), so nothing any other system does
## with those shows through a held black; under the debug console (100).

const LAYER := 45
const CURTAIN := Color(0.035, 0.03, 0.025)
const BAR := Color(0.0, 0.0, 0.0)
const TITLE_SIZE := 64
const LINE_SIZE := 20
const SPEAKER_SIZE := 13
const TINT_SHADER := "shader_type canvas_item;\nuniform vec4 tint : source_color = vec4(1.0);\nvoid fragment() {\n\tCOLOR = vec4(tint.rgb, texture(TEXTURE, UV).a * tint.a * COLOR.a);\n}\n"

var letterbox := CinematicDef.DEFAULT_LETTERBOX
## An extra scale on the subtitles alone. The player's UI size (Settings accessibility/ui_scale)
## scales the whole canvas now (Settings.apply_ui_scale), films' words with it, so this stays 1.
var text_scale := 1.0

var _root: Control
var _freeze: TextureRect
var _curtain: ColorRect
var _bar_top: ColorRect
var _bar_bottom: ColorRect
var _bars := 0.0
var _title: VBoxContainer
var _title_label: Label
var _title_line: Label
var _subtitle: VBoxContainer
var _speaker: Label
var _line: Label
var _prompt: HBoxContainer
var _prompt_fill: ColorRect
var _prompt_track: Control
var _caption: CenterContainer
var _caption_line: Label
var _caption_progress: Label
var _caption_mark: TextureRect
var _caption_tween: Tween = null
var _title_tween: Tween = null
var _line_tween: Tween = null
var _prompt_tween: Tween = null
## The words, the title card and the prompt fade on the wall clock, as the pictures run (WallTweens):
## on a machine drawing a frame every few seconds a line faded in over several frames and was read,
## if at all, half-inked.
var _wall := WallTweens.new()


func _init() -> void:
	layer = LAYER
	name = "CinematicOverlay"


func _ready() -> void:
	_build()
	get_viewport().size_changed.connect(_layout)
	_layout()


func _process(_delta: float) -> void:
	_wall.step()


func _build() -> void:
	var variant: String = UI.theme_variant if UI != null else "warm"
	var paper := ThemeBuilder.colour("paper_hi", variant)
	var metal := ThemeBuilder.colour("metal_hi", variant)
	_root = Control.new()
	_root.name = "Frame"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UI.theme_for(variant)
	add_child(_root)

	_freeze = TextureRect.new()
	_freeze.name = "Still"
	_freeze.set_anchors_preset(Control.PRESET_FULL_RECT)
	_freeze.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_freeze.stretch_mode = TextureRect.STRETCH_SCALE
	_freeze.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_freeze.visible = false
	_root.add_child(_freeze)

	_curtain = ColorRect.new()
	_curtain.name = "Curtain"
	_curtain.color = CURTAIN
	_curtain.set_anchors_preset(Control.PRESET_FULL_RECT)
	_curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_curtain)

	# --- the title card: the bell mark, the name, the rule, the saying ---------------------
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(centre)
	_title = VBoxContainer.new()
	_title.name = "TitleCard"
	_title.alignment = BoxContainer.ALIGNMENT_CENTER
	_title.add_theme_constant_override("separation", 2)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.modulate.a = 0.0
	centre.add_child(_title)
	var mark := TextureRect.new()
	mark.texture = ThemeBuilder.texture("mark_bell")
	mark.custom_minimum_size = Vector2(0, 92)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.material = _tinted(paper)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_child(mark)
	_title_label = UiKit.label("", "DisplayTitle", HORIZONTAL_ALIGNMENT_CENTER)
	_title_label.add_theme_font_size_override("font_size", TITLE_SIZE)
	_title_label.add_theme_color_override("font_color", paper)
	_shadow(_title_label, 3)
	_title.add_child(_title_label)
	var rule := NinePatchRect.new()
	rule.texture = ThemeBuilder.texture("rule_line")
	rule.patch_margin_left = 8
	rule.patch_margin_right = 8
	rule.custom_minimum_size = Vector2(420, 12)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rule.material = _tinted(Color(paper, 0.8))
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title.add_child(rule)
	_title_line = UiKit.label("", "Journal", HORIZONTAL_ALIGNMENT_CENTER)
	_title_line.add_theme_font_size_override("font_size", 21)
	_title_line.add_theme_color_override("font_color", paper)
	# a thin italic under a heavy shadow reads as dark ink on a light halo, the wrong way round
	_shadow(_title_line, 1, 2, 0.55)
	_title.add_child(_title_line)

	# --- the letterbox -------------------------------------------------------------------------
	_bar_top = _bar("BarTop")
	_bar_bottom = _bar("BarBottom")

	# --- subtitles, in the lower bar: who is speaking, and the words -----------------------------
	_subtitle = VBoxContainer.new()
	_subtitle.name = "Subtitle"
	_subtitle.alignment = BoxContainer.ALIGNMENT_CENTER
	_subtitle.add_theme_constant_override("separation", 1)
	_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle.modulate.a = 0.0
	_root.add_child(_subtitle)
	_speaker = UiKit.label("", "Metal", HORIZONTAL_ALIGNMENT_CENTER)
	_speaker.add_theme_color_override("font_color", metal)
	_speaker.uppercase = true
	_subtitle.add_child(_speaker)
	_line = UiKit.label("", "Body", HORIZONTAL_ALIGNMENT_CENTER)
	_line.add_theme_color_override("font_color", paper)
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.add_child(_line)

	# --- hold to skip: the words and a brass fill that grows while something is held -----------
	_prompt = HBoxContainer.new()
	_prompt.name = "SkipPrompt"
	_prompt.add_theme_constant_override("separation", 10)
	_prompt.alignment = BoxContainer.ALIGNMENT_END
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.modulate.a = 0.0
	_root.add_child(_prompt)
	var words := UiKit.label("Hold to skip", "Small")
	words.add_theme_color_override("font_color", Color(paper, 0.85))
	_prompt.add_child(words)
	_prompt_track = ColorRect.new()
	(_prompt_track as ColorRect).color = Color(paper, 0.18)
	_prompt_track.custom_minimum_size = Vector2(90, 4)
	_prompt_track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_prompt_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.add_child(_prompt_track)
	_prompt_fill = ColorRect.new()
	_prompt_fill.color = metal
	_prompt_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_fill.size = Vector2(0, 4)
	_prompt_track.add_child(_prompt_fill)

	# --- the caption a held black carries, as the menus' does ----------------------------------
	_caption = CenterContainer.new()
	_caption.name = "Caption"
	_caption.set_anchors_preset(Control.PRESET_FULL_RECT)
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.visible = false
	_root.add_child(_caption)
	var sheet := PanelContainer.new()
	sheet.theme_type_variation = &"SheetPanel"
	sheet.custom_minimum_size = Vector2(520, 0)
	sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption.add_child(sheet)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	sheet.add_child(col)
	_caption_mark = TextureRect.new()
	_caption_mark.texture = ThemeBuilder.texture("mark_bell")
	_caption_mark.custom_minimum_size = Vector2(0, 64)
	_caption_mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_caption_mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_caption_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption_mark.resized.connect(_centre_caption_pivot)
	col.add_child(_caption_mark)
	_caption_line = UiKit.label("", "Journal", HORIZONTAL_ALIGNMENT_CENTER)
	_caption_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption_line.custom_minimum_size = Vector2(460, 0)
	col.add_child(_caption_line)
	_caption_progress = UiKit.label("", "Small", HORIZONTAL_ALIGNMENT_CENTER)
	col.add_child(_caption_progress)


func _bar(bar_name: String) -> ColorRect:
	var r := ColorRect.new()
	r.name = bar_name
	r.color = BAR
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(r)
	return r


func _tinted(col: Color) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = TINT_SHADER
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("tint", col)
	return m


func _shadow(label: Label, shift: int, outline := -1, alpha := 0.7) -> void:
	label.add_theme_color_override("font_shadow_color", Color(0.04, 0.03, 0.02, alpha))
	label.add_theme_constant_override("shadow_offset_x", shift)
	label.add_theme_constant_override("shadow_offset_y", shift)
	label.add_theme_constant_override("shadow_outline_size", shift * 3 if outline < 0 else outline)


func _centre_caption_pivot() -> void:
	_caption_mark.pivot_offset = _caption_mark.size * 0.5


## The height of one bar at the full letterbox, for the viewport as it is now.
func bar_height() -> float:
	var s := get_viewport().get_visible_rect().size
	if s.x <= 0.0 or s.y <= 0.0:
		return 0.0
	return maxf(0.0, (s.y - s.x / letterbox) * 0.5)


func _layout() -> void:
	var s := get_viewport().get_visible_rect().size
	var h := bar_height() * clampf(_bars, 0.0, 1.0)
	_bar_top.position = Vector2.ZERO
	_bar_top.size = Vector2(s.x, h)
	_bar_bottom.position = Vector2(0.0, s.y - h)
	_bar_bottom.size = Vector2(s.x, h)
	# the words sit in the lower bar at its full height, whether or not it has finished arriving
	var full := maxf(bar_height(), 64.0)
	_line.add_theme_font_size_override("font_size", int(round(LINE_SIZE * text_scale)))
	_speaker.add_theme_font_size_override("font_size", int(round(SPEAKER_SIZE * text_scale)))
	_subtitle.position = Vector2(s.x * 0.12, s.y - full)
	_subtitle.size = Vector2(s.x * 0.76, full)
	_line.custom_minimum_size = Vector2(s.x * 0.76, 0)
	_prompt.position = Vector2(s.x - 330.0, s.y - full + (full - 24.0) * 0.5)
	_prompt.size = Vector2(300.0, 24.0)


# --- what the player drives ------------------------------------------------------------------------

## 0 is the world, 1 is black.
func set_curtain(alpha: float) -> void:
	_curtain.color.a = clampf(alpha, 0.0, 1.0)
	_curtain.visible = _curtain.color.a > 0.001


func curtain() -> float:
	return _curtain.color.a if _curtain.visible else 0.0


## The last frame of a shot, held over the next while it fades.
func freeze(texture: Texture2D) -> void:
	_freeze.texture = texture
	_freeze.visible = texture != null
	_freeze.modulate.a = 1.0


func set_freeze_alpha(alpha: float) -> void:
	_freeze.modulate.a = clampf(alpha, 0.0, 1.0)
	if _freeze.modulate.a <= 0.001:
		clear_freeze()


func clear_freeze() -> void:
	_freeze.visible = false
	_freeze.texture = null


func is_frozen() -> bool:
	return _freeze.visible


## 0 is no letterbox, 1 is the whole of it.
func set_bars(fraction: float) -> void:
	_bars = clampf(fraction, 0.0, 1.0)
	_layout()


func bars() -> float:
	return _bars


func say(speaker: String, text: String) -> void:
	_speaker.text = speaker
	_speaker.visible = not speaker.is_empty()
	_line.text = text
	if _line_tween != null and _line_tween.is_valid():
		_line_tween.kill()
	_subtitle.modulate = Color(0.30, 0.24, 0.19, 0.0)
	_line_tween = _wall.own(_subtitle.create_tween())
	_line_tween.tween_property(_subtitle, "modulate", Color(1, 1, 1, 1), 0.35).set_trans(Tween.TRANS_CUBIC)


func unsay() -> void:
	if _line.text.is_empty():
		return
	if _line_tween != null and _line_tween.is_valid():
		_line_tween.kill()
	_line_tween = _wall.own(_subtitle.create_tween())
	_line_tween.tween_property(_subtitle, "modulate:a", 0.0, 0.25)
	_line_tween.tween_callback(_clear_line)


func _clear_line() -> void:
	_line.text = ""
	_speaker.text = ""


func said() -> String:
	return _line.text


## How far the words on screen have inked in, 0 to 1.
func line_alpha() -> float:
	return _subtitle.modulate.a


func title_in(title: String, line: String, seconds := 1.6) -> void:
	_title_label.text = title.to_upper()
	_title_line.text = line
	_title_line.visible = not line.is_empty()
	if _title_tween != null and _title_tween.is_valid():
		_title_tween.kill()
	_title.modulate = Color(0.30, 0.24, 0.19, 0.0)
	_title_tween = _wall.own(_title.create_tween())
	_title_tween.tween_property(_title, "modulate", Color(1, 1, 1, 1), seconds).set_trans(Tween.TRANS_CUBIC)


func title_out(seconds := 1.4) -> void:
	if _title.modulate.a <= 0.0:
		return
	if _title_tween != null and _title_tween.is_valid():
		_title_tween.kill()
	_title_tween = _wall.own(_title.create_tween())
	_title_tween.tween_property(_title, "modulate:a", 0.0, seconds).set_trans(Tween.TRANS_SINE)


func title_shown() -> bool:
	return _title.modulate.a > 0.01


func prompt(shown: bool) -> void:
	_prompt_asked = shown
	var want := 1.0 if shown else 0.0
	# whatever is on its way goes first: a prompt asked for and let go before its fade had begun
	# (a skip on the next frame of a slow machine) kept fading in over the skip's black
	if _prompt_tween != null and _prompt_tween.is_valid():
		_prompt_tween.kill()
	if is_equal_approx(_prompt.modulate.a, want):
		return
	_prompt_tween = _wall.own(_prompt.create_tween())
	_prompt_tween.tween_property(_prompt, "modulate:a", want, 0.3 if shown else 0.6)


## Whether the skip prompt was last asked to show (it may still be fading in).
func prompt_asked() -> bool:
	return _prompt_asked


var _prompt_asked := false


func prompt_shown() -> bool:
	return _prompt.modulate.a > 0.01


## How far in the skip prompt is, from 0 to 1.
func prompt_alpha() -> float:
	return _prompt.modulate.a


func prompt_fill(fraction: float) -> void:
	_prompt_fill.size = Vector2(_prompt_track.custom_minimum_size.x * clampf(fraction, 0.0, 1.0), 4.0)


func caption_in(line: String) -> void:
	_caption_line.text = line
	if _caption.visible:
		return
	_caption.visible = true
	UiKit.ink_in(_caption, 0.0, 0.5)
	if _caption_tween != null and _caption_tween.is_valid():
		_caption_tween.kill()
	# the same sway as the menus' caption: a bell that has just stopped ringing
	_caption_mark.rotation = -0.05
	_caption_tween = _caption_mark.create_tween().set_loops()
	_caption_tween.tween_property(_caption_mark, "rotation", 0.05, 1.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_caption_tween.tween_property(_caption_mark, "rotation", -0.05, 1.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func caption_out() -> void:
	if not _caption.visible:
		return
	if _caption_tween != null and _caption_tween.is_valid():
		_caption_tween.kill()
	_caption.visible = false


func caption_shown() -> bool:
	return _caption.visible


func set_caption_progress(text: String) -> void:
	_caption_progress.text = text
