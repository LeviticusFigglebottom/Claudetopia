extends TestCase
## The bestiary as content: every creature in WORLD_BIBLE §8 exists, names only animation clips
## that CONTRACTS §3 allows, resolves its loot, carries tags the radiant boards can filter on,
## and is listed in its region's ecology. Anything dangling here is a content problem that the
## dangling-reference walk cannot see, because clips and tags are plain strings by design.

## CONTRACTS §3, verbatim. A humanoid enemy may only name one of these.
const HUMANOID_CLIPS: Array[String] = [
	"Idle", "Idle_Combat", "Walk", "Walk_Back", "Run", "Strafe_L", "Strafe_R", "Sneak_Idle",
	"Sneak_Walk", "Jump_Start", "Jump_Loop", "Jump_Land", "Fall_Loop",
	"Dodge_F", "Dodge_B", "Dodge_L", "Dodge_R",
	"Attack_1H_Light_1", "Attack_1H_Light_2", "Attack_1H_Light_3", "Attack_1H_Heavy",
	"Attack_2H_Light_1", "Attack_2H_Light_2", "Attack_2H_Heavy",
	"Attack_Dagger_1", "Attack_Dagger_2", "Attack_Unarmed_1", "Attack_Unarmed_2",
	"Riposte", "Backstab",
	"Block_Idle", "Block_Hit", "Parry", "Hit_Light", "Hit_Heavy", "Stagger", "Knockdown",
	"Get_Up", "Death_A", "Death_B",
	"Bow_Draw", "Bow_Aim", "Bow_Release", "Cast_Quick", "Cast_Long", "Cast_Loop", "Throw",
	"Interact", "Pick_Up", "Sit_Down", "Sit_Idle", "Stand_Up", "Sleep_Idle",
	"Work_Hammer", "Work_Chop", "Work_Stir", "Work_Dig", "Talk_1", "Talk_2",
	"Wave", "Bow_Gesture", "Laugh", "Rude", "Dance", "Cheer", "Cower", "Point",
	"Drink", "Eat", "Read",
]
## CONTRACTS §3: a creature rig must at least provide these, plus whatever it declares.
const CREATURE_CLIPS: Array[String] = ["Idle", "Walk", "Run", "Attack_1", "Attack_2", "Hit", "Death"]

## The traits `RadiantGenerator._enemies_for` narrows a pool by, read off the shipped templates.
## An enemy that carries none of these can never be the subject of a job board notice.
const BOUNTY_TRAITS: Array[String] = ["bandit", "raider", "outlaw", "smuggler", "poacher", "brigand"]
const HUNT_TRAITS: Array[String] = ["beast", "animal", "pack", "charger", "vermin"]
const CLEAR_TRAITS: Array[String] = ["swarm", "pack", "vermin", "brute"]

## Every creature WORLD_BIBLE §8 promises, by region.
const BESTIARY := {
	"core:region/hearthvale": ["core:enemy/roadside_bandit", "core:enemy/down_wolf", "core:enemy/bristleback", "core:enemy/hedge_wight"],
	"core:region/brightwater": ["core:enemy/cutpurse", "core:enemy/gutter_drake", "core:enemy/bravo", "core:enemy/smuggler_sayer"],
	"core:region/sedgemire": ["core:enemy/bog_drowned", "core:enemy/sallowjaw", "core:enemy/wisp", "core:enemy/leech_hound"],
	"core:region/briarwold": ["core:enemy/thornhound", "core:enemy/weaver", "core:enemy/warden", "core:enemy/poacher", "core:enemy/hart_knight"],
	"core:region/skerrow": ["core:enemy/crag_wolf", "core:enemy/scree_hag", "core:enemy/stone_thrall", "core:enemy/clanless_raider"],
	"core:region/cinderlea": ["core:enemy/ash_wight", "core:enemy/chorister", "core:enemy/tolling_knight", "core:enemy/bell_bearer"],
}


