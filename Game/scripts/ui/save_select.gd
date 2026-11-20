extends Control

var message: Label
var rows: VBoxContainer
var legacy_box: VBoxContainer

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
	rows=VBoxContainer.new();rows.name="SaveRows";box.add_child(rows)
	refresh_rows()
	message = Label.new()
	box.add_child(message)
	if FileAccess.file_exists(GameSession.legacy_path()):
		legacy_box=VBoxContainer.new();box.add_child(legacy_box)
		var legacy := Button.new()
		legacy.text = "读取旧版单存档"
		legacy.pressed.connect(func():
			var state := GameSession.State.new()
			if not state.load_cabin(GameSession.legacy_path(), GameSession.Rail.STATIONS.keys()):
				message.text = "旧存档无法读取，文件已保留。"
				return
			GameSession.active_save_path = GameSession.legacy_path()
			enter_game())
		legacy_box.add_child(legacy)
		var repair_legacy:=Button.new();repair_legacy.text="修复旧版单存档";repair_legacy.pressed.connect(repair_dialog.bind(GameSession.legacy_path()));legacy_box.add_child(repair_legacy)
		var delete_legacy:=Button.new();delete_legacy.text="删除旧版单存档";delete_legacy.pressed.connect(delete_dialog.bind(GameSession.legacy_path(),"旧版单存档"));legacy_box.add_child(delete_legacy)
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
		message.text = "存档暂时无法读取，原文件已保留。可以尝试备份修复，或恢复改动前的物品定义。"
		return
	enter_game()

func enter_game() -> void:
	var err := get_tree().change_scene_to_file("res://scenes/game/home.tscn")
	if err != OK:
		message.text = "场景加载失败：" + error_string(err)

func refresh_rows() -> void:
	if is_instance_valid(legacy_box):legacy_box.visible=FileAccess.file_exists(GameSession.legacy_path())
	for child in rows.get_children():rows.remove_child(child);child.queue_free()
	for slot in range(1, 4):
		var info := GameSession.slot_info(slot)
		var row := HBoxContainer.new()
		row.name="Slot%d" % slot;rows.add_child(row)
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
			label.text = "栏位 %d · 暂时无法读取（原文件保留）" % slot
			button.text = "无法读取"
			button.disabled = true
		else:
			label.text = "%d · %s · 第 %d 天 · %s" % [slot, info.name, info.day, info.station]
			button.text = "读取存档"
			button.pressed.connect(load_slot.bind(slot))
		if not info.is_empty():
			var remove:=Button.new();remove.name="Delete";remove.text="删除";remove.pressed.connect(delete_dialog.bind(GameSession.slot_path(slot),"栏位 %d" % slot));row.add_child(remove)
			if info.get("invalid",false):
				var repair:=Button.new();repair.name="Repair";repair.text="尝试修复";repair.pressed.connect(repair_dialog.bind(GameSession.slot_path(slot)));row.add_child(repair)

func delete_dialog(path: String, caption: String) -> void:
	var dialog:=ConfirmationDialog.new();dialog.name="DeleteSaveConfirmation";dialog.title="确认删除存档"
	dialog.dialog_text="确定删除%s？栏位将清空。文件会移入 saves/deleted，可手动恢复。" % caption
	dialog.get_ok_button().text="确认删除";dialog.get_cancel_button().text="取消";dialog.exclusive=true
	dialog.confirmed.connect(func():
		var err:=GameSession.delete_save(path)
		message.text="存档已删除，文件保留在 deleted 文件夹。" if err==OK else "删除失败："+error_string(err)
		refresh_rows();dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free);add_child(dialog);dialog.popup_centered()

func repair_dialog(path: String) -> void:
	var dialog:=ConfirmationDialog.new();dialog.name="RepairSaveConfirmation";dialog.title="备份并尝试修复"
	dialog.dialog_text="将备份原文件，按当前物品占位重新整理背包与柜子，并清理失效的当前订单。缺少定义或空间不足时停止，不丢弃物品。"
	dialog.get_ok_button().text="备份并修复";dialog.confirmed.connect(func():
		var result:Dictionary=GameSession.repair_save(path)
		message.text=str(result.get("error","")) if result.has("error") else "修复成功："+str(result.notes)+"\n备份："+str(result.backup)
		refresh_rows();dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free);add_child(dialog);dialog.popup_centered()
