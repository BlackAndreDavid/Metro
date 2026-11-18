extends Control
## A side-view street block. Buildings use the same placements in the foreground and parallax layer.

const Building = preload("res://scripts/content/exploration_building.gd")
const InteriorLight = preload("res://assets/shaders/surface_light.gdshader")
const AutoRepair = preload("res://scripts/auto_repair.gd")

signal pickup_requested(slot: int)
signal extraction_requested(station: String)
signal vehicle_requested(vehicle_id: String)
signal npc_requested(id: String)
signal cabinet_requested(id: String)
signal motion_updated(stamina: float, running: bool, slowed: float)
signal player_attacked(seconds: float)
signal moved

const NORTH := 0
const MIDDLE := 1
const SOUTH := 2
const SIPING := "四平路"
const TONGJI := AutoRepair.STATION
const DEFAULT_SEGMENT := 560.0
const DEFAULT_CELL_NAMES := [
	["校园西街", "教学楼", TONGJI],
	["文具店", SIPING, "办公街"],
	["邮电新村", "学生宿舍", "沿街商铺"],
]
const DEFAULT_WIDTH := DEFAULT_SEGMENT * 3
const DEFAULT_GROUND := 416.0
const DEFAULT_FLOOR_HEIGHT := 110.0
const SPEED := 188.0
const Motion = preload("res://scripts/exploration/player_motion.gd")
const Enemy = preload("res://scripts/exploration/enemy.gd")
const REACH := 43.0
## Each alley joins its row to the next row at the same horizontal position.
const DEFAULT_JUNCTIONS := [
	{"row": NORTH, "x": 478.0}, {"row": NORTH, "x": 1364.0},
	{"row": MIDDLE, "x": 324.0}, {"row": MIDDLE, "x": 908.0},
]
const DEFAULT_STATIONS := [
	{"name": TONGJI, "row": NORTH, "x": 1542.0},
	{"name": SIPING, "row": MIDDLE, "x": 1042.0},
	{"name": "邮电新村", "row": SOUTH, "x": 88.0},
]
const DEFAULT_BUILDINGS := [
	{"id": "lab", "row": NORTH, "name": "实习工坊", "x": 205.0, "width": 190.0, "floors": 1, "wall": Color("5e5a61")},
	{"id": "school", "row": NORTH, "name": "教学楼", "x": 574.0, "width": 266.0, "floors": 2, "wall": Color("736163")},
	{"id": "campus_shop", "row": NORTH, "name": "校门书店", "x": 1150.0, "width": 165.0, "floors": 1, "wall": Color("59576a")},
	{"id": "shop", "row": MIDDLE, "name": "文具店", "x": 88.0, "width": 198.0, "floors": 1, "wall": Color("635957")},
	{"id": "office", "row": MIDDLE, "name": "街道办事处", "x": 585.0, "width": 255.0, "floors": 2, "wall": Color("4d6061")},
	{"id": "tower", "row": MIDDLE, "name": "写字楼", "x": 1416.0, "width": 201.0, "floors": 2, "wall": Color("4b5964")},
	{"id": "service", "row": SOUTH, "name": "社区服务站", "x": 372.0, "width": 152.0, "floors": 1, "wall": Color("625957")},
	{"id": "dorm", "row": SOUTH, "name": "学生宿舍", "x": 600.0, "width": 267.0, "floors": 2, "wall": Color("655664")},
	{"id": "repair", "row": SOUTH, "name": "沿街维修铺", "x": 1224.0, "width": 235.0, "floors": 1, "wall": Color("635552")},
]
const DEFAULT_LOOT := [
	{"x": 217.0, "row": SOUTH, "building": "", "floor": 0},
	{"x": 726.0, "row": SOUTH, "building": "dorm", "floor": 0},
	{"x": 745.0, "row": SOUTH, "building": "dorm", "floor": 1},
	{"x": 752.0, "row": MIDDLE, "building": "office", "floor": 1},
	{"x": 210.0, "row": MIDDLE, "building": "shop", "floor": 0},
	{"x": 719.0, "row": NORTH, "building": "school", "floor": 1},
	{"x": 1495.0, "row": MIDDLE, "building": "tower", "floor": 1},
	{"x": 1361.0, "row": SOUTH, "building": "repair", "floor": 0},
	{"x": 1265.0, "row": NORTH, "building": "campus_shop", "floor": 0},
	{"x": 272.0, "row": SOUTH, "building": "", "floor": 0},
]
const DEFAULT_VEHICLES := [
	{"id": "dorm_sedan", "row": SOUTH, "x": 535.0, "color": Color("846268")},
	{"id": "repair_sedan", "row": SOUTH, "x": 1560.0, "color": Color("677378")},
	{"id": "office_sedan", "row": MIDDLE, "x": 1184.0, "color": Color("79777e")},
	{"id": "campus_sedan", "row": NORTH, "x": 1448.0, "color": Color("7d7562")},
]

