extends RefCounted
const Content = preload("res://scripts/content/content_registry.gd")
const Item = preload("res://scripts/items/item_definition.gd")
static var definitions: Dictionary = {}
static var aliases: Dictionary = {}
static func reload() -> void:
	definitions.clear();aliases.clear()
	for data in Content.read_json("res://content/items.json").get("items",[]):
		var key: String = data.get("runtime_id",data.id)
		definitions[key]=data;aliases[data.id]=key;aliases[key]=key
		for old in data.get("aliases",[]):aliases[old]=key
static func definition(id: String) -> Dictionary:
	if definitions.is_empty(): reload()
	return definitions.get(runtime_id(id),{})
static func runtime_id(id: String) -> String:
	if definitions.is_empty():reload()
	return aliases.get(id,id)
static func item_weight(weights: Dictionary, id: String) -> float:
	var current:String=definition(id).get("id",id)
	if weights.has(current):return float(weights[current])
	for key in weights:
		if runtime_id(key)==runtime_id(id):return float(weights[key])
	return 0.0
static func resources() -> Dictionary:
	reload()
	var result := {}
	for id in definitions: result[id] = Item.from_data(definitions[id])
	for alias in aliases:result[alias]=result[aliases[alias]]
	return result
static func in_category(category: String) -> Array:
	if definitions.is_empty(): reload()
	var result := []
	for id in definitions:
		var data: Dictionary = definitions[id]
		if data.get("category") == category and data.get("enabled",true) and not data.get("deleted",false): result.append(id)
	return result
