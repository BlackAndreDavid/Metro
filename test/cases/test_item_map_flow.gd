extends SceneTree
const State = preload("res://scripts/cabin_state.gd")
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var state := State.new()
	check(state.ITEM_DEFINITIONS.computer is MetroItem, "computer uses storable item class")
	var entry: Dictionary = {}
	for item in state.locker:
		if item.kind == "computer": entry = item
	check(not entry.is_empty() and state.material_count("computer") == 1, "initial computer exists once in storage")
	check(state.place({"source":"locker","id":entry.id,"rotated":true,"mirrored":true}, "locker", Vector2i(entry.x,entry.y)), "computer rotates in storage")
	check(entry.rotated and entry.mirrored, "stored orientation and mirror retained")
	var copy := State.new()
	var path := OS.get_environment("METRO_TEST_RESULTS").path_join("rotated_item.json")
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(state.save_data()))
	file.close()
	var loaded := copy.load_cabin(path,[state.station])
	var rotated_copy := false
	for item in copy.locker:
		if item.kind == "computer": rotated_copy = item.rotated and item.get("mirrored",false)
	check(loaded and rotated_copy, "rotated and mirrored computer save roundtrip")
	var malformed := state.locker.duplicate(true);malformed[0].mirrored="wrong"
	check(state.read_cargo(malformed,state.LOCKER).is_empty(),"invalid mirror flag rejected")
	check(state.place_furniture("computer", state.Furniture.default_placement("computer")).is_empty(), "stored computer can become furniture")
	check(state.material_count("computer") == 0 and not state.furniture_layout.computer.has("rotated"), "placement consumes item and discards storage rotation")
	var forged := state.save_data()
	forged.locker.append({"kind":"computer","x":0,"y":0,"rotated":false})
	state.write_save(path,forged)
	var before := copy.save_data()
	check(not copy.load_cabin(path,[state.station]) and copy.save_data() == before, "duplicate item and furniture ownership rejected atomically")
	state.locker.clear()
	state.inventory.clear()
	for container in ["locker","bag"]:
		var bounds: Vector2i = state.grid_size(container)
		for y in range(bounds.y):
			for x in range(bounds.x): state.entries(container).append(state.make_entry("water",Vector2i(x,y),false))
	check(not state.store_furniture("computer").is_empty() and state.furniture_layout.computer != null, "full storage rejects dismantling without losing computer")
	state.locker.clear()
	check(state.store_furniture("computer").is_empty() and state.material_count("computer") == 1, "dismantling returns computer item")
	check(not state.locker[0].rotated, "dismantled computer defaults upright")
	root.size = Vector2i(1280,720)
	var home = load("res://scenes/game/home.tscn").instantiate()
	root.add_child(home)
	current_scene = home
	await process_frame
	home.state.place_furniture("computer",home.state.Furniture.default_placement("computer"))
	home.show_cabin()
	await process_frame
	check(home.home_backdrop.get_node("Carriage/FurnitureSlots/Computer").rotation == 0, "furniture sprite bottom remains down")
	var stored: Dictionary = home.state.inventory[0]
	home.select_cargo("bag",stored.id)
	var flip := InputEventKey.new();flip.keycode=KEY_F;flip.pressed=true
	home._input(flip)
	check(home.selection.get("mirrored",false),"F toggles selected item mirror")
	check(home.state.place(home.selection,"bag",Vector2i(stored.x,stored.y)) and stored.mirrored,"mirror commits without changing occupied cells")
	home.clear_selection()
	home.show_news()
	var map = home.map_scene
	check(map.get_parent() == home.get_parent() and map.state == home.state and current_scene == map, "map is independent sibling with shared model")
	check(not home.visible and home.process_mode == Node.PROCESS_MODE_DISABLED and map.screen == "news", "source UI disabled while independent news and map are active")
	map.show_map()
	map.select_station("四平路")
	var power: float = home.state.car_power
	map.travel()
	check(home.visible and current_scene == home and not map.active and home.state.station == "四平路" and home.state.car_power < power, "map travel returns to home with shared state")
	home.construction.enter()
	var build = home.construction
	check(not build.actions.has_node("Map") and not build.has_method("open_map"), "renovation has no map function")
	check(home.view.get_node("BuildModeButton").text == "装修", "renovation label")
	build.exit()
	home.queue_free()
	await process_frame
	print("ITEM_MAP_FLOW: %d checks, %d failures" % [checks,failures])
	if failures == 0: print("ITEM_MAP_FLOW_OK")
	quit(1 if failures else 0)
