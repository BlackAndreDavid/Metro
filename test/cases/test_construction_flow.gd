extends SceneTree
const Furniture = preload("res://scripts/items/furniture.gd")
var checks := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func click(at: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.position = at
	press.global_position = at
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	root.push_input(press)
	var release = press.duplicate()
	release.pressed = false
	root.push_input(release)

func click_button(button: Button) -> void:
	await process_frame
	click(button.get_global_rect().get_center())
	await process_frame

func painted_point(item) -> Vector2:
	for y in range(item.padded_image.get_height() - 1, -1, -1):
		for x in range(item.padded_image.get_width() - 1, -1, -1):
			if item.padded_image.get_pixel(x, y).a > 0.9:
				return item.get_global_transform() * ((Vector2(x, y) + Vector2(0.5, 0.5)) / Vector2(item.padded_image.get_size()) * item.size)
	return item.global_position

func run() -> void:
	root.size = Vector2i(1280, 720)
	var home = load("res://scenes/game/home.tscn").instantiate()
	root.add_child(home)
	home.state.carriage_count = 2
	home.show_cabin()
	await process_frame
	var mode = home.construction
	check(mode.scene_file_path == "res://scenes/construction/construction_mode.tscn", "independent module scene")
	check(not mode.active and not mode.visible, "normal mode starts inactive")
	await click_button(home.view.get_node("BuildModeButton"))
	await process_frame
	check(mode.active and mode.visible, "single build entry opens scene via real click")
	check(mode.get_parent() == root and current_scene == mode, "construction is an independent active scene")
	check(mode.state == home.state, "construction shares the Home model")
	check(mode.has_node("World") and mode.find_child("SettingsButton", true, false) == null and not home.is_ancestor_of(mode), "Home UI is absent from construction tree")
	check(not home.visible and home.process_mode == Node.PROCESS_MODE_DISABLED, "no duplicate exit entry")
	check(mode.actions.get_node("Exit").text == "退出建造模式", "explicit exit button")
	for node in mode.actions.get_children():
		if node is Button:
			check(not node.text.begins_with("摆放"), "no per-furniture placement button")
	check(mode.get_node("Toolbar").get_global_rect().end.y <= 144, "module toolbar clears carriage")
	var door = mode.backdrop.get_node("Carriage/FurnitureSlots/Door")
	check(is_instance_of(door, Furniture), "furniture is a reusable class")
	check(mode.registered.size() == 3, "all installed furniture registered generically")
	var original: Dictionary = home.state.furniture_layout.duplicate()
	click(painted_point(door))
	await process_frame
	check(mode.screen == "construction" and mode.selected_id == "door", "world click selects door without exploring")
	check(home.state.furniture_layout == original and not mode.moving, "selection neither moves nor dismantles")
	check(not mode.actions.get_node("Move").disabled and not mode.actions.get_node("Dismantle").disabled, "shared actions enabled for selection")
	door = mode.backdrop.get_node("Carriage/FurnitureSlots/Door")
	check(door.is_selected and door.visual.material.get_shader_parameter("highlighted"), "selected furniture outlined")
	await click_button(mode.actions.get_node("Move"))
	await process_frame
	check(mode.moving and home.state.furniture_layout == original, "move previews without mutating layout")
	check(not mode.can_place_at(5) and not mode.can_place_at(6), "door footprint and mount constraints preserved")
	var layer = mode.backdrop.get_node("Carriage/FurnitureSlots")
	check(layer.has_node("Slot13"), "compatible two-cell destination offered in added car")
	await click_button(mode.actions.get_node("Cancel"))
	check(not mode.moving and mode.selected_id.is_empty() and home.state.furniture_layout == original, "cancel is nondestructive")
	mode.select_furniture("door")
	mode.begin_move()
	await process_frame
	var target = mode.backdrop.get_node("Carriage/FurnitureSlots/Slot13")
	click(target.get_global_rect().get_center())
	await process_frame
	check(home.state.furniture_layout.door == 13 and mode.focused_carriage == 1, "mouse move commits in destination carriage")
	check(not mode.moving and mode.selected_id == "door", "selection retained after move")
	await click_button(mode.actions.get_node("Dismantle"))
	check(home.state.furniture_layout.door == -1 and mode.selected_id.is_empty(), "explicit dismantle stores selected furniture")
	await click_button(mode.actions.get_node("Warehouse"))
	check(mode.get_node("Warehouse").visible and mode.inventory.item_count == 3, "single warehouse includes dismantled and unplaced items")
	var index := -1
	for i in range(mode.inventory.item_count):
		if mode.inventory.get_item_metadata(i) == "door":
			index = i
	check(index >= 0, "dismantled door available for reuse")
	mode.inventory.select(index)
	await click_button(mode.place_button)
	await process_frame
	check(mode.selected_id == "door" and mode.moving and not mode.get_node("Warehouse").visible, "shared warehouse placement starts preview")
	mode.place_at(3)
	check(home.state.furniture_layout.door == 3, "dismantled object can be restored without duplication")
	mode.select_furniture("screen")
	mode.begin_move()
	check(mode.can_place_at(7) and not mode.can_place_at(5), "screen uses only railing mounts")
	mode.place_at(7)
	check(home.state.furniture_layout.screen == 7, "same module moves screen")
	mode.select_furniture("locker")
	check(mode.screen == "construction" and mode.selected_id == "locker", "same module selects storage furniture")
	await click_button(mode.actions.get_node("Exit"))
	await process_frame
	check(not mode.active and not mode.visible and not mode.moving and mode.selected_id.is_empty(), "exit button fully leaves construction")
	check(home.view.get_node("BuildModeButton").visible, "normal entry restored")
	home.home_backdrop.get_node("Carriage/FurnitureSlots/Locker").use()
	check(home.screen == "locker", "normal furniture action restored after exit")
	home.show_cabin()
	mode.enter()
	await click_button(mode.actions.get_node("Expand"))
	check(mode.screen == "expansion" and mode.active and mode.get_node("Expansion").visible, "expansion uses module action without overlay")
	await click_button(mode.get_node("Expansion/Center/Panel/Margin/Items/Buttons/Back"))
	check(mode.visible and mode.selected_id.is_empty(), "real expansion Back button preserves construction")
	for kind in mode.state.EXPANSION_COST:
		for i in range(mode.state.EXPANSION_COST[kind]):
			mode.state.add_supply(kind, "locker")
	await click_button(mode.actions.get_node("Expand"))
	await click_button(mode.get_node("Expansion/Center/Panel/Margin/Items/Buttons/Confirm"))
	check(mode.state.carriage_count == 3 and home.state.carriage_count == 3 and mode.screen == "construction", "independent expansion confirmation updates shared model")
	mode.select_furniture("door")
	mode.begin_move()
	var before_escape: Dictionary = home.state.furniture_layout.duplicate()
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	mode._unhandled_key_input(esc)
	check(mode.active and not mode.moving and home.state.furniture_layout == before_escape, "escape cancels current move")
	mode._unhandled_key_input(esc)
	check(not mode.active, "escape exits with no selection")
	home.queue_free()
	await process_frame
	print("CONSTRUCTION_FLOW: %d checks, %d failures" % [checks, failures])
	if failures == 0:
		print("CONSTRUCTION_FLOW_OK")
	quit(1 if failures else 0)
