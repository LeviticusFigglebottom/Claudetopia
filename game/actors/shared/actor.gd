class_name Actor
extends CharacterBody3D
## Base for every fighting body (ARCHITECTURE §8): health, StaminaComponent, PoiseComponent,
## StatusEffects, SpellCaster, faction tag, `Model` pivot (rotated 180° so gameplay forward is −Z,
## CONTRACTS §1), Hurtbox, equipment sockets, AnimationDriver, hit resolution
## (dodge i-frames → parry → block → damage/poise/status), death and save data.
## Subclasses (Player, Enemy) own input/AI and movement; they call the helpers here.

signal health_changed(current: float, maximum: float)
signal stats_changed
signal died(killer: Node)
signal hit_taken(hit: HitData, outcome: String)
signal staggered
signal knocked_down
signal riposte_opened(duration: float)
signal guard_broken
signal shield_changed(amount: float)

const SOCKET_NAMES: Array[String] = ["Socket.WeaponR", "Socket.WeaponL", "Socket.ShieldL", "Socket.Back", "Socket.HipL", "Socket.Head", "Socket.Lantern"]
## Placeholder socket positions in Model space (+Z is the model's own forward), CONTRACTS §2.
const PLACEHOLDER_SOCKETS := {
	"Socket.WeaponR": Vector3(0.34, 0.95, 0.12), "Socket.WeaponL": Vector3(-0.34, 0.95, 0.12), "Socket.ShieldL": Vector3(-0.36, 1.05, 0.05),
	"Socket.Back": Vector3(0.0, 1.35, -0.2), "Socket.HipL": Vector3(-0.22, 0.95, -0.05), "Socket.Head": Vector3(0.0, 1.78, 0.0), "Socket.Lantern": Vector3(-0.36, 0.9, 0.2),
}
const LAYER_WORLD := 1 << 0
const LAYER_PLAYER := 1 << 1
const LAYER_ENEMY := 1 << 2
const LAYER_NPC := 1 << 3
const LAYER_TERRAIN := 1 << 10
## The near ring's trunks, rocks, walls, hedges and fences (world/scatter_solids.gd): a body walks
## into them; the camera's arm, sight and arrows do not see them.
const LAYER_SCATTER := 1 << 12
const BODY_MASK := LAYER_WORLD | LAYER_PLAYER | LAYER_ENEMY | LAYER_NPC | LAYER_TERRAIN | LAYER_SCATTER
const KNOCKDOWN_DURATION := 1.6
const GET_UP_DURATION := 0.8
const RIPOSTE_VICTIM_STUN := 1.2
## A shove slows at this rate (m/s²); a knockback of d metres starts at sqrt(2·SHOVE_DECEL·d) m/s.
const SHOVE_DECEL := 14.0
## How far being knocked off your feet carries you, before any knockback the blow itself carries.
const KNOCKDOWN_SHOVE := 1.2
## How far above the heightfield still counts as standing on it.
const GROUND_SKIN := 0.12
## The steepest ground a body walks up (degrees): its floor angle. Steeper ground is a wall.
const WALKABLE_SLOPE_DEG := 45.0

@export var display_name: String = "Actor"
@export var faction: String = "neutral"
@export var max_health: float = 100.0
@export var vigour: int = 10
@export var endurance: int = 10
@export var will: int = 10
@export var armour_flat: float = 0.0
@export var resists: Dictionary = {}          # hit kind -> 0..1 (negative = weakness)
@export var poise_max: float = 40.0
@export var body_kind: String = "humanoid"    # placeholder body: humanoid | quadruped
@export var body_variant: String = ""         # placeholder detail: wolf | boar | wight ...
@export var body_scale: float = 1.0
@export var tint: Color = Color(0.85, 0.8, 0.7)
@export var capsule_radius: float = 0.35
@export var capsule_height: float = 1.8
## Extra factions this actor also fights (beyond the player rule in is_hostile_to).
@export var hostile_to: Array[String] = []

var health: float = 100.0:
	set = set_health
var stamina: float:
	get = _get_stamina, set = _set_stamina
var max_stamina: float:
	get = _get_max_stamina, set = _set_max_stamina
var poise: float:
	get = _get_poise, set = _set_poise
var max_poise: float:
	get = _get_max_poise, set = _set_max_poise
var mana: float:
	get = _get_mana, set = _set_mana
var max_mana: float:
	get = _get_max_mana, set = _set_max_mana

