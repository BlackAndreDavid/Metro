extends Node

const State = preload("res://scripts/cabin_state.gd")
const Rail = preload("res://scripts/cabin_map.gd")
var active_save_path := ""
# Tests may override this directory; production saves are portable user data.
var save_directory := "user://saves"

func slot_path(slot: int) -> String:
	return save_directory.path_join("slot_%d.json" % slot)

func slot_info(slot: int) -> Dictionary:
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var state := State.new()
	if not state.load_cabin(path, Rail.STATIONS.keys()):
		return {"invalid": true}
	return {"name": state.base_name, "day": state.day, "station": state.station}

func create_slot(slot: int, base_name: String) -> Error:
	if slot < 1 or slot > 3 or base_name.strip_edges().is_empty() or base_name.length() > 24:
		return ERR_INVALID_PARAMETER
	if FileAccess.file_exists(slot_path(slot)):
		return ERR_ALREADY_EXISTS
	var state := State.new()
	state.base_name = base_name.strip_edges()
	return state.save_current(slot_path(slot))

func select_slot(slot: int) -> bool:
	if slot < 1 or slot > 3:
		return false
	var info := slot_info(slot)
	if info.is_empty() or info.get("invalid", false):
		return false
	active_save_path = slot_path(slot)
	return true

func legacy_path() -> String:
	var directory := OS.get_executable_path().get_base_dir() if OS.has_feature("template") else ProjectSettings.globalize_path("res://")
	return directory.path_join("saves/cabin_slot.json")


func allowed_save(path: String) -> bool:
	return path in [slot_path(1),slot_path(2),slot_path(3),legacy_path()]

func delete_slot(slot: int) -> Error:
	return delete_save(slot_path(slot)) if slot>=1 and slot<=3 else ERR_INVALID_PARAMETER

func delete_save(path: String) -> Error:
	if not allowed_save(path):return ERR_INVALID_PARAMETER
	if not FileAccess.file_exists(path):return ERR_FILE_NOT_FOUND
	var folder:=save_directory.path_join("deleted")
	var err:=DirAccess.make_dir_recursive_absolute(folder)
	if err!=OK:return err
	var destination:=folder.path_join(path.get_file().get_basename()+"_%d_%d.json" % [int(Time.get_unix_time_from_system()),Time.get_ticks_usec()])
	err=move_to_deleted(path,destination)
	if err!=OK:return err
	if FileAccess.file_exists(path+".rules_seen"):move_to_deleted(path+".rules_seen",destination+".rules_seen")
	if active_save_path==path:active_save_path=""
	return OK

func repair_slot(slot: int) -> Dictionary:
	return repair_save(slot_path(slot)) if slot>=1 and slot<=3 else {"error":"无效栏位"}

func repair_save(path: String) -> Dictionary:
	if not allowed_save(path):return {"error":"无效存档路径"}
	var parser:=JSON.new()
	if not FileAccess.file_exists(path) or parser.parse(FileAccess.get_file_as_string(path))!=OK or not parser.data is Dictionary:
		return {"error":"JSON 内容损坏，无法自动恢复；请使用已有备份或匹配版本。原文件已保留。"}
	var result:Dictionary=preload("res://scripts/core/save_repair.gd").repair(parser.data,Rail.STATIONS.keys())
	if result.has("error"):return result
	var backup:=path+".repair-backup-%d-%d.json" % [int(Time.get_unix_time_from_system()),Time.get_ticks_usec()]
	var err:=DirAccess.copy_absolute(path,backup)
	if err!=OK:return {"error":"备份失败，已停止修复："+error_string(err)}
	err=State.new().write_save(path,result.data)
	if err!=OK:return {"error":"修复文件写入失败，备份保留于："+backup}
	return {"ok":true,"backup":backup,"notes":result.notes}

func move_to_deleted(source: String, destination: String) -> Error:
	if FileAccess.file_exists(destination):return ERR_ALREADY_EXISTS
	var err:=DirAccess.rename_absolute(source,destination)
	if err==OK:return OK
	# Legacy saves may live on another drive from user://saves.
	err=DirAccess.copy_absolute(source,destination)
	return DirAccess.remove_absolute(source) if err==OK else err
