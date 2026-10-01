extends Control
## The head-up display (DESIGN §5.16): three bars, the belt (eight quick slots) and the weapon in
## hand with the weapon set's cycle notice, the compass strip,
## the lock-on reticle, the interaction prompt, the region title card, the boss bar, status
## icons and the subtitle line. It fades when nothing is happening, hides behind menus, and
## takes its resting opacity from Settings gameplay/hud_opacity.
##
## It reads other streams by group and by duck typing, so it works before they land:
##   player            health/max_health, stamina/max_stamina, mana/max_mana, `stats_changed`,
##                     `lock_on_changed(target)`, `spell_readied(id)`, `equipped_spell`,
##                     a child with `prompt_changed(text)`
##   equipment         quick_item(slot) / quick_count(slot)
##   quest_log         tracked_quest(), tracked_objectives() -> [{index, text, count, needed, anchor}],
##                     `tracked_changed(quest_id)`

const IDLE_SECONDS := 7.0
## The belt's sockets, the strap round them, and the lit socket of the weapon in the hand (px at the
## 1280x720 base): eight sockets fit between the boss bar and the right edge.
const SOCKET := 44.0
const BELT_WIDTH := SOCKET * 8.0 + 3.0 * 7.0 + 24.0
const WEAPON_SOCKET := 54.0
## How long the weapon set shows after a cycle (s), the last 0.4 fading.
const CYCLE_NOTICE_S := 1.8
## The breath gauge's wash over the Saying's fill, and how long it lingers full after surfacing.
const BREATH_TINT := Color(0.78, 0.95, 1.0, 0.92)
const BREATH_LINGER_S := 1.2
const IDLE_ALPHA := 0.35
const REGION_CARD_SECONDS := 4.2
const SUBTITLE_SECONDS := 4.0
const STATUS_DEFAULT_SECONDS := 12.0
## How long a new objective's line stays under the compass before it goes back to the journal.
const OBJECTIVE_SECONDS := 7.0
## A region's card waits while a cinematic plays and for this long (wall clock) after it hands
## over, so the first frame of control belongs to the place, the person at the fire and the
## objective's line, and the card comes after the line has gone.
const REGION_CARD_AFTER_HANDOVER_S := 8.0

var _player: Node = null
var _equipment: Node = null
var _quest_log: Node = null
## A region card asked for while a cinematic held the screen: [title, tagline, features], or [].
var _held_card: Array = []
## When a cinematic was last seen playing (Time.get_ticks_msec), or -1 for never.
var _cinematic_seen_ms := -1
## How long the card waits after a hand-over; a test shortens it.
var region_card_settle_s := REGION_CARD_AFTER_HANDOVER_S

var _bars: Dictionary = {}          # kind -> StatBar
var _breath_bar: StatBar = null     # the breath under water (_update_breath)
var _breath_linger := 0.0
var _compass: Compass
var _quick_slots: Array[Control] = []
## The belt's strap, the weapon in the hand over its left end, and the notice that shows the weapon
## set for a moment when the hand is cycled (show_weapon_cycle).
var _belt: PanelContainer
var _weapon_plate: PanelContainer
var _weapon_art: TextureRect
var _weapon_key: Label
var _cycle_notice: PanelContainer
var _cycle_name: Label
var _cycle_row: HBoxContainer
var _cycle_left := 0.0
var _saying_plate: PanelContainer
var _saying_mark: SchoolMark
var _saying_name: Label
var _saying_cost: Label
var _prompt: PanelContainer
var _prompt_label: Label
var _prompt_glyph: Label
var _reticle: TextureRect
## The aim's mark at the middle of the view while a bow is drawn or a saying aimed (triage 55).
var _crosshair: Crosshair
## The sneak read (_update_sneak_eye): while crouched, how much the most watchful near has of you.
var _eye: Label
var _eye_left := 0.0
var _region_card: VBoxContainer
var _region_name: Label
var _region_tagline: Label
var _region_features: Label
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
## Over the objective line when a quest moves: "NEW OBJECTIVE · MAIN QUEST" in the quest's colour;
## under it, the stage's first journal line, which says why (triage, fourth playtest: "going onto
## next stage of quest without clear direction why").
var _notice_head: Label
var _notice_why: Label
## Quests started this moment: their first stage is a new quest, not a new objective.
var _started_ms: Dictionary = {}

