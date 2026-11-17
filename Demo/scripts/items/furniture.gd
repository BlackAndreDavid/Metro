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
	if data.id == "screen":
		var info := Label.new()
		info.name = "StationInfo"
		info.text = "%s\n%s\n%s" % [home.state.station, home.state.date_text(), home.state.weather()]
		info.position = Vector2(8, 8)
		info.size = size - Vector2(16, 16)
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		info.add_theme_font_size_override("font_size", 13)
		info.add_theme_color_override("font_color", Color("322d3d"))
		add_child(info)

func use() -> void:
	if home.screen != "cabin":
		return
	if editing:
		home.store_home_furniture(definition.id)
	else:
		definition.perform(home)
