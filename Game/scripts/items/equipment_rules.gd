extends RefCounted
## Equipment owns items; inventory capacity comes only from the equipped backpack.
const Storage=preload("res://scripts/storage/storage_component.gd")
const ItemCatalog=preload("res://scripts/items/item_catalog.gd")

static func capacity(entry: Dictionary,definitions: Dictionary={}) -> Vector2i:
	var kind: String=entry.get("kind","")
	if definitions.has(kind):
		var definition: Resource=definitions[kind]
		return definition.storage if definition.has_storage() else Vector2i.ZERO
	var data: Dictionary=ItemCatalog.definition(kind)
	return Storage.from_data(data.get("storage")).size if "storage" in data.get("tags",[]) else Vector2i.ZERO

static func is_storage(kind: String,definitions: Dictionary={}) -> bool:
	var dimensions:=capacity({"kind":kind},definitions)
	return dimensions.x>0 and dimensions.y>0

# Compatibility entry point: the packing algorithm is owned by shared storage.
static func pack(state: RefCounted,cargo: Array,bounds: Vector2i) -> Dictionary:
	return Storage.pack(state.ITEM_DEFINITIONS,cargo,bounds)

static func plan(state: RefCounted,selection: Dictionary,target: String,cell: Vector2i) -> Dictionary:
	var source: String=selection.get("source","")
	if source=="ground" or source=="battery":return {"error":"请先拾取到随身储物格，再装备。"}
	var incoming: Dictionary=state.picked(source,int(selection.get("id",-999)))
	if incoming.is_empty():return {"error":"物品已失效。"}
	if target=="backpack" and not is_storage(incoming.kind,state.ITEM_DEFINITIONS):return {"error":"背包位置只能装备带有储物类标签的物品。"}
	var empty: Array[Dictionary]=[]
	if not state.fits_item(empty,state.grid_size(target),incoming.kind,cell,selection.get("rotated",false),selection.get("mirrored",false)):return {"error":"该物品的实际占位超出装备格。"}
	var incoming_copy:=incoming.duplicate(true);incoming_copy.x=cell.x;incoming_copy.y=cell.y;incoming_copy.rotated=selection.get("rotated",false);incoming_copy.mirrored=selection.get("mirrored",false)
	if source==target:return {"incoming":incoming_copy}
	var outgoing: Dictionary=state.backpack_item if target=="backpack" else state.active_item
	if source=="backpack" and not outgoing.is_empty() and not is_storage(outgoing.kind,state.ITEM_DEFINITIONS):return {"error":"请先卸下目标装备。"}
	var trial: Array[Dictionary]=[];trial.assign(state.entries(source).duplicate(true))
	for index in range(trial.size()-1,-1,-1):
		if trial[index].id==incoming.id:trial.remove_at(index)
	if not outgoing.is_empty():trial.append(outgoing.duplicate(true))
	var future_backpack: Dictionary=incoming_copy if target=="backpack" else outgoing if source=="backpack" else state.backpack_item
	var source_bounds: Vector2i=capacity(future_backpack,state.ITEM_DEFINITIONS) if source=="bag" else state.grid_size(source)
	var packed:=pack(state,trial,source_bounds)
	if packed.is_empty():return {"error":"原装备没有空间放回，请先整理来源储物格。"}
	var bag_trial: Array=packed.entries if source=="bag" else state.inventory
	var packed_bag:=pack(state,bag_trial,capacity(future_backpack,state.ITEM_DEFINITIONS))
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
