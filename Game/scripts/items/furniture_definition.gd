extends Resource
@export var id := ""
@export var display_name := ""
@export var function_text := ""
@export_enum("rest", "news", "gear", "locker", "map", "preparation", "none") var action := "rest"
@export_file("*.png") var texture_path := ""
# Keep save/placement validation independent of texture import order.
var texture: Texture2D:
	get:
		var source := load(texture_path) as Texture2D
		if id == "preparation":
			var image := source.get_image()
			return ImageTexture.create_from_image(image.get_region(image.get_used_rect()))
		return source
@export var fill_grid := true
@export var grid_size := Vector2i(2, 2)
@export_enum("floor", "hanging") var placement_type := "floor"
# Offset of the cropped image in the original 243x108 carriage canvas.
@export var source_origin := Vector2.ZERO

func perform(home: Control) -> void:
	if action == "none":
		return
	if action == "map":
		home.show_map()
	else:
		home.use_hotspot(action)
