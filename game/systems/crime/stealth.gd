class_name Stealth
extends Node
## Stealth service (DESIGN §5.13): light level at a point (sun through sky exposure and
## weather, plus registered StealthLight sources), movement noise, visibility, sneak-attack
## multipliers, pickpocket and lockpick models. The maths is static and pure; the node adds
## the world sampling (shadow raycast, weather, registered lights, the player's state).

static var instance: Stealth

const MOONLIGHT := 0.06
const SHADOW_FACTOR := 0.35
const SUN_RAY_M := 200.0
const WALK_SPEED := 4.2
const RUN_SPEED := 6.5
const MAX_NOISE_RADIUS_M := 30.0
const WEATHER_LIGHT := {
	"clear": 1.0, "clear_cold": 1.0, "thin_sun": 0.8, "still": 0.9, "wind": 0.95, "dry_wind": 0.9, "breezy": 0.9,
	"overcast": 0.7, "still_grey": 0.7, "rain": 0.5, "drizzle": 0.6, "squall": 0.45, "storm": 0.35,
	"fog": 0.4, "mist": 0.6, "snow": 0.8, "ashfall": 0.5,
}
const NOISE_WEIGHT := {"none": 0.9, "light": 1.0, "medium": 1.3, "heavy": 1.7}
const NOISE_SURFACE := {
	"grass": 0.8, "dirt": 0.9, "mud": 0.9, "peat": 0.8, "sand": 0.75, "snow": 0.7, "ash": 0.85,
	"stone": 1.0, "cobbles": 1.05, "wood": 1.2, "shingle": 1.3, "gravel": 1.3, "scree": 1.3, "water": 1.4,
}
const LOCK_LEVEL_NAMES: Array[String] = ["open", "simple", "sturdy", "clever", "guild", "oroth"]

var weather_factor := 1.0
var raining := false
var sky_exposure_override := -1.0   # tests and interiors: 0..1 forces the value
var lights: Array[Node3D] = []
var _visibility_cached := 0.0
var _visibility_frame := -1


static func ensure() -> Stealth:
	if instance != null and is_instance_valid(instance):
		return instance
	return Service.ensure(load("res://systems/crime/stealth.gd"), "Stealth") as Stealth


func _enter_tree() -> void:
	instance = self
	add_to_group("stealth")


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	EventBus.weather_changed.connect(_on_weather_changed)


func _on_weather_changed(region_id: String, weather_id: String) -> void:
	if GameState.current_region_id.is_empty() or region_id == GameState.current_region_id:
		set_weather(weather_id)


func set_weather(weather_id: String) -> void:
	weather_factor = float(WEATHER_LIGHT.get(weather_id, 0.8))
	raining = Schedules.is_rainy(weather_id)


func register_light(light: Node3D) -> void:
	if not light in lights:
		lights.append(light)


func unregister_light(light: Node3D) -> void:
	lights.erase(light)


# --- light ---------------------------------------------------------------------------------

## Sun contribution 0..1: moonlight floor plus daylight × sky exposure × weather.
static func sun_light(daylight: float, sky_exposure: float, weather_factor_: float = 1.0) -> float:
	var d := clampf(daylight, 0.0, 1.0) * clampf(sky_exposure, 0.0, 1.0) * clampf(weather_factor_, 0.0, 1.0)
	return clampf(MOONLIGHT + d * (1.0 - MOONLIGHT), 0.0, 1.0)


## Local light at `pos` from sources [{position: Vector3, range: float, energy: float}].
static func local_light(pos: Vector3, sources: Array) -> float:
	var total := 0.0
	for s in sources:
		var r := float(s.get("range", 0.0))
		if r <= 0.0:
			continue
		var d := pos.distance_to(s.get("position", Vector3.ZERO))
		if d >= r:
			continue
		var f := 1.0 - d / r
		total += float(s.get("energy", 1.0)) * f * f
	return clampf(total, 0.0, 1.0)


