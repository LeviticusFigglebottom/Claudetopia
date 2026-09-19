class_name EnemyAbilities
## The decisions behind the bestiary's special behaviours (DESIGN §5.4), kept pure so they can be
## unit-tested without a scene. `Enemy` owns the nodes, the timers and the hits; everything that
## is a *judgement* — may this attack be used, should the lure withdraw, how much is in the purse,
## which limb comes off next — lives here as a static func.
##
## Attack fields these add to the enemy def (all read by Enemy):
##   kind: "burst"       radial hit at `radius` instead of a forward capsule (a shriek, a ring)
##   kind: "projectile"  looses `projectile` at the target with `speed`/`gravity`
##   kind: "leap"        a charge with `leap_up` metres per second of lift (a pounce, a drop)
##   voice: true         cannot be used while the attacker is `silenced`
##   steal: {marks: [min, max]}   cuts the victim's purse on a landed hit
##   drain_stamina: n    takes n stamina from the victim; `drain_heal` heals the attacker for
##                       that fraction of what it took
##
## Behaviour fields:
##   lure{lure_distance, lure_break, lure_patience, lure_speed}  backs away keeping you coming
##   guards{radius, wrath}   a sentinel roused by looting near its post
##   parries{parry_chance, parry_delay, guard_stability}  an elite that guards and answers a swing
##
## Enemy def field:
##   limbs[{name, remove_attacks[], add_attacks[], poise_loss, speed_mult, say}]
##       one comes off each time the creature's poise breaks, changing what it can do.

## What a lure should do this frame.
const WITHDRAW := "withdraw"
const HOLD := "hold"
const ENGAGE := "engage"

const LURE_DEFAULTS := {"lure_distance": 8.0, "lure_break": 3.0, "lure_patience": 1.2, "lure_speed": 0.85}
const GUARD_DEFAULTS := {"radius": 14.0, "wrath": 1.0}
const PARRY_DEFAULTS := {"parry_chance": 0.45, "parry_delay": 0.3, "guard_stability": 0.6}


# --- attacks ------------------------------------------------------------------------------------

## May this attack be used now? A `voice` attack (a shriek, a sung note) needs a throat that
## is not silenced — which is the whole answer to the Cinderlea chorister.
static func is_usable(attack: Dictionary, silenced: bool) -> bool:
	if silenced and bool(attack.get("voice", false)):
		return false
	return true


## Attacks from `list` that may be used now, in the same order.
static func usable(list: Array, silenced: bool) -> Array:
	var out: Array = []
	for a in list:
		if typeof(a) == TYPE_DICTIONARY and is_usable(a, silenced):
			out.append(a)
	return out


static func is_burst(attack: Dictionary) -> bool:
	return str(attack.get("kind", "")) == "burst"


static func burst_radius(attack: Dictionary) -> float:
	return maxf(float(attack.get("radius", attack.get("range", 4.0))), 0.5)


static func is_projectile(attack: Dictionary) -> bool:
	return str(attack.get("kind", "")) == "projectile"


static func is_leap(attack: Dictionary) -> bool:
	return str(attack.get("kind", "")) == "leap"


## A leap is a charge that leaves the ground: metres per second of lift at the moment it goes.
static func leap_lift(attack: Dictionary) -> float:
	return float(attack.get("leap_up", 4.5))


# --- the cutpurse -------------------------------------------------------------------------------

## What a cut purse gives up: a share of what is in it, bounded by the attack's [min, max].
## `roll` is 0..1 from the caller's rng, so the same roll always takes the same amount.
static func steal_amount(attack: Dictionary, purse: int, roll: float) -> int:
	if purse <= 0:
		return 0
	var spec: Variant = attack.get("steal", null)
	if typeof(spec) != TYPE_DICTIONARY:
		return 0
	var marks: Variant = (spec as Dictionary).get("marks", [5, 20])
	var lo := 0
	var hi := 0
	if typeof(marks) == TYPE_ARRAY and (marks as Array).size() >= 2:
		lo = int((marks as Array)[0])
		hi = int((marks as Array)[1])
	else:
		lo = int(marks)
		hi = lo
	if hi < lo:
		var t := lo
		lo = hi
		hi = t
	var want := lo + int(round(clampf(roll, 0.0, 1.0) * float(hi - lo)))
	var share := float((spec as Dictionary).get("share", 0.0))
	if share > 0.0:
		want = maxi(want, int(round(float(purse) * clampf(share, 0.0, 1.0))))
	return clampi(want, 0, purse)


