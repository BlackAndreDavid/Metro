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
var registered: Dictionary = {}
@onready var actions: HBoxContainer = $Toolbar/Margin/Actions
@onready var inventory: ItemList = $Warehouse/Center/Panel/Margin/Items/Inventory
@onready var place_button: Button = $Warehouse/Center/Panel/Margin/Items/Buttons/Place

func _ready() -> void:
	_setup_theme()
	$Expansion/Center/Panel/Margin/Items/Buttons/Confirm.pressed.connect(confirm_expansion)
	$Expansion/Center/Panel/Margin/Items/Buttons/Back.pressed.connect(func(): _refresh(""))
	actions.get_node("Move").pressed.connect(begin_move)
	actions.get_node("Dismantle").pressed.connect(dismantle)
	actions.get_node("Cancel").pressed.connect(cancel_selection)
	actions.get_node("Warehouse").pressed.connect(open_warehouse)
	actions.get_node("Expand").pressed.connect(request_expansion)
	actions.get_node("Exit").pressed.connect(exit)
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
	deactivate()
	var source: Control = _return_scene.get_ref() if _return_scene != null else null
	if is_instance_valid(source):
		source.focused_carriage = focused_carriage
		source.process_mode = _return_process_mode
		source.show()
		get_tree().current_scene = _previous_current_scene
		source.show_cabin()

func deactivate() -> void:
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
	_refresh("已选中%s，可移动或拆除。" % Catalog.DEFINITIONS[kind].display_name)

func begin_move() -> void:
	if not active or selected_id.is_empty():
		return
	moving = true
	_refresh("点击兼容空位完成移动；取消不会改变原摆放位置。")

func can_place_at(slot: int) -> bool:
	return active and moving and not selected_id.is_empty() and state.furniture_placement_problem(selected_id, slot).is_empty()

func place_at(slot: int) -> void:
	if not active or not moving or selected_id.is_empty():
		return
	var problem: String = state.place_furniture(selected_id, slot)
	if problem.is_empty():
		focused_carriage = floori(slot / float(Catalog.SLOTS_PER_CARRIAGE))
		moving = false
	_refresh("家具位置已更新，请在床铺保存。" if problem.is_empty() else problem)

func dismantle() -> void:
	if not active or selected_id.is_empty():
		return
	var problem: String = state.store_furniture(selected_id)
	if problem.is_empty():
		selected_id = ""
		moving = false
	_refresh("家具已拆除并收纳到家具仓库。" if problem.is_empty() else problem)

func cancel_selection() -> void:
	selected_id = ""
	moving = false
	_refresh("")

func request_expansion() -> void:
	if not active:
		return
	selected_id = ""
	moving = false
	show_expansion()

func open_warehouse() -> void:
	if not active:
		return
	inventory.clear()
	for kind in Catalog.IDS:
		if int(state.furniture_layout[kind]) >= 0:
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
	if int(state.furniture_layout[kind]) >= 0:
		return
	selected_id = kind
	moving = true
	$Warehouse.hide()
	_refresh("请点击兼容空位放置%s。" % Catalog.DEFINITIONS[kind].display_name)

func refresh_ui() -> void:
	visible = active
	if not visible:
		return
	var has_selection := not selected_id.is_empty()
	actions.get_node("Selection").text = "建造模式 · " + (("移动中：" if moving else "已选中：") + Catalog.DEFINITIONS[selected_id].display_name if has_selection else "点击家具选中，再移动或拆除")
	actions.get_node("Move").disabled = not has_selection or moving
	actions.get_node("Dismantle").disabled = not has_selection or int(state.furniture_layout[selected_id]) < 0
	actions.get_node("Cancel").disabled = not has_selection

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
	refresh_ui()

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
	if not active or not event.is_pressed() or event.is_echo():
		return
	if event is InputEventKey and event.keycode == KEY_ESCAPE:
		if $Expansion.visible:
			_refresh("")
		elif $Warehouse.visible:
			$Warehouse.hide()
		elif not selected_id.is_empty():
			cancel_selection()
		else:
			exit()
		get_viewport().set_input_as_handled()
