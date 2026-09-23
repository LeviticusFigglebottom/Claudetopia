extends Control
## The head-up display (DESIGN §5.16): three bars, four quick slots, the compass strip,
## the lock-on reticle, the interaction prompt, the region title card, the boss bar, status
## icons and the subtitle line. It fades when nothing is happening, hides behind menus, and
## takes its resting opacity from Settings gameplay/hud_opacity.
##
## It reads other streams by group and by duck typing, so it works before they land:
##   player            health/max_health, stamina/max_stamina, mana/max_mana, `stats_changed`,
##                     `lock_on_changed(target)`, `spell_readied(id)`, `equipped_spell`,
##                     a child with `prompt_changed(text)`
##   equipment         quick_item(slot) / quick_count(slot)
##   quest_log         active_markers() -> [{place_id, radius}]

const IDLE_SECONDS := 7.0
const IDLE_ALPHA := 0.35
const REGION_CARD_SECONDS := 4.2
const SUBTITLE_SECONDS := 4.0
const STATUS_DEFAULT_SECONDS := 12.0
## How long a new objective's line stays under the compass before it goes back to the journal.
const OBJECTIVE_SECONDS := 7.0

var _player: Node = null
var _equipment: Node = null
var _quest_log: Node = null

var _bars: Dictionary = {}          # kind -> StatBar
var _compass: Compass
var _quick_slots: Array[Control] = []
var _saying_plate: PanelContainer
var _saying_mark: SchoolMark
var _saying_name: Label
var _saying_cost: Label
var _prompt: PanelContainer
var _prompt_label: Label
var _prompt_glyph: Label
var _reticle: TextureRect
var _region_card: VBoxContainer
var _region_name: Label
var _region_tagline: Label
var _boss_box: VBoxContainer
var _boss_name: Label
var _boss_bar: TextureProgressBar
var _status_row: HBoxContainer
var _subtitle: Label
## The subtitle fades on the wall clock (WallTweens): on a machine drawing a frame every few seconds,
## the Warden's first words were still half-inked on the first frame of control.
var _wall := WallTweens.new()
var _subtitle_tween: Tween = null
## The line under the compass that says what to do next when it changes.
var _objective: Label
var _objective_tween: Tween

var _lock_target: Node3D = null
var _boss_id := ""
var _boss_node: Node = null
var _idle := 0.0
var _statuses: Array[Dictionary] = []
var _marker_cache: Array[Dictionary] = []
var _prompt_action := "interact"
## The heading the strip shows: the view's, eased (Compass.ease_heading). -1 until the first frame.
var _shown_heading := -1.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Last in the frame, so the compass and the reticle read the view the camera rig set up this
	# frame rather than the one it left behind last frame.
	process_priority = 100
	_build()
	_connect_world()
	EventBus.region_entered.connect(_on_region_entered)
	# Every one of these is a method reference and not a closure, deliberately. A lambda
	# connected to an autoload's signal is not disconnected when the node that made it is
	# freed -- the bus holds the closure, not the node -- so a HUD from a finished world
	# went on being called for the rest of the process, once per signal, forever.
	EventBus.place_discovered.connect(_on_place_discovered)
	EventBus.boss_started.connect(_on_boss_started)
	EventBus.boss_defeated.connect(_on_boss_defeated)
	EventBus.status_applied.connect(_on_status_applied)
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.player_spawned.connect(_on_player_spawned)
	EventBus.item_equipped.connect(_on_item_equipped)
	EventBus.quest_started.connect(_on_quest_moved)
	EventBus.quest_stage_changed.connect(_on_quest_moved)
	UI.input_device_changed.connect(_on_input_device_changed)
	UI.variant_changed.connect(_on_variant_changed)
	Settings.changed.connect(_on_setting_changed)
	_apply_settings()
	_rebuild_markers()
	_refresh_quick()


func _on_place_discovered(_id: String) -> void:
	_rebuild_markers()


func _on_player_spawned(_p: Node) -> void:
	_connect_world()


func _on_item_equipped(_slot: String, _item_id: String) -> void:
	_refresh_quick()


func _on_input_device_changed(_pad: bool) -> void:
	_refresh_prompt_glyph()


