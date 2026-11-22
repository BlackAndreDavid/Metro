extends RefCounted
## Explicit, lossless cargo repacking. Never edits the original or guesses missing definitions.
const State=preload("res://scripts/cabin_state.gd")
const Items=preload("res://scripts/items/item_catalog.gd")
const Orders=preload("res://scripts/commerce/customer_orders.gd")
static func repair(raw: Dictionary, stations: Array) -> Dictionary:
	var candidate:=raw.duplicate(true)
	var containers: Array = ["bag","locker","preparation"] if int(raw.get("version",0)) >= 17 else ["bag","locker"]
	if int(raw.get("version",0))>=20:containers.append("pocket")
	var extra: Variant=raw.get("furniture_storage",{})
	if not extra is Dictionary:return {"error":"家具储物数据损坏。"}
	for kind in extra:
		if not extra[kind] is Array:return {"error":"家具储物列表损坏。"}
		containers.append("furniture:"+kind)
	candidate.furniture_storage={}
	var original:Dictionary={}
	for name in containers:
		if name.begins_with("furniture:"):
			original[name]=extra[name.trim_prefix("furniture:")].duplicate(true);continue
		if not raw.get(name) is Array:return {"error":"物品列表结构损坏，无法自动修复。"}
		original[name]=raw[name].duplicate(true);candidate[name]=[]
	var active:Variant=raw.get("active_item",{})
	if not active is Dictionary:return {"error":"主动位数据损坏。"}
	candidate.active_item={}
	var notes:PackedStringArray=[]
	if candidate.get("customer_visits") is Dictionary and not Orders.valid_saved(candidate.customer_visits):
		for record in candidate.customer_visits.values():
			if not record is Dictionary or not record.get("active") is Dictionary:continue
			var order:Dictionary=record.active
			if order.is_empty():continue
			if order.get("status")=="open" and (record.get("dismissed") is float or record.get("dismissed") is int):record.dismissed+=1
			if candidate.get("dialogue_progress") is Dictionary:candidate.dialogue_progress.erase(order.get("id",""))
			record.active={}
		notes.append("清理失效的当前订单，保留交易账目和已用顾客次数")
	var validator:=State.new()
	if not validator.load_data(candidate,stations):return {"error":"核心进度、家具或资金字段未通过校验，未修改原存档。请恢复匹配版本或使用备份。"}
	var bag:Array[Dictionary]=[];var locker:Array[Dictionary]=[];var preparation:Array[Dictionary]=[]
	var packed:Dictionary={"bag":bag,"locker":locker,"preparation":preparation}
	for name in containers:
		if not packed.has(name):packed[name]=[] as Array[Dictionary]
	var pending:Array=[]
	for name in containers:
		for source in original[name]:
			var item:=checked_item(source,validator)
			if item.has("error"):return item
			item.preferred=name;pending.append(item)
	pending.sort_custom(func(a,b):return validator.item_cells(a).size()>validator.item_cells(b).size())
	for item in pending:
		var preferred:String=item.preferred;item.erase("preferred")
		var placed:=false
		for name in ([preferred] if preferred=="preparation" or preferred.begins_with("furniture:") else [preferred,"locker" if preferred=="bag" else "bag"]):
			var bounds:Vector2i=validator.grid_size(name)
			if name==preferred and validator.fits_item(packed[name],bounds,item.kind,Vector2i(item.x,item.y),item.rotated,item.mirrored):
				packed[name].append(item);placed=true;break
			var trial: Array=packed[name].duplicate(true);trial.append(item)
			var result:Dictionary=validator.Equipment.pack(validator,trial,bounds)
			if not result.is_empty():packed[name]=result.entries;placed=true;break
		if not placed:return {"error":"空间不足，无法完整保留物品“%s”。请先恢复旧占位定义，或缩小该物品占位；原文件未修改。" % item.kind}
	candidate.bag=packed.bag;candidate.locker=packed.locker
	if "pocket" in containers:candidate.pocket=packed.pocket
	if "preparation" in containers:candidate.preparation=packed.preparation
	for name in containers:
		if name.begins_with("furniture:"):candidate.furniture_storage[name.trim_prefix("furniture:")]=packed[name]
	if not active.is_empty():
		var item:=checked_item(active,validator)
		if item.has("error"):return item
		item.x=0;item.y=0
		var empty: Array[Dictionary]=[]
		if validator.fits_item(empty,Vector2i(2,2),item.kind,Vector2i.ZERO,item.rotated,item.mirrored):candidate.active_item=item
		else:
			var placed:=false
			for name in ["bag","preparation","locker"]:
				var items: Array=packed[name].duplicate(true);items.append(item)
				var result: Dictionary=validator.Equipment.pack(validator,items,validator.grid_size(name))
				if not result.is_empty():packed[name]=result.entries;candidate[name]=result.entries;placed=true;break
			if not placed:return {"error":"主动位物品已超出2×2，且其他储物格不足；原文件未修改。"}
	if not validator.load_data(candidate,stations):return {"error":"整理后仍未通过完整校验，原存档未修改（请检查重复家具所有权等数据）。"}
	notes.append("保留全部物品，按当前占位重新整理背包和柜子")
	return {"data":validator.save_data().duplicate(true),"notes":"；".join(notes)}

static func checked_item(source: Variant, state: RefCounted) -> Dictionary:
	if not source is Dictionary or not source.get("kind") is String:return {"error":"存在无法识别的物品记录。"}
	var kind:=Items.runtime_id(source.kind)
	if not state.ITEM_DEFINITIONS.has(kind):return {"error":"缺少物品定义：%s。请恢复该物品或旧ID映射后再修复，不能自动猜测替代物。" % source.kind}
	if not source.get("rotated") is bool or not source.get("mirrored",false) is bool:return {"error":"物品方向字段损坏。"}
	for key in ["x","y"]:
		if not state.valid_index(source.get(key),-8,1000):return {"error":"物品坐标字段损坏。"}
	if kind=="aaa" and not state.valid_index(source.get("charge"),0,100):return {"error":"电池电量字段损坏。"}
	var item:Dictionary=source.duplicate(true);item.kind=kind;item.mirrored=source.get("mirrored",false);item.id=0
	return item
