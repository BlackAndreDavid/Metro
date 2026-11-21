extends RefCounted
## Grid placement is model data; hanging planes never occupy the floor grid.
# Inner walls begin at source x=2; ceiling ends at y=13 and floor starts at y=95.
# The carriage texture is displayed at 4x its native resolution.
const INTERIOR_RECT := Rect2(162, 196, 956, 328)
const GRID_SIZE := Vector2i(35, 12)
const CELL_SIDE := 956.0 / 35.0
const CELL_SIZE := Vector2(CELL_SIDE, CELL_SIDE)
const GRID_ORIGIN := INTERIOR_RECT.position
const CARRIAGE_PITCH := 972.0
const MOUNT_SIZE := Vector2i(4, 3)
const HANGING_ORIGINS := [Vector2(28, 22), Vector2(87, 22), Vector2(130, 20), Vector2(204, 21)]
const LEGACY_IDS := ["bed","computer","locker","door","screen"]
static var IDS: Array = []
static var DEFINITIONS: Dictionary = {}
static var SOURCES: Dictionary = {}
const GROUND_EDGE_Y := GRID_ORIGIN.y + GRID_SIZE.y * CELL_SIDE
static func _static_init() -> void:
	reload()
static func reload() -> void:
	IDS.clear();DEFINITIONS.clear();SOURCES.clear()
	var document: Dictionary=preload("res://scripts/content/content_registry.gd").read_json("res://content/furniture.json")
	for data in document.get("furniture",[]):
		SOURCES[data.id]=data.duplicate(true);IDS.append(data.id);DEFINITIONS[data.id]=preload("res://scripts/items/furniture_definition.gd").from_data(data)

static func floor_rect(car: int) -> Rect2:
	return Rect2(GRID_ORIGIN + Vector2(car * CARRIAGE_PITCH, 0), Vector2(GRID_SIZE) * CELL_SIZE)

static func mount_rect(car: int, mount: int) -> Rect2:
	var hook: Vector2 = HANGING_ORIGINS[mount] + Vector2(14, 0)
	return Rect2(Vector2(154 + car * CARRIAGE_PITCH, 144) + hook * 4 - Vector2(MOUNT_SIZE.x * CELL_SIZE.x / 2, 0), Vector2(MOUNT_SIZE) * CELL_SIZE)

static func placement_rect(kind: String, placement: Dictionary) -> Rect2:
	var plane := mount_rect(int(placement.car), int(placement.mount)) if placement.has("mount") else floor_rect(int(placement.car))
	return Rect2(plane.position + Vector2(placement.x, placement.y) * CELL_SIZE, Vector2(DEFINITIONS[kind].grid_size) * CELL_SIZE)

static func default_placement(kind: String, car: int = 0) -> Dictionary:
	var value: Variant = DEFINITIONS[kind].default_placement
	if value==null:return {}
	var result: Dictionary=canonical(value);result.car=car
	return result

static func initial_layout() -> Dictionary:
	var requested := {}
	for kind in IDS:
		var placement:=default_placement(kind)
		requested[kind]=placement if not placement.is_empty() and (DEFINITIONS[kind].initial_placed and DEFINITIONS[kind].enabled or kind in ["door","window"]) else null
	return reconcile_layout(requested,1)

static func base_kind(id: String) -> String:
	return id.get_slice("#",0)

static func ensure_instance(id: String) -> bool:
	if DEFINITIONS.has(id):return true
	var base:=base_kind(id)
	if id.count("#")!=1 or base not in IDS or not id.get_slice("#",1).is_valid_int() or int(id.get_slice("#",1))<1:return false
	var definition: Resource=preload("res://scripts/items/furniture_definition.gd").from_data(SOURCES[base])
	definition.id=id;DEFINITIONS[id]=definition
	return true

