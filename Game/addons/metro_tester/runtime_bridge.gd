extends Node
## Debug-only loopback client. All mutations execute on Godot's main thread.
const Link=preload("res://addons/metro_content_editor/project_link.gd")
var request:HTTPRequest
var elapsed:=0.0
var busy:=false
var token:=""
var run_id:=""
var results:Array=[]
var processed:Dictionary={}
var testing:=false
var session_directory:=""
func _ready()->void:
	if Engine.is_editor_hint() or not OS.is_debug_build():set_process(false);return
	process_mode=Node.PROCESS_MODE_ALWAYS
	run_id="%d-%d" % [OS.get_process_id(),Time.get_ticks_usec()]
	session_directory=ProjectSettings.globalize_path("res://.godot/metro-tester/saves/").path_join(run_id)
	request=HTTPRequest.new();request.timeout=3;request.max_redirects=0;request.request_completed.connect(response);add_child(request)
	if "--metro-tester" in OS.get_cmdline_user_args():start_session()
func start_session()->void:
	testing=true;GameSession.save_directory=session_directory;GameSession.active_save_path=""
func home_node(node:Node)->Node:
	if node.has_method("select_cargo") and node.has_method("show_cabin"):return node
	for child in node.get_children():
		var home:=home_node(child)
		if home!=null:return home
	return null
func _process(delta:float)->void:
	elapsed+=delta
	if elapsed<.35 or busy:return
	elapsed=0
	var info:=Link.read_json("res://.godot/metro_tester_connection.json")
	var project:=ProjectSettings.globalize_path("res://").simplify_path().trim_suffix("/")
	if info.get("protocol")!="metro-tester" or normalize(info.get("project",""))!=normalize(project) or not Link.valid_url(info.get("url","")):return
	token=info.get("token","")
	if token.is_empty():return
	var home:=home_node(get_tree().root)
	var values:Array=[];var seen:Dictionary={}
	if home!=null:
		walk(home.state,["state"],values,seen,0)
		if is_instance_valid(home.surface_block):walk(home.surface_block,["exploration"],values,seen,0);walk(home.surface_block.enemies,["monsters"],values,seen,0)
		walk(home,["home"],values,seen,0)
	var payload:Dictionary={"project":project,"run_id":run_id,"screen":str(home.screen) if home!=null else "主菜单（请先创建/读取测试存档）","values":values,"testing":testing,"results":results}
	busy=request.request(str(info.url)+"/api/runtime",PackedStringArray(["Content-Type: application/json","X-Metro-Token: "+token]),HTTPClient.METHOD_POST,JSON.stringify(payload))==OK
func normalize(path:String)->String:
	return path.replace("\\","/").trim_suffix("/").to_lower() if OS.get_name()=="Windows" else path.trim_suffix("/")
func walk(value:Variant,path:Array,rows:Array,seen:Dictionary,depth:int)->void:
	if rows.size()>=2500 or depth>7:return
	if value is bool or value is int or value is float:
		if value is float and not is_finite(value):return
		rows.append({"path":path,"value":value,"type":type_string(typeof(value))});return
	if value is Object:
		if not is_instance_valid(value) or seen.has(value.get_instance_id()):return
		seen[value.get_instance_id()]=true
		for property in value.get_property_list():
			if int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE and not str(property.name).begins_with("_"):walk(value.get(property.name),path+[str(property.name)],rows,seen,depth+1)
	elif value is Dictionary:
		for key in value:
			if key is String or key is int:walk(value[key],path+[key],rows,seen,depth+1)
	elif value is Array:
		for index in range(mini(250,value.size())):walk(value[index],path+[index],rows,seen,depth+1)
	elif value is Vector2 or value is Vector2i:
		for key in ["x","y"]:walk(value[key],path+[key],rows,seen,depth+1)
	elif value is Vector3 or value is Vector3i:
		for key in ["x","y","z"]:walk(value[key],path+[key],rows,seen,depth+1)
	elif value is Color:
		for key in ["r","g","b","a"]:walk(value[key],path+[key],rows,seen,depth+1)
func has_key(value:Variant,key:Variant)->bool:
	if value is Object:
		if not key is String or key.begins_with("_"):return false
		for property in value.get_property_list():
			if property.name==key and int(property.usage)&PROPERTY_USAGE_SCRIPT_VARIABLE:return true
	elif value is Dictionary:return value.has(key)
	elif value is Array:return (key is int or key is float) and key==floor(key) and key>=0 and key<value.size()
	elif value is Vector2 or value is Vector2i:return key in ["x","y"]
	elif value is Vector3 or value is Vector3i:return key in ["x","y","z"]
	elif value is Color:return key in ["r","g","b","a"]
	return false
