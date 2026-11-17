extends SceneTree
const State = preload("res://scripts/cabin_state.gd")
const Catalog = preload("res://scripts/items/furniture_catalog.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var expected := {"computer": Vector2i(2,2), "locker": Vector2i(2,12), "door": Vector2i(6,12), "bed": Vector2i(4,1), "screen": Vector2i(2,2)}
	for kind in expected: check(Catalog.DEFINITIONS[kind].grid_size == expected[kind], "explicit footprint: " + kind)
	check(Catalog.CELL_SIZE.x == Catalog.CELL_SIZE.y, "furniture cells are square")
	check(Catalog.placement_rect("locker",Catalog.default_placement("locker")).size == Vector2(52,312), "locker display occupies 2x12 square cells")
	check(Catalog.placement_rect("door",Catalog.default_placement("door")).size == Vector2(156,312), "door display occupies 6x12 square cells")
	var state := State.new()
	check(not state.place_furniture("locker", {"car":0,"x":20,"y":1}).is_empty(), "locker must fit twelve rows")
	check(not state.place_furniture("bed", {"car":0,"x":31,"y":11}).is_empty(), "right edge bounds")
	check(not state.place_furniture("door", {"car":0,"x":8,"y":1}).is_empty(), "door must fit all twelve rows")
	check(not state.place_furniture("computer", {"car":0,"x":9,"y":5}).is_empty(), "floor overlap rejected")
	check(not state.place_furniture("bed", {"car":1,"x":0,"y":0}).is_empty(), "missing carriage rejected")
	check(not state.place_furniture("screen", {"car":0,"x":0,"y":0}).is_empty(), "screen cannot use floor")
	check(not state.place_furniture("locker", {"car":0,"mount":0,"x":0,"y":0}).is_empty(), "ground furniture cannot use mounting plane")
	for mount in range(4):
		check(state.place_furniture("screen", {"car":0,"mount":mount,"x":0,"y":0}).is_empty(), "four independent mounts")
	check(not state.place_furniture("screen", {"car":0,"mount":0,"x":1,"y":0}).is_empty(), "mount maximum 2x2")
	check(state.place_furniture("computer", {"car":0,"x":16,"y":0}).is_empty(), "floor independent of hanging screen")
	var before := state.save_data()
	before.furniture_layout.computer.x = 14
	check(state.furniture_layout.computer.x == 16, "save snapshot does not alias nested placement")
	root.size = Vector2i(1280,720)
	var home = load("res://scenes/game/home.tscn").instantiate()
	root.add_child(home)
	home.show_cabin()
	await process_frame
	var backdrop = home.home_backdrop
	check(backdrop.carriage.get_node("HangingFixtures").get_index() > backdrop.carriage.get_node("FurnitureSlots").get_index(), "hanging visuals and GUI are in front of all ground furniture")
	for name in ["Door","Locker"]:
		var item = backdrop.get_node("Carriage/FurnitureSlots/" + name)
		var bounds := Catalog.placement_rect(name.to_lower(),home.state.furniture_layout[name.to_lower()])
		var raw := Vector2(item.definition.texture.get_size())
		check((item.size * raw / (raw + Vector2(4,4))).is_equal_approx(bounds.size), "sprite size matches occupied grid: " + name)
		item.set_highlighted(true)
		check(item.caption.visible and item.visual.material.get_shader_parameter("highlighted") and item.tooltip_text.is_empty(), "single shared hover: " + name)
	var screen = backdrop.get_node("Carriage/HangingFixtures/Screen")
	check(screen.definition.grid_size == Vector2i(2,2) and screen.get_parent().name == "HangingFixtures", "screen renders on mount plane")
	screen.use()
	check(home.map_scene.active and home.map_scene.screen == "map", "screen owns normal station action")
	home.show_cabin()
	home.home_backdrop.get_node("Carriage/FurnitureSlots/Locker").use()
	check(home.screen == "locker", "normal locker interaction")
	home.show_cabin()
	home.home_backdrop.get_node("Carriage/FurnitureSlots/Door").use()
	check(home.screen == "gear", "normal door interaction")
	home.queue_free()
	await process_frame
	print("FIXTURE_FLOW: %d checks, %d failures" % [checks, failures])
	if failures == 0: print("FIXTURE_FLOW_OK")
	quit(1 if failures else 0)