static func reconcile_layout(requested: Dictionary, count: int) -> Dictionary:
	var result: Dictionary={}
	var order: Array=requested.keys()
	var priorities: Dictionary={"door":0,"window":1,"locker":2,"preparation":3,"bed":4}
	order.sort_custom(func(a,b):return priorities.get(base_kind(a),5)<priorities.get(base_kind(b),5))
	for id in order:result[id]=null
	for id in order:
		if requested[id]==null or not ensure_instance(id):continue
		var preferred: Dictionary=canonical(requested[id])
		if free_placement(id,preferred,result,count):result[id]=preferred;continue
		var options: Array[Dictionary]=[]
		if DEFINITIONS[id].placement_type=="hanging":
			for car in range(count):
				for mount in range(HANGING_ORIGINS.size()):options.append({"car":car,"mount":mount,"x":0,"y":0})
		else:
			for car in range(count):
				for y in range(-occupancy_bounds(id).position.y,GRID_SIZE.y-occupancy_bounds(id).end.y+1):
					for x in range(-occupancy_bounds(id).position.x,GRID_SIZE.x-occupancy_bounds(id).end.x+1):options.append({"car":car,"x":x,"y":y})
		options.sort_custom(func(a,b):return placement_distance(a,preferred)<placement_distance(b,preferred))
		for option in options:
			if free_placement(id,option,result,count):result[id]=option;break
	return result

static func free_placement(id: String, at: Dictionary, layout: Dictionary, count: int) -> bool:
	if not valid_placement(id,at,count):return false
	for other in layout:
		if other!=id and layout[other]!=null and overlaps(id,at,other,layout[other]):return false
	var trial:=layout.duplicate(true);trial[id]=at
	return support_problem(id,at,trial).is_empty() and distance_problem(trial).is_empty()

static func valid_placement(kind: String, p: Variant, count: int, version: int = 19) -> bool:
	if not ensure_instance(kind) or not p is Dictionary:
		return false
	var hanging: bool = DEFINITIONS[kind].placement_type == "hanging"
	if p.size() != (4 if hanging else 3):
		return false
	for key in ["car", "x", "y"]:
		if not integer(p.get(key)):
			return false
	if p.car < 0 or p.car >= count:
		return false
	var bounds := (Vector2i(2, 2) if version <= 8 else (Vector2i(3, 3) if version == 9 else MOUNT_SIZE)) if hanging else (Vector2i(16, 12) if version == 6 else (Vector2i(34, 12) if version == 7 else GRID_SIZE))
	if hanging and (not integer(p.get("mount")) or p.mount < 0 or p.mount >= HANGING_ORIGINS.size()):
		return false
	if version>=19 and not hanging:
		var occupied:=cells(kind,p,"floor_cells")+cells(kind,p,"wall_cells")
		if occupied.is_empty():return false
		for cell in occupied:
			if not Rect2i(Vector2i.ZERO,bounds).has_point(cell):return false
		return true
	return Rect2i(Vector2i.ZERO, bounds).encloses(Rect2i(Vector2i(int(p.x), int(p.y)), footprint(kind, version)))

static func overlaps(a_kind: String, a: Dictionary, b_kind: String, b: Dictionary, version: int = 19) -> bool:
	if int(a.car) != int(b.car) or a.has("mount") != b.has("mount"):
		return false
	if a.has("mount") and int(a.mount) != int(b.mount):
		return false
	if version < 18 or a.has("mount"):
		return Rect2i(Vector2i(int(a.x),int(a.y)),footprint(a_kind,version)).intersects(Rect2i(Vector2i(int(b.x),int(b.y)),footprint(b_kind,version)))
	for plane in ["floor_cells","wall_cells"]:
		var occupied:=cells(a_kind,a,plane)
		for cell in cells(b_kind,b,plane):
			if cell in occupied:return true
	return false

static func cells(kind: String, p: Dictionary, plane: String) -> Array[Vector2i]:
	var result: Array[Vector2i]=[]
	for cell in DEFINITIONS[kind].get(plane):result.append(cell+Vector2i(int(p.x),int(p.y)))
	return result