func _on_variant_changed(_variant: String) -> void:
	_refresh_quick()


func _on_setting_changed(section: String, key: String, _value: Variant) -> void:
	if section == "gameplay" and key in ["hud_opacity", "compass", "subtitles"]:
		_apply_settings()


# --- construction ---------------------------------------------------------------------------

func _build() -> void:
	# compass strip, top centre
	_compass = Compass.new()
	_compass.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_compass.anchor_left = 0.5
	_compass.anchor_right = 0.5
	_compass.offset_left = -260.0
	_compass.offset_right = 260.0
	_compass.offset_top = 14.0
	_compass.offset_bottom = 70.0
	add_child(_compass)

	# what to do next, under the compass, for a few seconds whenever it changes
	_objective = UiKit.label("", "Small", HORIZONTAL_ALIGNMENT_CENTER)
	_objective.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_objective.anchor_left = 0.5
	_objective.anchor_right = 0.5
	_objective.offset_left = -300.0
	_objective.offset_right = 300.0
	_objective.offset_top = 74.0
	_objective.offset_bottom = 100.0
	_objective.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.6))
	_objective.add_theme_constant_override("shadow_offset_x", 1)
	_objective.add_theme_constant_override("shadow_offset_y", 1)
	_objective.modulate.a = 0.0
	_objective.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_objective)

	# bars, bottom left
	var bars := UiKit.column(5)
	bars.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	bars.offset_left = 26.0
	bars.offset_top = -132.0
	bars.offset_right = 306.0
	bars.offset_bottom = -26.0
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bars)
	# The three bars sit in one brass-framed plate, the way the quick slots and the toasts do.
	# Loose troughs on the grass read as a programmer's overlay against the painted country.
	var bar_plate := UiKit.panel("ChromePanel")
	bar_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars.add_child(bar_plate)
	var bar_column := UiKit.column(4)
	bar_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_column.add_theme_constant_override("margin_left", 6)
	bar_plate.add_child(bar_column)
	for kind: String in ["health", "stamina", "mana"]:
		var bar := StatBar.new()
		bar.kind = kind
		bar.custom_minimum_size = Vector2(268, 20 if kind == "health" else 15)
		bar.show_value = kind == "health"
		bar_column.add_child(bar)
		_bars[kind] = bar

	_status_row = UiKit.row(6)
	_status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars.add_child(_status_row)

	# quick slots, bottom right
	var quick := UiKit.row(8)
	quick.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	quick.offset_left = -400.0
	quick.offset_top = -108.0
	quick.offset_right = -24.0
	quick.offset_bottom = -26.0
	quick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(quick)
	for i in 4:
		var slot := _make_quick_slot(i + 1)
		quick.add_child(slot)
		_quick_slots.append(slot)

	# the readied saying, sitting over the quick slots: the school's mark, its name, and what
	# it costs against the breath in the bar on the other side of the screen
	_saying_plate = UiKit.panel("ChromePanel")
	_saying_plate.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_saying_plate.offset_left = -300.0
	_saying_plate.offset_top = -152.0
	_saying_plate.offset_right = -24.0
	_saying_plate.offset_bottom = -114.0
	_saying_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_saying_plate.visible = false
	add_child(_saying_plate)
	var saying_row := UiKit.row(8)
	saying_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_saying_plate.add_child(UiKit.margins(saying_row, 10, 0, 10, 0))
	_saying_mark = SchoolMark.new()
	_saying_mark.custom_minimum_size = Vector2(22, 22)
	_saying_mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	saying_row.add_child(_saying_mark)
	_saying_name = UiKit.label("", "Body")
	_saying_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_saying_name.clip_text = true
	saying_row.add_child(_saying_name)
	_saying_cost = UiKit.label("", "Small", HORIZONTAL_ALIGNMENT_RIGHT)
	saying_row.add_child(_saying_cost)

	# boss bar, above the quick slots
	_boss_box = UiKit.column(2)
	_boss_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_boss_box.anchor_left = 0.5
	_boss_box.anchor_right = 0.5
	_boss_box.offset_left = -240.0
	_boss_box.offset_right = 240.0
	_boss_box.offset_top = -112.0
	_boss_box.offset_bottom = -44.0
	_boss_box.visible = false
	_boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_boss_box)
	_boss_name = UiKit.label("", "Heading", HORIZONTAL_ALIGNMENT_CENTER)
	_boss_box.add_child(_boss_name)
	_boss_bar = TextureProgressBar.new()
	_boss_bar.texture_under = ThemeBuilder.variant_texture("warm", ["bar_track"])
	_boss_bar.texture_progress = ThemeBuilder.fill("boss")
	_boss_bar.nine_patch_stretch = true
	_boss_bar.stretch_margin_left = 6
	_boss_bar.stretch_margin_right = 6
	_boss_bar.stretch_margin_top = 6
	_boss_bar.stretch_margin_bottom = 6
	_boss_bar.min_value = 0.0
	_boss_bar.max_value = 1.0
	_boss_bar.step = 0.0
	_boss_bar.value = 1.0
	_boss_bar.custom_minimum_size = Vector2(0, 18)
	_boss_box.add_child(_boss_bar)

	# interaction prompt, a little below the middle
	_prompt = UiKit.panel("ChromePanel")
	_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_prompt.anchor_left = 0.5
	_prompt.anchor_right = 0.5
	_prompt.anchor_top = 0.5
	_prompt.anchor_bottom = 0.5
	_prompt.offset_left = -160.0
	_prompt.offset_right = 160.0
	_prompt.offset_top = 76.0
	_prompt.offset_bottom = 126.0
	_prompt.visible = false
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_prompt)
	var prow := UiKit.row(10)
	prow.alignment = BoxContainer.ALIGNMENT_CENTER
	_prompt.add_child(prow)
	_prompt_glyph = UiKit.label("E", "Emphasis")
	_prompt_glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_glyph.custom_minimum_size = Vector2(34, 0)
	_prompt_glyph.add_theme_color_override("font_color", ThemeBuilder.colour("accent", "warm"))
	prow.add_child(_prompt_glyph)
	_prompt_label = UiKit.label("", "Body")
	prow.add_child(_prompt_label)

	# region title card, centre
	_region_card = UiKit.column(2)
	_region_card.set_anchors_preset(Control.PRESET_CENTER)
	_region_card.anchor_left = 0.5
	_region_card.anchor_right = 0.5
	_region_card.anchor_top = 0.5
	_region_card.anchor_bottom = 0.5
	_region_card.offset_left = -400.0
	_region_card.offset_right = 400.0
	_region_card.offset_top = -120.0
	_region_card.offset_bottom = -10.0
	_region_card.modulate.a = 0.0
	_region_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_region_card)
	_region_name = UiKit.label("", "Title", HORIZONTAL_ALIGNMENT_CENTER)
	_region_card.add_child(_region_name)
	var card_rule := CenterContainer.new()
	var rule := UiKit.divider()
	rule.custom_minimum_size = Vector2(360, 16)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card_rule.add_child(rule)
	_region_card.add_child(card_rule)
	_region_tagline = UiKit.wrapped("", "Journal", 620)
	_region_tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_region_card.add_child(_region_tagline)

	# lock-on reticle
	_reticle = TextureRect.new()
	_reticle.texture = ThemeBuilder.marker("reticle")
	_reticle.custom_minimum_size = Vector2(46, 46)
	_reticle.size = Vector2(46, 46)
	_reticle.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_reticle.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle.visible = false
	_reticle.modulate = Color(1, 1, 1, 0.85)
	add_child(_reticle)

	# subtitles, above the bars
	_subtitle = UiKit.label("", "Body", HORIZONTAL_ALIGNMENT_CENTER)
	_subtitle.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_subtitle.anchor_left = 0.5
	_subtitle.anchor_right = 0.5
	_subtitle.offset_left = -420.0
	_subtitle.offset_right = 420.0
	_subtitle.offset_top = -176.0
	_subtitle.offset_bottom = -140.0
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.modulate.a = 0.0
	_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_subtitle)

	# the first minutes' controls, low in the middle: above the quick slots' tops and clear of
	# the bars' right edge at 1280 wide, under where a subtitle sits
	var hints := ControlHints.new()
	hints.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hints.anchor_left = 0.5
	hints.anchor_right = 0.5
	hints.offset_left = -330.0
	hints.offset_right = 330.0
	hints.offset_top = -148.0
	hints.offset_bottom = -116.0
	hints.grow_horizontal = Control.GROW_DIRECTION_BOTH      # wider than its rect, still centred
	add_child(hints)


