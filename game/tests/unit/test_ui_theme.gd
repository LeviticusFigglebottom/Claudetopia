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
