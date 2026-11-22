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
const HOLD_SECONDS := 0.5
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
var context_panel: PanelContainer
var context_actions: VBoxContainer
var dismantle_dialog: ConfirmationDialog
var warehouse_mode := "temporary"
var building_new := false
var build_panel: Control
@onready var actions: HBoxContainer = $Toolbar/Margin/Actions
@onready var inventory: ItemList = $Warehouse/Center/Panel/Margin/Items/Inventory
@onready var place_button: Button = $Warehouse/Center/Panel/Margin/Items/Buttons/Place

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_PASS
	_setup_theme()
	$Expansion/Center/Panel/Margin/Items/Buttons/Confirm.pressed.connect(confirm_expansion)
	$Expansion/Center/Panel/Margin/Items/Buttons/Back.pressed.connect(func(): _refresh(""))
	actions.get_node("Warehouse").pressed.connect(open_warehouse)
	actions.get_node("Warehouse").text="临时收纳仓库"
	var build_button:=Button.new();build_button.name="Build";build_button.text="建造 / 摆放";actions.add_child(build_button);build_button.pressed.connect(open_build_menu)
	actions.get_node("Expand").pressed.connect(request_expansion)
	actions.get_node("Exit").pressed.connect(exit)
	var check_button:=Button.new();check_button.name="Check";check_button.text="检查装修";actions.add_child(check_button)
	check_button.pressed.connect(func():
		var problem: String=state.furniture_completion_problem()
		$Message.text="检查通过，可以退出装修。" if problem.is_empty() else problem)
	context_panel=PanelContainer.new();context_panel.name="FurnitureActions";context_panel.z_index=60;context_panel.hide();add_child(context_panel)
	context_actions=VBoxContainer.new();context_panel.add_child(context_actions)
	for spec in [["Storage","查看储物格",edit_storage],["Temporary","临时收纳",temporarily_store_selected],["Dismantle","分解",dismantle]]:
		var button:=Button.new();button.name=spec[0];button.text=spec[1];button.custom_minimum_size=Vector2(158,34);context_actions.add_child(button);button.pressed.connect(spec[2])
	var temp_decompose:=Button.new();temp_decompose.name="Decompose";temp_decompose.text="分解选中";$Warehouse/Center/Panel/Margin/Items/Buttons.add_child(temp_decompose);temp_decompose.pressed.connect(decompose_selected_temporary)
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
	forward_inventory_drop(item)
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
	state.renovation_active=true
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
	_refresh("选中家具使用右上角操作；临时收纳必须在完成装修前清空。")

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
	if is_instance_valid(build_panel):build_panel.queue_free()
	clear_gesture()
	active = false
	state.renovation_active=false
	context_panel.hide()
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
	building_new=false
	moving = false
	_refresh("已选中%s，长按0.5秒拖动；右上角可查看储物、收纳或分解。" % Catalog.DEFINITIONS[kind].display_name)

func can_place_at(placement: Dictionary) -> bool:
	return active and moving and not selected_id.is_empty() and (not building_new or state.build_requirements_problem(selected_id).is_empty()) and state.furniture_placement_problem(selected_id, placement).is_empty()

func place_at(placement: Dictionary) -> void:
	if not active or not moving or selected_id.is_empty():
		return
	var problem: String = state.build_furniture(selected_id,placement) if building_new else state.place_furniture(selected_id, placement)
	if problem.is_empty():
		focused_carriage = int(placement.car)
		moving = false
		building_new=false
		clear_gesture()
	_refresh("家具位置已更新，请在床铺保存。" if problem.is_empty() else problem)

func dismantle() -> void:
	if not active or selected_id.is_empty():return
	request_decomposition(selected_id)

