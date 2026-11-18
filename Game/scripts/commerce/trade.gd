extends "res://scripts/ui/ui_builder.gd"
const Dialogue = preload("res://scripts/commerce/customer_dialogue.gd")
var active_story: Dictionary = {}
const Orders = preload("res://scripts/commerce/customer_orders.gd")
const DragItem = preload("res://scripts/commerce/trade_drag_item.gd")
var home: Control
var state: RefCounted
var selection: Array = []
@onready var window: Control = $Panel/CustomerWindow

func configure(owner_home: Control) -> void:
	home = owner_home
	state = home.state
	$Panel/Close.pressed.connect(home.show_cabin.bind(""))
	$Panel/Map.pressed.connect(home.open_market_map.bind(state.station))
	$Panel/Confirm.pressed.connect(confirm_order)
	$Panel/Dismiss.pressed.connect(dismiss_customer)
	$DialogueOverlay/Card/Dismiss.pressed.connect(dismiss_customer)
	$Panel/Basket.controller = self
	window.arrived.connect(on_customer_arrived)
	window.departed.connect(next_customer)
	var order := Orders.ensure(state)
	if not order.is_empty(): window.show_customer(int(order.visitor),order.status != "open")

func on_customer_arrived() -> void:
	if maybe_start_dialogue(): return
	# Arrival only changes readiness; keep native drag sources alive mid-drag.
	var quote := Orders.preview(state,selection)
	$Panel/Confirm.disabled = not quote.problem.is_empty()
	home.report(quote.problem)

func clear_column(column: Control) -> void:
	for node in column.get_children():
		column.remove_child(node)
		node.queue_free()

func next_customer() -> void:
	selection.clear()
	var order := Orders.next(state)
	if not order.is_empty(): window.show_customer(int(order.visitor))
	refresh("")

func refresh(message: String = "") -> void:
	var market: Dictionary = state.Markets.profile(state.station)
	var visits := Orders.record(state)
	var order: Dictionary = visits.active
	$Panel/Title.text = "%s · %s" % [market.name,state.station]
	$Panel/Account.text = "账户 %s 度 · 欠费 %s 度" % [home.energy_text(state.account),home.energy_text(state.debt)]
	$Panel/Order.text = "今日到访 %d / %d · 已完成 %d 单" % [visits.arrived,Orders.daily_limit(state.station),visits.completed] + " · 送客 %d 位" % visits.dismissed
	if order.is_empty():
		$Panel/Order.text += "\n今日顾客已全部接待，明日再来。"
	else:
		$Panel/Order.text += "\n顾客%s：%s类商品\n顾客预算 %s 度" % ["购买" if order.side == "buy" else "出售",Orders.CATEGORIES[order.category].name,home.energy_text(order.budget)]
		if order.status == "completed": $Panel/Order.text += "\n订单完成 · 顾客正在离开"
		elif order.status == "dismissed": $Panel/Order.text += "\n已送客 · 顾客正在离开"
	clear_column($Panel/Bag)
	clear_column($Panel/Stock)
	show_items($Panel/Bag,"玩家背包",false,order)
	show_items($Panel/Stock,"顾客货物",true,order)
	refresh_basket()
	var quote := Orders.preview(state,selection)
	$Panel/Quote.text = "商品 %d 件 · 合计 %s 度" % [selection.size(),home.energy_text(quote.total)]
	if not order.is_empty() and order.status == "open":
		$Panel/Quote.text += "\n顾客交易后预算 %s 度" % home.energy_text(order.budget + quote.total * (-1 if order.side == "buy" else 1))
	$Panel/Confirm.disabled = not quote.problem.is_empty() or window.phase != "stay"
	$Panel/Dismiss.disabled = order.is_empty() or order.get("status") != "open" or window.phase in ["empty","depart"]
	home.status = $Panel/Status
	var feedback: String = message if not message.is_empty() else quote.problem
	if feedback.is_empty() and not order.is_empty() and order.side == "sell" and state.credit_shortfall(quote.total) > 0:
		feedback = "本次需赊购 %s 度，确认后计入欠费。" % home.energy_text(state.credit_shortfall(quote.total))
	home.report(feedback)

func show_items(parent: Control, title: String, stock: bool, order: Dictionary) -> void:
	label(parent,title,Rect2(0,0,336,28),19)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	put(parent,scroll,Rect2(0,34,336,206))
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	if stock:
		if order.is_empty() or order.side != "sell" or order.status != "open":
			label(rows,"本订单不提供出售商品",Rect2(0,0,310,40),14,MUTED)
			return
		for kind in order.stock:
			if order.stock[kind] <= 0: continue
			add_card(rows,{"source":"stock","kind":kind},kind,Orders.price(state,order,kind),"库存 %d" % order.stock[kind])
	else:
		for entry in state.inventory:
			var value := Orders.price(state,order,entry.kind,int(entry.get("charge",100))) if not order.is_empty() and not Orders.ItemCatalog.definition(entry.kind).is_empty() else 0.0
			add_card(rows,{"source":"bag","id":entry.id},entry.kind,value,"%s类" % Orders.CATEGORIES[Orders.category_of(entry.kind)].name if not Orders.category_of(entry.kind).is_empty() else "非订单商品")

