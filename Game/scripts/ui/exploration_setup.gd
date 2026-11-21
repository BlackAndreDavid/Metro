extends Control

var controller: Control
var equipment: Control
var warehouse_title: Label
@export var panel_bounds := Rect2(70, 55, 1140, 610)

func configure(home: Control, message: String) -> void:
	controller=home
	var panel: Panel = home.modal("出站整备 · %s" % home.state.station, panel_bounds)
	var radiation: int = home.Rail.station_info(home.state.station).radiation
	home.action(panel, "普通防护服 · %d 度" % home.state.suit_rent(false), Rect2(24,82,250,44),home.choose_gear.bind("heavy",false),not home.loadout.heavy)
	home.action(panel, "加强防护服 · %d 度" % home.state.suit_rent(true), Rect2(288,82,250,44),home.choose_gear.bind("heavy",true),home.loadout.heavy)
	home.label(panel,"区域辐射 · %s / 外出上限 %d 秒" % [home.RADIATION[radiation],home.state.trip_limit()],Rect2(562,89,550,30),17,home.AMBER)
	warehouse_title=home.label(panel,"预备仓库 · %d × %d · 留在基地" % [home.state.grid_size("preparation").x,home.state.grid_size("preparation").y],Rect2(24,147,390,30),20)
	home.label(panel,"随身背包 · 带去探索",Rect2(500,147,370,30),20)
	home.add_grid(panel,"preparation",Vector2(24,188),mini(44,mini(352/home.state.grid_size("preparation").x,264/home.state.grid_size("preparation").y)))
	home.add_grid(panel,"bag",Vector2(500,188),44)
	home.label(panel,"装备栏",Rect2(834,147,245,30),20)
	equipment=preload("res://scripts/exploration/loadout_bar.gd").new();equipment.name="EquipmentPanel";panel.add_child(equipment);equipment.position=Vector2(834,188);equipment.size=Vector2(270,270);equipment.configure(home,true)
	home.wrapped(panel,"左键选中后放置，或直接拖拽物品。
滚轮旋转 / F 镜像 / Shift+点击自动转移",Rect2(500,416,300,60),15,home.MUTED)
	home.action(panel,"整理仓库",Rect2(24,478,150,38),home.sort_cargo.bind("preparation"))
	home.action(panel,"整理背包",Rect2(500,478,140,38),home.sort_cargo.bind("bag"))
	home.action(panel,"一键转移选中",Rect2(656,478,150,38),home.quick_place_selected)
	home.status=home.label(panel,"",Rect2(24,536,774,54),15,home.AMBER)
	home.status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	home.report(message)
	var rent: int=home.state.suit_rent(home.loadout.heavy)
	home.action(panel,"确认出发 · %d 度" % rent,Rect2(834,536,278,46),home.confirm_departure,true)

func refresh_inventory(message: String = "") -> void:
	for grid in controller.grids:
		grid.size=Vector2(controller.state.grid_size(grid.container)*grid.cell_size)
		grid.queue_redraw()
	warehouse_title.text="预备仓库 · %d × %d · 留在基地" % [controller.state.grid_size("preparation").x,controller.state.grid_size("preparation").y]
	equipment.refresh()
	controller.report(message)
