class_name WeaponInstance
extends Node3D
## One equipped weapon at runtime. Reads an item def's `weapon` block (CONTRACTS §7: class,
## damage, poise_damage, stamina_light/heavy, speed, reach, clips_set, parry, stability), owns
## a Hitbox sized by reach, and turns clip events (hit_start/hit_end) into swings.
## Sits under the actor's AttackOrigin node so the capsule points along the actor's forward.

signal charge_changed(charge: int, charge_max: int)
signal hit_landed(victim: Node, hit: HitData, outcome: String)

const CHAIN_LENGTH := {"1H": 3, "2H": 2, "dagger": 2, "unarmed": 2, "bow": 0, "staff": 2}
const UNARMED_BLOCK := {"class": "unarmed", "damage": 6.0, "poise_damage": 8.0, "stamina_light": 12.0, "stamina_heavy": 20.0, "speed": 1.2, "reach": 1.0, "clips_set": "unarmed", "parry": false, "stability": 0.2, "kind": "blunt"}
const HITBOX_RADIUS := 0.4
## Rig events that belong to the picture, not the fight: left out of a swing's timeline.
const PICTURE_EVENTS: Array[String] = ["cocked", "strike"]
## How far a swing reaches up and down from the attack origin (1.1 m on a person): from a hand's
## breadth off the ground to a little over the head. See Hitbox.set_swing.
const SWING_BELOW := 1.0
const SWING_ABOVE := 0.8

var item_id: String = ""
var item_def: Dictionary = {}
var block: Dictionary = {}
var weapon_class: String = "unarmed"
var damage: float = 6.0
var poise_damage: float = 8.0
var speed: float = 1.0
var reach: float = 1.0
var clips_set: String = "unarmed"
var can_parry: bool = false
var stability: float = 0.2
var kind: String = "blunt"
var skill_id: String = "one_handed"
var ranged: Dictionary = {}           # bows: {draw_time, speed, ammo_tag}
## The equipped stack's own state, and the enchantment out of it (CONTRACTS §7).
var data: Dictionary = {}
var enchant: Dictionary = {}
var owner_actor: Node = null
var hitbox: Hitbox = null
var current_hit: HitData = null


static func from_item(id: String, actor: Node, instance_data: Dictionary = {}) -> WeaponInstance:
	var w := WeaponInstance.new()
	w.owner_actor = actor
	w.configure(ContentDB.get_or_empty(id), id, instance_data)
	return w


static func unarmed(actor: Node) -> WeaponInstance:
	var w := WeaponInstance.new()
	w.owner_actor = actor
	w.configure({}, "")
	return w


## `instance_data` is the equipped stack's own state (CONTRACTS §7: temper, enchant, quality).
## A weapon on the ground is its definition; a weapon somebody has tempered and named is that
## definition plus what was done to it, and the swing has to know both.
func configure(def: Dictionary, id: String = "", instance_data: Dictionary = {}) -> void:
	item_id = id
	item_def = def
	data = instance_data.duplicate(true)
	block = def.get("weapon", UNARMED_BLOCK) if def.has("weapon") else UNARMED_BLOCK
	weapon_class = str(block.get("class", "unarmed"))
	damage = float(block.get("damage", 6.0))
	poise_damage = float(block.get("poise_damage", 8.0))
	speed = maxf(float(block.get("speed", 1.0)), 0.2)
	reach = maxf(float(block.get("reach", 1.0)), 0.5)
	clips_set = str(block.get("clips_set", "unarmed"))
	can_parry = bool(block.get("parry", false))
	stability = clampf(float(block.get("stability", 0.2)), 0.0, 1.0)
	kind = str(block.get("kind", DamageModel.kind_for_class(weapon_class)))
	skill_id = str(block.get("skill", DamageModel.skill_for_clips(clips_set)))
	ranged = def.get("ranged", {})
	var temper := 1.0 + ItemStack.TEMPER_BONUS_PER_TIER * float(int(data.get("temper", 0)))
	damage *= temper
	poise_damage *= temper
	enchant = data.get("enchant", {}) if typeof(data.get("enchant", {})) == TYPE_DICTIONARY else {}
	name = "Weapon_" + (Ids.name_of(id) if not id.is_empty() else "unarmed")
	if hitbox != null:
		hitbox.set_swing(HITBOX_RADIUS, minf(reach, 3.0), SWING_BELOW, SWING_ABOVE)


