extends Node
## The way in, pressed the way a player presses it.
##
##   ./run.sh flow
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path game --rendering-driver opengl3 \
##       --audio-driver Dummy --resolution 1280x720 -- --flow=captures/flow [--load=<slot> | --continue]
##
## Boot attaches this at the root when it sees --flow and then boots exactly as it does with no
## arguments. From there the probe does what a player does and nothing a player cannot: it waits
## for the title menu, finds New Game by the words on it and clicks it; waits for the Naming,
## clicks the name field and types, rolls the other names, clicks a swatch of each kind, opens
## a chooser and picks with the keys, drags a slider, clicks a Calling card, clicks Be named;
## then watches the world stand up, sampling the frame at 2, 5, 10, 20 and 40 seconds from the
## press. Every step is a PNG in --flow=<dir>, and the run ends with the body turned to face the
## camera so the PNG can be held against the Naming's.
##
## A new game then plays the opening (DESIGN §5.1a). The probe photographs every shot of it as it
## really plays, streaming and all, checks that each picture is a picture and each black is one
## the opening means (its black shot, or a hold with its caption up), and holds a key through the
## last shot to skip it, the way a player would. A Continue and a --load check that none plays.
##
## It fails, printing FLOW: FAIL and exiting 1, when a button cannot be found or does nothing,
## the screen is black where a caption or the world should be (mean luminance under BLACK:
## the fade's own rectangle measures 0.042, so anything under 0.06 is the fade or nothing), the
## fade is still down once the body stands, the HUD is not up, or the body standing in the
## world is not the one the Naming made. With --load=<slot> or --continue it skips the Naming
## and holds the loaded character against what the New Game run wrote to flow_state.json.
##
## With --naming-tour it stops at the Naming instead: it makes a run of complete looks there --
## each Calling with a face, a hair style, a beard, tones and a build -- through the screen's own
## controls, checks the preview body took every choice, captures each look whole, and quits
## without standing the world up. That is how the first screen a player sees gets looked at:
##
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path game --rendering-driver opengl3 \
##       --audio-driver Dummy --resolution 1280x720 -- --flow=captures/naming --naming-tour

const BLACK := 0.06
const NAME := "Tam Cresswell"
const SKIN := "amber"
const HAIR_COLOUR := "ginger"
const EYES := "green"
const CALLING := "core:calling/cragborn"
const SLOT := "flow"
const SAMPLE_SECONDS := [2.0, 5.0, 10.0, 20.0, 40.0]
## The looks --naming-tour makes, one per Calling and then a few that push the extremes: every
## face, hair style and beard the choosers offer appears at least once across the run.
const TOUR := [
	{"calling": "core:calling/hearthkeeper", "head": "round", "hair": "short", "beard": "",
		"skin": "fair", "hair_colour": "sand", "eyes": "blue", "build": 0.5, "height": 1.74},
	{"calling": "core:calling/wayfarer", "head": "angular", "hair": "tousled", "beard": "stubble",
		"skin": "wheat", "hair_colour": "brown", "eyes": "hazel", "build": 0.45, "height": 1.80},
	{"calling": "core:calling/reedborn", "head": "narrow", "hair": "long", "beard": "",
		"skin": "olive", "hair_colour": "black", "eyes": "dark_brown", "build": 0.35, "height": 1.70},
	{"calling": "core:calling/cragborn", "head": "broad", "hair": "braid", "beard": "short_beard",
		"skin": "fair", "hair_colour": "ginger", "eyes": "grey_green", "build": 0.8, "height": 1.84},
	{"calling": "core:calling/ashwalker", "head": "hawk", "hair": "cropped", "beard": "long_beard",
		"skin": "deep", "hair_colour": "soot", "eyes": "grey", "build": 0.4, "height": 1.78},
	{"calling": "core:calling/lantern_clerk", "head": "soft", "hair": "bun", "beard": "",
		"skin": "porcelain", "hair_colour": "ash_blond", "eyes": "pale_blue", "build": 0.2, "height": 1.66},
	{"calling": "core:calling/hearthkeeper", "head": "heavy_brow", "hair": "hood_friendly", "beard": "moustache",
		"skin": "umber", "hair_colour": "grey", "eyes": "brown", "build": 0.95, "height": 1.62},
	{"calling": "core:calling/reedborn", "head": "default", "hair": "braid", "beard": "",
		"skin": "ebony", "hair_colour": "white", "eyes": "amber", "build": 0.1, "height": 1.92},
	# the ends of both sliders, together: nothing a player can drag to may break the body
	{"calling": "core:calling/wayfarer", "head": "narrow", "hair": "long", "beard": "",
		"skin": "wheat", "hair_colour": "chestnut", "eyes": "hazel", "build": 0.0, "height": 1.55},
	{"calling": "core:calling/cragborn", "head": "broad", "hair": "short", "beard": "long_beard",
		"skin": "olive", "hair_colour": "dark_brown", "eyes": "brown", "build": 1.0, "height": 1.95},
	{"calling": "core:calling/lantern_clerk", "head": "round", "hair": "tousled", "beard": "",
		"skin": "fair", "hair_colour": "flax", "eyes": "blue", "build": 1.0, "height": 1.55},
	{"calling": "core:calling/ashwalker", "head": "angular", "hair": "cropped", "beard": "short_beard",
		"skin": "amber", "hair_colour": "black", "eyes": "green", "build": 0.0, "height": 1.95},
]
const WORLD_TIMEOUT := 420.0
## A world is not entered unless it has this many drawn things within NEAR_RADIUS of the body
## (terrain, water, sky and the body itself not counted). A void has none; the Hushline Stair,
## the emptiest place anybody starts, has hundreds.
const NEAR_RADIUS := 200.0
const MIN_NEAR := 10

var out_dir := "captures/flow"
var mode := "new"            # new | load | continue | new-game
var load_slot := ""
## --naming-tour=quick makes two looks and skips the presets, for iterating on the screen.
var tour_quick := false

var _checks: Array[Dictionary] = []
## What _photograph_the_opening saw, for _watch_the_opening to report.
var _opening := {"found": false, "done": false, "no_hud": false, "shots": 0, "seen": {}, "gave_up": false,
		"early": [], "seconds": 0.0}
var _notes: Array[String] = []
var _shot := 0
var _t0 := 0
var _errors_at_start := 0
var _spawned: Node = null
var _spawned_at_ms := -1
var _mouse := Vector2.ZERO
var _last_frame_ms := 0
var _gap_ms := 0
var _gap_from_ms := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--load="):
			mode = "load"
			load_slot = a.substr(7)
		elif a == "--continue":
			mode = "continue"
		elif a == "--new-game":
			mode = "new-game"
		elif a.begins_with("--naming-tour"):
			mode = "naming-tour"
			tour_quick = a == "--naming-tour=quick"
	out_dir = _absolute(out_dir)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_errors_at_start = Log.error_count
	EventBus.player_spawned.connect(func(p: Node) -> void:
			_spawned = p
			_spawned_at_ms = Time.get_ticks_msec())
	_run()


