extends TestCase
## Every perk, taken the way a character takes one and measured where it is meant to show.
##
## A perk is a line of text and a stat key. Nine of the keys had a reader and twenty-eight had
## none, so most of the perk screen was a promise with nothing behind it. Each test here puts a
## real character (the player scene: Progression, Inventory, Equipment, Crafting) on a real floor,
## raises the perk's skill to where the perk opens, takes whatever it requires first, measures the
## thing the text names, takes the perk with a perk point, and measures it again. What is compared
## is the change the perk alone makes. Each measurement prints a line:
##     ./run.sh test --filter=test_perks_do_what_they_say | grep PERK
##
## The last test is the tripwire: a perk whose stat key nothing in the game reads fails it.

const SWORD := "core:item/iron_sword"
const GREATSWORD := "core:item/iron_greatsword"
const DAGGER := "core:item/iron_dagger"
const BOW := "core:item/hunting_bow"
const ARROW := "core:item/arrow"
const SHIELD := "core:item/round_shield"
const PLATE: Array[String] = ["core:item/clan_bone_helm", "core:item/clan_plate", "core:item/clan_plate_gauntlets", "core:item/clan_plate_sabatons"]
const LEATHER: Array[String] = ["core:item/leather_cap", "core:item/leather_jerkin", "core:item/leather_gloves", "core:item/leather_boots"]
const FOE := "core:enemy/roadside_bandit"
const LICHEN := "core:item/lichen"
const APPLE := "core:item/apple"
const WATERCRESS := "core:item/watercress"
const YEW := "core:item/yew_berry"
const FOXGLOVE := "core:item/foxglove"
const MOTE := "core:item/ember_mote"
const EMBER_BURST := "core:effect/ember_burst"
const FORTIFY_ARMOUR := "core:effect/fortify_armour"
const GREATSWORD_RECIPE := "core:recipe/iron_greatsword"
const INGOT := "core:item/iron_ingot"
const KINDLE := "core:spell/kindle_bolt"
const FROST := "core:spell/hush_frost"
const MEND := "core:spell/mend"
const WARD := "core:spell/ward"
const BINDING_WORD := "core:spell/binding_word"
const HOUND := "core:spell/call_the_hound"

var root: Node3D
var player: Player
var prog: Progression
var bag: Inventory
var doll: Equipment
var crafting: Crafting
## Nodes a test put outside `root` (loosed arrows land under the current scene).
var _strays: Array[Node] = []


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func before_each() -> void:
	GameState.set_flag("new_game", false)
	Peers.overrides.clear()
	root = Node3D.new()
	root.name = "PerkBench"
	_tree().root.add_child(root)
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 80.0)
	shape.shape = box
	shape.position = Vector3(0.0, -0.5, 0.0)
	ground.add_child(shape)
	root.add_child(ground)
	player = (load("res://actors/player/player.tscn") as PackedScene).instantiate() as Player
	root.add_child(player)
	player.global_position = Vector3(0.0, 0.02, 0.0)
	player.rotation.y = 0.0
	player.camera_rig.yaw = 0.0
	prog = player.get_node("Progression") as Progression
	bag = player.get_node("Inventory") as Inventory
	doll = player.get_node("Equipment") as Equipment
	crafting = player.get_node("Crafting") as Crafting


func after_each() -> void:
	for n in _strays:
		if is_instance_valid(n):
			n.free()
	_strays.clear()
	for n in _tree().current_scene.get_children():
		if n is Projectile or n is WorldItem:
			n.free()
	if is_instance_valid(root):
		root.free()
	root = null
	player = null
	Peers.overrides.clear()


# --- harness --------------------------------------------------------------------------------------

func _frames(n: int) -> void:
	for i in maxi(n, 1):
		await _tree().physics_frame


## Raises the perk's skill to where it opens and takes whatever it requires, so that what is
## measured next is the character just before this perk.
func _ready_for(perk_id: String) -> void:
	var d := Perks.def(perk_id)
	assert_false(d.is_empty(), "%s is in the pack" % perk_id)
	var skill := str(d.get("skill", ""))
	prog.skill_set.set_level(skill, maxi(prog.skill_level(skill), int(d.get("requires_level", 0))))
	var before := str(d.get("requires_perk", ""))
	if not before.is_empty() and not prog.has_perk(before):
		_ready_for(before)
		_take(before)


## Takes a perk the way a character does: one perk point, spent on it.
func _take(perk_id: String) -> void:
	prog.leveling.perk_points += 1
	assert_true(prog.take_perk(perk_id), "%s can be taken" % perk_id)


func _report(perk_id: String, what: String, before: float, after: float, expected: float) -> void:
	print("PERK | %s | %s | %.3f | %.3f | expected %.3f" % [Ids.name_of(perk_id), what, before, after, expected])


func _equip(item_id: String, data: Dictionary = {}) -> ItemStack:
	var stack := bag.add(item_id, 1, data)
	assert_true(stack != null and doll.equip(stack), "%s is worn" % item_id)
	return stack


## A foe that stands where it is put and does nothing on its own.
func _foe(at: Vector3, yaw := PI) -> Enemy:
	var e := Enemy.new()
	e.configure(FOE)
	e.position = at
	e.rotation.y = yaw
	root.add_child(e)
	e.spawn_position = at
	e.brain.post = at
	e.perception.enabled = false
	e.set_physics_process(false)
	return e


func _hit_from(foe: Node3D, amount: float) -> HitData:
	var h := HitData.new()
	h.amount = amount
	h.kind = "slash"
	h.attacker = foe
	h.origin = foe.global_position
	return h


## Looses one arrow at full draw and returns it in flight.
func _loose() -> Projectile:
	var before := {}
	for n in _tree().current_scene.get_children():
		before[n] = true
	player._fire_arrow(1.0)
	for n in _tree().current_scene.get_children():
		if n is Projectile and not before.has(n):
			return n as Projectile
	return null


