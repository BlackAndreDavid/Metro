class_name MetroItem
extends Resource
## Storable objects have inventory orientation independent of furniture pose.
@export var id := ""
@export var display_name := ""
@export var inventory_size := Vector2i.ONE
@export_file("*.png") var texture_path := ""
@export var furniture_kind := ""
var _texture: Texture2D
var texture: Texture2D:
	get:
		if _texture == null:
			_texture = load(texture_path) as Texture2D
		return _texture
func footprint(rotated: bool = false) -> Vector2i:
	return Vector2i(inventory_size.y, inventory_size.x) if rotated else inventory_size
