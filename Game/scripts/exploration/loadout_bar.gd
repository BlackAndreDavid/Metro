extends PanelContainer
## Shared departure equipment panel and exploration equipment HUD.
var home:Control
var active:Control
var suit:Label
var battery_grid:Control
var preparation_mode := false
var tools_status: Label
func configure(controller:Control, preparing: bool = false)->void:
	home=controller;preparation_mode=preparing
	if preparing:
		configure_preparation();return
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",12);add_child(row)
	suit=Label.new();suit.custom_minimum_size=Vector2(118,64);suit.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;suit.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;suit.tooltip_text="防护服在出发时租用，探索中保留。";row.add_child(suit)
	var lamp:=VBoxContainer.new();row.add_child(lamp)
	home.flashlight_button=Button.new();home.flashlight_button.name="Flashlight";home.flashlight_button.custom_minimum_size=Vector2(215,28);home.flashlight_button.focus_mode=Control.FOCUS_NONE;home.flashlight_button.pressed.connect(func():home.report(home.state.toggle_flashlight());home.refresh_surface_light());lamp.add_child(home.flashlight_button)
	var battery_row:=HBoxContainer.new();lamp.add_child(battery_row)
	battery_grid=preload("res://scripts/cargo_grid.gd").new();battery_grid.custom_minimum_size=Vector2(34,34);battery_row.add_child(battery_grid);battery_grid.setup(home,"battery",34);home.grids.append(battery_grid)
	var hint:=Label.new();hint.text="← 电池槽 · 拖入/拖出";hint.add_theme_font_size_override("font_size",12);battery_row.add_child(hint)
	home.wrench_button=Button.new();home.wrench_button.name="Wrench";home.wrench_button.custom_minimum_size=Vector2(105,64);home.wrench_button.focus_mode=Control.FOCUS_NONE;home.wrench_button.disabled=not home.state.gear.get("wrench",false);home.wrench_button.pressed.connect(home.toggle_wrench);row.add_child(home.wrench_button)
	active=PanelContainer.new();active.name="ActiveSlot";active.set_script(preload("res://scripts/exploration/active_slot.gd"));active.custom_minimum_size=Vector2(250,64);row.add_child(active);active.configure(home)
	refresh()
func refresh()->void:
	if home==null:return
	if preparation_mode:
		refresh_preparation();return
	if home.state.gear.get("inventory_tools",false):home.state.sync_carried_tools()
	suit.text="防护服\n"+("加强型" if home.state.gear.get("heavy",false) else "普通型")
	active.refresh();battery_grid.queue_redraw()
	home.refresh_equipment()

func configure_preparation() -> void:
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",12);add_child(column)
	suit=Label.new();suit.add_theme_font_size_override("font_size",16);column.add_child(suit)
	tools_status=Label.new();tools_status.custom_minimum_size=Vector2(250,125);tools_status.add_theme_font_size_override("font_size",14);column.add_child(tools_status)
	active=preload("res://scripts/exploration/active_slot.gd").new();active.name="ActiveSlot";active.custom_minimum_size=Vector2(250,64);column.add_child(active);active.configure(home)
	refresh_preparation()

func refresh_preparation() -> void:
	home.state.sync_carried_tools()
	var carried: Dictionary=home.state.carried_tools()
	suit.text="防护服 · "+("加强型" if home.loadout.get("heavy",false) else "普通型")
	tools_status.text="携带即生效
手电筒 · %s（%s）
撬棍 · %s
扳手 · %s
大背包 · %s" % ["已携带" if carried.light else "未携带",home.installed_battery_text(),"已携带" if carried.crowbar else "未携带","已携带" if carried.wrench else "未携带","已携带" if carried.wide else "未携带"]
	active.refresh()
