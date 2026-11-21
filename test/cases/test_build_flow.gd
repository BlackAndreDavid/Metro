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
func _initialize() -> void: call_deferred("run")
func recipe(state) -> void:
	for kind in State.EXPANSION_COST:
		for i in range(State.EXPANSION_COST[kind]):
			check(state.add_supply(kind, "locker"), "recipe fits storage")
func run() -> void:
	var state := State.new()
	check(state.carriage_count == 1 and state.furniture_layout.bed != null, "initial non-item bed is already placed")
	check(state.travel_cost_per_stop() == 30 and state.daily_power_cost() == 2, "base power costs")
	var snapshot := state.save_data()
	check(not state.expand_carriage().is_empty() and snapshot == state.save_data(), "insufficient materials do not mutate state")
	recipe(state)
	check(state.expand_carriage().is_empty() and state.carriage_count == 2, "first expansion")
	for kind in State.EXPANSION_COST: check(state.material_count(kind) == 0, "exact recipe consumed")
	check(state.travel_cost_per_stop() == 40 and state.daily_power_cost() == 4, "expanded costs")
	state.car_power = 100
	check(state.travel_to("四平路", 1) and state.car_power == 60, "actual travel cost")
	check(state.extraction_cost("邮电新村") == 40, "expanded extraction quote")
	state.trip_active = true
	state.trip_deadline_ms = Time.get_ticks_msec() + 10000
	check(state.extract_at("邮电新村").is_empty() and state.car_power == 20, "actual expanded extraction cost")
	var bed := Catalog.default_placement("bed", 1)
	check(state.place_furniture("bed", bed).is_empty(), "furniture in added carriage")
	state.car_power = 100
	var path := OS.get_environment("METRO_TEST_RESULTS").path_join("expanded_save.json")
	check(state.save_next_day(path) == OK and state.car_power == 96, "expanded daily power deduction")
	var restored := State.new()
	check(restored.load_cabin(path, Rail.STATIONS.keys()) and restored.furniture_layout.bed == bed, "grid layout save round-trip")
	check(restored.carriage_count == 2 and restored.car_power == 96, "expanded state restored")
	var invalid := restored.save_data()
	invalid.furniture_layout.computer = invalid.furniture_layout.bed.duplicate()
	restored.write_save(path, invalid)
	var before := restored.save_data()
	check(not restored.load_cabin(path, Rail.STATIONS.keys()) and before == restored.save_data(), "invalid overlap load is atomic")
	var legacy := restored.save_data()
	legacy.locker = legacy.locker.filter(func(entry): return entry.kind != "computer")
	legacy.bag = legacy.bag.filter(func(entry): return entry.kind != "computer")
	legacy.version = 5
	for key in legacy.furniture_layout.keys():
		if key not in ["bed","computer","locker","door","screen"]:legacy.furniture_layout.erase(key)
	legacy.furniture_layout = {"bed": 11, "computer": 0, "door": 3, "locker": 2, "screen": 9}
	restored.write_save(path, legacy)
	check(restored.load_cabin(path, Rail.STATIONS.keys()) and restored.furniture_layout.bed.car == 1 and restored.furniture_layout.screen.mount == 3, "legacy slot save migrates carriage and mount")
	var grid_legacy := state.save_data()
	grid_legacy.version = 6
	for key in grid_legacy.furniture_layout.keys():
		if key not in ["bed","computer","locker","door","screen"]:grid_legacy.furniture_layout.erase(key)
	grid_legacy.furniture_layout = {"bed":{"car":1,"x":0,"y":11}, "computer":null, "door":{"car":0,"x":4,"y":0}, "locker":{"car":1,"x":0,"y":0}, "screen":{"car":0,"mount":3,"x":0,"y":0}}
	restored.write_save(path,grid_legacy)
	check(restored.load_cabin(path,Rail.STATIONS.keys()), "version 6 rectangular grid migrates")
	check(restored.furniture_layout.locker.car == 1 and restored.furniture_layout.locker.y == 0 and restored.furniture_layout.bed.car == 1 and restored.furniture_layout.bed.x >= 2, "expanded locker relocates colliding bed in same carriage")
	check(restored.furniture_layout.computer == null and restored.material_count("computer") == 1 and restored.furniture_layout.screen.mount == 3, "grid migration preserves stored computer and hanging mount")
	check(restored.valid_home_layout(restored.save_data()), "migrated square layout is valid")
	grid_legacy.furniture_layout.door.x = 15
	restored.write_save(path,grid_legacy)
	before = restored.save_data()
	check(not restored.load_cabin(path,Rail.STATIONS.keys()) and before == restored.save_data(), "invalid old grid rejected before migration")
	grid_legacy.version = 7
	for key in grid_legacy.furniture_layout.keys():
		if key not in ["bed","computer","locker","door","screen"]:grid_legacy.furniture_layout.erase(key)
	grid_legacy.furniture_layout = {"bed":{"car":1,"x":2,"y":11}, "computer":null, "door":{"car":0,"x":9,"y":0}, "locker":{"car":1,"x":0,"y":0}, "screen":{"car":0,"mount":2,"x":0,"y":0}}
	restored.write_save(path,grid_legacy)
	check(restored.load_cabin(path,Rail.STATIONS.keys()) and restored.valid_home_layout(restored.save_data()), "version 7 square grid migrates enlarged footprints")
	check(restored.furniture_layout.bed.car == 1 and restored.furniture_layout.bed.x >= 3 and restored.furniture_layout.bed.y <= 10, "wider bed moves away from enlarged cabinet and fits interior")
	check(restored.furniture_layout.screen.mount == 2 and restored.material_count("computer") == 1, "version 7 migration preserves mounts and inventory")
	grid_legacy.version = 8
	for key in grid_legacy.furniture_layout.keys():
		if key not in ["bed","computer","locker","door","screen"]:grid_legacy.furniture_layout.erase(key)
	grid_legacy.furniture_layout = {"bed":{"car":0,"x":15,"y":4}, "computer":null, "door":{"car":0,"x":9,"y":0}, "locker":{"car":1,"x":0,"y":0}, "screen":{"car":0,"mount":2,"x":0,"y":0}}
	restored.write_save(path,grid_legacy)
	check(restored.load_cabin(path,Rail.STATIONS.keys()) and restored.valid_home_layout(restored.save_data()), "version 8 migrates wider door and bed")
	check(restored.furniture_layout.bed.car == 0 and restored.furniture_layout.bed.x >= 17 and restored.furniture_layout.screen.mount == 2, "migration retains carriage and hook without overlap")
	var mount_legacy := restored.save_data()
	mount_legacy.version = 9
	for key in mount_legacy.furniture_layout.keys():
		if key not in ["bed","computer","locker","door","screen"]:mount_legacy.furniture_layout.erase(key)
	restored.write_save(path,mount_legacy)
	var old_layout: Dictionary = restored.furniture_layout.duplicate(true)
	check(restored.load_cabin(path,Rail.STATIONS.keys()) and restored.furniture_layout == old_layout, "version 9 screen expansion preserves exact floor layout and hooks")
	var computer_legacy := restored.save_data()
	computer_legacy.version = 10
	for key in computer_legacy.furniture_layout.keys():
		if key not in ["bed","computer","locker","door","screen"]:computer_legacy.furniture_layout.erase(key)
	computer_legacy.furniture_layout.computer = {"car":1,"x":25,"y":10}
	computer_legacy.furniture_layout.bed = {"car":1,"x":27,"y":10}
	computer_legacy.locker = computer_legacy.locker.filter(func(entry): return entry.kind != "computer")
	computer_legacy.bag = computer_legacy.bag.filter(func(entry): return entry.kind != "computer")
	restored.write_save(path,computer_legacy)
	check(restored.load_cabin(path,Rail.STATIONS.keys()) and restored.valid_home_layout(restored.save_data()), "version 10 migration resolves enlarged computer footprint")
	legacy.version = 4
	for key in legacy.furniture_layout.keys():
		if key not in ["bed","computer","locker","door","screen"]:legacy.furniture_layout.erase(key)
	legacy.furniture_layout = {"bed": 3, "computer": 0}
	restored.write_save(path, legacy)
	check(restored.load_cabin(path, Rail.STATIONS.keys()) and restored.furniture_layout.bed.car == 1, "version 4 migration")
	legacy.version = 3
	for key in legacy.furniture_layout.keys():
		if key not in ["bed","computer","locker","door","screen"]:legacy.furniture_layout.erase(key)
	legacy.erase("furniture_layout")
	legacy.erase("carriage_count")
	restored.write_save(path, legacy)
	check(restored.load_cabin(path, Rail.STATIONS.keys()) and restored.carriage_count == 1 and restored.furniture_layout.bed != null, "version 3 migration")
	recipe(state)
	check(state.expand_carriage().is_empty() and state.carriage_count == 3, "second expansion")
	recipe(state)
	before = state.save_data()
	check(not state.expand_carriage().is_empty() and before == state.save_data(), "expansion cap is atomic")
	root.size = Vector2i(1280,720)
	var home = load("res://scenes/game/home.tscn").instantiate()
	root.add_child(home)
	home.state.carriage_count = 2
	home.show_cabin()
	await process_frame
	var backdrop = home.home_backdrop
	backdrop.set_process(false)
	backdrop.pan_by(Vector2(-128,0))
	backdrop.choose_nearest_carriage()
	check(backdrop.focused_carriage == 1, "multi-car release selects closest carriage")
	var distance: float = backdrop.offset.distance_to(backdrop.return_target)
	backdrop._process(0.05)
	check(is_equal_approx(distance - backdrop.offset.distance_to(backdrop.return_target),minf(distance,16)), "camera returns at 320 pixels per second")
	home.queue_free()
	await process_frame
	print("BUILD_FLOW: %d checks, %d failures" % [checks, failures])
	if failures == 0: print("BUILD_FLOW_OK")
	quit(1 if failures else 0)
