extends "res://scripts/state.gd"

var base_name: String = "未命名基地"

const Markets = preload("res://scripts/cabin_markets.gd")
const Rail = preload("res://scripts/cabin_map.gd")
const AutoRepair = preload("res://scripts/auto_repair.gd")
const START_STATION := "邮电新村"
const SMALL := Vector2i(5, 4)
const LARGE := Vector2i(6, 5)
const LOCKER := Vector2i(8, 5)
const FOOTPRINTS := {
	"computer": Vector2i(2, 2), "copper": Vector2i(1, 2), "tools": Vector2i(3, 1),
	"book": Vector2i(1, 2), "meds": Vector2i(2, 2),
	"circuit": Vector2i(2, 1), "powercore": Vector2i(3, 2),
	"relic": Vector2i(2, 2),
	"aaa": Vector2i.ONE, "water": Vector2i.ONE, "ration": Vector2i.ONE,
	"tire": Vector2i(2, 2), "bolts": Vector2i.ONE, "steel_plate": Vector2i(3, 1),
	"car_battery": Vector2i(2, 2), "engine": Vector2i(3, 2),
}
const SUPPLY_NAMES := {"aaa": "七号电池", "water": "饮用水", "ration": "口粮"}
const RARITY := {
	"computer": 0,
	"book": 0, "copper": 0, "tools": 1,
	"meds": 2, "circuit": 2, "relic": 2, "powercore": 3,
	"aaa": 0, "water": 0, "ration": 0,
	"tire": 0, "bolts": 0, "steel_plate": 1, "car_battery": 2, "engine": 3,
}
const RARITY_NAMES := ["普通", "少见", "稀有", "珍稀"]
const RARITY_COLORS := [Color("bfc3ce"), Color("e4be76"), Color("ffa271"), Color("ff7873")]
const EPOCH := "2026-07-11T00:00:00"
const CABIN_SAVE_VERSION := 19
const CustomerDialogue = preload("res://scripts/commerce/customer_dialogue.gd")
const CustomerOrders = preload("res://scripts/commerce/customer_orders.gd")
const ItemCatalog = preload("res://scripts/items/item_catalog.gd")
static var ITEM_DEFINITIONS: Dictionary = {}
const Furniture = preload("res://scripts/items/furniture_catalog.gd")
const MAX_CARRIAGES := 3
const EXPANSION_COST := {"steel_plate": 2, "bolts": 4, "tools": 1}
const EXTRA_TRAVEL_COST := 10
const EXTRA_DAILY_COST := 2.0
var FURNITURE_IDS: Array:
	get:return furniture_layout.keys()
const Renovation=preload("res://scripts/construction/renovation_rules.gd")

const CAR_CAPACITY := 500.0
const CAR_START_POWER := 100.0
const ACCOUNT_START_POWER := 100.0
const STATION_CHARGE_CAP := 200
const TRAVEL_COST_PER_STOP := 30
const BATTERY_FILL_COST := 2.0
const COMPUTER_DAILY_COST := 2.0
const FULL_CHARGE := 100
const FLASHLIGHT_DRAIN_PER_SECOND := 5.0
const NO_CELL := -1
const TRIP_LIMIT_SECONDS := 90
const BLACKOUT_INTERVAL := 5

var carriage_count := 1
var furniture_layout := Furniture.initial_layout()
var station := START_STATION
const PREPARATION := Vector2i(8, 6)
const TOOL_CAPABILITIES := {"flashlight":"light", "crowbar":"crowbar", "wrench":"wrench", "large_backpack":"wide"}
var preparation: Array[Dictionary] = []
var furniture_storage: Dictionary = {}
var storage_sizes: Dictionary = {}
var furniture_owned: Array = []
var temporary_furniture: Array = []
var fixtures_seeded_cars := 1
var renovation_active := false
var technologies: Dictionary = {}
var learned_furniture: Array = []
var locker: Array[Dictionary] = []
var wide_bag := false
var collected: Dictionary = {}
var gear: Dictionary = {}
var next_id := 1
var active_item: Dictionary = {}
var market_usage: Dictionary = {}
var customer_visits: Dictionary = {}
var content_flags: Dictionary = {}
var dialogue_progress: Dictionary = {}
var npc_affection: Dictionary = {}
var faction_trust: Dictionary = {}
var narrative_history: Dictionary = {}
var daily_customer_ids: Dictionary = {}
var installed_charge := FULL_CHARGE
var flashlight_on := false
var flashlight_drain := 0.0
var trip_deadline_ms := 0
var debt := 0.0
var days_in_debt := 0
var days_without_water := 0
var days_without_food := 0
var drank_today := false
var ate_today := false
var game_over_reason := ""
var car_power := CAR_START_POWER
var world_seed := randi()
var charger_used: Dictionary = {}
var trip_loot: Array[String] = []
var trip_loot_station := ""
var auto_repair_level := 0

func _init() -> void:
	ITEM_DEFINITIONS = ItemCatalog.resources()
	account = ACCOUNT_START_POWER
	give_starter_supplies()
	add_supply("computer", "locker")
	give_preparation_tools()
	for kind in FURNITURE_IDS:
		if Furniture.DEFINITIONS[kind].default_owned:
			furniture_owned.append(kind)
			if furniture_layout[kind]==null and Furniture.DEFINITIONS[kind].item_id.is_empty():temporary_furniture.append(kind)

func date_unix(extra_days: int = 0) -> int:
	return Time.get_unix_time_from_datetime_string(EPOCH) + (day - 1 + extra_days) * 86400

func date_text(extra_days: int = 0) -> String:
	return Time.get_date_string_from_unix_time(date_unix(extra_days)).replace("-", ".")

func weather() -> String:
	return ["阴", "小雨", "雾", "晴"][(day - 1) % 4]

func news() -> String:
	var text := super.news().replace("收购价", "今日报价")
	if is_blackout():
		return text + "\n今日全线停电，充电站暂停，满电七号电池涨价 50%。"
	if is_blackout(1):
		return text + "\n明日计划停电，可提前充满备用电池。"
	return text

func is_blackout(extra_days: int = 0) -> bool:
	return (day + extra_days) % BLACKOUT_INTERVAL == 0

func has_charger(location: String) -> bool:
	return location in Markets.CHARGERS

func station_roll(location: String, purpose: String, maximum: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, day, location, purpose])
	return rng.randi_range(0, maximum)

func charger_stock(location: String) -> float:
	if is_blackout() or not has_charger(location):
		return 0.0
	var daily_supply := station_roll(location, "charger", roundi(STATION_CHARGE_CAP / 10.0)) * 10
	return maxf(0.0, daily_supply - float(charger_used.get(location, 0.0)))

func car_charge_limit() -> float:
	return minf(charger_stock(station), CAR_CAPACITY - car_power)

func charge_car(requested: float) -> float:
	if trip_active or not game_over_reason.is_empty() or not is_finite(requested) or requested <= 0.0:
		return 0.0
	var amount := car_charge_limit()
	if amount <= 0.0:
		return 0.0
	amount = minf(requested, amount)
	spend_or_owe(amount)
	car_power += amount
	charger_used[station] = float(charger_used.get(station, 0.0)) + amount
	return amount

func travel_to(destination: String, steps: int) -> bool:
	var cost := steps * travel_cost_per_stop()
	if trip_active or not game_over_reason.is_empty() or destination == station or cost <= 0 or car_power < cost:
		return false
	car_power -= cost
	station = destination
	return true

func extraction_cost(destination: String) -> int:
	var route := Rail.route(station, destination)
	return -1 if route.is_empty() else (route.size() - 1) * travel_cost_per_stop()

func extract_at(destination: String) -> String:
	if not trip_active or remaining_ms() == 0:
		return "外出时间已用完。"
	var cost := extraction_cost(destination)
	if cost < 0:
		return "车厢无法抵达这个站点。"
	if car_power < cost:
		return "车电不足。接应需要 %d 度，当前有 %s 度。" % [cost, str(snappedf(car_power, 0.1))]
	car_power -= cost
	station = destination
	end_trip()
	return ""