var shield_hp: float = 0.0
var shield_until: float = -1.0
var dead: bool = false
## What this body sounds like when it is struck (Foley.material_for): flesh, metal, stone, wood.
var body_material: String = "flesh"
## The surface its last footstep landed on, in Foley's names. Stealth reads it for noise.
var surface: String = ""
var _footfalls := Footfalls.new()
var is_blocking: bool = false
var block_stability: float = 0.0
var can_parry: bool = false
var parry_pressed_at: float = -100.0
var riposte_open_until: float = -100.0
var invulnerable_from: float = -100.0
var invulnerable_until: float = -100.0
## A dodge counted from one swinger is not counted again for this long (s): one blow, one dodge.
const DODGE_COUNTED_FOR_S := 0.8
var _dodges_counted: Dictionary = {}     # swinger's instance id -> when its dodge was counted
var stunned_until: float = -100.0
var last_attacker: Node = null
## The skill behind the last blow that reached this body ("kindling" for a Kindling saying): a foe
## that dies of a Kindling word gives up its last warmth as an Ember Mote (DESIGN §5.8).
var last_hit_skill: String = ""
## Ammunition that struck this body and survived it, item id -> count: what can be pulled back
## out of the body once it has fallen (LootDrops hands it over with the rest of the loot).
var lodged: Dictionary = {}
## The shove still to be spent, as a speed (m/s) that SHOVE_DECEL runs down. See integrate_shove.
var shove: Vector3 = Vector3.ZERO
## Where the last blow came from and when, for which way a stagger it causes throws the body.
var _blow_from := Vector3.ZERO
var _blow_at := -100.0
## A stagger this soon after a blow is that blow's.
const BLOW_REMEMBERED_S := 0.25
var gravity: float = 9.81

var model: Node3D = null
var attack_origin: Node3D = null
var hurtbox: Hurtbox = null
var stamina_comp: StaminaComponent = null
var poise_comp: PoiseComponent = null
var status: StatusEffects = null
var anim: AnimationDriver = null
var caster: SpellCaster = null
var _sockets: Dictionary = {}


static func now() -> float:
	return float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second)


func _ready() -> void:
	gravity = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.81))
	if collision_mask == 1:
		collision_mask = BODY_MASK
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(WALKABLE_SLOPE_DEG)
	# a walk is a walk up a slope as on the flat: without it the pace along the ground fell with
	# the slope's cosine squared uphill (to 59% at 40°) and rose downhill
	floor_constant_speed = true
	_ensure_nodes()
	_setup_components()
	add_to_group("actors")
	health = max_health


# --- construction -----------------------------------------------------------------------------

func _ensure_nodes() -> void:
	model = get_node_or_null("Model") as Node3D
	if model == null:
		model = Node3D.new()
		model.name = "Model"
		model.rotation.y = PI
		add_child(model)
	var has_shape := false
	for c in get_children():
		if c is CollisionShape3D:
			has_shape = true
	if not has_shape:
		var shape := CollisionShape3D.new()
		shape.name = "CollisionShape3D"
		var capsule := CapsuleShape3D.new()
		capsule.radius = capsule_radius
		capsule.height = capsule_height
		shape.shape = capsule
		shape.position = Vector3(0.0, capsule_height * 0.5, 0.0)
		add_child(shape)
	attack_origin = get_node_or_null("AttackOrigin") as Node3D
	if attack_origin == null:
		attack_origin = Node3D.new()
		attack_origin.name = "AttackOrigin"
		attack_origin.position = Vector3(0.0, (1.1 if body_kind == "humanoid" else 0.6) * body_scale, 0.0)
		add_child(attack_origin)
	hurtbox = get_node_or_null("Hurtbox") as Hurtbox
	if hurtbox == null:
		hurtbox = Hurtbox.create(self, capsule_radius + 0.08, capsule_height, capsule_height * 0.5)
		add_child(hurtbox)
	else:
		hurtbox.actor = self
	stamina_comp = get_node_or_null("Stamina") as StaminaComponent
	if stamina_comp == null:
		stamina_comp = StaminaComponent.new()
		stamina_comp.name = "Stamina"
		add_child(stamina_comp)
	poise_comp = get_node_or_null("Poise") as PoiseComponent
	if poise_comp == null:
		poise_comp = PoiseComponent.new()
		poise_comp.name = "Poise"
		add_child(poise_comp)
	status = get_node_or_null("Status") as StatusEffects
	if status == null:
		status = StatusEffects.new()
		status.name = "Status"
		add_child(status)
	caster = get_node_or_null("SpellCaster") as SpellCaster
	if caster == null:
		caster = SpellCaster.new()
		caster.name = "SpellCaster"
		add_child(caster)
	anim = get_node_or_null("AnimationDriver") as AnimationDriver
	if anim == null:
		anim = AnimationDriver.new()
		anim.name = "AnimationDriver"
		add_child(anim)


