extends PanelContainer
## Four physical equipment positions, reused by departure and exploration.
var home: Control
var active: Control
var suit: Label
var backpack: Control
var pocket: Control
var battery_grid: Control # Legacy callers tolerate this empty reference.
var preparation_mode := false
var equipment_grids: Array = []

func configure(controller: Control,preparing: bool = false,preparation_cell_size: int = 36) -> void:
	home=controller;preparation_mode=preparing
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",16 if preparing else 8);add_child(row)
	var positions: BoxContainer=row
	if preparing:
		positions=VBoxContainer.new();positions.add_theme_constant_override("separation",6)
	var helmet:=VBoxContainer.new();helmet.name="Helmet";helmet.custom_minimum_size=Vector2(112 if preparing else 90,80);row.add_child(helmet)
	var title:=Label.new();title.text="头盔";title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;helmet.add_child(title)
	suit=Label.new();suit.custom_minimum_size=Vector2(90,60);suit.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;suit.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;suit.tooltip_text="头盔随所租防护服自动变化。";helmet.add_child(suit)
	if preparing:row.add_child(positions)
	backpack=make_position(positions,"backpack","背包",preparation_cell_size if preparing else 20)
	pocket=make_position(positions,"pocket","口袋",preparation_cell_size if preparing else 26)
	active=make_position(positions,"active","主动 [空格]",preparation_cell_size if preparing else 26)
	refresh()

func make_position(parent: Control,container: String,title: String,pixels: int) -> Control:
	var column:=VBoxContainer.new();column.name=container.capitalize()+"Position";column.add_theme_constant_override("separation",2);parent.add_child(column)
	var label:=Label.new();label.text=title;label.add_theme_font_size_override("font_size",13);column.add_child(label)
	var grid: Control
	if container in ["active","backpack"]:grid=preload("res://scripts/exploration/equipment_slot.gd").new()
	else:grid=preload("res://scripts/cargo_grid.gd").new()
	grid.name="ActiveSlot" if container=="active" else container.capitalize()+"Grid";column.add_child(grid);grid.setup(home,container,pixels);grid.custom_minimum_size=grid.size
	equipment_grids.append(grid);home.grids.append(grid)
	return grid

func refresh() -> void:
	if home==null:return
	home.state.sync_carried_tools()
	var heavy: bool=home.loadout.get("heavy",false) if preparation_mode else home.state.gear.get("heavy",false)
	suit.text="加强型\n防护头盔" if heavy else "普通型\n防护头盔"
	for grid in equipment_grids:grid.queue_redraw()
