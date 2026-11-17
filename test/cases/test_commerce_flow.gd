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
	var window = home.home_backdrop.get_node("Carriage/Fixtures/TradeWindow0")
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
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = window.get_global_rect().get_center()
		event.global_position = event.position
		root.push_input(event)
	await process_frame
	check(home.screen == "trade", "customer window real click opens existing trading economy")
	home.queue_free()
	await process_frame
	print("COMMERCE_FLOW: %d checks, %d failures" % [checks,failures])
	if failures == 0: print("COMMERCE_FLOW_OK")
	quit(1 if failures else 0)
