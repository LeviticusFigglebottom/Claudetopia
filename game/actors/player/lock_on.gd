class_name PlayerLockOn
extends LockOn
## Player-side lock-on input on top of the LockOn targeting service: toggle (lock_on action),
## cycle with the mouse wheel / cycle_target action / right-stick flick.

const FLICK_THRESHOLD := 0.75
const FLICK_RESET := 0.3

var _flick_ready: bool = true


func handle_toggle(origin: Vector3, forward: Vector3) -> void:
	if is_locked():
		clear()
	else:
		acquire(origin, forward)


func handle_wheel(direction: int, origin: Vector3, forward: Vector3) -> void:
	if is_locked():
		cycle(origin, forward, direction)


func handle_cycle_action(origin: Vector3, forward: Vector3) -> void:
	if is_locked():
		cycle(origin, forward, 1)
	else:
		acquire(origin, forward)


## Right-stick flick while locked cycles targets; the stick must return to centre between flicks.
func handle_stick(look: Vector2, origin: Vector3, forward: Vector3) -> void:
	if not is_locked():
		_flick_ready = true
		return
	if _flick_ready and absf(look.x) >= FLICK_THRESHOLD:
		cycle(origin, forward, 1 if look.x > 0.0 else -1)
		_flick_ready = false
	elif absf(look.x) < FLICK_RESET:
		_flick_ready = true