class Ear extends Node:
	var heard: Array[float] = []

	func noise_heard(_pos: Vector3, loudness: float) -> void:
		heard.append(loudness)


# --- One-Handed -----------------------------------------------------------------------------------

func test_wardens_grip_one_handed_blades_deal_ten_percent_more() -> void:
	const PERK := "core:perk/wardens_grip"
	_ready_for(PERK)
	player.equip_weapon(GREATSWORD)
	var two_before := player.weapon.build_hit("light", 0, 0.0, player.get_skill("two_handed")).amount
	player.equip_weapon(SWORD)
	var before := player.weapon.build_hit("light", 0, 0.0, player.get_skill("one_handed")).amount
	_take(PERK)
	var after := player.weapon.build_hit("light", 0, 0.0, player.get_skill("one_handed")).amount
	player.equip_weapon(GREATSWORD)
	var two_after := player.weapon.build_hit("light", 0, 0.0, player.get_skill("two_handed")).amount
	_report(PERK, "sword light hit", before, after, before * 1.1)
	assert_near(after / before, 1.1, 0.0001, "a one-handed blade hits 10% harder")
	assert_near(two_after, two_before, 0.0001, "the grip is the one-handed grip: a greatsword is untouched")


func test_quick_steel_one_handed_lights_cost_fifteen_percent_less() -> void:
	const PERK := "core:perk/quick_steel"
	_ready_for(PERK)
	player.equip_weapon(SWORD)
	await _frames(2)
	var full := player.stamina_comp.current
	assert_true(player._start_attack("light", 0, false), "a light attack starts")
	var before := full - player.stamina_comp.current
	var heavy_before := player.weapon.stamina_cost("heavy")
	player._set_state(Player.State.FREE)
	player.weapon.end_attack()
	player.stamina_comp.refill()
	_take(PERK)
	full = player.stamina_comp.current
	assert_true(player._start_attack("light", 0, false), "and again")
	var after := full - player.stamina_comp.current
	_report(PERK, "stamina for a sword light", before, after, before * 0.85)
	assert_near(after, before * 0.85, 0.001, "the light attack costs 15% less")
	assert_near(player.weapon.stamina_cost("heavy"), heavy_before, 0.001, "a heavy is not a light attack")


func test_ringing_blow_one_handed_blades_deal_a_quarter_more_poise_damage() -> void:
	const PERK := "core:perk/ringing_blow"
	_ready_for(PERK)
	player.equip_weapon(SWORD)
	var before := player.weapon.build_hit("light", 0, 0.0, player.get_skill("one_handed")).poise_damage
	_take(PERK)
	var after := player.weapon.build_hit("light", 0, 0.0, player.get_skill("one_handed")).poise_damage
	_report(PERK, "sword poise damage", before, after, before * 1.25)
	assert_near(after / before, 1.25, 0.0001)
	# And it is felt: a foe's poise goes down by that much more.
	var foe := _foe(Vector3(0.0, 0.0, -1.2))
	var hit := player.weapon.build_hit("light", 0, 0.0, player.get_skill("one_handed"))
	hit.origin = player.global_position
	var poise_before := foe.poise
	foe.take_hit(hit)
	assert_near(poise_before - foe.poise, minf(after, poise_before), 0.001, "the foe loses the raised poise damage")


# --- Two-Handed -----------------------------------------------------------------------------------

func test_wide_sweep_two_handed_blades_deal_ten_percent_more() -> void:
	const PERK := "core:perk/wide_sweep"
	_ready_for(PERK)
	player.equip_weapon(GREATSWORD)
	var before := player.weapon.build_hit("heavy", 0, 1.0, player.get_skill("two_handed")).amount
	_take(PERK)
	var after := player.weapon.build_hit("heavy", 0, 1.0, player.get_skill("two_handed")).amount
	_report(PERK, "greatsword charged heavy", before, after, before * 1.1)
	assert_near(after / before, 1.1, 0.0001)


func test_hafted_poise_raises_poise_by_fifteen() -> void:
	const PERK := "core:perk/hafted_poise"
	_ready_for(PERK)
	var before := player.max_poise
	_take(PERK)
	var after := player.max_poise
	_report(PERK, "poise", before, after, before + 15.0)
	assert_near(after, before + 15.0, 0.001, "poise_max is raised by 15")
	assert_near(player.poise, after, 0.001, "and the body stands on all of it")


func test_bell_swing_heavies_cost_a_fifth_less() -> void:
	const PERK := "core:perk/bell_swing"
	_ready_for(PERK)
	player.equip_weapon(GREATSWORD)
	await _frames(2)
	var full := player.stamina_comp.current
	assert_true(player._start_attack("heavy", 0, false), "a heavy starts")
	var before := full - player.stamina_comp.current
	player._set_state(Player.State.FREE)
	player.weapon.end_attack()
	player.stamina_comp.refill()
	_take(PERK)
	full = player.stamina_comp.current
	assert_true(player._start_attack("heavy", 0, false), "and again")
	var after := full - player.stamina_comp.current
	_report(PERK, "stamina for a greatsword heavy", before, after, before * 0.8)
	assert_near(after, before * 0.8, 0.001)


# --- Archery --------------------------------------------------------------------------------------

func test_fernhold_draw_bows_draw_fifteen_percent_faster() -> void:
	const PERK := "core:perk/fernhold_draw"
	_ready_for(PERK)
	player.equip_weapon(BOW)
	var before := player.weapon.draw_time()
	_take(PERK)
	var after := player.weapon.draw_time()
	_report(PERK, "seconds to full draw", before, after, before / 1.15)
	assert_near(after, before / 1.15, 0.0001, "the draw is 15% faster")
	assert_near(before, float(ContentDB.get_or_empty(BOW)["ranged"]["draw_time"]), 0.0001, "and was the bow's own before")


