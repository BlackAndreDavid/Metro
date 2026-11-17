extends Control
## This layer moves scenery and furniture hit targets together; HUD stays fixed.
@export_range(0.0, 0.2) var max_offset_ratio := 0.2
@export_range(0.0, 1.0) var drag_sensitivity := 0.35
@export_range(0.0, 1.0) var background_parallax := 0.25
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
		var callback := pending_action
		pending_action = Callable()
		if not dragged and callback.is_valid():
			callback.call()

func pan_by(delta: Vector2) -> void:
	var limit := size * minf(max_offset_ratio, 0.2)
	offset = (offset + delta).clamp(-limit, limit)
	_apply_offset()

func _apply_offset() -> void:
	carriage.position = offset
	background.position = Vector2(-256, -144) + offset * background_parallax

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		dragging = false
		pending_action = Callable()
