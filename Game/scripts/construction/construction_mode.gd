class_name ConstructionMode
extends Control
## One controller and palette for every catalog furniture instance.
const Catalog = preload("res://scripts/items/furniture_catalog.gd")
const BACKDROP = preload("res://scenes/game/home_backdrop.tscn")
var state: RefCounted
var focused_carriage := 0
var font: Font
var screen := "construction"
var backdrop: Control
var construction: ConstructionMode:
	get:
		return self
var _return_scene: WeakRef
var _return_process_mode := Node.PROCESS_MODE_INHERIT
var _previous_current_scene: Node
var active := false
var selected_id := ""
var moving := false
const HOLD_SECONDS := 1.0
var hold_kind := ""
var hold_elapsed := 0.0
var hold_cancelled := false
var dragging_furniture := false
var pointer := Vector2.ZERO
var press_position := Vector2.ZERO
var grab_cell := Vector2i.ZERO
var candidate: Dictionary = {}
var registered: Dictionary = {}
var storage_panel: Control
@onready var actions: HBoxContainer = $Toolbar/Margin/Actions
@onready var inventory: ItemList = $Warehouse/Center/Panel/Margin/Items/Inventory
@onready var place_button: Button = $Warehouse/Center/Panel/Margin/Items/Buttons/Place

func _ready() -> void:
	_setup_theme()
	$Expansion/Center/Panel/Margin/Items/Buttons/Confirm.pressed.connect(confirm_expansion)
	$Expansion/Center/Panel/Margin/Items/Buttons/Back.pressed.connect(func(): _refresh(""))
	actions.get_node("Dismantle").pressed.connect(dismantle)
	actions.get_node("Warehouse").pressed.connect(open_warehouse)
	actions.get_node("Expand").pressed.connect(request_expansion)
	actions.get_node("Exit").pressed.connect(exit)
	var check_button:=Button.new();check_button.name="Check";check_button.text="检查装修";actions.add_child(check_button)
	check_button.pressed.connect(func():
		var problem: String=state.furniture_completion_problem()
		$Message.text="检查通过，可以退出装修。" if problem.is_empty() else problem)
	var storage_button:=Button.new();storage_button.name="Storage";storage_button.text="储物格";actions.add_child(storage_button);storage_button.pressed.connect(edit_storage)
	place_button.pressed.connect(take_from_warehouse)
	$Warehouse/Center/Panel/Margin/Items/Buttons/Close.pressed.connect(func(): $Warehouse.hide())
	inventory.item_selected.connect(func(_index): place_button.disabled = false)
	inventory.item_activated.connect(func(_index): take_from_warehouse())

func configure(owner_home: Control) -> void:
	# Share only the model and camera focus; do not reuse Home's UI or helpers.
	_return_scene = weakref(owner_home)
	state = owner_home.state
	focused_carriage = owner_home.focused_carriage
	owner_home.tree_exiting.connect(queue_free)

func _setup_theme() -> void:
	var ui_font := SystemFont.new()
	ui_font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	font = ui_font
	var ui_theme := Theme.new()
	ui_theme.default_font = font
	theme = ui_theme

func register_furniture(item: Node, data: Resource) -> void:
	item.build_controller = self
	item.selection_requested.connect(select_furniture)
	registered[data.id] = weakref(item)

func enter() -> void:
	if active:
		return
	var source: Control = _return_scene.get_ref() if _return_scene != null else null
	if not is_instance_valid(source) or not source.state.can_edit_home():
		return
	state = source.state
	focused_carriage = source.focused_carriage
	if not is_inside_tree():
		source.get_tree().root.add_child(self)
	_previous_current_scene = get_tree().current_scene
	_return_process_mode = source.process_mode
	source.hide()
	source.process_mode = Node.PROCESS_MODE_DISABLED
	get_tree().current_scene = self
	process_mode = Node.PROCESS_MODE_INHERIT
	active = true
	selected_id = ""
	moving = false
	screen = "construction"
	_refresh("点击家具选中，或从家具仓库取出家具。")

