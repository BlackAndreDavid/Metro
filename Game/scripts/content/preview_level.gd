extends SceneTree
## Content editor preview starts an isolated session and never loads/writes a player slot.
func _initialize() -> void:
	call_deferred("preview")

func preview() -> void:
	var station := "邮电新村"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--preview-station="): station = argument.trim_prefix("--preview-station=")
	var home = load("res://scenes/game/home.tscn").instantiate()
	home.set_meta("content_preview",true)
	root.add_child(home)
	home.state.station = station
	home.state.installed_charge = 100
	home.loadout = {"light":true,"heavy":true,"wide":false,"crowbar":false,"wrench":false}
	home.confirm_departure()
	home.state.trip_deadline_ms = Time.get_ticks_msec()+3600000