func _make_quick_slot(number: int) -> Control:
	var panel := UiKit.panel("ChromePanel")
	panel.custom_minimum_size = Vector2(58, 58)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(40, 40)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(stack)
	var icon := UiKit.icon_rect("potion", 34)
	icon.name = "Icon"
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(icon)
	var count := UiKit.label("", "Tiny", HORIZONTAL_ALIGNMENT_RIGHT)
	count.name = "Count"
	count.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	count.offset_left = -26.0
	count.offset_top = -14.0
	count.offset_right = 4.0
	count.offset_bottom = 4.0
	stack.add_child(count)
	var key := UiKit.label(str(number), "Tiny")
	key.name = "Key"
	key.set_anchors_preset(Control.PRESET_TOP_LEFT)
	key.offset_left = -4.0
	key.offset_top = -14.0
	key.offset_right = 22.0
	key.offset_bottom = 4.0
	key.modulate = Color(1, 1, 1, 0.7)
	stack.add_child(key)
	return panel


# --- world hookup -----------------------------------------------------------------------------

func _connect_world() -> void:
	_player = get_tree().get_first_node_in_group("player")
	_equipment = get_tree().get_first_node_in_group("equipment")
	_quest_log = get_tree().get_first_node_in_group("quest_log")
	if _player and is_instance_valid(_player):
		if _player.has_signal("stats_changed") and not _player.is_connected("stats_changed", _refresh_stats):
			_player.connect("stats_changed", _refresh_stats)
		if _player.has_signal("lock_on_changed") and not _player.is_connected("lock_on_changed", _on_lock_on):
			_player.connect("lock_on_changed", _on_lock_on)
		if _player.has_signal("spell_readied") and not _player.is_connected("spell_readied", _on_spell_readied):
			_player.connect("spell_readied", _on_spell_readied)
		var interactor := _find_interactor(_player)
		if interactor and not interactor.is_connected("prompt_changed", _on_prompt_changed):
			interactor.connect("prompt_changed", _on_prompt_changed)
		# The belt's counts are the bag's: a draught drunk or a swallow taken changes what the slot
		# says without anything being equipped, and the slot only ever listened for equipping.
		var bag := _player.get_node_or_null(NodePath("Inventory"))
		if bag != null and bag.has_signal("stack_changed"):
			if not bag.is_connected("changed", _on_bag_changed):
				bag.connect("changed", _on_bag_changed)
			if not bag.is_connected("stack_changed", _on_bag_stack_changed):
				bag.connect("stack_changed", _on_bag_stack_changed)
	_refresh_stats()
	_refresh_quick()
	_refresh_saying()


