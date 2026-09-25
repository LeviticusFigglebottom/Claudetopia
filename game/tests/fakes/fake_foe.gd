extends Node3D
## A stand-in foe with just what Waymarks reads of an Enemy: its content id and whether it is dead.

var id := ""
var dead := false


func content_id() -> String:
	return id
