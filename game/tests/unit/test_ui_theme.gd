extends TestCase
## The theme has to load, its fonts have to resolve, and every texture the manifest promises
## has to be on disk — otherwise a screen silently falls back to Godot's default grey.


func test_manifest_matches_the_textures_on_disk() -> void:
	var manifest := ThemeBuilder.manifest()
	assert_false(manifest.is_empty(), "ui_textures.json should load")
	var textures: Dictionary = manifest.get("textures", {})
	assert_gt(textures.size(), 80, "expected the full UI texture set")
	var missing: Array[String] = []
	for name: String in textures:
		var path: String = ThemeBuilder.UI_DIR + str(textures[name]["file"])
		if not ResourceLoader.exists(path):
			missing.append(path)
	assert_empty(missing, "textures named in the manifest are missing")


func test_icons_and_markers_resolve() -> void:
	var icons: Array = ThemeBuilder.manifest().get("icons", [])
	assert_eq(icons.size(), 32, "DESIGN asks for 32 drawn icons")
	for name in icons:
		assert_true(ThemeBuilder.icon(str(name)) is Texture2D, "icon %s should load" % name)
	for kind in ["town", "village", "fort", "deep_place", "landmark", "shrine", "quest_area",
			"bridge", "tower", "camp", "waterfall", "standing_stones", "giant_bones",
			"strange_tree", "wreck", "ruins", "hidden_valley", "edge", "strange", "player"]:
		assert_true(ThemeBuilder.marker(kind) is Texture2D, "marker %s should load" % kind)
	# an unknown kind still gives something to draw
	assert_true(ThemeBuilder.marker("core:place/nonsense") is Texture2D)


func test_every_place_and_poi_kind_has_a_marker() -> void:
	var markers: Array = ThemeBuilder.manifest().get("markers", [])
	var kinds := {}
	for type in ["place", "poi"]:
		for def in ContentDB.all(type):
			kinds[str(def.get("kind", ""))] = true
	var missing: Array[String] = []
	for kind: String in kinds:
		if not markers.has(kind):
			missing.append(kind)
	assert_empty(missing, "every place and POI kind in the pack needs a drawn marker")


func test_saved_themes_load_with_their_fonts() -> void:
	for variant: String in ["warm", "deep"]:
		var path: String = UI.THEME_PATHS[variant]
		assert_true(ResourceLoader.exists(path), "%s should be committed" % path)
		var theme: Theme = load(path)
		assert_true(theme is Theme, "%s should be a Theme" % path)
		assert_true(theme.default_font is Font, "the theme needs a body font")
		assert_gt(theme.default_font_size, 10)
		for variation in ["DisplayTitle", "Title", "Heading", "Body", "Small", "Journal"]:
			assert_true(theme.has_font("font", variation), "%s lacks font for %s" % [variant, variation])
			var font: Font = theme.get_font("font", variation)
			assert_true(font is Font, "%s font for %s should resolve" % [variant, variation])
			assert_gt(font.get_height(theme.get_font_size("font_size", variation)), 6.0)
		for type in ["Button", "PanelContainer", "TabContainer", "LineEdit", "ProgressBar"]:
			assert_true(theme.has_stylebox("panel", type) or theme.has_stylebox("normal", type)
					or theme.has_stylebox("background", type), "%s has no stylebox for %s" % [variant, type])


func test_theme_styleboxes_carry_their_nine_patch_margins() -> void:
	var box := ThemeBuilder.box("panel_brass")
	assert_true(box is StyleBoxTexture)
	assert_gt(box.get_texture_margin(SIDE_LEFT), 0.0, "the brass panel should be a nine-patch")
	assert_eq(box.get_texture_margin(SIDE_LEFT), box.get_texture_margin(SIDE_RIGHT))