func _ready() -> void:
	if hitbox == null:
		hitbox = Hitbox.create(owner_actor, HITBOX_RADIUS, minf(reach, 3.0))
		hitbox.set_swing(HITBOX_RADIUS, minf(reach, 3.0), SWING_BELOW, SWING_ABOVE)
		add_child(hitbox)
		hitbox.hit_landed.connect(_on_hit_landed)


func is_ranged() -> bool:
	return clips_set == "bow"


func is_two_handed() -> bool:
	return clips_set == "2H"


func chain_length() -> int:
	return int(CHAIN_LENGTH.get(clips_set, 2))


func display_name() -> String:
	return str(item_def.get("name", "Fists"))


## Clip name for an attack per CONTRACTS §3.
func clip_for(attack_kind: String, index: int = 0) -> String:
	match attack_kind:
		"heavy":
			match clips_set:
				"1H": return "Attack_1H_Heavy"
				"2H": return "Attack_2H_Heavy"
				"dagger": return "Attack_Dagger_2"
				"staff": return "Attack_Staff_Heavy"
				_: return "Attack_Unarmed_2"
		"riposte":
			return "Riposte"
		"backstab":
			return "Backstab"
		"draw":
			return "Bow_Draw"
		"aim":
			return "Bow_Aim"
		"release":
			return "Bow_Release"
		_:
			var i := clampi(index, 0, maxi(chain_length() - 1, 0)) + 1
			match clips_set:
				"1H": return "Attack_1H_Light_%d" % i
				"2H": return "Attack_2H_Light_%d" % i
				"dagger": return "Attack_Dagger_%d" % i
				"staff": return "Attack_Staff_%d" % i
				"bow": return "Bow_Release"
				_: return "Attack_Unarmed_%d" % i


## When a swing's blow lands and when it is spent: `{"length": s, "events": [{"t": s, "name":
## "hit_start"|"hit_end"|"cancel_ok"...}]}`. It is the swing's own clip, off the rig's sidecar,
## played at this weapon's `speed` -- a rapier's thrust is the sword's thrust, sooner, and a bell
## on a haft is the same two-handed swing, later. The AnimationDriver keeps time by this, so the
## hit window the game scores is the one the body is seen to swing.
##
## Before, the window was a placeholder built from `speed` alone, and the body swung its clip at
## the clip's own pace and fired the clip's events: the two agreed to within a frame or two for a
## sword, and `speed` did nothing at all once the forged rig arrived.
func timing_for(attack_kind: String, index: int = 0) -> Dictionary:
	var clip := clip_for(attack_kind, index)
	var rig := HumanoidModel.sidecar_timing(clip)
	if _has_window(rig):
		var swing_scale := 1.0 / speed if attack_kind == "light" or attack_kind == "heavy" else 1.0
		var events: Array = []
		for e in rig["events"]:
			# `cocked` is the picture's (where a foe's held wind-up waits), not the fight's
			if str(e["name"]) in PICTURE_EVENTS:
				continue
			events.append({"t": float(e["t"]) * swing_scale, "name": str(e["name"])})
		return {"length": float(rig["length"]) * swing_scale, "events": events}
	return _proportional_timing(attack_kind, index)


static func _has_window(t: Dictionary) -> bool:
	var names := {}
	for e in t.get("events", []):
		names[str(e.get("name", ""))] = true
	return float(t.get("length", 0.0)) > 0.0 and names.has("hit_start") and names.has("hit_end")


## The proportions a swing had before there was a rig to measure: kept for a clip the sidecar does
## not have, so a weapon never swings with no window at all.
func _proportional_timing(attack_kind: String, index: int = 0) -> Dictionary:
	var length: float
	var hs: float
	var he: float
	var co: float
	match attack_kind:
		"heavy":
			length = 1.4 / speed
			hs = 0.5
			he = 0.68
			co = 0.8
		"riposte", "backstab":
			length = 1.3
			hs = 0.5
			he = 0.7
			co = 0.85
		_:
			length = 0.85 / speed * (1.15 if index >= 2 else 1.0)
			hs = 0.38
			he = 0.58
			co = 0.68
	return {"length": length, "events": [{"t": length * hs, "name": "hit_start"}, {"t": length * he, "name": "hit_end"}, {"t": length * co, "name": "cancel_ok"}]}


