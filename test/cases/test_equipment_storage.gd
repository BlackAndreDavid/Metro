extends SceneTree
const State=preload("res://scripts/cabin_state.gd")
const Catalog=preload("res://scripts/items/furniture_catalog.gd")
var checks:=0
var failures:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func _initialize()->void:call_deferred("run")
func button(at:Vector2,pressed:bool)->void:
	var event:=InputEventMouseButton.new();event.position=at;event.global_position=at;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;root.push_input(event,true)
func motion(at:Vector2,previous:Vector2)->void:
	var event:=InputEventMouseMotion.new();event.position=at;event.global_position=at;event.relative=at-previous;event.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(event,true)
func drag(start:Vector2,finish:Vector2)->void:
	button(start,true);motion(start+Vector2(12,0),start);await process_frame
	motion(finish,start+Vector2(12,0));await process_frame
	check(root.gui_is_dragging(),"native item drag starts")
	button(finish,false);await process_frame
func run()->void:
	root.size=Vector2i(1280,720)
	var state:=State.new()
	var legacy_warehouse: Dictionary=state.save_data().duplicate(true)
	legacy_warehouse.storage_sizes.erase("preparation")
	legacy_warehouse.preparation.append({"kind":"water","x":7,"y":4,"rotated":false})
	var restored_warehouse:=State.new()
	check(restored_warehouse.load_data(legacy_warehouse,state.Rail.STATIONS.keys()) and restored_warehouse.grid_size("preparation")==Vector2i(8,6),"old warehouse capacity without a snapshot survives authored default changes without losing cargo")
	state=State.new()
	check(restored_warehouse.load_data(state.save_data(),state.Rail.STATIONS.keys()) and restored_warehouse.grid_size("preparation")==state.Furniture.DEFINITIONS.preparation.storage,"new furniture storage capacities persist independently of later defaults")
	var restore_storage:=State.new()
	state=State.new()
	var Item=load("res://scripts/items/item_definition.gd")
	state.ITEM_DEFINITIONS.storage_probe=Item.from_data({"id":"storage_probe","name":"储物探针","width":2,"height":2,"tags":["storage"],"storage":{"width":7,"height":6}})
	state.ITEM_DEFINITIONS.unit_probe=Item.from_data({"id":"unit_probe","name":"单格探针","width":1,"height":1})
	check(state.add_supply("storage_probe","preparation") and state.bag_size()==Vector2i(5,4),"an unequipped storage-tagged item grants no carried capacity")
	var custom: Dictionary=state.preparation.filter(func(e):return e.kind=="storage_probe")[0]
	check(state.place({"source":"preparation","id":custom.id,"rotated":false},"backpack",Vector2i.ZERO) and state.bag_size()==Vector2i(7,6),"any tagged storage item equips using authored capacity without a hard-coded backpack ID")
	state.inventory.clear()
	for index in range(21):state.inventory.append(state.make_entry("unit_probe",Vector2i(index%7,index/7),false))
	check(restore_storage.load_data(state.save_data(),state.Rail.STATIONS.keys()) and restore_storage.bag_size()==Vector2i(7,6) and restore_storage.inventory.size()==21,"custom storage equipment and its cargo survive v20 save round-trip")
	var custom_before: Dictionary=state.save_data().duplicate(true)
	var small: Dictionary=state.preparation.filter(func(e):return e.kind=="small_backpack")[0]
	check(not state.place({"source":"preparation","id":small.id,"rotated":false},"backpack",Vector2i.ZERO) and state.save_data()==custom_before,"a smaller storage item cannot replace equipment when contents exceed capacity")
	check(state.sort_container("bag").is_empty() and state.inventory.size()==21,"tagged item storage uses shared lossless sorting")
	check(not state.place({"source":"backpack","id":custom.id,"rotated":false},"preparation",Vector2i(6,0)),"tagged storage equipment must be emptied before removal")
	var storage_furniture: Resource=state.Furniture.DEFINITIONS.preparation
	check(storage_furniture.storage_component.get_script()==state.ITEM_DEFINITIONS.storage_probe.storage_component.get_script() and storage_furniture.storage_component.size==storage_furniture.storage,"furniture and item storage use the same component class")
	state=State.new()
	var definition=load("res://scripts/items/item_definition.gd").from_data({"id":"mask_probe","name":"空白占位测试","width":8,"height":8,"cells":[[0,0]]})
	state.ITEM_DEFINITIONS.mask_probe=definition
	var empty: Array[Dictionary]=[]
	check(state.fits_item(empty,Vector2i(2,2),"mask_probe",Vector2i(1,1)),"unused item canvas space does not reject an empty boundary cell")
	definition.occupancy.assign([Vector2i(7,7)])
	check(state.fits_item(empty,Vector2i(2,2),"mask_probe",Vector2i(-7,-7)),"leading blank padding can be placed by its actual cell")
	var packing:Dictionary=state.Equipment.pack(state,[{"id":999,"kind":"mask_probe","x":0,"y":0,"rotated":false}],Vector2i(2,2))
	check(not packing.is_empty() and state.item_within_bounds(packing.entries[0],Vector2i(2,2)),"auto-packing uses actual occupied cells including leading padding")
	check(not state.read_cargo([{"kind":"mask_probe","x":-7,"y":-7,"rotated":false}],Vector2i(2,2)).is_empty(),"actual-mask positions persist through cargo validation")
	state=State.new();state.inventory.clear();state.inventory.append(state.make_entry("water",Vector2i(99,99),false))
	check(state.depart({"heavy":false,"inventory_tools":true},0).is_empty() and state.item_within_bounds(state.inventory[0],state.bag_size()),"departure repacks a misplaced item when real capacity suffices")
	state.end_trip();var large:Dictionary=state.preparation.filter(func(e):return e.kind=="large_backpack")[0]
	check(state.place({"source":"preparation","id":large.id,"rotated":false},"backpack",Vector2i.ZERO) and state.bag_size()==Vector2i(6,5),"large backpack capacity follows the equipped item")
	var swap_case:=State.new();var swap_large:Dictionary=swap_case.preparation.filter(func(e):return e.kind=="large_backpack")[0]
	check(swap_case.equip_active(swap_large.id,"preparation").is_empty() and swap_case.bag_size()==Vector2i(5,4),"a backpack in the active position does not activate its storage")
	check(swap_case.place({"source":"backpack","id":swap_case.backpack_item.id,"rotated":false},"active",Vector2i.ZERO) and swap_case.bag_size()==Vector2i(6,5) and swap_case.active_item.kind=="small_backpack","swapping backpack and active positions uses the backpack actually returned to the equipment position")
	var before:Dictionary=state.save_data().duplicate(true)
	check(not state.place({"source":"backpack","id":state.backpack_item.id,"rotated":false},"preparation",Vector2i(6,4)) and state.save_data()==before,"a nonempty backpack cannot be removed")
	state.inventory.clear()
	var free:Dictionary=state.first_free_placement("large_backpack","preparation")
	check(state.place({"source":"backpack","id":state.backpack_item.id,"rotated":false},"preparation",free.cell) and state.bag_size()==Vector2i.ZERO,"no equipped backpack means no backpack storage")
	var lamp:Dictionary=state.preparation.filter(func(e):return e.kind=="flashlight")[0]
	check(not state.can_place({"source":"preparation","id":lamp.id,"rotated":false},"bag",Vector2i.ZERO),"a hidden absent backpack cannot receive items")
	check(state.place({"source":"preparation","id":lamp.id,"rotated":false},"pocket",Vector2i.ZERO) and state.carried_tools().light,"pocket is real carried 2x2 storage")
	check(state.equip_active(lamp.id,"pocket").is_empty() and state.pocket.is_empty() and state.active_item.id==lamp.id,"the active position equips one item from the pocket")
	state.add_supply("water","preparation");var water:Dictionary=state.preparation.filter(func(e):return e.kind=="water")[0]
	check(state.equip_active(water.id,"preparation").is_empty() and state.active_item.id==water.id and state.find_entry("preparation",lamp.id).size()>0,"equipping another active item swaps the previous item back")
	state.add_supply("meds","preparation");var meds:Dictionary=state.preparation.filter(func(e):return e.kind=="meds")[0];before=state.save_data().duplicate(true)
	check(not state.equip_active(meds.id,"preparation").is_empty() and state.save_data()==before,"an oversized item cannot bypass the 2x2 active position")
	var restored:=State.new()
	check(restored.load_data(state.save_data(),state.Rail.STATIONS.keys()) and restored.backpack_item.is_empty() and restored.active_item.kind=="water","v20 retains equipment and absent backpack state")
	var legacy:=State.new().save_data().duplicate(true);legacy.version=19;legacy.erase("backpack_item");legacy.erase("pocket")
	check(restored.load_data(legacy,state.Rail.STATIONS.keys()) and restored.backpack_item.kind=="small_backpack" and restored.bag_size()==Vector2i(5,4),"legacy saves migrate to an actual small backpack")
	var legacy_wide:Dictionary=legacy.duplicate(true);legacy_wide.wide=true
	legacy_wide.preparation=legacy_wide.preparation.filter(func(e):return e.kind!="large_backpack")
	legacy_wide.active_item={"kind":"large_backpack","x":0,"y":0,"rotated":false}
	check(restored.load_data(legacy_wide,state.Rail.STATIONS.keys()) and restored.backpack_item.kind=="large_backpack" and restored.active_item.is_empty() and restored.material_count("large_backpack")==0,"legacy active backpack becomes the equipped backpack without duplication")
	var screen:Resource=Catalog.DEFINITIONS.screen;var old_anchor:Vector2=screen.hanging_anchor;screen.hanging_anchor=Vector2(.1,.8)
	var at:Dictionary={"car":0,"mount":1,"x":0,"y":0};var bounds:Rect2=Catalog.visual_rect("screen",Catalog.placement_rect("screen",at))
	var delta:Vector2=((screen.hanging_anchor-Vector2(.5,.5))*bounds.size).rotated(deg_to_rad(float(screen.texture_binding.get("rotation",0))))
	check((bounds.get_center()+delta).is_equal_approx(Catalog.mount_position(0,1)),"the edited single anchor lands on the carriage mounting point")
	screen.hanging_anchor=old_anchor
	var home=load("res://scenes/game/home.tscn").instantiate();root.add_child(home);await process_frame;home.show_cabin();home.use_hotspot("gear");await process_frame
	check(home.view.bag_open and home.grids.any(func(g):return g.container=="bag"),"equipped backpack automatically opens its storage page")
	check(home.view.bag_panel.has_node("SortBackpack") and home.view.bag_panel.has_node("TransferSelected"),"backpack sorting and transfer actions belong to its collapsible storage page")
	var uniform: int=home.view.CELL_PIXELS
	check(home.grids.all(func(g):return g.cell_size==uniform),"warehouse, equipment and backpack storage use the same displayed cell size")
	var equipment: Control=home.view.equipment
	check(is_equal_approx(equipment.backpack.global_position.x,equipment.pocket.global_position.x) and is_equal_approx(equipment.pocket.global_position.x,equipment.active.global_position.x) and equipment.backpack.global_position.y<equipment.pocket.global_position.y and equipment.pocket.global_position.y<equipment.active.global_position.y,"backpack, pocket and active positions form a vertical column")
	var center_grid: Control=home.grids.filter(func(g):return g.container=="bag")[0]
	var warehouse_grid: Control=home.grids.filter(func(g):return g.container=="preparation")[0]
	check(warehouse_grid.get_global_rect().end.x<center_grid.global_position.x and center_grid.get_global_rect().end.x<equipment.global_position.x,"backpack storage is between the warehouse and right equipment column")
	home.view.set_bag_open(false);await process_frame
	var slot:Control=home.view.equipment.backpack;button(slot.get_global_rect().get_center(),true);button(slot.get_global_rect().get_center(),false);await process_frame
	check(home.view.bag_open and home.grids.any(func(g):return g.container=="bag"),"clicking the equipped backpack opens its storage page")
	var bag:Control=home.grids.filter(func(g):return g.container=="bag")[0];var prep:Control=home.grids.filter(func(g):return g.container=="preparation")[0]
	home.state.inventory.clear();home.state.inventory.append(home.state.make_entry("water",Vector2i(2,1),false));var id:int=home.state.inventory[0].id;home.view.refresh_inventory()
	free=home.state.first_free_placement("water","preparation")
	await drag(bag.global_position+Vector2(2.5,2.5)*bag.cell_size,prep.global_position+(Vector2(free.cell)+Vector2(.5,1.5))*prep.cell_size)
	check(home.state.find_entry("preparation",id).get("x")==free.cell.x and home.state.find_entry("preparation",id).get("y")==free.cell.y,"grabbing a lower cell preserves the placement anchor across different grid scales")
	home.view.set_bag_open(false)
	var ui_large: Dictionary=home.state.preparation.filter(func(e):return e.kind=="large_backpack")[0]
	await drag(prep.global_position+(Vector2(ui_large.x,ui_large.y)+Vector2(.5,.5))*prep.cell_size,home.view.equipment.backpack.get_global_rect().get_center())
	check(home.view.bag_open and home.grids.any(func(g):return g.container=="bag" and g.size==Vector2(6,5)*uniform),"equipping a large backpack automatically reopens and resizes its storage")
	if DisplayServer.get_name()!="headless" and not OS.get_environment("METRO_TEST_RESULTS").is_empty():
		await process_frame;await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(OS.get_environment("METRO_TEST_RESULTS"))
		root.get_texture().get_image().save_png(OS.get_environment("METRO_TEST_RESULTS").path_join("equipment-four-positions.png"))
	free=home.state.first_free_placement(home.state.backpack_item.kind,"preparation")
	check(home.state.place({"source":"backpack","id":home.state.backpack_item.id,"rotated":false},"preparation",free.cell),"empty equipped backpack can be returned to warehouse")
	home.view.refresh_inventory();home.view.set_bag_open(true);await process_frame
	check(not home.view.bag_open and not home.grids.any(func(g):return g.container=="bag"),"no backpack exposes no storage page beyond equipment positions")
	home.state.ITEM_DEFINITIONS.storage_ui=Item.from_data({"id":"storage_ui","name":"大容量储物探针","width":1,"height":1,"tags":["storage"],"storage":{"width":16,"height":16},"texture":"res://assets/textures/temp/items/locked_case.png"})
	check(home.state.add_supply("storage_ui","preparation"),"large-capacity tagged storage can be supplied")
	var storage_ui: Dictionary=home.state.preparation.filter(func(e):return e.kind=="storage_ui")[0]
	home.select_cargo("preparation",storage_ui.id);home.move_cargo("backpack",Vector2i.ZERO);await process_frame
	var large_grid: Control=home.grids.filter(func(g):return g.container=="bag")[0]
	check(home.view.bag_open and large_grid.size==Vector2(16,16)*uniform and large_grid.get_parent() is ScrollContainer and large_grid.get_parent().size.y<large_grid.size.y,"custom 16x16 storage scrolls within the central page instead of covering its actions")
	home.show_cabin();var furniture:Control=home.home_backdrop.carriage.get_node("FurnitureSlots/Door");furniture.set_highlighted(true)
	check(not furniture.caption.z_as_relative and furniture.caption.z_index>home.home_backdrop.carriage.get_node("Rails").z_index,"furniture action captions draw above the rails")
	if DisplayServer.get_name()!="headless" and not OS.get_environment("METRO_TEST_RESULTS").is_empty():
		var blocker:=ColorRect.new();blocker.color=Color.RED;blocker.mouse_filter=Control.MOUSE_FILTER_IGNORE;blocker.z_index=999;home.add_child(blocker);blocker.global_position=furniture.caption.get_global_rect().position;blocker.size=furniture.caption.get_global_rect().size
		await process_frame;await RenderingServer.frame_post_draw
		var region:=root.get_texture().get_image().get_region(Rect2i(blocker.get_global_rect()))
		var glyphs:=0
		for y in range(region.get_height()):
			for x in range(region.get_width()):
				var color:=region.get_pixel(x,y)
				if color.r>.8 and color.g>.8 and color.b>.75:glyphs+=1
		check(glyphs>20,"tooltip glyphs render above an opaque higher world layer")
		blocker.queue_free();await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("METRO_TEST_RESULTS").path_join("furniture-tooltip-top-layer.png"))
	home.queue_free();await process_frame
	print("EQUIPMENT_STORAGE_OK: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
