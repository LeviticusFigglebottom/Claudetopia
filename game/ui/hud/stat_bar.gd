class_name StatBar
extends Control
## One of the three bars. The fill drops at once; a paler "ghost" behind it lags a beat and
## then slides down, so a hit reads as a wound and not as a number changing.

const LAG_SECONDS := 0.45
const SLIDE_PER_SECOND := 0.55

@export var kind := "health"
@export var show_value := true

var value := 100.0:
	set(v):
		value = v
		_apply()
var max_value := 100.0:
	set(v):
		max_value = maxf(v, 0.001)
		_apply()

var _track: NinePatchRect
var _ghost: TextureProgressBar
var _fill: TextureProgressBar
var _label: Label
var _lag := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(240, 20)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_track = NinePatchRect.new()
	_track.texture = ThemeBuilder.variant_texture(UI.theme_variant, ["bar_track"])
	_set_patch(_track, 8)
	_track.set_anchors_preset(Control.PRESET_FULL_RECT)
	_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_track)

	_ghost = _make_bar(ThemeBuilder.fill("ghost"))
	_ghost.modulate = Color(1, 1, 1, 0.75)
	add_child(_ghost)
	_fill = _make_bar(ThemeBuilder.fill(kind))
	add_child(_fill)

	_label = UiKit.label("", "Tiny", HORIZONTAL_ALIGNMENT_RIGHT)
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.offset_right = -8.0
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.modulate = Color(1, 1, 1, 0.8)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)
	# A method reference, not a closure: freeing the bar takes the connection with it.
	UI.variant_changed.connect(_on_variant_changed)
	_apply()


func _on_variant_changed(variant: String) -> void:
	_track.texture = ThemeBuilder.variant_texture(variant, ["bar_track"])


func _make_bar(tex: Texture2D) -> TextureProgressBar:
	var b := TextureProgressBar.new()
	b.texture_progress = tex
	b.nine_patch_stretch = true
	b.stretch_margin_left = 6
	b.stretch_margin_right = 6
	b.stretch_margin_top = 6
	b.stretch_margin_bottom = 6
	b.min_value = 0.0
	b.max_value = 1.0
	b.step = 0.0
	b.value = 1.0
	b.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.offset_left = 4.0
	b.offset_top = 4.0
	b.offset_right = -4.0
	b.offset_bottom = -4.0
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


func _set_patch(np: NinePatchRect, margin: int) -> void:
	np.patch_margin_left = margin
	np.patch_margin_top = margin
	np.patch_margin_right = margin
	np.patch_margin_bottom = margin


func set_values(v: float, m: float) -> void:
	max_value = m
	value = v


func fraction() -> float:
	return clampf(value / maxf(max_value, 0.001), 0.0, 1.0)


func _apply() -> void:
	if _fill == null:
		return
	var f := fraction()
	_fill.value = f
	if f > _ghost.value:
		_ghost.value = f
	elif f < _ghost.value:
		_lag = LAG_SECONDS
	if _label:
		_label.text = "%d/%d" % [roundi(value), roundi(max_value)] if show_value else ""
	set_process(_ghost.value > f)


func _process(delta: float) -> void:
	var f := fraction()
	if _ghost.value <= f:
		_ghost.value = f
		set_process(false)
		return
	if _lag > 0.0:
		_lag -= delta
		return
	_ghost.value = maxf(f, _ghost.value - delta * SLIDE_PER_SECOND)
