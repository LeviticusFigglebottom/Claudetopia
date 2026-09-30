class_name ThemeBuilder
extends RefCounted
## Builds the Wickmere Theme from the textures written by tools/ui/gen_ui_textures.py.
##
## Nothing here hard-codes a pixel margin or a colour: everything comes from
## res://assets/ui/ui_textures.json, so regenerating the art updates the theme.
## Two variants exist: "warm" (parchment, brass, dark oak) and "deep" (ashen paper,
## cold bronze, ash), swapped by the UI autoload in deep places and dangerous regions.
##
## The saved themes at res://ui/theme/wickmere_theme.tres and wickmere_theme_deep.tres
## are produced by tools_gd/build_theme.tscn; UI falls back to building at runtime.

const UI_DIR := "res://assets/ui/"
const MANIFEST_PATH := UI_DIR + "ui_textures.json"
const FONT_DISPLAY := "res://assets/fonts/Cinzel-Variable.ttf"
const FONT_BODY := "res://assets/fonts/Spectral-Regular.ttf"
const FONT_ITALIC := "res://assets/fonts/Spectral-Italic.ttf"
const FONT_SEMIBOLD := "res://assets/fonts/Spectral-SemiBold.ttf"

## Type sizes, authored against the 1280x720 base viewport.
const SIZES := {"display": 52, "title": 34, "heading": 23, "body": 17, "small": 13, "tiny": 11}

static var _manifest: Dictionary = {}


static func manifest() -> Dictionary:
	if _manifest.is_empty():
		var text := FileAccess.get_file_as_string(MANIFEST_PATH)
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) == TYPE_DICTIONARY:
			_manifest = parsed
		else:
			push_error("ThemeBuilder: cannot read %s" % MANIFEST_PATH)
			_manifest = {"textures": {}, "variants": {}, "palette": {}}
	return _manifest


static func variants() -> Array:
	return manifest().get("variants", {}).keys()


# --- colours -----------------------------------------------------------------------------

static func colour(key: String, variant := "warm", alpha := 1.0) -> Color:
	var pal: Dictionary = manifest().get("palette", {}).get(variant, {})
	var rgb: Array = pal.get(key, [200, 190, 170])
	return Color8(int(rgb[0]), int(rgb[1]), int(rgb[2]), int(round(alpha * 255.0)))


static func bar_colour(kind: String, bright := true) -> Color:
	var pair: Array = manifest().get("bar_colours", {}).get(kind, [[200, 200, 200], [120, 120, 120]])
	var rgb: Array = pair[0] if bright else pair[1]
	return Color8(int(rgb[0]), int(rgb[1]), int(rgb[2]))


# --- textures ----------------------------------------------------------------------------

static func texture(name: String) -> Texture2D:
	var entry: Dictionary = manifest().get("textures", {}).get(name, {})
	if entry.is_empty():
		return null
	var path: String = UI_DIR + str(entry["file"])
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


static func icon(name: String) -> Texture2D:
	return texture(name) if manifest().get("icons", []).has(name) else null


## An item's painted picture (tools/ui/gen_item_art.py: the belt's and the weapon set's), by the
## name UiKit.item_art_name gives it; null when there is none.
static func item_art(name: String) -> Texture2D:
	return texture("item_" + name) if manifest().get("item_art", []).has(name) else null


static func marker(kind: String) -> Texture2D:
	var markers: Array = manifest().get("markers", [])
	return texture(kind if markers.has(kind) else "default")


static func fill(kind: String) -> Texture2D:
	return texture(str(manifest().get("fills", {}).get(kind, "")))


static func variant_texture(variant: String, path: Array) -> Texture2D:
	var node: Variant = manifest().get("variants", {}).get(variant, {})
	for step in path:
		if typeof(node) != TYPE_DICTIONARY or not node.has(step):
			return null
		node = node[step]
	return texture(str(node))


# --- styleboxes --------------------------------------------------------------------------