func item_name(kind: String) -> String:
	if ITEM_DEFINITIONS.has(kind):
		return ITEM_DEFINITIONS[kind].display_name
	if SUPPLY_NAMES.has(kind):
		return SUPPLY_NAMES[kind]
	if AutoRepair.PART_NAMES.has(kind):
		return AutoRepair.PART_NAMES[kind]
	return ITEMS[kind].name

func rarity_name(kind: String) -> String:
	return RARITY_NAMES[int(ItemCatalog.definition(kind).get("rarity",RARITY.get(kind,0)))]

func rarity_color(kind: String) -> Color:
	return RARITY_COLORS[int(ItemCatalog.definition(kind).get("rarity",RARITY.get(kind,0)))]

func bag_size() -> Vector2i:
	return LARGE if wide_bag else SMALL

func entries(container: String) -> Array[Dictionary]:
	if container == "active":
		var equipped: Array[Dictionary] = []
		if not active_item.is_empty(): equipped.append(active_item)
		return equipped
	if container == "battery":
		var slot: Array[Dictionary] = []
		if installed_charge != NO_CELL:
			slot.append({"id": NO_CELL, "kind": "aaa", "x": 0, "y": 0, "rotated": false, "charge": installed_charge})
		return slot
	if container.begins_with("furniture:"):
		var kind:=container.trim_prefix("furniture:")
		if not furniture_storage.has(kind):furniture_storage[kind]=[] as Array[Dictionary]
		return furniture_storage[kind]
	if container == "preparation": return preparation
	return locker if container == "locker" else inventory

func grid_size(container: String) -> Vector2i:
	if container == "battery":
		return Vector2i.ONE
	var kind:=container.trim_prefix("furniture:") if container.begins_with("furniture:") else container
	if storage_sizes.has(kind):return Vector2i(int(storage_sizes[kind][0]),int(storage_sizes[kind][1]))
	if container.begins_with("furniture:") and Furniture.DEFINITIONS.has(kind):return Furniture.DEFINITIONS[kind].storage
	if container == "preparation": return PREPARATION
	return LOCKER if container == "locker" else bag_size()

func footprint(kind: String, rotated: bool = false) -> Vector2i:
	if ITEM_DEFINITIONS.has(kind):
		return ITEM_DEFINITIONS[kind].footprint(rotated)
	var shape: Vector2i = FOOTPRINTS[kind]
	return Vector2i(shape.y, shape.x) if rotated else shape

func item_cells(entry: Dictionary) -> Array[Vector2i]:
	var offsets: Array[Vector2i] = ITEM_DEFINITIONS[entry.kind].cell_offsets(entry.get("rotated",false),entry.get("mirrored",false))
	var result: Array[Vector2i] = []
	for offset in offsets:result.append(Vector2i(entry.x,entry.y)+offset)
	return result

func fits_item(cargo: Array[Dictionary], bounds: Vector2i, kind: String, cell: Vector2i, rotated: bool=false, mirrored: bool=false, ignore_id: int=-1) -> bool:
	var candidate := {"kind":kind,"x":cell.x,"y":cell.y,"rotated":rotated,"mirrored":mirrored}
	return fits(cargo,bounds,Rect2i(cell,footprint(kind,rotated)),ignore_id,item_cells(candidate))

func item_rect(entry: Dictionary) -> Rect2i:
	return Rect2i(Vector2i(entry.x, entry.y), footprint(entry.kind, entry.rotated))

func entry_at(container: String, cell: Vector2i) -> Dictionary:
	for entry in entries(container):
		if cell in item_cells(entry):
			return entry
	return {}

func find_entry(container: String, id: int) -> Dictionary:
	for entry in entries(container):
		if entry.id == id:
			return entry
	return {}

func fits(cargo: Array[Dictionary], bounds: Vector2i, box: Rect2i, ignore_id: int = -1, mask: Array[Vector2i] = []) -> bool:
	if not Rect2i(Vector2i.ZERO,bounds).encloses(box):return false
	var candidate: Array[Vector2i] = mask.duplicate()
	if candidate.is_empty():
		for y in range(box.position.y,box.end.y):
			for x in range(box.position.x,box.end.x):candidate.append(Vector2i(x,y))
	for entry in cargo:
		if entry.id == ignore_id:continue
		for cell in item_cells(entry):
			if cell in candidate:return false
	return true

func ground_kind(slot: int) -> String:
	if slot < 0 or slot >= trip_loot.size() or not trip_active:
		return ""
	if slot in collected.get(trip_loot_station, []):
		return ""
	return trip_loot[slot]

func roll_loot(danger: int, crowbar: bool, location: String = "") -> Array[String]:
	if location.is_empty():
		location = station
	var rare_chance := 12 + 6 * danger
	var medical := station_roll(location, "medical", 99) < rare_chance
	var circuit := station_roll(location, "circuit", 99) < rare_chance
	var powercore := danger >= 3 and crowbar and station_roll(location, "powercore", 99) < 12
	return ["copper", "tools", "meds" if medical else "book", "powercore" if powercore else "", "circuit" if circuit else ""]

func picked(container: String, id: int) -> Dictionary:
	if container == "ground":
		var kind := ground_kind(id)
		return {} if kind.is_empty() else {"kind": kind, "rotated": false}
	return find_entry(container, id)

func can_place(selection: Dictionary, target: String, cell: Vector2i) -> bool:
	if not valid_container(target) or not valid_container(selection.get("source",""),true) or trip_active and (is_base_container(target) or is_base_container(selection.source)):
		return false
	var source: String = selection.source
	if source == "ground" and remaining_ms() == 0:
		return false
	var id: int = selection.id
	var entry := picked(source, id)
	if entry.is_empty():
		return false
	if target == "battery":
		return source == "bag" and entry.kind == "aaa" and cell == Vector2i.ZERO
	if source == "battery" and target != "bag":
		return false
	if not trip_active and (source == "preparation" or target == "preparation"):
		var trial: Array[Dictionary] = inventory.duplicate(true)
		if source == "bag":
			for i in range(trial.size()-1,-1,-1):
				if trial[i].id == id: trial.remove_at(i)
		if target == "bag":
			var incoming := entry.duplicate(true);incoming.x=cell.x;incoming.y=cell.y;incoming.rotated=selection.rotated;trial.append(incoming)
		var carried_trial: Array[Dictionary]=trial.duplicate()
		if source!="active" and not active_item.is_empty():carried_trial.append(active_item)
		var bounds := LARGE if cargo_has_tool(carried_trial,"wide") else SMALL
		for item in trial:
			if not Rect2i(Vector2i.ZERO,bounds).encloses(item_rect(item)):return false
	return fits_item(entries(target),grid_size(target),entry.kind,cell,selection.rotated,selection.get("mirrored",entry.get("mirrored",false)),id if source==target else -1)

func place(selection: Dictionary, target: String, cell: Vector2i) -> bool:
	if not can_place(selection, target, cell):
		return false
	var source: String = selection.source
	var id: int = selection.id
	var entry := picked(source, id)
	if target == "battery":
		install_battery(entry)
		return true
	if source == "battery":
		var spare := make_entry("aaa", cell, selection.rotated)
		spare.mirrored=selection.get("mirrored",false)
		spare.charge = installed_charge
		inventory.append(spare)
		installed_charge = NO_CELL
		flashlight_on = false
		return true
	if source == "ground":
		if not collected.has(trip_loot_station):
			collected[trip_loot_station] = []
		collected[trip_loot_station].append(id)
		entry = make_entry(entry.kind, cell, selection.rotated)
	elif source != target:
		if source == "active": active_item = {}
		else: entries(source).erase(entry)
	if source != target:
		entries(target).append(entry)
	entry.x = cell.x
	entry.y = cell.y
	entry.rotated = selection.rotated
	entry.mirrored = selection.get("mirrored",entry.get("mirrored",false))
	if source == "preparation" or target == "preparation": sync_carried_tools()
	elif trip_active and gear.get("inventory_tools",false): sync_carried_tools()
	return true

