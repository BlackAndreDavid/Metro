extends SceneTree
const Catalog=preload("res://scripts/items/furniture_catalog.gd")
var checks:=0
var failures:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func _initialize()->void:
	load(get_script().resource_path.get_base_dir()+"/support/furniture_fixtures.gd").canonical_profile()
	call_deferred("run")
func button(at:Vector2,pressed:bool)->void:
	var event:=InputEventMouseButton.new();event.position=at;event.global_position=at;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
func motion(at:Vector2,previous:Vector2)->void:
	var event:=InputEventMouseMotion.new();event.position=at;event.global_position=at;event.relative=at-previous;event.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(event,true)
func run()->void:
	root.size=Vector2i(1280,720)
	var home=load("res://scenes/game/home.tscn").instantiate();root.add_child(home);await process_frame
	var state=home.state
	state.carriage_count=2;state.ensure_carriage_fixtures();home.focused_carriage=1
	check(state.place_furniture("computer",{"car":1,"x":17,"y":10}).is_empty(),"computer placed upright on ground")
	home.show_cabin();home.construction.enter();await process_frame
	var mode=home.construction;mode.select_furniture("locker");mode.edit_storage();await process_frame
	var dock=mode.storage_panel;var grid=dock.grids[0]
	check(dock.panel.position.x==0 and dock.panel.size.x<=340 and dock.mouse_filter==Control.MOUSE_FILTER_IGNORE,"storage docks left and leaves the world interactive")
	var item:Control=mode.registered.computer.get_ref()
	var start:Vector2=item.get_global_rect().get_center()
	button(start,true);mode._process(.49)
	check(not mode.moving,"drag cannot start before half a second")
	mode._process(.02);await process_frame
	check(mode.dragging_furniture and mode.moving,"world input works with storage open and unlocks after half a second")
	var destination:Vector2=grid.global_position+Vector2.ONE*grid.cell_size*.5
	motion(destination,start);button(destination,false);await process_frame
	check(state.furniture_layout.computer==null and state.locker.any(func(e):return e.kind=="computer" and e.x==0 and e.y==0),"real world drag packs furniture into the exact storage cell")
	check(not state.temporary_furniture.has("computer"),"packed item is not left in temporary storage")
	var entry:Dictionary=state.locker.filter(func(e):return e.kind=="computer")[0]
	var count_before: int=state.material_count("computer")
	button(destination,true);motion(destination+Vector2(18,0),destination);await process_frame
	var target:Vector2=mode.backdrop.carriage.get_global_transform()*(Catalog.floor_rect(1).position+Vector2(17.5,10.5)*Catalog.CELL_SIDE)
	motion(target,destination+Vector2(18,0));await process_frame
	check(root.gui_is_dragging(),"cargo starts native drag from left storage")
	button(target,false);await process_frame
	check(state.furniture_layout.computer=={"car":1,"x":17,"y":10} and state.material_count("computer")==count_before-1,"native storage drag places upright furniture in the world")
	check(not state.entries("locker").any(func(e):return e.id==entry.id),"exact dragged inventory entry is consumed")
	var before:Dictionary=state.save_data().duplicate(true)
	check(not state.Renovation.pack_item_at(state,"computer","locker",Vector2i(7,4)).is_empty() and state.save_data()==before,"out of bounds packing leaves all state unchanged")
	check(Catalog.support_problem("computer",{"car":1,"x":17,"y":9},state.furniture_layout).length()>0,"physical-only furniture cannot float")
	var definition=load("res://scripts/items/furniture_definition.gd").from_data({"id":"test","name":"test","texture":"res://assets/textures/Locker.png","width":2,"height":2,"floor_cells":[[0,0]],"wall_cells":[[0,0],[1,0]]})
	check(definition.floor_cells==[Vector2i(0,0)] and definition.wall_cells==[Vector2i(1,0)],"legacy same-furniture duplicate cells resolve to physical occupancy")
	var mixed=load("res://scripts/items/furniture_definition.gd").from_data({"id":"depth_probe","name":"两层探针","texture":"res://assets/textures/Locker.png","width":2,"height":1,"floor_cells":[[1,0]],"wall_cells":[[0,0]],"texture_binding":{"x":0,"y":0,"width":2,"height":1,"rotation":0}})
	var mask: Image=mixed.physical_plane_mask(Vector2i(16,16)).get_image()
	check(mask.get_pixel(5,10).r<.5 and mask.get_pixel(14,10).r>.5,"shared-grid cell attributes map texture pixels to the correct depth")
	Catalog.IDS.append("depth_probe");Catalog.DEFINITIONS.depth_probe=mixed;state.furniture_layout.depth_probe={"car":1,"x":4,"y":3}
	mode._refresh("");await process_frame
	var physical: Control=mode.backdrop.get_node("Carriage/FurnitureSlots/Depth Probe")
	var wall: Control=mode.backdrop.get_node("Carriage/WallFixtures/Depth Probe")
	check(physical.render_plane==1 and wall.render_plane==2 and physical.get_parent().z_index>wall.get_parent().z_index,"mixed furniture draws physical and wall parts at separate depths")
	check(physical.position==wall.position and physical.size==wall.size and physical.rotation==wall.rotation,"depth splitting preserves the single texture binding")
	check(not Catalog.overlaps("depth_probe",{"car":1,"x":4,"y":3},"computer",{"car":1,"x":2,"y":2}),"different furniture can place physical cells in front of a wall cell")
	physical.set_highlighted(true)
	check(wall.visual.material.get_shader_parameter("highlighted") and physical.caption.visible and not wall.caption.visible,"both depth pieces highlight together without duplicate labels")
	physical.set_highlighted(false)
	check(not wall.visual.material.get_shader_parameter("highlighted") and not physical.visual.material.get_shader_parameter("highlighted"),"shared hover clears without leaving either depth highlighted")
	var screen: Resource=Catalog.DEFINITIONS.screen
	var original_size: Vector2i=screen.grid_size
	screen.grid_size=Vector2i(20,9)
	var hanging_at: Dictionary={"car":1,"mount":3,"x":0,"y":0}
	check(Catalog.valid_placement("screen",hanging_at,2),"hanging reference size has no mount-capacity limit")
	var visual_bounds: Rect2=Catalog.visual_rect("screen",Catalog.placement_rect("screen",hanging_at))
	check(visual_bounds.get_center().is_equal_approx(Catalog.mount_position(1,3)),"hanging artwork center aligns exactly to its attachment point")
	var original_reference: Array=screen.reference_cells.duplicate();screen.reference_cells.assign([Vector2i(19,8)])
	check(Catalog.visual_rect("screen",Catalog.placement_rect("screen",hanging_at))==visual_bounds,"editing reference cells does not alter runtime size or placement")
	check(Catalog.overlaps("screen",hanging_at,"screen",hanging_at) and not Catalog.overlaps("screen",hanging_at,"screen",{"car":1,"mount":2,"x":0,"y":0}),"one attachment point takes one object independent of reference size")
	screen.grid_size=original_size;screen.reference_cells.assign(original_reference)
	if DisplayServer.get_name()!="headless" and not OS.get_environment("METRO_TEST_RESULTS").is_empty():
		await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(OS.get_environment("METRO_TEST_RESULTS"))
		root.get_texture().get_image().save_png(OS.get_environment("METRO_TEST_RESULTS").path_join("renovation-dock.png"))
	mode.open_build_menu();await process_frame
	check(not is_instance_valid(mode.storage_panel) and is_instance_valid(mode.build_panel),"opening a modal palette closes the dock instead of covering its controls")
	home.queue_free();await process_frame
	print("RENOVATION_DOCK_OK: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
