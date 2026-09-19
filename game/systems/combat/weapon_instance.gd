class_name WeaponInstance
extends Node3D
## One equipped weapon at runtime. Reads an item def's `weapon` block (CONTRACTS §7: class,
## damage, poise_damage, stamina_light/heavy, speed, reach, clips_set, parry, stability), owns
## a Hitbox sized by reach, and turns clip events (hit_start/hit_end) into swings.
## Sits under the actor's AttackOrigin node so the capsule points along the actor's forward.

signal hit_landed(victim: Node, hit: HitData, outcome: String)

const CHAIN_LENGTH := {"1H": 3, "2H": 2, "dagger": 2, "unarmed": 2, "bow": 0, "staff": 0}
const UNARMED_BLOCK := {"class": "unarmed", "damage": 6.0, "poise_damage": 8.0, "stamina_light": 12.0, "stamina_heavy": 20.0, "speed": 1.2, "reach": 1.0, "clips_set": "unarmed", "parry": false, "stability": 0.2, "kind": "blunt"}
const HITBOX_RADIUS := 0.4

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
var owner_actor: Node = null
var hitbox: Hitbox = null
var current_hit: HitData = null


static func from_item(id: String, actor: Node) -> WeaponInstance:
	var w := WeaponInstance.new()
	w.owner_actor = actor
	w.configure(ContentDB.get_or_empty(id), id)
	return w


static func unarmed(actor: Node) -> WeaponInstance:
	var w := WeaponInstance.new()
	w.owner_actor = actor
	w.configure({}, "")
	return w


func configure(def: Dictionary, id: String = "") -> void:
	item_id = id
	item_def = def
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
	name = "Weapon_" + (Ids.name_of(id) if not id.is_empty() else "unarmed")
	if hitbox != null:
		hitbox.set_capsule(HITBOX_RADIUS, minf(reach, 3.0))


func _ready() -> void:
	if hitbox == null:
		hitbox = Hitbox.create(owner_actor, HITBOX_RADIUS, minf(reach, 3.0))
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
				"bow": return "Bow_Release"
				_: return "Attack_Unarmed_%d" % i


## Placeholder timing derived from the weapon's speed (used until the real clips supply events).
## Returns {"length": s, "events": [{"t": s, "name": "hit_start"|"hit_end"|"cancel_ok"}]}.
func timing_for(attack_kind: String, index: int = 0) -> Dictionary:
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


## Attack multiplier before crits: chain position for lights, 1.6 · charge for heavies.
func attack_mult(attack_kind: String, index: int = 0, charge_ratio: float = 0.0) -> float:
	match attack_kind:
		"heavy":
			return DamageModel.HEAVY_ATTACK_MULT * DamageModel.heavy_charge(charge_ratio)
		"riposte", "backstab":
			return 1.0
		_:
			return DamageModel.light_chain_mult(index)


func stamina_cost(attack_kind: String) -> float:
	match attack_kind:
		"riposte", "backstab":
			return 0.0
		_:
			return DamageModel.attack_stamina(attack_kind, block)


## Builds the HitData for one swing. `skill` is the wielder's skill level for this weapon.
func build_hit(attack_kind: String, index: int, charge_ratio: float, skill: float, crit_kind: String = "") -> HitData:
	var h := HitData.new()
	h.amount = DamageModel.raw_damage(damage, skill, attack_mult(attack_kind, index, charge_ratio), 1.0)
	h.kind = kind
	h.heavy = attack_kind == "heavy"
	h.poise_damage = poise_damage
	h.attacker = owner_actor
	h.crit_kind = crit_kind
	h.crit_mult = DamageModel.crit_multiplier(crit_kind, weapon_class)
	if crit_kind == "riposte" or crit_kind == "backstab":
		h.blockable = false
		h.parryable = false
		h.dodgeable = false
	elif attack_kind == "heavy":
		h.parryable = false
	h.skill_id = skill_id
	h.label = "%s:%s%d" % [weapon_class, attack_kind, index + 1]
	if weapon_class == "dagger":
		h.statuses = [{"id": "bleeding", "duration": 6.0, "magnitude": 0.0}]
	return h


## Arms the next swing; the hitbox opens on the hit_start clip event and closes on hit_end.
func begin_attack(hit: HitData) -> void:
	current_hit = hit


func on_clip_event(event_name: String) -> void:
	match event_name:
		"hit_start":
			if current_hit != null and hitbox != null:
				hitbox.begin_swing(current_hit)
		"hit_end":
			if hitbox != null:
				hitbox.end_swing()


func end_attack() -> void:
	if hitbox != null:
		hitbox.end_swing()
	current_hit = null


func is_swinging() -> bool:
	return hitbox != null and hitbox.active


func _on_hit_landed(hurtbox: Hurtbox, hit: HitData, outcome: String) -> void:
	hit_landed.emit(hurtbox.actor, hit, outcome)
