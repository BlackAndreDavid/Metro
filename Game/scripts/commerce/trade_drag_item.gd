extends PanelContainer
var payload: Dictionary
var caption := ""
func _get_drag_data(_at: Vector2) -> Variant:
	var preview := Label.new()
	preview.text = caption
	set_drag_preview(preview)
	return payload.duplicate()
