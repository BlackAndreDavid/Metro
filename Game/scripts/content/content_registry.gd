extends RefCounted
## Plain JSON content is authored by tools/editors; all paths remain inside res://.
static func read_json(path: String) -> Dictionary:
	if not path.begins_with("res://") or not FileAccess.file_exists(path): return {}
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return value if value is Dictionary else {}
static func registry() -> Dictionary: return read_json("res://content/registry.json")
static func entry(station: String) -> Dictionary: return registry().get("stations",{}).get(station,{})
static func level(station: String, world_seed: int=0, day: int=1) -> Dictionary:
	var data := read_json(entry(station).get("level",""))
	if data.is_empty(): return data
	var points: Array = data.get("loot",[]).duplicate(true)
	var pending: Array = []
	for building in data.get("buildings",[]):
		for source in building.get("loot_points",[]):
			var point: Dictionary = source.duplicate(true)
			point.x = float(building.x)+float(source.x)
			point.region_origin = float(building.x)
			point.row = building.row
			point.building = "" if source.get("outside",false) else building.id
			if source.get("outside",false): point.floor = 0
			append_spawn(pending,point,building.id+"/"+source.id,hash("%s/%s/%s" % [station,world_seed,day]))
	for source in data.get("spawn_points",[]):
		var point: Dictionary = source.duplicate(true)
		point.building = ""
		point.floor = 0
		append_spawn(pending,point,"outdoor/"+source.id,hash("%s/%s/%s" % [station,world_seed,day]))
	for point in pending:
		if point.has("slot"):
			while points.size() <= point.slot: points.append({"x":0,"row":0,"building":"","floor":0,"kind":""})
			points[point.slot] = point
	for point in pending:
		if not point.has("slot"): points.append(point)
	data["loot"] = points
	return data
static func scene(station: String) -> String: return entry(station).get("scene","res://scenes/game/exploration.tscn")

static func append_spawn(pending: Array, source: Dictionary, identifier: String, seed_value: int=0) -> void:
	for roll in range(int(source.get("rolls",1))):
		var point: Dictionary = source.duplicate(true)
		var choices: Array = point.get("choices",[])
		point.kind = choices[0].kind if choices.size() == 1 else ""
		point.spawn_id = identifier
		point.roll = roll
		if source.has("region"):
			var rng := RandomNumberGenerator.new();rng.seed=hash("%s/%s/%s" % [seed_value,identifier,0 if source.get("container","cabinet")=="cabinet" else roll])
			var at := sample_region(source.region,rng)
			point.x = float(source.get("region_origin",0))+at.x
			point.drop_height = at.y
		if source.get("container","cabinet") == "cabinet": point.cabinet = identifier
		if source.has("legacy_slot"): point.slot = int(source.legacy_slot)+roll
		pending.append(point)

static func region_at(region: Dictionary, t: float) -> Vector2:
	var a := Vector2(region.start[0],region.start[1]);var b := Vector2(region.end[0],region.end[1])
	if region.get("type")=="arc":
		var c := Vector2(region.control[0],region.control[1])
		return (1-t)*(1-t)*a+2*(1-t)*t*c+t*t*b
	return a.lerp(b,t)

static func sample_region(region: Dictionary, rng: RandomNumberGenerator) -> Vector2:
	# Sampling polyline arc length avoids concentrating drops at short sections of a curve.
	var points: Array[Vector2] = [];var lengths: Array[float] = [];var total := 0.0
	for i in range(33):points.append(region_at(region,i/32.0))
	for i in range(32):
		var distance := points[i].distance_to(points[i+1]);lengths.append(distance);total+=distance
	var roll := rng.randf()*total
	for i in range(32):
		if roll<=lengths[i]:return points[i].lerp(points[i+1],roll/maxf(0.0001,lengths[i]))
		roll-=lengths[i]
	return points.back()
