class_name TestCase
extends RefCounted
## Base class for unit tests. Subclass in tests/unit/test_*.gd; every method named test_* runs.
## Optional hooks: before_each(), after_each().

var _failures: Array[String] = []
var _current := ""


func fail(msg: String) -> void:
	_failures.append("%s: %s" % [_current, msg])


func assert_true(cond: bool, msg := "") -> void:
	if not cond:
		fail("expected true. %s" % msg)


func assert_false(cond: bool, msg := "") -> void:
	if cond:
		fail("expected false. %s" % msg)


func assert_eq(a: Variant, b: Variant, msg := "") -> void:
	if a != b:
		fail("expected %s == %s. %s" % [str(a), str(b), msg])


func assert_ne(a: Variant, b: Variant, msg := "") -> void:
	if a == b:
		fail("expected %s != %s. %s" % [str(a), str(b), msg])


func assert_near(a: float, b: float, eps := 0.001, msg := "") -> void:
	if absf(a - b) > eps:
		fail("expected %f ~= %f (eps %f). %s" % [a, b, eps, msg])


func assert_gt(a: Variant, b: Variant, msg := "") -> void:
	if not (a > b):
		fail("expected %s > %s. %s" % [str(a), str(b), msg])


func assert_has(container: Variant, key: Variant, msg := "") -> void:
	if not container.has(key):
		fail("expected to contain %s. %s" % [str(key), msg])


func assert_empty(container: Variant, msg := "") -> void:
	if container.size() != 0:
		fail("expected empty, got %d items: %s. %s" % [container.size(), str(container).left(300), msg])


## A place, wherever the map puts it, `offset` metres east and south of it and at height `y`: a
## test that wants to stand something "in Merrowby" asks for Merrowby rather than writing down
## where Merrowby was (docs/COORDINATES.md). A place that says nowhere gives the map's middle.
static func at_place(place_id: String, y := 0.0, offset := Vector2.ZERO) -> Vector3:
	var xz := PlaceRef.xz(place_id)
	if xz == Vector2.INF:
		xz = Vector2.ZERO
	return Vector3(xz.x + offset.x, y, xz.y + offset.y)


## Shuts a screen the test opened through the real event, after checking that it did open. A
## full-screen screen pauses the world, and one left open freezes the physics of whatever test
## runs next; the runner tidies up after a test that forgets, but it names the test, because a
## test is expected to put back what it took out.
func close_screen(menu_id: String, msg := "") -> void:
	var ui: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("UI")
	if ui == null:
		fail("no UI to close the %s screen in. %s" % [menu_id, msg])
		return
	if not bool(ui.call("is_menu_open", menu_id)):
		fail("expected the %s screen to be open. %s" % [menu_id, msg])
		return
	ui.call("close", menu_id)
