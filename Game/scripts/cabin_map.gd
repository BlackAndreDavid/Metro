extends Control
## Line geometry follows the central area of the Shentong Metro D202501 diagram.

const Network = preload("res://scripts/content/network_catalog.gd")
static var _network: Dictionary = Network.read_network()
static var STATIONS: Dictionary = _network.get("stations",{})
static var LINES: Array = _network.get("lines",[])
static func reload_network() -> bool:
	var updated := Network.read_network()
	if updated.is_empty(): return false
	_network = updated
	STATIONS = updated.stations
	LINES = updated.lines
	return true

const OTHER_TRANSFERS := {
	"世纪大道": [2, 6, 9], "浦东大道": [14], "南京东路": [2], "豫园": [14],
	"人民广场": [1, 2], "虹口足球场": [3], "宝山路": [3], "昌邑路": [14], "民生路": [6],
	"上海火车站": [1, 3], "中潭路": [3], "镇坪路": [3, 7], "曹杨路": [3, 11, 14],
	"金沙江路": [3, 13], "中山公园": [2, 3], "延安西路": [3], "宜山路": [3, 9],
	"上海体育馆": [1], "东安路": [7], "蓝村路": [6], "汉中路": [1, 13], "陆家浜路": [9], "耀华路": [7],
	"交通大学": [11], "陕西南路": [1], "一大会址·新天地": [13], "南京西路": [2, 13],
	"嘉善路": [9], "龙华中路": [7], "龙华": [11], "龙漕路": [3], "杨高中路": [9], "龙阳路": [2, 7, 16],
}

const ORIGIN := Vector2(12, 9)
const INK := Color("292a36")
const PAPER := Color("faf9f3")

var current: String
var selected: String
var font: Font
var planned: Array = []
var captions: Dictionary = {}
var map_textures: Dictionary = {}

