class_name SpellCaster
extends Node
## Runtime spell casting for one actor: mana pool, cast timer, and execution of the five
## implemented cast types (projectile, self, aura, target, summon). Rules come from SpellRuntime.
## Emits EventBus.skill_used(school skill, xp) on every completed cast.

signal cast_started(spell_id: String, cast_time: float)
signal cast_released(spell_id: String)
signal cast_failed(spell_id: String, reason: String)
signal mana_changed(current: float, maximum: float)

const MASK_HURTBOX := 1 << 5
const MASK_LOS := (1 << 0) | (1 << 10)

var actor: Node = null
var mana_max: float = 60.0
var mana: float = 60.0
var regen_per_s: float = SpellRuntime.MANA_REGEN_PER_S
var auto_advance: bool = true
## Optional: a Callable(spell_def) -> float giving the caster's skill for that school.
var skill_lookup: Callable = Callable()
## Optional: Callable() -> Node returning the current lock-on target for "target" spells.
var target_lookup: Callable = Callable()

var casting: bool = false
var current_spell_id: String = ""
var _def: Dictionary = {}
var _time_left: float = 0.0
var _explicit_target: Node = null
var _auras: Array[Dictionary] = []


func setup(owner_actor: Node, will: int) -> void:
	actor = owner_actor
	mana_max = SpellRuntime.mana_max(will)
	mana = mana_max
	mana_changed.emit(mana, mana_max)


func _physics_process(delta: float) -> void:
	if auto_advance:
		advance(delta)


func advance(delta: float) -> void:
	if not casting and mana < mana_max:
		mana = minf(mana_max, mana + regen_per_s * delta)
		mana_changed.emit(mana, mana_max)
	if casting:
		_time_left -= delta
		if _time_left <= 0.0:
			_release()
	_tick_auras(delta)


func skill_for(def: Dictionary) -> float:
	if skill_lookup.is_valid():
		return float(skill_lookup.call(def))
	return 0.0


func is_silenced() -> bool:
	if actor == null:
		return false
	var st: Node = actor.get("status")
	return st != null and st.has_method("blocks_casting") and st.blocks_casting()


## Starts a cast. Returns false (and emits cast_failed) when the rules refuse it.
func cast(spell_id: String, target: Node = null) -> bool:
	var def := ContentDB.get_or_empty(spell_id)
	var check := SpellRuntime.can_cast(def, mana, is_silenced(), skill_for(def), casting)
	if not bool(check["ok"]):
		cast_failed.emit(spell_id, str(check["reason"]))
		return false
	if str(def.get("cast_type")) == "target":
		var t := _resolve_target(target)
		if t == null:
			cast_failed.emit(spell_id, "no_target")
			return false
		_explicit_target = t
	else:
		_explicit_target = target
	mana -= SpellRuntime.cost_of(def, skill_for(def))
	mana_changed.emit(mana, mana_max)
	_def = def
	current_spell_id = spell_id
	_time_left = SpellRuntime.cast_time_of(def, skill_for(def))
	casting = true
	cast_started.emit(spell_id, _time_left)
	return true


## Interrupts the current cast (stagger, silence); mana already spent stays spent.
func interrupt() -> void:
	if casting:
		casting = false
		cast_failed.emit(current_spell_id, "interrupted")
		current_spell_id = ""


func restore_mana(amount: float) -> void:
	mana = clampf(mana + amount, 0.0, mana_max)
	mana_changed.emit(mana, mana_max)


func refill() -> void:
	mana = mana_max
	mana_changed.emit(mana, mana_max)


func _release() -> void:
	casting = false
	var def := _def
	var spell_id := current_spell_id
	current_spell_id = ""
	if is_silenced():
		cast_failed.emit(spell_id, "silenced")
		return
	match str(def.get("cast_type")):
		"projectile":
			_cast_projectile(def)
		"self":
			_apply_effects(actor, def, true)
		"aura":
			_start_aura(def)
		"target":
			_cast_target(def)
		"summon":
			_cast_summon(def)
	EventBus.skill_used.emit(SpellRuntime.skill_for(def), SpellRuntime.xp_for(def))
	cast_released.emit(spell_id)