func get_child_value(container:Variant,key:Variant)->Variant:
	return container.get(key) if container is Object else container[key]
func write_path(container:Variant,path:Array,new_value:Variant)->Dictionary:
	if path.is_empty():return {"error":"请选择数值路径"}
	var key:Variant=path[0]
	if not has_key(container,key):return {"error":"路径已失效或不是游戏脚本属性"}
	if container is Array:key=int(key)
	var old:Variant=get_child_value(container,key)
	var replacement:Variant
	if path.size()>1:
		var nested:=write_path(old,path.slice(1),new_value)
		if nested.has("error"):return nested
		replacement=nested.value
	else:
		if old is bool:
			if not new_value is bool:return {"error":"此属性需要 true/false"}
			replacement=new_value
		elif old is int or old is float:
			if not (new_value is int or new_value is float) or not is_finite(new_value):return {"error":"此属性需要有限数值"}
			if old is int and (new_value!=floor(new_value) or absf(new_value)>9007199254740991):return {"error":"此属性需要安全范围内的整数"}
			replacement=int(new_value) if old is int else float(new_value)
		else:return {"error":"仅允许修改数值或布尔属性"}
	if container is Object:container.set(key,replacement)
	else:container[key]=replacement
	return {"value":container}
func sandbox(home:Node)->String:
	if home.get_meta("metro_tester_sandbox",false):return ""
	if not testing:start_session()
	var path:String=home.save_path
	if not path.begins_with(session_directory):path=session_directory.path_join("live.json")
	var err:Error=home.state.write_save(path,home.state.save_data())
	if err!=OK:return "无法建立测试存档："+error_string(err)
	home.save_path=path;GameSession.active_save_path=path;home.set_meta("metro_tester_sandbox",true)
	return ""
func execute(command:Dictionary)->Dictionary:
	var id:String=command.get("id","")
	if processed.has(id):return processed[id]
	var result:Dictionary={"id":id,"ok":false,"message":""}
	var home:=home_node(get_tree().root)
	if home==null:result.message="请先在游戏内创建或读取一个测试基地";return result
	var problem:=sandbox(home)
	if not problem.is_empty():result.message=problem;return result
	match command.get("kind"):
		"set":
			if not command.get("path") is Array or command.path.size()>32:result.message="路径必须是数组";return result
			var roots:Dictionary={"state":home.state,"home":home}
			if is_instance_valid(home.surface_block):roots.exploration=home.surface_block;roots.monsters=home.surface_block.enemies
			var change:=write_path(roots,command.path,command.get("value"))
			result.ok=not change.has("error");result.message=change.get("error","数值已修改；测试存档："+home.save_path)
		"spawn":
			var item:Variant=command.get("item");var amount:Variant=command.get("count",1);var target:Variant=command.get("target","bag")
			if not item is String or not home.state.ITEM_DEFINITIONS.has(item) or not home.state.valid_index(amount,1,100) or target not in ["bag","locker"]:result.message="物品、数量或容器无效";return result
			if home.state.ItemCatalog.runtime_id(item)=="computer" and (home.state.material_count("computer")>0 or home.state.furniture_layout.computer!=null or amount>1):result.message="电脑为唯一家具物品，不能重复生成";return result
			var before:Array=home.state.entries(target).duplicate(true);var next_id:int=home.state.next_id
			for index in range(int(amount)):
				if not home.state.add_supply(item,target):
					home.state.entries(target).assign(before);home.state.next_id=next_id;result.message="空间不足，已撤销本次整批生成";return result
			result.ok=true;result.message="已生成 %d 件 %s" % [amount,item]
		"save":
			var err:Error=home.state.save_current(home.save_path);result.ok=err==OK;result.message=home.save_path if err==OK else error_string(err)
		_:result.message="未知指令"
	if is_instance_valid(home.view) and home.view.has_method("refresh_active"):home.view.refresh_active()
	for grid in home.grids:
		if is_instance_valid(grid):grid.queue_redraw()
	if home.screen=="cabin" and home.visible and not home.construction.active:home.show_cabin("测试模式 · 改动仅写入隔离测试存档")
	processed[id]=result
	if processed.size()>512:processed.erase(processed.keys()[0])
	return result
func response(result:int,code:int,_headers:PackedStringArray,body:PackedByteArray)->void:
	busy=false
	if result!=HTTPRequest.RESULT_SUCCESS or code!=200:return
	var data:Variant=JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary:return
	results=[]
	for command in data.get("commands",[]):
		if command is Dictionary:results.append(execute(command))