func _run() -> void:
	print("[flow] mode=%s -> %s" % [mode, out_dir])
	# With no world on disk every way in stops at the title, which says why; the run fails there,
	# with the title's words in the report, rather than waiting seven minutes for a body.
	var world_status := WorldStatus.current()
	if not _check(bool(world_status.get("playable", false)), "there is a world to go into (%s)"
			% str(world_status.get("state", ""))):
		var menu := await _wait_for_scene("main_menu.gd", 90.0)
		await _settle(2.2)
		await _capture("no_world")
		var notice: Node = menu.get("notice") if menu != null else null
		_check(notice != null, "and the title says so")
		_notes.append("the title says: %s" % (str(notice.call("text")).replace("\n", " / ") if notice != null
				else str(world_status.get("title", ""))))
		_finish()
		return
	match mode:
		"new":
			await _new_game_flow()
		"continue":
			await _continue_flow()
		"naming-tour":
			await _naming_tour()
		_:
			await _straight_in_flow()
	_finish()


# --- the three ways in ------------------------------------------------------------------------

func _new_game_flow() -> void:
	var menu := await _wait_for_scene("main_menu.gd", 90.0)
	if not _check(menu != null, "the title menu comes up from boot"):
		return
	await _settle(2.2)      # the words ink in over about a second and a half
	await _capture("title")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "the mouse is free on the title menu")
	_check(Music.overlay_playing() == "core:music/main_theme", "the title's theme is playing (%s)"
			% (Music.overlay_playing() if not Music.overlay_playing().is_empty() else "nothing"))
	var new_game := _button(menu, "New Game")
	if not _check(new_game != null and not new_game.disabled, "New Game is on the title menu, by name, and enabled"):
		return
	await _click(new_game)
	var naming := await _wait_for_scene("naming.gd", 30.0)
	if not _check(naming != null, "clicking New Game opens the Naming"):
		return
	await _settle(1.6)
	await _capture("naming")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "the mouse is free on the Naming")
	_check(Music.overlay_playing() == "core:music/naming", "the Naming's music is playing (%s)"
			% (Music.overlay_playing() if not Music.overlay_playing().is_empty() else "nothing"))
	var focus := get_viewport().gui_get_focus_owner()
	_check(focus is LineEdit, "the Naming opens with the keyboard in the name field, so a pad has somewhere to start (focus: %s)"
			% (focus.get_class() if focus != null else "nothing"))
	await _fill_the_naming(naming)
	await _settle(0.6)
	await _capture("naming_filled")
	var expected: Dictionary = naming.call("appearance_dict")
	expected["name"] = NAME
	expected["calling"] = str(naming.get("calling_id"))
	var be_named := _button(naming, "Be named")
	if not _check(be_named != null and not be_named.disabled, "Be named is there, by name, and enabled"):
		return
	await _click(be_named)
	_t0 = Time.get_ticks_msec()
	# The Naming fades for half a second and then changes scene, and the world's _ready then
	# blocks the loop until the ground is up: whatever frame was drawn last is what the player
	# looks at for the whole of that. So the caption is captured here, inside the fade, and the
	# gap in frames is reported below rather than hidden.
	var shown := await _wait_until(func() -> bool: return UI.is_loading_shown(), 2.0)
	_check(shown, "Be named puts the loading caption up at once")
	_check(UI.is_faded_out() or _spawned != null, "Be named fades the Naming out")
	await _capture("be_named_pressed")
	await _settle(0.42)
	var luma := await _capture("loading_caption")
	_check(UI.is_loading_shown() and luma > BLACK,
			"the last frame before the world is the caption over the black, not a dead screen (luma %.3f: %s)"
			% [luma, UI.loading_text().replace("\n", " / ")])
	await _watch_the_world_stand_up()
	if _spawned == null:
		return
	_verify_body(expected)
	await _portrait()
	var err := SaveSystem.save_to_slot(SLOT)
	_check(err == OK, "the character saves to slot '%s' for the load runs" % SLOT)
	var f := FileAccess.open("%s/flow_state.json" % out_dir, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(expected, "  "))


func _continue_flow() -> void:
	# Continue promises the newest slot, which is not necessarily the one the New Game run
	# wrote: anything else that saves — a journey run, another session on the same user://
	# directory, a quick save — takes that place. So the probe reads what Continue is about
	# to pick and holds the body against *that* character, fully when it is the flow slot
	# and by its saved summary otherwise.
	var newest := _newest_slot()
	if not _check(not newest.is_empty(), "there is a saved name for Continue to load"):
		return
	var expected := {}
	if str(newest.get("slot", "")) == SLOT:
		expected = _expected_from_the_first_run()
		if expected.is_empty():
			return
	else:
		_notes.append("Continue picked '%s' (saved %s), not this run's '%s': something else wrote a newer save, so the body is checked against that slot's own summary"
				% [newest.get("slot", ""), newest.get("saved_at", ""), SLOT])
	var menu := await _wait_for_scene("main_menu.gd", 90.0)
	if not _check(menu != null, "the title menu comes up from boot"):
		return
	await _settle(2.2)
	await _capture("title")
	var cont := _button(menu, "Continue")
	if not _check(cont != null and not cont.disabled, "Continue is on the title menu, by name, and enabled now that a name is saved"):
		return
	await _click(cont)
	_t0 = Time.get_ticks_msec()
	await _settle(0.8)
	await _capture("continue_pressed")
	await _watch_the_world_stand_up()
	if _spawned == null:
		return
	if expected.is_empty():
		_verify_body_against_slot(newest)
	else:
		_verify_body(expected)
	await _portrait()


## --naming-tour: title, New Game, and then the Naming through every look in TOUR.
func _naming_tour() -> void:
	var menu := await _wait_for_scene("main_menu.gd", 90.0)
	if not _check(menu != null, "the title menu comes up from boot"):
		return
	await _settle(2.2)
	var new_game := _button(menu, "New Game")
	if not _check(new_game != null and not new_game.disabled, "New Game is on the title menu"):
		return
	await _click(new_game)
	var naming := await _wait_for_scene("naming.gd", 30.0)
	if not _check(naming != null, "clicking New Game opens the Naming"):
		return
	await _settle(2.0)
	await _capture("as_it_opens")
	for i in TOUR.size():
		if tour_quick and not (i in [0, 3]):
			continue
		var look: Dictionary = TOUR[i]
		await _make_look(naming, look)
		await _settle(1.2)
		var label := "%s_%s_%s" % [Ids.name_of(str(look["calling"])), look["head"], look["hair"]]
		await _capture(label)
		_check_look(naming, look, label)
		await _close_in(naming, label)
	if tour_quick:
		return
	# every preset, through its own chooser, and three casts of the lots
	var presets := _find_meta(naming, "presets", "true") as OptionButton
	if _check(presets != null, "the Naming offers presets"):
		for i in range(1, presets.item_count):
			var name := presets.get_item_text(i)
			presets.select(i)
			presets.item_selected.emit(i)
			await _settle(1.2)
			await _capture("preset_%s" % name.to_lower().replace(" ", "_").replace("-", "_"))
			_check(presets.selected == 0, "choosing the preset '%s' leaves the chooser ready for the next" % name)
	var lots := _button(naming, "Cast lots")
	if _check(lots != null, "the Naming can cast lots for a look"):
		var seen := {}
		for k in 3:
			await _click(lots)
			await _settle(1.2)
			var look := _look(naming)
			seen[JSON.stringify(look.to_dict())] = true
			await _capture("lots_%d" % (k + 1))
		_check(seen.size() == 3, "three casts of the lots gave three different looks")