## Every creature that lives somewhere. A summon-only body (what a Calling spell stands up)
## belongs to no region, drops nothing and appears on no bounty board, so the ecology rules
## below do not apply to it; `_all_enemies()` is for the rules that do apply to everything.
func _enemies() -> Array:
	var out: Array = []
	for def in ContentDB.all("enemy"):
		# a teacher stood up only for a lesson (the ring's sparring partner) lives nowhere either
		if not bool(def.get("summon_only", false)) and not bool(def.get("training", false)):
			out.append(def)
	return out


func _all_enemies() -> Array:
	return ContentDB.all("enemy")


func _attack_lists(def: Dictionary) -> Array:
	## Base attacks plus everything a broken limb or a boss phase can bring in.
	var out: Array = [def.get("attacks", [])]
	for limb in def.get("limbs", []):
		out.append((limb as Dictionary).get("add_attacks", []))
	for phase in def.get("phases", []):
		out.append((phase as Dictionary).get("attacks", []))
	return out


# --- the bible's list ---------------------------------------------------------------------------

func test_every_creature_in_the_bible_exists() -> void:
	for region in BESTIARY:
		for id in BESTIARY[region]:
			assert_true(ContentDB.has(str(id)), "WORLD_BIBLE §8 promises %s" % id)
			assert_eq(str(ContentDB.get_or_empty(str(id)).get("region", "")), str(region), "%s is filed under the wrong region" % id)


func test_no_creature_is_defined_twice_or_left_as_a_stub() -> void:
	var seen := {}
	for def in _enemies():
		var id := str(def["id"])
		assert_false(seen.has(id), "%s is defined twice" % id)
		seen[id] = true
		assert_false(str(def.get("notes", "")).contains("stub"), "%s is still a narrative stub" % id)


func test_every_creature_carries_the_whole_field_set() -> void:
	for def in _enemies():
		var id := str(def["id"])
		for key in ["name", "archetype", "rig", "faction", "tint", "lore", "region", "stats", "perception", "behaviour", "attacks", "marks", "tags", "loot"]:
			assert_has(def, key, "%s is missing '%s'" % [id, key])
		assert_gt(str(def["lore"]).length(), 180, "%s needs a journal paragraph, not a line" % id)
		assert_true(ContentDB.has(str(def["region"])), "%s names an unknown region" % id)
		for key in ["hp", "stamina", "poise", "armour", "speed"]:
			assert_has(def["stats"], key, "%s stats missing %s" % [id, key])
		var marks: Array = def["marks"]
		assert_eq(marks.size(), 2, "%s marks should be [min, max]" % id)
		assert_true(int(marks[0]) <= int(marks[1]), "%s marks are back to front" % id)


# --- CONTRACTS §3 ---------------------------------------------------------------------------------

func test_every_attack_names_a_clip_that_exists() -> void:
	for def in _enemies():
		var id := str(def["id"])
		var humanoid := str(def.get("rig", "humanoid")) == "humanoid"
		var allowed: Array = HUMANOID_CLIPS.duplicate()
		if not humanoid:
			allowed = def.get("clips", [])
			assert_false(allowed.is_empty(), "%s uses a creature rig and must declare its clips" % id)
			for required in CREATURE_CLIPS:
				assert_true(allowed.has(required), "%s clips are missing the required %s" % [id, required])
		for list in _attack_lists(def):
			for attack in list:
				var clip := str((attack as Dictionary).get("clip", ""))
				assert_true(allowed.has(clip), "%s/%s names clip '%s', which is not in its contract" % [id, (attack as Dictionary).get("name", "?"), clip])