func _origin_and_direction() -> Array:
	var origin: Vector3 = Vector3.ZERO
	var dir: Vector3 = Vector3.FORWARD
	if actor is Node3D:
		var a := actor as Node3D
		origin = a.global_position + Vector3.UP * 1.4
		dir = -a.global_transform.basis.z
		if actor.has_method("aim_direction"):
			dir = actor.aim_direction()
		if actor.has_method("aim_origin"):
			origin = actor.aim_origin()
	if _explicit_target is Node3D and is_instance_valid(_explicit_target):
		var tp: Vector3 = _explicit_target.lock_point() if _explicit_target.has_method("lock_point") else (_explicit_target as Node3D).global_position + Vector3.UP
		dir = (tp - origin).normalized()
	return [origin, dir]


func _cast_projectile(def: Dictionary) -> void:
	if not (actor is Node3D):
		return
	var od := _origin_and_direction()
	var origin: Vector3 = od[0]
	var dir: Vector3 = od[1]
	var p := Projectile.make_bolt(SpellRuntime.color_for(def))
	p.max_range = SpellRuntime.range_of(def)
	var tree := actor.get_tree()
	var parent: Node = tree.current_scene if tree.current_scene != null else tree.root
	parent.add_child(p)
	var hit := SpellRuntime.build_hit(def, actor, skill_for(def))
	p.launch(origin + dir * 0.6, dir, SpellRuntime.speed_of(def), hit, float(def.get("gravity", 0.0)))


func _cast_target(def: Dictionary) -> void:
	var t := _explicit_target
	_explicit_target = null
	if t == null or not is_instance_valid(t):
		return
	if not _in_range_and_sight(t, SpellRuntime.range_of(def)):
		return
	var friendly: bool = actor != null and actor.has_method("is_hostile_to") and not actor.is_hostile_to(t)
	_apply_effects(t, def, friendly)


## Calling: the spell names something and it stands up beside the caster for a while. The
## called body is an ordinary enemy def turned to the caster's side, so it fights, takes hits
## and dies like anything else — it simply lets go when its time is up and leaves nothing.
func _cast_summon(def: Dictionary) -> void:
	if not (actor is Node3D):
		return
	var spawner := EnemySpawner.for_node(actor)
	if spawner == null:
		Log.warn("SpellCaster", "nothing to hold the called: %s" % str(def.get("id", "")))
		return
	var host := actor as Node3D
	var forward := -host.global_transform.basis.z
	for e in SpellRuntime.effects_of(def):
		if str(e.get("type", "")) != "summon":
			continue
		var enemy_id := str(e.get("enemy", ""))
		if enemy_id.is_empty():
			continue
		var count := maxi(int(e.get("count", 1)), 1)
		var radius := float(e.get("radius", 2.5))
		var seconds := float(e.get("duration", def.get("duration", SpellRuntime.DEFAULT_SUMMON_SECONDS)))
		for i in count:
			var spread := deg_to_rad(40.0) * (float(i) - float(count - 1) * 0.5)
			var at := host.global_position + forward.rotated(Vector3.UP, spread) * radius
			var called := spawner.spawn_one(enemy_id, at, host.rotation.y, {"group": "called:" + str(def.get("id", ""))})
			if called == null:
				continue
			called.become_ally(seconds)
			EventBus.notify.emit("%s answers." % called.display_name, "spell")


func _start_aura(def: Dictionary) -> void:
	var duration := maxf(SpellRuntime.duration_of(def), 0.5)
	_auras.append({"def": def, "remaining": duration, "tick_left": 0.0, "interval": 0.5})


