@tool
extends EditorPlugin
## Godot owns only launch/preferences/resource refresh; the desktop window reuses the complete editor.
const Link=preload("res://addons/metro_content_editor/project_link.gd")
var dock:VBoxContainer
var python:LineEdit
var automatic:CheckBox
var status:Label
var request:HTTPRequest
var poll:Timer
var links:Dictionary={}
var owned_pid:=-1
var attempts:=0
var base_url:=""
var token:=""
var action:=""
var connection:="res://.godot/metro_editor_connection.json"
func _enter_tree()->void:
	dock=VBoxContainer.new();dock.name="Metro内容编辑器"
	var open:=Button.new();open.text="打开独立编辑器窗口";open.pressed.connect(open_editor);dock.add_child(open)
	automatic=CheckBox.new();automatic.text="打开项目时自动启动";automatic.button_pressed=get_editor_interface().get_editor_settings().get_project_metadata("metro_editor","autostart",false);automatic.toggled.connect(func(v:bool):get_editor_interface().get_editor_settings().set_project_metadata("metro_editor","autostart",v));dock.add_child(automatic)
	var refresh:=Button.new();refresh.text="刷新 Godot 工程资源";refresh.pressed.connect(func():get_editor_interface().get_resource_filesystem().scan());dock.add_child(refresh)
	var advanced:=Button.new();advanced.text="启动设置 ▸";dock.add_child(advanced)
	python=LineEdit.new();python.placeholder_text="Python 可执行文件（含桌面依赖）";python.text=get_editor_interface().get_editor_settings().get_project_metadata("metro_editor","python","python" if OS.get_name()=="Windows" else "python3");python.hide();dock.add_child(python);advanced.pressed.connect(func():python.visible=not python.visible)
	status=Label.new();status.text="编辑器在独立程序窗口运行；打开后自动保存项目与编辑器的双向路径。";status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.custom_minimum_size.x=220;dock.add_child(status)
	request=HTTPRequest.new();request.timeout=5;request.request_completed.connect(response);dock.add_child(request)
	poll=Timer.new();poll.wait_time=.5;poll.timeout.connect(poll_startup);dock.add_child(poll)
	add_control_to_dock(DOCK_SLOT_RIGHT_BL,dock);add_tool_menu_item("Metro 独立内容编辑器",open_editor)
	if automatic.button_pressed and DisplayServer.get_name()!="headless":call_deferred("open_editor")
func open_editor()->void:
	links=Link.discover()
	if links.has("error"):status.text=links.error;return
	get_editor_interface().get_editor_settings().set_project_metadata("metro_editor","python",python.text.strip_edges())
	var args:=PackedStringArray([links.editor_root.path_join("desktop.py"),"--project",links.project,"--godot-executable",OS.get_executable_path(),"--connection-file",ProjectSettings.globalize_path(connection)])
	if owned_pid>0:
		if OS.is_process_running(owned_pid):
			if not base_url.is_empty():send("activate-token","/api/project")
			else:
				status.text="独立编辑器正在启动，请稍候。";attempts=0;poll.start()
			return
		owned_pid=-1
	owned_pid=OS.create_process(python.text.strip_edges(),args,false)
	if owned_pid<=0:status.text="Python 启动失败，请在启动设置填写解释器路径。";return
	attempts=0;status.text="正在打开独立编辑器…";poll.start()
func poll_startup()->void:
	attempts+=1
	var info:=Link.read_json(connection)
	if info.get("kind")=="desktop-error" and int(info.get("pid",-1))==owned_pid:
		poll.stop();status.text=info.get("error","启动失败");return
	if info.get("kind")=="desktop" and normalize(info.get("project",""))==normalize(links.project):
		base_url=info.get("url","")
		if not base_url.begins_with("http://127.0.0.1:"):poll.stop();status.text="编辑器地址无效。";return
		poll.stop();send("handshake","/api/bridge");return
	var alive:=OS.is_process_running(owned_pid)
	if not alive:owned_pid=-1
	if attempts>=60 or not alive:poll.stop();status.text="独立编辑器未能启动。请安装 requirements-desktop.txt 中的依赖，并查看 .godot/metro_editor_desktop.log。"
func send(next_action:String,path:String,method:int=HTTPClient.METHOD_GET)->void:
	action=next_action;request.cancel_request()
	var error:=request.request(base_url+path,PackedStringArray(["Content-Type: application/json","X-Editor-Token: "+token]),method,"{}" if method==HTTPClient.METHOD_POST else "")
	if error!=OK:status.text="无法连接独立编辑器："+error_string(error)
func response(result:int,code:int,_headers:PackedStringArray,body:PackedByteArray)->void:
	var parser:=JSON.new()
	if result!=HTTPRequest.RESULT_SUCCESS or code!=200 or parser.parse(body.get_string_from_utf8())!=OK:status.text="独立编辑器连接失败，请重新打开。";return
	var data:Dictionary=parser.data
	if action=="handshake":
		var remote:=str(data.get("project","")).replace("\\","/").trim_suffix("/");var local:String=links.project
		if OS.get_name()=="Windows":remote=remote.to_lower();local=local.to_lower()
		if data.get("protocol")!="metro-editor" or data.get("version")!=1 or not data.get("window") is Dictionary or data.window.get("kind")!="desktop" or remote!=local:status.text="连接的编辑器不是当前游戏项目的独立程序。";return
		send("activate-token","/api/project")
	elif action=="activate-token":token=data.token;send("show","/api/desktop/show",HTTPClient.METHOD_POST)
	else:status.text="独立编辑器已打开，双向路径已自动保存。"
func _exit_tree()->void:
	poll.stop();request.cancel_request();remove_tool_menu_item("Metro 独立内容编辑器");remove_control_from_docks(dock);dock.queue_free()
	# Keep the independent editor alive: closing Godot must not discard its unsaved work.

func normalize(path:String)->String:
	var value:=path.replace("\\","/").trim_suffix("/")
	return value.to_lower() if OS.get_name()=="Windows" else value
