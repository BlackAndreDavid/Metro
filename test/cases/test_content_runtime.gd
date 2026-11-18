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
	var directory: Dictionary = Content.read_json("res://content/customers.json")
	directory.customers.append({"id":"hot_customer","name":"动态新增客户","texture":"res://assets/textures/customers/hot_test.png","enabled":false})
	var catalog_file := FileAccess.open("res://content/customers.json",FileAccess.WRITE)
	catalog_file.store_string(JSON.stringify(directory))
	catalog_file.close()
	window.set_customer(5)
	check(window.get_node("Name").text == "动态新增客户" and window.portrait.texture.atlas != null,"an already-open trade window displays a newly appended customer without stale texture indices")
	var order := Orders.ensure(home.state)
	window.set_customer(int(order.visitor))
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
	check(home.state.npc_affection.get("editor_test") == 10 and home.state.faction_trust.get("red") == 11,"node effects update affinity and faction trust")
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
	check(home.state.npc_affection.get("editor_test") == 10 and home.state.faction_trust.get("red") == 11,"resuming a node does not replay additive effects")
	check("谢谢" in scene.get_node("DialogueOverlay/Card/TextScroll/Text").text, "reopened trade resumes authored branch")
	await click(scene.get_node("DialogueOverlay/Card/Scroll/Choices").get_child(0))
	check("第二个问题" in scene.get_node("DialogueOverlay/Card/TextScroll/Text").text,"one meeting continues through multiple NPC turns")
	await click(scene.get_node("DialogueOverlay/Card/Scroll/Choices").get_child(0))
	check("本次见面结束" in scene.get_node("DialogueOverlay/Card/TextScroll/Text").text,"player can answer a second time within the same encounter")
	await click(scene.get_node("DialogueOverlay/Card/Scroll/Choices").get_child(0))
	check(not scene.get_node("DialogueOverlay").visible and Dialogue.pending(home.state,Orders.ensure(home.state)).is_empty(), "story finishes and enables order")
	check(Orders.preview(home.state,[water]).problem.is_empty(), "transaction unlocked after dialogue")
	check(Dialogue.matches(home.state,{"flags_all":["editor_story_done"],"day_min":1,"has_items":{"water":1}}) and not Dialogue.matches(home.state,{"account_min":100000}), "editor condition grammar checks state")
	var meet := Dialogue.encounter(home.state,"editor_test")
	check(Dialogue.pending(home.state,meet).is_empty(),"cross-day follow-up cannot trigger on the same day")
	home.state.next_day()
	check(home.state.npc_affection.get("editor_test") == 10 and home.state.narrative_history.has("editor_test/test_story"),"next day keeps reputation and completed narrative events")
	meet = Dialogue.encounter(home.state,"editor_test")
	check(Dialogue.pending(home.state,meet).get("id") == "explore_followup","exploration story gates on previous-day event, affinity and faction trust")
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
	check(home.surface_block.CELL_NAMES.size() == 4 and home.surface_block.CELL_NAMES[0].size() == 1,"expanded map cells load in runtime")
	home.surface_block.row = 3
	home.surface_block.player_x = 330
	check(home.surface_block.interaction().get("kind") == "npc","authored exploration NPC is interactable")
	home.surface_block.interact()
	await process_frame
	var panel = home.view.get_child(home.view.get_child_count()-1)
	check(home.surface_block.interacting_npc and "昨天" in panel.text.text,"exploration opens NPC-authored follow-up and pauses movement")
	check(home.state.npc_affection.get("editor_test") == 12 and home.state.faction_trust.get("red") == 14,"exploration inherits and updates trade relationship values")
	panel.advance("")
	panel.finish_interaction()
	await process_frame
	check(not home.surface_block.interacting_npc and home.state.narrative_history.has("editor_test/explore_followup"),"exploration dialogue completes persistent event")
	var street = home.surface_block
	street.row = 0
	street.player_x = 500
	street.move_horizontal(1,20)
	check(street.player_x == 536 and street.street_column(street.player_x) == 0,"short street movement stops at its own endpoint")
	street.row = 1
	street.player_x = 2100
	street.move_horizontal(1,20)
	check(street.player_x == 2216 and street.street_column(street.player_x) == 3,"longer streets retain their extra cells")
	var links_valid := true
	for link in street.map_connections():
		for point in link:
			if point.x >= street.CELL_NAMES[point.y].size(): links_valid = false
	check(links_valid and street.street_column(1500,0) == 0,"ragged minimap connections never reference missing cells")
	var building: Dictionary = street.BUILDINGS[0]
	check(street.building_instances.has(building.id) and is_equal_approx(street.door_x(building),building.x+27),"building instances encapsulate shared geometry")
	home.queue_free()
	await process_frame
	print("CONTENT_RUNTIME: %d checks, %d failures" % [checks,failures])
	if failures == 0: print("CONTENT_RUNTIME_OK")
	quit(1 if failures else 0)
