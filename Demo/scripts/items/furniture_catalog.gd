extends RefCounted
## Shared placement schema used by state, resources and the rendered carriage.
const FLOOR_SLOTS := 6
const HANGING_SLOTS := 4
const SLOTS_PER_CARRIAGE := FLOOR_SLOTS + HANGING_SLOTS
# The first point reproduces Screen.aseprite's original (28,22) placement.
# Actual railing hooks in the art are at x=42,101,144,218;
# their tips are at y=22,22,20,21. The screen is centered below each tip.
const HANGING_ORIGINS := [Vector2(28, 22), Vector2(87, 22), Vector2(130, 20), Vector2(204, 21)]
const IDS := ["bed", "computer", "locker", "door", "screen"]
const DEFAULT_LAYOUT := {"bed": -1, "computer": -1, "locker": 2, "door": 3, "screen": 6}
const DEFINITIONS := {
	"bed": preload("res://resources/furniture/bed.tres"),
	"computer": preload("res://resources/furniture/computer.tres"),
	"locker": preload("res://resources/furniture/locker.tres"),
	"door": preload("res://resources/furniture/door.tres"),
	"screen": preload("res://resources/furniture/screen.tres"),
}

static func footprint(kind: String, slot: int, count: int) -> Array[int]:
	var cells: Array[int] = []
	if not DEFINITIONS.has(kind) or slot < 0 or slot >= count * SLOTS_PER_CARRIAGE:
		return cells
	var span: int = DEFINITIONS[kind].slot_span
	var local := slot % SLOTS_PER_CARRIAGE
	var hanging: bool = DEFINITIONS[kind].placement_type == "hanging"
	var start := FLOOR_SLOTS if hanging else 0
	var end := SLOTS_PER_CARRIAGE if hanging else FLOOR_SLOTS
	if local < start or local + span > end:
		return cells
	for index in range(span):
		cells.append(slot + index)
	return cells
