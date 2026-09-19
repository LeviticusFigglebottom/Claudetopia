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
##   voice: true         made with the voice: it cannot be started while the attacker is
##                       `silenced`, and a silence landed mid-channel breaks it
##   steal: {marks: [min, max]}   cuts the victim's purse on a landed hit
##   drain_stamina: n    takes n stamina from the victim; `drain_heal` heals the attacker for
##                       that fraction of what it took
##   channel: seconds    a held note: pulses every `channel_tick` seconds, heals the caster
##                       `heals_self` spread over the whole channel, and can be cut short by a
##                       silence (`voice`) or by `interrupt_damage` taken while `interruptible`
##   shockwave: metres   a landed blow's radial follow-through, at `shockwave_share` of its force
##   arena_wide: true    the radius is the arena's, not the attack's
##   combo_from: "name"  may only be thrown within `combo_window` of that other attack
##   shrinks_arena: m    takes that many metres off the arena bound, and keeps them
##
## Behaviour fields:
##   lure{lure_distance, lure_break, lure_patience, lure_speed}  backs away keeping you coming
##   guards{radius, wrath}   a sentinel roused by looting near its post
##   parries{parry_chance, parry_delay, guard_stability}  an elite that guards and answers a swing
##
## Enemy def field:
##   limbs[{name, breaks_at, damage, remove_attacks[], add_attacks[], poise_loss, speed_mult, say}]
##       one comes off each time the creature's poise breaks (`breaks_at: "poise"`, the default)
##       or each time it has taken `damage` since the last one went (`breaks_at: "damage"`),
##       changing what it can still do to you.
##
## Phase field:
##   renown_lights_arena: true   only what the player is known for stays lit.

## What a lure should do this frame.
const WITHDRAW := "withdraw"
const HOLD := "hold"
const ENGAGE := "engage"

const LURE_DEFAULTS := {"lure_distance": 8.0, "lure_break": 3.0, "lure_patience": 1.2, "lure_speed": 0.85}
## A channel pulses on this beat, and an unspecified `interrupt_damage` is this share of max hp.
const CHANNEL_TICK := 1.0
const INTERRUPT_SHARE := 0.06
## A shockwave carries this much of the blow that threw it, unless the attack says otherwise.
const SHOCKWAVE_SHARE := 0.5
## How long a combo stays open after the blow it follows.
const COMBO_WINDOW := 2.5
## What `arena_wide` means when no arena has been measured.
const DEFAULT_ARENA_RADIUS := 18.0
## Why a channel stopped.
const BROKE_SILENCED := "silenced"
const BROKE_DAMAGE := "damage"
const BROKE_INTERRUPTED := "interrupted"
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


# --- channelled attacks -------------------------------------------------------------------------

## Seconds this attack is held for, or 0 when it is an ordinary swing.
static func channel_seconds(attack: Dictionary) -> float:
	return maxf(float(attack.get("channel", 0.0)), 0.0)


static func is_channel(attack: Dictionary) -> bool:
	return channel_seconds(attack) > 0.0


static func channel_tick(attack: Dictionary) -> float:
	return maxf(float(attack.get("channel_tick", CHANNEL_TICK)), 0.05)


## How many pulses a full channel is worth. Used to spread `heals_self` across it, so that
## cutting the hymn off halfway really does deny her half of what she was taking back.
static func channel_pulses(attack: Dictionary) -> int:
	return maxi(int(round(channel_seconds(attack) / channel_tick(attack))), 1)


## What one pulse heals the singer. The whole `heals_self` only lands if the whole note does.
static func channel_heal_per_pulse(attack: Dictionary) -> float:
	return maxf(float(attack.get("heals_self", 0.0)), 0.0) / float(channel_pulses(attack))


## Damage that must land during a channel to break it, for an attack that admits interruption.
## An attack that does not say how tough its concentration is gets a share of the caster's health,
## so a large boss is not put off by a thrown pebble.
static func interrupt_damage(attack: Dictionary, max_health: float) -> float:
	if not bool(attack.get("interruptible", false)):
		return INF
	var stated := float(attack.get("interrupt_damage", 0.0))
	return stated if stated > 0.0 else maxf(max_health * INTERRUPT_SHARE, 1.0)


## Why this channel should stop now, or "" to let it run. Silence only reaches a note made with
## the voice: the Last Cantor's held note is the note itself, and no Hush-word touches it.
static func channel_break_reason(attack: Dictionary, silenced: bool, damage_taken: float, max_health: float) -> String:
	if silenced and bool(attack.get("voice", false)):
		return BROKE_SILENCED
	if damage_taken >= interrupt_damage(attack, max_health):
		return BROKE_DAMAGE
	return ""


# --- shockwaves -----------------------------------------------------------------------------------

static func has_shockwave(attack: Dictionary) -> bool:
	return float(attack.get("shockwave", 0.0)) > 0.0


static func is_arena_wide(attack: Dictionary) -> bool:
	return bool(attack.get("arena_wide", false))


