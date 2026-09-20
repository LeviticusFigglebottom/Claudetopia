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


## An interior knows it is a reedfolk house; the forge names its output by region. Handing
## `resolve()` a culture where it wants a region is not an error it can see — it falls
## through to "any region at all" and answers with a perfectly good barrel from the wrong
## part of the country. Both house interior calls did exactly that.
func test_a_culture_selects_its_own_regions_materials() -> void:
	var lib := PropLibrary.new()
	lib.scan()
	if lib.kinds_built() == 0:
		return
	for pair in Settlement.CULTURE_BY_REGION.keys():
		var region := Ids.name_of(str(pair))
		var culture := str(Settlement.CULTURE_BY_REGION[pair])
		assert_eq(lib.resolve("barrel", culture), lib.resolve("barrel", region),
			"asking as %s got a different barrel than asking as %s" % [culture, region])


## Two copies of the same mapping drift. This one is the inverse of the settlement builder's,
## and the day it stops being so is the day reedfolk houses quietly furnish themselves out of
## Skerrow without anything going red.
func test_the_culture_map_is_the_settlements_map_inverted() -> void:
	assert_eq(PropLibrary.REGION_BY_CULTURE.size(), Settlement.CULTURE_BY_REGION.size(),
		"the two culture maps have drifted apart in size")
	for region_id in Settlement.CULTURE_BY_REGION:
		var culture := str(Settlement.CULTURE_BY_REGION[region_id])
		assert_eq(str(PropLibrary.REGION_BY_CULTURE.get(culture, "")), Ids.name_of(str(region_id)),
			"%s does not map back to %s" % [culture, region_id])


## A stand-in that points at a kind the forge never built is worse than no stand-in at all:
## `resolve()` tries the kind, tries the substitute, finds neither, and the room draws a
## labelled box — so the entry reads as coverage in the source and delivers none in the room.
## Eleven smith's tools pointed at `tongs`, which nothing had ever built.
func test_every_stand_in_points_at_something_built() -> void:
	var lib := PropLibrary.new()
	lib.scan()
	if lib.kinds_built() == 0:
		return
	var dead: Array[String] = []
	for kind in PropLibrary.STAND_IN:
		var substitute := str(PropLibrary.STAND_IN[kind])
		if lib.resolve(substitute).is_empty():
			dead.append("%s -> %s" % [kind, substitute])
	assert_true(dead.is_empty(),
		"stand-ins pointing at a kind the forge never built: %s" % ", ".join(dead))