func make_entry(kind: String, cell: Vector2i, rotated: bool) -> Dictionary:
	kind = ItemCatalog.runtime_id(kind)
	var entry := {"id": next_id, "kind": kind, "x": cell.x, "y": cell.y, "rotated": rotated,"mirrored":false}
	if kind == "aaa":
		entry.charge = FULL_CHARGE
	next_id += 1
	return entry

func used_cells(container: String) -> int:
	var occupied := 0
	for entry in entries(container):
		occupied += item_cells(entry).size()
	return occupied

func enroll_auto_repair(level: int) -> String:
	if station != AutoRepair.STATION or trip_active or not game_over_reason.is_empty():
		return "请到同济大学站的培训点报名。"
	if level < 1 or level > AutoRepair.COURSES.size() or level != auto_repair_level + 1:
		return "请按顺序报名尚未学过的课程。"
	var fee: int = AutoRepair.COURSES[level - 1].fee
	if account < fee:
		return "报名需要 %d 度账户余额。" % fee
	account -= fee
	auto_repair_level = level
	return ""

func toggle_wrench() -> void:
	if trip_active and gear.get("wrench", false):
		gear.wrench_equipped = not gear.wrench_equipped

func vehicle_part_taken(vehicle_id: String, kind: String) -> bool:
	return kind in collected.get("vehicle/" + vehicle_id, [])

func salvage_vehicle_part(vehicle_id: String, kind: String) -> String:
	if not trip_active or remaining_ms() == 0:
		return "外出时间已用完。"
	if not gear.get("wrench_equipped", false):
		return "需要装备扳手。"
	var level := AutoRepair.required_level(kind)
	if level == 0 or auto_repair_level < level:
		return "尚未掌握这项拆解。"
	if vehicle_part_taken(vehicle_id, kind):
		return "这辆车上的该零件已经拆过。"
	if not add_supply(kind, "bag"):
		return "背包没有合适的空位。"
	var vehicle_key := "vehicle/" + vehicle_id
	var taken: Array = collected.get(vehicle_key, [])
	taken.append(kind)
	collected[vehicle_key] = taken
	return ""

func market_offer(side: String, kind: String, location: String = "", charge: int = FULL_CHARGE) -> Dictionary:
	var market_station := station if location.is_empty() else location
	var catalog: Dictionary
	if side == "stock":
		catalog = Markets.ESSENTIALS if Markets.ESSENTIALS.has(kind) else Markets.profile(market_station).stock
	else:
		catalog = Markets.demand(market_station)
	var terms: Array = catalog.get(kind, [])
	if terms.is_empty():
		return {}
	var used: int = market_usage.get(market_key(market_station, side, kind), 0)
	var multiplier := 1.5 if kind == "aaa" and is_blackout() else market_multiplier(kind)
	if side == "demand" and kind == "aaa":
		multiplier *= lerpf(0.5, 1.0, float(charge) / FULL_CHARGE)
	return {
		"price": snappedf(float(terms[0]) * multiplier, 0.1),
		"remaining": maxi(0, int(terms[1]) - used),
	}

func market_key(location: String, side: String, kind: String) -> String:
	return "%s/%s/%s" % [location, side, kind]

func record_trade(side: String, kind: String) -> void:
	var key := market_key(station, side, kind)
	market_usage[key] = market_usage.get(key, 0) + 1

func credit_shortfall(amount: float) -> float:
	return snappedf(maxf(0.0, amount - account), 0.1)

func spend_or_owe(amount: float) -> void:
	debt = snappedf(debt + credit_shortfall(amount), 0.1)
	account = maxf(0.0, account - amount)

func sell(id: int) -> float:
	var entry := find_entry("bag", id)
	if trip_active or entry.is_empty() or not game_over_reason.is_empty():
		return 0.0
	var offer := market_offer("demand", entry.kind, station, int(entry.get("charge", FULL_CHARGE)))
	if offer.is_empty() or offer.remaining == 0:
		return 0.0
	var paid: float = offer.price
	inventory.erase(entry)
	var repayment := minf(paid, debt)
	debt = snappedf(debt - repayment, 0.1)
	account += paid - repayment
	record_trade("demand", entry.kind)
	return paid

func purchase(kind: String) -> String:
	if trip_active or not game_over_reason.is_empty():
		return "回到车厢后可交易。"
	var offer := market_offer("stock", kind)
	if offer.is_empty():
		return "本站不出售这件物品。"
	if offer.remaining == 0:
		return "今天的库存已售完。"
	var cost: float = offer.price
	if not add_supply(kind, "bag"):
		return "背包没有合适的空位。"
	spend_or_owe(cost)
	record_trade("stock", kind)
	return ""

func first_free_placement(kind: String, container: String, mirrored:bool=false) -> Dictionary:
	var bounds := grid_size(container)
	var cargo := entries(container)
	for rotated in [false, true]:
		var shape := footprint(kind, rotated)
		for y in range(bounds.y):
			for x in range(bounds.x):
				var cell := Vector2i(x, y)
				if fits_item(cargo,bounds,kind,cell,rotated,mirrored):
					return {"cell": cell, "rotated": rotated}
	return {}

func add_supply(kind: String, container: String) -> bool:
	var placement := first_free_placement(kind, container)
	if placement.is_empty():
		return false
	entries(container).append(make_entry(kind, placement.cell, placement.rotated))
	return true

func pick_up_ground(slot: int) -> bool:
	var kind := ground_kind(slot)
	if kind.is_empty() or remaining_ms() == 0:
		return false
	var placement := first_free_placement(kind, "bag")
	if placement.is_empty():
		return false
	return place({"source": "ground", "id": slot, "rotated": placement.rotated}, "bag", placement.cell)

func give_starter_supplies() -> void:
	for kind in ["aaa", "water", "ration"]:
		if not add_supply(kind, "bag"):
			add_supply(kind, "locker")

func supply_count(kind: String) -> int:
	kind = ItemCatalog.runtime_id(kind)
	var count := 0
	for entry in inventory + all_base_cargo():
		if entry.kind == kind:
			count += 1
	return count

func consume_supply(kind: String) -> String:
	if trip_active or not game_over_reason.is_empty() or kind not in ["water", "ration"]:
		return "当前无法使用补给。"
	var water := kind == "water"
	if (water and drank_today) or (not water and ate_today):
		return "今日已%s。" % ("喝水" if water else "进食")
	for cargo in all_cargo_arrays():
		for entry in cargo:
			if entry.kind == kind:
				cargo.erase(entry)
				if water:
					drank_today = true
				else:
					ate_today = true
				return ""
	return "没有%s，可到交易窗口购买。" % item_name(kind)

func usable_spares() -> int:
	var count := 0
	for entry in inventory:
		if entry.kind == "aaa" and entry.charge > 0:
			count += 1
	return count

func spare_battery() -> Dictionary:
	var best: Dictionary = {}
	var charge_to_beat := maxi(installed_charge, 0)
	for entry in inventory:
		if entry.kind == "aaa" and entry.charge > charge_to_beat:
			best = entry
			charge_to_beat = entry.charge
	return best

func replace_battery() -> String:
	var entry := spare_battery()
	if entry.is_empty():
		return "背包里没有电量更高的可用七号电池。"
	install_battery(entry)
	return ""

func install_battery(entry: Dictionary) -> void:
	var replacement: int = entry.charge
	if installed_charge == NO_CELL:
		inventory.erase(entry)
	else:
		entry.charge = installed_charge
	installed_charge = replacement
	if installed_charge == 0:
		flashlight_on = false

