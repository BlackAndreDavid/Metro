extends SceneTree
const Orders = preload("res://scripts/commerce/customer_orders.gd")
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void: call_deferred("run")
func button(at: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = at
	event.global_position = at
	root.push_input(event)
func motion(at: Vector2, relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = at
	event.global_position = at
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event)
func click(node: Control) -> void:
	await process_frame
	var at := node.get_global_rect().get_center()
	button(at,true)
	button(at,false)
	await process_frame
func drag(card: Control, basket: Control, arriving: Control = null) -> void:
	await process_frame
	var start := card.get_global_rect().get_center()
	var target := basket.get_global_rect().end-Vector2(24,24)
	button(start,true)
	motion(start+Vector2(24,0),Vector2(24,0))
	await process_frame
	check(root.gui_is_dragging(), "real mouse motion starts native drag")
	if arriving != null:
		arriving.advance(arriving.approach_seconds)
		await process_frame
		check(root.gui_is_dragging(), "customer arrival preserves ongoing drag")
	motion(target,target-start-Vector2(24,0))
	await process_frame
	button(target,false)
	await process_frame
func bag_id(state,kind: String) -> int:
	for entry in state.inventory:
		if entry.kind == kind: return entry.id
	return -1
func run() -> void:
	root.size = Vector2i(1280,720)
	var home = load("res://scenes/game/home.tscn").instantiate()
	root.add_child(home)
	home.show_cabin()
	await process_frame
	var hotspot = home.home_backdrop.get_node("Carriage/Fixtures/TradeWindow0")
	check(not hotspot.has_node("Customer"), "Home keeps original window without visitors")
	var original: Image = home.home_backdrop.carriage.get_node("Texture").texture.get_image().get_region(Rect2i(137,17,101,49))
	original.convert(Image.FORMAT_RGBA8)
	check(hotspot.padded_image.get_region(Rect2i(2,2,101,49)).get_data() == original.get_data(), "Home window source pixels unchanged")
	await click(hotspot)
	check(home.screen == "trade" and home.view.scene_file_path == "res://scenes/commerce/trade.tscn", "original hotspot opens transaction scene")
	var scene = home.view
	var window = scene.get_node("Panel/CustomerWindow")
	window.set_process(false)
	var order := Orders.ensure(home.state)
	window.show_customer(int(order.visitor))
	check(window.size.x > 280 and window.size.y > 320, "customer window enlarged in both dimensions")
	check(window.portrait.texture is AtlasTexture and window.portrait.texture.region == Rect2(0,0,48,44), "window displays only upper body from independent full-body source")
	check(window.portrait.position.x < 0, "visitor starts left of window")
	var start_x: float = window.portrait.position.x
	window.advance(window.approach_seconds/2)
	check(window.portrait.position.x > start_x and window.portrait.modulate.a < 1, "visitor moves left to right while entering")
	window.advance(window.approach_seconds/2)
	var center: float = window.portrait.position.x
	window.advance(100)
	check(window.phase == "stay" and window.portrait.position.x == center, "unfinished visitor waits indefinitely")
	var battery = scene.find_child("Bag_"+str(bag_id(home.state,"aaa")),true,false)
	window.show_customer(int(order.visitor))
	await drag(battery,scene.get_node("Panel/Basket"),window)
	check(scene.selection.is_empty() and "类别" in scene.get_node("Panel/Status").text, "wrong category drop rejected visibly")
	var initial_budget: float = order.budget
	order.budget = 1.0
	scene.refresh("")
	var water_id := bag_id(home.state,"water")
	await drag(scene.find_child("Bag_"+str(water_id),true,false),scene.get_node("Panel/Basket"))
	check(scene.selection.size() == 1 and scene.get_node("Panel/Confirm").disabled and "买不起" in scene.get_node("Panel/Status").text, "over-budget drag shows cannot afford and disables confirmation")
	check(home.state.find_entry("bag",water_id).size() > 0, "dragging reserves selection without consuming inventory")
	await click(scene.find_child("Remove_0",true,false))
	check(scene.selection.is_empty(), "selected item can be removed")
	order.budget = initial_budget
	scene.refresh("")
	await drag(scene.find_child("Bag_"+str(water_id),true,false),scene.get_node("Panel/Basket"))
	check(scene.selection.size() == 1 and not scene.get_node("Panel/Confirm").disabled, "valid native drag enables confirmation")
	var quote := Orders.preview(home.state,scene.selection)
	var account: float = home.state.account
	await click(scene.get_node("Panel/Confirm"))
	check(home.state.find_entry("bag",water_id).is_empty() and is_equal_approx(home.state.account,account+quote.total), "confirm button commits exactly selected goods")
	check(is_equal_approx(order.budget,initial_budget-quote.total) and order.status == "completed", "customer purchase reduces budget and completes one order")
	check(window.phase == "depart" and Orders.record(home.state).arrived == 1, "new visitor waits until completed customer exits")
	window.advance(window.depart_seconds/2)
	check(window.portrait.position.x > center, "completed visitor leaves towards right")
	window.advance(window.depart_seconds/2)
	check(Orders.record(home.state).arrived == 2 and Orders.record(home.state).active.side == "sell", "next customer gets independent order after exit")
	var second_id: String = Orders.record(home.state).active.id
	await click(scene.get_node("Panel/Close"))
	check(home.screen == "cabin" and not is_instance_valid(window), "leaving transaction removes customer visuals from Home")
	await click(home.home_backdrop.get_node("Carriage/Fixtures/TradeWindow0"))
	scene = home.view
	window = scene.get_node("Panel/CustomerWindow")
	window.set_process(false)
	window.advance(window.approach_seconds)
	order = Orders.ensure(home.state)
	check(order.id == second_id and Orders.record(home.state).arrived == 2, "reopening resumes same order without refreshing quota")
	var kind: String = order.stock.keys()[0]
	var count: int = home.state.supply_count(kind)
	var budget: float = order.budget
	await drag(scene.find_child("Stock_"+kind,true,false),scene.get_node("Panel/Basket"))
	quote = Orders.preview(home.state,scene.selection)
	await click(scene.get_node("Panel/Confirm"))
	check(home.state.supply_count(kind) == count+1 and is_equal_approx(order.budget,budget+quote.total), "customer sale via drag and confirm increases customer budget")
	await click(scene.get_node("Panel/Close"))
	home.state.customer_visits[home.state.station] = {"arrived":Orders.daily_limit(home.state.station),"completed":Orders.daily_limit(home.state.station),"active":{}}
	await click(home.home_backdrop.get_node("Carriage/Fixtures/TradeWindow0"))
	scene = home.view
	check("今日顾客已全部接待" in scene.get_node("Panel/Order").text and scene.get_node("Panel/Confirm").disabled and scene.window.phase == "empty", "daily cap displays empty window and blocks additional trades")
	home.queue_free()
	await process_frame
	print("COMMERCE_FLOW: %d checks, %d failures" % [checks,failures])
	if failures == 0: print("COMMERCE_FLOW_OK")
	quit(1 if failures else 0)
