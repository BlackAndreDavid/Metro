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
			return {"project":project,"editor_root":str(candidate).simplify_path()}
	return {"error":"未找到 tools/editors/desktop.py，请保留 Game 与 tools 的仓库目录关系。"}
