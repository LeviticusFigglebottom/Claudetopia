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
