class_name Migrations
## Save-file migrations. Each step upgrades a save dictionary from version N to N+1.
## Add a new static function and append it to STEPS whenever SaveSystem.SCHEMA_VERSION bumps.
## Steps must be pure (no engine state) so they can be unit-tested with fixtures.

static var STEPS: Array[Callable] = [
	_v1_to_v2,
]


static func migrate(data: Dictionary) -> Dictionary:
	var v := int(data.get("schema_version", 1))
	while v - 1 < STEPS.size():
		var step: Callable = STEPS[v - 1]
		data = step.call(data)
		v += 1
		data["schema_version"] = v
	return data


## v1 -> v2: currency renamed "gold" -> "marks" in the player section; world section gained a
## weather block; clock gained explicit day numbering (v1 stored total hours).
static func _v1_to_v2(data: Dictionary) -> Dictionary:
	var sections: Dictionary = data.get("sections", {})
	if sections.has("player") and sections.player.has("gold"):
		sections.player["marks"] = sections.player["gold"]
		sections.player.erase("gold")
	if sections.has("clock") and sections.clock.has("total_hours"):
		var total: float = float(sections.clock["total_hours"])
		sections.clock = {"time_hours": fmod(total, 24.0), "day": int(total / 24.0) + 1}
	if not sections.has("world"):
		sections["world"] = {}
	if not sections.world.has("weather"):
		sections.world["weather"] = {}
	data["sections"] = sections
	return data