var _lock_target: Node3D = null
var _boss_id := ""
var _boss_node: Node = null
var _idle := 0.0
var _statuses: Array[Dictionary] = []
var _marker_cache: Array[Dictionary] = []
## Every place and POI on the map, read once, and where and when the strip last chose among them
## (CompassRules): it chooses again after a few metres or a second of the wall's time.
var _compass_places: Array = []
var _markers_from := Vector2.INF
var _markers_at_ms := -1000000
const MARKERS_EVERY_M := 8.0
const MARKERS_EVERY_MS := 1000
## The tracked quest's objectives where the world has them now (Waymarks.locate), looked up again a
## few times a second on the wall clock; the strip reads bearings off them every frame.
var _tracker: QuestTracker
var _hints: Control
var _waymarks: Array[Dictionary] = []   # [{key, at: Vector3, radius, ok, text, detail}]
var _waymarks_at_ms := -1000000
const WAYMARKS_EVERY_MS := 250
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
	get_viewport().size_changed.connect(_fit_to_canvas)
	_fit_to_canvas()
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
	EventBus.menu_opened.connect(_on_menu_opened)
	EventBus.item_equipped.connect(_on_item_equipped)
	EventBus.quest_started.connect(_on_quest_started)
	EventBus.quest_stage_changed.connect(_on_quest_moved)
	EventBus.quest_completed.connect(_on_quest_ended)
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
	_refresh_weapon_plate()


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
	_objective.offset_top = 90.0
	_objective.offset_bottom = 116.0
	_objective.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.6))
	_objective.add_theme_constant_override("shadow_offset_x", 1)
	_objective.add_theme_constant_override("shadow_offset_y", 1)
	_objective.modulate.a = 0.0
	_objective.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_objective)
	_notice_head = _notice_label("Tiny", 72.0, 90.0, 300.0)
	_notice_head.name = "NoticeHead"
	_notice_why = _notice_label("Small", 116.0, 160.0, 260.0)
	_notice_why.name = "NoticeWhy"
	_notice_why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice_why.max_lines_visible = 2
	_notice_why.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_notice_why.add_theme_color_override("font_color", Color(0.93, 0.9, 0.82, 0.92))

	# the tracked quest, top left: the compass has the top middle and the toasts the top right
	_tracker = QuestTracker.new()
	_tracker.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_tracker.offset_left = 22.0
	_tracker.offset_top = 18.0
	_tracker.offset_right = 22.0 + QuestTracker.WIDTH
	_tracker.offset_bottom = 18.0
	add_child(_tracker)

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
	# the breath, under water only: a short pale bar in the same plate, the Saying's blue washed
	# toward the water's white, that runs down while the head is under and fills again at the air
	_breath_bar = StatBar.new()
	_breath_bar.kind = "mana"
	_breath_bar.show_value = false
	_breath_bar.custom_minimum_size = Vector2(160, 9)
	_breath_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_breath_bar.modulate = BREATH_TINT
	_breath_bar.visible = false
	bar_column.add_child(_breath_bar)

	_status_row = UiKit.row(6)
	_status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars.add_child(_status_row)

	# the belt, bottom right: eight sockets on a stitched strap (things used, on 1-8), with the
	# weapon in the hand over its left end and the weapon set's notice above when it is cycled
	_belt = PanelContainer.new()
	_belt.add_theme_stylebox_override("panel", ThemeBuilder.box("belt_strap", PackedInt32Array([12, 5, 12, 5])))
	_belt.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_belt.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_belt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_belt.offset_left = -24.0 - BELT_WIDTH
	_belt.offset_right = -24.0
	_belt.offset_top = -24.0 - SOCKET - 10.0
	_belt.offset_bottom = -24.0
	_belt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_belt)
	var quick := UiKit.row(3)
	quick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	quick.alignment = BoxContainer.ALIGNMENT_CENTER
	_belt.add_child(quick)
	for i in Equipment.QUICK_SLOTS.size():
		var slot := _make_quick_slot(i + 1)
		quick.add_child(slot)
		_quick_slots.append(slot)
	_build_weapon_plate()

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
	_boss_box.offset_left = -220.0
	_boss_box.offset_right = 220.0
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
	_region_features = UiKit.wrapped("", "Small", 620)
	_region_features.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_region_card.add_child(_region_features)

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

	# the aim's mark, under the middle of the view
	_crosshair = Crosshair.new()
	add_child(_crosshair)

	# the sneak read, under the middle of the screen, only while crouched
	_eye = UiKit.label("", "Small", HORIZONTAL_ALIGNMENT_CENTER)
	_eye.set_anchors_preset(Control.PRESET_CENTER)
	_eye.anchor_left = 0.5
	_eye.anchor_right = 0.5
	_eye.offset_left = -120.0
	_eye.offset_right = 120.0
	_eye.offset_top = 64.0
	_eye.offset_bottom = 88.0
	_eye.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.7))
	_eye.add_theme_constant_override("shadow_offset_x", 1)
	_eye.add_theme_constant_override("shadow_offset_y", 1)
	_eye.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_eye.visible = false
	add_child(_eye)

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
	# over the belt's weapon socket, which stands up to 150 px off the foot at the right
	hints.offset_top = -192.0
	hints.offset_bottom = -160.0
	hints.grow_horizontal = Control.GROW_DIRECTION_BOTH      # wider than its rect, still centred
	add_child(hints)
	_hints = hints


## The HUD on the canvas the UI's size leaves (triage 28). At 1280x720 and wider everything sits
## where _build puts it. A large UI narrows the canvas (914x514 at 1.4 on 1280x720), and there the
## compass's strip ran under the tracked quest, the first minutes' controls across the bars and
## the saying's plate, and the prompt down among them. Narrow: a shorter compass with the tracked
## quest under it, the controls over the bars (the saying's plate a little narrower beside them), the subtitle
## over those, and the prompt kept above
## the subtitle. Follows the canvas as the setting changes.
func _fit_to_canvas() -> void:
	if _compass == null or not is_inside_tree():
		return
	var canvas := get_viewport_rect().size
	var narrow := canvas.x < 1100.0
	var half := 200.0 if narrow else 260.0
	_compass.offset_left = -half
	_compass.offset_right = half
	_tracker.offset_top = 78.0 if narrow else 18.0
	_tracker.offset_bottom = _tracker.offset_top
	if _hints != null:
		if narrow:
			# over the bars, from their left edge (clear of the saying's plate on the right)
			_hints.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
			_hints.grow_horizontal = Control.GROW_DIRECTION_END
			_hints.offset_left = 26.0
			_hints.offset_right = minf(canvas.x * 0.5, 660.0)
			_hints.offset_top = -172.0
			_hints.offset_bottom = -140.0
		else:
			_hints.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
			_hints.anchor_left = 0.5
			_hints.anchor_right = 0.5
			_hints.grow_horizontal = Control.GROW_DIRECTION_BOTH
			_hints.offset_left = -330.0
			_hints.offset_right = 330.0
			# over the belt's weapon socket, which stands up to 150 px off the foot at the right
			_hints.offset_top = -192.0
			_hints.offset_bottom = -160.0
	# the saying in hand, bottom right, a little narrower beside the controls
	_saying_plate.offset_left = -250.0 if narrow else -300.0
	var sub_half := minf(420.0, canvas.x * 0.5 - 24.0)
	_subtitle.offset_left = -sub_half
	_subtitle.offset_right = sub_half
	_subtitle.offset_top = -216.0 if narrow else -232.0
	_subtitle.offset_bottom = -180.0 if narrow else -196.0
	# the prompt a little below the middle, but never down among the subtitle and the bars
	var lowest := canvas.y * 0.5 + (-224.0 if narrow else -240.0)
	var lift := maxf(126.0 - lowest, 0.0)
	_prompt.offset_top = 76.0 - lift
	_prompt.offset_bottom = 126.0 - lift


