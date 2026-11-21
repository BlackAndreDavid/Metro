extends RefCounted
## Logic regressions use a wall-only window fixture. The renovation workflow tests
## the current authored dual-plane window and migration without changing this profile.
static func canonical_profile() -> void:
	var catalog=load("res://scripts/items/furniture_catalog.gd")
	var window: Resource=catalog.DEFINITIONS.window
	for row in window.occupancy_grid:
		for x in range(row.size()):
			if row[x]==1:row[x]=0
	catalog.SOURCES.window.occupancy_grid=window.occupancy_grid.duplicate(true)
	# Preserve geometry assumed by legacy rule tests; the workflow suite uses authored content.
	var prep: Resource=catalog.DEFINITIONS.preparation
	prep.grid_size=Vector2i(5,4);prep.occupancy_grid.clear()
	for y in range(4):prep.occupancy_grid.append([1,1,1,1,1])
	catalog.SOURCES.preparation.width=5;catalog.SOURCES.preparation.height=4
	catalog.SOURCES.preparation.occupancy_grid=prep.occupancy_grid.duplicate(true)
	prep.distance_rules[0].distance=3
	catalog.SOURCES.preparation.distance_rules=prep.distance_rules.duplicate(true)
