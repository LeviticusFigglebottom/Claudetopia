class_name CraftingStation
extends StaticBody3D
## A forge, an alembic, a Name-table: the thing you walk up to in order to make something.
##
## `station_screen.tscn` has always drawn all three (DESIGN §5.8) and `UI.MENUS` has always
## had it registered, and **nothing in the game ever called `UI.open("crafting")`**. Smithing,
## alchemy and enchanting were three complete systems and twenty-one recipes behind a door
## with no handle on it: there was no forge, no still and no bench anywhere in eight
## kilometres of country that a player could use.
##
## It attaches to a prop that is already in the room — `house_interior.gd` puts one on an
## anvil and on an alembic — so the thing you walk up to is the thing you were looking at,
## rather than an invisible trigger beside it.

const INTERACT_LAYER := 1 << 4   # 3d_physics/layer_5 "interactable"
const KNOWN := ["forge", "alembic", "name_table"]
const NAMES := {"forge": "the anvil", "alembic": "the alembic", "name_table": "the Name-table"}
## What it is for, when the player has not got what the station needs.
const IDLE := {
	"forge": "the anvil, cold",
	"alembic": "the alembic, unlit",
	"name_table": "the Name-table",
}

@export_enum("forge", "alembic", "name_table") var station := "forge"
@export var display_name := ""
@export var owner_npc := ""
@export var owner_faction := ""
## A station in somebody's workshop is theirs. Using it is not theft — a smith does not mind
## you straightening a nail — but the law hears about it if they have said otherwise.
@export var private := false

var size := Vector3(1.0, 1.0, 0.8)


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("crafting_station")
	collision_layer = INTERACT_LAYER
	collision_mask = 0
	if not owner_faction.is_empty() or not owner_npc.is_empty():
		Ownership.tag(self, owner_faction, owner_npc)
	if find_children("*", "CollisionShape3D", true, false).is_empty():
		var shape := CollisionShape3D.new()
		var form := BoxShape3D.new()
		form.size = size
		shape.shape = form
		shape.position.y = form.size.y * 0.5
		add_child(shape)


func prompt_text() -> String:
	if not display_name.is_empty():
		return display_name
	return str(NAMES.get(station, "the bench"))


func interact(_actor: Node) -> bool:
	if private and Ownership.is_owned_by_other(self):
		EventBus.notify.emit("That is not your bench.", "info")
		return false
	if not KNOWN.has(station):
		return false
	EventBus.crafting_station_used.emit(station, self)
	return true