## A nine-patch StyleBoxTexture built from a texture named in the manifest.
static func box(name: String, content := PackedInt32Array()) -> StyleBoxTexture:
	var entry: Dictionary = manifest().get("textures", {}).get(name, {})
	var sb := StyleBoxTexture.new()
	var tex := texture(name)
	if tex == null:
		return sb
	sb.texture = tex
	var m: Array = entry.get("margin", [0, 0, 0, 0])
	sb.set_texture_margin(SIDE_LEFT, float(m[0]))
	sb.set_texture_margin(SIDE_TOP, float(m[1]))
	sb.set_texture_margin(SIDE_RIGHT, float(m[2]))
	sb.set_texture_margin(SIDE_BOTTOM, float(m[3]))
	# Nine-patch centres are stretched, not tiled: a tiled centre shows its seams on paper.
	if content.size() == 4:
		sb.set_content_margin(SIDE_LEFT, float(content[0]))
		sb.set_content_margin(SIDE_TOP, float(content[1]))
		sb.set_content_margin(SIDE_RIGHT, float(content[2]))
		sb.set_content_margin(SIDE_BOTTOM, float(content[3]))
	return sb


static func variant_box(variant: String, path: Array, content := PackedInt32Array()) -> StyleBoxTexture:
	var node: Variant = manifest().get("variants", {}).get(variant, {})
	for step in path:
		if typeof(node) != TYPE_DICTIONARY or not node.has(step):
			return StyleBoxTexture.new()
		node = node[step]
	return box(str(node), content)


static func empty(margins := PackedInt32Array([0, 0, 0, 0])) -> StyleBoxEmpty:
	var sb := StyleBoxEmpty.new()
	sb.set_content_margin(SIDE_LEFT, float(margins[0]))
	sb.set_content_margin(SIDE_TOP, float(margins[1]))
	sb.set_content_margin(SIDE_RIGHT, float(margins[2]))
	sb.set_content_margin(SIDE_BOTTOM, float(margins[3]))
	return sb


static func flat(col: Color, radius := 0.0, margins := PackedInt32Array([0, 0, 0, 0])) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.corner_radius_top_left = int(radius)
	sb.corner_radius_top_right = int(radius)
	sb.corner_radius_bottom_left = int(radius)
	sb.corner_radius_bottom_right = int(radius)
	if margins.size() == 4:
		sb.set_content_margin(SIDE_LEFT, float(margins[0]))
		sb.set_content_margin(SIDE_TOP, float(margins[1]))
		sb.set_content_margin(SIDE_RIGHT, float(margins[2]))
		sb.set_content_margin(SIDE_BOTTOM, float(margins[3]))
	return sb


# --- fonts -------------------------------------------------------------------------------

static func display_font(weight := 620, spacing := 2) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = load(FONT_DISPLAY)
	fv.variation_opentype = {"wght": weight}
	fv.spacing_glyph = spacing
	return fv


static func body_font(path := FONT_BODY) -> FontFile:
	return load(path)


# --- the theme ---------------------------------------------------------------------------