# --- what the wielder's perks change -------------------------------------------------------------

## The wielder's modifier table (Actor.stat_mods), or null for a body with none.
func _mods() -> Modifiers:
	if owner_actor != null and is_instance_valid(owner_actor) and owner_actor.has_method("stat_mods"):
		return owner_actor.call("stat_mods") as Modifiers
	return null


func _mult(stat: String) -> float:
	var m := _mods()
	return m.get_mult(stat) if m != null else 1.0


func _add(stat: String) -> float:
	var m := _mods()
	return m.get_add(stat) if m != null else 0.0


## The damage multiplier of the skill this weapon trains: Warden's Grip for a one-handed blade
## (`damage_one_handed`), Wide Sweep for a two-handed one, Steady Breath for a bow or a crossbow
## (`damage_archery`).
func skill_damage_mult() -> float:
	return _mult("damage_" + skill_id)


## `damage` and `poise_damage` carry the stack's temper at the base 10% a tier (configure). Red Door
## makes every tier worth 15%, so the swing scales by the difference, read when it is swung so a
## perk taken with the blade in hand counts at once.
func temper_perk_scale() -> float:
	var tiers := float(int(data.get("temper", 0)))
	var extra := _add("temper_bonus")
	if tiers <= 0.0 or is_zero_approx(extra):
		return 1.0
	var base := 1.0 + ItemStack.TEMPER_BONUS_PER_TIER * tiers
	return (base + extra * tiers) / base


## Seconds to full draw: the bow's `draw_time`, shortened by Fernhold Draw (draws 15% faster).
func draw_time() -> float:
	return maxf(float(ranged.get("draw_time", 0.7)) / maxf(_mult("bow_draw_speed"), 0.01), 0.1)


## Attack multiplier before crits: chain position for lights, 1.6 · charge for heavies.
func attack_mult(attack_kind: String, index: int = 0, charge_ratio: float = 0.0) -> float:
	match attack_kind:
		"heavy":
			return DamageModel.HEAVY_ATTACK_MULT * DamageModel.heavy_charge(charge_ratio)
		"riposte", "backstab":
			return 1.0
		_:
			return DamageModel.light_chain_mult(index)


## What an attack takes out of the wielder. Bell Swing cheapens every heavy; Quick Steel cheapens
## the lights of a one-handed weapon (a bow's loose is not a light attack, whatever it costs).
func stamina_cost(attack_kind: String) -> float:
	match attack_kind:
		"riposte", "backstab":
			return 0.0
		"heavy":
			return DamageModel.attack_stamina(attack_kind, block) * _mult("stamina_cost_heavy")
		_:
			var cost := DamageModel.attack_stamina(attack_kind, block)
			if skill_id == "one_handed" and ranged.is_empty():
				cost *= _mult("stamina_cost_light")
			return cost


## Builds the HitData for one swing. `skill` is the wielder's skill level for this weapon.
func build_hit(attack_kind: String, index: int, charge_ratio: float, skill: float, crit_kind: String = "") -> HitData:
	var h := HitData.new()
	var tempered := temper_perk_scale()
	h.amount = DamageModel.raw_damage(damage * tempered, skill, attack_mult(attack_kind, index, charge_ratio), 1.0) * skill_damage_mult()
	h.kind = kind
	h.heavy = attack_kind == "heavy"
	h.poise_damage = poise_damage * tempered * _mult("poise_damage_" + skill_id)
	h.attacker = owner_actor
	h.crit_kind = crit_kind
	h.crit_mult = DamageModel.crit_multiplier(crit_kind, weapon_class)
	if crit_kind == "sneak":
		# Unsaid: a sneak attack multiplies by one more (×3 → ×4, a dagger's ×6 → ×7).
		h.crit_mult += _add("sneak_attack_mult")
	if crit_kind == "riposte" or crit_kind == "backstab":
		h.blockable = false
		h.parryable = false
		h.dodgeable = false
	elif attack_kind == "heavy":
		h.parryable = false
	h.skill_id = skill_id
	h.label = "%s:%s%d" % [weapon_class, attack_kind, index + 1]
	h.weapon_class = weapon_class
	h.weight = float(item_def.get("weight", 0.0))
	# a heavy blow drives the body it lands on back: more for a heavier weapon (Impact)
	h.knockback = Impact.knockback_for(h.weight, attack_kind == "heavy", clips_set)
	if weapon_class == "dagger":
		h.statuses = [{"id": "bleeding", "duration": 6.0, "magnitude": 0.0}]
	_add_enchantment(h)
	return h