func test_fletchers_thrift_a_quarter_more_arrows_survive() -> void:
	const PERK := "core:perk/fletchers_thrift"
	_ready_for(PERK)
	player.equip_weapon(BOW)
	bag.add(ARROW, 10)
	var first := _loose()
	assert_true(first != null, "an arrow flies")
	var before := first.recover_chance if first != null else -1.0
	_take(PERK)
	var second := _loose()
	var after := second.recover_chance if second != null else -1.0
	_report(PERK, "chance a loosed arrow survives", before, after, before + 0.25)
	assert_near(before, DamageModel.ARROW_RECOVERY, 0.0001, "the base share survives")
	assert_near(after, before + 0.25, 0.0001, "a quarter more of them")
	assert_eq(second.recover_item if second != null else "", ARROW, "and what survives is the arrow that flew")


func test_steady_breath_arrows_deal_fifteen_percent_more() -> void:
	const PERK := "core:perk/steady_breath"
	_ready_for(PERK)
	player.equip_weapon(BOW)
	bag.add(ARROW, 10)
	var first := _loose()
	var before := first.hit.amount if first != null else 0.0
	_take(PERK)
	var second := _loose()
	var after := second.hit.amount if second != null else 0.0
	_report(PERK, "arrow damage at full draw", before, after, before * 1.15)
	assert_gt(before, 0.0, "an arrow carries damage")
	assert_near(after / maxf(before, 0.001), 1.15, 0.0001)


# --- Block ----------------------------------------------------------------------------------------

func test_braced_stance_stability_while_blocking_rises_by_a_tenth() -> void:
	const PERK := "core:perk/braced_stance"
	_ready_for(PERK)
	player.equip_weapon(SWORD)
	_equip(SHIELD)
	var foe := _foe(Vector3(0.0, 0.0, -1.5))
	var stability_before := player.block_stability_value()
	player.is_blocking = true
	player.block_stability = player.block_stability_value()
	var hp := player.health
	assert_eq(player.take_hit(_hit_from(foe, 100.0)), "blocked")
	var through_before := hp - player.health
	player.health = player.max_health
	player.stamina_comp.refill()
	_take(PERK)
	var stability_after := player.block_stability_value()
	player.is_blocking = true
	player.block_stability = player.block_stability_value()
	hp = player.health
	assert_eq(player.take_hit(_hit_from(foe, 100.0)), "blocked")
	var through_after := hp - player.health
	_report(PERK, "guard stability", stability_before, stability_after, stability_before + 0.1)
	_report(PERK, "damage through the guard from 100", through_before, through_after, through_before - 10.0)
	assert_near(stability_after, stability_before + 0.1, 0.0001)
	assert_near(through_after, through_before - 10.0, 0.01, "a tenth more of the blow is stopped")


func test_ready_answer_widens_the_parry_window_by_six_hundredths() -> void:
	const PERK := "core:perk/ready_answer"
	_ready_for(PERK)
	player.equip_weapon(SWORD)
	_equip(SHIELD)
	var foe := _foe(Vector3(0.0, 0.0, -1.5))
	var before := player.parry_window()
	# A guard raised a fifth of a second before the blow: late by the book, in time with the perk.
	player.can_parry = true
	player.parry_pressed_at = Actor.now() - 0.2
	var late := player.take_hit(_hit_from(foe, 5.0))
	_take(PERK)
	var after := player.parry_window()
	player.can_parry = true
	player.parry_pressed_at = Actor.now() - 0.2
	var in_time := player.take_hit(_hit_from(foe, 5.0))
	_report(PERK, "parry window s", before, after, before + 0.06)
	assert_near(after, before + 0.06, 0.0001)
	assert_ne(late, "parried", "0.20 s early is outside DESIGN's 0.18 s")
	assert_eq(in_time, "parried", "and inside the widened 0.24 s")


# --- Armour ---------------------------------------------------------------------------------------

func test_broken_in_worn_armour_protects_ten_percent_better() -> void:
	const PERK := "core:perk/broken_in"
	_ready_for(PERK)
	for id in LEATHER:
		_equip(id)
	var foe := _foe(Vector3(0.0, 0.0, -1.5))
	var before := player.armour_flat
	var hp := player.health
	player.take_hit(_hit_from(foe, 50.0))
	var taken_before := hp - player.health
	player.health = player.max_health
	_take(PERK)
	var after := player.armour_flat
	hp = player.health
	player.take_hit(_hit_from(foe, 50.0))
	var taken_after := hp - player.health
	_report(PERK, "armour worn", before, after, before * 1.1)
	assert_gt(before, 0.0, "the leathers are armour")
	assert_near(after, before * 1.1, 0.0001)
	assert_near(taken_before - taken_after, after - before, 0.01, "a blow loses the extra armour's worth")