static func build(variant := "warm") -> Theme:
	var t := Theme.new()
	var ink := colour("ink", variant)
	var ink_soft := colour("ink_soft", variant)
	var paper := colour("paper_hi", variant)
	var paper_lo := colour("paper_lo", variant)
	var metal := colour("metal", variant)
	var metal_hi := colour("metal_hi", variant)
	var accent := colour("accent", variant)
	var edge := colour("paper_edge", variant)

	var display := display_font()
	var display_light := display_font(500, 3)
	var body := body_font()
	var italic := body_font(FONT_ITALIC)
	var semibold := body_font(FONT_SEMIBOLD)

	t.default_font = body
	t.default_font_size = SIZES.body

	# -- Label and its variations ---------------------------------------------------------
	t.set_font("font", "Label", body)
	t.set_font_size("font_size", "Label", SIZES.body)
	t.set_color("font_color", "Label", ink)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.0))
	t.set_constant("line_spacing", "Label", 3)
	t.set_stylebox("normal", "Label", empty())

	_label_variation(t, "DisplayTitle", display, SIZES.display, ink, 2)
	_label_variation(t, "Title", display, SIZES.title, ink, 2)
	_label_variation(t, "Heading", display_light, SIZES.heading, ink, 1)
	_label_variation(t, "Body", body, SIZES.body, ink, 3)
	_label_variation(t, "Small", body, SIZES.small, ink_soft, 2)
	_label_variation(t, "Tiny", body, SIZES.tiny, ink_soft, 1)
	_label_variation(t, "Journal", italic, SIZES.body, ink_soft, 5)
	_label_variation(t, "Emphasis", semibold, SIZES.body, ink, 3)
	_label_variation(t, "Metal", display_light, SIZES.small, metal, 1)

	# -- Button ---------------------------------------------------------------------------
	var pad := PackedInt32Array([22, 12, 22, 12])
	t.set_stylebox("normal", "Button", variant_box(variant, ["button", "normal"], pad))
	t.set_stylebox("hover", "Button", variant_box(variant, ["button", "hover"], pad))
	t.set_stylebox("pressed", "Button", variant_box(variant, ["button", "pressed"], pad))
	t.set_stylebox("disabled", "Button", variant_box(variant, ["button", "disabled"], pad))
	t.set_stylebox("focus", "Button", variant_box(variant, ["focus"], pad))
	t.set_font("font", "Button", display_light)
	t.set_font_size("font_size", "Button", SIZES.heading - 3)
	t.set_color("font_color", "Button", ink)
	t.set_color("font_hover_color", "Button", accent)
	t.set_color("font_pressed_color", "Button", ink)
	t.set_color("font_focus_color", "Button", ink)
	t.set_color("font_disabled_color", "Button", Color(ink_soft, 0.5))
	t.set_constant("h_separation", "Button", 8)
	t.set_constant("icon_max_width", "Button", 28)

	# A quieter button for lists, rows and tabs of text.
	t.set_type_variation("FlatButton", "Button")
	t.set_stylebox("normal", "FlatButton", empty(PackedInt32Array([10, 6, 10, 6])))
	t.set_stylebox("hover", "FlatButton", flat(Color(metal.r, metal.g, metal.b, 0.16), 2, PackedInt32Array([10, 6, 10, 6])))
	t.set_stylebox("pressed", "FlatButton", flat(Color(metal.r, metal.g, metal.b, 0.26), 2, PackedInt32Array([10, 6, 10, 6])))
	t.set_stylebox("disabled", "FlatButton", empty(PackedInt32Array([10, 6, 10, 6])))
	t.set_stylebox("focus", "FlatButton", variant_box(variant, ["focus"], PackedInt32Array([10, 6, 10, 6])))
	t.set_font("font", "FlatButton", body)
	t.set_font_size("font_size", "FlatButton", SIZES.body)
	t.set_color("font_color", "FlatButton", ink)
	t.set_color("font_hover_color", "FlatButton", accent)
	t.set_color("font_pressed_color", "FlatButton", ink)
	t.set_color("font_disabled_color", "FlatButton", Color(ink_soft, 0.45))

	# The main menu title words: no plate at all, just type that warms on hover.
	t.set_type_variation("TitleButton", "Button")
	t.set_stylebox("normal", "TitleButton", empty(PackedInt32Array([8, 4, 8, 4])))
	t.set_stylebox("hover", "TitleButton", empty(PackedInt32Array([8, 4, 8, 4])))
	t.set_stylebox("pressed", "TitleButton", empty(PackedInt32Array([8, 4, 8, 4])))
	t.set_stylebox("disabled", "TitleButton", empty(PackedInt32Array([8, 4, 8, 4])))
	t.set_stylebox("focus", "TitleButton", empty(PackedInt32Array([8, 4, 8, 4])))
	t.set_font("font", "TitleButton", display)
	t.set_font_size("font_size", "TitleButton", SIZES.title - 4)
	t.set_color("font_color", "TitleButton", ink)
	t.set_color("font_hover_color", "TitleButton", accent)
	t.set_color("font_pressed_color", "TitleButton", accent)
	t.set_color("font_focus_color", "TitleButton", accent)
	t.set_color("font_disabled_color", "TitleButton", Color(ink_soft, 0.4))

	# -- CheckBox / CheckButton / OptionButton --------------------------------------------
	for type in ["CheckBox", "CheckButton"]:
		t.set_stylebox("normal", type, empty(PackedInt32Array([6, 6, 6, 6])))
		t.set_stylebox("hover", type, empty(PackedInt32Array([6, 6, 6, 6])))
		t.set_stylebox("pressed", type, empty(PackedInt32Array([6, 6, 6, 6])))
		t.set_stylebox("disabled", type, empty(PackedInt32Array([6, 6, 6, 6])))
		t.set_stylebox("focus", type, variant_box(variant, ["focus"], PackedInt32Array([6, 6, 6, 6])))
		t.set_font("font", type, body)
		t.set_font_size("font_size", type, SIZES.body)
		t.set_color("font_color", type, ink)
		t.set_color("font_hover_color", type, accent)
		t.set_color("font_pressed_color", type, ink)
		t.set_color("font_disabled_color", type, Color(ink_soft, 0.45))
		t.set_constant("h_separation", type, 10)
		t.set_icon("checked", type, variant_texture(variant, ["check", "on"]))
		t.set_icon("unchecked", type, variant_texture(variant, ["check", "off"]))
		t.set_icon("radio_checked", type, variant_texture(variant, ["radio", "on"]))
		t.set_icon("radio_unchecked", type, variant_texture(variant, ["radio", "off"]))
		t.set_icon("checked_disabled", type, variant_texture(variant, ["check", "on"]))
		t.set_icon("unchecked_disabled", type, variant_texture(variant, ["check", "off"]))

	t.set_stylebox("normal", "OptionButton", variant_box(variant, ["button", "normal"], PackedInt32Array([16, 8, 34, 8])))
	t.set_stylebox("hover", "OptionButton", variant_box(variant, ["button", "hover"], PackedInt32Array([16, 8, 34, 8])))
	t.set_stylebox("pressed", "OptionButton", variant_box(variant, ["button", "pressed"], PackedInt32Array([16, 8, 34, 8])))
	t.set_stylebox("disabled", "OptionButton", variant_box(variant, ["button", "disabled"], PackedInt32Array([16, 8, 34, 8])))
	t.set_stylebox("focus", "OptionButton", variant_box(variant, ["focus"], PackedInt32Array([16, 8, 34, 8])))
	t.set_font("font", "OptionButton", body)
	t.set_font_size("font_size", "OptionButton", SIZES.body)
	t.set_color("font_color", "OptionButton", ink)
	t.set_color("font_hover_color", "OptionButton", accent)
	t.set_color("font_pressed_color", "OptionButton", ink)
	t.set_color("font_disabled_color", "OptionButton", Color(ink_soft, 0.45))

	# -- sliders --------------------------------------------------------------------------
	for type in ["HSlider", "VSlider"]:
		t.set_stylebox("slider", type, variant_box(variant, ["slider", "track"]))
		t.set_stylebox("grabber_area", type, flat(Color(metal.r, metal.g, metal.b, 0.75), 3))
		t.set_stylebox("grabber_area_highlight", type, flat(Color(metal_hi.r, metal_hi.g, metal_hi.b, 0.85), 3))
		t.set_icon("grabber", type, variant_texture(variant, ["slider", "grabber"]))
		t.set_icon("grabber_highlight", type, variant_texture(variant, ["slider", "grabber"]))
		t.set_icon("grabber_disabled", type, variant_texture(variant, ["slider", "grabber"]))
		t.set_constant("center_grabber", type, 1)
		t.set_constant("grabber_offset", type, 0)

	# -- progress bars --------------------------------------------------------------------
	t.set_stylebox("background", "ProgressBar", variant_box(variant, ["bar_track"]))
	t.set_stylebox("fill", "ProgressBar", box("fill_health"))
	t.set_font("font", "ProgressBar", body)
	t.set_font_size("font_size", "ProgressBar", SIZES.small)
	t.set_color("font_color", "ProgressBar", paper)

	# -- panels ---------------------------------------------------------------------------
	var panel_pad := PackedInt32Array([28, 26, 28, 26])
	t.set_stylebox("panel", "PanelContainer", variant_box(variant, ["panel"], panel_pad))
	t.set_stylebox("panel", "Panel", variant_box(variant, ["panel"]))
	t.set_type_variation("FramedPanel", "PanelContainer")
	t.set_stylebox("panel", "FramedPanel", variant_box(variant, ["panel_metal"], PackedInt32Array([32, 30, 32, 30])))
	t.set_type_variation("OakPanel", "PanelContainer")
	t.set_stylebox("panel", "OakPanel", variant_box(variant, ["panel_wood"], PackedInt32Array([32, 30, 32, 30])))
	# light chrome for HUD-sized boxes: quick slots, prompts, toasts
	t.set_type_variation("ChromePanel", "PanelContainer")
	t.set_stylebox("panel", "ChromePanel", variant_box(variant, ["panel_small"], PackedInt32Array([12, 10, 12, 10])))
	t.set_type_variation("ChromeWoodPanel", "PanelContainer")
	t.set_stylebox("panel", "ChromeWoodPanel", variant_box(variant, ["panel_small_wood"], PackedInt32Array([12, 10, 12, 10])))
	t.set_type_variation("PlainPanel", "PanelContainer")
	t.set_stylebox("panel", "PlainPanel", empty())
	t.set_type_variation("SheetPanel", "PanelContainer")
	var sheet := StyleBoxTexture.new()
	sheet.texture = variant_texture(variant, ["sheet"])
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		sheet.set_content_margin(side, 24.0)
	t.set_stylebox("panel", "SheetPanel", sheet)

	# -- tabs -----------------------------------------------------------------------------
	t.set_stylebox("panel", "TabContainer", variant_box(variant, ["panel"], PackedInt32Array([20, 18, 20, 18])))
	t.set_stylebox("tab_selected", "TabContainer", variant_box(variant, ["tab", "active"], PackedInt32Array([20, 8, 20, 8])))
	t.set_stylebox("tab_unselected", "TabContainer", variant_box(variant, ["tab", "inactive"], PackedInt32Array([20, 8, 20, 8])))
	t.set_stylebox("tab_hovered", "TabContainer", variant_box(variant, ["tab", "active"], PackedInt32Array([20, 8, 20, 8])))
	t.set_stylebox("tab_focus", "TabContainer", variant_box(variant, ["focus"]))
	t.set_stylebox("tabbar_background", "TabContainer", empty())
	t.set_font("font", "TabContainer", display_light)
	t.set_font_size("font_size", "TabContainer", SIZES.heading - 4)
	t.set_color("font_selected_color", "TabContainer", ink)
	t.set_color("font_unselected_color", "TabContainer", Color(ink_soft, 0.75))
	t.set_color("font_hovered_color", "TabContainer", accent)
	t.set_constant("side_margin", "TabContainer", 12)
	t.set_stylebox("tab_selected", "TabBar", variant_box(variant, ["tab", "active"], PackedInt32Array([20, 8, 20, 8])))
	t.set_stylebox("tab_unselected", "TabBar", variant_box(variant, ["tab", "inactive"], PackedInt32Array([20, 8, 20, 8])))
	t.set_stylebox("tab_hovered", "TabBar", variant_box(variant, ["tab", "active"], PackedInt32Array([20, 8, 20, 8])))
	t.set_stylebox("tab_focus", "TabBar", variant_box(variant, ["focus"]))
	t.set_font("font", "TabBar", display_light)
	t.set_font_size("font_size", "TabBar", SIZES.heading - 4)
	t.set_color("font_selected_color", "TabBar", ink)
	t.set_color("font_unselected_color", "TabBar", Color(ink_soft, 0.75))
	t.set_color("font_hovered_color", "TabBar", accent)

	# -- text entry -----------------------------------------------------------------------
	for type in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", type, variant_box(variant, ["button", "pressed"], PackedInt32Array([12, 8, 12, 8])))
		t.set_stylebox("focus", type, variant_box(variant, ["focus"], PackedInt32Array([12, 8, 12, 8])))
		t.set_stylebox("read_only", type, variant_box(variant, ["button", "disabled"], PackedInt32Array([12, 8, 12, 8])))
		t.set_font("font", type, body)
		t.set_font_size("font_size", type, SIZES.body)
		t.set_color("font_color", type, ink)
		t.set_color("font_placeholder_color", type, Color(ink_soft, 0.55))
		t.set_color("font_selected_color", type, paper)
		t.set_color("caret_color", type, accent)
		t.set_color("selection_color", type, Color(metal.r, metal.g, metal.b, 0.45))

	# -- scrollbars -----------------------------------------------------------------------
	for type in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", type, variant_box(variant, ["scroll", "track"]))
		t.set_stylebox("scroll_focus", type, variant_box(variant, ["scroll", "track"]))
		t.set_stylebox("grabber", type, variant_box(variant, ["scroll", "grabber"]))
		t.set_stylebox("grabber_highlight", type, variant_box(variant, ["scroll", "grabber"]))
		t.set_stylebox("grabber_pressed", type, variant_box(variant, ["scroll", "grabber"]))
	t.set_stylebox("panel", "ScrollContainer", empty())
	t.set_stylebox("focus", "ScrollContainer", empty())

	# -- lists ----------------------------------------------------------------------------
	t.set_stylebox("panel", "ItemList", empty(PackedInt32Array([4, 4, 4, 4])))
	t.set_stylebox("focus", "ItemList", variant_box(variant, ["focus"]))
	t.set_stylebox("selected", "ItemList", flat(Color(metal.r, metal.g, metal.b, 0.22), 2))
	t.set_stylebox("selected_focus", "ItemList", flat(Color(metal.r, metal.g, metal.b, 0.32), 2))
	t.set_stylebox("hovered", "ItemList", flat(Color(metal.r, metal.g, metal.b, 0.12), 2))
	t.set_stylebox("cursor", "ItemList", variant_box(variant, ["focus"]))
	t.set_stylebox("cursor_unfocused", "ItemList", empty())
	t.set_font("font", "ItemList", body)
	t.set_font_size("font_size", "ItemList", SIZES.body)
	t.set_color("font_color", "ItemList", ink)
	t.set_color("font_selected_color", "ItemList", ink)
	t.set_constant("v_separation", "ItemList", 6)
	t.set_constant("h_separation", "ItemList", 8)
	t.set_constant("icon_margin", "ItemList", 8)

	t.set_stylebox("panel", "Tree", empty(PackedInt32Array([4, 4, 4, 4])))
	t.set_stylebox("focus", "Tree", variant_box(variant, ["focus"]))
	t.set_stylebox("selected", "Tree", flat(Color(metal.r, metal.g, metal.b, 0.22), 2))
	t.set_stylebox("selected_focus", "Tree", flat(Color(metal.r, metal.g, metal.b, 0.32), 2))
	t.set_font("font", "Tree", body)
	t.set_font_size("font_size", "Tree", SIZES.body)
	t.set_color("font_color", "Tree", ink)
	t.set_color("font_selected_color", "Tree", ink)

	# -- popups and tooltips --------------------------------------------------------------
	t.set_stylebox("panel", "PopupMenu", variant_box(variant, ["panel_metal"], PackedInt32Array([20, 16, 20, 16])))
	t.set_stylebox("hover", "PopupMenu", flat(Color(metal.r, metal.g, metal.b, 0.24), 2))
	t.set_stylebox("separator", "PopupMenu", flat(Color(ink_soft.r, ink_soft.g, ink_soft.b, 0.35)))
	t.set_font("font", "PopupMenu", body)
	t.set_font_size("font_size", "PopupMenu", SIZES.body)
	t.set_color("font_color", "PopupMenu", ink)
	t.set_color("font_hover_color", "PopupMenu", accent)
	t.set_icon("checked", "PopupMenu", variant_texture(variant, ["check", "on"]))
	t.set_icon("unchecked", "PopupMenu", variant_texture(variant, ["check", "off"]))
	t.set_icon("radio_checked", "PopupMenu", variant_texture(variant, ["radio", "on"]))
	t.set_icon("radio_unchecked", "PopupMenu", variant_texture(variant, ["radio", "off"]))

	t.set_stylebox("panel", "PopupPanel", variant_box(variant, ["panel_metal"], PackedInt32Array([20, 16, 20, 16])))
	t.set_stylebox("panel", "TooltipPanel", variant_box(variant, ["tooltip"], PackedInt32Array([14, 10, 14, 10])))
	t.set_font("font", "TooltipLabel", body)
	t.set_font_size("font_size", "TooltipLabel", SIZES.small)
	t.set_color("font_color", "TooltipLabel", ink)

	# -- rich text ------------------------------------------------------------------------
	t.set_stylebox("normal", "RichTextLabel", empty())
	t.set_stylebox("focus", "RichTextLabel", empty())
	t.set_font("normal_font", "RichTextLabel", body)
	t.set_font("bold_font", "RichTextLabel", semibold)
	t.set_font("italics_font", "RichTextLabel", italic)
	t.set_font("bold_italics_font", "RichTextLabel", semibold)
	t.set_font("mono_font", "RichTextLabel", body)
	t.set_font_size("normal_font_size", "RichTextLabel", SIZES.body)
	t.set_font_size("bold_font_size", "RichTextLabel", SIZES.body)
	t.set_font_size("italics_font_size", "RichTextLabel", SIZES.body)
	t.set_color("default_color", "RichTextLabel", ink)
	t.set_color("font_shadow_color", "RichTextLabel", Color(0, 0, 0, 0))
	t.set_constant("line_separation", "RichTextLabel", 4)

	# -- containers -----------------------------------------------------------------------
	t.set_constant("separation", "HBoxContainer", 12)
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("h_separation", "GridContainer", 12)
	t.set_constant("v_separation", "GridContainer", 10)
	t.set_stylebox("separator", "HSeparator", _rule_box(ink_soft))
	t.set_stylebox("separator", "VSeparator", _rule_box(ink_soft))
	t.set_constant("separation", "HSeparator", 10)
	t.set_constant("separation", "VSeparator", 10)

	# -- window / dialogs ------------------------------------------------------------------
	t.set_stylebox("panel", "AcceptDialog", variant_box(variant, ["panel_metal"], PackedInt32Array([26, 22, 26, 22])))
	t.set_stylebox("embedded_border", "Window", variant_box(variant, ["panel_metal"]))
	t.set_font("title_font", "Window", display_light)
	t.set_font_size("title_font_size", "Window", SIZES.heading)
	t.set_color("title_color", "Window", ink)

	t.set_color("paper", "Wickmere", paper)
	t.set_color("paper_lo", "Wickmere", paper_lo)
	t.set_color("ink", "Wickmere", ink)
	t.set_color("ink_soft", "Wickmere", ink_soft)
	t.set_color("metal", "Wickmere", metal)
	t.set_color("metal_hi", "Wickmere", metal_hi)
	t.set_color("accent", "Wickmere", accent)
	t.set_color("edge", "Wickmere", edge)
	return t


static func _label_variation(t: Theme, name: String, font: Font, size: int, col: Color, spacing: int) -> void:
	t.set_type_variation(name, "Label")
	t.set_font("font", name, font)
	t.set_font_size("font_size", name, size)
	t.set_color("font_color", name, col)
	t.set_constant("line_spacing", name, spacing)
	t.set_stylebox("normal", name, empty())


static func _rule_box(col: Color) -> StyleBoxLine:
	var sb := StyleBoxLine.new()
	sb.color = Color(col.r, col.g, col.b, 0.45)
	sb.thickness = 1
	return sb