## A socket of the belt: the item's painting in a sunk well, its count at the foot, its key on a
## brass tab at the top left.
func _make_quick_slot(number: int) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", ThemeBuilder.box("belt_socket", PackedInt32Array([4, 4, 4, 4])))
	panel.custom_minimum_size = Vector2(SOCKET, SOCKET)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stack := Control.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(stack)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(icon)
	var count := UiKit.label("", "Tiny", HORIZONTAL_ALIGNMENT_RIGHT)
	count.name = "Count"
	_outline(count)
	count.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	count.offset_left = -30.0
	count.offset_top = -13.0
	count.offset_right = 1.0
	count.offset_bottom = 3.0
	stack.add_child(count)
	stack.add_child(_key_tab(str(number), "Key"))
	return panel


## A key's brass tab, pinned over a socket's top left corner.
func _key_tab(text: String, label_name: String) -> Control:
	var tab := PanelContainer.new()
	tab.name = label_name + "Tab"
	tab.add_theme_stylebox_override("panel", ThemeBuilder.box("belt_key_tab", PackedInt32Array([3, 0, 3, 0])))
	tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tab.position = Vector2(-7.0, -8.0)
	var key := UiKit.label(text, "Tiny", HORIZONTAL_ALIGNMENT_CENTER)
	key.name = label_name
	key.add_theme_color_override("font_color", ThemeBuilder.colour("ink", "warm"))
	key.add_theme_font_size_override("font_size", 11)
	key.custom_minimum_size = Vector2(9, 0)
	tab.add_child(key)
	return tab


func _outline(l: Label) -> void:
	l.add_theme_color_override("font_color", ThemeBuilder.colour("paper", "warm"))
	l.add_theme_color_override("font_outline_color", Color(0.08, 0.06, 0.04, 0.95))
	l.add_theme_constant_override("outline_size", 4)


## The weapon in the hand, in a lit socket over the belt's left end, with the cycle key on its tab;
## and the notice that shows the whole set for a moment when the hand is cycled.
func _build_weapon_plate() -> void:
	_weapon_plate = PanelContainer.new()
	_weapon_plate.name = "WeaponPlate"
	_weapon_plate.add_theme_stylebox_override("panel", ThemeBuilder.box("belt_socket_lit", PackedInt32Array([5, 5, 5, 5])))
	_weapon_plate.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_weapon_plate.offset_left = -24.0 - BELT_WIDTH
	_weapon_plate.offset_right = -24.0 - BELT_WIDTH + WEAPON_SOCKET
	_weapon_plate.offset_bottom = _belt.offset_top - 6.0
	_weapon_plate.offset_top = _weapon_plate.offset_bottom - WEAPON_SOCKET
	_weapon_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_weapon_plate)
	var stack := Control.new()
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weapon_plate.add_child(stack)
	_weapon_art = TextureRect.new()
	_weapon_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_weapon_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_weapon_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weapon_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	stack.add_child(_weapon_art)
	stack.add_child(_key_tab("", "CycleKey"))
	_weapon_key = stack.find_child("CycleKey", true, false) as Label

	_cycle_notice = UiKit.panel("ChromePanel")
	_cycle_notice.name = "WeaponCycle"
	_cycle_notice.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_cycle_notice.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_cycle_notice.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_cycle_notice.offset_right = -24.0
	_cycle_notice.offset_bottom = _weapon_plate.offset_top - 50.0
	_cycle_notice.offset_left = _cycle_notice.offset_right - 10.0
	_cycle_notice.offset_top = _cycle_notice.offset_bottom - 10.0
	_cycle_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cycle_notice.visible = false
	add_child(_cycle_notice)
	var col := UiKit.column(4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cycle_notice.add_child(UiKit.margins(col, 10, 4, 10, 6))
	_cycle_name = UiKit.label("", "Body", HORIZONTAL_ALIGNMENT_RIGHT)
	col.add_child(_cycle_name)
	_cycle_row = UiKit.row(4)
	_cycle_row.alignment = BoxContainer.ALIGNMENT_END
	_cycle_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_cycle_row)


