@tool
extends EditorPlugin
var checks:=0
var failures:=0
var desktop_pid:=-1
var report_path:=OS.get_environment("METRO_DESKTOP_REPORT")
func _enter_tree()->void:call_deferred("run")
func check(ok:bool,message:String)->void:
	checks+=1;print("DESKTOP_BRIDGE_CHECK ",message,": ",ok)
	if not ok:failures+=1;push_error(message)
func wait_for(predicate:Callable)->bool:
	for i in range(200):
		if predicate.call():return true
		await get_tree().create_timer(.1).timeout
	return false
func request_json(url:String,token:String="",post:bool=false)->Dictionary:
	var client:=HTTPRequest.new();client.timeout=5;add_child(client)
	var error:=client.request(url,PackedStringArray(["Content-Type: application/json","X-Editor-Token: "+token]),HTTPClient.METHOD_POST if post else HTTPClient.METHOD_GET,"{}" if post else "")
	if error!=OK:client.queue_free();return {}
	var response:Array=await client.request_completed;client.queue_free()
	if response[0]!=HTTPRequest.RESULT_SUCCESS or response[1]!=200:return {}
	var value:Variant=JSON.parse_string(response[3].get_string_from_utf8());return value if value is Dictionary else {}
func run()->void:
	if not await wait_for(func():return EditorInterface.get_base_control().find_child("Metro内容编辑器",true,false)!=null):check(false,"launcher dock exists");finish();return
	var dock:Node=EditorInterface.get_base_control().find_child("Metro内容编辑器",true,false)
	var label:Label
	var open:Button
	for child in dock.get_children():
		if child is LineEdit:child.text=""
		if child is Label:label=child
		if child is Button and child.text=="打开独立编辑器窗口":open=child
		if child is CheckBox:child.button_pressed=true
	check(EditorInterface.get_editor_settings().get_project_metadata("metro_editor","autostart",false),"autostart uses built-in persistent Godot project metadata")
	var link=load("res://addons/metro_content_editor/project_link.gd")
	check(await wait_for(func():return label.text.contains("浏览器编辑器已关联")),"browser-first discovery registers both paths without launching a desktop")
	check(link.read_json("res://content/editor-settings.local.json").get("godot_executable","")==OS.get_executable_path(),"browser handshake learns the running Godot executable")
	check(link.python_runtime(ProjectSettings.globalize_path("res://").trim_suffix("/")).contains(".venv-editor"),"relocated local Python environment is discovered with blank startup setting")
	for invalid in ["http://127.0.0.1:80@evil.test","http://127.0.0.1:0","http://127.0.0.1:99999","http://localhost:80","http://192.168.1.2:80"]:
		check(not link.valid_url(invalid),"reject non-loopback or invalid service URL: "+invalid)
	# Restart a browser after Godot is already open, using a fresh session on another port.
	var browser:Dictionary=link.read_json("res://.godot/metro_browser_connection.json")
	OS.kill(int(browser.pid))
	var paths:Dictionary=link.discover()
	var browser_pid:=OS.create_process(OS.get_environment("METRO_EDITOR_PYTHON"),PackedStringArray([paths.editor_root.path_join("server.py"),"--project",paths.project,"--port","0","--no-browser"]))
	check(await wait_for(func():return link.read_json("res://.godot/metro_browser_connection.json").get("pid",-1)==browser_pid),"browser can start after Godot")
	var new_browser:Dictionary=link.read_json("res://.godot/metro_browser_connection.json")
	check(await wait_for(func():return label.text.contains(str(new_browser.get("url","missing")))),"Godot-first discovery links the new browser session")
	OS.kill(browser_pid)
	open.pressed.emit()
	if not await wait_for(func():return label.text.contains("独立编辑器已打开")):
		check(false,"desktop launch: "+label.text);finish();return
	var info:Dictionary=link.read_json("res://.godot/metro_editor_connection.json");desktop_pid=int(info.pid)
	check(info.kind=="desktop","Godot launches a desktop program, not a browser or embedded Godot main screen")
	var manifest:Dictionary=await request_json(info.url+"/api/bridge")
	check(manifest.get("window",{}).get("native_window_id",0)>0,"independent native application window is created")
	var forward:Dictionary=link.read_json("res://content/editor-settings.local.json")
	var reverse:Dictionary=link.read_json(forward.editor_root.path_join(".projects.local.json"))
	check(forward.project==reverse.active_project and forward.godot_executable==OS.get_executable_path(),"project/editor/Godot executable paths save automatically in both directions")
	open.pressed.emit();await get_tree().create_timer(.5).timeout
	check(int(link.read_json("res://.godot/metro_editor_connection.json").pid)==desktop_pid,"reopening activates one existing window")
	var project:Dictionary=await request_json(info.url+"/api/project")
	EditorInterface.set_plugin_enabled("metro_content_editor",false)
	check(not (await request_json(info.url+"/api/bridge")).is_empty(),"disabling Godot launcher preserves the independent editor and its unsaved work")
	var closed:Dictionary=await request_json(info.url+"/api/desktop/close",project.token,true)
	check(closed.get("ok",false),"editor closes through its own native close handler")
	check(await wait_for(func():return not FileAccess.file_exists("res://.godot/metro_editor_connection.json")),"desktop service and connection file clean up on window close")
	check(await wait_for(func():return not OS.is_process_running(desktop_pid)),"desktop child process exits cleanly")
	finish()
func finish()->void:
	var file:=FileAccess.open(report_path,FileAccess.WRITE);file.store_string(JSON.stringify({"passed":failures==0,"checks":checks,"failures":failures,"pid":desktop_pid,"message":"Godot launcher, independent desktop window, automatic bidirectional paths, single instance, lifecycle and auto-start preference"}));file.close();get_tree().quit(0 if failures==0 else 1)
