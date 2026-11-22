extends "res://scripts/ui/ui_builder.gd"

const State = preload("res://scripts/cabin_state.gd")
const Rail = preload("res://scripts/cabin_map.gd")
const CargoGrid = preload("res://scripts/cargo_grid.gd")
const Content = preload("res://scripts/content/content_registry.gd")
const SurfaceBlock = preload("res://scripts/surface_block.gd")
const SurfaceMinimap = preload("res://scripts/surface_minimap.gd")
const AutoRepair = preload("res://scripts/auto_repair.gd")
const BACKDROP = preload("res://scenes/game/home_backdrop.tscn")
const EXPLORATION = preload("res://scenes/game/exploration.tscn")
const SETTINGS = preload("res://scenes/ui/settings_panel.tscn")

const LOOT_SPOTS := [Vector2(114, 348), Vector2(266, 380), Vector2(400, 335), Vector2(563, 397), Vector2(681, 335), Vector2(710, 455)]
const RADIATION := ["", "低", "中", "高"]

var state := State.new()
var font: SystemFont
var view: Control
var screen := ""
var selection: Dictionary = {}
var grids: Array[Control] = []
var status: Label
var time_label: Label
var map_scene: Control
var trade_supplies := false
var loadout: Dictionary = {}
var save_path: String
var pointer_position := Vector2.ZERO
var surface_block: SurfaceBlock
var surface_pack: Control
var surface_location: Label
var surface_prompt: Label
var flashlight_button: Button
var battery_panel: Control
var battery_slot_open := false
var wrench_button: Button
var vehicle_panel: Control
var home_backdrop: Control
var settings_panel: CanvasLayer
var settings_opened_ms := 0
var settings_was_paused := false
var focused_carriage := 0
const Construction = preload("res://scripts/construction/construction_mode.gd")
const CONSTRUCTION_SCENE = preload("res://scenes/construction/construction_mode.tscn")
var construction: Construction

func _ready() -> void:
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	var ui_theme := Theme.new()
	ui_theme.default_font = font
	theme = ui_theme
	construction = CONSTRUCTION_SCENE.instantiate()
	construction.configure(self)
	var directory := OS.get_executable_path().get_base_dir() if OS.has_feature("template") else ProjectSettings.globalize_path("res://")
	save_path = directory.path_join("saves/cabin_slot.json")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--save-file="):
			save_path = argument.trim_prefix("--save-file=")
	if not GameSession.active_save_path.is_empty():
		save_path = GameSession.active_save_path
	var tester:=get_node_or_null("/root/MetroTesterBridge")
	if tester!=null and tester.testing and not save_path.begins_with(tester.session_directory):save_path=tester.session_directory.path_join("live.json")
	if get_meta("content_preview",false): save_path = "user://content_preview/session_%d.json" % Time.get_ticks_usec()
	var has_save := FileAccess.file_exists(save_path)
	var loaded := state.load_cabin(save_path, Rail.STATIONS.keys())
	if not state.game_over_reason.is_empty():
		show_game_over()
	elif not FileAccess.file_exists(save_path + ".rules_seen"):
		show_rules("读取存档失败，已开始新游戏。" if has_save and not loaded else "")
	else:
		show_cabin("读取存档失败，已开始新游戏。" if has_save and not loaded else "")

func _process(delta: float) -> void:
	if screen == "surface" and not check_trip_timeout():
		update_trip_clock()
		var charge := state.installed_charge
		var was_lit := state.flashlight_on
		if is_instance_valid(surface_block): surface_block.auto_manage_flashlight()
		else: state.flashlight_on = false
		state.tick_flashlight(delta)
		if was_lit != state.flashlight_on:
			refresh_surface_light()
			report("光照充足，手电已自动关闭。" if state.installed_charge > 0 else "手电筒电池已耗尽。")
		elif charge != state.installed_charge:
			refresh_equipment()

func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		pointer_position = event.position
	if event is InputEventMouseButton and event.pressed and not selection.is_empty():
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			rotate_selection()
			get_viewport().set_input_as_handled()
			return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F11:
		var window := get_window()
		window.mode = Window.MODE_MAXIMIZED if window.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN
	elif event.physical_keycode == KEY_E and screen == "surface" and is_instance_valid(surface_block):
		if not check_trip_timeout() and not is_instance_valid(vehicle_panel):
			surface_block.interact()
	elif event.physical_keycode==KEY_B and screen=="gear":
		view.toggle_bag();get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_B and screen == "surface" and view.has_method("toggle_pack"):
		view.toggle_pack()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode == KEY_SPACE and screen == "surface":
		use_active_item()
		get_viewport().set_input_as_handled()
	elif event.physical_keycode in [KEY_1, KEY_KP_1] and screen == "surface":
		if not check_trip_timeout():
			var problem := ""
			if not is_instance_valid(surface_block) or surface_block.is_bright():
				state.flashlight_on = false
				problem = "当前光照充足，手电无需开启。"
			else: problem = state.toggle_flashlight()
			refresh_surface_light()
			report(problem)
	elif event.keycode == KEY_ESCAPE and is_instance_valid(vehicle_panel):
		close_vehicle()
	elif event.keycode == KEY_ESCAPE and not selection.is_empty():
		clear_selection()
	elif event.keycode == KEY_F and not selection.is_empty():
		flip_selection()
	elif event.keycode == KEY_R and not selection.is_empty():
		rotate_selection()
	elif event.keycode == KEY_ESCAPE and screen == "surface" and view.has_method("set_pack_open") and view.pack_open:
		view.set_pack_open(false)
	elif event.keycode == KEY_ESCAPE and screen == "rules":
		dismiss_rules()
	elif event.keycode == KEY_ESCAPE and screen not in ["cabin", "surface", "game_over"]:
		show_cabin()
	else:
		return
	get_viewport().set_input_as_handled()

func cabin_art() -> void:
	home_backdrop = BACKDROP.instantiate()
	# Modal pages keep the whole cabin, including raised rails/furniture, below UI.
	home_backdrop.z_index=0 if screen=="cabin" else -10
	view.add_child(home_backdrop)
	home_backdrop.interaction_enabled = screen == "cabin"
	home_backdrop.configure_world(self)

