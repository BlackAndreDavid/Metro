class_name MetroFurniture
extends "res://scripts/items/highlightable_item.gd"
signal selection_requested(kind: String)
var definition: Resource
var home: Control
var build_controller: Node
var is_selected := false

func configure(data: Resource, owner_home: Control, surface: Control) -> void:
	definition = data
	home = owner_home
	var building: bool = build_controller != null and build_controller.active
	is_selected = building and build_controller.selected_id == data.id
	set_item(data.texture, "选择" + data.display_name if building else data.function_text, surface)
	set_highlighted(false)
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
	if build_controller != null and build_controller.active:
		selection_requested.emit(definition.id)
	else:
		definition.perform(home)

func set_highlighted(value: bool) -> void:
	super.set_highlighted(value or is_selected)
	# Selection keeps the outline; only the hovered object shows a caption.
	caption.visible = value