func _on_bag_changed() -> void:
	_refresh_quick()


func _on_bag_stack_changed(_stack: ItemStack) -> void:
	_refresh_quick()


func _find_interactor(root: Node) -> Node:
	for child in root.get_children():
		if child.has_signal("prompt_changed"):
			return child
	return null


func _refresh_stats() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	for kind: String in _bars:
		var bar: StatBar = _bars[kind]
		var value: Variant = _player.get(kind)
		var maximum: Variant = _player.get("max_" + kind)
		if value == null or maximum == null:
			bar.visible = false
			continue
		bar.visible = true
		bar.set_values(float(value), float(maximum))
	_refresh_saying()


func _refresh_quick() -> void:
	for i in _quick_slots.size():
		var panel := _quick_slots[i]
		var icon := panel.find_child("Icon", true, false) as TextureRect
		var count := panel.find_child("Count", true, false) as Label
		var key := panel.find_child("Key", true, false) as Label
		if key:
			key.text = UI.prompt_for("quick_%d" % (i + 1))
		var item_id := ""
		var n := 0
		if _equipment and is_instance_valid(_equipment) and _equipment.has_method("quick_item"):
			item_id = str(_equipment.call("quick_item", "quick_%d" % (i + 1)))
			if _equipment.has_method("quick_count"):
				n = int(_equipment.call("quick_count", "quick_%d" % (i + 1)))
		if item_id.is_empty():
			if icon:
				icon.texture = null
			if count:
				count.text = ""
			panel.modulate = Color(1, 1, 1, 0.45)
			continue
		panel.modulate = Color(1, 1, 1, 1.0)
		var def := ContentDB.get_or_empty(item_id)
		if icon:
			icon.texture = ThemeBuilder.icon(UiKit.item_icon_name(def))
		if Flask.is_flask(item_id):
			# The flask shows its swallows against a full filling, and goes dim when it is dry.
			var flask := _equipment.call("quick_stack", "quick_%d" % (i + 1)) as ItemStack
			if count:
				count.text = "%d/%d" % [n, Flask.max_charges(flask)]
			if n <= 0:
				panel.modulate = Color(1, 1, 1, 0.45)
		elif count:
			count.text = str(n) if n > 1 else ""