const Content = preload("res://scripts/content/content_registry.gd")
var SEGMENT := DEFAULT_SEGMENT
var CELL_NAMES := DEFAULT_CELL_NAMES.duplicate(true)
var WIDTH := DEFAULT_WIDTH
var STREET_STARTS: Array = []
var motion := Motion.new()
var enemies: Array = []
var enemy_textures: Dictionary = {}
var hero_textures: Dictionary = {}
var hero_view: TextureRect
var hero_frame_key := ""
var visual_prompt_key := ""
var animation_time := 0.0
var footstep_time := 0.0
var footstep_audio: AudioStreamPlayer
var GROUND := DEFAULT_GROUND
var FLOOR_HEIGHT := DEFAULT_FLOOR_HEIGHT
var JUNCTIONS := DEFAULT_JUNCTIONS.duplicate(true)
var STATIONS := DEFAULT_STATIONS.duplicate(true)
var BUILDINGS := DEFAULT_BUILDINGS.duplicate(true)
var LOOT := DEFAULT_LOOT.duplicate(true)
var VEHICLES := DEFAULT_VEHICLES.duplicate(true)

var state
var font: Font
var building_instances: Dictionary = {}
var NPCS: Array = []
var npc_textures: Dictionary = {}
var interacting_npc := false
var row := SOUTH
var player_x := 88.0
var building := ""
var floor_index := 0
var facing := 1.0
var pace := 0.0
var visited: Dictionary = {}
var fares: Dictionary = {}
var shade: ColorRect
var lighting: ShaderMaterial
var inspecting_vehicle := false
var inspecting_container := false
var interaction_visuals: Dictionary = {}
var building_textures: Dictionary = {}

static func supports(station: String) -> bool:
	return not Content.entry(station).is_empty()

func setup(owner_state: RefCounted, ui_font: Font) -> void:
	state = owner_state
	apply_level(Content.level(state.station))
	font = ui_font
	var loader = preload("res://scripts/commerce/customer_catalog.gd")
	for direction in ["left","right"]:
		hero_textures[direction] = loader.load_texture("res://assets/textures/temp/characters/suit_walk_"+direction+".png")
	var specs: Array = Content.read_json("res://content/enemies.json").get("enemies",[])
	for placement in Content.level(state.station).get("monsters",[]):
		for definition in specs:
			if definition.id == placement.enemy and definition.get("enabled",true):
				enemies.append(Enemy.new(definition,placement))
				enemy_textures[definition.id] = loader.load_texture(definition.sprite.texture)
	footstep_audio = AudioStreamPlayer.new()
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = 11025
	var samples := PackedByteArray()
	for i in range(660): samples.append(clampi(int(128+sin(i*1.71)*34*(1.0-float(i)/660)),0,255))
	stream.data = samples
	footstep_audio.stream = stream
	add_child(footstep_audio)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = MOUSE_FILTER_IGNORE
	for station in STATIONS:
		fares[station.name] = state.extraction_cost(station.name)
		if station.name == state.station:
			row = station.row
			player_x = station.x
	visited[cell()] = true
	shade = ColorRect.new()
	shade.name = "InteriorLight"
	shade.mouse_filter = MOUSE_FILTER_IGNORE
	lighting = ShaderMaterial.new()
	lighting.shader = InteriorLight
	shade.material = lighting
	shade.hide()
	add_child(shade)
	setup_interaction_visuals()
	hero_view = TextureRect.new()
	hero_view.size = Vector2(32,64)
	hero_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hero_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hero_view)
	update_hero_visual()

func apply_level(data: Dictionary) -> void:
	if data.is_empty(): return
	NPCS = data.get("npcs",[]).duplicate(true)
	var catalog = preload("res://scripts/commerce/customer_catalog.gd")
	catalog.reload()
	for npc in NPCS:
		for entry in catalog.ENTRIES:
			if entry.id == npc.npc:
				npc_textures[npc.npc] = catalog.load_texture(entry.texture)
				npc["name"] = entry.name
	SEGMENT = float(data.get("segment",DEFAULT_SEGMENT))
	GROUND = float(data.get("ground",DEFAULT_GROUND))
	FLOOR_HEIGHT = float(data.get("floor_height",DEFAULT_FLOOR_HEIGHT))
	CELL_NAMES = data.get("cell_names",DEFAULT_CELL_NAMES).duplicate(true)
	STREET_STARTS = data.get("street_starts",[]).duplicate()
	while STREET_STARTS.size() < CELL_NAMES.size(): STREET_STARTS.append(0.0)
	WIDTH = 0.0
	for index in range(CELL_NAMES.size()): WIDTH = maxf(WIDTH,street_end(index))
	STATIONS = data.get("stations",DEFAULT_STATIONS).duplicate(true)
	BUILDINGS = data.get("buildings",DEFAULT_BUILDINGS).duplicate(true)
	JUNCTIONS = data.get("junctions",DEFAULT_JUNCTIONS).duplicate(true)
	LOOT = data.get("loot",DEFAULT_LOOT).duplicate(true)
	VEHICLES = data.get("vehicles",DEFAULT_VEHICLES).duplicate(true)
	building_instances.clear()
	for entry in BUILDINGS:
		building_instances[entry.id] = Building.new(entry)
		if entry.wall is String: entry.wall = Color(entry.wall)
	for entry in VEHICLES:
		if data.get("id","postal") != "postal": entry.id = data.id + "/" + entry.id
		if entry.color is String: entry.color = Color(entry.color)