func test_second_skin_halves_armour_weights_toll_on_rolling_and_noise() -> void:
	const PERK := "core:perk/second_skin"
	_ready_for(PERK)
	for id in PLATE:
		_equip(id)
	player.equip_weapon(GREATSWORD)
	var stealth := Stealth.ensure()
	await _frames(1)
	player.velocity = Vector3(Stealth.WALK_SPEED, 0.0, 0.0)
	var noise_before := stealth.player_noise()
	var roll_before := player.roll_params()
	_take(PERK)
	player.velocity = Vector3(Stealth.WALK_SPEED, 0.0, 0.0)
	var noise_after := stealth.player_noise()
	var roll_after := player.roll_params()
	var plain := Stealth.noise_level(Stealth.WALK_SPEED, "light", false, player.surface, stealth.raining)
	_report(PERK, "walking noise in plate", noise_before, noise_after, plain * 1.35)
	_report(PERK, "roll load", player.load_ratio, player.dodge_load_ratio(), -1.0)
	assert_eq(Stealth.armour_weight_class(player), "heavy", "the plate is heard as heavy")
	assert_near(noise_before, plain * 1.7, 0.0001, "plate walks 1.7 times as loud as cloth")
	assert_near(noise_after, plain * 1.35, 0.0001, "and half that extra with the perk")
	assert_eq(str(roll_before["tier"]), "medium", "a plated body with a greatsword rolls as a medium load")
	assert_eq(str(roll_after["tier"]), "light", "with the plate counted at half its weight it rolls light")
	assert_gt(float(roll_after["iframe_end"]) - float(roll_after["iframe_start"]), float(roll_before["iframe_end"]) - float(roll_before["iframe_start"]), "and is safe for longer")


# --- Sneak ----------------------------------------------------------------------------------------

func test_quiet_step_movement_noise_is_thirty_percent_less() -> void:
	const PERK := "core:perk/quiet_step"
	_ready_for(PERK)
	var stealth := Stealth.ensure()
	var ear := Ear.new()
	ear.add_to_group("perceivers")
	root.add_child(ear)
	await _frames(2)
	player.velocity = Vector3(Stealth.WALK_SPEED, 0.0, 0.0)
	var model_before := stealth.player_noise()
	player._emit_noise(0.4)
	player._emit_action_noise(0.5)
	_take(PERK)
	player.velocity = Vector3(Stealth.WALK_SPEED, 0.0, 0.0)
	var model_after := stealth.player_noise()
	player._emit_noise(0.4)
	player._emit_action_noise(0.5)
	_report(PERK, "walking noise", model_before, model_after, model_before * 0.7)
	_report(PERK, "a jump heard", ear.heard[0], ear.heard[2], ear.heard[0] * 0.7)
	assert_near(model_after, model_before * 0.7, 0.0001, "the stealth model's movement noise")
	assert_near(ear.heard[2], ear.heard[0] * 0.7, 0.0001, "what a foe hears of a jump")
	assert_near(ear.heard[3], ear.heard[1], 0.0001, "a blade going live is no quieter for soft feet")


func test_light_fingers_pickpocket_chance_rises_by_fifteen_points() -> void:
	const PERK := "core:perk/light_fingers"
	_ready_for(PERK)
	Stealth.ensure()
	var mark := Node3D.new()
	mark.set_script(_mark_script())
	root.add_child(mark)
	var rng := _rng_that_rolls_under(0.5)
	var before := float(Stealth.instance.pickpocket(player, mark, "core:item/candle", rng)["chance"])
	_take(PERK)
	rng = _rng_that_rolls_under(0.5)
	var after := float(Stealth.instance.pickpocket(player, mark, "core:item/candle", rng)["chance"])
	_report(PERK, "pickpocket chance", before, after, before + 0.15)
	assert_near(after, before + 0.15, 0.0001)


func _mark_script() -> GDScript:
	var s := GDScript.new()
	s.source_code = "extends Node3D\nvar detection := 0.0\n"
	s.reload()
	return s


## A generator whose next roll is under `p`: the attempt succeeds, finds nothing to take from a mark
## with no pockets, and ends without a crime on the ledger.
func _rng_that_rolls_under(p: float) -> RandomNumberGenerator:
	var seed_ := 1
	while true:
		var probe := RandomNumberGenerator.new()
		probe.seed = seed_
		if probe.randf() < p:
			break
		seed_ += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_
	return rng


func test_unsaid_sneak_attacks_multiply_by_one_more() -> void:
	const PERK := "core:perk/unsaid"
	_ready_for(PERK)
	player.equip_weapon(SWORD)
	var foe := _foe(Vector3(0.0, 0.0, -1.2))
	await _frames(2)
	player.is_sneaking = true
	assert_true(foe.is_unaware(), "the foe has not noticed")
	assert_true(player._start_attack("light", 0, false), "a blow from the dark")
	var before := player.weapon.current_hit.crit_mult
	player._set_state(Player.State.FREE)
	player.weapon.end_attack()
	player.stamina_comp.refill()
	_take(PERK)
	player.is_sneaking = true
	assert_true(player._start_attack("light", 0, false), "and another")
	var after := player.weapon.current_hit.crit_mult
	_report(PERK, "sneak attack multiplier (sword)", before, after, before + 1.0)
	assert_near(before, 3.0, 0.0001, "DESIGN's x3")
	assert_near(after, 4.0, 0.0001, "one more")
	player._set_state(Player.State.FREE)
	player.weapon.end_attack()
	player.equip_weapon(DAGGER)
	player.stamina_comp.refill()
	player.is_sneaking = true
	assert_true(player._start_attack("light", 0, false), "with a dagger")
	assert_near(player.weapon.current_hit.crit_mult, 7.0, 0.0001, "a dagger's x6 becomes x7")


# --- Speech ---------------------------------------------------------------------------------------

