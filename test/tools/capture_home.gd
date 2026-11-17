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
	home.state.place_furniture("bed", 1)
	home.state.place_furniture("computer", 0)
	home.show_cabin()
	await capture("home_furnished")
	home.home_backdrop.get_node("Carriage/FurnitureSlots/Bed").set_highlighted(true)
	await capture("home_bed_outline")
	home.home_backdrop.get_node("Carriage/FurnitureSlots/Bed").set_highlighted(false)
	for fixture in ["Door", "Locker", "Screen"]:
		var item = home.home_backdrop.get_node("Carriage/FurnitureSlots/" + fixture)
		item.set_highlighted(true)
		await capture("home_" + fixture.to_lower() + "_outline")
		item.set_highlighted(false)
	home.construction.enter()
	home.home_backdrop.get_node("Carriage/FurnitureSlots/Door").use()
	await capture("construction_selected")
	home.construction.dismantle()
	home.construction.open_warehouse()
	await capture("construction_warehouse")
	home.construction.get_node("Warehouse").hide()
	home.construction.select_furniture("door")
	home.construction.begin_move()
	home.construction.place_at(3)
	home.construction.select_furniture("screen")
	home.construction.begin_move()
	await capture("home_hanging_points")
	home.construction.exit()
	for kind in home.state.EXPANSION_COST:
		for i in range(home.state.EXPANSION_COST[kind]):
			home.state.add_supply(kind, "locker")
	home.confirm_expansion()
	await capture("home_expanded")
	home.show_settings()
	await capture("home_settings")
	home.close_settings()
	home.queue_free()
	await process_frame
	print("HOME_CAPTURE_OK")
	quit(0)