func toggle_flashlight() -> String:
	if not trip_active or remaining_ms() == 0:
		return "外出时间已用完。"
	if gear.get("inventory_tools",false) and not carried_tools().light:return "没有携带手电筒。"
	if installed_charge <= 0:
		return "手电筒没有电，请装入有电的七号电池。"
	flashlight_on = not flashlight_on
	return ""

func tick_flashlight(delta: float) -> void:
	if not trip_active or not flashlight_on:
		return
	flashlight_drain += delta * FLASHLIGHT_DRAIN_PER_SECOND
	var spent := mini(floori(flashlight_drain + 0.000001), installed_charge)
	flashlight_drain = maxf(0.0, flashlight_drain - spent)
	installed_charge -= spent
	if installed_charge == 0:
		flashlight_on = false
		flashlight_drain = 0.0

func battery_fill_cost(charge_level: int) -> float:
	if charge_level == NO_CELL:
		return 0.0
	return ceilf((FULL_CHARGE - charge_level) * BATTERY_FILL_COST / FULL_CHARGE)

func recharge_battery(id: int) -> String:
	if trip_active or not game_over_reason.is_empty():
		return "返回车厢后可给电池充电。"
	var entry := find_entry("bag", id) if id != NO_CELL else {}
	var charge_level := installed_charge if id == NO_CELL else int(entry.get("charge", NO_CELL))
	var cost := battery_fill_cost(charge_level)
	if cost <= 0.0:
		return "这节电池无需充电。"
	if car_power < cost:
		return "车内储电不足。"
	car_power -= cost
	if id == NO_CELL:
		installed_charge = FULL_CHARGE
	else:
		entry.charge = FULL_CHARGE
	return ""

func next_day() -> void:
	customer_visits.clear()
	daily_customer_ids.clear()
	dialogue_progress.clear()
	super.next_day()
	market_usage.clear()
	charger_used.clear()
	car_power = overnight_power()

func overnight_power() -> float:
	return maxf(0.0, car_power - daily_power_cost())

func trip_limit() -> int:
	return TRIP_LIMIT_SECONDS

func remaining_ms() -> int:
	return maxi(0, trip_deadline_ms - Time.get_ticks_msec()) if trip_active else 0

func suit_rent(heavy: bool) -> int:
	return 50 if heavy else 30

func depart(loadout: Dictionary, radiation: int, loot_station: String = "") -> String:
	if trip_active or not game_over_reason.is_empty():
		return "已经出发。"
	loadout = loadout.duplicate(true)
	if loadout.get("inventory_tools",false):loadout.merge(carried_tools(),true)
	if not loadout.get("inventory_tools",false) and (not loadout.get("light", false) or installed_charge <= 0):
		return "出站必须带手电筒并装入有电的七号电池。"
	if radiation >= 3 and not loadout.heavy:
		return "高辐射区需要加强防护服。"
	var bounds := LARGE if loadout.wide else SMALL
	for entry in inventory:
		if not Rect2i(Vector2i.ZERO, bounds).encloses(item_rect(entry)):
			return "有物品超出所选背包的边界，请先在柜子里整理。"
	spend_or_owe(suit_rent(loadout.heavy))
	gear = loadout.duplicate()
	gear.wrench = auto_repair_level > 0 and loadout.get("wrench", false)
	gear.wrench_equipped = gear.wrench
	trip_loot_station = station if loot_station.is_empty() else loot_station
	var loot_radiation: int = radiation if loot_station.is_empty() else Rail.station_info(loot_station).radiation
	trip_loot = roll_loot(loot_radiation, gear.crowbar, trip_loot_station)
	if not loot_station.is_empty():
		trip_loot.append_array(["book", "copper", "tools", "book"])
	trip_loot.append("aaa")
	wide_bag = loadout.wide
	trip_active = true
	trip_deadline_ms = Time.get_ticks_msec() + trip_limit() * 1000
	return ""

func end_trip() -> void:
	trip_active = false
	flashlight_on = false
	trip_deadline_ms = 0
	gear.clear()
	trip_loot.clear()
	trip_loot_station = ""

func fail_trip() -> int:
	if not trip_active:
		return 0
	var fee := 500 if gear.heavy else 300
	spend_or_owe(fee)
	inventory.clear()
	active_item.clear()
	installed_charge = NO_CELL
	flashlight_drain = 0.0
	end_trip()
	return fee

func survival_after_day() -> Dictionary:
	var dry_days := 0 if drank_today else days_without_water + 1
	var hungry_days := 0 if ate_today else days_without_food + 1
	var overdue_days := days_in_debt + 1 if debt > 0.0 else 0
	var reasons := PackedStringArray()
	if dry_days >= 2:
		reasons.append("连续两天未喝水")
	if hungry_days >= 3:
		reasons.append("连续三天未进食")
	if overdue_days >= 2:
		reasons.append("连续两天欠费未结清")
	return {
		"days_without_water": dry_days,
		"days_without_food": hungry_days,
		"days_in_debt": overdue_days,
		"drank_today": false,
		"ate_today": false,
		"game_over_reason": "、".join(reasons),
	}

func save_next_day(path: String) -> Error:
	if trip_active or not game_over_reason.is_empty():
		return ERR_BUSY
	if renovation_active and not furniture_completion_problem().is_empty():return ERR_INVALID_DATA
	var data := save_data()
	data.day = day + 1
	data.charger_used = {}
	data.car_power = overnight_power()
	data.merge(survival_after_day(), true)
	var err := write_save(path, data)
	if err != OK:
		return err
	next_day()
	restore_vitals(data)
	collected.clear()
	return OK

func save_current(path: String) -> Error:
	if renovation_active and not furniture_completion_problem().is_empty():return ERR_INVALID_DATA
	if trip_active:
		return ERR_BUSY
	return write_save(path, save_data())

func save_data() -> Dictionary:
	return {
		"base_name": base_name, "version": CABIN_SAVE_VERSION, "day": day, "account": account, "station": station,
		"wide": wide_bag, "bag": inventory, "locker": locker, "preparation": preparation, "furniture_storage": furniture_storage, "storage_sizes": storage_sizes, "furniture_owned": furniture_owned, "temporary_furniture":temporary_furniture.duplicate(), "fixtures_seeded_cars":fixtures_seeded_cars, "technologies":technologies.duplicate(), "learned_furniture":learned_furniture.duplicate(), "furniture_content_signature":furniture_signature(), "active_item":active_item.duplicate(true),
		"installed_charge": installed_charge, "debt": debt,
		"days_in_debt": days_in_debt, "days_without_water": days_without_water,
		"days_without_food": days_without_food, "drank_today": drank_today,
		"ate_today": ate_today, "game_over_reason": game_over_reason,
		"car_power": car_power, "world_seed": world_seed, "charger_used": charger_used,
		"auto_repair_level": auto_repair_level,
		"customer_visits": customer_visits.duplicate(true),
		"content_flags": content_flags.duplicate(true),
		"dialogue_progress": dialogue_progress.duplicate(true),
		"npc_affection": npc_affection.duplicate(true),
		"faction_trust": faction_trust.duplicate(true),
		"narrative_history": narrative_history.duplicate(true),
		"daily_customer_ids": daily_customer_ids.duplicate(true),
		"carriage_count": carriage_count, "furniture_layout": furniture_layout.duplicate(true),
	}

func write_save(path: String, data: Dictionary) -> Error:
	var err := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if err != OK:
		return err
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	err = file.get_error()
	file.close()
	if err == OK:
		err = DirAccess.rename_absolute(temp, path)
	if err != OK:
		DirAccess.remove_absolute(temp)
	return err

func restore_vitals(data: Dictionary) -> void:
	installed_charge = int(data.get("installed_charge", FULL_CHARGE))
	debt = float(data.get("debt", 0.0))
	days_in_debt = int(data.get("days_in_debt", 0))
	days_without_water = int(data.get("days_without_water", 0))
	days_without_food = int(data.get("days_without_food", 0))
	drank_today = data.get("drank_today", false)
	ate_today = data.get("ate_today", false)
	game_over_reason = data.get("game_over_reason", "")