func exit() -> void:
	if moving and state.furniture_layout.get(selected_id)==null:
		$Message.text="还有取出的家具未放置，请先放置或取消选择。";return
	var problem: String=state.furniture_completion_problem()
	if not problem.is_empty():$Message.text=problem;return
	deactivate()
	var source: Control = _return_scene.get_ref() if _return_scene != null else null
	if is_instance_valid(source):
		source.focused_carriage = focused_carriage
		source.process_mode = _return_process_mode
		source.show()
		get_tree().current_scene = _previous_current_scene
		source.show_cabin()

func deactivate() -> void:
	if is_instance_valid(storage_panel):storage_panel.queue_free()
	clear_gesture()
	active = false
	selected_id = ""
	moving = false
	$Warehouse.hide()
	hide()
	process_mode = Node.PROCESS_MODE_DISABLED

func on_page_changed(_page: String) -> void:
	# Home only calls this while its own scene is running.
	if not active:
		registered.clear()

func select_furniture(kind: String) -> void:
	if not active or not Catalog.DEFINITIONS.has(kind):
		return
	selected_id = kind
	moving = false
	_refresh("已选中%s，长按1秒可拖动，也可拆除。" % Catalog.DEFINITIONS[kind].display_name)

func can_place_at(placement: Dictionary) -> bool:
	return active and moving and not selected_id.is_empty() and state.furniture_placement_problem(selected_id, placement).is_empty()

func place_at(placement: Dictionary) -> void:
	if not active or not moving or selected_id.is_empty():
		return
	var problem: String = state.place_furniture(selected_id, placement)
	if problem.is_empty():
		focused_carriage = int(placement.car)
		moving = false
		clear_gesture()
	_refresh("家具位置已更新，请在床铺保存。" if problem.is_empty() else problem)

func dismantle() -> void:
	if not active or selected_id.is_empty():
		return
	var kind := selected_id
	var problem: String = state.store_furniture(kind)
	if problem.is_empty():
		selected_id = ""
		moving = false
	_refresh(("电脑已收纳到柜子或背包。" if kind == "computer" else "家具已拆除并收纳到家具仓库。") if problem.is_empty() else problem)

func cancel_selection() -> void:
	clear_gesture()
	selected_id = ""
	moving = false
	_refresh("")

func request_expansion() -> void:
	clear_gesture()
	if not active:
		return
	selected_id = ""
	moving = false
	show_expansion()

func open_warehouse() -> void:
	if not active:
		return
	cancel_selection()
	inventory.clear()
	for kind in Catalog.IDS:
		if not state.stored_furniture_available(kind):
			continue
		var data: Resource = Catalog.DEFINITIONS[kind]
		inventory.add_item(data.display_name, data.texture)
		var index := inventory.item_count - 1
		inventory.set_item_metadata(index, kind)
		inventory.set_item_tooltip_enabled(index, false)
	place_button.disabled = inventory.item_count == 0
	if inventory.item_count > 0:
		inventory.select(0)
	$Warehouse/Center/Panel/Margin/Items/Empty.visible = inventory.item_count == 0
	$Warehouse.show()
	inventory.grab_focus()

func take_from_warehouse() -> void:
	if not active:
		return
	var selected := inventory.get_selected_items()
	if selected.is_empty():
		return
	var kind: String = inventory.get_item_metadata(selected[0])
	if not state.stored_furniture_available(kind):
		return
	selected_id = kind
	moving = true
	$Warehouse.hide()
	grab_cell = Vector2i.ZERO
	_refresh("请点击兼容格放置%s。" % Catalog.DEFINITIONS[kind].display_name)

