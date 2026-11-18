extends "res://scripts/ui/ui_builder.gd"
## Transaction scene owns the animated customer window; Home only routes actions.
var home: Control
var state: RefCounted

func configure(owner_home: Control) -> void:
	home = owner_home
	state = home.state
	$Panel/Close.pressed.connect(home.show_cabin.bind(""))
	$Panel/Map.pressed.connect(home.open_market_map.bind(state.station))
	$Panel/CustomerWindow.set_customer(state.day)

func clear_column(column: Control) -> void:
	for node in column.get_children():
		column.remove_child(node)
		node.queue_free()

func refresh(message: String = "") -> void:
	var market: Dictionary = state.Markets.profile(state.station)
	$Panel/Title.text = "%s · %s" % [market.name,state.station]
	$Panel/Facility.text = market.facility
	clear_column($Panel/Stock)
	clear_column($Panel/Sales)
	show_stock($Panel/Stock,market)
	show_sales($Panel/Sales)
	$Panel/Account.text = "账户余额 %s 度    待还欠费 %s 度" % [home.energy_text(state.account),home.energy_text(state.debt)]
	home.status = $Panel/Status
	home.report(message)

func show_stock(parent: Control, market: Dictionary) -> void:
	action(parent,"本站货物",Rect2(0,0,126,34),home.set_trade_supplies.bind(false),not home.trade_supplies)
	action(parent,"生活补给",Rect2(138,0,126,34),home.set_trade_supplies.bind(true),home.trade_supplies)
	var stock: Dictionary = state.Markets.ESSENTIALS if home.trade_supplies else market.stock
	var row := 0
	for kind in stock:
		var offer: Dictionary = state.market_offer("stock",kind)
		var shape: Vector2i = state.footprint(kind)
		var y := 48 + row * 59
		label(parent,state.item_name(kind),Rect2(0,y,230,23),17,state.rarity_color(kind))
		var descriptor: String = "满电 · 停电涨价" if kind == "aaa" and state.is_blackout() else "满电" if kind == "aaa" else state.rarity_name(kind)
		label(parent,"%s · %d×%d 格 · 库存 %d" % [descriptor,shape.x,shape.y,offer.remaining],Rect2(0,y+23,235,21),13,MUTED)
		var shortfall: float = state.credit_shortfall(offer.price)
		var method := "赊购" if shortfall > 0 else "购买"
		var caption := "%s  %s 度" % [method,home.energy_text(offer.price)] if offer.remaining > 0 else "今日售罄"
		var buy := action(parent,caption,Rect2(240,y+2,166,42),home.buy_item.bind(kind))
		buy.name = "Buy_" + kind
		buy.disabled = offer.remaining == 0
		if shortfall > 0 and not buy.disabled:
			buy.tooltip_text = "本次记入欠费 %s 度" % home.energy_text(shortfall)
		row += 1

func show_sales(parent: Control) -> void:
	label(parent,"出售背包物品",Rect2(0,0,410,34),21)
	if state.inventory.is_empty():
		label(parent,"背包里没有可出售物品。",Rect2(0,45,410,36),16,MUTED)
		return
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	put(parent,scroll,Rect2(0,41,420,316))
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for entry in state.inventory:
		var kind: String = entry.kind
		var offer: Dictionary = state.market_offer("demand",kind,state.station,int(entry.get("charge",state.FULL_CHARGE)))
		var item_row := Control.new()
		item_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item_row.custom_minimum_size.y = 57
		rows.add_child(item_row)
		label(item_row,state.item_name(kind),Rect2(0,6,215,23),17,state.rarity_color(kind))
		var detail := "本站不收" if offer.is_empty() else "今日已满额"
		if not offer.is_empty() and offer.remaining > 0:
			detail = "今日还能收 %d 件" % offer.remaining
			var sell := action(item_row,"出售  %s 度" % home.energy_text(offer.price),Rect2(228,7,166,40),home.sell_item.bind(entry.id))
			sell.name = "Sell_" + str(entry.id)
		elif kind == "aaa" or not state.Markets.ESSENTIALS.has(kind):
			action(item_row,"查附近买家",Rect2(228,7,166,40),home.find_buyer.bind(kind))
		else: detail = "每日补给"
		if kind == "aaa": detail = "电量 %d%% · %s" % [entry.charge,detail]
		label(item_row,"%s · %s" % [state.rarity_name(kind),detail],Rect2(0,28,215,20),13,MUTED)
