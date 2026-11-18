extends RefCounted
## Plain JSON content is authored by tools/editors; all paths remain inside res://.
static func read_json(path: String) -> Dictionary:
	if not path.begins_with("res://") or not FileAccess.file_exists(path): return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}
static func registry() -> Dictionary: return read_json("res://content/registry.json")
static func entry(station: String) -> Dictionary: return registry().get("stations",{}).get(station,{})
static func level(station: String) -> Dictionary:
	var data := read_json(entry(station).get("level",""))
	if data.is_empty(): return data
	var points: Array = data.get("loot",[]).duplicate(true)
	var pending: Array = []
	for building in data.get("buildings",[]):
		for cabinet in building.get("loot_points",[]):
			for roll in range(int(cabinet.get("rolls",1))):
				var choices: Array = cabinet.get("choices",[])
				var point := {"x":float(building.x)+float(cabinet.x),"row":building.row,"building":building.id,"floor":cabinet.get("floor",0),"kind":choices[0].kind if choices.size() == 1 else "","choices":choices,"chance":cabinet.get("chance",1),"cabinet":building.id+"/"+cabinet.id,"roll":roll}
				if cabinet.has("legacy_slot"): point["slot"] = int(cabinet.legacy_slot)+roll
				pending.append(point)
	for point in pending:
		if point.has("slot"):
			while points.size() <= point.slot: points.append({"x":0,"row":0,"building":"","floor":0,"kind":""})
			points[point.slot] = point
	for point in pending:
		if not point.has("slot"): points.append(point)
	data["loot"] = points
	return data
static func scene(station: String) -> String: return entry(station).get("scene","res://scenes/game/exploration.tscn")
