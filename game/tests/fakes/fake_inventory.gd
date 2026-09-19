extends Node
## Test double for the inventory stream's marks API.

var marks := 0


func _ready() -> void:
	add_to_group("inventory")


func add_marks(n: int) -> void:
	marks += n


func remove_marks(n: int) -> int:
	var taken := mini(n, marks)
	marks -= taken
	return taken
