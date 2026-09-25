extends Control
## The chart (DESIGN §5.16). A painted map of the basin, unread until you have been there:
## fog lifts around places you have discovered and much further around places you have
## surveyed from a high vista. Quest areas are soft smudges, never pins, and nothing you
## have not found is drawn at all — the map does not do your looking for you.
##
## The chart itself is painted by tools/ui/gen_map.py; world_map.json carries the
## world-to-pixel transform.

const MAP_DIR := "res://assets/ui/map/"
const FOG_SHADER := "res://assets/shaders/map_fog.gdshader"
const MAX_REVEALS := 96
const ZOOM_MIN := 0.45
const ZOOM_MAX := 3.2
const PAN_SPEED := 620.0

## How far a place lights the paper, by what kind of place it is.
const REVEAL_M := {
	"city": 1250.0, "town": 950.0, "village": 720.0, "hamlet": 560.0, "camp": 460.0,
	"fort": 700.0, "lodge": 520.0, "landmark": 1100.0, "deep_place": 430.0,
	"interior_dungeon": 380.0, "ruin_village": 560.0, "poi": 420.0, "edge": 700.0,
	"shrine": 480.0, "bridge": 420.0, "tower": 780.0, "waterfall": 520.0,
	"standing_stones": 520.0, "giant_bones": 600.0, "strange_tree": 420.0, "wreck": 400.0,
	"ruins": 520.0, "hidden_valley": 460.0, "strange": 420.0,
	"cave": 420.0, "farmstead": 480.0, "mill": 560.0, "waystone": 380.0, "market_field": 520.0,
	"quarry": 600.0, "shieling": 460.0, "vista": 640.0,
}
const SURVEYED_M := 2100.0

var _info: Dictionary = {}
var _chart: TextureRect
var _fog: TextureRect
var _holder: Control
var _markers: Control
var _hover_plate: PanelContainer
var _hover_label: Label
var _foot: Label
var _zoom := 1.0
var _offset := Vector2.ZERO
var _chart_size := Vector2(1536, 1536)
var _dragging := false
var _places: Array[Dictionary] = []
var _marker_nodes: Array[TextureRect] = []
var _area_nodes: Array[TextureRect] = []
var _player_marker: TextureRect
var _hovered := -1


func setup(args: Dictionary) -> void:
	if args.has("centre_on"):
		var def := ContentDB.get_or_empty(str(args["centre_on"]))
		var pos: Array = def.get("position", [])
		if pos.size() >= 2:
			call_deferred("centre_on_world", Vector2(float(pos[0]), float(pos[1])))


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(UiKit.dim(0.72))
	_load_info()
	_build()
	_gather_places()
	_update_foot()
	_refresh_fog()
	_refresh_markers()
	call_deferred("_centre_on_player")


func _load_info() -> void:
	var path := MAP_DIR + "world_map.json"
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			_info = parsed
	if _info.is_empty():
		_info = {"size_px": 1536, "size_m": 8192.0, "origin": [-4096.0, -4096.0]}


func _build() -> void:
	var page := UiKit.page("The Chart")
	var frame: PanelContainer = page["frame"]
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 40.0
	frame.offset_top = 26.0
	frame.offset_right = -40.0
	frame.offset_bottom = -26.0
	add_child(frame)
	var body: VBoxContainer = page["body"]

	_holder = Control.new()
	_holder.clip_contents = true
	_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_holder.mouse_filter = Control.MOUSE_FILTER_STOP
	_holder.gui_input.connect(_on_map_input)
	body.add_child(_holder)

	var chart_texture: Texture2D = null
	var chart_path := MAP_DIR + str(_info.get("file", "world_map.png"))
	if ResourceLoader.exists(chart_path):
		chart_texture = load(chart_path)
	if chart_texture:
		_chart_size = chart_texture.get_size()

	_chart = TextureRect.new()
	_chart.texture = chart_texture
	_chart.size = _chart_size
	_chart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holder.add_child(_chart)

	_fog = TextureRect.new()
	_fog.texture = chart_texture
	_fog.size = _chart_size
	_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load(FOG_SHADER)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	var noise_tex := NoiseTexture2D.new()
	noise_tex.noise = noise
	noise_tex.seamless = true
	noise_tex.width = 256
	noise_tex.height = 256
	mat.set_shader_parameter("noise_tex", noise_tex)
	mat.set_shader_parameter("fog_colour", ThemeBuilder.colour("paper_hi", UI.theme_variant, 0.97))
	_fog.material = mat
	_holder.add_child(_fog)

	_markers = Control.new()
	_markers.set_anchors_preset(Control.PRESET_FULL_RECT)
	_markers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holder.add_child(_markers)

	_player_marker = TextureRect.new()
	_player_marker.texture = ThemeBuilder.marker("player")
	_player_marker.custom_minimum_size = Vector2(26, 26)
	_player_marker.size = Vector2(26, 26)
	_player_marker.pivot_offset = Vector2(13, 13)
	_player_marker.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_player_marker.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_player_marker.modulate = ThemeBuilder.colour("accent", UI.theme_variant)
	_player_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_markers.add_child(_player_marker)

	_hover_plate = UiKit.panel("ChromePanel")
	_hover_plate.visible = false
	_hover_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_label = UiKit.label("", "Body")
	_hover_plate.add_child(_hover_label)
	_markers.add_child(_hover_plate)

	_foot = UiKit.label("", "Tiny", HORIZONTAL_ALIGNMENT_CENTER)
	body.add_child(_foot)
	_update_foot()

	var close := UiKit.button("Close", "FlatButton")
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(func() -> void: UI.close("map"))
	body.add_child(close)
	UiKit.ink_in(frame, 0.0, 0.34)


