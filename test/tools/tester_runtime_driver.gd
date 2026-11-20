extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	var session=root.get_node("GameSession")
	session.save_directory=ProjectSettings.globalize_path("res://.godot/formal-slots")
	assert(session.create_slot(1,"原始测试档")==OK)
	var formal:String=session.slot_path(1);var original:=FileAccess.get_file_as_string(formal)
	assert(session.select_slot(1))
	var home=load("res://scenes/game/home.tscn").instantiate();root.add_child(home);current_scene=home;home.show_cabin()
	paused=true
	var before:int=home.state.supply_count("water")
	var file:=FileAccess.open(OS.get_environment("METRO_TESTER_READY"),FileAccess.WRITE);file.store_string(JSON.stringify({"before":before,"formal":formal}));file.close()
	var deadline:=Time.get_ticks_msec()+45000
	while not FileAccess.file_exists("res://.godot/tester-done") and Time.get_ticks_msec()<deadline:await process_frame
	assert(home.state.account==987.5)
	assert(home.state.health==47)
	assert(home.state.supply_count("water")==before+2)
	assert(home.pointer_position.x==123)
	assert(home.save_path.begins_with(root.get_node("MetroTesterBridge").session_directory))
	assert(FileAccess.get_file_as_string(formal)==original)
	assert(FileAccess.file_exists(home.save_path))
	paused=false;home.queue_free();await process_frame
	print("TESTER_RUNTIME_OK: numeric mutation, vector paths, item spawn, isolated saves, formal save unchanged")
	quit()
