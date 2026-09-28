class_name UiFit
extends Node
## Keeps a screen on the canvas whatever size the UI is (triage 28). The "Size of the UI" setting
## scales the whole canvas (Settings.apply_ui_scale), so at 1.4 a 1280x720 window lays its screens
## out on 914x514. A screen written for 1280x720 with a fixed 110 px either side of its page, or a
## list that is as tall as its entries, went off the edge. Two helpers, each a small node under
## the control it looks after, that follow the canvas as it changes (the setting is live):
##
## - `inset(frame, h, v)`: a full-rect page's margins, `h` and `v` at 1280x720 and narrower
##   as the canvas narrows, down to a few pixels at 914x514;
## - `fit_height(scroll, frame)`: a scroll area as tall as what is in it, but never so tall that
##   `frame` (the panel it is in, centred on the screen) leaves the canvas: past that it scrolls.
##
## Neither changes a font: what does not fit scrolls.

## The canvas the margins are full at, and the smallest one they narrow to (1280x720 at 1.4).
const FULL := Vector2(1280.0, 720.0)
const SMALLEST := Vector2(900.0, 500.0)
## What the margins come down to on the smallest canvas.
const LEAST_H := 14.0
const LEAST_V := 8.0

var _kind := ""
var _h := 0.0
var _v := 0.0
var _frame: Control
var _margin := 0.0


## Margins for a full-rect `frame`: `h` left and right, `v` top and bottom at 1280x720.
static func inset(frame: Control, h: float, v: float) -> void:
	var fit := UiFit.new()
	fit.name = "Inset"
	fit._kind = "inset"
	fit._h = h
	fit._v = v
	frame.add_child(fit)
	fit.apply_inset_now()


## A scroll area that grows with what is in it until `frame` would leave the canvas (with
## `margin` above and below), then scrolls.
static func fit_height(scroll: ScrollContainer, frame: Control, margin := 12.0) -> void:
	var fit := UiFit.new()
	fit.name = "FitHeight"
	fit._kind = "height"
	fit._frame = frame
	fit._margin = margin
	scroll.add_child(fit, false, Node.INTERNAL_MODE_BACK)


## The margin a page gets on a canvas this size, `full` at 1280x720 and narrowing to `least`.
static func margin_for(full: float, least: float, canvas: float, full_at: float, smallest: float) -> float:
	var t := clampf((canvas - smallest) / maxf(full_at - smallest, 1.0), 0.0, 1.0)
	return lerpf(minf(least, full), full, t)


## True when the canvas is narrower than a screen's wide layout wants (1.2 and up at 1280x720).
static func narrow(node: Node, below := 1100.0) -> bool:
	if node == null or not node.is_inside_tree():
		return false
	return node.get_viewport().get_visible_rect().size.x < below


func _ready() -> void:
	get_viewport().size_changed.connect(_refit)
	if _kind == "height":
		var scroll := get_parent() as ScrollContainer
		for c in scroll.get_children():
			if c is Control:
				(c as Control).minimum_size_changed.connect(_refit)
	_refit.call_deferred()


func _refit() -> void:
	if _kind == "inset":
		_apply_inset()
	else:
		_apply_height()


func apply_inset_now() -> void:
	_apply_inset()


func _apply_inset() -> void:
	var frame := get_parent() as Control
	if frame == null:
		return
	var canvas := FULL
	if is_inside_tree():
		canvas = get_viewport().get_visible_rect().size
	elif frame.is_inside_tree():
		canvas = frame.get_viewport().get_visible_rect().size
	var h := margin_for(_h, LEAST_H, canvas.x, FULL.x, SMALLEST.x)
	var v := margin_for(_v, LEAST_V, canvas.y, FULL.y, SMALLEST.y)
	frame.offset_left = h
	frame.offset_right = -h
	frame.offset_top = v
	frame.offset_bottom = -v


func _apply_height() -> void:
	var scroll := get_parent() as ScrollContainer
	if scroll == null or _frame == null or not is_instance_valid(_frame) or not is_inside_tree():
		return
	var content: Control = null
	for c in scroll.get_children():
		if c is Control and not c is ScrollBar:
			content = c
			break
	if content == null:
		return
	var need := content.get_combined_minimum_size().y
	var now := scroll.custom_minimum_size.y
	# what the rest of the frame needs besides this scroll area
	var rest := _frame.get_combined_minimum_size().y - maxf(now, 0.0)
	var room := get_viewport().get_visible_rect().size.y - 2.0 * _margin - rest
	var want := floorf(clampf(need, minf(96.0, need), maxf(room, 96.0)))
	if not is_equal_approx(want, now):
		scroll.custom_minimum_size.y = want
