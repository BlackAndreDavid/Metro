extends SceneTree
const State=preload("res://scripts/cabin_state.gd")
const Rail=preload("res://scripts/cabin_map.gd")
const Repair=preload("res://scripts/core/save_repair.gd")
var failures:=0
var checks:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func _initialize()->void:call_deferred("run")
func mouse(at: Vector2,down: bool)->void:
	var event:=InputEventMouseButton.new();event.position=at;event.global_position=at;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;root.push_input(event,true)
func motion(at: Vector2,previous: Vector2)->void:
	var event:=InputEventMouseMotion.new();event.position=at;event.global_position=at;event.relative=at-previous;event.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(event,true)
func drag(start: Vector2,destination: Vector2)->void:
	mouse(start,true);motion(start+Vector2(18,0),start);await process_frame
	motion(destination,start+Vector2(18,0));await process_frame
	check(root.gui_is_dragging(),"native drag starts through actual controls")
	mouse(destination,false);await process_frame
func cargo_grid(home: Control,container: String)->Control:
	for grid in home.grids:
		if grid.container==container:return grid
	return null
func cargo_point(grid: Control,entry: Dictionary)->Vector2:
	return grid.global_position+(Vector2(entry.x,entry.y)+Vector2(.5,.5))*grid.cell_size
