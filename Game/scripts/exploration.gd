extends Control
## Instanced by Home with its existing state. Edit the .tscn for page layout.
var controller: Control

func configure(home: Control) -> void:
	controller = home
	home.surface_location = $Location
	home.time_label = $Timer
	home.surface_prompt = $InteractionPrompt
	home.status = $Status
	home.surface_block = $StreetFrame/SurfaceBlock
	$Departure.text = "%s站出发    /    车电 %s" % [home.state.station, home.car_power_text()]
	$StreetFrame/SurfaceBlock.setup(home.state, home.font)
	$StreetFrame/SurfaceBlock.pickup_requested.connect(home.pick_up_surface_item)
	$StreetFrame/SurfaceBlock.extraction_requested.connect(home.extract_from_block)
	$StreetFrame/SurfaceBlock.vehicle_requested.connect(home.show_vehicle)
	$StreetFrame/SurfaceBlock.npc_requested.connect(show_npc)
	$StreetFrame/SurfaceBlock.moved.connect(home.update_surface_position)
	$Minimap.setup($StreetFrame/SurfaceBlock, home.font)
	for label in [$Departure, $Location, $Timer, $InteractionPrompt, $Status]:
		label.add_theme_color_override("font_color", home.TEXT)
	$Departure.add_theme_color_override("font_color", home.MINT)
	$InteractionPrompt.add_theme_color_override("font_color", home.AMBER)
	$Status.add_theme_color_override("font_color", home.AMBER)

func show_npc(id: String) -> void:
	if $StreetFrame/SurfaceBlock.interacting_npc: return
	var panel := preload("res://scripts/content/npc_interaction.gd").new()
	add_child(panel)
	panel.setup(controller.state,$StreetFrame/SurfaceBlock,id)