func add_card(parent: Control, payload: Dictionary, kind: String, value: float, detail: String) -> void:
	var card := DragItem.new()
	card.name = ("Stock_" + kind) if payload.source == "stock" else ("Bag_" + str(payload.id))
	card.payload = payload
	card.caption = "%s · %s 度" % [state.item_name(kind),home.energy_text(value)]
	card.custom_minimum_size = Vector2(310,58)
	card.mouse_default_cursor_shape = Control.CURSOR_DRAG
	card.add_theme_stylebox_override("panel",style(Color("302b43"),BORDER))
	parent.add_child(card)
	var text := Label.new()
	text.text = card.caption + "\n" + detail + " · 拖入下方订单"
	text.mouse_filter = MOUSE_FILTER_IGNORE
	text.add_theme_font_size_override("font_size",14)
	card.add_child(text)

func refresh_basket() -> void:
	var list = $Panel/Basket/Scroll/Items
	clear_column(list)
	$Panel/Basket/Empty.visible = selection.is_empty()
	for index in range(selection.size()):
		var payload: Dictionary = selection[index]
		var entry: Dictionary = state.find_entry("bag",int(payload.get("id",-1))) if payload.source == "bag" else payload
		var row := HBoxContainer.new()
		list.add_child(row)
		var text := Label.new()
		text.text = state.item_name(entry.get("kind","water"))
		text.size_flags_horizontal = SIZE_EXPAND_FILL
		text.mouse_filter = MOUSE_FILTER_IGNORE
		row.add_child(text)
		var remove := Button.new()
		remove.name = "Remove_" + str(index)
		remove.text = "移除"
		remove.pressed.connect(remove_item.bind(index))
		row.add_child(remove)

func queue_item(payload: Dictionary) -> void:
	var candidate := selection.duplicate(true)
	candidate.append(payload.duplicate())
	var quote := Orders.preview(state,candidate)
	if not quote.problem.is_empty() and not quote.problem.begins_with("买不起") and quote.problem != "背包没有足够的空间。":
		home.report(quote.problem)
		return
	selection = candidate
	refresh("")

func remove_item(index: int) -> void:
	selection.remove_at(index)
	refresh("")

func confirm_order() -> void:
	if window.phase != "stay": return
	var problem := Orders.confirm(state,selection)
	if not problem.is_empty():
		refresh(problem)
		return
	selection.clear()
	window.finish_order()
	refresh("交易完成，顾客正在向右离开。")

func dismiss_customer() -> void:
	var problem := Orders.dismiss(state)
	if not problem.is_empty():
		refresh(problem)
		return
	selection.clear()
	active_story = {}
	$DialogueOverlay.hide()
	window.finish_order()
	refresh("已送客，本次未结算，顾客正在向右离开。")

func maybe_start_dialogue() -> bool:
	var order: Dictionary = Orders.record(state).active
	active_story = Dialogue.pending(state,order)
	if active_story.is_empty():
		$DialogueOverlay.hide()
		return false
	$Panel/Confirm.disabled = true
	var saved: Dictionary = state.dialogue_progress.get(order.id,{})
	show_dialogue_node(saved.get("node",active_story.start))
	return true

func show_dialogue_node(id: String) -> void:
	var order: Dictionary = Orders.record(state).active
	var node: Dictionary = Dialogue.enter(state,order,active_story,id)
	$DialogueOverlay.show()
	$DialogueOverlay/Card/Speaker.text = node.get("speaker",window.Catalog.definition(int(order.visitor)).name)
	$DialogueOverlay/Card/TextScroll/Text.text = node.text
	clear_column($DialogueOverlay/Card/Scroll/Choices)
	var options: Array = Dialogue.Meeting.new(active_story).replies(id)
	var shown := 0
	for choice in options:
		if not Dialogue.matches(state,choice.get("conditions",{}),window.Catalog.definition(int(order.visitor)).id): continue
		var button := Button.new()
		button.text = choice.text
		button.pressed.connect(apply_choice.bind(choice,options.find(choice)))
		$DialogueOverlay/Card/Scroll/Choices.add_child(button)
		shown += 1
	if shown == 0:
		var button := Button.new()
		button.text = "继续" if not node.get("next","").is_empty() else "结束对话"
		button.pressed.connect(choose_dialogue.bind(node.get("next","")))
		$DialogueOverlay/Card/Scroll/Choices.add_child(button)

func choose_dialogue(next: String) -> void:
	if not next.is_empty():
		show_dialogue_node(next)
		return
	Dialogue.finish(state,Orders.record(state).active,active_story)
	active_story = {}
	$DialogueOverlay.hide()
	if not maybe_start_dialogue(): refresh("")

func apply_choice(choice: Dictionary, index: int) -> void:
	var order: Dictionary = Orders.record(state).active
	var current: String = state.dialogue_progress.get(order.id,{}).get("node",active_story.start)
	Dialogue.apply_effects(state,order,active_story,current+"/choice/"+str(index),choice.get("effects",{}))
	choose_dialogue(choice.get("next",""))