## Presses "Face", looks, and stands back again: the close framing has to hold for every look.
func _close_in(naming: Node, label: String) -> void:
	var face := _button(naming, "Face")
	if not _check(face != null, "%s: the portrait has a Face framing" % label):
		return
	await _click(face)
	await _settle(1.4)
	await _capture(label + "_face")
	var whole := _button(naming, "Whole figure")
	if _check(whole != null, "%s: and a Whole figure framing" % label):
		await _click(whole)
		await _settle(0.6)


## Makes one look through the controls a player would use, in the order they sit on the page.
func _make_look(naming: Node, look: Dictionary) -> void:
	for pair in [["Skin", "skin"], ["Hair", "hair_colour"], ["Eyes", "eyes"]]:
		var label := _label(naming, str(pair[0]))
		var swatch := _find_meta(label.get_parent(), "tone", str(look[pair[1]])) if label != null else null
		if _check(swatch != null, "the %s row has a %s swatch" % [pair[0], look[pair[1]]]):
			(swatch as Button).pressed.emit()
	# the beards are the ones the screen offers, which are only the ones that draw
	var options := {"hair": CharacterAppearance.HAIR_STYLES, "head": CharacterAppearance.HEADS,
		"beard": naming.call("offered_beards")}
	for slot in options:
		var o := _chooser(naming, slot)
		var index: int = (options[slot] as Array).find(str(look[slot]))
		if _check(o != null and index >= 0, "the %s chooser offers '%s'" % [slot, look[slot]]):
			o.select(index)
			o.item_selected.emit(index)
	for key in ["build", "height"]:
		var s := _slider(naming, key)
		if _check(s != null, "the %s slider is there" % key):
			s.value = float(look[key])
	var card := _find_meta(naming, "calling", str(look["calling"]))
	if _check(card != null, "there is a card for %s" % look["calling"]):
		(card as Button).pressed.emit()
	await _frames(3)


## The preview body wears exactly what was chosen, and every part it was asked for is on it.
func _check_look(naming: Node, look: Dictionary, label: String) -> void:
	var model: Node = naming.get("_model")
	if not _check(model != null, "%s: the Naming has a preview body" % label):
		return
	var worn: CharacterAppearance = model.get("appearance")
	_check(worn.skin == str(look["skin"]) and worn.hair_colour == str(look["hair_colour"])
			and worn.eye_colour == str(look["eyes"]),
			"%s: the body's tones are the swatches pressed (%s, %s, %s)" % [label, worn.skin, worn.hair_colour, worn.eye_colour])
	for slot in ["head", "hair", "beard"]:
		_check(worn.part(slot) == str(look[slot]),
				"%s: the body's %s is '%s' (it is '%s')" % [label, slot, look[slot], worn.part(slot)])
	var parts: Dictionary = model.get("_part_meshes")
	for slot in ["hair", "beard", "torso"]:
		if worn.part(slot).is_empty():
			continue
		var meshes: Array = parts.get(slot, [])
		var drawn := 0
		for mi in meshes:
			var m := mi as MeshInstance3D
			if m != null and m.mesh != null and m.mesh.get_surface_count() > 0:
				drawn += 1
		_check(drawn > 0, "%s: the %s '%s' is on the body with a mesh to draw" % [label, slot, worn.part(slot)])


## --load=<slot> and --new-game: boot goes straight to the world, no menu in between.
func _straight_in_flow() -> void:
	var expected := {}
	if mode == "load":
		expected = _expected_from_the_first_run()
		if expected.is_empty():
			return
	_t0 = Time.get_ticks_msec()
	await _settle(0.8)
	await _capture("boot")
	await _watch_the_world_stand_up()
	if _spawned == null:
		return
	if mode == "load":
		_verify_body(expected)
	else:
		_check(_spawned.call("body_model") != null, "a --new-game Foundling has a forge body")
		var look: CharacterAppearance = _spawned.get("appearance")
		_check(look != null and not look.part("torso").is_empty(), "and is dressed rather than the naked rig")
	await _portrait()


## The slot Continue will take: the newest, as the title menu sorts them.
func _newest_slot() -> Dictionary:
	var slots := SaveSystem.list_slots()
	return slots[0] if slots.size() > 0 else {}


## What can be asked of a character this run did not make: that the body standing there is the
## one that slot's summary names, dressed by the forge rather than a placeholder.
func _verify_body_against_slot(slot: Dictionary) -> void:
	var summary: Dictionary = slot.get("summary", {})
	var name := str(summary.get("name", ""))
	_check(str(_spawned.get("display_name")) == name,
			"the body is the one slot '%s' saved, %s (it answers to '%s')"
			% [slot.get("slot", ""), name, _spawned.get("display_name")])
	var model: Node = _spawned.call("body_model") if _spawned.has_method("body_model") else null
	if not _check(model != null, "the loaded player has a forge body, not a placeholder"):
		return
	var look: CharacterAppearance = model.get("appearance")
	_check(look != null and not look.part("torso").is_empty(),
			"and is dressed rather than the naked rig (torso: %s)" % (look.part("torso") if look else "none"))
	_check(look != null and look.skin in CharacterAppearance.SKIN_TONES,
			"and its skin is a tone the body's own vocabulary knows (%s)" % (look.skin if look else "none"))