func run()->void:
	var state:=State.new()
	check(state.grid_size("preparation")==Vector2i(8,6) and state.preparation.size()==4,"separate 8x6 warehouse has four physical starter tools")
	check(not state.carried_tools().light and not state.carried_tools().wide,"stored tools grant no carried capability")
	var lamp:Dictionary=state.preparation.filter(func(e):return e.kind=="flashlight")[0]
	check(state.auto_place({"source":"preparation","id":lamp.id,"rotated":false},"bag").is_empty() and state.carried_tools().light,"warehouse to bag grants flashlight capability")
	check(state.equip_active(lamp.id).is_empty() and state.carried_tools().light,"active tool no longer takes bag cells and remains carried")
	check(state.depart({"heavy":false,"inventory_tools":true},0).is_empty() and state.gear.light and not state.gear.crowbar,"departure capabilities come only from carried items")
	check(state.use_active().is_empty() and state.flashlight_on and not state.active_item.is_empty(),"Space uses flashlight without consuming tool")
	var warehouse: Array=state.preparation.duplicate(true)
	check(not state.place({"source":"preparation","id":warehouse[0].id,"rotated":false},"bag",Vector2i.ZERO),"base warehouse inaccessible while exploring")
	state.fail_trip()
	check(state.preparation==warehouse and state.active_item.is_empty(),"timeout loses carried tools but preserves stored tools")
	state=State.new();state.inventory.clear()
	var pack:Dictionary=state.preparation.filter(func(e):return e.kind=="large_backpack")[0]
	check(state.place({"source":"preparation","id":pack.id,"rotated":false},"backpack",Vector2i.ZERO) and state.bag_size()==Vector2i(6,5),"equipped large backpack expands storage")
	state.inventory.append(state.make_entry("bolts",Vector2i(5,4),false))
	var before:=state.save_data().duplicate(true)
	check(not state.auto_place({"source":"backpack","id":pack.id,"rotated":false},"preparation").is_empty() and state.save_data()==before,"cannot unload a backpack containing cargo")
	state.inventory.clear()
	var small:Dictionary=state.preparation.filter(func(e):return e.kind=="small_backpack")[0]
	check(state.place({"source":"preparation","id":small.id,"rotated":false},"backpack",Vector2i.ZERO) and state.bag_size()==Vector2i(5,4),"equipping small backpack restores its storage capacity")
	var identities: Array=state.preparation.map(func(e):return e.id)
	check(state.sort_container("preparation").is_empty() and state.preparation.all(func(e):return e.id in identities),"sorting warehouse preserves item identities")
	var materials:=State.new()
	for kind in materials.EXPANSION_COST:
		for n in range(materials.EXPANSION_COST[kind]):materials.add_supply(kind,"preparation")
	check(materials.expand_carriage().is_empty() and materials.material_count("steel_plate")==0 and materials.material_count("bolts")==0 and materials.material_count("tools")==0,"expansion consumes warehouse materials exactly once")
	var legacy:=State.new();legacy.wide_bag=true;legacy.inventory.append(legacy.make_entry("bolts",Vector2i(5,4),false));legacy.sync_carried_tools()
	check(legacy.bag_size()==Vector2i(5,4) and legacy.depart({"heavy":false,"inventory_tools":true},0).is_empty(),"departure reflows legacy out-of-bounds positions into the equipped backpack")
	var saved:=state.save_data().duplicate(true)
	var loaded:=State.new()
	check(loaded.load_data(saved,Rail.STATIONS.keys()) and loaded.preparation.size()==4,"warehouse persists in v17 saves")
	saved.version=16;saved.furniture_layout.erase("preparation");saved.furniture_layout.erase("window");saved.erase("preparation")
	check(loaded.load_data(saved,Rail.STATIONS.keys()) and loaded.preparation.size()==4,"v16 migrates existing cargo plus new starter warehouse")
	check(loaded.depart({"heavy":false,"inventory_tools":true},0).is_empty() and not loaded.gear.light,"may deliberately depart without a flashlight")
	check(not loaded.toggle_flashlight().is_empty(),"missing physical flashlight cannot light")
	loaded.end_trip();saved=loaded.save_data().duplicate(true)
	saved.preparation[0].x=100
	var fixed:=Repair.repair(saved,Rail.STATIONS.keys())
	check(not fixed.has("error") and loaded.load_data(fixed.data,Rail.STATIONS.keys()) and loaded.preparation.size()==4,"save repair preserves and repacks preparation storage")
	var home=load("res://scenes/game/home.tscn").instantiate();root.add_child(home);await process_frame
	home.show_cabin();home.state.Furniture.DEFINITIONS.preparation.perform(home);await process_frame
	check(home.screen=="cabin" and home.find_child("StorageDock",true,false)!=null,"preparation furniture opens ordinary storage instead of departure")
	for child in home.get_children():
		if child.get_script()==load("res://scripts/construction/storage_editor.gd"):child.queue_free()
	await process_frame
	home.state.Furniture.DEFINITIONS.door.perform(home);await process_frame
	check(home.screen=="gear", "only the door action opens departure")
	home.view.toggle_bag();await process_frame
	var targets:Array=[]
	for grid in home.grids:targets.append(grid.container)
	check("preparation" in targets and "bag" in targets and "battery" not in targets and is_instance_valid(home.view.equipment.active),"preparation uses shared grids and equipment instead of a standalone battery slot")
	var bag: Control
	for grid in home.grids:
		if grid.container=="bag":bag=grid
	var tool:Dictionary=home.state.preparation.filter(func(e):return e.kind=="flashlight")[0]
	var spot:Dictionary=home.state.first_free_placement("flashlight","bag")
	home.select_cargo("preparation",tool.id);home.selection.rotated=spot.rotated
	home.pointer_position=bag.get_global_transform_with_canvas()*(Vector2(spot.cell)*bag.cell_size+Vector2(5,5))
	bag._drop_data(Vector2.ZERO,home.selection)
	check(home.screen=="gear" and home.state.carried_tools().light and home.selection.is_empty(),"dropping a warehouse tool into bag stays in preparation UI and refreshes capability")
	var page: Control=home.view
	var native_tool: Dictionary=home.state.inventory.filter(func(e):return e.kind=="flashlight")[0]
	var target: Dictionary=home.state.first_free_placement("flashlight","preparation")
	var prep_grid: Control=cargo_grid(home,"preparation");bag=cargo_grid(home,"bag")
	await drag(cargo_point(bag,native_tool),prep_grid.global_position+(Vector2(target.cell)+Vector2(.5,.5))*prep_grid.cell_size)
	check(home.state.find_entry("preparation",native_tool.id).size()>0 and home.view==page and home.selection.is_empty(),"real bag-to-preparation drag refreshes in place")
	var stored_tool: Dictionary=home.state.find_entry("preparation",native_tool.id)
	target=home.state.first_free_placement("flashlight","bag")
	await drag(cargo_point(prep_grid,stored_tool),bag.global_position+(Vector2(target.cell)+Vector2(.5,.5))*bag.cell_size)
	check(home.state.carried_tools().light and home.view==page and home.selection.is_empty(),"real preparation-to-bag drag refreshes in place")
	native_tool=home.state.find_entry("bag",native_tool.id)
	await drag(cargo_point(bag,native_tool),home.view.equipment.active.get_global_rect().get_center())
	check(home.state.active_item.get("id")==native_tool.id and home.state.carried_tools().light and home.state.find_entry("bag",native_tool.id).is_empty(),"equipment drag keeps a flashlight carried outside inventory space")
	target=home.state.first_free_placement("flashlight","preparation")
	await drag(home.view.equipment.active.get_global_rect().get_center(),prep_grid.global_position+(Vector2(target.cell)+Vector2(.5,.5))*prep_grid.cell_size)
	check(home.state.active_item.is_empty() and not home.state.carried_tools().light and home.state.find_entry("preparation",native_tool.id).size()>0,"equipment can be dragged back to preparation storage")
	stored_tool=home.state.find_entry("preparation",native_tool.id)
	await drag(cargo_point(prep_grid,stored_tool),home.view.equipment.active.get_global_rect().get_center())
	check(home.state.active_item.get("id")==native_tool.id and home.state.find_entry("preparation",native_tool.id).is_empty(),"equipment accepts direct warehouse-to-slot dragging")
	var before_pixels: PackedByteArray
	if DisplayServer.get_name()!="headless":
		await process_frame
		await RenderingServer.frame_post_draw
		before_pixels=root.get_texture().get_image().get_region(Rect2i(Vector2i(bag.global_position),Vector2i(44,44))).get_data()
	var swapping:=State.new();var wide_tool: Dictionary=swapping.preparation.filter(func(e):return e.kind=="large_backpack")[0]
	check(swapping.place({"source":"preparation","id":wide_tool.id,"rotated":false},"backpack",Vector2i.ZERO) and swapping.bag_size()==Vector2i(6,5),"equipped backpack expands capacity")
	swapping.inventory.clear()
	for y in range(5):
		for x in range(6):swapping.inventory.append(swapping.make_entry("bolts",Vector2i(x,y),false))
	var outgoing:Dictionary=swapping.preparation.filter(func(e):return e.kind=="small_backpack")[0];var swap_before:Dictionary=swapping.save_data().duplicate(true)
	check(not swapping.place({"source":"preparation","id":outgoing.id,"rotated":false},"backpack",Vector2i.ZERO) and swapping.save_data()==swap_before,"equipment swap that would clip cargo is atomic")
	if DisplayServer.get_name()!="headless" and not OS.get_environment("METRO_TEST_RESULTS").is_empty():
		await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(OS.get_environment("METRO_TEST_RESULTS"))
		check(root.get_texture().get_image().get_region(Rect2i(Vector2i(bag.global_position),Vector2i(44,44))).get_data()==before_pixels,"persistent inventory textures survive a catalogue refresh")
		root.get_texture().get_image().save_png(OS.get_environment("METRO_TEST_RESULTS").path_join("departure-equipment.png"))
	home.queue_free();await process_frame
	print("PREPARATION_OK: %d checks, %d failures" % [checks,failures]);quit(1 if failures else 0)
