extends TestCase
## The region's card does not come up over the opening or its hand-over. In the flow's picture of the
## first moment of control, "Cinderlea" faded in over the middle of the frame, across the Choir on the
## skyline and the Warden at her fire, while the objective's line said to speak to her. The card now
## waits while a cinematic plays and for a settle after it, then comes up by itself.

const HUD_SCENE := preload("res://ui/hud/hud.tscn")


class FakeCinematic:
	extends Node
	var playing := true

	func _ready() -> void:
		add_to_group(CinematicPlayer.GROUP)

	func is_playing() -> bool:
		return playing


var _hud: Node = null
var _cin: FakeCinematic = null


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	_hud = HUD_SCENE.instantiate()
	_tree().root.add_child(_hud)
	_cin = FakeCinematic.new()
	_tree().root.add_child(_cin)


func after_each() -> void:
	for n in [_hud, _cin]:
		if n != null and is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.free()


func _card_alpha() -> float:
	return (_hud.get("_region_card") as CanvasItem).modulate.a


func _wall_wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await _tree().process_frame


func test_the_card_waits_out_the_opening_and_its_hand_over() -> void:
	_hud.set("region_card_settle_s", 1.0)
	await _tree().process_frame
	_hud.call("show_region_card", "Cinderlea", "Where the Dwindling is strong", "")
	await _wall_wait(0.5)
	assert_true(bool(_hud.call("region_card_waiting")), "the card is held while the opening plays")
	assert_true(_card_alpha() < 0.01, "and nothing of it is on the screen")
	_cin.playing = false
	await _wall_wait(0.4)
	assert_true(bool(_hud.call("region_card_waiting")), "it still waits just after the hand-over")
	assert_true(_card_alpha() < 0.01)
	await _wall_wait(1.6)
	assert_false(bool(_hud.call("region_card_waiting")), "once the hand-over has settled it comes up")
	assert_gt(_card_alpha(), 0.05, "and is drawn")
	assert_eq(str((_hud.get("_region_name") as Label).text), "Cinderlea")


func test_with_no_cinematic_the_card_comes_up_at_once() -> void:
	_cin.get_parent().remove_child(_cin)
	_cin.free()
	_cin = null
	await _tree().process_frame
	_hud.call("show_region_card", "Hearthvale", "The Vale", "")
	assert_false(bool(_hud.call("region_card_waiting")), "crossing into a region in play shows its card straight away")
