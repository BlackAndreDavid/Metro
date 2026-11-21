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
var width_input: SpinBox
var height_input: SpinBox
var grid_layer: Control

func configure(owner_ui: Control, furniture_kind: String, allow_resize: bool) -> void:
	state=owner_ui.state;font=owner_ui.font;kind=furniture_kind;target=state.storage_container(kind)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_STOP
	var veil:=ColorRect.new();veil.color=Color("100e1cdd");veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(veil)
	var panel:=Panel.new();panel.position=Vector2(130,84);panel.size=Vector2(1020,550);add_child(panel)
	var title:=Label.new();title.text=state.Furniture.DEFINITIONS[kind].display_name+" · 储物格";title.position=Vector2(24,20);panel.add_child(title)
	var close:=Button.new();close.text="关闭";close.position=Vector2(920,16);panel.add_child(close);close.pressed.connect(queue_free)
	if allow_resize:
		width_input=SpinBox.new();height_input=SpinBox.new()
		var dimensions: Vector2i=state.grid_size(target)
		for input in [width_input,height_input]:input.min_value=1;input.max_value=16;input.step=1;panel.add_child(input)
		width_input.position=Vector2(24,65);width_input.value=dimensions.x
		height_input.position=Vector2(174,65);height_input.value=dimensions.y
		var resize_button:=Button.new();resize_button.text="应用储物格宽 × 高";resize_button.position=Vector2(324,65);panel.add_child(resize_button)
		resize_button.pressed.connect(func():
			var problem: String=state.resize_furniture_storage(kind,Vector2i(int(width_input.value),int(height_input.value)))
			message.text="储物格已调整，缩小时不会删除物品。" if problem.is_empty() else problem
			if problem.is_empty():selection={};rebuild_grids())
	grid_layer=Control.new();grid_layer.position=Vector2(24,126);panel.add_child(grid_layer);rebuild_grids()
	message=Label.new();message.position=Vector2(24,492);message.size=Vector2(970,45);message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;message.text="拖拽在家具与背包之间转移 · R/滚轮旋转 · F镜像 · Shift+点击快速转移";panel.add_child(message)

func rebuild_grids() -> void:
	for child in grid_layer.get_children():child.queue_free()
	grids.clear()
	for container in [target,"bag"]:
		var grid=preload("res://scripts/cargo_grid.gd").new();grid_layer.add_child(grid)
		grid.position=Vector2(0 if container==target else 590,0)
		var dimensions: Vector2i=state.grid_size(container)
		grid.setup(self,container,mini(38,mini(540/dimensions.x,350/dimensions.y)));grids.append(grid)

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
	var problem: String=state.auto_place(selection,"bag" if selection.source==target else target)
	message.text="物品已转移。" if problem.is_empty() else problem
	if problem.is_empty():clear_selection()
