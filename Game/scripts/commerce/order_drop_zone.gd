extends Panel
var controller: Control
func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return is_instance_valid(controller) and data is Dictionary and data.get("source") in ["bag","stock"]
func _drop_data(_at: Vector2, data: Variant) -> void:
	controller.queue_item(data)