## The weapon set for a moment (CYCLE_NOTICE_S): the weapon now in the hand named and lit, the
## others beside it in their order, and the key that goes on round.
func show_weapon_cycle(item_id: String, weapons: Array) -> void:
	if _cycle_notice == null:
		return
	for c in _cycle_row.get_children():
		_cycle_row.remove_child(c)
		c.queue_free()
	for w in weapons:
		var id := str(w)
		var cell := PanelContainer.new()
		cell.add_theme_stylebox_override("panel", ThemeBuilder.box("belt_socket_lit" if id == item_id else "belt_socket",
				PackedInt32Array([4, 4, 4, 4])))
		cell.custom_minimum_size = Vector2(40, 40) if id == item_id else Vector2(34, 34)
		cell.size_flags_vertical = Control.SIZE_SHRINK_END
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.modulate = Color(1, 1, 1, 1.0 if id == item_id else 0.72)
		var art := TextureRect.new()
		art.texture = UiKit.item_picture(ContentDB.get_or_empty(id))
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(art)
		_cycle_row.add_child(cell)
	var def := ContentDB.get_or_empty(item_id)
	var name_text := str(def.get("name", item_id))
	if weapons.size() < 2:
		name_text += "  (no other weapon in the set)"
	_cycle_name.text = name_text
	_cycle_notice.visible = true
	_cycle_notice.reset_size()
	_cycle_notice.modulate.a = 1.0
	_cycle_left = CYCLE_NOTICE_S
	_idle = 0.0
	_refresh_weapon_plate()


func _update_cycle_notice(delta: float) -> void:
	if _cycle_notice == null or not _cycle_notice.visible:
		return
	_cycle_left -= delta
	_cycle_notice.modulate.a = clampf(_cycle_left / 0.4, 0.0, 1.0)
	if _cycle_left <= 0.0:
		_cycle_notice.visible = false


func _refresh_weapon_plate() -> void:
	if _weapon_plate == null:
		return
	var id := ""
	if _equipment and is_instance_valid(_equipment) and _equipment.has_method("item_id"):
		id = str(_equipment.call("item_id", "main_hand"))
	_weapon_plate.visible = not id.is_empty()
	_weapon_art.texture = UiKit.item_picture(ContentDB.get_or_empty(id)) if not id.is_empty() else null
	var many := false
	if _equipment and is_instance_valid(_equipment) and _equipment.has_method("weapon_round"):
		many = (_equipment.call("weapon_round") as Array).size() > 1
	_weapon_key.text = UI.prompt_for("cycle_weapon")
	(_weapon_key.get_parent() as Control).visible = many


# --- world hookup -----------------------------------------------------------------------------

func _connect_world() -> void:
	_player = get_tree().get_first_node_in_group("player")
	_equipment = get_tree().get_first_node_in_group("equipment")
	_quest_log = get_tree().get_first_node_in_group("quest_log")
	if _quest_log != null and _quest_log.has_signal("tracked_changed") \
			and not _quest_log.is_connected("tracked_changed", _on_tracked_changed):
		_quest_log.connect("tracked_changed", _on_tracked_changed)
	if _player and is_instance_valid(_player):
		if _player.has_signal("stats_changed") and not _player.is_connected("stats_changed", _refresh_stats):
			_player.connect("stats_changed", _refresh_stats)
		if _player.has_signal("lock_on_changed") and not _player.is_connected("lock_on_changed", _on_lock_on):
			_player.connect("lock_on_changed", _on_lock_on)
		if _player.has_signal("spell_readied") and not _player.is_connected("spell_readied", _on_spell_readied):
			_player.connect("spell_readied", _on_spell_readied)
		if _player.has_signal("weapon_cycled") and not _player.is_connected("weapon_cycled", show_weapon_cycle):
			_player.connect("weapon_cycled", show_weapon_cycle)
		var interactor := _find_interactor(_player)
		if interactor and not interactor.is_connected("prompt_changed", _on_prompt_changed):
			interactor.connect("prompt_changed", _on_prompt_changed)
		# A new body (a load, a respawn) brings a new Interactor: what the last one had up is not
		# on offer any more, and the new one says only what it finds (playtest 09-27, prompts
		# that stuck).
		var held: Variant = interactor.get("prompt") if interactor != null else null
		set_prompt(str(held) if held is String else "")
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
	_refresh_weapon_plate()
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
			# a slot with no key on this device (a pad has the D-pad's three) shows no tab
			(key.get_parent() as Control).visible = not key.text.is_empty()
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
			panel.modulate = Color(1, 1, 1, 0.62)
			continue
		panel.modulate = Color(1, 1, 1, 1.0)
		var def := ContentDB.get_or_empty(item_id)
		if icon:
			icon.texture = UiKit.item_picture(def)
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

## Asks the strip to choose again at the next frame (a place was found, the region changed).
func _rebuild_markers() -> void:
	_markers_from = Vector2.INF


## The places the strip shows from `origin`, chosen by CompassRules: within their kind's range when
## found, faintly within a shorter one when not, at most CompassRules.CAP of them. Quest areas are
## the smudges, and always show.
func _choose_markers(origin: Vector2) -> void:
	if _compass_places.is_empty():
		_compass_places = CompassRules.places_from_content()
	_markers_from = origin
	_markers_at_ms = Time.get_ticks_msec()
	_marker_cache.clear()
	for m in CompassRules.select(origin, _compass_places, GameState.is_discovered):
		var def := ContentDB.get_or_empty(str(m["id"]))
		_marker_cache.append({
			"xz": m["xz"],
			"texture": ThemeBuilder.marker(str(m["kind"])),
			"label": str(def.get("name", "")),
			"faint": not bool(m["found"]),
		})


