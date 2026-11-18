extends RefCounted
## Each customer has an independent texture; extend this list to add visitors.
const FALLBACK := [
	{"id":"scavenger", "name":"拾荒老人", "texture":"res://assets/textures/customers/scavenger.png"},
	{"id":"mechanic", "name":"维修工", "texture":"res://assets/textures/customers/mechanic.png"},
	{"id":"commuter", "name":"通勤旅客", "texture":"res://assets/textures/customers/commuter.png"},
	{"id":"medic", "name":"医护人员", "texture":"res://assets/textures/customers/medic.png"},
]

const Content = preload("res://scripts/content/content_registry.gd")
static var ENTRIES: Array = Content.read_json("res://content/customers.json").get("customers",FALLBACK.duplicate(true))
static func reload() -> void:
	var raw: Variant = Content.read_json("res://content/customers.json").get("customers",[])
	ENTRIES = raw if raw is Array and not raw.is_empty() else FALLBACK.duplicate(true)
static func definition(index: int) -> Dictionary:
	if ENTRIES.is_empty(): reload()
	return ENTRIES[posmod(index,ENTRIES.size())]

static func load_texture(path: String) -> Texture2D:
	# Editor-uploaded PNGs work immediately, without requiring a Godot import/restart.
	if FileAccess.file_exists(path):
		var image := Image.new()
		if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK: return ImageTexture.create_from_image(image)
	return load(path) as Texture2D if ResourceLoader.exists(path) else null