func request_decomposition(id: String) -> void:
	var problem: String=state.Renovation.decomposition_problem(state,id)
	if not problem.is_empty():$Message.text=problem;return
	if is_instance_valid(dismantle_dialog):dismantle_dialog.hide();dismantle_dialog.queue_free()
	dismantle_dialog=ConfirmationDialog.new();dismantle_dialog.name="DecompositionConfirmation";dismantle_dialog.title="确认分解家具";dismantle_dialog.ok_button_text="确认分解";dismantle_dialog.cancel_button_text="取消"
	var definition: Resource=Catalog.DEFINITIONS[id]
	dismantle_dialog.dialog_text="分解%s？家具将被消耗。\n消耗：%s\n获得：%s" % [definition.display_name,recipe_text(definition.dismantle_cost),recipe_text(definition.salvage)]
	add_child(dismantle_dialog)
	dismantle_dialog.confirmed.connect(func():
		var result: String=state.decompose_furniture(id)
		if result.is_empty():selected_id="";moving=false;building_new=false
		$Warehouse.hide();_refresh("家具已分解。" if result.is_empty() else result))
	dismantle_dialog.popup_centered(Vector2i(470,210))

func recipe_text(recipe: Dictionary) -> String:
	var names: PackedStringArray=[]
	for kind in recipe:names.append("%s × %d" % [state.item_name(kind),int(recipe[kind])])
	return "无" if names.is_empty() else "、".join(names)

func temporarily_store_selected() -> void:
	var problem: String=state.temporarily_store_furniture(selected_id)
	if problem.is_empty():selected_id="";moving=false
	_refresh("家具已临时收纳；完成装修前请放回或分解；物品类家具可摆放后拖入储物格。" if problem.is_empty() else problem)

func selected_temporary() -> String:
	var selected:=inventory.get_selected_items()
	return "" if selected.is_empty() else str(inventory.get_item_metadata(selected[0]))
func decompose_selected_temporary() -> void:
	var id:=selected_temporary()
	if not id.is_empty():request_decomposition(id)

func cancel_selection() -> void:
	clear_gesture()
	selected_id = ""
	moving = false
	building_new=false
	_refresh("")

func request_expansion() -> void:
	close_storage_dock()
	clear_gesture()
	if not active:
		return
	selected_id = ""
	moving = false
	show_expansion()

func open_warehouse() -> void:
	close_storage_dock()
	show_furniture_list("temporary")
func open_build_menu() -> void:
	if not active:return
	close_storage_dock()
	cancel_selection();$Warehouse.hide()
	if is_instance_valid(build_panel):build_panel.queue_free()
	build_panel=preload("res://scripts/construction/build_panel.gd").new();add_child(build_panel);build_panel.configure(self)
	build_panel.build_requested.connect(select_build_kind)
	context_panel.hide()
func select_build_kind(kind: String) -> void:
	var problem: String=state.build_requirements_problem(kind)
	if not problem.is_empty():$Message.text=problem;return
	if is_instance_valid(build_panel):build_panel.queue_free()
	selected_id=state.Renovation.next_id(state,kind);moving=true;building_new=true;grab_cell=Vector2i.ZERO
	_refresh("点击兼容位置放置%s；成功后扣除所需物品和材料。" % Catalog.DEFINITIONS[selected_id].display_name)
func show_furniture_list(mode: String) -> void:
	if not active:return
	cancel_selection();warehouse_mode=mode;inventory.clear()
	var items: Array=state.temporary_furniture if mode=="temporary" else Catalog.IDS
	for id in items:
		var definition: Resource=Catalog.DEFINITIONS[id]
		if mode=="build" and not definition.enabled:continue
		var text: String=definition.display_name
		if mode=="build":text+=" · "+(state.item_name(definition.item_id)+" × 1" if not definition.item_id.is_empty() else recipe_text(definition.build_cost))
		inventory.add_item(text,definition.texture);inventory.set_item_metadata(inventory.item_count-1,id)
	place_button.disabled=inventory.item_count==0
	if inventory.item_count>0:inventory.select(0)
	$Warehouse/Center/Panel/Margin/Items/Title.text="临时收纳仓库" if mode=="temporary" else "建造 / 从物品摆放"
	$Warehouse/Center/Panel/Margin/Items/Help.text="完成装修前必须清空；这些家具不会在分解后重新出现。" if mode=="temporary" else "放置成功后才消耗材料或对应物品。"
	$Warehouse/Center/Panel/Margin/Items/Empty.visible=inventory.item_count==0
	$Warehouse/Center/Panel/Margin/Items/Empty.text="临时收纳仓库为空。" if mode=="temporary" else "没有可建造的家具。"
	for node in ["Decompose"]:$Warehouse/Center/Panel/Margin/Items/Buttons.get_node(node).visible=mode=="temporary"
	$Warehouse.show();context_panel.hide();inventory.grab_focus()

