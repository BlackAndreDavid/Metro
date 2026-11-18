extends SceneTree
var output := OS.get_environment("METRO_TEST_RESULTS")
func _initialize() -> void: call_deferred("run")
func capture(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(name+".png"))
func run() -> void:
	if output.is_empty() or DisplayServer.get_name() == "headless":
		push_error("Requires a rendered display and METRO_TEST_RESULTS")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280,720)
	var home = load("res://scenes/game/home.tscn").instantiate()
	root.add_child(home)
	home.state.day = 2
	home.show_cabin()
	home.show_trade()
	var scene = home.view
	var order: Dictionary = home.state.CustomerOrders.ensure(home.state)
	order.visitor = 0
	order.budget = scene.window.Catalog.definition(0).base_budget
	scene.refresh("")
	scene.window.set_process(false)
	scene.window.show_customer(0)
	scene.window.advance(scene.window.approach_seconds)
	await capture("story-priority")
	scene.choose_dialogue("rumour")
	await capture("story-branch")
	scene.choose_dialogue("")
	await capture("story-finished-order")
	home.queue_free()
	await process_frame
	print("CONTENT_STORY_CAPTURE_OK")
	quit()