func test_fair_dealing_buys_for_less_and_sells_for_more() -> void:
	const PERK := "core:perk/fair_dealing"
	_ready_for(PERK)
	var shop := Merchant.new()
	shop.npc_id = "core:npc/_perk_shop"
	shop.stock_table = "core:table/stock_general"
	shop.marks = 5000
	shop.buys = ["all"]
	shop.place_id = "core:place/merrowby"
	shop.restock_on_clock = false
	root.add_child(shop)
	shop.stock[GREATSWORD] = 6
	var buy_before := shop.buy_price_of(GREATSWORD)
	var sell_before := shop.sell_price_of(GREATSWORD)
	_take(PERK)
	var buy_after := shop.buy_price_of(GREATSWORD)
	var sell_after := shop.sell_price_of(GREATSWORD)
	_report(PERK, "buy price", buy_before, buy_after, buy_before * 0.9)
	_report(PERK, "sell price", sell_before, sell_after, sell_before * 1.1)
	assert_true(absf(buy_after - buy_before * 0.9) <= 1.0, "10%% less to buy: %d then %d" % [buy_before, buy_after])
	assert_true(absf(sell_after - sell_before * 1.1) <= 1.0, "10%% more to sell: %d then %d" % [sell_before, sell_after])
	# The trade itself is charged at that price, not only quoted it.
	bag.add_marks(5000)
	var r := shop.buy(player, GREATSWORD, 1)
	assert_true(bool(r["ok"]), "the sale goes through")
	assert_eq(int(r["price"]), buy_after, "and costs what was quoted")


func test_loud_name_deeds_travel_a_fifth_further() -> void:
	const PERK := "core:perk/loud_name"
	_ready_for(PERK)
	var standing: Node = Social.standing
	standing.reset_for_new_game()
	var before: int = standing.add_renown(50, "a song")
	_take(PERK)
	var after: int = standing.add_renown(50, "a song") - before
	_report(PERK, "renown from a deed worth 50", before, after, before * 1.2)
	assert_eq(before, 50)
	assert_eq(after, 60, "20% further")
	var lost: int = standing.add_renown(-10, "quieted") - (before + after)
	assert_eq(lost, -10, "what is lost is not made louder")
	standing.reset_for_new_game()


# --- Alchemy --------------------------------------------------------------------------------------

func _brewed_magnitude(a: String, b: String) -> float:
	bag.add(a, 1)
	bag.add(b, 1)
	var r := crafting.combine([a, b])
	assert_true(bool(r["ok"]), "%s and %s brew" % [a, b])
	var best := -1.0
	for s in bag.stacks():
		if s.id == str(r["item_id"]):
			best = float(s.effect_entries()[0]["magnitude"])
			bag.remove_stack(s, s.count)
			break
	return best


func test_hedge_wise_potions_are_a_fifth_stronger() -> void:
	const PERK := "core:perk/hedge_wise"
	_ready_for(PERK)
	var before := _brewed_magnitude(APPLE, WATERCRESS)
	_take(PERK)
	var after := _brewed_magnitude(APPLE, WATERCRESS)
	_report(PERK, "restore health brewed", before, after, before * 1.2)
	assert_near(after, before * 1.2, 0.11)


func test_forager_gathers_one_more_of_every_ingredient() -> void:
	const PERK := "core:perk/forager"
	_ready_for(PERK)
	var wild := WorldItem.new()
	wild.item_id = LICHEN
	root.add_child(wild)
	assert_true(wild.interact(player), "lichen is picked")
	var before := bag.count(LICHEN)
	bag.remove(LICHEN, before)
	_take(PERK)
	wild = WorldItem.new()
	wild.item_id = LICHEN
	root.add_child(wild)
	assert_true(wild.interact(player), "and picked again")
	var after := bag.count(LICHEN)
	_report(PERK, "lichen from one plant", before, after, before + 1)
	assert_eq(before, 1)
	assert_eq(after, 2, "one more")
	# What the character let fall is picked up as it went down: no more of it.
	bag.remove(LICHEN, after)
	bag.add(LICHEN, 1)
	var dropped := bag.drop(LICHEN, 1)
	await _frames(1)
	assert_true(dropped is WorldItem and (dropped as WorldItem).interact(player), "a dropped leaf is taken back")
	assert_eq(bag.count(LICHEN), 1, "as one leaf")


func test_bitter_tongue_poisons_are_thirty_percent_stronger() -> void:
	const PERK := "core:perk/bitter_tongue"
	_ready_for(PERK)
	var before := _brewed_magnitude(YEW, FOXGLOVE)
	var potion_before := _brewed_magnitude(APPLE, WATERCRESS)
	_take(PERK)
	var after := _brewed_magnitude(YEW, FOXGLOVE)
	var potion_after := _brewed_magnitude(APPLE, WATERCRESS)
	_report(PERK, "damage health brewed", before, after, before * 1.3)
	assert_near(after, before * 1.3, 0.11)
	assert_near(potion_after, potion_before, 0.0001, "a healing draught is not a poison")


# --- Smithing -------------------------------------------------------------------------------------

func test_red_door_every_temper_tier_is_worth_fifteen_percent() -> void:
	const PERK := "core:perk/red_door"
	_ready_for(PERK)
	var sword := _equip(SWORD, {"temper": 2})
	var coat := _equip("core:item/leather_jerkin", {"temper": 2})
	assert_true(sword != null and coat != null)
	var hit_before := player.weapon.build_hit("light", 0, 0.0, player.get_skill("one_handed")).amount
	var armour_before := player.armour_flat
	_take(PERK)
	var hit_after := player.weapon.build_hit("light", 0, 0.0, player.get_skill("one_handed")).amount
	var armour_after := player.armour_flat
	_report(PERK, "tier-2 sword hit", hit_before, hit_after, hit_before * 1.3 / 1.2)
	_report(PERK, "tier-2 jerkin armour", armour_before, armour_after, armour_before * 1.3 / 1.2)
	assert_near(hit_after / hit_before, 1.3 / 1.2, 0.0001, "two tiers are +30% instead of +20%")
	assert_near(armour_after / armour_before, 1.3 / 1.2, 0.0001, "on the armour worn as well")


