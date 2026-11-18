extends RefCounted
const Content = preload("res://scripts/content/content_registry.gd")
const Item = preload("res://scripts/items/item_definition.gd")
static var definitions: Dictionary = {}
static func reload() -> void:
	definitions.clear()
	for data in Content.read_json("res://content/items.json").get("items",[]): definitions[data.id] = data
static func definition(id: String) -> Dictionary:
	if definitions.is_empty(): reload()
	return definitions.get(id,{})
static func resources() -> Dictionary:
	reload()
	var result := {}
	for id in definitions: result[id] = Item.from_data(definitions[id])
	return result
static func in_category(category: String) -> Array:
	if definitions.is_empty(): reload()
	var result := []
	for id in definitions:
		var data: Dictionary = definitions[id]
		if data.get("category") == category and data.get("enabled",true) and not data.get("deleted",false): result.append(id)
	return result
