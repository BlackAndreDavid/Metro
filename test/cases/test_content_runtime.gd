extends SceneTree
const State = preload("res://scripts/cabin_state.gd")
const Orders = preload("res://scripts/commerce/customer_orders.gd")
const Dialogue = preload("res://scripts/commerce/customer_dialogue.gd")
const Content = preload("res://scripts/content/content_registry.gd")
const Rail = preload("res://scripts/cabin_map.gd")
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void: call_deferred("run")
func click(node: Control) -> void:
	await process_frame
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = node.get_global_rect().get_center()
		event.global_position = event.position
		event.pressed = pressed
		root.push_input(event)
	await process_frame
func run() -> void:
	root.size = Vector2i(1280,720)
	var home = load("res://scenes/game/home.tscn").instantiate()
	root.add_child(home)
	home.show_cabin()
	home.show_trade()
	await process_frame
	var scene = home.view
	var window = scene.window
	window.set_process(false)
	var hot := Image.create(48,80,false,Image.FORMAT_RGBA8)
	hot.fill(Color("668c92"))
	hot.save_png("res://assets/textures/customers/hot_test.png")
	check(window.Catalog.load_texture("res://assets/textures/customers/hot_test.png").get_size() == Vector2(48,80), "new PNG can load before Godot import")
	var order := Orders.ensure(home.state)
	check(window.Catalog.definition(int(order.visitor)).id == "editor_test" and order.budget == 77, "editor weighted visitor and base budget used by runtime")
	check(order.category == "supplies", "edited category drives order")
	check(not Dialogue.pending(home.state,order).is_empty(), "condition-matched editor story has priority")
	window.advance(window.approach_seconds)
	check(scene.get_node("DialogueOverlay").visible and scene.get_node("Panel/Confirm").disabled, "arrival opens story before trading")
	var water: Dictionary
	for entry in home.state.inventory:
		if entry.kind == "water": water = {"source":"bag","id":entry.id}
	check(Orders.preview(home.state,[water]).problem == "请先完成顾客剧情。", "model also blocks confirmation while dialogue pending")
	await click(scene.get_node("DialogueOverlay/Card/Scroll/Choices").get_child(0))
	check(home.state.dialogue_progress[order.id].node == "thanks" and home.state.content_flags.get("editor_story_done",false), "branch transitions and node flags applied")
	var path := OS.get_environment("METRO_TEST_RESULTS").path_join("editor_dialogue_save.json")
	check(home.state.save_current(path) == OK, "dialogue can be saved midway")
	var resumed := State.new()
	check(resumed.load_cabin(path,Rail.STATIONS.keys()) and resumed.dialogue_progress[order.id].node == "thanks", "saved dialogue node and flags restored")
	home.show_cabin()
	home.state = resumed
	home.show_trade()
	scene = home.view
	window = scene.window
	window.set_process(false)
	window.advance(window.approach_seconds)
	check("谢谢" in scene.get_node("DialogueOverlay/Card/TextScroll/Text").text, "reopened trade resumes authored branch")
	await click(scene.get_node("DialogueOverlay/Card/Scroll/Choices").get_child(0))
	check(not scene.get_node("DialogueOverlay").visible and Dialogue.pending(home.state,Orders.ensure(home.state)).is_empty(), "story finishes and enables order")
	check(Orders.preview(home.state,[water]).problem.is_empty(), "transaction unlocked after dialogue")
	check(Dialogue.matches(home.state,{"flags_all":["editor_story_done"],"day_min":1,"has_items":{"water":1}}) and not Dialogue.matches(home.state,{"account_min":100000}), "editor condition grammar checks state")
	home.show_cabin()
	home.state.station = "南京东路"
	home.use_hotspot("gear")
	home.state.installed_charge = 100
	home.confirm_departure()
	await process_frame
	check(home.screen == "surface" and home.view.scene_file_path == Content.scene("南京东路"), "editor-generated tscn selected for station")
	check(home.surface_block.BUILDINGS[0].name == "编辑建筑" and home.surface_block.STATIONS.size() == 1 and home.surface_block.STATIONS[0].name == "南京东路", "authored buildings and station entry loaded")
	check(home.state.trip_loot[0] == "book" and home.surface_block.LOOT[0].kind == "book", "authored loot kind connects to inventory rules")
	check(home.surface_block.VEHICLES[0].id.begins_with("station_"), "custom level vehicle ids are namespaced")
	var x: float = home.surface_block.player_x
	home.surface_block.move_horizontal(1,0.1)
	check(home.surface_block.player_x > x and not home.view.get_node("Minimap").links.is_empty(), "custom level movement and minimap functional")
	home.queue_free()
	await process_frame
	print("CONTENT_RUNTIME: %d checks, %d failures" % [checks,failures])
	if failures == 0: print("CONTENT_RUNTIME_OK")
	quit(1 if failures else 0)
