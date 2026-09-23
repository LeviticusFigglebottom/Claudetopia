extends TestCase
## StaminaComponent, PoiseComponent and StatusEffects. The components advance by hand
## (auto_advance off) so the rules are checked without a scene tree or real time.

var stamina: StaminaComponent
var poise: PoiseComponent
var status: StatusEffects


func before_each() -> void:
	stamina = StaminaComponent.new()
	stamina.auto_advance = false
	stamina.setup(100.0)
	poise = PoiseComponent.new()
	poise.auto_advance = false
	poise.setup(40.0)
	status = StatusEffects.new()
	status.auto_advance = false


func after_each() -> void:
	stamina.free()
	poise.free()
	status.free()


# --- stamina ----------------------------------------------------------------------------------

func test_spend_and_regen_delay() -> void:
	stamina.spend(18.0)
	assert_near(stamina.current, 82.0)
	# regen waits 0.8 s
	stamina.advance(0.5)
	assert_near(stamina.current, 82.0, 0.001, "no regen during the delay")
	stamina.advance(0.4)
	assert_near(stamina.current, 82.0, 0.001, "the delay frame itself does not regen")
	stamina.advance(1.0)
	assert_near(stamina.current, 100.0, 0.001, "30/s for 1 s, capped at max")


func test_regen_rate_is_30_per_second() -> void:
	stamina.spend(50.0)
	stamina.advance(0.9)
	stamina.advance(0.5)
	assert_near(stamina.current, 65.0, 0.01, "50 + 30*0.5")


func test_actions_allowed_while_any_stamina_remains() -> void:
	stamina.spend(95.0)
	assert_true(stamina.can_afford(22.0), "a Souls-style attack may start on fumes")
	assert_true(stamina.try_spend(22.0))
	assert_near(stamina.current, 0.0)
	assert_true(stamina.is_exhausted())
	assert_false(stamina.try_spend(1.0), "but not while empty")


func test_exhausted_signal() -> void:
	var fired := {"n": 0}
	stamina.exhausted.connect(func() -> void: fired["n"] += 1)
	stamina.spend(100.0)
	assert_eq(fired["n"], 1)


func test_sprint_drain() -> void:
	assert_true(stamina.drain(DamageModel.STAMINA_SPRINT_PER_S, 1.0))
	assert_near(stamina.current, 92.0)
	stamina.current = 0.0
	assert_false(stamina.drain(8.0, 1.0), "cannot sprint on empty")


func test_regen_multiplier_slows_blocking() -> void:
	stamina.spend(50.0)
	stamina.regen_multiplier = 0.5
	stamina.advance(0.9)
	stamina.advance(1.0)
	assert_near(stamina.current, 65.0, 0.01, "half rate while blocking")


func test_stamina_save_round_trip() -> void:
	stamina.spend(30.0)
	var d := stamina.to_save()
	var other := StaminaComponent.new()
	other.from_save(d)
	assert_near(other.current, 70.0)
	assert_near(other.maximum, 100.0)
	other.free()


# --- poise ------------------------------------------------------------------------------------

func test_poise_regens_after_delay() -> void:
	poise.apply(10.0)
	assert_near(poise.current, 30.0)
	poise.advance(1.0)
	assert_near(poise.current, 30.0, 0.001, "1.5 s delay")
	poise.advance(0.6)
	poise.advance(1.0)
	assert_near(poise.current, 34.0, 0.01, "4/s")


func test_poise_breaks_and_resets() -> void:
	var broke := {"n": 0}
	poise.broken.connect(func() -> void: broke["n"] += 1)
	assert_false(poise.apply(30.0), "not broken yet")
	assert_near(poise.current, 10.0)
	assert_true(poise.apply(10.0), "reaching zero breaks poise")
	assert_eq(broke["n"], 1)
	assert_near(poise.current, 40.0, 0.001, "poise resets to max on break")


func test_heavy_hits_deal_more_poise_damage() -> void:
	poise.apply(10.0, true)
	assert_near(poise.current, 25.0, 0.001, "10 * 1.5")


func test_hyper_armour_ignores_small_hits() -> void:
	poise.set_hyper_armour(12.0)
	assert_true(poise.has_hyper_armour())
	assert_false(poise.apply(8.0))
	assert_near(poise.current, 40.0, 0.001, "small hit ignored entirely")
	assert_false(poise.apply(20.0))
	assert_near(poise.current, 20.0, 0.001, "a big hit still lands")
	poise.clear_hyper_armour()
	assert_false(poise.has_hyper_armour())
	assert_false(poise.apply(8.0))
	assert_near(poise.current, 12.0)


# --- status effects ---------------------------------------------------------------------------

func test_apply_and_expire() -> void:
	assert_true(status.apply("burning"))
	assert_true(status.has("burning"))
	assert_near(status.remaining("burning"), 4.0)
	status.advance(4.1)
	assert_false(status.has("burning"))