func begin_page(kind: String, scene: PackedScene = null) -> void:
	home_backdrop = null
	if is_instance_valid(view):
		view.hide()
		remove_child(view)
		view.queue_free()
	if kind != "surface":
		surface_block = null
		battery_slot_open = false
		vehicle_panel = null
	if is_instance_valid(construction):
		construction.on_page_changed(kind)
	screen = kind
	selection = {}
	grids.clear()
	status = null
	time_label = null
	view = scene.instantiate() if scene != null else Control.new()
	if scene == null:
		view.name = kind.capitalize()
	view.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(view)
	# Keep page visuals and GUI hit testing beneath the persistent settings button.
	move_child(view, $SettingsButton.get_index())
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func report(message: String, color: Color = AMBER) -> void:
	if is_instance_valid(status):
		status.text = message
		status.add_theme_color_override("font_color", color)

func energy_text(amount: float) -> String:
	var rounded := snappedf(amount, 0.1)
	return str(roundi(rounded)) if is_equal_approx(rounded, roundf(rounded)) else str(rounded)

func car_power_text() -> String:
	return "%s / %d 度" % [energy_text(state.car_power), State.CAR_CAPACITY]

func power(parent: Control, at: Vector2, title: String, value: String, tint: Color) -> void:
	plate(parent, Rect2(at, Vector2(232, 64)), Color("242135"), BORDER)
	plate(parent, Rect2(at, Vector2(3, 64)), tint)
	label(parent, title, Rect2(at + Vector2(15, 0), Vector2(75, 64)), 15, MUTED)
	label(parent, value, Rect2(at + Vector2(84, 0), Vector2(133, 64)), 20, tint, HORIZONTAL_ALIGNMENT_RIGHT)

func show_cabin(message: String = "") -> void:
	if is_instance_valid(map_scene) and map_scene.active:
		map_scene.exit(message)
		return
	begin_page("cabin")
	cabin_art()
	label(view, "终末地铁 · %s" % state.base_name, Rect2(32, 6, 560, 39), 30)
	label(view, "%s / %s / %s" % [state.station, state.date_text(), state.weather()], Rect2(34, 46, 560, 26), 17, MINT)
	power(view, Vector2(641, 8), "车内电源", car_power_text(), MINT)
	power(view, Vector2(889, 8), "账户余额", "%s 度" % energy_text(state.account), AMBER)
	var water := action(view, "已喝水" if state.drank_today else "喝水 · %d" % state.supply_count("water"),
		Rect2(32, 78, 122, 32), use_supply.bind("water"))
	water.disabled = state.drank_today
	var ration := action(view, "已进食" if state.ate_today else "进食 · %d" % state.supply_count("ration"),
		Rect2(164, 78, 122, 32), use_supply.bind("ration"))
	ration.disabled = state.ate_today
	var has_charger := state.has_charger(state.station)
	action(view, "充电站" if has_charger else "找充电站", Rect2(296, 78, 122, 32),
		show_charger.bind("") if has_charger else find_charger)
	action(view, "电池充电", Rect2(428, 78, 122, 32), show_battery_charger.bind(""))
	action(view, "汽修培训" if state.station == AutoRepair.STATION else "技能", Rect2(560, 78, 122, 32), show_skills.bind(""))
	var build_button := action(view, "装修", Rect2(692, 78, 122, 32), construction.enter)
	build_button.name = "BuildModeButton"
	build_button.visible = not construction.active
	if not construction.active:
		label(view, "%d 节车厢 · 行车 %d 度/站 · 每日 %s 度" % [state.carriage_count, state.travel_cost_per_stop(), energy_text(state.daily_power_cost())], Rect2(32, 116, 1100, 25), 15, MINT)
	if state.debt > 0:
		label(view, "欠费 %s 度" % energy_text(state.debt), Rect2(964, 82, 268, 32), 16, AMBER)
	if not message.is_empty():
		plate(view, Rect2(208, 647, 864, 38), Color("211f31e8"), BORDER)
		label(view, message, Rect2(222, 647, 836, 38), 16, MINT, HORIZONTAL_ALIGNMENT_CENTER)

	construction.refresh_ui()

func use_supply(kind: String) -> void:
	var problem := state.consume_supply(kind)
	var success := "今日已喝水。" if kind == "water" else "今日已进食。"
	show_cabin(success if problem.is_empty() else problem)

func show_skills(message: String = "") -> void:
	begin_page("skills")
	var panel := modal("技能树", Rect2(168, 94, 944, 530))
	var at_school := state.station == AutoRepair.STATION
	label(panel, "同济大学站 · 汽修培训", Rect2(24, 81, 470, 30), 18, MINT)
	label(panel, "账户余额 %s 度" % energy_text(state.account), Rect2(575, 81, 345, 30), 17, AMBER, HORIZONTAL_ALIGNMENT_RIGHT)
	for branch in range(4):
		var x := 24 + branch * 226
		var active := branch == 0
		plate(panel, Rect2(x, 124, 218, 44), Color("3e334c") if active else Color("292738"), AMBER if active else BORDER)
		if active:
			label(panel, "汽修  ·  %d 级" % state.auto_repair_level, Rect2(x, 124, 218, 44), 19, AMBER, HORIZONTAL_ALIGNMENT_CENTER)
		for index in range(AutoRepair.COURSES.size()):
			var level := index + 1
			var y := 181 + index * 91
			var learned := active and level <= state.auto_repair_level
			var available := active and level == state.auto_repair_level + 1
			var edge := MINT if learned else AMBER if available else BORDER
			plate(panel, Rect2(x + 108, y - 13, 2, 13), edge)
			plate(panel, Rect2(x, y, 218, 78), Color("322a40") if active else Color("292738"), edge)
			if not active:
				continue
			var course: Dictionary = AutoRepair.COURSES[index]
			label(panel, "%d 级 · %s" % [level, course.name], Rect2(x + 10, y + 3, 198, 24), 15, MINT if learned else TEXT)
			label(panel, AutoRepair.course_parts(course), Rect2(x + 10, y + 28, 198, 21), 13, MUTED)
			if available and at_school:
				var enroll := action(panel, "报名 · %d 度" % course.fee, Rect2(x + 10, y + 49, 198, 24), enroll_course.bind(level), true)
				enroll.add_theme_font_size_override("font_size", 13)
				enroll.disabled = state.account < course.fee
			else:
				var caption := "已掌握" if learned else "到同济大学站报名" if available else "需先学习上一级"
				label(panel, caption, Rect2(x + 10, y + 50, 198, 22), 12, MINT if learned else MUTED)
	status = label(panel, "", Rect2(24, 457, 896, 39), 16, AMBER)
	report(message)