func test_every_attack_has_a_rhythm_a_player_can_read() -> void:
	for def in _enemies():
		var id := str(def["id"])
		for list in _attack_lists(def):
			for a in list:
				var attack: Dictionary = a
				var name := str(attack.get("name", "?"))
				assert_gt(float(attack.get("telegraph", 0.0)), 0.3, "%s/%s has no wind-up" % [id, name])
				assert_gt(float(attack.get("recovery", 0.0)), 0.0, "%s/%s never recovers" % [id, name])
				assert_gt(float(attack.get("cooldown", 0.0)), 0.0, "%s/%s has no cooldown" % [id, name])
		# Two attacks that telegraph and recover identically are one attack twice.
		var attacks: Array = def.get("attacks", [])
		assert_true(attacks.size() >= 2, "%s needs at least two attacks" % id)
		var shapes := {}
		for a in attacks:
			var shape := "%.2f/%.2f/%.2f" % [float(a.get("telegraph", 0.0)), float(a.get("recovery", 0.0)), float(a.get("cooldown", 0.0))]
			assert_false(shapes.has(shape), "%s: '%s' has the same rhythm as '%s'" % [id, a.get("name", "?"), shapes.get(shape, "?")])
			shapes[shape] = str(a.get("name", "?"))


func test_every_attack_kind_and_status_is_one_the_code_runs() -> void:
	const KINDS: Array[String] = ["", "charge", "leap", "burst", "projectile", "spell"]
	for def in _enemies():
		var id := str(def["id"])
		for list in _attack_lists(def):
			for a in list:
				var attack: Dictionary = a
				var kind := str(attack.get("kind", ""))
				assert_true(KINDS.has(kind), "%s/%s has unknown kind '%s'" % [id, attack.get("name", "?"), kind])
				if kind == "spell":
					assert_true(ContentDB.has(str(attack.get("spell", ""))), "%s/%s casts an unknown spell" % [id, attack.get("name", "?")])
				if kind == "burst":
					assert_gt(EnemyAbilities.burst_radius(attack), float(attack.get("range", 0.0)) - 0.001, "%s/%s selects from further away than it reaches" % [id, attack.get("name", "?")])
				if attack.has("kind_damage"):
					assert_true(DamageModel.KINDS.has(str(attack["kind_damage"])), "%s/%s deals unknown damage kind" % [id, attack.get("name", "?")])
				for s in attack.get("statuses", []):
					assert_true(StatusEffects.RULES.has(str((s as Dictionary).get("id", ""))), "%s/%s applies unknown status '%s'" % [id, attack.get("name", "?"), (s as Dictionary).get("id", "")])


func test_every_archetype_is_one_the_brain_knows() -> void:
	for def in _enemies():
		assert_has(Brain.ARCHETYPES, str(def["archetype"]), "%s has archetype '%s'" % [def["id"], def["archetype"]])


# --- loot -----------------------------------------------------------------------------------------

func test_every_creature_drops_something_that_resolves() -> void:
	var rng := RandomNumberGenerator.new()
	for def in _enemies():
		var id := str(def["id"])
		var loot := str(def.get("loot", ""))
		if loot == "":
			continue                                  # hearthvale predates the loot field
		assert_true(ContentDB.has(loot), "%s points at missing loot table %s" % [id, loot])
		for level in [1, 10, 20]:
			rng.seed = hash(id) + level
			var results := LootTable.roll(loot, rng, {"region": str(def.get("region", "")), "level": level, "luck": 1.0, "flags": {}, "quests": {}})
			for r in results:
				if r.has("item"):
					assert_true(ContentDB.has(str(r["item"])), "%s rolled unknown item %s" % [loot, r["item"]])


func test_loot_tables_only_name_real_items_and_tables() -> void:
	for table in ContentDB.all("loot"):
		var entries: Array = table.get("entries", []) + table.get("guaranteed", [])
		assert_false(entries.is_empty(), "%s has nothing in it" % table["id"])
		for e in entries:
			var entry: Dictionary = e
			if entry.has("item"):
				assert_true(ContentDB.has(str(entry["item"])), "%s names unknown item %s" % [table["id"], entry["item"]])
			elif entry.has("table"):
				assert_true(ContentDB.has(str(entry["table"])), "%s nests unknown table %s" % [table["id"], entry["table"]])
			elif not entry.has("marks") and not entry.has("nothing"):
				fail("%s has an entry that drops nothing and says nothing: %s" % [table["id"], str(entry)])


