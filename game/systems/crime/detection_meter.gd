class_name DetectionMeter
extends RefCounted
## Per-observer detection meter (DESIGN §5.13). Rises while the observer can see the target
## by visibility × distance falloff × facing, holds briefly after losing sight, then falls.
## Hearing nudges it up to just under the witness threshold: sound alone never makes a
## witness. Thresholds: 0.35 suspicious, 0.6 witness (counts as seeing a crime), 1.0 detected.

const SUSPICIOUS := 0.35
const WITNESS := 0.6
const DETECTED := 1.0
const RISE_RATE := 0.9
const FALL_RATE := 0.25
const HOLD_SECONDS := 2.0
const PERIPHERAL_FACTOR := 0.5
const PERIPHERAL_EXTRA_DEG := 35.0

var level := 0.0
var last_known_position := Vector3.ZERO
var _hold := 0.0


## 1 inside the sight cone, PERIPHERAL_FACTOR in the peripheral band, 0 behind.
static func facing_factor(facing_dot: float, fov_deg: float) -> float:
	var half := clampf(fov_deg * 0.5, 1.0, 179.0)
	if facing_dot >= cos(deg_to_rad(half)):
		return 1.0
	if facing_dot >= cos(deg_to_rad(minf(half + PERIPHERAL_EXTRA_DEG, 179.0))):
		return PERIPHERAL_FACTOR
	return 0.0


static func distance_falloff(distance: float, sight_range: float) -> float:
	if sight_range <= 0.0 or distance >= sight_range:
		return 0.0
	var r := distance / sight_range
	return clampf(1.0 - r * r, 0.0, 1.0)


## Advances the meter by `delta` seconds. Returns the new level.
func update(delta: float, visibility: float, distance: float, sight_range: float, facing_dot: float, fov_deg: float, has_los: bool, target_position: Vector3 = Vector3.ZERO) -> float:
	var rate := 0.0
	if has_los:
		rate = clampf(visibility, 0.0, 1.0) * distance_falloff(distance, sight_range) * facing_factor(facing_dot, fov_deg) * RISE_RATE
	if rate > 0.0:
		level = minf(DETECTED, level + rate * delta)
		_hold = HOLD_SECONDS
		last_known_position = target_position
	elif _hold > 0.0:
		_hold = maxf(0.0, _hold - delta)
	else:
		level = maxf(0.0, level - FALL_RATE * delta)
	return level


## A sound of `loudness` (0..1) at `distance`. Bumps the meter toward suspicion.
func hear(loudness: float, distance: float, hearing_range: float, source_position: Vector3 = Vector3.ZERO) -> float:
	var radius := minf(hearing_range, Stealth.noise_radius_m(loudness))
	if radius <= 0.0 or distance > radius:
		return level
	var bump := clampf(loudness, 0.0, 1.0) * (1.0 - distance / radius) * 0.5
	var capped := minf(level + bump, WITNESS - 0.01)
	if capped > level:
		level = capped
		last_known_position = source_position
		# Only a noise that actually told them something keeps the meter from falling; an
		# already-alert observer can still be left behind by breaking line of sight.
		_hold = HOLD_SECONDS
	return level


func state() -> String:
	if level >= DETECTED:
		return "detected"
	if level >= WITNESS:
		return "alert"
	if level >= SUSPICIOUS:
		return "suspicious"
	return "unaware"


func is_witness() -> bool:
	return level >= WITNESS


func reset() -> void:
	level = 0.0
	_hold = 0.0
