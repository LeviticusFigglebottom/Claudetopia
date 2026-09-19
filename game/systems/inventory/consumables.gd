class_name Consumables
## What eating or drinking a thing actually does (CONTRACTS §7 `effect` defs). Pure rules, so
## they can be read and tested without a body.
##
## An effect entry off an item is `{effect, magnitude, duration}`; the effect def says what kind
## of thing it is:
##   instant  — `stat` (health|stamina|mana) moves by `magnitude` at once
##   buff     — `modifier{stat, op, scale}` for `duration` seconds
##   harm     — `status` applied for `duration` at `magnitude` a second
## and any effect may carry `cures[]`, which clears those statuses outright.
##
## Nothing here reaches for a node: `plan()` turns a list of entries into a list of small
## instructions, and the actor carries them out.

## Stat names an instant effect may move, and the actor method that moves each one.
const STAT_METHOD := {"health": "heal", "stamina": "restore_stamina", "mana": "restore_mana"}


## Turns the entries an item carries into instructions:
##   {"kind": "stat", "stat": "health", "amount": 20.0}
##   {"kind": "modifier", "source": "core:effect/x", "mods": [...], "duration": 60.0}
##   {"kind": "status", "id": "poisoned", "duration": 8.0, "magnitude": 5.0}
##   {"kind": "cure", "ids": ["poisoned"]}
static func plan(entries: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in entries:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = e
		var def := ContentDB.get_or_empty(str(entry.get("effect", "")))
		if def.is_empty():
			continue
		var magnitude := float(entry.get("magnitude", def.get("magnitude_base", 0.0)))
		var duration := float(entry.get("duration", def.get("duration_base", 0.0)))
		var cures: Array = def.get("cures", [])
		if not cures.is_empty():
			out.append({"kind": "cure", "ids": cures.duplicate()})
		match str(def.get("kind", "")):
			"instant":
				var stat := str(def.get("stat", ""))
				if STAT_METHOD.has(stat) and not is_zero_approx(magnitude):
					out.append({"kind": "stat", "stat": stat, "amount": magnitude})
			"buff":
				var mod: Dictionary = def.get("modifier", {})
				if mod.is_empty():
					continue
				var scale := float(mod.get("scale", 1.0))
				var m := {"stat": str(mod.get("stat", "")), "source": str(def.get("name", ""))}
				if str(mod.get("op", "add")) == "mult":
					m["mult"] = 1.0 + magnitude * scale
				else:
					m["add"] = magnitude * scale
				out.append({"kind": "modifier", "source": str(def.get("id", "")), "mods": [m],
						"duration": maxf(duration, 1.0)})
			"harm":
				var status := str(def.get("status", ""))
				if status != "":
					out.append({"kind": "status", "id": status, "duration": maxf(duration, 1.0),
							"magnitude": magnitude})
	return out