# --- tags and the job boards ------------------------------------------------------------------------

func test_tags_use_the_vocabulary_the_boards_filter_on() -> void:
	const VOCABULARY: Array[String] = [
		"beast", "animal", "pack", "charger", "vermin", "swarm", "brute",
		"bandit", "raider", "outlaw", "smuggler", "poacher", "brigand",
		"person", "humanoid", "undead", "revenant", "caster", "spirit", "construct",
		"quadruped", "arachnid", "boar", "stone", "plant", "treant", "guardian",
		"sentinel", "knight", "lure", "miniboss", "unquiet", "tolling_order",
		"called", "warden",
	]
	for def in _all_enemies():
		var tags: Array = def.get("tags", [])
		assert_false(tags.is_empty(), "%s has no tags" % def["id"])
		for t in tags:
			assert_true(VOCABULARY.has(str(t)), "%s carries tag '%s', which nothing reads" % [def["id"], t])


func test_beasts_bandits_and_swarms_are_tagged_so_the_boards_can_find_them() -> void:
	# Spot-checks against the bible: what a thing *is* must be in its tags, or a wanted notice
	# can never name it.
	const EXPECTED := {
		"core:enemy/cutpurse": "bandit", "core:enemy/bravo": "bandit",
		"core:enemy/smuggler_sayer": "smuggler", "core:enemy/poacher": "poacher",
		"core:enemy/clanless_raider": "raider",
		"core:enemy/gutter_drake": "beast", "core:enemy/sallowjaw": "beast",
		"core:enemy/leech_hound": "pack", "core:enemy/thornhound": "pack",
		"core:enemy/crag_wolf": "pack", "core:enemy/weaver": "vermin",
		"core:enemy/ash_wight": "swarm", "core:enemy/bog_drowned": "swarm",
		"core:enemy/stone_thrall": "brute", "core:enemy/bell_bearer": "brute",
		"core:enemy/tolling_knight": "undead", "core:enemy/wisp": "spirit",
	}
	for id in EXPECTED:
		var tags: Array = ContentDB.get_or_empty(str(id)).get("tags", [])
		assert_true(tags.has(str(EXPECTED[id])), "%s should be tagged '%s'" % [id, EXPECTED[id]])


func test_every_region_can_fill_a_hunt_or_a_clearance_notice() -> void:
	# Not every region has outlaws (the marsh and the ash do not), and a board that cannot fill a
	# bounty simply offers other work. But every region must have something huntable or clearable,
	# or its board has nothing at all to say.
	for region_id in BESTIARY:
		var found := false
		for id in BESTIARY[region_id]:
			var tags: Array = ContentDB.get_or_empty(str(id)).get("tags", [])
			for t in HUNT_TRAITS + CLEAR_TRAITS:
				if tags.has(t):
					found = true
					break
		assert_true(found, "%s has nothing a job board could post about" % region_id)


func test_the_bounty_boards_of_the_settled_regions_have_a_quarry() -> void:
	for region_id in ["core:region/hearthvale", "core:region/brightwater", "core:region/briarwold", "core:region/skerrow"]:
		var found := false
		for id in BESTIARY[region_id]:
			var tags: Array = ContentDB.get_or_empty(str(id)).get("tags", [])
			for t in BOUNTY_TRAITS:
				if tags.has(t):
					found = true
					break
		assert_true(found, "%s has law and no outlaws for its bounty board" % region_id)


# --- region wiring -----------------------------------------------------------------------------------

func test_every_region_lists_its_ecology_and_every_entry_is_real() -> void:
	for region in ContentDB.all("region"):
		var ecology: Array = region.get("enemy_ecology", [])
		assert_false(ecology.is_empty(), "%s has an empty enemy_ecology; spawners and boards go hungry" % region["id"])
		for id in ecology:
			assert_true(ContentDB.has(str(id)), "%s lists missing enemy %s" % [region["id"], id])
			assert_eq(str(ContentDB.get_or_empty(str(id)).get("region", "")), str(region["id"]), "%s lists %s, which lives elsewhere" % [region["id"], id])
		assert_eq(ecology.size(), (BESTIARY[str(region["id"])] as Array).size(), "%s ecology does not match the bible" % region["id"])


