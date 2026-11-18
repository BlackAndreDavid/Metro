extends RefCounted
## Plain JSON content is authored by tools/editors; all paths remain inside res://.
static func read_json(path: String) -> Dictionary:
	if not path.begins_with("res://") or not FileAccess.file_exists(path): return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}
static func registry() -> Dictionary: return read_json("res://content/registry.json")
static func entry(station: String) -> Dictionary: return registry().get("stations",{}).get(station,{})
static func level(station: String) -> Dictionary: return read_json(entry(station).get("level",""))
static func scene(station: String) -> String: return entry(station).get("scene","res://scenes/game/exploration.tscn")
