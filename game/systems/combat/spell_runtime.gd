class_name SpellRuntime
## Pure spell rules (DESIGN §5.3 "Saying"): mana pool, costs, cast times, silence, schools.
## Spell defs: {name, school, cost, cast_type (projectile|self|aura|target|summon), cast_time?,
## range?, speed?, radius?, duration?, effects[], description}. Effect shapes:
##   {"type": "damage", "kind": "fire", "amount": 18, "poise": 10}
##   {"type": "status", "id": "burning", "duration": 4, "magnitude": 3}
##   {"type": "heal", "amount": 30}
##   {"type": "shield", "amount": 40, "duration": 12}
##   {"type": "cleanse", "ids": ["bleeding", "poisoned"]}
##   {"type": "summon", "enemy": "core:enemy/x", "count": 1, "duration": 45, "radius": 2.5}

const SCHOOLS: Array[String] = ["kindling", "hush", "binding", "mending", "calling"]
const CAST_TYPES: Array[String] = ["projectile", "self", "aura", "target", "summon"]
const IMPLEMENTED_CAST_TYPES: Array[String] = ["projectile", "self", "aura", "target", "summon"]
## How long a called thing stays when its spell does not say.
const DEFAULT_SUMMON_SECONDS := 45.0
const SCHOOL_KIND := {"kindling": "fire", "hush": "frost", "binding": "blunt", "mending": "blunt", "calling": "pierce"}
const SCHOOL_COLOR := {"kindling": Color(1.0, 0.55, 0.2), "hush": Color(0.6, 0.85, 1.0), "binding": Color(0.85, 0.75, 0.4), "mending": Color(0.7, 1.0, 0.6), "calling": Color(0.75, 0.6, 0.95)}
const MANA_REGEN_PER_S := 3.0
const MAX_SKILL_DISCOUNT := 0.25   # −25% cost at skill 100
const MAX_SKILL_HASTE := 0.2       # −20% cast time at skill 100
const DEFAULT_CAST_TIME := 0.6
const DEFAULT_RANGE := 25.0
const DEFAULT_SPEED := 22.0
const DEFAULT_RADIUS := 4.0


static func mana_max(will: int) -> float:
	return DamageModel.mana_max(will)


static func school_of(def: Dictionary) -> String:
	return str(def.get("school", "kindling"))


## Skill that gains XP when this spell is cast (schools map 1:1 onto the five magic skills).
static func skill_for(def: Dictionary) -> String:
	return str(def.get("skill", school_of(def)))


static func cost_of(def: Dictionary, skill: float = 0.0) -> float:
	var base := float(def.get("cost", 10.0))
	return base * (1.0 - MAX_SKILL_DISCOUNT * clampf(skill, 0.0, 100.0) / 100.0)


static func cast_time_of(def: Dictionary, skill: float = 0.0) -> float:
	var base := float(def.get("cast_time", DEFAULT_CAST_TIME))
	return maxf(0.05, base * (1.0 - MAX_SKILL_HASTE * clampf(skill, 0.0, 100.0) / 100.0))


static func range_of(def: Dictionary) -> float:
	return float(def.get("range", DEFAULT_RANGE))


static func speed_of(def: Dictionary) -> float:
	return float(def.get("speed", DEFAULT_SPEED))


static func radius_of(def: Dictionary) -> float:
	return float(def.get("radius", DEFAULT_RADIUS))


static func duration_of(def: Dictionary) -> float:
	return float(def.get("duration", 0.0))


static func effects_of(def: Dictionary) -> Array:
	return def.get("effects", [])


static func xp_for(def: Dictionary) -> float:
	return float(def.get("cost", 10.0)) * 0.5


static func clip_for(def: Dictionary, skill: float = 0.0) -> String:
	if def.has("clip"):
		return str(def["clip"])
	return "Cast_Quick" if cast_time_of(def, skill) <= 0.7 else "Cast_Long"


static func color_for(def: Dictionary) -> Color:
	return SCHOOL_COLOR.get(school_of(def), Color.WHITE)


## Whether a cast may start. Returns
## {"ok": bool, "reason": ""|"unknown"|"cast_type"|"not_known"|"busy"|"silenced"|"mana"}.
## `known` is whether this caster has been taught the saying: a saying nobody taught you is
## not castable however the id got into the slot (DESIGN §5.3 — a Saying is something learned).
static func can_cast(def: Dictionary, mana: float, silenced: bool, skill: float = 0.0, busy: bool = false, known: bool = true) -> Dictionary:
	if def.is_empty():
		return {"ok": false, "reason": "unknown"}
	if not IMPLEMENTED_CAST_TYPES.has(str(def.get("cast_type", ""))):
		return {"ok": false, "reason": "cast_type"}
	if not known:
		return {"ok": false, "reason": "not_known"}
	if busy:
		return {"ok": false, "reason": "busy"}
	if silenced:
		return {"ok": false, "reason": "silenced"}
	if mana < cost_of(def, skill):
		return {"ok": false, "reason": "mana"}
	return {"ok": true, "reason": ""}


## Total direct damage of a spell's effects (for previews and tests).
static func direct_damage(def: Dictionary, skill: float = 0.0) -> float:
	var total := 0.0
	for e in effects_of(def):
		if str(e.get("type", "")) == "damage":
			total += float(e.get("amount", 0.0)) * DamageModel.skill_mult(skill)
	return total


## Builds the HitData a spell delivers to a hostile target (damage + status effects).
static func build_hit(def: Dictionary, caster: Node, skill: float = 0.0) -> HitData:
	var h := HitData.new()
	h.attacker = caster
	h.kind = str(SCHOOL_KIND.get(school_of(def), "fire"))
	h.parryable = false
	h.skill_id = skill_for(def)
	h.label = "spell:" + Ids.name_of(str(def.get("id", "core:spell/unknown")))
	for e in effects_of(def):
		match str(e.get("type", "")):
			"damage":
				h.amount += float(e.get("amount", 0.0)) * DamageModel.skill_mult(skill)
				h.poise_damage += float(e.get("poise", 0.0))
				if e.has("kind"):
					h.kind = str(e["kind"])
			"status":
				h.statuses.append({"id": str(e.get("id", "burning")), "duration": float(e.get("duration", 0.0)), "magnitude": float(e.get("magnitude", 0.0))})
	return h


static func heal_amount(effect: Dictionary, skill: float = 0.0) -> float:
	return float(effect.get("amount", 0.0)) * DamageModel.skill_mult(skill)