func test_the_radiant_generator_finds_a_quarry_in_every_region() -> void:
	var radiant := RadiantGenerator.new(null, null, ContentDB)
	for region_id in BESTIARY:
		var hunted := radiant._enemies_for(str(region_id), HUNT_TRAITS + CLEAR_TRAITS)
		assert_false(hunted.is_empty(), "no radiant target in %s" % region_id)
		for id in hunted:
			assert_true(ContentDB.has(id))


# --- difficulty ---------------------------------------------------------------------------------------

func test_the_regions_get_harder_in_the_order_design_sets_out() -> void:
	# DESIGN §4.1 / the region defs' `danger`: Hearthvale is the start and Cinderlea the end.
	# The measure is the toughest thing in each region, because that is what sets its ceiling.
	# Brightwater is left out on purpose: it is danger 1 like Hearthvale, a city rather than a
	# step up, and its hardest thing (a hired bravo) is meant to sit beside the hedge-wight.
	var ceilings: Array = []
	for region_id in ["core:region/hearthvale", "core:region/sedgemire", "core:region/briarwold", "core:region/skerrow", "core:region/cinderlea"]:
		var worst := 0.0
		for id in BESTIARY[region_id]:
			var def := ContentDB.get_or_empty(str(id))
			var hp := float(def["stats"]["hp"])
			var best_hit := 0.0
			for a in def.get("attacks", []):
				best_hit = maxf(best_hit, float((a as Dictionary).get("damage", 0.0)))
			worst = maxf(worst, hp * 0.1 + best_hit)
		ceilings.append(worst)
	for i in range(1, ceilings.size()):
		assert_gt(float(ceilings[i]), float(ceilings[i - 1]), "region %d is not harder than the one before it (%s)" % [i, str(ceilings)])


func test_nothing_can_kill_a_careful_player_in_one_blow_or_survive_a_patient_one() -> void:
	# The budgets from DESIGN §5.3: a mid-game player has ~130 HP and hits for ~22 light / ~35
	# heavy with the gear of their region. Nothing should one-shot them from full, and nothing
	# should need more than forty landed heavies to fall over.
	const PLAYER_HP := 130.0
	const PLAYER_HEAVY := 35.0
	for def in _enemies():
		var id := str(def["id"])
		for a in def.get("attacks", []):
			assert_true(float((a as Dictionary).get("damage", 0.0)) < PLAYER_HP, "%s/%s one-shots a mid-game player" % [id, (a as Dictionary).get("name", "?")])
		var per_heavy := maxf(PLAYER_HEAVY - float(def["stats"]["armour"]), DamageModel.MIN_DAMAGE)
		var swings := float(def["stats"]["hp"]) / per_heavy
		assert_true(swings <= 40.0, "%s takes %.0f heavies to kill" % [id, swings])
		# And everything must be able to hurt a careless one: a creature whose best hit is a
		# scratch is scenery, not an enemy.
		var best := 0.0
		for a in def.get("attacks", []):
			best = maxf(best, float((a as Dictionary).get("damage", 0.0)))
		assert_gt(best, 5.0, "%s cannot hurt anybody" % id)


# --- the bosses, held to the same contract ----------------------------------------------------------

## Bosses are enemies filed under another type. Everything the bestiary must satisfy about clips,
## attack kinds, statuses and archetypes, a boss must satisfy too — and nothing did, because the
## checks above only walk `all("enemy")`.
func _bosses() -> Array:
	return ContentDB.all("boss")