## Screen-blend of sun and local light.
static func combine_light(sun: float, local: float) -> float:
	return clampf(sun + local * (1.0 - sun), 0.0, 1.0)


## Direction to the sun for the clock time: rises east (+x), noon south (+z), sets west.
static func sun_direction(time_hours: float, elevation_deg: float) -> Vector3:
	var t := time_hours / 24.0 * TAU
	var el := deg_to_rad(elevation_deg)
	return Vector3(sin(t) * cos(el), sin(el), -cos(t) * cos(el)).normalized()


func light_sources() -> Array:
	var out: Array = []
	for l in lights:
		if is_instance_valid(l) and l.has_method("source"):
			var s: Dictionary = l.call("source")
			if not s.is_empty():
				out.append(s)
	return out


## 0 fully shadowed/indoors, 1 open sky. Raycasts toward the sun when a physics world exists.
func sky_exposure(pos: Vector3) -> float:
	if sky_exposure_override >= 0.0:
		return clampf(sky_exposure_override, 0.0, 1.0)
	if not GameState.current_interior_id.is_empty():
		return 0.0
	if not is_inside_tree() or WorldClock.daylight() <= 0.001:
		return 1.0
	var world := get_viewport().find_world_3d() if get_viewport() != null else null
	if world == null:
		return 1.0
	var space := world.direct_space_state
	if space == null:
		return 1.0
	var dir := sun_direction(WorldClock.time_hours, WorldClock.sun_elevation_deg())
	if dir.y <= 0.0:
		return 1.0
	var from := pos + Vector3.UP * 1.5
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * SUN_RAY_M)
	query.collision_mask = 1 | (1 << 10)   # world and terrain layers
	var hit := space.intersect_ray(query)
	return SHADOW_FACTOR if not hit.is_empty() else 1.0


func light_level(pos: Vector3) -> float:
	var sun := sun_light(WorldClock.daylight(), sky_exposure(pos), weather_factor)
	return combine_light(sun, local_light(pos, light_sources()))


# --- noise and visibility ----------------------------------------------------------------

static func noise_level(speed_mps: float, weight_class: String = "light", crouched: bool = false, surface: String = "", raining_: bool = false) -> float:
	var base := pow(clampf(speed_mps / RUN_SPEED, 0.0, 1.0), 1.5)
	var n := base * float(NOISE_WEIGHT.get(weight_class, 1.0)) * float(NOISE_SURFACE.get(surface, 1.0))
	if crouched:
		n *= 0.5
	if raining_:
		n *= 0.7
	return clampf(n, 0.0, 1.0)


static func noise_radius_m(noise: float) -> float:
	return clampf(noise, 0.0, 1.0) * MAX_NOISE_RADIUS_M


## How visible the player is 0..1 from light, noise, crouching and Sneak skill.
static func visibility(light: float, noise: float, crouched: bool, sneak_skill: int) -> float:
	var v := (0.1 + 0.7 * clampf(light, 0.0, 1.0)) * (0.55 if crouched else 1.0) * (1.0 - 0.5 * clampf(float(sneak_skill), 0.0, 100.0) / 100.0)
	v += 0.3 * clampf(noise, 0.0, 1.0)
	return clampf(v, 0.02, 1.0)


# --- sneak attacks ------------------------------------------------------------------------

## ×3 on an unaware target, ×6 with a dagger, ×1 once the target is alert (detection >= 0.6).
static func sneak_multiplier_for(weapon_class: String, target_awareness: float) -> float:
	if target_awareness >= DetectionMeter.WITNESS:
		return 1.0
	return 6.0 if weapon_class == "dagger" else 3.0


func sneak_multiplier(attacker: Node, target: Node) -> float:
	return sneak_multiplier_for(weapon_class_of(attacker), awareness_of(target))


