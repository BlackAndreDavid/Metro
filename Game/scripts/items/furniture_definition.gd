extends Resource
@export var id := ""
@export var display_name := ""
@export var function_text := ""
@export_enum("rest", "news", "gear", "locker", "map", "preparation", "trade", "storage", "none") var action := "rest"
@export_file("*.png") var texture_path := ""
# Keep save/placement validation independent of texture import order.
var texture: Texture2D:
	get:
		return frame_at(0.0)
@export var grid_size := Vector2i(2, 2)
@export_enum("floor", "hanging") var placement_type := "floor"
# Offset of the cropped image in the original 243x108 carriage canvas.
@export var source_origin := Vector2.ZERO

func perform(home: Control) -> void:
	if action == "none":
		return
	if id.contains("#") and action in ["locker","preparation","storage"]:
		home.show_furniture_storage(id)
	elif action == "storage":
		home.show_furniture_storage(id)
	elif action == "map":
		home.show_map()
	else:
		home.use_hotspot(action)

var floor_cells: Array[Vector2i] = []
var wall_cells: Array[Vector2i] = []
var reference_cells: Array[Vector2i] = []
var storage := Vector2i.ZERO
var item_id := ""
var effects: Array = []
var build_cost: Dictionary = {}
var required_technology: Dictionary = {}
var known := true
var dismantle_cost: Dictionary = {}
var salvage: Dictionary = {}
var distance_rules: Array = []
var support_surface := false
var animation := {"frames":1,"columns":1,"fps":6.0}
var texture_binding: Dictionary = {}
var default_placement: Variant = null
var default_owned := true
var enabled := true
var initial_placed := true
var _frames: Array[Texture2D] = []

func frame_at(seconds: float) -> Texture2D:
	if _frames.is_empty():
		var sheet := load(texture_path) as Texture2D
		var image := sheet.get_image()
		if image.is_compressed():image.decompress()
		var columns := int(animation.get("columns",1))
		var count := int(animation.get("frames",1))
		var rows := ceili(float(count)/columns)
		var frame_size := Vector2i(image.get_width()/columns,image.get_height()/rows)
		for index in range(count):
			var part := image.get_region(Rect2i(Vector2i(index%columns,index/columns)*frame_size,frame_size))
			if id.get_slice("#",0)=="preparation":part=part.get_region(part.get_used_rect())
			_frames.append(ImageTexture.create_from_image(part))
	return _frames[frame_index(seconds)]

func frame_index(seconds: float) -> int:
	var durations: Array=animation.get("durations",[])
	if not durations.is_empty():
		var total:=0.0
		for value in durations:total+=float(value)
		var at:=fmod(seconds*1000,total)
		for index in range(durations.size()):
			at-=float(durations[index])
			if at<0:return index
	return int(seconds*float(animation.get("fps",6)))%int(animation.get("frames",1))

static func from_data(data: Dictionary) -> Resource:
	var result=load("res://scripts/items/furniture_definition.gd").new()
	result.id=data.id;result.display_name=data.name;result.function_text=data.get("function_text",data.name)
	result.action=data.get("interaction","none");result.texture_path=data.texture
	result.grid_size=Vector2i(int(data.width),int(data.height))
	result.placement_type=data.get("placement_type","floor")
	for cell in data.get("floor_cells",[]):result.floor_cells.append(Vector2i(cell[0],cell[1]))
	for cell in data.get("wall_cells",[]):
		var at:=Vector2i(cell[0],cell[1])
		if at not in result.floor_cells:result.wall_cells.append(at)
	if result.placement_type=="hanging":result.floor_cells.clear();result.wall_cells.clear()
	for cell in data.get("reference_cells",[]):result.reference_cells.append(Vector2i(cell[0],cell[1]))
	var container: Variant=data.get("storage")
	if container is Dictionary:result.storage=Vector2i(int(container.width),int(container.height))
	result.item_id=data.get("item_id","");result.effects=data.get("effects",[]).duplicate()
	result.required_technology=data.get("required_technology",{}).duplicate();result.known=data.get("known",true)
	result.build_cost=data.get("build_cost",{}).duplicate();result.dismantle_cost=data.get("dismantle_cost",{}).duplicate();result.salvage=data.get("salvage",{}).duplicate()
	result.distance_rules=data.get("distance_rules",[]).duplicate(true);result.support_surface=data.get("support_surface",false)
	result.animation=data.get("animation",{"frames":1,"columns":1,"fps":6}).duplicate()
	result.texture_binding=data.get("texture_binding",{}).duplicate()
	result.enabled=data.get("enabled",true) and not data.get("deleted",false)
	result.initial_placed=data.get("initial_placed",data.get("default_placement")!=null)
	result.default_placement=data.get("default_placement");result.default_owned=data.get("default_owned",true) and result.enabled
	return result

var _physical_masks: Dictionary = {}
func physical_plane_mask(frame_size: Vector2i) -> Texture2D:
	if _physical_masks.has(frame_size):return _physical_masks[frame_size]
	var image:=Image.create(frame_size.x+4,frame_size.y+4,false,Image.FORMAT_RGBA8)
	var binding:=texture_binding
	var extent:=Vector2(binding.get("width",frame_size.x/32.0),binding.get("height",frame_size.y/32.0))
	var center:=Vector2(binding.get("x",0),binding.get("y",0))+extent/2
	var angle:=deg_to_rad(float(binding.get("rotation",0)))
	var occupied: Dictionary={}
	for cell in wall_cells:occupied[cell]=false
	for cell in floor_cells:occupied[cell]=true
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var point:=center+((Vector2(x-2+.5,y-2+.5)/Vector2(frame_size)-Vector2(.5,.5))*extent).rotated(angle)
			var cell:=Vector2i(point.floor())
			var physical: bool=occupied.get(cell,false)
			if not occupied.has(cell):
				var distance:=INF
				for candidate in occupied:
					var gap:=point.distance_squared_to(Vector2(candidate)+Vector2(.5,.5))
					if gap<distance:distance=gap;physical=occupied[candidate]
			image.set_pixel(x,y,Color.WHITE if physical else Color.BLACK)
	var result:=ImageTexture.create_from_image(image);_physical_masks[frame_size]=result
	return result
