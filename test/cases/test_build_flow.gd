extends SceneTree

const State = preload("res://scripts/cabin_state.gd")
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

func add_recipe(state) -> void:
	for kind in State.EXPANSION_COST:
		for i in range(State.EXPANSION_COST[kind]):
			check(state.add_supply(kind, "locker"), "test recipe fits locker")

func run() -> void:
	var state := State.new()
	check(state.carriage_count == 1 and state.furniture_layout == {"bed": -1, "computer": -1}, "new game has two owned unplaced furniture")
	check(state.travel_cost_per_stop() == 30 and state.daily_power_cost() == 2, "base costs preserved")
	check(not state.place_furniture("unknown", 0).is_empty(), "reject unknown furniture")
	check(not state.place_furniture("bed", 2).is_empty(), "reject slot outside existing carriage")
	check(state.place_furniture("bed", 1).is_empty(), "place bed")
	check(not state.place_furniture("computer", 1).is_empty() and state.furniture_layout.bed == 1, "occupied slot cannot be overwritten")
	check(state.place_furniture("computer", 0).is_empty(), "place computer")
	check(state.store_furniture("bed").is_empty() and state.furniture_layout.bed == -1, "store bed")
	check(state.place_furniture("computer", 1).is_empty() and state.furniture_layout.computer == 1, "move single furniture without duplication")
	state.trip_active = true
	check(not state.place_furniture("bed", 0).is_empty() and not state.expand_carriage().is_empty(), "no arrangement or expansion during expedition")
	state.trip_active = false
	var count_before := state.inventory.size() + state.locker.size()
	check(not state.expand_carriage().is_empty() and state.inventory.size() + state.locker.size() == count_before and state.carriage_count == 1, "insufficient recipe is atomic")
	# Material may be split between the locker and backpack.
	add_recipe(state)
	var bolt = state.locker.filter(func(entry): return entry.kind == "bolts")[0]
	state.locker.erase(bolt)
	var free := state.first_free_placement("bolts", "bag")
	bolt.x = free.cell.x
	bolt.y = free.cell.y
	state.inventory.append(bolt)
	check(state.expand_carriage().is_empty() and state.carriage_count == 2, "expand consuming mixed storage recipe")
	for kind in State.EXPANSION_COST:
		check(state.material_count(kind) == 0, "consume exact recipe")
	check(state.travel_cost_per_stop() == 40 and state.daily_power_cost() == 4, "expanded travel and daily costs")
	state.car_power = 100
	check(state.travel_to("四平路", 1) and state.car_power == 60, "actual train movement charges expanded cost")
	check(state.extraction_cost("邮电新村") == 40, "cross-station extraction cost matches expanded train")
	state.trip_active = true
	state.trip_deadline_ms = Time.get_ticks_msec() + 10000
	check(state.extract_at("邮电新村").is_empty() and state.car_power == 20, "actual extraction consumes expanded cost")
	state.car_power = 100
	check(state.place_furniture("bed", 3).is_empty(), "place in added carriage")
	var path := OS.get_environment("METRO_TEST_RESULTS").path_join("expanded_save.json")
	check(state.save_next_day(path) == OK and state.car_power == 96, "daily save debits expanded drain")
	var restored := State.new()
	check(restored.load_cabin(path, Rail.STATIONS.keys()), "expanded layout loads")
	check(restored.carriage_count == 2 and restored.furniture_layout.bed == 3 and restored.furniture_layout.computer == 1 and restored.car_power == 96, "layout train and power round-trip")
	var snapshot := restored.save_data()
	var invalid := snapshot.duplicate(true)
	invalid.furniture_layout.bed = invalid.furniture_layout.computer
	restored.write_save(path, invalid)
	check(not restored.load_cabin(path, Rail.STATIONS.keys()) and restored.save_data() == snapshot, "invalid overlapping layout cannot partially mutate live state")
	invalid = snapshot.duplicate(true)
	invalid.carriage_count = 99
	restored.write_save(path, invalid)
	check(not restored.load_cabin(path, Rail.STATIONS.keys()) and restored.carriage_count == 2, "reject excessive saved carriage count")
	var legacy := snapshot.duplicate(true)
	legacy.version = 3
	legacy.erase("carriage_count")
	legacy.erase("furniture_layout")
	restored.write_save(path, legacy)
	check(restored.load_cabin(path, Rail.STATIONS.keys()) and restored.carriage_count == 1 and restored.furniture_layout == {"bed": 1, "computer": 0}, "version 3 migrates old furniture positions")
	add_recipe(state)
	check(state.expand_carriage().is_empty() and state.carriage_count == 3, "second expansion")
	add_recipe(state)
	var inventory_before := state.save_data().duplicate(true)
	check(not state.expand_carriage().is_empty() and state.save_data() == inventory_before, "cap rejects without consuming materials")
	# Runtime UI: empty slots -> owned furniture -> outline -> actions -> new car.
	root.size = Vector2i(1280, 720)
	var home = load("res://scenes/game/home.tscn").instantiate()
	root.add_child(home)
	home.show_cabin()
	await process_frame
	var backdrop = home.home_backdrop
	check(backdrop.get_node("Carriage/FurnitureSlots").get_child_count() == 2, "new home exposes two empty slots")
	home.select_home_furniture("bed")
	home.place_home_furniture(1)
	home.select_home_furniture("computer")
	home.place_home_furniture(0)
	check(home.state.furniture_layout == {"bed": 1, "computer": 0}, "placement toolbar updates state")
	home.toggle_placement()
	await process_frame
	backdrop = home.home_backdrop
	var bed = backdrop.get_node("Carriage/FurnitureSlots/Bed")
	var computer = backdrop.get_node("Carriage/FurnitureSlots/Computer")
	check(bed.definition.texture.get_size() == Vector2(62, 10) and computer.definition.texture.get_size() == Vector2(23, 18), "cropped furniture textures")
	bed.set_highlighted(true)
	check(bed.caption.visible and bed.caption.text == "睡觉" and bed.visual.material.get_shader_parameter("highlighted"), "shared outline and action text")
	check(not computer._has_point(Vector2.ZERO), "transparent padding is not clickable")
	var desk_bounds: Rect2 = computer.get_rect()
	check(desk_bounds.position.is_equal_approx(Vector2(750, 416)), "computer crop origin compensated")
	check(bed.get_rect().get_center().is_equal_approx(Vector2(978, 480)), "bed crop alignment preserved")
	bed.use()
	check(home.screen == "rest", "bed owns rest action")
	home.show_cabin()
	computer = home.home_backdrop.get_node("Carriage/FurnitureSlots/Computer")
	computer.use()
	check(home.screen == "news", "computer owns computer action")
	home.show_cabin()
	backdrop = home.home_backdrop
	backdrop.set_process(false)
	backdrop.pan_by(Vector2(100, 0))
	backdrop._process(0.1)
	var first: float = backdrop.offset.x
	backdrop._process(0.1)
	check(is_equal_approx(100 - first, first - backdrop.offset.x) and is_equal_approx(first, 84), "constant speed return")
	backdrop._process(10.0)
	check(backdrop.offset == Vector2.ZERO, "return stops at center without overshoot")
	backdrop.start_drag(Vector2(500, 300))
	backdrop.pan_by(Vector2(60, 0))
	backdrop._process(0.1)
	check(backdrop.offset.x == 60, "no auto return while mouse held")
	backdrop.dragging = false
	# Inspect generated fixed HUD buttons at the centered view.
	for child in home.view.get_children():
		if child is Button:
			check(child.get_rect().end.y <= 144, "option buttons above carriage: %s %s" % [child.text, child.get_rect()])
	add_recipe(home.state)
	home.show_expansion()
	home.confirm_expansion()
	await process_frame
	backdrop = home.home_backdrop
	check(backdrop.train_count == 2 and backdrop.carriage.has_node("Carriage2"), "new car uses carriage texture")
	check(backdrop.get_node("Carriage/FurnitureSlots").get_child_count() == 4, "expansion adds two usable slots")
	var center: Vector2 = backdrop.carriage.position + Vector2(640 + 972 * backdrop.focused_carriage, 360) * backdrop.train_zoom
	check(center.is_equal_approx(Vector2(640, 360)), "expanded train focuses current carriage")
	backdrop.set_process(false)
	# Start on car 2; drag slightly right across the midpoint to car 1.
	backdrop.start_drag(Vector2(500, 300))
	backdrop.pan_by(Vector2(256, 30))
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	backdrop._input(release)
	check(backdrop.focused_carriage == 0 and home.focused_carriage == 0, "multi-car return picks nearest center")
	var before_return: Vector2 = backdrop.offset
	backdrop._process(0.1)
	check(is_equal_approx(before_return.distance_to(backdrop.offset), 16), "multi-car return uses constant speed")
	backdrop._process(10.0)
	var first_center: Vector2 = backdrop.carriage.position + Vector2(640, 360) * backdrop.train_zoom
	check(first_center.is_equal_approx(Vector2(640, 360)), "nearest first carriage ends centered")
	backdrop.start_drag(Vector2(500, 300))
	backdrop.pan_by(Vector2(-256, 0))
	backdrop.dragging = false
	backdrop.choose_nearest_carriage()
	check(backdrop.focused_carriage == 1, "opposite drag focuses second carriage")
	backdrop._process(10.0)
	home.show_cabin()
	check(home.home_backdrop.focused_carriage == 1, "page refresh preserves focused carriage")
	home.select_home_furniture("bed")
	home.place_home_furniture(3)
	check(home.state.furniture_layout.bed == 3, "UI moves bed into added car")
	var moved_bed = home.home_backdrop.get_node("Carriage/FurnitureSlots/Bed")
	moved_bed.use()
	check(home.state.furniture_layout.bed == -1, "arrangement click stores furniture")
	# A third carriage must participate in nearest-center selection as well.
	home.state.carriage_count = 3
	home.focused_carriage = 1
	home.show_cabin()
	backdrop = home.home_backdrop
	backdrop.set_process(false)
	backdrop.pan_by(Vector2(220, 0))
	backdrop.choose_nearest_carriage()
	check(backdrop.focused_carriage == 0, "three-car nearest selection")
	backdrop.offset = (backdrop.target_for_carriage(0) + backdrop.target_for_carriage(1)) / 2
	backdrop.choose_nearest_carriage()
	check(backdrop.focused_carriage == 0, "equal-distance tie keeps current focus")
	backdrop.focused_carriage = 1
	backdrop.choose_nearest_carriage()
	check(backdrop.focused_carriage == 1, "tie does not oscillate between cars")
	home.queue_free()
	await process_frame
	print("BUILD_FLOW: %d checks, %d failures" % [checks, failures])
	if failures == 0:
		print("BUILD_FLOW_OK")
	quit(1 if failures else 0)