func valid_vitals(data: Dictionary) -> bool:
	var amount: Variant = data.get("debt")
	if not (amount is float or amount is int) or not is_finite(amount) or amount < 0:
		return false
	return (valid_index(data.get("installed_charge"), NO_CELL, FULL_CHARGE)
		and valid_index(data.get("days_in_debt"), 0, 2)
		and valid_index(data.get("days_without_water"), 0, 2)
		and valid_index(data.get("days_without_food"), 0, 3)
		and data.get("drank_today") is bool and data.get("ate_today") is bool
		and data.get("game_over_reason") is String)

func valid_car_state(data: Dictionary) -> bool:
	var power: Variant = data.get("car_power")
	var used: Variant = data.get("charger_used")
	if not (power is float or power is int) or not is_finite(power) or power < 0 or power > CAR_CAPACITY:
		return false
	if not valid_index(data.get("world_seed"), 0, 0xffffffff) or not used is Dictionary:
		return false
	for location in used:
		var amount: Variant = used[location]
		if not has_charger(location) or not (amount is float or amount is int):
			return false
		if not is_finite(amount) or amount < 0 or amount > STATION_CHARGE_CAP:
			return false
	return true

func load_cabin(path: String, known_stations: Array) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return false
	var data: Variant = parser.data
	if not data is Dictionary:
		return false
	return load_data(data,known_stations)

func load_data(data: Dictionary, known_stations: Array) -> bool:
	var version: Variant = data.get("version")
	if version != 1 and version != 2 and version != 3 and version != 4 and version != 5 and version != 6 and version != 7 and version != 8 and version != 9 and version != 10 and version != 11 and version != 12 and version != 13 and version != 14 and version != 15 and version != 16 and version != 17 and version != 18 and version != CABIN_SAVE_VERSION:
		return false
	if version >= 15 and not CustomerDialogue.valid_social(data):
		return false
	if version >= 14 and not CustomerDialogue.valid_saved(data.get("content_flags"),data.get("dialogue_progress")):
		return false
	if version >= 12 and not CustomerOrders.valid_saved(data.get("customer_visits"),version == 12):
		return false
	if version >= 3 and not valid_car_state(data):
		return false
	if not valid_index(data.get("auto_repair_level", 0), 0, AutoRepair.COURSES.size()):
		return false
	if version >= 4 and not valid_home_layout(data, int(version)):
		return false
	var needs_upgrade: bool = version == 1
	if not needs_upgrade and not valid_vitals(data):
		return false
	if data.get("station") not in known_stations or not data.get("wide") is bool:
		return false
	var balance: Variant = data.get("account")
	if not (balance is float or balance is int) or not is_finite(balance) or balance < 0:
		return false
	if not valid_index(data.get("day"), 1, 100000):
		return false
	var raw_sizes: Variant=data.get("storage_sizes",{}) if version>=18 else {}
	if not raw_sizes is Dictionary:return false
	var loaded_sizes: Dictionary=raw_sizes
	for kind in loaded_sizes:
		var dimensions: Variant=loaded_sizes[kind]
		if not Furniture.DEFINITIONS.has(kind) or Furniture.DEFINITIONS[kind].storage==Vector2i.ZERO or not dimensions is Array or dimensions.size()!=2 or not valid_index(dimensions[0],1,16) or not valid_index(dimensions[1],1,16):return false
	var loaded_extra: Dictionary={}
	var raw_extra: Variant=data.get("furniture_storage",{}) if version>=18 else {}
	if not raw_extra is Dictionary:return false
	for kind in raw_extra:
		if not Furniture.DEFINITIONS.has(kind) or Furniture.DEFINITIONS[kind].storage==Vector2i.ZERO or kind in ["locker","preparation"]:return false
		var dimensions: Vector2i=Furniture.DEFINITIONS[kind].storage
		if loaded_sizes.has(kind):dimensions=Vector2i(loaded_sizes[kind][0],loaded_sizes[kind][1])
		var cargo:=read_cargo(raw_extra[kind],dimensions)
		if cargo.is_empty():return false
		loaded_extra[kind]=cargo.entries
	var loaded_owned: Variant=data.get("furniture_owned",Furniture.LEGACY_IDS.duplicate()) if version>=18 else Furniture.LEGACY_IDS.duplicate()
	if not loaded_owned is Array:return false
	for kind in loaded_owned:
		if not kind is String or (version>=18 and not data.furniture_layout.has(kind)) or not Furniture.ensure_instance(kind):return false
	var loaded_bag := read_cargo(data.get("bag"), LARGE if data.wide else SMALL)
	var loaded_locker := read_cargo(data.get("locker"),Vector2i(loaded_sizes.locker[0],loaded_sizes.locker[1]) if loaded_sizes.has("locker") else LOCKER)
	if loaded_bag.is_empty() or loaded_locker.is_empty():
		return false
	var loaded_preparation := read_cargo(data.get("preparation"),Vector2i(loaded_sizes.preparation[0],loaded_sizes.preparation[1]) if loaded_sizes.has("preparation") else PREPARATION) if version >= 17 else {"entries":[]}
	if loaded_preparation.is_empty():return false
	if version>=19:
		if not data.get("technologies",{}) is Dictionary or not data.get("learned_furniture",[]) is Array:return false
		for key in data.get("technologies",{}):
			if not (key is String or key is StringName) or not valid_index(data.technologies[key],0,100):return false
		for id in data.get("learned_furniture",[]):
			if id not in Furniture.IDS:return false
		if not data.get("temporary_furniture") is Array or not valid_index(data.get("fixtures_seeded_cars"),0,int(data.carriage_count)):return false
		for id in data.temporary_furniture:
			if not id is String or id not in loaded_owned or not data.furniture_layout.has(id) or data.furniture_layout[id]!=null:return false
	var loaded_active := {}
	if version >= 16:
		var raw_active: Variant = data.get("active_item")
		if not raw_active is Dictionary: return false
		if not raw_active.is_empty():
			if not ITEM_DEFINITIONS.has(raw_active.get("kind")) or not raw_active.get("rotated") is bool: return false
			var active_bounds := footprint(raw_active.kind,raw_active.rotated)
			var active_check := read_cargo([raw_active],active_bounds)
			if active_check.is_empty() or active_check.entries.size() != 1: return false
			loaded_active = active_check.entries[0]
	var loaded_layout := Furniture.copy_layout(data.furniture_layout) if version >= 18 else migrate_furniture(data, int(version))
	var extra_cargo: Array=[]
	for cargo in loaded_extra.values():extra_cargo.append_array(cargo)
	var computers:=0
	for id in loaded_layout:
		if Furniture.base_kind(id)=="computer" and loaded_layout[id]!=null:computers+=1
	for entry in loaded_bag.entries + loaded_locker.entries + loaded_preparation.entries + extra_cargo + ([loaded_active] if not loaded_active.is_empty() else []):
		if entry.kind == "computer": computers += 1
	if computers > 1 and version < 19:
		return false
	inventory.assign(loaded_bag.entries)
	locker.assign(loaded_locker.entries)
	preparation.assign(loaded_preparation.entries)
	furniture_storage=loaded_extra;storage_sizes=loaded_sizes;furniture_owned=loaded_owned.duplicate()
	furniture_layout=loaded_layout;carriage_count=int(data.get("carriage_count",1))
	temporary_furniture=data.get("temporary_furniture",[]).duplicate() if version>=19 else []
	fixtures_seeded_cars=int(data.get("fixtures_seeded_cars",0)) if version>=19 else 0
	technologies=data.get("technologies",{}).duplicate();learned_furniture=data.get("learned_furniture",[]).duplicate()
	active_item = loaded_active
	# Reissue runtime IDs across both grids after validating the saved placements.
	next_id = 1
	for entry in inventory+all_base_cargo()+([active_item] if not active_item.is_empty() else []):
		entry.id = next_id
		next_id += 1
	if version < 17: give_preparation_tools()
	carriage_count = int(data.carriage_count) if version >= 4 else 1
	furniture_layout = loaded_layout
	ensure_carriage_fixtures()
	if version<19 or data.get("furniture_content_signature","")!=furniture_signature():
		furniture_layout=Furniture.reconcile_layout(furniture_layout,carriage_count)
	for id in furniture_layout:
		if furniture_layout[id]!=null:
			if id not in furniture_owned:furniture_owned.append(id)
			temporary_furniture.erase(id)
	for id in furniture_owned:
		if furniture_layout.get(id)==null and Furniture.DEFINITIONS[id].item_id.is_empty() and id not in temporary_furniture:temporary_furniture.append(id)
	if version < 6 and furniture_layout.computer == null and material_count("computer") == 0:
		if not add_supply("computer", "locker") and not add_supply("computer", "bag"):
			furniture_layout.computer = Furniture.default_placement("computer")
	base_name = str(data.get("base_name", "未命名基地"))
	station = data.station
	wide_bag = data.wide
	account = balance
	day = int(data.day)
	auto_repair_level = int(data.get("auto_repair_level", 0))
	if version >= 3:
		car_power = float(data.car_power)
		world_seed = int(data.world_seed)
		charger_used = data.charger_used.duplicate()
	else:
		car_power = CAR_START_POWER
		world_seed = hash([station, day, account]) & 0xffffffff
		charger_used.clear()
	end_trip()
	collected.clear()
	market_usage.clear()
	customer_visits = data.customer_visits.duplicate(true) if version >= 12 else {}
	content_flags = data.content_flags.duplicate(true) if version >= 14 else {}
	dialogue_progress = data.dialogue_progress.duplicate(true) if version >= 14 else {}
	npc_affection = data.get("npc_affection",{}).duplicate(true) if version >= 15 else {}
	faction_trust = data.get("faction_trust",{}).duplicate(true) if version >= 15 else {}
	narrative_history = data.get("narrative_history",{}).duplicate(true) if version >= 15 else {}
	daily_customer_ids = data.get("daily_customer_ids",{}).duplicate(true) if version >= 15 else {}
	if version < 15:
		for visits in customer_visits.values():
			if not visits.active.is_empty(): daily_customer_ids[CustomerOrders.Visitors.definition(int(visits.active.visitor)).id] = true
	if version == 12:
		for visits in customer_visits.values(): visits.dismissed = 0
	flashlight_drain = 0.0
	restore_vitals({} if needs_upgrade else data)
	if needs_upgrade:
		give_starter_supplies()
	return true

