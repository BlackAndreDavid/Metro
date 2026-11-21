extends SceneTree
const Catalog = preload("res://scripts/items/furniture_catalog.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void:
	load(get_script().resource_path.get_base_dir()+"/support/furniture_fixtures.gd").canonical_profile()
	call_deferred("run")
func button(at: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.position = at
	e.global_position = at
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	root.push_input(e)
func motion(at: Vector2, previous: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	e.relative = at - previous
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(e)
func click(control: Control) -> void:
	await process_frame
	var at := control.get_global_rect().get_center()
	button(at, true)
	button(at, false)
	await process_frame
func painted_point(item) -> Vector2:
	for y in range(item.padded_image.get_height() - 1, -1, -1):
		for x in range(item.padded_image.get_width() - 1, -1, -1):
			if item.padded_image.get_pixel(x,y).a > 0.9:
				return item.get_global_transform() * ((Vector2(x,y) + Vector2(0.5,0.5)) / Vector2(item.padded_image.get_size()) * item.size)
	return item.global_position
func drop_point(mode, placement: Dictionary) -> Vector2:
	var local: Vector2
	if placement.has("mount"):
		local = Catalog.mount_rect(placement.car, placement.mount).get_center()
	else:
		local = Catalog.floor_rect(placement.car).position + (Vector2(placement.x,placement.y) + Vector2(mode.grab_cell) + Vector2(0.5,0.5)) * Catalog.CELL_SIZE
	return mode.backdrop.carriage.get_global_transform() * local
func run() -> void:
	root.size = Vector2i(1280,720)
	var home = load("res://scenes/game/home.tscn").instantiate()
	root.add_child(home)
	home.state.carriage_count = 2
	home.state.store_furniture("preparation") # Move the dependent storage after moving its door.
	home.show_cabin()
	await process_frame
	var mode = home.construction
	await click(home.view.get_node("BuildModeButton"))
	mode.set_process(false) # Deterministic boundary checks while real GUI input remains enabled.
	check(mode.active and current_scene == mode and not home.visible, "independent scene entered by real click")
	check(not mode.actions.has_node("Move") and not mode.actions.has_node("Cancel"), "removed Move and Cancel buttons")
	check(mode.state == home.state, "shared model")
	check(mode.backdrop.carriage.has_node("FurnitureGrid"), "ground grid replaces slots")
	check(mode.backdrop.carriage.get_node("HangingFixtures").has_node("MountGrid"), "separate front mounting grid")
	var item = mode.backdrop.get_node("Carriage/FurnitureSlots/Door")
	var at := painted_point(item)
	var original: Dictionary = home.state.furniture_layout.duplicate(true)
	button(at,true)
	mode._process(0.5)
	check(mode.get_node("HoldProgress").visible and is_equal_approx(mode.get_node("HoldProgress").progress,0.5), "charge ring half full after half a second")
	check(mode.get_node("HoldProgress").position.x > at.x and mode.get_node("HoldProgress").position.y < at.y, "ring above and right of cursor")
	check(not mode.moving and home.state.furniture_layout == original, "half a second cannot move")
	button(at,false)
	await process_frame
	check(mode.selected_id == "door" and not mode.moving and home.state.furniture_layout == original, "short release selects only")
	item = mode.backdrop.get_node("Carriage/FurnitureSlots/Door")
	at = painted_point(item)
	button(at,true)
	mode._process(0.99)
	check(not mode.moving, "less than one second cannot drag")
	mode._process(0.02)
	check(mode.moving and mode.dragging_furniture and not mode.get_node("HoldProgress").visible, "one second unlocks dragging")
	check(mode.backdrop.camera_locked and not mode.backdrop.dragging, "furniture drag cannot pan camera")
	var target := {"car":1,"x":0,"y":0}
	var destination := drop_point(mode,target)
	motion(destination,at)
	check(mode.candidate == target and mode.backdrop.carriage.get_node("FloorPreview").valid, "snapped valid drag preview")
	check(home.state.furniture_layout == original, "drag preview is not a state mutation")
	button(destination,false)
	await process_frame
	check(home.state.furniture_layout.door == target and mode.focused_carriage == 1, "release commits grid placement in destination carriage")
	check(not mode.moving and not mode.backdrop.camera_locked, "release clears drag and camera lock")
	home.state.place_furniture("preparation",{"car":1,"x":17,"y":8})
	mode._refresh("")
	var before_invalid: Dictionary = home.state.furniture_layout.duplicate(true)
	item = mode.backdrop.get_node("Carriage/FurnitureSlots/Door")
	at = painted_point(item)
	button(at,true)
	mode._process(1.0)
	motion(Vector2(1270,710),at)
	button(Vector2(1270,710),false)
	await process_frame
	check(home.state.furniture_layout == before_invalid and not mode.moving, "invalid release preserves original placement")
	item = mode.backdrop.get_node("Carriage/FurnitureSlots/Door")
	at = painted_point(item)
	button(at,true)
	mode._process(0.5)
	motion(at + Vector2(16,0),at)
	mode._process(3)
	button(at + Vector2(16,0),false)
	check(not mode.moving and home.state.furniture_layout == before_invalid, "movement before charging cancels hold")
	mode.select_furniture("door")
	await click(mode.context_actions.get_node("Temporary"))
	check(home.state.furniture_layout.door == null, "contextual temporary storage holds the furniture instance")
	home.state.store_furniture("bed")
	await click(mode.actions.get_node("Warehouse"))
	check(mode.inventory.item_count == 2, "temporary warehouse lists only the held bed and door")
	home.state.place_furniture("door",target) # Restore the exit required by the preparation storage.
	var index := -1
	for i in range(mode.inventory.item_count):
		if mode.inventory.get_item_metadata(i) == "screen": index = i
	check(index == -1, "installed furniture not duplicated in warehouse")
	for i in range(mode.inventory.item_count):
		if mode.inventory.get_item_metadata(i) == "bed": index = i
	mode.inventory.select(index)
	await click(mode.place_button)
	var bed := {"car":0,"x":10,"y":10}
	var point := drop_point(mode,bed)
	motion(point,mode.pointer)
	button(point,true)
	button(point,false)
	await process_frame
	check(home.state.furniture_layout.bed == bed, "warehouse item placed using same grid")
	var screen = mode.backdrop.get_node("Carriage/HangingFixtures/Screen")
	at = painted_point(screen)
	button(at,true)
	mode._process(1)
	var hanging := {"car":1,"mount":3,"x":0,"y":0}
	point = drop_point(mode,hanging)
	motion(point,at)
	check(mode.candidate == hanging and mode.backdrop.carriage.get_node("HangingFixtures/HangingPreview").valid, "screen preview uses independent front mounting plane")
	button(point,false)
	await process_frame
	check(home.state.furniture_layout.screen == hanging, "screen drag snaps to mount capacity")
	await click(mode.actions.get_node("Exit"))
	check(not mode.active and home.visible, "explicit exit restores Home")
	check(home.state.furniture_layout.bed == bed and home.state.furniture_layout.screen == hanging, "exit retains shared edits")
	home.queue_free()
	await process_frame
	print("CONSTRUCTION_FLOW: %d checks, %d failures" % [checks,failures])
	if failures == 0: print("CONSTRUCTION_FLOW_OK")
	quit(1 if failures else 0)
