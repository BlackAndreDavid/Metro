extends SceneTree
const State = preload("res://scripts/cabin_state.gd")
const Orders = preload("res://scripts/commerce/customer_orders.gd")
const Rail = preload("res://scripts/cabin_map.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _initialize() -> void: call_deferred("run")
func payload_for(state,kind: String) -> Dictionary:
	for entry in state.inventory:
		if entry.kind == kind: return {"source":"bag","id":entry.id}
	return {}
func run() -> void:
	var state := State.new()
	check(Orders.daily_limit("邮电新村") == 4 and Orders.daily_limit("四平路") == 6 and Orders.daily_limit("同济大学") == 5, "station-specific visitor caps")
	var order := Orders.ensure(state)
	check(order.side == "buy" and order.category == "supplies" and Orders.record(state).arrived == 1, "first customer buys a category rather than exact item")
	check(Orders.ensure(state).id == order.id and Orders.record(state).arrived == 1, "reopening does not reroll order or consume another slot")
	var water := payload_for(state,"water")
	var ration := payload_for(state,"ration")
	var battery := payload_for(state,"aaa")
	check(not Orders.preview(state,[battery]).problem.is_empty(), "wrong category rejected")
	check(not Orders.preview(state,[water,water]).problem.is_empty(), "same inventory object cannot be selected twice")
	order.budget = 1.0
	var before := state.save_data().duplicate(true)
	check(Orders.preview(state,[water]).problem.begins_with("买不起"), "over-budget order says cannot afford")
	check(not Orders.confirm(state,[water]).is_empty() and state.save_data() == before, "over-budget rejection is atomic")
	order.budget = 100.0
	var quote := Orders.preview(state,[water,ration])
	check(quote.problem.is_empty() and quote.total > 0, "different goods in one category accepted")
	state.debt = 3.0
	var account: float = state.account
	check(Orders.confirm(state,[water,ration]).is_empty(), "customer purchase commits")
	check(is_equal_approx(order.budget,100-quote.total) and state.debt == 0 and is_equal_approx(state.account,account+quote.total-3), "customer purchase reduces budget and repays player debt")
	check(state.supply_count("water") == 0 and state.supply_count("ration") == 0 and order.status == "completed", "completed order consumes precisely selected items")
	before = state.save_data().duplicate(true)
	check(not Orders.confirm(state,[water]).is_empty() and state.save_data() == before, "completed order cannot pay twice")
	var second := Orders.next(state)
	check(second.side == "sell" and Orders.record(state).arrived == 2, "next visitor has one selling category order")
	check(second.visitor != order.visitor, "consecutive customers have distinct appearances")
	var kind: String = second.stock.keys()[0]
	check(not Orders.preview(state,[{"source":"stock","kind":kind},{"source":"stock","kind":kind},{"source":"stock","kind":kind}]).problem.is_empty(), "seller stock cannot be duplicated")
	state.inventory.clear()
	var bounds: Vector2i = state.grid_size("bag")
	for y in range(bounds.y):
		for x in range(bounds.x): state.inventory.append(state.make_entry("water",Vector2i(x,y),false))
	before = state.save_data().duplicate(true)
	check(not Orders.confirm(state,[{"source":"stock","kind":kind}]).is_empty() and state.save_data() == before, "full bag rejects whole purchase atomically")
	state.inventory.clear()
	account = state.account
	var budget: float = second.budget
	quote = Orders.preview(state,[{"source":"stock","kind":kind},{"source":"stock","kind":kind}])
	check(quote.problem.is_empty() and quote.placements[0] != quote.placements[1], "multiple incoming items receive distinct free cells")
	check(Orders.confirm(state,[{"source":"stock","kind":kind},{"source":"stock","kind":kind}]).is_empty(), "customer sale commits multiple items")
	check(is_equal_approx(second.budget,budget+quote.total) and is_equal_approx(state.account,account-quote.total) and second.stock[kind] == 0, "customer sale increases budget and deducts player payment and stock")
	var path := OS.get_environment("METRO_TEST_RESULTS").path_join("customer_save.json")
	check(state.save_current(path) == OK, "order records can be saved")
	var loaded := State.new()
	check(loaded.load_cabin(path,Rail.STATIONS.keys()) and Orders.ensure(loaded).id == second.id and Orders.ensure(loaded).status == "completed", "reload preserves completed order awaiting departure")
	Orders.next(loaded)
	var pending := Orders.ensure(loaded)
	loaded.write_save(path,loaded.save_data())
	var resumed := State.new()
	check(resumed.load_cabin(path,Rail.STATIONS.keys()) and Orders.ensure(resumed).id == pending.id and Orders.record(resumed).arrived == 3, "pending order survives save without new visit")
	var invalid := loaded.save_data()
	invalid.customer_visits[loaded.station].active.budget = -1
	loaded.write_save(path,invalid)
	before = resumed.save_data().duplicate(true)
	check(not resumed.load_cabin(path,Rail.STATIONS.keys()) and resumed.save_data() == before, "invalid customer budget load is atomic")
	var legacy := state.save_data()
	legacy.version = 11
	legacy.erase("customer_visits")
	state.write_save(path,legacy)
	check(resumed.load_cabin(path,Rail.STATIONS.keys()) and resumed.customer_visits.is_empty(), "version 11 save gains fresh customer records")
	var capped := State.new()
	var origin: String = capped.station
	for i in range(Orders.daily_limit(origin)):
		var current := Orders.ensure(capped)
		current.budget = 100000.0
		capped.inventory.clear()
		var choice: Dictionary
		if current.side == "buy":
			var item: String = Orders.CATEGORIES[current.category].items[0]
			capped.add_supply(item,"bag")
			choice = payload_for(capped,item)
		else: choice = {"source":"stock","kind":current.stock.keys()[0]}
		check(Orders.confirm(capped,[choice]).is_empty(), "daily visitor order completes")
		Orders.next(capped)
	check(Orders.ensure(capped).is_empty() and Orders.record(capped).arrived == Orders.daily_limit(origin), "daily customer cap cannot be exceeded")
	capped.station = "四平路"
	check(not Orders.ensure(capped).is_empty() and Orders.record(capped).arrived == 1, "new station has independent quota")
	capped.station = origin
	check(Orders.ensure(capped).is_empty(), "returning station does not reset quota")
	capped.next_day()
	check(not Orders.ensure(capped).is_empty() and Orders.record(capped).arrived == 1, "next day resets customer quotas")
	print("CUSTOMER_ORDERS: %d checks, %d failures" % [checks,failures])
	if failures == 0: print("CUSTOMER_ORDERS_OK")
	quit(1 if failures else 0)