func test_every_boss_in_the_bible_exists_with_a_fight_in_it() -> void:
	const PROMISED: Array[String] = [
		"core:boss/barrow_reeve", "core:boss/she_who_waits", "core:boss/hart_of_thorns",
		"core:boss/stone_thrall_king", "core:boss/last_cantor",
	]
	for id in PROMISED:
		assert_true(ContentDB.has(id), "WORLD_BIBLE §9 promises %s" % id)
		var def := ContentDB.get_or_empty(id)
		assert_true(ContentDB.has(str(def.get("arena", ""))), "%s fights nowhere" % id)
		assert_true(ContentDB.has(str(def.get("region", ""))), "%s belongs to no region" % id)
		var phases: Array = def.get("phases", [])
		assert_gt(phases.size(), 1, "%s needs a fight with turns in it" % id)
		assert_false((def.get("attacks", []) as Array).is_empty(), "%s opens with nothing to throw" % id)
		for i in phases.size():
			var p: Dictionary = phases[i]
			assert_has(p, "say", "%s has a phase that says nothing" % id)
			# The first phase may fight with the def's own attack set; a later one that adds
			# nothing is a phase change the player cannot see.
			if i > 0:
				assert_false((p.get("attacks", []) as Array).is_empty(), "%s phase %d changes nothing" % [id, i])
	assert_eq(_bosses().size(), PROMISED.size(), "the bible lists five bosses")


func test_every_boss_attack_names_a_clip_that_exists() -> void:
	for def in _bosses():
		var id := str(def["id"])
		var allowed: Array = HUMANOID_CLIPS.duplicate()
		if str(def.get("rig", "humanoid")) != "humanoid":
			allowed = def.get("clips", [])
			assert_false(allowed.is_empty(), "%s uses a creature rig and must declare its clips" % id)
			for required in CREATURE_CLIPS:
				assert_true(allowed.has(required), "%s clips are missing the required %s" % [id, required])
		for list in _attack_lists(def):
			for attack in list:
				var clip := str((attack as Dictionary).get("clip", ""))
				assert_true(allowed.has(clip), "%s/%s names clip '%s', which is not in its contract" % [id, (attack as Dictionary).get("name", "?"), clip])


func test_every_boss_attack_is_built_out_of_parts_the_code_runs() -> void:
	const KINDS: Array[String] = ["", "charge", "leap", "burst", "projectile", "spell"]
	for def in _bosses():
		var id := str(def["id"])
		for list in _attack_lists(def):
			for a in list:
				var attack: Dictionary = a
				var name := str(attack.get("name", "?"))
				assert_true(KINDS.has(str(attack.get("kind", ""))), "%s/%s has unknown kind '%s'" % [id, name, attack.get("kind", "")])
				if attack.has("kind_damage"):
					assert_true(DamageModel.KINDS.has(str(attack["kind_damage"])), "%s/%s deals unknown damage kind" % [id, name])
				for s in attack.get("statuses", []):
					assert_true(StatusEffects.RULES.has(str((s as Dictionary).get("id", ""))), "%s/%s applies unknown status" % [id, name])
				if attack.has("summons"):
					assert_true(ContentDB.has(str((attack["summons"] as Dictionary).get("enemy", ""))), "%s/%s calls up nothing that exists" % [id, name])
				if attack.has("spell"):
					assert_true(ContentDB.has(str(attack["spell"])), "%s/%s casts an unknown spell" % [id, name])
				assert_gt(float(attack.get("telegraph", 0.0)), 0.3, "%s/%s has no wind-up" % [id, name])
				# A second beat must name a first beat that this boss actually has.
				var after := str(attack.get("combo_from", ""))
				if after != "":
					assert_false(_attack_named(def, after).is_empty(), "%s/%s follows '%s', which it cannot throw" % [id, name, after])


