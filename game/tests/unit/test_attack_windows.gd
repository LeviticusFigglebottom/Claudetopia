extends TestCase
## Every swing in the pack has a hit window, and every enemy blow a wind-up before it can hurt.
##
## DESIGN §5.3: "Hitboxes are weapon-defined capsules active on animation frames (hit_start,
## hit_end per attack)". §5.4: "attack set with telegraph times". The first half walks the data:
## each weapon's swings, each enemy's and each boss's attacks, every phase. The second half stands
## every one of them up in its real body -- the forged humanoid where the def says humanoid -- and
## throws each attack, measuring the time from the telegraph to the moment the blow can hurt
## anybody. That half is the one that matters: until the AnimationDriver kept the time, a humanoid
## threw its blow on its clip's own schedule whatever the data said, so a hedge wight's authored
## one-second wind-up came out at 0.43 s, and nothing that only read the data could have seen it.

const FRAME := 1.0 / 60.0
## A wind-up shorter than this is not a telegraph a person can answer: roughly a quarter second to
## see it, and a roll's first i-frame is 0.08 s after that.
const MIN_TELEGRAPH := 0.3
## A window of one frame can be stepped over by a hitbox that moves.
const MIN_WINDOW := 2.0 * FRAME

var root: Node3D


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func after_each() -> void:
	if root != null and is_instance_valid(root):
		root.free()
	root = null


static func _event(timing: Dictionary, name: String) -> float:
	for e in timing.get("events", []):
		if str(e["name"]) == name:
			return float(e["t"])
	return -1.0


## Every attack an enemy or a boss can throw: its base set and each phase's, with where it came
## from. [[def_id, attack, where]]
static func _all_attacks() -> Array:
	var out: Array = []
	for type in ["enemy", "boss"]:
		for def in ContentDB.all(type):
			for a in def.get("attacks", []):
				out.append([str(def["id"]), a, "base"])
			var i := 0
			for phase in def.get("phases", []):
				for a in (phase as Dictionary).get("attacks", []):
					out.append([str(def["id"]), a, "phase %d" % i])
				i += 1
	return out


# --- the data ----------------------------------------------------------------------------------

func test_every_weapon_has_a_hit_window_for_every_swing_it_can_make() -> void:
	var swings := 0
	var weapons := 0
	for def in ContentDB.all("item"):
		if not def.has("weapon"):
			continue
		weapons += 1
		var id := str(def["id"])
		var w := WeaponInstance.new()
		w.configure(def, id)
		if w.is_ranged():
			var r: Dictionary = def.get("ranged", {})
			assert_true(float(r.get("draw_time", 0.0)) > 0.0 or float(r.get("reload_time", 0.0)) > 0.0,
				"%s is a bow with neither a draw nor a reload" % id)
			var ammo := ContentDB.get_or_empty(str(r.get("ammo_item", "")))
			assert_true(ammo.has("projectile"), "%s shoots %s, which has no projectile block" % [id, str(r.get("ammo_item", ""))])
			w.free()
			continue
		var attacks: Array = []
		for i in maxi(w.chain_length(), 1):
			attacks.append(["light", i])
		attacks.append_array([["heavy", 0], ["riposte", 0], ["backstab", 0]])
		for a in attacks:
			var t := w.timing_for(str(a[0]), int(a[1]))
			var length := float(t.get("length", 0.0))
			var hs := _event(t, "hit_start")
			var he := _event(t, "hit_end")
			var co := _event(t, "cancel_ok")
			var what := "%s %s %d (%s)" % [id, a[0], int(a[1]) + 1, w.clip_for(str(a[0]), int(a[1]))]
			assert_true(hs > 0.0, "%s: the hit window opens after the swing starts (hit_start %.3f)" % [what, hs])
			assert_true(he > hs + MIN_WINDOW - 0.0001, "%s: the window is at least two frames (%.3f-%.3f)" % [what, hs, he])
			assert_true(he <= length + 0.0001, "%s: the window closes inside the swing (%.3f of %.3f)" % [what, he, length])
			assert_true(co >= he - 0.0001, "%s: nothing is cancelled before the window closes (cancel_ok %.3f)" % [what, co])
			swings += 1
		w.free()
	assert_gt(weapons, 25, "the pack's weapons were read")
	assert_gt(swings, 100, "every swing of every weapon was walked (%d)" % swings)


func test_every_enemy_attack_winds_up_before_it_can_hurt() -> void:
	var walked := 0
	for entry in _all_attacks():
		var owner := str(entry[0])
		var a: Dictionary = entry[1]
		var what := "%s %s (%s)" % [owner, str(a.get("name", "?")), str(entry[2])]
		match str(a.get("kind", "")):
			"charge", "leap":
				# The run is wound up first, and the blow at the end of it is wound up again.
				assert_true(Enemy.CHARGE_WINDUP >= MIN_TELEGRAPH, "%s: the charge's wind-up" % what)
				assert_true(float(a.get("telegraph", 0.0)) >= MIN_TELEGRAPH, "%s: the blow after the run winds up %.2f s" % [what, float(a.get("telegraph", 0.0))])
			"spell":
				var spell := ContentDB.get_or_empty(str(a.get("spell", "")))
				assert_false(spell.is_empty(), "%s: casts %s, which does not exist" % [what, str(a.get("spell", ""))])
				assert_true(SpellRuntime.cast_time_of(spell) >= MIN_TELEGRAPH, "%s: a %.2f s cast is its wind-up" % [what, SpellRuntime.cast_time_of(spell)])
			_:
				var tel := float(a.get("telegraph", 0.0))
				assert_true(tel >= MIN_TELEGRAPH, "%s: a %.2f s telegraph" % [what, tel])
				var timing := Enemy.attack_timing(a)
				var live := _event(timing, "hit_start")
				if live < 0.0:
					live = _event(timing, "channel_start")
				assert_near(live, tel, 0.0001, "%s: the blow is live at the end of its telegraph" % what)
		walked += 1
	assert_gt(walked, 90, "every enemy and boss attack was walked (%d)" % walked)


