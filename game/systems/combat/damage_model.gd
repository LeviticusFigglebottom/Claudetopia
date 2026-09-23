class_name DamageModel
## Pure combat formulas from DESIGN.md §5.3 (normative numbers). No state, no nodes.
## Everything here is a static func so it can be unit-tested without a scene.

# --- stamina -------------------------------------------------------------------------------
const STAMINA_LIGHT := 18.0
const STAMINA_HEAVY := 32.0
const STAMINA_DODGE := 22.0
const STAMINA_SPRINT_PER_S := 8.0
const STAMINA_REGEN_PER_S := 30.0
const STAMINA_REGEN_DELAY := 0.8
const BLOCK_STAMINA_FACTOR := 0.6

## "Load affects dodge and stamina regen" (DESIGN §5.7): how much of the regen a load band keeps.
## The design gives no numbers; these are the pass-one proposal, one step per band of the roll.
const LOAD_REGEN_MULT := {"light": 1.0, "medium": 0.9, "heavy": 0.75, "overloaded": 0.5}

# --- poise ---------------------------------------------------------------------------------
const POISE_REGEN_PER_S := 4.0
const POISE_REGEN_DELAY := 1.5
const HEAVY_POISE_MULT := 1.5
## The poise damage a heavy's wind-up and swing shrug off (DESIGN §5.3's hyper-armour threshold).
## The design gives no number; this is the brute's own default, so a player's heavy stands up to
## exactly what a brute's does.
const HEAVY_HYPER_ARMOUR := 12.0

# --- timing --------------------------------------------------------------------------------
const INPUT_BUFFER := 0.25
const PARRY_WINDOW := 0.18
const RIPOSTE_OPEN_DURATION := 2.0
const DODGE_DURATION := 0.6
const DODGE_IFRAME_START := 0.08
const DODGE_IFRAME_END := 0.38
const DODGE_DISTANCE := 3.4
const LIGHT_CHAIN_MAX := 3
const HEAVY_CHARGE_TIME := 1.0

# --- lock-on -------------------------------------------------------------------------------
const LOCK_ON_RANGE := 30.0
const LOCK_ON_CONE_DEG := 70.0
const LOCK_ON_BREAK_RANGE := 40.0

# --- multipliers ---------------------------------------------------------------------------
const HEAVY_ATTACK_MULT := 1.6
const LIGHT_CHAIN_MULTS: Array[float] = [1.0, 1.0, 1.2]
const CRIT := {"riposte": 3.0, "backstab": 3.0, "sneak": 3.0, "sneak_dagger": 6.0}
const MIN_DAMAGE := 1.0

## Hit kinds a hitbox can carry; resists are keyed by these.
const KINDS: Array[String] = ["slash", "pierce", "blunt", "fire", "frost", "poison", "silence"]

## Default hit kind per weapon class (a weapon block may override with an explicit "kind").
const CLASS_KIND := {
	"sword": "slash", "axe": "slash", "greatsword": "slash", "greataxe": "slash", "scythe": "slash", "claw": "slash",
	"dagger": "pierce", "spear": "pierce", "bow": "pierce", "arrow": "pierce", "crossbow": "pierce", "bite": "pierce", "tusk": "pierce", "rapier": "pierce",
	"mace": "blunt", "hammer": "blunt", "club": "blunt", "staff": "blunt", "unarmed": "blunt", "charge": "blunt",
}

## Skill that gains XP per clips_set.
const CLIPS_SKILL := {"1H": "one_handed", "2H": "two_handed", "dagger": "one_handed", "bow": "archery", "staff": "kindling", "unarmed": "one_handed"}


# --- pools ---------------------------------------------------------------------------------

static func stamina_max(endurance: int) -> float:
	return 100.0 + 8.0 * float(endurance)


static func mana_max(will: int) -> float:
	return 60.0 + 6.0 * float(will)


## DESIGN.md gives Vigour -> HP without a number; 60 + 4·Vigour (100 at the starting 10) is the
## pass-one proposal. It lives here, and Leveling asks for it rather than keeping its own.
static func hp_max(vigour: int) -> float:
	return 60.0 + 4.0 * float(vigour)


# --- damage --------------------------------------------------------------------------------

static func skill_mult(skill: float) -> float:
	return 1.0 + maxf(skill, 0.0) / 200.0


## Damage before the victim's defence: weapon_base · skill_mult · attack_mult · charge · crit.
static func raw_damage(weapon_base: float, skill: float, attack_mult: float = 1.0, charge: float = 1.0, crit_mult: float = 1.0) -> float:
	return maxf(weapon_base, 0.0) * skill_mult(skill) * attack_mult * charge * crit_mult


## (raw − armour_flat) · (1 − resist), never below MIN_DAMAGE. resist may be negative (weakness).
static func apply_defence(raw: float, armour_flat: float, resist: float = 0.0) -> float:
	var r := clampf(resist, -2.0, 0.95)
	return maxf(MIN_DAMAGE, (raw - maxf(armour_flat, 0.0)) * (1.0 - r))


static func damage(weapon_base: float, skill: float, attack_mult: float, charge: float, armour_flat: float, resist: float, crit_mult: float = 1.0) -> float:
	return apply_defence(raw_damage(weapon_base, skill, attack_mult, charge, crit_mult), armour_flat, resist)


static func crit_multiplier(crit_kind: String, weapon_class: String = "") -> float:
	if crit_kind.is_empty():
		return 1.0
	if crit_kind == "sneak" and weapon_class == "dagger":
		return CRIT["sneak_dagger"]
	return float(CRIT.get(crit_kind, 1.0))


