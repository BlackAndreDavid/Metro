extends RefCounted
const Items = preload("res://scripts/items/item_catalog.gd")
static func roll(state: RefCounted, point: Dictionary, station: String, index: int) -> String:
	var token := "cabinet/"+str(point.get("spawn_id",point.get("cabinet",index)))+"/"+str(point.get("roll",0))
	if float(state.station_roll(station,token+"/chance",1000000))/1000001.0 >= float(point.get("chance",1)): return ""
	var total := 0.0
	var choices: Array = point.get("choices",[])
	for choice in choices:
		if not Items.definition(choice.kind).get("deleted",false) and Items.definition(choice.kind).get("enabled",true): total += float(choice.weight)
	if total <= 0: return ""
	var random_value: float = float(state.station_roll(station,token+"/item",1000000))/1000001.0*total
	for choice in choices:
		if Items.definition(choice.kind).get("deleted",false) or not Items.definition(choice.kind).get("enabled",true): continue
		random_value -= float(choice.weight)
		if random_value < 0: return Items.runtime_id(choice.kind)
	return ""
