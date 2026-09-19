class_name StealthLight
extends Node3D
## A light source as far as stealth is concerned. Place under (or next to) a lantern, hearth
## or window; it registers with Stealth and contributes energy × (1 - d/range)² at the player.
## With `auto_from_light` it copies range/energy from a parent OmniLight3D or SpotLight3D.

@export var range_m := 6.0
@export var energy := 1.0
@export var enabled := true
@export var auto_from_light := true


func _ready() -> void:
	if auto_from_light:
		var parent := get_parent()
		if parent is OmniLight3D:
			range_m = (parent as OmniLight3D).omni_range
			energy = (parent as OmniLight3D).light_energy
		elif parent is SpotLight3D:
			range_m = (parent as SpotLight3D).spot_range
			energy = (parent as SpotLight3D).light_energy


func _enter_tree() -> void:
	if Stealth.instance != null:
		Stealth.instance.register_light(self)


func _exit_tree() -> void:
	if Stealth.instance != null:
		Stealth.instance.unregister_light(self)


func source() -> Dictionary:
	if not enabled or not is_visible_in_tree():
		return {}
	return {"position": global_position, "range": range_m, "energy": energy}
