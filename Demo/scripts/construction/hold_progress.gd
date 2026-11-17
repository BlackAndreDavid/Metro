extends Control
var progress := 0.0

func _draw() -> void:
	draw_circle(Vector2.ZERO, 12, Color(0.04, 0.05, 0.08, 0.9))
	draw_arc(Vector2.ZERO, 9, -PI / 2, PI * 1.5, 48, Color(0.4, 0.4, 0.5), 2, true)
	if progress > 0:
		draw_arc(Vector2.ZERO, 9, -PI / 2, -PI / 2 + TAU * progress, 48, Color.WHITE, 2, true)
