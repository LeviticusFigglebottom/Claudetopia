extends Control
## The chart (DESIGN §5.16). A painted map of the basin, unread until you have been there:
## fog lifts around places you have discovered and much further around places you have
## surveyed from a high vista. Quest areas are soft smudges over places you have found; the
## tracked quest's objectives are seals of red wax where the world has them now (Waymarks), found
## or not, the same as on the compass. Nothing else you have not found is drawn.
##
## The chart itself is painted by tools/ui/gen_map.py; world_map.json carries the
## world-to-pixel transform.
##
## Beside it, the road (triage 30, then 43): every lit Hearthstone, then every place you have
## found, by region, nearest first, with a line to find one by name; a click on a found place's
## marker chooses it ("Travel there", a double-click goes at once). A press takes the road from
## wherever you stand (Hearth.travel_to: the fade, the set-down, the clock, the wait for the
## country). Refused, with the reason said on the page, indoors, with a foe on you, or with more
## in the bag than you can carry.

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
	"cairn": 320.0, "tally_post": 300.0, "grave": 280.0, "gibbet": 360.0, "fold": 340.0, "well": 300.0,
	"lantern_post": 360.0, "hut": 340.0, "crossroads": 380.0, "peat_cut": 300.0, "beacon": 560.0,
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
## The tracked quest's objectives on the chart: [{xz, text}], read once as the chart opens.
var _pins: Array[Dictionary] = []
var _pin_nodes: Array[TextureRect] = []
const PIN_PX := Vector2(30, 30)
var _player_marker: TextureRect
var _hovered := -1
## The road: its column, the line that says why it is shut, the place chosen on the chart, the
## line to find a place by name, and its list.
const ROAD_W := 230.0
var _road: VBoxContainer
var _road_why: Label
var _road_list: VBoxContainer
var _road_find: LineEdit
var _chosen_box: VBoxContainer
var _chosen_label: Label
var _chosen_go: Button
var _chosen := ""
## Where a left press on the paper began: a release near it is a click (on a marker, a choice).
var _press_at := Vector2.INF


