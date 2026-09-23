class_name Compass
extends Control
## The compass strip (DESIGN §5.16): cardinal points, discovered places only, and quest
## *areas* as soft ink smudges — never a pin, never an undiscovered place. The map does not
## remove the need to look at the world, and neither does this.
##
## World convention (CONTRACTS §1): x east, z south, so north is -Z. A bearing is degrees
## clockwise from north. The maths below is static and pure so tests can check it without
## a scene (tests/unit/test_compass.gd).

const CARDINALS := {0.0: "n", 45.0: "ne", 90.0: "e", 135.0: "se", 180.0: "s", 225.0: "sw", 270.0: "w", 315.0: "nw"}
const SPAN_DEG := 150.0        ## how much of the horizon the strip shows end to end
const MARKER_SIZE := Vector2(26, 26)
const SMUDGE_SIZE := Vector2(52, 52)

var heading_deg := 0.0
var player_xz := Vector2.ZERO
var markers: Array[Dictionary] = []      ## [{bearing, texture, kind, label, distance}]
var areas: Array[Dictionary] = []        ## [{bearing, width_deg}]

var _strip: TextureRect
var _marker_root: Control
var _tick_major: Texture2D
var _tick_minor: Texture2D
var _smudge: Texture2D
var _cardinal_tex: Dictionary = {}
var _pool: Array[Control] = []


# --- pure maths ---------------------------------------------------------------------------

## Wraps an angle difference into -180..180.
static func wrap_delta(degrees: float) -> float:
	return fposmod(degrees + 180.0, 360.0) - 180.0


## Compass bearing (0 = north = -Z, 90 = east = +X) from one world point to another.
static func bearing_deg(from_xz: Vector2, to_xz: Vector2) -> float:
	var d := to_xz - from_xz
	if d.length_squared() < 0.000001:
		return 0.0
	return fposmod(rad_to_deg(atan2(d.x, -d.y)), 360.0)


## Bearing of a facing direction. Forward in Godot is -Z, so a yaw of 0 looks north.
static func heading_from_basis(basis: Basis) -> float:
	var f := -basis.z
	return fposmod(rad_to_deg(atan2(f.x, -f.z)), 360.0)


## Where a bearing sits on a strip `width` wide, 0 at the left edge, `width` at the right.
## The centre of the strip is the way the player is facing.
static func strip_offset(bearing: float, heading: float, width: float, span := SPAN_DEG) -> float:
	return width * 0.5 + wrap_delta(bearing - heading) / span * width


## True when a bearing falls inside the strip (with a little slack so glyphs slide off).
static func on_strip(bearing: float, heading: float, span := SPAN_DEG, slack_deg := 6.0) -> bool:
	return absf(wrap_delta(bearing - heading)) <= span * 0.5 + slack_deg


## How far off centre, 0 at the edge of the strip and 1 dead ahead — used to fade the ends.
static func centre_weight(bearing: float, heading: float, span := SPAN_DEG) -> float:
	return clampf(1.0 - absf(wrap_delta(bearing - heading)) / (span * 0.5), 0.0, 1.0)


## One frame of easing the shown heading toward the view's, the short way round, with a time
## constant of `tau` seconds so a mouse's discrete steps do not shake the glyphs. A jump bigger
## than `snap_deg` in one frame is a cut (a respawn, a door) and is taken at once.
static func ease_heading(shown: float, target: float, delta: float, tau := 0.03, snap_deg := 75.0) -> float:
	var d := wrap_delta(target - shown)
	if absf(d) > snap_deg or tau <= 0.0:
		return fposmod(target, 360.0)
	return fposmod(shown + d * (1.0 - exp(-delta / tau)), 360.0)


# --- the control ----------------------------------------------------------------------------