func valid_index(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is float or value is int) and is_finite(value) and value == floor(value) and value >= minimum and value <= maximum

func read_cargo(raw: Variant, bounds: Vector2i) -> Dictionary:
	if not raw is Array:
		return {}
	var cargo: Array[Dictionary] = []
	for entry in raw:
		if not entry is Dictionary or not ITEM_DEFINITIONS.has(entry.get("kind")) or not entry.get("rotated") is bool:
			return {}
		if not valid_index(entry.get("x"), 0, bounds.x - 1) or not valid_index(entry.get("y"), 0, bounds.y - 1):
			return {}
		if not entry.get("mirrored",false) is bool:return {}
		var cell := Vector2i(int(entry.x), int(entry.y))
		if not fits_item(cargo,bounds,entry.kind,cell,entry.rotated,entry.get("mirrored",false)):
			return {}
		var restored := {"id": 0, "kind": ItemCatalog.runtime_id(entry.kind), "x": cell.x, "y": cell.y, "rotated": entry.rotated,"mirrored":entry.get("mirrored",false)}
		if ItemCatalog.runtime_id(entry.kind) == "aaa":
			if not valid_index(entry.get("charge"), 0, FULL_CHARGE):
				return {}
			restored.charge = int(entry.charge)
		cargo.append(restored)
	return {"entries": cargo}

# Home layout and costs live in the saved game state, not in scene instances.
func travel_cost_per_stop() -> int:
	return TRAVEL_COST_PER_STOP + (carriage_count - 1) * EXTRA_TRAVEL_COST

func daily_power_cost() -> float:
	return COMPUTER_DAILY_COST + (carriage_count - 1) * EXTRA_DAILY_COST

func can_edit_home() -> bool:
	return not trip_active and game_over_reason.is_empty()

func furniture_placement_problem(kind: String, placement: Variant) -> String:
	if not can_edit_home():
		return "当前不能布置家具。"
	if not Furniture.valid_placement(kind, placement, carriage_count):
		return "超出网格边界或位置类型不匹配；屏幕只能放在独立挂点。"
	for other in FURNITURE_IDS:
		if other != kind and furniture_layout[other] != null and Furniture.overlaps(kind, placement, other, furniture_layout[other]):
			return "此处占位格已被%s占用。" % Furniture.DEFINITIONS[other].display_name
	var trial:=furniture_layout.duplicate(true);trial[kind]=Furniture.canonical(placement)
	for other in trial:
		if trial[other]!=null:
			var support:=Furniture.support_problem(other,trial[other],trial)
			if not support.is_empty():return support
	return Furniture.distance_problem(trial)

func place_furniture(kind: String, placement: Variant) -> String:
	var problem := furniture_placement_problem(kind, placement)
	if not problem.is_empty():
		return problem
	var item_id: String=Furniture.DEFINITIONS[kind].item_id
	if not item_id.is_empty() and furniture_layout.get(kind)==null and kind not in temporary_furniture:
		var consumed:=false
		for cargo in all_cargo_arrays():
			for entry in cargo:
				if entry.kind==ItemCatalog.runtime_id(item_id):cargo.erase(entry);consumed=true;break
			if consumed:break
		if not consumed and not active_item.is_empty() and active_item.kind==ItemCatalog.runtime_id(item_id):active_item={};consumed=true
		if not consumed:return "储物格里没有可摆放的"+Furniture.DEFINITIONS[kind].display_name+"。"
	if item_id.is_empty() and kind not in furniture_owned:return "请先花费材料建造此家具。"
	if kind not in furniture_owned:furniture_owned.append(kind)
	temporary_furniture.erase(kind)
	furniture_layout[kind] = Furniture.canonical(placement)
	return ""

func store_furniture(kind: String) -> String:
	if Furniture.DEFINITIONS.has(kind) and not Furniture.DEFINITIONS[kind].item_id.is_empty():return Renovation.pack_item(self,kind)
	return Renovation.temporary_store(self,kind)

func temporarily_store_furniture(kind: String) -> String:
	return Renovation.temporary_store(self,kind)
func decompose_furniture(kind: String) -> String:
	return Renovation.decompose(self,kind)
func build_furniture(kind: String,placement: Dictionary) -> String:
	return Renovation.build(self,kind,placement)

func material_count(kind: String) -> int:
	kind = ItemCatalog.runtime_id(kind)
	var count := 0
	for entry in inventory + all_base_cargo():
		if entry.kind == kind:
			count += 1
	return count

func expansion_problem() -> String:
	if not can_edit_home():
		return "当前不能扩建车厢。"
	if carriage_count >= MAX_CARRIAGES:
		return "已达到 %d 节车厢上限。" % MAX_CARRIAGES
	for kind in EXPANSION_COST:
		if material_count(kind) < EXPANSION_COST[kind]:
			return "扩建材料不足：%s。" % item_name(kind)
	return ""

func expand_carriage() -> String:
	var problem := expansion_problem()
	if not problem.is_empty():
		return problem
	# Check the whole recipe first, then consume each unique entry once.
	for kind in EXPANSION_COST:
		var remaining: int = EXPANSION_COST[kind]
		for cargo in all_cargo_arrays():
			for index in range(cargo.size() - 1, -1, -1):
				if remaining > 0 and cargo[index].kind == kind:
					cargo.remove_at(index)
					remaining -= 1
	carriage_count += 1
	ensure_carriage_fixtures()
	return ""

