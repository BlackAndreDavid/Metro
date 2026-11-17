extends SceneTree

var checks := 0
var failures := 0
var clicks := 0

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(description)

func _initialize() -> void:
	call_deferred("run")

func mouse_button(at: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = at
	event.global_position = at
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	return event

func run() -> void:
	root.size = Vector2i(1280, 720)
	var home = load("res://scenes/game/home.tscn").instantiate()
	root.add_child(home)
	await process_frame
	home.state.place_furniture("computer", 0)
	home.state.place_furniture("bed", 1)
	home.show_cabin()
	await process_frame
	check(home.name == "Home", "renamed home scene")
	check(home.get_node("SettingsButton").text == "设置", "settings button caption")
	var backdrop = home.home_backdrop
	check(backdrop.get_node("Background").get_index() < backdrop.carriage.get_index(), "background behind carriage")
	check(backdrop.carriage.get_node("Texture").texture.get_size() == Vector2(243, 108), "trimmed carriage texture")
	var car_rect: Rect2 = backdrop.carriage.get_node("Texture").get_rect()
	check(car_rect.get_center().is_equal_approx(Vector2(640, 360)), "visible carriage centered after trim")
	backdrop.pan_by(Vector2(100000, -100000))
	check(backdrop.offset.is_equal_approx(Vector2(256, -144)), "pan clamps at 20 percent")
	check(backdrop.carriage.position == backdrop.offset, "furniture and texture pan together")
	check(backdrop.background.position.is_equal_approx(Vector2(-256, -144) + backdrop.offset * 0.25), "background parallax")
	backdrop.pan_by(-backdrop.offset)
	backdrop.start_drag(Vector2(500, 350), func(): clicks += 1)
	backdrop._input(mouse_button(Vector2(500, 350), false))
	check(clicks == 1, "click invokes interaction")
	backdrop.start_drag(Vector2(500, 350), func(): clicks += 1)
	var motion := InputEventMouseMotion.new()
	motion.global_position = Vector2(600, 390)
	motion.relative = Vector2(100, 40)
	backdrop._input(motion)
	backdrop._input(mouse_button(motion.global_position, false))
	check(clicks == 1, "drag suppresses accidental hotspot click")
	check(backdrop.offset.is_equal_approx(Vector2(35, 14)), "gentle drag sensitivity")
	backdrop.pan_by(-backdrop.offset)
	# Exercise real GUI routing on the computer tag, including click-vs-drag.
	var tag = backdrop.get_node("Carriage/FurnitureSlots/Computer")
	var hit := Vector2.ZERO
	for y in range(tag.padded_image.get_height()):
		for x in range(tag.padded_image.get_width()):
			if tag.padded_image.get_pixel(x, y).a > 0.9:
				hit = (Vector2(x, y) + Vector2(0.5, 0.5)) / Vector2(tag.padded_image.get_size()) * tag.size
	var point: Vector2 = tag.global_position + hit
	root.push_input(mouse_button(point, true))
	var gui_motion := InputEventMouseMotion.new()
	gui_motion.position = point + Vector2(80, 20)
	gui_motion.global_position = gui_motion.position
	gui_motion.relative = Vector2(80, 20)
	gui_motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(gui_motion)
	root.push_input(mouse_button(gui_motion.position, false))
	await process_frame
	check(home.screen == "cabin" and not backdrop.offset.is_zero_approx(), "real hotspot GUI drag pans without opening computer")
	backdrop.pan_by(-backdrop.offset)
	root.push_input(mouse_button(point, true))
	root.push_input(mouse_button(point, false))
	await process_frame
	check(home.screen == "news", "computer GUI click opens news")
	home.show_map()
	check(home.screen == "map", "news close reveals map")
	home.select_station("四平路")
	check(home.selected_station == "四平路", "computer map station selection")
	home.show_cabin()
	home.use_hotspot("gear")
	check(home.view.scene_file_path == "res://scenes/game/exploration_setup.tscn", "separate departure setup scene")
	home.state.installed_charge = 100
	home.confirm_departure()
	await process_frame
	check(home.state.trip_active and home.screen == "surface", "departure enters exploration")
	check(home.view.scene_file_path == "res://scenes/game/exploration.tscn", "independent exploration scene")
	check(home.surface_block == home.view.get_node("StreetFrame/SurfaceBlock"), "editable street node")
	check(home.surface_pack.get_parent() == home.view.get_node("PackAnchor"), "pack anchored by scene")
	var street = home.surface_block
	var before_x: float = street.player_x
	street.move_horizontal(1.0, 0.1)
	check(street.player_x > before_x, "exploration movement remains functional")
	home.show_surface()
	check(home.surface_block == street, "backpack refresh retains exploration instance")
	var remaining: int = home.state.remaining_ms()
	home.show_settings()
	check(paused, "settings pauses gameplay")
	var panel = home.settings_panel
	check(panel.get_node("Center/Panel/Margin/Items/Return").visible, "return menu integrated")
	panel.volume.value = 0.4
	var config := ConfigFile.new()
	check(config.load("user://settings.cfg") == OK and is_equal_approx(config.get_value("audio", "volume"), 0.4), "volume saved")
	panel.fullscreen.button_pressed = not panel.fullscreen.button_pressed
	config.load("user://settings.cfg")
	check(config.get_value("display", "fullscreen") == panel.fullscreen.button_pressed, "fullscreen preference saved")
	panel.get_node("Center/Panel/Margin/Items/Return").pressed.emit()
	check(home.has_node("ReturnConfirmation") and paused, "settings return opens confirmation while paused")
	home.get_node("ReturnConfirmation").canceled.emit()
	check(is_instance_valid(home.settings_panel) and paused, "cancel return keeps settings open")
	await create_timer(0.12).timeout
	panel.close()
	check(not paused, "settings resumes gameplay")
	check(absi(home.state.remaining_ms() - remaining) < 80, "settings time excluded from trip deadline")
	home.return_to_cabin()
	check(home.screen == "cabin" and not home.state.trip_active, "return from exploration")
	home.queue_free()
	await process_frame
	print("HOME_FLOW: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
