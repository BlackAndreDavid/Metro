extends Control
const Catalog = preload("res://scripts/items/furniture_catalog.gd")
var kind := ""
var bounds := Rect2()
var texture: Texture2D
var valid := false

func _draw() -> void:
	if texture == null:
		return
	var color := Color(0.4, 1, 0.65, 0.8) if valid else Color(1, 0.3, 0.3, 0.8)
	draw_rect(bounds, Color(color, 0.2), true)
	draw_rect(bounds, color, false, 2)
	draw_texture_rect(texture, Catalog.visual_rect(kind,bounds), false, Color(1, 1, 1, 0.65))