func _setup_components() -> void:
	stamina_comp.setup(DamageModel.stamina_max(endurance))
	poise_comp.setup(poise_max)
	status.actor = self
	caster.setup(self, will)
	caster.skill_lookup = func(def: Dictionary) -> float: return get_skill(SpellRuntime.skill_for(def))
	anim.setup(model, body_kind, tint, body_scale, body_variant)
	# Method references, not closures, all the way down: a closure is not disconnected when
	# the actor that made it is freed, and one on a component that outlived its owner is a
	# call into nothing once per stat change for the rest of the process.
	stamina_comp.changed.connect(_on_pool_changed)
	poise_comp.changed.connect(_on_pool_changed)
	caster.mana_changed.connect(_on_pool_changed)
	poise_comp.broken.connect(_on_poise_broken)
	status.damage_tick.connect(_on_status_damage)
	status.expired.connect(_on_status_expired)
	anim.clip_event.connect(_on_clip_event)
	anim.clip_finished.connect(_on_clip_finished)


func _on_pool_changed(_current: float, _maximum: float) -> void:
	stats_changed.emit()


# --- stat properties (coordinator contract: health/max_health/stamina/... as floats) ----------

func set_health(v: float) -> void:
	health = clampf(v, 0.0, max_health)
	health_changed.emit(health, max_health)
	stats_changed.emit()


func _get_stamina() -> float:
	return stamina_comp.current if stamina_comp else 0.0


func _set_stamina(v: float) -> void:
	if stamina_comp:
		stamina_comp.current = clampf(v, 0.0, stamina_comp.maximum)
		stats_changed.emit()


func _get_max_stamina() -> float:
	return stamina_comp.maximum if stamina_comp else 0.0


func _set_max_stamina(v: float) -> void:
	if stamina_comp:
		stamina_comp.setup(v, false)


func _get_poise() -> float:
	return poise_comp.current if poise_comp else 0.0


func _set_poise(v: float) -> void:
	if poise_comp:
		poise_comp.current = clampf(v, 0.0, poise_comp.maximum)
		stats_changed.emit()


func _get_max_poise() -> float:
	return poise_comp.maximum if poise_comp else 0.0


func _set_max_poise(v: float) -> void:
	if poise_comp:
		poise_comp.maximum = maxf(v, 1.0)
		poise_comp.current = minf(poise_comp.current, poise_comp.maximum)


func _get_mana() -> float:
	return caster.mana if caster else 0.0


func _set_mana(v: float) -> void:
	if caster:
		caster.mana = clampf(v, 0.0, caster.mana_max)
		stats_changed.emit()


func _get_max_mana() -> float:
	return caster.mana_max if caster else 0.0


func _set_max_mana(v: float) -> void:
	if caster:
		caster.mana_max = maxf(v, 0.0)
		caster.mana = minf(caster.mana, caster.mana_max)


# --- queries ------------------------------------------------------------------------------------

func is_dead() -> bool:
	return dead


func is_alive() -> bool:
	return not dead


func forward() -> Vector3:
	return -global_transform.basis.z


func content_id() -> String:
	return ""


## Skill level used for damage; the progression stream overrides this on the player.
func get_skill(_skill_id: String) -> float:
	return 10.0


func is_hostile_to(other: Node) -> bool:
	if other == null or other == self or not (other is Actor):
		return false
	var o := other as Actor
	if o.faction == faction:
		return false
	if faction == "player" or o.faction == "player":
		return true
	return hostile_to.has(o.faction) or o.hostile_to.has(faction)


func is_stunned() -> bool:
	return now() < stunned_until or (status != null and status.blocks_actions())


## True when a new voluntary action may start.
func can_act() -> bool:
	return not dead and not is_stunned()


## Subclasses report whether a committed action (attack, cast, dodge) is in progress.
func is_busy() -> bool:
	return false


func is_riposte_open() -> bool:
	return now() < riposte_open_until


## Whether this body is rolling, or has just come out of a roll (a Player's is_rolling). Only a
## body that rolls says so.
func is_rolling() -> bool:
	return false


