extends Node3D
## Minimal interior used by tests: an entrance marker and an exit door.

func _ready() -> void:
	var m := Marker3D.new()
	m.name = "Entrance"
	m.position = Vector3(2, 0, 3)
	add_child(m)
	var d := preload("res://systems/interiors/door.tscn").instantiate()
	d.is_exit = true
	d.position = Vector3(2, 0, 4)
	add_child(d)