func take_from_warehouse() -> void:
	if not active:
		return
	var selected := inventory.get_selected_items()
	if selected.is_empty():
		return
	var kind: String = inventory.get_item_metadata(selected[0])
	building_new=warehouse_mode=="build"
	if not building_new and kind not in state.temporary_furniture:return
	selected_id = state.Renovation.next_id(state,kind) if building_new else kind
	moving = true
	$Warehouse.hide()
	grab_cell = Vector2i.ZERO
	_refresh("请点击兼容格放置%s。" % Catalog.DEFINITIONS[kind].display_name)

func refresh_ui() -> void:
	visible = active
	if not visible:
		return
	var has_selection := not selected_id.is_empty()
	actions.get_node("Selection").text = "装修 · " + (("移动中：" if moving else "已选中：") + Catalog.DEFINITIONS[selected_id].display_name if has_selection else "长按家具0.5秒后拖动，或点击选中拆除")
	var at: Variant=state.furniture_layout.get(selected_id)
	context_panel.visible=has_selection and at!=null and not moving and not $Warehouse.visible
	if context_panel.visible:
		context_actions.get_node("Storage").visible=Catalog.DEFINITIONS[selected_id].storage!=Vector2i.ZERO
	update_context_position()

func update_context_position() -> void:
	if not is_instance_valid(context_panel) or not context_panel.visible or not registered.has(selected_id):return
	var item: Control=registered[selected_id].get_ref()
	if not is_instance_valid(item):context_panel.hide();return
	var rect:=item.get_global_rect()
	context_panel.position=Vector2(rect.end.x+8,rect.position.y).clamp(Vector2(8,76),size-context_panel.size-Vector2(8,8))

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
	forward_inventory_drop(backdrop)
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
	if not active or is_instance_valid(storage_panel) or is_instance_valid(build_panel) or not event.is_pressed() or event.is_echo():
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
	building_new=false
	if is_instance_valid(storage_panel):storage_panel.clear_selection()
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
	if active:update_context_position()
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
	if selected_id.is_empty() or $Toolbar.get_global_rect().has_point(at) or (context_panel.visible and context_panel.get_global_rect().has_point(at)):
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
	if Catalog.DEFINITIONS[selected_id].wall_cells.is_empty() and not Catalog.DEFINITIONS[selected_id].floor_cells.is_empty():
		var bottom:=0
		for occupied in Catalog.DEFINITIONS[selected_id].floor_cells:bottom=maxi(bottom,occupied.y+1)
		if absf(anchor.y+bottom*Catalog.CELL_SIDE-Catalog.GROUND_EDGE_Y)<=Catalog.CELL_SIDE*0.45:cell.y=Catalog.GRID_SIZE.y-bottom
	return {"car": car, "x": cell.x, "y": cell.y}

func update_drag_preview() -> void:
	candidate = target_at(pointer)
	backdrop.update_preview(selected_id, candidate, not candidate.is_empty() and can_place_at(candidate))

func finish_drag() -> void:
	if is_instance_valid(storage_panel) and storage_panel.contains_point(pointer):
		var cell: Vector2i=storage_panel.furniture_cell_at(pointer)
		var problem: String="请拖入左侧储物格。" if cell.x<0 else state.Renovation.pack_item_at(state,selected_id,storage_panel.target,cell)
		moving=false;clear_gesture()
		if problem.is_empty():selected_id="";storage_panel.redraw()
		_refresh("家具已收纳为物品。" if problem.is_empty() else problem)
		return
	var placement := target_at(pointer)
	if not placement.is_empty() and can_place_at(placement):
		place_at(placement)
	else:
		var problem: String="指针不在可布置区域。" if placement.is_empty() else state.furniture_placement_problem(selected_id,placement)
		if building_new and problem.is_empty():problem=state.build_requirements_problem(selected_id)
		moving = false
		clear_gesture()
		_refresh(problem+" 已保留原位置。")

