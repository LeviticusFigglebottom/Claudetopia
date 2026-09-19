class_name WorldProbe
## Graceful access to the world stream's static accessor (`World.get_height(x, z)`,
## `World.region_id_at(pos)`). The World class is looked up by name at runtime so this code
## compiles before it exists. Fallbacks: region base height from the region def, and the
## nearest region by its map centre/radius. Also holds the small geometry helpers every
## system needs (cell indices per CONTRACTS §6, place positions, region law lookup).

const CELL_SIZE_M := 256.0
const WORLD_HALF_M := 4096.0

static var _world_script: Script = null
static var _looked_up := false


static func _world() -> Script:
	if _looked_up:
		return _world_script
	_looked_up = true
	for c in ProjectSettings.get_global_class_list():
		if str(c.get("class", "")) == "World":
			var s: Variant = load(str(c["path"]))
			if s is Script:
				_world_script = s
			break
	return _world_script


static func reset_cache() -> void:
	_looked_up = false
	_world_script = null


static func has_world() -> bool:
	var w := _world()
	return w != null and w.has_method("get_height")


static func get_height(x: float, z: float, fallback: float = NAN) -> float:
	var w := _world()
	if w != null and w.has_method("get_height"):
		var v: Variant = w.call("get_height", x, z)
		if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
			return float(v)
	if not is_nan(fallback):
		return fallback
	var rid := region_id_at(Vector3(x, 0.0, z))
	var r := ContentDB.get_or_empty(rid)
	return float(r.get("map", {}).get("base_height", 0.0))


static func region_id_at(pos: Vector3) -> String:
	var w := _world()
	if w != null and w.has_method("region_id_at"):
		var v: Variant = w.call("region_id_at", pos)
		if typeof(v) == TYPE_STRING and not str(v).is_empty():
			return str(v)
	return nearest_region_id(pos)


## Region whose map centre is nearest in units of its own radius.
static func nearest_region_id(pos: Vector3) -> String:
	var best := ""
	var best_score := INF
	for r in ContentDB.all("region"):
		var m: Dictionary = r.get("map", {})
		var c: Array = m.get("center", [0, 0])
		var radius := maxf(float(m.get("radius", 1000.0)), 1.0)
		var d := Vector2(pos.x - float(c[0]), pos.z - float(c[1])).length() / radius
		if d < best_score:
			best_score = d
			best = r["id"]
	return best


static func cell_of(pos: Vector3) -> Vector2i:
	return Vector2i(floori((pos.x + WORLD_HALF_M) / CELL_SIZE_M), floori((pos.z + WORLD_HALF_M) / CELL_SIZE_M))


static func place_position(place_id: String) -> Vector3:
	var p := ContentDB.get_or_empty(place_id)
	var xz: Array = p.get("position", [0, 0])
	var x := float(xz[0]) if xz.size() > 0 else 0.0
	var z := float(xz[1]) if xz.size() > 1 else 0.0
	return Vector3(x, get_height(x, z), z)


static func cell_of_place(place_id: String) -> Vector2i:
	return cell_of(place_position(place_id))


static func region_of_place(place_id: String) -> String:
	return str(ContentDB.get_or_empty(place_id).get("region", ""))


## Nearest place def to a position (any kind), or {} when no places exist.
static func nearest_place(pos: Vector3, max_distance_m: float = INF) -> Dictionary:
	var best: Dictionary = {}
	var best_d := max_distance_m
	for p in ContentDB.all("place"):
		var xz: Array = p.get("position", [0, 0])
		var d := Vector2(pos.x - float(xz[0]), pos.z - float(xz[1])).length()
		if d < best_d:
			best_d = d
			best = p
	return best


## Law of a region: {faction_id, law{region, jail_place, arrest_threshold, fine_multiplier,
## jail_days_per_100, style}}. style is "none" and faction_id "" in lawless regions.
static func law_of_region(region_id: String) -> Dictionary:
	var r := ContentDB.get_or_empty(region_id)
	var fid := str(r.get("law_faction", ""))
	if fid.is_empty():
		return {"faction_id": "", "law": {"style": "none", "region": region_id, "arrest_threshold": 0, "fine_multiplier": 0.0, "jail_days_per_100": 0, "jail_place": ""}}
	var f := ContentDB.get_or_empty(fid)
	var law: Dictionary = f.get("law", {}).duplicate()
	if not law.has("style"):
		law["style"] = "fine_or_jail"
	if not law.has("region"):
		law["region"] = region_id
	return {"faction_id": fid, "law": law}


## Culture label of a region as a short key: vale, lakefolk, reedfolk, clans, woodfolk, pilgrims.
static func culture_key(region_id: String) -> String:
	var c := str(ContentDB.get_or_empty(region_id).get("culture", "")).to_lower()
	if c.contains("vale"):
		return "vale"
	if c.contains("lake"):
		return "lakefolk"
	if c.contains("reed"):
		return "reedfolk"
	if c.contains("clan") or c.contains("skerrow"):
		return "clans"
	if c.contains("wood"):
		return "woodfolk"
	if c.contains("pilgrim") or c.contains("ash"):
		return "pilgrims"
	return c


static func culture_of_place(place_id: String) -> String:
	return culture_key(region_of_place(place_id))
