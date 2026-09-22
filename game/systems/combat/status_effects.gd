class_name StatusEffects
extends Node
## Status effects on one actor (DESIGN §5.3): burning, chilled, bleeding, poisoned, silenced,
## quieted, stagger, knockdown (+ warded as a visible marker for a Binding shield).
## Rules (durations, ticks, stacking) live in RULES; the owner reads speed_multiplier(),
## blocks_actions(), blocks_casting() and listens to damage_tick for damage over time.
## Pure enough for tests: call advance(delta) without a scene tree.

signal applied(id: String, stacks: int)
signal expired(id: String)
signal damage_tick(id: String, amount: float, kind: String)
signal renown_tick(amount: float)

## stacking: refresh (restart duration), stack (add a stack up to max_stacks and restart),
## extend (add duration up to max_duration), ignore (do nothing while active or immune).
const RULES := {
	"burning": {"duration": 4.0, "tick": 0.5, "dps": 3.0, "kind": "fire", "stacking": "refresh"},
	"chilled": {"duration": 5.0, "speed_mult": 0.6, "stacking": "refresh"},
	"webbed": {"duration": 5.0, "speed_mult": 0.45, "stacking": "refresh"},
	"bleeding": {"duration": 6.0, "tick": 1.0, "dps": 2.0, "kind": "slash", "stacking": "stack", "max_stacks": 3},
	"poisoned": {"duration": 10.0, "tick": 1.0, "dps": 1.5, "kind": "poison", "stacking": "extend", "max_duration": 30.0},
	"silenced": {"duration": 6.0, "blocks_casting": true, "stacking": "refresh"},
	"quieted": {"duration": 30.0, "tick": 5.0, "renown_drain": 1.0, "stacking": "refresh"},
	"stagger": {"duration": 0.8, "blocks_actions": true, "stacking": "refresh"},
	"knockdown": {"duration": 1.6, "blocks_actions": true, "stacking": "ignore", "immunity": 1.5},
	"warded": {"duration": 12.0, "stacking": "refresh"},
}

## The actor this belongs to (used for EventBus.status_applied; may stay null in tests).
var actor: Node = null
var auto_advance: bool = true
## id -> {"remaining": float, "duration": float, "magnitude": float, "stacks": int, "tick_left": float}
var active: Dictionary = {}
var _immune: Dictionary = {}   # id -> seconds of immunity left


func _physics_process(delta: float) -> void:
	if auto_advance:
		advance(delta)


static func rule(id: String) -> Dictionary:
	return RULES.get(id, {"duration": 5.0, "stacking": "refresh"})


## Applies (or stacks/refreshes) an effect. duration/magnitude <= 0 mean "use the rule".
## Returns false when the effect was ignored (already active with "ignore" stacking, or immune).
func apply(id: String, duration: float = -1.0, magnitude: float = -1.0, _source: Node = null) -> bool:
	var r := rule(id)
	if _immune.get(id, 0.0) > 0.0:
		return false
	var dur: float = duration if duration > 0.0 else float(r.get("duration", 5.0))
	var mag: float = magnitude if magnitude > 0.0 else float(r.get("dps", 0.0))
	var stacking := str(r.get("stacking", "refresh"))
	if active.has(id):
		var e: Dictionary = active[id]
		match stacking:
			"ignore":
				return false
			"stack":
				e["stacks"] = mini(int(e["stacks"]) + 1, int(r.get("max_stacks", 3)))
				e["remaining"] = maxf(float(e["remaining"]), dur)
			"extend":
				e["remaining"] = minf(float(e["remaining"]) + dur, float(r.get("max_duration", dur * 3.0)))
			_:
				e["remaining"] = maxf(float(e["remaining"]), dur)
		e["magnitude"] = maxf(float(e["magnitude"]), mag)
		e["duration"] = maxf(float(e["duration"]), float(e["remaining"]))
		applied.emit(id, int(e["stacks"]))
	else:
		active[id] = {"remaining": dur, "duration": dur, "magnitude": mag, "stacks": 1, "tick_left": float(r.get("tick", 0.0))}
		applied.emit(id, 1)
	if actor != null and Engine.get_main_loop() != null and Engine.get_main_loop().root.has_node("EventBus"):
		EventBus.status_applied.emit(actor, id)
	return true