func enroll_course(level: int) -> void:
	var problem := state.enroll_auto_repair(level)
	var message := "已掌握汽修 %d 级。" % level
	if level == 1:
		message += " 培训点已发放扳手，可在出站时携带。"
	show_skills(message if problem.is_empty() else problem)

func use_hotspot(kind: String) -> void:
	match kind:
		"locker": show_locker()
		"trade":
			trade_supplies = false
			show_trade()
		"rest": show_rest()
		"preparation": show_furniture_storage("preparation")
		"gear":
			loadout = {"heavy": false, "inventory_tools":true}
			state.sync_carried_tools()
			show_gear()
		"news":
			show_news()

func modal(title: String, bounds: Rect2, on_close: Callable = Callable()) -> Panel:
	cabin_art()
	overlay(view, Color("0d0b16ae"))
	var frame := plate(view, bounds, DARK, BORDER)
	label(frame, title, Rect2(24, 13, bounds.size.x - 130, 44), 28)
	action(frame, "关闭", Rect2(bounds.size.x - 88, 18, 64, 34), on_close if on_close.is_valid() else show_cabin.bind(""))
	plate(frame, Rect2(24, 66, bounds.size.x - 48, 1), BORDER)
	return frame

func show_rules(message: String) -> void:
	begin_page("rules")
	var panel := modal("简要规则", Rect2(302, 99, 676, 522), dismiss_rules)
	var rules := [
		["用电与欠费", "行车每站耗 %d 度，车厢每日结算耗 %d 度。充电、购物和租防护服时，余额不足可挂账。七号电池在车内充。" % [state.travel_cost_per_stop(), state.daily_power_cost()]],
		["限时探索", "每次出站限时 %d 秒。门旁预备仓库可拖拽携带工具，手电筒按 1 开关照明。" % state.trip_limit()],
		["超时赔偿", "超时丢失随身物品。普通防护服赔偿 300 度，加强型 500 度，余额不足记作欠费。"],
		["每日生存", "每天喝水、进食，睡觉时结算。连续两天未喝水或欠费、连续三天未进食都会结束本轮。"],
	]
	for index in range(rules.size()):
		var y := 83 + index * 89
		label(panel, rules[index][0], Rect2(24, y, 628, 25), 18, MINT)
		wrapped(panel, rules[index][1], Rect2(24, y + 28, 628, 53), 16, TEXT)
	if not message.is_empty():
		label(panel, message, Rect2(24, 440, 628, 21), 14, AMBER)
	action(panel, "开始游戏", Rect2(24, 466, 628, 41), dismiss_rules, true)

func dismiss_rules() -> void:
	DirAccess.make_dir_recursive_absolute(save_path.get_base_dir())
	var seen := FileAccess.open(save_path + ".rules_seen", FileAccess.WRITE)
	if seen != null:
		seen.store_string("seen\n")
		seen.close()
	show_cabin()

func show_charger(message: String = "") -> void:
	begin_page("charger")
	var panel := modal("车辆充电 · %s" % state.station, Rect2(300, 148, 680, 424))
	var supply := state.charger_stock(state.station)
	var limit := state.car_charge_limit()
	var service := "本站今日剩余 %s 度" % energy_text(supply)
	if state.is_blackout():
		service = "今日停电，充电站暂停。"
	label(panel, service, Rect2(24, 85, 632, 33), 21, MINT if supply > 0 else AMBER)
	label(panel, "车内电源  %s" % car_power_text(), Rect2(24, 132, 302, 31), 19)
	label(panel, "账户余额  %s 度" % energy_text(state.account), Rect2(340, 132, 316, 31), 19, AMBER)
	label(panel, "充入多少就扣多少，账户不足的部分记为欠费。",
		Rect2(24, 180, 632, 25), 15, MUTED)
	vehicle_charge_option(panel, "充入", 30.0, limit, Rect2(24, 223, 170, 44))
	vehicle_charge_option(panel, "充入", 100.0, limit, Rect2(206, 223, 178, 44))
	vehicle_charge_option(panel, "充到上限", limit, limit, Rect2(396, 223, 260, 44), true)
	label(panel, "待还欠费  %s 度" % energy_text(state.debt), Rect2(24, 300, 410, 36), 17, AMBER)
	action(panel, "查其他充电站", Rect2(474, 300, 182, 36), find_charger)
	status = label(panel, "", Rect2(24, 359, 632, 32), 16, AMBER)
	report(message)

func vehicle_charge_option(parent: Control, title: String, amount: float, limit: float, bounds: Rect2, prominent: bool = false) -> void:
	var shortfall := state.credit_shortfall(amount)
	var caption := "%s %s 度" % [title, energy_text(amount)]
	var enabled := amount > 0.0 and amount <= limit
	if enabled and shortfall > 0.0:
		caption += " · 欠 %s 度" % energy_text(shortfall)
	var button := action(parent, caption, bounds, charge_vehicle.bind(amount), prominent)
	button.disabled = not enabled

func added_debt_note(previous_debt: float) -> String:
	var amount := state.debt - previous_debt
	return " · 新增欠费 %s 度" % energy_text(amount) if amount > 0.0 else ""

func charge_vehicle(requested: float) -> void:
	var previous_debt := state.debt
	var amount := state.charge_car(requested)
	var message := "已充入 %s 度%s" % [energy_text(amount), added_debt_note(previous_debt)]
	show_charger(message if amount > 0.0 else "当前无法向车辆充电。")

func show_battery_charger(message: String = "") -> void:
	begin_page("battery_charger")
	var panel := modal("电池充电 · 车内电源", Rect2(300, 126, 680, 478))
	label(panel, "半电池补满消耗 1 度，空电池消耗 2 度。", Rect2(24, 83, 620, 27), 17, MINT)
	charge_row(panel, "手电筒电池", State.NO_CELL, state.installed_charge, Rect2(24, 124, 609, 42))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	put(panel, scroll, Rect2(24, 181, 632, 187))
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	var index := 0
	for entry in state.inventory:
		if entry.kind != "aaa":
			continue
		index += 1
		var row := Control.new()
		row.custom_minimum_size.y = 47
		rows.add_child(row)
		charge_row(row, "备用电池 %d" % index, entry.id, entry.charge, Rect2(0, 0, 609, 42))
	if index == 0:
		label(panel, "背包里没有备用电池。", Rect2(24, 184, 632, 32), 15, MUTED)
	label(panel, "车内电源  %s" % car_power_text(), Rect2(24, 382, 632, 27), 17, AMBER)
	status = label(panel, "", Rect2(24, 424, 632, 31), 16, AMBER)
	report(message)