func valid_home_layout(data: Dictionary, version: int = CABIN_SAVE_VERSION) -> bool:
	if not valid_index(data.get("carriage_count"), 1, MAX_CARRIAGES):
		return false
	var layout: Variant = data.get("furniture_layout")
	var ids: Array = (["bed", "computer"] if version == 4 else Furniture.LEGACY_IDS) if version < 18 else (data.furniture_layout.keys() if data.get("furniture_layout") is Dictionary else [])
	if not layout is Dictionary or (version < 18 and layout.size()!=ids.size()):
		return false
	for required in Furniture.LEGACY_IDS:
		if version>=18 and not layout.has(required):return false
	for key in layout:
		if key not in ids or (version>=18 and not Furniture.ensure_instance(key)):
			return false
	if version <= 5:
		var occupied: Array[int] = []
		for kind in ids:
			var value: Variant = layout.get(kind)
			var per_car := 2 if version == 4 else 10
			if not valid_index(value, -1, int(data.carriage_count) * per_car - 1):
				return false
			if int(value) < 0:
				continue
			var span := 2 if kind == "door" and version == 5 else 1
			var local := int(value) % per_car
			if version == 5 and ((kind == "screen" and local < 6) or (kind != "screen" and local + span > 6)):
				return false
			for cell in range(int(value), int(value) + span):
				if cell in occupied:
					return false
				occupied.append(cell)
		return true
	for kind in ids:
		var p: Variant = layout.get(kind)
		if p == null:
			continue
		if not Furniture.valid_placement(kind, p, int(data.carriage_count), version):
			return false
		for other in ids:
			if (version<18 or version>=19 and data.get("furniture_content_signature","")==furniture_signature()) and other != kind and layout.get(other) != null and Furniture.valid_placement(other, layout[other], int(data.carriage_count), version) and Furniture.overlaps(kind, p, other, layout[other], version):
				return false
	return true

func migrate_furniture(data: Dictionary, version: int) -> Dictionary:
	if version in [11,12,13,14,15,16,17,18]:
		return Furniture.add_missing_layout(data.furniture_layout,int(data.carriage_count))
	if version in [6, 7, 8, 9, 10]:
		var migrated:=Furniture.migrate_grid_layout(data.furniture_layout,version)
		for key in FURNITURE_IDS:
			if key not in Furniture.LEGACY_IDS:migrated.erase(key)
		return Furniture.add_missing_layout(migrated,int(data.carriage_count))
	var layout := Furniture.initial_layout()
	if version <= 3:
		layout.bed = Furniture.default_placement("bed")
		layout.computer = Furniture.default_placement("computer")
		return layout
	var legacy: Dictionary = data.furniture_layout
	var ids: Array = (["bed", "computer"] if version == 4 else Furniture.LEGACY_IDS) if version < 18 else (data.furniture_layout.keys() if data.get("furniture_layout") is Dictionary else [])
	for kind in ids:
		var old := int(legacy[kind])
		if old < 0:
			layout[kind] = null
			continue
		var per_car := 2 if version == 4 else 10
		var car := floori(old / float(per_car))
		layout[kind] = Furniture.default_placement(kind, car)
		if kind == "screen":
			layout[kind].mount = old % 10 - 6
	return layout

func stored_furniture_available(kind: String) -> bool:
	if not Furniture.DEFINITIONS.has(kind) or furniture_layout.get(kind)!=null:return false
	if kind in temporary_furniture:return true
	var item_id: String=Furniture.DEFINITIONS[kind].item_id
	return false if item_id.is_empty() else material_count(item_id)>0 or (not active_item.is_empty() and active_item.kind==ItemCatalog.runtime_id(item_id))

## Equip/swap is atomic; the active container owns its entry outside the backpack grid.
func equip_active(id: int, source: String = "bag") -> String:
	if source not in ["bag","preparation"] or (trip_active and source!="bag"):return "当前无法从该储物空间装备。"
	var incoming:=find_entry(source,id)
	if incoming.is_empty():return "先在储物格中选中道具。"
	var cargo:=entries(source)
	var trial: Array[Dictionary]=cargo.duplicate(true)
	for index in range(trial.size()-1,-1,-1):
		if trial[index].id==id:trial.remove_at(index)
	var future_bag: Array[Dictionary]=trial.duplicate(true) if source=="bag" else inventory.duplicate(true)
	future_bag.append(incoming)
	if source=="bag" and not active_item.is_empty():future_bag.append(active_item)
	var bounds:=grid_size(source) if source!="bag" else LARGE if cargo_has_tool(future_bag,"wide") else SMALL
	for entry in trial:
		if not Rect2i(Vector2i.ZERO,bounds).encloses(item_rect(entry)):return "当前装备无法收回，请先整理储物空间。"
	if source!="bag":
		var bag_bounds:=LARGE if cargo_has_tool(future_bag,"wide") else SMALL
		for entry in inventory:
			if not Rect2i(Vector2i.ZERO,bag_bounds).encloses(item_rect(entry)):return "背包缩小前请先整理超出边界的物品。"
	var placement: Dictionary={}
	if not active_item.is_empty():
		for rotated in [false,true]:
			for y in range(bounds.y):
				for x in range(bounds.x):
					if placement.is_empty() and fits_item(trial,bounds,active_item.kind,Vector2i(x,y),rotated,active_item.get("mirrored",false)):placement={"x":x,"y":y,"rotated":rotated}
		if placement.is_empty():return "原储物空间无法收回当前装备，换装未执行。"
	cargo.erase(incoming)
	if not active_item.is_empty():active_item.merge(placement,true);cargo.append(active_item)
	active_item=incoming;active_item.x=0;active_item.y=0;active_item.rotated=false
	sync_carried_tools()
	return ""

func unequip_active() -> String:
	if active_item.is_empty(): return "主动位为空。"
	var placement := first_free_placement(active_item.kind,"bag",active_item.get("mirrored",false))
	if placement.is_empty(): return "背包没有足够空间。"
	active_item.x = placement.cell.x; active_item.y = placement.cell.y; active_item.rotated = placement.rotated
	inventory.append(active_item)
	active_item = {}
	return ""

func use_active() -> String:
	if active_item.is_empty(): return "主动位为空，可在背包中装备道具。"
	if not game_over_reason.is_empty(): return "当前无法使用主动道具。"
	var capability: String = TOOL_CAPABILITIES.get(active_item.kind,"")
	if capability == "light":return toggle_flashlight()
	if capability == "wrench":
		toggle_wrench();return ""
	if capability in ["crowbar","wide"]:return "该工具在携带时自动生效。"
	var action: String = ItemCatalog.definition(active_item.kind).get("active_use",{}).get("action","none")
	match action:
		"drink":
			if drank_today: return "今天已经喝过水。"
			drank_today = true
		"eat":
			if ate_today: return "今天已经进食。"
			ate_today = true
		"heal":
			if health >= 100: return "当前无需医疗。"
			health = minf(100,health+float(ItemCatalog.definition(active_item.kind).get("active_use",{}).get("amount",25)))
		_: return "这件道具没有主动使用效果。"
	active_item = {}
	return ""

## Quick actions share the same masks, clocks and ownership rules as drag placement.
func auto_place(selection:Dictionary,target:String)->String:
	if selection.is_empty():return "请先选择物品。"
	var entry:=picked(selection.get("source",""),int(selection.get("id",-999)))
	if entry.is_empty():return "物品已失效。"
	var placement:=first_free_placement(entry.kind,target,selection.get("mirrored",entry.get("mirrored",false)))
	if placement.is_empty():return "目标容器没有足够空间。"
	var choice:=selection.duplicate();choice.rotated=placement.rotated
	return "" if place(choice,target,placement.cell) else "当前不能放置到该容器。"