func _expected_from_the_first_run() -> Dictionary:
	var path := "%s/flow_state.json" % out_dir
	if not FileAccess.file_exists(path):
		_check(false, "flow_state.json from the New Game run is at %s (run the new-game flow first)" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		_check(false, "flow_state.json is readable")
		return {}
	return parsed


# --- the Naming, control by control ------------------------------------------------------------

func _fill_the_naming(naming: Node) -> void:
	# the name: click the field, select what is there, type over it
	var edit := _first_of(naming, "LineEdit") as LineEdit
	if _check(edit != null, "the name field is on the Naming"):
		await _click(edit)
		_check(edit.has_focus(), "clicking the name field gives it the keyboard")
		await _key(KEY_A, true)
		await _type(NAME)
		_check(edit.text == NAME, "typing puts the name in the field (it reads '%s')" % edit.text)
		_check(str(naming.get("player_name")) == NAME, "and the Naming hears it")

	# the other names roll
	var before := _suggestions(naming)
	var again := _button_with_tooltip(naming, "other names")
	if _check(again != null, "the 'other names' button is there"):
		await _click(again)
		await _frames(2)
		_check(_suggestions(naming) != before, "'other names' rolls three new names")

	# one swatch of each kind
	await _press_swatch(naming, "Skin", SKIN)
	_check(_look(naming).skin == SKIN, "the skin swatch sets the skin (record says %s)" % _look(naming).skin)
	_check(_model_look(naming) != null and _model_look(naming).skin == SKIN, "and the preview body takes it")
	await _press_swatch(naming, "Hair", HAIR_COLOUR)
	_check(_look(naming).hair_colour == HAIR_COLOUR, "the hair swatch sets the hair colour (%s)" % _look(naming).hair_colour)
	_check(_model_look(naming) != null and _model_look(naming).hair_colour == HAIR_COLOUR, "and the preview body takes it")
	await _press_swatch(naming, "Eyes", EYES)
	_check(_look(naming).eye_colour == EYES, "the eye swatch sets the eyes (%s)" % _look(naming).eye_colour)

	# a chooser, clicked open and worked with the keys. Opened by the mouse, a list starts with
	# nothing highlighted, so the first press down lands on its first item (engine behaviour,
	# and what a mouse-and-keys player sees); the second moves on from there.
	var hair := _chooser(naming, "hair")
	if _check(hair != null, "the hair chooser is there"):
		var was := _look(naming).part("hair")
		await _click(hair)
		# the list opens on a later idle frame, and on a loaded machine that is not always the
		# third: wait for it (a second at most) rather than for a fixed count. If it never opens,
		# pressing on would send Down and Enter to whatever holds the focus instead -- once, Be
		# named -- and every check after this one would be reading a freed screen.
		if _check(await _popup_opens(hair), "clicking the hair chooser opens its list"):
			await _key(KEY_DOWN)
			await _key(KEY_DOWN)
			await _key(KEY_DOWN)
			await _key(KEY_ENTER)
			await _frames(2)
			var now := _look(naming).part("hair")
			_check(now != was and now == CharacterAppearance.HAIR_STYLES[2],
					"three presses down and Enter pick the third hair style (%s -> %s)" % [was, now])
			_check(_model_look(naming) != null and _model_look(naming).part("hair") == now, "and the preview body wears it")
	var face := _chooser(naming, "head")
	if _check(face != null, "the face chooser is there"):
		await _click(face)
		if _check(await _popup_opens(face), "clicking the face chooser opens its list"):
			await _key(KEY_DOWN)
			await _key(KEY_DOWN)
			await _key(KEY_ENTER)
			await _frames(2)
			_check(_look(naming).part("head") == CharacterAppearance.HEADS[1],
					"two presses down and Enter pick the second face (%s)" % _look(naming).part("head"))
			_check(_model_look(naming) != null and _model_look(naming).part("head") == CharacterAppearance.HEADS[1],
					"and the preview body wears that head")

	# a slider, dragged
	var height := _slider(naming, "height")
	if _check(height != null, "the height slider is there"):
		await _drag(height, 0.12, 0.94)
		_check(_look(naming).height > 1.85, "dragging the height slider raises the height (%.2f m)" % _look(naming).height)
		var model: Node = naming.get("_model")
		var rig: Node3D = model.get("_rig_root") if model != null else null
		_check(rig != null and rig.scale.y > 1.03, "and the preview body grows (scale %.3f)" % (rig.scale.y if rig else 0.0))
	var build := _slider(naming, "build")
	if _check(build != null, "the build slider is there"):
		await _drag(build, 0.5, 0.95)
		_check(_look(naming).build > 0.8, "dragging the build slider broadens the build (%.2f)" % _look(naming).build)

	# a Calling card
	var card := _find_meta(naming, "calling", CALLING)
	if _check(card != null, "the Cragborn card is there"):
		await _click(card)
		await _frames(2)
		_check(str(naming.get("calling_id")) == CALLING, "clicking a Calling card selects it")
		_check(_model_look(naming) != null and _model_look(naming).culture == "clans",
				"and the preview dresses for its people (%s)" % (_model_look(naming).culture if _model_look(naming) else "no body"))

	# the pad's way round: from the name field, Tab must be able to reach one of everything
	# and get out again to Be named, without being trapped in a wrapping chain
	if edit != null:
		await _click(edit)
		var reached := {}
		var last: Control = null
		for i in 90:
			await _key(KEY_TAB)
			var f := get_viewport().gui_get_focus_owner()
			if f == null or f == last:
				continue
			last = f
			reached[_kind_of(f)] = true
			if f is Button and (f as Button).text == "Be named":
				break
		var kinds := ["swatch", "chooser", "slider", "card", "Back", "Be named"]
		var missing: Array[String] = []
		for k in kinds:
			if not reached.has(k):
				missing.append(k)
		_check(missing.is_empty(), "Tab from the name field reaches a swatch, a chooser, a slider, a Calling card, Back and Be named (missing: %s)" % ", ".join(missing))


func _kind_of(c: Control) -> String:
	if c.has_meta("tone"):
		return "swatch"
	if c.has_meta("calling"):
		return "card"
	if c is OptionButton:
		return "chooser"
	if c is HSlider:
		return "slider"
	if c is Button and not (c as Button).text.is_empty():
		return (c as Button).text
	if c is LineEdit:
		return "name"
	return c.get_class()


## Whether a chooser's list is showing within `max_frames` idle frames of being clicked.
func _popup_opens(chooser: OptionButton, max_frames := 60) -> bool:
	for i in max_frames:
		if chooser.get_popup().visible:
			return true
		await _frames(1)
	return chooser.get_popup().visible


func _look(naming: Node) -> CharacterAppearance:
	return naming.get("appearance") as CharacterAppearance


func _model_look(naming: Node) -> CharacterAppearance:
	var model: Node = naming.get("_model")
	return model.get("appearance") as CharacterAppearance if model != null else null


func _suggestions(naming: Node) -> PackedStringArray:
	var out := PackedStringArray()
	var row: Node = naming.get("_suggest_row")
	if row == null:
		return out
	for c in row.get_children():
		if c is Button and not (c as Button).text.is_empty():
			out.append((c as Button).text)
	return out


func _press_swatch(naming: Node, label_text: String, tone: String) -> void:
	var label := _label(naming, label_text)
	if not _check(label != null, "the %s swatches are labelled" % label_text):
		return
	var swatch := _find_meta(label.get_parent(), "tone", tone)
	if not _check(swatch != null, "the %s row has a %s swatch" % [label_text, tone]):
		return
	await _click(swatch)
	await _frames(2)


func _chooser(root: Node, slot: String) -> OptionButton:
	return _find_meta(root, "slot", slot) as OptionButton


func _slider(root: Node, key: String) -> HSlider:
	return _find_meta(root, "key", key) as HSlider


# --- the world -----------------------------------------------------------------------------------

## Samples the frame on the clock from the press, then waits for a body and a lifted fade.
func _watch_the_world_stand_up() -> void:
	if mode in ["new", "new-game"]:
		_photograph_the_opening()
	for at in SAMPLE_SECONDS:
		while _elapsed() < float(at):
			await get_tree().process_frame
		var luma := await _capture("world_%02ds" % int(at))
		var actual := _elapsed()
		if _spawned != null:
			_notes.append("%.0f s sample (drawn at %.1f s): the body is up, luma %.3f" % [float(at), actual, luma])
			# mid-lift the black is still going; a black frame with the fade gone is dead -- unless
			# the opening is playing and the black is one it means
			_check(luma > BLACK or UI.is_faded_out() or _opening_means_the_black(),
					"%.0f s in, the world is not a black screen (luma %.3f)" % [float(at), luma])
			continue
		_check(UI.is_loading_shown(), "%.0f s in (%.1f s), the loading caption is up: %s"
				% [float(at), actual, UI.loading_text().replace("\n", " / ")])
		_check(luma > BLACK, "%.0f s in, the screen is not black (luma %.3f)" % [float(at), luma])
	while _spawned == null and _elapsed() < WORLD_TIMEOUT:
		await get_tree().process_frame
	if not _check(_spawned != null, "a body stands in the world within %d s (took %.0f s)"
			% [int(WORLD_TIMEOUT), (_spawned_at_ms - _t0) / 1000.0 if _spawned != null else _elapsed()]):
		return
	# The fade is held while the cells round the body keep arriving (UI.wait_for_country), up to
	# UI.COUNTRY_CAP_S; the lift is waited for while it is held, and a little after.
	var held_caption := ""
	if UI.is_holding_for_country():
		await _settle(0.3)
		held_caption = UI.loading_text().replace("\n", " / ")
		await _capture("holding_for_country")
	var lifted := await _wait_until(func() -> bool: return not UI.is_faded_out(), UI.COUNTRY_CAP_S + 30.0)
	_check(lifted, "the fade lifts once the body stands and the country round it is in")
	var wait: Dictionary = UI.last_country_wait
	if not wait.is_empty():
		var cells: Vector2i = wait.get("cells", Vector2i.ZERO)
		var at_spawn: Vector2i = wait.get("at_spawn", Vector2i.ZERO)
		_notes.append("when the body stood, %d of %d near cells were in, which is what the fade used to lift on; it waited %.1f s and %d frames more, and %d of %d were in when it lifted%s%s"
				% [at_spawn.x, at_spawn.y, float(wait.get("ms", 0)) / 1000.0, int(wait.get("frames", 0)), cells.x, cells.y,
					" (gave up: %s)" % str(wait.get("why", "")) if bool(wait.get("timed_out", false)) else "",
					"; caption while held: %s" % held_caption if not held_caption.is_empty() else ""])
		_check(not bool(wait.get("timed_out", false)), "the near cells were all in before the fade lifted (%d of %d)" % [cells.x, cells.y])
		# A streamer that is not following the body counts nothing, and nothing is all in at once:
		# the fade would lift at the first frame again, and the check above would not see it.
		_check(cells.y > 0, "the fade counted the cells round the body, not round something else (%d)" % cells.y)
	# a new game's opening begins once that hold has let the fade go (CinematicPlayer.begin waits
	# for it), and hands over before the world is photographed standing
	await _watch_the_opening()
	await _settle(2.5)
	var luma := await _capture("world_standing")
	_check(luma > BLACK, "the world is on the screen with the fade up (luma %.3f)" % luma)
	_check(UI.hud() != null and UI.hud().visible, "the HUD is up")
	_check(not UI.is_loading_shown(), "the loading caption has gone")
	_check(not UI.is_faded_out(), "the fade is not still down")
	await _check_the_ground()
	_notes.append("body stood at %.1f s from the press; %d cells streamed"
			% [(_spawned_at_ms - _t0) / 1000.0, _cells()])
	if _gap_ms > 1500:
		_notes.append("no frame was drawn between %.1f s and %.1f s after the press: the world stands up synchronously, and the caption drawn last is what the player looks at for all of it"
				% [(_gap_from_ms - _t0) / 1000.0, (_gap_from_ms + _gap_ms - _t0) / 1000.0])


## The opening on a new game; on a Continue or a load, that there is none. Every shot is
## photographed at the middle of its playing time, every picture must be more than the black, and
## the last shot is skipped by holding a key for longer than the prompt asks, through the same
## input a player's hand would give it.
func _watch_the_opening() -> void:
	var new_game := mode in ["new", "new-game"]
	if not new_game:
		var cin := await _wait_for_opening(8.0)
		_check(cin == null, "a %s does not play the opening" % mode)
		return
	# the photographs were taken as it played (_photograph_the_opening, started at the press)
	var finished := await _wait_until(func() -> bool: return bool(_opening["done"]), 900.0)
	if not _check(bool(_opening["found"]), "a new game plays the opening after the Naming"):
		return
	_check(bool(_opening["no_hud"]), "no HUD over the opening's pictures")
	var seen: Dictionary = _opening["seen"]
	var count := int(_opening["shots"])
	var gave_up := bool(_opening["gave_up"])
	var early: Array = _opening["early"]
	_notes.append("the opening: %d of %d shots photographed as they played, %.0f s from its first frame to the skip%s%s"
			% [seen.size(), count, float(_opening["seconds"]),
				"; its overall cap handed over first" if gave_up else "",
				"; shown before all of their country came: %s" % ", ".join(early) if not early.is_empty() else ""])
	# a machine too slow to show it all in the cap is handed over rather than left inside it; that
	# is the design, and the note says it happened
	_check(finished and (seen.size() == count or gave_up), "every shot of the opening was shown (%d of %d)%s"
			% [seen.size(), count, ", until the overall cap handed over" if gave_up else ""])
	# a skip fades to black, arrives at the hand-over and lifts: a handful of frames, which on a
	# machine drawing one every five seconds is most of a minute
	var gone := await _wait_until(func() -> bool: return get_tree().get_first_node_in_group(CinematicPlayer.GROUP) == null, 90.0)
	_check(gone, "the overall cap ended the opening and it let go of the screen" if gave_up
			else "holding a key skips the opening and it lets go of the screen")
	_check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "the mouse is the player's again after the opening")
	await _first_moment_of_control()