func charge_row(parent: Control, title: String, id: int, charge: int, bounds: Rect2) -> void:
	var text := "未装入" if charge == State.NO_CELL else "%d%%" % charge
	label(parent, "%s · %s" % [title, text], Rect2(bounds.position, Vector2(330, bounds.size.y)), 16)
	var cost := state.battery_fill_cost(charge)
	var caption := "充满 · %s 度" % energy_text(cost) if cost > 0.0 else "充电"
	var charge_button := action(parent, caption,
		Rect2(bounds.position + Vector2(bounds.size.x - 158, 0), Vector2(158, bounds.size.y)), charge_battery.bind(id))
	charge_button.disabled = cost <= 0.0 or state.car_power < cost

func charge_battery(id: int) -> void:
	var problem := state.recharge_battery(id)
	show_battery_charger("电池已充满。" if problem.is_empty() else problem)

func find_charger() -> void:
	var routes := Rail.routes_from(state.station)
	var nearest := ""
	for location in routes:
		if location == state.station or not state.has_charger(location):
			continue
		if nearest.is_empty():
			nearest = location
		var travel_cost: int = (routes[location].size() - 1) * state.travel_cost_per_stop()
		if state.charger_stock(location) > 0.0 and state.car_power >= travel_cost:
			open_market_map(location)
			return
	if not nearest.is_empty():
		open_market_map(nearest)

func show_rest() -> void:
	begin_page("rest")
	var panel := modal("休息与存档", Rect2(340, 180, 600, 360))
	label(panel, "醒来日期   %s" % state.date_text(1), Rect2(24, 85, 480, 34), 20, MINT)
	var after := state.survival_after_day()
	label(panel, "今日饮水 · %s     结算后连续未喝 %d / 2 天" % ["已喝" if state.drank_today else "未喝", after.days_without_water],
		Rect2(24, 129, 552, 26), 16, MUTED)
	label(panel, "今日进食 · %s     结算后连续未吃 %d / 3 天" % ["已吃" if state.ate_today else "未吃", after.days_without_food],
		Rect2(24, 163, 552, 26), 16, MUTED)
	label(panel, "待还欠费 %s 度     结算后连续欠费 %d / 2 天" % [energy_text(state.debt), after.days_in_debt],
		Rect2(24, 197, 552, 26), 16, MUTED)
	label(panel, "车厢每日耗电 %d 度     结算后车内剩余 %s 度" % [state.daily_power_cost(), energy_text(state.overnight_power())],
		Rect2(24, 231, 552, 26), 16, MUTED)
	status = label(panel, "", Rect2(24, 259, 552, 26), 15, AMBER)
	report("今晚结算会结束本轮。" if not after.game_over_reason.is_empty() else "")
	action(panel, "睡到下一天并保存", Rect2(24, 290, 552, 43), sleep_and_save, true)

func sleep_and_save() -> void:
	var err := state.save_next_day(save_path)
	if err == OK:
		if state.game_over_reason.is_empty():
			show_cabin("已保存 · %s" % state.date_text())
		else:
			show_game_over()
	else:
		report("存档写入失败（%s）。" % error_string(err))

func show_game_over() -> void:
	begin_page("game_over")
	cabin_art()
	overlay(view, Color("0d0b16c9"))
	var panel := plate(view, Rect2(340, 205, 600, 310), DARK, BORDER)
	label(panel, "游戏结束", Rect2(28, 23, 544, 52), 34)
	wrapped(panel, state.game_over_reason, Rect2(28, 91, 544, 81), 22, AMBER)
	status = label(panel, "", Rect2(28, 193, 544, 28), 15, AMBER)
	action(panel, "开始新游戏", Rect2(28, 241, 544, 43), restart_game, true)

func restart_game() -> void:
	var fresh := State.new()
	fresh.base_name = state.base_name
	var err := fresh.save_current(save_path)
	if err != OK:
		report("新存档写入失败（%s）。" % error_string(err))
		return
	state = fresh
	focused_carriage = 0
	show_cabin()

func show_trade(message: String = "") -> void:
	if screen != "trade" or not is_instance_valid(view) or view.scene_file_path != "res://scenes/commerce/trade.tscn":
		begin_page("trade", preload("res://scenes/commerce/trade.tscn"))
		view.configure(self)
	view.refresh(message)

func set_trade_supplies(enabled: bool) -> void:
	trade_supplies = enabled
	show_trade()

func buy_item(kind: String) -> void:
	var previous_debt := state.debt
	var problem := state.purchase(kind)
	var message := "已购买 %s，放入背包%s" % [state.item_name(kind), added_debt_note(previous_debt)]
	show_trade(message if problem.is_empty() else problem)

func sell_item(id: int) -> void:
	var old_debt := state.debt
	var amount := state.sell(id)
	var payment := snappedf(old_debt - state.debt, 0.1)
	if amount <= 0:
		show_trade("当前无法出售，请查看本站收购范围和额度。")
	elif payment > 0:
		show_trade("成交 %s 度 · 偿还欠费 %s 度" % [str(amount), str(payment)])
	else:
		show_trade("到账  +%s 度" % str(amount))

func open_market_map(location: String) -> void:
	ensure_map_scene()
	map_scene.enter(location)

func find_buyer(kind: String) -> void:
	var routes := Rail.routes_from(state.station)
	var destination := ""
	var best_distance := 0
	var best_price := 0.0
	for location in routes:
		var offer := state.market_offer("demand", kind, location)
		if offer.is_empty() or offer.remaining == 0:
			continue
		var distance: int = routes[location].size() - 1
		if destination.is_empty() or distance < best_distance or (distance == best_distance and offer.price > best_price):
			destination = location
			best_distance = distance
			best_price = offer.price
	if destination.is_empty():
		report("今天没有仍可收购 %s 的站点。" % state.item_name(kind))
	else:
		open_market_map(destination)

func ensure_map_scene() -> void:
	if not is_instance_valid(map_scene):
		map_scene = preload("res://scenes/map/metro_map.tscn").instantiate()
		map_scene.configure(self, show_cabin)

func show_news() -> void:
	ensure_map_scene()
	map_scene.enter("", true)

func show_map() -> void:
	ensure_map_scene()
	if map_scene.active: map_scene.show_map()
	else: map_scene.enter()

func add_grid(parent: Control, target: String, at: Vector2, pixels: int) -> void:
	var grid := CargoGrid.new()
	grid.setup(self, target, pixels)
	grid.position = at
	parent.add_child(grid)
	grids.append(grid)