static func integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(value) and value == floor(value)

static func canonical(p: Dictionary) -> Dictionary:
	var result := {"car": int(p.car), "x": int(p.x), "y": int(p.y)}
	if p.has("mount"):
		result.mount = int(p.mount)
	return result

static func copy_layout(layout: Dictionary) -> Dictionary:
	var result := {}
	for kind in IDS:
		result[kind]=canonical(layout[kind]) if layout.get(kind)!=null else null
	for id in layout:
		if ensure_instance(id):result[id]=canonical(layout[id]) if layout[id]!=null else null
	return result

static func footprint(kind: String, version: int = 19) -> Vector2i:
	if version <= 10 and kind == "computer": return Vector2i(2, 2)
	if version == 9 and kind == "screen": return Vector2i(3, 3)
	if version <= 8 and kind == "screen": return Vector2i(2, 2)
	if version == 8 and kind == "bed": return Vector2i(2, 8)
	if version <= 7 and kind == "bed": return Vector2i(4, 1)
	if version in [7,8] and kind == "door": return Vector2i(6, 12)
	if version == 6 and kind == "locker": return Vector2i(2, 2)
	if version == 7 and kind == "locker": return Vector2i(2, 12)
	if version == 6 and kind == "door": return Vector2i(4, 12)
	return DEFINITIONS[kind].grid_size

static func migrate_grid_layout(layout: Dictionary, version: int) -> Dictionary:
	var result := {}
	for kind in IDS: result[kind] = null
	var old_cell := Vector2(56,26) if version == 6 else (Vector2(26,26) if version == 7 else CELL_SIZE)
	var old_origin := Vector2(174,212) if version <= 7 else GRID_ORIGIN
	# Place full-height furniture first, then preserve nearby positions of smaller items.
	for kind in ["screen", "door", "locker", "computer", "bed"]:
		if layout.get(kind) == null: continue
		var old: Dictionary = canonical(layout[kind])
		if kind == "screen":
			result[kind] = old
			continue
		# Preserve the old bottom-left pixel position when the footprint changes.
		var old_bottom := old_origin + Vector2(old.x,old.y + footprint(kind,version).y) * old_cell
		var desired := (old_bottom - GRID_ORIGIN) / CELL_SIZE - Vector2(0,footprint(kind).y)
		var best: Dictionary = {}
		var distance := INF
		for y in range(GRID_SIZE.y - footprint(kind).y + 1):
			for x in range(GRID_SIZE.x - footprint(kind).x + 1):
				var p := {"car": old.car, "x": x, "y": y}
				var blocked := false
				for other in IDS:
					if result[other] != null and overlaps(kind, p, other, result[other]): blocked = true
				var d := Vector2(x,y).distance_squared_to(desired)
				if not blocked and d < distance:
					best = p
					distance = d
		result[kind] = best
	return result

static func visual_rect(kind: String, bounds: Rect2) -> Rect2:
	var data: Resource = DEFINITIONS[kind]
	if not data.texture_binding.is_empty():
		var binding: Dictionary=data.texture_binding
		return Rect2(bounds.position+Vector2(binding.x,binding.y)*CELL_SIZE,Vector2(binding.width,binding.height)*CELL_SIZE)
	# Unbound artwork uses a fixed native scale, independent of the occupied cells.
	return Rect2(bounds.position,Vector2(data.texture.get_size())*CELL_SIZE/32.0)


static func support_problem(kind: String, p: Dictionary, layout: Dictionary) -> String:
	var data: Resource=DEFINITIONS[kind]
	if p.has("mount") or not data.wall_cells.is_empty():return ""
	var occupied:=cells(kind,p,"floor_cells")
	for cell in occupied:
		var below:=cell+Vector2i.DOWN
		if below in occupied or is_on_ground(cell):continue
		var supported:=false
		for other in layout:
			var at: Variant=layout[other]
			if other==kind or at==null or not DEFINITIONS.has(other) or not DEFINITIONS[other].support_surface:continue
			if int(at.car)==int(p.car) and not at.has("mount") and below in cells(other,at,"floor_cells"):supported=true;break
		if not supported:return data.display_name+"下方没有地面或平整支撑面。"
	return ""

