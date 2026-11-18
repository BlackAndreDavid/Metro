extends RefCounted
const Meeting = preload("res://scripts/commerce/meeting_dialogue.gd")
const Customers = preload("res://scripts/commerce/customer_catalog.gd")

static func matches(state: RefCounted, conditions: Dictionary, npc_id: String = "") -> bool:
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
	var npc := customer_by_id(npc_id)
	var affection := float(state.npc_affection.get(npc_id,0))
	var trust := float(state.faction_trust.get(npc.get("faction","none"),0))
	if affection < conditions.get("affection_min",-INF) or affection > conditions.get("affection_max",INF): return false
	if trust < conditions.get("trust_min",-INF) or trust > conditions.get("trust_max",INF): return false
	for event in conditions.get("events_all",[]):
		if not state.narrative_history.has(event): return false
	return true

static func customer_by_id(id: String) -> Dictionary:
	for customer in Customers.ENTRIES:
		if customer.id == id: return customer
	return {}

static func encounter(state: RefCounted, npc: String, context: String = "exploration") -> Dictionary:
	for i in range(Customers.ENTRIES.size()):
		if Customers.ENTRIES[i].id == npc:
			return {"id":"%d/%s/%s" % [state.day,context,npc],"visitor":i,"status":"open","context":context}
	return {}

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
		if order.get("context","trade") not in story.get("contexts",["trade"]): continue
		var ready := true
		for dependency in story.get("after",[]):
			var event: String = dependency.get("npc",customer.id)+"/"+dependency.story
			if not state.narrative_history.has(event) or state.day < state.narrative_history.get(event,0)+dependency.get("days",1): ready = false
		if ready and matches(state,story.get("conditions",{}),customer.id): return story
	return {}

static func enter(state: RefCounted, order: Dictionary, story: Dictionary, node: String) -> Dictionary:
	if not story.nodes.has(node): node = story.start
	state.dialogue_progress[order.id] = {"story":story.id,"node":node}
	var content: Dictionary = Meeting.new(story).turn(node)
	for flag in content.get("set_flags",[]): state.content_flags[flag] = true
	apply_effects(state,order,story,node,content.get("effects",{}))
	return content

static func finish(state: RefCounted, order: Dictionary, story: Dictionary) -> void:
	state.content_flags["dialogue/"+order.id+"/"+story.id] = true
	var customer: Dictionary = Customers.definition(int(order.visitor))
	if story.get("once",true): state.content_flags["story/"+customer.id+"/"+story.id] = true
	state.narrative_history[customer.id+"/"+story.id] = state.day
	state.dialogue_progress.erase(order.id)

static func valid_saved(flags: Variant, progress: Variant) -> bool:
	if not flags is Dictionary or not progress is Dictionary: return false
	for key in flags:
		if not key is String or not flags[key] is bool: return false
	for key in progress:
		var p: Variant = progress[key]
		if not key is String or not p is Dictionary or p.size() != 2 or not p.has_all(["story","node"]) or not p.story is String or not p.node is String: return false
	return true

## Effect tokens survive saves and prevent additive effects replaying after load/backtracking.
static func apply_effects(state: RefCounted, order: Dictionary, story: Dictionary, token: String, effects: Dictionary) -> void:
	var key: String = "effect/"+order.id+"/"+story.id+"/"+token
	if state.content_flags.get(key,false): return
	state.content_flags[key] = true
	var npc: Dictionary = Customers.definition(int(order.visitor))
	state.npc_affection[npc.id] = clampf(float(state.npc_affection.get(npc.id,0))+float(effects.get("affection",0)),-100,100)
	var faction: String = npc.get("faction","none")
	if faction != "none": state.faction_trust[faction] = clampf(float(state.faction_trust.get(faction,0))+float(effects.get("trust",0)),-100,100)
	for flag in effects.get("set_flags",[]): state.content_flags[flag] = true

static func valid_social(data: Dictionary) -> bool:
	for field in ["npc_affection","faction_trust","narrative_history","daily_customer_ids"]:
		if not data.get(field) is Dictionary: return false
		for key in data[field]:
			if not key is String: return false
			var value: Variant = data[field][key]
			if field == "daily_customer_ids":
				if not value is bool: return false
			else:
				if not (value is float or value is int) or not is_finite(float(value)): return false
				if field == "narrative_history":
					if value < 1 or value > data.get("day",0) or value != int(value): return false
				elif value < -100 or value > 100: return false
	return true