## The ids on the strip now, nearest-and-biggest first: for the tests and the flow.
func compass_marker_labels() -> Array[String]:
	var out: Array[String] = []
	for m in _marker_cache:
		out.append(str(m["label"]) + (" (unfound)" if bool(m.get("faint", false)) else ""))
	return out


## Looks the tracked quest's objectives up again at the next frame (a stage moved, the journal
## chose another quest).
func _on_tracked_changed(_quest_id: String) -> void:
	_waymarks_at_ms = -1000000


func _on_quest_ended(quest_id: String, outcome: String) -> void:
	_waymarks_at_ms = -1000000
	if _notice_head == null or quest_id == "" or str(_quest_def(quest_id).get("layer", "")) == "radiant" and outcome == "failed":
		return
	var name_of := str(_quest_def(quest_id).get("name", ""))
	if name_of != "":
		show_quest_notice(quest_id, "Quest complete", name_of)


## Where the player is, for the waymarks: the body's feet, else the camera; INF with neither.
func _player_feet() -> Vector3:
	if _player and is_instance_valid(_player) and _player is Node3D and (_player as Node3D).is_inside_tree():
		return (_player as Node3D).global_position
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	return cam.global_position if cam != null else Vector3.INF


## The tracked quest's open objectives, where the world has them now, and the tracker's rows.
func _update_waymarks() -> void:
	if Time.get_ticks_msec() - _waymarks_at_ms < WAYMARKS_EVERY_MS:
		return
	_waymarks_at_ms = Time.get_ticks_msec()
	_waymarks.clear()
	if _quest_log == null or not is_instance_valid(_quest_log) or not _quest_log.has_method("tracked_objectives"):
		_quest_log = get_tree().get_first_node_in_group("quest_log")
		if _quest_log == null or not _quest_log.has_method("tracked_objectives"):
			_tracker.show_quest("", [])
			return
	var quest_id := str(_quest_log.call("tracked_quest"))
	var from := _player_feet()
	var inside := str(GameState.current_interior_id)
	var rows: Array[Dictionary] = []
	for o in _quest_log.call("tracked_objectives"):
		var obj: Dictionary = o
		if bool(obj.get("done", false)):
			continue
		var a: Dictionary = obj["anchor"]
		var at := Waymarks.locate(a, from, inside)
		var ok := bool(at.get("ok", false))
		var metres := Waymarks._flat(from, at["at"]) if ok and from != Vector3.INF else INF
		var radius := float(at.get("radius", 0.0)) if ok else 0.0
		var progress := ""
		if str(obj.get("type", "")) in ["kill", "collect", "use_item"]:
			progress = QuestTracker.progress_text(int(obj.get("count", 0)), int(obj.get("needed", 1)), str(a.get("about", "")))
		var key := "%s|%d|%d" % [quest_id, int(_quest_log.call("stage_of", quest_id)), int(obj.get("index", 0))]
		# two steps at one place ("Go to" and "Rest at" Pilgrim's Ash) say how far once, on the first
		var how_far := QuestTracker.distance_text(metres, radius)
		if ok:
			for w in _waymarks:
				if bool(w["ok"]) and Waymarks._flat(w["at"], at["at"]) < 2.0:
					how_far = ""
		var detail := QuestTracker.detail_text(progress, how_far)
		_waymarks.append({"key": key, "ok": ok, "at": at.get("at", Vector3.INF), "radius": radius,
				"text": str(obj.get("text", "")), "detail": detail, "optional": bool(obj.get("optional", false))})
		rows.append({"key": key, "text": str(obj.get("text", "")) + (" (if you like)" if bool(obj.get("optional", false)) else ""),
				"detail": detail})
	var title := str(ContentDB.get_or_empty(quest_id).get("name", "")) if quest_id != "" else ""
	if title == "" and quest_id != "" and _quest_log.has_method("definition"):
		title = str((_quest_log.call("definition", quest_id) as Dictionary).get("name", ""))
	_tracker.show_quest(title, rows, _row_was_done)


## Whether a tracker row's objective ("quest|stage|index") was done, for the tick as it goes.
func _row_was_done(key: String) -> bool:
	var parts := key.split("|")
	if parts.size() < 3 or _quest_log == null or not is_instance_valid(_quest_log) or not _quest_log.has_method("objective_done_in"):
		return true
	return bool(_quest_log.call("objective_done_in", parts[0], int(parts[1]), int(parts[2])))


## The strip's view of the waymarks from `origin`: a pin for each objective you are not yet within,
## a smudge over the area of each you are.
func _waymark_glyphs(origin: Vector2) -> Dictionary:
	var pins: Array[Dictionary] = []
	var areas: Array[Dictionary] = []
	for w in _waymarks:
		if not bool(w["ok"]):
			continue
		var at: Vector3 = w["at"]
		var to := Vector2(at.x, at.z)
		var dist := origin.distance_to(to)
		var bearing := Compass.bearing_deg(origin, to)
		if dist <= float(w["radius"]):
			areas.append({"bearing": bearing, "width_deg": 60.0 if dist < 1.0 else
					clampf(rad_to_deg(atan(float(w["radius"]) / dist)) * 2.0, 6.0, 60.0)})
		else:
			# two steps at one place (Wren and Merrowby) are one pin, not two stacked
			var same := false
			for p in pins:
				if absf(Compass.wrap_delta(float(p["bearing"]) - bearing)) < 1.5:
					same = true
			if not same:
				pins.append({"bearing": bearing, "distance": dist})
	return {"pins": pins, "areas": areas}


# --- per frame --------------------------------------------------------------------------------

