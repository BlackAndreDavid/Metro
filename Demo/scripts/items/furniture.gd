class_name MetroFurniture
extends "res://scripts/items/highlightable_item.gd"
signal selection_requested(kind: String)
var definition: Resource
var home: Control
var build_controller: Node
var is_selected := false

func configure(data: Resource, owner_home: Control, surface: Control) -> void:
	rotation = 0.0 # Storage rotation never becomes a furniture rotation.
	definition = data
	home = owner_home
	var building: bool = build_controller != null and build_controller.active
	is_selected = building and build_controller.selected_id == data.id
	set_item(data.texture, data.display_name + " · 长按1秒移动" if building else data.function_text, surface)
	set_highlighted(false)
	activated.connect(use)
	if data.id == "screen":
		var info := Label.new()
		info.name = "StationInfo"
		info.text = "%s\n%s\n%s" % [home.state.station, home.state.date_text(), home.state.weather()]
		info.position = Vector2(4, 4)
		info.size = size - Vector2(8, 8)
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		info.add_theme_font_size_override("font_size", 13)
		info.add_theme_color_override("font_color", Color("322d3d"))
		add_child(info)

func use() -> void:
	if build_controller != null and build_controller.active:
		selection_requested.emit(definition.id)
	elif home.screen == "cabin":
		definition.perform(home)

func set_highlighted(value: bool) -> void:
	super.set_highlighted(value or is_selected)
	# Selection keeps the outline; only the hovered object shows a caption.
	caption.visible = value

func _gui_input(event: InputEvent) -> void:
	if build_controller != null and build_controller.active and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			grab_focus()
			build_controller.press_furniture(definition.id, event.global_position)
		accept_event()
		return
	super._gui_input(event)
