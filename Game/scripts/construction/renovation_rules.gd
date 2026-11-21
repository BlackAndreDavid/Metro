extends RefCounted
## Atomic temporary storage, construction and decomposition of furniture instances.
const Catalog=preload("res://scripts/items/furniture_catalog.gd")

static func count_placed(state: RefCounted, base: String) -> int:
	var count:=0
	for id in state.furniture_layout:
		if Catalog.base_kind(id)==base and state.furniture_layout[id]!=null:count+=1
	return count

static func removal_problem(state: RefCounted, id: String, decompose: bool) -> String:
	if not state.can_edit_home() or not state.furniture_layout.has(id):return "当前不能处理这件家具。"
	var base:=Catalog.base_kind(id)
	if state.furniture_layout[id]!=null and base in ["door","window"] and count_placed(state,base)<=1:return "全车至少保留一个车门和一个车窗，不能移除最后一个。"
	var definition: Resource=Catalog.DEFINITIONS[id]
	if decompose and definition.storage!=Vector2i.ZERO and not state.entries(state.storage_container(id)).is_empty():return "请先清空该家具的储物空间，再分解。"
	var trial: Dictionary=state.furniture_layout.duplicate(true);trial[id]=null
	for other in trial:
		if trial[other]!=null:
			var problem:=Catalog.support_problem(other,trial[other],trial)
			if not problem.is_empty():return "该家具仍在支撑其他家具："+problem
	return ""

static func temporary_store(state: RefCounted, id: String) -> String:
	if state.furniture_layout.get(id)==null:return "该家具已在临时收纳中。"
	var problem:=removal_problem(state,id,false)
	if not problem.is_empty():return problem
	state.furniture_layout[id]=null
	if id not in state.temporary_furniture:state.temporary_furniture.append(id)
	return ""

static func pack_item(state: RefCounted,id: String) -> String:
	if not state.furniture_layout.has(id) or not Catalog.DEFINITIONS.has(id):return "家具不存在。"
	var definition: Resource=Catalog.DEFINITIONS[id]
	if definition.item_id.is_empty():return "此家具没有物品属性，请放回车厢或分解。"
	var problem:=removal_problem(state,id,true)
	if not problem.is_empty():return problem
	for target in state.available_storage_containers()+["bag"]:
		if target!=state.storage_container(id) and state.add_supply(definition.item_id,target):
			state.furniture_layout[id]=null;state.temporary_furniture.erase(id);state.furniture_owned.erase(id)
			return ""
	return "没有储物空间，家具保持原状。"

static func recipe_problem(state: RefCounted,recipe: Dictionary) -> String:
	for kind in recipe:
		if state.material_count(kind)<int(recipe[kind]):return "材料不足：%s × %d（拥有%d）。" % [state.item_name(kind),int(recipe[kind]),state.material_count(kind)]
	return ""

static func consume(state: RefCounted,recipe: Dictionary) -> void:
	for kind in recipe:
		var remaining:=int(recipe[kind])
		for cargo in state.all_cargo_arrays():
			for index in range(cargo.size()-1,-1,-1):
				if remaining>0 and cargo[index].kind==state.ItemCatalog.runtime_id(kind):cargo.remove_at(index);remaining-=1

static func cargo_backup(state: RefCounted) -> Dictionary:
	var snapshot: Dictionary={"next_id":state.next_id,"cargo":{},"extra_storage":state.furniture_storage.duplicate(true),"storage_sizes":state.storage_sizes.duplicate(true)}
	for name in state.storage_containers()+["bag"]:snapshot.cargo[name]=state.entries(name).duplicate(true)
	return snapshot
static func restore_cargo(state: RefCounted,snapshot: Dictionary) -> void:
	state.furniture_storage=snapshot.extra_storage.duplicate(true);state.storage_sizes=snapshot.storage_sizes.duplicate(true)
	for name in snapshot.cargo:state.entries(name).assign(snapshot.cargo[name])
	state.next_id=snapshot.next_id

static func next_id(state: RefCounted,base: String) -> String:
	if state.furniture_layout.get(base)==null and base not in state.furniture_owned:return base
	var index:=1
	while state.furniture_layout.has(base+"#"+str(index)):index+=1
	var id:=base+"#"+str(index);Catalog.ensure_instance(id);return id

static func build(state: RefCounted,id: String,placement: Dictionary) -> String:
	if not Catalog.ensure_instance(id) or state.furniture_layout.get(id)!=null:return "目标家具已存在。"
	var definition: Resource=Catalog.DEFINITIONS[id]
	var problem: String=state.build_requirements_problem(id)
	if not problem.is_empty():return problem
	problem=state.furniture_placement_problem(id,placement)
	if not problem.is_empty():return problem
	problem=recipe_problem(state,definition.build_cost)
	if not problem.is_empty():return problem
	var snapshot:=cargo_backup(state);consume(state,definition.build_cost)
	var was_owned: bool=id in state.furniture_owned
	var existed: bool=state.furniture_layout.has(id)
	state.furniture_layout[id]=null
	if not was_owned:state.furniture_owned.append(id)
	problem=state.place_furniture(id,placement)
	if not problem.is_empty():
		restore_cargo(state,snapshot)
		if not was_owned:state.furniture_owned.erase(id)
		if not existed:state.furniture_layout.erase(id)
	return problem

static func decomposition_problem(state: RefCounted,id: String) -> String:
	var problem:=removal_problem(state,id,true)
	if not problem.is_empty():return problem
	if state.furniture_layout.get(id)==null and id not in state.temporary_furniture:return "该家具没有可分解的实体。"
	return recipe_problem(state,Catalog.DEFINITIONS[id].dismantle_cost)

static func decompose(state: RefCounted,id: String) -> String:
	var problem:=decomposition_problem(state,id)
	if not problem.is_empty():return problem
	var definition: Resource=Catalog.DEFINITIONS[id]
	var snapshot:=cargo_backup(state);consume(state,definition.dismantle_cost)
	for kind in definition.salvage:
		for unit in range(int(definition.salvage[kind])):
			var placed:=false
			for target in state.available_storage_containers()+["bag"]:
				if target!=state.storage_container(id) and state.add_supply(kind,target):placed=true;break
			if not placed:restore_cargo(state,snapshot);return "没有空间存放分解材料，未消耗材料或家具。"
	state.furniture_layout[id]=null;state.furniture_owned.erase(id);state.temporary_furniture.erase(id)
	state.furniture_storage.erase(id);state.storage_sizes.erase(id)
	return ""