static func steals(attack: Dictionary) -> bool:
	return typeof(attack.get("steal", null)) == TYPE_DICTIONARY


# --- the leech-hound ----------------------------------------------------------------------------

static func drain_amount(attack: Dictionary) -> float:
	return maxf(float(attack.get("drain_stamina", 0.0)), 0.0)


## What the drinker gets back from what it took (0 by default: a drain is not a heal).
static func drain_heal(attack: Dictionary, drained: float) -> float:
	return maxf(drained * clampf(float(attack.get("drain_heal", 0.0)), 0.0, 2.0), 0.0)


# --- the wisp -----------------------------------------------------------------------------------

static func lure_params(behaviour: Dictionary) -> Dictionary:
	var out: Dictionary = LURE_DEFAULTS.duplicate()
	out.merge(behaviour, true)
	return out


## A lantern that is not a lantern: it keeps its distance and goes on keeping it, until you have
## stayed close enough for long enough that backing away would just be running, and then it turns.
## `closed_for` is how long the target has been inside `lure_break`.
static func lure_decision(distance: float, behaviour: Dictionary, closed_for: float) -> String:
	var p := lure_params(behaviour)
	var brk := float(p["lure_break"])
	if distance <= brk and closed_for >= float(p["lure_patience"]):
		return ENGAGE
	if distance < float(p["lure_distance"]):
		return WITHDRAW
	return HOLD


static func lures(behaviour: Dictionary) -> bool:
	return bool(behaviour.get("lure", false))


# --- the Warden ---------------------------------------------------------------------------------

static func guard_params(behaviour: Dictionary) -> Dictionary:
	var spec: Variant = behaviour.get("guards", null)
	if typeof(spec) != TYPE_DICTIONARY:
		return {}
	var out: Dictionary = GUARD_DEFAULTS.duplicate()
	out.merge(spec as Dictionary, true)
	return out


## A sentinel that does not chase still has an opinion about what happens at its feet: taking
## something inside the guarded radius rouses it, wherever it is looking.
static func greed_rouses(post: Vector3, taken_at: Vector3, behaviour: Dictionary) -> bool:
	var p := guard_params(behaviour)
	if p.is_empty():
		return false
	return post.distance_to(taken_at) <= float(p["radius"])


## Aggression a roused guardian fights at: its own, raised by `wrath`, never above 1.
static func guard_aggression(base: float, behaviour: Dictionary) -> float:
	var p := guard_params(behaviour)
	if p.is_empty():
		return base
	return clampf(base + float(p["wrath"]), 0.0, 1.0)


# --- the bravo ----------------------------------------------------------------------------------

static func parry_params(behaviour: Dictionary) -> Dictionary:
	var out: Dictionary = PARRY_DEFAULTS.duplicate()
	out.merge(behaviour, true)
	return out


## When a duelist who has seen a swing start should press its guard. Returns a negative number
## when this one goes unanswered — a bravo that parried everything would not be a fight.
static func parry_press_at(now: float, behaviour: Dictionary, roll: float) -> float:
	var p := parry_params(behaviour)
	if roll > float(p["parry_chance"]):
		return -1.0
	return now + maxf(float(p["parry_delay"]), 0.0)


static func parries(behaviour: Dictionary) -> bool:
	return bool(behaviour.get("parries", false))


# --- the stone-thrall ---------------------------------------------------------------------------

## The limb that comes off next, or {} when there is nothing left to break.
static func next_limb(limbs: Array, broken: int) -> Dictionary:
	if broken < 0 or broken >= limbs.size():
		return {}
	var limb: Variant = limbs[broken]
	return limb if typeof(limb) == TYPE_DICTIONARY else {}


## The moveset once a limb is gone: the attacks it swung with are dropped, the ones the stump
## and the loose rubble allow are added. Named attacks that are not in the list are ignored.
static func attacks_after_limb(current: Array, limb: Dictionary) -> Array:
	var removed: Array = limb.get("remove_attacks", [])
	var out: Array = []
	for a in current:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if removed.has(str((a as Dictionary).get("name", ""))):
			continue
		out.append(a)
	for a in limb.get("add_attacks", []):
		if typeof(a) == TYPE_DICTIONARY:
			out.append(a)
	return out


static func poise_after_limb(poise_max: float, limb: Dictionary) -> float:
	return maxf(poise_max - float(limb.get("poise_loss", 0.0)), 1.0)


static func speed_after_limb(speed: float, limb: Dictionary) -> float:
	return maxf(speed * float(limb.get("speed_mult", 1.0)), 0.2)