func setup(ui_font: Font, location: String, destination: String, on_select: Callable) -> void:
	reload_network()
	font = ui_font
	for image in _network.get("textures",[]):
		map_textures[image.id] = preload("res://scripts/commerce/customer_catalog.gd").load_texture(image.texture)
	current = location
	selected = destination
	planned = route(location, destination)
	mouse_filter = MOUSE_FILTER_IGNORE
	clip_contents = true
	layout_captions()
	for station in STATIONS:
		var center := project(STATIONS[station][0])
		var caption: Vector2 = captions[station]
		var label_size := font.get_string_size(station, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
		var hit := Button.new()
		hit.flat = true
		hit.focus_mode = Control.FOCUS_NONE
		hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		hit.position = center - Vector2(9, 9)
		hit.size = Vector2(18, 18)
		hit.tooltip_text = station
		hit.pressed.connect(on_select.bind(station))
		add_child(hit)
		var text_hit := Button.new()
		text_hit.flat = true
		text_hit.focus_mode = Control.FOCUS_NONE
		text_hit.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		text_hit.position = caption
		text_hit.size = Vector2(label_size.x, 15)
		text_hit.tooltip_text = station
		text_hit.pressed.connect(on_select.bind(station))
		add_child(text_hit)

static func station_lines(station: String) -> Array:
	var result: Array = OTHER_TRANSFERS.get(station, []).duplicate()
	for line in LINES:
		if station in line[2]:
			result.append(line[0])
	result.sort()
	return result

static func station_info(station: String) -> Dictionary:
	var index := STATIONS.keys().find(station)
	var ruins := [
		"沿街商铺遗址\n地下停车库",
		"社区诊所旧址\n废弃居民楼",
		"废弃学校\n旧货仓库",
		"通信机房旧址\n废弃公交车场",
	]
	var level := [1, 2, 1, 2, 2, 3, 3][index % 7] as int
	return {"outside": ruins[index % ruins.size()], "radiation": level}

static func route(from: String, to: String) -> Array:
	if not STATIONS.has(to):
		return []
	return routes_from(from, to).get(to, [])

static func routes_from(from: String, until: String = "") -> Dictionary:
	if not STATIONS.has(from):
		return {}
	var paths := {from: [from]}
	var frontier: Array = [from]
	while not frontier.is_empty():
		var here: String = frontier.pop_front()
		if here == until:
			break
		for line in LINES:
			var stops: Array = line[2].filter(func(point: Variant) -> bool: return point is String)
			if stops.size() < 2: continue
			var loop: bool = stops.front() == stops.back()
			if loop:
				stops.pop_back()
			var index := stops.find(here)
			if index == -1:
				continue
			for adjacent in [index - 1, index + 1]:
				if loop:
					adjacent = posmod(adjacent, stops.size())
				if adjacent < 0 or adjacent >= stops.size():
					continue
				var next: String = stops[adjacent]
				if not paths.has(next):
					paths[next] = paths[here] + [next]
					frontier.append(next)
	return paths

func layout_captions() -> void:
	var used: Array[Rect2] = []
	for station in STATIONS:
		var center := project(STATIONS[station][0])
		used.append(Rect2(center - Vector2(8, 7), Vector2(16, 14)))
	for station in STATIONS:
		var center := project(STATIONS[station][0])
		var preferred: Vector2 = STATIONS[station][1]
		var width := font.get_string_size(station, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var offsets: Array[Vector2] = [
			preferred, Vector2(10, -8), Vector2(-width - 10, -8),
			Vector2(-width / 2, -25), Vector2(-width / 2, 9),
			Vector2(8, -23), Vector2(8, 9), Vector2(-width - 8, -23), Vector2(-width - 8, 9),
			Vector2(-width / 2, -43), Vector2(-width / 2, 26),
			Vector2(13, -42), Vector2(-width - 13, -42),
			Vector2(13, 28), Vector2(-width - 13, 28),
			Vector2(53, -8), Vector2(-width - 53, -8),
		]
		for radius in [34, 44, 54, 64, 78]:
			for step in range(16):
				var around := Vector2.from_angle(step * TAU / 16.0) * float(radius)
				offsets.append(around - Vector2(width / 2.0, 8))
		for offset in offsets:
			var box := Rect2(center + offset, Vector2(width, 16))
			if box.position.x < 1 or box.position.y < 1 or box.end.x > 848 or box.end.y > 503:
				continue
			if used.any(func(other: Rect2) -> bool: return other.intersects(box.grow(2))):
				continue
			captions[station] = box.position
			used.append(box)
			break
		if not captions.has(station):
			captions[station] = center + preferred

func project(point: Vector2) -> Vector2:
	return point * map_scale() + ORIGIN

func plot(points: Array, color: Color, width: float) -> void:
	var vertices := PackedVector2Array()
	for point in points:
		vertices.append(project(STATIONS[point][0] if point is String else point))
	if vertices.size() >= 2: draw_polyline(vertices, color, width, true)

func _draw() -> void:
	if font == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), PAPER)
	draw_map_textures()
	for line in LINES:
		plot(line[2], Color(line[1]), 4.0)
	if planned.size() > 1:
		for line in LINES:
			var last := ""
			var segment: Array = []
			for point in line[2]:
				segment.append(point)
				if point is String:
					var index := planned.find(last)
					if index != -1 and absi(planned.find(point) - index) == 1 and point in planned:
						plot(segment, PAPER, 11.0)
						plot(segment, Color(line[1]), 7.0)
					segment = [point]
					last = point
	for station in STATIONS:
		var center := project(STATIONS[station][0])
		var caption: Vector2 = captions[station]
		var in_route: bool = station in planned
		var interchange := station_lines(station).size() > 1
		if station == current:
			draw_circle(center, 11, Color("f3d09b"))
		if station == selected and station != current:
			draw_circle(center, 11, Color("c9b6e7"))
		if interchange:
			draw_capsule(center, INK, 4.5)
			draw_capsule(center, PAPER, 3.0)
		else:
			draw_stop(station, center, caption)
		var label_width := font.get_string_size(station, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var label_rect := Rect2(caption, Vector2(label_width, 16))
		var edge := center.clamp(label_rect.position, label_rect.end)
		if center.distance_to(edge) > 24.0:
			draw_line(center.move_toward(edge, 6.0), edge, Color("837a86"), 1.0, true)
		draw_rect(label_rect.grow_individual(2, 0, 2, 0), Color(PAPER, 0.94))
		draw_string(font, caption + Vector2(0, 13), station, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, INK if in_route else Color("464350"))

func draw_capsule(center: Vector2, tint: Color, radius: float) -> void:
	var offset := Vector2(4, 0)
	draw_line(center - offset, center + offset, tint, radius * 2, true)
	draw_circle(center - offset, radius, tint, true, -1.0, true)
	draw_circle(center + offset, radius, tint, true, -1.0, true)

func draw_stop(station: String, center: Vector2, caption: Vector2) -> void:
	for line in LINES:
		var points: Array = line[2]
		var index := points.find(station)
		if index == -1:
			continue
		var adjacent: Variant = points[index - 1] if index > 0 else points[index + 1]
		var neighbor: Vector2 = STATIONS[adjacent][0] if adjacent is String else adjacent
		var outward := (center - project(neighbor)).orthogonal().normalized()
		var toward := caption + Vector2(12, 8) - center
		if outward.dot(toward) < 0:
			outward *= -1
		draw_line(center, center + outward * 6, Color(line[1]), 4.0, true)
		return

func map_scale() -> Vector2:
	var canvas: Dictionary = _network.get("canvas",{"width":1500,"height":1150})
	return Vector2(maxf(size.x-24,1)/float(canvas.width),maxf(size.y-18,1)/float(canvas.height))

func draw_map_textures() -> void:
	for image in _network.get("textures",[]):
		var texture: Texture2D = map_textures.get(image.id)
		if texture == null or not image.get("visible",true): continue
		var angle := deg_to_rad(float(image.get("rotation",0)))
		var scale := map_scale()
		var origin := project(Vector2(image.position[0],image.position[1]))
		draw_set_transform_matrix(Transform2D(Vector2(cos(angle),sin(angle))*scale,Vector2(-sin(angle),cos(angle))*scale,origin))
		draw_texture_rect(texture,Rect2(Vector2.ZERO,Vector2(image.size[0],image.size[1])),false,Color(1,1,1,float(image.get("opacity",1))))
		draw_set_transform_matrix(Transform2D.IDENTITY)