func sort_container(container:String)->String:
	if not valid_container(container) or container in ["battery","active"] or (trip_active and (is_base_container(container) or remaining_ms()==0)):return "当前不能整理该容器。"
	var original:Array[Dictionary]=entries(container)
	var ordered:Array[Dictionary]=original.duplicate(true)
	ordered.sort_custom(func(a,b):return item_cells(a).size()>item_cells(b).size())
	var trial:Array[Dictionary]=[]
	for entry in ordered:
		var placed:=false
		for rotated in [entry.rotated,not entry.rotated]:
			for y in range(grid_size(container).y):
				for x in range(grid_size(container).x):
					if not placed and fits_item(trial,grid_size(container),entry.kind,Vector2i(x,y),rotated,entry.get("mirrored",false)):
						entry.x=x;entry.y=y;entry.rotated=rotated;trial.append(entry);placed=true
			if placed:break
		if not placed:return "暂时无法整理为更紧凑布局，原摆放已保留。"
	original.assign(trial)
	return ""


func give_preparation_tools() -> void:
	for kind in TOOL_CAPABILITIES:
		add_supply(kind,"preparation")

func cargo_has_tool(cargo: Array[Dictionary], capability: String) -> bool:
	for entry in cargo:
		if TOOL_CAPABILITIES.get(entry.kind,"") == capability:return true
	return false

func carried_tools() -> Dictionary:
	var result := {}
	var carried: Array[Dictionary]=inventory.duplicate()
	if not active_item.is_empty():carried.append(active_item)
	for capability in ["light","crowbar","wrench","wide"]:result[capability]=cargo_has_tool(carried,capability)
	return result

func sync_carried_tools() -> void:
	var carried := carried_tools()
	# Legacy large bags may be full before their owner first carries the new physical backpack.
	# Keep their grid accessible until reorganized; depart() still checks the actual carried capacity.
	var can_shrink := true
	for entry in inventory:
		if not Rect2i(Vector2i.ZERO,SMALL).encloses(item_rect(entry)):can_shrink=false
	wide_bag = carried.wide or not can_shrink
	if trip_active and gear.get("inventory_tools",false):
		gear.merge(carried,true)
		gear.wrench = carried.wrench and auto_repair_level > 0
		if not gear.wrench:gear.wrench_equipped=false
		if not carried.light:flashlight_on=false


func storage_container(kind: String) -> String:
	return kind if kind in ["locker","preparation"] else "furniture:"+kind

func storage_containers() -> Array:
	var result: Array=["locker","preparation"]
	for kind in FURNITURE_IDS:
		if kind not in ["locker","preparation"] and Furniture.DEFINITIONS[kind].storage!=Vector2i.ZERO and (furniture_layout.get(kind)!=null or kind in furniture_owned or furniture_storage.has(kind)):result.append(storage_container(kind))
	return result

func all_cargo_arrays() -> Array:
	var result: Array=[inventory]
	for container in storage_containers():result.append(entries(container))
	return result

func all_base_cargo() -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	for container in storage_containers():result.append_array(entries(container))
	return result

func is_base_container(container: String) -> bool:
	return container in storage_containers()

func valid_container(container: String, source: bool=false) -> bool:
	return container in (["bag","battery","active"] if source else ["bag","battery"]) or container in storage_containers() or (source and container=="ground")

func resize_furniture_storage(kind: String, dimensions: Vector2i) -> String:
	if not can_edit_home() or not Furniture.DEFINITIONS.has(kind) or Furniture.DEFINITIONS[kind].storage==Vector2i.ZERO:return "该家具没有可调整的储物空间。"
	if dimensions.x<1 or dimensions.y<1 or dimensions.x>16 or dimensions.y>16:return "储物格尺寸须为1～16。"
	for entry in entries(storage_container(kind)):
		if not Rect2i(Vector2i.ZERO,dimensions).encloses(item_rect(entry)):return "缩小后有物品超出边界，请先移动物品。"
	storage_sizes[kind]=[dimensions.x,dimensions.y]
	return ""

func furniture_completion_problem() -> String:
	if not temporary_furniture.is_empty():
		var names: PackedStringArray=[]
		for id in temporary_furniture:names.append(Furniture.DEFINITIONS[id].display_name)
		return "临时收纳仓库仍有家具："+"、".join(names)+"。请放回或分解；物品类家具可摆放后拖入储物格。"
	for base in ["door","window"]:
		if Renovation.count_placed(self,base)<1:return "全车至少保留一个车门和一个车窗。"
	for id in furniture_layout:
		if furniture_layout[id]==null:continue
		var problem:=furniture_placement_problem(id,furniture_layout[id])
		if not problem.is_empty():return Furniture.DEFINITIONS[id].display_name+"："+problem
	return ""


func available_storage_containers() -> Array:
	var result: Array=[]
	for kind in FURNITURE_IDS:
		if furniture_layout.get(kind)!=null and Furniture.DEFINITIONS[kind].storage!=Vector2i.ZERO:result.append(storage_container(kind))
	return result


func furniture_signature() -> String:
	return FileAccess.get_file_as_string("res://content/furniture.json").sha256_text()

func ensure_carriage_fixtures() -> void:
	for car in range(fixtures_seeded_cars,carriage_count):
		for base in ["door","window"]:
			var present:=false
			for id in furniture_layout:
				if Furniture.base_kind(id)==base and furniture_layout[id]!=null and int(furniture_layout[id].car)==car:present=true;break
			if present:continue
			var id:=Renovation.next_id(self,base)
			furniture_layout[id]=Furniture.default_placement(base,car)
			if id not in furniture_owned:furniture_owned.append(id)
	fixtures_seeded_cars=carriage_count


func technology_level(id: String) -> int:
	return auto_repair_level if id=="auto_repair" else int(technologies.get(id,0))
func build_conditions(id: String) -> Array:
	var definition: Resource=Furniture.DEFINITIONS[id]
	var result: Array=[]
	for tech in definition.required_technology:
		var required:=int(definition.required_technology[tech]);var current:=technology_level(tech)
		result.append({"met":current>=required,"text":"技术 · %s %d/%d级" % [{"auto_repair":"汽修","carpentry":"木工","electronics":"电工"}.get(tech,tech),current,required]})
	if definition.required_technology.is_empty():result.append({"met":true,"text":"技术 · 无需技术"})
	var materials: Dictionary=definition.build_cost.duplicate()
	if not definition.item_id.is_empty():materials[definition.item_id]=int(materials.get(definition.item_id,0))+1
	for kind in materials:
		var amount:=material_count(kind)
		if not active_item.is_empty() and kind==definition.item_id and active_item.kind==ItemCatalog.runtime_id(kind):amount+=1
		result.append({"met":amount>=int(materials[kind]),"text":"材料 · %s %d/%d" % [item_name(kind),amount,int(materials[kind])]})
	if materials.is_empty():result.append({"met":true,"text":"材料 · 无需材料"})
	return result
func build_options() -> Array:
	var result: Array=[]
	for id in Furniture.IDS:
		var definition: Resource=Furniture.DEFINITIONS[id]
		if not definition.enabled or not (definition.known or id in learned_furniture):continue
		var conditions:=build_conditions(id);var ready:=true
		for condition in conditions:
			if not condition.met:ready=false
		result.append({"id":id,"conditions":conditions,"ready":ready})
	result.sort_custom(func(a,b):return a.ready if a.ready!=b.ready else String(a.id).to_lower()<String(b.id).to_lower())
	return result
func build_requirements_problem(id: String) -> String:
	if not Furniture.DEFINITIONS.has(id):return "未知家具。"
	var definition: Resource=Furniture.DEFINITIONS[id]
	if not definition.enabled or not (definition.known or Furniture.base_kind(id) in learned_furniture):return "尚未掌握该家具的建造方式。"
	for condition in build_conditions(id):
		if not condition.met:return "尚未满足："+condition.text
	return ""