## A swing that went live at this body while it rolled: a dodge, as a lesson counts it
## (EventBus.act_done "dodge"), once for each blow. It used to be counted only when the swing's
## hitbox touched the body inside its i-frames, so a roll that carried the body out of the swing's
## reach, the roll a lesson means by "roll through his swing", never counted, nor did one that
## rolled into a riposte a moment early (playtest 2026-09-27, 5). The swinger calls this as its
## blow goes live (Enemy._open_hitbox) and take_hit when the blow finds the body in its i-frames;
## the second of the two for one blow is not counted again.
func count_dodge(attacker: Node) -> void:
	var t := now()
	var key := attacker.get_instance_id() if attacker != null and is_instance_valid(attacker) else 0
	if t - float(_dodges_counted.get(key, -100.0)) < DODGE_COUNTED_FOR_S:
		return
	_dodges_counted[key] = t
	EventBus.act_done.emit("dodge", self, attacker, "")


func is_invulnerable() -> bool:
	var t := now()
	return t >= invulnerable_from and t < invulnerable_until


func lock_point() -> Vector3:
	return global_position + Vector3.UP * ((1.15 if body_kind == "humanoid" else 0.6) * body_scale)


func speed_multiplier() -> float:
	return status.speed_multiplier() if status else 1.0


# --- what perks, potions and worn enchantments change ---------------------------------------------

## The modifier table this body's perks, potions and worn enchantments feed (Progression.mods), or
## null for a body that has none (an enemy, a test double). A perk's promise is kept by reading its
## stat through here at the moment the thing it names happens.
func stat_mods() -> Modifiers:
	return null


## Product of every multiplier on `stat` (1 for a body with no table).
func stat_mult(stat: String) -> float:
	var m := stat_mods()
	return m.get_mult(stat) if m != null else 1.0


## Sum of every addition to `stat` (0 for a body with no table).
func stat_add(stat: String) -> float:
	var m := stat_mods()
	return m.get_add(stat) if m != null else 0.0


## How long before a blow a raised guard still turns it into a parry: DESIGN §5.3's 0.18 s, widened
## by whatever widens it (Ready Answer: +0.06 s).
func parry_window() -> float:
	return DamageModel.PARRY_WINDOW + stat_add("parry_window")


## This body's resistance to a kind of harm: its own, plus what a potion or a worn enchantment adds
## (`resist_fire` +0.25 from a Resist Fire draught).
func resist_to(kind: String) -> float:
	return DamageModel.resist_of(resists, kind) + stat_add("resist_" + kind)


## An arrow or bolt that struck this body and can be recovered from it once it has fallen.
func lodge(item_id: String, count: int = 1) -> void:
	if item_id.is_empty() or count <= 0:
		return
	lodged[item_id] = int(lodged.get(item_id, 0)) + count


# --- hit resolution -----------------------------------------------------------------------------

## Resolves one incoming hit. Returns "dead", "dodged", "parried", "blocked" or "hit".
func take_hit(hit: HitData) -> String:
	if dead:
		return "dead"
	var t := now()
	if hit.dodgeable and is_invulnerable():
		hit_taken.emit(hit, "dodged")
		count_dodge(hit.attacker)
		return "dodged"
	var to_origin := hit.origin - global_position
	_blow_from = hit.origin
	_blow_at = t
	var facing := DamageModel.is_facing(forward(), to_origin)
	if hit.attacker != null and hit.attacker != self:
		last_attacker = hit.attacker
	last_hit_skill = hit.skill_id
	if hit.parryable and can_parry and facing and DamageModel.parry_succeeds(parry_pressed_at, t, parry_window()):
		parry_pressed_at = -100.0
		if hit.attacker is Actor and is_instance_valid(hit.attacker):
			(hit.attacker as Actor).open_riposte(DamageModel.RIPOSTE_OPEN_DURATION)
		anim.play_intent("Parry")
		Foley.play("parry_clang", _struck_at())
		Impact.land(self, hit, "parried")
		hit_taken.emit(hit, "parried")
		EventBus.act_done.emit("parry", self, hit.attacker, "")
		return "parried"
	if hit.blockable and is_blocking and facing:
		var raw := hit.amount * hit.crit_mult
		var through := DamageModel.block_damage(raw, block_stability)
		var final := DamageModel.apply_defence(through, armour_flat, resist_to(hit.kind))
		stamina_comp.spend(DamageModel.block_stamina_cost(raw, block_stability))
		_apply_damage(final, hit.kind, hit.attacker, hit.label)
		if dead:
			return "hit"
		if stamina_comp.is_exhausted():
			is_blocking = false
			guard_broken.emit()
			stagger(1.0)
		else:
			poise_comp.apply(hit.poise_damage * 0.5, hit.heavy)
			if not is_stunned():
				anim.play_intent("Block_Hit")
		Foley.play("block_clang", _struck_at())
		Impact.land(self, hit, "blocked")
		hit_taken.emit(hit, "blocked")
		EventBus.act_done.emit("block", self, hit.attacker, "")
		return "blocked"
	var raw_full := hit.amount * hit.crit_mult
	var dmg := DamageModel.apply_defence(raw_full, armour_flat, resist_to(hit.kind))
	# The blow lands on whatever the body is made of: flesh, mail, stone or wood, heard with the rest
	# of it where the blade meets the body (Impact)
	Impact.land(self, hit, "hit")
	_apply_damage(dmg, hit.kind, hit.attacker, hit.label)
	if dead:
		hit_taken.emit(hit, "hit")
		return "hit"
	for s in hit.statuses:
		status.apply(str(s.get("id", "")), float(s.get("duration", -1.0)), float(s.get("magnitude", -1.0)), hit.attacker)
	var push_dir := -to_origin
	push_dir.y = 0.0
	push_dir = push_dir.normalized() if push_dir.length_squared() > 0.0001 else -forward()
	if hit.knockback > 0.0:
		_add_shove(push_dir, hit.knockback)
	if hit.crit_kind == "riposte" or hit.crit_kind == "backstab":
		riposte_open_until = -100.0
		stunned_until = maxf(stunned_until, t + RIPOSTE_VICTIM_STUN)
		on_action_interrupted()
		# a riposte lands from in front and rocks the body back; a backstab (or any crit from behind
		# or the side) throws it the way it was struck, as a stagger does
		var crit_react := "Hit_Heavy"
		if not Impact.way_of(forward(), to_origin).is_empty():
			crit_react = reaction_clip("Stagger", hit.origin)
		anim.play_intent(crit_react, {"length": RIPOSTE_VICTIM_STUN})
	elif hit.knockdown:
		knock_down(push_dir)
	elif not poise_comp.apply(hit.poise_damage, hit.heavy):
		if not is_busy() and not is_stunned():
			anim.play_intent(reaction_clip("Hit_Light", hit.origin))
	hit_taken.emit(hit, "hit")
	return "hit"


