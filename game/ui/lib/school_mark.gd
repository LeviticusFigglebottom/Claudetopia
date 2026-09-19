class_name SchoolMark
extends Control
## The mark the Circle puts at the head of a working: one hand-drawn sigil per school of
## Saying, in the school's own colour (SpellRuntime.SCHOOL_COLOR). Drawn rather than iconed
## because none of the thirty-two drawn icons means "frost" or "a name said back".
##
## Used by the sayings screen and by the HUD's readied plate:
##     var m := SchoolMark.new(); m.school = "hush"; m.custom_minimum_size = Vector2(18, 18)

@export var school: String = "kindling":
	set(value):
		school = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var centre := size * 0.5
	var r := minf(size.x, size.y) * 0.40
	var width := maxf(r * 0.16, 1.6)
	var ink := ThemeBuilder.colour("ink_soft", UI.theme_variant, 0.35)
	var tint: Color = SpellRuntime.SCHOOL_COLOR.get(school, Color.WHITE)
	# the deep variant's paper is ash, so the school colour is pulled back towards the metal
	if UI.theme_variant != "warm":
		tint = tint.lerp(ThemeBuilder.colour("metal", UI.theme_variant), 0.45)
	draw_arc(centre, r, 0.0, TAU, 40, ink, width * 0.7, true)
	match school:
		"kindling":   # a flame: two strokes brought up to a point
			draw_line(centre + Vector2(-r * 0.45, r * 0.5), centre + Vector2(0.0, -r * 0.62), tint, width, true)
			draw_line(centre + Vector2(r * 0.45, r * 0.5), centre + Vector2(0.0, -r * 0.62), tint, width, true)
			draw_line(centre + Vector2(-r * 0.45, r * 0.5), centre + Vector2(r * 0.45, r * 0.5), tint, width, true)
		"hush":       # a mouth closed: an empty arch with a line ruled under it
			draw_arc(centre, r * 0.62, PI, TAU, 24, tint, width, true)
			draw_line(centre + Vector2(-r * 0.7, r * 0.18), centre + Vector2(r * 0.7, r * 0.18), tint, width, true)
		"binding":    # a box: a short sentence about where a thing stops
			draw_rect(Rect2(centre - Vector2(r * 0.6, r * 0.6), Vector2(r * 1.2, r * 1.2)), tint, false, width)
		"mending":    # two strokes brought back together and carried on
			draw_line(centre + Vector2(-r * 0.7, -r * 0.5), centre + Vector2(0.0, r * 0.1), tint, width, true)
			draw_line(centre + Vector2(r * 0.7, -r * 0.5), centre + Vector2(0.0, r * 0.1), tint, width, true)
			draw_line(centre + Vector2(0.0, r * 0.1), centre + Vector2(0.0, r * 0.68), tint, width, true)
		"calling":    # a bell and its clapper: a name said, and something answering
			draw_arc(centre + Vector2(0.0, r * 0.12), r * 0.6, PI, TAU, 24, tint, width, true)
			draw_line(centre + Vector2(-r * 0.72, r * 0.12), centre + Vector2(r * 0.72, r * 0.12), tint, width, true)
			draw_circle(centre + Vector2(0.0, r * 0.48), maxf(width * 0.9, 1.6), tint)
		_:
			draw_circle(centre, r * 0.35, tint)