func _on_spell_readied(_spell_id: String) -> void:
	_refresh_saying()
	_idle = 0.0


## The readied saying's plate. Hidden when nothing is readied, so a character who does not Say
## never sees a slot asking to be filled.
func _refresh_saying() -> void:
	if _saying_plate == null:
		return
	var id := ""
	if _player and is_instance_valid(_player):
		id = str(_player.get("equipped_spell"))
	var def := ContentDB.get_or_empty(id)
	if id.is_empty() or def.is_empty():
		_saying_plate.visible = false
		return
	var was_hidden := not _saying_plate.visible
	_saying_plate.visible = true
	_saying_mark.school = SpellRuntime.school_of(def)
	_saying_name.text = str(def.get("name", id))
	var cost := float(def.get("cost", 0.0))
	_saying_cost.text = "%d" % roundi(cost)
	var mana: Variant = _player.get("mana") if _player and is_instance_valid(_player) else null
	var enough := mana == null or float(mana) >= cost
	_saying_cost.modulate = Color(1, 1, 1, 1) if enough else ThemeBuilder.colour("accent", UI.theme_variant)
	_saying_plate.modulate = Color(1, 1, 1, 1.0 if enough else 0.7)
	if was_hidden:
		UiKit.ink_in(_saying_plate, 0.0, 0.3)


func _refresh_prompt_glyph() -> void:
	_prompt_glyph.text = UI.prompt_for(_prompt_action)


# --- markers ----------------------------------------------------------------------------------

## Discovered places only, by their def `position` ([x, z]); quest areas become smudges.
func _rebuild_markers() -> void:
	_marker_cache.clear()
	for place_id in GameState.discovered_places:
		var def := ContentDB.get_or_empty(place_id)
		var pos: Array = def.get("position", [])
		if pos.size() < 2:
			continue
		_marker_cache.append({
			"xz": Vector2(float(pos[0]), float(pos[1])),
			"texture": ThemeBuilder.marker(str(def.get("kind", "poi"))),
			"label": str(def.get("name", "")),
		})


func _quest_areas() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _quest_log == null or not is_instance_valid(_quest_log) or not _quest_log.has_method("active_markers"):
		return out
	for m in _quest_log.call("active_markers"):
		if typeof(m) != TYPE_DICTIONARY:
			continue
		var def := ContentDB.get_or_empty(str(m.get("place_id", "")))
		var pos: Array = def.get("position", [])
		if pos.size() < 2:
			continue
		out.append({"xz": Vector2(float(pos[0]), float(pos[1])), "radius": float(m.get("radius", 150.0))})
	return out


# --- per frame --------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_wall.step()
	_idle += delta
	_update_compass(delta)
	_update_reticle()
	_update_statuses(delta)
	_update_boss()
	_update_idle_fade(delta)