func _tick_auras(delta: float) -> void:
	if _auras.is_empty() or not (actor is Node3D):
		return
	for i in range(_auras.size() - 1, -1, -1):
		var a: Dictionary = _auras[i]
		a["remaining"] = float(a["remaining"]) - delta
		a["tick_left"] = float(a["tick_left"]) - delta
		if float(a["tick_left"]) <= 0.0:
			a["tick_left"] = float(a["interval"])
			var def: Dictionary = a["def"]
			for victim in _hurtbox_actors_within(SpellRuntime.radius_of(def)):
				var friendly: bool = actor.has_method("is_hostile_to") and not actor.is_hostile_to(victim)
				_apply_effects(victim, def, friendly, float(a["interval"]) / maxf(float(def.get("duration", 1.0)), 0.5))
		if float(a["remaining"]) <= 0.0:
			_auras.remove_at(i)


func _hurtbox_actors_within(radius: float) -> Array[Node]:
	var out: Array[Node] = []
	var a := actor as Node3D
	var space := a.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	q.shape = sphere
	q.transform = Transform3D(Basis.IDENTITY, a.global_position + Vector3.UP)
	q.collide_with_areas = true
	q.collide_with_bodies = false
	q.collision_mask = MASK_HURTBOX
	for r in space.intersect_shape(q, 32):
		var c: Object = r.get("collider")
		if c is Hurtbox and (c as Hurtbox).actor != null and not out.has((c as Hurtbox).actor):
			out.append((c as Hurtbox).actor)
	return out


func _resolve_target(explicit: Node) -> Node:
	if explicit != null and is_instance_valid(explicit):
		return explicit
	if target_lookup.is_valid():
		var t: Variant = target_lookup.call()
		if t is Node and is_instance_valid(t):
			return t
	return null


func _in_range_and_sight(t: Node, max_range: float) -> bool:
	if not (actor is Node3D and t is Node3D):
		return false
	var a := actor as Node3D
	var from := a.global_position + Vector3.UP * 1.4
	var to: Vector3 = t.lock_point() if t.has_method("lock_point") else (t as Node3D).global_position + Vector3.UP
	if from.distance_to(to) > max_range:
		return false
	var q := PhysicsRayQueryParameters3D.create(from, to, MASK_LOS)
	return a.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## Applies a spell's effects to one node. Hostile targets receive damage/status as a hit;
## friendly targets (and self) receive heals, shields and cleanses. `scale` thins aura ticks.
func _apply_effects(target: Node, def: Dictionary, friendly: bool, scale: float = 1.0) -> void:
	if target == null or not is_instance_valid(target):
		return
	var skill := skill_for(def)
	var hit_needed := false
	for e in SpellRuntime.effects_of(def):
		match str(e.get("type", "")):
			"heal":
				if friendly and target.has_method("heal"):
					target.heal(SpellRuntime.heal_amount(e, skill) * scale)
			"shield":
				if friendly and target.has_method("add_shield"):
					target.add_shield(float(e.get("amount", 0.0)) * DamageModel.skill_mult(skill), float(e.get("duration", 10.0)))
			"cleanse":
				var st: Node = target.get("status")
				if friendly and st != null and st.has_method("clear_many"):
					st.clear_many(e.get("ids", []))
			"damage", "status":
				if not friendly:
					hit_needed = true
	if hit_needed and target.has_method("take_hit"):
		var hit := SpellRuntime.build_hit(def, actor, skill)
		hit.amount *= scale
		hit.poise_damage *= scale
		hit.dodgeable = false
		hit.source = self
		if actor is Node3D:
			hit.origin = (actor as Node3D).global_position
		target.take_hit(hit)


func to_save() -> Dictionary:
	return {"mana": mana, "mana_max": mana_max}


func from_save(d: Dictionary) -> void:
	mana_max = float(d.get("mana_max", mana_max))
	mana = clampf(float(d.get("mana", mana_max)), 0.0, mana_max)
	mana_changed.emit(mana, mana_max)