func test_colours_differ_between_the_two_variants() -> void:
	var warm := ThemeBuilder.colour("metal", "warm")
	var deep := ThemeBuilder.colour("metal", "deep")
	assert_ne(warm, deep, "cold bronze should not be brass")
	assert_gt(warm.r + warm.g, deep.r + deep.g, "brass is warmer than cold bronze")
	for kind in ["health", "stamina", "mana", "poise", "boss"]:
		assert_true(ThemeBuilder.fill(kind) is Texture2D, "bar fill %s should load" % kind)


func test_ui_autoload_is_wired() -> void:
	assert_true(UI.hud_layer is CanvasLayer)
	assert_true(UI.menu_layer.layer > UI.hud_layer.layer)
	assert_true(UI.toast_layer.layer > UI.menu_layer.layer)
	assert_true(UI.fade_layer.layer > UI.toast_layer.layer)
	assert_true(UI.fade_layer.layer < 100, "the debug console sits at 100 and must stay on top")
	for menu_id: String in UI.MENUS:
		var path: String = UI.MENUS[menu_id]["scene"]
		assert_true(ResourceLoader.exists(path), "menu '%s' scene missing: %s" % [menu_id, path])
	assert_false(UI.is_menu_open())


## TestCase is a RefCounted, so the tree comes from the main loop.
func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func test_opening_a_screen_pauses_the_world_and_closing_lets_go() -> void:
	var opened: Array[String] = []
	var closed: Array[String] = []
	var on_open := func(id: String) -> void: opened.append(id)
	var on_close := func(id: String) -> void: closed.append(id)
	EventBus.menu_opened.connect(on_open)
	EventBus.menu_closed.connect(on_close)

	assert_false(UI.is_menu_open(), "nothing should be open to begin with")
	var screen := UI.open("journal")
	assert_true(screen != null, "the journal should open")
	assert_true(UI.is_menu_open(), "the stack should know it is open")
	assert_true(UI.is_menu_open("journal"))
	assert_eq(UI.top_menu(), "journal")
	assert_true(_tree().paused, "a full-screen screen pauses the world")
	assert_eq(opened, ["journal"] as Array[String])

	# a second screen stacks on top and the first is still open underneath
	UI.open("skills")
	assert_eq(UI.top_menu(), "skills")
	assert_true(UI.is_menu_open("journal"))
	UI.close()
	assert_eq(UI.top_menu(), "journal")
	assert_true(_tree().paused, "still paused while one remains")

	UI.close()
	assert_false(UI.is_menu_open())
	assert_false(_tree().paused, "closing the last screen lets the world run")
	assert_eq(closed, ["skills", "journal"] as Array[String])

	# opening the same screen twice gives back the same one rather than stacking it
	var first := UI.open("journal")
	var second := UI.open("journal")
	assert_eq(first, second)
	UI.close_all()
	assert_false(UI.is_menu_open())
	assert_false(_tree().paused)

	EventBus.menu_opened.disconnect(on_open)
	EventBus.menu_closed.disconnect(on_close)


func test_a_book_opens_the_reader_through_the_event_bus() -> void:
	var books := ContentDB.ids_of("book")
	assert_gt(books.size(), 0, "the pack should have books")
	EventBus.book_opened.emit(books[0])
	assert_true(UI.is_menu_open("book"), "EventBus.book_opened should open the reader")
	assert_true(GameState.read_books.has(books[0]), "opening a book marks it read")
	UI.close_all()
	assert_false(_tree().paused)


func test_the_theme_variant_follows_the_danger_of_the_region() -> void:
	var before := GameState.current_region_id
	GameState.enter_region("core:region/hearthvale")
	assert_eq(UI.theme_variant, "warm", "a settled region keeps brass and oak")
	GameState.enter_region("core:region/cinderlea")
	assert_eq(UI.theme_variant, "deep", "danger 5 swaps to cold bronze and ash")
	GameState.enter_region("core:region/hearthvale")
	assert_eq(UI.theme_variant, "warm")
	GameState.current_region_id = before