## The strip shows where the player LOOKS: the view's heading, not the body's. It always read the
## camera, and the camera used to turn with the body, so a second of D swung the strip 90 degrees
## in steps of up to 21 a frame with the mouse still. Bearings to places are taken from where the
## body is drawn this frame (its interpolated position), so a marker does not step at 60 Hz.
func _update_compass(delta: float) -> void:
	if not _compass.visible:
		return
	var origin := Vector2.ZERO
	var heading := -1.0
	var cam := get_viewport().get_camera_3d()
	if cam:
		heading = Compass.heading_from_basis(cam.global_transform.basis)
		origin = Vector2(cam.global_position.x, cam.global_position.z)
	if _player and is_instance_valid(_player) and _player is Node3D and (_player as Node3D).is_inside_tree():
		var p := _player as Node3D
		var at := p.get_global_transform_interpolated().origin
		origin = Vector2(at.x, at.z)
		if cam == null:
			heading = Compass.heading_from_basis(p.global_transform.basis)
	if heading >= 0.0:
		_shown_heading = heading if _shown_heading < 0.0 else Compass.ease_heading(_shown_heading, heading, delta)
	var shown := maxf(_shown_heading, 0.0)
	_compass.heading_deg = shown
	_compass.player_xz = origin
	var markers: Array[Dictionary] = []
	for m in _marker_cache:
		var to: Vector2 = m["xz"]
		markers.append({"bearing": Compass.bearing_deg(origin, to), "texture": m["texture"],
				"label": m["label"], "distance": origin.distance_to(to)})
	_compass.markers = markers
	var areas: Array[Dictionary] = []
	for a in _quest_areas():
		var to: Vector2 = a["xz"]
		var dist: float = maxf(origin.distance_to(to), 1.0)
		areas.append({"bearing": Compass.bearing_deg(origin, to),
				"width_deg": clampf(rad_to_deg(atan(float(a["radius"]) / dist)) * 2.0, 6.0, 60.0)})
	_compass.areas = areas
	_compass.refresh()


func _update_reticle() -> void:
	if _lock_target == null or not is_instance_valid(_lock_target):
		_reticle.visible = false
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		# no camera (review harness): park the reticle where the target would be framed
		_reticle.visible = true
		_reticle.position = size * Vector2(0.5, 0.46) - _reticle.size * 0.5
		return
	# where the target is drawn this frame, not where the last physics tick left it
	var at := _lock_target.get_global_transform_interpolated().origin
	if cam.is_position_behind(at):
		_reticle.visible = false
		return
	_reticle.visible = true
	_reticle.position = cam.unproject_position(at) - _reticle.size * 0.5


func _update_statuses(delta: float) -> void:
	var changed := false
	for i in range(_statuses.size() - 1, -1, -1):
		_statuses[i]["left"] = float(_statuses[i]["left"]) - delta
		if float(_statuses[i]["left"]) <= 0.0:
			_statuses.remove_at(i)
			changed = true
	if changed:
		_rebuild_status_icons()


func _update_boss() -> void:
	if not _boss_box.visible:
		return
	if _boss_node and is_instance_valid(_boss_node):
		var hp: Variant = _boss_node.get("health")
		var mx: Variant = _boss_node.get("max_health")
		if hp != null and mx != null and float(mx) > 0.0:
			_boss_bar.value = clampf(float(hp) / float(mx), 0.0, 1.0)


func _update_idle_fade(_delta: float) -> void:
	var busy := _lock_target != null or _boss_box.visible or _prompt.visible
	if not busy and _bars.has("health"):
		busy = (_bars["health"] as StatBar).fraction() < 0.6
	# Stamina being spent or coming back is worth seeing: holding sprint sends no input events, so
	# a long run used to fade the bars out at seven seconds while the stamina drained.
	if not busy and _bars.has("stamina"):
		busy = (_bars["stamina"] as StatBar).fraction() < 0.995
	var target := _rest_alpha() if (_idle < IDLE_SECONDS or busy) else _rest_alpha() * IDLE_ALPHA
	modulate.a = move_toward(modulate.a, target, _delta * 1.6)


func _rest_alpha() -> float:
	return clampf(float(Settings.get_value("gameplay", "hud_opacity", 1.0)), 0.1, 1.0)


## The HUD arriving after something else has had the screen (the opening): from nothing, and
## awake, so it inks up to its resting opacity instead of to its idle one.
func come_up() -> void:
	modulate.a = 0.0
	_idle = 0.0


func _input(_event: InputEvent) -> void:
	_idle = 0.0


# --- events ------------------------------------------------------------------------------------

func _on_lock_on(target: Node3D) -> void:
	_lock_target = target
	_idle = 0.0


func _on_prompt_changed(text: String) -> void:
	set_prompt(text)


