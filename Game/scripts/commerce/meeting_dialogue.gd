extends RefCounted
## A complete encounter: multiple NPC turns, branching player replies and a shared ending.
var definition: Dictionary

func _init(story: Dictionary = {}) -> void:
	definition = story

func turn(id: String) -> Dictionary:
	var nodes: Dictionary = definition.get("nodes",{})
	return nodes.get(id,nodes.get(definition.get("start",""),{}))

func replies(id: String) -> Array:
	return turn(id).get("choices",[])