## Every shot of the opening, photographed at the middle of its playing time, every picture more
## than the black, and the last shot skipped by holding a key for longer than the prompt asks,
## through the same input a player's hand would give it. Started beside the probe's other waits
## the moment "Be named" is pressed, not after them: on a machine drawing a frame every few seconds
## the black shot is over before the fade's lift has been waited out.
func _photograph_the_opening() -> void:
	var cin: CinematicPlayer = null
	var until := Time.get_ticks_msec() + int(WORLD_TIMEOUT * 1000.0)
	while cin == null and Time.get_ticks_msec() < until:
		await RenderingServer.frame_pre_draw
		cin = get_tree().get_first_node_in_group(CinematicPlayer.GROUP) as CinematicPlayer
	if cin == null:
		_opening["done"] = true
		return
	_opening["found"] = true
	# its first pictures, not while it waits under the menus' fade for the country
	while is_instance_valid(cin) and not cin.is_playing() and Time.get_ticks_msec() < until:
		await RenderingServer.frame_pre_draw
	_opening["no_hud"] = not UI.hud_visible
	var shots := CinematicDef.shots_of(cin.def)
	_opening["shots"] = shots.size()
	var last := shots.size() - 1
	var seen: Dictionary = _opening["seen"]
	var started := Time.get_ticks_msec()
	var skipped := false
	while is_instance_valid(cin) and cin.is_playing() and Time.get_ticks_msec() - started < 600000:
		# read after the opening has moved this frame and before it is drawn, so the picture taken
		# is the moment read: at a few seconds a frame, the next frame can be half a shot later
		await RenderingServer.frame_pre_draw
		if not is_instance_valid(cin) or not cin.is_playing():
			break
		_opening["gave_up"] = cin.gave_up
		_opening["early"] = cin.shown_early.duplicate()
		if cin.gave_up:
			continue
		var i := cin.current_shot()
		var shot: Dictionary = shots[i]
		var half := float(shot.get("duration", 1.0)) * 0.5
		if not seen.has(i) and cin.phase_name() == "PLAY" and cin.shot_time() >= half:
			seen[i] = true
			var black := bool(shot.get("black", false))
			var luma := await _capture("opening_%02d_%s" % [i, str(shot.get("id", ""))])
			if not is_instance_valid(cin):
				break
			if black:
				_check(cin.overlay().said() != "", "the black shot '%s' carries its words (%s)" % [shot.get("id"), cin.overlay().said()])
			else:
				_check(luma > BLACK, "shot '%s' is a picture, not the black (luma %.3f)" % [shot.get("id"), luma])
			if i == last and not skipped:
				skipped = true
				await _hold_to_skip(cin)
				break
	_opening["seconds"] = (Time.get_ticks_msec() - started) / 1000.0
	_opening["done"] = true


