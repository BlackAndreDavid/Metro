extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var scene = load("res://scenes/game/cabin.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	if scene.screen != "rules":
		quit(2)
		return
	scene.show_cabin("")
	await process_frame
	if scene.screen != "cabin" or scene.view.get_child_count() == 0:
		quit(3)
		return
	print("ONBOARDING_SMOKE: rules and cabin UI initialized")
	scene.queue_free()
	await process_frame
	quit(0)