func cell() -> Vector2i:
	return Vector2i(street_column(player_x), row)

func street_start(street: int = -1) -> float:
	var index := row if street < 0 else street
	return float(STREET_STARTS[index]) if index < STREET_STARTS.size() else 0.0

func street_end(street: int = -1) -> float:
	return street_start(street)+street_width(street)

func street_width(street: int = -1) -> float:
	return SEGMENT * CELL_NAMES[row if street < 0 else street].size()

func street_column(x: float, street: int = -1) -> int:
	return clampi(floori((x-street_start(street)) / SEGMENT), 0, CELL_NAMES[row if street < 0 else street].size() - 1)

func map_connections() -> Array[Array]:
	var connections: Array[Array] = []
	for street in range(CELL_NAMES.size()):
		for column in range(CELL_NAMES[street].size() - 1):
			connections.append([Vector2i(column, street), Vector2i(column + 1, street)])
	for junction in JUNCTIONS:
		if junction.x < maxf(street_start(junction.row),street_start(junction.row+1))+24 or junction.x > minf(street_end(junction.row),street_end(junction.row+1))-24: continue
		var column := street_column(junction.x,junction.row)
		var target_column := street_column(junction.x,junction.row+1)
		var alley := [Vector2i(column, junction.row), Vector2i(target_column, junction.row + 1)]
		if not connections.has(alley):
			connections.append(alley)
	return connections

func junction_destination(junction: Dictionary) -> int:
	if junction.x < maxf(street_start(junction.row),street_start(junction.row+1))+24 or junction.x > minf(street_end(junction.row),street_end(junction.row+1))-24: return -1
	if row == junction.row:
		return row + 1
	if row == junction.row + 1:
		return row - 1
	return -1

func junction_caption(destination: int) -> String:
	return ["去北街", "去中街", "去南街"][destination] if destination < 3 else "去第%d街" % (destination+1)

func _process(delta: float) -> void:
	if state == null or not state.trip_active: return
	animation_time += delta
	var blocked := inspecting_vehicle or interacting_npc or inspecting_container or get_viewport().gui_is_dragging()
	var left := Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)
	var right := Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)
	move_horizontal(0.0 if blocked else float(right)-float(left),delta,not blocked and Input.is_physical_key_pressed(KEY_SHIFT))
	update_enemies(delta)
	motion_updated.emit(motion.stamina,motion.running,motion.slow_remaining)
	update_interaction_visuals()
	queue_redraw()

func move_horizontal(axis: float, delta: float, sprint: bool = false) -> void:
	var velocity := motion.step(delta,axis,sprint)
	if is_zero_approx(axis):
		pace = 0.0
		return
	var location := active_building()
	var minimum := street_start()+24.0
	var maximum := street_end()-24.0
	if not location.is_empty():
		var area: Rect2 = building_instances[location.id].collision_bounds(GROUND,FLOOR_HEIGHT)
		minimum = clampf(area.position.x+12.0,street_start()+24,street_end()-24)
		maximum = clampf(area.end.x-12.0,minimum,street_end()-24)
	var previous := player_x
	player_x = clampf(player_x+velocity*delta,minimum,maximum)
	motion.moving = not is_equal_approx(previous,player_x)
	facing = signf(axis)
	pace += delta*14.0*(1.5 if motion.running else 1.0)
	if motion.moving:
		footstep_time += delta
		if footstep_time >= (0.24 if motion.running else 0.4):
			footstep_time = 0
			if is_instance_valid(footstep_audio):
				footstep_audio.volume_db = -20 if motion.running else -28
				footstep_audio.play()
	position_changed()