func _input(event: InputEvent) -> void:
	if not active or screen != "construction" or $Warehouse.visible or $Expansion.visible or is_instance_valid(build_panel) or (is_instance_valid(dismantle_dialog) and dismantle_dialog.visible):
		return
	if event is InputEventMouse:
		pointer = event.position
		if is_instance_valid(storage_panel) and storage_panel.contains_point(pointer) and not dragging_furniture and hold_kind.is_empty():return
	if get_viewport().gui_is_dragging():return
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
		elif event.pressed and moving and not $Toolbar.get_global_rect().has_point(pointer) and not (context_panel.visible and context_panel.get_global_rect().has_point(pointer)):
			finish_drag()
			get_viewport().set_input_as_handled()


func edit_storage() -> void:
	if selected_id.is_empty() or Catalog.DEFINITIONS[selected_id].storage==Vector2i.ZERO:return
	clear_gesture()
	close_storage_dock()
	storage_panel=preload("res://scripts/construction/storage_editor.gd").new();add_child(storage_panel)
	storage_panel.configure(self,selected_id,false)
	context_panel.hide()
	storage_panel.tree_exited.connect(refresh_ui)

# Native inventory drags can leave the left dock and become upright furniture.
func inventory_furniture(payload: Variant) -> String:
	if not is_instance_valid(storage_panel) or not payload is Dictionary or payload!=storage_panel.selection:return ""
	var entry: Dictionary=state.picked(payload.get("source",""),int(payload.get("id",-1)))
	if entry.is_empty():return ""
	for id in Catalog.IDS:
		var definition: Resource=Catalog.DEFINITIONS[id]
		if definition.enabled and not definition.item_id.is_empty() and state.ItemCatalog.runtime_id(definition.item_id)==entry.kind:return id
	return ""

func inventory_drop_target(at: Vector2,id: String) -> Dictionary:
	var previous:=selected_id;var previous_grab:=grab_cell
	selected_id=id;grab_cell=Vector2i.ZERO
	var result:=target_at(at)
	selected_id=previous;grab_cell=previous_grab
	return result

func _can_drop_data(at: Vector2,payload: Variant) -> bool:
	at=pointer # Use the last viewport event, also valid for injected/remote drags.
	if not active:return false
	var id:=inventory_furniture(payload)
	if id.is_empty() or storage_panel.contains_point(at):return false
	id=state.Renovation.next_id(state,id)
	var target:=inventory_drop_target(at,id)
	return not target.is_empty() and state.furniture_placement_problem(id,target).is_empty()

func _drop_data(at: Vector2,payload: Variant) -> void:
	at=pointer
	var base:=inventory_furniture(payload)
	if base.is_empty():return
	var id: String=state.Renovation.next_id(state,base)
	# Select the exact dragged item, rather than consuming a different instance.
	var entry: Dictionary=state.picked(payload.source,payload.id)
	var target:=inventory_drop_target(at,id)
	var problem: String=state.furniture_placement_problem(id,target)
	if problem.is_empty():
		state.entries(payload.source).erase(entry)
		if id not in state.furniture_owned:state.furniture_owned.append(id)
		state.temporary_furniture.append(id)
		problem=state.place_furniture(id,target)
		if not problem.is_empty():
			state.entries(payload.source).append(entry);state.furniture_owned.erase(id);state.temporary_furniture.erase(id)
		else:selected_id=id;storage_panel.clear_selection();storage_panel.redraw()

	_refresh("物品已摆放为家具，朝向已恢复。" if problem.is_empty() else problem)

func forward_inventory_drop(control: Control) -> void:
	control.set_drag_forwarding(Callable(),func(at: Vector2,payload: Variant):return _can_drop_data(control.get_global_transform_with_canvas()*at,payload),func(at: Vector2,payload: Variant):_drop_data(control.get_global_transform_with_canvas()*at,payload))

func close_storage_dock() -> void:
	if not is_instance_valid(storage_panel):return
	var previous:=storage_panel
	storage_panel=null
	remove_child(previous);previous.queue_free()
