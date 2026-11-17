extends SceneTree
## Optional graphical check. Requires an X11 display and a rendered Godot driver.
var output := OS.get_environment("METRO_TEST_RESULTS")

func _initialize() -> void:
	call_deferred("run")

func capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var err := root.get_texture().get_image().save_png(output.path_join(name + ".png"))
	if err != OK:
		push_error("Screenshot failed: " + error_string(err))
		quit(1)

func run() -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless":
		push_error("Set METRO_TEST_RESULTS and run with an X11 display")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	var home = load("res://scenes/game/home.tscn").instantiate()
	root.add_child(home)
	home.show_cabin()
	await capture("home_empty")
	home.state.place_furniture("bed", home.state.Furniture.default_placement("bed"))
	home.state.place_furniture("computer", home.state.Furniture.default_placement("computer"))
	home.show_cabin()
	await capture("home_furnished")
	var customers = home.home_backdrop.get_node("Carriage/Fixtures/TradeWindow0")
	customers.set_process(false)
	for depth in [0.15,0.5,1.0]:
		customers.apply_depth(depth)
		await capture("customer_depth_" + str(int(depth*100)))
	home.home_backdrop.get_node("Carriage/FurnitureSlots/Bed").set_highlighted(true)
	await capture("home_bed_outline")
	home.home_backdrop.get_node("Carriage/FurnitureSlots/Bed").set_highlighted(false)
	for fixture in ["Door", "Locker", "Screen"]:
		var branch := "HangingFixtures/" if fixture == "Screen" else "FurnitureSlots/"
		var item = home.home_backdrop.get_node("Carriage/" + branch + fixture)
		item.set_highlighted(true)
		await capture("home_" + fixture.to_lower() + "_outline")
		item.set_highlighted(false)
	home.construction.enter()
	home.construction.backdrop.get_node("Carriage/FurnitureSlots/Door").use()
	await capture("construction_selected")
	home.construction.dismantle()
	home.construction.open_warehouse()
	await capture("construction_warehouse")
	home.construction.get_node("Warehouse").hide()
	home.construction.selected_id = "screen"
	home.construction.moving = true
	home.construction._refresh("")
	await capture("home_hanging_points")
	home.construction.exit()
	for kind in home.state.EXPANSION_COST:
		for i in range(home.state.EXPANSION_COST[kind]):
			home.state.add_supply(kind, "locker")
	home.construction.enter()
	home.construction.request_expansion()
	home.construction.confirm_expansion()
	await capture("home_expanded")
	home.construction.exit()
	home.show_map()
	await capture("independent_map")
	home.map_scene.exit()
	home.construction.enter()
	var bed = home.construction.backdrop.get_node("Carriage/FurnitureSlots/Bed")
	home.construction.press_furniture("bed",bed.global_position + bed.size / 2)
	home.construction.set_process(false)
	home.construction._process(0.5)
	await capture("hold_progress")
	home.construction.exit()
	home.state.store_furniture("computer")
	for item in home.state.locker:
		if item.kind == "computer": item.rotated = true
	home.show_locker()
	await capture("rotated_item")
	home.show_cabin()
	await process_frame
	var at: Vector2 = home.get_node("SettingsButton").get_global_rect().get_center()
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = at
		event.global_position = at
		event.pressed = pressed
		root.push_input(event)
	await process_frame
	if not is_instance_valid(home.settings_panel):
		push_error("Actual settings button click failed")
		quit(1)
		return
	await capture("home_settings")
	home.close_settings()
	home.queue_free()
	await process_frame
	print("HOME_CAPTURE_OK")
	quit(0)