func update_enemies(delta: float) -> void:
	var perception := {"row":row,"x":player_x,"indoors":not building.is_empty(),"moving":motion.moving,"noise_radius":motion.noise_radius(),"vertical_offset":-floor_index*FLOOR_HEIGHT}
	for enemy in enemies:
		var hit: Dictionary = enemy.step(delta,perception,Vector2(street_start(enemy.row),street_end(enemy.row)),GROUND)
		if not hit.is_empty():
			state.trip_deadline_ms -= int(hit.time_penalty*1000)
			motion.apply_slow(float(hit.slow_seconds),float(hit.slow_multiplier))
			player_attacked.emit(float(hit.time_penalty))

func position_changed() -> void:
	update_hero_visual()
	visited[cell()] = true
	update_lighting()
	queue_redraw()
	moved.emit()

func active_building() -> Dictionary:
	for entry in BUILDINGS:
		if entry.id == building:
			return entry
	return {}

func can_take(slot: int) -> bool:
	if slot < 0 or slot >= LOOT.size() or (not building.is_empty() and not state.flashlight_on):
		return false
	var point: Dictionary = LOOT[slot]
	return point.row == row and point.building == building and point.floor == floor_index and absf(player_x - point.x) <= REACH

func nearby_vehicle() -> String:
	if building.is_empty():
		for vehicle in VEHICLES:
			if row == vehicle.row and absf(player_x - vehicle.x) <= REACH:
				return vehicle.id
	return ""

func interaction() -> Dictionary:
	if interacting_npc or inspecting_container: return {}
	for npc in NPCS:
		if building.is_empty() and npc.row == row and absf(player_x-npc.x) <= REACH:
			return {"kind":"npc","id":npc.npc,"caption":"交谈 · "+npc.get("name",npc.npc)}
	var location := active_building()
	for point in LOOT:
		if point.has("cabinet") and point.row == row and point.building == building and int(point.floor) == floor_index and absf(player_x-point.x) <= REACH:
			if not building.is_empty() and not state.flashlight_on: continue
			return {"kind":"cabinet","id":point.cabinet,"caption":"打开柜子"}
	for slot in range(LOOT.size()):
		if not can_take(slot):
			continue
		var item: String = state.ground_kind(slot)
		if not item.is_empty():
			return {"kind": "pickup", "slot": slot, "caption": "拾取 %s" % state.item_name(item)}
	if not location.is_empty():
		if location.floors > 1 and absf(player_x - stair_x(location)) <= REACH:
			return {"kind": "stairs", "caption": "上二楼" if floor_index == 0 else "下一楼"}
		if floor_index == 0 and absf(player_x - door_x(location)) <= REACH:
			return {"kind": "leave", "id":building,"caption": "回到街道"}
		return {}
	for station in STATIONS:
		if row == station.row and absf(player_x - station.x) <= REACH:
			var cost: int = fares[station.name]
			var caption: String = "从%s站撤离" % station.name
			if cost > 0:
				caption += " · 耗 %d 度车电" % cost
			return {"kind": "extract", "station": station.name, "caption": caption}
	for junction in JUNCTIONS:
		var destination := junction_destination(junction)
		if destination >= 0 and absf(player_x - junction.x) <= REACH:
			return {"kind": "alley", "row": destination, "x": junction.x, "caption": "穿巷" + junction_caption(destination)}
	for entry in BUILDINGS:
		if row == entry.row and absf(player_x - door_x(entry)) <= REACH:
			return {"kind": "enter", "id": entry.id, "caption": "进入%s" % entry.name}
	var vehicle := nearby_vehicle()
	if not vehicle.is_empty():
		return {"kind": "vehicle", "id": vehicle, "caption": "检查废弃汽车"}
	return {}

func interact() -> void:
	var target := interaction()
	match target.get("kind", ""):
		"cabinet": cabinet_requested.emit(target.id)
		"npc": npc_requested.emit(target.id)
		"pickup": pickup_requested.emit(target.slot)
		"extract": extraction_requested.emit(target.station)
		"vehicle": vehicle_requested.emit(target.id)
		"stairs":
			floor_index = 1 - floor_index
			position_changed()
		"leave":
			building = ""
			position_changed()
		"alley":
			row = target.row
			player_x = target.x
			position_changed()
		"enter":
			building = target.id
			player_x = door_x(active_building())
			position_changed()

func door_x(entry: Dictionary) -> float:
	return (building_instances[entry.id] if building_instances.has(entry.id) else Building.new(entry)).door_x()

func stair_x(entry: Dictionary) -> float:
	return (building_instances[entry.id] if building_instances.has(entry.id) else Building.new(entry)).stair_x()

func camera_offset() -> float:
	return clampf(player_x-size.x*0.5,street_start(),maxf(street_start(),street_end()-size.x))

