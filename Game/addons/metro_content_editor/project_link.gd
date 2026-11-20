@tool
extends RefCounted
## Discovery only. Persistence belongs to the shared editor service, avoiding two implementations.
static func read_json(path:String)->Dictionary:
	if not FileAccess.file_exists(path):return {}
	var parser:=JSON.new()
	return parser.data if parser.parse(FileAccess.get_file_as_string(path))==OK and parser.data is Dictionary else {}
static func discover()->Dictionary:
	var project:=ProjectSettings.globalize_path("res://").simplify_path().trim_suffix("/")
	var settings:=read_json(project.path_join("content/editor-settings.local.json"))
	for candidate in [project.get_base_dir().path_join("tools/editors"),settings.get("editor_root","")]:
		if not str(candidate).is_empty() and FileAccess.file_exists(str(candidate).path_join("desktop.py")):
			return {"project":project,"editor_root":str(candidate).simplify_path(),"external":str(candidate).simplify_path()!=project.get_base_dir().path_join("tools/editors")}
	return {"error":"未找到 tools/editors/desktop.py，请保留 Game 与 tools 的仓库目录关系。"}

static func valid_url(url:String)->bool:
	var pattern:=RegEx.new();pattern.compile("^http://127\\.0\\.0\\.1:([0-9]{1,5})$")
	var matched:=pattern.search(url)
	return matched!=null and int(matched.get_string(1))>0 and int(matched.get_string(1))<=65535

static func resolve_python_override(project:String,override:String)->String:
	var value:=override.strip_edges().trim_prefix('"').trim_suffix('"').replace("\\","/")
	if value.is_empty():return ""
	if value.is_absolute_path():return value if FileAccess.file_exists(value) else ""
	if value.contains("/"):
		# Relative overrides belong to the repository, not Godot's working directory.
		var candidate:=project.get_base_dir().path_join(value).simplify_path()
		return candidate if FileAccess.file_exists(candidate) else ""
	for folder in OS.get_environment("PATH").split(";" if OS.get_name()=="Windows" else ":"):
		if folder.is_empty() or folder.to_lower().contains("windowsapps"):continue
		for name in [value,value+".exe"] if OS.get_name()=="Windows" else [value]:
			var candidate:String=folder.path_join(name)
			if FileAccess.file_exists(candidate):return candidate
	return ""

static func python_runtime(project:String,override:String="")->String:
	# Only inspect known local paths/PATH. Discovery never executes a candidate.
	var selected:=resolve_python_override(project,override)
	if not selected.is_empty():return selected
	var root:=project.get_base_dir()
	var suffix:="Scripts/python.exe" if OS.get_name()=="Windows" else "bin/python"
	for folder in [root.path_join(".venv-editor"),root.path_join(".venv"),root.path_join("tools/editors/.venv")]:
		var candidate:String=folder.path_join(suffix)
		if FileAccess.file_exists(candidate):return candidate
	var names:=["python.exe","python3.exe"] if OS.get_name()=="Windows" else ["python3","python"]
	for folder in OS.get_environment("PATH").split(";" if OS.get_name()=="Windows" else ":"):
		if folder.is_empty() or folder.to_lower().contains("windowsapps"):continue
		for name in names:
			var candidate:String=folder.path_join(name)
			if FileAccess.file_exists(candidate):return candidate
	return ""