## What the player is handed (DESIGN §5.1a): their own body on the screen, the person who speaks
## first standing in view and near, the story's first objective written under the compass and its
## smudge on the strip. Read on the first frame after the hand-over, and photographed a moment
## later once the HUD has inked in.
func _first_moment_of_control() -> void:
	await get_tree().process_frame
	var opening := ContentDB.get_or_empty(GameServices.OPENING)
	var greeter := str(opening.get("greeter", ""))
	var body := _spawned as Node3D
	var cam := get_viewport().get_camera_3d()
	_check(body != null and _on_screen(cam, body.global_position + Vector3(0.0, 1.0, 0.0)),
			"the first frame of control shows the player's own body")
	# the second playtest was stood on a pad in the sea: the spawn's own test of dry ground, here
	var world := _world()
	var provider: Object = world.get("provider") if world != null else null
	if body != null and provider != null:
		var feet := body.global_position
		_check(PlayerSpawn._dry_at(provider, feet.x, feet.z),
				"standing on dry ground, %.1f m above the nearest water" % (feet.y - float(provider.call("nearest_water_level", feet.x, feet.z))))
	var person: Node3D = null
	if NpcRegistry.instance != null and greeter != "":
		person = NpcRegistry.instance.actor(greeter) as Node3D
	var far_off := body.global_position.distance_to(person.global_position) if person != null and body != null else INF
	_check(person != null and far_off < 14.0,
			"%s stands at the start, %.1f m from the player" % [str(ContentDB.get_or_empty(greeter).get("name", greeter)), far_off])
	_check(person != null and _on_screen(cam, person.global_position + Vector3(0.0, 1.2, 0.0)),
			"and is in view on the first frame of control")
	var hud := UI.hud()
	var marked := hud != null and hud.has_method("quest_marker_on_strip") and bool(hud.call("quest_marker_on_strip"))
	_check(marked, "the first objective's smudge is on the compass strip")
	await _settle(1.2)
	var line := str(hud.call("objective_shown")) if hud != null and hud.has_method("objective_shown") else ""
	_check(not line.is_empty(), "the first objective is written under the compass: %s" % line)
	await _capture("first_moment_of_control")
	var services := get_tree().get_first_node_in_group("game_services")
	var words := str(services.get("first_words")) if services != null else ""
	_notes.append("handed over at %s; the first words were \"%s\"; the objective line read \"%s\""
			% [str(body.global_position.round()) if body != null else "?", words, line])


## Whether a point is in front of the camera and inside the picture.
func _on_screen(cam: Camera3D, point: Vector3) -> bool:
	if cam == null or cam.is_position_behind(point):
		return false
	var at := cam.unproject_position(point)
	return get_viewport().get_visible_rect().has_point(at)


## A key held the way a hand holds one: pressed, kept down past the prompt's fill, let go. The
## prompt is looked for on the frame the key goes down, before the hold can have filled: on a
## machine drawing a frame every few seconds the next frame is already past the second it asks for.
func _hold_to_skip(cin: CinematicPlayer) -> void:
	# at the start of a frame, as a hand's key arrives: the opening sees it before it moves on
	await get_tree().process_frame
	var ev := InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.physical_keycode = KEY_SPACE
	ev.pressed = true
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await _capture("opening_hold_to_skip")
	if is_instance_valid(cin) and cin.overlay() != null:
		_check(cin.overlay().prompt_shown(), "pressing a key during the opening shows the skip prompt")
	# kept down, on the wall clock, until the opening has taken it as a skip
	var taken := await _wait_until(func() -> bool: return not is_instance_valid(cin) or cin.skipped,
			CinematicPlayer.SKIP_HOLD_SECONDS + 30.0)
	_check(taken, "holding it down past the prompt's fill is taken as a skip")
	var up := ev.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()


## Looks once more when the time is up, since one long frame can outlast the whole wait.
func _wait_for_opening(timeout: float) -> CinematicPlayer:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while true:
		var found := get_tree().get_first_node_in_group(CinematicPlayer.GROUP)
		if found is CinematicPlayer:
			return found as CinematicPlayer
		if Time.get_ticks_msec() >= deadline:
			return null
		await get_tree().process_frame
	return null


## Whether a black frame now is one the opening means: its black shot, the curtain it fades in
## from, or a hold for the country with its caption up.
func _opening_means_the_black() -> bool:
	var cin := get_tree().get_first_node_in_group(CinematicPlayer.GROUP) as CinematicPlayer
	if cin == null or not cin.is_playing() or cin.overlay() == null:
		return false
	return cin.overlay().curtain() > 0.4 or cin.overlay().caption_shown()

