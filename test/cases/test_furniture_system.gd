extends SceneTree
const State=preload("res://scripts/cabin_state.gd")
const Catalog=preload("res://scripts/items/furniture_catalog.gd")
const Definition=preload("res://scripts/items/furniture_definition.gd")
const Rail=preload("res://scripts/cabin_map.gd")
var failures:=0
var checks:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	var state:=State.new()
	check(state.furniture_completion_problem().is_empty(),"new base furniture is placed, or its item is safely stored")
	check(Catalog.IDS.has("preparation") and Catalog.IDS.has("window"),"preparation and window belong to shared furniture registry")
	check(Catalog.DEFINITIONS.preparation.distance_rules[0].distance==3,"preparation uses common three-cell door requirement")
	check(state.place_furniture("preparation",{"car":0,"x":18,"y":8}).is_empty(),"preparation is movable within door range")
	check(state.place_furniture("window",{"car":0,"x":20,"y":1}).is_empty(),"wall furniture may overlap floor furniture")
	check(not state.place_furniture("computer",{"car":0,"x":23,"y":5}).is_empty() and state.material_count("computer")==1,"unsupported furniture rejects atomically")
	check(state.place_furniture("computer",{"car":0,"x":18,"y":6}).is_empty(),"computer can sit on a flat storage top")
	check(not state.store_furniture("preparation").is_empty(),"cannot dismantle a support under existing furniture")
	check(not state.place_furniture("preparation",{"car":0,"x":4,"y":8}).is_empty(),"moving support cannot leave furniture floating")
	check(state.store_furniture("computer").is_empty() and state.material_count("computer")==1,"dual furniture returns to item storage, retaining separate item texture")
	check(state.place_furniture("preparation",{"car":0,"x":4,"y":8}).is_empty(),"supported storage can move to other side of door")
	var layout:=state.furniture_layout.duplicate(true);layout.preparation={"car":0,"x":29,"y":8}
	check(not Catalog.distance_problem(layout).is_empty(),"far preparation fails generic requirement")
	var rule:Dictionary=Catalog.DEFINITIONS.preparation.distance_rules[0]
	var previous:=rule.duplicate(true);rule.target_type="effect";rule.target="exit";Catalog.DEFINITIONS.door.effects=["exit"]
	check(Catalog.distance_problem(state.furniture_layout).is_empty(),"effect-tag requirements resolve through same distance engine")
	rule.relation="exclude";check(not Catalog.distance_problem(state.furniture_layout).is_empty(),"same engine supports effect exclusion")
	rule.assign(previous);Catalog.DEFINITIONS.door.effects=[]
	check(state.resize_furniture_storage("preparation",Vector2i(10,7)).is_empty(),"renovation resizes storage")
	state.preparation.append(state.make_entry("bolts",Vector2i(9,6),false))
	check(not state.resize_furniture_storage("preparation",Vector2i(8,6)).is_empty() and state.grid_size("preparation")==Vector2i(10,7),"shrinking storage cannot truncate occupied items")
	var saved:=state.save_data().duplicate(true);var loaded:=State.new()
	check(loaded.load_data(saved,Rail.STATIONS.keys()) and loaded.grid_size("preparation")==Vector2i(10,7) and loaded.furniture_layout.preparation.x==4,"v18 persists furniture placement and storage dimensions")
	var old:=State.new().save_data().duplicate(true);old.version=17
	for key in ["window","preparation"]:old.furniture_layout.erase(key)
	old.erase("furniture_storage");old.erase("storage_sizes");old.erase("furniture_owned")
	check(loaded.load_data(old,Rail.STATIONS.keys()) and loaded.furniture_layout.preparation!=null and loaded.furniture_layout.window!=null,"v17 migration adds missing furniture without losing old cargo")
	var custom=Definition.from_data({"id":"custom_storage","name":"储物物品家具","texture":"res://assets/textures/Locker.png","width":2,"height":2,"floor_cells":[],"wall_cells":[[0,0]],"item_id":"tools","storage":{"width":4,"height":4}})
	Catalog.IDS.append(custom.id);Catalog.DEFINITIONS[custom.id]=custom
	var custom_state:=State.new();custom_state.add_supply("tools","locker")
	check(custom_state.place_furniture(custom.id,{"car":0,"x":4,"y":5}).is_empty(),"custom item furniture consumes its linked item and can attach to a wall")
	var computer:Dictionary=custom_state.locker.filter(func(e):return e.kind=="computer")[0]
	check(custom_state.auto_place({"source":"locker","id":computer.id,"rotated":true},custom_state.storage_container(custom.id)).is_empty(),"all storage furniture accept dual item furniture")
	var custom_save:=custom_state.save_data().duplicate(true);var custom_loaded:=State.new()
	check(custom_loaded.load_data(custom_save,Rail.STATIONS.keys()) and custom_loaded.entries("furniture:custom_storage").size()==1,"custom storage cargo survives save/load")
	check(not custom_state.store_furniture(custom.id).is_empty(),"non-empty storage furniture cannot hide cargo by becoming an item")
	check(custom_state.resize_furniture_storage(custom.id,Vector2i(6,5)).is_empty(),"custom storage dimensions use the common renovation interface")
	var selection:Dictionary={"source":"furniture:custom_storage","id":computer.id,"rotated":false}
	check(custom_state.auto_place(selection,"bag").is_empty() and custom_state.store_furniture(custom.id).is_empty(),"empty dual storage furniture returns to an inventory upright")
	Catalog.IDS.erase(custom.id);Catalog.DEFINITIONS.erase(custom.id)
	check(state.store_furniture("bed").is_empty() and not state.furniture_completion_problem().is_empty(),"non-item furniture must be placed before finishing renovation")
	check(state.save_current(OS.get_environment("METRO_TEST_RESULTS").path_join("unfinished-furniture.json"))==ERR_INVALID_DATA,"unfinished furniture cannot be saved")
	var animated=Definition.from_data({"id":"animation_test","name":"动画","texture":"res://assets/textures/temp/items/water_bottle.png","width":1,"height":1,"floor_cells":[[0,0]],"animation":{"frames":2,"columns":2,"fps":2,"durations":[100,300]}})
	check(animated.frame_index(.05)==0 and animated.frame_index(.2)==1 and animated.frame_index(.45)==0,"animation supports variable frame durations and looping")
	check(animated.frame_at(.05).get_width()*2==load(animated.texture_path).get_width(),"animation displays a frame instead of the full sheet")
	Catalog.DEFINITIONS[animated.id]=animated
	var native_rect:=Catalog.visual_rect(animated.id,Rect2(Vector2.ZERO,Catalog.CELL_SIZE))
	var expanded_rect:=Catalog.visual_rect(animated.id,Rect2(Vector2.ZERO,Catalog.CELL_SIZE*Vector2(8,6)))
	check(native_rect==expanded_rect,"unbound furniture art retains native scale when its grid changes")
	animated.texture_binding={"x":1.0,"y":0.5,"width":3.0,"height":2.0,"rotation":90.0}
	var bound_rect:=Catalog.visual_rect(animated.id,Rect2(Vector2.ZERO,Catalog.CELL_SIZE))
	check(bound_rect.position.is_equal_approx(Catalog.CELL_SIZE*Vector2(1,.5)) and bound_rect.size.is_equal_approx(Catalog.CELL_SIZE*Vector2(3,2)),"runtime furniture uses the editor-authored texture binding")
	Catalog.DEFINITIONS.erase(animated.id)
	var home=load("res://scenes/game/home.tscn").instantiate();root.add_child(home);await process_frame;home.show_cabin()
	var rotated=load("res://scenes/items/furniture.tscn").instantiate();root.add_child(rotated);rotated.size=Vector2(96,64);rotated.configure(animated,home,home.home_backdrop)
	check(is_equal_approx(rotated.rotation_degrees,90) and is_equal_approx(rotated.caption.rotation_degrees,-90),"authored rotation is rendered while the function label stays upright")
	rotated.queue_free()
	var art=home.home_backdrop.carriage
	check(art.has_node("FurnitureSlots/Preparation") and art.has_node("WallFixtures/Window"),"movable preparation and window use MetroFurniture instances")
	check(art.get_node("Rails").z_index>art.get_node("FurnitureSlots").z_index and art.get_node("HangingFixtures").z_index>art.get_node("Rails").z_index,"rail and hanging fixtures render above furniture")
	home.construction.enter();await process_frame
	var mode=home.construction
	var original_binding: Dictionary=Catalog.DEFINITIONS.preparation.texture_binding.duplicate()
	Catalog.DEFINITIONS.preparation.texture_binding=original_binding.duplicate();Catalog.DEFINITIONS.preparation.texture_binding.x=20;Catalog.DEFINITIONS.preparation.texture_binding.y=-4;Catalog.DEFINITIONS.preparation.texture_binding.rotation=90
	mode.state.carriage_count=2;mode._refresh("")
	var sprite_center:=Catalog.visual_rect("preparation",Catalog.placement_rect("preparation",mode.state.furniture_layout.preparation)).get_center()
	var cursor: Vector2=mode.backdrop.carriage.get_global_transform()*sprite_center
	mode.press_furniture("preparation",cursor);mode._process(1.0)
	check(mode.target_at(cursor)==mode.state.furniture_layout.preparation,"dragging displaced artwork preserves its occupied anchor across carriage boundaries")
	Catalog.DEFINITIONS.preparation.texture_binding=original_binding;mode.state.carriage_count=1;mode.cancel_selection()
	mode.select_furniture("preparation");mode.edit_storage();await process_frame
	check(is_instance_valid(mode.storage_panel) and mode.storage_panel.grids.size()==2,"renovation storage inspector reuses draggable cargo grids")
	mode.storage_panel.queue_free();await process_frame
	mode.state.store_furniture("bed");mode.exit()
	check(mode.active and mode.get_node("Message").text.contains("未放置"),"exit checks and explains unplaced furniture")
	mode.state.place_furniture("bed",Catalog.default_placement("bed"));mode.exit();check(not mode.active,"valid complete renovation can finish")
	home.queue_free();await process_frame
	print("FURNITURE_SYSTEM_OK: %d checks, %d failures" % [checks,failures]);quit(1 if failures else 0)
