extends Control
## This layer moves scenery and furniture hit targets together; HUD stays fixed.
@export_range(0.0, 0.1) var max_offset_ratio := 0.1
@export_range(0.0, 1.0) var drag_sensitivity := 0.35
@export_range(0.0, 1.0) var background_parallax := 0.25
@export_range(1.0, 1000.0) var return_speed := 320.0
const HIGHLIGHTABLE = preload("res://scenes/items/highlightable_item.tscn")
const FURNITURE = preload("res://scenes/items/furniture.tscn")
const Catalog = preload("res://scripts/items/furniture_catalog.gd")
var DEFINITIONS: Dictionary = Catalog.DEFINITIONS
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
var camera_locked := false
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
	if not interaction_enabled or camera_locked:
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
	var limit := size * minf(max_offset_ratio, 0.1)
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
	if not camera_locked and not dragging and not offset.is_equal_approx(return_target):
		offset = offset.move_toward(return_target, return_speed * delta)
		_apply_offset()

func furniture_rect(kind: String, placement: Dictionary) -> Rect2:
	return Catalog.placement_rect(kind, placement)

func make_grid(parent: Control, hanging: bool) -> void:
	var grid = preload("res://scripts/construction/placement_grid.gd").new()
	grid.name = "MountPoints" if hanging else "FurnitureGrid"
	grid.cars = train_count
	grid.hanging = hanging
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(grid)

func make_preview(parent: Control, name: String) -> void:
	var preview = preload("res://scripts/construction/placement_preview.gd").new()
	preview.name = name
	preview.z_index=4 # Placement feedback stays above the world layers.
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(preview)

func update_preview(kind: String, placement: Dictionary, valid: bool) -> void:
	for name in ["FloorPreview", "HangingFixtures/HangingPreview"]:
		var preview = carriage.get_node(name)
		preview.texture = null
		if not kind.is_empty() and not placement.is_empty() and (placement.has("mount") == name.begins_with("Hanging")):
			preview.bounds = Catalog.placement_rect(kind, placement)
			preview.kind = kind
			preview.texture = Catalog.DEFINITIONS[kind].texture
			preview.valid = valid
		preview.queue_redraw()

func configure_world(home: Control) -> void:
	home.state.ensure_carriage_fixtures()
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
	if home.construction.active:
		make_grid(carriage, false)
	var wall_layer:=Control.new()
	wall_layer.name="WallFixtures";wall_layer.mouse_filter=Control.MOUSE_FILTER_IGNORE
	carriage.add_child(wall_layer)
	var floor_layer := Control.new()
	floor_layer.name = "FurnitureSlots"
	floor_layer.z_index=1
	floor_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carriage.add_child(floor_layer)
	make_preview(carriage, "FloorPreview")
	var rail_layer:=Control.new()
	rail_layer.name="Rails";rail_layer.mouse_filter=Control.MOUSE_FILTER_IGNORE;rail_layer.z_index=2
	carriage.add_child(rail_layer)
	for index in range(train_count):
		var rail:=TextureRect.new();rail.texture=preload("res://assets/textures/Rail.png")
		rail.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;rail.mouse_filter=Control.MOUSE_FILTER_IGNORE
		rail.position=Vector2(158+index*972,152);rail.size=Vector2(964,416);rail.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		rail_layer.add_child(rail)
	var hanging_layer := Control.new()
	hanging_layer.name = "HangingFixtures"
	hanging_layer.z_index=3
	hanging_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	carriage.add_child(hanging_layer)
	if home.construction.active:
		make_grid(hanging_layer, true)
	for kind in home.state.furniture_layout:
		var placement: Variant = home.state.furniture_layout[kind]
		if placement == null:
			continue
		var bounds := Catalog.visual_rect(kind, furniture_rect(kind, placement))
		var data: Resource = DEFINITIONS[kind]
		var planes: Array=[2,1] if data.placement_type!="hanging" and not data.floor_cells.is_empty() and not data.wall_cells.is_empty() else [0]
		var depth_views: Array=[]
		for plane in planes:
			var item = FURNITURE.instantiate()
			item.render_plane=plane
			depth_views.append(item)
			item.name = kind.capitalize()
			var raw := Vector2(data.texture.get_size())
			var pixel_scale := bounds.size / raw
			item.size = (raw + Vector2(4, 4)) * pixel_scale
			item.position = bounds.position - Vector2(2, 2) * pixel_scale
			(hanging_layer if data.placement_type == "hanging" else wall_layer if plane==2 or (data.floor_cells.is_empty() and not data.wall_cells.is_empty()) else floor_layer).add_child(item)
			home.construction.register_furniture(item, data)
			item.configure(data, home, self)
			if home.construction.moving and home.construction.selected_id == kind:
				item.modulate.a = 0.25
				item.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if depth_views.size()==2:
			depth_views[0].depth_partner=weakref(depth_views[1]);depth_views[1].depth_partner=weakref(depth_views[0])
	make_preview(hanging_layer, "HangingPreview")
	_apply_offset()

func _open_trade() -> void:
	if is_instance_valid(home_controller) and home_controller.screen == "cabin" and not home_controller.construction.active:
		home_controller.use_hotspot("trade")

func zoom_for_count() -> float:
	# Keep adjacent centers closer than twice the 10% pan limit, allowing
	# a gentle drag to cross the midpoint and focus the neighboring car.
	return minf(0.25, 1120.0 / (972.0 * train_count)) if train_count > 1 else 1.0

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
