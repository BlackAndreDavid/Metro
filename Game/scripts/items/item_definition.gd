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
var occupancy: Array[Vector2i] = []
var texture_binding: Dictionary = {}
var _texture: Texture2D
var texture: Texture2D:
	get:
		if _texture == null:
			_texture = preload("res://scripts/commerce/customer_catalog.gd").load_texture(texture_path) if not texture_path.is_empty() else null
		return _texture
func footprint(rotated: bool = false) -> Vector2i:
	return Vector2i(inventory_size.y, inventory_size.x) if rotated else inventory_size

func cell_offsets(rotated: bool = false, mirrored: bool = false) -> Array[Vector2i]:
	var source: Array[Vector2i] = occupancy.duplicate()
	if source.is_empty():
		for y in range(inventory_size.y):
			for x in range(inventory_size.x): source.append(Vector2i(x,y))
	var result: Array[Vector2i] = []
	for cell in source:
		if mirrored:cell.x = inventory_size.x-1-cell.x
		result.append(Vector2i(inventory_size.y-1-cell.y,cell.x) if rotated else cell)
	return result

static func from_data(data: Dictionary) -> Resource:
	var result = load("res://scripts/items/item_definition.gd").new()
	result.id = data.get("runtime_id",data.id)
	result.display_name = data.get("name",data.id)
	result.inventory_size = Vector2i(int(data.get("width",1)),int(data.get("height",1)))
	for cell in data.get("cells",[]):result.occupancy.append(Vector2i(int(cell[0]),int(cell[1])))
	result.texture_binding = data.get("texture_binding",{}).duplicate(true)
	result.texture_path = data.get("texture","")
	result.price = float(data.get("price",0))
	result.furniture_kind = data.get("furniture_kind","computer" if result.id=="computer" else "")
	result.category = data.get("category","none")
	result.rarity = int(data.get("rarity",0))
	return result
