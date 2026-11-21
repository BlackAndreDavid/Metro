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
	check(state.auto_place({"source":"preparation","id":pack.id,"rotated":false},"bag").is_empty() and state.bag_size()==Vector2i(6,5),"carried large backpack expands storage")
	state.inventory.append(state.make_entry("bolts",Vector2i(5,4),false))
	var before:=state.save_data().duplicate(true)
	check(not state.auto_place({"source":"bag","id":pack.id,"rotated":false},"preparation").is_empty() and state.save_data()==before,"cannot remove backpack while cargo exceeds small bounds")
	state.inventory.pop_back()
	check(state.auto_place({"source":"bag","id":pack.id,"rotated":false},"preparation").is_empty() and state.bag_size()==Vector2i(5,4),"returning backpack safely shrinks carry capacity")
	var identities: Array=state.preparation.map(func(e):return e.id)
	check(state.sort_container("preparation").is_empty() and state.preparation.all(func(e):return e.id in identities),"sorting warehouse preserves item identities")
	var materials:=State.new()
	for kind in materials.EXPANSION_COST:
		for n in range(materials.EXPANSION_COST[kind]):materials.add_supply(kind,"preparation")
	check(materials.expand_carriage().is_empty() and materials.material_count("steel_plate")==0 and materials.material_count("bolts")==0 and materials.material_count("tools")==0,"expansion consumes warehouse materials exactly once")
	var legacy:=State.new();legacy.wide_bag=true;legacy.inventory.append(legacy.make_entry("bolts",Vector2i(5,4),false));legacy.sync_carried_tools()
	check(legacy.bag_size()==Vector2i(6,5) and not legacy.depart({"heavy":false,"inventory_tools":true},0).is_empty(),"legacy wide cargo remains accessible until reorganized or physical backpack carried")
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
	home.show_cabin();home.use_hotspot("preparation");await process_frame
	check(home.screen=="gear" and home.loadout=={"heavy":false,"inventory_tools":true},"furniture opens the new inventory-based departure UI")
	var targets:Array=[]
	for grid in home.grids:targets.append(grid.container)
	check("preparation" in targets and "bag" in targets and "battery" in targets,"preparation screen uses shared drag-enabled grids")
	var bag: Control
	for grid in home.grids:
		if grid.container=="bag":bag=grid
	var tool:Dictionary=home.state.preparation.filter(func(e):return e.kind=="flashlight")[0]
	var spot:Dictionary=home.state.first_free_placement("flashlight","bag")
	home.select_cargo("preparation",tool.id);home.selection.rotated=spot.rotated
	home.pointer_position=bag.get_global_transform_with_canvas()*(Vector2(spot.cell)*44+Vector2(5,5))
	bag._drop_data(Vector2.ZERO,home.selection)
	check(home.screen=="gear" and home.state.carried_tools().light and home.selection.is_empty(),"dropping a warehouse tool into bag stays in preparation UI and refreshes capability")
	home.queue_free();await process_frame
	print("PREPARATION_OK: %d checks, %d failures" % [checks,failures]);quit(1 if failures else 0)
