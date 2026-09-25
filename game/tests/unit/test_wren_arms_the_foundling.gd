extends TestCase
## Wren arms the Foundling as the first talk ends (the Naming's `wake` stage): the callings start
## with a dagger, a knife, an axe or nothing, and her line at the Choir is "Sword up". The `arm`
## effect gives one of a weapon and puts it in the main hand when that hand is empty or holds a
## weaker one.

const SWORD := "core:item/iron_sword"
const DAGGER := "core:item/iron_dagger"
const AXE := "core:item/iron_axe"
const NAMING := "core:quest/the_naming"

var _holder: Node = null
var _bag: Inventory = null
var _gear: Equipment = null
var _ctx: SocialContext = null


func before_each() -> void:
	_holder = Node.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(_holder)
	_bag = Inventory.new()
	_holder.add_child(_bag)
	_gear = Equipment.new()
	_gear.inventory = _bag
	_holder.add_child(_gear)
	_ctx = SocialContext.new()
	_ctx.set_provider("inventory", _bag)
	_ctx.set_provider("equipment", _gear)


func after_each() -> void:
	_holder.get_parent().remove_child(_holder)
	_holder.free()


func _held() -> String:
	var s: ItemStack = _gear.get_slot("main_hand")
	return s.id if s != null else ""


func test_an_empty_hand_is_given_the_sword() -> void:
	Effects.apply({"arm": SWORD}, _ctx)
	assert_empty(_ctx.problems)
	assert_eq(_bag.count(SWORD), 1, "the sword is in the bag")
	assert_eq(_held(), SWORD, "and in the hand")


func test_a_dagger_is_put_down_for_it() -> void:
	_bag.add(DAGGER, 1)
	_gear.equip(DAGGER, "main_hand")
	Effects.apply({"arm": SWORD}, _ctx)
	assert_eq(_held(), SWORD, "a sword is better than a dagger")
	assert_eq(_bag.count(DAGGER), 1, "and the dagger stays in the bag")


func test_an_axe_as_good_is_kept() -> void:
	_bag.add(AXE, 1)
	_gear.equip(AXE, "main_hand")
	Effects.apply({"arm": SWORD}, _ctx)
	assert_eq(_held(), AXE, "the cragborn's axe hits as hard, and stays in the hand")
	assert_eq(_bag.count(SWORD), 1, "the sword goes in the bag")


func test_the_naming_arms_the_foundling_when_the_first_talk_ends() -> void:
	var wake: Dictionary = {}
	for st in ContentDB.get_def(NAMING).get("stages", []):
		if str((st as Dictionary).get("id", "")) == "wake":
			wake = st
	var armed := false
	for e in wake.get("on_complete", []):
		if typeof(e) == TYPE_DICTIONARY and str((e as Dictionary).get("arm", "")) == SWORD:
			armed = true
	assert_true(armed, "speaking to Wren ends with her sword in the Foundling's hand")
	assert_true(ContentDB.has(SWORD))
