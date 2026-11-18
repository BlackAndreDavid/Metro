class_name MetroItem
extends Resource
## Storable objects have inventory orientation independent of furniture pose.
@export var id := ""
@export var display_name := ""
@export var inventory_size := Vector2i.ONE
@export_file("*.png") var texture_path := ""
@export var furniture_kind := ""
@export var price := 0.0
@export var category := "none"
@export var rarity := 0
var _texture: Texture2D
var texture: Texture2D:
	get:
		if _texture == null:
			_texture = preload("res://scripts/commerce/customer_catalog.gd").load_texture(texture_path) if not texture_path.is_empty() else null
		return _texture
func footprint(rotated: bool = false) -> Vector2i:
	return Vector2i(inventory_size.y, inventory_size.x) if rotated else inventory_size

static func from_data(data: Dictionary) -> Resource:
	var result = load("res://scripts/items/item_definition.gd").new()
	result.id = data.id
	result.display_name = data.get("name",data.id)
	result.inventory_size = Vector2i(int(data.get("width",1)),int(data.get("height",1)))
	result.texture_path = data.get("texture","")
	result.price = float(data.get("price",0))
	result.furniture_kind = "computer" if result.id == "computer" else data.get("furniture_kind","")
	result.category = data.get("category","none")
	result.rarity = int(data.get("rarity",0))
	return result
