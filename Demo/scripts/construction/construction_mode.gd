class_name ConstructionMode
extends Control
## One controller and palette for every catalog furniture instance.
signal expansion_requested
const Catalog = preload("res://scripts/items/furniture_catalog.gd")
var home: Control
var active := false
var selected_id := ""
var moving := false
var registered: Dictionary = {}
@onready var actions: HBoxContainer = $Toolbar/Margin/Actions
@onready var inventory: ItemList = $Warehouse/Center/Panel/Margin/Items/Inventory
@onready var place_button: Button = $Warehouse/Center/Panel/Margin/Items/Buttons/Place

func _ready() -> void:
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
	home = owner_home
	refresh_ui()

func register_furniture(item: Node, data: Resource) -> void:
	item.build_controller = self
	item.selection_requested.connect(select_furniture)
	registered[data.id] = weakref(item)

func enter() -> void:
	if not home.state.can_edit_home():
		return
	active = true
	selected_id = ""
	moving = false
	_refresh("点击车厢中的家具选中，或从家具仓库取出家具。")

func exit() -> void:
	deactivate()
	_refresh("")

func deactivate() -> void:
	active = false
	selected_id = ""
	moving = false
	$Warehouse.hide()
	hide()

func on_page_changed(page: String) -> void:
	registered.clear()
	if page not in ["cabin", "expansion"]:
		deactivate()
	visible = active and page == "cabin"
	$Warehouse.hide()

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
	return active and moving and not selected_id.is_empty() and home.state.furniture_placement_problem(selected_id, slot).is_empty()

func place_at(slot: int) -> void:
	if not active or not moving or selected_id.is_empty():
		return
	var problem: String = home.state.place_furniture(selected_id, slot)
	if problem.is_empty():
		home.focused_carriage = floori(slot / float(Catalog.SLOTS_PER_CARRIAGE))
		moving = false
	_refresh("家具位置已更新，请在床铺保存。" if problem.is_empty() else problem)

func dismantle() -> void:
	if not active or selected_id.is_empty():
		return
	var problem: String = home.state.store_furniture(selected_id)
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
	expansion_requested.emit()

func open_warehouse() -> void:
	if not active:
		return
	inventory.clear()
	for kind in Catalog.IDS:
		if int(home.state.furniture_layout[kind]) >= 0:
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
	if int(home.state.furniture_layout[kind]) >= 0:
		return
	selected_id = kind
	moving = true
	$Warehouse.hide()
	_refresh("请点击兼容空位放置%s。" % Catalog.DEFINITIONS[kind].display_name)

func refresh_ui() -> void:
	visible = active and home != null and home.screen == "cabin"
	if not visible:
		return
	var has_selection := not selected_id.is_empty()
	actions.get_node("Selection").text = ("移动中：" if moving else "已选中：") + Catalog.DEFINITIONS[selected_id].display_name if has_selection else "点击家具选中，再移动或拆除"
	actions.get_node("Move").disabled = not has_selection or moving
	actions.get_node("Dismantle").disabled = not has_selection or int(home.state.furniture_layout[selected_id]) < 0
	actions.get_node("Cancel").disabled = not has_selection

func _refresh(message: String) -> void:
	home.show_cabin(message)

func _unhandled_key_input(event: InputEvent) -> void:
	if not active or not event.is_pressed() or event.is_echo():
		return
	if event is InputEventKey and event.keycode == KEY_ESCAPE:
		if $Warehouse.visible:
			$Warehouse.hide()
		elif not selected_id.is_empty():
			cancel_selection()
		else:
			exit()
		get_viewport().set_input_as_handled()
