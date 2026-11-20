extends RefCounted
## Shared editor/runtime contract. Routing stops are names; bends are coordinate pairs.
static func read_network() -> Dictionary:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://content/network_map.json"))
	if not raw is Dictionary or raw.get("version") != 1 or not raw.get("stations") is Dictionary or not raw.get("lines") is Array:
		push_error("Invalid network_map.json")
		return {}
	var stations := {}
	for name in raw.stations:
		var station: Dictionary = raw.stations[name]
		stations[name] = [Vector2(station.position[0],station.position[1]),Vector2(station.label[0],station.label[1])]
	var lines: Array = []
	for source in raw.lines:
		var points: Array = []
		for point in source[2]:
			points.append(point if point is String else Vector2(point[0],point[1]))
		lines.append([int(source[0]),source[1],points])
	return {"stations":stations,"lines":lines,"textures":raw.get("textures",[]),"canvas":raw.get("canvas",{"width":1500,"height":1150})}