func cargo_title(target: String) -> String:
	var dimensions := state.grid_size(target)
	return "%s   %d / %d 格" % ["柜子" if target == "locker" else "背包", state.used_cells(target), dimensions.x * dimensions.y]

func show_locker(message: String = "") -> void:
	begin_page("locker")
	var panel := modal("柜子与背包", Rect2(130, 113, 1020, 495))
	label(panel, cargo_title("bag"), Rect2(40, 91, 350, 34), 21)
	label(panel, cargo_title("locker"), Rect2(516, 91, 450, 34), 21)
	add_grid(panel, "bag", Vector2(40, 139), 52)
	add_grid(panel, "locker", Vector2(516, 139), mini(52,mini(416/state.grid_size("locker").x,260/state.grid_size("locker").y)))
	action(panel,"一键放置所选",Rect2(40,48,180,32),quick_place_selected)
	action(panel,"整理背包",Rect2(230,48,140,32),sort_cargo.bind("bag"))
	action(panel,"整理柜子",Rect2(516,48,140,32),sort_cargo.bind("locker"))
	label(panel, "点选或拖动物品到目标格   /   滚轮或 R 旋转   /   F 镜像   /   右键取消", Rect2(40, 414, 930, 23), 16, MUTED)
	status = label(panel, "", Rect2(40, 447, 936, 27), 16, AMBER)
	report(message)

func click_cell(target: String, cell: Vector2i) -> void:
	if not selection.is_empty():
		move_cargo(target, cell)
		return
	var entry := state.entry_at(target, cell)
	if not entry.is_empty():
		select_cargo(target, entry.id)

func select_cargo(source: String, id: int) -> void:
	if check_trip_timeout():
		return
	if source == "ground" and is_instance_valid(surface_block) and not surface_block.can_take(id):
		report("走近物品后按 E 拾取。")
		return
	var entry := state.picked(source, id)
	if entry.is_empty():
		return
	selection = {"source": source, "id": id, "rotated": entry.rotated, "mirrored": entry.get("mirrored",false)}
	update_cargo_preview()

func clear_selection() -> void:
	selection = {}
	report("")
	for grid in grids:
		grid.queue_redraw()

func rotate_selection() -> void:
	selection.rotated = not selection.rotated
	update_cargo_preview()

func flip_selection() -> void:
	selection.mirrored = not selection.get("mirrored",false)
	update_cargo_preview()

func update_cargo_preview() -> void:
	var entry := state.picked(selection.source, selection.id)
	var shape := state.footprint(entry.kind, selection.rotated)
	report("已选 %s · %s · %d × %d" % [state.item_name(entry.kind), state.rarity_name(entry.kind), shape.x, shape.y], state.rarity_color(entry.kind))
	for grid in grids:
		grid.queue_redraw()

func drag_preview() -> Control:
	var entry := state.picked(selection.source, selection.id)
	var ghost := Panel.new()
	ghost.size = Vector2(152, 36)
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tint := state.rarity_color(entry.kind)
	ghost.add_theme_stylebox_override("panel", style(Color("322d45ee"), tint))
	label(ghost, state.item_name(entry.kind), Rect2(8, 0, 134, 36), 15, tint)
	return ghost

func move_cargo(target: String, cell: Vector2i) -> void:
	if check_trip_timeout() or selection.is_empty():
		return
	var entry := state.picked(selection.source, selection.id)
	if entry.is_empty():
		clear_selection()
		return
	if selection.source == "ground" and is_instance_valid(surface_block) and not surface_block.can_take(selection.id):
		clear_selection()
		report("走近物品后按 E 拾取。")
		return
	if not state.place(selection, target, cell):
		var problem := "该位置被占用或实际占位超出边界，请旋转或选择其他空位。"
		if target in ["active","backpack"]:problem=state.Equipment.plan(state,selection,target,cell).get("error",problem)
		elif selection.source=="backpack" and not state.inventory.is_empty():problem="请先清空背包内部物品，再卸下背包。"
		if target == "battery":
			problem = "从背包选择七号电池，再放入手电筒。"
		report(problem)
		return
	if check_trip_timeout():
		return
	var container_name: String = {"locker": "柜子", "preparation":"预备仓库", "bag": "背包", "battery": "手电筒","pocket":"口袋","active":"主动位","backpack":"背包装备位"}.get(target,target)
	var message := "%s 已放入%s。" % [state.item_name(entry.kind), container_name]
	if screen == "locker":
		show_locker(message)
	elif screen == "gear":
		clear_selection();view.refresh_inventory(message)
	else:
		show_surface(message)

func show_gear(message: String = "") -> void:
	begin_page("gear", preload("res://scenes/game/exploration_setup.tscn"))
	view.configure(self, message)

func installed_battery_text() -> String:
	return "未装七号电池" if state.installed_charge == State.NO_CELL else "%d%%" % state.installed_charge

func swap_button(parent: Control, bounds: Rect2) -> void:
	var button := action(parent, "更换电池 · 可用备用 %d" % state.usable_spares(), bounds, swap_battery)
	button.disabled = state.spare_battery().is_empty()

func swap_battery() -> void:
	if check_trip_timeout():
		return
	var problem := state.replace_battery()
	var message := "已更换七号电池 · %s。" % installed_battery_text() if problem.is_empty() else problem
	if screen == "surface":
		show_surface(message)
	else:
		show_gear(message)

func choose_gear(key: String, enabled: bool) -> void:
	loadout[key] = enabled
	show_gear()

func confirm_departure() -> void:
	var previous_debt := state.debt
	var level := Content.level(state.station,state.world_seed,state.day)
	var loot_station: String = level.get("loot_station",state.station) if SurfaceBlock.supports(state.station) else ""
	var problem := state.depart(loadout, Rail.station_info(state.station).radiation, loot_station)
	if problem.is_empty():
		if not level.is_empty():
			var points: Array = level.get("loot",[])
			while state.trip_loot.size() < points.size():
				state.trip_loot.append(["copper","book","tools","aaa"][state.station_roll(state.station,"editor-loot/%d" % state.trip_loot.size(),3)])
			for i in range(points.size()):
				if points[i].has("choices"):
					state.trip_loot[i] = preload("res://scripts/exploration/loot_table.gd").roll(state,points[i],loot_station,i)
				elif not points[i].get("kind","").is_empty(): state.trip_loot[i] = points[i].kind
		var debt_note := added_debt_note(previous_debt)
		show_surface("防护服已租用" + debt_note if not debt_note.is_empty() else "")
	else:
		report(problem)

