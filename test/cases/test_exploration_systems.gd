extends SceneTree
const Motion = preload("res://scripts/exploration/player_motion.gd")
const Enemy = preload("res://scripts/exploration/enemy.gd")
const Content = preload("res://scripts/content/content_registry.gd")
const Loot = preload("res://scripts/exploration/loot_table.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:failures += 1;push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var motion := Motion.new()
	check(is_equal_approx(motion.step(1,1,false),188),"walk speed reduced exactly 20 percent")
	check(motion.noise_radius() == 32,"walking noise is half human height")
	check(is_equal_approx(motion.step(1,1,true),282) and motion.stamina == 75,"Shift runs at 1.5x and drains stamina")
	check(motion.noise_radius() == 96,"running noise is 1.5 human heights")
	motion.step(3,1,true)
	check(motion.stamina == 0 and motion.exhausted,"exhaustion clamps stamina at zero")
	check(motion.step(0.1,1,true) == 188,"holding Shift cannot run while exhausted")
	motion.step(2,0,false);motion.step(0.1,0,false)
	check(motion.stamina > 25 and not motion.exhausted and motion.noise_radius() == 0,"rest restores stamina and releases exhaustion without idle noise")
	motion.apply_slow(2,0.8)
	check(is_equal_approx(motion.step(0.1,1,false),150.4),"pounce slows walking by twenty percent")
	motion.step(2,0,false)
	check(motion.slow_remaining == 0,"slow expires after two seconds")
	var spec: Dictionary = Content.read_json("res://content/enemies.json").enemies[0].duplicate(true)
	# Fixed-size behavior fixture; live sprite/collider dimensions remain artist-editable.
	spec.sprite.width = 128;spec.sprite.collision_width = 128
	var enemy := Enemy.new(spec,{"id":"rat_test","row":0,"x":400})
	check(enemy.body_rect(416).size == Vector2(128,32),"rat collider is four human widths and half human height")
	check(enemy.perceive({"row":0,"x":160,"indoors":false}).vision,"forward vision cone sees twice body length")
	check(not enemy.perceive({"row":0,"x":640,"indoors":false}).vision,"distant target behind rat is outside cone and circle")
	check(enemy.perceive({"row":0,"x":480,"indoors":false}).vision,"circle sees close targets behind rat")
	check(not enemy.perceive({"row":1,"x":400,"noise_radius":999,"moving":true}).sound,"hearing cannot cross streets")
	var stationary := spec.duplicate(true);stationary.movement.patrol_speed = 0
	enemy = Enemy.new(stationary,{"id":"vision","row":0,"x":400})
	for i in range(10):enemy.step(0.1,{"row":0,"x":160,"indoors":false},Vector2(0,1800),416)
	check(enemy.awareness == 100 and enemy.alerted,"vision adds ten awareness per tenth second")
	var hearing := Enemy.new(stationary,{"id":"hearing","row":0,"x":400})
	for i in range(10):hearing.step(0.1,{"row":0,"x":450,"indoors":true,"moving":true,"noise_radius":96},Vector2(0,1800),416)
	check(hearing.awareness == 50 and not hearing.alerted,"sound alone adds five awareness per tenth second")
	for i in range(50):enemy.step(0.1,{"row":1,"x":160,"indoors":false},Vector2(0,1800),416)
	check(enemy.awareness == 0 and not enemy.alerted and enemy.row == 0,"alert fades without sensing and enemy never changes streets")
	var patrol := Enemy.new(spec,{"id":"patrol","row":0,"x":64,"facing":-1})
	patrol.step(0.1,{"row":1,"x":0},Vector2(0,1800),416)
	check(patrol.x == 64 and patrol.facing == 1,"patrol turns around at collision boundary")
	patrol.timer = 0.05;patrol.step(0.1,{"row":1,"x":0},Vector2(0,1800),416)
	check(patrol.action == "patrol_wait" and patrol.timer == 1,"patrol alternates one-to-two-second moves with one-second stops")
	var attack := Enemy.new(spec,{"id":"attack","row":0,"x":300})
	attack.awareness = 100;attack.alerted = true
	attack.step(0.01,{"row":0,"x":240},Vector2(0,1800),416)
	var hit := attack.step(0.1,{"row":0,"x":240},Vector2(0,1800),416)
	check(hit.get("time_penalty") == 5 and hit.get("slow_seconds") == 2 and hit.get("slow_multiplier") == 0.8,"pounce collision applies exact duration loss and slow")
	check(attack.attack_jump() > 0 and attack.body_rect(416).end.y < 416,"pounce follows a visible jump arc with matching collision position")
	check(attack.step(0.1,{"row":0,"x":240},Vector2(0,1800),416).is_empty(),"one pounce cannot hit repeatedly")
	attack.step(0.1,{"row":0,"x":240},Vector2(0,1800),416);var stopped := attack.x
	attack.step(0.5,{"row":0,"x":240},Vector2(0,1800),416)
	check(attack.action == "recovery" and attack.x == stopped,"rat remains stationary during two-second recovery")
	var home = load("res://scenes/game/home.tscn").instantiate();root.add_child(home)
	home.show_cabin();home.state.installed_charge = 100;home.loadout = {"light":true,"heavy":true,"wide":false,"crowbar":false,"wrench":false};home.confirm_departure()
	await process_frame
	var street = home.surface_block
	var before_x: float = street.player_x
	for code in [KEY_SHIFT,KEY_D]:
		var press := InputEventKey.new();press.keycode = code;press.physical_keycode = code;press.pressed = true;Input.parse_input_event(press)
	# Wait for real input processing instead of assuming a cold frame completes in 150ms.
	var input_deadline := Time.get_ticks_msec()+2000
	while Time.get_ticks_msec()<input_deadline and not (street.motion.running and street.player_x>before_x and home.view.get_node("Stamina").value<100):
		await process_frame
	check(street.motion.running and street.player_x > before_x and home.view.get_node("Stamina").value < 100,"actual Shift plus movement input drives stamina HUD and sprint")
	for code in [KEY_SHIFT,KEY_D]:
		var release := InputEventKey.new();release.keycode = code;release.physical_keycode = code;release.pressed = false;Input.parse_input_event(release)
	street.set_process(false)
	check(street.hero_textures.right != null and street.enemies.size() > 0,"exploration loads supplied suit animation and placed monster")
	var point: Dictionary = street.LOOT[0]
	street.row = int(point.row);street.player_x = point.x;street.building = point.building;street.floor_index = int(point.floor);home.state.flashlight_on = true;street.position_changed();street.update_interaction_visuals()
	var key: String = "cabinet/"+point.cabinet
	check(street.interaction().get("kind") == "cabinet" and street.interaction_visuals.has(key),"building point is exposed as an interactable storage cabinet")
	var visual = street.interaction_visuals[key].control
	check(visual.visual.material.shader == preload("res://assets/shaders/item_outline.gdshader") and visual.hovered,"nearby cabinet reuses common outline/highlight module")
	check(home.surface_prompt.text.is_empty() and not visual.caption.visible and street.hero_view.is_visible_in_tree(),"nearby interaction shows only its outline and keeps the hero visible indoors")
	var expected: String = home.state.ground_kind(0);home.state.inventory.clear();street.interact();await process_frame
	var panel = home.view.get_child(home.view.get_child_count()-1)
	check(street.inspecting_container and panel.cabinet == point.cabinet,"cabinet opens its own contents UI")
	panel.take_item(0)
	check(home.state.ground_kind(0).is_empty() and home.state.inventory.size() == 1 and home.state.inventory[0].kind == expected,"cabinet loot transfers atomically without duplication")
	panel.finish();await process_frame
	check(not street.inspecting_container,"closing cabinet restores movement")
	street.row = street.enemies[0].row;street.building = "";street.player_x = street.enemies[0].x-50
	var rat = street.enemies[0];rat.awareness = 100;rat.alerted = true;rat.action = "chase_move";rat.timer = 3
	var deadline: int = home.state.trip_deadline_ms
	street.update_enemies(0.01);street.update_enemies(0.1)
	check(home.state.trip_deadline_ms == deadline-5000 and street.motion.slow_remaining == 2,"real exploration attack deducts five seconds and applies temporary slow")
	check(Loot.roll(home.state,{"chance":0,"choices":[{"kind":"water","weight":1}]},home.state.station,0) == "","zero-chance cabinet generates nothing")
	check(Loot.roll(home.state,{"chance":1,"choices":[{"kind":"water","weight":1}]},home.state.station,0) == "water","weighted cabinet generation supports deterministic guaranteed item")
	street.row = 0;street.CELL_NAMES[0] = ["偏移街道"];street.STREET_STARTS[0] = 300;street.player_x = 600
	street.move_horizontal(1,10)
	check(street.player_x == 836 and street.cell().x == 0 and street.camera_offset() == 300,"offset street movement, local cell indexing and camera share the same origin")
	home.queue_free();await process_frame
	print("EXPLORATION_SYSTEMS: %d checks, %d failures" % [checks,failures])
	if failures == 0:print("EXPLORATION_SYSTEMS_OK")
	quit(1 if failures else 0)
