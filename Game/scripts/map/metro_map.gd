extends "res://scripts/ui/ui_builder.gd"
const State = preload("res://scripts/cabin_state.gd")
const Rail = preload("res://scripts/cabin_map.gd")
const AutoRepair = preload("res://scripts/auto_repair.gd")
const RADIATION := ["", "低", "中", "高"]
var state: RefCounted
var font: Font
var view: Control
var screen := "map"
var selected_station := ""
var outside_tab := false
var active := false
var _source: WeakRef
var _resume: Callable
var _previous_scene: Node
var _source_process := Node.PROCESS_MODE_INHERIT

func configure(source: Control, resume: Callable) -> void:
	_source = weakref(source)
	_resume = resume
	state = source.state
	source.tree_exiting.connect(queue_free)

func _ready() -> void:
	var system_font := SystemFont.new()
	system_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	font = system_font
	var ui_theme := Theme.new()
	ui_theme.default_font = font
	theme = ui_theme

func enter(destination: String = "", news_first: bool = false) -> void:
	if active: return
	var source: Control = _source.get_ref()
	state = source.state
	if not is_inside_tree(): source.get_tree().root.add_child(self)
	_previous_scene = get_tree().current_scene
	_source_process = source.process_mode
	source.hide()
	source.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().current_scene = self
	process_mode = Node.PROCESS_MODE_INHERIT
	active = true
	selected_station = destination
	outside_tab = false
	show()
	if news_first: show_news()
	else: show_map()

func exit(message: String = "") -> void:
	if not active: return
	active = false
	hide()
	process_mode = Node.PROCESS_MODE_DISABLED
	var source: Control = _source.get_ref()
	if is_instance_valid(source):
		source.process_mode = _source_process
		source.show()
		get_tree().current_scene = _previous_scene
		_resume.call(message)

func begin_page(kind: String) -> void:
	if is_instance_valid(view):
		view.hide()
		remove_child(view)
		view.queue_free()
	screen = kind
	view = Control.new()
	view.mouse_filter = MOUSE_FILTER_IGNORE
	view.name = "MapContent"
	add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func energy_text(amount: float) -> String:
	return str(snappedf(amount, 0.1))
func car_power_text() -> String:
	return "%s / %d 度" % [energy_text(state.car_power), State.CAR_CAPACITY]
func _unhandled_key_input(event: InputEvent) -> void:
	if active and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if screen == "news": show_map()
		else: exit()
		get_viewport().set_input_as_handled()

func show_news() -> void:
	show_map()
	screen = "news"
	overlay(view, Color("141021bb"))
	var card := plate(view, Rect2(318, 173, 644, 372), Color("2c253b"), Color("746582"))
	card.name = "NewsCard"
	label(card, "当日新闻", Rect2(28, 20, 430, 48), 30)
	action(card, "关闭", Rect2(550, 25, 66, 36), show_map)
	label(card, "%s    地面天气 · %s" % [state.date_text(), state.weather()], Rect2(28, 75, 522, 25), 16, MINT)
	plate(card, Rect2(28, 113, 588, 1), BORDER)
	wrapped(card, state.news(), Rect2(28, 138, 588, 123), 21)
	action(card, "关闭并查看线路图", Rect2(28, 293, 588, 47), show_map, true)

