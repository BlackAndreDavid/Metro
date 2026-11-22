extends RefCounted
## Equipment owns items; inventory capacity comes only from the equipped backpack.
const BACKPACKS := {"small_backpack":Vector2i(5,4),"large_backpack":Vector2i(6,5)}

static func capacity(entry: Dictionary) -> Vector2i:
	return BACKPACKS.get(entry.get("kind",""),Vector2i.ZERO)

static func pack(state: RefCounted,cargo: Array,bounds: Vector2i) -> Dictionary:
	var original: Array[Dictionary]=[];original.assign(cargo.duplicate(true))
	var preserved: Array[Dictionary]=[]
	for item in original:
		if not state.fits_item(preserved,bounds,item.kind,Vector2i(item.x,item.y),item.rotated,item.get("mirrored",false)):break
		preserved.append(item)
	if preserved.size()==original.size():return {"entries":preserved}
	var total:=0
	for item in original:total+=state.item_cells(item).size()
	if total>bounds.x*bounds.y:return {}
	original.sort_custom(func(a,b):return state.item_cells(a).size()>state.item_cells(b).size())
	var trial: Array[Dictionary]=[]
	for item in original:
		var placed:=false
		for rotated in [item.rotated,not item.rotated]:
			var offsets: Array=state.ITEM_DEFINITIONS[item.kind].cell_offsets(rotated,item.get("mirrored",false))
			var low:=Vector2i(1000,1000);var high:=Vector2i(-1000,-1000)
			for offset in offsets:low=low.min(offset);high=high.max(offset)
			for y in range(-low.y,bounds.y-high.y):
				for x in range(-low.x,bounds.x-high.x):
					if not placed and state.fits_item(trial,bounds,item.kind,Vector2i(x,y),rotated,item.get("mirrored",false)):
						item.x=x;item.y=y;item.rotated=rotated;trial.append(item);placed=true
				if placed:break
				if placed:break
			if placed:break
		if not placed:return {}
	return {"entries":trial}

static func plan(state: RefCounted,selection: Dictionary,target: String,cell: Vector2i) -> Dictionary:
	var source: String=selection.get("source","")
	if source=="ground" or source=="battery":return {"error":"请先拾取到随身储物格，再装备。"}
	var incoming: Dictionary=state.picked(source,int(selection.get("id",-999)))
	if incoming.is_empty():return {"error":"物品已失效。"}
	if target=="backpack" and not BACKPACKS.has(incoming.kind):return {"error":"背包位置只能装备背包类物品。"}
	var empty: Array[Dictionary]=[]
	if not state.fits_item(empty,state.grid_size(target),incoming.kind,cell,selection.get("rotated",false),selection.get("mirrored",false)):return {"error":"该物品的实际占位超出装备格。"}
	var incoming_copy:=incoming.duplicate(true);incoming_copy.x=cell.x;incoming_copy.y=cell.y;incoming_copy.rotated=selection.get("rotated",false);incoming_copy.mirrored=selection.get("mirrored",false)
	if source==target:return {"incoming":incoming_copy}
	var outgoing: Dictionary=state.backpack_item if target=="backpack" else state.active_item
	if source=="backpack" and not outgoing.is_empty() and not BACKPACKS.has(outgoing.kind):return {"error":"请先卸下目标装备。"}
	var trial: Array[Dictionary]=[];trial.assign(state.entries(source).duplicate(true))
	for index in range(trial.size()-1,-1,-1):
		if trial[index].id==incoming.id:trial.remove_at(index)
	if not outgoing.is_empty():trial.append(outgoing.duplicate(true))
	var future_backpack: Dictionary=incoming_copy if target=="backpack" else outgoing if source=="backpack" else state.backpack_item
	var source_bounds: Vector2i=capacity(future_backpack) if source=="bag" else state.grid_size(source)
	var packed:=pack(state,trial,source_bounds)
	if packed.is_empty():return {"error":"原装备没有空间放回，请先整理来源储物格。"}
	var bag_trial: Array=packed.entries if source=="bag" else state.inventory
	var packed_bag:=pack(state,bag_trial,capacity(future_backpack))
	if packed_bag.is_empty():return {"error":"新背包容量不足；卸下背包前需先清空内部物品。"}
	return {"incoming":incoming_copy,"source":packed.entries,"bag":packed_bag.entries}

static func apply(state: RefCounted,selection: Dictionary,target: String,cell: Vector2i) -> bool:
	var result:=plan(state,selection,target,cell)
	if result.has("error"):return false
	var source: String=selection.source
	if source!=target:
		if source=="active":state.active_item=result.source[0] if not result.source.is_empty() else {}
		elif source=="backpack":state.backpack_item=result.source[0] if not result.source.is_empty() else {}
		else:state.entries(source).assign(result.source)
		state.inventory.assign(result.bag)
	if target=="active":state.active_item=result.incoming
	else:state.backpack_item=result.incoming
	state.sync_carried_tools()
	return true