# --- the running game --------------------------------------------------------------------------

## Every enemy and boss, in its real body, throws every attack it has; the wind-up is measured from
## the telegraph it signals to the moment the blow can land: its hitbox opening, its burst going
## off, its arrow leaving, its note being held, its spell being released, or its charge setting off.
func test_every_enemy_in_its_own_body_winds_up_for_as_long_as_it_says() -> void:
	root = Node3D.new()
	root.name = "WindUps"
	_tree().root.add_child(root)
	var by_owner: Dictionary = {}
	for entry in _all_attacks():
		if not by_owner.has(entry[0]):
			by_owner[entry[0]] = []
		(by_owner[entry[0]] as Array).append(entry)
	var results: Array = []
	var running := {"n": 0}
	var slot := 0
	for owner in by_owner.keys():
		var e := Enemy.new()
		e.configure(str(owner))
		root.add_child(e)
		e.global_position = Vector3(float(slot % 8) * 40.0, 0.0, float(slot / 8) * 40.0)
		e.perception.enabled = false
		e.set_physics_process(false)
		var mark := Node3D.new()
		root.add_child(mark)
		mark.global_position = e.global_position + Vector3(0.0, 0.0, -30.0)
		e.target = mark
		slot += 1
		running["n"] = int(running["n"]) + 1
		_throw_all(e, by_owner[owner], results, running)
	for i in 1200:
		if int(running["n"]) == 0:
			break
		await _tree().physics_frame
	assert_eq(int(running["n"]), 0, "every enemy finished throwing its attacks")
	var humanoid := 0
	var worst := 0.0
	for r in results:
		var what := str(r["what"])
		if bool(r["humanoid"]):
			humanoid += 1
		assert_true(float(r["measured"]) >= 0.0, "%s never went live" % what)
		var off := float(r["measured"]) - float(r["authored"])
		worst = maxf(worst, absf(off))
		assert_true(absf(off) <= FRAME * 1.01, "%s: authored %.3f s, measured %.3f s" % [what, float(r["authored"]), float(r["measured"])])
	print("MEASURE | enemy wind-ups, authored against measured, %d attacks (%d on the humanoid rig) | 0 frames apart | worst %.3f s | " % [results.size(), humanoid, worst])
	assert_gt(results.size(), 90, "the attacks were thrown")
	assert_gt(humanoid, 30, "and the humanoid rig threw its share")


func _throw_all(e: Enemy, entries: Array, results: Array, running: Dictionary) -> void:
	await _tree().physics_frame
	for entry in entries:
		var a: Dictionary = entry[1]
		var kind := str(a.get("kind", ""))
		var marks := {"tel": -1, "live": -1}
		var on_tel := func(_n: String, _d: float) -> void:
			if int(marks["tel"]) < 0:
				marks["tel"] = Engine.get_physics_frames()
		var on_live := func(_n: Variant = null, _m: Variant = null) -> void:
			if int(marks["live"]) < 0 and int(marks["tel"]) >= 0:
				marks["live"] = Engine.get_physics_frames()
		e.telegraph.connect(on_tel)
		e.attack_launched.connect(on_live)
		e.channel_started.connect(on_live)
		e.caster.cast_released.connect(on_live)
		var authored := float(a.get("telegraph", 0.6))
		if kind == "spell":
			authored = SpellRuntime.cast_time_of(ContentDB.get_or_empty(str(a.get("spell", ""))))
		elif kind == "charge" or kind == "leap":
			authored = Enemy.CHARGE_WINDUP * 0.95      # charge_go: the run sets off
		e.on_action_interrupted()
		e._global_cooldown = 0.0
		e._begin_attack(a)
		for i in int((authored + 1.0) / FRAME):
			if (kind == "charge" or kind == "leap") and e._charging and int(marks["live"]) < 0:
				marks["live"] = Engine.get_physics_frames()
			if int(marks["live"]) >= 0:
				break
			await _tree().physics_frame
		e.telegraph.disconnect(on_tel)
		e.attack_launched.disconnect(on_live)
		e.channel_started.disconnect(on_live)
		e.caster.cast_released.disconnect(on_live)
		var measured := -1.0
		if int(marks["tel"]) >= 0 and int(marks["live"]) >= 0:
			measured = float(int(marks["live"]) - int(marks["tel"])) * FRAME
		results.append({"what": "%s %s (%s)" % [str(entry[0]), str(a.get("name", "?")), str(entry[2])],
			"authored": authored, "measured": measured, "humanoid": e.anim.has_real_model()})
		e.on_action_interrupted()
		e.full_restore()
		await _tree().physics_frame
	running["n"] = int(running["n"]) - 1