func show_surface(message: String = "") -> void:
	if SurfaceBlock.supports(state.station):
		show_exploration_block(message)
	else:
		show_legacy_surface(message)

func show_exploration_block(message: String) -> void:
	if not is_instance_valid(surface_block):
		var scene_path := Content.scene(state.station)
		begin_page("surface",load(scene_path) if ResourceLoader.exists(scene_path) else EXPLORATION)
		view.configure(self)
	selection = {}
	update_trip_clock()
	update_surface_pack(true)
	refresh_surface_light()
	report(message)

func pick_up_surface_item(slot: int) -> void:
	if check_trip_timeout() or (is_instance_valid(surface_block) and not surface_block.can_take(slot)):
		return
	var kind := state.ground_kind(slot)
	if kind.is_empty():
		return
	if not state.pick_up_ground(slot):
		report("随身储物格没有合适的空位。")
		return
	show_surface("已拾取%s，放入背包。" % state.item_name(kind))

func close_vehicle() -> void:
	if is_instance_valid(vehicle_panel):
		vehicle_panel.hide()
		vehicle_panel.queue_free()
		vehicle_panel = null
	if is_instance_valid(surface_block):
		surface_block.inspecting_vehicle = false

func show_vehicle(vehicle_id: String) -> void:
	if check_trip_timeout() or surface_block.nearby_vehicle() != vehicle_id:
		return
	close_vehicle()
	clear_selection()
	surface_block.inspecting_vehicle = true
	var frame := Panel.new()
	frame.name = "VehicleParts"
	frame.add_theme_stylebox_override("panel", style(DARK, AMBER))
	put(view, frame, Rect2(170, 278, 489, 298))
	vehicle_panel = frame
	label(frame, "废弃汽车", Rect2(19, 12, 230, 31), 22)
	var equipped: bool = state.gear.wrench_equipped
	var caption := "汽修 %d 级 · 扳手已装备" % state.auto_repair_level if equipped else "汽修 %d 级 · 需要装备扳手" % state.auto_repair_level
	label(frame, caption, Rect2(20, 43, 350, 23), 15, MINT if equipped else AMBER)
	action(frame, "关闭", Rect2(406, 14, 64, 34), close_vehicle)
	var y := 72
	for course in AutoRepair.COURSES:
		for kind in course.parts:
			var required := AutoRepair.required_level(kind)
			var taken := state.vehicle_part_taken(vehicle_id, kind)
			var caption_right := "已拆除" if taken else "需汽修 %d 级" % required if state.auto_repair_level < required else "拆下并收纳"
			var dimensions := state.footprint(kind)
			plate(frame, Rect2(19, y, 451, 39), Color("2e283e"), BORDER)
			label(frame, "%s   %d×%d 格" % [state.item_name(kind), dimensions.x, dimensions.y], Rect2(29, y, 250, 39), 15, state.rarity_color(kind) if not taken else MUTED)
			var button := action(frame, caption_right, Rect2(315, y + 3, 148, 33), take_vehicle_part.bind(vehicle_id, kind))
			button.disabled = not equipped or taken or state.auto_repair_level < required
			y += 43

func take_vehicle_part(vehicle_id: String, kind: String) -> void:
	if check_trip_timeout() or surface_block.nearby_vehicle() != vehicle_id:
		return
	var problem := state.salvage_vehicle_part(vehicle_id, kind)
	if not problem.is_empty():
		report(problem)
		return
	show_exploration_block("")
	show_vehicle(vehicle_id)
	report("已拆下%s，放入背包。" % state.item_name(kind))

func update_surface_position() -> void:
	var cell: Vector2i = surface_block.cell()
	var title: String = surface_block.CELL_NAMES[cell.y][cell.x]
	var location: Dictionary = surface_block.active_building()
	if not location.is_empty():
		title = "%s · %d 楼" % [location.name, surface_block.floor_index + 1]
	if is_instance_valid(surface_location): surface_location.text = title
	var target: Dictionary = surface_block.interaction()
	surface_prompt.text = "" if target.is_empty() or surface_block.has_visual_target(target) else "[ E ]  " + target.caption
	if not location.is_empty() and not state.flashlight_on and target.is_empty():
		surface_prompt.text = "[ 1 ]  打开手电筒"
	if selection.get("source") == "ground" and not surface_block.can_take(selection.id):
		clear_selection()

func extract_from_block(destination: String) -> void:
	if check_trip_timeout():
		return
	var cost := state.extraction_cost(destination)
	var problem := state.extract_at(destination)
	if not problem.is_empty():
		report(problem)
		return
	var message := "已返回 %s。" % destination
	if cost > 0:
		message = "已从%s站撤离 · 车厢接应耗电 %d 度" % [destination, cost]
	show_cabin(message)

func show_legacy_surface(message: String) -> void:
	var was_open: bool = screen == "surface" and view != null and view.has_method("toggle_pack") and view.pack_open
	begin_page("surface",EXPLORATION)
	view.configure_legacy(self)
	action(view,"返回车厢",Rect2(24,24,121,41),return_to_cabin)
	update_trip_clock()
	var landscape := SurfaceScenery.new()
	landscape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	put(view.get_node("StreetFrame"), landscape, Rect2(0,0,1280,720))
	for id in range(LOOT_SPOTS.size()):
		var kind := state.ground_kind(id)
		if kind.is_empty():
			continue
		var name := state.item_name(kind)
		var dims := state.footprint(kind)
		var anchor: Vector2 = LOOT_SPOTS[id]
		var tint := state.rarity_color(kind)
		var prop := plate(landscape, Rect2(anchor - Vector2(14, -7), Vector2(28, 15)), tint, Color("211d29"))
		plate(prop, Rect2(5, 3, 14, 3), tint.lightened(0.4))
		var hotspot := action(landscape, name, Rect2(anchor - Vector2(68, 34), Vector2(136, 34)), pick_up_surface_item.bind(id))
		hotspot.tooltip_text = "%s · %d × %d 格" % [state.rarity_name(kind), dims.x, dims.y]
		hotspot.add_theme_font_size_override("font_size", 14)
		hotspot.add_theme_color_override("font_color", tint)
		hotspot.set_drag_forwarding(ground_drag.bind(hotspot, id), Callable(), Callable())
		var sprite_hit := invisible_action(landscape, prop.get_rect().grow(4), pick_up_surface_item.bind(id))
		sprite_hit.tooltip_text = "%s · %s" % [name, hotspot.tooltip_text]
		sprite_hit.set_drag_forwarding(ground_drag.bind(sprite_hit, id), Callable(), Callable())
	update_surface_pack(true)
	view.set_pack_open(was_open)
	report(message)