## Is there a world under and around the body? A copy of the game with no built world passed every
## check above: the screen was not black (fog is not black), the fade was up, the HUD was up, and
## the body stood at y = 0 on nothing. So: the ground is drawn, something solid is under the feet,
## and the country has something in it within 200 m.
func _check_the_ground() -> void:
	var body := _spawned as Node3D
	if body == null or not is_instance_valid(body):
		return
	var world := _world()
	var drawn_by := str(world.get("terrain_mode")) if world != null else ""
	_check(drawn_by in ["terrain3d", "fallback"], "the ground is drawn (by %s)" % (drawn_by if not drawn_by.is_empty() else "nothing"))
	# On the coarse ground the player is owed the account of it, and a plate that stays while they
	# walk on it: a toast once said it, and a player took the coarse ground for the game's look.
	var said: Node = world.get("ground_notice") as Node if world != null else null
	if drawn_by == "fallback":
		_check(said != null and bool(said.call("plate_showing")), "the corner says the ground is the coarse one (%s)"
				% (str(said.call("text")) if said != null else "nothing says so"))
		var st: Variant = world.get("status")
		if st is Dictionary and bool((st as Dictionary).get("announce", false)) and said != null:
			# The card lets the region's title card go first (GroundNotice.AFTER_ARRIVAL_S), in game
			# time. When frames are slow the engine clamps each frame's delta to what its capped
			# physics steps cover (measured: 0.12 to 0.15 s for a 0.5 s frame), so on software
			# Vulkan under load the 4.8 s is half a minute of the clock or more.
			var asked := Time.get_ticks_msec()
			var up := await _wait_until(func() -> bool: return bool(said.get("card_shown")), 90.0)
			_check(up, "and a card says why, once the region's name has been shown (%.1f s later)"
					% ((Time.get_ticks_msec() - asked) / 1000.0))
			if up:
				await _settle(0.8)
				await _capture("coarse_ground_card")
	elif drawn_by == "terrain3d":
		_check(said == null, "nothing says the ground is coarse, because it is not")
		# Terrain3D builds its clipmap and its collision round the camera it was given last. It
		# was left on the fly camera, which flew off on the player's keys, and a player walked under
		# the ground (World.follow). Standing still, the flow could not see that; this can.
		var tn: Object = world.get("terrain_node") as Object
		if tn != null and tn.has_method("get_camera"):
			var cam := tn.call("get_camera") as Node
			_check(cam != null and (cam == body or body.is_ancestor_of(cam)),
					"Terrain3D's ground and collision follow the body's own camera (%s)"
					% (str(cam.get_path()) if cam != null else "no camera"))
	var feet := body.global_position
	var q := PhysicsRayQueryParameters3D.create(feet + Vector3.UP * 2.0, feet + Vector3.DOWN * 40.0, (1 << 0) | (1 << 10))
	var own: Array[RID] = []
	if body is CollisionObject3D:
		own.append((body as CollisionObject3D).get_rid())
	q.exclude = own
	var hit := body.get_world_3d().direct_space_state.intersect_ray(q)
	var what := "nothing within 40 m"
	var solid := false
	if not hit.is_empty():
		var gap := feet.y - (hit["position"] as Vector3).y
		what = "%s %.2f m below the feet" % [str((hit.get("collider") as Node).name) if hit.get("collider") is Node else "a collider", gap]
		solid = absf(gap) < 1.5
	elif drawn_by == "terrain3d":
		# Terrain3D builds its collision around its camera; the drawn height is the ground too
		var data: Object = (world.get("terrain_node") as Object).get("data") if world.get("terrain_node") != null else null
		var h: float = float(data.call("get_height", feet)) if data != null else NAN
		if not is_nan(h):
			what = "no collider yet, and Terrain3D draws the ground %.2f m below the feet" % (feet.y - h)
			solid = absf(feet.y - h) < 1.5
	_check(solid, "there is ground under the body (%s)" % what)
	var near := _things_within(body, NEAR_RADIUS)
	_check(near >= MIN_NEAR, "the country has things in it within %.0f m of the body (%d drawn, want %d)" % [NEAR_RADIUS, near, MIN_NEAR])
	_notes.append("objects drawn in the last frame: %d" % int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)))


func _world() -> Node:
	var world_script := load("res://world/world.gd") as GDScript
	return world_script.get("instance") if world_script != null else null


## Drawn things (meshes, scatter, buildings, props, people) whose bounds come within `radius` of the
## body, not counting the body, the ground, the water or the sky.
func _things_within(body: Node3D, radius: float) -> int:
	var world := _world()
	if world == null:
		return 0
	var skip: Array[Node] = [body]
	for field in ["terrain_node", "fallback", "water", "atmosphere"]:
		var part: Variant = world.get(field)
		if part is Node:
			skip.append(part as Node)
	var count := 0
	for n in world.find_children("*", "GeometryInstance3D", true, false):
		var g := n as GeometryInstance3D
		if not g.is_visible_in_tree():
			continue
		var skipped := false
		for s in skip:
			if s == g or s.is_ancestor_of(g):
				skipped = true
				break
		if skipped:
			continue
		var box := g.global_transform * g.get_aabb()
		var closest := body.global_position.clamp(box.position, box.end)
		if closest.distance_to(body.global_position) <= radius:
			count += 1
	return count


## The longest stretch without a frame, so the report can say how long the screen stood still.
func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if _last_frame_ms > 0 and _t0 > 0 and now - _last_frame_ms > _gap_ms:
		_gap_ms = now - _last_frame_ms
		_gap_from_ms = _last_frame_ms
	_last_frame_ms = now


func _cells() -> int:
	var world_script := load("res://world/world.gd") as GDScript
	var world: Node = world_script.get("instance") if world_script != null else null
	if world == null:
		return 0
	var streamer: Node = world.get("streamer")
	return int(streamer.call("loaded_count")) if streamer != null else 0


## Is the body standing there the one that was made?
func _verify_body(expected: Dictionary) -> void:
	var player := _spawned
	_check(str(player.get("display_name")) == str(expected.get("name", "")),
			"the body is called %s (it answers to '%s')" % [expected.get("name", ""), player.get("display_name")])
	var model: Node = player.call("body_model") if player.has_method("body_model") else null
	if not _check(model != null, "the player has a forge body, not a placeholder"):
		return
	var look: CharacterAppearance = model.get("appearance")
	for key in ["skin", "hair_colour", "eye_colour", "culture"]:
		_check(str(look.get(key)) == str(expected.get(key, "")),
				"the body's %s is %s (it is %s)" % [key, expected.get(key, ""), look.get(key)])
	var parts: Dictionary = expected.get("parts", {})
	for slot in ["hair", "head", "torso"]:
		_check(look.part(slot) == str(parts.get(slot, "")),
				"the body's %s is %s (it is %s)" % [slot, parts.get(slot, ""), look.part(slot)])
	_check(absf(look.height - float(expected.get("height", 0.0))) < 0.011,
			"the body is %.2f m tall (it is %.2f m)" % [float(expected.get("height", 0.0)), look.height])
	var calling := str(expected.get("calling", ""))
	var signature := str(ContentDB.get_or_empty(calling).get("signature_item", ""))
	var bag: Node = player.get_node_or_null("Inventory")
	_check(bag != null and bool(bag.call("has", signature)),
			"the Calling's signature item (%s) is in the bag" % Ids.name_of(signature))
	var prog: Node = player.get_node_or_null("Progression")
	_check(prog != null and str(prog.get("calling_id")) == calling, "the Calling %s is applied" % Ids.name_of(calling))