func _update_foot() -> void:
	var drag := "drag to move · wheel to zoom" if not UI.using_gamepad else "left stick to move · triggers to zoom"
	_foot.text = "%s   ·   %d places found   ·   %s" % [drag, _places.size(),
			str(ContentDB.get_or_empty(GameState.current_region_id).get("name", ""))]


# --- the world on the paper ---------------------------------------------------------------

func world_to_chart(xz: Vector2) -> Vector2:
	var origin: Array = _info.get("origin", [-4096.0, -4096.0])
	var size_m := float(_info.get("size_m", 8192.0))
	return Vector2((xz.x - float(origin[0])) / size_m, (xz.y - float(origin[1])) / size_m) * _chart_size


func world_to_uv(xz: Vector2) -> Vector2:
	var origin: Array = _info.get("origin", [-4096.0, -4096.0])
	var size_m := float(_info.get("size_m", 8192.0))
	return Vector2((xz.x - float(origin[0])) / size_m, (xz.y - float(origin[1])) / size_m)


func metres_to_uv(metres: float) -> float:
	return metres / float(_info.get("size_m", 8192.0))


func chart_to_screen(point: Vector2) -> Vector2:
	return _offset + point * _zoom


func _apply_transform() -> void:
	_chart.position = _offset
	_chart.scale = Vector2(_zoom, _zoom)
	_fog.position = _offset
	_fog.scale = Vector2(_zoom, _zoom)
	_refresh_markers()


func centre_on_world(xz: Vector2) -> void:
	var chart := world_to_chart(xz)
	_offset = _holder.size * 0.5 - chart * _zoom
	_apply_transform()


func _centre_on_player() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player and player is Node3D:
		centre_on_world(Vector2((player as Node3D).global_position.x, (player as Node3D).global_position.z))
	else:
		centre_on_world(_home_xz())


## Where the chart opens with nobody on the map: the place the content calls its start hub
## (Merrowby), wherever the map has put it, else the middle of the map.
static func _home_xz() -> Vector2:
	for p in ContentDB.all("place"):
		var tags: Variant = p.get("tags", [])
		if typeof(tags) == TYPE_ARRAY and (tags as Array).has("start_hub"):
			var xz := PlaceRef.xz(str(p.get("id", "")))
			if xz != Vector2.INF:
				return xz
	return Vector2.ZERO


# --- places, fog and markers ----------------------------------------------------------------

func _gather_places() -> void:
	_places.clear()
	for place_id in GameState.discovered_places:
		var def := ContentDB.get_or_empty(place_id)
		var pos: Array = def.get("position", [])
		if pos.size() < 2:
			continue
		var kind := str(def.get("kind", "poi"))
		_places.append({
			"id": place_id, "name": str(def.get("name", place_id)), "kind": kind,
			"xz": Vector2(float(pos[0]), float(pos[1])),
			"surveyed": GameState.has_flag("surveyed:" + place_id),
			"feature": str(def.get("unique_feature", "")),
		})


## One circle per place you have found, wider for ones you have looked out from.
func reveals() -> PackedVector3Array:
	var out := PackedVector3Array()
	for place in _places:
		if out.size() >= MAX_REVEALS:
			break
		var uv := world_to_uv(place["xz"])
		var metres: float = float(REVEAL_M.get(str(place["kind"]), 420.0))
		if bool(place["surveyed"]):
			metres = maxf(metres, SURVEYED_M)
		out.append(Vector3(uv.x, uv.y, metres_to_uv(metres)))
	return out


func _refresh_fog() -> void:
	if _fog == null or _fog.material == null:
		return
	var list := reveals()
	var mat: ShaderMaterial = _fog.material
	mat.set_shader_parameter("reveal_count", list.size())
	if list.size() > 0:
		mat.set_shader_parameter("reveals", list)


