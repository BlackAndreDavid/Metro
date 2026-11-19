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
		for source in building.get("loot_points",[]):
			var point: Dictionary = source.duplicate(true)
			point.x = float(building.x)+float(source.x)
			point.row = building.row
			point.building = "" if source.get("outside",false) else building.id
			if source.get("outside",false): point.floor = 0
			append_spawn(pending,point,building.id+"/"+source.id)
	for source in data.get("spawn_points",[]):
		var point: Dictionary = source.duplicate(true)
		point.building = ""
		point.floor = 0
		append_spawn(pending,point,"outdoor/"+source.id)
	for point in pending:
		if point.has("slot"):
			while points.size() <= point.slot: points.append({"x":0,"row":0,"building":"","floor":0,"kind":""})
			points[point.slot] = point
	for point in pending:
		if not point.has("slot"): points.append(point)
	data["loot"] = points
	return data
static func scene(station: String) -> String: return entry(station).get("scene","res://scenes/game/exploration.tscn")

static func append_spawn(pending: Array, source: Dictionary, identifier: String) -> void:
	for roll in range(int(source.get("rolls",1))):
		var point: Dictionary = source.duplicate(true)
		var choices: Array = point.get("choices",[])
		point.kind = choices[0].kind if choices.size() == 1 else ""
		point.spawn_id = identifier
		point.roll = roll
		if source.get("container","cabinet") == "cabinet": point.cabinet = identifier
		if source.has("legacy_slot"): point.slot = int(source.legacy_slot)+roll
		pending.append(point)
