class_name PoiseComponent
extends Node
## Poise: attacks deal poise damage; regen 4/s after 1.5 s; at 0 the owner staggers and poise
## resets to max (DESIGN §5.3). Hyper-armour frames ignore poise damage below a threshold.

signal changed(current: float, maximum: float)
signal broken

var maximum: float = 40.0
var current: float = 40.0
var regen_per_s: float = DamageModel.POISE_REGEN_PER_S
var regen_delay: float = DamageModel.POISE_REGEN_DELAY
## > 0 while the owner is in hyper-armour frames: hits with less poise damage than this are ignored.
var hyper_armour_threshold: float = 0.0
var auto_advance: bool = true

var _delay_left: float = 0.0


func setup(new_maximum: float) -> void:
	maximum = maxf(new_maximum, 1.0)
	current = maximum
	changed.emit(current, maximum)


func _physics_process(delta: float) -> void:
	if auto_advance:
		advance(delta)


func advance(delta: float) -> void:
	if _delay_left > 0.0:
		_delay_left = maxf(_delay_left - delta, 0.0)
		return
	if current < maximum:
		current = minf(maximum, current + regen_per_s * delta)
		changed.emit(current, maximum)


## Applies poise damage. Returns true when poise broke (the owner must stagger).
func apply(amount: float, heavy: bool = false) -> bool:
	var dealt := DamageModel.poise_damage(amount, heavy, hyper_armour_threshold)
	if dealt <= 0.0:
		return false
	current = maxf(0.0, current - dealt)
	_delay_left = regen_delay
	changed.emit(current, maximum)
	if current <= 0.0:
		current = maximum
		broken.emit()
		return true
	return false


func set_hyper_armour(threshold: float) -> void:
	hyper_armour_threshold = maxf(threshold, 0.0)


func clear_hyper_armour() -> void:
	hyper_armour_threshold = 0.0


func has_hyper_armour() -> bool:
	return hyper_armour_threshold > 0.0


func reset() -> void:
	current = maximum
	_delay_left = 0.0
	changed.emit(current, maximum)


func ratio() -> float:
	return current / maximum if maximum > 0.0 else 0.0


func to_save() -> Dictionary:
	return {"current": current, "maximum": maximum}


func from_save(d: Dictionary) -> void:
	maximum = float(d.get("maximum", maximum))
	current = clampf(float(d.get("current", maximum)), 0.0, maximum)