## The breath gauge: shown while the player swims and has any breath to get back.
func _update_breath(delta: float) -> void:
	if _breath_bar == null:
		return
	var sw: Variant = _player.get("swimmer") if _player != null and is_instance_valid(_player) else null
	var swimmer := sw as Swimmer
	var swimming := swimmer != null and _player.has_method("is_swimming") and bool(_player.call("is_swimming"))
	if swimming and swimmer.breath < Swimmer.BREATH_S - 0.01:
		_breath_linger = BREATH_LINGER_S
	elif _breath_linger > 0.0:
		_breath_linger -= delta
	var up := swimming and _breath_linger > 0.0
	if up:
		_breath_bar.set_values(swimmer.breath, Swimmer.BREATH_S)
		come_up()
	_breath_bar.visible = up


func _process(delta: float) -> void:
	_wall.step()
	_idle += delta
	# a body put away and another stood up without a spawn (a bench, a test) is found again
	if Engine.get_process_frames() % 30 == 0 and (_player == null or not is_instance_valid(_player)
			or _player != get_tree().get_first_node_in_group("player")):
		_connect_world()
	_update_waymarks()
	_update_compass(delta)
	_update_reticle()
	_update_crosshair(delta)
	_update_sneak_eye(delta)
	_update_statuses(delta)
	_update_boss()
	_update_breath(delta)
	_update_idle_fade(delta)
	_update_held_card()
	_update_cycle_notice(delta)


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
	if _markers_from == Vector2.INF or origin.distance_to(_markers_from) > MARKERS_EVERY_M \
			or Time.get_ticks_msec() - _markers_at_ms > MARKERS_EVERY_MS:
		_choose_markers(origin)
	var markers: Array[Dictionary] = []
	for m in _marker_cache:
		var to: Vector2 = m["xz"]
		markers.append({"bearing": Compass.bearing_deg(origin, to), "texture": m["texture"],
				"label": m["label"], "distance": origin.distance_to(to), "faint": m["faint"]})
	_compass.markers = markers
	var glyphs := _waymark_glyphs(origin)
	var areas: Array[Dictionary] = []
	areas.assign(glyphs["areas"])
	var pins: Array[Dictionary] = []
	pins.assign(glyphs["pins"])
	_compass.areas = areas
	_compass.pins = pins
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


## The aim's mark (Crosshair) as the player's aim has it (Player.crosshair), through the view's own
## field of view; hidden without a player that aims, or with a menu over the world.
func _update_crosshair(delta: float) -> void:
	var state := {}
	var who: Node = _player if _player != null and is_instance_valid(_player) and not _player.is_queued_for_deletion() else null
	if who == null:
		# a player put in the place of one being freed: the group can still name the old one first
		for p in get_tree().get_nodes_in_group("player"):
			if not p.is_queued_for_deletion():
				who = p
				break
	if who != null and who.has_method("crosshair"):
		state = who.call("crosshair")
	var cam := get_viewport().get_camera_3d()
	_crosshair.show_state(state, cam.fov if cam != null else 70.0, delta)


## What the crosshair shows now: {visible, gap (px), on_target}, for tests.
func crosshair_shown() -> Dictionary:
	return {"visible": _crosshair.visible, "gap": _crosshair.gap, "on_target": _crosshair.on_target}


## The sneak read (DESIGN 5.13's detection state): while crouched, what the most watchful of those
## near has of you, in the detection meter's own thresholds (DetectionMeter). Stealth had every
## number and the player none: crouched in the dark and upright in plain sight looked the same from
## the inside, and a stealth start could not teach the one thing it is about.
const EYE_RANGE_M := 40.0
const EYE_EVERY_S := 0.15
const EYE_WORDS := {"unaware": "Unseen", "suspicious": "Noticed", "alert": "Seen", "detected": "Found"}
const EYE_TINTS := {"unaware": Color(0.72, 0.8, 0.74, 0.85), "suspicious": Color(0.95, 0.82, 0.45, 0.95),
		"alert": Color(0.98, 0.58, 0.32, 1.0), "detected": Color(0.95, 0.35, 0.28, 1.0)}


## The read for a detection level: unaware | suspicious | alert | detected.
static func eye_state(level: float) -> String:
	if level >= DetectionMeter.DETECTED:
		return "detected"
	if level >= DetectionMeter.WITNESS:
		return "alert"
	if level >= DetectionMeter.SUSPICIOUS:
		return "suspicious"
	return "unaware"


## The highest detection of the player among foes and people within EYE_RANGE_M of `at`.
static func watched_level(tree: SceneTree, at: Vector3) -> float:
	var most := 0.0
	for group: String in ["enemy", "npc"]:
		for n in tree.get_nodes_in_group(group):
			if not (n is Node3D) or not (n as Node3D).is_inside_tree():
				continue
			if (n as Node3D).global_position.distance_to(at) > EYE_RANGE_M:
				continue
			if n.has_method("is_alive") and not bool(n.call("is_alive")):
				continue
			if group == "npc" and not ("detection" in n):
				continue
			most = maxf(most, Stealth.awareness_of(n))
	return most


func _update_sneak_eye(delta: float) -> void:
	var crouched := _player != null and is_instance_valid(_player) and _player is Node3D and Stealth.is_crouched(_player)
	if not crouched:
		_eye.visible = false
		return
	_eye_left -= delta
	if _eye.visible and _eye_left > 0.0:
		return
	_eye_left = EYE_EVERY_S
	var state := eye_state(watched_level(get_tree(), (_player as Node3D).global_position))
	_eye.text = str(EYE_WORDS[state])
	_eye.modulate = EYE_TINTS[state]
	_eye.visible = true


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
	var busy := _lock_target != null or _boss_box.visible or _prompt.visible or _crosshair.visible
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