## The interaction prompt on the screen now ("[E] Talk to Wren Tallow"), or "" when none is up.
func prompt_text() -> String:
	return _prompt_label.text if _prompt != null and _prompt.visible else ""


func set_prompt(text: String, action := "interact") -> void:
	_prompt_action = action
	_prompt_label.text = text
	_refresh_prompt_glyph()
	var wanted := not text.is_empty()
	if wanted and not _prompt.visible:
		_prompt.visible = true
		UiKit.ink_in(_prompt, 0.0, 0.22)
	elif not wanted:
		_prompt.visible = false
	_idle = 0.0


func _on_region_entered(region_id: String, _previous: String) -> void:
	var def := ContentDB.get_or_empty(region_id)
	if def.is_empty():
		return
	show_region_card(str(def.get("name", "")), str(def.get("tagline", "")))
	_rebuild_markers()


## The name of a place arrives in ink and then lets go of the screen.
func show_region_card(title: String, tagline: String) -> void:
	_region_name.text = title
	_region_tagline.text = tagline
	_region_card.modulate = Color(0.3, 0.24, 0.19, 0.0)
	var tw := create_tween()
	tw.tween_property(_region_card, "modulate", Color(1, 1, 1, 1), 1.1).set_trans(Tween.TRANS_CUBIC)
	tw.tween_interval(REGION_CARD_SECONDS)
	tw.tween_property(_region_card, "modulate:a", 0.0, 1.4)


## A quest started or moved on: its next thing to do goes under the compass for a few seconds, so
## the player learns it from the screen and not from the journal, and the smudge on the strip
## above it says which way. Nothing is shown for a stage with nothing left to do.
func _on_quest_moved(quest_id: String, _stage: Variant = null) -> void:
	var line := objective_line(quest_id)
	if not line.is_empty():
		show_objective(line)


## "The Naming: Speak to the Warden at her fire" -- the quest's name and its first objective not
## yet done, or "" when there is none.
func objective_line(quest_id: String) -> String:
	var log_node := _quest_log if _quest_log != null and is_instance_valid(_quest_log) \
			else get_tree().get_first_node_in_group("quest_log")
	if log_node == null or not log_node.has_method("objectives_of"):
		return ""
	for o in log_node.call("objectives_of", quest_id):
		var obj: Dictionary = o
		if bool(obj.get("done", false)) or bool(obj.get("optional", false)):
			continue
		var name_of := str(ContentDB.get_or_empty(quest_id).get("name", ""))
		var text := str(obj.get("text", ""))
		return text if name_of.is_empty() else "%s: %s" % [name_of, text]
	return ""


func show_objective(text: String, seconds := OBJECTIVE_SECONDS) -> void:
	_objective.text = text
	if _objective_tween != null and _objective_tween.is_valid():
		_objective_tween.kill()
	_objective.modulate = Color(1, 1, 1, 0.0)
	_objective_tween = create_tween()
	_objective_tween.tween_property(_objective, "modulate:a", 1.0, 0.5)
	_objective_tween.tween_interval(seconds)
	_objective_tween.tween_property(_objective, "modulate:a", 0.0, 1.2)
	# the whole HUD is woken, so the line is not read through the idle fade
	_idle = 0.0


## The objective line as it stands, and whether it is on the screen: for the tests and the probe.
func objective_shown() -> String:
	return _objective.text if _objective != null and _objective.modulate.a > 0.05 else ""


## Whether a quest's smudge is on the part of the strip the compass is showing now.
func quest_marker_on_strip() -> bool:
	if _compass == null or not _compass.visible:
		return false
	for a in _quest_areas():
		var to: Vector2 = a["xz"]
		if Compass.on_strip(Compass.bearing_deg(_compass.player_xz, to), _compass.heading_deg, Compass.SPAN_DEG, 24.0):
			return true
	return false


