class_name EconomyService
extends Node
## The economy's hub (group "economy"). Holds every merchant's stock and marks across cell
## loads, owns the "economy" save section, and carries the `trade_requested` signal the UI
## stream listens to. Merchants register themselves; a merchant whose actor is despawned
## keeps its state here and picks it up again when it respawns.

static var instance: EconomyService

signal trade_requested(merchant: Node)
signal merchant_registered(merchant: Node)

const SECTION := "economy"

var merchants: Dictionary = {}        # merchant_id -> Merchant (live nodes only)
var saved_state: Dictionary = {}      # merchant_id -> state dict (all merchants, live or not)


static func ensure() -> EconomyService:
	if instance != null and is_instance_valid(instance):
		return instance
	return Service.ensure(load("res://systems/economy/economy_service.gd"), "EconomyService") as EconomyService


func _enter_tree() -> void:
	instance = self
	add_to_group("economy")


func _exit_tree() -> void:
	if instance == self:
		instance = null
	if SaveSystem.participants.get(SECTION) == self:
		SaveSystem.unregister(SECTION)


func _ready() -> void:
	SaveSystem.register(SECTION, self)
	var pending := SaveSystem.take_pending(SECTION)
	if not pending.is_empty():
		from_save(pending)


static func register_merchant(m: Merchant) -> void:
	var svc := ensure()
	if svc == null:
		return
	svc._add(m)


static func unregister_merchant(m: Merchant) -> void:
	if instance != null and is_instance_valid(instance):
		instance._remove(m)


static func request_trade(m: Merchant, player: Node = null) -> void:
	var svc := ensure()
	if svc == null:
		return
	svc.trade_requested.emit(m)
	EventBus.dialogue_started.emit(m.merchant_id())
	if player != null:
		svc.set_meta("last_trade_player", player.get_path())


func _add(m: Merchant) -> void:
	var id := m.merchant_id()
	merchants[id] = m
	if saved_state.has(id):
		m.from_dict(saved_state[id])
	merchant_registered.emit(m)


func _remove(m: Merchant) -> void:
	var id := m.merchant_id()
	if merchants.get(id) == m:
		saved_state[id] = m.to_dict()
		merchants.erase(id)


func merchant(id: String) -> Merchant:
	var m: Variant = merchants.get(id)
	return m if m is Merchant and is_instance_valid(m) else null


## Every merchant known this session, live or remembered, as {id: state}.
func states() -> Dictionary:
	var out := saved_state.duplicate(true)
	for id in merchants:
		var m: Merchant = merchants[id]
		if is_instance_valid(m):
			out[id] = m.to_dict()
	return out


func to_save() -> Dictionary:
	return {"merchants": states()}


func from_save(d: Dictionary) -> void:
	saved_state = d.get("merchants", {}).duplicate(true)
	for id in merchants:
		var m: Merchant = merchants[id]
		if is_instance_valid(m) and saved_state.has(id):
			m.from_dict(saved_state[id])