## Target awareness: its `detection` property, its perception child's, or 1 (aware) if none.
static func awareness_of(target: Object) -> float:
	if target == null or not is_instance_valid(target):
		return 1.0
	if "detection" in target:
		return float(target.get("detection"))
	var perception: Variant = target.get("perception")
	if perception is Object and "detection" in perception:
		return float(perception.get("detection"))
	if target is Node:
		var p := (target as Node).get_node_or_null("Perception")
		if p != null and "detection" in p:
			return float(p.get("detection"))
	return 1.0


## Weapon class of an attacker: get_weapon_class(), `weapon_class`, or the main-hand item's
## weapon.clips_set/class via an Equipment object exposing main_hand()/equipped(slot).
static func weapon_class_of(attacker: Object) -> String:
	if attacker == null or not is_instance_valid(attacker):
		return "unarmed"
	if attacker.has_method("get_weapon_class"):
		return str(attacker.call("get_weapon_class"))
	if "weapon_class" in attacker:
		return str(attacker.get("weapon_class"))
	var item_id := ""
	var eq: Variant = attacker.get("equipment")
	if eq is Object:
		if eq.has_method("main_hand"):
			item_id = str(eq.call("main_hand"))
		elif eq.has_method("equipped"):
			item_id = str(eq.call("equipped", "main_hand"))
	if item_id.is_empty() and "main_hand" in attacker:
		item_id = str(attacker.get("main_hand"))
	if item_id.is_empty() or not ContentDB.has(item_id):
		return "unarmed"
	var w: Dictionary = ContentDB.get_or_empty(item_id).get("weapon", {})
	return str(w.get("clips_set", w.get("class", "unarmed"))).to_lower()


# --- pickpocket and locks ---------------------------------------------------------------

static func pickpocket_chance(sneak_skill: int, target_awareness: float, item_value: int) -> float:
	var c := 0.30 + 0.6 * clampf(float(sneak_skill), 0.0, 100.0) / 100.0 - 0.5 * clampf(target_awareness, 0.0, 1.0) - minf(0.4, float(item_value) / 500.0)
	return clampf(c, 0.02, 0.95)


static func pickpocket_roll(chance: float, rng: RandomNumberGenerator) -> bool:
	return rng.randf() < chance


## Resolves a pickpocket attempt end to end: rolls, moves the item, records the crime
## (a failed attempt is seen by the victim, so it is always witnessed), and grants Sneak XP.
## Returns {ok, chance, caught, item_id}. `rng` lets tests fix the outcome.
func pickpocket(thief: Node, victim: Node, item_id: String, rng: RandomNumberGenerator = null) -> Dictionary:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var value := ContentQuery.item_value(item_id)
	var chance := pickpocket_chance(Peers.skill_level("sneak"), awareness_of(victim), value)
	var ok := pickpocket_roll(chance, rng)
	var victim_id := str(victim.get("npc_id")) if victim != null and "npc_id" in victim else ""
	var pos := (victim as Node3D).global_position if victim is Node3D else Vector3.ZERO
	if ok and Peers.inventory_of(thief) == null:
		# Nowhere to put it: better to fumble than to make the item vanish.
		ok = false
	EventBus.skill_used.emit("sneak", 6.0 + float(value) * 0.05)
	if ok:
		if not Peers.take_item(victim, item_id, 1):
			return {"ok": false, "chance": chance, "caught": false, "item_id": item_id}
		if not Peers.give_item(thief, item_id, 1):
			Peers.give_item(victim, item_id, 1)   # put it back rather than destroy it
			ok = false
	if ok:
		EventBus.notify.emit("Taken.", "stealth")
	else:
		EventBus.notify.emit("A hand closes on your wrist.", "stealth")
		if victim != null and "detection" in victim:
			victim.set("detection", 1.0)
	# `ensure()` rather than `instance`: a pickpocketing that goes unrecorded because the
	# ledger happened not to be up is the silence this whole area keeps producing.
	var ledger := Bounty.ensure()
	if ledger != null:
		var opts := {"victim": victim_id, "target": item_id, "value": value}
		if not ok and not victim_id.is_empty():
			# Caught in the act: the victim witnesses it whatever else they were doing, and
			# so does anyone else with a view — `extra_witnesses` adds to the usual scan.
			opts["extra_witnesses"] = [{"npc_id": victim_id, "detection": 1.0, "line_of_sight": true, "is_guard": victim is Node and (victim as Node).is_in_group("guard"), "reaction": "report"}]
		ledger.commit("pickpocket", pos, opts)
	return {"ok": ok, "chance": chance, "caught": not ok, "item_id": item_id}