## What a Name-table wrote on the blade. An effect with an `on_hit` block changes the hit: the
## kind of damage it does and the mark it leaves. Charge is what it costs to say it again, and
## a spent enchantment is a decoration until it is recharged.
func _add_enchantment(h: HitData) -> void:
	if enchant.is_empty():
		return
	var eff := ContentDB.get_or_empty(str(enchant.get("effect", "")))
	var on_hit: Dictionary = eff.get("on_hit", {})
	if on_hit.is_empty():
		return
	var cost := int(eff.get("charge_cost", 0))
	if cost > 0 and int(enchant.get("charge", 0)) < cost:
		return
	var magnitude := float(enchant.get("magnitude", eff.get("magnitude_base", 0.0)))
	var duration := float(enchant.get("duration", eff.get("duration_base", 0.0)))
	h.amount += magnitude
	if on_hit.has("damage_type"):
		h.kind = str(on_hit["damage_type"])
	if on_hit.has("status"):
		var statuses: Array = h.statuses.duplicate()
		statuses.append({"id": str(on_hit["status"]), "duration": duration, "magnitude": magnitude})
		h.statuses = statuses
	h.enchant_cost = cost


## Arms the next swing; the hitbox opens on the hit_start clip event and closes on hit_end.
func begin_attack(hit: HitData) -> void:
	current_hit = hit


func on_clip_event(event_name: String) -> void:
	match event_name:
		"hit_start":
			if current_hit != null and hitbox != null:
				# The swing's own hit: a blow that lands the moment the hitbox opens can end the
				# attack (a stagger, a death: end_attack) and clear current_hit under us. `./run.sh
				# fights` hit it three to five times a run.
				var hit := current_hit
				# The whoosh goes with the blade, not with the button: it is heard as the swing
				# goes live, whatever the wind-up before it, and before anything it lands on.
				@warning_ignore("static_called_on_instance")
				var whoosh := Foley.swing_for(weapon_class, hit.heavy)
				if not whoosh.is_empty() and is_inside_tree():
					Foley.play(whoosh, global_position, -4.0 if clips_set == "unarmed" else 0.0)
				hitbox.begin_swing(hit)
				# (an attack ended inside begin_swing keeps its trail out)
				if hit.heavy and current_hit == hit and owner_actor != null:
					Impact.trail(owner_actor, true)
		"hit_end":
			if hitbox != null:
				hitbox.end_swing()
			if owner_actor != null:
				Impact.trail(owner_actor, false)


func end_attack() -> void:
	if hitbox != null:
		hitbox.end_swing()
	if owner_actor != null:
		Impact.trail(owner_actor, false)
	current_hit = null


func is_swinging() -> bool:
	return hitbox != null and hitbox.active


func _on_hit_landed(hurtbox: Hurtbox, hit: HitData, outcome: String) -> void:
	if hit.enchant_cost > 0 and (outcome == "hit" or outcome == "blocked"):
		_spend_charge(hit.enchant_cost)
	hit_landed.emit(hurtbox.actor, hit, outcome)


## Takes charge off the blade and off the stack it came from, so the running-down survives
## unequipping and a save. Emits so a HUD can show a weapon going quiet.
func _spend_charge(cost: int) -> void:
	var left := maxi(int(enchant.get("charge", 0)) - cost, 0)
	enchant["charge"] = left
	charge_changed.emit(left, int(enchant.get("charge_max", left)))
	if owner_actor == null or not owner_actor.has_method("on_weapon_charge_spent"):
		return
	owner_actor.call("on_weapon_charge_spent", item_id, left)
