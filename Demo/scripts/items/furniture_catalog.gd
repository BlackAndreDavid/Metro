extends RefCounted
## Grid placement is model data; hanging planes never occupy the floor grid.
const GRID_SIZE := Vector2i(34, 12)
const CELL_SIZE := Vector2(26, 26)
const GRID_ORIGIN := Vector2(174, 212)
const CARRIAGE_PITCH := 972.0
const MOUNT_SIZE := Vector2i(2, 2)
const HANGING_ORIGINS := [Vector2(28, 22), Vector2(87, 22), Vector2(130, 20), Vector2(204, 21)]
const IDS := ["bed", "computer", "locker", "door", "screen"]
const DEFINITIONS := {
	"bed": preload("res://resources/furniture/bed.tres"),
	"computer": preload("res://resources/furniture/computer.tres"),
	"locker": preload("res://resources/furniture/locker.tres"),
	"door": preload("res://resources/furniture/door.tres"),
	"screen": preload("res://resources/furniture/screen.tres"),
}

static func floor_rect(car: int) -> Rect2:
	return Rect2(GRID_ORIGIN + Vector2(car * CARRIAGE_PITCH, 0), Vector2(GRID_SIZE) * CELL_SIZE)

static func mount_rect(car: int, mount: int) -> Rect2:
	var hook: Vector2 = HANGING_ORIGINS[mount] + Vector2(14, 0)
	return Rect2(Vector2(154 + car * CARRIAGE_PITCH, 144) + hook * 4 - Vector2(CELL_SIZE.x, 0), Vector2(MOUNT_SIZE) * CELL_SIZE)

static func placement_rect(kind: String, placement: Dictionary) -> Rect2:
	var plane := mount_rect(int(placement.car), int(placement.mount)) if placement.has("mount") else floor_rect(int(placement.car))
	return Rect2(plane.position + Vector2(placement.x, placement.y) * CELL_SIZE, Vector2(DEFINITIONS[kind].grid_size) * CELL_SIZE)

static func default_placement(kind: String, car: int = 0) -> Dictionary:
	match kind:
		"door": return {"car": car, "x": 9, "y": 0}
		"locker": return {"car": car, "x": 0, "y": 0}
		"computer": return {"car": car, "x": 22, "y": 10}
		"bed": return {"car": car, "x": 28, "y": 11}
		"screen": return {"car": car, "mount": 0, "x": 0, "y": 0}
	return {}

static func initial_layout() -> Dictionary:
	return {"bed": null, "computer": null, "locker": default_placement("locker"), "door": default_placement("door"), "screen": default_placement("screen")}

static func valid_placement(kind: String, p: Variant, count: int, legacy: bool = false) -> bool:
	if not DEFINITIONS.has(kind) or not p is Dictionary:
		return false
	var hanging: bool = DEFINITIONS[kind].placement_type == "hanging"
	if p.size() != (4 if hanging else 3):
		return false
	for key in ["car", "x", "y"]:
		if not integer(p.get(key)):
			return false
	if p.car < 0 or p.car >= count:
		return false
	var bounds := MOUNT_SIZE if hanging else (Vector2i(16, 12) if legacy else GRID_SIZE)
	if hanging and (not integer(p.get("mount")) or p.mount < 0 or p.mount >= HANGING_ORIGINS.size()):
		return false
	return Rect2i(Vector2i.ZERO, bounds).encloses(Rect2i(Vector2i(int(p.x), int(p.y)), footprint(kind, legacy)))

static func overlaps(a_kind: String, a: Dictionary, b_kind: String, b: Dictionary, legacy: bool = false) -> bool:
	if int(a.car) != int(b.car) or a.has("mount") != b.has("mount"):
		return false
	if a.has("mount") and int(a.mount) != int(b.mount):
		return false
	return Rect2i(Vector2i(int(a.x), int(a.y)), footprint(a_kind, legacy)).intersects(Rect2i(Vector2i(int(b.x), int(b.y)), footprint(b_kind, legacy)))

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
		result[kind] = canonical(layout[kind]) if layout[kind] != null else null
	return result

static func footprint(kind: String, legacy: bool = false) -> Vector2i:
	if legacy and kind == "locker": return Vector2i(2, 2)
	if legacy and kind == "door": return Vector2i(4, 12)
	return DEFINITIONS[kind].grid_size

static func migrate_rectangular_layout(layout: Dictionary) -> Dictionary:
	var result := {}
	for kind in IDS: result[kind] = null
	# Place full-height furniture first, then preserve nearby positions of smaller items.
	for kind in ["screen", "door", "locker", "computer", "bed"]:
		if layout[kind] == null: continue
		var old: Dictionary = canonical(layout[kind])
		if kind == "screen":
			result[kind] = old
			continue
		var desired := Vector2(roundf(old.x * 56.0 / CELL_SIZE.x), old.y)
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
