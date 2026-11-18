extends Control
const Catalog = preload("res://scripts/items/furniture_catalog.gd")
var cars := 1
var hanging := false

func _draw() -> void:
	var color := Color(0.65, 0.78, 0.85, 0.25) if not hanging else Color(0.6, 0.85, 1.0, 0.65)
	for car in range(cars):
		var planes: Array[Rect2] = []
		if hanging:
			for mount in range(Catalog.HANGING_ORIGINS.size()):
				planes.append(Catalog.mount_rect(car, mount))
		else:
			planes.append(Catalog.floor_rect(car))
		var dimensions := Catalog.MOUNT_SIZE if hanging else Catalog.GRID_SIZE
		for plane in planes:
			draw_rect(plane, Color(color, 0.04), true)
			for x in range(dimensions.x + 1):
				var at := plane.position + Vector2(x * Catalog.CELL_SIZE.x, 0)
				draw_line(at, at + Vector2(0, plane.size.y), color, 1)
			for y in range(dimensions.y + 1):
				var at := plane.position + Vector2(0, y * Catalog.CELL_SIZE.y)
				draw_line(at, at + Vector2(plane.size.x, 0), color, 1)
