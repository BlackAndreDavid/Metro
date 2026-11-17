extends Control
## This layer moves scenery and furniture hit targets together; HUD stays fixed.
@export_range(0.0, 0.2) var max_offset_ratio := 0.2
@export_range(0.0, 1.0) var drag_sensitivity := 0.35
@export_range(0.0, 1.0) var background_parallax := 0.25
@export_range(1.0, 1000.0) var return_speed := 160.0
const FURNITURE = preload("res://scenes/items/furniture.tscn")
const DEFINITIONS = {"bed": preload("res://resources/furniture/bed.tres"), "computer": preload("res://resources/furniture/computer.tres")}
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

func slot_rect(slot: int) -> Rect2:
	# Both slots originate at the furniture's pre-trim position in the carriage.
	var kind: String = "computer" if slot % 2 == 0 else "bed"
	var definition: Resource = DEFINITIONS[kind]
	return Rect2(Vector2(154, 144) + definition.source_origin * 4.0 - Vector2(8, 8) + Vector2(floori(slot / 2.0) * 972, 0),
		Vector2(definition.texture.get_size()) * 4.0 + Vector2(16, 16))

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
	var layer := Control.new()
	layer.name = "FurnitureSlots"
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carriage.add_child(layer)
	for slot in range(train_count * 2):
		var occupant := ""
		for kind in home.state.FURNITURE_IDS:
			if int(home.state.furniture_layout[kind]) == slot:
				occupant = kind
		var bounds := slot_rect(slot)
		if occupant.is_empty():
			var callback: Callable = home.place_home_furniture.bind(slot)
			var button: Button = home.action(layer, "空槽 %d" % (slot + 1), bounds, callback)
			button.name = "Slot%d" % slot
			button.modulate.a = 0.75 if home.placement_mode else 0.4
			bind_hotspot(button, callback)
		else:
			var data: Resource = DEFINITIONS[occupant]
			var item = FURNITURE.instantiate()
			item.name = occupant.capitalize()
			var padded := (Vector2(data.texture.get_size()) + Vector2(4, 4)) * 4.0
			var fit := minf(1.0, minf(bounds.size.x / padded.x, bounds.size.y / padded.y))
			item.size = padded * fit
			item.position = bounds.get_center() - item.size * 0.5
			layer.add_child(item)
			item.configure(data, home, self, home.placement_mode)
	_apply_offset()

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