func update_lighting() -> void:
	var location := active_building()
	shade.visible = not location.is_empty()
	if not shade.visible:
		return
	var height: float = location.floors * FLOOR_HEIGHT
	shade.position = Vector2(location.x - camera_offset(), GROUND - height)
	shade.size = Vector2(location.width, height)
	lighting.set_shader_parameter("interior_size", shade.size)
	lighting.set_shader_parameter("lamp_position", Vector2(player_x - location.x + 10.0 * facing, height - floor_index * FLOOR_HEIGHT - 29.0))
	lighting.set_shader_parameter("facing", facing)
	lighting.set_shader_parameter("lamp_on", state.flashlight_on)

func _draw() -> void:
	if state == null:
		return
	var camera_x := camera_offset()
	draw_rect(Rect2(Vector2.ZERO, size), Color("40394c"))
	draw_rect(Rect2(0, 120, size.x, 176), Color("675161"))
	draw_circle(Vector2(616 - camera_x * 0.09, 113), 29, Color("a97c76"))
	for i in range(28):
		var height := float(44 + (i * 57) % 119)
		draw_rect(Rect2(i * 54 - camera_x * 0.16, 278 - height, 46, height), Color("524555"))
	if row > NORTH:
		draw_set_transform(Vector2(24 - camera_x * 0.53, 24), 0.0, Vector2.ONE * 0.73)
		for entry in BUILDINGS:
			if entry.row == row - 1:
				draw_facade(entry, true)
		for station in STATIONS:
			if station.row == row - 1:
				draw_station(station, true)
		draw_set_transform(Vector2.ZERO)
		draw_rect(Rect2(0, 323, size.x, 28), Color("514452"))
		draw_line(Vector2(0, 323), Vector2(size.x, 323), Color("746172"), 2.0)
	draw_set_transform(Vector2(-camera_x, 0))
	draw_rect(Rect2(street_start(), GROUND, street_width(), size.y - GROUND), Color("292738"))
	draw_rect(Rect2(street_start(), GROUND, street_width(), 13), Color("6d5b69"))
	draw_rect(Rect2(street_start(), GROUND + 13, street_width(), 16), Color("423b51"))
	for x in range(int(street_start()),int(street_end()),96):
		draw_rect(Rect2(x, GROUND + 59, 46, 2), Color("665367"))
	for junction in JUNCTIONS:
		var destination := junction_destination(junction)
		if destination < 0:
			continue
		var x: float = junction.x
		draw_rect(Rect2(x - 24, GROUND - 52, 48, 52), Color("3b3445"))
		draw_rect(Rect2(x - 26, GROUND - 54, 52, 4), Color("847080"))
		sign_at(junction_caption(destination), x, GROUND - 60, 76, Color("483949"))
	for entry in BUILDINGS:
		if entry.row != row:
			continue
		if entry.id == building:
			draw_interior(entry)
		else:
			draw_facade(entry, false)
	for station in STATIONS:
		if station.row == row:
			draw_station(station, false)
	for vehicle in VEHICLES:
		if vehicle.row == row:
			draw_vehicle(vehicle)
	for slot in range(LOOT.size()):
		var point: Dictionary = LOOT[slot]
		var kind: String = state.ground_kind(slot)
		if point.has("cabinet"): continue
		if point.row == row and point.building == building and (building.is_empty() or state.flashlight_on) and not kind.is_empty():
			var tint: Color = state.rarity_color(kind)
			draw_rect(Rect2(point.x - 9, GROUND - point.floor * FLOOR_HEIGHT - 12, 18, 10), tint.darkened(0.44))
			draw_line(Vector2(point.x - 8, GROUND - point.floor * FLOOR_HEIGHT - 12), Vector2(point.x + 8, GROUND - point.floor * FLOOR_HEIGHT - 12), tint, 2.0)
	for npc in NPCS:
		if not interaction_visuals.has("npc/"+npc.npc) and npc.row == row and building.is_empty() and npc_textures.get(npc.npc) != null:
			draw_texture_rect(npc_textures[npc.npc],Rect2(npc.x-24,GROUND-80,48,80),false)
	draw_enemies()
	if motion.moving:
		draw_arc(Vector2(player_x,GROUND-floor_index*FLOOR_HEIGHT-32),motion.noise_radius(),0,TAU,48,Color(0.6,0.85,0.8,0.2),1.0)
	draw_player(Vector2(player_x, GROUND - floor_index * FLOOR_HEIGHT))
	draw_set_transform(Vector2.ZERO)
	draw_rect(Rect2(Vector2.ZERO, size), Color("726176"), false, 2.0)