func _apply_damage(amount: float, kind: String, attacker: Node, label: String) -> float:
	var dealt := amount
	if shield_hp > 0.0 and now() < shield_until:
		var absorbed := minf(shield_hp, dealt)
		shield_hp -= absorbed
		dealt -= absorbed
		shield_changed.emit(shield_hp)
		# a Ward that took a blow is a lesson learned (a mage's `ward` act)
		if absorbed > 0.0:
			EventBus.act_done.emit("ward", self, attacker, "")
	if dealt > 0.0:
		health = health - dealt
	EventBus.damage_dealt.emit(attacker, self, amount, kind)
	if health <= 0.0 and not dead:
		die(attacker)
	return dealt


## Damage that bypasses hit resolution (falls, hazards, damage-over-time).
func apply_raw_damage(amount: float, kind: String = "blunt", attacker: Node = null) -> void:
	if dead or amount <= 0.0:
		return
	_apply_damage(amount, kind, attacker, "raw")


func heal(amount: float) -> void:
	if dead or amount <= 0.0:
		return
	health = health + amount


## Puts stamina and breath back, the way `heal` puts health back, so what a potion does can be
## said in one vocabulary (Consumables.plan).
func restore_stamina(amount: float) -> void:
	if dead or amount <= 0.0 or stamina_comp == null:
		return
	stamina_comp.restore(amount)


func restore_mana(amount: float) -> void:
	if dead or amount <= 0.0 or caster == null:
		return
	caster.restore_mana(amount)


## Carries out what Consumables.plan() worked out from an item's effects. Actors take their
## own potions; nothing else has to know how an effect def is shaped.
func take_effects(entries: Array) -> void:
	if dead:
		return
	for step in Consumables.plan(entries):
		match str(step.get("kind", "")):
			"stat":
				var method := str(Consumables.STAT_METHOD.get(str(step["stat"]), ""))
				if method != "" and has_method(method):
					call(method, float(step["amount"]))
			"status":
				status.apply(str(step["id"]), float(step["duration"]), float(step["magnitude"]), self)
			"cure":
				status.clear_many(step["ids"])
			"modifier":
				_apply_timed_modifier(step)


## A buff is a modifier with a clock on it. Actors without a modifier table (an enemy, a test
## double) simply do not get the buff rather than failing.
func _apply_timed_modifier(step: Dictionary) -> void:
	var mods_node: Node = get_node_or_null(NodePath("Progression"))
	if mods_node == null or not mods_node.has_method("add_timed_modifier"):
		return
	mods_node.call("add_timed_modifier", str(step["source"]), step["mods"], float(step["duration"]))


