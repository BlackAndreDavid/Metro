extends Control

func _ready() -> void:
	preload("res://scripts/ui/settings_panel.gd").apply_saved_settings()
	$Center/Panel/Margin/Items/Start.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/ui/save_select.tscn"))
	$Center/Panel/Margin/Items/Settings.pressed.connect(show_settings)
	$Center/Panel/Margin/Items/Quit.pressed.connect(func(): get_tree().quit())
	$Center/Panel/Margin/Items/Start.grab_focus()

func show_settings() -> void:
	if has_node("SettingsPanel"):
		return
	var panel = preload("res://scenes/ui/settings_panel.tscn").instantiate()
	panel.show_return_to_menu = false
	add_child(panel)