static func resist_of(resists: Dictionary, kind: String) -> float:
	return float(resists.get(kind, 0.0))


static func kind_for_class(weapon_class: String) -> String:
	return str(CLASS_KIND.get(weapon_class, "slash"))


static func skill_for_clips(clips_set: String) -> String:
	return str(CLIPS_SKILL.get(clips_set, "one_handed"))


static func light_chain_mult(index: int) -> float:
	return LIGHT_CHAIN_MULTS[clampi(index, 0, LIGHT_CHAIN_MULTS.size() - 1)]


## charge_ratio 0..1 (how long the heavy was held) -> DESIGN's `charge` factor 1.0..1.5.
static func heavy_charge(charge_ratio: float) -> float:
	return 1.0 + 0.5 * clampf(charge_ratio, 0.0, 1.0)


# --- poise ---------------------------------------------------------------------------------

## Poise damage actually applied: heavies deal more, hyper-armour ignores hits below a threshold.
static func poise_damage(base: float, heavy: bool = false, hyper_armour_threshold: float = 0.0) -> float:
	var amount := maxf(base, 0.0) * (HEAVY_POISE_MULT if heavy else 1.0)
	if hyper_armour_threshold > 0.0 and amount < hyper_armour_threshold:
		return 0.0
	return amount


# --- stamina costs -------------------------------------------------------------------------

## Cost of an attack from a weapon block (falls back to the DESIGN defaults).
static func attack_stamina(attack_kind: String, weapon: Dictionary) -> float:
	match attack_kind:
		"heavy":
			return float(weapon.get("stamina_heavy", STAMINA_HEAVY))
		_:
			return float(weapon.get("stamina_light", STAMINA_LIGHT))


static func block_stamina_cost(incoming_damage: float, stability: float) -> float:
	return maxf(incoming_damage, 0.0) * BLOCK_STAMINA_FACTOR * (1.0 - clampf(stability, 0.0, 1.0))


## Damage let through a raised guard. Proposal: linear in (1 − stability); armour applies after.
static func block_damage(incoming_damage: float, stability: float) -> float:
	return maxf(incoming_damage, 0.0) * (1.0 - clampf(stability, 0.0, 1.0))


# --- timing checks -------------------------------------------------------------------------

## True when the block press happened within `window` seconds *before* the hit.
static func parry_succeeds(block_pressed_at: float, hit_at: float, window: float = PARRY_WINDOW) -> bool:
	var dt := hit_at - block_pressed_at
	return dt >= 0.0 and dt <= window


## Buffered input is still valid when pressed no more than INPUT_BUFFER seconds ago.
static func buffer_valid(pressed_at: float, now: float, window: float = INPUT_BUFFER) -> bool:
	return pressed_at >= 0.0 and now - pressed_at <= window


## Dodge roll parameters by load ratio (0 = naked, 1 = at max load, >1 over-encumbered).
## Heavy load lengthens the roll and cuts the i-frames (DESIGN §5.3).
static func dodge_params(load_ratio: float) -> Dictionary:
	match load_tier(load_ratio):
		"light":
			return {"duration": DODGE_DURATION, "iframe_start": DODGE_IFRAME_START, "iframe_end": DODGE_IFRAME_END, "distance": DODGE_DISTANCE, "tier": "light"}
		"medium":
			return {"duration": 0.66, "iframe_start": 0.08, "iframe_end": 0.34, "distance": 3.0, "tier": "medium"}
		"heavy":
			return {"duration": 0.8, "iframe_start": 0.1, "iframe_end": 0.3, "distance": 2.4, "tier": "heavy"}
	return {"duration": 1.0, "iframe_start": 0.12, "iframe_end": 0.26, "distance": 1.6, "tier": "overloaded"}


## The band a load ratio falls in: light below 30%, medium below 70%, heavy up to 100%, and
## overloaded past it.
static func load_tier(load_ratio: float) -> String:
	var l := maxf(load_ratio, 0.0)
	if l < 0.3:
		return "light"
	if l < 0.7:
		return "medium"
	if l <= 1.0:
		return "heavy"
	return "overloaded"


static func load_regen_mult(load_ratio: float) -> float:
	return float(LOAD_REGEN_MULT.get(load_tier(load_ratio), 1.0))


static func in_iframes(elapsed: float, params: Dictionary) -> bool:
	return elapsed >= float(params["iframe_start"]) and elapsed <= float(params["iframe_end"])


## Facing test used by block/parry: the defender must face the hit's origin (within ~84°).
static func is_facing(forward: Vector3, to_origin: Vector3, min_dot: float = 0.1) -> bool:
	var f := Vector3(forward.x, 0.0, forward.z)
	var t := Vector3(to_origin.x, 0.0, to_origin.z)
	if t.length_squared() < 0.0001 or f.length_squared() < 0.0001:
		return true
	return f.normalized().dot(t.normalized()) >= min_dot


## Backstab test: attacker stands behind the victim (attacker roughly along −forward of the victim).
static func is_behind(victim_forward: Vector3, victim_to_attacker: Vector3, max_dot: float = -0.5) -> bool:
	var f := Vector3(victim_forward.x, 0.0, victim_forward.z).normalized()
	var t := Vector3(victim_to_attacker.x, 0.0, victim_to_attacker.z)
	if t.length_squared() < 0.0001:
		return false
	return f.dot(t.normalized()) <= max_dot
