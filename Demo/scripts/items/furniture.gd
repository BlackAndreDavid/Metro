extends "res://scripts/items/highlightable_item.gd"
var definition: Resource
var home: Control
var editing := false

func configure(data: Resource, owner_home: Control, surface: Control, arrange: bool) -> void:
	definition = data
	home = owner_home
	editing = arrange
	set_item(data.texture, "收纳" + data.display_name if arrange else data.function_text, surface)
	activated.connect(use)

func use() -> void:
	if home.screen != "cabin":
		return
	if editing:
		home.store_home_furniture(definition.id)
	else:
		definition.perform(home)