func test_thrifty_forge_recipes_take_a_quarter_fewer_materials() -> void:
	const PERK := "core:perk/thrifty_forge"
	_ready_for(PERK)
	prog.skill_set.set_level("smithing", maxi(prog.skill_level("smithing"), 40))
	crafting.learn_recipe(GREATSWORD_RECIPE)
	bag.add(INGOT, 20)
	bag.add("core:item/leather", 5)
	assert_true(crafting.craft(GREATSWORD_RECIPE), "a greatsword is forged")
	var before := 20 - bag.count(INGOT)
	var left := bag.count(INGOT)
	_take(PERK)
	assert_true(crafting.craft(GREATSWORD_RECIPE), "and another")
	var after := left - bag.count(INGOT)
	_report(PERK, "ingots for a greatsword", before, after, ceilf(before * 0.75))
	assert_eq(before, 4)
	assert_eq(after, 3, "a quarter fewer, rounded up")


# --- Enchanting -----------------------------------------------------------------------------------

func _written(sword_note: String) -> Dictionary:
	var sword := bag.add(SWORD, 1)
	bag.add(MOTE, 4)
	assert_true(crafting.enchant(sword, sword_note, 4), "a note is written")
	return sword.enchantment()


func test_ember_keeper_notes_hold_a_quarter_more_charge() -> void:
	const PERK := "core:perk/ember_keeper"
	_ready_for(PERK)
	crafting.learn_enchantment(EMBER_BURST)
	var before := float(_written(EMBER_BURST).get("charge", 0.0))
	_take(PERK)
	var after := float(_written(EMBER_BURST).get("charge", 0.0))
	_report(PERK, "charge from four motes", before, after, before * 1.25)
	assert_near(after, before * 1.25, 0.01)


func test_deep_writing_enchantments_are_a_fifth_stronger() -> void:
	const PERK := "core:perk/deep_writing"
	_ready_for(PERK)
	crafting.learn_enchantment(EMBER_BURST)
	var before := float(_written(EMBER_BURST).get("magnitude", 0.0))
	_take(PERK)
	var note := _written(EMBER_BURST)
	var after := float(note.get("magnitude", 0.0))
	_report(PERK, "ember burst magnitude", before, after, before * 1.2)
	assert_near(after, before * 1.2, 0.11)
	# And the blade says it: the swing carries the written magnitude on top of the steel.
	player.equip_weapon(SWORD)
	var plain := player.weapon.build_hit("light", 0, 0.0, player.get_skill("one_handed")).amount
	player.equip_weapon(SWORD, {"enchant": note})
	var burning := player.weapon.build_hit("light", 0, 0.0, player.get_skill("one_handed")).amount
	assert_near(burning - plain, after, 0.001, "the stronger note is in the blow")


# --- Athletics ------------------------------------------------------------------------------------

func test_wind_in_the_chest_raises_stamina_by_fifteen() -> void:
	const PERK := "core:perk/wind_in_the_chest"
	_ready_for(PERK)
	var before := player.max_stamina
	_take(PERK)
	var after := player.max_stamina
	_report(PERK, "stamina", before, after, before + 15.0)
	assert_near(after, before + 15.0, 0.001)


func test_strong_back_carries_twenty_more() -> void:
	const PERK := "core:perk/strong_back"
	_ready_for(PERK)
	var before := bag.capacity()
	_take(PERK)
	var after := bag.capacity()
	_report(PERK, "carry capacity", before, after, before + 20.0)
	assert_near(after, before + 20.0, 0.001)


func test_roll_away_rolls_are_safe_longer_and_cheaper() -> void:
	const PERK := "core:perk/roll_away"
	_ready_for(PERK)
	await _frames(2)
	var full := player.stamina_comp.current
	assert_true(player._start_dodge(), "a roll")
	var cost_before := full - player.stamina_comp.current
	var safe_before := player.invulnerable_until - player.invulnerable_from
	await _frames(50)
	player._set_state(Player.State.FREE)
	player.stamina_comp.refill()
	_take(PERK)
	full = player.stamina_comp.current
	assert_true(player._start_dodge(), "another roll")
	var cost_after := full - player.stamina_comp.current
	var safe_after := player.invulnerable_until - player.invulnerable_from
	_report(PERK, "roll stamina", cost_before, cost_after, cost_before * 0.85)
	_report(PERK, "roll safe window s", safe_before, safe_after, safe_before + 0.05)
	assert_near(cost_after, cost_before * 0.85, 0.001, "15% less stamina")
	assert_near(safe_after, safe_before + 0.05, 0.0001, "a twentieth of a second longer")


# --- Kindling -------------------------------------------------------------------------------------

func _mana_for(spell_id: String) -> float:
	player.caster.refill()
	var full := player.caster.mana
	assert_true(player.caster.cast(spell_id), "%s is said" % spell_id)
	var spent := full - player.caster.mana
	player.caster.interrupt()
	return spent


func test_warm_word_kindling_costs_fifteen_percent_less() -> void:
	const PERK := "core:perk/warm_word"
	_ready_for(PERK)
	prog.learn_spell(KINDLE)
	prog.learn_spell(FROST)
	var before := _mana_for(KINDLE)
	var other_before := _mana_for(FROST)
	_take(PERK)
	var after := _mana_for(KINDLE)
	_report(PERK, "mana for a kindle bolt", before, after, before * 0.85)
	assert_near(after, before * 0.85, 0.001)
	assert_near(_mana_for(FROST), other_before, 0.001, "a Hush saying costs what it did")


