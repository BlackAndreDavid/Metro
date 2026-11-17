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
