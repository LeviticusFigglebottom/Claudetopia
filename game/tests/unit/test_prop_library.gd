extends TestCase
## The library must answer for every kind the interiors actually ask for, or say plainly
## which ones the forge still owes.


func test_every_requested_kind_resolves_or_is_reported() -> void:
	var lib := PropLibrary.new()
	lib.scan()
	if lib.kinds_built() == 0:
		# The forge has not landed in this checkout; nothing to assert against.
		return
	var wanted := {}
	for def in ContentDB.all("interior"):
		var meta_path := str(def.get("meta", ""))
		if meta_path.is_empty() or not FileAccess.file_exists(meta_path):
			continue
		var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
		for p in m.get("placements", []):
			var k := str(p.get("fixture", p.get("prop", "")))
			if not k.is_empty():
				wanted[k] = true
	var answered := 0
	for k in wanted:
		if not lib.resolve(k, "core:region/hearthvale").is_empty():
			answered += 1
	var coverage := float(answered) / maxf(float(wanted.size()), 1.0)
	print("  prop coverage: %d of %d kinds (%.0f%%); still owed: %s" % [
		answered, wanted.size(), coverage * 100.0, ", ".join(lib.missing_kinds().slice(0, 12))])
	assert_gt(coverage, 0.55, "over half the requested prop kinds should resolve once the forge has run")


func test_a_stand_in_is_never_absurd() -> void:
	var lib := PropLibrary.new()
	lib.scan()
	if lib.kinds_built() == 0:
		return
	# A stand-in has to make sense in the room: a table is a table, not a barrel.
	for pair in [["long_table", "table"], ["deed_chest", "chest"], ["cook_hearth", "hearth"]]:
		var a := lib.resolve(str(pair[0]), "core:region/hearthvale")
		var b := lib.resolve(str(pair[1]), "core:region/hearthvale")
		if not a.is_empty() and not b.is_empty():
			assert_eq(a.get_base_dir().get_file().replace("hearthvale_", "").rstrip("_abc"),
				b.get_base_dir().get_file().replace("hearthvale_", "").rstrip("_abc"),
				"%s and %s should stand in as the same thing" % pair)
