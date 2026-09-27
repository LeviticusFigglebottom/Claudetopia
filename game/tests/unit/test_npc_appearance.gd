extends TestCase
## Villagers with clothes on. `apply_appearance` is what dresses the rig, and outside the
## character-creation screen nothing had ever called it — so every NPC the world stood up was
## the bare humanoid, and a village at midday was two dozen naked people standing in a street.

const A_VILLAGER := "core:npc/maud_brambling"
const A_CLANSWOMAN := "core:npc/ordda_ko_brindle"


func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


func _stand_up(npc_id: String) -> Node:
	var npc := (load("res://actors/npc/npc.tscn") as PackedScene).instantiate()
	npc.set("npc_id", npc_id)
	_tree().root.add_child(npc)
	return npc


func _model_of(npc: Node) -> Node:
	for child in npc.find_children("*", "Node3D", true, false):
		if child.has_method("apply_appearance"):
			return child
	return null


func _worn(npc: Node) -> Array[String]:
	var out: Array[String] = []
	var model := _model_of(npc)
	if model == null:
		return out
	var look: Variant = model.get("appearance")
	if look == null:
		return out
	for slot in CharacterAppearance.SLOTS:
		var part := str((look as CharacterAppearance).part(slot))
		if not part.is_empty() and part != "default":
			out.append("%s:%s" % [slot, part])
	return out


func test_a_villager_is_wearing_something() -> void:
	var npc := _stand_up(A_VILLAGER)
	var worn := _worn(npc)
	assert_gt(worn.size(), 0, "%s is standing in the street with nothing on" % A_VILLAGER)
	npc.queue_free()


func test_the_same_person_looks_the_same_every_time() -> void:
	var a := _stand_up(A_VILLAGER)
	var first := _worn(a)
	a.queue_free()
	await _tree().process_frame
	var b := _stand_up(A_VILLAGER)
	assert_eq(_worn(b), first, "%s changed clothes between two visits" % A_VILLAGER)
	b.queue_free()


func test_two_people_do_not_wear_the_same_thing() -> void:
	var a := _stand_up(A_VILLAGER)
	var b := _stand_up(A_CLANSWOMAN)
	assert_ne(_worn(a), _worn(b), "the whole roster is in one outfit")
	a.queue_free()
	b.queue_free()


func test_an_npc_takes_the_numbers_its_own_def_states() -> void:
	# Ordda's def gives her an age; the roll must not overwrite what the writer wrote.
	var block: Dictionary = ContentDB.get_or_empty(A_CLANSWOMAN).get("appearance", {})
	if not block.has("age"):
		return
	var npc := _stand_up(A_CLANSWOMAN)
	var look: Variant = _model_of(npc).get("appearance")
	assert_near(float((look as CharacterAppearance).age), float(block["age"]), 0.01,
			"the roll overwrote the age her def states")
	npc.queue_free()


func test_a_child_stands_a_child_height() -> void:
	# Elsie is tagged a child, Winnow is only written as nine and `child_small`; both were rolled
	# as grown women of their culture and stood as tall as their parents.
	for id in ["core:npc/elsie_wick", "core:npc/winnow_pennywort"]:
		if ContentDB.get_or_empty(id).is_empty():
			continue
		var npc := _stand_up(id)
		var look: CharacterAppearance = _model_of(npc).get("appearance")
		assert_gt(1.45, look.height, "%s is %.2f m tall" % [id, look.height])
		assert_gt(look.height, 1.1, "%s is shrunk past any child" % id)
		npc.queue_free()
	var grown := _stand_up(A_VILLAGER)
	assert_gt((_model_of(grown).get("appearance") as CharacterAppearance).height, 1.5,
			"a grown villager was taken for a child")
	grown.queue_free()


func test_prose_in_a_def_is_not_mistaken_for_a_part_name() -> void:
	# `"build": "short_thick"` and `"hair": "red_grey_shaved_sides"` are written for a person
	# reading the pack, not for the mesh. Applying them as values would break the appearance.
	var npc := _stand_up(A_CLANSWOMAN)
	var look: CharacterAppearance = _model_of(npc).get("appearance")
	assert_true(look != null, "no appearance at all")
	assert_gt(_worn(npc).size(), 0, "a def with prose in it left her undressed")
	npc.queue_free()


## A named woman is a woman: every named person in the packs says which they are, and the def's word
## goes into the roll, so she is never given the beard, the height or the man's body her seed would
## have rolled (triage 2026-09-27 item 21).
func test_a_named_woman_stands_up_a_woman() -> void:
	for id in [A_VILLAGER, A_CLANSWOMAN, "core:npc/lettie_wick", "core:npc/rosen_wyke"]:
		var def := ContentDB.get_or_empty(id)
		if def.is_empty():
			continue
		assert_near(float((def.get("appearance", {}) as Dictionary).get("feminine", -1.0)), 1.0, 0.001,
				"%s's def does not say she is a woman" % id)
		var npc := _stand_up(id)
		var model := _model_of(npc)
		if model != null and model.get("appearance") != null:
			var look := model.get("appearance") as CharacterAppearance
			assert_true(look.is_woman(), "%s stood up a man" % id)
			assert_eq(look.part("beard"), "", "%s has a beard" % id)
			if ResourceLoader.exists("res://assets/models/characters/bodies/woman/woman.glb"):
				assert_eq(str(model.get("body_variant_worn")), CharacterAppearance.WOMAN_BODY,
						"%s is in '%s', not a woman's body" % [id, model.get("body_variant_worn")])
		npc.queue_free()


## And every named person says: none is left to the seed's coin.
func test_every_named_person_says_whether_a_woman_or_a_man() -> void:
	var unsaid: Array[String] = []
	for def in ContentDB.all("npc"):
		var id := str(def.get("id", ""))
		var tags: Array = def.get("tags", [])
		if bool(def.get("example", false)) or tags.has("animal") or id.begins_with("core:npc/guard_"):
			continue
		var raw: Variant = def.get("appearance", {})
		if not (raw is Dictionary and (raw as Dictionary).has("feminine")):
			unsaid.append(id)
	assert_true(unsaid.is_empty(), "named people the dice decide: %s" % [unsaid])