## Width of the timing sweet spot 0..1 for a Sneak skill against a lock level 1..5.
static func lockpick_window(skill: int, lock_level: int) -> float:
	return clampf(0.35 + float(skill) / 250.0 - float(lock_level) * 0.06, 0.03, 0.6)


## timing_accuracy: 0 = dead centre of the sweet spot, 1 = as far off as possible.
## Returns {success, broke, window, margin}. Misses beyond window + tolerance snap the pick.
static func lockpick_attempt(skill: int, lock_level: int, timing_accuracy: float) -> Dictionary:
	var window := lockpick_window(skill, lock_level)
	var miss := clampf(timing_accuracy, 0.0, 1.0)
	if miss <= window:
		return {"success": true, "broke": false, "window": window, "margin": window - miss}
	var break_at := window + 0.25 + float(skill) / 400.0
	return {"success": false, "broke": miss > break_at, "window": window, "margin": window - miss}


static func lock_level_name(level: int) -> String:
	return LOCK_LEVEL_NAMES[clampi(level, 0, LOCK_LEVEL_NAMES.size() - 1)]


# --- the player ------------------------------------------------------------------------------

static func is_crouched(actor: Object) -> bool:
	if actor == null or not is_instance_valid(actor):
		return false
	for key in ["crouched", "is_sneaking", "sneaking", "is_crouched"]:
		if key in actor:
			return bool(actor.get(key))
	if actor.has_method("is_sneaking"):
		return bool(actor.call("is_sneaking"))
	return false


static func speed_of(actor: Object) -> float:
	if actor == null or not is_instance_valid(actor):
		return 0.0
	if "velocity" in actor:
		var v: Variant = actor.get("velocity")
		if v is Vector3:
			return Vector3(v.x, 0.0, v.z).length()
	return 0.0


static func armour_weight_class(actor: Object) -> String:
	if actor == null or not is_instance_valid(actor):
		return "light"
	if "weight_class" in actor:
		return str(actor.get("weight_class"))
	var eq: Variant = actor.get("equipment")
	if eq is Object:
		if eq.has_method("weight_class"):
			return str(eq.call("weight_class"))
		if "weight_class" in eq:
			return str(eq.get("weight_class"))
	return "light"


static func surface_of(actor: Object) -> String:
	if actor != null and is_instance_valid(actor) and "surface" in actor:
		return str(actor.get("surface"))
	return ""


func player_noise() -> float:
	var p := Peers.player()
	if p == null:
		return 0.0
	return noise_level(speed_of(p), armour_weight_class(p), is_crouched(p), surface_of(p), raining)


func player_light() -> float:
	var p := Peers.player()
	if p == null or not (p is Node3D):
		return sun_light(WorldClock.daylight(), 1.0, weather_factor)
	return light_level((p as Node3D).global_position)


## How visible the player is right now. Every observer asks this every physics frame and the
## answer is a property of the player, not of the asker, so it is computed once per frame
## (the light sample alone costs a raycast).
func player_visibility() -> float:
	var frame := Engine.get_physics_frames()
	if frame == _visibility_frame:
		return _visibility_cached
	var p := Peers.player()
	_visibility_cached = 0.0 if p == null else visibility(player_light(), player_noise(), is_crouched(p), Peers.skill_level("sneak"))
	_visibility_frame = frame
	return _visibility_cached