func advance(delta: float) -> void:
	for id in _immune.keys():
		_immune[id] = float(_immune[id]) - delta
		if _immune[id] <= 0.0:
			_immune.erase(id)
	for id in active.keys():
		# A tick or an expiry earlier in this loop can end another effect (a burn that kills, a
		# handler that clears stagger); the keys were copied before the loop, the entries were not.
		if not active.has(id):
			continue
		var e: Dictionary = active[id]
		var r := rule(id)
		var tick := float(r.get("tick", 0.0))
		if tick > 0.0:
			e["tick_left"] = float(e["tick_left"]) - delta
			while float(e["tick_left"]) <= 0.0:
				e["tick_left"] = float(e["tick_left"]) + tick
				_fire_tick(id, e, r, tick)
		e["remaining"] = float(e["remaining"]) - delta
		if float(e["remaining"]) <= 0.0:
			active.erase(id)
			var imm := float(r.get("immunity", 0.0))
			if imm > 0.0:
				_immune[id] = imm
			expired.emit(id)


func _fire_tick(id: String, e: Dictionary, r: Dictionary, tick: float) -> void:
	if r.has("dps"):
		var dps: float = float(e["magnitude"]) if float(e["magnitude"]) > 0.0 else float(r["dps"])
		damage_tick.emit(id, dps * tick * float(e["stacks"]), str(r.get("kind", "poison")))
	if r.has("renown_drain"):
		renown_tick.emit(float(r["renown_drain"]))


func has(id: String) -> bool:
	return active.has(id)


func remaining(id: String) -> float:
	return float(active[id]["remaining"]) if active.has(id) else 0.0


func stacks(id: String) -> int:
	return int(active[id]["stacks"]) if active.has(id) else 0


func magnitude(id: String) -> float:
	return float(active[id]["magnitude"]) if active.has(id) else 0.0


func is_immune(id: String) -> bool:
	return _immune.get(id, 0.0) > 0.0


func clear(id: String) -> void:
	if active.erase(id):
		expired.emit(id)


func clear_many(ids: Array) -> void:
	for id in ids:
		clear(str(id))


func clear_all() -> void:
	for id in active.keys():
		clear(id)
	_immune.clear()


func active_ids() -> Array[String]:
	var out: Array[String] = []
	for id in active.keys():
		out.append(str(id))
	out.sort()
	return out


## Product of all active speed multipliers (chilled = 0.6).
func speed_multiplier() -> float:
	var m := 1.0
	for id in active.keys():
		m *= float(rule(id).get("speed_mult", 1.0))
	return m


func blocks_actions() -> bool:
	for id in active.keys():
		if bool(rule(id).get("blocks_actions", false)):
			return true
	return false


func blocks_casting() -> bool:
	for id in active.keys():
		if bool(rule(id).get("blocks_casting", false)):
			return true
	return false


func to_save() -> Dictionary:
	var out := {}
	for id in active.keys():
		var e: Dictionary = active[id]
		out[id] = {"remaining": e["remaining"], "magnitude": e["magnitude"], "stacks": e["stacks"]}
	return {"active": out}


func from_save(d: Dictionary) -> void:
	active.clear()
	_immune.clear()
	var saved: Dictionary = d.get("active", {})
	for id in saved.keys():
		var e: Dictionary = saved[id]
		var r := rule(id)
		active[id] = {"remaining": float(e.get("remaining", 1.0)), "duration": float(e.get("remaining", 1.0)), "magnitude": float(e.get("magnitude", 0.0)), "stacks": int(e.get("stacks", 1)), "tick_left": float(r.get("tick", 0.0))}