func test_expiry_signal() -> void:
	var gone := {"id": ""}
	status.expired.connect(func(id: String) -> void: gone["id"] = id)
	status.apply("stagger", 0.5)
	status.advance(0.6)
	assert_eq(str(gone["id"]), "stagger")


func test_damage_ticks() -> void:
	var total := {"amount": 0.0, "kind": ""}
	status.damage_tick.connect(func(_id: String, amount: float, kind: String) -> void:
		total["amount"] = float(total["amount"]) + amount
		total["kind"] = kind)
	status.apply("burning")           # 3 dps, tick 0.5 s, 4 s
	status.advance(1.0)
	assert_near(float(total["amount"]), 3.0, 0.01, "3 dps for 1 s")
	assert_eq(str(total["kind"]), "fire")


## Found by the headless fights: a burn's tick ended a stagger that came later in the same pass,
## and the pass then read the stagger it had already lost (a SCRIPT ERROR that abandoned the rest
## of the frame's statuses). The effects after it must still run down.
func test_an_effect_ended_mid_pass_does_not_stop_the_others() -> void:
	status.damage_tick.connect(func(_id: String, _amount: float, _kind: String) -> void: status.clear("stagger"))
	status.apply("burning")           # ticks at once when 0.5 s passes
	status.apply("stagger", 5.0)
	status.apply("chilled", 5.0)
	status.advance(0.5)
	assert_false(status.has("stagger"), "the tick's handler ended the stagger")
	assert_near(status.remaining("chilled"), 4.5, 0.001, "the effect after it still ran down")
	assert_near(status.remaining("burning"), 3.5, 0.001)

func test_chilled_slows_movement() -> void:
	assert_near(status.speed_multiplier(), 1.0)
	status.apply("chilled")
	assert_near(status.speed_multiplier(), 0.6)


func test_silenced_blocks_casting_only() -> void:
	status.apply("silenced")
	assert_true(status.blocks_casting())
	assert_false(status.blocks_actions(), "silence stops Saying, not swinging")


func test_stagger_and_knockdown_block_actions() -> void:
	status.apply("stagger")
	assert_true(status.blocks_actions())
	status.clear("stagger")
	status.apply("knockdown")
	assert_true(status.blocks_actions())


func test_bleeding_stacks_to_a_cap() -> void:
	status.apply("bleeding")
	assert_eq(status.stacks("bleeding"), 1)
	status.apply("bleeding")
	status.apply("bleeding")
	assert_eq(status.stacks("bleeding"), 3)
	status.apply("bleeding")
	assert_eq(status.stacks("bleeding"), 3, "capped at max_stacks")


func test_bleeding_stacks_multiply_ticks() -> void:
	var total := {"amount": 0.0}
	status.damage_tick.connect(func(_id: String, amount: float, _k: String) -> void:
		total["amount"] = float(total["amount"]) + amount)
	status.apply("bleeding")
	status.apply("bleeding")
	status.advance(1.0)
	assert_near(float(total["amount"]), 4.0, 0.01, "2 dps * 1 s * 2 stacks")


func test_poison_extends_up_to_a_cap() -> void:
	status.apply("poisoned")
	assert_near(status.remaining("poisoned"), 10.0)
	status.apply("poisoned")
	assert_near(status.remaining("poisoned"), 20.0, 0.01, "extends")
	status.apply("poisoned")
	status.apply("poisoned")
	assert_near(status.remaining("poisoned"), 30.0, 0.01, "capped at max_duration")


func test_refresh_stacking_keeps_the_longest() -> void:
	status.apply("burning", 6.0)
	status.apply("burning", 2.0)
	assert_near(status.remaining("burning"), 6.0, 0.01, "a shorter refresh must not cut it short")


func test_knockdown_is_ignored_while_active_and_grants_immunity() -> void:
	assert_true(status.apply("knockdown"))
	assert_false(status.apply("knockdown"), "no knockdown-locking")
	status.advance(1.7)
	assert_false(status.has("knockdown"))
	assert_true(status.is_immune("knockdown"))
	assert_false(status.apply("knockdown"), "immune for a moment after getting up")
	status.advance(1.6)
	assert_true(status.apply("knockdown"), "immunity lapses")


func test_quieted_drains_renown() -> void:
	var drained := {"amount": 0.0}
	status.renown_tick.connect(func(amount: float) -> void: drained["amount"] = float(drained["amount"]) + amount)
	status.apply("quieted")
	status.advance(5.1)
	assert_near(float(drained["amount"]), 1.0, 0.01)


func test_clear_and_save_round_trip() -> void:
	status.apply("burning")
	status.apply("bleeding")
	status.apply("bleeding")
	var ids := status.active_ids()
	assert_eq(ids.size(), 2)
	var d := status.to_save()
	status.clear_all()
	assert_empty(status.active_ids())
	status.from_save(d)
	assert_true(status.has("burning"))
	assert_eq(status.stacks("bleeding"), 2)
	status.clear_many(["burning", "bleeding"])
	assert_empty(status.active_ids())