func _ready() -> void:
	custom_minimum_size = Vector2(520, 56)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tick_major = ThemeBuilder.texture("compass_tick_major")
	_tick_minor = ThemeBuilder.texture("compass_tick_minor")
	_smudge = ThemeBuilder.texture("smudge")
	for letter in CARDINALS.values():
		_cardinal_tex[letter] = ThemeBuilder.texture("compass_" + str(letter))

	# The strip is pale parchment, and against a bright sky it disappears. A soft dark scrim
	# behind it gives the glyphs something to sit on without putting a box on the screen.
	var scrim := ColorRect.new()
	scrim.color = Color(0.07, 0.06, 0.05, 0.22)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.offset_left = 18.0
	scrim.offset_right = -18.0
	scrim.offset_top = 4.0
	scrim.offset_bottom = -6.0
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	_strip = TextureRect.new()
	_strip.texture = ThemeBuilder.texture("compass_strip")
	_strip.set_anchors_preset(Control.PRESET_FULL_RECT)
	_strip.stretch_mode = TextureRect.STRETCH_SCALE
	_strip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_strip)

	_marker_root = Control.new()
	_marker_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_marker_root.clip_contents = true
	_marker_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_marker_root)
	UI.variant_changed.connect(_on_variant_changed)


func _on_variant_changed(variant: String) -> void:
	_strip.texture = ThemeBuilder.variant_texture(variant, ["compass_strip"])
	_smudge = ThemeBuilder.texture("smudge" if variant == "warm" else "smudge_deep")


func refresh() -> void:
	for c in _pool:
		c.visible = false
	var used := 0
	var w := size.x

	# quest areas first: soft ink smudges behind everything, no pins (DESIGN §5.16)
	for area in areas:
		if not on_strip(float(area["bearing"]), heading_deg, SPAN_DEG, 24.0):
			continue
		var node := _take(used)
		used += 1
		_as_texture(node, _smudge, SMUDGE_SIZE * (1.0 + 0.5 * clampf(float(area.get("width_deg", 10.0)) / 40.0, 0.0, 1.5)))
		node.position = Vector2(strip_offset(float(area["bearing"]), heading_deg, w) - node.size.x * 0.5,
				size.y * 0.62 - node.size.y * 0.5)
		node.modulate = Color(1, 1, 1, 0.42 * centre_weight(float(area["bearing"]), heading_deg))

	# cardinals and their ticks
	for deg: float in CARDINALS:
		if not on_strip(deg, heading_deg):
			continue
		var letter := str(CARDINALS[deg])
		var major := int(deg) % 90 == 0
		var node := _take(used)
		used += 1
		var tex: Texture2D = _cardinal_tex.get(letter, null)
		var glyph_size := Vector2(34, 22) if major else Vector2(28, 18)
		_as_texture(node, tex, glyph_size)
		node.position = Vector2(strip_offset(deg, heading_deg, w) - node.size.x * 0.5, 2.0)
		var weight := centre_weight(deg, heading_deg)
		node.modulate = Color(1, 1, 1, (0.95 if major else 0.6) * (0.25 + 0.75 * weight))

		var tick := _take(used)
		used += 1
		_as_texture(tick, _tick_major if major else _tick_minor, Vector2(6, 14))
		tick.position = Vector2(strip_offset(deg, heading_deg, w) - 3.0, size.y - 13.0)
		tick.modulate = node.modulate

	# discovered places
	for m in markers:
		var bearing := float(m["bearing"])
		if not on_strip(bearing, heading_deg):
			continue
		var node := _take(used)
		used += 1
		_as_texture(node, m["texture"] as Texture2D, MARKER_SIZE)
		node.position = Vector2(strip_offset(bearing, heading_deg, w) - node.size.x * 0.5, size.y * 0.46)
		node.modulate = Color(1, 1, 1, 0.55 + 0.45 * centre_weight(bearing, heading_deg))


func _take(index: int) -> Control:
	while _pool.size() <= index:
		var t := TextureRect.new()
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_marker_root.add_child(t)
		_pool.append(t)
	var node := _pool[index]
	node.visible = true
	return node


func _as_texture(node: Control, tex: Texture2D, wanted: Vector2) -> void:
	var t := node as TextureRect
	t.texture = tex
	t.size = wanted
	t.custom_minimum_size = wanted
