extends RefCounted
## Customer-facing directions: buy = customer buys from player; sell = customer sells to player.
const Visitors = preload("res://scripts/commerce/customer_catalog.gd")
const Markets = preload("res://scripts/cabin_markets.gd")
const CATEGORIES := {
	"supplies":{"name":"生活补给","items":["water","ration","meds"]},
	"power":{"name":"电力用品","items":["aaa","car_battery","powercore"]},
	"materials":{"name":"工业材料","items":["copper","circuit","steel_plate","bolts","tire","engine","tools"]},
	"documents":{"name":"文书旧物","items":["book","relic"]},
}
const BASE_PRICES := {"water":6.0,"ration":8.0,"meds":80.0,"aaa":12.0,"car_battery":64.0,"powercore":176.0,"copper":27.0,"circuit":82.0,"steel_plate":36.0,"bolts":8.0,"tire":18.0,"engine":110.0,"tools":52.0,"book":32.0,"relic":105.0}
const GROUP_LIMITS := {"community":4,"workshop":6,"clinic":4,"warehouse":7,"school":5,"central":8,"archive":3}
const STATION_LIMITS := {"邮电新村":4,"四平路":6,"同济大学":5}

static func daily_limit(station: String) -> int:
	if STATION_LIMITS.has(station): return STATION_LIMITS[station]
	for group in Markets.STATION_GROUPS:
		if station in Markets.STATION_GROUPS[group]: return GROUP_LIMITS[group]
	return GROUP_LIMITS.community

static func category_of(kind: String) -> String:
	for category in CATEGORIES:
		if kind in CATEGORIES[category].items: return category
	return ""

static func record(state: RefCounted) -> Dictionary:
	return state.customer_visits.get(state.station,{"arrived":0,"completed":0,"active":{}})

static func ensure(state: RefCounted) -> Dictionary:
	if not state.can_edit_home(): return {}
	if not state.customer_visits.has(state.station):
		state.customer_visits[state.station] = {"arrived":0,"completed":0,"active":{}}
	var visits: Dictionary = state.customer_visits[state.station]
	if not visits.active.is_empty() or visits.arrived >= daily_limit(state.station): return visits.active
	var index := int(visits.arrived)
	var pool: Array[String] = ["supplies"]
	var profile := Markets.profile(state.station)
	for kind in profile.stock.keys() + profile.demand.keys():
		var category := category_of(kind)
		if not category.is_empty() and category not in pool: pool.append(category)
	var category: String = pool[index % pool.size()]
	var stock := {}
	if index % 2 == 1:
		for kind in CATEGORIES[category].items: stock[kind] = 2
	visits.active = {"id":"%d/%s/%d" % [state.day,state.station,index],"visitor":posmod(state.station_roll(state.station,"visitor-base",Visitors.ENTRIES.size()-1)+index,Visitors.ENTRIES.size()),"side":"buy" if index % 2 == 0 else "sell","category":category,"budget":float(45 + state.station_roll(state.station,"budget/%d" % index,155)),"status":"open","stock":stock,"total":0.0}
	visits.arrived += 1
	return visits.active

static func next(state: RefCounted) -> Dictionary:
	var visits := record(state)
	if visits.active.is_empty() or visits.active.status != "completed": return visits.active
	visits.active = {}
	return ensure(state)

static func price(state: RefCounted, order: Dictionary, kind: String, charge: int = 100) -> float:
	var offer: Dictionary = state.market_offer("demand" if order.side == "buy" else "stock",kind,state.station,charge)
	if not offer.is_empty(): return offer.price
	var value: float = BASE_PRICES[kind] * state.market_multiplier(kind) * (0.75 if order.side == "buy" else 1.0)
	if kind == "aaa" and order.side == "buy": value *= lerpf(0.5,1.0,float(charge)/100.0)
	return snappedf(value,0.1)

