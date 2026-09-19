class_name StaminaComponent
extends Node
## Stamina pool: drains per action, regenerates 30/s after 0.8 s (DESIGN §5.3).
## Pure enough to unit test: call advance(delta) yourself when there is no scene tree.

signal changed(current: float, maximum: float)
signal exhausted

var maximum: float = 100.0
var current: float = 100.0
var regen_per_s: float = DamageModel.STAMINA_REGEN_PER_S
var regen_delay: float = DamageModel.STAMINA_REGEN_DELAY
## Blocking or being over-encumbered slows regeneration (owner sets this each frame).
var regen_multiplier: float = 1.0
var auto_advance: bool = true

var _delay_left: float = 0.0


func setup(new_maximum: float, fill: bool = true) -> void:
	maximum = maxf(new_maximum, 1.0)
	if fill:
		current = maximum
	else:
		current = minf(current, maximum)
	changed.emit(current, maximum)


func _physics_process(delta: float) -> void:
	if auto_advance:
		advance(delta)


func advance(delta: float) -> void:
	if _delay_left > 0.0:
		_delay_left = maxf(_delay_left - delta, 0.0)
		return
	if current < maximum:
		current = minf(maximum, current + regen_per_s * regen_multiplier * delta)
		changed.emit(current, maximum)


## An action can start while there is any stamina left; the cost may push it to 0 (Souls rule).
func can_afford(_cost: float) -> bool:
	return current > 0.0


func try_spend(cost: float) -> bool:
	if not can_afford(cost):
		return false
	spend(cost)
	return true


func spend(cost: float) -> void:
	if cost <= 0.0:
		return
	current = maxf(0.0, current - cost)
	_delay_left = regen_delay
	changed.emit(current, maximum)
	if current <= 0.0:
		exhausted.emit()


## Continuous drain (sprint): rate per second, applied for delta. Returns false when empty.
func drain(rate_per_s: float, delta: float) -> bool:
	if current <= 0.0:
		return false
	spend(rate_per_s * delta)
	return current > 0.0


func restore(amount: float) -> void:
	current = clampf(current + amount, 0.0, maximum)
	changed.emit(current, maximum)


func refill() -> void:
	current = maximum
	_delay_left = 0.0
	changed.emit(current, maximum)


func is_exhausted() -> bool:
	return current <= 0.0


func is_regenerating() -> bool:
	return _delay_left <= 0.0 and current < maximum


func ratio() -> float:
	return current / maximum if maximum > 0.0 else 0.0


func to_save() -> Dictionary:
	return {"current": current, "maximum": maximum}


func from_save(d: Dictionary) -> void:
	maximum = float(d.get("maximum", maximum))
	current = clampf(float(d.get("current", maximum)), 0.0, maximum)
	changed.emit(current, maximum)
