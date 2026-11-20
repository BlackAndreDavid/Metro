@tool
extends EditorPlugin
const Link=preload("res://addons/metro_content_editor/project_link.gd")
var dock:VBoxContainer
var status:Label
var http:HTTPRequest
var timer:Timer
var info:Dictionary={}
var linked:=""
var busy:=false
var pid:=-1
func _enter_tree()->void:
	dock=VBoxContainer.new();dock.name="Metro测试器"
	var open:=Button.new();open.text="打开独立测试器";open.pressed.connect(open_tester);dock.add_child(open)
	status=Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.custom_minimum_size.x=230;status.text="自动发现项目环境和测试器。测试窗口也可从 tools/tester 启动。";dock.add_child(status)
	http=HTTPRequest.new();http.timeout=3;http.max_redirects=0;http.request_completed.connect(response);dock.add_child(http)
	timer=Timer.new();timer.wait_time=1;timer.autostart=true;timer.timeout.connect(discover);dock.add_child(timer)
	add_control_to_dock(DOCK_SLOT_RIGHT_BL,dock);add_tool_menu_item("Metro 游戏测试器",open_tester)
func open_tester()->void:
	var project:=ProjectSettings.globalize_path("res://").simplify_path().trim_suffix("/")
	var binary:=project.get_base_dir().path_join("tools/bin/MetroTester/MetroTester.exe" if OS.get_name()=="Windows" else "tools/bin/MetroTester/MetroTester")
	var packaged:=FileAccess.file_exists(binary)
	var executable:=binary if packaged else Link.python_runtime(project)
	var desktop:=project.get_base_dir().path_join("tools/tester/desktop.py")
	if executable.is_empty() or (not packaged and not FileAccess.file_exists(desktop)):status.text="未找到 Python 或 tools/tester，请保留完整仓库并安装 requirements.txt。";return
	if pid>0 and OS.is_process_running(pid) and not info.is_empty():activate();return
	var args:=PackedStringArray(["--project",project,"--godot-executable",OS.get_executable_path()])
	if not packaged:args.insert(0,desktop)
	pid=OS.create_process(executable,args)
	status.text="正在打开测试器 · Python："+executable
	linked="";discover()
func normalize(path:String)->String:
	return path.replace("\\","/").trim_suffix("/").to_lower() if OS.get_name()=="Windows" else path.trim_suffix("/")
func discover()->void:
	if busy:return
	if pid>0 and not OS.is_process_running(pid) and not FileAccess.file_exists("res://.godot/metro_tester_connection.json"):
		status.text="测试器启动失败。请安装 tools/tester/requirements.txt，并查看 .godot/metro-tester/desktop-error.log";pid=-1
	var found:=Link.read_json("res://.godot/metro_tester_connection.json")
	var project:=ProjectSettings.globalize_path("res://").simplify_path().trim_suffix("/")
	if found.get("protocol")!="metro-tester" or normalize(found.get("project",""))!=normalize(project) or not Link.valid_url(found.get("url","")):return
	if found.get("session_id","")==linked:return
	info=found;busy=http.request(str(info.url)+"/api/bridge")==OK
func activate()->void:
	if busy:return
	busy=http.request(str(info.url)+"/api/show",PackedStringArray(["Content-Type: application/json","X-Metro-Token: "+str(info.token)]),HTTPClient.METHOD_POST,"{}") == OK
func response(result:int,code:int,_headers:PackedStringArray,body:PackedByteArray)->void:
	busy=false
	if result!=HTTPRequest.RESULT_SUCCESS or code!=200:status.text="测试器尚未连接，请查看 .godot/metro-tester/desktop-error.log";return
	var data:Variant=JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary:return
	if data.get("protocol")=="metro-tester":
		if data.get("session_id")!=info.get("session_id") or normalize(data.get("project",""))!=normalize(ProjectSettings.globalize_path("res://")):return
		linked=str(info.session_id)
		busy=http.request(str(info.url)+"/api/link",PackedStringArray(["Content-Type: application/json","X-Metro-Token: "+str(info.token)]),HTTPClient.METHOD_POST,JSON.stringify({"project":ProjectSettings.globalize_path("res://").trim_suffix("/"),"godot_executable":OS.get_executable_path()}))==OK
	else:status.text="测试器双向路径已保存。\n"+str(info.url)+"\n项目："+str(info.project)+"\n程序："+str(info.tool_root)
func _exit_tree()->void:
	timer.stop();http.cancel_request();remove_tool_menu_item("Metro 游戏测试器");remove_control_from_docks(dock);dock.queue_free()
