extends Control

var message: Label

func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color("121521")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(660, 0)
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)
	var title := Label.new()
	title.text = "选择存档 · 三个基地"
	title.add_theme_font_size_override("font_size", 32)
	box.add_child(title)
	for slot in range(1, 4):
		var info := GameSession.slot_info(slot)
		var row := HBoxContainer.new()
		box.add_child(row)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = "栏位 %d · 空存档" % slot
		row.add_child(label)
		var button := Button.new()
		button.custom_minimum_size = Vector2(140, 52)
		row.add_child(button)
		if info.is_empty():
			button.text = "创建基地"
			button.pressed.connect(create_dialog.bind(slot))
		elif info.get("invalid", false):
			label.text = "栏位 %d · 存档损坏（已保留）" % slot
			button.text = "无法读取"
			button.disabled = true
		else:
			label.text = "%d · %s · 第 %d 天 · %s" % [slot, info.name, info.day, info.station]
			button.text = "读取存档"
			button.pressed.connect(load_slot.bind(slot))
	message = Label.new()
	box.add_child(message)
	if FileAccess.file_exists(GameSession.legacy_path()):
		var legacy := Button.new()
		legacy.text = "读取旧版单存档"
		legacy.pressed.connect(func():
			var state := GameSession.State.new()
			if not state.load_cabin(GameSession.legacy_path(), GameSession.Rail.STATIONS.keys()):
				message.text = "旧存档无法读取，文件已保留。"
				return
			GameSession.active_save_path = GameSession.legacy_path()
			enter_game())
		box.add_child(legacy)
	var back := Button.new()
	back.text = "返回主菜单"
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn"))
	box.add_child(back)

func create_dialog(slot: int) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "创建基地 · 栏位 %d" % slot
	dialog.dialog_text = "基地名称（1–24 字）"
	var name_input := LineEdit.new()
	name_input.max_length = 24
	name_input.placeholder_text = "输入基地名称"
	name_input.position = Vector2(12, 52)
	name_input.custom_minimum_size = Vector2(330, 40)
	dialog.min_size = Vector2i(360, 160)
	dialog.add_child(name_input)
	dialog.get_ok_button().disabled = true
	name_input.text_changed.connect(func(value): dialog.get_ok_button().disabled = value.strip_edges().is_empty())
	dialog.confirmed.connect(func():
		var err := GameSession.create_slot(slot, name_input.text)
		if err != OK:
			message.text = "创建失败：" + error_string(err)
		else:
			load_slot(slot)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()
	name_input.grab_focus()

func load_slot(slot: int) -> void:
	if not GameSession.select_slot(slot):
		message.text = "存档读取失败，文件已保留。"
		return
	enter_game()

func enter_game() -> void:
	var err := get_tree().change_scene_to_file("res://scenes/game/cabin.tscn")
	if err != OK:
		message.text = "场景加载失败：" + error_string(err)
