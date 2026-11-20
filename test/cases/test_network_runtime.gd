extends SceneTree
const Rail=preload("res://scripts/cabin_map.gd")
const Catalog=preload("res://scripts/content/network_catalog.gd")
var failures:=0
func check(ok:bool,message:String)->void:
	if not ok:failures+=1;push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	check(Rail.reload_network(),"shared editor JSON loads without a running web server")
	var document:=Catalog.read_network()
	check(document.stations.size()>=74 and document.lines.size()>=5,"existing station map migrates completely")
	check(Rail.route("邮电新村","四平路")==["邮电新村","四平路"],"original adjacency preserved")
	check(Rail.route("邮电新村","南京东路").size()>2,"original cross-station routes remain available")
	var original_lines:Array=Rail.LINES.duplicate(true)
	# A bend-only route cannot create false travel connections or crash BFS.
	Rail.LINES=[[90,"abcdef",[Vector2(0,0),Vector2(100,100)]],[91,"aabbcc",["邮电新村",Vector2(200,100),"南京东路"]]]
	check(Rail.route("邮电新村","南京东路")==["邮电新村","南京东路"],"edited topology ignores decorative bends when computing travel")
	check(Rail.route("邮电新村","四平路").is_empty(),"deleted route links stop being traversable")
	Rail.LINES=[[91,"aabbcc",["邮电新村","四平路","南京东路","邮电新村"]]]
	check(Rail.route("邮电新村","南京东路")==["邮电新村","南京东路"],"new closed route connects last and first stops")
	Rail.LINES=original_lines
	var map:=Rail.new();root.add_child(map);map.size=Vector2(849,505)
	var font:=SystemFont.new();font.font_names=PackedStringArray(["sans-serif"])
	map.setup(font,"邮电新村","四平路",func(_station:String):pass)
	check(map.map_textures.get("network_base")!=null,"texture layer renders from the same saved map document")
	check(map.get_child_count()==Rail.STATIONS.size()*2,"edited station positions still create clickable map and label targets")
	await process_frame
	map.queue_free();await process_frame
	if failures==0:print("NETWORK_RUNTIME_OK")
	quit(1 if failures else 0)
