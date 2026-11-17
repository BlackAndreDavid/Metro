extends Resource
@export var id := ""
@export var display_name := ""
@export var function_text := ""
@export_enum("rest", "news", "gear", "locker", "map") var action := "rest"
@export_file("*.png") var texture_path := ""
# Keep save/placement validation independent of texture import order.
var texture: Texture2D:
	get:
		return load(texture_path) as Texture2D
@export_range(1, 2) var slot_span := 1
@export_enum("floor", "hanging") var placement_type := "floor"
# Offset of the cropped image in the original 243x108 carriage canvas.
@export var source_origin := Vector2.ZERO

func perform(home: Control) -> void:
	if action == "map":
		home.show_map()
	else:
		home.use_hotspot(action)
