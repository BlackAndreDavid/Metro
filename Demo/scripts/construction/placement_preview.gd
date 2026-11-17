extends Control
var bounds := Rect2()
var texture: Texture2D
var valid := false

func _draw() -> void:
	if texture == null:
		return
	var color := Color(0.4, 1, 0.65, 0.8) if valid else Color(1, 0.3, 0.3, 0.8)
	draw_rect(bounds, Color(color, 0.2), true)
	draw_rect(bounds, color, false, 2)
	var scale_factor := minf(bounds.size.x / texture.get_width(), bounds.size.y / texture.get_height())
	var size := Vector2(texture.get_size()) * scale_factor
	draw_texture_rect(texture, Rect2(bounds.position + Vector2((bounds.size.x - size.x) / 2, bounds.size.y - size.y), size), false, Color(1, 1, 1, 0.65))