func draw_vehicle(vehicle: Dictionary) -> void:
	var x: float = vehicle.x
	var y := GROUND
	var paint: Color = vehicle.color
	var tires_removed: bool = state.vehicle_part_taken(vehicle.id, "tire")
	draw_rect(Rect2(x - 64, y - 6, 128, 6), Color("332b3a"))
	for offset in [-37.0, 35.0]:
		draw_circle(Vector2(x + offset, y - 10), 7 if tires_removed else 13, Color("2e2b36"))
		draw_circle(Vector2(x + offset, y - 10), 5, Color("817481"))
	var body := PackedVector2Array([
		Vector2(x - 60, y - 15), Vector2(x - 61, y - 34), Vector2(x - 43, y - 41),
		Vector2(x - 29, y - 59), Vector2(x + 17, y - 59), Vector2(x + 36, y - 40),
		Vector2(x + 57, y - 33), Vector2(x + 59, y - 15),
	])
	draw_colored_polygon(body, paint)
	draw_colored_polygon(PackedVector2Array([
		Vector2(x - 39, y - 40), Vector2(x - 25, y - 55), Vector2(x + 14, y - 55), Vector2(x + 30, y - 40),
	]), Color("373642"))
	draw_rect(Rect2(x - 7, y - 55, 4, 16), paint)
	draw_rect(Rect2(x - 52, y - 22, 105, 3), paint.darkened(0.35))
	draw_rect(Rect2(x + 48, y - 31, 9, 5), Color("d0b592"))
	draw_rect(Rect2(x - 60, y - 33, 8, 5), Color("a96967"))
	if state.vehicle_part_taken(vehicle.id, "steel_plate"):
		draw_rect(Rect2(x - 21, y - 36, 40, 12), Color("413844"))

func draw_facade(entry: Dictionary, distant: bool) -> void:
	if building_textures.has(entry.id):
		draw_texture_rect(building_textures[entry.id],Rect2(entry.x,GROUND-entry.floors*FLOOR_HEIGHT,entry.width,entry.floors*FLOOR_HEIGHT),false)
		return
	var top: float = GROUND - entry.floors * FLOOR_HEIGHT
	var wall: Color = entry.wall.lerp(Color("735f72"), 0.68) if distant else entry.wall
	draw_rect(Rect2(entry.x, top, entry.width, GROUND - top), wall)
	draw_rect(Rect2(entry.x - 4, top, entry.width + 8, 8), wall.lightened(0.24))
	draw_rect(Rect2(entry.x + entry.width - 10, top + 8, 10, GROUND - top - 8), wall.darkened(0.22))
	for level in range(entry.floors):
		var y := GROUND - level * FLOOR_HEIGHT
		draw_rect(Rect2(entry.x, y - 9, entry.width, 9), wall.darkened(0.22))
		for x in range(57, int(entry.width) - 37, 55):
			var window := Rect2(entry.x + x, y - 75, 37, 47)
			draw_rect(window.grow(3), wall.lightened(0.19))
			draw_rect(window, wall.darkened(0.46))
			draw_line(window.position + Vector2(18, 0), window.position + Vector2(18, 47), wall.lightened(0.1), 2.0)
			draw_rect(Rect2(window.position + Vector2(2, 28), Vector2(15, 17)), wall.lightened(0.13))
	draw_door(door_x(entry), GROUND, wall)
	sign_at(entry.name, entry.x + entry.width * 0.55, GROUND - 12, 110, wall.darkened(0.35))

func draw_station(entry: Dictionary, distant: bool) -> void:
	var x: float = entry.x
	var color := Color("65576e") if distant else Color("544460")
	draw_rect(Rect2(x - 46, GROUND - 79, 92, 79), color)
	draw_rect(Rect2(x - 51, GROUND - 84, 102, 9), color.lightened(0.32))
	draw_rect(Rect2(x - 30, GROUND - 46, 60, 46), color.darkened(0.56))
	for i in range(4):
		draw_rect(Rect2(x - 29, GROUND - 6 - i * 9, 58, 2), color.lightened(0.13))
	sign_at(entry.name + "站", x, GROUND - 53, 90, color.darkened(0.24))

func draw_door(x: float, y: float, wall: Color) -> void:
	draw_rect(Rect2(x - 15, y - 57, 30, 57), wall.darkened(0.48))
	draw_rect(Rect2(x - 15, y - 57, 30, 4), wall.lightened(0.31))
	draw_rect(Rect2(x + 7, y - 30, 4, 3), Color("c9a382"))