static func preview(state: RefCounted, selection: Array) -> Dictionary:
	var order: Dictionary = record(state).active
	var result := {"problem":"","total":0.0,"placements":[],"entries":[],"kinds":[]}
	if state.trip_active or not state.game_over_reason.is_empty(): result.problem = "当前不能交易。"
	elif order.is_empty(): result.problem = "今日顾客已全部接待。"
	elif order.status != "open": result.problem = "订单已完成，请等待顾客离开。"
	elif selection.is_empty(): result.problem = "请拖入订单类别的商品。"
	elif selection.size() > 100: result.problem = "选择商品过多。"
	if not result.problem.is_empty(): return result
	var used := {}
	var quantities := {}
	var trial: Array[Dictionary] = state.inventory.duplicate(true)
	for payload in selection:
		if not payload is Dictionary or payload.size() != 2:
			result.problem = "无效的商品选择。"; return result
		var kind := ""
		var charge := 100
		if order.side == "buy":
			if payload.get("source") != "bag" or not state.Furniture.integer(payload.get("id")):
				result.problem = "顾客本次只购买背包里的商品。"; return result
			var entry: Dictionary = state.find_entry("bag",int(payload.id))
			if entry.is_empty() or used.has(entry.id): result.problem = "商品已失效或重复选择。"; return result
			used[entry.id] = true
			kind = entry.kind
			charge = int(entry.get("charge",100))
			result.entries.append(entry.id)
		else:
			if payload.get("source") != "stock" or not payload.get("kind") is String:
				result.problem = "顾客本次只出售窗口里的商品。"; return result
			kind = payload.kind
			quantities[kind] = quantities.get(kind,0)+1
			if quantities[kind] > order.stock.get(kind,0): result.problem = "顾客没有足够的这件商品。"; return result
		if category_of(kind) != order.category: result.problem = "这件商品不属于订单要求的类别。"; return result
		result.total = snappedf(result.total + price(state,order,kind,charge),0.1)
		result.kinds.append(kind)
		if order.side == "sell":
			var placement := free_placement(state,trial,kind)
			if placement.is_empty(): result.problem = "背包没有足够的空间。"; return result
			result.placements.append(placement)
			trial.append({"id":-trial.size()-2,"kind":kind,"x":placement.x,"y":placement.y,"rotated":placement.rotated})
	if order.side == "buy" and result.total > order.budget:
		result.problem = "买不起：顾客预算 %s 度，商品总价 %s 度。" % [str(order.budget),str(result.total)]
	return result

static func free_placement(state: RefCounted, cargo: Array[Dictionary], kind: String) -> Dictionary:
	var bounds: Vector2i = state.grid_size("bag")
	for rotated in [false,true]:
		for y in range(bounds.y):
			for x in range(bounds.x):
				if state.fits(cargo,bounds,Rect2i(Vector2i(x,y),state.footprint(kind,rotated))):
					return {"kind":kind,"x":x,"y":y,"rotated":rotated}
	return {}

static func confirm(state: RefCounted, selection: Array) -> String:
	var quote := preview(state,selection)
	if not quote.problem.is_empty(): return quote.problem
	var visits := record(state)
	var order: Dictionary = visits.active
	if order.side == "buy":
		for id in quote.entries: state.inventory.erase(state.find_entry("bag",id))
		var repayment := minf(quote.total,state.debt)
		state.debt = snappedf(state.debt-repayment,0.1)
		state.account = snappedf(state.account+quote.total-repayment,0.1)
		order.budget = snappedf(order.budget-quote.total,0.1)
	else:
		for p in quote.placements: state.inventory.append(state.make_entry(p.kind,Vector2i(p.x,p.y),p.rotated))
		state.spend_or_owe(quote.total)
		order.budget = snappedf(order.budget+quote.total,0.1)
		for kind in quote.kinds: order.stock[kind] -= 1
	for kind in quote.kinds: state.record_trade("demand" if order.side == "buy" else "stock",kind)
	order.status = "completed"
	order.total = quote.total
	visits.completed += 1
	return ""

static func valid_saved(raw: Variant) -> bool:
	if not raw is Dictionary: return false
	for station in raw:
		if not station is String: return false
		var r: Variant = raw[station]
		if not r is Dictionary or r.size() != 3 or not r.has_all(["arrived","completed","active"]): return false
		for key in ["arrived","completed"]:
			if not (r[key] is int or r[key] is float) or not is_finite(r[key]) or r[key] != floor(r[key]): return false
		if r.arrived < 0 or r.arrived > daily_limit(station) or r.completed < 0 or r.completed > r.arrived: return false
		var o: Variant = r.active
		if not o is Dictionary: return false
		if o.is_empty():
			if r.arrived != r.completed: return false
			continue
		if o.size() != 8 or not o.has_all(["id","visitor","side","category","budget","status","stock","total"]): return false
		if not o.id is String or o.side not in ["buy","sell"] or not CATEGORIES.has(o.category) or o.status not in ["open","completed"]: return false
		if not (o.visitor is int or o.visitor is float) or not is_finite(o.visitor) or o.visitor != floor(o.visitor) or o.visitor < 0 or o.visitor >= Visitors.ENTRIES.size(): return false
		for key in ["budget","total"]:
			if not (o[key] is int or o[key] is float) or not is_finite(o[key]) or o[key] < 0 or o[key] > 1000000: return false
		if not o.stock is Dictionary or (o.side == "buy" and not o.stock.is_empty()): return false
		for kind in o.stock:
			var quantity: Variant = o.stock[kind]
			if not kind is String or category_of(kind) != o.category or not (quantity is int or quantity is float) or not is_finite(quantity) or quantity != floor(quantity) or quantity < 0 or quantity > 2: return false
		if r.arrived < 1 or r.completed != r.arrived - (1 if o.status == "open" else 0): return false
	return true
