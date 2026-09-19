extends Node
## Saves the Wickmere themes built by ui/theme/theme_builder.gd so the game does not
## have to build them at startup. Run headlessly after regenerating the UI textures:
##   godot --headless --path game --audio-driver Dummy res://tools_gd/build_theme.tscn

const OUT := {"warm": "res://ui/theme/wickmere_theme.tres", "deep": "res://ui/theme/wickmere_theme_deep.tres"}


func _ready() -> void:
	var failed := false
	for variant: String in OUT:
		var theme := ThemeBuilder.build(variant)
		var err := ResourceSaver.save(theme, OUT[variant])
		if err != OK:
			push_error("build_theme: cannot save %s (%d)" % [OUT[variant], err])
			failed = true
		else:
			print("saved %s (%d font items, %d stylebox types)" % [OUT[variant],
					theme.get_font_type_list().size(), theme.get_stylebox_type_list().size()])
	get_tree().quit(1 if failed else 0)
