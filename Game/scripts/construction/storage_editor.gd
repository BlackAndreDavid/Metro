extends Control
## Shared cargo grid and placement rules for Home and renovation storage inspectors.
var state: RefCounted
var font: Font
var kind := ""
var target := ""
var selection: Dictionary = {}
var grids: Array = []
var pointer_position := Vector2.ZERO
var message: Label
var grid_layer: Control
var show_backpack := true
var owner_mode: Control
var panel: Panel

func configure(owner_ui: Control, furniture_kind: String, show_bag: bool = true) -> void:
	owner_mode=owner_ui;state=owner_ui.state;font=owner_ui.font;kind=furniture_kind;target=state.storage_container(kind);show_backpack=show_bag;z_index=110
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_STOP if show_backpack else Control.MOUSE_FILTER_IGNORE
	if show_backpack:
		var veil:=ColorRect.new();veil.color=Color("100e1cdd");veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(veil)
	panel=Panel.new();panel.name="StorageDock";panel.position=Vector2(130,84) if show_backpack else Vector2(0,78);panel.size=Vector2(1020,550) if show_backpack else Vector2(336,550);panel.mouse_filter=Control.MOUSE_FILTER_STOP;add_child(panel)
	var title:=Label.new();title.text=state.Furniture.DEFINITIONS[kind].display_name+" · 储物格";title.position=Vector2(24,20);panel.add_child(title)
	var close:=Button.new();close.text="关闭";close.position=Vector2(920 if show_backpack else 264,16);panel.add_child(close);close.pressed.connect(queue_free)
	if not show_backpack:
		var take:=Button.new();take.name="TakeSelected";take.text="取出选中到背包";take.position=Vector2(16,440);panel.add_child(take);take.pressed.connect(take_selected_to_bag)
		var take_all:=Button.new();take_all.name="TakeAll";take_all.text="全部取出";take_all.position=Vector2(208,440);panel.add_child(take_all);take_all.pressed.connect(take_all_to_bag)
	grid_layer=Control.new();grid_layer.position=Vector2(24,126) if show_backpack else Vector2(16,155);panel.add_child(grid_layer);rebuild_grids()
	message=Label.new();message.position=Vector2(24 if show_backpack else 16,492);message.size=Vector2(970 if show_backpack else 304,45);message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;message.text="家具长按0.5秒后拖入格子收纳；格内物品可拖回车厢摆放。R旋转 · F镜像" if not show_backpack else "拖拽在家具与背包之间转移 · R/滚轮旋转 · F镜像 · Shift+点击快速转移";panel.add_child(message)

func rebuild_grids() -> void:
	for child in grid_layer.get_children():child.queue_free()
	grids.clear()
	for container in ([target,"bag"] if show_backpack else [target]):
		if container=="bag" and state.backpack_item.is_empty():continue
		var grid=preload("res://scripts/cargo_grid.gd").new();grid_layer.add_child(grid)
		grid.position=Vector2(0 if container==target else 590,0)
		var dimensions: Vector2i=state.grid_size(container)
		var cell_size:=mini(38,mini((540 if show_backpack else 304)/dimensions.x,(270 if not show_backpack else 350)/dimensions.y))
		grid.setup(self,container,cell_size)
		if not show_backpack:grid.position.x=(304-grid.size.x)/2
		grids.append(grid)

func _input(event: InputEvent) -> void:
	if event is InputEventMouse:pointer_position=event.position
	if selection.is_empty():return
	if event is InputEventKey and event.pressed:
		if event.keycode==KEY_R:selection.rotated=not selection.rotated
		elif event.keycode==KEY_F:selection.mirrored=not selection.get("mirrored",false)
		elif event.keycode==KEY_ESCAPE:clear_selection()
		else:return
		get_viewport().set_input_as_handled();redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		selection.rotated=not selection.rotated;redraw();get_viewport().set_input_as_handled()
func redraw() -> void:
	for grid in grids:grid.queue_redraw()
func select_cargo(source: String, id: int) -> void:
	var entry: Dictionary=state.picked(source,id)
	if not entry.is_empty():selection={"source":source,"id":id,"rotated":entry.rotated,"mirrored":entry.get("mirrored",false)};redraw()
func clear_selection() -> void:
	selection={};redraw()
func click_cell(container: String, cell: Vector2i) -> void:
	if not selection.is_empty():move_cargo(container,cell)
	else:
		var entry: Dictionary=state.entry_at(container,cell)
		if not entry.is_empty():select_cargo(container,entry.id)
func move_cargo(container: String, cell: Vector2i) -> void:
	if state.place(selection,container,cell):clear_selection();message.text="物品已转移。"
	else:message.text="无法放置，请检查空位与物品方向。"
	redraw()
func drag_preview() -> Control:
	var label:=Label.new();var entry: Dictionary=state.picked(selection.source,selection.id);label.text=state.item_name(entry.kind);return label
func quick_place_selected() -> void:
	if selection.is_empty():return
	var problem: String=state.sort_container(target) if not show_backpack else state.auto_place(selection,"bag" if selection.source==target else target)
	message.text="物品已转移。" if problem.is_empty() else problem
	if problem.is_empty():clear_selection()


func take_selected_to_bag() -> void:
	if selection.is_empty():message.text="请先选择物品。";return
	var problem: String=state.auto_place(selection,"bag")
	if problem.is_empty():clear_selection()
	message.text="物品已取出。" if problem.is_empty() else problem
	redraw()
func take_all_to_bag() -> void:
	var count:=0
	for entry in state.entries(target).duplicate():
		if state.auto_place({"source":target,"id":entry.id,"rotated":entry.rotated},"bag").is_empty():count+=1
	clear_selection();message.text="已取出%d件物品；背包装不下的物品仍在原处。" % count;redraw()

func contains_point(at: Vector2) -> bool:
	return panel.get_global_rect().has_point(at)

func furniture_cell_at(at: Vector2) -> Vector2i:
	if grids.is_empty():return Vector2i(-1,-1)
	var grid: Control=grids[0]
	if not grid.get_global_rect().has_point(at):return Vector2i(-1,-1)
	return grid.cell_at(grid.get_global_transform_with_canvas().affine_inverse()*at)