func _refresh_markers() -> void:
	while _marker_nodes.size() < _places.size():
		var t := TextureRect.new()
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.size = Vector2(30, 30)
		t.custom_minimum_size = Vector2(30, 30)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_markers.add_child(t)
		_marker_nodes.append(t)
	for i in _marker_nodes.size():
		var node := _marker_nodes[i]
		if i >= _places.size():
			node.visible = false
			continue
		var place: Dictionary = _places[i]
		node.visible = true
		node.texture = ThemeBuilder.marker(str(place["kind"]))
		node.modulate = Color(1, 1, 1, 1.0 if i == _hovered else 0.88)
		node.position = chart_to_screen(world_to_chart(place["xz"])) - node.size * 0.5

	# quest areas: a wash where the work is, sized by how vague the direction is
	var markers: Array = []
	var quests := get_tree().get_first_node_in_group("quest_log")
	if quests and is_instance_valid(quests) and quests.has_method("active_markers"):
		markers = quests.call("active_markers")
	while _area_nodes.size() < markers.size():
		var s := TextureRect.new()
		s.texture = ThemeBuilder.texture("smudge" if UI.theme_variant == "warm" else "smudge_deep")
		s.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		s.stretch_mode = TextureRect.STRETCH_SCALE
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		s.modulate = Color(1, 1, 1, 0.5)
		_markers.add_child(s)
		_markers.move_child(s, 0)
		_area_nodes.append(s)
	for i in _area_nodes.size():
		var node := _area_nodes[i]
		if i >= markers.size():
			node.visible = false
			continue
		var m: Dictionary = markers[i]
		var def := ContentDB.get_or_empty(str(m.get("place_id", "")))
		var pos: Array = def.get("position", [])
		if pos.size() < 2 or not GameState.is_discovered(str(m.get("place_id", ""))):
			node.visible = false
			continue
		var radius := float(m.get("radius", 200.0))
		var px := metres_to_uv(radius) * _chart_size.x * _zoom * 2.6
		node.visible = true
		node.size = Vector2(px, px)
		node.position = chart_to_screen(world_to_chart(Vector2(float(pos[0]), float(pos[1])))) - node.size * 0.5

	var player := get_tree().get_first_node_in_group("player")
	if player and player is Node3D:
		var p := player as Node3D
		_player_marker.visible = true
		_player_marker.position = chart_to_screen(world_to_chart(Vector2(p.global_position.x, p.global_position.z))) - _player_marker.size * 0.5
		_player_marker.rotation = deg_to_rad(Compass.heading_from_basis(p.global_transform.basis))
	else:
		_player_marker.visible = false


# --- input -----------------------------------------------------------------------------------

func _on_map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(mb.position, 1.14)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(mb.position, 1.0 / 1.14)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging:
			_offset += mm.relative
			_clamp_offset()
			_apply_transform()
		else:
			_update_hover(mm.position)


func _zoom_at(point: Vector2, factor: float) -> void:
	var before := (point - _offset) / _zoom
	_zoom = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	_offset = point - before * _zoom
	_clamp_offset()
	_apply_transform()


func _clamp_offset() -> void:
	var span := _chart_size * _zoom
	var view := _holder.size
	_offset.x = clampf(_offset.x, minf(view.x - span.x, 0.0), maxf(0.0, view.x - span.x))
	_offset.y = clampf(_offset.y, minf(view.y - span.y, 0.0), maxf(0.0, view.y - span.y))


func _update_hover(point: Vector2) -> void:
	var best := -1
	var best_distance := 26.0
	for i in _places.size():
		var screen := chart_to_screen(world_to_chart(_places[i]["xz"]))
		var d := screen.distance_to(point)
		if d < best_distance:
			best_distance = d
			best = i
	if best == _hovered:
		if best >= 0:
			_hover_plate.position = point + Vector2(18, -10)
		return
	_hovered = best
	if best < 0:
		_hover_plate.visible = false
	else:
		var place: Dictionary = _places[best]
		_hover_label.text = str(place["name"])
		_hover_plate.visible = true
		_hover_plate.position = point + Vector2(18, -10)
		UiKit.ink_in(_hover_plate, 0.0, 0.16)
	_refresh_markers()


func _process(delta: float) -> void:
	if not UI.is_menu_open("map"):
		return
	var pan := Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_forward", "move_back"))
	if pan.length() > 0.15:
		_offset -= pan * PAN_SPEED * delta
		_clamp_offset()
		_apply_transform()
	var zoom_axis := 0.0
	if InputMap.has_action("attack_heavy") and Input.is_action_pressed("attack_heavy"):
		zoom_axis += 1.0
	if InputMap.has_action("block") and Input.is_action_pressed("block"):
		zoom_axis -= 1.0
	if absf(zoom_axis) > 0.01:
		_zoom_at(_holder.size * 0.5, 1.0 + zoom_axis * delta * 1.6)


## Used by the review harness so the chart is shown at a readable place without a player.
func review_focus(xz: Vector2, zoom := 1.0) -> void:
	_zoom = zoom
	centre_on_world(xz)