func update_surface_pack(walking: bool) -> void:
	if state.backpack_item.is_empty() and view.has_method("set_pack_open") and view.pack_open:view.set_pack_open(false)
	if is_instance_valid(surface_pack) and surface_pack.is_inside_tree():
		var bag_grids:=grids.filter(func(grid):return is_instance_valid(grid) and grid.container=="bag")
		if (not state.backpack_item.is_empty())==not bag_grids.is_empty():
			for grid in grids:
				if is_instance_valid(grid):grid.size=Vector2(state.grid_size(grid.container)*grid.cell_size);grid.queue_redraw()
			if surface_pack.has_node("BackpackTitle"):surface_pack.get_node("BackpackTitle").text=cargo_title("bag")
			if view.has_method("refresh_active"):view.refresh_active()
			return
	if is_instance_valid(surface_pack):
		surface_pack.hide()
		surface_pack.queue_free()
	grids.clear()
	if view.has_node("LoadoutBar"):grids.append_array(view.get_node("LoadoutBar").equipment_grids)
	var parent: Control = view.get_node("PackAnchor") if view.has_node("PackAnchor") else view
	var bounds := Rect2(Vector2.ZERO, parent.size) if parent != view else Rect2(836, 112, 404, 524)
	var sidebar := plate(parent, bounds, DARK, BORDER)
	surface_pack = sidebar
	var bag_title:=label(sidebar, cargo_title("bag"), Rect2(24,17,354,33),22);bag_title.name="BackpackTitle"
	if not state.backpack_item.is_empty():add_grid(sidebar, "bag", Vector2(24,60),48)
	else:label(sidebar,"未装备背包 · 仅可使用装备格",Rect2(24,60,354,60),17,MUTED)
	if view.has_node("LoadoutBar") and is_instance_valid(view.get_node("LoadoutBar").battery_grid):grids.append(view.get_node("LoadoutBar").battery_grid)
	plate(sidebar,Rect2(24,317,356,1),BORDER)
	action(sidebar,"一键拾取附近",Rect2(24,330,168,34),quick_pickup_nearby).focus_mode=Control.FOCUS_NONE
	action(sidebar,"一键整理背包",Rect2(202,330,178,34),sort_cargo.bind("bag")).focus_mode=Control.FOCUS_NONE
	action(sidebar,"一键放置所选",Rect2(24,374,356,34),quick_place_selected).focus_mode=Control.FOCUS_NONE
	wrapped(sidebar,"装备与主动道具已合并至左上角。\n拖拽调整背包、口袋和主动位。
七号电池放入主动位后按空格更换电池。",Rect2(24,420,356,56),14,MUTED)
	var instructions := "B 背包 · 空格 主动 · R 旋转 · F 镜像 · 1 照明" if walking else "点击拾取或拖入背包 · R 旋转 · F 镜像 · 1 照明"
	label(sidebar, instructions, Rect2(24, 488 if walking else 483, 356, 26), 14, MUTED)
	refresh_equipment()
	if view.has_method("refresh_active"): view.refresh_active()

func toggle_battery_slot() -> void:
	battery_slot_open = not battery_slot_open
	battery_panel.visible = battery_slot_open
	if not battery_slot_open and selection.get("source") == "battery":
		clear_selection()

func toggle_wrench() -> void:
	if check_trip_timeout():
		return
	state.toggle_wrench()
	refresh_equipment()
	if is_instance_valid(vehicle_panel):
		show_vehicle(surface_block.nearby_vehicle())

func refresh_equipment() -> void:
	if not is_instance_valid(flashlight_button):
		return
	var caption := "手电筒 · %s · %s" % ["开" if state.flashlight_on else "关", installed_battery_text()]
	flashlight_button.disabled = state.gear.get("inventory_tools",false) and not state.carried_tools().light
	flashlight_button.text = "手电筒 · 未携带" if flashlight_button.disabled else caption
	flashlight_button.add_theme_color_override("font_color", MINT if state.flashlight_on else TEXT)
	if is_instance_valid(wrench_button) and is_instance_valid(surface_block):
		var equipped: bool = state.gear.wrench_equipped
		var caption_wrench := "未携带" if not state.gear.wrench else "已装备" if equipped else "已收起"
		wrench_button.text = "扳手 · " + caption_wrench
		wrench_button.add_theme_color_override("font_color", MINT if equipped else TEXT)
	for grid in grids:
		if grid.container == "battery":
			grid.queue_redraw()

func refresh_surface_light() -> void:
	refresh_equipment()
	if is_instance_valid(surface_block):
		surface_block.update_lighting()
		surface_block.queue_redraw()
		update_surface_position()

func ground_drag(_at: Vector2, node: Control, id: int) -> Variant:
	select_cargo("ground", id)
	if selection.get("source") != "ground" or selection.get("id") != id:
		return null
	node.set_drag_preview(drag_preview())
	return selection

func return_to_cabin() -> void:
	if check_trip_timeout():
		return
	state.end_trip()
	show_cabin("已返回 %s。" % state.station)

func update_trip_clock() -> void:
	if not is_instance_valid(time_label):return
	if is_instance_valid(view) and view.has_method("update_countdown"):view.update_countdown(state.remaining_ms(),state.trip_limit()*1000)
	var seconds := ceili(state.remaining_ms() / 1000.0)
	var caption := "探索 %02d:%02d" % [seconds/60,seconds%60]
	if time_label.text == caption:
		return
	time_label.text = caption
	if not view.has_method("update_countdown"):time_label.add_theme_color_override("font_color", Color("ff9188") if seconds <= 5 else AMBER)

func check_trip_timeout() -> bool:
	if not state.trip_active or state.remaining_ms() > 0:
		return false
	var fee := state.fail_trip()
	var debt_text := " · 尚欠 %s 度" % str(state.debt) if state.debt > 0.0 else ""
	show_cabin("外出超时 · 携带物品全部丢失 · 防护服赔偿 %d 度%s" % [fee, debt_text])
	return true

class SurfaceScenery extends Control:
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("50465b"))
		draw_rect(Rect2(0, 0, 777, 133), Color("70657c"))
		draw_rect(Rect2(0, 124, 777, 98), Color("8c7681"))
		draw_rect(Rect2(0, 208, 777, 90), Color("a38b89"))
		draw_rect(Rect2(583, 36, 85, 85), Color("bea19a"))
		for skyline in [Rect2(18, 158, 94, 153), Rect2(146, 201, 60, 105), Rect2(371, 157, 96, 141), Rect2(476, 184, 42, 106), Rect2(627, 178, 122, 128)]:
			draw_rect(skyline, Color("716274"))
		draw_rect(Rect2(0, 295, 777, 229), Color("433b4c"))
		draw_rect(Rect2(0, 302, 777, 17), Color("514555"))
		for ruin in [Rect2(19, 110, 151, 205), Rect2(326, 163, 157, 155), Rect2(614, 123, 134, 190)]:
			draw_rect(ruin, Color("524656"))
			draw_rect(Rect2(ruin.position, Vector2(ruin.size.x, 13)), Color("665767"))
			for col in range(3):
				for floor_index in range(3):
					var window_at: Vector2 = ruin.position + Vector2(17 + col * 39, 36 + floor_index * 38)
					draw_rect(Rect2(window_at, Vector2(21, 26)), Color("312d41"))
		for slab in [Rect2(32, 326, 134, 10), Rect2(198, 402, 109, 8), Rect2(343, 358, 106, 10), Rect2(483, 429, 145, 11), Rect2(651, 365, 81, 8)]:
			draw_rect(slab, Color("695664"))
		for i in range(124):
			var p := Vector2((i * 97) % 775, 316 + (i * 73) % 206)
			draw_rect(Rect2(p, Vector2(3 + i % 7, 2)), Color("584959") if i % 2 == 0 else Color("383445"))
		draw_rect(Rect2(Vector2.ZERO, size), Color("81708b"), false, 2.0)