func setup(args: Dictionary) -> void:
	if args.has("choose"):
		call_deferred("choose", str(args["choose"]))
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
	_gather_pins()
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
	add_child(frame)
	UiFit.inset(frame, 40.0, 26.0)
	var body: VBoxContainer = page["body"]

	var row := UiKit.row(14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(row)
	_holder = Control.new()
	_holder.clip_contents = true
	_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_holder.mouse_filter = Control.MOUSE_FILTER_STOP
	_holder.gui_input.connect(_on_map_input)
	row.add_child(_holder)
	_build_road(row)

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


## The road, beside the chart: shown when there is anywhere to go. A line to find a place by
## name, the place chosen on the chart with its "Travel there", and the list: the lit stones
## first, then every place found, grouped by region, the nearest region and the nearest place in
## it first.
func _build_road(row: HBoxContainer) -> void:
	_road = UiKit.column(6)
	_road.custom_minimum_size = Vector2(ROAD_W, 0)
	_road.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(_road)
	# wrapped to the column: on one line the heading made the column half the chart's width
	_road.add_child(UiKit.wrapped("The road", "Heading", ROAD_W))
	_road_why = UiKit.wrapped("", "Small", ROAD_W)
	_road_why.visible = false
	_road.add_child(_road_why)
	_chosen_box = UiKit.column(4)
	_chosen_box.visible = false
	_chosen_label = UiKit.wrapped("", "Body", ROAD_W)
	_chosen_box.add_child(_chosen_label)
	_chosen_go = UiKit.button("Travel there", "FlatButton")
	_chosen_go.pressed.connect(func() -> void:
		if not _chosen.is_empty():
			take_road(_chosen))
	_chosen_box.add_child(_chosen_go)
	_road.add_child(_chosen_box)
	_road_find = LineEdit.new()
	_road_find.placeholder_text = "Find a place"
	_road_find.clear_button_enabled = true
	_road_find.custom_minimum_size = Vector2(ROAD_W, 0)
	_road_find.text_changed.connect(func(_t: String) -> void: _filter_road())
	_road.add_child(_road_find)
	_road_list = UiKit.column(4)
	_road.add_child(UiKit.scroll(_road_list))
	refresh_road()


## Fills the road's list: the lit stones, then every place found by region, and says why the road
## is shut when it is.
func refresh_road() -> void:
	if _road == null:
		return
	for child in _road_list.get_children():
		_road_list.remove_child(child)
		child.queue_free()
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var targets: Array[Dictionary] = []
	if player != null:
		targets = Hearth.destinations_from(player.global_position)
	_road.visible = not targets.is_empty()
	if targets.is_empty():
		return
	var why := Hearth.why_no_travel()
	_road_why.text = why
	_road_why.visible = not why.is_empty()
	_chosen_go.disabled = not why.is_empty()
	var buttons: Array[Control] = []
	var stones := targets.filter(func(t: Dictionary) -> bool: return bool(t["stone"]))
	if not stones.is_empty():
		_road_list.add_child(_group_heading("Hearthstones"))
		for t in stones:
			buttons.append(_road_button(t, why))
	# by region: nearest region first (targets are nearest first), nearest place first in each
	var regions: Array[String] = []
	var by_region: Dictionary = {}
	for t in targets:
		if bool(t["stone"]):
			continue
		var r := str(t["region_name"])
		if not by_region.has(r):
			by_region[r] = []
			regions.append(r)
		(by_region[r] as Array).append(t)
	for r in regions:
		_road_list.add_child(_group_heading(r))
		for t in by_region[r]:
			buttons.append(_road_button(t, why))
	UiKit.focus_chain(buttons)
	_filter_road()


func _group_heading(text: String) -> Label:
	var l := UiKit.wrapped(text, "Small", ROAD_W)
	l.set_meta("road_group", true)
	l.modulate = Color(1, 1, 1, 0.75)
	return l


func _road_button(t: Dictionary, why: String) -> Button:
	var id := str(t["id"])
	var b := UiKit.button("%s  ·  %.1f km" % [str(t["name"]), float(t["km"])], "FlatButton")
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.tooltip_text = "Take the road to %s" % str(t["name"])
	b.set_meta("travel_to", id)
	b.set_meta("travel_name", str(t["name"]).to_lower())
	b.disabled = not why.is_empty()
	b.pressed.connect(take_road.bind(id))
	_road_list.add_child(b)
	return b


## Shows only the places whose name has the words typed, and the headings over any shown.
func _filter_road() -> void:
	if _road_list == null:
		return
	var want := _road_find.text.strip_edges().to_lower() if _road_find != null else ""
	var heading: Control = null
	var shown_under := 0
	for c in _road_list.get_children():
		var ctl := c as Control
		if ctl == null or ctl.is_queued_for_deletion():
			continue
		if ctl.has_meta("road_group"):
			if heading != null:
				heading.visible = shown_under > 0
			heading = ctl
			shown_under = 0
			continue
		ctl.visible = want.is_empty() or str(ctl.get_meta("travel_name", "")).contains(want)
		if ctl.visible:
			shown_under += 1
	if heading != null:
		heading.visible = shown_under > 0


## A place chosen on the chart (a click on its marker): named at the top of the road, with how far
## and "Travel there". False for a place the road does not go to.
func choose(id: String) -> bool:
	if not Hearth.can_travel_to(id):
		return false
	_chosen = id
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var km := 0.0
	if player != null:
		var there := TravelPlaces.centre_of(id)
		km = Vector2(there.x - player.global_position.x, there.z - player.global_position.z).length() / 1000.0
	var def := ContentDB.get_or_empty(id)
	_chosen_label.text = "%s  ·  %.1f km" % [str(def.get("name", id)), km]
	var why := Hearth.why_no_travel()
	_chosen_go.disabled = not why.is_empty()
	_chosen_box.visible = true
	_road.visible = true
	UiKit.ink_in(_chosen_box, 0.0, 0.16)
	return true


## The place chosen on the chart, "" for none.
func chosen() -> String:
	return _chosen


## Takes the road to the lit stone or found place `id` from here: the chart closes and the journey
## runs under the fade. False (and the reason said on the page) when the road is shut.
func take_road(id: String) -> bool:
	var why := Hearth.why_no_travel()
	if why.is_empty() and not Hearth.can_travel_to(id):
		why = "You have not been there."
	if not why.is_empty():
		EventBus.notify.emit(why, "warning")
		refresh_road()
		return false
	UI.close("map")
	return Hearth.travel_to(id)


func _update_foot() -> void:
	var drag := "drag to move · wheel to zoom · click a place to travel" if not UI.using_gamepad \
			else "left stick to move · triggers to zoom"
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


## The tracked quest's open objectives, where the world has them (the door of the building for
## somebody indoors, the Choir for a fight at the Choir).
func _gather_pins() -> void:
	_pins.clear()
	var quests := get_tree().get_first_node_in_group("quest_log")
	if quests == null or not is_instance_valid(quests) or not quests.has_method("tracked_objectives"):
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var from := player.global_position if player != null else Vector3.INF
	for o in quests.call("tracked_objectives"):
		var obj: Dictionary = o
		if bool(obj.get("done", false)):
			continue
		var at := Waymarks.locate(obj["anchor"], from, str(GameState.current_interior_id))
		if bool(at.get("ok", false)):
			_pins.append({"xz": at["map_xz"], "text": str(obj.get("text", ""))})


## Where the tracked objectives are on the chart, for the tests and the review harness.
func tracked_pins() -> Array[Dictionary]:
	return _pins.duplicate()


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

	# the tracked objectives: a wax seal with its ribbon's point on the spot
	while _pin_nodes.size() < _pins.size():
		var pin := TextureRect.new()
		pin.texture = ThemeBuilder.variant_texture("warm", ["quest_pin"])
		pin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pin.size = PIN_PX
		pin.custom_minimum_size = PIN_PX
		pin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_markers.add_child(pin)
		_pin_nodes.append(pin)
	for i in _pin_nodes.size():
		var pin := _pin_nodes[i]
		pin.visible = i < _pins.size()
		if pin.visible:
			var xz: Vector2 = _pins[i]["xz"]
			pin.position = chart_to_screen(world_to_chart(xz)) - Vector2(PIN_PX.x * 0.5, PIN_PX.y * 0.93)
	if _hover_plate != null:
		_markers.move_child(_hover_plate, _markers.get_child_count() - 1)

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
			if mb.pressed:
				_press_at = mb.position
				if mb.double_click:
					var twice := place_at(mb.position)
					if not twice.is_empty() and Hearth.can_travel_to(twice):
						take_road(twice)
			elif _press_at != Vector2.INF and mb.position.distance_to(_press_at) < 6.0:
				_press_at = Vector2.INF
				var id := place_at(mb.position)
				if not id.is_empty():
					choose(id)
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


## The found place whose marker is under `point` (the paper's own coordinates), "" for none.
func place_at(point: Vector2) -> String:
	var best := ""
	var best_distance := 26.0
	for place in _places:
		var d := chart_to_screen(world_to_chart(place["xz"])).distance_to(point)
		if d < best_distance:
			best_distance = d
			best = str(place["id"])
	return best


## Where the found place `id`'s marker is on the paper, INF when it has none.
func marker_point(id: String) -> Vector2:
	for place in _places:
		if str(place["id"]) == id:
			return chart_to_screen(world_to_chart(place["xz"]))
	return Vector2.INF


func _update_hover(point: Vector2) -> void:
	var best := -1
	var best_distance := 26.0
	for i in _places.size():
		var screen := chart_to_screen(world_to_chart(_places[i]["xz"]))
		var d := screen.distance_to(point)
		if d < best_distance:
			best_distance = d
			best = i
	# a pin answers with its objective, above the place it stands on (-2 - its index)
	for i in _pins.size():
		var tip := chart_to_screen(world_to_chart(_pins[i]["xz"])) - Vector2(0.0, PIN_PX.y * 0.5)
		var d := tip.distance_to(point)
		if d < best_distance:
			best_distance = d
			best = -2 - i
	if best == _hovered:
		if best != -1:
			_hover_plate.position = point + Vector2(18, -10)
		return
	_hovered = best
	if best == -1:
		_hover_plate.visible = false
	else:
		_hover_label.text = str(_places[best]["name"]) if best >= 0 else str(_pins[-2 - best]["text"])
		_hover_plate.visible = true
		_hover_plate.position = point + Vector2(18, -10)
		UiKit.ink_in(_hover_plate, 0.0, 0.16)
	_refresh_markers()


func _process(delta: float) -> void:
	if not UI.is_menu_open("map"):
		return
	# the keys that move the paper are letters too: while a name is being typed, they are the name's
	if _road_find != null and _road_find.has_focus():
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
