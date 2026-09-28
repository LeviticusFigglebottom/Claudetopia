class_name Crosshair
extends Control
## The aim's mark at the middle of the view (triage 55): where a drawn bow's arrow or an aimed
## saying goes (Player.aim_point is under it, and the shot is sent there). Four ticks round a gap as
## wide as the shot's spread, closing to a point as a bow comes to full draw and opening as a tired
## arm shakes; a small dot at the middle; warm when the aim is on a living body within reach.
## The HUD (hud.gd) sets it from Player.crosshair() every frame and hides it otherwise; it is the
## HUD's child, so it takes the HUD's opacity and the UI's scale with everything else.

const TICK := 7.0                 ## length of each tick
const WIDTH := 2.0
const GAP_LEAST := 3.0            ## the gap at no spread
const GAP_MOST := 60.0
const DOT := 1.6
const PALE := Color(0.96, 0.93, 0.86, 0.92)
const ON := Color(0.98, 0.52, 0.36, 1.0)
const SHADE := Color(0.05, 0.04, 0.03, 0.55)
const EASE_S := 0.06              ## the gap follows the spread this quickly, so it does not flicker

## The gap from the middle to the ticks (px), and whether a body is under the aim.
var gap := GAP_LEAST
var on_target := false
var _gap_to := GAP_LEAST


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false


## Shows the mark for `state` (Player.crosshair()) seen through a view `fov_deg` high: the spread
## (radians) turned into pixels at this control's height.
func show_state(state: Dictionary, fov_deg: float, delta: float) -> void:
	var up := bool(state.get("visible", false))
	if up != visible:
		visible = up
		if up:
			gap = _gap_to
	if not up:
		return
	var half := tan(deg_to_rad(clampf(fov_deg, 10.0, 170.0)) * 0.5)
	var px_per := size.y * 0.5 / maxf(half, 0.01)
	_gap_to = clampf(GAP_LEAST + tan(float(state.get("spread", 0.0))) * px_per, GAP_LEAST, GAP_MOST)
	gap = lerpf(gap, _gap_to, 1.0 - exp(-maxf(delta, 0.0) / EASE_S))
	var on := bool(state.get("on_target", false))
	if on != on_target:
		on_target = on
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var col := ON if on_target else PALE
	for d: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		var a := c + d * gap
		var b := c + d * (gap + TICK)
		draw_line(a, b, SHADE, WIDTH + 2.0, true)
		draw_line(a, b, col, WIDTH, true)
	draw_circle(c, DOT + 1.0, SHADE)
	draw_circle(c, DOT, col)
