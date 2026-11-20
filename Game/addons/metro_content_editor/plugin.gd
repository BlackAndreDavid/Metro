@tool
extends EditorPlugin
## The web editor and game share res://content, using the versioned /api/bridge handshake.
var dock: VBoxContainer
var python: LineEdit
var address: LineEdit
var status: Label
var request: HTTPRequest
var poll: Timer
var owned_pid := -1
var attempts := 0
var connected_ready := false
var connection := "res://.godot/metro_editor_connection.json"
func _enter_tree() -> void:
	dock = VBoxContainer.new();dock.name = "Metro内容编辑器"
	var title := Label.new();title.text = "地图 / 关卡 / 角色";dock.add_child(title)
	python = LineEdit.new();python.placeholder_text = "Python 可执行文件"
	python.text = get_editor_interface().get_editor_settings().get_project_metadata("metro_editor","python","python" if OS.get_name() == "Windows" else "python3")
	dock.add_child(python)
	add_button("启动内容编辑器",start_editor)
	address = LineEdit.new();address.placeholder_text = "http://127.0.0.1:8765";address.text = "http://127.0.0.1:8765";dock.add_child(address)
	add_button("连接并检查接口",connect_editor)
	add_button("在浏览器中打开",open_editor)
	add_button("刷新 Godot 工程资源",refresh_content)
	add_button("停止本面板启动的服务",stop_editor)
	status = Label.new();status.text = "未连接。地图数据保存在 content/network_map.json。";status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART;status.custom_minimum_size.x = 230;dock.add_child(status)
	request = HTTPRequest.new();request.timeout = 5;request.request_completed.connect(on_handshake);dock.add_child(request)
	poll = Timer.new();poll.wait_time = .5;poll.timeout.connect(poll_startup);dock.add_child(poll)
	add_control_to_dock(DOCK_SLOT_RIGHT_BL,dock)
func add_button(text: String, callback: Callable) -> void:
	var button := Button.new();button.text = text;button.pressed.connect(callback);dock.add_child(button)
func start_editor() -> void:
	if owned_pid > 0 and OS.is_process_running(owned_pid):
		connect_editor();return
	var server := ProjectSettings.globalize_path("res://../tools/editors/server.py").simplify_path()
	if not FileAccess.file_exists(server): status.text = "找不到 tools/editors/server.py，请保留 Game 与 tools 的目录关系。";return
	get_editor_interface().get_editor_settings().set_project_metadata("metro_editor","python",python.text.strip_edges())
	if FileAccess.file_exists(connection): DirAccess.remove_absolute(ProjectSettings.globalize_path(connection))
	var args := PackedStringArray([server,"--project",ProjectSettings.globalize_path("res://"),"--port","0","--no-browser","--connection-file",ProjectSettings.globalize_path(connection)])
	owned_pid = OS.create_process(python.text.strip_edges(),args,true)
	if owned_pid <= 0: status.text = "Python 启动失败，请检查可执行文件路径。";return
	connected_ready = false;attempts = 0;status.text = "正在启动本机编辑器…";poll.start()
func poll_startup() -> void:
	attempts += 1
	if FileAccess.file_exists(connection):
		var info: Variant = JSON.parse_string(FileAccess.get_file_as_string(connection))
		if info is Dictionary and info.get("pid") == owned_pid:
			address.text = info.get("url","");poll.stop();connect_editor();return
	var alive := OS.is_process_running(owned_pid)
	if not alive: owned_pid = -1
	if attempts >= 30 or not alive:
		poll.stop();status.text = "启动未完成，请检查 Python 与 Pillow。安装：python -m pip install -r tools/editors/requirements.txt"
func connect_editor() -> void:
	var url := address.text.strip_edges().trim_suffix("/")
	if not url.begins_with("http://127.0.0.1:") or not url.get_slice(":",2).is_valid_int():
		status.text = "仅连接 http://127.0.0.1:端口 的本机编辑器。";return
	request.cancel_request();connected_ready = false
	var error := request.request(url+"/api/bridge")
	status.text = "正在检查接口…" if error == OK else "无法发起连接："+error_string(error)
func on_handshake(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200: status.text = "连接失败，请先启动内容编辑器。";return
	var parser := JSON.new()
	if parser.parse(body.get_string_from_utf8()) != OK:
		status.text = "接口响应不是有效 JSON，请检查编辑器版本。";return
	var data: Variant = parser.data
	if not data is Dictionary or data.get("protocol") != "metro-editor" or data.get("version") != 1:
		status.text = "编辑器接口版本不兼容。";return
	var remote_project := str(data.get("project","")).replace("\\","/").trim_suffix("/")
	var local_project := ProjectSettings.globalize_path("res://").replace("\\","/").trim_suffix("/")
	if OS.get_name() == "Windows":
		remote_project = remote_project.to_lower();local_project = local_project.to_lower()
	if remote_project != local_project:
		status.text = "该编辑器连接的是另一个 Game 工程。";return
	connected_ready = true;status.text = "已连接 Metro 接口 v1。保存后刷新资源；游戏重新打开地图时读取新线路。"
func open_editor() -> void:
	if not connected_ready: status.text = "请先启动或连接并检查接口。";return
	OS.shell_open(address.text.strip_edges())
func refresh_content() -> void:
	get_editor_interface().get_resource_filesystem().scan()
	status.text = "正在刷新资源。地图与角色内容将在游戏下次打开对应界面时读取。"
func stop_editor() -> void:
	poll.stop();request.cancel_request()
	if owned_pid > 0 and OS.is_process_running(owned_pid): OS.kill(owned_pid)
	owned_pid = -1;connected_ready = false;status.text = "本面板启动的服务已停止。"
func _exit_tree() -> void:
	stop_editor()
	remove_control_from_docks(dock);dock.queue_free()
