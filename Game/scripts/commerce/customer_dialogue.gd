extends RefCounted
const Customers = preload("res://scripts/commerce/customer_catalog.gd")

static func matches(state: RefCounted, conditions: Dictionary) -> bool:
	if not conditions.get("stations",[]).is_empty() and state.station not in conditions.stations: return false
	var values := {"day":state.day,"account":state.account,"debt":state.debt,"completed":state.customer_visits.get(state.station,{}).get("completed",0)}
	for key in values:
		if values[key] < conditions.get(key+"_min",-INF) or values[key] > conditions.get(key+"_max",INF): return false
	if conditions.has("blackout") and state.is_blackout() != conditions.blackout: return false
	for kind in conditions.get("has_items",{}):
		if state.material_count(kind) < conditions.has_items[kind]: return false
	for flag in conditions.get("flags_all",[]):
		if not state.content_flags.get(flag,false): return false
	for flag in conditions.get("flags_none",[]):
		if state.content_flags.get(flag,false): return false
	return true

static func pending(state: RefCounted, order: Dictionary) -> Dictionary:
	if order.is_empty() or order.status != "open": return {}
	var customer: Dictionary = Customers.definition(int(order.visitor))
	var stories: Array = customer.get("stories",[]).duplicate(true)
	var saved: Dictionary = state.dialogue_progress.get(order.id,{})
	for story in stories:
		if story.id == saved.get("story",""): return story
	stories.sort_custom(func(a: Dictionary,b: Dictionary): return a.get("priority",0) > b.get("priority",0))
	for story in stories:
		if state.content_flags.get("dialogue/"+order.id+"/"+story.id,false): continue
		if story.get("once",true) and state.content_flags.get("story/"+customer.id+"/"+story.id,false): continue
		if matches(state,story.get("conditions",{})): return story
	return {}

static func enter(state: RefCounted, order: Dictionary, story: Dictionary, node: String) -> Dictionary:
	if not story.nodes.has(node): node = story.start
	state.dialogue_progress[order.id] = {"story":story.id,"node":node}
	var content: Dictionary = story.nodes[node]
	for flag in content.get("set_flags",[]): state.content_flags[flag] = true
	return content

static func finish(state: RefCounted, order: Dictionary, story: Dictionary) -> void:
	state.content_flags["dialogue/"+order.id+"/"+story.id] = true
	var customer: Dictionary = Customers.definition(int(order.visitor))
	if story.get("once",true): state.content_flags["story/"+customer.id+"/"+story.id] = true
	state.dialogue_progress.erase(order.id)

static func valid_saved(flags: Variant, progress: Variant) -> bool:
	if not flags is Dictionary or not progress is Dictionary: return false
	for key in flags:
		if not key is String or not flags[key] is bool: return false
	for key in progress:
		var p: Variant = progress[key]
		if not key is String or not p is Dictionary or p.size() != 2 or not p.has_all(["story","node"]) or not p.story is String or not p.node is String: return false
	return true
