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
	var height := height_for(data,floor_height)
	return Rect2(float(data.get("x",0)),ground-height,float(data.get("width",160)),height)

func collision_bounds(ground: float, floor_height: float) -> Rect2:
	var box: Dictionary = data.get("collision",{})
	var height := float(box.get("height",height_for(data,floor_height)))
	return Rect2(float(data.get("x",0))+float(box.get("x",0)),ground-height-float(box.get("y",0)),float(box.get("width",data.get("width",160))),height)

static func elevation(definition: Dictionary, index: int, fallback: float=110.0) -> float:
	var floors: Array = definition.get("floor_positions",[])
	return float(floors[index]) if index>=0 and index<floors.size() else index*fallback

static func height_for(definition: Dictionary, fallback: float=110.0) -> float:
	return elevation(definition,int(definition.get("floors",1))-1,fallback)+fallback