## The radius a radial part of this attack covers: the arena's when it says `arena_wide`, its own
## `shockwave` reach when it has one, otherwise whatever a plain burst would use.
static func radial_radius(attack: Dictionary, arena_radius: float = DEFAULT_ARENA_RADIUS) -> float:
	if is_arena_wide(attack):
		return maxf(arena_radius, 1.0)
	if has_shockwave(attack):
		return float(attack["shockwave"])
	return burst_radius(attack)


## The ring a landed blow throws out: the same blow at a share of its force, with the knockdown
## and the statuses left on the blow itself. Rolling out of the hammer should not also roll you
## out of the floor it hit.
static func shockwave_attack(attack: Dictionary, arena_radius: float = DEFAULT_ARENA_RADIUS) -> Dictionary:
	var share := clampf(float(attack.get("shockwave_share", SHOCKWAVE_SHARE)), 0.0, 1.0)
	return {
		"name": str(attack.get("name", "attack")) + "_shockwave",
		"kind": "burst",
		"radius": radial_radius(attack, arena_radius),
		"damage": float(attack.get("damage", 0.0)) * share,
		"poise_damage": float(attack.get("poise_damage", 0.0)) * share,
		"kind_damage": str(attack.get("kind_damage", "blunt")),
		"weapon_class": str(attack.get("weapon_class", "hammer")),
		"heavy": bool(attack.get("heavy", false)),
		"unparryable": true,
		"noise": 1.2,
	}


# --- combos ---------------------------------------------------------------------------------------

static func combo_window(attack: Dictionary) -> float:
	return maxf(float(attack.get("combo_window", COMBO_WINDOW)), 0.0)


## True when this attack may be thrown at all. One that exists only as the second beat of a pair
## waits for the first beat, so the pair reads as one movement instead of two coin flips.
static func combo_ready(attack: Dictionary, last_attack: String, since: float) -> bool:
	var after := str(attack.get("combo_from", ""))
	if after.is_empty():
		return true
	return last_attack == after and since <= combo_window(attack)


# --- limbs ----------------------------------------------------------------------------------------

## "poise" (the default) or "damage": what takes the next piece off this thing.
static func limb_trigger(limb: Dictionary) -> String:
	return str(limb.get("breaks_at", "poise"))


static func limb_breaks_on_poise(limb: Dictionary) -> bool:
	return limb_trigger(limb) == "poise"


## Damage that must pile up before a `breaks_at: "damage"` limb comes away.
static func limb_damage_needed(limb: Dictionary) -> float:
	return maxf(float(limb.get("damage", 0.0)), 1.0)


## Every attack name that the limbs broken so far have taken away, in order.
static func names_removed(limbs: Array, broken: int) -> Array[String]:
	var out: Array[String] = []
	for i in mini(broken, limbs.size()):
		var limb: Variant = limbs[i]
		if typeof(limb) != TYPE_DICTIONARY:
			continue
		for n in (limb as Dictionary).get("remove_attacks", []):
			if not out.has(str(n)):
				out.append(str(n))
	return out


## Every attack that the limbs broken so far have brought in, in order.
static func attacks_added(limbs: Array, broken: int) -> Array:
	var out: Array = []
	for i in mini(broken, limbs.size()):
		var limb: Variant = limbs[i]
		if typeof(limb) != TYPE_DICTIONARY:
			continue
		for a in (limb as Dictionary).get("add_attacks", []):
			if typeof(a) == TYPE_DICTIONARY:
				out.append(a)
	return out


## A moveset with every broken limb's consequences applied to it. A boss that changes phase does
## not grow its arms back: the phase's own attacks go through the same filter.
static func apply_broken_limbs(base: Array, limbs: Array, broken: int) -> Array:
	if broken <= 0:
		return base.duplicate()
	var removed := names_removed(limbs, broken)
	var out: Array = []
	for a in base:
		if typeof(a) != TYPE_DICTIONARY:
			continue
		if removed.has(str((a as Dictionary).get("name", ""))):
			continue
		out.append(a)
	for a in attacks_added(limbs, broken):
		var already := false
		for b in out:
			if str((b as Dictionary).get("name", "")) == str((a as Dictionary).get("name", "")):
				already = true
				break
		if not already:
			out.append(a)
	return out


# --- the arena ------------------------------------------------------------------------------------

static func shrinks_arena_by(attack: Dictionary) -> float:
	return maxf(float(attack.get("shrinks_arena", 0.0)), 0.0)


static func lights_by_renown(phase: Dictionary) -> bool:
	return bool(phase.get("renown_lights_arena", false))


## What share of this attack lands on somebody standing in the light. 1.0 (the default) means
## the attack does not care where you are standing; the Last Cantor's held note does, which is
## the only thing that makes `renown_lights_arena` worth more than atmosphere.
static func lit_damage_share(attack: Dictionary) -> float:
	if not attack.has("spares_lit"):
		return 1.0
	return clampf(float(attack["spares_lit"]), 0.0, 1.0)


## How many lights stay burning at a renown tier of 0..4. Nobody is known for nothing, so one
## always survives: the Cantor leaves you the ground you are standing on and no more.
static func lights_for_renown(renown_tier: int) -> int:
	return clampi(renown_tier, 0, 4) + 1
