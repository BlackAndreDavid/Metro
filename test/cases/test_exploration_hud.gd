extends SceneTree
const State = preload("res://scripts/cabin_state.gd")
const Content = preload("res://scripts/content/content_registry.gd")
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1;push_error(message)
func _initialize() -> void:call_deferred("run")
func key(code: Key) -> void:
	var e := InputEventKey.new();e.keycode=code;e.physical_keycode=code;e.pressed=true;Input.parse_input_event(e)
	e = InputEventKey.new();e.keycode=code;e.physical_keycode=code;e.pressed=false;Input.parse_input_event(e)
func run() -> void:
	root.size=Vector2i(1280,720)
	var home=load("res://scenes/game/home.tscn").instantiate();root.add_child(home)
	home.show_cabin();home.state.installed_charge=100
	home.loadout={"light":true,"heavy":false,"wide":false,"crowbar":false,"wrench":false};home.confirm_departure()
	await process_frame
	var street=home.surface_block;street.set_process(false)
	check(street.size==Vector2(1280,720) and not home.view.get_node("PackAnchor").visible,"full screen world, backpack collapsed")
	check(not home.view.has_node("Location") and not home.view.has_node("Departure") and home.view.get_node("Stamina").position.y>650,"removed station/electric info; stamina bottom left")
	check(home.view.get_node("Timer").z_index>home.view.get_node("StreetFrame").z_index and not home.time_label.text.is_empty(),"countdown remains above the full-screen world")
	check(home.view.get_node("LoadoutBar").position.x<50 and home.view.get_node("LoadoutBar").position.y<120,"equipment and active slots share the top-left bar")
	check(is_equal_approx(battery_center(home.view.get_node("BackpackButton")).y,360) and is_equal_approx(home.view.get_node("BackpackButton").get_global_rect().end.x,1280),"backpack button touches the right edge at vertical center")
	home.view.update_countdown(500,1000);check(home.view.time_tint==Color("f0c96a"),"countdown turns yellow at 50 percent")
	home.view.update_countdown(150,1000);check(home.view.time_tint==Color("ed7169"),"countdown turns red at 15 percent")
	home.view.update_countdown(900,1000);check(home.view.time_tint==Color("82d9ad"),"countdown remains green above half")
	check(street.shade.get_index()>street.hero_view.get_index(),"one lighting overlay covers actors, interactables and their outline")
	key(KEY_B);await process_frame
	check(home.view.pack_open and street.inspecting_pack and street.size==Vector2(1280,720),"B opens overlay without resizing world")
	var b=home.view.get_node("BackpackButton");var at:Vector2=b.get_global_rect().get_center()
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.position=at;event.global_position=at;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;Input.parse_input_event(event)
	await process_frame
	check(not home.view.pack_open and not street.inspecting_pack,"backpack mouse button closes overlay")
	home.state.inventory.clear();home.state.add_supply("meds","bag");home.state.health=50
	var id:int=home.state.inventory[0].id
	check(home.state.equip_active(id).is_empty() and home.state.inventory.is_empty(),"active item occupies no backpack grid")
	key(KEY_SPACE);await process_frame
	check(home.state.health==mini(100,50+int(home.state.ItemCatalog.definition("meds").get("active_use",{}).get("amount",25))) and home.state.active_item.is_empty(),"Space consumes equipped medical item")
	home.state.add_supply("tools","bag");home.state.equip_active(home.state.inventory[0].id)
	var count:int=home.state.inventory.size();var active_id:int=home.state.active_item.id
	check(not home.state.use_active().is_empty() and home.state.active_item.id==active_id,"nonusable item does not disappear")
	check(home.state.place({"source":"active","id":active_id,"rotated":true},"bag",Vector2i.ZERO) and home.state.active_item.is_empty() and home.state.inventory.size()==count+1,"active can rotate back into backpack without duplication")
	home.state.equip_active(home.state.inventory[0].id)
	var path:String=OS.get_environment("METRO_TEST_RESULTS").path_join("active-save.json")
	home.state.end_trip();home.state.save_current(path)
	var restored=State.new()
	check(restored.load_cabin(path,home.Rail.STATIONS.keys()) and restored.active_item.kind=="tools","v16 save restores independent active container")
	var old:Dictionary=home.state.save_data();old.version=15;old.erase("active_item");var f=FileAccess.open(path,FileAccess.WRITE);f.store_string(JSON.stringify(old));f.close()
	check(restored.load_cabin(path,home.Rail.STATIONS.keys()) and restored.active_item.is_empty(),"v15 saves migrate with an empty active slot")
	var packed=State.new();packed.inventory.clear();packed.add_supply("tools","bag");packed.equip_active(packed.inventory[0].id)
	for y in range(4):
		for x in range(5):packed.inventory.append(packed.make_entry("bolts",Vector2i(x,y),false))
	var before:Dictionary=packed.save_data().duplicate(true)
	check(not packed.equip_active(packed.inventory[0].id).is_empty() and packed.save_data()==before,"full bag rejects swap atomically")
	check(not packed.unequip_active().is_empty() and packed.save_data()==before,"full bag rejects unequip without item loss")
	# Resume an isolated exploration for pickup and light rules.
	home.confirm_departure();await process_frame;street=home.surface_block;street.set_process(false)
	var slot:int=-1
	for i in range(street.LOOT.size()):
		if not street.LOOT[i].has("cabinet") and not home.state.ground_kind(i).is_empty():slot=i;break
	check(slot>=0,"outdoor loose spawn expands and rolls loot")
	if slot>=0:
		var point:Dictionary=street.LOOT[slot];street.row=point.row;street.player_x=point.x;street.building="";street.floor_index=0
		home.state.flashlight_on=true;street.position_changed();street.update_interaction_visuals()
		check(not home.state.flashlight_on and street.can_take(slot),"outdoors auto switches off flashlight and permits pickup")
		check(street.interaction_visuals.has("pickup/"+str(slot)),"loose items reuse common highlighter")
		home.pick_up_surface_item(slot);street.update_interaction_visuals()
		check(home.state.ground_kind(slot).is_empty() and not street.interaction_visuals["pickup/"+str(slot)].control.visible,"loose pickup transfers once and hides sprite")
	var point:Dictionary=street.LOOT[0];street.row=point.row;street.player_x=point.x;street.building=point.building;street.floor_index=point.floor
	home.state.flashlight_on=false;street.position_changed()
	check(street.can_take(0) and street.interaction().get("kind")=="cabinet","darkness does not block opening/pickup")
	var building=street.active_building();building.light_level=.8;home.state.flashlight_on=true
	check(street.auto_manage_flashlight() and not home.state.flashlight_on,"bright interior auto switches flashlight off")
	var door=street.interaction_visuals["enter/"+point.building].control
	check(street.enemy_layer.get_index()>door.get_index() and street.enemy_layer.z_index==0 and street.enemy_layer.get_index()<street.hero_view.get_index(),"enemies render in front of doors without overriding overlay UI")
	street.building="";street.move_horizontal(1,.1,false)
	check(street.footstep_mode=="walk" and street.footstep_audio.stream.loop_mode==AudioStreamWAV.LOOP_FORWARD,"walking selects seamless rustle loop")
	street.move_horizontal(1,.1,true);check(street.footstep_mode=="run","running selects separate impact loop")
	street.move_horizontal(0,.1,false);check(street.footstep_mode.is_empty() and not street.footstep_audio.playing,"footsteps stop immediately while idle")
	# Unregistered stations still use the shared fullscreen backpack/active HUD.
	home.state.end_trip();home.state.station="南京东路";home.state.inventory.clear();home.confirm_departure();await process_frame
	check(not is_instance_valid(home.surface_block) and home.view.has_method("toggle_pack") and not home.view.pack_open,"legacy exploration shares collapsed backpack and active HUD")
	key(KEY_B);await process_frame
	check(home.view.pack_open and home.view.get_node("StreetFrame").size==Vector2(1280,720),"legacy B overlay also leaves scenery fullscreen")
	home.queue_free();await process_frame
	print("EXPLORATION_HUD: %d checks, %d failures"%[checks,failures]);if failures==0:print("EXPLORATION_HUD_OK")
	quit(1 if failures else 0)

func battery_center(control:Control)->Vector2:return control.get_global_rect().get_center()
