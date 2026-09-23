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
