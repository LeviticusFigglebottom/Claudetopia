extends Node
## EventBus: global signals between systems. Systems never reference each other directly
## for cross-cutting events; they emit or connect here. Keep payloads plain (ids, numbers).

# world & time
signal region_entered(region_id: String, previous_region_id: String)
signal place_discovered(place_id: String)
signal hour_changed(hour: int)
signal new_day(day: int)
signal weather_changed(region_id: String, weather_id: String)
signal cell_loaded(cell: Vector2i)
signal cell_unloaded(cell: Vector2i)
signal interior_entered(interior_id: String)
signal interior_exited(interior_id: String)

# player & combat
signal player_spawned(player: Node)
signal player_died(position: Vector3)
signal player_respawned(hearthstone_id: String)
signal hearthstone_rested(hearthstone_id: String)
signal echo_recovered(marks: int)
signal damage_dealt(attacker: Node, victim: Node, amount: float, kind: String)
signal entity_killed(victim: Node, killer: Node, enemy_id: String)
signal boss_started(boss_id: String)
signal boss_defeated(boss_id: String)
signal status_applied(target: Node, effect_id: String)
## A called thing's time ran out and it let go (Calling; no death, no marks).
signal summon_dismissed(enemy_id: String, summon: Node)

# progression & items
signal skill_used(skill_id: String, xp: float)
signal skill_level_up(skill_id: String, new_level: int)
signal level_up(new_level: int)
signal item_acquired(item_id: String, count: int)
signal item_removed(item_id: String, count: int)
signal item_equipped(slot: String, item_id: String)
signal item_used(item_id: String, effects: Array)
signal container_opened(container: Node, actor: Node)
signal recipe_learned(recipe_id: String)
## A saying (spell) was added to what the character knows; Progression owns the list.
signal spell_learned(spell_id: String)
signal ingredient_effect_discovered(item_id: String, effect_index: int)
signal item_crafted(recipe_id: String, item_id: String, count: int)
signal item_enchanted(item_id: String, effect_id: String)
signal enchantment_learned(effect_id: String)
signal marks_changed(new_total: int, delta: int)
signal attribute_raised(attribute: String, new_value: int)
signal perk_taken(perk_id: String)

# social
signal dialogue_started(npc_id: String)
signal dialogue_ended(npc_id: String)
signal gesture_performed(gesture_id: String, target_npc_id: String)
signal quest_started(quest_id: String)
signal quest_stage_changed(quest_id: String, stage: int)
signal quest_completed(quest_id: String, outcome: String)
signal faction_reputation_changed(faction_id: String, new_value: int, delta: int)
signal faction_rank_changed(faction_id: String, new_rank: int)
signal morality_changed(new_value: int, delta: int, reason: String)
signal renown_changed(new_value: int, delta: int, reason: String)
signal rumour_spread(rumour_id: String, place_id: String)
signal npc_gesture(npc_id: String, gesture_id: String)
signal disposition_changed(npc_id: String, new_value: int, delta: int)
signal deed_applied(deed_id: String, hearth_delta: int, renown_delta: int, witnesses: int)
signal escort_arrived(npc_id: String, place_id: String)

# crime & stealth
signal crime_committed(crime: Dictionary)
signal bounty_changed(faction_id: String, new_bounty: int)
signal arrested(faction_id: String)
signal detection_changed(observer: Node, level: float)

# economy & property
signal transaction(merchant_id: String, item_id: String, count: int, price: int, bought: bool)
signal property_purchased(property_id: String)
signal job_completed(job_id: String, pay: int)

# ui
signal notify(text: String, kind: String)
signal book_opened(book_id: String)
signal menu_opened(menu_id: String)
signal menu_closed(menu_id: String)

# save
signal game_saved(slot: String)
signal game_loaded(slot: String)


func emit_notify(text: String, kind: String = "info") -> void:
	notify.emit(text, kind)