func test_every_boss_archetype_and_limb_is_one_the_code_knows() -> void:
	for def in _bosses():
		var id := str(def["id"])
		assert_has(Brain.ARCHETYPES, str(def.get("archetype", "")), "%s has an unknown archetype" % id)
		for limb in def.get("limbs", []):
			var l: Dictionary = limb
			assert_true(["poise", "damage"].has(EnemyAbilities.limb_trigger(l)), "%s limb '%s' breaks on nothing the code checks" % [id, l.get("name", "?")])
			if not EnemyAbilities.limb_breaks_on_poise(l):
				assert_gt(EnemyAbilities.limb_damage_needed(l), 1.0, "%s limb '%s' needs a damage threshold" % [id, l.get("name", "?")])
			for removed in l.get("remove_attacks", []):
				assert_false(_attack_named(def, str(removed)).is_empty(), "%s limb '%s' removes '%s', which it never had" % [id, l.get("name", "?"), removed])


func test_every_boss_provides_what_the_boss_code_reads() -> void:
	# The reverse of the dead-data check: fields the code looks up that a def must supply.
	for def in _bosses():
		var id := str(def["id"])
		for key in ["name", "archetype", "stats", "behaviour", "perception", "attacks", "phases", "marks", "tags", "drops", "arena", "region", "lore"]:
			assert_has(def, key, "%s is missing '%s'" % [id, key])
		for key in ["hp", "stamina", "poise", "armour", "speed"]:
			assert_has(def["stats"], key, "%s stats missing %s" % [id, key])
		if str(def.get("rig", "humanoid")) != "humanoid":
			# A custom rig with no body kind is drawn as a quadruped, which no boss is.
			assert_has(def, "body", "%s uses a creature rig and must say what body it is" % id)
		if def.has("loot"):
			assert_true(ContentDB.has(str(def["loot"])), "%s points at a missing loot table" % id)
		# What it is made of, so that what you bring to the fight matters.
		assert_has(def, "resists", "%s takes a dagger exactly as well as a hammer" % id)
		var weak := false
		for kind in def["resists"]:
			assert_true(DamageModel.KINDS.has(str(kind)), "%s resists unknown damage kind '%s'" % [id, kind])
			if float(def["resists"][kind]) < 0.0:
				weak = true
		assert_true(weak, "%s has no weakness; there is nothing to work out" % id)


func test_a_channel_is_stoppable_or_says_plainly_that_it_is_not() -> void:
	# `channel`, `heals_self`, `interruptible` and `voice` only mean something together: a note
	# that heals and cannot be stopped by anything is a fight the player cannot win.
	for def in _bosses():
		var id := str(def["id"])
		for list in _attack_lists(def):
			for a in list:
				var attack: Dictionary = a
				if not EnemyAbilities.is_channel(attack):
					continue
				var name := str(attack.get("name", "?"))
				assert_gt(EnemyAbilities.channel_pulses(attack), 0, "%s/%s is a channel with no beats" % [id, name])
				if float(attack.get("heals_self", 0.0)) > 0.0:
					var stoppable := bool(attack.get("voice", false)) or bool(attack.get("interruptible", false))
					assert_true(stoppable, "%s/%s heals and cannot be stopped" % [id, name])
				assert_has(attack, "note", "%s/%s should say in the data how it is meant to be answered" % [id, name])


func test_the_bosses_get_harder_in_the_order_the_thread_meets_them() -> void:
	# The main thread's order: Hollin Barrow, the Nave, the Moot, Oskeld, the Seat.
	const ORDER: Array[String] = [
		"core:boss/barrow_reeve", "core:boss/she_who_waits", "core:boss/hart_of_thorns",
		"core:boss/stone_thrall_king", "core:boss/last_cantor",
	]
	var last := 0.0
	for id in ORDER:
		var def := ContentDB.get_or_empty(id)
		var worst := 0.0
		for list in _attack_lists(def):
			for a in list:
				worst = maxf(worst, float((a as Dictionary).get("damage", 0.0)))
		var weight := float(def["stats"]["hp"]) * 0.05 + worst
		assert_gt(weight, last, "%s is not a step up from the one before it" % id)
		last = weight


func _attack_named(def: Dictionary, name: String) -> Dictionary:
	for list in _attack_lists(def):
		for a in list:
			if str((a as Dictionary).get("name", "")) == name:
				return a
	return {}
