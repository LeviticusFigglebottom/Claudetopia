extends TestCase
## Words that have to be read fade on the wall clock (WallTweens).
##
## A Tween runs on the engine's delta. On a machine drawing a frame every few seconds the engine
## counts each frame as an eighth of a second, so the opening's lines and the Warden's first words
## were still half-inked on the frame the player looked at. Each test here gives the words one long
## frame that the engine counts as next to nothing, then reads the ink.

const HUD_SCENE := "res://ui/hud/hud.tscn"
## A long frame, as a slow machine draws them.
const LONG_FRAME_MS := 500
## What the engine counts it as.
const COUNTED_S := 0.001


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func test_a_cinematic_line_is_fully_in_after_one_long_frame() -> void:
	var overlay := CinematicOverlay.new()
	_tree().root.add_child(overlay)
	overlay._process(COUNTED_S)
	overlay.say("THE WARDEN", "There. Said out loud, and heard. That is how it holds.")
	OS.delay_msec(LONG_FRAME_MS)
	overlay._process(COUNTED_S)
	assert_gt(overlay.line_alpha(), 0.99, "the line is fully in after one long frame (%.2f)" % overlay.line_alpha())
	overlay.title_in("Wickmere", "")
	OS.delay_msec(1700)
	overlay._process(COUNTED_S)
	assert_true(overlay.title_shown(), "and so is the title card")
	_tree().root.remove_child(overlay)
	overlay.free()


## The key that asks for the skip prompt goes down while a long frame is being drawn and is read at
## the start of the next. On the engine's delta the prompt came in by an eighth of a second a frame
## however long the frames were, and a hold of a second is a skip on the wall clock: on a loaded
## machine the prompt could still be half in when the skip took it away again.
func test_the_skip_prompt_is_in_on_the_frame_after_its_key() -> void:
	var overlay := CinematicOverlay.new()
	_tree().root.add_child(overlay)
	overlay._process(COUNTED_S)
	OS.delay_msec(LONG_FRAME_MS)
	overlay.prompt(true)
	overlay._process(COUNTED_S)
	assert_gt(overlay.prompt_alpha(), 0.99, "the skip prompt is fully in on the frame after its key (%.2f)" % overlay.prompt_alpha())
	overlay.prompt(false)
	OS.delay_msec(LONG_FRAME_MS + 200)
	overlay._process(COUNTED_S)
	assert_false(overlay.prompt_shown(), "and gone on the frame after it is let go (%.2f)" % overlay.prompt_alpha())
	_tree().root.remove_child(overlay)
	overlay.free()


## The story's next thing to do, under the compass, and a place's name as the player comes to it.
func test_the_objective_line_and_a_place_s_name_are_in_after_one_long_frame() -> void:
	var hud: Node = (load(HUD_SCENE) as PackedScene).instantiate()
	_tree().root.add_child(hud)
	hud.call("_process", COUNTED_S)
	hud.call("show_objective", "The Naming: Speak to the Warden at her fire")
	hud.call("show_region_card", "Cinderlea", "The heath above the Hush")
	OS.delay_msec(1200)
	hud.call("_process", COUNTED_S)
	var line := (hud.get("_objective") as Control).modulate.a
	assert_gt(line, 0.99, "the objective line is fully in after one long frame (%.2f)" % line)
	var card := (hud.get("_region_card") as Control).modulate.a
	assert_gt(card, 0.99, "and so is the place's name (%.2f)" % card)
	_tree().root.remove_child(hud)
	hud.free()


func test_the_hud_subtitle_is_fully_in_after_one_long_frame() -> void:
	var hud: Node = (load(HUD_SCENE) as PackedScene).instantiate()
	_tree().root.add_child(hud)
	hud.call("_process", COUNTED_S)
	hud.call("show_subtitle", "Wren Tallow: There you are. Eyes working? Good.", 6.0)
	OS.delay_msec(LONG_FRAME_MS)
	hud.call("_process", COUNTED_S)
	var ink := float(hud.call("subtitle_alpha"))
	assert_gt(ink, 0.99, "the Warden's first words are fully in after one long frame (%.2f)" % ink)
	_tree().root.remove_child(hud)
	hud.free()
