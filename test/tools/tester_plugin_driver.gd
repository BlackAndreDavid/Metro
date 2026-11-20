@tool
extends EditorPlugin
var http:HTTPRequest
func _enter_tree()->void:call_deferred("run")
func wait_for(predicate:Callable)->bool:
	for i in range(300):
		if predicate.call():return true
		await get_tree().create_timer(.1).timeout
	return false
func run()->void:
	assert(await wait_for(func():return EditorInterface.get_base_control().find_child("Metro测试器",true,false)!=null))
	var dock:Node=EditorInterface.get_base_control().find_child("Metro测试器",true,false)
	dock.get_child(0).pressed.emit()
	var link=load("res://addons/metro_content_editor/project_link.gd")
	assert(await wait_for(func():return int(link.read_json("res://.godot/metro_tester_connection.json").get("native_window_id",0))>0))
	assert(await wait_for(func():return dock.get_child(1).text.contains("双向路径")))
	var info:Dictionary=link.read_json("res://.godot/metro_tester_connection.json")
	var settings:Dictionary=link.read_json("res://content/tester-settings.local.json")
	assert(settings.godot_executable==OS.get_executable_path())
	assert(info.kind=="native" and info.pid>0)
	EditorInterface.set_plugin_enabled("metro_tester",false)
	assert(OS.is_process_running(int(info.pid)))
	http=HTTPRequest.new();add_child(http);http.timeout=4
	http.request(str(info.url)+"/api/close",PackedStringArray(["X-Metro-Token: "+str(info.token)]),HTTPClient.METHOD_POST,"{}")
	await http.request_completed
	assert(await wait_for(func():return not FileAccess.file_exists("res://.godot/metro_tester_connection.json")))
	print("TESTER_PLUGIN_OK: Godot launcher, automatic runtime discovery, native window, bidirectional paths, lifecycle")
	get_tree().quit()
