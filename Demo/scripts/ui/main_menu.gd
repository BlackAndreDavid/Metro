extends Control

func _ready() -> void:
	var config := ConfigFile.new()
	if config.load("user://settings.cfg") == OK:
		AudioServer.set_bus_volume_db(0, linear_to_db(float(config.get_value("audio", "volume", 1.0))))
		if not DisplayServer.get_name() == "headless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if config.get_value("display", "fullscreen", false) else DisplayServer.WINDOW_MODE_WINDOWED)
	$Center/Panel/Margin/Items/Start.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/ui/save_select.tscn"))
	$Center/Panel/Margin/Items/Settings.pressed.connect(show_settings)
	$Center/Panel/Margin/Items/Quit.pressed.connect(func(): get_tree().quit())
	$Center/Panel/Margin/Items/Start.grab_focus()

func show_settings() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "设置"
	dialog.min_size = Vector2i(400, 180)
	var box := VBoxContainer.new()
	dialog.add_child(box)
	var label := Label.new()
	label.text = "主音量"
	box.add_child(label)
	var volume := HSlider.new()
	volume.min_value = 0
	volume.max_value = 1
	volume.step = 0.01
	volume.value = db_to_linear(AudioServer.get_bus_volume_db(0))
	box.add_child(volume)
	var fullscreen := CheckButton.new()
	fullscreen.text = "全屏"
	fullscreen.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	box.add_child(fullscreen)
	volume.value_changed.connect(func(value): AudioServer.set_bus_volume_db(0, linear_to_db(value)))
	fullscreen.toggled.connect(func(value):
		if DisplayServer.get_name() != "headless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if value else DisplayServer.WINDOW_MODE_WINDOWED))
	dialog.confirmed.connect(func():
		var config := ConfigFile.new()
		config.set_value("audio", "volume", volume.value)
		config.set_value("display", "fullscreen", fullscreen.button_pressed)
		var err := config.save("user://settings.cfg")
		if err != OK:
			push_error("设置保存失败：" + error_string(err))
		dialog.queue_free())
	dialog.close_requested.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()
