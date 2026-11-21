extends RefCounted
## Logic regressions use a wall-only window fixture. The renovation workflow tests
## the current authored dual-plane window and migration without changing this profile.
static func canonical_profile() -> void:
	var catalog=load("res://scripts/items/furniture_catalog.gd")
	catalog.DEFINITIONS.window.floor_cells=[] as Array[Vector2i]
	catalog.SOURCES.window.floor_cells=[]