## Turns the camera round to look the body in the face, for the eye rather than for a check.
func _portrait() -> void:
	var rig: Node = _spawned.get("camera_rig")
	if rig == null:
		return
	var was: float = float(rig.get("yaw"))
	rig.set("yaw", was + PI)
	await _settle(2.0)
	await _capture("portrait")
	rig.set("yaw", was)


# --- pressing things -----------------------------------------------------------------------------

## A click: move the mouse there, press, release, the way a hand does it.
func _click(c: Control) -> void:
	await _reveal(c)
	var p := c.get_global_rect().get_center()
	await _mouse_move(p)
	await _mouse_button(p, true)
	await _frames(2)
	await _mouse_button(p, false)
	await _frames(2)


## A drag along a slider from one fraction of its width to another.
func _drag(s: Control, from_ratio: float, to_ratio: float) -> void:
	await _reveal(s)
	var r := s.get_global_rect()
	var y := r.get_center().y
	var x0 := r.position.x + r.size.x * from_ratio
	var x1 := r.position.x + r.size.x * to_ratio
	await _mouse_move(Vector2(x0, y))
	await _mouse_button(Vector2(x0, y), true)
	for i in 8:
		await _mouse_move(Vector2(lerpf(x0, x1, float(i + 1) / 8.0), y))
	await _mouse_button(Vector2(x1, y), false)
	await _frames(2)


## Where a point of the UI is in window pixels. A control's rect is in canvas units -- the
## 1280x720 the project is laid out in -- and a mouse event is in the window's own pixels, so at
## 2560x1440 every click the probe made landed at half the distance from the corner and missed.
func _to_window(p: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * p


func _mouse_move(p: Vector2) -> void:
	var w := _to_window(p)
	var ev := InputEventMouseMotion.new()
	ev.position = w
	ev.global_position = w
	ev.relative = w - _mouse
	ev.button_mask = 0
	_mouse = w
	Input.warp_mouse(w)
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await get_tree().process_frame


func _mouse_button(p: Vector2, pressed: bool) -> void:
	var w := _to_window(p)
	var ev := InputEventMouseButton.new()
	ev.position = w
	ev.global_position = w
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	await get_tree().process_frame


func _key(keycode: Key, ctrl := false) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = keycode
		ev.physical_keycode = keycode
		ev.key_label = keycode
		ev.ctrl_pressed = ctrl
		ev.pressed = pressed
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		await get_tree().process_frame


func _type(text: String) -> void:
	for i in text.length():
		for pressed in [true, false]:
			var ev := InputEventKey.new()
			ev.unicode = text.unicode_at(i)
			ev.pressed = pressed
			Input.parse_input_event(ev)
			Input.flush_buffered_events()
			await get_tree().process_frame


## A control below the fold is scrolled to, as a wheel would; that it had to be is noted.
func _reveal(c: Control) -> void:
	var n: Node = c.get_parent()
	while n != null and not (n is ScrollContainer):
		n = n.get_parent()
	if n == null:
		return
	var sc := n as ScrollContainer
	if not sc.get_global_rect().encloses(c.get_global_rect()):
		_notes.append("had to scroll to reach %s" % _describe(c))
		sc.ensure_control_visible(c)
		await get_tree().process_frame
		await get_tree().process_frame


func _describe(c: Control) -> String:
	if c is Button and not (c as Button).text.is_empty():
		return "the '%s' button" % (c as Button).text
	for key in ["tone", "slot", "key", "calling"]:
		if c.has_meta(key):
			return "%s %s" % [key, c.get_meta(key)]
	return c.get_class()


# --- finding things ------------------------------------------------------------------------------

func _wait_for_scene(script_file: String, timeout: float) -> Node:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		var s := get_tree().current_scene
		if s != null and s.get_script() != null and str((s.get_script() as Script).resource_path).ends_with(script_file):
			return s
		await get_tree().process_frame
	return null


func _wait_until(pred: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(pred.call()):
			return true
		await get_tree().process_frame
	return bool(pred.call())


func _walk(root: Node, pred: Callable) -> Node:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if bool(pred.call(n)):
			return n
		var kids := n.get_children()
		for i in range(kids.size() - 1, -1, -1):
			stack.append(kids[i])
	return null


func _button(root: Node, text: String) -> Button:
	return _walk(root, func(n: Node) -> bool: return n is Button and (n as Button).text == text) as Button


func _button_with_tooltip(root: Node, tip: String) -> Button:
	return _walk(root, func(n: Node) -> bool: return n is Button and (n as Button).tooltip_text == tip) as Button


func _label(root: Node, text: String) -> Label:
	return _walk(root, func(n: Node) -> bool: return n is Label and (n as Label).text == text) as Label


func _first_of(root: Node, cls: String) -> Node:
	return _walk(root, func(n: Node) -> bool: return n.is_class(cls))


func _find_meta(root: Node, key: String, value: String) -> Control:
	return _walk(root, func(n: Node) -> bool: return n is Control and n.has_meta(key) and str(n.get_meta(key)) == value) as Control


# --- looking and reporting -----------------------------------------------------------------------

## Writes the frame and returns its mean luminance (0..1), computed on a 64x36 reduction.
func _capture(name: String) -> float:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	_shot += 1
	var path := "%s/%s_%02d_%s.png" % [out_dir, mode, _shot, name]
	img.save_png(path)
	var luma := _mean_luma(img)
	print("[flow] %s  luma=%.3f" % [path, luma])
	return luma


static func _mean_luma(img: Image) -> float:
	var small := img.duplicate() as Image
	small.resize(64, 36, Image.INTERPOLATE_BILINEAR)
	var total := 0.0
	for y in 36:
		for x in 64:
			var c := small.get_pixel(x, y)
			total += 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
	return total / (64.0 * 36.0)


func _check(ok: bool, what: String) -> bool:
	_checks.append({"ok": ok, "what": what})
	print("[flow] %s  %s" % ["ok  " if ok else "FAIL", what])
	return ok


func _elapsed() -> float:
	return (Time.get_ticks_msec() - _t0) / 1000.0


func _settle(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _absolute(path: String) -> String:
	if path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path("res://../%s" % path)


func _finish() -> void:
	var failed := 0
	for c in _checks:
		if not bool(c["ok"]):
			failed += 1
	var report := {
		"mode": mode, "checks": _checks, "notes": _notes,
		"log_errors": Log.error_count - _errors_at_start, "out": out_dir,
	}
	var f := FileAccess.open("%s/flow_report_%s.json" % [out_dir, mode], FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  "))
	for n in _notes:
		print("[flow] note: %s" % n)
	print("FLOW: %s (%s: %d checks, %d failed, %d errors logged)"
			% ["PASS" if failed == 0 else "FAIL", mode, _checks.size(), failed, Log.error_count - _errors_at_start])
	get_tree().quit(0 if failed == 0 else 1)