## Nothing in the world is offered from under a menu; the Interactor offers it again when the
## world runs again.
func _on_menu_opened(_menu_id: String) -> void:
	set_prompt("")


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
	# what the country is known for, the first time you come into it and not every crossing after
	var features := ""
	var seen := "region_card_seen/" + region_id
	if not bool(GameState.get_flag(seen, false)):
		features = known_for(def)
		GameState.set_flag(seen, true)
	show_region_card(str(def.get("name", "")), str(def.get("tagline", "")), features)
	_rebuild_markers()


## What a region is known for, from its identity's `unique_features`: "Known for the only apple
## trees in Wickmere, the Chalk Hound hill figure and the Wardens' Roll." Every region listed three
## and nothing read them. "" when it lists none.
static func known_for(def: Dictionary) -> String:
	var list: Array = (def.get("identity", {}) as Dictionary).get("unique_features", [])
	var items: Array[String] = []
	for f in list:
		if str(f).strip_edges() != "":
			items.append(str(f).strip_edges())
	if items.is_empty():
		return ""
	var joined := items[0]
	if items.size() > 1:
		joined = ", ".join(items.slice(0, items.size() - 1)) + " and " + items[-1]
	return "Known for %s." % joined


## The name of a place arrives in ink and then lets go of the screen, with what it is known for
## under it the first time.
func show_region_card(title: String, tagline: String, features := "") -> void:
	_note_cinematic()
	if _card_must_wait():
		# the latest crossing wins: it is where the player is when the card can be read
		_held_card = [title, tagline, features]
		return
	_held_card = []
	_region_name.text = title
	_region_tagline.text = tagline
	_region_features.text = features
	_region_features.visible = features != ""
	_region_card.modulate = Color(0.3, 0.24, 0.19, 0.0)
	# words to be read keep the wall clock (WallTweens)
	var tw := _wall.own(create_tween())
	tw.tween_property(_region_card, "modulate", Color(1, 1, 1, 1), 1.1).set_trans(Tween.TRANS_CUBIC)
	tw.tween_interval(REGION_CARD_SECONDS)
	tw.tween_property(_region_card, "modulate:a", 0.0, 1.4)


## Whether a region card held now would be shown over a cinematic or its hand-over.
func region_card_waiting() -> bool:
	return not _held_card.is_empty()


func _note_cinematic() -> void:
	for n in get_tree().get_nodes_in_group(CinematicPlayer.GROUP):
		if n.has_method("is_playing") and bool(n.call("is_playing")):
			_cinematic_seen_ms = Time.get_ticks_msec()
			return


func _card_must_wait() -> bool:
	if _cinematic_seen_ms < 0:
		return false
	return Time.get_ticks_msec() - _cinematic_seen_ms < int(region_card_settle_s * 1000.0)


## A card held back comes up once the hand-over has settled.
func _update_held_card() -> void:
	_note_cinematic()
	if not _held_card.is_empty() and not _card_must_wait():
		var c := _held_card
		_held_card = []
		show_region_card(str(c[0]), str(c[1]), str(c[2]))


## A quest started or moved on: its next thing to do goes under the compass for a few seconds, so
## the player learns it from the screen and not from the journal, and the smudge on the strip
## above it says which way. Nothing is shown for a stage with nothing left to do.
func _on_quest_moved(quest_id: String, stage: Variant = null) -> void:
	# the tracker's rows now, not at its next look
	_waymarks_at_ms = -1000000
	var line := objective_line(quest_id)
	if line.is_empty():
		return
	# the stage a quest starts at is the quest's news, not a new objective
	var started: Dictionary = _started_ms.get(quest_id, {})
	var is_new := not started.is_empty() and Time.get_ticks_msec() - int(started["ms"]) < 1500 \
			and (stage == null or int(stage) == int(started["stage"]))
	show_quest_notice(quest_id, "New quest" if is_new else "New objective", line, stage_reason(quest_id))
	var log_node := _quest_log if _quest_log != null and is_instance_valid(_quest_log) \
			else get_tree().get_first_node_in_group("quest_log")
	if _tracker != null and log_node != null and log_node.has_method("tracked_quest") \
			and str(log_node.call("tracked_quest")) == quest_id:
		_tracker.announce()


func _on_quest_started(quest_id: String) -> void:
	var log_node := _quest_log if _quest_log != null and is_instance_valid(_quest_log) \
			else get_tree().get_first_node_in_group("quest_log")
	var at := int(log_node.call("stage_of", quest_id)) if log_node != null and log_node.has_method("stage_of") else 0
	_started_ms[quest_id] = {"ms": Time.get_ticks_msec(), "stage": at}
	_on_quest_moved(quest_id)


## A label of the notice under the compass, `half` either side of the middle.
func _notice_label(variation: String, top: float, bottom: float, half: float) -> Label:
	var l := UiKit.label("", variation, HORIZONTAL_ALIGNMENT_CENTER)
	l.set_anchors_preset(Control.PRESET_CENTER_TOP)
	l.anchor_left = 0.5
	l.anchor_right = 0.5
	l.offset_left = -half
	l.offset_right = half
	l.offset_top = top
	l.offset_bottom = bottom
	l.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.7))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.modulate.a = 0.0
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


