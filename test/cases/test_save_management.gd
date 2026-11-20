extends SceneTree
const State=preload("res://scripts/cabin_state.gd")
var failures:=0
var checks:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	var session=root.get_node("GameSession")
	session.save_directory=OS.get_environment("METRO_TEST_RESULTS").path_join("save-management-%d-%d" % [int(Time.get_unix_time_from_system()),Time.get_ticks_usec()])
	check(session.create_slot(1,"待修复基地")==OK,"create isolated save")
	var path:String=session.slot_path(1);var state:=State.new();var raw:Dictionary=state.save_data().duplicate(true)
	raw.bag[1].x=raw.bag[0].x;raw.bag[1].y=raw.bag[0].y
	state.write_save(path,raw);var original:=FileAccess.get_file_as_string(path)
	check(session.slot_info(1).get("invalid",false),"changed geometry overlap remains rejected by normal loading")
	var screen=load("res://scenes/ui/save_select.tscn").instantiate();root.add_child(screen)
	screen.rows.get_node("Slot1/Repair").pressed.emit()
	check(FileAccess.get_file_as_string(path)==original and screen.has_node("RepairSaveConfirmation"),"repair requires confirmation before touching the file")
	screen.get_node("RepairSaveConfirmation").canceled.emit();await process_frame
	var result:Dictionary=session.repair_slot(1)
	check(result.get("ok",false),"explicit repair repacks conflicting items")
	check(FileAccess.get_file_as_string(result.get("backup",""))==original,"repair backup preserves the exact original bytes")
	var loaded:=State.new();check(loaded.load_cabin(path,session.Rail.STATIONS.keys()),"repaired save loads through strict validation")
	check(loaded.inventory.size()+loaded.locker.size()==raw.bag.size()+raw.locker.size() and loaded.account==raw.account,"repair preserves item count and funds")
	var missing:Dictionary=raw.duplicate(true);missing.bag[0].kind="missing_definition";state.write_save(path,missing);original=FileAccess.get_file_as_string(path)
	check(session.repair_slot(1).has("error") and FileAccess.get_file_as_string(path)==original,"unknown items stop repair without replacement or overwrite")
	var full:Dictionary=raw.duplicate(true);full.bag=[]
	for i in range(200):full.bag.append({"kind":"water","x":0,"y":0,"rotated":false})
	state.write_save(path,full);original=FileAccess.get_file_as_string(path)
	check(session.repair_slot(1).has("error") and FileAccess.get_file_as_string(path)==original,"insufficient space stops without dropping goods")
	var invalid:Dictionary=raw.duplicate(true);invalid.account=-100;state.write_save(path,invalid);original=FileAccess.get_file_as_string(path)
	check(session.repair_slot(1).has("error") and FileAccess.get_file_as_string(path)==original,"repair does not bypass core finance validation")
	state.write_save(path,loaded.save_data());screen.refresh_rows();session.select_slot(1)
	screen.rows.get_node("Slot1/Delete").pressed.emit()
	check(FileAccess.file_exists(path) and screen.has_node("DeleteSaveConfirmation"),"delete button opens confirmation and retains the file")
	screen.get_node("DeleteSaveConfirmation").canceled.emit();await process_frame
	check(FileAccess.file_exists(path),"cancel leaves save intact")
	screen.rows.get_node("Slot1/Delete").pressed.emit();screen.get_node("DeleteSaveConfirmation").confirmed.emit();await process_frame
	check(not FileAccess.file_exists(path) and session.active_save_path.is_empty(),"confirm deletes only the selected slot and clears its active path")
	check(DirAccess.get_files_at(session.save_directory.path_join("deleted")).size()==1,"deleted save is recoverable from the local deleted directory")
	check(session.delete_slot(0)==ERR_INVALID_PARAMETER and session.delete_save("user://unrelated.json")==ERR_INVALID_PARAMETER,"deletion is limited to configured save slots")
	check(session.create_slot(1,"新基地")==OK,"deleted slot can be reused")
	state.ItemCatalog.aliases["battery_alias"]="aaa";state.ITEM_DEFINITIONS["battery_alias"]=state.ITEM_DEFINITIONS.aaa
	var battery:Array=[{"kind":"battery_alias","x":0,"y":0,"rotated":false,"charge":75}]
	var restored:Dictionary=state.read_cargo(battery,Vector2i.ONE)
	check(not restored.is_empty() and restored.entries[0].kind=="aaa" and restored.entries[0].charge==75,"renamed battery retains charge during save loading")
	battery[0].erase("charge");check(state.read_cargo(battery,Vector2i.ONE).is_empty(),"battery aliases cannot bypass charge validation")
	screen.queue_free();await process_frame
	print("SAVE_MANAGEMENT: %d checks, %d failures" % [checks,failures])
	if failures==0:print("SAVE_MANAGEMENT_OK")
	quit(0 if failures==0 else 1)