func test_mote_catcher_catches_one_more_mote_from_a_kindled_foe() -> void:
	const PERK := "core:perk/mote_catcher"
	_ready_for(PERK)
	prog.learn_spell(KINDLE)
	var first := _foe(Vector3(0.0, 0.0, -5.0))
	first.health = 1.0
	var motes := bag.count(MOTE)
	assert_true(player.caster.cast(KINDLE, first), "a kindle bolt at the first foe")
	for i in 120:
		await _tree().physics_frame
		if first.dead:
			break
	assert_true(first.dead, "the bolt kills it")
	var before := bag.count(MOTE) - motes
	_take(PERK)
	var second := _foe(Vector3(0.0, 0.0, -5.0))
	second.health = 1.0
	motes = bag.count(MOTE)
	player.caster.refill()
	assert_true(player.caster.cast(KINDLE, second), "and at the second")
	for i in 120:
		await _tree().physics_frame
		if second.dead:
			break
	var after := bag.count(MOTE) - motes
	_report(PERK, "motes from a foe a Kindling word killed", before, after, before + 1)
	assert_eq(before, Enchanting.MOTES_PER_WARMTH, "a Kindling kill gives up its last warmth")
	assert_eq(after, before + 1, "one more")
	# A foe put down with steel keeps its warmth.
	var third := _foe(Vector3(0.0, 0.0, -1.2))
	motes = bag.count(MOTE)
	player.equip_weapon(SWORD)
	var blow := player.weapon.build_hit("light", 0, 0.0, player.get_skill("one_handed"))
	blow.amount = 999.0
	blow.origin = player.global_position
	third.take_hit(blow)
	assert_true(third.dead)
	assert_eq(bag.count(MOTE) - motes, 0, "a sword kill catches nothing")


# --- Hush -----------------------------------------------------------------------------------------

func test_quieted_hush_costs_fifteen_percent_less() -> void:
	const PERK := "core:perk/quieted"
	_ready_for(PERK)
	prog.learn_spell(FROST)
	var before := _mana_for(FROST)
	_take(PERK)
	var after := _mana_for(FROST)
	_report(PERK, "mana for a frost bolt", before, after, before * 0.85)
	assert_near(after, before * 0.85, 0.001)


# --- Binding --------------------------------------------------------------------------------------

func test_held_fast_wards_and_snares_last_thirty_percent_longer() -> void:
	const PERK := "core:perk/held_fast"
	_ready_for(PERK)
	prog.learn_spell(WARD)
	prog.learn_spell(BINDING_WORD)
	var foe := _foe(Vector3(0.0, 0.0, -4.0))
	player.caster.refill()
	assert_true(player.caster.cast(WARD))
	player.caster.advance(5.0)
	var ward_before := player.shield_until - Actor.now()
	var snare_before := _snare(foe)
	_take(PERK)
	player.caster.refill()
	assert_true(player.caster.cast(WARD))
	player.caster.advance(5.0)
	var ward_after := player.shield_until - Actor.now()
	var snare_after := _snare(foe)
	_report(PERK, "ward seconds", ward_before, ward_after, ward_before * 1.3)
	_report(PERK, "binding word hold seconds", snare_before, snare_after, snare_before * 1.3)
	assert_near(ward_after, ward_before * 1.3, 0.02)
	assert_gt(snare_before, 0.0, "the Binding word holds the foe")
	assert_near(snare_after, snare_before * 1.3, 0.02)


## How long a Binding word holds the foe it is said at.
func _snare(foe: Enemy) -> float:
	foe.status.clear_all()
	foe.stunned_until = -100.0
	foe.health = foe.max_health
	player.caster.refill()
	assert_true(player.caster.cast(BINDING_WORD, foe), "a Binding word at the foe")
	player.caster.advance(5.0)
	return foe.status.remaining("stagger")


# --- Mending --------------------------------------------------------------------------------------

func test_tender_mending_heals_a_fifth_more() -> void:
	const PERK := "core:perk/tender"
	_ready_for(PERK)
	prog.learn_spell(MEND)
	player.health = 10.0
	player.caster.refill()
	assert_true(player.caster.cast(MEND))
	player.caster.advance(5.0)
	var before := player.health - 10.0
	_take(PERK)
	player.health = 10.0
	player.caster.refill()
	assert_true(player.caster.cast(MEND))
	player.caster.advance(5.0)
	var after := player.health - 10.0
	_report(PERK, "health from Mend", before, after, before * 1.2)
	assert_gt(before, 0.0)
	assert_near(after, before * 1.2, 0.01)


# --- Calling --------------------------------------------------------------------------------------

func test_loud_company_what_you_call_stays_thirty_percent_longer() -> void:
	const PERK := "core:perk/loud_company"
	_ready_for(PERK)
	prog.learn_spell(HOUND)
	var before := _called_for()
	_take(PERK)
	var after := _called_for()
	_report(PERK, "seconds the hound stays", before, after, before * 1.3)
	assert_gt(before, 0.0, "the hound comes")
	assert_near(after, before * 1.3, 0.01)


## Calls the hound and returns how long it will stay.
func _called_for() -> float:
	var seen := {}
	for n in _tree().get_nodes_in_group("enemy"):
		seen[n] = true
	player.caster.refill()
	assert_true(player.caster.cast(HOUND), "the hound is called")
	player.caster.advance(5.0)
	for n in _tree().get_nodes_in_group("enemy"):
		if not seen.has(n) and n is Enemy and (n as Enemy).faction == "player":
			var left := (n as Enemy).life_left
			(n as Enemy).dismiss()
			return left
	return -1.0


# --- what the perks stand on --------------------------------------------------------------------

## A foe's eyes read the player's `stealth_visibility`, and nothing wrote it: a figure crouched in
## the dark was seen as plainly as one in noon sun. Stealth writes it now, every physics frame.
func test_what_a_foe_sees_of_the_player_follows_light_and_crouch() -> void:
	var stealth := Stealth.ensure()
	await _frames(2)
	stealth.sky_exposure_override = 1.0
	player.is_sneaking = false
	await _frames(2)
	var plain := player.stealth_visibility
	stealth.sky_exposure_override = 0.0
	player.is_sneaking = true
	await _frames(2)
	var hidden := player.stealth_visibility
	stealth.sky_exposure_override = -1.0
	print("PERK | stealth feed | visibility in the open, then crouched in shadow | %.3f | %.3f | lower" % [plain, hidden])
	assert_gt(plain, hidden, "crouched in shadow is harder to see than standing in the open")
	assert_true(hidden < 1.0, "and the foe's eyes are told so")


