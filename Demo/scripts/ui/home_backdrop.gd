extends Control
## This layer moves scenery and furniture hit targets together; HUD stays fixed.
@export_range(0.0, 0.2) var max_offset_ratio := 0.2
@export_range(0.0, 1.0) var drag_sensitivity := 0.35
@export_range(0.0, 1.0) var background_parallax := 0.25
@export_range(1.0, 1000.0) var return_speed := 160.0
const FURNITURE = preload("res://scenes/items/furniture.tscn")
const Catalog = preload("res://scripts/items/furniture_catalog.gd")
const DEFINITIONS = Catalog.DEFINITIONS
const HIGHLIGHTABLE = preload("res://scenes/items/highlightable_item.tscn")
var train_count := 1
var train_zoom := 1.0
var focused_carriage := 0
var return_target := Vector2.ZERO
var focus_anchor := Vector2.ZERO
var home_controller: Control
var offset := Vector2.ZERO
var dragging := false
var dragged := false
var press_position := Vector2.ZERO
var pending_action := Callable()
var interaction_enabled := true
@onready var background: TextureRect = $Background
@onready var carriage: Control = $Carriage

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_apply_offset()

func bind_hotspot(button: Button, callback: Callable) -> void:
	# GUI input gates world dragging; ordinary HUD/settings buttons never pan.
	button.pressed.disconnect(callback)
	button.gui_input.connect(_hotspot_input.bind(callback))

func _hotspot_input(event: InputEvent, callback: Callable) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		start_drag(event.global_position, callback)
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		callback.call()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		start_drag(event.global_position)

func start_drag(at: Vector2, callback: Callable = Callable()) -> void:
	if not interaction_enabled:
		return
	dragging = true
	dragged = false
	press_position = at
	pending_action = callback

func _input(event: InputEvent) -> void:
	if not dragging:
		return
	if event is InputEventMouseMotion:
		if event.global_position.distance_to(press_position) > 6.0:
			dragged = true
		if dragged:
			pan_by(event.relative * drag_sensitivity)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		dragging = false
		choose_nearest_carriage()
		var callback := pending_action
		pending_action = Callable()
		if not dragged and callback.is_valid():
			callback.call()

func pan_by(delta: Vector2) -> void:
	var limit := size * minf(max_offset_ratio, 0.2)
	offset = focus_anchor + (offset + delta - focus_anchor).clamp(-limit, limit)
	_apply_offset()

func _apply_offset() -> void:
	train_zoom = zoom_for_count()
	carriage.scale = Vector2.ONE * train_zoom
	carriage.position = size * 0.5 - Vector2(154 + 486 * train_count, 360) * train_zoom + offset
	background.position = Vector2(-256, -144) + offset * background_parallax

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		dragging = false
		pending_action = Callable()
		choose_nearest_carriage()

func _process(delta: float) -> void:
	if not dragging and not offset.is_equal_approx(return_target):
		offset = offset.move_toward(return_target, return_speed * delta)
		_apply_offset()

func native_rect(kind: String) -> Rect2:
	var definition: Resource = DEFINITIONS[kind]
	return Rect2(Vector2(154, 144) + definition.source_origin * 4.0 - Vector2(8, 8),
		Vector2(definition.texture.get_size()) * 4.0 + Vector2(16, 16))

func slot_rect(slot: int) -> Rect2:
	var local_slot := slot % Catalog.SLOTS_PER_CARRIAGE
	var bounds: Rect2
	match local_slot:
		0: bounds = native_rect("computer")
		1: bounds = native_rect("bed")
		2: bounds = native_rect("locker")
		3, 4:
			bounds = native_rect("door")
			bounds.size.x /= 2.0
			bounds.position.x += (local_slot - 3) * bounds.size.x
		5:
			bounds = Rect2(Vector2(154, 144) + Vector2(28, 44) * 4.0 - Vector2(8, 8), Vector2(128, 232))
		6, 7, 8, 9:
			bounds = native_rect("screen")
			bounds.position += (Catalog.HANGING_ORIGINS[local_slot - Catalog.FLOOR_SLOTS] - Catalog.HANGING_ORIGINS[0]) * 4.0
	bounds.position.x += floori(slot / float(Catalog.SLOTS_PER_CARRIAGE)) * 972
	return bounds

func furniture_rect(kind: String, slot: int) -> Rect2:
	var bounds := slot_rect(slot)
	for cell in Catalog.footprint(kind, slot, train_count):
		bounds = bounds.merge(slot_rect(cell))
	return bounds

