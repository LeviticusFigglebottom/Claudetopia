class_name HitData
extends RefCounted
## One hit travelling from a Hitbox/Projectile/Spell to a Hurtbox. Plain data, copied per swing.
## `amount` is the attacker-side damage (weapon · skill · attack mult · charge); the victim applies
## crit, block, armour and resist in Actor.take_hit().

var amount: float = 0.0
var kind: String = "slash"
var poise_damage: float = 0.0
var heavy: bool = false
var attacker: Node = null            # the Actor responsible (may be null for hazards)
var source: Node = null              # hitbox / projectile / caster that delivered it
var swing_id: int = 0
var origin: Vector3 = Vector3.ZERO   # where the hit came from, for facing checks
var crit_kind: String = ""           # "", "riposte", "backstab", "sneak"
var crit_mult: float = 1.0
var blockable: bool = true
var parryable: bool = true
var dodgeable: bool = true
var knockdown: bool = false
var knockback: float = 0.0           # metres of shove along the hit direction
var statuses: Array = []             # [{"id": "bleeding", "duration": 6.0, "magnitude": 1.0}]
var skill_id: String = ""            # skill that gains XP when this lands
var label: String = ""               # attack name, for logs and tests
## What struck: the weapon's class ("sword", "greatsword", "claw" ...) and its weight in kg (0 when
## no item says), for how the blow lands on the eye and the ear (Impact), not for the numbers.
var weapon_class: String = ""
var weight: float = 0.0
## Charge an enchantment spends when this hit lands; the wielder's weapon takes it back off
## the blade so a named weapon runs down with use.
var enchant_cost: int = 0


func copy() -> HitData:
	var h := HitData.new()
	h.amount = amount
	h.kind = kind
	h.poise_damage = poise_damage
	h.heavy = heavy
	h.attacker = attacker
	h.source = source
	h.swing_id = swing_id
	h.origin = origin
	h.crit_kind = crit_kind
	h.crit_mult = crit_mult
	h.blockable = blockable
	h.parryable = parryable
	h.dodgeable = dodgeable
	h.knockdown = knockdown
	h.knockback = knockback
	h.statuses = statuses.duplicate(true)
	h.skill_id = skill_id
	h.label = label
	h.enchant_cost = enchant_cost
	h.weapon_class = weapon_class
	h.weight = weight
	return h


func is_crit() -> bool:
	return crit_mult > 1.0


func describe() -> String:
	return "%s %.1f %s%s" % [label, amount, kind, (" crit:" + crit_kind) if is_crit() else ""]
