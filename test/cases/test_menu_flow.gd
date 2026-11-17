extends SceneTree

var checks := 0
var failed := false

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failed = true
		push_error(description)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var session = root.get_node("GameSession")
	session.save_directory = OS.get_environment("METRO_TEST_RESULTS").path_join("slots")
	check(session.create_slot(0, "无效") == ERR_INVALID_PARAMETER, "reject invalid slot")
	check(session.create_slot(1, "  ") == ERR_INVALID_PARAMETER, "reject blank base name")
	for slot in range(1, 4):
		check(session.create_slot(slot, "基地%d" % slot) == OK, "create slot")
		check(session.slot_info(slot).name == "基地%d" % slot, "name persisted")
	check(session.create_slot(1, "覆盖") == ERR_ALREADY_EXISTS, "protect existing save")
	var menu = load("res://scenes/ui/main_menu.tscn").instantiate()
	root.add_child(menu)
	check(menu.get_node("Center/Panel/Margin/Items/Start").text == "开始", "menu start button")
	menu.show_settings()
	menu.queue_free()
	await process_frame
	var slots = load("res://scenes/ui/save_select.tscn").instantiate()
	root.add_child(slots)
	slots.create_dialog(1)
	slots.queue_free()
	await process_frame
	check(session.select_slot(2), "select second save")
	var cabin = load("res://scenes/game/home.tscn").instantiate()
	root.add_child(cabin)
	check(cabin.save_path == session.slot_path(2), "cabin uses selected slot")
	check(cabin.state.base_name == "基地2", "cabin loads correct base")
	check(cabin.state.save_next_day(cabin.save_path) == OK, "save next day")
	check(session.slot_info(2).day == 2, "selected save advances")
	check(session.slot_info(1).day == 1 and session.slot_info(3).day == 1, "other slots isolated")
	cabin.queue_free()
	await process_frame
	var broken := FileAccess.open(session.slot_path(3), FileAccess.WRITE)
	broken.store_string("bad json")
	broken.close()
	check(not session.select_slot(3), "reject corrupt save")
	var suite = load(OS.get_environment("METRO_TEST_ROOT").path_join("cases/test_state.gd")).new()
	var runner = load("res://addons/godot_ai/testing/test_runner.gd").new()
	var result = runner.run_suites([suite], "game_state", "", {}, true)
	print("STATE_RESULT: ", JSON.stringify(result))
	check(result.total == 1 and result.failed == 0 and result.skipped == 0 and result.results[0].assertion_count == 33, "existing state regression")
	for slot in range(1, 4):
		DirAccess.remove_absolute(session.slot_path(slot))
	DirAccess.remove_absolute(session.save_directory)
	print("MENU_FLOW: %d checks, failed=%s" % [checks, failed])
	quit(1 if failed else 0)
