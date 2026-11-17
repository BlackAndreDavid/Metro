extends CanvasLayer

signal closed
signal return_requested
@export var show_return_to_menu := true
@onready var volume: HSlider = $Center/Panel/Margin/Items/Volume
@onready var fullscreen: CheckButton = $Center/Panel/Margin/Items/Fullscreen
@onready var error_label: Label = $Center/Panel/Margin/Items/Error

static func apply_saved_settings() -> void:
	var config := ConfigFile.new()
	if config.load("user://settings.cfg") != OK:
		return
	AudioServer.set_bus_volume_db(0, linear_to_db(clampf(float(config.get_value("audio", "volume", 1.0)), 0.0, 1.0)))
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if config.get_value("display", "fullscreen", false) else DisplayServer.WINDOW_MODE_WINDOWED)

func _ready() -> void:
	volume.value = db_to_linear(AudioServer.get_bus_volume_db(0))
	fullscreen.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	$Center/Panel/Margin/Items/Return.visible = show_return_to_menu
	volume.value_changed.connect(func(value):
		AudioServer.set_bus_volume_db(0, linear_to_db(value))
		persist())
	fullscreen.toggled.connect(func(value):
		if DisplayServer.get_name() != "headless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if value else DisplayServer.WINDOW_MODE_WINDOWED)
		persist())
	$Center/Panel/Margin/Items/Close.pressed.connect(close)
	$Center/Panel/Margin/Items/Return.pressed.connect(func(): return_requested.emit())
	$Center/Panel/Margin/Items/Close.grab_focus()

func persist() -> void:
	var config := ConfigFile.new()
	config.load("user://settings.cfg")
	config.set_value("audio", "volume", volume.value)
	config.set_value("display", "fullscreen", fullscreen.button_pressed)
	var err := config.save("user://settings.cfg")
	error_label.text = "设置保存失败：" + error_string(err) if err != OK else ""

func close() -> void:
	closed.emit()
	queue_free()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
