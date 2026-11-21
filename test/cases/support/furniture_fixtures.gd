extends RefCounted
## Logic regressions use a wall-only window fixture. The renovation workflow tests
## the current authored dual-plane window and migration without changing this profile.
static func canonical_profile() -> void:
	var catalog=load("res://scripts/items/furniture_catalog.gd")
	catalog.DEFINITIONS.window.floor_cells=[] as Array[Vector2i]
	catalog.SOURCES.window.floor_cells=[]
	# Preserve geometry assumed by legacy rule tests; the workflow suite uses authored content.
	var prep: Resource=catalog.DEFINITIONS.preparation
	prep.grid_size=Vector2i(5,4);prep.floor_cells.clear()
	for y in range(4):
		for x in range(5):prep.floor_cells.append(Vector2i(x,y))
	catalog.SOURCES.preparation.width=5;catalog.SOURCES.preparation.height=4
	catalog.SOURCES.preparation.floor_cells=[]
	for cell in prep.floor_cells:catalog.SOURCES.preparation.floor_cells.append([cell.x,cell.y])
