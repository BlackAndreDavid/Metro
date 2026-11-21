extends Control
var state: RefCounted
var street: Control
var controller: Control
var cabinet: String
var contents: VBoxContainer
func setup(owner_state: RefCounted, surface: Control, home: Control, id: String) -> void:
	state = owner_state; street = surface; controller = home; cabinet = id
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new();dim.color = Color(0,0,0,0.7);dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(dim)
	var panel := PanelContainer.new();panel.position = Vector2(300,170);panel.size = Vector2(600,420);add_child(panel)
	var column := VBoxContainer.new();column.add_theme_constant_override("separation",12);panel.add_child(column)
	var title := Label.new();title.text = "储物柜 · 物资";title.add_theme_font_size_override("font_size",24);column.add_child(title)
	var scroll := ScrollContainer.new();scroll.custom_minimum_size = Vector2(560,300);column.add_child(scroll)
	contents = VBoxContainer.new();contents.size_flags_horizontal = Control.SIZE_EXPAND_FILL;scroll.add_child(contents)
	var take_all:=Button.new();take_all.name="TakeAll";take_all.text="一键拾取全部";take_all.pressed.connect(take_all_items);column.add_child(take_all)
	var close := Button.new();close.text = "关闭柜子";close.pressed.connect(finish);column.add_child(close)
	street.inspecting_container = true
	refresh()
func refresh() -> void:
	for child in contents.get_children():contents.remove_child(child);child.queue_free()
	var found := false
	for slot in range(street.LOOT.size()):
		if street.LOOT[slot].get("cabinet","") != cabinet:continue
		var kind: String = state.ground_kind(slot)
		if kind.is_empty():continue
		found = true
		var row := HBoxContainer.new();contents.add_child(row)
		var texture := TextureRect.new();texture.custom_minimum_size = Vector2(48,48);texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE;texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED;texture.texture = state.ITEM_DEFINITIONS[kind].texture;row.add_child(texture)
		var take := Button.new();take.text = "拿取 · "+state.item_name(kind);take.size_flags_horizontal = Control.SIZE_EXPAND_FILL;take.pressed.connect(take_item.bind(slot));row.add_child(take)
	if not found:
		var empty := Label.new();empty.text = "柜子是空的。";contents.add_child(empty)
func take_item(slot: int) -> void:
	if not street.can_take(slot) or not state.pick_up_ground(slot):controller.report("无法拿取：检查距离、背包空间和剩余时间。");return
	controller.update_surface_pack(true)
	controller.report("物资已放入背包。")
	refresh()
func finish() -> void:
	if is_instance_valid(street):street.inspecting_container = false
	queue_free()

func take_all_items()->void:
	var slots:Array=[]
	for slot in range(street.LOOT.size()):
		if street.LOOT[slot].get("cabinet","")==cabinet:slots.append(slot)
	var count:int=controller.quick_pickup_slots(slots)
	controller.report("已拾取%d件，未装下的物资保留在柜子中。" % count)
	refresh()
