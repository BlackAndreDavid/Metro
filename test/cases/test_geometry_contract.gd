extends SceneTree
const State=preload("res://scripts/cabin_state.gd")
const Item=preload("res://scripts/items/item_definition.gd")
const Building=preload("res://scripts/content/exploration_building.gd")
const Content=preload("res://scripts/content/content_registry.gd")
const Surface=preload("res://scripts/surface_block.gd")
var failures:=0
var checks:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	var state:=State.new()
	var item:Resource=Item.from_data({"id":"elbow","width":2,"height":2,"cells":[[0,0],[0,1],[1,1]],"texture_binding":{"x":-.25,"y":.5,"width":3,"height":1,"rotation":35}})
	state.ITEM_DEFINITIONS.elbow=item
	state.ITEM_DEFINITIONS.test_unit=Item.from_data({"id":"test_unit","width":1,"height":1})
	check(item.cell_offsets().size()==3 and Vector2i(1,0) not in item.cell_offsets(),"irregular item retains its empty cell")
	check(Vector2i(1,0) in item.cell_offsets(false,true) and Vector2i.ZERO not in item.cell_offsets(false,true),"mirror transforms the mask rather than just the sprite")
	check(Vector2i.ZERO in item.cell_offsets(true) and Vector2i(1,1) not in item.cell_offsets(true),"quarter turn transforms actual occupied cells")
	state.inventory.clear();var entry:Dictionary=state.make_entry("elbow",Vector2i.ZERO,false);state.inventory.append(entry)
	check(state.fits_item(state.inventory,state.SMALL,"test_unit",Vector2i(1,0)),"a second item fits into the hole")
	check(not state.fits_item(state.inventory,state.SMALL,"test_unit",Vector2i(0,1)),"solid occupied cells reject another item")
	check(state.entry_at("bag",Vector2i(1,0)).is_empty() and state.used_cells("bag")==3,"hit testing and capacity count actual occupied cells")
	state.inventory.append(state.make_entry("test_unit",Vector2i(1,0),false))
	check(not state.read_cargo(state.inventory,state.SMALL).is_empty(),"interlocking items survive cargo save validation")
	check(not state.fits_item(state.inventory,state.SMALL,"elbow",Vector2i.ZERO,false,true,entry.id),"mirroring is checked against occupied neighbours")
	check(item.texture_binding.rotation==35 and item.texture_binding.width==3,"manual texture binding remains independent of the physical mask")
	var building:Dictionary={"id":"floors","x":100,"width":200,"floors":3,"floor_positions":[0,90,245]}
	check(Building.elevation(building,2)==245 and Building.height_for(building)==355,"per-floor elevations define building geometry")
	var street:=Surface.new();street.apply_level(Content.level("邮电新村"));street.BUILDINGS=[building];street.building="floors";street.floor_index=2
	check(street.floor_elevation()==245,"exploration uses the active building's authored floor height");street.free()
	var region:Dictionary={"type":"arc","start":[0,0],"end":[200,0],"control":[100,80]}
	var rng:=RandomNumberGenerator.new();rng.seed=42
	var at:=Content.sample_region(region,rng)
	check(at.x>=0 and at.x<=200 and at.y>=0 and at.y<=40,"random drop remains on the authored Bezier arc")
	check(Content.region_at(region,.5)==Vector2(100,40),"arc control point governs curve shape")
	var source:Dictionary={"x":0,"row":0,"floor":0,"building":"floors","container":"loose","rolls":3,"region_origin":100.0,"region":region,"choices":[{"kind":"test_unit","weight":1}]}
	var a:Array=[];var b:Array=[];Content.append_spawn(a,source,"stable",123);Content.append_spawn(b,source,"stable",123)
	check(a==b and a.size()==3,"reopening uses identical drop positions for the same day and seed")
	check(a[0].x!=a[1].x and a[0].has("drop_height"),"loose drops independently sample the line including vertical offsets")
	source.container="cabinet";var cabinets:Array=[];Content.append_spawn(cabinets,source,"cabinet",123)
	check(cabinets[0].x==cabinets[1].x,"all contents of one cabinet share its randomized location")
	print("GEOMETRY_CONTRACT: %d checks, %d failures" % [checks,failures])
	if failures==0:print("GEOMETRY_CONTRACT_OK")
	quit(0 if failures==0 else 1)
