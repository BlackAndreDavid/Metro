extends SceneTree
const State = preload("res://scripts/cabin_state.gd")
const Catalog = preload("res://scripts/items/furniture_catalog.gd")
const Rail = preload("res://scripts/cabin_map.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var state := State.new()
	check(Catalog.DEFINITIONS.door.slot_span == 2 and Catalog.DEFINITIONS.locker.slot_span == 1, "door occupies twice locker capacity")
	check(Catalog.footprint("door", 3, 1) == [3, 4], "door reserves both floor cells")
	check(not state.place_furniture("locker", 4).is_empty(), "cannot occupy door second half")
	var before := state.furniture_layout.duplicate()
	check(not state.place_furniture("door", 2).is_empty() and state.furniture_layout == before, "failed door move does not overwrite locker")
	state.store_furniture("door")
	check(not state.place_furniture("door", 5).is_empty(), "door cannot extend into hanging cells")
	check(not state.place_furniture("door", 9).is_empty(), "door cannot span carriage boundary")
	check(not state.place_furniture("screen", 5).is_empty(), "screen rejects floor")
	check(not state.place_furniture("locker", 7).is_empty(), "floor furniture rejects hanging point")
	for point in range(4):
		check(state.place_furniture("screen", Catalog.FLOOR_SLOTS + point).is_empty(), "screen can use each of four hanging points")
	check(state.furniture_layout.screen == 9, "screen moved without duplication")
	check(state.place_furniture("door", 3).is_empty(), "door returns to native location")
	var output := OS.get_environment("METRO_TEST_RESULTS")
	var path := output.path_join("fixture_save.json")
	state.save_current(path)
	var restored := State.new()
	check(restored.load_cabin(path, Rail.STATIONS.keys()) and restored.furniture_layout.screen == 9, "hanging placement persists")
	var data := state.save_data()
	data.furniture_layout.locker = 4
	state.write_save(path, data)
	var snapshot := restored.save_data().duplicate(true)
	check(not restored.load_cabin(path, Rail.STATIONS.keys()) and restored.save_data() == snapshot, "saved overlap with door second half rejected atomically")
	data = state.save_data()
	data.furniture_layout.screen = 5
	state.write_save(path, data)
	check(not restored.load_cabin(path, Rail.STATIONS.keys()), "saved screen on floor rejected")
	data = state.save_data()
	data.version = 4
	data.carriage_count = 2
	data.furniture_layout = {"bed": 3, "computer": 0}
	state.write_save(path, data)
	check(restored.load_cabin(path, Rail.STATIONS.keys()), "version 4 layout migrates")
	check(restored.carriage_count == 2 and restored.furniture_layout.bed == 11 and restored.furniture_layout.computer == 0, "legacy two-slot indices remapped without moving carriage")
	check(restored.furniture_layout.door == 3 and restored.furniture_layout.locker == 2 and restored.furniture_layout.screen == 6, "legacy services restored at original positions")
	data.furniture_layout.bed = 0
	state.write_save(path, data)
	check(not restored.load_cabin(path, Rail.STATIONS.keys()), "invalid old overlapping layout still rejected")
	root.size = Vector2i(1280, 720)
	var home = load("res://scenes/game/home.tscn").instantiate()
	root.add_child(home)
	home.show_cabin()
	await process_frame
	var layer = home.home_backdrop.get_node("Carriage/FurnitureSlots")
	var fixtures := {
		"Door": [Vector2(63, 78), Vector2(390, 212), "出站探索"],
		"Locker": [Vector2(25, 76), Vector2(162, 232), "整理物品"],
		"Screen": [Vector2(28, 20), Vector2(266, 232), "查看站点信息"],
	}
	for name in fixtures:
		var item = layer.get_node(name)
		check(item.definition.texture.get_size() == fixtures[name][0], "cropped texture: " + name)
		check((item.position + Vector2(8, 8)).is_equal_approx(fixtures[name][1]), "crop position compensated: " + name)
		item.set_highlighted(true)
		check(item.visual.material.get_shader_parameter("highlighted") and item.caption.visible and item.caption.text == fixtures[name][2], "common highlight and function caption: " + name)
		check(item.tooltip_text.is_empty() and item.get_tooltip().is_empty(), "no native tooltip duplicate: " + name)
		item.set_highlighted(false)
		check(not item.caption.visible, "one caption hides on leave: " + name)
	check(layer.get_node("Screen/StationInfo").text.contains(home.state.station), "screen retains station display")
	check(not home.home_backdrop.carriage.has_node("Hotspots"), "old invisible hotspots removed")
	for child in home.view.get_children():
		if child is Button:
			check(child.text not in ["柜子", "交易", "出站探索", "探索", "布置家具", "扩建车厢"], "duplicate main toolbar action removed")
	check(home.view.has_node("BuildModeButton") and not home.view.has_node("BuildModePanel"), "single build entry when not building")
	home.toggle_build_mode()
	check(home.build_mode and home.view.has_node("BuildModePanel"), "build mode opens child toolbar")
	var toolbar = home.view.get_node("BuildModePanel")
	check(toolbar.get_child(0).text == "家具布置" and toolbar.get_child(1).text == "扩建车厢", "placement and expansion integrated")
	home.select_home_furniture("screen")
	layer = home.home_backdrop.get_node("Carriage/FurnitureSlots")
	check(layer.has_node("Screen") and layer.has_node("Slot7") and layer.has_node("Slot8") and layer.has_node("Slot9"), "four hanger positions displayed including occupied point")
	check(not layer.has_node("Slot0") and not layer.has_node("Slot5"), "screen selection hides incompatible floor cells")
	var hanger = layer.get_node("Slot7")
	var point: Vector2 = hanger.global_position + hanger.size / 2
	var press := InputEventMouseButton.new()
	press.position = point
	press.global_position = point
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	root.push_input(press)
	var release = press.duplicate()
	release.pressed = false
	root.push_input(release)
	await process_frame
	check(home.screen == "cabin" and home.state.furniture_layout.screen == 7, "hanger GUI click takes priority over door behind it")
	home.place_home_furniture(8)
	check(home.state.furniture_layout.screen == 8, "UI hangs screen on chosen railing point")
	home.toggle_build_mode()
	layer = home.home_backdrop.get_node("Carriage/FurnitureSlots")
	check(not home.build_mode and not home.placement_mode, "leaving build clears arrangement mode")
	layer.get_node("Locker").use()
	check(home.screen == "locker", "locker owns storage action")
	home.show_cabin()
	home.home_backdrop.get_node("Carriage/FurnitureSlots/Screen").use()
	check(home.screen == "map", "screen owns station information action")
	home.show_cabin()
	home.home_backdrop.get_node("Carriage/Fixtures/TradeWindow0").activated.emit()
	check(home.screen == "trade", "window retains trade through shared highlight module")
	home.show_cabin()
	home.home_backdrop.get_node("Carriage/FurnitureSlots/Door").use()
	check(home.screen == "gear", "door owns exploration action")
	home.queue_free()
	await process_frame
	print("FIXTURE_FLOW: %d checks, %d failures" % [checks, failures])
	if failures == 0:
		print("FIXTURE_FLOW_OK")
	quit(1 if failures else 0)