func configure_home(home: Control) -> void:
	train_count = home.state.carriage_count
	home_controller = home
	focused_carriage = clampi(home.focused_carriage, 0, train_count - 1)
	home.focused_carriage = focused_carriage
	focus_anchor = target_for_carriage(focused_carriage)
	return_target = focus_anchor
	offset = focus_anchor
	for index in range(1, train_count):
		var extra := TextureRect.new()
		extra.name = "Carriage%d" % (index + 1)
		extra.texture = $Carriage/Texture.texture
		extra.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		extra.mouse_filter = Control.MOUSE_FILTER_IGNORE
		extra.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		extra.position = Vector2(154 + index * 972, 144)
		extra.size = Vector2(972, 432)
		carriage.add_child(extra)
	var fixtures := Control.new()
	fixtures.name = "Fixtures"
	fixtures.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carriage.add_child(fixtures)
	for index in range(train_count):
		# The window remains part of the carriage art. Reuse the common item
		# component over that exact region instead of an invisible tooltip button.
		var image: Image = $Carriage/Texture.texture.get_image().get_region(Rect2i(137, 17, 101, 49))
		var window = HIGHLIGHTABLE.instantiate()
		window.name = "TradeWindow%d" % index
		window.position = Vector2(694 + index * 972, 204)
		window.size = Vector2(420, 212)
		fixtures.add_child(window)
		window.set_item(ImageTexture.create_from_image(image), "交易", self)
		window.activated.connect(_open_trade)
	var layer := Control.new()
	layer.name = "FurnitureSlots"
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carriage.add_child(layer)
	var occupied: Array[int] = []
	for kind in Catalog.IDS:
		occupied.append_array(Catalog.footprint(kind, int(home.state.furniture_layout[kind]), train_count))
	for slot in range(train_count * Catalog.SLOTS_PER_CARRIAGE):
		if slot in occupied or not home.build_mode:
			continue
		var callback: Callable = home.place_home_furniture.bind(slot)
		var hanging := slot % Catalog.SLOTS_PER_CARRIAGE >= Catalog.FLOOR_SLOTS
		if hanging and not home.build_mode:
			continue
		if home.placement_mode and not home.selected_furniture.is_empty():
			var selected_hanging: bool = DEFINITIONS[home.selected_furniture].placement_type == "hanging"
			if hanging != selected_hanging:
				continue
		var text := "挂点 %d" % (slot % Catalog.SLOTS_PER_CARRIAGE - Catalog.FLOOR_SLOTS + 1) if hanging else "空槽 %d" % (slot % Catalog.SLOTS_PER_CARRIAGE + 1)
		var button: Button = home.action(layer, text, slot_rect(slot), callback)
		button.name = "Slot%d" % slot
		button.set_meta("hanging_point", hanging)
		button.modulate.a = 0.75 if home.placement_mode else 0.4
		bind_hotspot(button, callback)
	for kind in Catalog.IDS:
		var slot: int = home.state.furniture_layout[kind]
		if slot < 0:
			continue
		var bounds := furniture_rect(kind, slot)
		var data: Resource = DEFINITIONS[kind]
		var item = FURNITURE.instantiate()
		item.name = kind.capitalize()
		var padded := (Vector2(data.texture.get_size()) + Vector2(4, 4)) * 4.0
		var fit := minf(1.0, minf(bounds.size.x / padded.x, bounds.size.y / padded.y))
		item.size = padded * fit
		item.position = bounds.get_center() - item.size * 0.5
		layer.add_child(item)
		item.configure(data, home, self, home.placement_mode)
	# Hanging controls must be last in the GUI tree as well as drawn on top;
	# z_index alone would leave the door intercepting a hanger click.
	for child in layer.get_children():
		if child.get_meta("hanging_point", false):
			layer.move_child(child, layer.get_child_count() - 1)
	_apply_offset()

func _open_trade() -> void:
	if is_instance_valid(home_controller) and home_controller.screen == "cabin":
		home_controller.use_hotspot("trade")

func zoom_for_count() -> float:
	# Keep adjacent centers closer than twice the 20% pan limit, allowing
	# a gentle drag to cross the midpoint and focus the neighboring car.
	return minf(0.5, 1120.0 / (972.0 * train_count)) if train_count > 1 else 1.0

func target_for_carriage(index: int) -> Vector2:
	return Vector2(((train_count - 1) * 0.5 - index) * 972.0 * zoom_for_count(), 0)

func choose_nearest_carriage() -> void:
	var nearest := focused_carriage
	var nearest_distance := offset.distance_squared_to(target_for_carriage(nearest))
	for index in range(train_count):
		var distance := offset.distance_squared_to(target_for_carriage(index))
		# Ties preserve the current carriage instead of oscillating.
		if distance < nearest_distance - 0.01:
			nearest = index
			nearest_distance = distance
	focused_carriage = nearest
	return_target = target_for_carriage(nearest)
	focus_anchor = return_target
	if is_instance_valid(home_controller):
		home_controller.focused_carriage = nearest