## Why the quest's current stage is asked of you: the first line of its journal (the stage's
## journal says, first, what has happened and why this is next), cut at a sentence when long.
func stage_reason(quest_id: String) -> String:
	var log_node := _quest_log if _quest_log != null and is_instance_valid(_quest_log) \
			else get_tree().get_first_node_in_group("quest_log")
	if log_node == null or not log_node.has_method("stage_def") or not log_node.has_method("journal_of"):
		return ""
	var stage: Dictionary = log_node.call("stage_def", quest_id, int(log_node.call("stage_of", quest_id)))
	return QuestCues.first_line(str(log_node.call("journal_of", stage)))


## The notice under the compass: a head ("NEW OBJECTIVE · SIDE QUEST", in the quest's colour),
## the objective line, and why.
func show_quest_notice(quest_id: String, head: String, line: String, why := "") -> void:
	var tier := QuestCues.tier_of(quest_id, _quest_def(quest_id))
	_notice_head.text = ("%s  ·  %s" % [head, QuestCues.tier_word(tier)]).to_upper()
	_notice_head.add_theme_color_override("font_color", QuestCues.tier_colour(tier))
	_notice_why.text = why
	show_objective(line, OBJECTIVE_SECONDS + (2.0 if why != "" else 0.0), true)


func _quest_def(quest_id: String) -> Dictionary:
	if _quest_log != null and is_instance_valid(_quest_log) and _quest_log.has_method("definition"):
		return _quest_log.call("definition", quest_id)
	return ContentDB.get_or_empty(quest_id)


## What the notice shows now, while it is up: {head, line, why}; {} when it is not.
func quest_notice_shown() -> Dictionary:
	var fading_in := _objective_tween != null and _objective_tween.is_valid() and _objective_tween.is_running()
	if _objective == null or _objective.text == "" or (_objective.modulate.a <= 0.05 and not fading_in):
		return {}
	return {"head": _notice_head.text, "line": _objective.text, "why": _notice_why.text}


## "The Naming: Speak to the Warden at her fire" -- the quest's name and its first objective not
## yet done, or "" when there is none.
func objective_line(quest_id: String) -> String:
	var log_node := _quest_log if _quest_log != null and is_instance_valid(_quest_log) \
			else get_tree().get_first_node_in_group("quest_log")
	if log_node == null or not log_node.has_method("objectives_of"):
		return ""
	for o in log_node.call("objectives_of", quest_id):
		var obj: Dictionary = o
		if bool(obj.get("done", false)) or bool(obj.get("optional", false)) or bool(obj.get("veiled", false)):
			continue
		var name_of := str(_quest_def(quest_id).get("name", ""))
		var text := str(obj.get("text", ""))
		return text if name_of.is_empty() else "%s: %s" % [name_of, text]
	return ""


func show_objective(text: String, seconds := OBJECTIVE_SECONDS, with_notice := false) -> void:
	_objective.text = text
	if not with_notice:
		_notice_head.text = ""
		_notice_why.text = ""
	if _objective_tween != null and _objective_tween.is_valid():
		_objective_tween.kill()
	for l: Label in [_objective, _notice_head, _notice_why]:
		l.modulate = Color(1, 1, 1, 0.0)
	_objective_tween = create_tween()
	_objective_tween.set_parallel(true)
	for l: Label in [_objective, _notice_head, _notice_why]:
		_objective_tween.tween_property(l, "modulate:a", 1.0, 0.5)
	_objective_tween.set_parallel(false)
	_objective_tween.tween_interval(seconds)
	_objective_tween.set_parallel(true)
	for l: Label in [_objective, _notice_head, _notice_why]:
		_objective_tween.tween_property(l, "modulate:a", 0.0, 1.2)
	# the whole HUD is woken, so the line is not read through the idle fade
	_idle = 0.0


## The objective line as it stands, and whether it is on the screen: for the tests and the probe.
func objective_shown() -> String:
	return _objective.text if _objective != null and _objective.modulate.a > 0.05 else ""


## Whether the tracked quest's pin, or its smudge once you are within its radius, is on the part of
## the strip the compass is showing now (not waiting at an end).
func quest_marker_on_strip() -> bool:
	if _compass == null or not _compass.visible:
		return false
	var glyphs := _waymark_glyphs(_compass.player_xz)
	for p in glyphs["pins"]:
		if Compass.on_strip(float(p["bearing"]), _compass.heading_deg, Compass.SPAN_DEG, 0.0):
			return true
	for a in glyphs["areas"]:
		if Compass.on_strip(float(a["bearing"]), _compass.heading_deg, Compass.SPAN_DEG, 24.0):
			return true
	return false


## The tracked objectives as the HUD has them now: [{text, detail, ok, xz, radius}], for the tests,
## the probe and the captures.
func tracked_waymarks() -> Array[Dictionary]:
	_waymarks_at_ms = -1000000
	_update_waymarks()
	var out: Array[Dictionary] = []
	for w in _waymarks:
		var at: Vector3 = w["at"]
		out.append({"text": w["text"], "detail": w["detail"], "ok": w["ok"], "radius": w["radius"],
				"xz": Vector2(at.x, at.z) if bool(w["ok"]) else Vector2.INF})
	return out


## The tracker as it is drawn: {title, rows: [{text, detail, done}]}.
func tracker_shown() -> Dictionary:
	return {"title": _tracker.shown_title(), "rows": _tracker.shown_rows()}


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


func _on_boss_defeated(_defeated_id: String) -> void:
	_boss_node = null
	# the fight is over: this cleared the parameter, which shadowed the member, so the next foe
	# struck after a boss fell was taken for the boss (_on_damage_dealt)
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
