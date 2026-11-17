extends Resource
@export var id := ""
@export var display_name := ""
@export var function_text := ""
@export_enum("rest", "news") var action := "rest"
@export var texture: Texture2D
# Offset of the cropped image in the original 243x108 carriage canvas.
@export var source_origin := Vector2.ZERO

func perform(home: Control) -> void:
	home.use_hotspot(action)
