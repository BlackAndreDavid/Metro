extends SceneTree
var output := OS.get_environment("METRO_TEST_RESULTS")
func _initialize() -> void:call_deferred("run")
func capture(name: String) -> void:
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name+".png"))
func run() -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless":quit(1);return
	DirAccess.make_dir_recursive_absolute(output);root.size = Vector2i(1280,720)
	var home = load("res://scenes/game/home.tscn").instantiate();root.add_child(home);home.show_cabin();home.state.installed_charge = 100
	home.loadout = {"light":true,"heavy":true,"wide":false,"crowbar":false,"wrench":false};home.confirm_departure();await process_frame
	var street = home.surface_block;street.set_process(false)
	home.state.inventory.clear();home.state.add_supply("meds","bag");home.state.equip_active(home.state.inventory[0].id);home.view.refresh_active()
	for i in range(5):street.move_horizontal(1,0.1,true)
	street.motion_updated.emit(street.motion.stamina,true,0);street.update_interaction_visuals();street.queue_redraw();await capture("suit-sprint-rat")
	home.view.set_pack_open(true);await capture("backpack-active-overlay");home.view.set_pack_open(false)
	var point: Dictionary = street.LOOT[0];street.row = int(point.row);street.player_x = point.x;street.building = point.building;street.floor_index = int(point.floor);home.state.flashlight_on = true
	street.position_changed();street.update_interaction_visuals();await capture("cabinet-highlight")
	street.interact();await capture("cabinet-contents")
	home.queue_free();await process_frame;print("EXPLORATION_CAPTURE_OK");quit()