func show_subtitle(text: String, seconds := SUBTITLE_SECONDS) -> void:
	if not bool(Settings.get_value("gameplay", "subtitles", true)):
		return
	_subtitle.text = text
	_subtitle.modulate = Color(0.3, 0.24, 0.19, 0.0)
	# a new line replaces the last one's fade rather than racing it for the label
	if _subtitle_tween != null and _subtitle_tween.is_valid():
		_subtitle_tween.kill()
	_subtitle_tween = _wall.own(create_tween())
	_subtitle_tween.tween_property(_subtitle, "modulate", Color(1, 1, 1, 1), 0.3)
	_subtitle_tween.tween_interval(seconds)
	_subtitle_tween.tween_property(_subtitle, "modulate:a", 0.0, 0.6)


## How far the subtitle has inked in, 0 to 1: for a test or the flow probe to read what a player sees.
func subtitle_alpha() -> float:
	return _subtitle.modulate.a if _subtitle != null else 0.0


func _on_boss_started(boss_id: String) -> void:
	_boss_id = boss_id
	var def := ContentDB.get_or_empty(boss_id)
	_boss_name.text = str(def.get("name", "")) if not def.is_empty() else Ids.name_of(boss_id).capitalize()
	_boss_bar.value = 1.0
	_boss_bar.texture_under = ThemeBuilder.variant_texture(UI.theme_variant, ["bar_track"])
	_boss_node = null
	_boss_box.visible = true
	UiKit.ink_in(_boss_box, 0.0, 0.8)


func _on_boss_defeated(_boss_id: String) -> void:
	_boss_node = null
	_boss_id = ""
	var tw := create_tween()
	tw.tween_property(_boss_box, "modulate:a", 0.0, 1.0)
	tw.tween_callback(func() -> void:
			_boss_box.visible = false
			_boss_box.modulate.a = 1.0)


func _on_damage_dealt(_attacker: Node, victim: Node, _amount: float, _kind: String) -> void:
	if _boss_id.is_empty() or _boss_node != null:
		return
	if victim and is_instance_valid(victim) and victim.get("max_health") != null and not victim.is_in_group("player"):
		_boss_node = victim


func _on_status_applied(target: Node, effect_id: String) -> void:
	if target != null and not target.is_in_group("player"):
		return
	var def := ContentDB.get_or_empty(effect_id)
	var seconds := float(def.get("duration_base", STATUS_DEFAULT_SECONDS))
	if seconds <= 0.0:
		seconds = STATUS_DEFAULT_SECONDS
	for s in _statuses:
		if s["id"] == effect_id:
			s["left"] = seconds
			return
	_statuses.append({"id": effect_id, "left": seconds, "name": str(def.get("name", Ids.name_of(effect_id)))})
	_rebuild_status_icons()


func _rebuild_status_icons() -> void:
	for child in _status_row.get_children():
		child.queue_free()
	for s in _statuses:
		var def := ContentDB.get_or_empty(str(s["id"]))
		var icon := UiKit.icon_rect(_status_icon_name(def), 26)
		icon.tooltip_text = "%s" % s["name"]
		_status_row.add_child(icon)
		UiKit.ink_in(icon, 0.0, 0.3)


func _status_icon_name(def: Dictionary) -> String:
	var tags: Array = def.get("tags", [])
	var stat := str(def.get("stat", ""))
	var kind := str(def.get("kind", ""))
	if tags.has("poison") or stat == "poison" or kind == "harm":
		return "skull"
	if tags.has("fire") or tags.has("burning"):
		return "hearth"
	if tags.has("frost") or tags.has("cold"):
		return "amulet"
	if tags.has("stealth") or tags.has("sight"):
		return "eye"
	if tags.has("restore") or tags.has("heal"):
		return "potion"
	if kind == "buff":
		return "shield"
	return "bell"


# --- settings ------------------------------------------------------------------------------------

func _apply_settings() -> void:
	_compass.visible = bool(Settings.get_value("gameplay", "compass", true))
	modulate.a = _rest_alpha()
	_idle = 0.0


## Used by tools_gd/ui_review.tscn to show a believable HUD without a world.
func review_state(state: String) -> void:
	_connect_world()
	_idle = 0.0
	if state == "combat":
		show_subtitle("The Reeve rings the hammer, and the barrow answers.")
		set_prompt("")
	else:
		show_region_card("Hearthvale", str(ContentDB.get_or_empty("core:region/hearthvale").get("tagline", "")))
		show_subtitle("Skylarks, and somewhere down the lane a mill wheel that should not be turning.")
