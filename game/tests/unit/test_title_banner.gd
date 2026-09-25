extends TestCase
## The title's menu hangs as a banner in the left third, so the country behind it is the picture
## (the vista's shots keep that third quiet); only the plain account of a world that is not there
## takes the centred sheet. The title and its five words sit on the banner, inside the sheet.

const MENU := preload("res://ui/menus/main_menu.tscn")


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func after_each() -> void:
	WorldStatus.override = {}


static func _facts(changes := {}) -> Dictionary:
	var f := {"manifest": true, "runtime_maps": true, "cells": 1024, "cells_expected": 1024, "pois": true,
		"terrain_class": true, "terrain_regions": 16, "forced_fallback": false,
		"os": "Linux", "arch": "x86_64", "os_version": "6.8"}
	for k in changes:
		f[k] = changes[k]
	return f


func test_the_menu_hangs_in_the_left_third() -> void:
	WorldStatus.override = _facts()
	var menu: Control = MENU.instantiate()
	_tree().root.add_child(menu)
	await _tree().process_frame
	await _tree().process_frame
	var screen := menu.get_viewport_rect().size
	var sheet := menu.get_node("Sheet") as Control
	var column := menu.get_node("Column") as Control
	var r := sheet.get_global_rect()
	assert_true(r.end.x <= screen.x * 0.34, "the sheet ends a third of the way across (%.0f of %.0f)" % [r.end.x, screen.x])
	assert_gt(r.size.y, screen.y * 0.9, "and hangs the height of the screen")
	var c := column.get_global_rect()
	assert_true(r.encloses(Rect2(c.position.x, c.position.y, c.size.x, 1.0)), "the column is on the sheet")
	for b in menu.find_children("*", "Button", true, false):
		var br := (b as Control).get_global_rect()
		assert_true(br.position.x >= r.position.x and br.end.x <= r.end.x, "%s is on the sheet" % (b as Button).text)
	menu.queue_free()
	await _tree().process_frame


func test_a_missing_world_keeps_the_centred_sheet() -> void:
	WorldStatus.override = _facts({"manifest": false})
	var menu: Control = MENU.instantiate()
	_tree().root.add_child(menu)
	await _tree().process_frame
	var sheet := menu.get_node("Sheet") as Control
	var mid := sheet.get_global_rect().get_center().x
	assert_near(mid, menu.get_viewport_rect().size.x * 0.5, 2.0, "centred, with room for the account")
	menu.queue_free()
	await _tree().process_frame
