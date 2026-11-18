class_name MetroExplorationBuilding
extends RefCounted
## Building instance geometry. Editor templates serialize into this shared dictionary format.
var data: Dictionary

func _init(definition: Dictionary = {}) -> void:
	data = definition.duplicate(true)

func door_x() -> float:
	return float(data.get("x",0))+27.0

func stair_x() -> float:
	return float(data.get("x",0))+float(data.get("width",160))-34.0

func bounds(ground: float, floor_height: float) -> Rect2:
	var height := float(data.get("floors",1))*floor_height
	return Rect2(float(data.get("x",0)),ground-height,float(data.get("width",160)),height)
