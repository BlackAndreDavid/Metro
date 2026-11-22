extends "res://scripts/cargo_grid.gd"
## Single-item equipment positions share the same occupancy and drag path as storage.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed and (host.selection.is_empty() or container=="backpack"):
		if container=="backpack":
			var selected: Dictionary={} if host.selection.is_empty() else host.state.picked(host.selection.source,host.selection.id)
			if selected.is_empty() or not host.state.Equipment.is_storage(selected.kind,host.state.ITEM_DEFINITIONS):host.toggle_equipped_bag();accept_event();return
		if container=="active" and host.screen=="surface" and not host.view.pack_open:
			host.use_active_item();accept_event();return
	super._gui_input(event)

func _get_tooltip(at: Vector2) -> String:
	if container=="backpack":
		var entry:Dictionary=host.state.backpack_item
		var title: String="未装备背包" if entry.is_empty() else host.state.item_name(entry.kind)+" · %d×%d" % [host.state.bag_size().x,host.state.bag_size().y]
		return title+"\n拖入储物类物品装备；点击展开储物页，拖出可卸下（需先清空）。"
	return super._get_tooltip(at)

func _get_drag_data(_at: Vector2) -> Variant:
	var items: Array=host.state.entries(container)
	if items.is_empty():return null
	var occupied: Array=host.state.item_cells(items[0])
	return super._get_drag_data((Vector2(occupied[0])+Vector2(.5,.5))*cell_size)

func drag_cell() -> Vector2i:
	var candidate:=super.drag_cell()
	if host.selection.is_empty():return candidate
	var entry: Dictionary=host.state.picked(host.selection.source,host.selection.id)
	if entry.is_empty():return candidate
	var empty: Array[Dictionary]=[]
	var bounds: Vector2i=host.state.grid_size(container)
	if host.state.fits_item(empty,bounds,entry.kind,candidate,host.selection.rotated,host.selection.get("mirrored",false)):return candidate
	for y in range(bounds.y):
		for x in range(bounds.x):
			if host.state.fits_item(empty,bounds,entry.kind,Vector2i(x,y),host.selection.rotated,host.selection.get("mirrored",false)):return Vector2i(x,y)
	return candidate
