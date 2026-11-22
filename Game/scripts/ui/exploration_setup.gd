extends Control

var controller: Control
var equipment: Control
var warehouse_title: Label
var bag_title: Label
var bag_panel: Panel
const CELL_PIXELS := 36
var content_panel: Panel
var equipped_backpack_id := -1
var bag_open := false
@export var panel_bounds := Rect2(70, 55, 1140, 610)

func configure(home: Control, message: String) -> void:
	controller=home
	var panel: Panel = home.modal("出站整备 · %s" % home.state.station, panel_bounds)
	content_panel=panel
	var radiation: int = home.Rail.station_info(home.state.station).radiation
	home.action(panel, "普通防护服 · %d 度" % home.state.suit_rent(false), Rect2(24,82,250,44),home.choose_gear.bind("heavy",false),not home.loadout.heavy)
	home.action(panel, "加强防护服 · %d 度" % home.state.suit_rent(true), Rect2(288,82,250,44),home.choose_gear.bind("heavy",true),home.loadout.heavy)
	home.label(panel,"区域辐射 · %s / 外出上限 %d 秒" % [home.RADIATION[radiation],home.state.trip_limit()],Rect2(562,89,550,30),17,home.AMBER)
	warehouse_title=home.label(panel,"预备仓库 · %d × %d · 留在基地" % [home.state.grid_size("preparation").x,home.state.grid_size("preparation").y],Rect2(24,147,390,30),20)
	var warehouse_scroll:=ScrollContainer.new();warehouse_scroll.name="WarehouseScroll";warehouse_scroll.position=Vector2(24,188);warehouse_scroll.size=Vector2(376,240);panel.add_child(warehouse_scroll)
	home.add_grid(warehouse_scroll,"preparation",Vector2.ZERO,CELL_PIXELS)
	var warehouse_grid: Control=home.grids[-1]
	warehouse_grid.custom_minimum_size=warehouse_grid.size
	home.label(panel,"装备栏",Rect2(814,124,280,24),18)
	equipment=preload("res://scripts/exploration/loadout_bar.gd").new();equipment.name="EquipmentPanel";panel.add_child(equipment);equipment.position=Vector2(814,151);equipment.size=Vector2(296,374);equipment.configure(home,true,CELL_PIXELS)
	home.wrapped(panel,"左键选中后放置，或直接拖拽物品。
滚轮旋转 / F 镜像 / Shift+点击自动转移",Rect2(24,434,376,40),15,home.MUTED)
	home.action(panel,"整理仓库",Rect2(24,478,150,38),home.sort_cargo.bind("preparation"))
	home.status=home.label(panel,"",Rect2(24,536,774,54),15,home.AMBER)
	home.status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	home.report(message)
	var rent: int=home.state.suit_rent(home.loadout.heavy)
	home.action(panel,"确认出发 · %d 度" % rent,Rect2(834,536,278,46),home.confirm_departure,true)
	equipped_backpack_id=int(home.state.backpack_item.get("id",-1))
	set_bag_open(not home.state.backpack_item.is_empty())

func refresh_inventory(message: String = "") -> void:
	for grid in controller.grids:
		grid.size=Vector2(controller.state.grid_size(grid.container)*grid.cell_size)
		grid.custom_minimum_size=grid.size
		grid.queue_redraw()
	warehouse_title.text="预备仓库 · %d × %d · 留在基地" % [controller.state.grid_size("preparation").x,controller.state.grid_size("preparation").y]
	equipment.refresh()
	if is_instance_valid(bag_title) and not controller.state.backpack_item.is_empty():bag_title.text=controller.state.item_name(controller.state.backpack_item.kind)
	var current_id: int=int(controller.state.backpack_item.get("id",-1))
	if current_id!=equipped_backpack_id:
		equipped_backpack_id=current_id
		set_bag_open(current_id!=-1)
	controller.report(message)

func toggle_bag() -> void:
	set_bag_open(not bag_open)

func set_bag_open(value: bool) -> void:
	if value and controller.state.backpack_item.is_empty():controller.report("请先拖入并装备储物类物品。");return
	bag_open=value
	equipment.show()
	if is_instance_valid(bag_panel):
		controller.grids=controller.grids.filter(func(grid):return grid.container!="bag")
		bag_panel.hide();bag_panel.queue_free()
	if not value:return
	bag_panel=Panel.new();bag_panel.name="BackpackStorage";bag_panel.position=Vector2(432,188);bag_panel.size=Vector2(342,286);content_panel.add_child(bag_panel)
	bag_title=controller.label(bag_panel,controller.state.item_name(controller.state.backpack_item.kind),Rect2(12,6,228,28),18)
	controller.action(bag_panel,"收起",Rect2(270,6,60,28),set_bag_open.bind(false))
	var scroll:=ScrollContainer.new();scroll.name="StorageScroll";scroll.position=Vector2(12,44);scroll.size=Vector2(318,190);bag_panel.add_child(scroll)
	controller.add_grid(scroll,"bag",Vector2.ZERO,CELL_PIXELS)
	var storage_grid: Control=controller.grids[-1];storage_grid.custom_minimum_size=storage_grid.size
	var sort_button: Button=controller.action(bag_panel,"一键整理背包",Rect2(12,242,148,36),controller.sort_cargo.bind("bag"));sort_button.name="SortBackpack"
	var transfer_button: Button=controller.action(bag_panel,"一键转移",Rect2(170,242,160,36),controller.quick_place_selected);transfer_button.name="TransferSelected"