func add_shield(amount: float, duration: float) -> void:
	shield_hp = maxf(shield_hp, amount)
	shield_until = now() + duration
	status.apply("warded", duration)
	shield_changed.emit(shield_hp)


## The reaction to a blow from `origin`: `base` ("Hit_Light", "Stagger") is the one to a blow from
## in front; a blow from behind or from either side plays its _B, _L or _R when the body has it.
func reaction_clip(base: String, origin: Vector3) -> String:
	var way := Impact.way_of(forward(), origin - global_position)
	if way.is_empty():
		return base
	var named := "%s_%s" % [base, way]
	var body: Node = anim.model if anim != null else null
	# a placeholder body plays the front's reaction whichever way it was struck
	if body != null and body.has_method("has_clip") and bool(body.call("has_clip", named)):
		return named
	return base


func stagger(duration: float = 0.8) -> void:
	if dead:
		return
	stunned_until = maxf(stunned_until, now() + duration)
	status.apply("stagger", duration)
	on_action_interrupted()
	# thrown the way the blow that broke the guard or the poise threw it, when there was one
	var clip := reaction_clip("Stagger", _blow_from) if now() - _blow_at <= BLOW_REMEMBERED_S else "Stagger"
	anim.play_intent(clip, {"length": duration})
	Foley.play("stagger_thud", _struck_at())
	staggered.emit()
	# whoever's blow did it, when it was a blow (a lesson's "a heavy swing staggers the other")
	if now() - _blow_at <= BLOW_REMEMBERED_S and last_attacker != null and is_instance_valid(last_attacker):
		EventBus.act_done.emit("stagger", last_attacker, self, "")


func knock_down(direction: Vector3) -> void:
	if dead:
		return
	if not status.apply("knockdown"):
		stagger(0.8)
		return
	stunned_until = maxf(stunned_until, now() + KNOCKDOWN_DURATION + GET_UP_DURATION)
	# Off your feet carries you at least this far; a blow that already throws you further does not
	# throw you further still for putting you down.
	_add_shove(direction, maxf(KNOCKDOWN_SHOVE - shove_left(), 0.0))
	on_action_interrupted()
	anim.play_intent("Knockdown", {"length": KNOCKDOWN_DURATION})
	knocked_down.emit()


## Called on the attacker whose swing was parried: helpless for `duration`, riposte deals 3×.
func open_riposte(duration: float = DamageModel.RIPOSTE_OPEN_DURATION) -> void:
	if dead:
		return
	riposte_open_until = now() + duration
	stunned_until = maxf(stunned_until, riposte_open_until)
	on_action_interrupted()
	anim.play_intent("Stagger", {"length": duration})
	riposte_opened.emit(duration)


func set_invulnerable_window(from: float, until: float) -> void:
	invulnerable_from = from
	invulnerable_until = until


func clear_invulnerability() -> void:
	invulnerable_from = -100.0
	invulnerable_until = -100.0


## Subclasses cancel their committed action here (close hitboxes, drop state).
func on_action_interrupted() -> void:
	pass


func die(killer: Node = null) -> void:
	if dead:
		return
	dead = true
	health = 0.0
	is_blocking = false
	collision_layer = 0
	hurtbox.set_enabled(false)
	status.clear_all()
	on_action_interrupted()
	anim.play_intent("Death_A")
	died.emit(killer)
	EventBus.entity_killed.emit(self, killer, content_id())


## Brings a dead actor back at full strength (respawn / hearthstone reset).
func revive() -> void:
	dead = false
	lodged.clear()
	last_hit_skill = ""
	hurtbox.set_enabled(true)
	anim.stop()
	full_restore()


func full_restore() -> void:
	health = max_health
	stamina_comp.refill()
	poise_comp.reset()
	caster.refill()
	status.clear_all()
	shield_hp = 0.0
	stunned_until = -100.0
	riposte_open_until = -100.0
	clear_invulnerability()
	shove = Vector3.ZERO
	stats_changed.emit()


# --- reactions ----------------------------------------------------------------------------------

func _on_poise_broken() -> void:
	stagger(0.8)


func _on_status_damage(id: String, amount: float, kind: String) -> void:
	if dead:
		return
	var dmg := maxf(amount * (1.0 - resist_to(kind)), 0.0)
	if dmg > 0.0:
		_apply_damage(dmg, kind, last_attacker if is_instance_valid(last_attacker) else null, "status:" + id)


func _on_status_expired(id: String) -> void:
	if id == "knockdown" and not dead:
		anim.play_intent("Get_Up", {"length": GET_UP_DURATION})


func _on_clip_event(_event_name: String) -> void:
	pass


