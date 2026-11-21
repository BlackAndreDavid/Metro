extends PanelContainer
var home: Control
var icon: TextureRect
var caption: Label
func configure(controller: Control) -> void:
	home = controller
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var column := HBoxContainer.new();add_child(column)
	icon = TextureRect.new();icon.custom_minimum_size = Vector2(40,40);icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;icon.mouse_filter = Control.MOUSE_FILTER_IGNORE;column.add_child(icon)
	caption = Label.new();caption.clip_text=true;caption.custom_minimum_size=Vector2(160,38);caption.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER;caption.add_theme_font_size_override("font_size",12);caption.mouse_filter = Control.MOUSE_FILTER_IGNORE;column.add_child(caption)
	refresh()
func refresh() -> void:
	if home == null: return
	var entry: Dictionary = home.state.active_item
	icon.texture = null if entry.is_empty() else home.state.ITEM_DEFINITIONS[entry.kind].texture
	caption.text = "主动 [空格]\n"+("未装备" if entry.is_empty() else home.state.item_name(entry.kind))
	tooltip_text = "从仓库或背包拖入装备，拖回储物格可卸下；出发后按空格使用。" if home.screen=="gear" else "打开背包后拖入道具，或从这里拖回背包；空格使用。"
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if inventory_open() and home.selection.get("source") in ["bag","preparation"]: home.equip_selected_active()
		elif home.screen=="surface" and not inventory_open(): home.use_active_item()
		accept_event()
func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("source") in (["bag","preparation"] if home.screen=="gear" else ["bag"]) and inventory_open()
func _drop_data(_at: Vector2, data: Variant) -> void:
	home.equip_selected_active(int(data.id),str(data.source))
func _get_drag_data(_at: Vector2) -> Variant:
	if home.state.active_item.is_empty() or not inventory_open(): return null
	home.select_cargo("active",home.state.active_item.id)
	var preview := Label.new();preview.text = home.state.item_name(home.state.active_item.kind);set_drag_preview(preview)
	return home.selection

func inventory_open() -> bool:
	return home.screen=="gear" or (home.screen=="surface" and home.view.has_method("set_pack_open") and home.view.pack_open)
