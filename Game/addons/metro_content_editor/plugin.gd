@tool
extends EditorPlugin
## Launch the full editor; associate browser/desktop services through the same handshake.
const Link=preload("res://addons/metro_content_editor/project_link.gd")
var dock:VBoxContainer
var python:LineEdit
var automatic:CheckBox
var status:Label
var request:HTTPRequest
var poll:Timer
var observer:Timer
var links:Dictionary={}
var owned_pid:=-1
var attempts:=0
var base_url:=""
var token:=""
var action:=""
var connection:="res://.godot/metro_editor_connection.json"
var pending:Dictionary={}
var seen:Dictionary={}
var activate:=false
var linked_kind:=""
func _enter_tree()->void:
	dock=VBoxContainer.new();dock.name="Metro内容编辑器"
	var open:=Button.new();open.text="打开独立编辑器窗口";open.pressed.connect(open_editor);dock.add_child(open)
	automatic=CheckBox.new();automatic.text="打开项目时自动启动";automatic.button_pressed=get_editor_interface().get_editor_settings().get_project_metadata("metro_editor","autostart",false);automatic.toggled.connect(func(v:bool):get_editor_interface().get_editor_settings().set_project_metadata("metro_editor","autostart",v));dock.add_child(automatic)
	var refresh:=Button.new();refresh.text="刷新 Godot 工程资源";refresh.pressed.connect(func():get_editor_interface().get_resource_filesystem().scan());dock.add_child(refresh)
	var reconnect:=Button.new();reconnect.text="重新查找并关联";reconnect.pressed.connect(func():seen.clear();discover_service());dock.add_child(reconnect)
	var advanced:=Button.new();advanced.text="启动设置 ▸";dock.add_child(advanced)
	python=LineEdit.new();python.placeholder_text="留空自动查找项目环境 / PATH";python.text=get_editor_interface().get_editor_settings().get_project_metadata("metro_editor","python_override","");python.hide();dock.add_child(python);advanced.pressed.connect(func():python.visible=not python.visible)
	status=Label.new();status.text="自动查找本项目的浏览器 / 独立编辑器。启动设置留空即可自动寻找 Python。";status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.custom_minimum_size.x=220;dock.add_child(status)
	request=HTTPRequest.new();request.timeout=5;request.max_redirects=0;request.request_completed.connect(response);dock.add_child(request)
	poll=Timer.new();poll.wait_time=.5;poll.timeout.connect(poll_startup);dock.add_child(poll)
	observer=Timer.new();observer.wait_time=2;observer.timeout.connect(discover_service);observer.autostart=true;dock.add_child(observer)
	links=Link.discover()
	add_control_to_dock(DOCK_SLOT_RIGHT_BL,dock);add_tool_menu_item("Metro 独立内容编辑器",open_editor)
	if automatic.button_pressed and DisplayServer.get_name()!="headless":call_deferred("open_editor")
	else:call_deferred("discover_service")
func open_editor()->void:
	links=Link.discover()
	if links.has("error"):status.text=links.error;return
	if links.get("external",false):status.text="发现项目外编辑器："+links.editor_root+"。为避免自动执行外部脚本，请将可信工具放回仓库 tools/editors。";return
	get_editor_interface().get_editor_settings().set_project_metadata("metro_editor","python_override",python.text.strip_edges())
	var executable:=Link.python_runtime(links.project,python.text)
	if executable.is_empty():status.text="未找到 Python。请安装 Python 和 requirements-desktop.txt，或在启动设置填写解释器。";return
	activate=true
	if owned_pid>0 and OS.is_process_running(owned_pid):
		if linked_kind=="desktop" and not base_url.is_empty():send("activate-token","/api/project")
		else:attempts=0;poll.start()
		return
	var args:=PackedStringArray([links.editor_root.path_join("desktop.py"),"--project",links.project,"--godot-executable",OS.get_executable_path(),"--connection-file",ProjectSettings.globalize_path(connection)])
	owned_pid=OS.create_process(executable,args,false)
	if owned_pid<=0:activate=false;status.text="Python 启动失败："+executable;return
	attempts=0;status.text="正在打开独立编辑器…\nPython："+executable;poll.start()