func _on_clip_finished(_clip: String) -> void:
	pass


# --- sockets ------------------------------------------------------------------------------------

## Node names cannot contain '.', so the contract's `Socket.WeaponR` becomes the node
## `Socket_WeaponR`. The BoneAttachment3D still targets the exact bone name from CONTRACTS §2.
static func socket_node_name(socket_name: String) -> String:
	return socket_name.replace(".", "_")


## Equipment attachment point (CONTRACTS §2): a BoneAttachment3D when the rig exists, else a
## Marker3D placeholder at the rig's approximate position. Look up by the contract name.
func get_socket(socket_name: String) -> Node3D:
	if _sockets.has(socket_name) and is_instance_valid(_sockets[socket_name]):
		return _sockets[socket_name]
	var node_name := socket_node_name(socket_name)
	var found := model.find_child(node_name, true, false) as Node3D
	if found == null:
		var skeleton := _find_skeleton(model)
		if skeleton != null and skeleton.find_bone(socket_name) >= 0:
			var att := BoneAttachment3D.new()
			att.name = node_name
			att.bone_name = socket_name
			att.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # follows the animation per frame
			skeleton.add_child(att)
			found = att
	if found == null:
		var marker := Marker3D.new()
		marker.name = node_name
		marker.position = PLACEHOLDER_SOCKETS.get(socket_name, Vector3(0.0, 1.0, 0.0)) * body_scale
		model.add_child(marker)
		found = marker
	_sockets[socket_name] = found
	return found


func _find_skeleton(root: Node) -> Skeleton3D:
	if root is Skeleton3D:
		return root
	for c in root.get_children():
		var s := _find_skeleton(c)
		if s != null:
			return s
	return null


# --- movement helpers ---------------------------------------------------------------------------

## Keeps this body real (BodyGuard): a NaN or runaway body is put back on its last good ground.
## Call once a physics frame after the move; `home` (() -> Vector3) is where it goes with none.
## Returns true when it was put back.
var body_guard := BodyGuard.new()

func guard_body(delta: float, home := Callable()) -> bool:
	return body_guard.check(self, delta, on_ground(), home)


func apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y < 0.0:
		velocity.y = -0.5


## The water a foe or a villager stands or swims in (the player has its own State.SWIM on the same
## Swimmer). Read after the body has chosen where to go: past the knee it wades slower, and in water
## deeper than its chest it floats with its head at the surface, its model in the swim, rather than
## walking the bed with the water over its head. Returns the share of its pace the water leaves it
## (1 on dry land); `floating` says whether it is afloat this tick.
var water: Swimmer = null
var floating := false


func water_tick(delta: float) -> float:
	if water == null:
		water = Swimmer.new()
	water.body_scale = body_scale
	var provider: Object = World.terrain()
	var bed := NAN
	if provider != null and provider.has_method("get_height"):
		bed = float(provider.call("get_height", global_position.x, global_position.z))
	water.read(global_position, bed)
	var was := floating
	if floating:
		floating = not water.can_stand()
	else:
		floating = water.deep_enough()
	if floating:
		velocity.y = clampf((water.float_feet_y() - global_position.y) * Swimmer.FLOAT_SPRING, -Swimmer.FLOAT_MOST, Swimmer.FLOAT_MOST)
	if floating != was and anim != null:
		anim.set_swimming(floating)
	if floating:
		return Swimmer.SWIM_SPEED / maxf(Vector2(velocity.x, velocity.z).length(), Swimmer.SWIM_SPEED)
	return water.wade_mult()


## Holds a body on the heightfield where no collider holds it. Terrain3D builds its collision
## round the camera `World.follow` gives it (world.gd), and the coarse fallback ground has its own,
## so in the game a body on open ground stands on a collider; where there is none (a test or a
## tool, or ground whose collision is not built yet) it would sink. This puts it back on the
## ground from below, and down the last GROUND_SKIN to keep it on a descent. An interior sits in
## its own pocket high above the map, and a bridge or a roof is above the ground, so neither is
## disturbed.
## It stands down while a collider holds the body, and never pulls a rising body down. The two
## surfaces are not one on a slope: a capsule of radius r resting on the collider stands
## r(1/cos θ - 1) above the height under its middle, 2.2 cm at 20° and 10.7 cm at 40°. Pulled down
## to it every tick, it sank into the slope and the collider pushed it back downhill: a jog made
## 48% of its pace up 35°, 17% up 40°, and a walk could not get onto a 40° slope. And a jump rises
## 7.7 cm in its first tick, inside the skin, so it was pulled back down every tick and never left.
## Returns true when the heightfield was what held the body up this frame.
func snap_to_terrain() -> bool:
	if not is_inside_tree() or is_on_floor():
		return false
	var provider: Object = World.terrain()
	if provider == null or not provider.has_method("get_height"):
		return false
	var ground: float = float(provider.call("get_height", global_position.x, global_position.z))
	if global_position.y > ground + GROUND_SKIN:
		return false
	if velocity.y > 0.0 and global_position.y > ground:
		return false
	global_position.y = ground
	if velocity.y < 0.0:
		velocity.y = 0.0
	return true