func draw_interior(entry: Dictionary) -> void:
	var top: float = GROUND - entry.floors * FLOOR_HEIGHT
	draw_rect(Rect2(entry.x, top, entry.width, GROUND - top), Color("534150"))
	for level in range(entry.floors):
		var y := GROUND - level * FLOOR_HEIGHT
		var light := Color("96727b") if level == floor_index else Color("685260")
		draw_rect(Rect2(entry.x + 8, y - 98, entry.width - 16, 97), light)
		draw_rect(Rect2(entry.x + 8, y - 24, entry.width - 16, 23), light.darkened(0.22))
		draw_rect(Rect2(entry.x, y - 3, entry.width, 8), Color("463947"))
		draw_rect(Rect2(entry.x + 63, y - 80, 54, 37), Color("b39b9b").lerp(light, 0.26))
		draw_line(Vector2(entry.x + 90, y - 80), Vector2(entry.x + 90, y - 43), light, 3.0)
		draw_rect(Rect2(entry.x + 71, y - 28, 63, 7), Color("563e4a"))
		draw_rect(Rect2(entry.x + 76, y - 21, 5, 18), Color("563e4a"))
		draw_rect(Rect2(entry.x + 125, y - 21, 5, 18), Color("563e4a"))
		draw_rect(Rect2(entry.x + 155, y - 47, 22, 45), light.darkened(0.44))
		draw_line(Vector2(entry.x + 155, y - 24), Vector2(entry.x + 177, y - 24), light, 2.0)
	draw_rect(Rect2(entry.x - 4, top, entry.width + 8, 8), Color("897383"))
	draw_door(door_x(entry), GROUND, entry.wall)
	if entry.floors > 1:
		var x := stair_x(entry)
		for step in range(10):
			draw_rect(Rect2(x - 46 + step * 5, GROUND - 4 - step * 11, 20, 4), Color("5b4855"))
		draw_line(Vector2(x - 48, GROUND - 22), Vector2(x + 3, GROUND - FLOOR_HEIGHT - 19), Color("bb9290"), 2.0)
		sign_at("楼梯", x, GROUND - 51, 42, Color("594353"))

func sign_at(caption: String, x: float, bottom: float, width: float, fill: Color) -> void:
	draw_rect(Rect2(x - width / 2.0, bottom - 21, width, 21), fill)
	draw_string(font, Vector2(x - width / 2.0, bottom - 5), caption, HORIZONTAL_ALIGNMENT_CENTER, width, 13, Color("efdbcc"))

func draw_player(at: Vector2) -> void:
	if is_instance_valid(hero_view): return
	var texture: Texture2D = hero_textures.get("right" if facing >= 0 else "left")
	if texture == null: return
	var frame := int(animation_time*(12 if motion.running else 8))%4 if motion.moving else 0
	var width := texture.get_width()/4.0
	draw_texture_rect_region(texture,Rect2(at-Vector2(16,64),Vector2(32,64)),Rect2(frame*width,0,width,texture.get_height()))

func draw_enemies() -> void:
	for enemy in enemies:
		if enemy.row != row or not building.is_empty(): continue
		var sprite: Dictionary = enemy.sprite()
		var texture: Texture2D = enemy_textures.get(enemy.definition.id)
		if texture != null:
			var count := maxi(1,int(sprite.get("frames",1)))
			var frame: int = int(enemy.animation_clock*float(sprite.get("fps",8)))%count if enemy.action.ends_with("move") or enemy.action == "pounce" else 0
			var width := float(sprite.get("width",128))
			var height := float(sprite.get("height",32))
			var target := Rect2(enemy.x-width/2,GROUND-height-enemy.attack_jump(),width,height)
			var flip: bool = (enemy.facing > 0) == bool(sprite.get("faces_left",true))
			if flip: target.position.x += target.size.x; target.size.x = -target.size.x
			draw_texture_rect_region(texture,target,Rect2(frame*texture.get_width()/float(count),0,texture.get_width()/float(count),texture.get_height()))
		if enemy.awareness > 0:
			var top := GROUND-float(sprite.get("height",32))-12
			draw_rect(Rect2(enemy.x-30,top,60,5),Color("292738"))
			draw_rect(Rect2(enemy.x-30,top,60*enemy.awareness/100,5),Color("e87b75") if enemy.alerted else Color("efc488"))
			if enemy.alerted: draw_string(font,Vector2(enemy.x-4,top-3),"!",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("ff9690"))

func target_key(target: Dictionary) -> String:
	return target.get("kind","")+"/"+str(target.get("id",target.get("station",target.get("slot",""))))

func has_visual_target(target: Dictionary) -> bool:
	var key := target_key(target)
	return interaction_visuals.has(key) and interaction_visuals[key].control.visible

func add_interaction_visual(target: Dictionary, placement: Dictionary, texture: Texture2D, display_size: Vector2, outline_only: bool = false) -> void:
	if texture == null: return
	var key := target_key(target)
	if interaction_visuals.has(key): return
	var control = preload("res://scenes/items/highlightable_item.tscn").instantiate()
	add_child(control)
	control.size = display_size
	control.set_item(texture,"[ E ] "+target.caption)
	control.caption.position.y = -48
	control.visual.material.set_shader_parameter("outline_only",outline_only)
	control.activated.connect(activate_visual.bind(target))
	interaction_visuals[key] = {"control":control,"placement":placement,"size":display_size,"target":target}