func discover_service()->void:
	if not action.is_empty() or not poll.is_stopped():return
	var project:=ProjectSettings.globalize_path("res://").simplify_path().trim_suffix("/")
	# Prefer desktop; each service has its own connection file, so they cannot overwrite one another.
	var candidates:Array=[Link.read_json(connection),Link.read_json("res://.godot/metro_browser_connection.json")]
	var settings:=Link.read_json("res://content/editor-settings.local.json")
	if settings.get("services") is Dictionary:candidates.append_array(settings.services.values())
	for info in candidates:
		if not info is Dictionary:continue
		var signature:String=JSON.stringify(info)
		if info.get("kind","") not in ["desktop","browser"] or normalize(info.get("project",""))!=normalize(project) or not Link.valid_url(info.get("url","")):continue
		if seen.has(signature):continue
		activate=false;begin_link(info);return
func begin_link(info:Dictionary)->void:
	pending=info;seen[JSON.stringify(info)]=true;base_url=info.url;token=""
	send("handshake","/api/bridge")
func poll_startup()->void:
	attempts+=1
	var info:=Link.read_json(connection)
	if info.get("kind")=="desktop-error" and int(info.get("pid",-1))==owned_pid:
		poll.stop();activate=false;status.text=info.get("error","启动失败");return
	if info.get("kind")=="desktop" and normalize(info.get("project",""))==normalize(links.project) and Link.valid_url(info.get("url","")):
		poll.stop();begin_link(info);return
	var alive:=OS.is_process_running(owned_pid)
	if not alive:owned_pid=-1
	if attempts>=60 or not alive:poll.stop();activate=false;status.text="独立编辑器未能启动。请安装 requirements-desktop.txt 中的依赖，并查看 .godot/metro_editor_desktop.log。"
func send(next_action:String,path:String,method:int=HTTPClient.METHOD_GET,payload:Dictionary={})->void:
	action=next_action;request.cancel_request()
	var error:=request.request(base_url+path,PackedStringArray(["Content-Type: application/json","X-Editor-Token: "+token]),method,JSON.stringify(payload) if method==HTTPClient.METHOD_POST else "")
	if error!=OK:action="";status.text="无法连接编辑器："+error_string(error)
func response(result:int,code:int,_headers:PackedStringArray,body:PackedByteArray)->void:
	var current:=action;action=""
	var parser:=JSON.new()
	if result!=HTTPRequest.RESULT_SUCCESS or code!=200 or parser.parse(body.get_string_from_utf8())!=OK or not parser.data is Dictionary:
		status.text="编辑器连接失败；重新启动编辑器后会自动发现。";return
	var data:Dictionary=parser.data
	if current=="handshake":
		var project:=ProjectSettings.globalize_path("res://").simplify_path().trim_suffix("/")
		if data.get("protocol")!="metro-editor" or data.get("version")!=1 or normalize(data.get("project",""))!=normalize(project) or data.get("session_id","")!=pending.get("session_id","") or data.get("kind")!=pending.get("kind"):
			status.text="服务身份或项目不匹配，未建立关联。";return
		linked_kind=pending.get("kind","");send("activate-token","/api/project")
	elif current=="activate-token":
		token=str(data.get("token",""))
		send("linked","/api/link",HTTPClient.METHOD_POST,{"project":ProjectSettings.globalize_path("res://").simplify_path().trim_suffix("/"),"godot_executable":OS.get_executable_path()})
	elif current=="linked" and activate and linked_kind=="desktop":send("show","/api/desktop/show",HTTPClient.METHOD_POST)
	else:
		activate=false
		status.text=("独立编辑器已打开" if linked_kind=="desktop" else "浏览器编辑器已关联")+"，双向路径已保存。\n服务："+base_url+"\n编辑器："+str(pending.get("editor_root",""))+"\nGodot："+OS.get_executable_path()
func _exit_tree()->void:
	poll.stop();observer.stop();request.cancel_request();remove_tool_menu_item("Metro 独立内容编辑器");remove_control_from_docks(dock);dock.queue_free()
	# The independent window keeps unsaved work when Godot closes.
func normalize(path:String)->String:
	var value:=path.replace("\\","/").trim_suffix("/")
	return value.to_lower() if OS.get_name()=="Windows" else value