func show_map() -> void:
	Rail.reload_network()
	begin_page("map")
	overlay(view, Color("1a1728"))
	label(view, "上海地铁线路图", Rect2(40, 25, 420, 46), 34)
	label(view, "中心城区", Rect2(321, 30, 200, 45), 18, MUTED)
	action(view, "当日新闻", Rect2(1014, 28, 102, 38), show_news)
	action(view, "返回", Rect2(1132, 28, 108, 38), exit)
	var paper := plate(view, Rect2(40, 89, 865, 585), Rail.PAPER)
	paper.name = "NetworkMapPanel"
	var map := Rail.new()
	map.name = "RailMap"
	map.setup(font, state.station, selected_station, select_station)
	put(paper, map, Rect2(8, 50, 849, 505))
	var legend_x := 19.0
	for line in Rail.LINES:
		var color := Color(line[1])
		plate(paper, Rect2(legend_x, 16, 19, 18), color)
		label(paper, str(line[0]), Rect2(legend_x, 16, 19, 18), 12, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		label(paper, "号线", Rect2(legend_x + 26, 15, 38, 20), 13, Rail.INK)
		legend_x += 72
	label(paper, "●  当前站     ▱  换乘站", Rect2(604, 15, 235, 20), 13, Rail.INK, HORIZONTAL_ALIGNMENT_RIGHT)
	label(paper, "站点示意依据申通地铁 D202501 版线路图", Rect2(19, 554, 810, 22), 12, Color("625b65"))
	var detail := plate(view, Rect2(923, 89, 317, 585), DARK, BORDER)
	detail.name = "StationDetails"
	label(detail, "当前站 · %s" % state.station, Rect2(20, 15, 280, 29), 15, MINT)
	if selected_station.is_empty():
		label(detail, "选择目的地", Rect2(20, 60, 280, 39), 26)
		wrapped(detail, "点击线路图上的站点查看站内设施、周边遗址和行车耗电。", Rect2(20, 125, 272, 92), 17, MUTED)
		label(detail, "车内电源  %s" % car_power_text(), Rect2(20, 469, 275, 32), 17, MINT)
		return
	label(detail, selected_station, Rect2(20, 49, 280, 43), 29)
	var lines := PackedStringArray()
	for line in Rail.station_lines(selected_station):
		lines.append("%d 号线" % line)
	label(detail, "  /  ".join(lines), Rect2(20, 93, 280, 22), 14, MUTED)
	action(detail, "站内设施", Rect2(20, 132, 135, 38), set_map_tab.bind(false), not outside_tab)
	action(detail, "站外情报", Rect2(162, 132, 135, 38), set_map_tab.bind(true), outside_tab)
	var info := Rail.station_info(selected_station)
	if outside_tab:
		label(detail, "区域辐射 · %s" % RADIATION[info.radiation], Rect2(20, 186, 270, 28), 18, AMBER)
		label(detail, "附近建筑遗址", Rect2(20, 224, 270, 27), 15, MUTED)
		wrapped(detail, info.outside, Rect2(20, 256, 270, 66), 17)
	else:
		show_map_market(detail, selected_station)
	plate(detail, Rect2(20, 333, 277, 1), BORDER)
	var path := Rail.route(state.station, selected_station)
	var steps := maxi(0, path.size() - 1)
	var fare: int = steps * state.travel_cost_per_stop()
	label(detail, "行车路线 · %d 站" % steps, Rect2(20, 345, 275, 27), 16, MINT)
	var itinerary := "  →  ".join(PackedStringArray(path))
	wrapped(detail, itinerary, Rect2(20, 382, 276, 103), 14, MUTED)
	label(detail, "车内电源  %s" % car_power_text(), Rect2(20, 485, 275, 27), 17, MINT)
	var caption := "前往 · 耗电 %d 度" % fare
	if steps == 0:
		caption = "已在本站" if selected_station == state.station else "线路未接通"
	elif state.car_power < fare:
		caption = "车电不足 · 需 %d 度" % fare
	var go := action(detail, caption, Rect2(20, 523, 277, 43), travel, true)
	go.disabled = steps == 0 or state.car_power < fare

func show_map_market(detail: Control, location: String) -> void:
	var market := State.Markets.profile(location)
	var facility: String = "学校 · 汽修培训" if location == AutoRepair.STATION else market.facility
	label(detail, facility, Rect2(20, 183, 277, 26), 16, MINT)
	if state.has_charger(location):
		var stock: float = state.charger_stock(location)
		var service := "充电站停电" if state.is_blackout() else "电站余 %s 度" % energy_text(stock)
		label(detail, service, Rect2(181, 183, 116, 26), 13, MINT if stock > 0 else AMBER, HORIZONTAL_ALIGNMENT_RIGHT)
	var quotes := ScrollContainer.new()
	quotes.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	put(detail, quotes, Rect2(20, 210, 277, 119))
	var columns := Control.new()
	var demand := State.Markets.demand(location)
	columns.custom_minimum_size = Vector2(262, 24 + maxi(market.stock.size(), demand.size()) * 22)
	quotes.add_child(columns)
	map_quote_column(columns, location, market.stock, "stock", 0, "本站供应 / 度", "售罄")
	map_quote_column(columns, location, demand, "demand", 132, "本站收购 / 度", "满额")

func map_quote_column(detail: Control, location: String, items: Dictionary, side: String, x: float, title: String, exhausted: String) -> void:
	label(detail, title, Rect2(x, 0, 130, 21), 13, MUTED)
	var row := 0
	for kind in items:
		var offer: Dictionary = state.market_offer(side, kind, location)
		var y := 22 + row * 22
		label(detail, state.item_name(kind), Rect2(x, y, 81, 20), 12, state.rarity_color(kind))
		var price := energy_text(offer.price) if offer.remaining > 0 else exhausted
		if side == "demand" and kind == "aaa" and offer.remaining > 0:
			var empty: Dictionary = state.market_offer(side, kind, location, 0)
			price = "%s–%s" % [energy_text(empty.price), price]
		label(detail, price, Rect2(x + 81, y, 49, 20), 12, TEXT if offer.remaining > 0 else MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
		row += 1

func select_station(station: String) -> void:
	selected_station = station
	outside_tab = false
	show_map()

func set_map_tab(outside: bool) -> void:
	outside_tab = outside
	show_map()

func travel() -> void:
	var steps := Rail.route(state.station, selected_station).size() - 1
	if state.travel_to(selected_station, steps):
		exit("已抵达 %s · 消耗车内电源 %d 度" % [state.station, steps * state.travel_cost_per_stop()])

