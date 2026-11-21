extends SceneTree
const State=preload("res://scripts/cabin_state.gd")
const Catalog=preload("res://scripts/items/furniture_catalog.gd")
const Rail=preload("res://scripts/cabin_map.gd")
const Definition=preload("res://scripts/items/furniture_definition.gd")
var checks:=0
var failures:=0
func check(ok:bool,text:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(text)
func _initialize()->void:call_deferred("run")
func give(state,recipe:Dictionary)->void:
	for kind in recipe:
		for n in range(int(recipe[kind])):check(state.add_supply(kind,"locker"),"test materials fit")
func click(control:Control)->void:
	await process_frame
	if control.get_window()!=root:
		control.pressed.emit();await process_frame;return # Native dialog buttons use their built-in signal path in headless tests.
	for pressed in [true,false]:
		var e:=InputEventMouseButton.new();e.position=control.get_global_rect().get_center();e.global_position=e.position;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=pressed;control.get_viewport().push_input(e,true)
	await process_frame
func run()->void:
	root.size=Vector2i(1280,720)
	var state:=State.new()
	check(state.valid_home_layout(state.save_data()),"factory layout does not overlap despite authored window floor cells")
	check(state.Renovation.count_placed(state,"door")==1 and state.Renovation.count_placed(state,"window")==1,"initial carriage contains a door and window")
	var before:=state.save_data().duplicate(true)
	check(not state.decompose_furniture("door").is_empty() and state.save_data()==before,"last door cannot be decomposed")
	check(not state.temporarily_store_furniture("window").is_empty(),"last window cannot be removed to temporary storage")
	state.carriage_count=3;state.ensure_carriage_fixtures()
	check(state.Renovation.count_placed(state,"door")==3 and state.Renovation.count_placed(state,"window")==3,"each additional initial carriage has independent fixtures")
	var alias:=state.Renovation.next_id(state,"door")
	before=state.save_data().duplicate(true)
	check(not state.build_furniture(alias,{"car":1,"x":0,"y":0}).is_empty() and state.save_data()==before,"failed construction does not charge or grant furniture")
	give(state,Catalog.DEFINITIONS.door.build_cost)
	check(state.build_furniture(alias,{"car":1,"x":0,"y":0}).is_empty(),"additional door is constructed with materials")
	check(state.material_count("steel_plate")==0 and state.material_count("bolts")==0,"construction charges exact recipe once")
	give(state,Catalog.DEFINITIONS.door.dismantle_cost)
	check(state.decompose_furniture(alias).is_empty() and alias not in state.furniture_owned and alias not in state.temporary_furniture,"decomposition destroys ownership instead of filling a permanent warehouse")
	check(state.material_count("steel_plate")==1 and state.material_count("tools")==0,"decomposition charges and returns materials")
	var second_door: String=state.furniture_layout.keys().filter(func(id):return Catalog.base_kind(id)=="door" and state.furniture_layout[id]!=null and state.furniture_layout[id].car==1)[0]
	var old_door:Dictionary=state.furniture_layout[second_door].duplicate()
	check(state.temporarily_store_furniture(second_door).is_empty() and second_door in state.temporary_furniture,"temporary storage tracks the actual instance")
	check(state.furniture_completion_problem().contains("临时收纳"),"renovation completion requires an empty temporary warehouse")
	check(state.place_furniture(second_door,old_door).is_empty() and second_door not in state.temporary_furniture,"returning temporarily held furniture costs no new materials")
	check(not state.decompose_furniture("locker").is_empty(),"all storage furniture must be empty before decomposition")
	# Factory conflict recovery retains the old bed in temporary storage, not as a free new catalogue item.
	if "bed" in state.temporary_furniture:check(state.place_furniture("bed",{"car":1,"x":0,"y":10}).is_empty(),"pending bed can be grounded in a free added carriage")
	check(state.furniture_completion_problem().is_empty(),"complete layout passes support, collision, distance and fixture checks")
	var saved:=state.save_data().duplicate(true);var restored:=State.new()
	check(restored.load_data(saved,Rail.STATIONS.keys()) and restored.Renovation.count_placed(restored,"door")==3,"v19 restores independent fixtures")
	var remove_door: String=restored.furniture_layout.keys().filter(func(id):return Catalog.base_kind(id)=="door" and restored.furniture_layout[id]!=null and restored.furniture_layout[id].car==2)[0]
	give(restored,Catalog.DEFINITIONS.door.dismantle_cost);check(restored.decompose_furniture(remove_door).is_empty(),"a non-last door may be removed")
	saved=restored.save_data().duplicate(true);var reloaded:=State.new()
	check(reloaded.load_data(saved,Rail.STATIONS.keys()) and reloaded.Renovation.count_placed(reloaded,"door")==2,"loading does not respawn decomposed fixtures")
	var legacy:=State.new().save_data().duplicate(true);legacy.version=18;legacy.erase("furniture_content_signature");legacy.furniture_layout.bed=Catalog.default_placement("bed");legacy.furniture_layout.preparation={"car":0,"x":17,"y":8}
	check(reloaded.load_data(legacy,Rail.STATIONS.keys()) and reloaded.valid_home_layout(reloaded.save_data()),"legacy authored overlaps recover without losing furniture or blocking saves")
	# Technical and material conditions are evaluated independently and sorted automatically.
	var requirement:Dictionary=Catalog.DEFINITIONS.bed.required_technology.duplicate();Catalog.DEFINITIONS.bed.required_technology={"auto_repair":1}
	var conditions:Array=state.build_conditions("bed")
	check(not conditions[0].met and conditions.any(func(c):return c.met),"unmet technology does not dim independently met conditions")
	state.auto_repair_level=1;give(state,Catalog.DEFINITIONS.bed.build_cost)
	check(state.build_options().filter(func(option):return option.id=="bed")[0].ready,"technology and resources jointly unlock a furniture entry")
	var options:Array=state.build_options();var seen_locked:=false;var previous_id:=""
	for option in options:
		if not option.ready:seen_locked=true
		else:
			check(not seen_locked,"ready entries precede locked entries")
			check(previous_id.is_empty() or previous_id<option.id,"ready entries are sorted by ID");previous_id=option.id
	Catalog.DEFINITIONS.bed.required_technology=requirement
	# Overflow must restore every cargo grid, runtime ID and per-instance storage metadata.
	var overflow:=State.new();var bed_cost:Dictionary=Catalog.DEFINITIONS.bed.dismantle_cost.duplicate();var bed_salvage:Dictionary=Catalog.DEFINITIONS.bed.salvage.duplicate()
	Catalog.DEFINITIONS.bed.dismantle_cost={};Catalog.DEFINITIONS.bed.salvage={"tools":1000}
	var overflow_before:=overflow.save_data().duplicate(true)
	check(not overflow.decompose_furniture("bed").is_empty() and overflow.save_data()==overflow_before,"salvage overflow rolls back all inventory, furniture and runtime IDs")
	Catalog.DEFINITIONS.bed.dismantle_cost=bed_cost;Catalog.DEFINITIONS.bed.salvage=bed_salvage
	var cargo_snapshot:Dictionary=state.Renovation.cargo_backup(state)
	state.furniture_storage["locker#99"]=[];state.storage_sizes["locker#99"]={"width":3,"height":3}
	state.Renovation.restore_cargo(state,cargo_snapshot)
	check(not state.furniture_storage.has("locker#99") and not state.storage_sizes.has("locker#99"),"failed transaction removes newly allocated storage metadata")
	state.technologies.carpentry=2;var technology_restore:=State.new()
	check(technology_restore.load_data(state.save_data(),Rail.STATIONS.keys()) and technology_restore.technology_level("carpentry")==2,"custom technology levels survive save and reload")
	var home=load("res://scenes/game/home.tscn").instantiate();root.add_child(home);await process_frame;home.state=state;home.show_cabin();home.construction.enter();await process_frame
	var mode=home.construction
	var floor_data={"id":"floor_probe","name":"地面检测","texture":"res://assets/textures/Locker.png","width":2,"height":3,"floor_cells":[[0,0],[1,0]],"wall_cells":[],"texture_binding":{"x":0,"y":-2,"width":2,"height":3,"rotation":0}}
	Catalog.IDS.append("floor_probe");Catalog.DEFINITIONS.floor_probe=Definition.from_data(floor_data)
	mode.selected_id="floor_probe";mode.moving=true;mode.grab_cell=Vector2i.ZERO;mode.context_panel.hide()
	var local_ground:=Vector2(Catalog.floor_rect(2).position.x+2.3*Catalog.CELL_SIDE,Catalog.GROUND_EDGE_Y-Catalog.CELL_SIDE+.2)
	var ground_target:Dictionary=mode.target_at(mode.backdrop.carriage.get_global_transform()*local_ground)
	check(ground_target=={"car":2,"x":2,"y":11},"bottom edge snaps to the explicit ground despite subpixel offsets")
	check(Catalog.valid_placement("floor_probe",ground_target,3) and Catalog.support_problem("floor_probe",ground_target,state.furniture_layout).is_empty(),"empty trailing rows do not prevent occupied cells from touching the ground")
	mode.cancel_selection();Catalog.IDS.erase("floor_probe");Catalog.DEFINITIONS.erase("floor_probe")
	check(not mode.actions.has_node("Dismantle") and not mode.actions.has_node("Storage"),"furniture actions leave the global toolbar")
	mode.select_furniture("preparation");await process_frame
	check(mode.context_panel.visible and mode.context_actions.get_node("Storage").visible,"selected furniture exposes upper-right contextual storage")
	await click(mode.context_actions.get_node("Storage"))
	check(is_instance_valid(mode.storage_panel) and mode.storage_panel.grids.size()==1 and mode.storage_panel.grids[0].container=="preparation","storage opens a single furniture inventory")
	check(mode.storage_panel.z_index>mode.backdrop.carriage.get_node("HangingFixtures").z_index,"storage modal renders and receives input above the furniture world")
	var grid=mode.storage_panel.grids[0];var stored:Dictionary=state.preparation[0]
	var point:Vector2=grid.global_position+(Vector2(stored.x,stored.y)+Vector2(.5,.5))*grid.cell_size
	for pressed in [true,false]:
		var e:=InputEventMouseButton.new();e.position=point;e.global_position=point;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=pressed;grid.get_viewport().push_input(e)
	await process_frame
	check(mode.storage_panel.selection.get("id")==stored.id and mode.selected_id=="preparation","furniture inventory receives real mouse input instead of selecting world furniture behind it")
	await click(mode.storage_panel.find_child("TakeSelected",true,false))
	check(mode.storage_panel.selection.is_empty() and state.find_entry("bag",stored.id).size()>0,"single-furniture panel can empty selected contents into the backpack")
	mode.storage_panel.queue_free();await process_frame
	mode.select_furniture("bed");await process_frame;await click(mode.context_actions.get_node("Temporary"))
	check("bed" in state.temporary_furniture,"contextual temporary storage removes the selected placed instance")

	mode.open_warehouse();await process_frame
	check(mode.get_node("Warehouse").visible and mode.get_node("Warehouse").z_index>=100 and mode.inventory.item_count==state.temporary_furniture.size(),"temporary warehouse is visible above world layers and lists only temporarily held instances")
	await click(mode.place_button)
	check(mode.moving and mode.selected_id=="bed" and not mode.get_node("Warehouse").visible,"temporary warehouse place button receives real input above world layers")
	mode.place_at({"car":1,"x":0,"y":10})
	check("bed" not in state.temporary_furniture,"temporary placement clears the pending warehouse entry")
	give(state,Catalog.DEFINITIONS.screen.build_cost)
	var screen_tech:Dictionary=Catalog.DEFINITIONS.screen.required_technology.duplicate();Catalog.DEFINITIONS.screen.required_technology={"carpentry":1};state.technologies.carpentry=0
	mode.open_build_menu();await process_frame
	check(is_instance_valid(mode.build_panel) and mode.build_panel.rows.get_child_count()>0,"dedicated build panel shows known furniture")
	var frames:Array=[]
	for row in mode.build_panel.rows.get_children():
		var frame=row.find_child("ThumbnailFrame",true,false)
		if frame!=null:frames.append(frame.size)
	check(frames.all(func(v):return v==Vector2(96,72)),"all furniture thumbnail frames have the same size")
	var screen_row=mode.build_panel.rows.get_node("screen")
	check(not screen_row.get_meta("ready"),"build row is gray while a technology requirement is unmet")
	var met_conditions:=0
	for label in screen_row.find_child("Requirements",true,false).get_children():
		if label.has_meta("met") and label.get_meta("met"):
			met_conditions+=1;check(label.get_theme_color("font_color")==mode.build_panel.READY,"met conditions remain bright within a locked row")
	check(met_conditions>0,"locked row independently exposes already met material conditions")
	state.technologies.carpentry=1
	await create_timer(.3).timeout
	check(mode.build_panel.rows.get_node("screen").get_meta("ready"),"open build panel automatically refreshes when technology becomes sufficient")
	Catalog.DEFINITIONS.screen.required_technology=screen_tech
	mode.build_panel.queue_free();await process_frame
	# Modal confirmation really gates decomposition, including cancellation.
	mode.select_furniture("bed");give(state,Catalog.DEFINITIONS.bed.dismantle_cost);before=state.save_data().duplicate(true)
	await click(mode.context_actions.get_node("Dismantle"))
	check(is_instance_valid(mode.dismantle_dialog) and mode.dismantle_dialog.visible and state.save_data()==before,"decomposition asks confirmation before any mutation")
	await click(mode.dismantle_dialog.get_cancel_button());check(state.save_data()==before and not mode.dismantle_dialog.visible,"cancel closes confirmation and keeps furniture and materials unchanged")
	mode.dismantle();await process_frame;await click(mode.dismantle_dialog.get_ok_button())
	check(state.furniture_layout.bed==null and "bed" not in state.temporary_furniture,"confirmed UI action decomposes rather than permanently stores furniture: "+mode.get_node("Message").text)
	home.queue_free();await process_frame
	print("RENOVATION_WORKFLOW_OK: %d checks, %d failures" % [checks,failures]);quit(1 if failures else 0)