func return_to_menu() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.name = "ReturnConfirmation"
	dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	dialog.dialog_text = "返回主菜单？未在床铺保存的进度将丢失。"
	dialog.confirmed.connect(func():
		close_settings()
		get_tree().change_scene_to_file("res://scenes/ui/main_menu.tscn"))
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()

func show_settings() -> void:
	if is_instance_valid(settings_panel):
		return
	if is_instance_valid(home_backdrop):
		home_backdrop.dragging = false
	settings_panel = SETTINGS.instantiate()
	settings_opened_ms = Time.get_ticks_msec()
	settings_was_paused = get_tree().paused
	settings_panel.closed.connect(close_settings)
	settings_panel.return_requested.connect(return_to_menu)
	add_child(settings_panel)
	get_tree().paused = true

func close_settings() -> void:
	if not is_instance_valid(settings_panel):
		return
	if state.trip_active:
		state.trip_deadline_ms += Time.get_ticks_msec() - settings_opened_ms
	get_tree().paused = settings_was_paused
	settings_panel.queue_free()
	settings_panel = null

func equip_selected_active(id: int = -1, source: String = "") -> void:
	if check_trip_timeout(): return
	if id < 0:
		if selection.get("source") not in ["bag","preparation"]: report("先在储物格中选中道具。"); return
		id = int(selection.id)
	if source.is_empty():source=selection.get("source","bag")
	var problem := state.equip_active(id,source)
	if problem.is_empty():
		clear_selection()
		if screen=="gear":view.refresh_inventory("道具已装备，不再占用储物格。")
		else:
			update_surface_pack(true)
			report("道具已装备到主动位，不再占用背包格。")
	else: report(problem)

func unequip_active_item() -> void:
	if check_trip_timeout(): return
	var problem := state.unequip_active()
	if problem.is_empty():
		clear_selection();update_surface_pack(true);report("主动道具已放回背包。")
	else: report(problem)

func use_active_item() -> void:
	if check_trip_timeout(): return
	var problem := state.use_active()
	if problem.is_empty():
		clear_selection();update_surface_pack(true);report("已使用主动道具。")
	else: report(problem)

func sort_cargo(container:String)->void:
	if check_trip_timeout():return
	var problem:=state.sort_container(container)
	clear_selection()
	if screen=="locker":show_locker(problem if not problem.is_empty() else "整理完成，物品数量与状态已保留。")
	elif screen=="gear":view.refresh_inventory(problem if not problem.is_empty() else "整理完成。")
	elif screen=="surface":update_surface_pack(true);report(problem if not problem.is_empty() else "背包整理完成。")

func quick_place_selected()->void:
	if check_trip_timeout():return
	if selection.is_empty():report("先选中物品，再一键放置。也可 Shift+点击物品快速放置。");return
	var source:String=selection.source
	if source=="ground":pick_up_surface_item(int(selection.id));return
	if screen=="surface" and source=="bag":equip_selected_active();return
	var target:="locker" if screen=="locker" and source=="bag" else "preparation" if screen=="gear" and source=="bag" else "bag"
	var problem:=state.auto_place(selection,target)
	if problem.is_empty():clear_selection()
	if screen=="locker":show_locker(problem if not problem.is_empty() else "物品已自动放置。")
	elif screen=="gear":view.refresh_inventory(problem if not problem.is_empty() else "物品已自动放置。")
	elif screen=="surface":update_surface_pack(true);report(problem if not problem.is_empty() else "物品已自动放置。")

func quick_pickup_nearby()->void:
	if check_trip_timeout() or not is_instance_valid(surface_block):return
	var slots:Array=[]
	for slot in range(surface_block.LOOT.size()):
		if not surface_block.LOOT[slot].has("cabinet") and surface_block.can_take(slot):slots.append(slot)
	var count:=quick_pickup_slots(slots)
	report("已拾取%d件物资；未装下或不在范围内的物资仍在原处。" % count)

func quick_pickup_slots(slots:Array)->int:
	if check_trip_timeout() or not is_instance_valid(surface_block):return 0
	var count:=0
	for slot in slots:
		if surface_block.can_take(int(slot)) and state.pick_up_ground(int(slot)):count+=1
	if count>0:
		clear_selection();update_surface_pack(true);surface_block.update_interaction_visuals()
	return count


func show_furniture_storage(kind: String) -> void:
	var panel:=preload("res://scripts/construction/storage_editor.gd").new()
	add_child(panel);panel.configure(self,kind)

func toggle_equipped_bag() -> void:
	if state.backpack_item.is_empty():report("请先装备背包物品。");return
	if screen=="gear":view.toggle_bag()
	elif screen=="surface":view.toggle_pack()