## A note written on armour (Fortify Armour) and a Resist draught are modifiers; the paper doll
## worked the first out and handed it to nothing, and nothing read the second.
func test_a_note_on_worn_armour_and_a_resist_draught_are_felt() -> void:
	var coat := bag.add("core:item/leather_jerkin", 1)
	coat.data["enchant"] = {"effect": FORTIFY_ARMOUR, "magnitude": 7.0, "charge": 0.0, "charge_max": 0.0, "charge_cost": 0.0}
	var bare := player.armour_flat
	assert_true(doll.equip(coat), "the written coat is worn")
	var worn := player.armour_flat
	assert_near(worn - bare, 6.0 + 7.0, 0.001, "the coat's 6 and the note's 7")
	var foe := _foe(Vector3(0.0, 0.0, -1.5))
	var burn := _hit_from(foe, 40.0)
	burn.kind = "fire"
	var hp := player.health
	player.take_hit(burn)
	var plain := hp - player.health
	player.health = player.max_health
	prog.add_timed_modifier("core:effect/resist_fire", [{"stat": "resist_fire", "add": 0.5}], 60.0)
	hp = player.health
	burn = _hit_from(foe, 40.0)
	burn.kind = "fire"
	player.take_hit(burn)
	var resisted := hp - player.health
	assert_near(resisted, plain * 0.5, 0.01, "half the fire is resisted")


## Arrows that survive are found again: one that stands in a wall becomes a pickup where it struck,
## and one that stays in a body comes out of it with the body's loot.
func test_an_arrow_that_survives_is_found_again() -> void:
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 4.0, 0.4)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(0.0, 1.5, -6.0)
	root.add_child(wall)
	var arrow := (load("res://systems/combat/arrow.tscn") as PackedScene).instantiate() as Projectile
	root.add_child(arrow)
	arrow.recover_item = ARROW
	arrow.recover_chance = 1.0
	var found := {"pickup": null}
	arrow.recovered.connect(func(p: Node) -> void: found["pickup"] = p)
	arrow.launch(Vector3(2.0, 1.5, -1.0), Vector3.FORWARD, 40.0, HitData.new(), 0.0)
	for i in 30:
		await _tree().physics_frame
		if found["pickup"] != null:
			break
	var pickup := found["pickup"] as WorldItem
	assert_true(pickup != null, "the arrow is left in the wall to be found")
	if pickup != null:
		assert_eq(pickup.item_id, ARROW)
		var had := bag.count(ARROW)
		assert_true(pickup.interact(player))
		assert_eq(bag.count(ARROW), had + 1, "and taken back into the quiver")
	var foe := _foe(Vector3(0.0, 0.0, -1.5))
	foe.lodge(ARROW, 2)
	var back := LootDrops.lodged_in(foe)
	assert_eq(back.size(), 1, "a body gives back what is lodged in it")
	if back.size() == 1:
		assert_eq(str(back[0]["item"]), ARROW)
		assert_eq(int(back[0]["count"]), 2)


# --- the tripwire ---------------------------------------------------------------------------------

## A perk whose stat key nothing in the game reads is text with nothing behind it. A key counts as
## read when a script outside the tests asks a modifier table for it by name (get_mult, get_add,
## apply, scale, stat_mult, stat_add, stat_mult_of, stat_add_of, school_mult), or asks for a family
## by its prefix ("damage_" + the weapon's skill, "spell_cost_" + the saying's school) and the key
## is that prefix and a real skill or school.
func test_every_perk_stat_has_a_reader() -> void:
	var exact := {}
	var prefixes := {}
	var reader := RegEx.new()
	reader.compile("\\b(?:get_mult|get_add|apply|scale|stat_mult|stat_add|stat_mult_of|stat_add_of|school_mult|_mult|_add)\\(\\s*(?:[A-Za-z_][A-Za-z0-9_.]*\\s*,\\s*)?\"([a-z_]+)\"\\s*(\\+|,)?")
	for path in _scripts("res://"):
		var text := FileAccess.get_file_as_string(path)
		for m in reader.search_all(text):
			var key := m.get_string(1)
			if key.ends_with("_") and m.get_string(2) != "":
				prefixes[key] = true
			else:
				exact[key] = true
	var suffixes: Array[String] = []
	for s in Player.SKILL_IDS:
		suffixes.append(s)
	for s in SpellRuntime.SCHOOLS:
		if not suffixes.has(s):
			suffixes.append(s)
	var unread: Array[String] = []
	var keys := 0
	for id in Perks.all_ids():
		for e in Perks.def(id).get("effects", []):
			var key := str(e.get("stat", ""))
			keys += 1
			var read := exact.has(key)
			if not read:
				for p in prefixes:
					if key.begins_with(str(p)) and suffixes.has(key.substr(str(p).length())):
						read = true
			if not read:
				unread.append("%s (%s)" % [key, Ids.name_of(id)])
	print("PERK | tripwire | %d perk stat keys, %d unread | %s" % [keys, unread.size(), ", ".join(unread)])
	assert_gt(keys, 30, "the perks were scanned")
	assert_empty(unread, "perk stats nothing reads")


func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if not name.begins_with("."):
			var path := dir.path_join(name)
			if d.current_is_dir():
				if not (name in ["tests", "addons", "tools_gd", "terrain_data", "generated", "assets"]):
					out.append_array(_scripts(path))
			elif name.ends_with(".gd"):
				out.append(path)
		name = d.get_next()
	d.list_dir_end()
	return out
