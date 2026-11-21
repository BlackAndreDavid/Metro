extends Control
signal build_requested(id: String)
var state: RefCounted
var rows: VBoxContainer
var scroll: ScrollContainer
var last_signature := ""
var elapsed := 0.0
const READY:=Color("82d9ad")
const LOCKED:=Color("8c899b")

func configure(owner_mode: Control) -> void:
	state=owner_mode.state;theme=owner_mode.theme;z_index=100
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_STOP
	var veil:=ColorRect.new();veil.color=Color("100e1cdd");veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(veil)
	var panel:=PanelContainer.new();panel.position=Vector2(184,82);panel.size=Vector2(912,556);add_child(panel)
	var margin:=MarginContainer.new();for side in ["left","top","right","bottom"]:margin.add_theme_constant_override("margin_"+side,16)
	panel.add_child(margin)
	var body:=VBoxContainer.new();body.add_theme_constant_override("separation",12);margin.add_child(body)
	var header:=HBoxContainer.new();body.add_child(header)
	var title:=Label.new();title.text="建造 / 摆放已知家具";title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(title)
	var close:=Button.new();close.name="Close";close.text="关闭";header.add_child(close);close.pressed.connect(queue_free)
	var hint:=Label.new();hint.text="全部满足的家具置顶并按ID排序；成功放置后才消耗物品与材料。";hint.add_theme_font_size_override("font_size",14);body.add_child(hint)
	scroll=ScrollContainer.new();scroll.name="BuildScroll";scroll.custom_minimum_size=Vector2(860,430);scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;body.add_child(scroll)
	rows=VBoxContainer.new();rows.name="FurnitureRows";rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL;rows.add_theme_constant_override("separation",8);scroll.add_child(rows)
	refresh()

func signature() -> String:
	return JSON.stringify([state.technologies,state.auto_repair_level,state.all_base_cargo(),state.inventory,state.active_item,state.learned_furniture])
func _process(delta: float) -> void:
	if state==null:return
	elapsed+=delta
	if elapsed>=0.2:
		elapsed=0
		if signature()!=last_signature:refresh()

func refresh() -> void:
	var old_scroll:=scroll.scroll_vertical
	for child in rows.get_children():rows.remove_child(child);child.queue_free()
	var options: Array=state.build_options()
	for option in options:
		var definition: Resource=state.Furniture.DEFINITIONS[option.id]
		var row:=PanelContainer.new();row.name=option.id;row.set_meta("ready",option.ready);rows.add_child(row)
		var background:=StyleBoxFlat.new();background.bg_color=Color("263d37") if option.ready else Color("292835");background.border_color=READY.darkened(.4) if option.ready else LOCKED.darkened(.55);background.set_border_width_all(1)
		for side in ["left","right","top","bottom"]:background.set("content_margin_"+side,10.0)
		row.add_theme_stylebox_override("panel",background)
		var line:=HBoxContainer.new();line.add_theme_constant_override("separation",14);row.add_child(line)
		var frame:=Control.new();frame.name="ThumbnailFrame";frame.custom_minimum_size=Vector2(96,72);frame.size_flags_vertical=Control.SIZE_SHRINK_CENTER;line.add_child(frame)
		var image:=TextureRect.new();image.name="Texture";image.size=Vector2(96,72);image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;image.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;image.texture=definition.texture;image.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;image.modulate=Color.WHITE if option.ready else Color(.55,.55,.6,.65);frame.add_child(image)
		var details:=VBoxContainer.new();details.name="Requirements";details.size_flags_horizontal=Control.SIZE_EXPAND_FILL;line.add_child(details)
		var name_label:=Label.new();name_label.text=definition.display_name+" · "+option.id;name_label.add_theme_color_override("font_color",Color("f2eadd") if option.ready else LOCKED);details.add_child(name_label)
		if option.conditions.is_empty():add_condition(details,"技术：无需技术   材料：无",true)
		for condition in option.conditions:add_condition(details,condition.text,condition.met)
		var choose:=Button.new();choose.name="Build";choose.text="摆放" if not definition.item_id.is_empty() else "建造";choose.disabled=not option.ready;choose.custom_minimum_size=Vector2(80,40);choose.size_flags_vertical=Control.SIZE_SHRINK_CENTER;line.add_child(choose)
		choose.pressed.connect(func():build_requested.emit(option.id))
	if options.is_empty():var empty:=Label.new();empty.text="没有已知家具。";rows.add_child(empty)
	scroll.set_deferred("scroll_vertical",old_scroll);last_signature=signature()

func add_condition(parent: Control,text: String,met: bool) -> void:
	var label:=Label.new();label.text=("✓ " if met else "✕ ")+text;label.set_meta("met",met);label.add_theme_font_size_override("font_size",14);label.add_theme_color_override("font_color",READY if met else LOCKED);parent.add_child(label)
