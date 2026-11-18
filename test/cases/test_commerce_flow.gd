extends SceneTree
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1280,720)
	var home = load("res://scenes/game/home.tscn").instantiate()
	root.add_child(home)
	home.show_cabin()
	await process_frame
	var hotspot = home.home_backdrop.get_node("Carriage/Fixtures/TradeWindow0")
	check(not hotspot.has_method("apply_depth") and not hotspot.has_node("Customer"), "Home retains original static window without customer animation")
	var original: Image = home.home_backdrop.carriage.get_node("Texture").texture.get_image().get_region(Rect2i(137,17,101,49))
	original.convert(Image.FORMAT_RGBA8)
	check(hotspot.padded_image.get_region(Rect2i(2,2,101,49)).get_data() == original.get_data(), "Home window uses original carriage pixels")
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = hotspot.get_global_rect().get_center()
		event.global_position = event.position
		root.push_input(event)
	await process_frame
	check(home.screen == "trade" and home.view.scene_file_path == "res://scenes/commerce/trade.tscn", "original Home hotspot opens independent transaction scene")
	var scene = home.view
	var window = scene.get_node("Panel/CustomerWindow")
	check(window.is_ancestor_of(window.portrait) and home.home_backdrop == null, "customer belongs only to transaction scene")
	window.set_process(false)
	window.phase = "approach"
	window.elapsed = 0
	window.apply_depth(0)
	var files := {}
	for data in window.Catalog.ENTRIES:
		var texture: Texture2D = load(data.texture)
		check(texture.get_size() == Vector2(48,80) and not files.has(data.texture), "independent pixel sprite: " + data.id)
		files[data.texture] = true
	check(window.portrait.modulate.a == 0 and is_equal_approx(window.portrait.scale.x,0.42), "distant visitor starts small and transparent")
	window.advance(window.approach_seconds/2)
	check(is_equal_approx(window.depth,0.5) and window.portrait.modulate.a > 0 and window.portrait.modulate.r < 1, "approaching visitor scales brightens and fades in")
	window.advance(window.approach_seconds/2)
	check(window.phase == "stay" and window.depth == 1 and window.portrait.modulate == Color.WHITE, "near visitor is full size opaque and bright")
	window.advance(window.stay_seconds+window.depart_seconds/2)
	check(window.phase == "depart" and is_equal_approx(window.depth,0.5), "departure reverses depth consistently")
	var old: int = window.customer_index
	window.advance(window.depart_seconds/2+window.gap_seconds)
	check(window.customer_index != old and window.phase == "approach", "next independent customer appears after gap")
	window.phase = "stay"
	window.elapsed = 1.0
	window.apply_depth(1)
	var index: int = window.customer_index
	home.set_trade_supplies(true)
	check(home.view == scene and scene.get_node("Panel/CustomerWindow") == window and window.customer_index == index and window.elapsed == 1.0, "switching goods preserves customer animation")
	var before: int = home.state.supply_count("water")
	var balance: float = home.state.account
	var buy = scene.get_node("Panel/Stock/Buy_water")
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = buy.get_global_rect().get_center()
		event.global_position = event.position
		root.push_input(event)
	await process_frame
	check(home.state.supply_count("water") == before+1 and home.state.account < balance, "transaction purchase button preserves real inventory and account behavior")
	check(home.view == scene and window.customer_index == index and window.phase == "stay", "transaction refresh preserves visitor")
	var sold_id: int = home.state.inventory[0].id
	var sale = scene.find_child("Sell_" + str(sold_id),true,false)
	check(sale != null, "transaction scene exposes sale button")
	balance = home.state.account
	if sale != null:
		for pressed in [true,false]:
			var event := InputEventMouseButton.new()
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = pressed
			event.position = sale.get_global_rect().get_center()
			event.global_position = event.position
			root.push_input(event)
		await process_frame
	check(home.state.find_entry("bag",sold_id).is_empty() and home.state.account > balance and home.view == scene, "real sale updates account without recreating transaction scene")
	var close = scene.get_node("Panel/Close")
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = close.get_global_rect().get_center()
		event.global_position = event.position
		root.push_input(event)
	await process_frame
	check(home.screen == "cabin" and not is_instance_valid(window), "closing transaction removes visitor and returns to original Home")
	check(not home.home_backdrop.get_node("Carriage/Fixtures/TradeWindow0").has_node("Customer"), "returning Home still has no customer actor")
	home.queue_free()
	await process_frame
	print("COMMERCE_FLOW: %d checks, %d failures" % [checks,failures])
	if failures == 0: print("COMMERCE_FLOW_OK")
	quit(1 if failures else 0)