## Where on the body a blow is heard: chest height.
func _struck_at() -> Vector3:
	return global_position + Vector3.UP * capsule_height * 0.6 if is_inside_tree() else Vector3.INF


## Standing on something: a floor collider, or the terrain heightfield bodies are snapped to.
func on_ground() -> bool:
	if is_on_floor():
		return true
	var provider: Object = World.terrain()
	if provider == null or not provider.has_method("get_height") or not is_inside_tree():
		return false
	return global_position.y <= float(provider.call("get_height", global_position.x, global_position.z)) + GROUND_SKIN


## The footsteps this body's movement makes this frame (Footfalls), and the surface they land on
## for Stealth. Call once per physics frame after moving.
func step_sounds(delta: float, volume_db: float = 0.0) -> void:
	if dead:
		return
	var pace := Vector2(velocity.x, velocity.z).length()
	var under := _footfalls.advance(self, delta, pace, on_ground(), body_scale, volume_db)
	if not under.is_empty():
		surface = under


## Pushes the body `metres` along `direction` (HitData.knockback is metres), over the next few
## frames, whatever it is doing meanwhile.
## Two shoves add as distances, not as speeds (speeds would add up to far more than the sum).
func _add_shove(direction: Vector3, metres: float) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if metres <= 0.0 or flat.length_squared() < 0.0001:
		return
	var carried := shove.normalized() * shove_left() if shove.length_squared() > 0.0001 else Vector3.ZERO
	var total := carried + flat.normalized() * metres
	shove = total.normalized() * sqrt(2.0 * SHOVE_DECEL * total.length()) if total.length_squared() > 0.0001 else Vector3.ZERO


## How many metres the shove still has to carry the body, on open ground.
func shove_left() -> float:
	return shove.length_squared() / (2.0 * SHOVE_DECEL)


## Moves the body by this frame's share of the shove and runs the shove down. The shove is its own
## motion, never folded into `velocity`: it used to be added to the velocity every frame, so a body
## whose state only damps its velocity (stunned, knocked down) summed sixty shoves a second, and a
## bristleback's charge threw the player at 140 m/s off the edge of the world (`./run.sh fights`).
func integrate_shove(delta: float) -> void:
	if shove.length_squared() < 0.0001:
		shove = Vector3.ZERO
		return
	var hit := move_and_collide(Vector3(shove.x, 0.0, shove.z) * delta)
	if hit != null:
		# A wall takes the part of the shove that points into it; the rest slides along it.
		shove = shove.slide(hit.get_normal())
		shove.y = 0.0
	shove = shove.move_toward(Vector3.ZERO, SHOVE_DECEL * delta)


## Turns the body toward a world point at turn_speed rad/s.
func face_toward(point: Vector3, turn_speed: float, delta: float) -> void:
	var d := point - global_position
	d.y = 0.0
	if d.length_squared() < 0.0001:
		return
	var target_yaw := atan2(-d.x, -d.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(turn_speed * delta, 0.0, 1.0))


func snap_facing(direction: Vector3) -> void:
	var d := Vector3(direction.x, 0.0, direction.z)
	if d.length_squared() > 0.0001:
		rotation.y = atan2(-d.x, -d.z)


func yaw_to(point: Vector3) -> float:
	var d := point - global_position
	return atan2(-d.x, -d.z)


# --- save ---------------------------------------------------------------------------------------

func to_save() -> Dictionary:
	return {
		"health": health,
		"position": [global_position.x, global_position.y, global_position.z],
		"yaw": rotation.y,
		"dead": dead,
		"status": status.to_save(),
	}


func from_save(d: Dictionary) -> void:
	if d.has("position") and d["position"] is Array and d["position"].size() == 3:
		var p: Array = d["position"]
		global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	rotation.y = float(d.get("yaw", rotation.y))
	if is_inside_tree():
		reset_physics_interpolation()     # a load puts a body somewhere; it does not walk it there
	status.from_save(d.get("status", {}))
	if bool(d.get("dead", false)):
		die(null)
	else:
		health = float(d.get("health", max_health))
