extends Control
const Catalog = preload("res://scripts/items/furniture_catalog.gd")
var kind := ""
var bounds := Rect2()
var texture: Texture2D
var valid := false

func _draw() -> void:
	if texture == null:
		return
	var color := Color(0.4, 1, 0.65, 0.8) if valid else Color(1, 0.3, 0.3, 0.8)
	var definition: Resource=Catalog.DEFINITIONS[kind]
	for plane in ["wall_cells","floor_cells"]:
		for cell in definition.get(plane):
			var rect:=Rect2(bounds.position+Vector2(cell)*Catalog.CELL_SIZE,Catalog.CELL_SIZE)
			draw_rect(rect,Color(Color("76a5dc") if plane=="wall_cells" else color,0.25),true)
	draw_rect(bounds, color, false, 2)
	var image_bounds:=Catalog.visual_rect(kind,bounds)
	draw_set_transform(image_bounds.get_center(),deg_to_rad(float(definition.texture_binding.get("rotation",0))))
	draw_texture_rect(texture,Rect2(-image_bounds.size/2,image_bounds.size),false,Color(1,1,1,0.65))
	draw_set_transform(Vector2.ZERO)