func refresh_ui() -> void:
	visible = active
	if not visible:
		return
	var has_selection := not selected_id.is_empty()
	actions.get_node("Selection").text = "装修 · " + (("移动中：" if moving else "已选中：") + Catalog.DEFINITIONS[selected_id].display_name if has_selection else "长按家具1秒后拖动，或点击选中拆除")
	actions.get_node("Storage").disabled = not has_selection or state.furniture_layout.get(selected_id)==null or Catalog.DEFINITIONS[selected_id].storage==Vector2i.ZERO
	actions.get_node("Dismantle").disabled = not has_selection or state.furniture_layout[selected_id] == null

func _refresh(message: String) -> void:
	screen = "construction"
	$Expansion.hide()
	registered.clear()
	if is_instance_valid(backdrop):
		backdrop.hide()
		$World.remove_child(backdrop)
		backdrop.queue_free()
	backdrop = BACKDROP.instantiate()
	$World.add_child(backdrop)
	backdrop.configure_world(self)
	$Message.text = message
	$Toolbar.show()
	show()
	backdrop.camera_locked = moving
	refresh_ui()
	if moving:
		update_drag_preview()

func action(parent: Control, caption: String, bounds: Rect2, callback: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.position = bounds.position
	button.size = bounds.size
	button.add_theme_font_size_override("font_size", 14)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func show_expansion() -> void:
	screen = "expansion"
	$Toolbar.hide()
	$Warehouse.hide()
	$Expansion.show()
	var text := "当前 %d / %d 节车厢\n" % [state.carriage_count, state.MAX_CARRIAGES]
	for kind in state.EXPANSION_COST:
		text += "%s × %d（拥有 %d）\n" % [state.item_name(kind), state.EXPANSION_COST[kind], state.material_count(kind)]
	text += "行车：%d → %d 度/站\n每日：%s → %s 度" % [state.travel_cost_per_stop(), state.travel_cost_per_stop() + state.EXTRA_TRAVEL_COST, str(state.daily_power_cost()), str(state.daily_power_cost() + state.EXTRA_DAILY_COST)]
	$Expansion/Center/Panel/Margin/Items/Details.text = text
	$Expansion/Center/Panel/Margin/Items/Error.text = state.expansion_problem()
	$Expansion/Center/Panel/Margin/Items/Buttons/Confirm.disabled = not state.expansion_problem().is_empty()

func confirm_expansion() -> void:
	var problem: String = state.expand_carriage()
	if not problem.is_empty():
		$Expansion/Center/Panel/Margin/Items/Error.text = problem
		return
	focused_carriage = state.carriage_count - 1
	_refresh("扩建完成，请返回后在床铺保存。")

func _unhandled_key_input(event: InputEvent) -> void:
	if not active or is_instance_valid(storage_panel) or not event.is_pressed() or event.is_echo():
		return
	if event is InputEventKey and event.keycode == KEY_ESCAPE:
		if $Expansion.visible:
			_refresh("")
		elif $Warehouse.visible:
			$Warehouse.hide()
		elif not selected_id.is_empty() or not hold_kind.is_empty() or moving:
			cancel_selection()
		else:
			exit()
		get_viewport().set_input_as_handled()

func clear_gesture() -> void:
	hold_kind = ""
	hold_elapsed = 0
	hold_cancelled = false
	dragging_furniture = false
	candidate = {}
	if has_node("HoldProgress"):
		$HoldProgress.hide()
	if is_instance_valid(backdrop):
		backdrop.camera_locked = false

func press_furniture(kind: String, at: Vector2) -> void:
	if not active or screen != "construction" or moving:
		return
	hold_kind = kind
	hold_elapsed = 0
	hold_cancelled = false
	pointer = at
	press_position = at
	backdrop.dragging = false
	backdrop.pending_action = Callable()
	backdrop.camera_locked = true
	var placement: Dictionary = state.furniture_layout[kind]
	var local: Vector2 = backdrop.carriage.get_global_transform().affine_inverse() * at
	var rect := Catalog.placement_rect(kind, placement)
	grab_cell = Vector2i(((local - rect.position) / Catalog.CELL_SIZE).floor())
	show_hold_progress()

func show_hold_progress() -> void:
	$HoldProgress.visible = not hold_cancelled
	$HoldProgress.position = (pointer + Vector2(24, -24)).clamp(Vector2(14, 14), size - Vector2(14, 14))
	$HoldProgress.progress = hold_elapsed / HOLD_SECONDS
	$HoldProgress.queue_redraw()

func _process(delta: float) -> void:
	if not active or screen != "construction" or hold_kind.is_empty() or hold_cancelled:
		return
	hold_elapsed = minf(HOLD_SECONDS, hold_elapsed + delta)
	show_hold_progress()
	if hold_elapsed >= HOLD_SECONDS:
		selected_id = hold_kind
		hold_kind = ""
		$HoldProgress.hide()
		dragging_furniture = true
		moving = true
		_refresh("拖到目标格后松开；红色位置不可放置，Esc 可取消。")

func target_at(at: Vector2) -> Dictionary:
	if selected_id.is_empty() or $Toolbar.get_global_rect().has_point(at):
		return {}
	var local: Vector2 = backdrop.carriage.get_global_transform().affine_inverse() * at
	if Catalog.DEFINITIONS[selected_id].placement_type == "hanging":
		for car in range(state.carriage_count):
			for mount in range(Catalog.HANGING_ORIGINS.size()):
				if Catalog.mount_rect(car, mount).has_point(local):
					return {"car": car, "mount": mount, "x": 0, "y": 0}
		return {}
	# Artwork can extend beyond its occupied grid or into an adjacent carriage.
	var anchor := local - Vector2(grab_cell) * Catalog.CELL_SIZE
	var car := floori((anchor.x - 154) / Catalog.CARRIAGE_PITCH)
	if car < 0 or car >= state.carriage_count or anchor.y < 144 or anchor.y > 576:
		return {}
	var cell := Vector2i(((anchor - Catalog.floor_rect(car).position) / Catalog.CELL_SIZE).floor())
	return {"car": car, "x": cell.x, "y": cell.y}

func update_drag_preview() -> void:
	candidate = target_at(pointer)
	backdrop.update_preview(selected_id, candidate, not candidate.is_empty() and can_place_at(candidate))

func finish_drag() -> void:
	var placement := target_at(pointer)
	if not placement.is_empty() and can_place_at(placement):
		place_at(placement)
	else:
		moving = false
		clear_gesture()
		_refresh("落点无效，已保留原位置。")

func _input(event: InputEvent) -> void:
	if not active or screen != "construction" or $Warehouse.visible or $Expansion.visible or is_instance_valid(storage_panel):
		return
	if event is InputEventMouse:
		pointer = event.position
	if event is InputEventMouseMotion:
		if not hold_kind.is_empty() and pointer.distance_to(press_position) > 8 and hold_elapsed < HOLD_SECONDS:
			hold_cancelled = true
			$HoldProgress.hide()
			backdrop.camera_locked = false
		if moving:
			update_drag_preview()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed and not hold_kind.is_empty():
			var kind := hold_kind
			var cancelled := hold_cancelled
			clear_gesture()
			if not cancelled:
				select_furniture(kind)
			get_viewport().set_input_as_handled()
		elif not event.pressed and dragging_furniture:
			finish_drag()
			get_viewport().set_input_as_handled()
		elif event.pressed and moving and not $Toolbar.get_global_rect().has_point(pointer):
			finish_drag()
			get_viewport().set_input_as_handled()


func edit_storage() -> void:
	if selected_id.is_empty() or Catalog.DEFINITIONS[selected_id].storage==Vector2i.ZERO:return
	clear_gesture()
	storage_panel=preload("res://scripts/construction/storage_editor.gd").new();add_child(storage_panel)
	storage_panel.configure(self,selected_id,true)