func activate_visual(target: Dictionary) -> void:
	if target_key(interaction()) == target_key(target): interact()

func setup_interaction_visuals() -> void:
	var loader = preload("res://scripts/commerce/customer_catalog.gd")
	var cabinet_texture: Texture2D = loader.load_texture("res://assets/textures/Locker.png")
	for point in LOOT:
		if point.has("cabinet"):
			add_interaction_visual({"kind":"cabinet","id":point.cabinet,"caption":"打开柜子"},point,cabinet_texture,Vector2(28,48))
	for npc in NPCS:
		add_interaction_visual({"kind":"npc","id":npc.npc,"caption":"交谈 · "+npc.get("name",npc.npc)}, {"x":npc.x,"row":npc.row,"building":"","floor":0},npc_textures.get(npc.npc),Vector2(48,80))
	var door_texture: Texture2D = loader.load_texture("res://assets/textures/Door.png")
	for entry in BUILDINGS:
		if not entry.get("texture","").is_empty(): building_textures[entry.id] = loader.load_texture(entry.texture)
		add_interaction_visual({"kind":"enter","id":entry.id,"caption":"进入"+entry.name},{"x":door_x(entry),"row":entry.row,"building":"","floor":0},door_texture,Vector2(24,54))
		add_interaction_visual({"kind":"leave","id":entry.id,"caption":"回到街道"},{"x":door_x(entry),"row":entry.row,"building":entry.id,"floor":0},door_texture,Vector2(24,54))
	var mask := Image.create(128,64,false,Image.FORMAT_RGBA8);mask.fill(Color.TRANSPARENT)
	mask.fill_rect(Rect2i(3,25,122,31),Color.WHITE);mask.fill_rect(Rect2i(32,3,51,38),Color.WHITE)
	for center in [Vector2i(27,53),Vector2i(99,53)]:
		for y in range(64):
			for x in range(128):
				if Vector2(center).distance_to(Vector2(x,y)) <= 10:mask.set_pixel(x,y,Color.WHITE)
	for vehicle in VEHICLES:
		add_interaction_visual({"kind":"vehicle","id":vehicle.id,"caption":"检查废弃汽车"},{"x":vehicle.x,"row":vehicle.row,"building":"","floor":0},ImageTexture.create_from_image(mask),Vector2(128,64),true)
	var station_mask := Image.create(64,76,false,Image.FORMAT_RGBA8);station_mask.fill(Color.TRANSPARENT);station_mask.fill_rect(Rect2i(4,3,56,73),Color.WHITE)
	for station in STATIONS:
		add_interaction_visual({"kind":"extract","station":station.name,"caption":"从"+station.name+"站撤离"},{"x":station.x,"row":station.row,"building":"","floor":0},ImageTexture.create_from_image(station_mask),Vector2(64,76),true)
	update_interaction_visuals()

func update_interaction_visuals() -> void:
	var active_key := target_key(interaction())
	for key in interaction_visuals:
		var entry: Dictionary = interaction_visuals[key]
		var control: Control = entry.control
		var point: Dictionary = entry.placement
		control.visible = int(point.row) == row and point.get("building","") == building and int(point.get("floor",0)) == floor_index
		if not building.is_empty() and not state.flashlight_on: control.visible = false
		if not control.visible: continue
		control.position = Vector2(float(point.x)-camera_offset()-entry.size.x/2,GROUND-floor_index*FLOOR_HEIGHT-entry.size.y)
		var local := control.get_local_mouse_position()
		var hover: bool = control.get_rect().has_point(control.position+local) and control._has_point(local)
		control.set_highlighted(key == active_key or hover)
	update_hero_visual()
	var current_prompt := active_key if has_visual_target(interaction()) else ""
	if current_prompt != visual_prompt_key:
		visual_prompt_key = current_prompt
		moved.emit()

func update_hero_visual() -> void:
	if not is_instance_valid(hero_view): return
	var direction := "right" if facing >= 0 else "left"
	var texture: Texture2D = hero_textures.get(direction)
	if texture == null: return
	var frame := int(animation_time*(12 if motion.running else 8))%4 if motion.moving else 0
	var key := direction+str(frame)
	if key != hero_frame_key:
		hero_frame_key = key
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2(frame*texture.get_width()/4.0,0,texture.get_width()/4.0,texture.get_height())
		hero_view.texture = atlas
	hero_view.position = Vector2(player_x-camera_offset()-16,GROUND-floor_index*FLOOR_HEIGHT-64)
