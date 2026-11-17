extends SceneTree
var failures := 0
var checks := 0
var button_events := 0
var backdrop_events := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void: call_deferred("run")
func click(control: Control) -> void:
	await process_frame
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = control.get_global_rect().get_center()
		event.global_position = event.position
		root.push_input(event)
	await process_frame
func open_and_close(home, context: String) -> void:
	await click(home.get_node("SettingsButton"))
	check(is_instance_valid(home.settings_panel) and paused, "real settings click opens paused panel: " + context)
	if not is_instance_valid(home.settings_panel): return
	var panel = home.settings_panel
	check(panel.get_node("Center/Panel/Margin/Items/Volume").visible and panel.get_node("Center/Panel/Margin/Items/Fullscreen").visible, "settings controls visible: " + context)
	await click(panel.get_node("Center/Panel/Margin/Items/Close"))
	check(not is_instance_valid(home.settings_panel) and not paused, "real close button resumes game: " + context)
func run() -> void:
	root.size = Vector2i(1280,720)
	var home = load("res://scenes/game/home.tscn").instantiate()
	root.add_child(home)
	await process_frame
	check(home.get_node("SettingsButton").get_parent() == home and home.get_node("SettingsButton").owner == home, "settings button is a saved direct child of home scene")
	home.show_cabin()
	home.get_node("SettingsButton").gui_input.connect(func(event):
		if event is InputEventMouseButton: button_events += 1)
	home.home_backdrop.gui_input.connect(func(event):
		if event is InputEventMouseButton: backdrop_events += 1)
	await open_and_close(home,"home")
	check(button_events == 2 and backdrop_events == 0, "settings receives mouse press/release without backdrop interception")
	home.show_locker()
	await open_and_close(home,"storage")
	home.show_cabin()
	await open_and_close(home,"refreshed home")
	home.use_hotspot("gear")
	home.state.installed_charge = 100
	home.confirm_departure()
	await open_and_close(home,"exploration")
	home.queue_free()
	await process_frame
	print("SETTINGS_INPUT: %d checks, %d failures" % [checks,failures])
	if failures == 0: print("SETTINGS_INPUT_OK")
	quit(1 if failures else 0)