static func distance_problem(layout: Dictionary) -> String:
	for kind in layout:
		if layout[kind]==null or not DEFINITIONS.has(kind):continue
		var data: Resource=DEFINITIONS[kind]
		for rule in data.distance_rules:
			var matches:=false
			for other in layout:
				if other==kind or layout[other]==null or not DEFINITIONS.has(other):continue
				if rule.target_type=="furniture" and base_kind(other)!=rule.target:continue
				if rule.target_type=="effect" and rule.target not in DEFINITIONS[other].effects:continue
				if int(layout[kind].car)!=int(layout[other].car):continue
				var a:=placement_rect(kind,layout[kind]);var b:=placement_rect(other,layout[other])
				var gap:=Vector2(maxf(0,maxf(a.position.x-b.end.x,b.position.x-a.end.x)),maxf(0,maxf(a.position.y-b.end.y,b.position.y-a.end.y)))/CELL_SIDE
				if (gap.length()<=float(rule.distance)+0.0001 if rule.relation=="require" else gap.length()<float(rule.distance)-0.0001):matches=true
			if rule.relation=="require" and not matches:return data.display_name+"需要在 %s 格内靠近 %s。" % [rule.distance,rule.target]
			if rule.relation=="exclude" and matches:return data.display_name+"必须远离 %s 至少 %s 格。" % [rule.target,rule.distance]
	return ""


static func add_missing_layout(layout: Dictionary, count: int) -> Dictionary:
	var result:=copy_layout(layout)
	for kind in IDS:
		if layout.has(kind):continue
		result[kind]=null
		var data: Resource=DEFINITIONS[kind]
		if data.default_placement==null or not data.default_owned:continue
		var preferred: Dictionary=data.default_placement
		var candidates: Array[Dictionary]=[]
		for car in range(count):
			for y in range(GRID_SIZE.y-data.grid_size.y+1):
				for x in range(GRID_SIZE.x-data.grid_size.x+1):candidates.append({"car":car,"x":x,"y":y})
		candidates.sort_custom(func(a,b):return placement_distance(a,preferred)<placement_distance(b,preferred))
		for candidate in candidates:
			var blocked:=false
			for other in result:
				if other!=kind and result[other]!=null and overlaps(kind,candidate,other,result[other]):blocked=true;break
			if blocked:continue
			var trial:=result.duplicate(true);trial[kind]=candidate
			if support_problem(kind,candidate,trial).is_empty() and distance_problem(trial).is_empty():result[kind]=candidate;break
	return result


static func is_on_ground(cell: Vector2i) -> bool:
	return absf(GRID_ORIGIN.y+(cell.y+1)*CELL_SIDE-GROUND_EDGE_Y)<0.001


static func occupancy_bounds(id: String) -> Rect2i:
	var occupied: Array[Vector2i]=cells(id,{"x":0,"y":0},"floor_cells")+cells(id,{"x":0,"y":0},"wall_cells")
	if occupied.is_empty():return Rect2i(Vector2i.ZERO,DEFINITIONS[id].grid_size)
	var left:=occupied[0];var right:=occupied[0]+Vector2i.ONE
	for cell in occupied:left=left.min(cell);right=right.max(cell+Vector2i.ONE)
	return Rect2i(left,right-left)


static func placement_distance(at: Dictionary, preferred: Dictionary) -> float:
	return pow(float(at.car)-float(preferred.car),2)*10000+Vector2(at.x,at.y).distance_squared_to(Vector2(preferred.x,preferred.y))+pow(float(at.get("mount",0))-float(preferred.get("mount",0)),2)
